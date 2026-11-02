import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/co_request_model.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/request_status.dart';
import '../services/co_request_service.dart';
import '../services/location_service.dart';
import '../../profile/services/profile_service.dart';

/// CoRequestProvider - Manages state for co-requests across screens
/// Connects to Firestore for real-time data synchronization
class CoRequestProvider extends ChangeNotifier {
  static final CoRequestProvider _instance = CoRequestProvider._internal();
  factory CoRequestProvider() => _instance;
  CoRequestProvider._internal();

  final CoRequestService _service = CoRequestService();
  final LocationService _locationService = LocationService();

  // User's current position for distance calculation
  Position? _userPosition;

  // All requests (for feed)
  List<CoRequest> _allRequests = [];
  List<CoRequest> get allRequests => _allRequests;

  // User's own created requests
  List<CoRequest> _myRequests = [];
  List<CoRequest> get myRequests => _myRequests;

  // Requests user has joined (not created)
  List<CoRequest> _joinedRequests = [];
  List<CoRequest> get joinedRequests => _joinedRequests;

  // Loading states
  bool _isLoadingFeed = false;
  bool get isLoadingFeed => _isLoadingFeed;

  bool _isLoadingMyRequests = false;
  bool get isLoadingMyRequests => _isLoadingMyRequests;

  // Stream subscriptions
  StreamSubscription<List<CoRequest>>? _feedSubscription;
  StreamSubscription<List<CoRequest>>? _myRequestsSubscription;
  StreamSubscription<List<CoRequest>>? _joinedRequestsSubscription;

  // Get current user ID from Firebase Auth
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  String get currentUserName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'You';

  String? get currentUserPhotoUrl =>
      FirebaseAuth.instance.currentUser?.photoURL;

  /// Initialize and load data from Firestore.
  ///
  /// Uses one-time fetches instead of real-time streams for the feed to
  /// minimize Firestore read costs. The feed uses 9 geohash range queries;
  /// as snapshots each one would fire on every document change in the range,
  /// multiplying reads by 9× per user. Pull-to-refresh covers freshness.
  Future<void> initialize() async {
    // Get user's current position for distance calculation
    _userPosition = await _locationService.getCurrentPosition();

    await loadFeedRequests();
    await loadMyRequests();
  }

  /// Calculate distances for all requests based on user position
  List<CoRequest> _calculateDistances(List<CoRequest> requests) {
    if (_userPosition == null) return requests;

    return requests.map((request) {
      final distance = _locationService.calculateDistance(
        _userPosition!.latitude,
        _userPosition!.longitude,
        request.latitude,
        request.longitude,
      );
      return request.copyWith(distanceMeters: distance);
    }).toList();
  }

  // Feed and My/Joined requests all use one-time fetches to minimize
  // Firestore read costs. Pull-to-refresh handles freshness.

  /// Load active requests for feed (one-time fetch, geo-filtered)
  Future<void> loadFeedRequests() async {
    _isLoadingFeed = true;
    notifyListeners();

    try {
      final requests = await _service.getActiveRequests(
        userLat: _userPosition?.latitude,
        userLng: _userPosition?.longitude,
      );
      _allRequests = _calculateDistances(requests);
    } catch (e) {
      debugPrint('Error loading feed: $e');
    } finally {
      _isLoadingFeed = false;
      notifyListeners();
    }
  }

  /// Load user's own requests + joined requests (one-time fetch).
  ///
  /// [silent] — when true, skips the loading spinner so the UI doesn't
  /// flash while background-refreshing (e.g. on tab tap or post-mutation).
  Future<void> loadMyRequests({bool silent = false}) async {
    final userId = currentUserId;
    if (userId == null) return;

    if (!silent) {
      _isLoadingMyRequests = true;
      notifyListeners();
    }

    try {
      // Load created requests
      final myReqs = await _service.getMyRequests(userId);
      _myRequests = _calculateDistances(myReqs);
      // Load joined requests
      final joinedReqs = await _service.getJoinedRequests(userId);
      _joinedRequests = _calculateDistances(joinedReqs);
    } catch (e) {
      debugPrint('Error loading my requests: $e');
    } finally {
      _isLoadingMyRequests = false;
      notifyListeners();
    }
  }

