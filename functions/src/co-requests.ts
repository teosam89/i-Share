/**
 * Co-Request Cloud Functions
 * Covers: lifecycle notifications, secure callable actions, scheduled expiry, QR verification, geohash backfill.
 */

import * as admin from "firebase-admin";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { db, messaging } from "./lib/firebase";

// ──────────────── FIRESTORE TRIGGERS ────────────────

/**
 * Increment totalRequests counter when a new co-request is created.
 * Broadcast notifications removed — only relevant per-user events are notified.
 */
export const onNewRequest = onDocumentCreated(
    "co_requests/{requestId}",
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const requestData = snapshot.data();
        const requestId = event.params.requestId;
        const initiatorId: string | undefined = requestData.initiatorId;

        console.log(`New request created: ${requestId}`);

        // Increment totalRequests for the initiator (server-side — client no longer writes this)
        if (initiatorId) {
            try {
                await db.collection("profiles").doc(initiatorId).update({
                    totalRequests: admin.firestore.FieldValue.increment(1),
                });
                console.log(`totalRequests +1 → ${initiatorId}`);
            } catch (error) {
                console.error("Error incrementing totalRequests:", error);
            }
        }
    }
);

/**
 * Unified co-request update handler.
 *
 * Replaces the previous three separate triggers (onUserJoinRequest,
 * onRequestStatusChange, onRequestEdited) that all listened to
 * co_requests/{requestId} and could race against each other.
 *
 * Dispatch priority (if/else-if — only ONE branch per update):
 *   1. Status change   → notify all participants (completed/cancelled)
 *   2. Participant join → notify initiator
 *   3. Field edit       → notify other participants
 */
