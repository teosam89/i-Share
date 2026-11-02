/// JoinRequest Model - Represents a pending request to join a co-request
library;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/join_status.dart';

/// JoinRequest - A user's request to join a co-request (pending host approval)
class JoinRequest {
  final String id;
  final String requestId; // CoRequest ID
  final String requestProductName; // For display purposes
  
  // Requester info
  final String requesterId;
  final String requesterName;
  final String? requesterPhotoUrl;
  
  // Host info (initiator who approves)
  final String hostId;
  final String hostName;
  
  // Status
  final String status; // pending, accepted, rejected, cancelled
  
  // Optional message from requester
  final String? message;
  
  // Timestamps
  final DateTime createdAt;
  final DateTime? respondedAt;

  JoinRequest({
    required this.id,
    required this.requestId,
    required this.requestProductName,
    required this.requesterId,
    required this.requesterName,
    this.requesterPhotoUrl,
    required this.hostId,
    required this.hostName,
    required this.status,
    this.message,
    required this.createdAt,
    this.respondedAt,
  });

  /// Check if this request is pending
  bool get isPending => status == JoinStatus.pending;

  /// Check if this request was accepted
  bool get isAccepted => status == JoinStatus.accepted;

  /// Check if this request was rejected
  bool get isRejected => status == JoinStatus.rejected;

  /// Create from Firestore document
  factory JoinRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JoinRequest(
      id: doc.id,
      requestId: data['requestId'] ?? '',
      requestProductName: data['requestProductName'] ?? 'Unknown Product',
      requesterId: data['requesterId'] ?? '',
      requesterName: data['requesterName'] ?? 'Unknown User',
      requesterPhotoUrl: data['requesterPhotoUrl'],
      hostId: data['hostId'] ?? '',
      hostName: data['hostName'] ?? 'Unknown Host',
      status: data['status'] ?? JoinStatus.pending,
      message: data['message'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'requestId': requestId,
      'requestProductName': requestProductName,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requesterPhotoUrl': requesterPhotoUrl,
      'hostId': hostId,
      'hostName': hostName,
      'status': status,
      'message': message,
      'createdAt': Timestamp.fromDate(createdAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
    };
  }

  /// Create a copy with updated fields
  JoinRequest copyWith({
    String? status,
    DateTime? respondedAt,
  }) {
    return JoinRequest(
      id: id,
      requestId: requestId,
      requestProductName: requestProductName,
      requesterId: requesterId,
      requesterName: requesterName,
      requesterPhotoUrl: requesterPhotoUrl,
      hostId: hostId,
      hostName: hostName,
      status: status ?? this.status,
      message: message,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}
