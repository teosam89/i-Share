import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../models/app_notification.dart';
import '../../co_request/screens/request_detail_screen.dart';
import '../../co_request/screens/join_requests_screen.dart';
import '../../co_request/services/co_request_service.dart';
import '../../realtime_match/screens/realtime_match_screen.dart';

/// In-app notification inbox — fallback channel when push is disabled.
class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  final _firestore = FirebaseFirestore.instance;

  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _notificationsRef =>
      _firestore.collection('profiles').doc(_userId).collection('notifications');

  Stream<List<AppNotification>> _getNotificationsStream() {
    return _notificationsRef
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AppNotification.fromFirestore(doc))
            .toList());
  }

  Future<void> _markAsRead(String notificationId) async {
    await _notificationsRef.doc(notificationId).update({'isRead': true});
  }

  Future<void> _markAllAsRead() async {
    final snapshot =
        await _notificationsRef.where('isRead', isEqualTo: false).get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Mark read then navigate to the relevant screen based on notification type.
  Future<void> _handleNotificationTap(AppNotification notification) async {
    if (!notification.isRead) {
      _markAsRead(notification.id);
    }

    final refId = notification.referenceId;
    if (refId == null || refId.isEmpty) return;

    switch (notification.type) {
      // Host received a new join request — go to join requests screen
      // CF sends 'join_request_pending'; legacy/manual entries use 'join_request'
      case 'join_request':
      case 'join_request_pending':
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JoinRequestsScreen(
              requestId: refId,
              productName: notification.title,
            ),
          ),
        );
        break;

      // RTM match found — go to realtime match screen
      case 'rtm_match_found':
      case 'match_found':
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RealtimeMatchScreen()),
        );
        break;

      // Join approved / request updated — fetch request then navigate to detail
      // CF sends 'join_request_approved' / 'request_edited'; legacy uses 'join_approved' / 'request_update'
      case 'join_approved':
      case 'join_request_approved':
      case 'request_update':
      case 'request_edited':
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final nav = Navigator.of(context);

        final request = await CoRequestService().getRequest(refId);
        if (request == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Request not found or has been deleted.')),
          );
          return;
        }
        nav.push(
          MaterialPageRoute(
            builder: (_) => RequestDetailScreen(request: request),
          ),
        );
        break;

      default:
        break;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'join_request':
      case 'join_request_pending':
        return Icons.group_add;
      case 'join_approved':
      case 'join_request_approved':
        return Icons.check_circle_outline;
      case 'rtm_match_found':
      case 'match_found':
        return Icons.radar;
      case 'qr_ready':
        return Icons.qr_code;
      case 'request_update':
      case 'request_edited':
        return Icons.shopping_bag;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'join_request':
      case 'join_request_pending':
        return AppColors.primary;
      case 'join_approved':
      case 'join_request_approved':
        return AppColors.success;
      case 'rtm_match_found':
      case 'match_found':
        return AppColors.accent;
      case 'qr_ready':
        return AppColors.secondary;
      case 'request_update':
      case 'request_edited':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _markAllAsRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _getNotificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see updates about your requests\nand matches here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final iconColor = _getNotificationColor(notification.type);

              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getNotificationIcon(notification.type),
                    color: iconColor,
                    size: 22,
                  ),
                ),
                title: Text(
                  notification.title,
                  style: TextStyle(
                    fontWeight: notification.isRead
                        ? FontWeight.normal
                        : FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  notification.body,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: notification.isRead
                    ? null
                    : Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                tileColor:
                    notification.isRead ? null : AppColors.primary.withValues(alpha: 0.04),
                onTap: () => _handleNotificationTap(notification),
              );
            },
          );
        },
      ),
    );
  }
}
