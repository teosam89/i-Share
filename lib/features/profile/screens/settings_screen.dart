import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_settings/app_settings.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../notifications/services/notification_service.dart';

/// SettingsScreen - User settings including notification preferences
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  bool _systemNotificationsEnabled = true;
  bool _notifyJoinRequest = true;
  bool _notifyJoinApproved = true;
  bool _notifyRtmMatch = true;
  bool _isLoading = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _loadAppVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When user returns from system settings, re-check permission
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      // Check actual system notification permission
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      final isSystemEnabled =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      // Load per-category preferences from Firestore
      final profileDoc = await _firestore
          .collection('profiles')
          .doc(userId)
          .get();
      final data = profileDoc.data() ?? {};

      if (mounted) {
        setState(() {
          _systemNotificationsEnabled = isSystemEnabled;
          _notifyJoinRequest = data['notify_joinRequest'] ?? true;
          _notifyJoinApproved = data['notify_joinApproved'] ?? true;
          _notifyRtmMatch = data['notify_rtmMatch'] ?? true;
          _isLoading = false;
        });
      }

      // Sync Firestore state with actual system permission
      await _firestore.collection('profiles').doc(userId).set({
        'notificationsEnabled': isSystemEnabled,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SettingsScreen] Error loading settings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      if (mounted) setState(() => _appVersion = '1.0.0');
    }
  }

  Future<void> _updateSystemNotification(bool enabled) async {
    if (enabled) {
      // Try to request permission
      final granted = await _notificationService.requestPermission();
      if (!granted) {
        // Permission denied — open system settings
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable notifications in system settings'),
              duration: Duration(seconds: 2),
            ),
          );
          AppSettings.openAppSettings(type: AppSettingsType.notification);
        }
        return;
      }
      // Permission granted
      setState(() => _systemNotificationsEnabled = true);
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await _firestore.collection('profiles').doc(userId).set({
          'notificationsEnabled': true,
        }, SetOptions(merge: true));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications enabled'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } else {
      // User wants to disable — update UI + Firestore immediately
      setState(() => _systemNotificationsEnabled = false);
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        await _firestore.collection('profiles').doc(userId).set({
          'notificationsEnabled': false,
        }, SetOptions(merge: true));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'In-app notifications disabled. You can also disable system notifications in device settings.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Update a specific notification category toggle
  Future<void> _updateCategoryToggle(String key, bool value) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      switch (key) {
        case 'notify_joinRequest':
          _notifyJoinRequest = value;
          break;
        case 'notify_joinApproved':
          _notifyJoinApproved = value;
          break;
        case 'notify_rtmMatch':
          _notifyRtmMatch = value;
          break;
      }
    });

    try {
      await _firestore.collection('profiles').doc(userId).set({
        key: value,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SettingsScreen] Error updating $key: $e');
    }
  }

  void _showPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _PrivacyPolicyPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const SizedBox(height: 16),

                // Master Notifications Toggle
                _buildSectionHeader('Notifications'),
                SwitchListTile(
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Master toggle for all notifications'),
                  value: _systemNotificationsEnabled,
                  onChanged: _updateSystemNotification,
                  secondary: Icon(
                    Icons.notifications_outlined,
                    color: AppColors.primary,
                  ),
                ),

                // Sub-category toggles (only active when system is enabled)
                if (_systemNotificationsEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Column(
                      children: [
                        _buildCategoryToggle(
                          icon: Icons.person_add_rounded,
                          title: 'Join Request Received',
                          subtitle:
                              'When someone applies to join your request (host)',
                          value: _notifyJoinRequest,
                          onChanged: (val) =>
                              _updateCategoryToggle('notify_joinRequest', val),
                        ),
                        _buildCategoryToggle(
                          icon: Icons.check_circle_outline_rounded,
                          title: 'Join Approved',
                          subtitle:
                              'When your join application is approved (participant)',
                          value: _notifyJoinApproved,
                          onChanged: (val) =>
                              _updateCategoryToggle('notify_joinApproved', val),
                        ),
                        _buildCategoryToggle(
                          icon: Icons.flash_on_rounded,
                          title: 'RTM Match Found',
                          subtitle:
                              'When real-time match finds a partner for you',
                          value: _notifyRtmMatch,
                          onChanged: (val) =>
                              _updateCategoryToggle('notify_rtmMatch', val),
                        ),
                      ],
                    ),
                  ),
                ],

                const Divider(),

                // About Section
                _buildSectionHeader('About'),
                ListTile(
                  leading: Icon(
                    Icons.privacy_tip_outlined,
                    color: AppColors.textSecondary,
                  ),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: _showPrivacyPolicy,
                ),
                ListTile(
                  leading: Icon(
                    Icons.info_outline,
                    color: AppColors.textSecondary,
                  ),
                  title: const Text('App Version'),
                  trailing: Text(_appVersion.isEmpty ? '...' : _appVersion),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCategoryToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, size: 20, color: AppColors.textSecondary),
      dense: true,
    );
  }
}

/// Privacy Policy page
class _PrivacyPolicyPage extends StatelessWidget {
  const _PrivacyPolicyPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'i-Share Privacy Policy',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last updated: February 2026',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _section(
              'Information We Collect',
              'We collect information you provide when creating an account, '
                  'including your email address, display name, phone number (optional), '
                  'and profile photo. We also collect location data when you create or '
                  'search for co-buy requests, and usage data to improve the app experience.',
            ),
            _section(
              'How We Use Your Information',
              'Your information is used to:\n'
                  '• Provide and maintain the i-Share service\n'
                  '• Match you with nearby users for co-buying opportunities\n'
                  '• Send push notifications about requests, matches, and messages\n'
                  '• Enable chat communication between matched users\n'
                  '• Verify your identity through phone number or email\n'
                  '• Improve app functionality and user experience',
            ),
            _section(
              'Data Sharing',
              'We do not sell your personal information. Your profile details '
                  '(display name, rating, and photo) are visible to other users within '
                  'the app. Location data is shared only in the context of co-buy '
                  'requests you create or join. We may share data with Firebase '
                  '(Google) for authentication, storage, and cloud messaging services.',
            ),
            _section(
              'Data Storage & Security',
              'Your data is stored securely on Firebase (Google Cloud) servers. '
                  'We implement appropriate security measures including encrypted '
                  'connections, secure authentication, and access controls. Chat '
                  'messages are stored in Firestore and are only accessible to '
                  'chat participants.',
            ),
            _section(
              'Push Notifications',
              'We send push notifications for new co-buy requests, chat messages, '
                  'match updates, and request status changes. You can disable '
                  'notifications at any time from the Settings page or your device '
                  'system settings. You can also mute individual chats.',
            ),
            _section(
              'Your Rights',
              'You have the right to:\n'
                  '• Access and update your personal information\n'
                  '• Delete your account and associated data\n'
                  '• Opt out of push notifications\n'
                  '• Mute individual chat notifications\n'
                  '• Report inappropriate content or users',
            ),
            _section(
              'Location Data',
              'Location data is used solely for matching nearby users and '
                  'displaying deal locations. We do not track your location in the '
                  'background. Location access is requested only when creating or '
                  'browsing co-buy requests.',
            ),
            _section(
              'Contact Us',
              'If you have any questions about this Privacy Policy, '
                  'please contact the developer through the GitHub repository of this project.',
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
