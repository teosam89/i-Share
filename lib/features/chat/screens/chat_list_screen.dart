import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/services/auth_provider.dart';
import '../../profile/services/profile_service.dart';
import '../../shared/widgets/user_avatar.dart';
import '../models/chat_model.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';

/// Chat list tab — manages its own Firestore stream subscription.
/// Does NOT share a stream with the nav badge to avoid the late-subscriber
/// problem: a shared broadcast stream does not replay past emissions to new
/// listeners, causing an infinite spinner for users with zero chat rooms.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  /// Own stream — created fresh in initState() so this widget always receives
  /// the very first Firestore emission (including empty-list for new users).
  late final Stream<List<ChatRoom>> _stream;

  /// DM profile cache: userId → display info.
  /// Fetched once per userId per session; never re-fetched on rebuild.
  final Map<String, ({String name, String? photoUrl})> _profileCache = {};

  @override
  void initState() {
    super.initState();
    _stream = ChatService().getUserChatRooms();
  }

  /// Kick off async fetches for any DM user not yet in cache.
  /// Sets a placeholder immediately to prevent duplicate in-flight requests.
  /// Calls setState once per completed fetch to update the tile.
  void _prefetchDmProfiles(List<ChatRoom> rooms, String currentUserId) {
    for (final room in rooms) {
      if (!room.isDM && !room.id.startsWith('dm_')) continue;
      final otherId = room.getOtherUserId(currentUserId);
      if (otherId == null || otherId.isEmpty) continue;
      if (_profileCache.containsKey(otherId)) continue; // cached or in-flight

      // Optimistic placeholder prevents duplicate fetches on rapid rebuilds
      _profileCache[otherId] = (name: '', photoUrl: null);
      ProfileService().getDisplayInfo(otherId).then((info) {
        if (mounted) setState(() => _profileCache[otherId] = info);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<List<ChatRoom>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Treat permission errors (new user, no chats) as empty list
          if (snapshot.hasError) {
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
                    'No chats yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join a split to start chatting!',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          final chatRooms = snapshot.data ?? [];

          if (chatRooms.isEmpty) {
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
                    'No chats yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join a split to start chatting!',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          final currentUserId = context.read<AuthProvider>().userId ?? '';
          // Prefetch profiles for any uncached DM users (no-op if all cached)
          _prefetchDmProfiles(chatRooms, currentUserId);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chatRooms.length,
            itemBuilder: (context, index) {
              return _buildChatRoomTile(context, chatRooms[index], currentUserId);
            },
          );
        },
      ),
    );
  }

  Widget _buildChatRoomTile(
    BuildContext context,
    ChatRoom room,
    String currentUserId,
  ) {
    final isUnread = room.hasUnread(currentUserId);
    final isMuted = room.isMutedBy(currentUserId);
    return _buildChatTileContent(context, room, currentUserId, isUnread, isMuted);
  }

  Widget _buildChatTileContent(
    BuildContext context,
    ChatRoom room,
    String currentUserId,
    bool isUnread,
    bool isMuted,
  ) {
    // DM tile — use cached profile info; fallback to room.productName while fetching
    if (room.isDM || room.id.startsWith('dm_')) {
      final otherUserId = room.getOtherUserId(currentUserId);
      final cached = otherUserId != null ? _profileCache[otherUserId] : null;
      final otherUserName =
          (cached != null && cached.name.isNotEmpty) ? cached.name : room.productName;
      final otherUserPhoto = cached?.photoUrl;

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            UserAvatar(photoUrl: otherUserPhoto, name: otherUserName, radius: 25),
            if (isUnread)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          otherUserName,
          style: TextStyle(
            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          room.lastMessage ?? 'No messages yet',
          style: TextStyle(
            color: isUnread ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildTrailing(room, isUnread, isMuted),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatRoomId: room.id,
              productName: otherUserName,
            ),
          ),
        ),
      );
    }

    // Group chat tile
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Stack(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.groups, color: AppColors.primary),
          ),
          if (isUnread)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        room.productName,
        style: TextStyle(
          fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        room.lastMessage ?? 'No messages yet',
        style: TextStyle(
          color: isUnread ? AppColors.textPrimary : AppColors.textSecondary,
          fontSize: 13,
          fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _buildTrailing(room, isUnread, isMuted),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(chatRoomId: room.id, productName: room.productName),
        ),
      ),
    );
  }

  /// Trailing timestamp + optional mute icon, shared by DM and group tiles.
  Widget? _buildTrailing(ChatRoom room, bool isUnread, bool isMuted) {
    if (room.lastMessageAt != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(room.lastMessageAt!),
            style: TextStyle(
              color: isUnread ? AppColors.primary : AppColors.textTertiary,
              fontSize: 12,
              fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (isMuted) ...[
            const SizedBox(height: 4),
            Icon(Icons.notifications_off, size: 14, color: AppColors.textTertiary),
          ],
        ],
      );
    }
    if (isMuted) {
      return Icon(Icons.notifications_off, size: 14, color: AppColors.textTertiary);
    }
    return null;
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
