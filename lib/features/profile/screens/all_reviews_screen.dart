import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../models/user_profile_model.dart';
import '../services/profile_service.dart';
import '../../shared/widgets/user_avatar.dart';

/// AllReviewsScreen - Shows all reviews for a user with batch-loaded profiles
class AllReviewsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AllReviewsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
  final ProfileService _profileService = ProfileService();

  /// Cache of reviewer profiles: userId -> photoUrl
  final Map<String, String?> _profileCache = {};
  bool _profilesLoaded = false;

  /// Batch-fetch all reviewer profiles in one go (Firestore whereIn, max 10 per batch)
  Future<void> _loadReviewerProfiles(List<UserRating> ratings) async {
    if (_profilesLoaded) return;

    final uniqueIds = ratings.map((r) => r.fromUserId).toSet().toList();

    // Firestore whereIn supports max 10 items per query, batch if needed
    for (var i = 0; i < uniqueIds.length; i += 10) {
      final batch = uniqueIds.skip(i).take(10).toList();
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('profiles')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          _profileCache[doc.id] = data['photoUrl'] as String?;
        }
      } catch (e) {
        debugPrint('[AllReviewsScreen] Error batch fetching profiles: $e');
      }
    }

    // Mark IDs without a profile doc
    for (final id in uniqueIds) {
      _profileCache.putIfAbsent(id, () => null);
    }

    if (mounted) {
      setState(() => _profilesLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.userName}\'s Reviews')),
      body: StreamBuilder<List<UserRating>>(
        stream: _profileService.getUserRatings(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final ratings = snapshot.data ?? [];

          if (ratings.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star_outline_rounded,
                      size: 48,
                      color: Colors.amber.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No reviews yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reviews will appear here after split completions.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }

          // Anti-spam: max 2 reviews per unique reviewer
          final filteredRatings = _filterReviewsPerUser(ratings, maxPerUser: 2);

          // Batch-load profiles once
          if (!_profilesLoaded) {
            _loadReviewerProfiles(filteredRatings);
          }

          // Calculate average rating
          final avgRating = filteredRatings.isEmpty
              ? 0.0
              : filteredRatings.map((r) => r.rating).reduce((a, b) => a + b) /
                    filteredRatings.length;

          return Column(
            children: [
              // Summary header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Average rating
                    Column(
                      children: [
                        Text(
                          avgRating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (index) => Icon(
                              index < avgRating.round()
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 18,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${filteredRatings.length} reviews',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    // Rating distribution bars
                    Expanded(
                      child: Column(
                        children: List.generate(5, (index) {
                          final star = 5 - index;
                          final count = filteredRatings
                              .where((r) => r.rating == star)
                              .length;
                          final fraction = filteredRatings.isEmpty
                              ? 0.0
                              : count / filteredRatings.length;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  '$star',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.star_rounded,
                                  size: 12,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: fraction,
                                      backgroundColor: AppColors.border,
                                      color: Colors.amber,
                                      minHeight: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),

              // Reviews list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredRatings.length,
                  itemBuilder: (context, index) {
                    return _buildReviewItem(context, filteredRatings[index]);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReviewItem(BuildContext context, UserRating rating) {
    final photoUrl = _profileCache[rating.fromUserId];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reviewer avatar (from cache, no more per-item network call)
          UserAvatar(
            photoUrl: photoUrl,
            name: rating.fromUserName,
            radius: 20,
          ),
          const SizedBox(width: 12),
          // Review content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rating.fromUserName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...List.generate(
                      5,
                      (index) => Icon(
                        index < rating.rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
                if (rating.comment != null && rating.comment!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    rating.comment!,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatRelativeTime(rating.createdAt),
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<UserRating> _filterReviewsPerUser(
    List<UserRating> ratings, {
    int maxPerUser = 2,
  }) {
    final Map<String, int> userReviewCount = {};
    final List<UserRating> filtered = [];

    for (final rating in ratings) {
      final count = userReviewCount[rating.fromUserId] ?? 0;
      if (count < maxPerUser) {
        filtered.add(rating);
        userReviewCount[rating.fromUserId] = count + 1;
      }
    }

    return filtered;
  }

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}
