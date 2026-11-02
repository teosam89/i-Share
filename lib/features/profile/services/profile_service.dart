import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_profile_model.dart';
import '../../../core/constants/app_constants.dart';

/// ProfileService - Handles user profile and credibility operations
class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _profilesRef => _firestore.collection(AppConstants.profilesCollection);

  CollectionReference _ratingsRef(String userId) =>
      _profilesRef.doc(userId).collection(AppConstants.ratingsCollection);

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Get or create user profile
  Future<UserProfile> getOrCreateProfile({String? userId}) async {
    final uid = userId ?? currentUserId;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final doc = await _profilesRef.doc(uid).get();

      if (doc.exists) {
        return UserProfile.fromFirestore(doc);
      }

      // Create new profile from Firebase Auth data
      final user = _auth.currentUser;
      final profile = UserProfile(
        id: uid,
        displayName: user?.displayName ?? 'User',
        email: user?.email,
        photoUrl: user?.photoURL,
        createdAt: DateTime.now(),
      );

      await _profilesRef.doc(uid).set(profile.toFirestore());
      debugPrint('[ProfileService] Created profile for: $uid');

      return profile;
    } catch (e) {
      debugPrint('[ProfileService] Error getting profile: $e');
      rethrow;
    }
  }

  /// Get user profile by ID
  Future<UserProfile?> getProfile(String userId) async {
    try {
      final doc = await _profilesRef.doc(userId).get();
      if (doc.exists) {
        return UserProfile.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('[ProfileService] Error getting profile: $e');
      return null;
    }
  }

  /// Update editable profile fields from a UserProfile object.
  ///
  /// Only writes displayName, photoUrl, and any non-null optional fields.
  /// Never writes credibility stats (rating, score, completedRequests, etc.)
  /// — those are managed exclusively by Cloud Functions.
  ///
  /// photoUrl is always written (null = intentional avatar removal).
  /// Other nullable fields are skipped when null to avoid overwriting
  /// existing Firestore data with a partial UserProfile object.
  Future<void> updateProfileFull(UserProfile profile) async {
    try {
      final updates = <String, dynamic>{
        'displayName': profile.displayName,
        'photoUrl': profile.photoUrl,
        'lastActiveAt': FieldValue.serverTimestamp(),
      };
      if (profile.email != null) updates['email'] = profile.email;
      if (profile.phone != null) updates['phone'] = profile.phone;
      if (profile.gender != null) updates['gender'] = profile.gender;
      if (profile.bannerColor != null) updates['bannerColor'] = profile.bannerColor;
      if (profile.bio != null) {
        updates['bio'] = profile.bio!.isEmpty ? FieldValue.delete() : profile.bio;
      }
      await _profilesRef.doc(profile.id).update(updates);
      debugPrint('[ProfileService] Updated profile: ${profile.id}');
    } catch (e) {
      debugPrint('[ProfileService] Error updating profile: $e');
      rethrow;
    }
  }

  /// Update specific profile fields
  Future<void> updateProfile({
    required String userId,
    String? displayName,
    String? email,
    String? phone,
    String? gender,
    String? bio,
    String? photoUrl,
    int? bannerColor,
  }) async {
    try {
      final updates = <String, dynamic>{
        'lastActiveAt': FieldValue.serverTimestamp(),
      };
      if (displayName != null) updates['displayName'] = displayName;
      if (email != null) updates['email'] = email;
      if (phone != null) updates['phone'] = phone;
      if (gender != null) updates['gender'] = gender;
      if (bio != null) {
        updates['bio'] = bio.isEmpty ? FieldValue.delete() : bio;
      }
      if (photoUrl != null) updates['photoUrl'] = photoUrl;
      if (bannerColor != null) updates['bannerColor'] = bannerColor;

      await _profilesRef.doc(userId).update(updates);
      debugPrint('[ProfileService] Updated profile fields for: $userId');
    } catch (e) {
      debugPrint('[ProfileService] Error updating profile: $e');
      rethrow;
    }
  }

  /// Update last active timestamp
  Future<void> updateLastActive() async {
    if (currentUserId == null) return;

    try {
      await _profilesRef.doc(currentUserId).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ProfileService] Error updating last active: $e');
    }
  }

  /// Get ratings received by a user (capped at 50 — older ratings are
  /// visible on the All Reviews screen which paginates separately).
  Stream<List<UserRating>> getUserRatings(String userId) {
    return _ratingsRef(userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => UserRating.fromFirestore(doc))
              .toList(),
        );
  }

  /// Get display info (name + photoUrl) for any user.
  /// Never throws — returns safe defaults on error.
  Future<({String name, String? photoUrl})> getDisplayInfo(String userId) async {
    try {
      final doc = await _profilesRef.doc(userId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        return (
          name: data?['displayName'] as String? ?? 'User',
          photoUrl: data?['photoUrl'] as String?,
        );
      }
    } catch (e) {
      debugPrint('[ProfileService] Error getting display info for $userId: $e');
    }
    return (name: 'User', photoUrl: null);
  }

}
