/// Co-Request Model - Data structure for group buying requests
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/request_status.dart';

class CoRequest {
  final String id;
  final String initiatorId;
  final String initiatorName;
  final String? initiatorPhotoUrl;

  // UGC Product Info
  final String productName;
  final String? productPhotoUrl;
  final String dealDescription;

  // Split Logic
  final double totalPrice;
  final int totalQuantity;
  final int partnersNeeded;
  final double pricePerPerson;

  // Location
  final double latitude;
  final double longitude;
  final String? geohash; // Geohash for server-side proximity queries
  final String storeName;
  final String? storeAddress;
  final double? distanceMeters;

  // Additional Notes
  final String? notes;

  // Category
  final String category;

  // Status
  final String status; // active, pending, matched, completed, cancelled
  final List<String> participants;

  // Timestamps
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? completedAt;

  CoRequest({
    required this.id,
    required this.initiatorId,
    required this.initiatorName,
    this.initiatorPhotoUrl,
    required this.productName,
    this.productPhotoUrl,
    required this.dealDescription,
    required this.totalPrice,
    required this.totalQuantity,
    required this.partnersNeeded,
    required this.pricePerPerson,
    required this.latitude,
    required this.longitude,
    this.geohash,
    required this.storeName,
    this.storeAddress,
    this.distanceMeters,
    this.notes,
    required this.category,
    required this.status,
    required this.participants,
    required this.createdAt,
    required this.expiresAt,
    this.completedAt,
  });

  /// Calculate price per person
  static double calculatePricePerPerson(double totalPrice, int partnersNeeded) {
    final totalPeople = partnersNeeded + 1;
    return (totalPrice / totalPeople * 100).round() / 100;
  }