export const onCoRequestUpdated = onDocumentUpdated(
    "co_requests/{requestId}",
    async (event) => {
        const beforeData = event.data?.before.data();
        const afterData = event.data?.after.data();
        const requestId = event.params.requestId;

        if (!beforeData || !afterData) return;

        // ── Branch 1: Status changed ──
        if (beforeData.status !== afterData.status) {
            const newStatus = afterData.status;

            let title = "";
            let body = "";

            switch (newStatus) {
                case "completed":
                    title = "Request Completed!";
                    body = `The request for ${afterData.productName} has been completed`;
                    break;
                case "cancelled":
                    title = "Request Cancelled";
                    body = `The request for ${afterData.productName} was cancelled`;
                    break;
                default:
                    return; // Don't notify for other status transitions
            }

            console.log(`Request ${requestId} status → ${newStatus}`);

            const participants: string[] = afterData.participants || [];
            const allUserIds = [...new Set([afterData.initiatorId, ...participants])];
            const tokens: string[] = [];

            for (const userId of allUserIds) {
                const userDoc = await db.collection("profiles").doc(userId).get();
                const token = userDoc.data()?.fcmToken;
                if (token) tokens.push(token);
            }

            if (tokens.length > 0) {
                try {
                    await messaging.sendEachForMulticast({
                        tokens,
                        notification: { title, body },
                        data: { type: "status_change", requestId, newStatus },
                        android: {
                            priority: "high",
                            notification: { channelId: "request_updates", icon: "ic_notification" },
                        },
                    });
                    console.log(`Status notification → ${tokens.length} users`);
                } catch (error) {
                    console.error("Error sending status notification:", error);
                }
            }

            // ── Credibility scoring for status changes (batched) ──
            try {
                const initiatorId: string = afterData.initiatorId;
                const allIds = [...new Set([initiatorId, ...participants])];

                if (newStatus === "completed") {
                    const batch = db.batch();
                    for (const uid of allIds) {
                        const profileRef = db.collection("profiles").doc(uid);
                        batch.update(profileRef, {
                            score: admin.firestore.FieldValue.increment(15),
                            completedRequests: admin.firestore.FieldValue.increment(1),
                        });
                        const activityRef = profileRef.collection("score_activities").doc();
                        batch.set(activityRef, {
                            event: "completeDeal",
                            points: 15,
                            description: "Completed a split",
                            relatedId: requestId,
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                    }
                    await batch.commit();
                    console.log(`Credibility: +15 → ${allIds.length} users (completed)`);

                } else if (newStatus === "cancelled") {
                    const otherCount = participants.filter((id: string) => id !== initiatorId).length;
                    const penalty = otherCount > 0 ? -25 : 0;
                    const hostRef = db.collection("profiles").doc(initiatorId);

                    if (penalty !== 0) {
                        const batch = db.batch();
                        batch.update(hostRef, {
                            score: admin.firestore.FieldValue.increment(penalty),
                            cancelledRequests: admin.firestore.FieldValue.increment(1),
                        });
                        const activityRef = hostRef.collection("score_activities").doc();
                        batch.set(activityRef, {
                            event: "cancelWithParticipants",
                            points: penalty,
                            description: "Cancelled request (participants affected)",
                            relatedId: requestId,
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        });
                        await batch.commit();
                        console.log(`Credibility: ${penalty} → host ${initiatorId} (cancelled)`);
                    } else {
                        await hostRef.update({
                            cancelledRequests: admin.firestore.FieldValue.increment(1),
                        });
                    }
                }
            } catch (credError) {
                console.error("Error updating credibility on status change:", credError);
            }

            return; // Done — skip other branches
        }

        // ── Branch 2: New participant joined ──
        const beforeParticipants: string[] = beforeData.participants || [];
        const afterParticipants: string[] = afterData.participants || [];

        if (afterParticipants.length > beforeParticipants.length) {
            const newParticipant = afterParticipants.find(
                (p) => !beforeParticipants.includes(p)
            );
            if (!newParticipant) return;

            console.log(`User ${newParticipant} joined request ${requestId}`);

            const initiatorId = afterData.initiatorId;
            const initiatorDoc = await db.collection("profiles").doc(initiatorId).get();
            if (!initiatorDoc.exists) return;

            const fcmToken = initiatorDoc.data()?.fcmToken;
            if (!fcmToken) {
                console.log("Initiator has no FCM token");
                return;
            }

            const joinerDoc = await db.collection("profiles").doc(newParticipant).get();
            const joinerName = joinerDoc.data()?.displayName || "Someone";

            // Increment totalJoined for the new participant.
            // Centralised here so all participant-add paths are covered
            // (acceptJoinRequestSecure, addParticipantFromRtm, etc.)
            try {
                await db.collection("profiles").doc(newParticipant).update({
                    totalJoined: admin.firestore.FieldValue.increment(1),
                    lastActiveAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                console.log(`totalJoined +1 → ${newParticipant}`);
            } catch (error) {
                console.error("Error incrementing totalJoined:", error);
            }

            try {
                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: "New Partner Joined!",
                        body: `${joinerName} joined your request for ${afterData.productName}`,
                    },
                    data: { type: "user_joined", requestId, joinerId: newParticipant },
                    android: {
                        priority: "high",
                        notification: { channelId: "request_updates", icon: "ic_notification" },
                    },
                    apns: { payload: { aps: { badge: 1, sound: "default" } } },
                });
                console.log(`Join notification → initiator ${initiatorId}`);
            } catch (error) {
                console.error("Error sending join notification:", error);
            }

            return; // Done — skip edit branch
        }

        // ── Branch 3: Field edit (only if status & participants unchanged) ──
        const trackedFields = [
            "productName", "dealDescription", "totalPrice",
            "totalQuantity", "partnersNeeded", "storeName",
            "category", "notes", "productPhotoUrl",
        ];

        const changedFields: string[] = [];
        for (const field of trackedFields) {
            if (beforeData[field] !== afterData[field]) {
                changedFields.push(field);
            }
        }

        if (changedFields.length === 0) return;

        console.log(`Request ${requestId} edited: ${changedFields.join(", ")}`);

        const initiatorId = afterData.initiatorId;
        const participants: string[] = afterData.participants || [];
        const recipientIds = participants.filter((id: string) => id !== initiatorId);

        if (recipientIds.length === 0) return;

        const productName = afterData.productName || "the request";

        for (const userId of recipientIds) {
            try {
                const userDoc = await db.collection("profiles").doc(userId).get();
                if (!userDoc.exists) continue;

                const fcmToken = userDoc.data()!.fcmToken;
                if (!fcmToken) continue;

                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: "Request Updated",
                        body: `The host updated "${productName}" (${changedFields.length} change${changedFields.length > 1 ? "s" : ""})`,
                    },
                    data: { type: "request_edited", requestId },
                    android: {
                        priority: "high",
                        notification: { channelId: "request_updates", icon: "ic_notification" },
                    },
                    apns: { payload: { aps: { badge: 1, sound: "default" } } },
                });
                console.log(`Edit notification → ${userId}`);
            } catch (error) {
                console.error(`Error sending edit notification to ${userId}:`, error);
            }
        }
    }
);

/**
 * Send notification when a pending join request is created.
 * Notifies the host that someone wants to join their request.
 * Respects notify_joinRequest user preference.
 */
