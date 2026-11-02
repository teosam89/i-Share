import 'package:cloud_firestore/cloud_firestore.dart';

/// UserRemark - Personal remark/note for another user (only visible to owner)
class UserRemark {
  final String targetUserId;
  final String remark;
  final DateTime updatedAt;

  UserRemark({
    required this.targetUserId,
    required this.remark,
    required this.updatedAt,
  });

  factory UserRemark.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserRemark(
      targetUserId: doc.id,
      remark: data['remark'] ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {'remark': remark, 'updatedAt': Timestamp.fromDate(updatedAt)};
  }
}
