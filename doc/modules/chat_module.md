# Chat Module — Real-Time Messaging System

> **Module path:** `lib/features/chat/`  
> **Files:** 3 (1 model, 1 screen, 1 service)  
> **Total LOC:** ~2,100

---

## Overview

The Chat module provides real-time messaging between users via Firestore listeners. It supports three chat room types: **Group Chats** (auto-created for co-requests), **Direct Messages** (DMs, user-to-user), and **RTM Chats** (auto-created when a Real-Time Match is found). Features include text/image messages, system messages, per-user mute, read status tracking, unread indicators, and chat deletion.

---

## Files & Responsibilities

| File | LOC | Purpose |
|------|-----|---------|
| `models/chat_model.dart` | 168 | `ChatRoom` + `ChatMessage` data models with Firestore serialization |
| `services/chat_service.dart` | 443 | All chat CRUD: send/stream messages, create/manage rooms, mute, mark read, image upload, delete |
| `screens/chat_screen.dart` | 1,482 | Full-featured chat UI: message list, input, image preview, chat info, mute toggle, delete, navigate to linked request/RTM |

---

## Data Models

### ChatRoom

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Document ID. Format: `{requestId}` for group, `dm_{user1}_{user2}` for DM, `rtm_{matchId}` for RTM |
| `requestId` | `String?` | Linked co-request ID (null for DMs) |
| `productName` | `String` | Product name (or other user's display name for DMs) |
| `participantIds` | `List<String>` | All user UIDs in the room |
| `createdAt` | `DateTime` | Room creation time |
| `lastMessageAt` | `DateTime?` | Timestamp of the most recent message |
| `lastMessage` | `String?` | Preview text of the latest message |
| `isDM` | `bool` | `true` for DMs, `false` for group/RTM chats |
| `lastReadAt` | `Map<String, DateTime>` | Per-user last read timestamps |
| `mutedBy` | `List<String>` | UIDs of users who muted this chat |

### ChatMessage

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Document ID |
| `chatRoomId` | `String` | Parent room ID |
| `senderId` | `String` | Sender UID (or "system" for system messages) |
| `senderName` | `String` | Sender display name |
| `senderPhotoUrl` | `String?` | Sender avatar |
| `content` | `String` | Message text or image URL |
| `type` | `String` | `text`, `image`, or `system` |
| `timestamp` | `DateTime` | Message timestamp |
| `isRead` | `bool` | Legacy single-user read flag |

---

## Key Features

### Message Types
1. **Text messages** — Standard text, with sender bubble styling
2. **Image messages** — Camera/gallery pick → staged preview → upload to Firebase Storage → send as image URL
3. **System messages** — Auto-generated for events (user joined, request edited, etc.)

### Mute Functionality
- Per-user, per-chat mute via `mutedBy[]` array in Firestore
- `ChatService.toggleMute()` uses `FieldValue.arrayUnion/Remove`
- Muted chats skip push notifications (checked in Cloud Function `onNewChatMessage`)
- Mute state shown as bell icon toggle in chat app bar

### Read Status & Unread Indicators
- `lastReadAt[userId]` updated via `ChatService.markAsRead()` when chat is opened
- `ChatRoom.hasUnread(userId)` compares `lastMessageAt > lastReadAt[userId]`
- Unread dot shown on chat list items and navigation badge count

### Chat Deletion
- Available for completed co-requests and closed RTM matches
- Removes user from `participantIds[]` (hides from chat list)
- Does NOT delete messages or the room itself

### Chat Lock
- When linked co-request status is `completed`, `expired`, or `cancelled`, or RTM status is `closed`
- Message input is disabled, replaced with a "Chat locked" notice

### Chat Info Panel
- **Group chats:** Shows all participants, linked request details, navigate to request, mute toggle, delete option
- **DM chats:** Shows other user's profile, personal remark (via `RemarkService`), navigate to full profile
- **RTM chats:** Links to RTM detail screen

---

## Service Methods (`ChatService`)

| Method | Description |
|--------|-------------|
| `getChatRoomsStream()` | Real-time stream of rooms where user is a participant |
| `getMessagesStream()` | Paginated message stream (oldest first, infinite scroll) |
| `sendMessage()` | Send text message + update room metadata (lastMessage, lastMessageAt) |
| `sendImageMessage()` | Upload image to Storage → send as image message |
| `createChatRoom()` | Create group chat for co-request |
| `createDmChatRoom()` | Create DM room (deterministic ID: `dm_{min}_{max}`) |
| `findExistingDmRoom()` | Check if DM room already exists |
| `addParticipant()` | Add user to existing room |
| `removeParticipant()` | Remove user from room |
| `markAsRead()` | Update `lastReadAt[userId]` to now |
| `toggleMute()` | Toggle mute status for current user |
| `isMuted()` | Check if chat is muted by current user |
| `sendSystemMessage()` | Send a system-type message |
| `deleteChatRoom()` | Remove user from room (hide the chat) |
| `getUnreadCount()` | Count rooms with unread messages |

---

## Screen Breakdown (`ChatScreen` — 1,482 lines)

| Section | Description |
|---------|-------------|
| `initState` | Subscribe to messages stream, listen for access changes, check lock status, resolve DM name, load mute state |
| `_listenForAccessChanges()` | Exit screen if user removed from room |
| `_checkChatLockStatus()` | Check linked request/RTM status → lock UI |
| `_sendMessage()` | Send text message, scroll to bottom |
| `_showImagePickerOptions()` | Camera/gallery bottom sheet |
| `_pickImage()` / `_sendPendingImage()` | Stage image preview → upload & send |
| `_showChatInfo()` | Bottom sheet with participants, linked request, mute, delete |
| `_showDmChatInfo()` | DM-specific info with remark editing |
| `_showRtmChatInfo()` | Navigate to RTM detail screen |
| `_confirmDeleteChat()` | Confirm dialog → delete (hide) chat |
| `_toggleMute()` | Mute/unmute with snackbar feedback |
| `build()` | StreamBuilder for messages, ListView.builder with bubbles, input bar |
| `_buildMessageBubble()` | Styled bubble: sender/receiver, avatar, timestamp, image tap |
| `_buildImagePreview()` | Staged image preview bar above input |
| `_buildMessageInput()` | TextField + attachment + send buttons |
| `_buildLockedNotice()` | Disabled input with lock explanation |
