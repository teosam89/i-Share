import 'package:cloud_firestore/cloud_firestore.dart';

/// Verification status for user account
class Verifications {
  final bool email;
  final bool phone;
  final bool identity;

  Verifications({
    this.email = false,
    this.phone = false,
    this.identity = false,
  });

  factory Verifications.fromMap(Map<String, dynamic>? data) {
    if (data == null) return Verifications();
    return Verifications(
      email: data['email'] ?? false,
      phone: data['phone'] ?? false,
      identity: data['identity'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'email': email,
    'phone': phone,
    'identity': identity,
  };

  int get verifiedCount => [email, phone, identity].where((v) => v).length;
}

/// UserProfile Model - Represents a user's profile with credibility stats
class UserProfile {
  final String id; // Same as Firebase Auth UID
  final String displayName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final String? gender; // 'male', 'female', 'other'
  final String? bio;
  final int? bannerColor; // Custom banner color as int (e.g., 0xFF4A90E2)
  final DateTime createdAt;
  final DateTime? lastActiveAt;

  // Credibility Stats
  final int score; // Internal behavior score (0-1000)
  final int totalRequests; // Requests initiated
  final int totalJoined; // Requests joined
  final int completedRequests; // Successfully completed
  final int cancelledRequests; // Cancelled by user
  final double rating; // Average rating (1-5)
  final int ratingCount; // Number of ratings received
  final Verifications verifications; // Account verifications
  final List<String> badges; // Achievement badges

  // Derived Stats
  double get completionRate {
    final total = totalRequests + totalJoined;
    if (total == 0) return 0;
    return completedRequests / total;
  }

  /// 3-tier credibility level based on score
  String get credibilityLevel {
    if (score < 300) return 'User';
    if (score < 700) return 'Trusted';
    return 'Elite';
  }

  /// Icon asset path for credibility level
  String get credibilityIcon {
    switch (credibilityLevel) {
      case 'Elite':
        return 'assets/icons/CElite.png';
      case 'Trusted':
        return 'assets/icons/CTrusted.png';
      case 'User':
      default:
        return 'assets/icons/CUser.png';
    }
  }

  UserProfile({
    required this.id,
    required this.displayName,
    this.email,
    this.phone,
    this.photoUrl,
    this.gender,
    this.bio,
    this.bannerColor,
    required this.createdAt,
    this.lastActiveAt,
    this.score = 100, // New users start with 100 points
    this.totalRequests = 0,
    this.totalJoined = 0,
    this.completedRequests = 0,
    this.cancelledRequests = 0,
    this.rating = 0.0,
    this.ratingCount = 0,
    Verifications? verifications,
    List<String>? badges,
  }) : verifications = verifications ?? Verifications(),
       badges = badges ?? [];

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      id: doc.id,
      displayName: data['displayName'] ?? 'User',
      email: data['email'],
      phone: data['phone'],
      photoUrl: data['photoUrl'],
      gender: data['gender'],
      bio: data['bio'],
      bannerColor: data['bannerColor'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate(),
      score: data['score'] ?? 100,
      totalRequests: data['totalRequests'] ?? 0,
      totalJoined: data['totalJoined'] ?? 0,
      completedRequests: data['completedRequests'] ?? 0,
      cancelledRequests: data['cancelledRequests'] ?? 0,
      rating: (data['rating'] ?? 0.0).toDouble(),
      ratingCount: data['ratingCount'] ?? 0,
      verifications: Verifications.fromMap(data['verifications']),
      badges: List<String>.from(data['badges'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'gender': gender,
      'bio': bio,
      'bannerColor': bannerColor,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActiveAt': lastActiveAt != null
          ? Timestamp.fromDate(lastActiveAt!)
          : FieldValue.serverTimestamp(),
      'score': score,
      'totalRequests': totalRequests,
      'totalJoined': totalJoined,
      'completedRequests': completedRequests,
      'cancelledRequests': cancelledRequests,
      'rating': rating,
      'ratingCount': ratingCount,
      'verifications': verifications.toMap(),
      'badges': badges,
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? email,
    String? phone,
    String? photoUrl,
    String? gender,
    String? bio,
    int? bannerColor,
    DateTime? lastActiveAt,
    int? score,
    int? totalRequests,
    int? totalJoined,
    int? completedRequests,
    int? cancelledRequests,
    double? rating,
    int? ratingCount,
    Verifications? verifications,
    List<String>? badges,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      gender: gender ?? this.gender,
      bio: bio ?? this.bio,
      bannerColor: bannerColor ?? this.bannerColor,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      score: score ?? this.score,
      totalRequests: totalRequests ?? this.totalRequests,
      totalJoined: totalJoined ?? this.totalJoined,
      completedRequests: completedRequests ?? this.completedRequests,
      cancelledRequests: cancelledRequests ?? this.cancelledRequests,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      verifications: verifications ?? this.verifications,
      badges: badges ?? this.badges,
    );
  }
}

/// UserRating Model - Individual rating given to a user
class UserRating {
  final String id;
  final String fromUserId;
  final String fromUserName;
  final String toUserId;
  final String requestId;
  final int rating; // 1-5 stars
  final String? comment;
  final DateTime createdAt;

  UserRating({
    required this.id,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.requestId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory UserRating.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserRating(
      id: doc.id,
      fromUserId: data['fromUserId'] ?? '',
      fromUserName: data['fromUserName'] ?? 'Anonymous',
      toUserId: data['toUserId'] ?? '',
      requestId: data['requestId'] ?? '',
      rating: data['rating'] ?? 5,
      comment: data['comment'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'toUserId': toUserId,
      'requestId': requestId,
      'rating': rating,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
