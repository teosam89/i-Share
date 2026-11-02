import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/request_status.dart';
import '../models/co_request_model.dart';
import '../models/join_request_model.dart';
import '../providers/co_request_provider.dart';
import '../services/join_request_service.dart';
import 'join_requests_screen.dart';
import 'create_request_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../profile/screens/profile_screen.dart';
import '../../profile/services/credibility_service.dart';
import '../../profile/models/user_profile_model.dart';
import 'qr_verification_screen.dart';
import '../services/qr_verification_service.dart';
import '../../shared/widgets/user_avatar.dart';
import 'review_screen.dart';
import '../services/bookmark_service.dart';

/// Request Detail Screen - Shows full details of a co-request
/// Allows users to join/leave requests and view participant info
class RequestDetailScreen extends StatefulWidget {
  final CoRequest request;

  const RequestDetailScreen({super.key, required this.request});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late CoRequest _request;
  final JoinRequestService _joinRequestService = JoinRequestService();
  final CredibilityService _credibilityService = CredibilityService();
  final BookmarkService _bookmarkService = BookmarkService();
  JoinRequest? _myJoinRequest;
  bool _isLoadingJoinStatus = true;
  bool _isSubmittingRequest = false;
  bool _isLeaving = false; // #6: Loading state for leave button
  bool _hasReviewed = true; // Assume reviewed until checked
  bool _isBookmarked = false;

  // Real-time stream subscriptions
  StreamSubscription? _requestSubscription;
  StreamSubscription? _joinRequestSubscription;

  @override
  void initState() {
    super.initState();
    _request = widget.request;
    _listenToRequestChanges();
    _listenToJoinRequestStatus();
    _checkReviewStatus();
    _loadBookmarkStatus();
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    _joinRequestSubscription?.cancel();
    super.dispose();
  }

  /// Check if current user has already reviewed for this request
  Future<void> _checkReviewStatus() async {
    if (_request.status != RequestStatus.completed) return;

    final hasReviewed = await _credibilityService.hasReviewedForRequest(
      _request.id,
      _request.participants,
    );

    if (mounted) {
      setState(() => _hasReviewed = hasReviewed);
    }
  }

  Future<void> _loadBookmarkStatus() async {
    final bookmarked = await _bookmarkService.isBookmarked(_request.id);
    if (mounted) setState(() => _isBookmarked = bookmarked);
  }

  Future<void> _toggleBookmark() async {
    final newState = !_isBookmarked;
    // Optimistic update — update UI immediately before async write
    setState(() => _isBookmarked = newState);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newState ? 'Added to Bookmarks' : 'Removed from Bookmarks',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    await _bookmarkService.toggle(_request.id);
  }

  /// Listen to co_request document changes (participants, status updates)
  void _listenToRequestChanges() {
    _requestSubscription = FirebaseFirestore.instance
        .collection('co_requests')
        .doc(_request.id)
        .snapshots()
        .listen((snapshot) {
          if (!mounted || !snapshot.exists) return;
          final updatedRequest = CoRequest.fromFirestore(snapshot);
          setState(() {
            _request = updatedRequest;
          });
          // Re-check review status if status changed to completed
          if (updatedRequest.status == RequestStatus.completed) {
            _checkReviewStatus();
          }
        });
  }

