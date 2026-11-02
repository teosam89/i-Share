/// Co-Request Service - Firebase Firestore & Storage integration
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import '../models/co_request_model.dart';
import 'geohash_util.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/request_status.dart';

class CoRequestService {
  // Singleton pattern
  static final CoRequestService _instance = CoRequestService._internal();
  factory CoRequestService() => _instance;
  CoRequestService._internal();

  // Firestore collection reference
  final CollectionReference<Map<String, dynamic>> _requestsRef =
      FirebaseFirestore.instance.collection(AppConstants.coRequestsCollection);

  // ============ CRUD Operations ============

  /// Create a new request in Firestore
  Future<String> createRequest({
    required String initiatorId,
    required String initiatorName,
    String? initiatorPhotoUrl,
    required String productName,
    String? productPhotoUrl,
    required String dealDescription,
    required double totalPrice,
    required int totalQuantity,
    required int partnersNeeded,
    required String category,
    required String storeName,
    required double latitude,
    required double longitude,
    required int expiryHours,
    String? notes,
  }) async {
    // Comprehensive input validation
    if (productName.trim().isEmpty) {
      throw ArgumentError('productName cannot be empty');
    }
    if (productName.length > 200) {
      throw ArgumentError('productName must be 200 characters or less');
    }
    if (partnersNeeded < 1 || partnersNeeded > 50) {
      throw ArgumentError('partnersNeeded must be between 1 and 50');
    }
    if (totalPrice <= 0 || totalPrice > 999999) {
      throw ArgumentError('totalPrice must be between 0 and 999999');
    }
    if (totalQuantity < 1) {
      throw ArgumentError('totalQuantity must be at least 1');
    }
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError('latitude must be between -90 and 90');
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError('longitude must be between -180 and 180');
    }
    if (expiryHours < 1 || expiryHours > 168) {
      throw ArgumentError('expiryHours must be between 1 and 168 (7 days)');
    }

    try {
      final pricePerPerson = CoRequest.calculatePricePerPerson(
        totalPrice,
        partnersNeeded,
      );
      final now = DateTime.now();

      final docRef = await _requestsRef.add({
        'initiatorId': initiatorId,
        'initiatorName': initiatorName,
        'initiatorPhotoUrl': initiatorPhotoUrl,
        'productName': productName,
        'productPhotoUrl': productPhotoUrl,
        'dealDescription': dealDescription,
        'totalPrice': totalPrice,
        'totalQuantity': totalQuantity,
        'partnersNeeded': partnersNeeded,
        'pricePerPerson': pricePerPerson,
        'category': category,
        'storeName': storeName,
        'latitude': latitude,
        'longitude': longitude,
        'geohash': GeoHashUtil.encode(latitude, longitude),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'status': RequestStatus.active,
        // Initiator is now included in participants from the start
        'participants': <String>[initiatorId],
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(now.add(Duration(hours: expiryHours))),
      });

      debugPrint('[CoRequestService] Created request: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('[CoRequestService] Error creating request: $e');
      rethrow;
    }
  }

  /// Get a single request by ID
  Future<CoRequest?> getRequest(String requestId) async {
    try {
      final doc = await _requestsRef.doc(requestId).get();
      if (!doc.exists) return null;
      return CoRequest.fromFirestore(doc);
    } catch (e) {
      debugPrint('[CoRequestService] Error getting request: $e');
      return null;
    }
  }

