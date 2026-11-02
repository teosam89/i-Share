import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/places_autocomplete.dart';
import '../services/location_service.dart';

/// Location Picker Screen - Allows user to select location on map
class LocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _selectedLocation;
  String? _selectedAddress;
  bool _isLoadingAddress = false;
  Set<Marker> _markers = {};

  // Default to Kuala Lumpur
  static const LatLng _defaultLocation = LatLng(
    AppConstants.defaultLatitude,
    AppConstants.defaultLongitude,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  void _initializeLocation() {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedLocation = LatLng(
        widget.initialLatitude!,
        widget.initialLongitude!,
      );
      _selectedAddress = widget.initialAddress;
      _updateMarker();
    } else {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (!mounted) return;

    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Location access denied. Enable it in Settings.',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: _locationService.openAppSettings,
          ),
        ),
      );
      return;
    }

    setState(() {
      _selectedLocation = LatLng(position.latitude, position.longitude);
    });
    _updateMarker();
    _getAddressForLocation();
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_selectedLocation!, 16),
    );
  }

  void _updateMarker() {
    if (_selectedLocation == null) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('selected'),
          position: _selectedLocation!,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() => _selectedLocation = newPosition);
            _getAddressForLocation();
          },
        ),
      };
    });
  }

  Future<void> _getAddressForLocation() async {
    if (_selectedLocation == null) return;

    setState(() => _isLoadingAddress = true);

    final address = await _locationService.getShortAddress(
      _selectedLocation!.latitude,
      _selectedLocation!.longitude,
    );

    if (mounted) {
      setState(() {
        _selectedAddress = address;
        _isLoadingAddress = false;
      });
    }
  }

  void _onMapTap(LatLng position) {
    setState(() => _selectedLocation = position);
    _updateMarker();
    _getAddressForLocation();
  }

  void _confirmLocation() {
    if (_selectedLocation != null) {
      Navigator.pop(context, {
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
        'address': _selectedAddress,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        actions: [
          TextButton(
            onPressed: _selectedLocation != null ? _confirmLocation : null,
            child: const Text('Confirm'),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedLocation ?? _defaultLocation,
              zoom: 15,
            ),
            onMapCreated: (controller) => _mapController = controller,
            markers: _markers,
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Search bar at top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: PlacesAutocomplete(
              hintText: 'Search for a place...',
              countryCode: 'my',
              onPlaceSelected: (PlaceResult result) {
                final newLocation = LatLng(result.latitude, result.longitude);
                setState(() {
                  _selectedLocation = newLocation;
                  _selectedAddress = result.description;
                });
                _updateMarker();
                _mapController?.animateCamera(
                  CameraUpdate.newLatLngZoom(newLocation, 17),
                );
              },
            ),
          ),

          // Center pin (when no marker)
          if (_selectedLocation == null)
            const Center(
              child: Icon(Icons.location_pin, size: 48, color: Colors.red),
            ),

          // Bottom info card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _isLoadingAddress
                            ? const Text('Getting address...')
                            : Text(
                                _selectedAddress ??
                                    'Tap on map to select location',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                  if (_selectedLocation != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _getCurrentLocation,
                          icon: const Icon(Icons.my_location, size: 18),
                          label: const Text('Current Location'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selectedLocation != null
                              ? _confirmLocation
                              : null,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Confirm'),
                        ),
                      ),
                    ],
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
