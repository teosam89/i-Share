import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lottie/lottie.dart' hide Marker;
import '../../../core/constants/app_colors.dart';
import '../models/realtime_match_model.dart';
import '../services/realtime_match_service.dart';
import '../../chat/screens/chat_screen.dart';
import '../../co_request/models/co_request_model.dart';
import '../../profile/screens/profile_screen.dart';
import '../../shared/widgets/user_avatar.dart';

/// MatchWaitingScreen - Shows match preview (Accept/Skip) or waiting status
class MatchWaitingScreen extends StatefulWidget {
  final String matchId;

  /// User's product intent text (needed for join/create)
  final String? productIntent;

  /// True when showing a candidate for preview (not yet joined)
  final bool isPreview;

  /// Search params for retry after skip (only needed when isPreview=true)
  final String? searchCategory;
  final double? searchLatitude;
  final double? searchLongitude;
  final double? searchRadiusKm;
  final int? searchMaxPartners;

  const MatchWaitingScreen({
    super.key,
    required this.matchId,
    this.productIntent,
    this.isPreview = false,
    this.searchCategory,
    this.searchLatitude,
    this.searchLongitude,
    this.searchRadiusKm,
    this.searchMaxPartners,
  });

  @override
  State<MatchWaitingScreen> createState() => _MatchWaitingScreenState();
}

class _MatchWaitingScreenState extends State<MatchWaitingScreen> {
  final RealtimeMatchService _matchService = RealtimeMatchService();
  bool _closedHandled = false;
  bool _isProcessing = false;

