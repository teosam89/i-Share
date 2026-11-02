import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Report reasons enum
enum ReportReason { spam, fraud, harassment, inappropriate, other }

/// Report service for handling user reports
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _reportsRef => _firestore.collection('reports');

  String? get currentUserId => _auth.currentUser?.uid;

  /// Get display text for report reason
  static String getReasonText(ReportReason reason) {
    switch (reason) {
      case ReportReason.spam:
        return 'Spam / Advertising';
      case ReportReason.fraud:
        return 'Fraud / Scam';
      case ReportReason.harassment:
        return 'Harassment / Abuse';
      case ReportReason.inappropriate:
        return 'Inappropriate Content';
      case ReportReason.other:
        return 'Other';
    }
  }

  /// Submit a report against a user
  Future<bool> submitReport({
    required String reportedUserId,
    required ReportReason reason,
    String? requestId,
    String? description,
  }) async {
    if (currentUserId == null) return false;
    if (currentUserId == reportedUserId) {
      debugPrint('[ReportService] Cannot report yourself');
      return false;
    }

    try {
      // Check if already reported this user recently (within 24h)
      final recentReport = await _reportsRef
          .where('reporterId', isEqualTo: currentUserId)
          .where('reportedUserId', isEqualTo: reportedUserId)
          .where(
            'createdAt',
            isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(hours: 24)),
            ),
          )
          .limit(1)
          .get();

      if (recentReport.docs.isNotEmpty) {
        debugPrint('[ReportService] Already reported this user recently');
        return false;
      }

      await _reportsRef.add({
        'reporterId': currentUserId,
        'reportedUserId': reportedUserId,
        'requestId': requestId,
        'reason': reason.name,
        'description': description,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[ReportService] Report submitted successfully');
      return true;
    } catch (e) {
      debugPrint('[ReportService] Error submitting report: $e');
      return false;
    }
  }

  /// Check if current user has reported a specific user
  Future<bool> hasReportedUser(String userId) async {
    if (currentUserId == null) return false;

    try {
      final report = await _reportsRef
          .where('reporterId', isEqualTo: currentUserId)
          .where('reportedUserId', isEqualTo: userId)
          .limit(1)
          .get();

      return report.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
