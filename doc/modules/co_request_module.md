# Co-Request Module — Group Buying Requests (Core Feature)

> **Module path:** `lib/features/co_request/`  
> **Files:** 18 (2 models, 4 services, 1 provider, 9 screens, 2 widgets)  
> **Total LOC:** ~5,800

---

## Overview

The Co-Request module is the core feature of i-Share. It enables users to create group buying requests, browse and join requests, manage join applications (host approval flow), verify transactions via QR codes, and rate transaction partners after completion.

---

## Files & Responsibilities

### Models
| File | LOC | Purpose |
|------|-----|---------|
| `models/co_request_model.dart` | 381 | `CoRequest` data model with Firestore serialization, `calculatePricePerPerson()`, `copyWith()`, mock data, `RequestCategories` (12 categories with icons) |
| `models/join_request_model.dart` | 119 | `JoinRequest` model with status constants (pending/accepted/rejected/cancelled) |

### Services
| File | LOC | Purpose |
|------|-----|---------|
| `services/co_request_service.dart` | 500 | CRUD for `co_requests` collection + `ImageUploadService` for Firebase Storage uploads |
| `services/join_request_service.dart` | 255 | CRUD for `join_requests` subcollection, uses `acceptJoinRequestSecure` Cloud Function |
| `services/qr_verification_service.dart` | 256 | QR code generation/verification, session reuse, `VerificationResult` / `VerificationStatus` models |
| `services/location_service.dart` | 139 | Singleton for GPS, reverse geocoding, distance calculation, permission handling |

### Provider
| File | LOC | Purpose |
|------|-----|---------|
| `providers/co_request_provider.dart` | 478 | ChangeNotifier: real-time Firestore listeners, CRUD operations, category filtering, distance calculation, user stats updates, RTM→CoBuy participant adding |

### Screens
| File | LOC | Purpose |
|------|-----|---------|
| `screens/create_request_screen.dart` | ~1,900 | Create + Edit request form: product info, image, price, location, category, expiry |
| `screens/feed_screen.dart` | ~400 | Browse active requests with search, category filter, real-time updates |
| `screens/request_detail_screen.dart` | ~800 | Full request details: join, leave, open chat, QR verify, complete, cancel |
| `screens/my_requests_screen.dart` | ~350 | Tabbed view: "My Requests" + "Joined Requests" with status filters |
| `screens/join_requests_screen.dart` | ~300 | Host view: manage pending join applications (accept/reject) |
| `screens/qr_verification_screen.dart` | ~500 | QR display (host) + QR scanner (participant), live verification status |
| `screens/review_screen.dart` | ~300 | Post-deal rating (1-5 stars) with comment, duplicate check |
| `screens/location_picker_screen.dart` | ~350 | Google Maps picker: GPS auto or manual pin, reverse geocode display |
| `screens/map_view_screen.dart` | ~300 | Map view of nearby active requests with markers |

### Widgets
| File | LOC | Purpose |
|------|-----|---------|
| `widgets/request_card.dart` | ~200 | Reusable card component for feed/list display |
| `widgets/common_widgets.dart` | ~150 | Shared UI components (status chips, price display, etc.) |

---

## Architecture

```
┌────────────────────┐     ┌──────────────────────┐     ┌────────────────────────┐
│  Screens (9)       │────→│  CoRequestProvider   │────→│  CoRequestService      │
│  Feed, Detail,     │     │  (ChangeNotifier)    │     │  JoinRequestService    │
│  Create, QR, etc.  │     │  Real-time listeners │     │  QrVerificationService │
└────────────────────┘     └──────────┬───────────┘     │  LocationService       │
                                      │                 │  ImageUploadService    │
                              notifyListeners()         └──────────┬─────────────┘
                                      │                            │
                              ┌───────▼───────┐           Cloud Firestore
                              │   main.dart   │           Cloud Functions
                              │  Consumer<>   │           Firebase Storage
                              └───────────────┘
```

---

## CoRequest Model Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Firestore document ID |
| `initiatorId` | `String` | Host user's UID |
| `initiatorName` | `String` | Host display name |
| `initiatorPhotoUrl` | `String?` | Host avatar URL |
| `productName` | `String` | Product/deal name |
| `productPhotoUrl` | `String?` | Product image (Firebase Storage) |
| `dealDescription` | `String` | Deal details text |
| `totalPrice` | `double` | Total price for the group |
| `pricePerPerson` | `double` | Auto-calculated: `totalPrice / (partnersNeeded + 1)` |
| `totalQuantity` | `int` | Total quantity available |
| `partnersNeeded` | `int` | Number of partners needed (1–10) |
| `participants` | `List<String>` | User IDs who joined (includes initiator) |
| `storeName` | `String` | Store/shop name |
| `latitude` / `longitude` | `double` | Store coordinates |
| `storeAddress` | `String?` | Reverse-geocoded address |
| `distanceMeters` | `double?` | Client-side distance from user |
| `category` | `String` | One of 12 categories |
| `status` | `String` | `active` / `completed` / `expired` / `cancelled` |
| `notes` | `String?` | Additional notes |
| `createdAt` | `DateTime` | Creation timestamp |
| `expiresAt` | `DateTime` | Expiry timestamp |
| `completedAt` | `DateTime?` | Completion timestamp |

