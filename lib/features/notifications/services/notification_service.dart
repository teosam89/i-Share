import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[NotificationService] Background message: ${message.messageId}');
  // Handle background message here
}

/// NotificationService - Handles FCM push notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _fcmToken;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  String? get fcmToken => _fcmToken;

  /// Initialize notification service
  Future<void> initialize() async {
    // Request permissions
    await requestPermission();

    // Get FCM token
    await _getFCMToken();

    // Listen for token refresh
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[NotificationService] Token refreshed: $newToken');
      _fcmToken = newToken;
      _saveTokenToFirestore(newToken);
    });

    // Handle foreground messages
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    // Handle notification tap when app was in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check for initial message (app opened from terminated state via notification)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    debugPrint('[NotificationService] Initialized successfully');
  }

  /// Request notification permission
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      final isAuthorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      debugPrint(
        '[NotificationService] Permission status: ${settings.authorizationStatus}',
      );
      return isAuthorized;
    } catch (e) {
      debugPrint('[NotificationService] Error requesting permission: $e');
      return false;
    }
  }

  /// Get FCM token
  Future<String?> _getFCMToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      debugPrint('[NotificationService] FCM Token: $_fcmToken');

      if (_fcmToken != null) {
        await _saveTokenToFirestore(_fcmToken!);
      }

      return _fcmToken;
    } catch (e) {
      debugPrint('[NotificationService] Error getting FCM token: $e');
      return null;
    }
  }

  /// Save FCM token to Firestore for the current user
  Future<void> _saveTokenToFirestore(String token) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore.collection('profiles').doc(userId).set({
        'fcmToken': token,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[NotificationService] Token saved to Firestore');
    } catch (e) {
      debugPrint('[NotificationService] Error saving token: $e');
    }
  }

  /// Handle foreground message
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[NotificationService] Foreground message received');
    debugPrint('  Title: ${message.notification?.title}');
    debugPrint('  Body: ${message.notification?.body}');
    debugPrint('  Data: ${message.data}');

    // Save to in-app notification inbox (fallback for disabled push)
    _saveToInbox(message);

    // Show in-app notification
    _showInAppNotification(message);
  }

  /// Persist notification to Firestore inbox for in-app fallback.
  Future<void> _saveToInbox(RemoteMessage message) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestore
          .collection('profiles')
          .doc(userId)
          .collection('notifications')
          .add({
        'title': message.notification?.title ?? 'Notification',
        'body': message.notification?.body ?? '',
        'type': message.data['type'] ?? 'general',
        'referenceId': message.data['requestId'] ?? message.data['matchId'],
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      debugPrint('[NotificationService] Error saving to inbox: $e');
    }
  }

  /// Get unread notification count stream for badge display.
  Stream<int> getUnreadCountStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return Stream.value(0);

    return _firestore
        .collection('profiles')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Handle notification tap (when app is in background/terminated)
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[NotificationService] Notification tapped');
    debugPrint('  Data: ${message.data}');

    // Navigate based on notification data
    final type = message.data['type'];
    final requestId = message.data['requestId'];

    if (type == 'new_request' && requestId != null) {
      // Navigate to request detail
      debugPrint(
        '[NotificationService] Should navigate to request: $requestId',
      );
      // Navigation will be handled by the app
    }
  }

  /// Show in-app notification (snackbar style)
  void _showInAppNotification(RemoteMessage message) {
    // This will be called from the UI layer
    _onNotificationReceived?.call(message);
  }

  // Callback for UI to show notification
  Function(RemoteMessage)? _onNotificationReceived;

  void setNotificationCallback(Function(RemoteMessage) callback) {
    _onNotificationReceived = callback;
  }

  /// Subscribe to a topic (e.g., for broadcast notifications)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('[NotificationService] Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('[NotificationService] Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('[NotificationService] Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('[NotificationService] Error unsubscribing from topic: $e');
    }
  }

  /// Clean up
  void dispose() {
    _foregroundSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
  }
}
