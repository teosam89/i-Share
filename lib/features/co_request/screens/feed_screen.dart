import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/network_aware_widget.dart';
import '../models/co_request_model.dart';
import '../providers/co_request_provider.dart';
import '../widgets/request_card.dart';
import '../widgets/common_widgets.dart';
import '../widgets/skeleton_card.dart';
import '../../../core/constants/join_status.dart';
import 'create_request_screen.dart';
import 'request_detail_screen.dart';
import 'map_view_screen.dart';
import '../services/bookmark_service.dart';
import '../widgets/user_guide_sheet.dart';

/// Sort options for the feed
enum SortOption {
  newest, // By creation time (newest first)
  expiringSoon, // By expiry time (expiring soon first)
  alphabetical, // By product name A-Z
  priceLowHigh, // By price per person (low to high)
  priceHighLow, // By price per person (high to low)
  nearest, // By distance (nearest first)
  mostPartners, // By partners needed (most first)
}

/// Feed Screen - Displays nearby co-requests from Firestore
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'all';
  SortOption _currentSort = SortOption.nearest;
  Timer? _debounceTimer;
  String _debouncedQuery = '';
  bool _showSavedOnly = false;
  Set<String> _bookmarkedIds = {};

  // Track request IDs that the current user has pending join requests for
  Set<String> _pendingRequestIds = {};
  @override
  void initState() {
    super.initState();
    // Initialize and load data from Firestore
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CoRequestProvider>().initialize();
    });
    _loadPendingJoinRequests();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await BookmarkService().getBookmarks();
    if (mounted) setState(() => _bookmarkedIds = bookmarks);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Fetch current user's pending join requests (one-time, not real-time).
  /// collectionGroup('join_requests') scans ALL subcollections — using
  /// .snapshots() here fires on every join-request change across the entire
  /// database, which is very expensive at scale. One-time .get() + refresh
  /// on pull-to-refresh is sufficient for showing the "Pending" badge.
  Future<void> _loadPendingJoinRequests() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('join_requests')
          .where('requesterId', isEqualTo: userId)
          .where('status', isEqualTo: JoinStatus.pending)
          .get();

      if (!mounted) return;
      setState(() {
        _pendingRequestIds = snapshot.docs
            .map((doc) => doc.data()['requestId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      });
    } catch (e) {
      debugPrint('Error loading pending join requests: $e');
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _debouncedQuery = query);
      }
    });
  }

  List<CoRequest> _getFilteredAndSortedRequests(List<CoRequest> requests) {
    var filtered = requests;

    // FATAL FIX #1: Filter out expired requests
    filtered = filtered.where((r) => !r.isExpired).toList();

    // Filter out full requests (participants.length >= partnersNeeded + 1)
    // Note: participants now includes initiator, so total = partnersNeeded + 1
    filtered = filtered
        .where((r) => r.participants.length < r.partnersNeeded + 1)
        .toList();

    // Filter by category
    if (_selectedCategory != 'all') {
      filtered = filtered
          .where((r) => r.category == _selectedCategory)
          .toList();
    }

    // Filter by search (using debounced query)
    final searchQuery = _debouncedQuery.toLowerCase();
    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (r) =>
                r.productName.toLowerCase().contains(searchQuery) ||
                r.dealDescription.toLowerCase().contains(searchQuery) ||
                r.storeName.toLowerCase().contains(searchQuery),
          )
          .toList();
    }

    // Filter by saved/bookmarked
    if (_showSavedOnly) {
      filtered = filtered.where((r) => _bookmarkedIds.contains(r.id)).toList();
    }

    // Apply sorting
    filtered = _applySorting(filtered);

    return filtered;
  }

  List<CoRequest> _applySorting(List<CoRequest> requests) {
    final sorted = List<CoRequest>.from(requests);

    switch (_currentSort) {
      case SortOption.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.expiringSoon:
        sorted.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
        break;
      case SortOption.alphabetical:
        sorted.sort(
          (a, b) => a.productName.toLowerCase().compareTo(
            b.productName.toLowerCase(),
          ),
        );
        break;
      case SortOption.priceLowHigh:
        sorted.sort((a, b) => a.pricePerPerson.compareTo(b.pricePerPerson));
        break;
      case SortOption.priceHighLow:
        sorted.sort((a, b) => b.pricePerPerson.compareTo(a.pricePerPerson));
        break;
      case SortOption.nearest:
        sorted.sort((a, b) {
          final distA = a.distanceMeters ?? double.infinity;
          final distB = b.distanceMeters ?? double.infinity;
          return distA.compareTo(distB);
        });
        break;
      case SortOption.mostPartners:
        sorted.sort((a, b) => b.partnersNeeded.compareTo(a.partnersNeeded));
        break;
    }

    return sorted;
  }

  String _getSortLabel(SortOption option) {
    switch (option) {
      case SortOption.newest:
        return 'Newest First';
      case SortOption.expiringSoon:
        return 'Expiring Soon';
      case SortOption.alphabetical:
        return 'A-Z';
      case SortOption.priceLowHigh:
        return 'Price: Low to High';
      case SortOption.priceHighLow:
        return 'Price: High to Low';
      case SortOption.nearest:
        return 'Nearest';
      case SortOption.mostPartners:
        return 'Most Partners';
    }
  }

  IconData _getSortIcon(SortOption option) {
    switch (option) {
      case SortOption.newest:
        return Icons.schedule;
      case SortOption.expiringSoon:
        return Icons.timer_outlined;
      case SortOption.alphabetical:
        return Icons.sort_by_alpha;
      case SortOption.priceLowHigh:
        return Icons.arrow_upward;
      case SortOption.priceHighLow:
        return Icons.arrow_downward;
      case SortOption.nearest:
        return Icons.near_me;
      case SortOption.mostPartners:
        return Icons.group;
    }
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Sort By',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),

              // Sort options
              ...SortOption.values.map((option) => _buildSortOption(option)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortOption(SortOption option) {
    final isSelected = _currentSort == option;
    return ListTile(
      leading: Icon(
        _getSortIcon(option),
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Text(
        _getSortLabel(option),
        style: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.primary)
          : null,
      onTap: () {
        setState(() => _currentSort = option);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.help_outline_rounded),
          tooltip: 'App Guide',
          onPressed: () => showUserGuide(context),
        ),
        title: const Text('Nearby Deals'),
        actions: [
          IconButton(
            icon: Icon(
              _showSavedOnly ? Icons.bookmark : Icons.bookmark_border,
              color: _showSavedOnly ? AppColors.primary : null,
            ),
            tooltip: 'Saved',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!_showSavedOnly) await _loadBookmarks();
              final entering = !_showSavedOnly;
              setState(() => _showSavedOnly = entering);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      entering ? 'Showing saved requests' : 'Showing all requests',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapViewScreen()),
              );
            },
            tooltip: 'Map View',
          ),
        ],
      ),
      body: Consumer<CoRequestProvider>(
        builder: (context, provider, _) {
          final filteredRequests = _getFilteredAndSortedRequests(
            provider.allRequests,
          );

          return Column(
            children: [
              // Network status banner
              const NetworkStatusBanner(),

              // Search Bar
              RequestSearchBar(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onClear: () {
                  _debounceTimer?.cancel();
                  setState(() => _debouncedQuery = '');
                },
              ),

              // Category Filter
              CategoryFilterChips(
                selectedCategory: _selectedCategory,
                onCategorySelected: (category) {
                  setState(() => _selectedCategory = category);
                },
              ),

              const SizedBox(height: 8),

              // Results Count & Sort Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '${filteredRequests.length} deals nearby',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showSortBottomSheet,
                      icon: const Icon(Icons.sort, size: 18),
                      label: Text(_getSortLabel(_currentSort)),
                    ),
                  ],
                ),
              ),

              // Request List
              Expanded(
                child: provider.isLoadingFeed
                    ? const FeedSkeletonLoader()
                    : filteredRequests.isEmpty
                    ? EmptyStateWidget(
                        icon: Icons.shopping_bag_outlined,
                        title: 'No deals found',
                        subtitle: _searchController.text.isNotEmpty
                            ? 'Try a different search term'
                            : 'Be the first to create a split request!',
                        actionLabel: 'Create Request',
                        onAction: () => _navigateToCreate(),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Future.wait([
                            provider.loadFeedRequests(),
                            _loadPendingJoinRequests(),
                          ]);
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: filteredRequests.length,
                          itemBuilder: (context, index) {
                            final request = filteredRequests[index];
                            return RequestCard(
                              request: request,
                              isPendingApproval: _pendingRequestIds.contains(
                                request.id,
                              ),
                              isBookmarked: _bookmarkedIds.contains(request.id),
                              onTap: () => _navigateToDetail(request),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _navigateToCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRequestScreen()),
    );
    // Refresh feed after creating a request
    if (mounted) {
      context.read<CoRequestProvider>().loadFeedRequests();
    }
  }

  void _navigateToDetail(CoRequest request) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RequestDetailScreen(request: request)),
    );
    // Refresh bookmark state when returning — user may have bookmarked in detail
    if (mounted) _loadBookmarks();
  }
}