export const onPendingJoinRequest = onDocumentCreated(
    "co_requests/{requestId}/join_requests/{joinRequestId}",
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const joinData = snapshot.data();
        const requestId = event.params.requestId;

        if (joinData.status !== "pending") return;

        const hostId = joinData.hostId;
        if (!hostId) return;

        try {
            const hostDoc = await db.collection("profiles").doc(hostId).get();
            if (!hostDoc.exists) return;

            const hostData = hostDoc.data()!;
            const fcmToken = hostData.fcmToken;

            if (hostData.notify_joinRequest === false) {
                console.log(`Host ${hostId} has disabled join request notifications`);
                return;
            }

            if (!fcmToken) {
                console.log(`Host ${hostId} has no FCM token`);
                return;
            }

            const requesterName = joinData.requesterName || "Someone";
            const requestDoc = await db.collection("co_requests").doc(requestId).get();
            const productName = requestDoc.data()?.productName || "your request";

            await messaging.send({
                token: fcmToken,
                notification: {
                    title: "New Join Application!",
                    body: `${requesterName} wants to join your request for ${productName}`,
                },
                data: {
                    type: "join_request_pending",
                    requestId: requestId,
                    joinRequestId: event.params.joinRequestId,
                },
                android: {
                    priority: "high",
                    notification: { channelId: "request_updates", icon: "ic_notification" },
                },
                apns: { payload: { aps: { badge: 1, sound: "default" } } },
            });

            console.log(`Pending join notification sent to host ${hostId} for request ${requestId}`);
        } catch (error) {
            console.error("Error sending pending join notification:", error);
        }
    }
);

/**
 * Send notification when a join request is approved.
 * Triggered when join_request status changes from pending to accepted.
 * Respects notify_joinApproved user preference.
 */
export const onJoinRequestApproved = onDocumentUpdated(
    "co_requests/{requestId}/join_requests/{joinRequestId}",
    async (event) => {
        const beforeData = event.data?.before.data();
        const afterData = event.data?.after.data();

        if (!beforeData || !afterData) return;

        if (beforeData.status !== "pending" || afterData.status !== "accepted") return;

        const requestId = event.params.requestId;
        const requesterId = afterData.requesterId;

        if (!requesterId) return;

        try {
            const requesterDoc = await db.collection("profiles").doc(requesterId).get();
            if (!requesterDoc.exists) return;

            const requesterData = requesterDoc.data()!;
            const fcmToken = requesterData.fcmToken;

            if (requesterData.notify_joinApproved === false) {
                console.log(`User ${requesterId} has disabled join approved notifications`);
                return;
            }

            if (!fcmToken) {
                console.log(`User ${requesterId} has no FCM token`);
                return;
            }

            const requestDoc = await db.collection("co_requests").doc(requestId).get();
            const productName = requestDoc.data()?.productName || "the request";

            await messaging.send({
                token: fcmToken,
                notification: {
                    title: "Application Approved!",
                    body: `You've been accepted to join the request for ${productName}`,
                },
                data: { type: "join_request_approved", requestId: requestId },
                android: {
                    priority: "high",
                    notification: { channelId: "request_updates", icon: "ic_notification" },
                },
                apns: { payload: { aps: { badge: 1, sound: "default" } } },
            });

            console.log(`Approval notification sent to ${requesterId} for request ${requestId}`);
        } catch (error) {
            console.error("Error sending approval notification:", error);
        }
    }
);

// ──────────────── SECURE CALLABLE FUNCTIONS ────────────────

/**
 * Secure function to accept a join request.
 * Only the host can call this, and it handles all updates atomically.
 */
