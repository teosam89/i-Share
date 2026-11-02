import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../../core/constants/app_colors.dart';
import '../../auth/services/auth_provider.dart';
import '../../auth/screens/login_screen.dart';
import '../models/user_profile_model.dart';
import '../services/profile_service.dart';
import '../services/credibility_service.dart';
import '../widgets/report_user_dialog.dart';
import 'account_settings_screen.dart';
import 'all_reviews_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../notifications/services/notification_service.dart';
import '../../notifications/screens/notification_inbox_screen.dart';

/// ProfileScreen - Displays user profile with credibility stats
class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isCurrentUser;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final ImagePicker _imagePicker = ImagePicker();
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isUploadingAvatar = false;
  bool _isBioExpanded = false;
  final bool _isEditMode = false;
  StreamSubscription? _profileSubscription;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _listenToProfileChanges();
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  /// Listen to real-time profile document changes (score, rating, etc.)
  /// Only subscribes for the current user's own profile — viewing another
  /// user's profile uses a one-time load and doesn't need a persistent listener.
  void _listenToProfileChanges() {
    if (!widget.isCurrentUser) return;
    _profileSubscription = FirebaseFirestore.instance
        .collection('profiles')
        .doc(widget.userId)
        .snapshots()
        .listen((snapshot) {
          if (!mounted || !snapshot.exists) return;
          final updatedProfile = UserProfile.fromFirestore(snapshot);
          setState(() {
            _profile = updatedProfile;
          });
        });
  }

  Future<void> _loadProfile() async {
    try {
      final profile = widget.isCurrentUser
          ? await _profileService.getOrCreateProfile()
          : await _profileService.getProfile(widget.userId);

      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not load profile. Please try again.')));
      }
    }
  }

  Future<void> _showLogoutDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final authProvider = context.read<AuthProvider>();
      await authProvider.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  /// Open account settings
  void _openAccountSettings() async {
    if (_profile == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountSettingsScreen(profile: _profile!),
      ),
    );
    // Reload profile if changes were made
    if (result == true) {
      _loadProfile();
    }
  }

  /// Start direct message with this user
  Future<void> _startDirectMessage() async {
    if (_profile == null) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final chatService = ChatService();

    try {
      // Create or get existing DM chat room
      final chatRoomId = await chatService.getOrCreateDmChatRoom(
        currentUser.uid,
        widget.userId,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatRoomId: chatRoomId,
              productName: _profile!.displayName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not start chat. Please try again.')));
      }
    }
  }

  /// Show report dialog for this user
  void _showReportDialog() {
    if (_profile == null) return;
    showReportUserDialog(
      context: context,
      reportedUserId: widget.userId,
      reportedUserName: _profile!.displayName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCurrentUser ? 'My Profile' : 'User Profile'),
        actions: [
          if (widget.isCurrentUser) ...[
            // Notification inbox
            StreamBuilder<int>(
              stream: NotificationService().getUnreadCountStream(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return IconButton(
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationInboxScreen(),
                    ),
                  ),
                  tooltip: 'Notifications',
                );
              },
            ),
            // Settings & Logout combined into overflow menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'settings') _openAccountSettings();
                if (value == 'logout') _showLogoutDialog();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined),
                      SizedBox(width: 12),
                      Text('Settings'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 12),
                      Text('Logout'),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            // DM button for visitor mode
            IconButton(
              icon: const Icon(Icons.message_outlined),
              onPressed: _startDirectMessage,
              tooltip: 'Send Message',
            ),
            // Report button for visitor mode
            IconButton(
              icon: const Icon(Icons.report_outlined),
              onPressed: () => _showReportDialog(),
              tooltip: 'Report User',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
          ? _buildProfileNotFound()
          : _buildProfileContent(),
    );
  }

  Widget _buildProfileNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off_outlined,
            size: 64,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Profile not found',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// Show avatar picker bottom sheet
  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_profile?.photoUrl != null)
              ListTile(
                leading: Icon(Icons.delete, color: AppColors.error),
                title: Text(
                  'Remove Photo',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Pick image from camera or gallery
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );

      if (image != null && mounted) {
        // Simple crop - minimal UI
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: AppColors.primary,
              toolbarWidgetColor: Colors.white,
              backgroundColor: Colors.white,
              activeControlsWidgetColor: AppColors.primary,
              cropFrameColor: AppColors.primary,
              cropGridColor: Colors.grey,
              lockAspectRatio: false,
              hideBottomControls: true, // Hide all bottom buttons
            ),
            IOSUiSettings(
              title: 'Crop Photo',
              doneButtonTitle: 'Done',
              cancelButtonTitle: 'Cancel',
              rotateButtonsHidden: true,
              resetButtonHidden: true,
              aspectRatioPickerButtonHidden: true,
            ),
          ],
        );

        if (croppedFile != null && mounted) {
          await _uploadAvatar(File(croppedFile.path));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not select image. Please try again.')));
      }
    }
  }

  /// Upload avatar to Firebase Storage
  Future<void> _uploadAvatar(File imageFile) async {
    if (_profile == null) return;

    // Guard: reject if still > 3 MB after client-side compression
    final sizeBytes = await imageFile.length();
    if (sizeBytes > 3 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image is too large. Please choose a smaller photo.')),
        );
      }
      return;
    }

    setState(() => _isUploadingAvatar = true);

    try {
      // Upload to Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('avatars')
          .child('${_profile!.id}.jpg');

      await storageRef.putFile(imageFile);
      final downloadUrl = await storageRef.getDownloadURL();

      // Update Firebase Auth
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePhotoURL(downloadUrl);
      }

      // Update Firestore profile
      final updatedProfile = UserProfile(
        id: _profile!.id,
        displayName: _profile!.displayName,
        email: _profile!.email,
        photoUrl: downloadUrl,
        rating: _profile!.rating,
        ratingCount: _profile!.ratingCount,
        totalRequests: _profile!.totalRequests,
        totalJoined: _profile!.totalJoined,
        completedRequests: _profile!.completedRequests,
        cancelledRequests: _profile!.cancelledRequests,
        createdAt: _profile!.createdAt,
        lastActiveAt: _profile!.lastActiveAt,
      );
      await _profileService.updateProfileFull(updatedProfile);

      setState(() {
        _profile = updatedProfile;
        _isUploadingAvatar = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✓ Avatar updated!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not upload photo. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Remove avatar
  Future<void> _removeAvatar() async {
    if (_profile == null) return;

    try {
      // Update Firestore profile
      final updatedProfile = UserProfile(
        id: _profile!.id,
        displayName: _profile!.displayName,
        email: _profile!.email,
        photoUrl: null,
        rating: _profile!.rating,
        ratingCount: _profile!.ratingCount,
        totalRequests: _profile!.totalRequests,
        totalJoined: _profile!.totalJoined,
        completedRequests: _profile!.completedRequests,
        cancelledRequests: _profile!.cancelledRequests,
        createdAt: _profile!.createdAt,
        lastActiveAt: _profile!.lastActiveAt,
      );
      await _profileService.updateProfileFull(updatedProfile);

      // Update Firebase Auth
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePhotoURL(null);
      }

      setState(() => _profile = updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Avatar removed')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Show edit profile dialog
  Future<void> _showEditProfileDialog() async {
    final nameController = TextEditingController(text: _profile?.displayName);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter your name',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      await _updateDisplayName(result);
    }
  }

  /// Update display name in both Firebase Auth and Firestore
  Future<void> _updateDisplayName(String newName) async {
    try {
      // 1. Update Firebase Auth displayName
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updateDisplayName(newName);
      }

      // 2. Update Firestore profile
      if (_profile != null) {
        final updatedProfile = UserProfile(
          id: _profile!.id,
          displayName: newName,
          email: _profile!.email,
          photoUrl: _profile!.photoUrl,
          rating: _profile!.rating,
          ratingCount: _profile!.ratingCount,
          totalRequests: _profile!.totalRequests,
          totalJoined: _profile!.totalJoined,
          completedRequests: _profile!.completedRequests,
          cancelledRequests: _profile!.cancelledRequests,
          createdAt: _profile!.createdAt,
          lastActiveAt: _profile!.lastActiveAt,
        );
        await _profileService.updateProfileFull(updatedProfile);

        setState(() => _profile = updatedProfile);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('✓ Profile updated!'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildProfileContent() {
    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Profile Header
            _buildProfileHeader(),

            // Credibility Badge
            _buildCredibilitySection(),

            // Stats Grid
            _buildStatsGrid(),

            // Ratings Section
            _buildRatingsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    // Use custom banner color or default to primary
    final bannerColor = _profile?.bannerColor != null
        ? Color(_profile!.bannerColor!)
        : AppColors.primary;

    // Create a darker shade for gradient
    final darkerColor = HSLColor.fromColor(bannerColor)
        .withLightness(
          (HSLColor.fromColor(bannerColor).lightness - 0.15).clamp(0.0, 1.0),
        )
        .toColor();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Background with curved bottom
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                darkerColor,
                bannerColor,
                bannerColor.withValues(alpha: 0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Decorative shapes for visual depth
              Positioned(
                top: -30,
                right: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                top: 60,
                left: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 40,
                right: -10,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 50,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              // Actual content
              Column(
                children: [
                  // Avatar with decorative ring
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer glow ring
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 3,
                          ),
                        ),
                      ),
                      // Inner avatar
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: Colors.white,
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: Colors.grey.shade100,
                            backgroundImage: _profile?.photoUrl != null
                                ? CachedNetworkImageProvider(_profile!.photoUrl!)
                                : null,
                            child: _isUploadingAvatar
                                ? const CircularProgressIndicator()
                                : _profile?.photoUrl == null
                                ? Text(
                                    (_profile?.displayName.isNotEmpty == true)
                                        ? _profile!.displayName[0].toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: bannerColor,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      // Camera button - only show in edit mode
                      if (widget.isCurrentUser && _isEditMode)
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: GestureDetector(
                            onTap: _showAvatarPicker,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: bannerColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Name with gender icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _profile?.displayName ?? 'Unknown User',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_profile?.gender != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _profile!.gender == 'male'
                                ? Icons.male
                                : Icons.female,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                      if (widget.isCurrentUser && _isEditMode)
                        IconButton(
                          onPressed: _showEditProfileDialog,
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 18,
                          ),
                          tooltip: 'Edit Name',
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Member since with icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Member since ${_formatDate(_profile?.createdAt)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  // Bio — expandable
                  if (_profile?.bio != null && _profile!.bio!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildExpandableBio(_profile!.bio!),
                  ],
                ],
              ),
            ],
          ),
        ),
        // Curved bottom overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 30,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableBio(String bio) {
    final bioStyle = TextStyle(
      fontSize: 13,
      color: Colors.white.withValues(alpha: 0.95),
      height: 1.4,
    );
    const maxLinesCollapsed = 2;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Measure if text overflows 2 lines
          final textSpan = TextSpan(text: bio, style: bioStyle);
          final tp = TextPainter(
            text: textSpan,
            maxLines: maxLinesCollapsed,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: constraints.maxWidth);

          final isOverflowing = tp.didExceedMaxLines;

          if (!isOverflowing) {
            // Short bio — just show it
            return Text(bio, textAlign: TextAlign.center, style: bioStyle);
          }

          // Long bio — expandable
          return GestureDetector(
            onTap: () => setState(() => _isBioExpanded = !_isBioExpanded),
            child: AnimatedCrossFade(
              firstChild: Column(
                children: [
                  Text(
                    bio,
                    textAlign: TextAlign.center,
                    maxLines: maxLinesCollapsed,
                    overflow: TextOverflow.ellipsis,
                    style: bioStyle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'more',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              secondChild: Column(
                children: [
                  Text(bio, textAlign: TextAlign.center, style: bioStyle),
                  const SizedBox(height: 2),
                  Text(
                    'less',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              crossFadeState: _isBioExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCredibilitySection() {
    final level = _profile?.credibilityLevel ?? 'User';
    final iconPath = _profile?.credibilityIcon ?? 'assets/icons/CUser.png';
    final score = _profile?.score ?? 100;

    Color badgeColor;
    switch (level) {
      case 'Elite':
        badgeColor = const Color(0xFFFFD700); // Gold
        break;
      case 'Trusted':
        badgeColor = AppColors.success; // Green
        break;
      case 'User':
      default:
        badgeColor = AppColors.primary; // Blue
    }

    // Progress bar calculations
    int levelMin;
    int levelMax;
    String nextLevel;
    Color nextLevelColor;
    String nextLevelIcon;

    if (score < 300) {
      // User → Trusted
      levelMin = 0;
      levelMax = 300;
      nextLevel = 'Trusted';
      nextLevelColor = AppColors.success;
      nextLevelIcon = 'assets/icons/CTrusted.png';
    } else if (score < 700) {
      // Trusted → Elite
      levelMin = 300;
      levelMax = 700;
      nextLevel = 'Elite';
      nextLevelColor = const Color(0xFFFFD700);
      nextLevelIcon = 'assets/icons/CElite.png';
    } else {
      // Elite (maxed out)
      levelMin = 700;
      levelMax = 1000;
      nextLevel = 'Elite';
      nextLevelColor = const Color(0xFFFFD700);
      nextLevelIcon = 'assets/icons/CElite.png';
    }

    final progressInLevel = (score - levelMin).clamp(0, levelMax - levelMin);
    final progressFraction = progressInLevel / (levelMax - levelMin);
    final isMaxLevel = score >= 700;
    final pointsToNext = isMaxLevel ? 0 : levelMax - score;

    return GestureDetector(
      onTap: () => _showCredibilityDetails(badgeColor),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: badgeColor.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          children: [
            // Top row: Icon + Level badge + Stars
            Row(
              children: [
                // Credibility Icon with gradient background
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        badgeColor.withValues(alpha: 0.15),
                        badgeColor.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Image.asset(iconPath, fit: BoxFit.contain),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              level,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: AppColors.textTertiary,
                            size: 14,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // Star rating
                          ...List.generate(5, (index) {
                            final rating = _profile?.rating ?? 0;
                            return Icon(
                              index < rating.floor()
                                  ? Icons.star_rounded
                                  : index < rating
                                  ? Icons.star_half_rounded
                                  : Icons.star_outline_rounded,
                              size: 18,
                              color: Colors.amber,
                            );
                          }),
                          const SizedBox(width: 6),
                          Text(
                            _profile?.rating.toStringAsFixed(1) ?? '0.0',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            ' (${_profile?.ratingCount ?? 0})',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Divider
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Divider(
                height: 1,
                color: AppColors.border.withValues(alpha: 0.5),
              ),
            ),

            // Progress bar section
            Column(
              children: [
                // Score label row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$score pts',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                    if (!isMaxLevel)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(nextLevelIcon, width: 16, height: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$pointsToNext pts to $nextLevel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: nextLevelColor,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium,
                            size: 16,
                            color: nextLevelColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Max Level!',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: nextLevelColor,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Progress bar
                Stack(
                  children: [
                    // Background track
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // Filled progress
                    FractionallySizedBox(
                      widthFactor: progressFraction.clamp(0.02, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              badgeColor,
                              isMaxLevel
                                  ? badgeColor
                                  : Color.lerp(
                                      badgeColor,
                                      nextLevelColor,
                                      progressFraction,
                                    )!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColor.withValues(alpha: 0.4),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Level markers
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$levelMin',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      isMaxLevel ? '1000+' : '$levelMax',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Low credibility warning
            if (score < 50) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your credibility score is low. Please be mindful of your actions.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Show level guide explanation dialog
  void _showLevelGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.school, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Level Guide'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLevelGuideItem(
                'User',
                '0 - 299 points',
                AppColors.primary,
                'assets/icons/CUser.png',
                'Starting level for all users',
              ),
              const SizedBox(height: 16),
              _buildLevelGuideItem(
                'Trusted',
                '300 - 699 points',
                AppColors.success,
                'assets/icons/CTrusted.png',
                'Reliable member with good track record',
              ),
              const SizedBox(height: 16),
              _buildLevelGuideItem(
                'Elite',
                '700+ points',
                const Color(0xFFFFD700),
                'assets/icons/CElite.png',
                'Top-tier member with excellent reputation',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to earn points:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPointItem('+15', 'Complete a split'),
                    _buildPointItem('+10', 'Receive 5-star rating'),
                    _buildPointItem('+3', 'Receive 4-star rating'),
                    _buildPointItem('+20', 'Verify email'),
                    _buildPointItem('+30', 'Verify phone'),
                    const SizedBox(height: 12),
                    Text(
                      'Point deductions:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPointItem(
                      '-5',
                      'Receive low rating (≤3 stars)',
                      isNegative: true,
                    ),
                    _buildPointItem('-10', 'Leave a request', isNegative: true),
                    _buildPointItem(
                      '-10',
                      'Request expired (with participants)',
                      isNegative: true,
                    ),
                    _buildPointItem(
                      '-25',
                      'Cancel as host (with participants)',
                      isNegative: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelGuideItem(
    String level,
    String points,
    Color color,
    String iconPath,
    String description,
  ) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.asset(iconPath, fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    level,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    points,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                description,
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPointItem(
    String points,
    String description, {
    bool isNegative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              points,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isNegative ? AppColors.error : AppColors.success,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              description,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// Show credibility details bottom sheet
  void _showCredibilityDetails(Color badgeColor) {
    final score = _profile?.score ?? 100;
    final level = _profile?.credibilityLevel ?? 'User';
    final iconPath = _profile?.credibilityIcon ?? 'assets/icons/CUser.png';

    // Calculate progress to next level
    int nextLevelScore;
    String nextLevel;
    int currentLevelMin;
    if (score < 300) {
      nextLevelScore = 300;
      nextLevel = 'Trusted';
      currentLevelMin = 0;
    } else if (score < 700) {
      nextLevelScore = 700;
      nextLevel = 'Elite';
      currentLevelMin = 300;
    } else {
      nextLevelScore = score;
      nextLevel = 'Max Level';
      currentLevelMin = 700;
    }
    final progressRange = nextLevelScore - currentLevelMin;
    final progressValue = score - currentLevelMin;
    final progress = score < 700 ? progressValue / progressRange : 1.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) => SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar with help button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            onPressed: () => _showLevelGuide(ctx),
                            icon: Icon(
                              Icons.help_outline,
                              color: AppColors.textSecondary,
                              size: 22,
                            ),
                            tooltip: 'Level Guide',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Header with icon and score
                  Center(
                    child: Column(
                      children: [
                        // Icon on white/light background
                        Container(
                          width: 80,
                          height: 80,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.3),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: badgeColor.withValues(alpha: 0.15),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Image.asset(iconPath, fit: BoxFit.contain),
                        ),
                        const SizedBox(height: 16),
                        // Current Level label
                        Text(
                          'Current Level',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Level name with colored badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: badgeColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            level,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Score display
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '$score',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: ' points',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Progress to next level
                  if (score < 700) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Next: $nextLevel',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${nextLevelScore - score} to go',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: progress.clamp(0.0, 1.0),
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        badgeColor,
                                        badgeColor.withValues(alpha: 0.7),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$score / $nextLevelScore',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Recent Activities - only visible to profile owner
                  if (widget.isCurrentUser) ...[
                    // Recent Activities header
                    Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Recent Activities',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: CredibilityService().getScoreActivities(
                        widget.userId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final activities = snapshot.data ?? [];

                        if (activities.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.emoji_events_outlined,
                                      size: 28,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No activities yet',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Complete splits to earn points!',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: activities.map((activity) {
                            final points = activity['points'] as int? ?? 0;
                            final isPositive = points >= 0;
                            final timestamp =
                                activity['createdAt'] as Timestamp?;
                            final date = timestamp?.toDate();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isPositive
                                          ? Color.alphaBlend(AppColors.success.withValues(alpha: 0.1), Colors.white)
                                          : Color.alphaBlend(AppColors.error.withValues(alpha: 0.1), Colors.white),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isPositive
                                          ? Icons.trending_up_rounded
                                          : Icons.trending_down_rounded,
                                      color: isPositive
                                          ? AppColors.success
                                          : AppColors.error,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          activity['description'] ?? 'Activity',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (date != null)
                                          Text(
                                            _formatActivityDate(date),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textTertiary,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPositive
                                          ? Color.alphaBlend(AppColors.success.withValues(alpha: 0.1), Colors.white)
                                          : Color.alphaBlend(AppColors.error.withValues(alpha: 0.1), Colors.white),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${isPositive ? '+' : ''}$points',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isPositive
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ], // end isCurrentUser Recent Activities
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatActivityDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildStatsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              icon: Icons.add_circle_outline,
              label: 'Created',
              value: '${_profile?.totalRequests ?? 0}',
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.group_add_outlined,
              label: 'Joined',
              value: '${_profile?.totalJoined ?? 0}',
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              icon: Icons.check_circle_outline,
              label: 'Completed',
              value: '${_profile?.completedRequests ?? 0}',
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingsSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Reviews',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AllReviewsScreen(
                        userId: widget.userId,
                        userName: _profile?.displayName ?? 'User',
                      ),
                    ),
                  );
                },
                child: Text(
                  'View All >',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<UserRating>>(
            stream: _profileService.getUserRatings(widget.userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final ratings = snapshot.data ?? [];

              if (ratings.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.star_outline_rounded,
                          size: 36,
                          color: Colors.amber.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No reviews yet',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isCurrentUser
                            ? 'Complete your first split to earn reviews!'
                            : 'This user hasn\'t received any reviews yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Anti-spam: max 2 reviews per unique reviewer
              final filteredRatings = _filterReviewsPerUser(
                ratings,
                maxPerUser: 2,
              );

              return Column(
                children: filteredRatings
                    .take(3) // Show up to 3 preview reviews
                    .map((rating) => _buildRatingItem(rating))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Filter reviews to show max [maxPerUser] reviews per unique reviewer.
  /// Prevents a single user from dominating the reviews section.
  /// Reviews are already sorted by createdAt descending (newest first).
  List<UserRating> _filterReviewsPerUser(
    List<UserRating> ratings, {
    int maxPerUser = 2,
  }) {
    final Map<String, int> userReviewCount = {};
    final List<UserRating> filtered = [];

    for (final rating in ratings) {
      final count = userReviewCount[rating.fromUserId] ?? 0;
      if (count < maxPerUser) {
        filtered.add(rating);
        userReviewCount[rating.fromUserId] = count + 1;
      }
    }

    return filtered;
  }

  Widget _buildRatingItem(UserRating rating) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reviewer avatar
          FutureBuilder<UserProfile?>(
            future: _profileService.getProfile(rating.fromUserId),
            builder: (context, snapshot) {
              final photoUrl = snapshot.data?.photoUrl;
              return UserAvatar(
                photoUrl: photoUrl,
                name: rating.fromUserName,
              );
            },
          ),
          const SizedBox(width: 12),
          // Review content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        rating.fromUserName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ...List.generate(
                      5,
                      (index) => Icon(
                        index < rating.rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
                if (rating.comment != null && rating.comment!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    rating.comment!,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatRelativeTime(rating.createdAt),
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unknown';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }
}
