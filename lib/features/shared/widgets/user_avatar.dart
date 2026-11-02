import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Shared avatar widget: shows a network photo when available,
/// falls back to the first letter of [name] on a tinted background.
class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;

  const UserAvatar({
    required this.photoUrl,
    required this.name,
    this.radius = 20,
    this.backgroundColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor:
          backgroundColor ?? AppColors.primary.withValues(alpha: 0.1),
      backgroundImage: hasPhoto ? CachedNetworkImageProvider(photoUrl!) : null,
      onBackgroundImageError: hasPhoto ? (_, __) {} : null,
      child: hasPhoto
          ? null
          : Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.7,
              ),
            ),
    );
  }
}
