import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/network_aware_widget.dart';
import '../../co_request/models/co_request_model.dart';
import '../../co_request/services/location_service.dart';
import '../../co_request/screens/location_picker_screen.dart';
import '../models/realtime_match_model.dart';
import '../services/realtime_match_service.dart';
import 'match_waiting_screen.dart';

/// RealtimeMatchScreen - Select location, radius, partner count, and category to start matching
class RealtimeMatchScreen extends StatefulWidget {
  const RealtimeMatchScreen({super.key});

  @override
  State<RealtimeMatchScreen> createState() => _RealtimeMatchScreenState();
}

class _RealtimeMatchScreenState extends State<RealtimeMatchScreen> {
  final LocationService _locationService = LocationService();
  final RealtimeMatchService _matchService = RealtimeMatchService();
  final TextEditingController _productIntentController =
      TextEditingController();

  // Step tracking (5 steps: location, radius, partners, category, intent)
  int _currentStep = 0;

  // Location
  Position? _currentPosition;
  String _locationName = '';
  bool _isLoadingLocation = true;
  bool _useCurrentLocation =
      true; // Track if using current or searched location

  // Radius
  double _selectedRadius = 2.0;
  GoogleMapController? _mapController; // For dynamic zoom

  // Partner count
  int _selectedPartnerCount = 1;

  // Category
  String? _selectedCategory;

