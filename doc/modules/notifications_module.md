# Notifications Module — Push Notifications via FCM

> **Module path:** `lib/features/notifications/`  
> **Files:** 1 (1 service)  
> **Total LOC:** ~150

---

## Overview

The Notifications module manages Firebase Cloud Messaging (FCM) integration, handling device token registration, background/foreground message processing, and in-app navigation from notification taps.

---

## File

| File | LOC | Purpose |
|------|-----|---------|
| `services/notification_service.dart` | ~150 | FCM token management, foreground handler, background handler, tap navigation |

---

## Key Features

### Token Management
- `requestPermission()` → requests iOS/Android push permission
- `getToken()` → retrieves FCM device token
- Stores token in `profiles/{userId}.fcmToken` (single string, latest device)
- Token refresh listener auto-updates Firestore

### Message Handling
| Context | Handler | Behavior |
|---------|---------|----------|
| **Foreground** | `FirebaseMessaging.onMessage` | Shows local snackbar/overlay notification |
| **Background** | `FirebaseMessaging.onBackgroundMessage` | System tray notification (handled by OS) |
| **Tap (terminated)** | `getInitialMessage()` | Opens relevant screen on cold start |
| **Tap (background)** | `onMessageOpenedApp` | Navigates to relevant screen |

### Notification Types (Server-Side)

All push notifications are triggered by Cloud Functions:

| Cloud Function | Trigger | Notification Content |
|----------------|---------|---------------------|
| `onNewChatMessage` | New message in chat | **DM:** sender name as title, message as body / **Group:** productName as title, "sender: message" as body |
| `onNewRequest` | New co-request created | title: "New Split Request!", body: "{productName} - {dealDescription}" |
| `onPendingJoinRequest` | User applies to join | title: "New Join Application!", body: "{requesterName} wants to join your request for {productName}" |
| `onJoinRequestApproved` | Host accepts application | title: "Application Approved!", body: "You've been accepted to join the request for {productName}" |
| `onRequestEdited` | Host edits request | title: "Request Updated", body: "The host updated \'{productName}\' (N changes)" |
| `onRequestStatusChange` | Status → completed/cancelled | title: "Request Completed/Cancelled", body: status-specific message |
| `onRTMMatchFound` | RTM status → matched | title: "Match Found!", body: "A real-time match has been found for {productName}" |
| `onUserJoinRequest` | New participant added | title: "New Partner Joined!", body: "{joinerName} joined your request for {productName}" |

### Mute Respect
- `onNewChatMessage` Cloud Function checks `mutedBy[]` array on the chat room
- If the recipient UID is in `mutedBy`, no notification is sent
- Mute state is managed by `ChatService.toggleMute()`

### Navigation Data
Notification payloads include `type` and relevant ID fields:
```json
{
  "type": "chat_message",      // or "new_request", "join_request_pending", etc.
  "chatRoomId": "roomId",       // for chat messages
  "requestId": "requestId",     // for request-related notifications
  "isDM": "true"                // for DM chat messages
}
```
`NotificationService` uses this data to navigate to the appropriate screen on tap.

---

## Integration with App Lifecycle

```
main.dart
    │
    ├─ FirebaseMessaging.onBackgroundMessage (top-level function)
    │
    └─ MainScreen.initState()
        └─ NotificationService.initialize()
            ├─ requestPermission()
            ├─ getToken() → save to Firestore
            ├─ setupTokenRefreshListener()
            ├─ setupForegroundHandler()
            └─ checkInitialMessage() → navigate if launched from notification
```