  /// Update an existing request
  Future<void> updateRequest({
    required String requestId,
    String? productName,
    String? productPhotoUrl,
    String? dealDescription,
    double? totalPrice,
    int? totalQuantity,
    int? partnersNeeded,
    String? category,
    String? storeName,
    double? latitude,
    double? longitude,
    int? expiryHours,
    String? notes,
    String? status,
    List<String>? participants,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (productName != null) updates['productName'] = productName;
      if (productPhotoUrl != null) updates['productPhotoUrl'] = productPhotoUrl;
      if (dealDescription != null) updates['dealDescription'] = dealDescription;
      if (totalPrice != null) {
        updates['totalPrice'] = totalPrice;
        if (partnersNeeded != null) {
          updates['pricePerPerson'] = CoRequest.calculatePricePerPerson(
            totalPrice,
            partnersNeeded,
          );
        }
      }
      if (totalQuantity != null) updates['totalQuantity'] = totalQuantity;
      if (partnersNeeded != null) updates['partnersNeeded'] = partnersNeeded;
      if (category != null) updates['category'] = category;
      if (storeName != null) updates['storeName'] = storeName;
      if (latitude != null) updates['latitude'] = latitude;
      if (longitude != null) updates['longitude'] = longitude;
      if (latitude != null && longitude != null) {
        updates['geohash'] = GeoHashUtil.encode(latitude, longitude);
      }
      if (notes != null) updates['notes'] = notes;
      if (expiryHours != null) {
        updates['expiresAt'] = Timestamp.fromDate(
          DateTime.now().add(Duration(hours: expiryHours)),
        );
      }
      if (status != null) updates['status'] = status;
      if (participants != null) updates['participants'] = participants;

      if (updates.isNotEmpty) {
        await _requestsRef.doc(requestId).update(updates);
        debugPrint('[CoRequestService] Updated request: $requestId');
      }
    } catch (e) {
      debugPrint('[CoRequestService] Error updating request: $e');
      rethrow;
    }
  }

  /// Update product photo URL
  Future<void> updateProductPhotoUrl({
    required String requestId,
    required String photoUrl,
  }) async {
    try {
      await _requestsRef.doc(requestId).update({'productPhotoUrl': photoUrl});
      debugPrint('[CoRequestService] Updated photo URL for: $requestId');
    } catch (e) {
      debugPrint('[CoRequestService] Error updating photo URL: $e');
      rethrow;
    }
  }

  /// Delete a request and all associated data
  Future<void> deleteRequest(String requestId) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Get request data first for notification
      final requestDoc = await _requestsRef.doc(requestId).get();
      final requestData = requestDoc.data();
      final productName = requestData?['productName'] ?? 'This request';
      final participants = List<String>.from(
        requestData?['participants'] ?? [],
      );

      // 1. Delete all join_requests in subcollection
      final joinRequestsSnapshot = await _requestsRef
          .doc(requestId)
          .collection(AppConstants.joinRequestsCollection)
          .get();
      for (final doc in joinRequestsSnapshot.docs) {
        await doc.reference.delete();
      }
      debugPrint(
        '[CoRequestService] Deleted ${joinRequestsSnapshot.docs.length} join requests',
      );

      // 2. Send notification message to chat room before deleting
      final chatRoomRef = firestore.collection(AppConstants.chatRoomsCollection).doc(requestId);
      final chatRoomDoc = await chatRoomRef.get();
      if (chatRoomDoc.exists && participants.isNotEmpty) {
        // Send system message to notify participants
        await chatRoomRef.collection(AppConstants.messagesCollection).add({
          'senderId': 'system',
          'senderName': 'System',
          'content':
              '⚠️ The host has deleted "$productName". This chat will be removed.',
          'type': 'system',
          'timestamp': FieldValue.serverTimestamp(),
        });
        debugPrint('[CoRequestService] Sent deletion notification to chat');

        // Small delay to ensure message is delivered
        await Future.delayed(const Duration(milliseconds: 500));

        // Delete all messages in chat room
        final messagesSnapshot = await chatRoomRef.collection(AppConstants.messagesCollection).get();
        for (final doc in messagesSnapshot.docs) {
          await doc.reference.delete();
        }
        await chatRoomRef.delete();
        debugPrint('[CoRequestService] Deleted chat room and messages');
      }

      // 3. Delete QR verification document if exists
      try {
        await firestore.collection('qr_verifications').doc(requestId).delete();
      } catch (_) {
        // Ignore if doesn't exist
      }

      // 4. Delete the request document
      await _requestsRef.doc(requestId).delete();

      // 5. Delete associated image from Storage
      await ImageUploadService().deleteProductImage(requestId);

