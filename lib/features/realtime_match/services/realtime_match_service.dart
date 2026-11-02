import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/realtime_match_model.dart';
import '../../chat/services/chat_service.dart';
import '../../co_request/services/location_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/request_status.dart';
import '../../co_request/models/co_request_model.dart';

/// RealtimeMatchService - Handles real-time partner matching operations
class RealtimeMatchService {
  static final RealtimeMatchService _instance =
      RealtimeMatchService._internal();
  factory RealtimeMatchService() => _instance;
  RealtimeMatchService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ChatService _chatService = ChatService();
  final LocationService _locationService = LocationService();

  CollectionReference get _matchesRef =>
      _firestore.collection(AppConstants.realtimeMatchesCollection);
  CollectionReference get _profilesRef => _firestore.collection(AppConstants.profilesCollection);

  String? get currentUserId => _auth.currentUser?.uid;

  /// Fetch current user's display name from profiles collection
  Future<String> _getCurrentUserName() async {
    if (currentUserId == null) return 'User';
    try {
      final doc = await _profilesRef.doc(currentUserId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return data['displayName'] ?? _auth.currentUser?.displayName ?? 'User';
      }
      return _auth.currentUser?.displayName ?? 'User';
    } catch (e) {
      return _auth.currentUser?.displayName ?? 'User';
    }
  }

  /// Fetch current user's photo URL from profiles collection
  Future<String?> _getCurrentUserPhoto() async {
    if (currentUserId == null) return null;
    try {
      final doc = await _profilesRef.doc(currentUserId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return data['photoUrl'] ?? _auth.currentUser?.photoURL;
      }
      return _auth.currentUser?.photoURL;
    } catch (e) {
      return _auth.currentUser?.photoURL;
    }
  }

  /// Find matching room within radius for the same category and partner count.
  /// Returns a candidate WITHOUT auto-joining. Caller decides Accept/Skip.
  Future<RealtimeMatch?> findMatchingRoom({
    required String category,
    required String productIntent,
    required double latitude,
    required double longitude,
    required double radiusKm,
    required int maxPartners,
  }) async {
    // Guard against null currentUserId
    if (currentUserId == null) {
      debugPrint('[RealtimeMatchService] No authenticated user');
      return null;
    }

    try {
      // Use queryAliases so 'groceries' also matches old 'food' docs
      final categoryValues =
          RequestCategories.queryAliases[category] ?? [category];

      // Query for waiting rooms with matching category and maxPartners
      final snapshot = await _matchesRef
          .where('category', whereIn: categoryValues)
          .where('maxPartners', isEqualTo: maxPartners)
          .where('status', isEqualTo: RequestStatus.waiting)
          .get();

      for (final doc in snapshot.docs) {
        final match = RealtimeMatch.fromFirestore(doc);

        // Skip if expired
        if (match.isExpired) continue;

        // Skip if already a participant or owner
        if (match.isOwner(currentUserId!) ||
            match.isParticipant(currentUserId!)) {
          continue;
        }

        // Skip if room is full
        if (match.isFull) continue;

        // Skip if current user already skipped this room
        if (match.skippedBy.contains(currentUserId!)) continue;

        // Calculate distance
        final distance = _locationService.calculateDistance(
          latitude,
          longitude,
          match.latitude,
          match.longitude,
        );

        // Check if within both users' radius (use the smaller radius)
        final maxDistance =
            (radiusKm < match.radiusKm ? radiusKm : match.radiusKm) * 1000;

        if (distance <= maxDistance) {
          debugPrint('[RealtimeMatchService] Found matching room: ${match.id}');
          return match;
        }
      }

      debugPrint('[RealtimeMatchService] No matching room found');
      return null;
    } catch (e) {
      debugPrint('[RealtimeMatchService] Error finding match: $e');
      return null;
    }
  }

