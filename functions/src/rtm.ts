/**
 * Realtime Match (RTM) Cloud Functions
 * Covers: match notifications, secure leave action, scheduled cleanup.
 */

import * as admin from "firebase-admin";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, messaging } from "./lib/firebase";

/**
 * Send notification when an RTM match is found.
 * Triggered when realtime_match status changes to "matched".
 * Respects notify_rtmMatch user preference.
 */
export const onRTMMatchFound = onDocumentUpdated(
    "realtime_matches/{matchId}",
    async (event) => {
        const beforeData = event.data?.before.data();
        const afterData = event.data?.after.data();

        if (!beforeData || !afterData) return;

        // Only fire when status transitions to "matched"
        if (beforeData.status === "matched" || afterData.status !== "matched") return;

        const matchId = event.params.matchId;
        const participants: string[] = afterData.participants || [];
        const productName = afterData.productName || afterData.description || "your item";

        console.log(`RTM match found: ${matchId} with ${participants.length} participants`);

        for (const userId of participants) {
            try {
                const userDoc = await db.collection("profiles").doc(userId).get();
                if (!userDoc.exists) continue;

                const userData = userDoc.data()!;
                const fcmToken = userData.fcmToken;

                if (userData.notify_rtmMatch === false) {
                    console.log(`User ${userId} has disabled RTM match notifications`);
                    continue;
                }

                if (!fcmToken) {
                    console.log(`User ${userId} has no FCM token`);
                    continue;
                }

                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: "Match Found!",
                        body: `A real-time match has been found for ${productName}`,
                    },
                    data: { type: "rtm_match_found", matchId: matchId },
                    android: {
                        priority: "high",
                        notification: { channelId: "rtm_updates", icon: "ic_notification" },
                    },
                    apns: { payload: { aps: { badge: 1, sound: "default" } } },
                });

                console.log(`RTM match notification sent to ${userId}`);
            } catch (error) {
                console.error(`Error sending RTM notification to ${userId}:`, error);
            }
        }
    }
);

/**
 * Secure function for leaving a realtime match.
 * Handles ownership transfer, status reversion, and chat room cleanup.
 */