  /// Current candidate match ID (changes on skip → retry)
  late String _currentMatchId;

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _currentMatchId = widget.matchId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RealtimeMatch?>(
      stream: _matchService.getMatchStream(_currentMatchId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final match = snapshot.data;
        if (match == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Match')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.search_off, size: 64, color: AppColors.warning),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No Matches Found',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your match session has ended or no nearby partners were found. Try these:',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 28),

                    // Suggestion: Try again with wider radius
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop({'retry': true}),
                        icon: const Icon(Icons.radar, size: 20),
                        label: const Text('Try Again'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Suggestion: Create a request instead
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).pushNamed('/create-request');
                        },
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        label: const Text('Create a Request Instead'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Go back
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Go Back',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Preview mode: show candidate card with Accept/Skip
        if (widget.isPreview && !match.isParticipant(_currentUserId)) {
          return _buildPreviewScreen(match);
        }

        // Auto-pop for non-owner participants when match is closed
        if (match.status == 'closed' && !_closedHandled) {
          _closedHandled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final message = match.convertedToCoBuyId != null
                ? 'A Co-Buy Request has been created! Check the feed.'
                : 'This match has been closed.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
            Navigator.pop(context);
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Real-Time Match'),
            centerTitle: true,
            actions: [
              IconButton(
                onPressed: () => _leaveMatch(match),
                icon: const Icon(Icons.exit_to_app),
                tooltip: 'Leave Match',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Match Status Card
                _buildStatusCard(match),
                const SizedBox(height: 20),

                // Participants Card
                _buildParticipantsCard(match),
                const SizedBox(height: 20),

                // Location Card
                _buildLocationCard(match),
                const SizedBox(height: 20),

                // Map Preview Card
                _buildMapCard(match),
                const SizedBox(height: 20),
              ],
            ),
          ),
          // Open Chat button fixed at the bottom, safe from system nav bar
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: _buildChatButton(match),
            ),
          ),
        );
      },
    );
  }

  // ───────── Preview Mode UI ─────────

  Widget _buildPreviewScreen(RealtimeMatch candidate) {
    final ownerIntent =
        candidate.participantIntents[candidate.ownerId] ?? 'Not specified';
    final myIntent = widget.productIntent ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match Found!'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Lottie celebration
            SizedBox(
              width: 100,
              height: 100,
              child: Lottie.asset(
                'assets/icons/Success.json',
                fit: BoxFit.contain,
                repeat: false,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A potential partner was found!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            // Intent comparison card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // My intent
                  _buildIntentRow(
                    label: 'You want to buy',
                    intent: myIntent,
                    color: AppColors.primary,
                    icon: Icons.person,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: AppColors.border),
                  ),
                  // Their intent
                  _buildIntentRow(
                    label: 'They want to buy',
                    intent: ownerIntent,
                    color: AppColors.accent,
                    icon: Icons.person_outline,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Location + Category info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 20, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          candidate.locationName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Image.asset(
                        RequestCategories.icons[candidate.category] ??
                            'assets/icons/CateOthers.png',
                        width: 20,
                        height: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        RequestCategories.labels[candidate.category] ??
                            candidate.category,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Text(
                        '${candidate.participantCount}/${candidate.maxPartners + 1} partners',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              // Skip button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _onSkip(candidate),
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Skip'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Accept button
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : () => _onAccept(candidate),
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Accept & Join'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntentRow({
    required String label,
    required String intent,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                intent,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Accept: join the candidate room
  Future<void> _onAccept(RealtimeMatch candidate) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final success = await _matchService.joinRoom(
      candidate.id,
      productIntent: widget.productIntent ?? '',
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      // Now joined — StreamBuilder will pick up the change and
      // exit preview mode (isParticipant becomes true)
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not join. The room may be full or expired.'),
          backgroundColor: AppColors.error,
        ),
      );
      Navigator.pop(context);
    }
  }

  /// Skip: mark room skipped, search for next candidate, or create new room
  Future<void> _onSkip(RealtimeMatch candidate) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    await _matchService.skipRoom(candidate.id);

    // Retry search with same params
    final nextCandidate = await _matchService.findMatchingRoom(
      category: widget.searchCategory ?? candidate.category,
      productIntent: widget.productIntent ?? '',
      latitude: widget.searchLatitude ?? candidate.latitude,
      longitude: widget.searchLongitude ?? candidate.longitude,
      radiusKm: widget.searchRadiusKm ?? candidate.radiusKm,
      maxPartners: widget.searchMaxPartners ?? candidate.maxPartners,
    );

    if (!mounted) return;

    if (nextCandidate != null) {
      // Show next candidate
      setState(() {
        _currentMatchId = nextCandidate.id;
        _isProcessing = false;
      });
    } else {
      // No more candidates — create a new room
      final newMatch = await _matchService.createRoom(
        category: widget.searchCategory ?? candidate.category,
        productIntent: widget.productIntent ?? '',
        latitude: widget.searchLatitude ?? candidate.latitude,
        longitude: widget.searchLongitude ?? candidate.longitude,
        radiusKm: widget.searchRadiusKm ?? candidate.radiusKm,
        locationName: candidate.locationName,
        maxPartners: widget.searchMaxPartners ?? candidate.maxPartners,
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (newMatch != null) {
        // Replace current screen with the new waiting room
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MatchWaitingScreen(matchId: newMatch.id),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not create room. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  // ───────── Waiting Mode UI (existing) ─────────

  Widget _buildStatusCard(RealtimeMatch match) {
    // Client-side expiry check: show expired immediately without waiting for CF cleanup
    final isExpired = match.isExpired && match.status != 'closed';
    final isWaiting = match.status == 'waiting' && !isExpired;
    final isClosed = match.status == 'closed';

    final Color statusColor;
    final IconData statusIcon;
    final String statusText;

    if (isExpired) {
      statusColor = AppColors.error;
      statusIcon = Icons.timer_off;
      statusText = 'Match Expired';
    } else if (isClosed) {
      statusColor = AppColors.textSecondary;
      statusIcon = Icons.exit_to_app;
      statusText = 'Exiting...';
    } else if (isWaiting) {
      statusColor = AppColors.warning;
      statusIcon = Icons.hourglass_empty;
      statusText = 'Waiting for partners...';
    } else {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle;
      statusText = 'Matched!';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Lottie animation for waiting/matched; icon for expired/closed
          if (isWaiting)
            SizedBox(
              width: 120,
              height: 120,
              child: Lottie.asset(
                'assets/icons/LoadingMatching.json',
                fit: BoxFit.contain,
              ),
            )
          else if (!isClosed && !isExpired)
            // Matched state - show success animation
            SizedBox(
              width: 120,
              height: 120,
              child: Lottie.asset(
                'assets/icons/Success.json',
                fit: BoxFit.contain,
                repeat: false,
              ),
            )
          else
            // Expired or closed state - show icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(statusIcon, size: 48, color: statusColor),
            ),
          const SizedBox(height: 16),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          // Category badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  RequestCategories.icons[match.category] ??
                      'assets/icons/CateOthers.png',
                  width: 18,
                  height: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  RequestCategories.labels[match.category] ?? match.category,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Show own product intent
          if (match.participantIntents[_currentUserId] != null) ...[
            const SizedBox(height: 10),
            Text(
              'Looking for: ${match.participantIntents[_currentUserId]}',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParticipantsCard(RealtimeMatch match) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Participants (${match.participantCount})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fetch and display all participants
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _fetchParticipantProfiles(match.participants),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final profiles = snapshot.data!;
              return Column(
                children: profiles.map((profile) {
                  final isOwner = profile['id'] == match.ownerId;
                  final isCurrentUser = profile['id'] == _currentUserId;
                  return _buildParticipantTile(
                    userId: profile['id'],
                    name: profile['displayName'] ?? 'User',
                    photoUrl: profile['photoUrl'],
                    isOwner: isOwner,
                    isCurrentUser: isCurrentUser,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantTile({
    required String userId,
    required String name,
    String? photoUrl,
    bool isOwner = false,
    bool isCurrentUser = false,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ProfileScreen(userId: userId, isCurrentUser: isCurrentUser),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            UserAvatar(photoUrl: photoUrl, name: name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.textTertiary.withValues(
                              alpha: 0.2,
                            ),
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
                  if (isOwner)
                    Text(
                      'Room Owner',
                      style: TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
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

  Widget _buildLocationCard(RealtimeMatch match) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.location_on, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.locationName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Radius: ${match.radiusKm < 1 ? "${(match.radiusKm * 1000).toInt()}m" : "${match.radiusKm.toInt()}km"}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatButton(RealtimeMatch match) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: match.chatRoomId != null ? () => _openChat(match) : null,
        icon: const Icon(Icons.chat),
        label: const Text('Open Chat'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  void _openChat(RealtimeMatch match) {
    if (match.chatRoomId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatRoomId: match.chatRoomId!,
          productName:
              'Real-Time Match: ${RequestCategories.labels[match.category] ?? match.category}',
        ),
      ),
    );
  }

  Future<void> _leaveMatch(RealtimeMatch match) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Match?'),
        content: const Text('Are you sure you want to leave this match?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _matchService.leaveRoom(match.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _buildMapCard(RealtimeMatch match) {
    // Calculate zoom level based on radius
    double getZoomLevel(double radiusKm) {
      if (radiusKm <= 1) return 14.5;
      if (radiusKm <= 2) return 13.5;
      if (radiusKm <= 5) return 12.0;
      if (radiusKm <= 10) return 11.0;
      return 10.0;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.map, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Coverage Area',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.25,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(match.latitude, match.longitude),
                  zoom: getZoomLevel(match.radiusKm),
                ),
                circles: {
                  Circle(
                    circleId: const CircleId('radius'),
                    center: LatLng(match.latitude, match.longitude),
                    radius: match.radiusKm * 1000,
                    fillColor: AppColors.primary.withValues(alpha: 0.15),
                    strokeColor: AppColors.primary,
                    strokeWidth: 2,
                  ),
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('center'),
                    position: LatLng(match.latitude, match.longitude),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure,
                    ),
                    infoWindow: InfoWindow(
                      title:
                          RequestCategories.labels[match.category] ??
                          match.category,
                      snippet:
                          '${match.participantCount}/${match.maxPartners + 1} partners',
                    ),
                  ),
                },
                zoomControlsEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