  /// Format time remaining
  String get timeRemaining {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours % 24}h ${remaining.inMinutes % 60}m left';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
    }
    return '${remaining.inMinutes}m left';
  }

  /// Check if expires within 1 hour (for urgency styling)
  bool get isUrgent {
    final remaining = expiresAt.difference(DateTime.now());
    return !remaining.isNegative && remaining.inMinutes <= 60;
  }

  /// Check if expired
  bool get isExpired => expiresAt.isBefore(DateTime.now());

  /// Check if all partner slots are filled
  /// Note: participants list includes the initiator, so full = partnersNeeded + 1
  bool get isFull => participants.length >= partnersNeeded + 1;

  /// Badge display label with priority: Full > Expired > TimeRemaining
  /// Returns ('label', 'type') where type is 'full', 'expired', 'urgent', 'normal'
  (String label, String type) get displayBadge {
    if (status == RequestStatus.completed) return ('Completed', 'completed');
    if (status == RequestStatus.cancelled) return ('Cancelled', 'cancelled');
    if (isFull) return ('Full', 'full');
    if (isExpired) return ('Expired', 'expired');
    if (isUrgent) return (timeRemaining, 'urgent');
    return (timeRemaining, 'normal');
  }

  /// Format distance
  String get distanceText {
    if (distanceMeters == null) return 'Unknown';
    if (distanceMeters! < 1000) return '${distanceMeters!.round()}m away';
    return '${(distanceMeters! / 1000).toStringAsFixed(1)}km away';
  }

  /// Check if current user is the initiator
  bool isInitiator(String userId) => initiatorId == userId;

  // ============ Firestore Serialization ============

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
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
      'latitude': latitude,
      'longitude': longitude,
      if (geohash != null) 'geohash': geohash,
      'storeName': storeName,
      'storeAddress': storeAddress,
      if (notes != null) 'notes': notes,
      'category': category,
      'status': status,
      'participants': participants,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
    };
  }

  /// Create from Firestore document
  factory CoRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CoRequest(
      id: doc.id,
      initiatorId: data['initiatorId'] ?? '',
      initiatorName: data['initiatorName'] ?? 'Unknown',
      initiatorPhotoUrl: data['initiatorPhotoUrl'],
      productName: data['productName'] ?? '',
      productPhotoUrl: data['productPhotoUrl'],
      dealDescription: data['dealDescription'] ?? '',
      totalPrice: (data['totalPrice'] ?? 0).toDouble(),
      totalQuantity: data['totalQuantity'] ?? 1,
      partnersNeeded: data['partnersNeeded'] ?? 1,
      pricePerPerson: (data['pricePerPerson'] ?? 0).toDouble(),
      latitude: (data['latitude'] ?? 0).toDouble(),
      longitude: (data['longitude'] ?? 0).toDouble(),
      geohash: data['geohash'],
      storeName: data['storeName'] ?? '',
      storeAddress: data['storeAddress'],
      distanceMeters: null, // Calculated client-side
      notes: data['notes'],
      category: RequestCategories.normalizeCategory(data['category'] ?? 'others'),
      status: data['status'] ?? RequestStatus.active,
      participants: List<String>.from(data['participants'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(hours: 2)),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Create a copy with updated fields
  CoRequest copyWith({
    String? id,
    String? initiatorId,
    String? initiatorName,
    String? initiatorPhotoUrl,
    String? productName,
    String? productPhotoUrl,
    String? dealDescription,
    double? totalPrice,
    int? totalQuantity,
    int? partnersNeeded,
    double? pricePerPerson,
    double? latitude,
    double? longitude,
    String? geohash,
    String? storeName,
    String? storeAddress,
    double? distanceMeters,
    String? notes,
    String? category,
    String? status,
    List<String>? participants,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? completedAt,
  }) {
    return CoRequest(
      id: id ?? this.id,
      initiatorId: initiatorId ?? this.initiatorId,
      initiatorName: initiatorName ?? this.initiatorName,
      initiatorPhotoUrl: initiatorPhotoUrl ?? this.initiatorPhotoUrl,
      productName: productName ?? this.productName,
      productPhotoUrl: productPhotoUrl ?? this.productPhotoUrl,
      dealDescription: dealDescription ?? this.dealDescription,
      totalPrice: totalPrice ?? this.totalPrice,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      partnersNeeded: partnersNeeded ?? this.partnersNeeded,
      pricePerPerson: pricePerPerson ?? this.pricePerPerson,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geohash: geohash ?? this.geohash,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      status: status ?? this.status,
      participants: participants ?? this.participants,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

// ============ CATEGORY CONSTANTS ============

class RequestCategories {
  static const String groceries = 'groceries';
  static const String fresh = 'fresh';
  static const String snacks = 'snacks';
  static const String household = 'household';
  static const String personal = 'personal';
  static const String babyPets = 'baby_pets';
  static const String electronics = 'electronics';
  static const String others = 'others';

  static const Map<String, String> labels = {
    groceries: 'Groceries',
    fresh: 'Fresh Foods',
    snacks: 'Snacks & Drinks',
    household: 'Household',
    personal: 'Personal Care',
    babyPets: 'Baby & Pets',
    electronics: 'Electronics',
    others: 'Others',
  };

  static const Map<String, String> icons = {
    groceries: 'assets/icons/CateFoodBeve.png',
    fresh: 'assets/icons/CateFresh.png',
    snacks: 'assets/icons/CateSnacks.png',
    household: 'assets/icons/CateHousehold.png',
    personal: 'assets/icons/CateBeuty.png',
    babyPets: 'assets/icons/CateBabyPet.png',
    electronics: 'assets/icons/CateElectro.png',
    others: 'assets/icons/CateOthers.png',
  };

  static const Map<String, double> iconSizes = {
    groceries: 24,
    fresh: 24,
    snacks: 24,
    household: 24,
    personal: 24,
    babyPets: 24,
    electronics: 18,
    others: 18,
  };

  static List<String> get all => [
    groceries,
    fresh,
    snacks,
    household,
    personal,
    babyPets,
    electronics,
    others,
  ];

  /// Maps new keys to the set of Firestore values they should match.
  /// Used for server-side queries where old docs still carry 'food'.
  static const Map<String, List<String>> queryAliases = {
    groceries: [groceries, 'food'],
  };

  /// Normalize legacy category keys read from Firestore.
  static String normalizeCategory(String category) {
    if (category == 'food') return groceries;
    return category;
  }
}
