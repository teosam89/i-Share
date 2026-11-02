/// JoinRequestService - Handles Firestore operations for join request approval flow
library;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/join_request_model.dart';
import '../models/co_request_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/join_status.dart';
import '../../profile/services/profile_service.dart';

class JoinRequestService {
  static final JoinRequestService _instance = JoinRequestService._internal();
  factory JoinRequestService() => _instance;
  JoinRequestService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Note: ChatService and ProfileService updates are now handled by Cloud Functions

  // Collection references
  CollectionReference get _requestsRef => _firestore.collection(AppConstants.coRequestsCollection);

  CollectionReference _joinRequestsRef(String requestId) =>
      _requestsRef.doc(requestId).collection(AppConstants.joinRequestsCollection);

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;
  String get currentUserName => _auth.currentUser?.displayName ?? 'User';
  String? get currentUserPhotoUrl => _auth.currentUser?.photoURL;

  // ============ CREATE ============

  /// Create a new join request (user wants to join a co-request)
  Future<JoinRequest> createJoinRequest({
    required CoRequest coRequest,
    String? message,
  }) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    if (currentUserId == coRequest.initiatorId) {
      throw Exception('Cannot request to join your own request');
    }

    // Check if already requested
    final existing = await getMyJoinRequest(coRequest.id);
    if (existing != null) {
      throw Exception('You have already requested to join this request');
    }

    // Check if already a participant
    if (coRequest.participants.contains(currentUserId)) {
      throw Exception('You are already a participant');
    }

    try {
      // Fetch user profile for display name and photo
      final displayInfo = await ProfileService().getDisplayInfo(currentUserId!);
      final requesterName = displayInfo.name;
      final requesterPhotoUrl = displayInfo.photoUrl;

      final joinRequest = JoinRequest(
        id: '',
        requestId: coRequest.id,
        requestProductName: coRequest.productName,
        requesterId: currentUserId!,
        requesterName: requesterName,
        requesterPhotoUrl: requesterPhotoUrl,
        hostId: coRequest.initiatorId,
        hostName: coRequest.initiatorName,
        status: JoinStatus.pending,
        message: message,
        createdAt: DateTime.now(),
      );

      final docRef = await _joinRequestsRef(
        coRequest.id,
      ).add(joinRequest.toFirestore());

      debugPrint('[JoinRequestService] Created join request: ${docRef.id}');

      return JoinRequest(
        id: docRef.id,
        requestId: joinRequest.requestId,
        requestProductName: joinRequest.requestProductName,
        requesterId: joinRequest.requesterId,
        requesterName: joinRequest.requesterName,
        requesterPhotoUrl: joinRequest.requesterPhotoUrl,
        hostId: joinRequest.hostId,
        hostName: joinRequest.hostName,
        status: joinRequest.status,
        message: joinRequest.message,
        createdAt: joinRequest.createdAt,
      );
    } catch (e) {
      debugPrint('[JoinRequestService] Error creating join request: $e');
      rethrow;
    }
  }

  // ============ READ ============

  /// Get pending join requests for a co-request (Host view)
  Stream<List<JoinRequest>> getPendingJoinRequests(String requestId) {
    return _joinRequestsRef(requestId)
        .where('status', isEqualTo: JoinStatus.pending)
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => JoinRequest.fromFirestore(doc))
              .toList();
          // Sort on client side to avoid composite index
          requests.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return requests;
        });
  }

  /// Get all pending requests across all user's co-requests (for badge count)
  Stream<int> getPendingRequestCount() {
    if (currentUserId == null) return Stream.value(0);

    // Query all join requests where current user is host
    return _firestore
        .collectionGroup('join_requests')
        .where('hostId', isEqualTo: currentUserId)
        .where('status', isEqualTo: JoinStatus.pending)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Check if current user has an active (pending/accepted) request for a co-request
  /// P1 #7: Rejected requests are ignored, allowing re-application
  Future<JoinRequest?> getMyJoinRequest(String requestId) async {
    if (currentUserId == null) return null;

    try {
      // Only check for pending or accepted status (not rejected)
      final query = await _joinRequestsRef(requestId)
          .where('requesterId', isEqualTo: currentUserId)
          .where(
            'status',
            whereIn: [JoinStatus.pending, JoinStatus.accepted],
          )
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;
      return JoinRequest.fromFirestore(query.docs.first);
    } catch (e) {
      debugPrint('[JoinRequestService] Error getting my join request: $e');
      return null;
    }
  }

  /// Stream for current user's join request status on a specific co-request.
  /// Filters to pending/accepted only — consistent with getMyJoinRequest.
  /// Rejected requests are excluded so a re-applicant doesn't see stale state.
  Stream<JoinRequest?> streamMyJoinRequest(String requestId) {
    if (currentUserId == null) return Stream.value(null);

    return _joinRequestsRef(requestId)
        .where('requesterId', isEqualTo: currentUserId)
        .where('status', whereIn: [JoinStatus.pending, JoinStatus.accepted])
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return JoinRequest.fromFirestore(snapshot.docs.first);
        });
  }

  // ============ UPDATE ============

  /// Accept a join request (Host action) - Uses secure Cloud Function
  Future<void> acceptJoinRequest({
    required String requestId,
    required JoinRequest joinRequest,
  }) async {
    if (currentUserId != joinRequest.hostId) {
      throw Exception('Only the host can accept join requests');
    }

    try {
      // Call secure Cloud Function instead of direct Firestore update
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('acceptJoinRequestSecure');

      await callable.call({
        'requestId': requestId,
        'joinRequestId': joinRequest.id,
      });

      debugPrint(
        '[JoinRequestService] Accepted join request: ${joinRequest.id}',
      );
    } catch (e) {
      debugPrint('[JoinRequestService] Error accepting join request: $e');
      rethrow;
    }
  }

  /// Reject a join request (Host action)
  Future<void> rejectJoinRequest({
    required String requestId,
    required JoinRequest joinRequest,
  }) async {
    if (currentUserId != joinRequest.hostId) {
      throw Exception('Only the host can reject join requests');
    }

    try {
      await _joinRequestsRef(requestId).doc(joinRequest.id).update({
        'status': JoinStatus.rejected,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
        '[JoinRequestService] Rejected join request: ${joinRequest.id}',
      );
    } catch (e) {
      debugPrint('[JoinRequestService] Error rejecting join request: $e');
      rethrow;
    }
  }

  /// Cancel a join request (Requester action)
  Future<void> cancelJoinRequest({
    required String requestId,
    required String joinRequestId,
  }) async {
    try {
      await _joinRequestsRef(requestId).doc(joinRequestId).delete();
      debugPrint('[JoinRequestService] Cancelled join request: $joinRequestId');
    } catch (e) {
      debugPrint('[JoinRequestService] Error cancelling join request: $e');
      rethrow;
    }
  }
}
