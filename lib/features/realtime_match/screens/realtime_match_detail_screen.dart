import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../models/realtime_match_model.dart';
import '../services/realtime_match_service.dart';
import '../../chat/services/chat_service.dart';
import '../../profile/screens/profile_screen.dart';
import '../../co_request/models/co_request_model.dart';
import 'rtm_to_cobuy_screen.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../shared/widgets/user_avatar.dart';

/// RealtimeMatchDetailScreen - Dedicated detail screen for Real-Time Match
/// Shows match info, participants, and provides "Convert to Co-Buy" functionality
class RealtimeMatchDetailScreen extends StatefulWidget {
  final String matchId;

  const RealtimeMatchDetailScreen({super.key, required this.matchId});

  @override
  State<RealtimeMatchDetailScreen> createState() =>
      _RealtimeMatchDetailScreenState();
}

class _RealtimeMatchDetailScreenState extends State<RealtimeMatchDetailScreen> {
  final RealtimeMatchService _matchService = RealtimeMatchService();
  bool _isLoading = false;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Get status display text and color
  (String, Color) _getStatusDisplay(String status) {
    switch (status) {
      case 'waiting':
        return ('Looking for Partners', AppColors.warning);
      case 'matched':
        return ('Matched!', AppColors.success);
      case 'closed':
        return ('Closed', AppColors.textTertiary);
      default:
        return ('Unknown', AppColors.textTertiary);
    }
  }

  /// Get category display name
  String _getCategoryLabel(String category) {
    return RequestCategories.labels[category] ?? category;
  }

  /// Leave the match
  Future<void> _leaveMatch(RealtimeMatch match) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Match?'),
        content: Text(
          match.isOwner(_currentUserId)
              ? 'As the owner, leaving will close this match for everyone.'
              : 'Are you sure you want to leave this match?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isLoading = true);

      final success = await _matchService.leaveRoom(widget.matchId);

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Left the match')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to leave match'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  /// Convert RTM to Co-Buy Request
  Future<void> _convertToCoBuy(RealtimeMatch match) async {
    // Navigate to dedicated RTM to Co-Buy conversion screen
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RtmToCoBuyScreen(match: match)),
    );
  }

  /// Delete chat room for a closed match
  Future<void> _deleteChatRoom(RealtimeMatch match) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat Room?'),
        content: const Text(
          'This will permanently delete the chat room and all messages. This action cannot be undone.',
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
      setState(() => _isLoading = true);
      try {
        final chatRoomId = 'rtm_${match.id}';
        await ChatService().deleteChatRoom(chatRoomId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Chat room deleted'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to delete chat room'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match Details')),
      body: StreamBuilder<RealtimeMatch?>(
        stream: _matchService.getMatchStream(widget.matchId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Match not found',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          final match = snapshot.data!;
          final (statusText, statusColor) = _getStatusDisplay(match.status);
          final isOwner = match.isOwner(_currentUserId);
          final timeAgo = timeago.format(match.createdAt);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primary.withValues(alpha: 0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.flash_on,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'REAL-TIME',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Category Title
                      Text(
                        _getCategoryLabel(match.category),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Status
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Match Info Section
                _buildSectionTitle('Match Information'),
                const SizedBox(height: 12),
                _buildInfoCard([
                  _buildInfoRow(
                    Icons.location_on_outlined,
                    'Location',
                    match.locationName,
                  ),
                  _buildInfoRow(
                    Icons.radar,
                    'Search Radius',
                    MatchRadius.getLabel(match.radiusKm),
                  ),
                  _buildInfoRow(
                    Icons.group_outlined,
                    'Partners Needed',
                    '${match.participantCount - 1}/${match.maxPartners}',
                  ),
                  _buildInfoRow(Icons.access_time, 'Created', timeAgo),
                  _buildInfoRow(
                    Icons.timer_outlined,
                    'Expires',
                    match.isExpired
                        ? 'Expired'
                        : timeago.format(match.expiresAt, allowFromNow: true),
                  ),
                ]),
                const SizedBox(height: 24),

                // Participants Section
                _buildSectionTitle(
                  'Participants (${match.participantCount}/${match.maxPartners + 1})',
                ),
                const SizedBox(height: 12),
                _buildParticipantsList(match),
                const SizedBox(height: 24),

                // Next Steps Section
                if (match.status == 'matched') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: AppColors.success,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Next Steps',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Great! You\'ve matched with partners. Now discuss in the chat to decide:',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStepItem('1', 'What product to buy together'),
                        _buildStepItem('2', 'Where and when to meet'),
                        _buildStepItem('3', 'How to split the cost'),
                        const SizedBox(height: 16),
                        Text(
                          isOwner
                              ? 'Once decided, create a Co-Buy Request to track the transaction:'
                              : 'Once decided, ask the Room Owner to create a Co-Buy Request to track the transaction.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Action Buttons
                if (match.status != 'closed') ...[
                  // Convert to Co-Buy Button (only for owner when matched)
                  if (isOwner && match.status == 'matched')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _convertToCoBuy(match),
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: const Text('Create Co-Buy Request'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),

                  if (isOwner && match.status == 'matched')
                    const SizedBox(height: 12),

                  // Leave/Close Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _leaveMatch(match),
                      icon: Icon(
                        isOwner ? Icons.close : Icons.exit_to_app,
                        color: AppColors.error,
                      ),
                      label: Text(
                        isOwner ? 'Close Match' : 'Leave Match',
                        style: TextStyle(color: AppColors.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],

                // Closed status message
                if (match.status == 'closed') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This match has been closed.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Delete Chat Room button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _deleteChatRoom(match),
                      icon: Icon(Icons.delete_outline, color: AppColors.error),
                      label: Text(
                        'Delete Chat Room',
                        style: TextStyle(color: AppColors.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsList(RealtimeMatch match) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchParticipantProfiles(match.participants),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final profiles = snapshot.data!;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: profiles.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, index) {
              final profile = profiles[index];
              final isOwner = profile['id'] == match.ownerId;
              final isCurrentUser = profile['id'] == _currentUserId;
              final intent = match.participantIntents[profile['id']];

              return ListTile(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        userId: profile['id'],
                        isCurrentUser: isCurrentUser,
                      ),
                    ),
                  );
                },
                leading: UserAvatar(
                  photoUrl: profile['photoUrl'] as String?,
                  name: profile['displayName'] ?? 'U',
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile['displayName'] ?? 'User',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.textTertiary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'You',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isOwner)
                      Text(
                        'Match Owner',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                        ),
                      ),
                    if (intent != null)
                      Text(
                        'Wants: $intent',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      (profile['rating'] ?? 0.0).toStringAsFixed(1),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchParticipantProfiles(
    List<String> participantIds,
  ) async {
    final profiles = <Map<String, dynamic>>[];

    for (final id in participantIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(id)
            .get();

        if (doc.exists) {
          profiles.add({'id': id, ...doc.data()!});
        } else {
          profiles.add({'id': id, 'displayName': 'User'});
        }
      } catch (e) {
        profiles.add({'id': id, 'displayName': 'User'});
      }
    }

    return profiles;
  }
}
