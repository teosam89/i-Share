import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/services/auth_provider.dart';
import '../../co_request/screens/feed_screen.dart';
import '../../co_request/screens/my_requests_screen.dart';
import '../../co_request/screens/create_request_screen.dart';
import '../../co_request/providers/co_request_provider.dart';
import '../../chat/services/chat_service.dart';
import '../../co_request/services/join_request_service.dart';
import '../../chat/models/chat_model.dart';
import '../../chat/screens/chat_list_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../profile/services/profile_service.dart';
import '../../realtime_match/screens/realtime_match_screen.dart';
import '../../realtime_match/widgets/active_match_indicator.dart';
import '../../realtime_match/services/realtime_match_service.dart';
import '../../realtime_match/models/realtime_match_model.dart';

/// MainScreen - App shell with bottom navigation
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<bool> _tabVisited = [true, false, false, false];
  final ProfileService _profileService = ProfileService();
  /// Nav badge stream only — NOT shared with ChatListScreen.
  /// ChatListScreen owns its own subscription to avoid late-subscriber spinner.
  late final Stream<List<ChatRoom>> _chatRoomsStream;

  @override
  void initState() {
    super.initState();
    // Single shared stream — nav badge and chat tab both listen to this
    _chatRoomsStream = ChatService().getUserChatRooms();
    // Ensure user profile exists
    _profileService.getOrCreateProfile();
    _profileService.updateLastActive();
    // Show first-visit guide (once only)
    _showFirstVisitGuide();
  }

  Future<void> _showFirstVisitGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('hasSeenAppGuide') == true) return;

    // Wait for first frame to render before showing
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to i-Share!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Here\'s a quick overview',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              _buildGuideItem(
                Icons.explore,
                AppColors.primary,
                'Discover',
                'Browse nearby deals and co-buying requests on the feed or map.',
              ),
              _buildGuideItem(
                Icons.add_circle,
                AppColors.accent,
                'Create or Match',
                'Tap the + button to create a request or find a partner instantly.',
              ),
              _buildGuideItem(
                Icons.chat_bubble,
                AppColors.secondary,
                'Chat',
                'Coordinate with your co-buying partners in real time.',
              ),
              _buildGuideItem(
                Icons.qr_code_scanner,
                AppColors.info,
                'Verify & Review',
                'Scan QR codes to verify meetups, then rate your experience.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Got it!', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await prefs.setBool('hasSeenAppGuide', true);
  }

  Widget _buildGuideItem(
    IconData icon,
    Color color,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              const FeedScreen(),
              _tabVisited[1] ? const MyRequestsScreen() : const SizedBox.shrink(),
              _tabVisited[2] ? const ChatListScreen() : const SizedBox.shrink(),
              _tabVisited[3] ? _buildProfileTab()       : const SizedBox.shrink(),
            ],
          ),
          // Floating indicator for active matches
          const ActiveMatchIndicator(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _buildNavItem(
                  0,
                  Icons.explore_outlined,
                  Icons.explore,
                  'Discover',
                ),
              ),
              Expanded(child: _buildMySplitsNavItem()),
              // Center Add Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildAddButton(),
              ),
              Expanded(child: _buildChatsNavItem()),
              Expanded(
                child: _buildNavItem(
                  3,
                  Icons.person_outline,
                  Icons.person,
                  'Profile',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    final matchService = RealtimeMatchService();

    return StreamBuilder<List<RealtimeMatch>>(
      stream: matchService.getUserMatches(),
      builder: (context, snapshot) {
        final hasActiveMatch = (snapshot.data ?? []).isNotEmpty;

        return GestureDetector(
          onTap: () => _showAddOptionsSheet(hasActiveMatch),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
        );
      },
    );
  }

  void _showAddOptionsSheet(bool hasActiveMatch) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Create New',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            // Create Request option
            _buildSheetOption(
              icon: Icons.add_shopping_cart,
              iconColor: AppColors.primary,
              title: 'Create Request',
              subtitle: 'Share bulk purchases with others',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateRequestScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            // Real Time Match option
            _buildSheetOption(
              icon: Icons.radar,
              iconColor: hasActiveMatch ? Colors.grey : AppColors.accent,
              title: hasActiveMatch ? 'Matching...' : 'Real Time Match',
              subtitle: hasActiveMatch
                  ? 'You have an active match'
                  : 'Find nearby partners instantly',
              enabled: !hasActiveMatch,
              onTap: () {
                Navigator.pop(context);
                if (hasActiveMatch) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please leave your current match first.'),
                      backgroundColor: AppColors.warning,
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RealtimeMatchScreen(),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: enabled ? onTap : null,
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    bool showBadge = false,
    VoidCallback? onTapExtra,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
          _tabVisited[index] = true;
        });
        onTapExtra?.call();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 22,
                ),
                if (showBadge)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// My Splits nav item with notification dot for pending join requests.
  /// Triggers a silent background refresh on every tap so host-approved
  /// joins and newly created requests appear without restarting the app.
  Widget _buildMySplitsNavItem() {
    final userId = context.read<AuthProvider>().userId;

    void silentRefresh() =>
        context.read<CoRequestProvider>().loadMyRequests(silent: true);

    if (userId == null) {
      return _buildNavItem(
        1,
        Icons.receipt_long_outlined,
        Icons.receipt_long,
        'My Splits',
        onTapExtra: silentRefresh,
      );
    }

    return StreamBuilder<int>(
      stream: JoinRequestService().getPendingRequestCount(),
      builder: (context, snapshot) {
        final hasPending = (snapshot.data ?? 0) > 0;
        return _buildNavItem(
          1,
          Icons.receipt_long_outlined,
          Icons.receipt_long,
          'My Splits',
          showBadge: hasPending,
          onTapExtra: silentRefresh,
        );
      },
    );
  }

  /// Chats nav item with notification dot for unread messages
  /// Uses per-user lastReadAt timestamps — no nested queries needed
  Widget _buildChatsNavItem() {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      return _buildNavItem(
        2,
        Icons.chat_bubble_outline,
        Icons.chat_bubble,
        'Chats',
      );
    }

    return StreamBuilder<List<ChatRoom>>(
      stream: _chatRoomsStream,
      builder: (context, snapshot) {
        final hasUnread =
            snapshot.hasData &&
            snapshot.data!.any((room) => room.hasUnread(userId));

        return _buildNavItem(
          2,
          Icons.chat_bubble_outline,
          Icons.chat_bubble,
          'Chats',
          showBadge: hasUnread,
        );
      },
    );
  }

  Widget _buildProfileTab() {
    final authProvider = context.watch<AuthProvider>();
    final userId = authProvider.userId ?? '';

    return ProfileScreen(userId: userId, isCurrentUser: true);
  }

}
