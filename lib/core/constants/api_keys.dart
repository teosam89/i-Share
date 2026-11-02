import 'package:flutter_dotenv/flutter_dotenv.dart';

/// API Keys loaded from .env file at runtime.
/// Never hardcode keys in source — they live in the project root `.env`.
class ApiKeys {
  /// Google Maps SDK key — used for GoogleMap widget and geocoding.
  static String get googleMapsApiKey =>
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  /// Google Places API key — used for PlacesAutocomplete HTTP calls.
  static String get googlePlacesApiKey =>
      dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';
}
