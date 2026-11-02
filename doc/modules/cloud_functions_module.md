# Cloud Functions Module — Backend Logic & Automation

> **Module path:** `functions/src/index.ts`  
> **Files:** 1  
> **Total LOC:** ~1,554

---

## Overview

The Cloud Functions module contains all serverless backend logic for i-Share. It runs on Firebase Cloud Functions (Node.js) and provides:
- **Secure callable functions** for operations requiring atomicity and authorization
- **Firestore triggers** for automated side effects (notifications, cleanup)
- **Scheduled tasks** for periodic maintenance

---

## Functions Summary (18 Total)

### Secure Callable Functions (5)

| Function | Description |
|----------|-------------|
| `acceptJoinRequestSecure` | Atomically: accept join request → add to participants → create chat → update stats |
| `verifyQrCodeSecure` | Verify QR code scan: rate-limit (5 attempts), anti-self-verify, update verified list |
| `leaveRequestSecure` | Leave co-request: remove from participants, send system message, apply credibility penalty |
| `leaveRtmRoomSecure` | Leave RTM room: remove from participants, handle status transitions correctly |
| `notifyRequestEdited` | Notify all participants when host edits a request |

### Firestore Triggers (8)

| Function | Trigger | Side Effect |
|----------|---------|-------------|
| `onNewChatMessage` | `chat_rooms/{roomId}/messages/{msgId}` created | Send FCM push to all participants (respects mute) |
| `onNewRequest` | `co_requests/{requestId}` created | Push notification to all registered FCM tokens |
| `onPendingJoinRequest` | `co_requests/{requestId}/join_requests/{joinId}` created | Notify host of new join application |
| `onJoinRequestApproved` | `join_requests` status → `accepted` | Notify requester of approval |
| `onRequestCompleted` | `co_requests` status → `completed` | Notify all participants, update stats |
| `onDealCompleted` | `co_requests` completedAt set | Additional completion logic |
| `onHostCancelled` | `co_requests` status → `cancelled` | Credibility penalty to host, notify participants |
| `onRequestExpired` | `co_requests` status → `expired` | Credibility penalty if participants existed |

### Scheduled Functions (2)

| Function | Schedule | Description |
|----------|----------|-------------|
| `cleanupExpiredRequests` | Every 30 minutes | Finds active requests past `expiresAt`, sets status=expired (only if not fully joined) |
| `cleanupExpiredRtmRooms` | Every 30 minutes | Finds waiting RTM rooms past `expiresAt`, sets status=closed |

### HTTP Functions (1)

| Function | Description |
|----------|-------------|
| `sendTestNotification` | Debug-only function for testing FCM delivery |

### Utility Functions (2)

| Function | Description |
|----------|-------------|
| `checkExpiredRequests` | On-demand version of `cleanupExpiredRequests` |
| `syncFcmToken` | Callable to sync device FCM token to user profile |

---

## Notification Format

### Chat Messages
- **DM format:** `"{senderName}: {message}"`
- **Group format:** `"{senderName} in {productName}: {message}"`
- **Image messages:** Content replaced with `"Sent an image"`

### Mute Check Logic
```typescript
const chatRoomDoc = await db.doc(`chat_rooms/${roomId}`).get();
const mutedBy = chatRoomDoc.data()?.mutedBy || [];

// Skip notification if recipient muted this chat
if (mutedBy.includes(recipientUid)) {
    console.log(`Skipping notification for muted user: ${recipientUid}`);
    continue;
}
```

---

## Security Patterns

### Callable Function Auth
All callable functions verify authentication:
```typescript
export const functionName = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Must be signed in');
    }
    const userId = request.auth.uid;
    // ... business logic
});
```

### Rate Limiting (QR Verification)
```typescript
const MAX_ATTEMPTS = 5;
const attempts = verificationDoc.data()?.attempts?.[participantId] || 0;
if (attempts >= MAX_ATTEMPTS) {
    return { success: false, message: 'Rate limit exceeded' };
}
```

### Anti-Self-Verification
```typescript
if (participantId === verificationDoc.data()?.ownerId) {
    return { success: false, message: 'Cannot verify yourself' };
}
```

---

## Deployment

```bash
cd functions
npm install
firebase deploy --only functions
```

Individual function deployment:
```bash
firebase deploy --only functions:onNewChatMessage
```
