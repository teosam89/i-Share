# Real-Time Match (RTM) Module — Live Partner Matching

> **Module path:** `lib/features/realtime_match/`  
> **Files:** 7 (1 model, 4 screens, 1 service, 1 widget)  
> **Total LOC:** ~2,500

---

## Overview

The Real-Time Match (RTM) module allows users to find co-buying partners instantly based on location proximity and shared interest categories. It implements a wizard-based matching flow, live waiting room, match-to-co-buy conversion, and dedicated RTM chat.

---

## Files & Responsibilities

| File | LOC | Purpose |
|------|-----|---------|
| `models/realtime_match_model.dart` | 150 | `RealtimeMatch` model + `MatchRadius` (0.5/1/2/5/10 km) + `PartnerCount` (1/2/3) constants |
| `services/realtime_match_service.dart` | 382 | Firestore CRUD: find/create/join/leave rooms, location-based matching, chat room creation, close for conversion |
| `screens/realtime_match_screen.dart` | ~600 | Matching wizard: category → location → radius → partner count → search/create |
| `screens/match_waiting_screen.dart` | ~350 | Live waiting room: real-time status updates, expires countdown, leave room |
| `screens/realtime_match_detail_screen.dart` | ~350 | Match detail: participant list, status, convert to CoBuy, open chat, close match |
| `screens/rtm_to_cobuy_screen.dart` | ~600 | Pre-filled CoBuy creation form from RTM, auto-adds all participants |
| `widgets/active_match_indicator.dart` | ~100 | Floating badge on home showing active match count |

---

## RealtimeMatch Model

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Firestore document ID |
| `ownerId` | `String` | Room creator UID |
| `ownerName` | `String` | Creator display name |
| `ownerPhotoUrl` | `String?` | Creator avatar |
| `category` | `String` | Shopping category |
| `latitude` / `longitude` | `double` | Match center coordinates |
| `radiusKm` | `double` | Match radius in km |
| `locationName` | `String` | Reverse-geocoded location |
| `participants` | `List<String>` | User UIDs in the room |
| `maxPartners` | `int` | Max partners (1–3), excluding owner |
| `status` | `String` | `waiting`, `matched`, `closed` |
| `chatRoomId` | `String?` | Linked chat room ID (`rtm_{matchId}`) |
| `createdAt` | `DateTime` | Room creation time |
| `expiresAt` | `DateTime` | Auto-expiry (default 24h) |

---

## Matching Algorithm

```
User selects: category, location, radius, partner count
    │
    ├─ Query Firestore: realtime_matches
    │   WHERE status == 'waiting'
    │   AND category == selected
    │   AND maxPartners == selected
    │   AND NOT expired
    │
    ├─ Filter by distance: LocationService.calculateDistance() < radiusKm
    │   (Client-side geo-filter since Firestore lacks native geo queries)
    │
    ├─ Match found → joinRoom() (Transaction-based to prevent race conditions)
    │   ├─ Add user to participants[]
    │   ├─ If room full (participants.length >= maxPartners + 1):
    │   │   ├─ Set status = 'matched'
    │   │   └─ Create chat room (rtm_{matchId})
    │   └─ Navigate to MatchWaitingScreen
    │
    └─ No match → createRoom()
        ├─ Create new waiting room
        ├─ Navigate to MatchWaitingScreen
        └─ Wait for other users to join
```

---

## Key Flows

### RTM → Co-Buy Conversion
```
RealtimeMatchDetailScreen → "Convert to CoBuy"
    │
    ├─ Opens RtmToCobuyScreen (pre-filled with RTM data)
    │   ├─ Category, location, participant count pre-set
    │   └─ User fills: product name, price, description, image, expiry
    │
    ├─ Creates new CoRequest
    │   ├─ Auto-adds all RTM participants via addParticipantFromRtm()
    │   └─ Creates group chat for the CoBuy request
    │
    └─ Closes RTM match (status → 'closed')
        └─ System message: "This match has been converted to a Co-Buy request"
```

### Leave/Close Room
- **Leave:** Uses `leaveRtmRoomSecure` Cloud Function (handles status transitions correctly)
- **Close:** Owner sets status to `closed`, prevents further joins

### Restrictions
- Users can only have **one active waiting match** at a time
- Cannot join own room
- Room auto-expires after 24 hours

---

## Service Methods (`RealtimeMatchService`)

| Method | Description |
|--------|-------------|
| `findMatchingRoom()` | Query waiting rooms by category/radius + distance filter |
| `createRoom()` | Create new waiting room with user as owner |
| `joinRoom()` | Transaction-based join (prevents race conditions) |
| `leaveRoom()` | Cloud Function call: `leaveRtmRoomSecure` |
| `closeMatchForConversion()` | Set status='closed' + system message to chat |
| `getUserMatches()` | Stream of user's active matches |
| `getMatchStream()` | Real-time stream of single match |
| `getUserActiveWaitingMatches()` | Check for existing waiting matches |
| `getActiveMatchesStream()` | All active matches (for map display) |
| `_getCurrentUserName/Photo()` | Fetch profile data for room creation |