      debugPrint('[CoRequestService] Deleted request: $requestId');
    } catch (e) {
      debugPrint('[CoRequestService] Error deleting request: $e');
      rethrow;
    }
  }

  // ============ Query Operations ============

  /// Get active requests near a location (geohash-filtered).
  ///
  /// Queries Firestore using geohash range(s) so only nearby documents
  /// are transferred — far cheaper than fetching everything.
  /// Falls back to unfiltered query when [userLat]/[userLng] are null.
  Future<List<CoRequest>> getActiveRequests({
    double? userLat,
    double? userLng,
    int limit = 50,
  }) async {
    try {
      final now = DateTime.now();
      List<CoRequest> results = [];

      if (userLat != null && userLng != null) {
        // Geo-filtered: query each geohash range covering ~5km around user
        final ranges = GeoHashUtil.queryRanges(userLat, userLng);
        for (final range in ranges) {
          final snapshot = await _requestsRef
              .where('status', isEqualTo: RequestStatus.active)
              .where('geohash', isGreaterThanOrEqualTo: range.start)
              .where('geohash', isLessThan: range.end)
              .limit(limit)
              .get();
          results.addAll(
            snapshot.docs.map((doc) => CoRequest.fromFirestore(doc)),
          );
        }
      } else {
        // Fallback: no location available — fetch all active
        final snapshot = await _requestsRef
            .where('status', isEqualTo: RequestStatus.active)
            .limit(limit)
            .get();
        results = snapshot.docs
            .map((doc) => CoRequest.fromFirestore(doc))
            .toList();
      }

      // Client-side: filter expired, deduplicate, sort
      final seen = <String>{};
      final filtered = results
          .where((r) => r.expiresAt.isAfter(now) && seen.add(r.id))
          .toList();
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return filtered;
    } catch (e) {
      debugPrint('[CoRequestService] Error getting active requests: $e');
      return [];
    }
  }

  /// Get requests created by a specific user
  Future<List<CoRequest>> getMyRequests(String userId) async {
    try {
      // NO orderBy - avoids composite index requirement
      final snapshot = await _requestsRef
          .where('initiatorId', isEqualTo: userId)
          .get();

      // Sort client-side
      final requests = snapshot.docs
          .map((doc) => CoRequest.fromFirestore(doc))
          .toList();
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    } catch (e) {
      debugPrint('[CoRequestService] Error getting my requests: $e');
      return [];
    }
  }

  /// Get requests user has joined (not created by them)
  Future<List<CoRequest>> getJoinedRequests(String userId) async {
    try {
      final snapshot = await _requestsRef
          .where('participants', arrayContains: userId)
          .get();

      // Filter out requests created by user, sort client-side
      final requests = snapshot.docs
          .map((doc) => CoRequest.fromFirestore(doc))
          .where((r) => r.initiatorId != userId) // Exclude own requests
          .toList();
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    } catch (e) {
      debugPrint('[CoRequestService] Error getting joined requests: $e');
      return [];
    }
  }

  // ============ Real-Time Streams ============

  /// Stream of active requests with optional geohash filtering.
  ///
  /// When [userLat]/[userLng] are provided, uses geohash range queries
  /// and merges multiple streams. Otherwise falls back to unfiltered stream.
  Stream<List<CoRequest>> streamActiveRequests({
    double? userLat,
    double? userLng,
  }) {
    if (userLat != null && userLng != null) {
      final ranges = GeoHashUtil.queryRanges(userLat, userLng);

      // Create a stream per geohash range and merge results
      final streams = ranges.map((range) => _requestsRef
          .where('status', isEqualTo: RequestStatus.active)
          .where('geohash', isGreaterThanOrEqualTo: range.start)
          .where('geohash', isLessThan: range.end)
          .snapshots()
          .map((snap) => snap.docs.map((d) => CoRequest.fromFirestore(d)).toList()));

      // Combine all range streams into one deduplicated list
      return _mergeStreams(streams.toList());
    }

    // Fallback: no location
    return _requestsRef
        .where('status', isEqualTo: RequestStatus.active)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final requests = snapshot.docs
              .map((doc) => CoRequest.fromFirestore(doc))
              .where((r) => r.expiresAt.isAfter(now))
              .toList();
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Merge multiple CoRequest list streams into one deduplicated stream.
  Stream<List<CoRequest>> _mergeStreams(
    List<Stream<List<CoRequest>>> streams,
  ) async* {
    // Store latest snapshot from each stream
    final buckets = List<List<CoRequest>>.filled(streams.length, const []);
    final controller = StreamController<List<CoRequest>>();

    final subscriptions = <StreamSubscription>[];
    for (int i = 0; i < streams.length; i++) {
      subscriptions.add(streams[i].listen((data) {
        buckets[i] = data;
        // Merge all buckets, deduplicate, filter, sort
        final now = DateTime.now();
        final seen = <String>{};
        final merged = buckets
            .expand((b) => b)
            .where((r) => r.expiresAt.isAfter(now) && seen.add(r.id))
            .toList();
        merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        controller.add(merged);
      }));
    }

    // onCancel must be set BEFORE yield* so it fires when the consumer cancels.
    // If set after yield*, the async* generator body is suspended at yield* and
    // onCancel is never registered — inner subscriptions would leak forever.
    controller.onCancel = () {
      for (final sub in subscriptions) {
        sub.cancel();
      }
      controller.close();
    };

    yield* controller.stream;
  }

  /// Stream of user's own requests
  Stream<List<CoRequest>> streamMyRequests(String userId) {
    return _requestsRef.where('initiatorId', isEqualTo: userId).snapshots().map(
      (snapshot) {
        final requests = snapshot.docs
            .map((doc) => CoRequest.fromFirestore(doc))
            .toList();
        // Sort client-side
        requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return requests;
      },
    );
  }

  /// Stream of requests user has joined (not created by them)
  Stream<List<CoRequest>> streamJoinedRequests(String userId) {
    return _requestsRef
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => CoRequest.fromFirestore(doc))
              .where((r) => r.initiatorId != userId) // Exclude own requests
              .toList();
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  // ============ Participant Actions ============

  /// Join a request as participant
  Future<bool> joinRequest(String requestId, String userId) async {
    try {
      await _requestsRef.doc(requestId).update({
        'participants': FieldValue.arrayUnion([userId]),
      });
      debugPrint('[CoRequestService] User $userId joined request $requestId');
      return true;
    } catch (e) {
      debugPrint('[CoRequestService] Error joining request: $e');
      return false;
    }
  }

  /// Leave a request (participants only) - Uses secure Cloud Function
  Future<bool> leaveRequest(String requestId, String userId) async {
    try {
      // Call secure Cloud Function instead of direct Firestore update
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('leaveRequestSecure');

      await callable.call({'requestId': requestId});

      debugPrint('[CoRequestService] User $userId left request $requestId');
      return true;
    } catch (e) {
      debugPrint('[CoRequestService] Error leaving request: $e');
      return false;
    }
  }

  /// Extend an expired request by adding more time
  /// Resets status to 'active' so it counts towards credibility again
  Future<void> extendRequest(String requestId, int additionalHours) async {
    final newExpiresAt = DateTime.now().add(Duration(hours: additionalHours));
    await _requestsRef.doc(requestId).update({
      'expiresAt': Timestamp.fromDate(newExpiresAt),
      'status': RequestStatus.active,
    });
    debugPrint(
      '[CoRequestService] Extended request $requestId by $additionalHours hours',
    );
  }
}

