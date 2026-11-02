# Profile & Trust Module — User Profiles, Credibility, Ratings & Reports

> **Module path:** `lib/features/profile/`  
> **Files:** 13 (2 models, 4 services, 4 screens, 3 widgets)  
> **Total LOC:** ~3,500

---

## Overview

The Profile module manages user profiles, the credibility scoring system, user ratings, personal remarks, and user reporting. It forms the trust layer of i-Share, ensuring that reliable users are rewarded and bad actors are penalized.

---

## Files & Responsibilities

### Models
| File | LOC | Purpose |
|------|-----|---------|
| `models/user_profile_model.dart` | ~120 | Extended profile model with credibility score, rating, stats, bio, bannerColor |
| `models/remark_model.dart` | ~30 | `UserRemark` model (targetUserId, remark text, updatedAt) |

### Services
| File | LOC | Purpose |
|------|-----|---------|
| `services/profile_service.dart` | 267 | Profile CRUD: getOrCreateProfile, updateProfile, submitRating |
| `services/credibility_service.dart` | 409 | Credibility scoring engine: 11 event types, 3-tier system, weighted rating, audit log |
| `services/remark_service.dart` | 64 | Private user-to-user remarks (client-side only, Firestore subcollection) |
| `services/report_service.dart` | 104 | Report submission with 24h duplicate check, 5 reason types |

### Screens
| File | LOC | Purpose |
|------|-----|---------|
| `screens/profile_screen.dart` | ~800 | User profile view: stats grid, credibility badge, ratings list, bio, DM/report/remark actions |
| `screens/account_settings_screen.dart` | ~700 | Account management: link email/phone/Google, change password, notification prefs |
| `screens/settings_screen.dart` | ~300 | App settings: about, privacy, logout |
| `screens/all_reviews_screen.dart` | ~200 | Full list of ratings received |

### Widgets
| File | LOC | Purpose |
|------|-----|---------|
| `widgets/credibility_badge.dart` | ~150 | Reusable badge: tier icon + score + level text |
| `widgets/rate_user_dialog.dart` | ~200 | Star rating dialog with optional comment |
| `widgets/report_user_dialog.dart` | ~200 | Report dialog with reason selector + description |

---

## Credibility Scoring System

### 3-Tier System

| Tier | Score Range | Badge Color | Icon |
|------|------------|-------------|------|
| User | 0–299 | 🔵 Blue (0xFF4FC3F7) | `assets/icons/CUser.png` |
| Trusted | 300–699 | 🟢 Green (0xFF81C784) | `assets/icons/CTrusted.png` |
| Elite | 700+ | 🟡 Gold (0xFFFFD54F) | `assets/icons/CElite.png` |

### Score Events (11 types)

| Event | Points | Trigger |
|-------|--------|---------|
| `completeDeal` | **+15** | Host completes a deal |
| `rating5Star` | **+10** | Receives a 5-star rating |
| `rating4Star` | **+3** | Receives a 4-star rating |
| `cancelWithParticipants` | **-25** | Host cancels request that has participants |
| `leaveRequest` | **-10** | Participant leaves a request |
| `expiredWithParticipants` | **-10** | Host let request expire with participants |
| `verifyEmail` | **+20** | Email verification completed |
| `verifyPhone` | **+30** | Phone verification completed |
| `complaint` | reserved | For future use |

- **Default starting score:** 100 points (on registration)
- **Score floor:** 0 (cannot go negative, clamped in `updateScore`)

### Anti-Fraud: Weighted Rating Average
```
For each rater:
    rater_average = mean(all ratings from this rater to this user)

Final average = mean(all rater_averages)
```
This prevents a single user from inflating scores through spam ratings.

### Audit Trail
Every score change creates a `profiles/{userId}/score_activities/{activityId}` document:
```json
{
  "event": "completeDeal",
  "description": "Completed a deal",
  "points": 15,
  "createdAt": "2026-...",
  "relatedId": "requestId"
}
```

---

## Profile Service Methods

| Method | Description |
|--------|-------------|
| `getOrCreateProfile(userId)` | Fetch profile; create with defaults if missing |
| `updateProfile(userId, data)` | Update display name, bio, avatar, banner color |
| `submitRating(ratedUserId, requestId, rating, comment)` | Submit rating (calls CredibilityService internally) |
| `getUserProfile(userId)` | One-shot profile fetch |
| `getUserProfileStream(userId)` | Real-time profile stream |

---

## Remark Service

Private notes that only the current user can see — stored as a subcollection under the user's profile: `profiles/{currentUserId}/remarks/{targetUserId}`.

| Method | Description |
|--------|-------------|
| `getRemark(targetUserId)` | Fetch remark for a user |
| `setRemark(targetUserId, remark)` | Set or update remark |
| `deleteRemark(targetUserId)` | Delete remark |

Privacy: Remarks are readable only by the creator. Target user has no visibility.

---

## Report Service

Reports are stored in a top-level `reports` collection with admin visibility.

### Report Reasons (5)
| Reason | Display Text |
|--------|-------------|
| `spam` | Spam / Advertising |
| `fraud` | Fraud / Scam |
| `harassment` | Harassment / Abuse |
| `inappropriate` | Inappropriate Content |
| `other` | Other |

### Anti-Abuse
- Cannot report yourself
- 24-hour cooldown per reporter-target pair
- `hasReportedUser()` check before showing report button

---

## Account Settings Screen

Manages linked authentication providers and preferences:

| Feature | Description |
|---------|-------------|
| **Link Email** | Link/unlink email+password to existing account |
| **Link Phone** | Link/unlink phone number with OTP flow |
| **Link Google** | Link/unlink Google Sign-In provider |
| **Change Password** | For email-linked accounts |
| **Notification Preferences** | Toggle push notifications (via SharedPreferences + FCM topic) |

---

## Screen Flow

```
ProfileScreen (viewable by any user)
    │
    ├─ Own profile:
    │   ├─ "Edit Profile" → inline edit (display name, bio, avatar, banner)
    │   ├─ "Account Settings" → AccountSettingsScreen
    │   ├─ "Settings" → SettingsScreen
    │   └─ Stats grid: Requests, Joined, Completed, Rating
    │
    └─ Other user's profile:
        ├─ "Send DM" → creates/opens DM chat
        ├─ "Add Remark" → private note dialog
        ├─ "Report User" → ReportUserDialog
        ├─ "View All Reviews" → AllReviewsScreen
        └─ Credibility badge with score + tier
```