  /// Listen to current user's join request status in real-time
  void _listenToJoinRequestStatus() {
    final provider = context.read<CoRequestProvider>();
    final isOwner = provider.isMyRequest(_request);
    final hasJoined = _request.participants.contains(provider.currentUserId);

    // Skip if owner or already joined
    if (isOwner || hasJoined) {
      setState(() => _isLoadingJoinStatus = false);
      return;
    }

    // Use real-time stream instead of one-time fetch
    _joinRequestSubscription = _joinRequestService
        .streamMyJoinRequest(_request.id)
        .listen(
          (joinRequest) {
            if (!mounted) return;
            setState(() {
              _myJoinRequest = joinRequest;
              _isLoadingJoinStatus = false;
            });
          },
          onError: (e) {
            debugPrint('[RequestDetailScreen] Error streaming join status: $e');
            if (mounted) {
              setState(() => _isLoadingJoinStatus = false);
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CoRequestProvider>();
    final isOwner = provider.isMyRequest(_request);
    final hasJoined = _request.participants.contains(provider.currentUserId);
    final isFull = _request.isFull;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with Image
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).size.height * 0.3,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(background: _buildImageSection()),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.arrow_back, color: Colors.black),
              ),
            ),
            actions: [
              // Bookmark
              IconButton(
                onPressed: _toggleBookmark,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: _isBookmarked ? AppColors.accent : Colors.black,
                  ),
                ),
              ),
              // Only show options menu for active requests that user owns
              if (isOwner && _request.status == RequestStatus.active)
                IconButton(
                  onPressed: _showOptionsMenu,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.more_vert, color: Colors.black),
                  ),
                ),
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Badge
                  _buildStatusBadge(),
                  const SizedBox(height: 16),

                  // Expired Warning Banner (only if expired + not full)
                  if (_request.isExpired && !_request.isFull)
                    _buildExpiredWarningBanner(isOwner),
                  if (_request.isExpired && !_request.isFull)
                    const SizedBox(height: 16),

                  // Deal Description
                  _buildDealBadge(),
                  const SizedBox(height: 12),

                  // Additional Notes
                  _buildNotesSection(),
                  if (_request.notes != null && _request.notes!.isNotEmpty)
                    const SizedBox(height: 12),

                  // Product Name
                  Text(
                    _request.productName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Price Section
                  _buildPriceSection(),
                  const SizedBox(height: 24),

                  // Initiator Info
                  _buildInitiatorSection(),
                  const SizedBox(height: 24),

                  // Location Section
                  _buildLocationSection(),
                  const SizedBox(height: 24),

                  // Participants Section
                  _buildParticipantsSection(),
                  const SizedBox(height: 100), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Action Button
      bottomNavigationBar: _buildBottomBar(isOwner, hasJoined, isFull),
    );
  }

  Widget _buildImageSection() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Product Image or Placeholder
          if (_request.productPhotoUrl != null)
            GestureDetector(
              onTap: () {
                // Open fullscreen image viewer with zoom
                showDialog(
                  context: context,
                  builder: (_) => Dialog.fullscreen(
                    backgroundColor: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: CachedNetworkImage(
                            imageUrl: _request.productPhotoUrl!,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned(
                          top: 16,
                          right: 16,
                          child: SafeArea(
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 28,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: CachedNetworkImage(
                imageUrl: _request.productPhotoUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _buildImagePlaceholder(),
              ),
            )
          else
            _buildImagePlaceholder(),

          // Gradient Overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 80,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Category & Time Badges
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    RequestCategories.icons[_request.category] ??
                        'assets/icons/CateOthers.png',
                    width: RequestCategories.iconSizes[_request.category] ?? 24,
                    height:
                        RequestCategories.iconSizes[_request.category] ?? 24,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    RequestCategories.labels[_request.category] ?? 'Other',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Timer badge - HIDE for completed requests
          if (_request.status != RequestStatus.completed)
            Positioned(
              top: 100,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _request.timeRemaining,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      color: AppColors.surfaceVariant,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 8),
            Text(
              'Product Photo',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color bgColor;
    Color textColor;
    String label;

    // Priority: Full > Expired > Status
    if (_request.isFull &&
        _request.status != RequestStatus.completed &&
        _request.status != RequestStatus.cancelled) {
      bgColor = AppColors.success.withValues(alpha: 0.1);
      textColor = AppColors.success;
      label = '👥 Full';
    } else if (_request.isExpired &&
        _request.status != RequestStatus.completed &&
        _request.status != RequestStatus.cancelled) {
      bgColor = AppColors.error.withValues(alpha: 0.1);
      textColor = AppColors.error;
      label = '⏰ Expired';
    } else {
      switch (_request.status) {
        case RequestStatus.active:
          bgColor = AppColors.success.withValues(alpha: 0.1);
          textColor = AppColors.success;
          label = '🟢 Active';
          break;
        case RequestStatus.matched:
          bgColor = AppColors.primary.withValues(alpha: 0.1);
          textColor = AppColors.primary;
          label = '✅ Matched';
          break;
        case RequestStatus.completed:
          bgColor = AppColors.textTertiary.withValues(alpha: 0.1);
          textColor = AppColors.textSecondary;
          label = '✓ Completed';
          break;
        default:
          bgColor = AppColors.surfaceVariant;
          textColor = AppColors.textSecondary;
          label = _request.status;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  /// Expired warning banner — shown when request is expired + not full
  /// Tells users credibility won't be counted, suggests creating new or extending
  Widget _buildExpiredWarningBanner(bool isOwner) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Deal Expired',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This deal has expired and will not count towards credibility scores. '
            'We recommend creating a new request.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (isOwner) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showExtendTimeDialog,
                icon: const Icon(Icons.timer, size: 18),
                label: const Text('Extend Time'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: BorderSide(color: AppColors.warning),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Show dialog for host to extend expired request time
  void _showExtendTimeDialog() {
    final options = [
      (1, '+ 1 hour'),
      (2, '+ 2 hours'),
      (6, '+ 6 hours'),
      (12, '+ 12 hours'),
      (24, '+ 24 hours'),
    ];
    int selectedHours = 2;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Extend Time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose how much time to add. The deal will become active again and count towards credibility.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              RadioGroup<int>(
                groupValue: selectedHours,
                onChanged: (v) => setDialogState(() => selectedHours = v!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: options.map((opt) {
                    final (hours, label) = opt;
                    return RadioListTile<int>(
                      value: hours,
                      title: Text(label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _extendRequest(selectedHours);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Extend'),
            ),
          ],
        ),
      ),
    );
  }

  /// Extend the request by the given number of hours
  Future<void> _extendRequest(int additionalHours) async {
    try {
      final provider = context.read<CoRequestProvider>();
      await provider.extendRequest(_request.id, additionalHours);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deal extended by $additionalHours hour${additionalHours > 1 ? 's' : ''}! It\'s now active again.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to extend request. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildDealBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_offer, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _request.dealDescription,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    if (_request.notes == null || _request.notes!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Additional Notes',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _request.notes!,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    final savings = _request.totalPrice - _request.pricePerPerson;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Price',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RM ${_request.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: AppColors.primary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'You Pay Only',
                      style: TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'RM ${_request.pricePerPerson.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.savings, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  'You Save RM ${savings.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitiatorSection() {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('profiles')
          .doc(_request.initiatorId)
          .get(),
      builder: (context, snapshot) {
        UserProfile? hostProfile;
        if (snapshot.hasData && snapshot.data?.exists == true) {
          hostProfile = UserProfile.fromFirestore(snapshot.data!);
        }

        // Use hostProfile data when available, fallback to request data
        final displayName = hostProfile?.displayName ?? _request.initiatorName;
        final photoUrl = hostProfile?.photoUrl ?? _request.initiatorPhotoUrl;

        return GestureDetector(
          onTap: () => _viewProfile(_request.initiatorId),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    UserAvatar(
                      photoUrl: photoUrl,
                      name: displayName,
                      radius: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName.isNotEmpty ? displayName : 'User',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: AppColors.textTertiary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          // Credibility info
                          if (hostProfile != null)
                            Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  hostProfile.rating > 0
                                      ? '${hostProfile.rating.toStringAsFixed(1)} (${hostProfile.ratingCount})'
                                      : 'New',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.shopping_bag_outlined,
                                  color: AppColors.primary,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${hostProfile.completedRequests} deals',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const Spacer(),
                                _buildCredibilityBadge(hostProfile),
                              ],
                            )
                          else
                            Text(
                              'Request Initiator • Tap to view profile',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _openDirectMessage,
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mail_outline,
                          color: AppColors.primary,
                        ),
                      ),
                      tooltip: 'Message Host',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCredibilityBadge(UserProfile profile) {
    final level = profile.credibilityLevel;
    final color = Color(CredibilityService.getCredibilityColor(level));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(profile.credibilityIcon, width: 14, height: 14),
          const SizedBox(width: 2),
          Text(
            level,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.store, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _request.storeName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_request.storeAddress != null &&
                    _request.storeAddress!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _request.storeAddress!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (_request.distanceMeters != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _request.distanceText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              final lat = _request.latitude;
              final lng = _request.longitude;
              final label = Uri.encodeComponent(_request.storeName);
              launchUrl(
                Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)'),
                mode: LaunchMode.externalApplication,
              );
            },
            icon: Icon(Icons.directions, color: AppColors.primary, size: 28),
            tooltip: 'Navigate',
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsSection() {
    final spots = _request.partnersNeeded;
    // Subtract 1 because participants includes initiator, but partnersNeeded doesn't
    final joined = (_request.participants.length - 1).clamp(0, spots);

    // Get partner IDs (participants excluding initiator)
    final partnerIds = _request.participants
        .where((id) => id != _request.initiatorId)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Partners',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: joined >= spots
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$joined / $spots',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: joined >= spots
                      ? AppColors.success
                      : AppColors.secondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: spots > 0 ? joined / spots : 0,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(
              joined >= spots ? AppColors.success : AppColors.primary,
            ),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 12),

        // Partner avatars - fetched from profiles
        if (partnerIds.isNotEmpty)
          _buildPartnerAvatars(partnerIds)
        else
          Text(
            'Waiting for partners to join...',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),

        // Completed timestamp (only shown for completed requests)
        if (_request.status == RequestStatus.completed && _request.completedAt != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Completed on ${DateFormat('EEEE, h:mm a · d/M/y').format(_request.completedAt!)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Build partner avatars from Firestore profiles
  Widget _buildPartnerAvatars(List<String> partnerIds) {
    return FutureBuilder<List<DocumentSnapshot>>(
      future: Future.wait(
        partnerIds
            .take(5)
            .map(
              (id) => FirebaseFirestore.instance
                  .collection('profiles')
                  .doc(id)
                  .get(),
            ),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 40,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final profiles = snapshot.data ?? [];

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: profiles.asMap().entries.map((entry) {
            final index = entry.key;
            final doc = entry.value;
            final userId = partnerIds[index];

            String displayName = 'User';
            String? photoUrl;

            if (doc.exists) {
              final data = doc.data() as Map<String, dynamic>?;
              displayName = data?['displayName'] ?? 'User';
              photoUrl = data?['photoUrl'];
            }

            return GestureDetector(
              onTap: () => _viewProfile(userId),
              child: Tooltip(
                message: displayName,
                child: UserAvatar(
                  photoUrl: photoUrl,
                  name: displayName,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBottomBar(bool isOwner, bool hasJoined, bool isFull) {
    // Don't show action buttons for completed/cancelled requests
    final isFinished =
        _request.status == RequestStatus.completed || _request.status == RequestStatus.cancelled;

    if (isFinished) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _request.status == RequestStatus.completed
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _request.status == RequestStatus.completed
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: _request.status == RequestStatus.completed
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _request.status == RequestStatus.completed
                          ? 'This split has been completed'
                          : 'This split was cancelled',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _request.status == RequestStatus.completed
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
              // Review button for completed requests (if not yet reviewed)
              if (_request.status == RequestStatus.completed &&
                  !_hasReviewed &&
                  hasJoined) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReviewScreen(
                            requestId: _request.id,
                            participantIds: _request.participants,
                            isHost: isOwner,
                          ),
                        ),
                      ).then((_) {
                        // Refresh review status when returning (fallback)
                        _checkReviewStatus();
                      });
                    },
                    icon: const Icon(Icons.star),
                    label: const Text('Rate Participants'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
              // Leave button for cancelled requests (participant only, not owner)
              if (_request.status == RequestStatus.cancelled && hasJoined && !isOwner) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLeaving ? null : _leaveCancelledRequest,
                    icon: _isLeaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.exit_to_app),
                    label: Text(_isLeaving ? 'Leaving...' : 'Leave this split'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: isOwner
            ? _buildOwnerActions()
            : _buildParticipantActions(hasJoined, isFull),
      ),
    );
  }

  Widget _buildOwnerActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pending requests badge row
        StreamBuilder<List<JoinRequest>>(
          stream: _joinRequestService.getPendingJoinRequests(_request.id),
          builder: (context, snapshot) {
            final pendingCount = snapshot.data?.length ?? 0;
            if (pendingCount == 0) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: _viewPendingRequests,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$pendingCount pending join request${pendingCount > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        // Group Chat Button (full width)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.groups),
            label: const Text('Open Group Chat'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Action buttons row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cancelRequest,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _markAsCompleted,
                icon: const Icon(Icons.check_circle),
                label: const Text('Complete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParticipantActions(bool hasJoined, bool isFull) {
    // If already joined - show scan QR + group chat + leave
    if (hasJoined) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scan QR Button - Only show for active/matched status
          if (_request.status == RequestStatus.active || _request.status == RequestStatus.matched) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _scanQrToVerify,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR to Verify'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Group Chat Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openChat,
              icon: const Icon(Icons.groups),
              label: const Text('Open Group Chat'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Leave Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLeaving ? null : _leaveRequest,
              icon: _isLeaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.exit_to_app),
              label: Text(_isLeaving ? 'Leaving...' : 'Leave Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      );
    }

    // Loading state
    if (_isLoadingJoinStatus) {
      return const Center(child: CircularProgressIndicator());
    }

    // If has pending join request
    if (_myJoinRequest != null && _myJoinRequest!.isPending) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.hourglass_empty, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Approval',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Waiting for host to accept your request',
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
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _cancelJoinRequest,
            icon: const Icon(Icons.close),
            label: const Text('Cancel Request'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error),
              minimumSize: const Size(double.infinity, 45),
            ),
          ),
        ],
      );
    }

    // If was rejected
    if (_myJoinRequest != null && _myJoinRequest!.isRejected) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.block, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your request was declined by the host',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      );
    }

    // Default: show Request to Join button
    return ElevatedButton.icon(
      onPressed: isFull || _isSubmittingRequest ? null : _requestToJoin,
      icon: _isSubmittingRequest
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(isFull ? Icons.group_off : Icons.person_add_alt_1),
      label: Text(isFull ? 'Request Full' : 'Request to Join'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        disabledBackgroundColor: AppColors.surfaceVariant,
      ),
    );
  }

  void _showOptionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit Request'),
            onTap: () {
              Navigator.pop(ctx);
              // Navigate to CreateRequestScreen in edit mode
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRequestScreen(editRequest: _request),
                ),
              ).then((_) {
                if (!mounted) return;
                // Refresh data after editing
                context.read<CoRequestProvider>().loadFeedRequests();
                context.read<CoRequestProvider>().loadMyRequests();
              });
            },
          ),
          ListTile(
            leading: Icon(Icons.delete, color: AppColors.error),
            title: Text(
              'Delete Request',
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _deleteRequest();
            },
          ),
        ],
      ),
    );
  }

  /// Request to join (creates pending join request)
  Future<void> _requestToJoin() async {
    setState(() => _isSubmittingRequest = true);

    try {
      final joinRequest = await _joinRequestService.createJoinRequest(
        coRequest: _request,
      );

      if (mounted) {
        setState(() {
          _myJoinRequest = joinRequest;
          _isSubmittingRequest = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✓ Request sent! Waiting for host approval.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmittingRequest = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Cancel pending join request
  Future<void> _cancelJoinRequest() async {
    if (_myJoinRequest == null) return;

    try {
      await _joinRequestService.cancelJoinRequest(
        requestId: _request.id,
        joinRequestId: _myJoinRequest!.id,
      );

      if (mounted) {
        setState(() => _myJoinRequest = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request cancelled')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// View pending join requests (Host only)
  void _viewPendingRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JoinRequestsScreen(
          requestId: _request.id,
          productName: _request.productName,
        ),
      ),
    );
  }

  Future<void> _leaveRequest() async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Request'),
        content: const Text(
          'Are you sure you want to leave this request?\n\n'
          'You will also lose access to the group chat and any related discussions.',
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

    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _isLeaving = true); // #6: Show loading

    try {
      final provider = context.read<CoRequestProvider>();
      final success = await provider.leaveRequest(_request.id);
      if (mounted && success) {
        // Credibility penalty handled server-side by leaveRequestSecure CF

        setState(() {
          _request = _request.copyWith(
            participants: _request.participants
                .where((id) => id != provider.currentUserId)
                .toList(),
          );
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Left the request')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  /// Leave a cancelled request (no credibility penalty since owner cancelled)
  Future<void> _leaveCancelledRequest() async {
    setState(() => _isLeaving = true);

    try {
      final provider = context.read<CoRequestProvider>();
      final success = await provider.leaveRequest(_request.id);
      if (mounted && success) {
        // No credibility penalty — the request was cancelled by the owner
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Left the cancelled split')),
        );
        Navigator.pop(context); // Go back since there's nothing to do here
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  /// Scan QR to verify presence (for participants)
  Future<void> _scanQrToVerify() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QrVerificationScreen(
          requestId: _request.id,
          participantIds: _request.participants
              .where((id) => id != _request.initiatorId)
              .toList(),
          ownerId: _request.initiatorId,
          isOwner: false,
          onAllVerified: () {
            // Participant doesn't need to handle this
          },
        ),
      ),
    );
  }

  /// Open group chat for this request
  Future<void> _openChat() async {
    final provider = context.read<CoRequestProvider>();
    final currentUserId = provider.currentUserId;

    // Verify user is owner or participant
    final isOwner = _request.initiatorId == currentUserId;
    final isParticipant = _request.participants.contains(currentUserId);

    if (!isOwner && !isParticipant) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must join this request to access the chat'),
        ),
      );
      return;
    }

    try {
      final chatService = ChatService();

      // Get all participant IDs including initiator
      final participantIds = {
        _request.initiatorId,
        ..._request.participants,
      }.toList(); // Remove duplicates

      // Create or get existing chat room
      final chatRoom = await chatService.getOrCreateChatRoom(
        requestId: _request.id,
        productName: _request.productName,
        participantIds: participantIds,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatRoomId: _request.id,
              productName:
                  chatRoom.productName, // Use group name from chat room
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open chat. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Open direct message with the Host
  Future<void> _openDirectMessage() async {
    final provider = context.read<CoRequestProvider>();
    final currentUserId = provider.currentUserId;

    if (currentUserId == null) return;

    // Don't DM yourself
    if (currentUserId == _request.initiatorId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This is your own request')));
      return;
    }

    try {
      // Create DM chat room ID (sorted user IDs to ensure consistency)
      final userIds = [currentUserId, _request.initiatorId]..sort();
      final dmChatRoomId = 'dm_${userIds.join('_')}';

      // Create or get DM chat room
      final dmRef = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(dmChatRoomId);
      final dmDoc = await dmRef.get();

      if (!dmDoc.exists) {
        await dmRef.set({
          'requestId': null, // DM, not linked to request
          'productName': 'Direct Message',
          'participantIds': userIds,
          'isDM': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatRoomId: dmChatRoomId,
              productName: _request.initiatorName, // Show host name as title
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open direct message. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// View user profile
  void _viewProfile(String userId) {
    final provider = context.read<CoRequestProvider>();
    final isCurrentUser = userId == provider.currentUserId;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProfileScreen(userId: userId, isCurrentUser: isCurrentUser),
      ),
    );
  }

  Future<void> _cancelRequest() async {
    // Owner is always in participants; only count OTHER participants
    final otherParticipants = _request.participants
        .where((id) => id != _request.initiatorId)
        .toList();
    final hasParticipants = otherParticipants.isNotEmpty;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasParticipants) ...[
              Text(
                'This request has ${otherParticipants.length} participant(s).',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cancelling will affect your credibility score.',
                        style: TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const Text('This will remove your request.'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.success,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No penalty since no one has joined yet!',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Request'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Yes, Cancel',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // Credibility penalty handled server-side by onCoRequestUpdated CF

      final success = await context.read<CoRequestProvider>().updateRequest(
        requestId: _request.id,
        status: RequestStatus.cancelled,
      );
      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasParticipants
                  ? 'Request cancelled'
                  : 'Request cancelled (no penalty applied)',
            ),
            backgroundColor: hasParticipants ? null : AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _markAsCompleted() async {
    // Owner is always in participants; check for OTHER participants
    final otherParticipants = _request.participants
        .where((id) => id != _request.initiatorId)
        .toList();
    if (otherParticipants.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.group_off,
                  size: 48,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'This request has no participants yet.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You need at least one participant to complete this split.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Show QR verification confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To complete this request, all participants must verify their presence.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.qr_code, color: AppColors.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QR Verification',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'A QR code will be shown for ${_request.participants.where((id) => id != _request.initiatorId).length} participant(s) to scan.',
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
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Show QR Code'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Navigate to QR verification screen
    final allVerified = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QrVerificationScreen(
          requestId: _request.id,
          participantIds: _request.participants
              .where((id) => id != _request.initiatorId)
              .toList(),
          ownerId: _request.initiatorId,
          isOwner: true,
          onAllVerified: () {
            // Will be handled by the return value
          },
        ),
      ),
    );

    if (allVerified == true && mounted) {
      // All verified, complete the request
      final success = await context.read<CoRequestProvider>().updateRequest(
        requestId: _request.id,
        status: RequestStatus.completed,
      );

      if (success && mounted) {
        // Credibility scoring handled server-side by onCoRequestUpdated CF

        // Clean up verification data
        final qrService = QrVerificationService();
        await qrService.cleanUpVerification(_request.id);

        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🎉 Request completed!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _deleteRequest() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Request?'),
        content: const Text('This cannot be undone. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await context.read<CoRequestProvider>().deleteRequest(
        _request.id,
      );
      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request deleted')));
      }
    }
  }
}
