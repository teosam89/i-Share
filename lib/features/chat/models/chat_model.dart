import 'package:cloud_firestore/cloud_firestore.dart';

/// Chat Room Model - Represents a chat room for a co-request or DM
class ChatRoom {
  final String
  id; // Same as requestId for group chats, dm_{user1}_{user2} for DMs
  final String? requestId; // null for DMs
  final String productName; // For DMs, this is the other person's name
  final List<String> participantIds;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final String? lastMessage;
  final bool isDM; // true for direct messages, false for group chats
  final Map<String, DateTime> lastReadAt; // Per-user read timestamps
  final List<String> mutedBy; // UIDs of users who muted this chat
  final List<String> hiddenBy; // UIDs of users who hid this chat from their list

  ChatRoom({
    required this.id,
    this.requestId,
    required this.productName,
    required this.participantIds,
    required this.createdAt,
    this.lastMessageAt,
    this.lastMessage,
    this.isDM = false,
    this.lastReadAt = const {},
    this.mutedBy = const [],
    this.hiddenBy = const [],
  });

  /// Check if this chat room has unread messages for the given user
  bool hasUnread(String userId) {
    if (lastMessageAt == null) return false;
    final userLastRead = lastReadAt[userId];
    if (userLastRead == null) return true; // Never read = unread
    return lastMessageAt!.isAfter(userLastRead);
  }

  /// Check if this chat is muted by the given user
  bool isMutedBy(String userId) => mutedBy.contains(userId);

  factory ChatRoom.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse lastReadAt map: { "userId": Timestamp, ... }
    final rawLastReadAt = data['lastReadAt'] as Map<String, dynamic>? ?? {};
    final parsedLastReadAt = rawLastReadAt.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate());
      }
      return MapEntry(key, DateTime.now());
    });

    return ChatRoom(
      id: doc.id,
      requestId: data['requestId'],
      productName: data['productName'] ?? 'Unknown Product',
      participantIds: List<String>.from(data['participantIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessage: data['lastMessage'],
      isDM: data['isDM'] ?? false,
      lastReadAt: parsedLastReadAt,
      mutedBy: List<String>.from(data['mutedBy'] ?? []),
      hiddenBy: List<String>.from(data['hiddenBy'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'requestId': requestId,
      'productName': productName,
      'participantIds': participantIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastMessageAt': lastMessageAt != null
          ? Timestamp.fromDate(lastMessageAt!)
          : null,
      'lastMessage': lastMessage,
      'isDM': isDM,
      'lastReadAt': lastReadAt.map(
        (key, value) => MapEntry(key, Timestamp.fromDate(value)),
      ),
      'mutedBy': mutedBy,
      'hiddenBy': hiddenBy,
    };
  }

  /// Get the other user's ID for DM chats
  String? getOtherUserId(String currentUserId) {
    if ((!isDM && !id.startsWith('dm_')) || participantIds.length != 2) {
      return null;
    }
    return participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
  }
}

/// Chat Message Model - Individual message in a chat room
class ChatMessage {
  final String id;
  final String chatRoomId;
  final String senderId;
  final String senderName;
  final String? senderPhotoUrl;
  final String content;
  final String type; // text, image, system
  final DateTime timestamp;
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl,
    required this.content,
    this.type = 'text',
    required this.timestamp,
    this.isRead = false,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      chatRoomId: data['chatRoomId'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderPhotoUrl: data['senderPhotoUrl'],
      content: data['content'] ?? '',
      type: data['type'] ?? 'text',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRead: data['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'chatRoomId': chatRoomId,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'content': content,
      'type': type,
      'timestamp': Timestamp.fromDate(timestamp),
      'isRead': isRead,
    };
  }

  /// Check if this message is from the current user
  bool isFromUser(String currentUserId) => senderId == currentUserId;

  /// Create a system message (e.g., "User joined the chat")
  /// senderId must be the current user's UID to pass Firestore rules.
  /// The message is still rendered as a system message via type='system'.
  static ChatMessage system({
    required String chatRoomId,
    required String content,
    required String senderId,
  }) {
    return ChatMessage(
      id: '',
      chatRoomId: chatRoomId,
      senderId: senderId,
      senderName: 'System',
      content: content,
      type: 'system',
      timestamp: DateTime.now(),
    );
  }
}
