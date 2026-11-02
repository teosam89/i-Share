# Auth Module — Authentication & User Onboarding

> **Module path:** `lib/features/auth/`  
> **Files:** 11 (1 model, 8 screens, 2 services)  
> **Total LOC:** ~2,550

---

## Overview

The Auth module handles all user registration, login, and onboarding flows. It supports three authentication methods — **Email/Password**, **Phone/OTP**, and **Google Sign-In** — and manages reactive auth state across the entire app via `AuthProvider` (Provider pattern).

---

## Files & Responsibilities

| File | LOC | Purpose |
|------|-----|---------|
| `models/user_model.dart` | 114 | Firestore-backed user data model with `fromFirestore()` / `toFirestore()` / `copyWith()` |
| `services/auth_service.dart` | 387 | Firebase Auth API wrapper (register, login, OTP, Google, verification) |
| `services/auth_provider.dart` | 553 | ChangeNotifier state manager — caches auth state, handles routing, awards verification scores |
| `screens/splash_screen.dart` | 289 | Animated splash with shimmer loading bar; auto-navigates based on auth state |
| `screens/login_screen.dart` | 441 | Main auth entry: Email Login, Phone Login, Google Sign-In, Sign Up options |
| `screens/email_login_screen.dart` | ~250 | Email + password sign-in form with password reset link |
| `screens/email_register_screen.dart` | ~280 | Email + password registration with field validation |
| `screens/email_verification_screen.dart` | ~200 | Email verification status check with re-send option |
| `screens/phone_login_screen.dart` | 407 | Phone number input → OTP entry → auto-verify callback |
| `screens/phone_register_screen.dart` | ~400 | Phone number registration with OTP flow |
| `screens/profile_setup_screen.dart` | 456 | First-time user onboarding: display name, avatar (camera/gallery + crop), upload to Firebase Storage |

---

## Architecture

```
┌───────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Screens     │────→│   AuthProvider   │────→│   AuthService   │
│ (UI + Input)  │     │ (ChangeNotifier) │     │ (Firebase Auth) │
└───────────────┘     └──────┬───────────┘     └────────┬────────┘
                             │                          │
                     notifyListeners()          Firebase Auth SDK
                             │                  Cloud Firestore
                     ┌───────▼───────┐          Firebase Storage
                     │   main.dart   │
                     │  Consumer<>   │
                     │  (Route Gate) │
                     └───────────────┘
```

---

## Auth Methods

### 1. Email/Password

| Step | Method | Details |
|------|--------|---------|
| Register | `AuthService.registerWithEmail()` | Creates Firebase Auth user → creates Firestore profile document → sends verification email |
| Login | `AuthService.signInWithEmail()` | Authenticates → checks/creates Firestore profile → updates `lastActiveAt` |
| Verify Email | `AuthService.sendEmailVerification()` | Sends verification link; `checkEmailVerified()` reloads user and checks `emailVerified` |
| Password Reset | `AuthService.sendPasswordResetEmail()` | Sends Firebase password reset email |

### 2. Phone/OTP

| Step | Method | Details |
|------|--------|---------|
| Send OTP | `AuthService.sendOTP()` | Calls `verifyPhoneNumber()` with callbacks: `onCodeSent`, `onError`, `onAutoVerify` |
| Verify OTP | `AuthService.verifyOTP()` | Creates `PhoneAuthCredential` → `signInWithCredential()` → creates profile if new |
| Auto-verify | `AuthService.signInWithPhoneCredential()` | For devices with auto-SMS reading; same flow as manual verify |

### 3. Google Sign-In

| Step | Method | Details |
|------|--------|---------|
| Sign In | `AuthService.signInWithGoogle()` | `GoogleSignIn().signIn()` → gets `idToken` + `accessToken` → `GoogleAuthProvider.credential()` → `signInWithCredential()` |

---

## Key Behaviors

### Reactive Auth State (`AuthProvider`)
- Listens to `FirebaseAuth.authStateChanges()`
- Protects against transient `null` during token refresh (500ms debounce)
- Caches login state via `SharedPreferences` to avoid false logouts
- Routes user to:
  - `ProfileSetupScreen` if `isProfileComplete == false`
  - `MainScreen` if profile is complete
  - `LoginScreen` if no auth session

### Credibility Score on Verification
- `_awardVerificationScore()` checks `verifications` map in Firestore to prevent duplicate scoring
- Email verified → **+20 points** (`CredibilityEvent.verifyEmail`)
- Phone verified → **+30 points** (`CredibilityEvent.verifyPhone`)
- Score awarded only once per verification type (idempotent)

### User Document Creation (`_createUserDocument`)
When a new user signs in for the first time, a `profiles/{userId}` document is created with:
- `displayName`, `email`, `phone`, `photoUrl`
- `score: 100` (default credibility)
- `totalRequests: 0`, `totalJoined: 0`, `completedRequests: 0`, `cancelledRequests: 0`
- `ratingCount: 0`, `rating: 0.0`
- `verifications: { email: bool, phone: bool, identity: false }`
- `badges: []`
- `createdAt`, `lastActiveAt`

### Error Handling
- `_handleAuthException()` maps Firebase error codes to user-friendly messages:
  - `email-already-in-use` → "An account already exists with this email"
  - `wrong-password` → "Incorrect password"
  - `user-not-found` → "No account found with this email"
  - `too-many-requests` → "Too many attempts. Please try again later"

---

## UserModel Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `userId` | `String` | — | Firebase Auth UID |
| `email` | `String?` | null | Email address |
| `phoneNumber` | `String?` | null | Phone number |
| `displayName` | `String` | required | Display name |
| `photoURL` | `String?` | null | Avatar URL (Firebase Storage) |
| `location` | `GeoPoint?` | null | User location |
| `address` | `String?` | null | Address string |
| `trustScore` | `double` | 0.0 | Legacy trust score |
| `totalCompletedSplits` | `int` | 0 | Legacy completed count |
| `verificationStatus` | `String` | "unverified" | "verified" or "unverified" |
| `createdAt` | `DateTime` | required | Account creation time |
| `lastActive` | `DateTime` | required | Last activity timestamp |

---

## Screen Flows

```
SplashScreen
    │
    ├─ auth == null ──→ LoginScreen
    │                      ├─ "Sign In with Email" ──→ EmailLoginScreen
    │                      │                             └─ success ──→ ProfileSetupScreen / MainScreen
    │                      ├─ "Sign In with Phone" ──→ PhoneLoginScreen
    │                      │                             └─ OTP verified ──→ ProfileSetupScreen / MainScreen
    │                      ├─ "Sign In with Google" ──→ GoogleSignIn popup
    │                      │                             └─ success ──→ ProfileSetupScreen / MainScreen
    │                      └─ "Sign Up" ──→ BottomSheet
    │                             ├─ Email ──→ EmailRegisterScreen ──→ EmailVerificationScreen
    │                             └─ Phone ──→ PhoneRegisterScreen
    │
    └─ auth != null
           ├─ profile incomplete ──→ ProfileSetupScreen
           └─ profile complete ──→ MainScreen
```
