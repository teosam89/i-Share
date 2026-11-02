import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/request_status.dart';
import '../../shared/widgets/user_avatar.dart';

/// ReviewScreen - Rate all participants after QR verification completion
class ReviewScreen extends StatefulWidget {
  final String requestId;
  final List<String> participantIds;
  final bool isHost; // P0 #3: Only host can complete the request

  const ReviewScreen({
    super.key,
    required this.requestId,
    required this.participantIds,
    this.isHost = false,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // Map of userId -> rating (1-5)
  final Map<String, int> _ratings = {};
  // Map of userId -> comment
  final Map<String, String> _comments = {};
  // Map of userId -> profile data
  final Map<String, Map<String, dynamic>> _profiles = {};
  // All users to rate (participants + initiator, excluding self)
  List<String> _usersToRate = [];

  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      // First, get the request to find the initiatorId
      final requestDoc = await FirebaseFirestore.instance
          .collection('co_requests')
          .doc(widget.requestId)
          .get();

      // Collect all user IDs to rate (participants + initiator)
      final Set<String> allUserIds = {...widget.participantIds};

      if (requestDoc.exists) {
        final initiatorId = requestDoc.data()?['initiatorId'] as String?;
        if (initiatorId != null) {
          allUserIds.add(initiatorId);
        }
      }

      // Remove current user from the list
      allUserIds.remove(_currentUserId);
      _usersToRate = allUserIds.toList();

      // Load profiles for all users
      for (final userId in _usersToRate) {
        final doc = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(userId)
            .get();

        if (doc.exists) {
          _profiles[userId] = doc.data()!;
        }
      }
    } catch (e) {
      debugPrint('[ReviewScreen] Error loading profiles: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _allRated {
    // Check if all users have been rated
    for (final userId in _usersToRate) {
      if (!_ratings.containsKey(userId) || _ratings[userId] == 0) {
        return false;
      }
    }
    return _usersToRate.isNotEmpty;
  }

  Future<void> _submitReviews() async {
    if (!_allRated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please rate all participants')),
      );
      return;
    }

    // P0 #4: Check if already submitted reviews for this request
    if (_currentUserId != null && _usersToRate.isNotEmpty) {
      final existingRating = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(_usersToRate.first)
          .collection('ratings')
          .where('fromUserId', isEqualTo: _currentUserId)
          .where('requestId', isEqualTo: widget.requestId)
          .limit(1)
          .get();

      if (existingRating.docs.isNotEmpty) {
        // Reviews already submitted - but if Host, still need to complete the request
        if (widget.isHost) {
          setState(() => _isSubmitting = true);
          try {
            await _completeRequest();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Request completed successfully!'),
                  backgroundColor: AppColors.success,
                ),
              );
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } catch (e) {
            debugPrint('[ReviewScreen] Error completing request: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Something went wrong. Please try again.',
                  ),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          } finally {
            if (mounted) setState(() => _isSubmitting = false);
          }
          return;
        }

        // Non-host: just show message and go back
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You have already submitted reviews for this request',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      // Submit ratings via secure Cloud Function
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('submitRatingSecure');

      for (final userId in _ratings.keys) {
        final rating = _ratings[userId]!;
        final comment = _comments[userId];

        await callable.call({
          'ratedUserId': userId,
          'requestId': widget.requestId,
          'rating': rating,
          'comment': comment,
        });
      }

      // P0 #3: Only Host can complete the request
      if (widget.isHost) {
        await _completeRequest();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reviews submitted successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        // Navigate back to home
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('[ReviewScreen] Error submitting reviews: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Complete the request: award credibility and update status
  Future<void> _completeRequest() async {
    final requestDoc = await FirebaseFirestore.instance
        .collection('co_requests')
        .doc(widget.requestId)
        .get();

    if (!requestDoc.exists) return;

    final data = requestDoc.data();
    final currentStatus = data?['status'] as String?;

    // Credibility scoring handled server-side by onCoRequestUpdated CF
    // when status changes to 'completed'

    // Update request status to completed (skip if already completed)
    if (currentStatus != RequestStatus.completed) {
      await FirebaseFirestore.instance
          .collection(AppConstants.coRequestsCollection)
          .doc(widget.requestId)
          .update({
            'status': RequestStatus.completed,
            'completedAt': FieldValue.serverTimestamp(),
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Participants'),
        automaticallyImplyLeading: false, // No back button
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppColors.primary.withValues(alpha: 0.1),
                  child: Column(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 48,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Split Completed!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Please rate your experience with each participant',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // Participants list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _usersToRate.length,
                    itemBuilder: (context, index) {
                      final userId = _usersToRate[index];
                      return _buildParticipantCard(userId);
                    },
                  ),
                ),

                // Submit button
                Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                  ),
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
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting || !_allRated
                          ? null
                          : _submitReviews,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.success,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Submit Reviews',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildParticipantCard(String userId) {
    final profile = _profiles[userId];
    final displayName = profile?['displayName'] ?? 'User';
    final photoUrl = profile?['photoUrl'];
    final currentRating = _ratings[userId] ?? 0;

    // Determine feedback style
    final isLowRating = currentRating > 0 && currentRating <= 3;
    final isHighRating = currentRating >= 4;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLowRating
              ? AppColors.error.withValues(alpha: 0.3)
              : isHighRating
              ? AppColors.success.withValues(alpha: 0.3)
              : Colors.grey.shade200,
          width: isLowRating || isHighRating ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info
          Row(
            children: [
              UserAvatar(
                photoUrl: photoUrl,
                name: displayName,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Star rating
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starNumber = index + 1;
              final isSelected = currentRating >= starNumber;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _ratings[userId] = starNumber;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    isSelected
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 40,
                    color: isSelected
                        ? (starNumber <= 3 ? Colors.orange : Colors.amber)
                        : Colors.grey.shade300,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Feedback indicator
          if (currentRating > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isLowRating
                    ? AppColors.error.withValues(alpha: 0.1)
                    : AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isLowRating
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle,
                    size: 18,
                    color: isLowRating ? AppColors.error : AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      isLowRating
                          ? 'Low ratings will affect user\'s credibility'
                          : 'Positive feedback',
                      style: TextStyle(
                        fontSize: 13,
                        color: isLowRating
                            ? AppColors.error
                            : AppColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Comment field
          TextField(
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add a comment (optional)',
              hintStyle: TextStyle(color: AppColors.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (value) {
              _comments[userId] = value;
            },
          ),
        ],
      ),
    );
  }
}
