# Home & Navigation Module — App Shell & Routing

> **Module path:** `lib/features/home/`  
> **Files:** 2 (2 screens)  
> **Total LOC:** ~600

---

## Overview

The Home module provides the main app shell with bottom navigation, tab routing, and the home dashboard screen.

---

## Files

| File | LOC | Purpose |
|------|-----|---------|
| `screens/main_screen.dart` | ~350 | App shell: BottomNavigationBar (4 tabs), Provider initialization, notification setup, RTM active indicator |
| `screens/home_screen.dart` | ~250 | Dashboard: quick action cards, active requests summary, RTM match status |

---

## Navigation Tabs (4 + Center FAB)

| Index | Tab | Icon | Screen |
|-------|-----|------|--------|
| 0 | Discover | `Icons.explore` | `FeedScreen` (co_request module) |
| 1 | My Splits | `Icons.list_alt` | `MyRequestsScreen` (co_request module) |
| — | + (Center FAB) | `Icons.add` | Bottom sheet: Create Request / Real-Time Match |
| 2 | Chats | `Icons.chat` | Chat list (StreamBuilder on `ChatService.getChatRoomsStream`) |
| 3 | Profile | `Icons.person` | `ProfileScreen` (own profile) |

### Badge Indicators
- **Chats tab:** Red dot shown when `unreadCount > 0`
- **My Splits tab:** Badge for pending join requests (host notifications)

---

## MainScreen Responsibilities

| Responsibility | Description |
|----------------|-------------|
| Provider init | Initializes `CoRequestProvider`, loads feed/my requests |
| FCM setup | Calls `NotificationService.initialize()` |
| Navigation | `IndexedStack` to preserve tab state across switches |
| System UI | Sets `SystemUiMode.manual` (top + bottom overlays, avoids edge-to-edge overlap) |
| Active RTM | Shows `ActiveMatchIndicator` floating badge if user has active RTM |

---

## HomeScreen Features

| Feature | Description |
|---------|-------------|
| Quick Actions | Cards for: Create Request, Browse Feed, Start RTM, My Requests |
| Active Requests | Count of user's active co-requests |
| Pending Joins | Count of pending join applications (host view) |
| RTM Status | Shows active real-time match status |
| Welcome Banner | Personalized greeting with user's display name |