---

## Request Categories (5)

| Key | Label | Icon Asset |
|-----|-------|------------|
| `food` | Food & Groceries | `assets/icons/CateFoodBeve.png` |
| `household` | Household | `assets/icons/CateHousehold.png` |
| `electronics` | Electronics | `assets/icons/CateElectro.png` |
| `personal` | Personal Care | `assets/icons/CateBeuty.png` |
| `others` | Others | `assets/icons/CateOthers.png` |

---

## Key Flows

### Create Request Flow
```
CreateRequestScreen
    │
    ├─ Fill form: product name, image (camera/gallery), deal description
    ├─ Price: total price + partner count → auto-calculate price per person
    ├─ Location: GPS auto-detect OR manual map picker (LocationPickerScreen)
    ├─ Category: 12 categories selector
    ├─ Expiry: 1h / 3h / 6h / 12h / 24h / 2d / 3d / 7d
    └─ Submit
         ├─ Upload image → Firebase Storage (via ImageUploadService)
         ├─ Create Firestore document (via CoRequestService.createRequest)
         ├─ Increment user's totalRequests count
         └─ Trigger onNewRequest Cloud Function → push notification to all users
```

### Join Request Flow
```
FeedScreen → RequestDetailScreen → "Apply to Join"
    │
    ├─ Creates JoinRequest document in subcollection (status: "pending")
    ├─ Triggers onPendingJoinRequest CF → notifies host
    │
    ├─ Host opens JoinRequestsScreen
    │   ├─ Accept → acceptJoinRequestSecure Cloud Function (atomic)
    │   │   ├─ Updates JoinRequest.status = "accepted"
    │   │   ├─ Adds user to co_request.participants[]
    │   │   ├─ Increments user's totalJoined
    │   │   ├─ Creates/updates chat room
    │   │   └─ Triggers onJoinRequestApproved CF → notifies requester
    │   │
    │   └─ Reject → updates JoinRequest.status = "rejected"
    │       └─ User can re-apply after rejection
    │
    └─ Requester can cancel pending request
```

### QR Verification Flow
```
RequestDetailScreen → "Verify with QR"
    │
    ├─ Host: QrVerificationScreen (display mode)
    │   ├─ Generates QR data: { requestId, secret, ownerId }
    │   ├─ Stores session in qr_verifications/{requestId}
    │   ├─ Reuses existing non-expired session (preserves verified users)
    │   └─ Shows real-time verification status list
    │
    └─ Participant: QrVerificationScreen (scan mode)
        ├─ Scans QR → calls verifyQrCodeSecure Cloud Function
        ├─ Rate limiting: max 5 attempts per user per session
        ├─ Anti-fraud: owner cannot self-verify
        └─ Success → added to verifiedIds[]
```

### Edit Request Flow
```
RequestDetailScreen → "Edit" (host only)
    │
    ├─ Opens CreateRequestScreen in edit mode (prefilled)
    ├─ Only sends CHANGED fields to Firestore
    │   └─ Prevents arePriceFieldsLocked() rule violation when participants exist
    ├─ Triggers onRequestEdited CF → notifies all participants
    └─ System message sent to chat room
```

### Request Lifecycle
```
Status Transitions:
  active ──→ completed  (host marks complete, all participants notified)
  active ──→ expired    (auto via cleanupExpiredRequests CF, non-full only)
  active ──→ cancelled  (host cancels, credibility penalty if participants exist)
  expired ──→ active    (host extends with additional hours)

Credibility Effects:
  • Complete deal:             +15 to host
  • Cancel with participants:  -25 to host
  • Cancel without participants: 0
  • Leave request:             -10 to participant
  • Request expires with participants: -10 to host
```

---

## Firestore Security Rules (Co-Request Specific)

- **Create:** Any authenticated user
- **Read:** Any authenticated user
- **Update:** Host only (`initiatorId == request.auth.uid`), with:
  - `initiatorId` is immutable after creation
  - Status transitions forward-only: `active → completed/expired/cancelled`
  - Price fields (`totalPrice`, `pricePerPerson`, `partnersNeeded`) locked when `participants.size() > 1`
- **Delete:** Host only
