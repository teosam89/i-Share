import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Credibility score event types — used by AuthProvider for verification scoring
enum CredibilityEvent {
  completeDeal, // +15
  rating5Star, // +10
  rating4Star, // +3
  rating3Below, // -5
  cancelWithParticipants, // -25 (only when others joined)
  cancelNoParticipants, // 0 (no harm done)
  leaveRequest, // -10
  expiredWithParticipants, // -10 (host let request expire with participants)
  complaint, // reserved for future use
  verifyEmail, // +20
  verifyPhone, // +30
}

/// Read-only credibility utilities.
///
/// All score WRITES are handled server-side by Cloud Functions:
///   - onCoRequestUpdated   → completed (+15), cancelled (-25)
///   - leaveRequestSecure   → leave (-10)
///   - submitRatingSecure   → rating score adjustment
///   - closeExpiredCoRequests → expired with participants (-10)
///   - AuthProvider._awardVerificationScore → email/phone verification
///
/// This service only provides display helpers and read streams.
class CredibilityService {
  static final CredibilityService _instance = CredibilityService._internal();
  factory CredibilityService() => _instance;
  CredibilityService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _profilesRef => _firestore.collection('profiles');

  String? get currentUserId => _auth.currentUser?.uid;

  /// Score points for each event type (used by AuthProvider for verification)
  static const Map<CredibilityEvent, int> eventPoints = {
    CredibilityEvent.completeDeal: 15,
    CredibilityEvent.rating5Star: 10,
    CredibilityEvent.rating4Star: 3,
    CredibilityEvent.rating3Below: -5,
    CredibilityEvent.cancelWithParticipants: -25,
    CredibilityEvent.cancelNoParticipants: 0,
    CredibilityEvent.leaveRequest: -10,
    CredibilityEvent.expiredWithParticipants: -10,
    CredibilityEvent.complaint: -20,
    CredibilityEvent.verifyEmail: 20,
    CredibilityEvent.verifyPhone: 30,
  };

  /// Get human-readable description for event
  static String getEventDescription(CredibilityEvent event) {
    switch (event) {
      case CredibilityEvent.completeDeal:
        return 'Completed a split';
      case CredibilityEvent.rating5Star:
        return 'Received 5-star rating';
      case CredibilityEvent.rating4Star:
        return 'Received 4-star rating';
      case CredibilityEvent.rating3Below:
        return 'Received low rating';
      case CredibilityEvent.cancelWithParticipants:
        return 'Cancelled request (participants affected)';
      case CredibilityEvent.cancelNoParticipants:
        return 'Cancelled request (no participants)';
      case CredibilityEvent.leaveRequest:
        return 'Left a request';
      case CredibilityEvent.expiredWithParticipants:
        return 'Request expired with participants';
      case CredibilityEvent.complaint:
        return 'Received complaint';
      case CredibilityEvent.verifyEmail:
        return 'Verified email';
      case CredibilityEvent.verifyPhone:
        return 'Verified phone';
    }
  }

  // ============ Display Helpers ============

  /// Get credibility level based on score (3-tier system)
  static String getCredibilityLevel(int score) {
    if (score < 300) return 'User';
    if (score < 700) return 'Trusted';
    return 'Elite';
  }

  /// Get credibility color based on level
  static int getCredibilityColor(String level) {
    switch (level) {
      case 'Elite':
        return 0xFFFFD700; // Gold
      case 'Trusted':
        return 0xFF4CAF50; // Green
      case 'User':
      default:
        return 0xFF2196F3; // Blue
    }
  }

  /// Get credibility icon path based on level
  static String getCredibilityIcon(String level) {
    switch (level) {
      case 'Elite':
        return 'assets/icons/CElite.png';
      case 'Trusted':
        return 'assets/icons/CTrusted.png';
      case 'User':
      default:
        return 'assets/icons/CUser.png';
    }
  }

  // ============ Read Streams ============

  /// Get score activities stream for a user
  Stream<List<Map<String, dynamic>>> getScoreActivities(
    String userId, {
    int limit = 20,
  }) {
    return _profilesRef
        .doc(userId)
        .collection('score_activities')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  /// Get user's ratings stream
  Stream<List<Map<String, dynamic>>> getUserRatings(String userId) {
    return _profilesRef
        .doc(userId)
        .collection('ratings')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  /// Check if current user has reviewed anyone for a specific request
  Future<bool> hasReviewedForRequest(
    String requestId,
    List<String> participantIds,
  ) async {
    final raterId = currentUserId;
    if (raterId == null) return true;

    try {
      for (final participantId in participantIds) {
        if (participantId == raterId) continue;

        final existingRating = await _profilesRef
            .doc(participantId)
            .collection('ratings')
            .where('fromUserId', isEqualTo: raterId)
            .where('requestId', isEqualTo: requestId)
            .limit(1)
            .get();

        if (existingRating.docs.isNotEmpty) {
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