  // Matching
  bool _isMatching = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _productIntentController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    final position = await _locationService.getCurrentPosition();
    if (position != null && mounted) {
      final address = await _locationService.getShortAddress(
        position.latitude,
        position.longitude,
      );
      setState(() {
        _currentPosition = position;
        _locationName = address ?? 'Current Location';
        _isLoadingLocation = false;
      });
    } else {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _startMatching() async {
    if (_currentPosition == null || _selectedCategory == null) return;

    final productIntent = _productIntentController.text.trim();
    if (productIntent.isEmpty) return;

    setState(() => _isMatching = true);

    try {
      // Check if user already has an active waiting match
      final activeMatches = await _matchService.getUserActiveWaitingMatches();
      if (activeMatches.isNotEmpty) {
        final firstMatch = activeMatches.firstOrNull;
        if (firstMatch != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'You already have an active match. Please leave it first.',
              ),
              backgroundColor: AppColors.warning,
            ),
          );
          // Navigate to existing match
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MatchWaitingScreen(matchId: firstMatch.id),
            ),
          );
        }
        return;
      }

      // Try to find existing match (returns candidate, does NOT auto-join)
      final candidate = await _matchService.findMatchingRoom(
        category: _selectedCategory!,
        productIntent: productIntent,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        radiusKm: _selectedRadius,
        maxPartners: _selectedPartnerCount,
      );

      if (candidate != null && mounted) {
        // Found a candidate — navigate to waiting screen for preview
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MatchWaitingScreen(
              matchId: candidate.id,
              productIntent: productIntent,
              isPreview: true,
              searchCategory: _selectedCategory!,
              searchLatitude: _currentPosition!.latitude,
              searchLongitude: _currentPosition!.longitude,
              searchRadiusKm: _selectedRadius,
              searchMaxPartners: _selectedPartnerCount,
            ),
          ),
        );
      } else {
        // No candidate — create new room
        final newMatch = await _matchService.createRoom(
          category: _selectedCategory!,
          productIntent: productIntent,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          radiusKm: _selectedRadius,
          locationName: _locationName,
          maxPartners: _selectedPartnerCount,
        );

        if (newMatch != null && mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MatchWaitingScreen(matchId: newMatch.id),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[RealtimeMatchScreen] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isMatching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Real-Time Match'), centerTitle: true),
      body: Column(
        children: [
          const NetworkStatusBanner(),
          Expanded(
            child: Stepper(
              currentStep: _currentStep,
              onStepContinue: _onStepContinue,
              onStepCancel: _onStepCancel,
              controlsBuilder: (context, details) =>
                  _buildStepControls(details),
              steps: [
                _buildLocationStep(),
                _buildRadiusStep(),
                _buildPartnerCountStep(),
                _buildCategoryStep(),
                _buildProductIntentStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Step _buildLocationStep() {
    return Step(
      title: const Text('Select Location'),
      subtitle: _locationName.isNotEmpty ? Text(_locationName) : null,
      isActive: _currentStep >= 0,
      state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      content: Column(
        children: [
          if (_isLoadingLocation)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else ...[
            _buildLocationOption(
              icon: Icons.my_location,
              title: 'Use Current Location',
              subtitle: _locationName,
              isSelected: _useCurrentLocation,
              onTap: () {
                _loadCurrentLocation();
                setState(() => _useCurrentLocation = true);
              },
            ),
            const SizedBox(height: 12),
            // Select on Map button
            OutlinedButton.icon(
              onPressed: _openLocationPicker,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Select on Map'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: _currentPosition?.latitude,
          initialLongitude: _currentPosition?.longitude,
          initialAddress: _locationName,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _currentPosition = Position(
          latitude: result['latitude'],
          longitude: result['longitude'],
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
        _locationName = result['address'] ?? '';
        _useCurrentLocation = false;
      });
    }
  }

  Widget _buildLocationOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Step _buildRadiusStep() {
    // Calculate zoom level based on radius
    double getZoomLevel(double radiusKm) {
      if (radiusKm <= 0.5) return 15.0;
      if (radiusKm <= 1) return 14.0;
      if (radiusKm <= 2) return 13.0;
      if (radiusKm <= 5) return 11.5;
      if (radiusKm <= 10) return 10.5;
      return 9.5;
    }

    return Step(
      title: const Text('Select Radius'),
      subtitle: Text(MatchRadius.getLabel(_selectedRadius)),
      isActive: _currentStep >= 1,
      state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      content: Column(
        children: [
          // Slider
          Slider(
            value: MatchRadius.options.indexOf(_selectedRadius).toDouble(),
            min: 0,
            max: (MatchRadius.options.length - 1).toDouble(),
            divisions: MatchRadius.options.length - 1,
            label: MatchRadius.getLabel(_selectedRadius),
            onChanged: (value) {
              final newRadius = MatchRadius.options[value.toInt()];
              setState(() {
                _selectedRadius = newRadius;
              });
              // Animate map zoom when radius changes
              if (_mapController != null && _currentPosition != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(
                      target: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      zoom: getZoomLevel(newRadius),
                    ),
                  ),
                );
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: MatchRadius.options.map((r) {
                final isSelected = r == _selectedRadius;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedRadius = r);
                    // Animate map zoom when radius is tapped
                    if (_mapController != null && _currentPosition != null) {
                      _mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            ),
                            zoom: getZoomLevel(r),
                          ),
                        ),
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: Text(
                      MatchRadius.getLabel(r),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Map Preview with Circle
          if (_currentPosition != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.25,
                child: GoogleMap(
                  // Key forces rebuild when location changes
                  key: ValueKey(
                    'map_${_currentPosition!.latitude}_${_currentPosition!.longitude}',
                  ),
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    zoom: getZoomLevel(_selectedRadius),
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    // Ensure map shows selected location after creation
                    if (_currentPosition != null) {
                      controller.moveCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: LatLng(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                            ),
                            zoom: getZoomLevel(_selectedRadius),
                          ),
                        ),
                      );
                    }
                  },
                  circles: {
                    Circle(
                      circleId: const CircleId('radius'),
                      center: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      radius: _selectedRadius * 1000, // km to meters
                      fillColor: AppColors.primary.withValues(alpha: 0.15),
                      strokeColor: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  },
                  markers: {
                    Marker(
                      markerId: const MarkerId('center'),
                      position: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueAzure,
                      ),
                    ),
                  },
                  zoomControlsEnabled: false,
                  scrollGesturesEnabled: true,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Step _buildPartnerCountStep() {
    return Step(
      title: const Text('Partner Count'),
      subtitle: Text('$_selectedPartnerCount partner(s)'),
      isActive: _currentStep >= 2,
      state: _currentStep > 2 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How many partners are you looking for?',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: PartnerCount.options.map((count) {
              final isSelected = count == _selectedPartnerCount;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPartnerCount = count),
                  child: Container(
                    margin: EdgeInsets.only(
                      right: count < PartnerCount.options.last ? 12 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.people,
                          size: 32,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          count == 1 ? 'Partner' : 'Partners',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Step _buildCategoryStep() {
    return Step(
      title: const Text('Select Category'),
      subtitle: _selectedCategory != null
          ? Text(RequestCategories.labels[_selectedCategory] ?? '')
          : null,
      isActive: _currentStep >= 3,
      state: _currentStep > 3 ? StepState.complete : StepState.indexed,
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: RequestCategories.all.map((category) {
          final isSelected = category == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    RequestCategories.icons[category] ??
                        'assets/icons/CateOthers.png',
                    width: 20,
                    height: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    RequestCategories.labels[category] ?? category,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Step _buildProductIntentStep() {
    return Step(
      title: const Text('What are you buying?'),
      subtitle: _productIntentController.text.isNotEmpty
          ? Text(_productIntentController.text)
          : null,
      isActive: _currentStep >= 4,
      state: _currentStep > 4 ? StepState.complete : StepState.indexed,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Describe what you want to buy so potential partners can see it.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _productIntentController,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: 'e.g., Eggs 30-pack, Fresh milk 2L',
              prefixIcon: Icon(Icons.shopping_bag_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildStepControls(ControlsDetails details) {
    final isLastStep = _currentStep == 4;
    final canContinue = _canContinue();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: details.onStepCancel,
              child: const Text('Back'),
            ),
          const Spacer(),
          FilledButton(
            onPressed: canContinue
                ? (isLastStep ? _startMatching : details.onStepContinue)
                : null,
            child: _isMatching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isLastStep ? 'Start Matching' : 'Continue'),
          ),
        ],
      ),
    );
  }

  bool _canContinue() {
    switch (_currentStep) {
      case 0:
        return _currentPosition != null;
      case 1:
        return true;
      case 2:
        return true;
      case 3:
        return _selectedCategory != null;
      case 4:
        return _productIntentController.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  void _onStepContinue() {
    if (_currentStep < 4) {
      setState(() => _currentStep++);
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }
}
