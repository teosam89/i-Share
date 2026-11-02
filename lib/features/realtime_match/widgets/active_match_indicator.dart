import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/realtime_match_model.dart';
import '../services/realtime_match_service.dart';
import '../screens/match_waiting_screen.dart';

/// ActiveMatchIndicator - Draggable floating widget to show active match status
/// Shows when user has an active match and is not on the match screen
class ActiveMatchIndicator extends StatefulWidget {
  const ActiveMatchIndicator({super.key});

  @override
  State<ActiveMatchIndicator> createState() => _ActiveMatchIndicatorState();
}

class _ActiveMatchIndicatorState extends State<ActiveMatchIndicator> {
  // Position of the floating indicator
  double _xPos = -1; // -1 means not initialized
  double _yPos = -1;

  @override
  Widget build(BuildContext context) {
    final matchService = RealtimeMatchService();
    final screenSize = MediaQuery.of(context).size;

    // Initialize position if not set
    if (_xPos < 0) {
      _xPos = screenSize.width * 0.55;
      _yPos = screenSize.height - 200;
    }

    return StreamBuilder<List<RealtimeMatch>>(
      stream: matchService.getUserMatches(),
      builder: (context, snapshot) {
        final matches = snapshot.data ?? [];

        // Only show if user has active matches
        if (matches.isEmpty) return const SizedBox.shrink();

        final activeMatch = matches.firstOrNull;
        if (activeMatch == null) return const SizedBox.shrink();

        final isWaiting = activeMatch.status == 'waiting';

        return Positioned(
          left: _xPos,
          top: _yPos,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _xPos += details.delta.dx;
                _yPos += details.delta.dy;

                // Keep within screen bounds
                _xPos = _xPos.clamp(0, screenSize.width - 150);
                _yPos = _yPos.clamp(0, screenSize.height - 150);
              });
            },
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchWaitingScreen(matchId: activeMatch.id),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isWaiting
                      ? [
                          AppColors.warning,
                          AppColors.warning.withValues(alpha: 0.8),
                        ]
                      : [
                          AppColors.success,
                          AppColors.success.withValues(alpha: 0.8),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: (isWaiting ? AppColors.warning : AppColors.success)
                        .withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulsing radar icon for waiting
                  if (isWaiting)
                    _PulsingIcon(icon: Icons.radar, color: Colors.white)
                  else
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    isWaiting ? 'Matching...' : 'Matched!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pulsing animation for the radar icon
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Icon(widget.icon, color: widget.color, size: 20),
        );
      },
    );
  }
}