  /// Create a new matching room with the owner's product intent
  Future<RealtimeMatch?> createRoom({
    required String category,
    required String productIntent,
    required double latitude,
    required double longitude,
    required double radiusKm,
    required String locationName,
    required int maxPartners,
  }) async {
    if (currentUserId == null) return null;

    try {
      final docRef = _matchesRef.doc();

      // Fetch user info from profiles collection
      final ownerName = await _getCurrentUserName();
      final ownerPhoto = await _getCurrentUserPhoto();

      // Create chat room for this match
      final chatRoom = await _chatService.getOrCreateChatRoom(
        requestId: 'rtm_${docRef.id}',
        productName: 'Real-Time Match: $category',
        participantIds: [currentUserId!],
      );

      final now = DateTime.now();
      final match = RealtimeMatch(
        id: docRef.id,
        ownerId: currentUserId!,
        ownerName: ownerName,
        ownerPhotoUrl: ownerPhoto,
        category: category,
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
        locationName: locationName,
        participants: [currentUserId!],
        participantIntents: {currentUserId!: productIntent},
        maxPartners: maxPartners,
        status: RequestStatus.waiting,
        chatRoomId: chatRoom.id,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)), // 24h expiry
      );

      await docRef.set(match.toFirestore());

      // Send welcome message
      await _chatService.sendSystemMessage(
        chatRoomId: chatRoom.id,
        content:
            '🔄 Real-Time Match room created. Looking for $maxPartners partner(s)...',
      );

