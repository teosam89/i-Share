import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/request_status.dart';

/// RealtimeMatch Model - Data structure for real-time partner matching rooms
class RealtimeMatch {
  final String id;
  final String ownerId;
  final String ownerName;
  final String? ownerPhotoUrl;
  final String category;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final String locationName;
  final List<String> participants;
  final int maxPartners; // Max partners needed (1, 2, or 3)
  final String status; // 'waiting', 'matched', 'closed'
  final String? chatRoomId;
  final String? convertedToCoBuyId; // Set when closed via RTM → Co-Buy conversion
  final Map<String, String> participantIntents; // userId → product intent text
  final List<String> skippedBy; // userIds who skipped this room
  final DateTime createdAt;
  final DateTime expiresAt; // Expiry time for waiting matches

  RealtimeMatch({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    this.ownerPhotoUrl,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.locationName,
    required this.participants,
    this.participantIntents = const {},
    this.skippedBy = const [],
    this.maxPartners = 1,
    required this.status,
    this.chatRoomId,
    this.convertedToCoBuyId,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Check if user is the owner
  bool isOwner(String userId) => ownerId == userId;

  /// Check if user is a participant
  bool isParticipant(String userId) => participants.contains(userId);

  /// Get participant count
  int get participantCount => participants.length;

  /// Check if room is full (owner + maxPartners)
  bool get isFull => participantCount >= (maxPartners + 1);

  /// Check if match has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'ownerPhotoUrl': ownerPhotoUrl,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'radiusKm': radiusKm,
      'locationName': locationName,
      'participants': participants,
      'participantIntents': participantIntents,
      'skippedBy': skippedBy,
      'maxPartners': maxPartners,
      'status': status,
      'chatRoomId': chatRoomId,
      'convertedToCoBuyId': convertedToCoBuyId,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
    };
  }

  /// Create from Firestore document
  factory RealtimeMatch.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RealtimeMatch(
      id: doc.id,
      ownerId: data['ownerId'] ?? '',
      ownerName: data['ownerName'] ?? 'Unknown',
      ownerPhotoUrl: data['ownerPhotoUrl'],
      category: data['category'] ?? 'others',
      latitude: (data['latitude'] ?? 0).toDouble(),
      longitude: (data['longitude'] ?? 0).toDouble(),
      radiusKm: (data['radiusKm'] ?? 1).toDouble(),
      locationName: data['locationName'] ?? '',
      participants: List<String>.from(data['participants'] ?? []),
      participantIntents: Map<String, String>.from(data['participantIntents'] ?? {}),
      skippedBy: List<String>.from(data['skippedBy'] ?? []),
      maxPartners: data['maxPartners'] ?? 1,
      status: data['status'] ?? RequestStatus.waiting,
      chatRoomId: data['chatRoomId'],
      convertedToCoBuyId: data['convertedToCoBuyId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(hours: 24)), // Default 24h expiry
    );
  }

  /// Create a copy with updated fields
  RealtimeMatch copyWith({
    String? id,
    String? ownerId,
    String? ownerName,
    String? ownerPhotoUrl,
    String? category,
    double? latitude,
    double? longitude,
    double? radiusKm,
    String? locationName,
    List<String>? participants,
    Map<String, String>? participantIntents,
    List<String>? skippedBy,
    int? maxPartners,
    String? status,
    String? chatRoomId,
    String? convertedToCoBuyId,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return RealtimeMatch(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      ownerPhotoUrl: ownerPhotoUrl ?? this.ownerPhotoUrl,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusKm: radiusKm ?? this.radiusKm,
      locationName: locationName ?? this.locationName,
      participants: participants ?? this.participants,
      participantIntents: participantIntents ?? this.participantIntents,
      skippedBy: skippedBy ?? this.skippedBy,
      maxPartners: maxPartners ?? this.maxPartners,
      status: status ?? this.status,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      convertedToCoBuyId: convertedToCoBuyId ?? this.convertedToCoBuyId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

/// Radius options for matching
class MatchRadius {
  static const List<double> options = [0.5, 1.0, 2.0, 5.0, 10.0];

  static String getLabel(double km) {
    if (km < 1) return '${(km * 1000).toInt()}m';
    return '${km.toInt()}km';
  }
}

/// Partner count options
class PartnerCount {
  static const List<int> options = [1, 2, 3];
}
