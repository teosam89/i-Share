import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/places_autocomplete.dart';
import '../../co_request/services/location_service.dart';

/// ChatLocationShareScreen — lets user send their current location, search a
/// place, or pick a point on the map.
///
/// Returns `Map<String, dynamic>` with keys: latitude, longitude, address
/// Returns null if user cancels (Navigator.pop without a value).
class ChatLocationShareScreen extends StatefulWidget {
  const ChatLocationShareScreen({super.key});

  @override
  State<ChatLocationShareScreen> createState() =>
      _ChatLocationShareScreenState();
}

class _ChatLocationShareScreenState extends State<ChatLocationShareScreen> {
  final LocationService _locationService = LocationService();
  GoogleMapController? _mapController;

  // Current GPS location
  LatLng? _currentLocation;
  String? _currentAddress;
  bool _isLoadingCurrent = true;

  // User-selected location (map tap or search)
  LatLng? _selectedLocation;
  String? _selectedAddress;
  bool _isLoadingSelectedAddress = false;

  Set<Marker> _markers = {};

  static const LatLng _defaultLocation = LatLng(
    AppConstants.defaultLatitude,
    AppConstants.defaultLongitude,
  );

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (!mounted) return;

    if (position == null) {
      setState(() => _isLoadingCurrent = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not get your location. Check permissions.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: _locationService.openAppSettings,
          ),
        ),
      );
      return;
    }

    final address = await _locationService.getShortAddress(
      position.latitude,
      position.longitude,
    );
    if (!mounted) return;

    final loc = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentLocation = loc;
      _currentAddress = address;
      _isLoadingCurrent = false;
    });

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(loc, 16));
  }

  /// Re-center the map to the user's current GPS position.
  void _recenterToCurrentLocation() {
    if (_currentLocation == null) return;
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_currentLocation!, 16),
    );
  }

  void _onMapTap(LatLng position) {
    _placeMarkerAt(position);
    _fetchSelectedAddress(position);
  }

  /// Place a draggable marker at [position] and update selected state.
  void _placeMarkerAt(LatLng position) {
    setState(() {
      _selectedLocation = position;
      _selectedAddress = null;
      _isLoadingSelectedAddress = true;
      _markers = {
        Marker(
          markerId: const MarkerId('selected'),
          position: position,
          draggable: true,
          onDragEnd: (newPos) {
            setState(() {
              _selectedLocation = newPos;
              _selectedAddress = null;
              _isLoadingSelectedAddress = true;
            });
            _fetchSelectedAddress(newPos);
          },
        ),
      };
    });
  }

  Future<void> _fetchSelectedAddress(LatLng pos) async {
    final address = await _locationService.getShortAddress(
      pos.latitude,
      pos.longitude,
    );
    if (!mounted) return;
    setState(() {
      _selectedAddress = address;
      _isLoadingSelectedAddress = false;
    });
  }

  /// Called when user selects a place from the search bar.
  void _onPlaceSelected(PlaceResult result) {
    final newLocation = LatLng(result.latitude, result.longitude);
    final address =
        result.address.isNotEmpty ? result.address : result.description;

    _placeMarkerAt(newLocation);
    // Address is already known from Places API — no reverse geocode needed.
    setState(() {
      _selectedAddress = address;
      _isLoadingSelectedAddress = false;
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(newLocation, 17),
    );
  }

  void _sendCurrentLocation() {
    if (_currentLocation == null) return;
    Navigator.pop(context, {
      'latitude': _currentLocation!.latitude,
      'longitude': _currentLocation!.longitude,
      'address': _currentAddress,
    });
  }

  void _sendSelectedLocation() {
    if (_selectedLocation == null) return;
    Navigator.pop(context, {
      'latitude': _selectedLocation!.latitude,
      'longitude': _selectedLocation!.longitude,
      'address': _selectedAddress,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share Location')),
      body: Stack(
        children: [
          // Full-screen interactive map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLocation ?? _defaultLocation,
              zoom: 15,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              if (_currentLocation != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(_currentLocation!, 16),
                );
              }
            },
            markers: _markers,
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // replaced by tappable icon in card
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Top overlay: search bar + current location card
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Places search bar
                PlacesAutocomplete(
                  hintText: 'Search for a place…',
                  countryCode: 'my',
                  onPlaceSelected: _onPlaceSelected,
                ),
                const SizedBox(height: 8),
                // Current location quick-send card
                _buildCurrentLocationCard(),
              ],
            ),
          ),

          // Bottom card: selected location (map tap or search result)
          if (_selectedLocation != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildSelectedLocationCard(),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentLocationCard() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Tappable icon — re-centers map to current GPS position
            GestureDetector(
              onTap: _recenterToCurrentLocation,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.my_location,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send Current Location',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _isLoadingCurrent
                      ? Text(
                          'Getting your location…',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : Text(
                          _currentAddress ?? 'Location unavailable',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed:
                  (_isLoadingCurrent || _currentLocation == null)
                      ? null
                      : _sendCurrentLocation,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Send', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedLocationCard() {
    return Container(
      margin: const EdgeInsets.all(12),
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
              Icon(Icons.location_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: _isLoadingSelectedAddress
                    ? Text(
                        'Getting address…',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : Text(
                        _selectedAddress ?? 'Selected location',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _sendSelectedLocation,
              child: const Text('Send This Location'),
            ),
          ),
        ],
      ),
    );
  }
}
