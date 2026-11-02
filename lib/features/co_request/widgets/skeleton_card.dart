import 'package:flutter/material.dart';

/// Skeleton/shimmer loading placeholder that mimics [RequestCard] layout.
/// Shown while Feed data is loading for a polished first impression.
class FeedSkeletonLoader extends StatefulWidget {
  const FeedSkeletonLoader({super.key});

  @override
  State<FeedSkeletonLoader> createState() => _FeedSkeletonLoaderState();
}

class _FeedSkeletonLoaderState extends State<FeedSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: 3,
          itemBuilder: (context, index) {
            return _SkeletonCard(shimmerValue: _animation.value);
          },
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double shimmerValue;

  const _SkeletonCard({required this.shimmerValue});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image area placeholder
          _ShimmerBox(
            width: double.infinity,
            height: 160,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            shimmerValue: shimmerValue,
          ),

          // Content area
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Deal description chip
                _ShimmerBox(
                  width: 100,
                  height: 24,
                  borderRadius: BorderRadius.circular(6),
                  shimmerValue: shimmerValue,
                ),
                const SizedBox(height: 10),

                // Product name line
                _ShimmerBox(
                  width: double.infinity,
                  height: 18,
                  borderRadius: BorderRadius.circular(4),
                  shimmerValue: shimmerValue,
                ),
                const SizedBox(height: 8),

                // Price row
                Row(
                  children: [
                    _ShimmerBox(
                      width: 80,
                      height: 16,
                      borderRadius: BorderRadius.circular(4),
                      shimmerValue: shimmerValue,
                    ),
                    const SizedBox(width: 12),
                    _ShimmerBox(
                      width: 60,
                      height: 16,
                      borderRadius: BorderRadius.circular(4),
                      shimmerValue: shimmerValue,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Location row
                Row(
                  children: [
                    _ShimmerBox(
                      width: 14,
                      height: 14,
                      borderRadius: BorderRadius.circular(7),
                      shimmerValue: shimmerValue,
                    ),
                    const SizedBox(width: 6),
                    _ShimmerBox(
                      width: 150,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                      shimmerValue: shimmerValue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final double shimmerValue;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.shimmerValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.grey[300]!,
            Colors.grey[100]!,
            Colors.grey[300]!,
          ],
          stops: [
            (shimmerValue - 0.3).clamp(0.0, 1.0),
            shimmerValue.clamp(0.0, 1.0),
            (shimmerValue + 0.3).clamp(0.0, 1.0),
          ],
        ),
      ),
    );
  }
}
