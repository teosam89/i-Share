import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/remark_model.dart';

/// RemarkService - Manages personal remarks/notes for other users
/// Remarks are stored in users/{currentUserId}/remarks/{targetUserId}
class RemarkService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get the remarks collection reference for current user
  CollectionReference<Map<String, dynamic>> get _remarksRef {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not authenticated');
    }
    return _firestore.collection('profiles').doc(userId).collection('remarks');
  }

  /// Get remark for a specific user
  Future<UserRemark?> getRemark(String targetUserId) async {
    try {
      final doc = await _remarksRef.doc(targetUserId).get();
      if (doc.exists) {
        return UserRemark.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('[RemarkService] Error getting remark: $e');
      return null;
    }
  }

  /// Set or update remark for a user
  Future<bool> setRemark(String targetUserId, String remark) async {
    try {
      final userRemark = UserRemark(
        targetUserId: targetUserId,
        remark: remark.trim(),
        updatedAt: DateTime.now(),
      );
      await _remarksRef.doc(targetUserId).set(userRemark.toFirestore());
      debugPrint('[RemarkService] Remark saved for user: $targetUserId');
      return true;
    } catch (e) {
      debugPrint('[RemarkService] Error saving remark: $e');
      return false;
    }
  }

  /// Delete remark for a user
  Future<bool> deleteRemark(String targetUserId) async {
    try {
      await _remarksRef.doc(targetUserId).delete();
      debugPrint('[RemarkService] Remark deleted for user: $targetUserId');
      return true;
    } catch (e) {
      debugPrint('[RemarkService] Error deleting remark: $e');
      return false;
    }
  }
}
