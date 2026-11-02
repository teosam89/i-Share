import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../../core/constants/api_keys.dart';

/// Custom Google Places Autocomplete using direct API calls
/// This avoids the keyboard focus bug in google_places_flutter package
class PlacesAutocomplete extends StatefulWidget {
  final Function(PlaceResult) onPlaceSelected;
  final String? initialValue;
  final String hintText;
  final String countryCode;

  const PlacesAutocomplete({
    super.key,
    required this.onPlaceSelected,
    this.initialValue,
    this.hintText = 'Search for a place...',
    this.countryCode = 'my',
  });

  @override
  State<PlacesAutocomplete> createState() => _PlacesAutocompleteState();
}

class _PlacesAutocompleteState extends State<PlacesAutocomplete> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();

  List<PlacePrediction> _predictions = [];
  bool _isLoading = false;
  bool _showOverlay = false;
  Timer? _debounce;
  OverlayEntry? _overlayEntry;

  /// Session token groups autocomplete keystrokes + place details into one
  /// billed session ($2.83 total instead of per-keystroke + $17 details).
  String _sessionToken = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    }
  }

  void _onTextChanged(String query) {
    _debounce?.cancel();

    if (query.length < 2) {
      _removeOverlay();
      setState(() {
        _predictions = [];
        _showOverlay = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&components=country:${widget.countryCode}'
        '&sessiontoken=$_sessionToken'
        '&key=${ApiKeys.googlePlacesApiKey}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = (data['predictions'] as List)
            .map((p) => PlacePrediction.fromJson(p))
            .toList();

        if (mounted) {
          setState(() {
            _predictions = predictions;
            _isLoading = false;
            _showOverlay = predictions.isNotEmpty;
          });

          if (_showOverlay) {
            _showResultsOverlay();
          }
        }
      }
    } catch (e) {
      debugPrint('Places API error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _getPlaceDetails(PlacePrediction prediction) async {
    _removeOverlay();

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${prediction.placeId}'
        '&fields=geometry,formatted_address'
        '&sessiontoken=$_sessionToken'
        '&key=${ApiKeys.googlePlacesApiKey}',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final result = data['result'];
        final location = result['geometry']['location'];

        final placeResult = PlaceResult(
          placeId: prediction.placeId,
          description: prediction.description,
          address: result['formatted_address'] ?? prediction.description,
          latitude: location['lat'].toDouble(),
          longitude: location['lng'].toDouble(),
        );

        _controller.text = prediction.description;
        widget.onPlaceSelected(placeResult);
        _focusNode.unfocus();
        // Reset token so the next search starts a new billing session
        _sessionToken = const Uuid().v4();
      }
    } catch (e) {
      debugPrint('Place Details error: $e');
    }
  }

  void _showResultsOverlay() {
    _removeOverlay();

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        width: MediaQuery.of(context).size.width - 32,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 56),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            // Explicit color ensures the overlay renders above platform views
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _predictions.length,
                itemBuilder: (context, index) {
                  final prediction = _predictions[index];
                  return ListTile(
                    leading: const Icon(Icons.location_on_outlined, size: 20),
                    title: Text(
                      prediction.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () => _getPlaceDetails(prediction),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _removeOverlay();
                      setState(() => _predictions = []);
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }
}

/// Place prediction from autocomplete API
class PlacePrediction {
  final String placeId;
  final String description;

  PlacePrediction({required this.placeId, required this.description});

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      placeId: json['place_id'],
      description: json['description'],
    );
  }
}

/// Place result with coordinates
class PlaceResult {
  final String placeId;
  final String description;
  final String address;
  final double latitude;
  final double longitude;

  PlaceResult({
    required this.placeId,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}
