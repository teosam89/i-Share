# Core Utilities Module — Shared Constants, Theme, and Widgets

> **Module path:** `lib/core/`  
> **Files:** 7 (2 constants, 1 theme, 1 service, 3 widgets)  
> **Total LOC:** ~800

---

## Overview

The Core module provides shared constants, theming, and reusable widgets used across all feature modules. It defines the app's visual identity, API configuration, and utility components.

---

## Files & Responsibilities

### Constants
| File | LOC | Purpose |
|------|-----|---------|
| `constants/app_colors.dart` | 78 | Color palette: primary (blue #2563EB), secondary (green #10B981), accent (amber #F59E0B), surface, background, text, status colors, trust score colors, category colors, gradients |
| `constants/app_constants.dart` | 80 | App name (`i-Share`), version, default values (search radius 5km, expiry 48h, participants 2–10), 10 legacy product categories, notification types, validation limits, map defaults (Kuala Lumpur) |

### Theme
| File | LOC | Purpose |
|------|-----|---------|
| `theme/app_theme.dart` | 250 | Material 3 `ThemeData`: light theme (primary), minimal dark theme (optional), custom `ColorScheme`, `TextTheme`, button styles, input decoration, card/dialog/chip themes |

### Services
| File | LOC | Purpose |
|------|-----|---------|
| `services/update_service.dart` | ~100 | App version check: compares installed version vs. Firestore `app_config/latest_version`, prompts update dialog |

### Widgets
| File | LOC | Purpose |
|------|-----|---------|
| `widgets/image_crop_screen.dart` | ~150 | Full-screen image cropper using `image_cropper` package, returns cropped file path |
| `widgets/network_aware_widget.dart` | ~100 | Wrapper that shows offline banner when no internet (uses `connectivity_plus`) |
| `widgets/places_autocomplete.dart` | ~120 | Google Places autocomplete text field for location search (uses `google_places_flutter`) |

---

## Color System (`AppColors`)

| Color | Hex | Usage |
|-------|-----|-------|
| `primary` | `#2563EB` (Blue) | App bar, buttons, accents |
| `primaryLight` | `#60A5FA` | Gradient ends, light accents |
| `primaryDark` | `#1E40AF` | Pressed states, dark headers |
| `secondary` | `#10B981` (Green) | Success states, secondary actions |
| `accent` | `#F59E0B` (Amber) | CTAs, highlights, warnings |
| `surface` | `#FFFFFF` (White) | Cards, dialogs |
| `background` | `#F9FAFB` (Light Gray) | App background |
| `textPrimary` | `#111827` (Near Black) | Main text |
| `textSecondary` | `#6B7280` (Gray) | Subtitles, hints |
| `success` | `#10B981` (Green) | Completed, verified |
| `warning` | `#F59E0B` (Amber) | Expiry warnings |
| `error` | `#EF4444` (Red) | Errors, cancel, delete |
| `info` | `#3B82F6` (Blue) | Informational badges |

---

## Theme (`AppTheme`)

- **Mode:** Light theme (primary), minimal dark theme (optional)
- **Material 3:** `useMaterial3: true`
- **Font:** System default (no custom fonts)
- **Cards:** Flat (elevation: 0) with 1px border, rounded corners (borderRadius: 12)
- **Input fields:** Filled white with rounded borders (borderRadius: 12)
- **Buttons:** Flat ElevatedButton (elevation: 0) with primary blue, rounded corners (borderRadius: 12)
- **Bottom Nav:** Fixed type, selected = primary blue, unselected = gray

---

## Update Service

Checks for new app versions on startup:
```
Firestore: app_config/latest_version
    │
    ├─ currentVersion < latestVersion → show update dialog
    │   ├─ Force update → blocks app until updated
    │   └─ Optional update → dismissable dialog
    │
    └─ currentVersion >= latestVersion → no action
```

---

## Network-Aware Widget

Wraps screens with connectivity monitoring:
- Uses `connectivity_plus` to listen for connection changes
- Shows a red "No Internet" banner when offline
- Auto-dismisses when connection restored
