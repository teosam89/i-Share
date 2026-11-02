import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/constants/app_colors.dart';
import 'core/services/update_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/auth/screens/profile_setup_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/services/auth_provider.dart';
import 'features/co_request/providers/co_request_provider.dart';
import 'features/home/screens/main_screen.dart';
import 'features/notifications/services/notification_service.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background message: ${message.notification?.title}');
}

void main() async {
  if (kDebugMode) {
    FlutterSkillBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  // Load environment variables (.env)
  await dotenv.load(fileName: '.env');

  // Initialize Firebase
  await Firebase.initializeApp();

  // Set up FCM background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notification service
  await NotificationService().initialize();

  // Use manual system UI mode to prevent nav bar from overlapping app content
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const IShareApp());
}

class IShareApp extends StatefulWidget {
  const IShareApp({super.key});

  @override
  State<IShareApp> createState() => _IShareAppState();
}

class _IShareAppState extends State<IShareApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Check for app updates immediately (before login)
    _checkForAppUpdate();
  }

  Future<void> _checkForAppUpdate() async {
    // Small delay to let the navigator build
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final updateInfo = await UpdateService().checkForUpdate();
    if (!mounted) return;
    if (updateInfo != null) {
      final navState = _navigatorKey.currentState;
      if (navState != null && navState.context.mounted) {
        _showUpdateDialog(navState.context, updateInfo);
      }
    }
  }

  void _showUpdateDialog(BuildContext ctx, AppUpdateInfo info) {
    showDialog(
      context: ctx,
      barrierDismissible: !info.forceUpdate,
      builder: (dialogCtx) => PopScope(
        canPop: !info.forceUpdate,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.system_update, color: AppColors.primary, size: 28),
              const SizedBox(width: 12),
              const Text('Update Available'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version (v${info.latestVersion}) is available.',
                style: const TextStyle(fontSize: 15),
              ),
              if (info.releaseNotes != null &&
                  info.releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's New:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.releaseNotes!,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (info.forceUpdate) ...[
                const SizedBox(height: 12),
                Text(
                  'This update is required to continue using the app.',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!info.forceUpdate)
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Later'),
              ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final url = Uri.parse(info.downloadUrl);
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not open download link. Please update manually.',
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(
          create: (_) => CoRequestProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'i-Share',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            // Show splash while auth hasn't initialized yet
            if (!auth.isInitialized) {
              return const SplashScreen();
            }

            // Once initialized, route based on auth state
            if (auth.isLoggedIn) {
              if (auth.needsProfileSetup) {
                return const ProfileSetupScreen();
              }
              // Check if user has seen onboarding (handles force-close edge case)
              return FutureBuilder<bool>(
                future: OnboardingScreen.hasSeenOnboarding(),
                builder: (context, onboardingSnapshot) {
                  if (!onboardingSnapshot.hasData) {
                    return const SplashScreen();
                  }
                  if (onboardingSnapshot.data == true) {
                    return const MainScreen();
                  }
                  return const OnboardingScreen();
                },
              );
            }

            // Confirmed not logged in
            return const LoginScreen();
          },
        ),
      ),
    );
  }
}
