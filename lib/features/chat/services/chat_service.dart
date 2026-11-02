import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/chat_model.dart';
import '../../../core/constants/app_constants.dart';

/// ChatService - Handles all Firestore operations for chat functionality
class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection references
  CollectionReference get _chatRoomsRef => _firestore.collection(AppConstants.chatRoomsCollection);

  // Cached sender profile — avoids a Firestore read per message send
  Map<String, dynamic>? _cachedProfile;
  String? _cachedProfileUid;

  CollectionReference _messagesRef(String chatRoomId) =>
      _chatRoomsRef.doc(chatRoomId).collection(AppConstants.messagesCollection);

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Get current user's profile from Firestore, caching the result for the
  /// lifetime of the singleton. Cache is invalidated on user switch.
  Future<Map<String, dynamic>?> _getCurrentUserProfile() async {
    if (currentUserId == null) return null;
    if (_cachedProfile != null && _cachedProfileUid == currentUserId) {
      return _cachedProfile;
    }
    try {
      final doc = await _firestore
          .collection(AppConstants.profilesCollection)
          .doc(currentUserId)
          .get();
      if (doc.exists) {
        _cachedProfile = doc.data();
        _cachedProfileUid = currentUserId;
        return _cachedProfile;
      }
    } catch (e) {
      debugPrint('[ChatService] Error fetching user profile: $e');
    }
    return null;
  }

  /// Create or get existing chat room for a request
  Future<ChatRoom> getOrCreateChatRoom({
    required String requestId,
    required String productName,
    required List<String> participantIds,
  }) async {
    try {
      // Check if chat room exists
      // Note: This may fail with permission-denied if user is not yet a participant
      // In that case, we proceed to create the chat room
      bool chatRoomExists = false;
      ChatRoom? existingChatRoom;

      try {
        final doc = await _chatRoomsRef.doc(requestId).get();
        if (doc.exists) {
          debugPrint('[ChatService] Chat room exists: $requestId');
          chatRoomExists = true;
          existingChatRoom = ChatRoom.fromFirestore(doc);
        }
      } catch (e) {
        // Permission denied means the chat room might not exist yet
        // or user is not a participant - proceed to create
        debugPrint('[ChatService] Could not check chat room existence: $e');
      }

      if (chatRoomExists && existingChatRoom != null) {
        return existingChatRoom;
      }

      // Format group name with suffix for better clarity
      final groupName = '$productName Split Group';

      // Create new chat room
      final chatRoom = ChatRoom(
        id: requestId,
        requestId: requestId,
        productName: groupName,
        participantIds: participantIds,
        createdAt: DateTime.now(),
      );

      await _chatRoomsRef.doc(requestId).set(chatRoom.toFirestore());
      debugPrint('[ChatService] Created chat room: $requestId');

      // Add system message
      await sendSystemMessage(
        chatRoomId: requestId,
        content:
            '👋 Welcome! This is the group chat for splitting "$productName".',
      );

      return chatRoom;
    } catch (e) {
      debugPrint('[ChatService] Error creating chat room: $e');
      rethrow;
    }
  }

  /// Add participant to chat room
  Future<void> addParticipant(String chatRoomId, String participantId) async {
    try {
      await _chatRoomsRef.doc(chatRoomId).update({
        'participantIds': FieldValue.arrayUnion([participantId]),
      });
      debugPrint(
        '[ChatService] Added participant $participantId to $chatRoomId',
      );
    } catch (e) {
      debugPrint('[ChatService] Error adding participant: $e');
      rethrow;
    }
  }

  /// Send a text message
  Future<void> sendMessage({
    required String chatRoomId,
    required String content,
  }) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Fetch sender info from Firestore profiles (more reliable than Auth displayName)
      final profile = await _getCurrentUserProfile();
      final senderName =
          profile?['displayName'] ?? _auth.currentUser?.displayName ?? 'User';
      final senderPhotoUrl =
          profile?['photoUrl'] ?? _auth.currentUser?.photoURL;

      final message = ChatMessage(
        id: '',
        chatRoomId: chatRoomId,
        senderId: currentUserId!,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        content: content,
        type: 'text',
        timestamp: DateTime.now(),
      );

      await _messagesRef(chatRoomId).add(message.toFirestore());

      // Update chat room with last message + sender's read timestamp
      await _chatRoomsRef.doc(chatRoomId).update({
        'lastMessage': '$senderName: $content',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastReadAt.$currentUserId': FieldValue.serverTimestamp(),
      });

      debugPrint('[ChatService] Message sent to $chatRoomId by $senderName');
    } catch (e) {
      debugPrint('[ChatService] Error sending message: $e');
      rethrow;
    }
  }

  /// Send a location message
  Future<void> sendLocationMessage({
    required String chatRoomId,
    required double latitude,
    required double longitude,
  }) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    try {
      final profile = await _getCurrentUserProfile();
      final senderName =
          profile?['displayName'] ?? _auth.currentUser?.displayName ?? 'User';
      final senderPhotoUrl =
          profile?['photoUrl'] ?? _auth.currentUser?.photoURL;

      final content = '$latitude,$longitude';
      final message = ChatMessage(
        id: '',
        chatRoomId: chatRoomId,
        senderId: currentUserId!,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        content: content,
        type: 'location',
        timestamp: DateTime.now(),
      );

      await _messagesRef(chatRoomId).add(message.toFirestore());

      await _chatRoomsRef.doc(chatRoomId).update({
        'lastMessage': '$senderName shared a location',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastReadAt.$currentUserId': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ChatService] Error sending location: $e');
      rethrow;
    }
  }

  /// Recall a sent message (soft delete — sets content to recalled text)
  Future<void> recallMessage({
    required String chatRoomId,
    required String messageId,
  }) async {
    if (currentUserId == null) return;

    try {
      await _messagesRef(chatRoomId).doc(messageId).update({
        'content': 'This message was recalled',
        'type': 'recalled',
      });
    } catch (e) {
      debugPrint('[ChatService] Error recalling message: $e');
      rethrow;
    }
  }

  /// Send a system message
  Future<void> sendSystemMessage({
    required String chatRoomId,
    required String content,
  }) async {
    try {
      final message = ChatMessage.system(
        chatRoomId: chatRoomId,
        content: content,
        senderId: currentUserId ?? 'system',
      );

      await _messagesRef(chatRoomId).add(message.toFirestore());

      // Update chat room with last message so it shows in chat list
      await _chatRoomsRef.doc(chatRoomId).update({
        'lastMessage': content,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      debugPrint('[ChatService] System message sent: $content');
    } catch (e) {
      debugPrint('[ChatService] Error sending system message: $e');
    }
  }

  /// Send an image message
  Future<void> sendImageMessage({
    required String chatRoomId,
    required String imagePath,
  }) async {
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    try {
      // Fetch sender info from Firestore profiles
      final profile = await _getCurrentUserProfile();
      final senderName =
          profile?['displayName'] ?? _auth.currentUser?.displayName ?? 'User';
      final senderPhotoUrl =
          profile?['photoUrl'] ?? _auth.currentUser?.photoURL;

      // Upload image to Firebase Storage
      final file = File(imagePath);

      // Guard: reject if still > 8 MB after client-side compression
      final sizeBytes = await file.length();
      if (sizeBytes > 8 * 1024 * 1024) {
        throw Exception('Image is too large. Please choose a smaller photo.');
      }

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_$currentUserId.jpg';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('chat_images')
          .child(chatRoomId)
          .child(fileName);

      final uploadTask = await storageRef.putFile(file);
      final imageUrl = await uploadTask.ref.getDownloadURL();

      // Create image message
      final message = ChatMessage(
        id: '',
        chatRoomId: chatRoomId,
        senderId: currentUserId!,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        content: imageUrl,
        type: 'image',
        timestamp: DateTime.now(),
      );

      await _messagesRef(chatRoomId).add(message.toFirestore());

      // Update chat room with last message + sender's read timestamp
      await _chatRoomsRef.doc(chatRoomId).update({
        'lastMessage': '$senderName: 📷 Photo',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastReadAt.$currentUserId': FieldValue.serverTimestamp(),
      });

      debugPrint('[ChatService] Image sent to $chatRoomId');
    } catch (e) {
      debugPrint('[ChatService] Error sending image: $e');
      rethrow;
    }
  }

  /// Get real-time stream of messages for a chat room (paginated)
  /// [limit] - Maximum number of recent messages to load (default: 50)
  /// Returns messages in descending order (newest first) for use with
  /// ListView(reverse: true) which renders newest at bottom.
  Stream<List<ChatMessage>> getMessagesStream(
    String chatRoomId, {
    int limit = 50,
  }) {
    return _messagesRef(chatRoomId)
        .orderBy('timestamp', descending: true)
        .limit(limit) // Pagination: only load recent messages
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ChatMessage.fromFirestore(doc))
              .toList(),
        );
  }

  /// Load older messages before a given timestamp (for infinite scroll)
  Future<List<ChatMessage>> loadOlderMessages(
    String chatRoomId, {
    required DateTime beforeTimestamp,
    int limit = 30,
  }) async {
    final snapshot = await _messagesRef(chatRoomId)
        .orderBy('timestamp', descending: true)
        .where('timestamp', isLessThan: Timestamp.fromDate(beforeTimestamp))
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => ChatMessage.fromFirestore(doc))
        .toList()
        .reversed
        .toList();
  }

  /// Get chat rooms for current user (excludes hidden ones)
  Stream<List<ChatRoom>> getUserChatRooms() {
    if (currentUserId == null) return Stream.value([]);

    return _chatRoomsRef
        .where('participantIds', arrayContains: currentUserId)
        .snapshots()
        .map((snapshot) {
          final rooms = snapshot.docs
              .map((doc) => ChatRoom.fromFirestore(doc))
              .where((room) => !room.hiddenBy.contains(currentUserId))
              .toList();
          // Sort on client side to avoid composite index
          rooms.sort((a, b) {
            final aTime = a.lastMessageAt ?? a.createdAt;
            final bTime = b.lastMessageAt ?? b.createdAt;
            return bTime.compareTo(aTime); // descending
          });
          return rooms;
        });
  }

  /// Check if chat room exists for a request
  Future<bool> chatRoomExists(String requestId) async {
    final doc = await _chatRoomsRef.doc(requestId).get();
    return doc.exists;
  }

  /// Mark chat room as read for the current user
  /// Updates only the per-user lastReadAt timestamp (single write)
  Future<void> markAsRead(String chatRoomId) async {
    if (currentUserId == null) return;

    try {
      await _chatRoomsRef.doc(chatRoomId).update({
        'lastReadAt.$currentUserId': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ChatService] Error marking as read: $e');
    }
  }

  /// Mark individual messages as read in a chat room.
  /// Only marks messages sent by OTHER users (not your own).
  Future<void> markMessagesAsRead(String chatRoomId) async {
    if (currentUserId == null) return;

    try {
      final snapshot = await _messagesRef(chatRoomId)
          .where('isRead', isEqualTo: false)
          .where('senderId', isNotEqualTo: currentUserId)
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[ChatService] Error marking messages as read: $e');
    }
  }

  /// Delete chat room (for cleanup when request is deleted)
  Future<void> deleteChatRoom(String chatRoomId) async {
    try {
      // Delete all messages first
      final messages = await _messagesRef(chatRoomId).get();
      final batch = _firestore.batch();

      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(_chatRoomsRef.doc(chatRoomId));
      await batch.commit();

      debugPrint('[ChatService] Deleted chat room: $chatRoomId');
    } catch (e) {
      debugPrint('[ChatService] Error deleting chat room: $e');
    }
  }

  /// Create or get existing DM chat room between two users
  Future<String> getOrCreateDmChatRoom(String userId1, String userId2) async {
    // Create consistent chat room ID by sorting user IDs
    final sortedIds = [userId1, userId2]..sort();
    final chatRoomId = 'dm_${sortedIds[0]}_${sortedIds[1]}';

    try {
      final doc = await _chatRoomsRef.doc(chatRoomId).get();

      if (doc.exists) {
        debugPrint('[ChatService] DM chat room exists: $chatRoomId');
        return chatRoomId;
      }

      // Create new DM chat room
      final chatRoom = ChatRoom(
        id: chatRoomId,
        requestId: '', // No request for DM
        productName: 'Direct Message', // Will be replaced with user name in UI
        participantIds: [userId1, userId2],
        createdAt: DateTime.now(),
      );

      await _chatRoomsRef.doc(chatRoomId).set(chatRoom.toFirestore());
      debugPrint('[ChatService] Created DM chat room: $chatRoomId');

      // Add welcome system message
      await sendSystemMessage(
        chatRoomId: chatRoomId,
        content: '👋 You can now start messaging!',
      );

      return chatRoomId;
    } catch (e) {
      debugPrint('[ChatService] Error creating DM chat room: $e');
      rethrow;
    }
  }

  /// Toggle mute status for the current user on a chat room
  /// Returns the new mute state (true = now muted, false = now unmuted)
  Future<bool> toggleMute(String chatRoomId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      final doc = await _chatRoomsRef.doc(chatRoomId).get();
      final data = doc.data() as Map<String, dynamic>?;
      final mutedBy = List<String>.from(data?['mutedBy'] ?? []);
      final isMuted = mutedBy.contains(userId);

      if (isMuted) {
        await _chatRoomsRef.doc(chatRoomId).update({
          'mutedBy': FieldValue.arrayRemove([userId]),
        });
        debugPrint('[ChatService] Unmuted $chatRoomId for $userId');
        return false;
      } else {
        await _chatRoomsRef.doc(chatRoomId).update({
          'mutedBy': FieldValue.arrayUnion([userId]),
        });
        debugPrint('[ChatService] Muted $chatRoomId for $userId');
        return true;
      }
    } catch (e) {
      debugPrint('[ChatService] Error toggling mute: $e');
      rethrow;
    }
  }

  /// Check if current user has muted a chat room
  Future<bool> isChatMuted(String chatRoomId) async {
    final userId = currentUserId;
    if (userId == null) return false;

    try {
      final doc = await _chatRoomsRef.doc(chatRoomId).get();
      final data = doc.data() as Map<String, dynamic>?;
      final mutedBy = List<String>.from(data?['mutedBy'] ?? []);
      return mutedBy.contains(userId);
    } catch (e) {
      return false;
    }
  }
}
