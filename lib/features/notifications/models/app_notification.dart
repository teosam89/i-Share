import 'package:cloud_firestore/cloud_firestore.dart';

/// In-app notification model — fallback for when push notifications are disabled.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type; // 'join_request', 'match_found', 'qr_ready', 'general'
  final String? referenceId; // related request/match ID
  final DateTime createdAt;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.type = 'general',
    this.referenceId,
    required this.createdAt,
    this.isRead = false,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: data['type'] ?? 'general',
      referenceId: data['referenceId'],
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'body': body,
      'type': type,
      'referenceId': referenceId,
      'createdAt': Timestamp.fromDate(createdAt),
      'isRead': isRead,
    };
  }
}
