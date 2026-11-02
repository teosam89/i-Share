import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Data for a single guide page in the carousel.
class _GuidePage {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final List<String> bullets;

  const _GuidePage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.bullets,
  });
}

/// App-wide user guide shown as a swipeable carousel bottom sheet.
/// Triggered by the "?" button on the Discover screen.
class UserGuideSheet extends StatefulWidget {
  const UserGuideSheet({super.key});

  @override
  State<UserGuideSheet> createState() => _UserGuideSheetState();
}

class _UserGuideSheetState extends State<UserGuideSheet> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_GuidePage> _pages = [
    _GuidePage(
      icon: Icons.explore_outlined,
      iconColor: Color(0xFF4CAF50),
      title: 'Discover Nearby Deals',
      description:
          'Browse co-buy requests from people around you on the Discover feed.',
      bullets: [
        'Filter by category: Food, Electronics, Beauty, and more',
        'Adjust your search radius to find closer deals',
        'Sort by price, distance, expiry, or newest',
        'Bookmark requests to revisit them later',
      ],
    ),
    _GuidePage(
      icon: Icons.add_shopping_cart_outlined,
      iconColor: Color(0xFF2196F3),
      title: 'Start a Co-Buy',
      description:
          'Create your own request when you want to share the cost of a purchase.',
      bullets: [
        'Set the product name, price per person, and quantity',
        'Choose how many partners you need',
        'Pin the pick-up location on the map',
        'Set a deadline — expired requests close automatically',
      ],
    ),
    _GuidePage(
      icon: Icons.group_outlined,
      iconColor: Color(0xFFFF9800),
      title: 'Join & Coordinate',
      description:
          'Found a deal you like? Join the request and coordinate with the group.',
      bullets: [
        'Tap any request to view full details',
        'Send a join request — the host reviews and accepts',
        'Once accepted, join the group chat automatically',
        'Share location or images in chat to coordinate pick-up',
      ],
    ),
    _GuidePage(
      icon: Icons.bolt_outlined,
      iconColor: Color(0xFF9C27B0),
      title: 'Real-Time Match',
      description:
          'Need a co-buyer right now? Real-Time Match finds someone instantly.',
      bullets: [
        'Enter what you want to buy and your intent',
        'Get matched with nearby users looking for the same thing',
        'Accept or skip suggestions in real time',
        'Matched users go straight into a group chat',
      ],
    ),
    _GuidePage(
      icon: Icons.verified_user_outlined,
      iconColor: Color(0xFFF44336),
      title: 'Profile & Credibility',
      description:
          'Your credibility score reflects how trustworthy you are as a co-buyer.',
      bullets: [
        'Score grows with every successful co-buy',
        'Ratings from partners appear on your profile',
        'Higher scores make others more likely to accept you',
        'View your past requests and transaction history',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              children: [
                Text(
                  'How to use i-Share',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_currentPage + 1} / ${_pages.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Carousel
          SizedBox(
            height: 340,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) =>
                  _buildPage(_pages[index]),
            ),
          ),

          // Dot indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (i) {
              final active = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),

          const SizedBox(height: 20),

          // Navigation buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _goToPage(_currentPage - 1),
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentPage > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _currentPage < _pages.length - 1
                        ? () => _goToPage(_currentPage + 1)
                        : () => Navigator.pop(context),
                    child: Text(
                      _currentPage < _pages.length - 1 ? 'Next' : 'Got it!',
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildPage(_GuidePage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon circle
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: page.iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(page.icon, size: 36, color: page.iconColor),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Center(
            child: Text(
              page.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Description
          Center(
            child: Text(
              page.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bullet points
          ...page.bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: page.iconColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
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
}

/// Show the user guide as a modal bottom sheet.
void showUserGuide(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const UserGuideSheet(),
  );
}
