import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../models/co_request_model.dart';
import '../providers/co_request_provider.dart';
import '../services/location_service.dart';
import '../../realtime_match/models/realtime_match_model.dart';
import '../../realtime_match/services/realtime_match_service.dart';
import 'request_detail_screen.dart';

/// Map View Screen - Displays requests on an interactive map
/// Features: Dynamic markers, user tracker, radius slider, auto-zoom
class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  final RealtimeMatchService _realtimeMatchService = RealtimeMatchService();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _currentPosition;
  Set<Marker> _markers = {};
  bool _isLoading = true;
  double _searchRadius = 5.0; // km
  CoRequest? _selectedRequest;
  String _searchQuery = '';
  bool _showLegend = false;
  String? _selectedCategory;
  double _currentZoom = 14.0;
  static const double _clusterZoomThreshold = 13.5;

  // Real-time match data
  List<RealtimeMatch> _realtimeMatches = [];
  StreamSubscription<List<RealtimeMatch>>? _rtmSubscription;
  final bool _showRealtimeMatches =
      true; // Toggle to show/hide real-time match pins

  // Radius options in km
  final List<double> _radiusOptions = [0.5, 1.0, 2.0, 5.0, 10.0];

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _listenToRealtimeMatches();
  }

  void _listenToRealtimeMatches() {
    _rtmSubscription = _realtimeMatchService.getActiveMatchesStream().listen((
      matches,
    ) {
      if (mounted) {
        setState(() => _realtimeMatches = matches);
        _updateMarkers();
      }
    });
  }

  Future<void> _initializeLocation() async {
    try {
      final position = await _locationService.getCurrentPosition();
      if (mounted && position != null) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });
        _updateMarkers();
      } else if (mounted) {
        setState(() {
          _currentPosition = LatLng(AppConstants.defaultLatitude, AppConstants.defaultLongitude);
          _isLoading = false;
        });
        _updateMarkers();
      }
    } catch (e) {
      debugPrint('[MapViewScreen] Location error: $e');
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(AppConstants.defaultLatitude, AppConstants.defaultLongitude);
          _isLoading = false;
        });
        _updateMarkers();
      }
    }
  }

  /// Get zoom level based on radius
  double _getZoomLevel(double radiusKm) {
    if (radiusKm <= 0.5) return 16.0;
    if (radiusKm <= 1.0) return 15.0;
    if (radiusKm <= 2.0) return 14.0;
    if (radiusKm <= 5.0) return 12.5;
    if (radiusKm <= 10.0) return 11.5;
    return 10.0;
  }

  /// Handle radius change with auto-zoom
  void _onRadiusChanged(double radius) {
    setState(() => _searchRadius = radius);
    _updateMarkers();

    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_currentPosition!, _getZoomLevel(radius)),
      );
    }
  }

  /// Get marker color based on category
  double _getCategoryHue(String category) {
    switch (category) {
      case 'groceries':
      case 'food': // legacy compat
        return BitmapDescriptor.hueGreen;
      case 'fresh':
        return BitmapDescriptor.hueYellow;
      case 'snacks':
        return BitmapDescriptor.hueOrange;
      case 'household':
        return BitmapDescriptor.hueCyan;
      case 'personal':
        return BitmapDescriptor.hueRose;
      case 'baby_pets':
        return BitmapDescriptor.hueMagenta;
      case 'electronics':
        return BitmapDescriptor.hueViolet;
      case 'others':
        return BitmapDescriptor.hueAzure;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  /// Update markers based on filtered requests
  void _updateMarkers() {
    final provider = context.read<CoRequestProvider>();
    final requests = provider.allRequests;

    final newMarkers = <Marker>{};

    // Collect filtered co-requests first
    final filteredRequests = <CoRequest>[];
    for (final request in requests) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesSearch =
            request.productName.toLowerCase().contains(query) ||
            request.dealDescription.toLowerCase().contains(query) ||
            request.storeName.toLowerCase().contains(query);
        if (!matchesSearch) continue;
      }
      if (_selectedCategory != null &&
          _selectedCategory != 'realtime' &&
          request.category.toLowerCase() != _selectedCategory!.toLowerCase()) {
        continue;
      }
      if (_selectedCategory == 'realtime') continue;
      if (_currentPosition != null) {
        final distance = _locationService.calculateDistance(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          request.latitude,
          request.longitude,
        );
        if (distance > _searchRadius * 1000) continue;
      }
      filteredRequests.add(request);
    }

    // Cluster or show individually based on zoom level
    if (_currentZoom < _clusterZoomThreshold && filteredRequests.length > 5) {
      // Grid-based clustering at low zoom
      final cellSize = 0.01 * (15 - _currentZoom).clamp(1.0, 5.0);
      final clusters = <String, List<CoRequest>>{};
      for (final request in filteredRequests) {
        final cellX = (request.latitude / cellSize).floor();
        final cellY = (request.longitude / cellSize).floor();
        final key = '$cellX,$cellY';
        clusters.putIfAbsent(key, () => []).add(request);
      }

      for (final entry in clusters.entries) {
        final clusterRequests = entry.value;
        // Use the first request's position as the cluster center
        final center = clusterRequests.first;
        if (clusterRequests.length == 1) {
          newMarkers.add(_buildRequestMarker(center));
        } else {
          // Cluster marker
          newMarkers.add(Marker(
            markerId: MarkerId('cluster_${entry.key}'),
            position: LatLng(center.latitude, center.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueViolet,
            ),
            infoWindow: InfoWindow(
              title: '${clusterRequests.length} deals nearby',
              snippet: 'Zoom in to see details',
            ),
            onTap: () {
              _mapController?.animateCamera(
                CameraUpdate.newLatLngZoom(
                  LatLng(center.latitude, center.longitude),
                  _clusterZoomThreshold + 1,
                ),
              );
            },
          ));
        }
      }
    } else {
      // Show individual markers
      for (final request in filteredRequests) {
        newMarkers.add(_buildRequestMarker(request));
      }
    }

    // Add Real-Time Match markers (blue pins)
    if (_showRealtimeMatches) {
      for (final match in _realtimeMatches) {
        // Skip if filtering by non-realtime category
        if (_selectedCategory != null && _selectedCategory != 'realtime') {
          continue;
        }

        // Filter by radius
        if (_currentPosition != null) {
          final distance = _locationService.calculateDistance(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            match.latitude,
            match.longitude,
          );

          if (distance > _searchRadius * 1000) continue;
        }

        final categoryLabel =
            RequestCategories.labels[match.category] ?? match.category;
        final partnerInfo =
            '${match.participantCount}/${match.maxPartners + 1} partners';

        final marker = Marker(
          markerId: MarkerId('rtm_${match.id}'),
          position: LatLng(match.latitude, match.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: '$categoryLabel (LIVE)',
            snippet: partnerInfo,
          ),
        );

        newMarkers.add(marker);
      }
    }

    if (mounted) {
      setState(() => _markers = newMarkers);
    }
  }

  Marker _buildRequestMarker(CoRequest request) {
    return Marker(
      markerId: MarkerId(request.id),
      position: LatLng(request.latitude, request.longitude),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        _getCategoryHue(request.category),
      ),
      infoWindow: InfoWindow(
        title: request.productName,
        snippet: 'RM ${request.pricePerPerson.toStringAsFixed(2)}/person',
        onTap: () => _showRequestDetail(request),
      ),
      onTap: () {
        setState(() => _selectedRequest = request);
      },
    );
  }

  void _showRequestDetail(CoRequest request) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RequestDetailScreen(request: request)),
    );
  }

  void _moveToCurrentLocation() async {
    if (_currentPosition != null && _mapController != null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          _currentPosition!,
          _getZoomLevel(_searchRadius),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Deals Map'),
        actions: [
          // Search button
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(),
          ),
          // Legend toggle
          IconButton(
            icon: Icon(
              _showLegend ? Icons.legend_toggle : Icons.legend_toggle_outlined,
            ),
            onPressed: () => setState(() => _showLegend = !_showLegend),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Google Map
                Consumer<CoRequestProvider>(
                  builder: (context, provider, child) {
                    return GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target:
                            _currentPosition ?? LatLng(AppConstants.defaultLatitude, AppConstants.defaultLongitude),
                        zoom: _getZoomLevel(_searchRadius),
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _updateMarkers();
                      },
                      onCameraMove: (position) {
                        if ((_currentZoom < _clusterZoomThreshold) !=
                            (position.zoom < _clusterZoomThreshold)) {
                          _currentZoom = position.zoom;
                          _updateMarkers();
                        }
                        _currentZoom = position.zoom;
                      },
                      markers: _markers,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      circles: _currentPosition != null
                          ? {
                              Circle(
                                circleId: const CircleId('radius'),
                                center: _currentPosition!,
                                radius: _searchRadius * 1000,
                                fillColor: AppColors.primary.withValues(
                                  alpha: 0.1,
                                ),
                                strokeColor: AppColors.primary.withValues(
                                  alpha: 0.3,
                                ),
                                strokeWidth: 2,
                              ),
                            }
                          : {},
                    );
                  },
                ),

                // Category legend (top right, collapsible)
                if (_showLegend)
                  Positioned(top: 16, right: 16, child: _buildLegendCard()),

                // Stats pill (top left)
                Positioned(top: 16, left: 16, child: _buildStatsPill()),

                // Selected request card
                if (_selectedRequest != null)
                  Positioned(
                    bottom: 180,
                    left: 16,
                    right: 16,
                    child: _buildRequestCard(_selectedRequest!),
                  ),

                // Bottom control panel
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomControlPanel(),
                ),

                // My location button
                Positioned(
                  bottom: 180,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'myLocation',
                    onPressed: _moveToCurrentLocation,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.my_location, color: AppColors.primary),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatsPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            '${_markers.length} deals',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (_selectedCategory != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _selectedCategory!,
                    style: TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      setState(() => _selectedCategory = null);
                      _updateMarkers();
                    },
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Map category keys to legend colors (must match _getCategoryHue)
  static const Map<String, Color> _categoryColors = {
    'groceries': Colors.green,
    'fresh': Colors.yellow,
    'snacks': Colors.orange,
    'household': Colors.teal,
    'personal': Colors.pink,
    'baby_pets': Colors.purple,
    'electronics': Colors.deepPurple,
    'others': Colors.blue,
  };

  Widget _buildLegendCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Categories',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...RequestCategories.all.map(
            (cat) => _buildLegendItem(
              Icons.location_on,
              RequestCategories.labels[cat]!,
              cat,
              _categoryColors[cat] ?? Colors.grey,
            ),
          ),
          const Divider(height: 16),
          _buildRealtimeLegendItem(),
        ],
      ),
    );
  }

  Widget _buildRealtimeLegendItem() {
    final isSelected = _selectedCategory == 'realtime';
    final color = AppColors.primary;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = isSelected ? null : 'realtime';
        });
        _updateMarkers();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              'Real-Time',
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_realtimeMatches.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                '(${_realtimeMatches.length})',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(
    IconData icon,
    String label,
    String category,
    Color color,
  ) {
    final isSelected =
        _selectedCategory?.toLowerCase() == category.toLowerCase();
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedCategory = isSelected ? null : category;
        });
        _updateMarkers();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControlPanel() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Radius label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Search Radius',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _searchRadius >= 1
                      ? '${_searchRadius.toInt()} km'
                      : '${(_searchRadius * 1000).toInt()} m',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Radius slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.primary.withValues(alpha: 0.2),
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.1),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: _radiusOptions.indexOf(_searchRadius).toDouble(),
              min: 0,
              max: (_radiusOptions.length - 1).toDouble(),
              divisions: _radiusOptions.length - 1,
              onChanged: (value) {
                _onRadiusChanged(_radiusOptions[value.toInt()]);
              },
            ),
          ),

          // Radius labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _radiusOptions.map((r) {
              return Text(
                r >= 1 ? '${r.toInt()}km' : '${(r * 1000).toInt()}m',
                style: TextStyle(
                  fontSize: 10,
                  color: _searchRadius == r
                      ? AppColors.primary
                      : AppColors.textTertiary,
                  fontWeight: _searchRadius == r
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Deals'),
        content: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search products, stores...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                      _updateMarkers();
                      Navigator.pop(context);
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() => _searchQuery = value);
            _updateMarkers();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(CoRequest request) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _showRequestDetail(request),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Product image or placeholder
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: request.productPhotoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: request.productPhotoUrl!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(Icons.image_outlined, color: AppColors.textTertiary),
              ),
              const SizedBox(width: 12),

              // Request info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.productName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.store,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            request.storeName,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RM ${request.pricePerPerson.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      request.timeRemaining,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              // Close button
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() => _selectedRequest = null);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _rtmSubscription?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
