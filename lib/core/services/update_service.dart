import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Model for app update information
class AppUpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final bool forceUpdate;
  final String? releaseNotes;

  AppUpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.forceUpdate = false,
    this.releaseNotes,
  });
}

/// Service to check for app updates via Firestore
class UpdateService {
  static final UpdateService _instance = UpdateService._();
  factory UpdateService() => _instance;
  UpdateService._();

  /// Check if a newer version is available
  ///
  /// Returns [AppUpdateInfo] if update is available, null otherwise.
  /// Reads from Firestore document: app_config/latest_version
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      // Get latest version from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('latest_version')
          .get();

      if (!doc.exists) {
        debugPrint(
          '[UpdateService] No app_config/latest_version document found',
        );
        return null;
      }

      final data = doc.data()!;
      final latestVersion = data['version'] as String? ?? currentVersion;
      final downloadUrl = data['downloadUrl'] as String? ?? '';
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      final releaseNotes = data['releaseNotes'] as String?;

      // Compare versions
      if (_isNewerVersion(currentVersion, latestVersion)) {
        debugPrint(
          '[UpdateService] Update available: $currentVersion → $latestVersion',
        );
        return AppUpdateInfo(
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          forceUpdate: forceUpdate,
          releaseNotes: releaseNotes,
        );
      }

      debugPrint('[UpdateService] App is up to date ($currentVersion)');
      return null;
    } catch (e) {
      debugPrint('[UpdateService] Error checking for update: $e');
      return null;
    }
  }

  /// Compare semantic versions: returns true if [latest] > [current]
  bool _isNewerVersion(String current, String latest) {
    final currentParts = current.split('.').map(int.tryParse).toList();
    final latestParts = latest.split('.').map(int.tryParse).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      final l = i < latestParts.length ? (latestParts[i] ?? 0) : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false; // equal
  }
}
