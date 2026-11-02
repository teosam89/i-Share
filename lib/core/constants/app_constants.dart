class AppConstants {
  // App Information
  static const String appName = 'i-Share';
  static const String appVersion = '1.0.0';
  static const String appTagline = 'Share the cost, not the waste';

  // API Keys (Placeholders - Replace with actual keys)
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY_HERE';

  // Firebase Collections
  static const String coRequestsCollection = 'co_requests';
  static const String chatRoomsCollection = 'chat_rooms';
  static const String profilesCollection = 'profiles';
  static const String realtimeMatchesCollection = 'realtime_matches';
  static const String joinRequestsCollection = 'join_requests';
  static const String messagesCollection = 'messages';
  static const String ratingsCollection = 'ratings';
  static const String reportsCollection = 'reports';

  // Default Values
  static const double defaultSearchRadius = 5.0; // km
  static const int defaultRequestExpiryHours = 48;
  static const int minParticipants = 2;
  static const int maxParticipants = 10;

  // Search Radius Options (km)
  static const List<double> searchRadiusOptions = [1.0, 3.0, 5.0, 10.0, 15.0];

  // Request Expiry Options (hours)
  static const List<int> expiryOptions = [6, 12, 24, 48, 72];

  // Trust Score Thresholds
  static const double minTrustScore = 0.0;
  static const double maxTrustScore = 5.0;
  static const double goodTrustScore = 4.0;

  // Pagination
  static const int itemsPerPage = 20;

  // Image Settings
  static const int maxImageSizeKB = 5120; // 5MB
  static const double imageQuality = 0.8;

  // Notification Types
  static const String notifNewJoiner = 'new_joiner';
  static const String notifRequestFull = 'request_full';
  static const String notifNearbyRequest = 'nearby_request';
  static const String notifMeetingReminder = 'meeting_reminder';
  static const String notifRequestExpiring = 'request_expiring';

  // Deep Link Prefixes
  static const String deepLinkPrefix = 'ishare://';

  // Validation
  static const int minProductNameLength = 3;
  static const int maxProductNameLength = 100;
  static const int minNotesLength = 0;
  static const int maxNotesLength = 500;

  // Map Settings
  static const double defaultMapZoom = 14.0;
  static const double nearbyRequestZoom = 12.0;

  // Malaysian Default Location (Kuala Lumpur)
  static const double defaultLatitude = 3.1390;
  static const double defaultLongitude = 101.6869;
}
