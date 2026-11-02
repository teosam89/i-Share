import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// QR Verification Service - Handles QR code generation and verification
/// for request completion confirmation
class QrVerificationService {
  static final QrVerificationService _instance =
      QrVerificationService._internal();
  factory QrVerificationService() => _instance;
  QrVerificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _verificationsRef =>
      _firestore.collection('qr_verifications');

  /// Generate a unique QR code for a request
  /// Returns the QR data string and stores verification state in Firestore
  /// If a valid (non-expired) session already exists, reuses it to preserve
  /// previously verified participants.
  Future<String> generateQrCode({
    required String requestId,
    required List<String> participantIds,
    required String
    ownerId, // SECURITY: Store owner ID to prevent self-verification
  }) async {
    try {
      // Check if a valid verification session already exists
      final existingDoc = await _verificationsRef.doc(requestId).get();
      if (existingDoc.exists) {
        final data = existingDoc.data() as Map<String, dynamic>;
        final expiresAt = data['expiresAt'] as Timestamp?;

        // Reuse existing session if not expired
        if (expiresAt != null && expiresAt.toDate().isAfter(DateTime.now())) {
          final existingSecret = data['secret'] as String;
          final createdAt = data['createdAt'] as Timestamp?;

          debugPrint(
            '[QrVerificationService] Reusing existing QR session for: $requestId '
            '(verified: ${(data['verifiedIds'] as List?)?.length ?? 0})',
          );

          return jsonEncode({
            'requestId': requestId,
            'secret': existingSecret,
            'timestamp':
                createdAt?.millisecondsSinceEpoch ??
                DateTime.now().millisecondsSinceEpoch,
          });
        }
      }

      // Generate new session (no existing or expired)
      final random = Random.secure();
      final secret = List.generate(
        16,
        (_) => random.nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final qrData = {
        'requestId': requestId,
        'secret': secret,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // Store verification state
      await _verificationsRef.doc(requestId).set({
        'secret': secret,
        'participantIds': participantIds,
        'ownerId': ownerId, // SECURITY: Store owner to block self-verification
        'verifiedIds': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      });

      debugPrint(
        '[QrVerificationService] Generated new QR for request: $requestId',
      );
      return jsonEncode(qrData);
    } catch (e) {
      debugPrint('[QrVerificationService] Error generating QR: $e');
      rethrow;
    }
  }

  /// Verify a participant by scanning QR code
  /// Returns true if verification successful
  Future<VerificationResult> verifyParticipant({
    required String qrData,
    required String participantId,
  }) async {
    try {
      final data = jsonDecode(qrData) as Map<String, dynamic>;
      final requestId = data['requestId'] as String;
      final secret = data['secret'] as String;

      // Get verification document
      final doc = await _verificationsRef.doc(requestId).get();
      if (!doc.exists) {
        return VerificationResult(
          success: false,
          message: 'Verification session not found',
        );
      }

      final docData = doc.data() as Map<String, dynamic>;
      final storedSecret = docData['secret'] as String;
      final participantIds = List<String>.from(docData['participantIds'] ?? []);
      final verifiedIds = List<String>.from(docData['verifiedIds'] ?? []);
      final ownerId = docData['ownerId'] as String?;

      // SECURITY: Check if user is the owner (owner cannot verify themselves)
      if (ownerId != null && participantId == ownerId) {
        return VerificationResult(
          success: false,
          message: 'Host cannot verify themselves. Only participants can scan.',
        );
      }

      // Check if expired
      final expiresAt = docData['expiresAt'];
      if (expiresAt != null) {
        final expiryTime = expiresAt is Timestamp
            ? expiresAt.toDate()
            : DateTime.parse(expiresAt.toString());
        if (DateTime.now().isAfter(expiryTime)) {
          return VerificationResult(
            success: false,
            message: 'QR code has expired. Please generate a new one.',
          );
        }
      }

      // Validate secret
      if (secret != storedSecret) {
        return VerificationResult(success: false, message: 'Invalid QR code');
      }

      // Check if participant is in the stored list
      if (!participantIds.contains(participantId)) {
        return VerificationResult(
          success: false,
          message: 'You are not a participant of this request',
        );
      }

      // SECURITY: Real-time check against co_requests doc to catch
      // participants who left AFTER the QR session was created
      final requestDoc = await _firestore
          .collection('co_requests')
          .doc(requestId)
          .get();
      if (requestDoc.exists) {
        final currentParticipants = List<String>.from(
          requestDoc.data()?['participants'] ?? [],
        );
        if (!currentParticipants.contains(participantId)) {
          return VerificationResult(
            success: false,
            message: 'You are no longer a participant of this request',
          );
        }
      }

      // Check if already verified
      if (verifiedIds.contains(participantId)) {
        return VerificationResult(
          success: true,
          message: 'Already verified',
          alreadyVerified: true,
        );
      }

      // Add to verified list
      await _verificationsRef.doc(requestId).update({
        'verifiedIds': FieldValue.arrayUnion([participantId]),
      });

      debugPrint(
        '[QrVerificationService] Verified participant: $participantId',
      );
      return VerificationResult(
        success: true,
        message: 'Verification successful!',
      );
    } catch (e) {
      debugPrint('[QrVerificationService] Error verifying: $e');
      return VerificationResult(success: false, message: 'Error: $e');
    }
  }

  /// Get real-time verification status
  Stream<VerificationStatus> getVerificationStatus(String requestId) {
    return _verificationsRef.doc(requestId).snapshots().map((doc) {
      if (!doc.exists) {
        return VerificationStatus(
          participantIds: [],
          verifiedIds: [],
          isComplete: false,
        );
      }

      final data = doc.data() as Map<String, dynamic>;
      final participantIds = List<String>.from(data['participantIds'] ?? []);
      final verifiedIds = List<String>.from(data['verifiedIds'] ?? []);

      return VerificationStatus(
        participantIds: participantIds,
        verifiedIds: verifiedIds,
        isComplete:
            participantIds.length == verifiedIds.length &&
            participantIds.isNotEmpty,
      );
    });
  }

  /// Check if all participants verified
  Future<bool> isAllVerified(String requestId) async {
    final doc = await _verificationsRef.doc(requestId).get();
    if (!doc.exists) return false;

    final data = doc.data() as Map<String, dynamic>;
    final participantIds = List<String>.from(data['participantIds'] ?? []);
    final verifiedIds = List<String>.from(data['verifiedIds'] ?? []);

    return participantIds.length == verifiedIds.length &&
        participantIds.isNotEmpty;
  }

  /// Clean up verification data after completion
  Future<void> cleanUpVerification(String requestId) async {
    try {
      await _verificationsRef.doc(requestId).delete();
      debugPrint('[QrVerificationService] Cleaned up verification: $requestId');
    } catch (e) {
      debugPrint('[QrVerificationService] Error cleaning up: $e');
    }
  }
}

/// Result of a verification attempt
class VerificationResult {
  final bool success;
  final String message;
  final bool alreadyVerified;

  VerificationResult({
    required this.success,
    required this.message,
    this.alreadyVerified = false,
  });
}

/// Status of verification for a request
class VerificationStatus {
  final List<String> participantIds;
  final List<String> verifiedIds;
  final bool isComplete;

  VerificationStatus({
    required this.participantIds,
    required this.verifiedIds,
    required this.isComplete,
  });

  int get totalCount => participantIds.length;
  int get verifiedCount => verifiedIds.length;
}
