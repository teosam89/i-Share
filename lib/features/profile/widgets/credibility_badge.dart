import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/user_profile_model.dart';
import '../services/credibility_service.dart';

/// Widget to display user's credibility information
class CredibilityBadge extends StatelessWidget {
  final UserProfile profile;
  final bool compact;

  const CredibilityBadge({
    super.key,
    required this.profile,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact();
    }
    return _buildFull();
  }

  Widget _buildCompact() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Star rating
        Icon(Icons.star, color: Colors.amber, size: 14),
        const SizedBox(width: 2),
        Text(
          profile.rating > 0 ? profile.rating.toStringAsFixed(1) : 'New',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: profile.rating > 0
                ? AppColors.textPrimary
                : AppColors.textSecondary,
          ),
        ),
        if (profile.ratingCount > 0) ...[
          Text(
            ' (${profile.ratingCount})',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(width: 8),
        // Trust level badge
        _buildLevelBadge(),
      ],
    );
  }

  Widget _buildFull() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Credibility',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              _buildLevelBadge(),
            ],
          ),
          const SizedBox(height: 12),
          // Stats row
          Row(
            children: [
              _buildStatItem(
                icon: Icons.star,
                iconColor: Colors.amber,
                value: profile.rating > 0
                    ? profile.rating.toStringAsFixed(1)
                    : '-',
                label: '${profile.ratingCount} reviews',
              ),
              const SizedBox(width: 16),
              _buildStatItem(
                icon: Icons.shopping_bag_outlined,
                iconColor: AppColors.primary,
                value: '${profile.completedRequests}',
                label: 'deals',
              ),
              const SizedBox(width: 16),
              _buildStatItem(
                icon: Icons.calendar_today_outlined,
                iconColor: AppColors.secondary,
                value: _formatJoinDate(),
                label: 'member',
              ),
            ],
          ),
          // Verifications
          if (profile.verifications.verifiedCount > 0) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildVerifications(),
          ],
          // Badges
          if (profile.badges.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: profile.badges
                  .map((badge) => _buildBadgeChip(badge))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelBadge() {
    final level = profile.credibilityLevel;
    final color = Color(CredibilityService.getCredibilityColor(level));
    final iconPath = profile.credibilityIcon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(iconPath, width: 16, height: 16),
          const SizedBox(width: 4),
          Text(
            level,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifications() {
    return Row(
      children: [
        if (profile.verifications.email)
          _buildVerificationItem(Icons.email_outlined, 'Email'),
        if (profile.verifications.phone)
          _buildVerificationItem(Icons.phone_outlined, 'Phone'),
        if (profile.verifications.identity)
          _buildVerificationItem(Icons.verified_user_outlined, 'ID'),
      ],
    );
  }

  Widget _buildVerificationItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeChip(String badge) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        badge,
        style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
      ),
    );
  }

  String _formatJoinDate() {
    final months = DateTime.now().difference(profile.createdAt).inDays ~/ 30;
    if (months < 1) return 'New';
    if (months < 12) return '${months}mo';
    return '${months ~/ 12}yr';
  }
}