  /// Create a new request
  Future<String?> createRequest({
    required String productName,
    required String? productPhotoPath,
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
    final userId = currentUserId;
    if (userId == null) {
      debugPrint('Cannot create request: User not logged in');
      return null;
    }

    try {
      // Fetch user profile for display name and photo
      final displayInfo = await ProfileService().getDisplayInfo(userId);
      final initiatorName = displayInfo.name;
      final initiatorPhotoUrl = displayInfo.photoUrl;

      // Create request in Firestore first (without image)
      final requestId = await _service.createRequest(
        initiatorId: userId,
        initiatorName: initiatorName,
        initiatorPhotoUrl: initiatorPhotoUrl,
        productName: productName,
        productPhotoUrl: null, // Will be updated after image upload
        dealDescription: dealDescription,
        totalPrice: totalPrice,
        totalQuantity: totalQuantity,
        partnersNeeded: partnersNeeded,
        category: category,
        storeName: storeName,
        latitude: latitude,
        longitude: longitude,
        expiryHours: expiryHours,
        notes: notes,
      );

      // Upload image if provided
      if (productPhotoPath != null) {
        final imageUrl = await ImageUploadService().uploadProductImage(
          requestId: requestId,
          imagePath: productPhotoPath,
        );
        if (imageUrl != null) {
          // Update the request with the image URL
          await _service.updateProductPhotoUrl(
            requestId: requestId,
            photoUrl: imageUrl,
          );
        }
      }

      // Refresh My Splits so the new request is immediately visible.
      // Silent = no spinner since the user is still on the create screen.
      unawaited(loadMyRequests(silent: true));

      return requestId;
    } catch (e) {
      debugPrint('Error creating request: $e');
      return null;
    }
  }

  /// Update a request (for editing)
  Future<bool> updateRequest({
    required String requestId,
    String? productName,
    String? productPhotoPath, // New image path to upload
    String? existingPhotoUrl, // Keep existing photo if no new one
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
  }) async {
    try {
      String? photoUrl = existingPhotoUrl;

      // Upload new image if provided
      if (productPhotoPath != null) {
        photoUrl = await ImageUploadService().uploadProductImage(
          requestId: requestId,
          imagePath: productPhotoPath,
        );
      }

      await _service.updateRequest(
        requestId: requestId,
        productName: productName,
        productPhotoUrl: photoUrl,
        dealDescription: dealDescription,
        totalPrice: totalPrice,
        totalQuantity: totalQuantity,
        partnersNeeded: partnersNeeded,
        category: category,
        storeName: storeName,
        latitude: latitude,
        longitude: longitude,
        expiryHours: expiryHours,
        notes: notes,
        status: status,
      );

      // Streams auto-update — no manual refresh needed.
      return true;
    } catch (e) {
      debugPrint('Error updating request: $e');
      return false;
    }
  }

  /// Delete a request
  Future<bool> deleteRequest(String requestId) async {
    try {
      await _service.deleteRequest(requestId);
      return true;
    } catch (e) {
      debugPrint('Error deleting request: $e');
      return false;
    }
  }

  /// Join a request as participant
  Future<bool> joinRequest(String requestId) async {
    final userId = currentUserId;
    if (userId == null) return false;

    return await _service.joinRequest(requestId, userId);
  }

  /// Leave a request
  Future<bool> leaveRequest(String requestId) async {
    final userId = currentUserId;
    if (userId == null) return false;

    return await _service.leaveRequest(requestId, userId);
  }

  /// Extend an expired request by adding additional hours
  /// Reactivates the request (status → active, new expiresAt)
  Future<void> extendRequest(String requestId, int additionalHours) async {
    await _service.extendRequest(requestId, additionalHours);
    // Stream auto-updates — no manual refresh needed.
  }

  /// Add a participant directly from RTM conversion (no join request needed)
  /// This is used when converting RTM to Co-Buy - all RTM participants are auto-added
  Future<bool> addParticipantFromRtm({
    required String requestId,
    required String participantId,
  }) async {
    try {
      // Verify participant's profile exists
      await FirebaseFirestore.instance
          .collection(AppConstants.profilesCollection)
          .doc(participantId)
          .get();

      // Add participant directly to the request
      await FirebaseFirestore.instance
          .collection(AppConstants.coRequestsCollection)
          .doc(requestId)
          .update({
            'participants': FieldValue.arrayUnion([participantId]),
          });

      // Add participant to chat room
      await FirebaseFirestore.instance
          .collection(AppConstants.chatRoomsCollection)
          .doc(requestId)
          .update({
            'participantIds': FieldValue.arrayUnion([participantId]),
          });

      // Note: totalJoined stat is incremented by onCoRequestUpdated Cloud Function
      // when it detects the new participant — no client-side write needed.

      debugPrint(
        '[CoRequestProvider] Added RTM participant $participantId to request $requestId',
      );
      return true;
    } catch (e) {
      debugPrint('[CoRequestProvider] Error adding RTM participant: $e');
      return false;
    }
  }

  /// Get requests filtered by status
  /// 'active' = my created active requests
  /// 'matched' = requests I joined (not created)
  /// 'completed' = my created completed requests + joined completed
  List<CoRequest> getMyRequestsByStatus(String status) {
    if (status == 'all') {
      return [..._myRequests, ..._joinedRequests];
    }
    if (status == RequestStatus.matched) {
      // Show requests user joined but not completed
      return _joinedRequests.where((r) => r.status != RequestStatus.completed).toList();
    }
    if (status == RequestStatus.completed) {
      // Show both created and joined completed requests
      final myCompleted = _myRequests.where((r) => r.status == RequestStatus.completed);
      final joinedCompleted = _joinedRequests.where(
        (r) => r.status == RequestStatus.completed,
      );
      return [...myCompleted, ...joinedCompleted];
    }
    // 'active' = my created active requests
    return _myRequests.where((r) => r.status == status).toList();
  }

  /// Check if a request belongs to current user
  bool isMyRequest(CoRequest request) {
    return request.initiatorId == currentUserId;
  }

  /// Clear all data and stop listeners (e.g., on logout)
  void clear() {
    _feedSubscription?.cancel();
    _myRequestsSubscription?.cancel();
    _joinedRequestsSubscription?.cancel();
    _allRequests.clear();
    _myRequests.clear();
    _joinedRequests.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _feedSubscription?.cancel();
    _myRequestsSubscription?.cancel();
    _joinedRequestsSubscription?.cancel();
    super.dispose();
  }
}
