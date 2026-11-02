import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../profile/models/user_profile_model.dart';

/// Authentication service handling Firebase Auth operations
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection reference - using profiles as unified user data store
  CollectionReference get _profilesCollection =>
      _firestore.collection('profiles');

  /// Get current Firebase user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Check if user is logged in
  bool get isLoggedIn => currentUser != null;

  // ============ EMAIL AUTHENTICATION ============

  /// Register with email and password
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user document in Firestore
      if (credential.user != null) {
        await _createUserDocument(credential.user!);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update last active
      if (credential.user != null) {
        await _updateLastActive(credential.user!.uid);
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Send email verification to current user
  /// Returns null on success, or error message on failure
  Future<String?> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      debugPrint(
        '[EmailVerification] currentUser: ${user?.uid}, email: ${user?.email}, emailVerified: ${user?.emailVerified}',
      );

      if (user == null) {
        debugPrint('[EmailVerification] ERROR: No user signed in');
        return 'No user signed in';
      }

      if (user.emailVerified) {
        debugPrint('[EmailVerification] Email already verified');
        return null; // already verified, not an error
      }

      debugPrint(
        '[EmailVerification] Sending verification email to ${user.email}...',
      );
      await user.sendEmailVerification();
      debugPrint('[EmailVerification] Verification email sent successfully');
      return null; // success
    } on FirebaseAuthException catch (e) {
      debugPrint(
        '[EmailVerification] FirebaseAuthException: ${e.code} - ${e.message}',
      );
      return _handleAuthException(e);
    } catch (e) {
      debugPrint('[EmailVerification] Error: $e');
      return e.toString();
    }
  }

  /// Check if current user's email is verified
  Future<bool> checkEmailVerified() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload();
        return _auth.currentUser?.emailVerified ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Reload current user to get latest state
  Future<void> reloadUser() async {
    try {
      await _auth.currentUser?.reload();
    } catch (e) {
      // Ignore reload errors
    }
  }

  // ============ PHONE AUTHENTICATION ============

  /// Send OTP to phone number
  Future<void> sendOTP({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    required Function(PhoneAuthCredential credential) onAutoVerify,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification on Android
          onAutoVerify(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(_handleAuthException(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Timeout handling
        },
      );
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Verify OTP and sign in
  Future<UserCredential> verifyOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Create or update user document
      if (userCredential.user != null) {
        final exists = await _userExists(userCredential.user!.uid);
        if (!exists) {
          await _createUserDocument(userCredential.user!);
        } else {
          await _updateLastActive(userCredential.user!.uid);
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with phone credential (for auto-verification)
  Future<UserCredential> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    try {
      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        final exists = await _userExists(userCredential.user!.uid);
        if (!exists) {
          await _createUserDocument(userCredential.user!);
        } else {
          await _updateLastActive(userCredential.user!.uid);
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ============ GOOGLE SIGN-IN ============

  /// Sign in with Google account (google_sign_in v7 API)
  Future<UserCredential> signInWithGoogle() async {
    try {
      // Initialize Google Sign-In (safe to call multiple times before authenticate)
      await GoogleSignIn.instance.initialize();

      // Trigger the interactive sign-in flow
      final GoogleSignInAccount account = await GoogleSignIn.instance
          .authenticate();

      // Get the idToken from authentication
      final idToken = account.authentication.idToken;

      // Request an access token via authorization client
      final authzClient = account.authorizationClient;
      final clientAuthz = await authzClient.authorizeScopes(<String>['email']);
      final accessToken = clientAuthz.accessToken;

      // Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        final exists = await _userExists(userCredential.user!.uid);
        if (!exists) {
          await _createUserDocument(userCredential.user!);
        } else {
          await _updateLastActive(userCredential.user!.uid);
        }
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ============ USER MANAGEMENT ============

  /// Sign out
  Future<void> signOut() async {
    // Sign out of Google if signed in
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  /// Get user profile from Firestore (profiles collection)
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final doc = await _profilesCollection.doc(userId).get();
      if (doc.exists) {
        return UserProfile.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update user profile
  Future<void> updateUserProfile({
    required String userId,
    String? displayName,
    String? photoURL,
    GeoPoint? location,
    String? address,
  }) async {
    final updates = <String, dynamic>{'lastActive': Timestamp.now()};

    if (displayName != null) updates['displayName'] = displayName;
    if (photoURL != null) updates['photoUrl'] = photoURL;
    if (location != null) updates['location'] = location;
    if (address != null) updates['address'] = address;

    await _profilesCollection.doc(userId).update(updates);
  }

  /// Check if user document exists in profiles
  Future<bool> _userExists(String userId) async {
    final doc = await _profilesCollection.doc(userId).get();
    return doc.exists;
  }

  /// Create user profile document in Firestore
  Future<void> _createUserDocument(User user) async {
    final batch = FirebaseFirestore.instance.batch();
    final profileRef = _profilesCollection.doc(user.uid);
    final activitiesRef = profileRef.collection('score_activities');
    
    // Calculate initial score based on verified methods
    final hasPhone = user.phoneNumber != null;
    final hasVerifiedEmail = user.emailVerified;
    int initialScore = 100; // Base score
    
    // Log activities for initial verifications
    if (hasPhone) {
      initialScore += 30; // Phone verification bonus
      batch.set(activitiesRef.doc(), {
        'event': 'verify_phone',
        'points': 30,
        'createdAt': Timestamp.now(),
        'description': 'Verified phone number during registration',
      });
    }
    
    if (hasVerifiedEmail) {
      initialScore += 20; // Email verification bonus
      batch.set(activitiesRef.doc(), {
        'event': 'verify_email',
        'points': 20,
        'createdAt': Timestamp.now(),
        'description': 'Verified email address',
      });
    }

    batch.set(profileRef, {
      'displayName': user.displayName ?? 'User',
      'email': user.email,
      'phone': user.phoneNumber,
      'photoUrl': user.photoURL,
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
    
    await batch.commit();
  }

  /// Update last active timestamp
  Future<void> _updateLastActive(String userId) async {
    await _profilesCollection.doc(userId).update({
      'lastActiveAt': Timestamp.now(),
    });
  }

  /// Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak (min 6 characters)';
      case 'user-not-found':
        return 'No account found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-verification-code':
        return 'Invalid OTP code';
      case 'invalid-phone-number':
        return 'Invalid phone number format';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'user-disabled':
        return 'This account has been disabled';
      case 'internal-error':
        return 'Authentication service error. Please check your internet connection and try again.';
      default:
        return e.message ?? 'Authentication error occurred';
    }
  }
}