// ============ Image Upload Service ============

class ImageUploadService {
  static final ImageUploadService _instance = ImageUploadService._internal();
  factory ImageUploadService() => _instance;
  ImageUploadService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload product image to Firebase Storage
  Future<String?> uploadProductImage({
    required String requestId,
    required String imagePath,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('[ImageUploadService] File does not exist: $imagePath');
        return null;
      }

      // Guard: reject if still > 5 MB after client-side compression
      final sizeBytes = await file.length();
      if (sizeBytes > 5 * 1024 * 1024) {
        debugPrint('[ImageUploadService] Image too large: ${sizeBytes ~/ 1024} KB');
        throw Exception('Image is too large. Please choose a smaller photo.');
      }

      final ref = _storage.ref().child('co_requests/$requestId/product.jpg');
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint('[ImageUploadService] Uploaded image: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('[ImageUploadService] Error uploading image: $e');
      return null;
    }
  }

  /// Delete product image from Storage
  Future<void> deleteProductImage(String requestId) async {
    try {
      final ref = _storage.ref().child('co_requests/$requestId/product.jpg');
      await ref.delete();
      debugPrint('[ImageUploadService] Deleted image for request: $requestId');
    } catch (e) {
      // Ignore if file doesn't exist
      debugPrint('[ImageUploadService] Error deleting image: $e');
    }
  }
}
