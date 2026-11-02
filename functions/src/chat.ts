/**
 * Chat Cloud Functions
 * Covers: push notifications for new chat messages across DM, group, and RTM chat rooms.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { db, messaging } from "./lib/firebase";

/**
 * Send push notification when a new chat message is created.
 * - DM: title = sender's display name, body = message content
 * - Group chat: title = chat room name, body = "senderName: message"
 * - Skips system messages, the sender, and users who muted the chat.
 */
export const onNewChatMessage = onDocumentCreated(
    "chat_rooms/{chatRoomId}/messages/{messageId}",
    async (event) => {
        const snapshot = event.data;
        if (!snapshot) return;

        const messageData = snapshot.data();
        const chatRoomId = event.params.chatRoomId;

        // Skip system messages
        if (messageData.type === "system") return;

        const senderId = messageData.senderId;
        const senderName = messageData.senderName || "Someone";
        const content = messageData.content || "";
        const messageType = messageData.type || "text";

        const chatRoomDoc = await db.collection("chat_rooms").doc(chatRoomId).get();
        if (!chatRoomDoc.exists) return;

        const chatRoomData = chatRoomDoc.data()!;
        const isDM = chatRoomData.isDM === true || chatRoomId.startsWith("dm_");
        const participantIds: string[] = chatRoomData.participantIds || [];
        const mutedBy: string[] = chatRoomData.mutedBy || [];
        const chatRoomName = chatRoomData.productName || "Chat";

        let notifTitle: string;
        let notifBody: string;

        if (isDM) {
            notifTitle = senderName;
            notifBody = messageType === "image" ? "Sent a photo" : content;
        } else {
            notifTitle = chatRoomName;
            notifBody = messageType === "image"
                ? `${senderName}: Sent a photo`
                : `${senderName}: ${content}`;
        }

        // Send to all participants except the sender and muted users
        const recipients = participantIds.filter(
            (id) => id !== senderId && !mutedBy.includes(id)
        );

        if (recipients.length === 0) return;

        for (const userId of recipients) {
            try {
                const userDoc = await db.collection("profiles").doc(userId).get();
                if (!userDoc.exists) continue;

                const fcmToken = userDoc.data()?.fcmToken;
                if (!fcmToken) continue;

                await messaging.send({
                    token: fcmToken,
                    notification: { title: notifTitle, body: notifBody },
                    data: {
                        type: "chat_message",
                        chatRoomId: chatRoomId,
                        isDM: isDM ? "true" : "false",
                        senderId: senderId,
                    },
                    android: {
                        priority: "high",
                        notification: { channelId: "chat_messages", icon: "ic_notification" },
                    },
                    apns: { payload: { aps: { badge: 1, sound: "default" } } },
                });
            } catch (error) {
                console.error(`Error sending chat notification to ${userId}:`, error);
            }
        }

        console.log(`Chat notification sent for ${chatRoomId} to ${recipients.length} recipients`);
    }
);
