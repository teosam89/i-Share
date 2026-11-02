import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/network_aware_widget.dart';
import '../../../core/constants/request_status.dart';
import '../providers/co_request_provider.dart';
import '../services/join_request_service.dart';
import '../widgets/request_card.dart';
import '../widgets/common_widgets.dart';
import 'create_request_screen.dart';
import 'request_detail_screen.dart';

/// My Requests Screen - Displays user's own created requests
/// Allows Edit/Delete management
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Refresh My/Joined requests when this tab is first visited.
    // The provider loads data once on initialize(); this keeps it fresh
    // without a permanent real-time stream subscription.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CoRequestProvider>().loadMyRequests();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildTabWithBadge(String text, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Requests'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Consumer<CoRequestProvider>(
            builder: (context, provider, _) {
              final activeCount = provider
                  .getMyRequestsByStatus(RequestStatus.active)
                  .length;
              final matchedCount = provider
                  .getMyRequestsByStatus(RequestStatus.matched)
                  .length;
              final completedCount = provider
                  .getMyRequestsByStatus(RequestStatus.completed)
                  .length;

              return TabBar(
                controller: _tabController,
                tabs: [
                  _buildTabWithBadge('Active', activeCount),
                  _buildTabWithBadge('Matched', matchedCount),
                  _buildTabWithBadge('Completed', completedCount),
                ],
              );
            },
          ),
        ),
      ),
      body: Column(
        children: [
          const NetworkStatusBanner(),
          Expanded(
            child: Consumer<CoRequestProvider>(
              builder: (context, provider, child) {
                if (provider.isLoadingMyRequests) {
                  return const Center(child: CircularProgressIndicator());
                }
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRequestList(provider, RequestStatus.active),
                    _buildRequestList(provider, RequestStatus.matched),
                    _buildRequestList(provider, RequestStatus.completed),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestList(CoRequestProvider provider, String status) {
    final requests = provider.getMyRequestsByStatus(status);

    if (requests.isEmpty) {
      // RefreshIndicator on empty state so users can pull-to-refresh
      // even before any data exists (e.g. right after creating first request).
      return RefreshIndicator(
        onRefresh: () async => provider.loadMyRequests(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: 400,
            child: EmptyStateWidget(
              icon: status == RequestStatus.active
                  ? Icons.post_add_outlined
                  : status == RequestStatus.matched
                  ? Icons.handshake_outlined
                  : Icons.check_circle_outline,
              title: status == RequestStatus.active
                  ? 'No active requests'
                  : status == RequestStatus.matched
                  ? 'No matched requests'
                  : 'No completed requests',
              subtitle: status == RequestStatus.active
                  ? 'Create a new split request to find partners'
                  : status == RequestStatus.matched
                  ? 'Matched requests will appear here'
                  : 'Your completed splits will be shown here',
              actionLabel:
                  status == RequestStatus.active ? 'Create Request' : null,
              onAction: status == RequestStatus.active
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateRequestScreen(),
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.loadMyRequests();
      },
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final request = requests[index];
          // Only show edit/delete for active requests user created (not completed/cancelled)
          final isOwner = provider.isMyRequest(request);
          final isActive = request.status == RequestStatus.active;
          final canModify = isOwner && isActive;

          // Use StreamBuilder to get real-time pending join request count
          return StreamBuilder<int>(
            stream: JoinRequestService()
                .getPendingJoinRequests(request.id)
                .map((requests) => requests.length),
            initialData: 0,
            builder: (context, snapshot) {
              final pendingCount = snapshot.data ?? 0;
              return RequestCard(
                request: request,
                showDistance: false,
                showActions: canModify,
                pendingCount: isOwner && isActive ? pendingCount : 0,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestDetailScreen(request: request),
                  ),
                ),
                onEdit: canModify
                    ? () => _showEditRequest(context, request)
                    : null,
                onDelete: canModify
                    ? () => _showDeleteConfirmation(context, provider, request)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  /// Navigate to edit request screen
  void _showEditRequest(BuildContext context, dynamic request) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateRequestScreen(editRequest: request),
      ),
    );
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(
    BuildContext context,
    CoRequestProvider provider,
    dynamic request,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Request?'),
        content: Text(
          'Are you sure you want to delete "${request.productName}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await provider.deleteRequest(request.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Request deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Something went wrong. Please try again.',
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