export const acceptJoinRequestSecure = onCall(
    { region: "asia-southeast1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        const { requestId, joinRequestId } = request.data;

        if (!requestId || !joinRequestId) {
            throw new HttpsError("invalid-argument", "Missing requestId or joinRequestId");
        }

        const callerId = request.auth.uid;

        try {
            const joinRequestRef = db.collection("co_requests")
                .doc(requestId)
                .collection("join_requests")
                .doc(joinRequestId);
            const joinRequestDoc = await joinRequestRef.get();

            if (!joinRequestDoc.exists) {
                throw new HttpsError("not-found", "Join request not found");
            }

            const joinRequest = joinRequestDoc.data()!;

            if (joinRequest.hostId !== callerId) {
                throw new HttpsError("permission-denied", "Only the host can accept requests");
            }

            if (joinRequest.status !== "pending") {
                throw new HttpsError("failed-precondition", "Join request is not pending");
            }

            const coRequestRef = db.collection("co_requests").doc(requestId);
            const coRequestDoc = await coRequestRef.get();

            if (!coRequestDoc.exists) {
                throw new HttpsError("not-found", "Request not found");
            }

            const coRequest = coRequestDoc.data()!;

            if (coRequest.status !== "active") {
                throw new HttpsError("failed-precondition",
                    `Cannot accept: request is ${coRequest.status}`);
            }

            const currentParticipants: string[] = coRequest.participants || [];
            const partnersNeeded = coRequest.partnersNeeded || 1;
            if (currentParticipants.length >= partnersNeeded + 1) {
                throw new HttpsError("failed-precondition",
                    "Cannot accept: request is already full");
            }

            const requesterId = joinRequest.requesterId;
            const requesterName = joinRequest.requesterName || "User";

            const batch = db.batch();

            batch.update(joinRequestRef, {
                status: "accepted",
                respondedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            batch.update(coRequestRef, {
                participants: admin.firestore.FieldValue.arrayUnion(requesterId),
            });

            // totalJoined and lastActiveAt are now handled by onCoRequestUpdated
            // Branch 2, which fires for ALL participant-add paths. Removed from
            // here to avoid double-counting.

            await batch.commit();

            // Add to chat room (outside batch — chat room may not exist)
            const chatRoomRef = db.collection("chat_rooms").doc(requestId);
            const chatRoomDoc = await chatRoomRef.get();

            if (chatRoomDoc.exists) {
                await chatRoomRef.update({
                    participantIds: admin.firestore.FieldValue.arrayUnion(requesterId),
                });
                await chatRoomRef.collection("messages").add({
                    type: "system",
                    content: `${requesterName} joined the group`,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
            }

            console.log(`Accepted join request: ${joinRequestId} for request: ${requestId}`);
            return { success: true };

        } catch (error) {
            console.error("Error accepting join request:", error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", "Failed to accept join request");
        }
    }
);

/**
 * Secure function for user to leave a request.
 * Updates all related data atomically and applies credibility penalty.
 */
export const leaveRequestSecure = onCall(
    { region: "asia-southeast1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        const { requestId } = request.data;
        if (!requestId) {
            throw new HttpsError("invalid-argument", "Missing requestId");
        }

        const userId = request.auth.uid;

        try {
            const coRequestRef = db.collection("co_requests").doc(requestId);
            const coRequestDoc = await coRequestRef.get();

            if (!coRequestDoc.exists) {
                throw new HttpsError("not-found", "Request not found");
            }

            const coRequest = coRequestDoc.data()!;

            if (coRequest.initiatorId === userId) {
                throw new HttpsError("permission-denied", "Initiator cannot leave their own request");
            }

            const participants: string[] = coRequest.participants || [];
            if (!participants.includes(userId)) {
                throw new HttpsError("failed-precondition", "User is not a participant");
            }

            const batch = db.batch();

            batch.update(coRequestRef, {
                participants: admin.firestore.FieldValue.arrayRemove(userId),
            });

            const joinRequestsSnapshot = await coRequestRef
                .collection("join_requests")
                .where("requesterId", "==", userId)
                .get();

            joinRequestsSnapshot.docs.forEach((doc) => {
                batch.delete(doc.ref);
            });

            await batch.commit();

            // Remove from chat room (outside batch)
            const chatRoomRef = db.collection("chat_rooms").doc(requestId);
            const chatRoomDoc = await chatRoomRef.get();

            if (chatRoomDoc.exists) {
                await chatRoomRef.update({
                    participantIds: admin.firestore.FieldValue.arrayRemove(userId),
                });
            }

            console.log(`User ${userId} left request ${requestId}`);

            // Apply credibility penalty for leaving
            const profileRef = db.collection("profiles").doc(userId);
            await profileRef.update({
                score: admin.firestore.FieldValue.increment(-10),
            });
            await profileRef.collection("score_activities").add({
                event: "leaveRequest",
                points: -10,
                description: "Left a request",
                relatedId: requestId,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log(`Applied -10 credibility for user ${userId} leaving request ${requestId}`);

            return { success: true };

        } catch (error) {
            console.error("Error leaving request:", error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", "Failed to leave request");
        }
    }
);

/**
 * Secure QR verification with rate limiting.
 * Prevents brute force attacks by limiting attempts per user.
 */
export const verifyQrCodeSecure = onCall(
    { region: "asia-southeast1" },
    async (request) => {
        if (!request.auth) {
            throw new HttpsError("unauthenticated", "User must be authenticated");
        }

        const { requestId, secret } = request.data;
        if (!requestId || !secret) {
            throw new HttpsError("invalid-argument", "Missing requestId or secret");
        }

        const userId = request.auth.uid;
        const MAX_ATTEMPTS = 5;

        try {
            const verificationRef = db.collection("qr_verifications").doc(requestId);
            const verificationDoc = await verificationRef.get();

            if (!verificationDoc.exists) {
                throw new HttpsError("not-found", "Verification session not found");
            }

            const data = verificationDoc.data()!;

            const attempts = data.attempts || {};
            const userAttempts = attempts[userId] || 0;

            if (userAttempts >= MAX_ATTEMPTS) {
                throw new HttpsError("resource-exhausted", "Too many verification attempts. Please wait or get a new QR code.");
            }

            await verificationRef.update({
                [`attempts.${userId}`]: admin.firestore.FieldValue.increment(1),
            });

            const expiresAt = data.expiresAt?.toDate ? data.expiresAt.toDate() : new Date(data.expiresAt);
            if (new Date() > expiresAt) {
                throw new HttpsError("failed-precondition", "QR code has expired");
            }

            if (secret !== data.secret) {
                console.log(`Invalid QR attempt by ${userId} for ${requestId}`);
                return { success: false, message: "Invalid QR code", remainingAttempts: MAX_ATTEMPTS - userAttempts - 1 };
            }

            const participantIds: string[] = data.participantIds || [];
            if (!participantIds.includes(userId)) {
                throw new HttpsError("permission-denied", "You are not a participant of this request");
            }

            const verifiedIds: string[] = data.verifiedIds || [];
            if (verifiedIds.includes(userId)) {
                return { success: true, message: "Already verified", alreadyVerified: true };
            }

            await verificationRef.update({
                verifiedIds: admin.firestore.FieldValue.arrayUnion(userId),
            });

            console.log(`Verified participant ${userId} for request ${requestId}`);
            return { success: true, message: "Verification successful!" };

        } catch (error) {
            console.error("Error verifying QR:", error);
            if (error instanceof HttpsError) throw error;
            throw new HttpsError("internal", "Verification failed");
        }
    }
);

// ──────────────── SCHEDULED FUNCTIONS ────────────────

/**
 * Scheduled function to expire non-full co-requests.
 * Runs every hour. Full requests (participants >= partnersNeeded + 1) are exempt.
 *
 * NOTE: closeExpiredCoRequests was removed — it was a duplicate of this function
 * that lacked the "full request" exemption logic. Delete it from Firebase console
 * with: firebase functions:delete closeExpiredCoRequests
 */
export const cleanupExpiredRequests = onSchedule(
    {
        schedule: "every 1 hours",
        timeZone: "Asia/Kuala_Lumpur",
    },
    async () => {
        const now = admin.firestore.Timestamp.now();

        try {
            const expiredRequests = await db
                .collection("co_requests")
                .where("status", "==", "active")
                .where("expiresAt", "<", now)
                .get();

            if (expiredRequests.empty) {
                console.log("No expired requests to clean up");
                return;
            }

            // Full requests stay active even after expiry
            const nonFullExpired = expiredRequests.docs.filter((doc) => {
                const data = doc.data();
                const participants: string[] = data.participants || [];
                const partnersNeeded: number = data.partnersNeeded || 1;
                const isFull = participants.length >= partnersNeeded + 1;
                if (isFull) {
                    console.log(`Skipping full request ${doc.id} (${participants.length}/${partnersNeeded + 1} participants)`);
                }
                return !isFull;
            });

            if (nonFullExpired.length === 0) {
                console.log(`All ${expiredRequests.size} expired requests are full — nothing to expire`);
                return;
            }

            console.log(`Expiring ${nonFullExpired.length} requests (${expiredRequests.size - nonFullExpired.length} full skipped)`);

            const batch = db.batch();
            nonFullExpired.forEach((doc) => {
                batch.update(doc.ref, { status: "expired" });
            });
            await batch.commit();

            // Apply credibility penalty to hosts whose requests expired with participants
            for (const doc of nonFullExpired) {
                const data = doc.data();
                const participants: string[] = data.participants || [];
                if (participants.length > 0) {
                    const hostId = data.initiatorId;
                    if (hostId) {
                        try {
                            const profileRef = db.collection("profiles").doc(hostId);
                            await profileRef.update({
                                score: admin.firestore.FieldValue.increment(-10),
                            });
                            await profileRef.collection("score_activities").add({
                                event: "expiredWithParticipants",
                                points: -10,
                                description: "Request expired with participants",
                                relatedId: doc.id,
                                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                            });
                            console.log(`Applied -10 credibility to host ${hostId} for expired request ${doc.id}`);
                        } catch (err) {
                            console.error(`Error applying credibility for expired request ${doc.id}:`, err);
                        }
                    }
                }
            }

            console.log(`Successfully expired ${nonFullExpired.length} requests`);

        } catch (error) {
            console.error("Error cleaning up expired requests:", error);
        }
    }
);