      debugPrint('[RealtimeMatchService] Created room: ${match.id}');
      return match;
    } catch (e) {
      debugPrint('[RealtimeMatchService] Error creating room: $e');
      return null;
    }
  }

  /// Join an existing matching room (uses Transaction to prevent race conditions)
  Future<bool> joinRoom(String matchId, {required String productIntent}) async {
    if (currentUserId == null) return false;

    try {
      // Use transaction to prevent race conditions
      final result = await _firestore.runTransaction<bool>((transaction) async {
        final docRef = _matchesRef.doc(matchId);
        final doc = await transaction.get(docRef);

        if (!doc.exists) return false;

        final match = RealtimeMatch.fromFirestore(doc);

        // Check if already a participant
        if (match.participants.contains(currentUserId!)) {
          return false; // Already joined
        }

        // Check if room is full
        if (match.isFull) {
          return false;
        }

        // Check if expired
        if (match.isExpired) {
          return false;
        }

        // Calculate new count
        final newCount = match.participantCount + 1;
        final isFull = newCount >= (match.maxPartners + 1);

        // Atomically update participants and their intents
        transaction.update(docRef, {
          'participants': FieldValue.arrayUnion([currentUserId!]),
          'participantIntents.${currentUserId!}': productIntent,
          'status': isFull ? RequestStatus.matched : RequestStatus.waiting,
        });

        return true;
      });

      if (!result) {
        debugPrint(
          '[RealtimeMatchService] Could not join room (full/expired/already joined)',
        );
        return false;
      }

      // Post-transaction: add to chat room (outside transaction for simpler logic)
      final doc = await _matchesRef.doc(matchId).get();
      final match = RealtimeMatch.fromFirestore(doc);

      if (match.chatRoomId != null) {
        await _chatService.addParticipant(match.chatRoomId!, currentUserId!);

        // Send join notification
        final userName = await _getCurrentUserName();
        await _chatService.sendSystemMessage(
          chatRoomId: match.chatRoomId!,
          content: '👋 $userName joined the match!',
        );
      }

      debugPrint('[RealtimeMatchService] Joined room: $matchId');
      return true;
    } catch (e) {
      debugPrint('[RealtimeMatchService] Error joining room: $e');
      return false;
    }
  }

  /// Skip a matching room — adds current user to skippedBy so it won't appear again
  Future<bool> skipRoom(String matchId) async {
    if (currentUserId == null) return false;

    try {
      await _matchesRef.doc(matchId).update({
        'skippedBy': FieldValue.arrayUnion([currentUserId!]),
      });
      debugPrint('[RealtimeMatchService] Skipped room: $matchId');
      return true;
    } catch (e) {
      debugPrint('[RealtimeMatchService] Error skipping room: $e');
      return false;
    }
  }

  /// Leave a matching room - Uses secure Cloud Function
  /// P1 #10: Cloud Function handles status correctly without invalid transitions
  Future<bool> leaveRoom(String matchId) async {
    if (currentUserId == null) return false;

    try {
      // Call secure Cloud Function instead of direct Firestore update
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('leaveRealtimeMatchSecure');

      await callable.call({'matchId': matchId});

      debugPrint('[RealtimeMatchService] Left room: $matchId');
      return true;
    } catch (e) {
      debugPrint('[RealtimeMatchService] Error leaving room: $e');
      return false;
    }
  }

  /// Close a match when converting to Co-Buy Request.
  /// This sets status to 'closed' so all participants know the match has ended.
  /// Returns true if the match was successfully closed.
  /// The status write is retried once on failure; the system message is best-effort.
  Future<bool> closeMatchForConversion(
    String matchId,
    String newCoBuyId,
  ) async {
    if (currentUserId == null) return false;

    try {
      // Get the match to verify ownership and get chat room ID
      final doc = await _matchesRef.doc(matchId).get();
      if (!doc.exists) return false;

      final match = RealtimeMatch.fromFirestore(doc);

      // Only the owner can close for conversion
      if (match.ownerId != currentUserId) {
        debugPrint(
          '[RealtimeMatchService] Only owner can close match for conversion',
        );
        return false;
      }

      // Critical: mark match as closed — retry once with minimal payload on failure
      try {
        await _matchesRef.doc(matchId).update({
          'status': RequestStatus.closed,
          'closedReason': 'converted_to_cobuy',
          'convertedToCoBuyId': newCoBuyId,
          'closedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint(
          '[RealtimeMatchService] First close attempt failed, retrying: $e',
        );
        await _matchesRef.doc(matchId).update({
          'status': RequestStatus.closed,
          'convertedToCoBuyId': newCoBuyId,
        });
      }

      // Non-critical: send system message — failure here does not affect match closure
      if (match.chatRoomId != null) {
        try {
          final userName = await _getCurrentUserName();
          await _chatService.sendSystemMessage(
            chatRoomId: match.chatRoomId!,
            content:
                '🎉 $userName has created a Co-Buy Request! This match chat is now closed. Please continue the conversation in the new Co-Buy group chat.',
          );
        } catch (e) {
          debugPrint(
            '[RealtimeMatchService] System message failed (match is still closed): $e',
          );
        }
      }

      debugPrint(
        '[RealtimeMatchService] Closed match for conversion: $matchId -> Co-Buy: $newCoBuyId',
      );
      return true;
    } catch (e) {
      debugPrint(
        '[RealtimeMatchService] Error closing match for conversion: $e',
      );
      return false;
    }
  }

  /// Get stream of user's active matches
  Stream<List<RealtimeMatch>> getUserMatches() {
    if (currentUserId == null) return Stream.value([]);

    return _matchesRef
        .where('participants', arrayContains: currentUserId)
        .where('status', whereIn: [RequestStatus.waiting, RequestStatus.matched])
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RealtimeMatch.fromFirestore(doc))
              .toList(),
        );
  }

  /// Get stream of a specific match
  Stream<RealtimeMatch?> getMatchStream(String matchId) {
    return _matchesRef.doc(matchId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return RealtimeMatch.fromFirestore(doc);
    });
  }

  /// Get user's active waiting matches (for single match restriction)
  Future<List<RealtimeMatch>> getUserActiveWaitingMatches() async {
    if (currentUserId == null) return [];

    try {
      final snapshot = await _matchesRef
          .where('participants', arrayContains: currentUserId)
          .where('status', isEqualTo: RequestStatus.waiting)
          .get();

      return snapshot.docs
          .map((doc) => RealtimeMatch.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('[RealtimeMatchService] Error getting active matches: $e');
      return [];
    }
  }

  /// Get stream of all active matches (for map display)
  Stream<List<RealtimeMatch>> getActiveMatchesStream() {
    return _matchesRef
        .where('status', whereIn: [RequestStatus.waiting, RequestStatus.matched])
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RealtimeMatch.fromFirestore(doc))
              .toList(),
        );
  }
}
