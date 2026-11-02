import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import 'chat_location_share_screen.dart';
import '../models/chat_model.dart';
import '../services/chat_service.dart';
import '../../profile/screens/profile_screen.dart';
import '../../profile/services/remark_service.dart';
import '../../realtime_match/screens/realtime_match_detail_screen.dart';
import '../../shared/widgets/user_avatar.dart';

/// ChatScreen - Real-time chat interface for request participants
class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String productName;
  final VoidCallback? onViewRequest;

  const ChatScreen({
    super.key,
    required this.chatRoomId,
    required this.productName,
    this.onViewRequest,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();
  late final Stream<List<ChatMessage>> _messagesStream;
  bool _isSending = false;
  bool _isChatLocked = false;
  bool _isMuted = false; // Whether current user has muted this chat
  String? _lockReason;
  String? _pendingImagePath; // Staged image to preview before sending
  StreamSubscription? _accessSubscription;
  String? _dmOtherUserName; // Resolved display name for DM chats

  @override
  void initState() {
    super.initState();
    _messagesStream = _chatService.getMessagesStream(widget.chatRoomId);
    // Mark chat as read when entering
    _chatService.markAsRead(widget.chatRoomId);
    _chatService.markMessagesAsRead(widget.chatRoomId);
    // Check if chat is locked (request completed/cancelled)
    _checkChatLockStatus();
    // Listen for access changes (user removed from chat)
    _listenForAccessChanges();
    // Resolve other user's name for DM chats
    if (widget.chatRoomId.startsWith('dm_')) {
      _resolveOtherUserName();
    }
    // Load mute state
    _loadMuteState();
  }

  /// Listen for changes to chat room access - exit if user is removed
  void _listenForAccessChanges() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    _accessSubscription = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.chatRoomId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            if (!snapshot.exists) {
              // Chat room deleted
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chat room no longer exists')),
              );
              return;
            }

            final participantIds = List<String>.from(
              snapshot.data()?['participantIds'] ?? [],
            );
            if (!participantIds.contains(userId)) {
              // User was removed from chat
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You no longer have access to this chat'),
                ),
              );
            }
          },
          onError: (error) {
            // Permission denied after leaving — gracefully exit
            if (!mounted) return;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You no longer have access to this chat'),
              ),
            );
          },
        );
  }

  Future<void> _checkChatLockStatus() async {
    try {
      // Check Co-Buy request status
      if (!widget.chatRoomId.startsWith('rtm_') &&
          !widget.chatRoomId.startsWith('dm_')) {
        final doc = await FirebaseFirestore.instance
            .collection('co_requests')
            .doc(widget.chatRoomId)
            .get();

        if (doc.exists && mounted) {
          final status = doc.data()?['status'] as String?;
          if (status == 'completed' || status == 'cancelled') {
            setState(() {
              _isChatLocked = true;
              _lockReason = status == 'completed'
                  ? 'This split has been completed'
                  : 'This split has been cancelled';
            });
          }
        }
      }

      // Check RTM match status for rtm_ prefixed chat rooms
      if (widget.chatRoomId.startsWith('rtm_')) {
        final matchId = widget.chatRoomId.replaceFirst('rtm_', '');
        final matchDoc = await FirebaseFirestore.instance
            .collection('realtime_matches')
            .doc(matchId)
            .get();

        if (matchDoc.exists && mounted) {
          final status = matchDoc.data()?['status'] as String?;
          if (status == 'closed') {
            setState(() {
              _isChatLocked = true;
              _lockReason = 'This match has been closed';
            });
          }
        } else if (!matchDoc.exists && mounted) {
          // Match was deleted (expired/all left)
          setState(() {
            _isChatLocked = true;
            _lockReason = 'This match no longer exists';
          });
        }
      }
    } catch (e) {
      debugPrint('[ChatScreen] Error checking lock status: $e');
    }
  }

  @override
  void dispose() {
    _accessSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    // Fire-and-forget: mark as read on exit so messages received while viewing
    // don't appear as unread after the user navigates away.
    _chatService.markAsRead(widget.chatRoomId);
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // For reversed ListView, "bottom" is at minScrollExtent (0)
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    // P0 Fix: Limit message length to prevent spam
    const maxLength = 500;
    if (content.length > maxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message too long. Max $maxLength characters.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await _chatService.sendMessage(
        chatRoomId: widget.chatRoomId,
        content: content,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message. Please try again.')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  /// Show attachment options: Camera, Gallery, Share Location
  void _showAttachmentSheet() {
    if (_isSending || _isChatLocked) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.location_on_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Share Location'),
              onTap: () {
                Navigator.pop(ctx);
                _showLocationShareScreen();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Navigate to location share screen; send result as a location message
  Future<void> _showLocationShareScreen() async {
    if (_isSending || _isChatLocked) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ChatLocationShareScreen(),
      ),
    );

    if (result == null || !mounted) return;

    setState(() => _isSending = true);
    try {
      await _chatService.sendLocationMessage(
        chatRoomId: widget.chatRoomId,
        latitude: result['latitude'] as double,
        longitude: result['longitude'] as double,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share location.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Pick an image from the given source and stage it for preview
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image == null) return;

      setState(() {
        _pendingImagePath = image.path;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not select image. Please try again.')));
      }
    }
  }

  /// Recall a sent message (within 2 minutes)
  void _showRecallDialog(ChatMessage message) {
    final isMe = message.isFromUser(_chatService.currentUserId ?? '');
    if (!isMe || message.type == 'system' || message.type == 'recalled') return;

    final age = DateTime.now().difference(message.timestamp);
    if (age.inMinutes > 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Messages can only be recalled within 2 minutes.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recall Message'),
        content: const Text('This message will be replaced with "This message was recalled" for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _chatService.recallMessage(
                  chatRoomId: widget.chatRoomId,
                  messageId: message.id,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to recall message.')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Recall'),
          ),
        ],
      ),
    );
  }

  /// Cancel the staged image
  void _cancelPendingImage() {
    setState(() {
      _pendingImagePath = null;
    });
  }

  /// Send the staged image
  Future<void> _sendPendingImage() async {
    if (_pendingImagePath == null || _isSending) return;

    final imagePath = _pendingImagePath!;
    setState(() {
      _isSending = true;
      _pendingImagePath = null;
    });

    try {
      await _chatService.sendImageMessage(
        chatRoomId: widget.chatRoomId,
        imagePath: imagePath,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  /// Show image in fullscreen dialog
  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: InteractiveViewer(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.error,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show chat room info - participants and linked request (or DM info or RTM info)
  Future<void> _showChatInfo() async {
    // Check if this is a DM chat room
    if (widget.chatRoomId.startsWith('dm_')) {
      return _showDmChatInfo();
    }

    // Check if this is a Real-Time Match chat room
    if (widget.chatRoomId.startsWith('rtm_')) {
      return _showRtmChatInfo();
    }

    // Fetch request and chat room data
    final requestDoc = await FirebaseFirestore.instance
        .collection('co_requests')
        .doc(widget.chatRoomId)
        .get();

    final chatRoomDoc = await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(widget.chatRoomId)
        .get();

    if (!mounted) return;

    final requestData = requestDoc.data();
    final chatRoomData = chatRoomDoc.data();
    final participantIds = List<String>.from(
      chatRoomData?['participantIds'] ?? [],
    );

    // Fetch participant profiles
    final participantProfiles = <Map<String, dynamic>>[];
    for (final id in participantIds) {
      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(id)
          .get();
      if (profileDoc.exists) {
        participantProfiles.add({'id': id, ...profileDoc.data()!});
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Product name
                Text(
                  widget.productName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${requestData?['status'] ?? 'Unknown'}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),

                // Participants section
                Text(
                  'Participants (${participantProfiles.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ...participantProfiles.map(
                  (profile) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(ctx); // Close bottom sheet
                      final currentUserId =
                          FirebaseAuth.instance.currentUser?.uid;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            userId: profile['id'],
                            isCurrentUser: profile['id'] == currentUserId,
                          ),
                        ),
                      );
                    },
                    leading: UserAvatar(
                      photoUrl: profile['photoUrl'] as String?,
                      name: profile['displayName'] as String? ?? 'U',
                    ),
                    title: Text(profile['displayName'] ?? 'User'),
                    subtitle: profile['id'] == requestData?['initiatorId']
                        ? Text(
                            'Host',
                            style: TextStyle(color: AppColors.primary),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${(profile['rating'] ?? 0.0).toStringAsFixed(1)}',
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // View request button — only shown when caller provides callback
                if (widget.onViewRequest != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onViewRequest!();
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('View Request Details'),
                    ),
                  ),

                // Delete chat button - only for completed/cancelled
                if (requestData?['status'] == 'completed' ||
                    requestData?['status'] == 'cancelled') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _confirmDeleteChat();
                      },
                      icon: Icon(Icons.delete_outline, color: AppColors.error),
                      label: Text(
                        'Delete Chat',
                        style: TextStyle(color: AppColors.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.error),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Show DM chat info - other user's profile and personal remark
  Future<void> _showDmChatInfo() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Extract other user ID from DM room ID (format: dm_userId1_userId2)
    final parts = widget.chatRoomId.split('_');
    if (parts.length != 3) return;

    final otherUserId = parts[1] == currentUserId ? parts[2] : parts[1];

    // Fetch other user's profile
    final profileDoc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(otherUserId)
        .get();

    if (!mounted) return;

    final profile = profileDoc.data() ?? {};
    final displayName = profile['displayName'] ?? 'User';
    final photoUrl = profile['photoUrl'];
    final rating = (profile['rating'] ?? 0.0).toDouble();

    // Fetch current remark
    final remarkService = RemarkService();
    final existingRemark = await remarkService.getRemark(otherUserId);

    if (!mounted) return;

    final remarkController = TextEditingController(
      text: existingRemark?.remark ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // User profile section
            Row(
              children: [
                UserAvatar(photoUrl: photoUrl, name: displayName, radius: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Remark section
            Text(
              'Remark (only visible to you)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: remarkController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Add a personal note...',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final remark = remarkController.text.trim();
                  if (remark.isEmpty) {
                    await remarkService.deleteRemark(otherUserId);
                  } else {
                    await remarkService.setRemark(otherUserId, remark);
                  }
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Remark saved')),
                    );
                  }
                },
                child: const Text('Save Remark'),
              ),
            ),
            const SizedBox(height: 16),

            // View profile button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        userId: otherUserId,
                        isCurrentUser: false,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.person_outline),
                label: const Text('View Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show Real-Time Match chat info - navigates to dedicated RTM detail screen
  Future<void> _showRtmChatInfo() async {
    // Extract match ID from chat room ID (format: rtm_matchId)
    final matchId = widget.chatRoomId.replaceFirst('rtm_', '');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RealtimeMatchDetailScreen(matchId: matchId),
      ),
    );
  }

  /// Confirm and delete chat (hide from user's chat list)
  /// This only hides the chat, not leave the group. Only available for completed requests.
  Future<void> _confirmDeleteChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat'),
        content: Text(
          _isChatLocked
              ? 'Are you sure you want to delete this chat? '
                    'This will permanently remove it from your chat list.'
              : 'Are you sure you want to delete this chat? '
                    'This will remove it from your chat list. '
                    'You can rejoin the request to see the chat again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        // Cancel access subscription to prevent issues
        await _accessSubscription?.cancel();
        _accessSubscription = null;

        // Add user to hiddenBy array (hides chat without leaving group)
        final userId = _chatService.currentUserId;
        if (userId != null) {
          await FirebaseFirestore.instance
              .collection('chat_rooms')
              .doc(widget.chatRoomId)
              .update({
                'hiddenBy': FieldValue.arrayUnion([userId]),
              });
        }

        if (mounted) {
          Navigator.pop(context); // Go back to previous screen
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat removed from your list')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not delete chat. Please try again.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  /// Resolve the other user's display name for DM chats.
  /// Parses the other UID directly from the room ID (dm_uid1_uid2) to
  /// avoid a redundant chat_room document read.
  Future<void> _resolveOtherUserName() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Format: dm_{uid1}_{uid2} — Firebase UIDs are alphanumeric, no underscores
      final parts = widget.chatRoomId.split('_');
      if (parts.length != 3) return;

      final otherUserId = parts[1] == currentUserId ? parts[2] : parts[1];
      if (otherUserId.isEmpty) return;

      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(otherUserId)
          .get();
      if (profileDoc.exists && mounted) {
        setState(() {
          _dmOtherUserName = profileDoc.data()?['displayName'];
        });
      }
    } catch (_) {
      // Fallback to productName if resolution fails
    }
  }

  /// Load the current mute state for this chat
  Future<void> _loadMuteState() async {
    final muted = await _chatService.isChatMuted(widget.chatRoomId);
    if (mounted) {
      setState(() => _isMuted = muted);
    }
  }

  /// Toggle mute/unmute for this chat
  Future<void> _toggleMute() async {
    try {
      final nowMuted = await _chatService.toggleMute(widget.chatRoomId);
      if (mounted) {
        setState(() => _isMuted = nowMuted);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nowMuted
                  ? 'Notifications muted for this chat'
                  : 'Notifications unmuted for this chat',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not change notification settings. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: widget.chatRoomId.startsWith('dm_'),
        title: widget.chatRoomId.startsWith('dm_')
            ? Text(
                _dmOtherUserName ?? widget.productName,
                style: const TextStyle(fontSize: 16),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.productName,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    'Group Chat',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isMuted ? Icons.notifications_off : Icons.notifications_active,
            ),
            tooltip: _isMuted ? 'Unmute' : 'Mute',
            onPressed: _toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showChatInfo,
          ),
        ],
      ),
      body: Column(
        children: [
          // Privacy notice - only show for group chats (co_request, rtm), not DM
          if (!widget.chatRoomId.startsWith('dm_'))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.warning.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This chat is only visible to participants of this split.',
                      style: TextStyle(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Message list
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (_, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  // Capture navigator/messenger synchronously during build,
                  // then defer pop to avoid calling Navigator inside build().
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  Future.microtask(() {
                    nav.pop();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'You no longer have access to this chat',
                        ),
                      ),
                    );
                  });
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.chatRoomId.startsWith('dm_')
                              ? 'Say hi! '
                              : 'Send a message to coordinate your split!',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // With reverse: true, newest messages automatically appear at bottom
                // No need to manually scroll

                return ListView.builder(
                  controller: _scrollController,
                  reverse:
                      true, // Newest messages at bottom (standard chat pattern)
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _buildMessageBubble(message);
                  },
                );
              },
            ),
          ),

          // Image preview (when image is staged)
          _buildImagePreview(),

          // Message input (or locked notice)
          _isChatLocked ? _buildLockedNotice() : _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isSystem = message.type == 'system';
    final isMe = message.isFromUser(_chatService.currentUserId ?? '');

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Text(
              message.content,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: isMe ? () => _showRecallDialog(message) : null,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            UserAvatar(
              photoUrl: message.senderPhotoUrl,
              name: message.senderName,
              radius: 16,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: (message.type == 'image')
                        ? Colors.transparent
                        : (message.type == 'recalled')
                            ? AppColors.surfaceVariant
                            : (isMe ? AppColors.primary : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: (message.type != 'image' && message.type != 'recalled')
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: _buildBubbleContent(message, isMe),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.isRead ? Icons.done_all : Icons.done,
                          size: 14,
                          color: message.isRead
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildBubbleContent(ChatMessage message, bool isMe) {
    if (message.type == 'recalled') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(
              message.content,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }
    if (message.type == 'location') {
      final parts = message.content.split(',');
      final lat = double.tryParse(parts.isNotEmpty ? parts[0] : '');
      final lng = double.tryParse(parts.length > 1 ? parts[1] : '');
      return GestureDetector(
        onTap: (lat != null && lng != null)
            ? () => launchUrl(Uri.parse('https://maps.google.com/?q=$lat,$lng'))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on,
                size: 20,
                color: isMe ? Colors.white : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shared Location',
                      style: TextStyle(
                        color: isMe ? Colors.white : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Tap to open in Maps',
                      style: TextStyle(
                        color: isMe
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (message.type == 'image') {
      return GestureDetector(
        onTap: () => _showFullScreenImage(message.content),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          child: CachedNetworkImage(
            imageUrl: message.content,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 200,
              height: 200,
              color: AppColors.surfaceVariant,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              width: 200,
              height: 200,
              color: AppColors.surfaceVariant,
              child: const Icon(Icons.error),
            ),
          ),
        ),
      );
    }
    // Default: text message
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        message.content,
        style: TextStyle(
          color: isMe ? Colors.white : AppColors.textPrimary,
          fontSize: 15,
        ),
      ),
    );
  }

  /// Build image preview bar above the message input (when image is staged)
  Widget _buildImagePreview() {
    if (_pendingImagePath == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.textTertiary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // Image thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_pendingImagePath!),
              width: 60,
              height: 60,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          // Label
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Image ready to send',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap send to share',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          // Cancel button
          IconButton(
            onPressed: _cancelPendingImage,
            icon: Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceVariant,
              padding: const EdgeInsets.all(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Attachment button: expands to Camera / Gallery / Location
          IconButton(
            onPressed: _isSending || _isChatLocked
                ? null
                : _showAttachmentSheet,
            icon: Icon(
              Icons.add_circle_outline,
              color: _isChatLocked
                  ? AppColors.textTertiary
                  : AppColors.textSecondary,
            ),
            padding: const EdgeInsets.all(8),
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 1,
              enabled:
                  _pendingImagePath == null, // disable text when image staged
              decoration: InputDecoration(
                hintText: _pendingImagePath != null
                    ? 'Tap send to share image'
                    : 'Type a message...',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isSending
                ? null
                : (_pendingImagePath != null
                      ? _sendPendingImage
                      : _sendMessage),
            icon: _isSending
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(Icons.send_rounded, color: AppColors.primary),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inDays > 0) {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
    return '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildLockedNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                color: AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _lockReason ?? 'Chat is locked',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