export const leaveRealtimeMatchSecure = onCall(
    { region: "asia-southeast1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        const { matchId } = request.data;
        if (!matchId) {
            throw new HttpsError("invalid-argument", "Missing matchId");
        }

        const userId = request.auth.uid;

        try {
            const matchRef = db.collection("realtime_matches").doc(matchId);
            const matchDoc = await matchRef.get();

            if (!matchDoc.exists) {
                throw new HttpsError("not-found", "Match not found");
            }

            const match = matchDoc.data()!;
            const participants: string[] = match.participants || [];

            if (!participants.includes(userId)) {
                throw new HttpsError("failed-precondition", "You are not a participant");
            }

            const newParticipants = participants.filter((id: string) => id !== userId);

            if (newParticipants.length === 0) {
                // Last person leaving — delete match and its chat room
                await matchRef.delete();

                if (match.chatRoomId) {
                    const chatRoomRef = db.collection("chat_rooms").doc(match.chatRoomId);
                    const messagesSnapshot = await chatRoomRef.collection("messages").get();

                    if (!messagesSnapshot.empty) {
                        const batch = db.batch();
                        messagesSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
                        await batch.commit();
                        console.log(`Deleted ${messagesSnapshot.size} messages from chat room ${match.chatRoomId}`);
                    }

                    await chatRoomRef.delete();
                }

                console.log(`Deleted empty realtime match: ${matchId}`);
            } else {
                const updates: Record<string, unknown> = { participants: newParticipants };

                // Revert to 'waiting' if the room was matched but is no longer full
                const maxPartners = match.maxPartners || 1;
                if (match.status === "matched" && newParticipants.length < maxPartners + 1) {
                    updates.status = "waiting";
                    console.log(`Match ${matchId} reverted to 'waiting' (${newParticipants.length}/${maxPartners + 1})`);
                }

                // Transfer ownership if the owner is leaving
                if (match.ownerId === userId) {
                    const newOwnerId = newParticipants[0];
                    updates.ownerId = newOwnerId;

                    const profileDoc = await db.collection("profiles").doc(newOwnerId).get();
                    if (profileDoc.exists) {
                        const profileData = profileDoc.data();
                        updates.ownerName = profileData?.displayName || "User";
                        updates.ownerPhotoUrl = profileData?.photoUrl || null;
                    }
                }

                await matchRef.update(updates);

                if (match.chatRoomId) {
                    const chatRoomRef = db.collection("chat_rooms").doc(match.chatRoomId);
                    await chatRoomRef.update({
                        participantIds: admin.firestore.FieldValue.arrayRemove(userId),
                    });

                    const leaverDoc = await db.collection("profiles").doc(userId).get();
                    const leaverName = leaverDoc.exists ? leaverDoc.data()?.displayName || "A user" : "A user";
                    await chatRoomRef.collection("messages").add({
                        type: "system",
                        content: `${leaverName} left the match`,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                    });
                }

                console.log(`User ${userId} left realtime match ${matchId}`);
            }

            return { success: true };

        } catch (error) {
            console.error("Error leaving realtime match:", error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", "Failed to leave match");
        }
    }
);

/**
 * Scheduled cleanup for expired realtime matches.
 * Runs every 30 minutes to close waiting matches that have passed their expiresAt.
 */
export const cleanupExpiredMatches = onSchedule(
    {
        schedule: "every 30 minutes",
        timeZone: "Asia/Kuala_Lumpur",
    },
    async () => {
        const now = admin.firestore.Timestamp.now();

        try {
            const expiredMatches = await db
                .collection("realtime_matches")
                .where("status", "==", "waiting")
                .where("expiresAt", "<", now)
                .get();

            if (expiredMatches.empty) {
                console.log("No expired matches to clean up");
                return;
            }

            console.log(`Found ${expiredMatches.size} expired matches to clean up`);

            const batch = db.batch();
            expiredMatches.docs.forEach((doc) => {
                batch.update(doc.ref, {
                    status: "closed",
                    closedReason: "expired",
                    closedAt: now,
                });
            });
            await batch.commit();

            console.log(`Successfully closed ${expiredMatches.size} expired matches`);

        } catch (error) {
            console.error("Error cleaning up expired matches:", error);
        }
    }
);

/**
 * Scheduled cleanup for old realtime matches and orphaned chat rooms.
 * Runs daily at 3:00 AM Malaysia time (UTC+8).
 */
export const cleanupOldRealtimeMatches = onSchedule(
    {
        schedule: "0 3 * * *",
        timeZone: "Asia/Kuala_Lumpur",
        region: "asia-southeast1",
    },
    async () => {
        console.log("Starting realtime matches cleanup...");

        const now = admin.firestore.Timestamp.now();
        const cutoffDate = new Date(now.toMillis() - 24 * 60 * 60 * 1000); // 24 hours ago
        const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffDate);

        let deletedCount = 0;

        try {
            // 1. Delete closed matches and their chat rooms
            const closedMatches = await db.collection("realtime_matches")
                .where("status", "==", "closed")
                .get();

            for (const doc of closedMatches.docs) {
                const chatRoomId = `rtm_${doc.id}`;

                const messagesSnapshot = await db.collection("chat_rooms")
                    .doc(chatRoomId)
                    .collection("messages")
                    .get();

                const batch = db.batch();
                messagesSnapshot.docs.forEach((msgDoc) => batch.delete(msgDoc.ref));
                await batch.commit();

                await db.collection("chat_rooms").doc(chatRoomId).delete();
                await doc.ref.delete();
                deletedCount++;
            }

            console.log(`Deleted ${closedMatches.size} closed matches`);

            // 2. Delete stale waiting matches (older than 24 hours)
            const staleMatches = await db.collection("realtime_matches")
                .where("status", "==", "waiting")
                .where("createdAt", "<", cutoffTimestamp)
                .get();

            for (const doc of staleMatches.docs) {
                const chatRoomId = `rtm_${doc.id}`;

                const messagesSnapshot = await db.collection("chat_rooms")
                    .doc(chatRoomId)
                    .collection("messages")
                    .get();

                const batch = db.batch();
                messagesSnapshot.docs.forEach((msgDoc) => batch.delete(msgDoc.ref));
                await batch.commit();

                await db.collection("chat_rooms").doc(chatRoomId).delete();
                await doc.ref.delete();
                deletedCount++;
            }

            console.log(`Deleted ${staleMatches.size} stale waiting matches`);

            // 3. Cleanup orphaned rtm_ chat rooms (no corresponding match document)
            const rtmChatRooms = await db.collection("chat_rooms")
                .where(admin.firestore.FieldPath.documentId(), ">=", "rtm_")
                .where(admin.firestore.FieldPath.documentId(), "<", "rtm_~")
                .get();

            let orphanedCount = 0;
            for (const chatDoc of rtmChatRooms.docs) {
                const matchId = chatDoc.id.replace("rtm_", "");
                const matchDoc = await db.collection("realtime_matches").doc(matchId).get();

                if (!matchDoc.exists) {
                    const messagesSnapshot = await chatDoc.ref.collection("messages").get();
                    const batch = db.batch();
                    messagesSnapshot.docs.forEach((msgDoc) => batch.delete(msgDoc.ref));
                    await batch.commit();

                    await chatDoc.ref.delete();
                    orphanedCount++;
                }
            }

            console.log(`Deleted ${orphanedCount} orphaned chat rooms`);
            console.log(`Cleanup complete. Total: ${deletedCount} matches, ${orphanedCount} orphaned rooms`);

        } catch (error) {
            console.error("Error during cleanup:", error);
        }
    }
);
