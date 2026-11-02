import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../profile/models/user_profile_model.dart';
import 'auth_service.dart';
import '../../profile/services/credibility_service.dart';

/// Authentication state provider for state management
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  // State variables
  User? _firebaseUser;
  UserProfile? _userProfile;
  bool _isLoading = false;
  bool _initialized = false;
  String? _errorMessage;
  bool _wasLoggedIn = false; // Track if user was previously logged in
  bool _isReturningUser =
      false; // True if user was logged in before app restart

  // Phone verification state
  String? _verificationId;
  bool _codeSent = false;
  bool _autoVerifying = false;

  // Getters
  User? get firebaseUser => _firebaseUser;
  UserProfile? get userProfile => _userProfile;
  /// Convenience getter — most callers only need the UID
  String? get userId => _firebaseUser?.uid;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isLoggedIn => _firebaseUser != null;
  bool get isInitialized => _initialized;
  bool get codeSent => _codeSent;
  bool get autoVerifying => _autoVerifying;
  String? get verificationId => _verificationId;

  /// True if user was logged in before this app session (skip splash animation)
  bool get isReturningUser => _isReturningUser;

  /// Check if profile setup is needed
  bool get needsProfileSetup {
    if (_userProfile == null) return true;
    return _userProfile!.displayName.isEmpty || _userProfile!.displayName == 'User';
  }

  AuthProvider() {
    _initializeAuth();
  }

  /// Initialize auth with cached state awareness
  Future<void> _initializeAuth() async {
    // Start splash timer — ensures animation plays for at least 2.5 seconds
    final splashTimer = Future.delayed(const Duration(milliseconds: 2500));

    // Check if user was previously logged in
    final prefs = await SharedPreferences.getInstance();
    _wasLoggedIn = prefs.getBool('was_logged_in') ?? false;
    _isReturningUser = _wasLoggedIn;

    // Wait for minimum splash time before allowing auth state to propagate
    await splashTimer;

    // Listen to auth state changes
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  /// Handle auth state changes — with protection against transient null
  Future<void> _onAuthStateChanged(User? user) async {
    if (user != null) {
      _firebaseUser = user;
      _wasLoggedIn = true;

      // Fetch user data from Firestore
      _userProfile = await _authService.getUserProfile(user.uid);

      // Cache login state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('was_logged_in', true);
    } else if (_wasLoggedIn) {
      // Was logged in but got null — could be transient token refresh
      // Wait briefly and re-check before treating as real logout
      debugPrint(
        '[AuthProvider] Got null user while was logged in, waiting to confirm...',
      );
      await Future.delayed(const Duration(seconds: 2));

      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        // Token refresh resolved — user is still logged in
        debugPrint('[AuthProvider] User recovered after token refresh');
        _firebaseUser = currentUser;
        _userProfile = await _authService.getUserProfile(currentUser.uid);
      } else {
        // Real logout
        debugPrint('[AuthProvider] Confirmed real logout');
        _firebaseUser = null;
        _userProfile = null;
        _wasLoggedIn = false;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('was_logged_in', false);
      }
    } else {
      // First launch, not logged in
      _firebaseUser = null;
      _userProfile = null;
    }

    _initialized = true;
    notifyListeners();
  }

  /// Set loading state
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Set error message
  void _setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Clear error (only notifies if actually clearing something)
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  // ============ EMAIL AUTHENTICATION ============

  /// Register with email
  Future<bool> registerWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      await _authService.registerWithEmail(email: email, password: password);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  /// Sign in with email
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      await _authService.signInWithEmail(email: email, password: password);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _setError(_getFirebaseAuthErrorMessage(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      // Parse Firebase error from string if not caught as FirebaseAuthException
      final errorMessage = _parseFirebaseError(e.toString());
      _setError(errorMessage);
      _setLoading(false);
      return false;
    }
  }

  /// Convert Firebase Auth error codes to user-friendly messages
  String _getFirebaseAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email. Please register first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Invalid email format. Please check your email.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'email-already-in-use':
        return 'This email is already registered. Please login instead.';
      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';
      case 'invalid-credential':
        return 'Invalid email or password. Please check and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return 'Login failed. Please check your email and password.';
    }
  }

  /// Parse Firebase error from string
  String _parseFirebaseError(String error) {
    // Handle various Firebase error formats
    if (error.contains('user-not-found')) {
      return 'No account found with this email. Please register first.';
    } else if (error.contains('wrong-password')) {
      return 'Incorrect password. Please try again.';
    } else if (error.contains('invalid-email')) {
      return 'Invalid email format. Please check your email.';
    } else if (error.contains('invalid-credential') ||
        error.contains('INVALID_LOGIN_CREDENTIALS')) {
      return 'Invalid email or password. Please check and try again.';
    } else if (error.contains('too-many-requests')) {
      return 'Too many failed attempts. Please try again later.';
    } else if (error.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (error.contains('email-already-in-use')) {
      return 'This email is already registered. Please login instead.';
    }
    return 'Login failed. Please check your email and password.';
  }

  /// Send password reset email
  Future<bool> sendPasswordReset(String email) async {
    _setLoading(true);
    _setError(null);

    try {
      await _authService.sendPasswordResetEmail(email);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  /// Send email verification to current user
  /// Returns null on success, or error message on failure
  Future<String?> sendEmailVerification() async {
    try {
      return await _authService.sendEmailVerification();
    } catch (e) {
      return e.toString();
    }
  }

  /// Check if current user's email is verified
  Future<bool> checkEmailVerified() async {
    try {
      final isVerified = await _authService.checkEmailVerified();
      if (isVerified && _firebaseUser != null) {
        // Award credibility score for email verification (only once)
        await _awardVerificationScore(
          _firebaseUser!.uid,
          'email',
          CredibilityEvent.verifyEmail,
        );
        // Refresh user data
        await refreshUserData();
      }
      return isVerified;
    } catch (e) {
      return false;
    }
  }

  // ============ PHONE AUTHENTICATION ============

  /// Send OTP to phone
  Future<void> sendOTP(String phoneNumber) async {
    _setLoading(true);
    _setError(null);
    _codeSent = false;

    await _authService.sendOTP(
      phoneNumber: phoneNumber,
      onCodeSent: (String verificationId) {
        _verificationId = verificationId;
        _codeSent = true;
        _setLoading(false);
      },
      onError: (String error) {
        _setError(error);
        _setLoading(false);
      },
      onAutoVerify: (PhoneAuthCredential credential) async {
        // Auto verification on Android — set flag to show loading UI
        _autoVerifying = true;
        notifyListeners();
        await _signInWithPhoneCredential(credential);
        _autoVerifying = false;
      },
    );
  }

  /// Verify OTP code
  Future<bool> verifyOTP(String smsCode) async {
    if (_verificationId == null) {
      _setError('Verification ID not found. Please resend OTP.');
      return false;
    }

    _setLoading(true);
    _setError(null);

    try {
      await _authService.verifyOTP(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      _codeSent = false;
      _verificationId = null;

      // Award credibility score for phone verification (only once)
      final user = _authService.currentUser;
      if (user != null) {
        await _awardVerificationScore(
          user.uid,
          'phone',
          CredibilityEvent.verifyPhone,
        );
      }

      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  /// Sign in with phone credential (auto-verify)
  Future<void> _signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    try {
      await _authService.signInWithPhoneCredential(credential);
      _codeSent = false;
      _verificationId = null;

      // Award credibility score for phone verification (only once)
      final user = _authService.currentUser;
      if (user != null) {
        await _awardVerificationScore(
          user.uid,
          'phone',
          CredibilityEvent.verifyPhone,
        );
      }

      _setLoading(false);
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
    }
  }

  // ============ GOOGLE SIGN-IN ============

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _setError(null);

    try {
      await _authService.signInWithGoogle();

      // Google accounts have verified emails, award credibility
      final user = _authService.currentUser;
      if (user != null) {
        await _awardVerificationScore(
          user.uid,
          'email',
          CredibilityEvent.verifyEmail,
        );
      }

      _setLoading(false);
      return true;
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('cancelled')) {
        // User cancelled — not an error
        _setLoading(false);
        return false;
      }
      _setError(_parseFirebaseError(msg));
      _setLoading(false);
      return false;
    }
  }

  /// Reset phone verification state (to change phone number)
  void resetPhoneVerification() {
    _codeSent = false;
    _verificationId = null;
    _errorMessage = null;
    notifyListeners();
  }

  // ============ USER MANAGEMENT ============

  /// Sign out
  Future<void> signOut() async {
    _setLoading(true);
    await _authService.signOut();
    _firebaseUser = null;
    _userProfile = null;
    _codeSent = false;
    _verificationId = null;
    _setLoading(false);
  }

  /// Update user profile
  Future<bool> updateProfile({
    required String displayName,
    String? photoURL,
  }) async {
    if (_firebaseUser == null) return false;

    _setLoading(true);
    _setError(null);

    try {
      // Check if profile document exists, create if not
      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(_firebaseUser!.uid)
          .get();

      if (!profileDoc.exists) {
        // Calculate initial score based on verified methods
        final hasPhone = _firebaseUser!.phoneNumber != null;
        final hasVerifiedEmail = _firebaseUser!.emailVerified;
        int initialScore = 100; // Base score
        if (hasPhone) initialScore += 30; // Phone verified = +30
        if (hasVerifiedEmail) initialScore += 20; // Email verified = +20

        // Create new profile document with computed score (atomic write)
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(_firebaseUser!.uid)
            .set({
              'displayName': displayName,
              'email': _firebaseUser!.email,
              'phone': _firebaseUser!.phoneNumber,
              'photoUrl': photoURL,
              'createdAt': Timestamp.now(),
              'lastActiveAt': Timestamp.now(),
              // Credibility — score includes verification bonuses
              'score': initialScore,
              'totalRequests': 0,
              'totalJoined': 0,
              'completedRequests': 0,
              'cancelledRequests': 0,
              'rating': 0.0,
              'ratingCount': 0,
              'verifications': {
                'email': hasVerifiedEmail,
                'phone': hasPhone,
                'identity': false,
              },
              'badges': [],
            });

        // Log score activities for awarded bonuses (non-blocking)
        try {
          final activitiesRef = FirebaseFirestore.instance
              .collection('profiles')
              .doc(_firebaseUser!.uid)
              .collection('score_activities');

          if (hasPhone) {
            await activitiesRef.add({
              'event': CredibilityEvent.verifyPhone.name,
              'points': 30,
              'description': 'Verified phone',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          if (hasVerifiedEmail) {
            await activitiesRef.add({
              'event': CredibilityEvent.verifyEmail.name,
              'points': 20,
              'description': 'Verified email',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (e) {
          // Activity logging is non-critical — profile and score are already saved
          debugPrint('[AuthProvider] Error logging score activities: $e');
        }
      } else {
        // Update existing profile document
        await FirebaseFirestore.instance
            .collection('profiles')
            .doc(_firebaseUser!.uid)
            .update({
              'displayName': displayName,
              if (photoURL != null) 'photoUrl': photoURL,
              'lastActiveAt': Timestamp.now(),
            });
      }

      // Refresh user data from profiles
      _userProfile = await _authService.getUserProfile(_firebaseUser!.uid);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      return false;
    }
  }

  /// Refresh user data
  Future<void> refreshUserData() async {
    if (_firebaseUser != null) {
      _userProfile = await _authService.getUserProfile(_firebaseUser!.uid);
      notifyListeners();
    }
  }

  /// Award credibility score for verification (email/phone), only once.
  /// Uses a Firestore transaction to prevent double-awarding when auto-verify
  /// and manual OTP complete concurrently (e.g., Android SMS auto-fill race).
  Future<void> _awardVerificationScore(
    String userId,
    String verificationType, // 'email' or 'phone'
    CredibilityEvent event,
  ) async {
    final points = CredibilityService.eventPoints[event] ?? 0;
    if (points == 0) return;

    try {
      final profileRef =
          FirebaseFirestore.instance.collection('profiles').doc(userId);

      // Atomic check-then-write: if already verified, the transaction is a no-op
      bool awarded = false;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final profileDoc = await transaction.get(profileRef);
        if (!profileDoc.exists) return;

        final data = profileDoc.data() as Map<String, dynamic>;
        final verifications =
            data['verifications'] as Map<String, dynamic>? ?? {};

        if (verifications[verificationType] == true) return; // Already awarded

        transaction.update(profileRef, {
          'score': FieldValue.increment(points),
          'verifications.$verificationType': true,
        });
        awarded = true;
      });

      if (!awarded) {
        debugPrint(
          '[AuthProvider] $verificationType already verified, skipping award',
        );
        return;
      }

      // Log activity outside transaction (non-critical, best-effort)
      try {
        await profileRef.collection('score_activities').add({
          'event': event.name,
          'points': points,
          'description': CredibilityService.getEventDescription(event),
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[AuthProvider] Error logging score activity: $e');
      }

      debugPrint('[AuthProvider] Awarded ${event.name} (+$points) to $userId');
    } catch (e) {
      debugPrint('[AuthProvider] Error awarding verification score: $e');
    }
  }
}
