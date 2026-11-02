import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import '../../auth/services/auth_provider.dart' as app_auth;
import '../../../core/constants/app_colors.dart';
import '../models/user_profile_model.dart';
import '../services/profile_service.dart';
import 'settings_screen.dart';

/// Account Settings Screen - Edit profile details
class AccountSettingsScreen extends StatefulWidget {
  final UserProfile profile;

  const AccountSettingsScreen({super.key, required this.profile});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _profileService = ProfileService();
  final _imagePicker = ImagePicker();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _bioController;
  String? _selectedGender;
  String? _currentAvatarUrl;
  int? _selectedBannerColor;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _isBannerExpanded = false;
  String? _bioError;
  String? _linkedEmail; // updated after linkWithCredential

  // Preset color palette
  static const List<int> _colorPalette = [
    0xFF4A90E2, // Blue (default)
    0xFF5C6BC0, // Indigo
    0xFF7E57C2, // Deep Purple
    0xFFAB47BC, // Purple
    0xFFEC407A, // Pink
    0xFFEF5350, // Red
    0xFFFF7043, // Deep Orange
    0xFFFF9800, // Orange
    0xFFFFC107, // Amber
    0xFF66BB6A, // Green
    0xFF26A69A, // Teal
    0xFF26C6DA, // Cyan
    0xFF42A5F5, // Light Blue
    0xFF78909C, // Blue Grey
    0xFF8D6E63, // Brown
    0xFF757575, // Grey
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _phoneController = TextEditingController(text: widget.profile.phone ?? '');
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
    _bioController.addListener(_validateBio);
    _selectedGender = widget.profile.gender;
    _currentAvatarUrl = widget.profile.photoUrl;
    _selectedBannerColor = widget.profile.bannerColor ?? 0xFF4A90E2;

    // Reload Firebase user to get fresh emailVerified status
    _refreshFirebaseUser();
  }

  /// Reload the Firebase Auth user to ensure emailVerified is up-to-date
  Future<void> _refreshFirebaseUser() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (mounted) setState(() {});
    } catch (_) {
      // Ignore reload errors (e.g., no network)
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Settings'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(onPressed: _saveChanges, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Avatar with banner preview
          _buildAvatarSection(),
          const SizedBox(height: 20),

          // Profile Section
          _buildSectionHeader('Profile'),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _nameController,
            label: 'Display Name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _bioController,
            label: 'Bio',
            icon: Icons.info_outline,
            maxLines: 3,
            maxLength: 100,
            hint: 'Tell others about yourself...',
          ),
          if (_bioError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 12),
              child: Text(
                _bioError!,
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          _buildGenderSelector(),
          const SizedBox(height: 20),

          // Customization — collapsible
          _buildSectionHeader('Customization'),
          const SizedBox(height: 6),
          _buildBannerColorPicker(),
          const SizedBox(height: 20),

          // Contact & Security — unified card group
          _buildSectionHeader('Contact & Security'),
          const SizedBox(height: 6),
          _buildContactSecurityCard(),
          const SizedBox(height: 20),

          // App Settings
          _buildSectionHeader('App Settings'),
          const SizedBox(height: 6),
          _buildActionTile(
            icon: Icons.notifications_outlined,
            title: 'Notifications & Preferences',
            subtitle: 'Push notifications, app settings',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    int? maxLength,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildGenderChip('male', 'Male', Icons.male),
            _buildGenderChip('female', 'Female', Icons.female),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderChip(String value, String label, IconData icon) {
    final isSelected = _selectedGender == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedGender = selected ? value : null);
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: AppColors.surfaceVariant,
      onTap: onTap,
    );
  }

  Widget _buildBannerColorPicker() {
    final bannerColor = Color(_selectedBannerColor ?? 0xFF4A90E2);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Tappable header — always visible
          InkWell(
            onTap: () => setState(() => _isBannerExpanded = !_isBannerExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Banner Color',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  // Current color swatch
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: bannerColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: bannerColor.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _isBannerExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable body
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  // Preview banner
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          bannerColor,
                          bannerColor.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'Preview',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Color palette grid
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ..._colorPalette.map(
                        (colorValue) => _buildColorOption(colorValue),
                      ),
                      // Custom color button
                      GestureDetector(
                        onTap: _showCustomColorPicker,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.border,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.add,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            crossFadeState: _isBannerExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildColorOption(int colorValue) {
    final isSelected = _selectedBannerColor == colorValue;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedBannerColor = colorValue);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(colorValue),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Color(colorValue).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  void _showCustomColorPicker() {
    final hexController = TextEditingController();
    int? customColor = _selectedBannerColor;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Custom Color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Color preview
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Color(customColor ?? 0xFF4A90E2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 16),
              // Hex input
              TextField(
                controller: hexController,
                decoration: InputDecoration(
                  labelText: 'Hex Color',
                  hintText: '#4A90E2',
                  prefixIcon: const Icon(Icons.tag),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  String hex = value.replaceAll('#', '').toUpperCase();
                  if (hex.length == 6) {
                    try {
                      final parsed = int.parse('FF$hex', radix: 16);
                      setDialogState(() => customColor = parsed);
                    } catch (_) {}
                  }
                },
              ),
              const SizedBox(height: 16),
              // RGB sliders
              _buildColorSlider(
                label: 'Red',
                value: ((customColor ?? 0xFF4A90E2) >> 16) & 0xFF,
                color: Colors.red,
                onChanged: (val) {
                  setDialogState(() {
                    final g = ((customColor ?? 0xFF4A90E2) >> 8) & 0xFF;
                    final b = (customColor ?? 0xFF4A90E2) & 0xFF;
                    customColor = 0xFF000000 | (val << 16) | (g << 8) | b;
                  });
                },
              ),
              _buildColorSlider(
                label: 'Green',
                value: ((customColor ?? 0xFF4A90E2) >> 8) & 0xFF,
                color: Colors.green,
                onChanged: (val) {
                  setDialogState(() {
                    final r = ((customColor ?? 0xFF4A90E2) >> 16) & 0xFF;
                    final b = (customColor ?? 0xFF4A90E2) & 0xFF;
                    customColor = 0xFF000000 | (r << 16) | (val << 8) | b;
                  });
                },
              ),
              _buildColorSlider(
                label: 'Blue',
                value: (customColor ?? 0xFF4A90E2) & 0xFF,
                color: Colors.blue,
                onChanged: (val) {
                  setDialogState(() {
                    final r = ((customColor ?? 0xFF4A90E2) >> 16) & 0xFF;
                    final g = ((customColor ?? 0xFF4A90E2) >> 8) & 0xFF;
                    customColor = 0xFF000000 | (r << 16) | (g << 8) | val;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => _selectedBannerColor = customColor);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorSlider({
    required String label,
    required int value,
    required Color color,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
              inactiveTrackColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            '$value',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  void _validateBio() {
    final text = _bioController.text;
    final lineCount = '\n'.allMatches(text).length + 1;
    setState(() {
      if (lineCount > 3) {
        _bioError = 'Bio cannot exceed 3 lines';
      } else {
        _bioError = null;
      }
    });
  }

  Future<void> _saveChanges() async {
    if (_bioError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fix the bio before saving.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);

    try {
      await _profileService.updateProfile(
        userId: widget.profile.id,
        displayName: _nameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        bio: _bioController.text.trim(),
        gender: _selectedGender,
        bannerColor: _selectedBannerColor,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings saved!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate changes
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save settings. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _hasEmailProvider {
    final user = FirebaseAuth.instance.currentUser;
    // Google users also have a verified email
    return user?.providerData.any(
          (p) => p.providerId == 'password' || p.providerId == 'google.com',
        ) ??
        false;
  }

  bool get _hasPhoneProvider {
    final user = FirebaseAuth.instance.currentUser;
    return user?.providerData.any((p) => p.providerId == 'phone') ?? false;
  }

  Widget _buildContactSecurityCard() {
    final user = FirebaseAuth.instance.currentUser;
    final hasEmail = _hasEmailProvider;
    final emailText = _linkedEmail ?? widget.profile.email ?? user?.email;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Email tile
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(
              hasEmail && emailText != null ? emailText : 'Not linked',
              style: TextStyle(
                color: hasEmail ? null : AppColors.textSecondary,
              ),
            ),
            trailing: hasEmail
                ? (user != null && user.emailVerified
                      ? const Icon(
                          Icons.verified,
                          color: Colors.green,
                          size: 20,
                        )
                      : TextButton(
                          onPressed: _handleEmailVerification,
                          child: const Text('Verify'),
                        ))
                : TextButton(
                    onPressed: _linkEmail,
                    child: const Text('Link Email'),
                  ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: AppColors.border.withValues(alpha: 0.5),
          ),
          // Phone tile
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone'),
            subtitle: Text(
              _phoneController.text.isEmpty ? 'Not set' : _phoneController.text,
            ),
            trailing: _hasPhoneProvider
                ? const Icon(Icons.verified, color: Colors.green, size: 20)
                : const Icon(Icons.chevron_right, size: 20),
            onTap: () => _showEditPhoneDialog(),
          ),
          // Change Password — only if user has email/password provider
          if (hasEmail) ...[
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: AppColors.border.withValues(alpha: 0.5),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Change Password'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _changePassword,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleEmailVerification() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Email Verification'),
          content: const Text(
            'A verification email has been sent to your inbox.\n\n'
            'If you\'ve already clicked the link, tap "I\'ve Verified" to confirm.\n'
            'If you didn\'t receive the email, tap "Resend Email".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _resendVerificationEmail();
              },
              child: const Text('Resend Email'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _checkEmailVerificationStatus();
              },
              child: const Text("I've Verified"),
            ),
          ],
        );
      },
    );
  }

  /// Check if the user has already verified their email and award score
  Future<void> _checkEmailVerificationStatus() async {
    try {
      final authProvider = context.read<app_auth.AuthProvider>();
      final isVerified = await authProvider.checkEmailVerified();

      if (!mounted) return;

      if (isVerified) {
        // Refresh UI state
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email verified successfully! Credibility score updated.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Email not verified yet. Please check your inbox and click the verification link.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not check email status. Please try again.')),
        );
      }
    }
  }

  /// Resend the verification email
  Future<void> _resendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (kDebugMode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('[DEV] Email verification skipped in debug mode.'),
            ),
          );
        }
        return;
      }

      await user.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email sent! Check your inbox.'),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message;
        switch (e.code) {
          case 'too-many-requests':
            message =
                'Too many attempts. A verification email was already sent — please check your inbox.';
            break;
          default:
            message = e.message ?? 'Failed to send verification email.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not resend verification email. Please try again.')));
      }
    }
  }

  void _linkEmail() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    bool obscurePassword = true;
    bool obscureConfirm = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.link, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              const Text('Link Email', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Link an email address to your account so you can also sign in with email and set a password.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter an email';
                    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a password';
                    if (v.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(
                      Icons.check_circle_outline,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(
                        () => obscureConfirm = !obscureConfirm,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  validator: (v) {
                    if (v != passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                // Inline error banner — shown inside dialog, not behind it
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.error,
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
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        isLoading = true;
                        errorMessage = null;
                      });

                      try {
                        final credential = EmailAuthProvider.credential(
                          email: emailController.text.trim(),
                          password: passwordController.text,
                        );
                        await user.linkWithCredential(credential);

                        // Update email in Firestore profile
                        await _profileService.updateProfile(
                          userId: widget.profile.id,
                          email: emailController.text.trim(),
                        );

                        // Award credibility score for email verification (only once)
                        try {
                          final profileDoc = await FirebaseFirestore.instance
                              .collection('profiles')
                              .doc(widget.profile.id)
                              .get();
                          final verifications =
                              profileDoc.data()?['verifications']
                                  as Map<String, dynamic>? ??
                              {};
                          if (verifications['email'] != true) {
                            // Score awarded by AuthProvider._awardVerificationScore
                            await FirebaseFirestore.instance
                                .collection('profiles')
                                .doc(widget.profile.id)
                                .update({'verifications.email': true});
                          }
                        } catch (e) {
                          debugPrint(
                            '[AccountSettings] Error awarding email verify score: $e',
                          );
                        }

                        // Send verification (skip in debug)
                        if (!kDebugMode) {
                          await user.sendEmailVerification();
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          setState(() {
                            _linkedEmail = emailController.text.trim();
                          }); // Rebuild to show new email
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                kDebugMode
                                    ? 'Email linked! [DEV: verification skipped]'
                                    : 'Email linked! Check your inbox to verify.',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        String message;
                        switch (e.code) {
                          case 'email-already-in-use':
                            message =
                                'This email is already registered. Please use a different email.';
                            break;
                          case 'invalid-email':
                            message = 'Invalid email address.';
                            break;
                          case 'credential-already-in-use':
                            message =
                                'This credential is already linked to another account.';
                            break;
                          case 'provider-already-linked':
                            message =
                                'An email is already linked to this account.';
                            break;
                          default:
                            message = e.message ?? 'Something went wrong.';
                        }
                        setDialogState(() {
                          isLoading = false;
                          errorMessage = message;
                        });
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                          errorMessage =
                              'Something went wrong. Please try again.';
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Link'),
            ),
          ],
        ),
      ),
    );
  }

  void _changePassword() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    final currentPwdController = TextEditingController();
    final newPwdController = TextEditingController();
    final confirmPwdController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              const Text('Change Password', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentPwdController,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureCurrent
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(
                        () => obscureCurrent = !obscureCurrent,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Enter current password'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: newPwdController,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_reset, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscureNew = !obscureNew),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter new password';
                    if (v.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: confirmPwdController,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(
                      Icons.check_circle_outline,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(
                        () => obscureConfirm = !obscureConfirm,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                  ),
                  validator: (v) {
                    if (v != newPwdController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                // Inline error banner
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.error,
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
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        isLoading = true;
                        errorMessage = null;
                      });

                      try {
                        // Re-authenticate with current password
                        final credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: currentPwdController.text,
                        );
                        await user.reauthenticateWithCredential(credential);

                        // Update password
                        await user.updatePassword(newPwdController.text);

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password changed successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        String message;
                        switch (e.code) {
                          case 'wrong-password':
                          case 'invalid-credential':
                            message = 'Current password is incorrect.';
                            break;
                          case 'weak-password':
                            message =
                                'New password is too weak. Use at least 6 characters.';
                            break;
                          case 'requires-recent-login':
                            message =
                                'Please log out and log back in, then try again.';
                            break;
                          default:
                            message = e.message ?? 'Something went wrong.';
                        }
                        setDialogState(() {
                          isLoading = false;
                          errorMessage = message;
                        });
                      } catch (e) {
                        setDialogState(() {
                          isLoading = false;
                          errorMessage =
                              'Something went wrong. Please try again.';
                        });
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final bannerColor = Color(_selectedBannerColor ?? 0xFF4A90E2);
    final lighterColor = HSLColor.fromColor(bannerColor)
        .withLightness(
          (HSLColor.fromColor(bannerColor).lightness + 0.15).clamp(0.0, 1.0),
        )
        .toColor();

    return SizedBox(
      height: 170,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Banner gradient — fills the top half
          Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [bannerColor, lighterColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: bannerColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          // Avatar + button, centered on the banner edge
          Positioned(
            top: 55,
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: AppColors.surfaceVariant,
                        backgroundImage: _currentAvatarUrl != null
                            ? CachedNetworkImageProvider(_currentAvatarUrl!)
                            : null,
                        child: _currentAvatarUrl == null
                            ? Icon(
                                Icons.person,
                                size: 44,
                                color: AppColors.textSecondary,
                              )
                            : null,
                      ),
                    ),
                    if (_isUploadingAvatar)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black38,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: _showAvatarOptions,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: bannerColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _showAvatarOptions,
                  child: Text(
                    'Change Photo',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Validate Malaysian phone number (after stripping leading 0).
  /// Valid patterns: 01X-XXXXXXX (9–10 digits after the leading 0).
  /// Returns the cleaned digits (without leading 0) or null if invalid.
  String? _validateMalaysianPhone(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    // Strip leading 0 if user typed it (e.g. "0198974155" → "198974155")
    if (digits.startsWith('0')) digits = digits.substring(1);
    // Malaysian mobile: 9 or 10 digits after country code
    // Starts with 1 (e.g. 1X-XXXXXXX)
    if (digits.length < 9 || digits.length > 10) return null;
    if (!digits.startsWith('1')) return null;
    return digits;
  }

  void _showEditPhoneDialog() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Pre-fill: strip "+60" prefix if present
    String prefill = _phoneController.text;
    if (prefill.startsWith('+60')) prefill = prefill.substring(3);

    final phoneController = TextEditingController(text: prefill);
    final otpController = TextEditingController();
    bool isOtpStep = false;
    bool isLoading = false;
    String? errorMessage;
    String? verificationId;
    String? pendingPhone; // digits after +60

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isOtpStep ? Icons.sms_outlined : Icons.phone_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                isOtpStep ? 'Verify OTP' : 'Edit Phone',
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isOtpStep) ...[
                Text(
                  'Enter your Malaysian phone number. An OTP will be sent to verify it.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Locked +60 prefix
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.surfaceVariant,
                      ),
                      child: const Text(
                        '🇲🇾 +60',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Phone number input
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        autofocus: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '0123456789',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (isOtpStep) ...[
                Text(
                  'We sent a 6-digit code to +60$pendingPhone',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    hintText: '- - - - - -',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Didn't receive the code?",
                      style: TextStyle(fontSize: 12),
                    ),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              otpController.clear();
                              setDialogState(() {
                                errorMessage = null;
                                isLoading = true;
                              });
                              // Resend OTP
                              FirebaseAuth.instance.verifyPhoneNumber(
                                phoneNumber: '+60$pendingPhone',
                                verificationCompleted: (credential) async {
                                  // Auto-verify
                                  try {
                                    await user.updatePhoneNumber(credential);
                                    await _profileService.updateProfile(
                                      userId: widget.profile.id,
                                      phone: '+60$pendingPhone',
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      setState(() {
                                        _phoneController.text =
                                            '+60$pendingPhone';
                                      });
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Phone number verified and updated!',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    }
                                  } on FirebaseAuthException catch (e) {
                                    setDialogState(() {
                                      isLoading = false;
                                      errorMessage = _phoneErrorMessage(e.code);
                                    });
                                  }
                                },
                                verificationFailed: (e) {
                                  setDialogState(() {
                                    isLoading = false;
                                    errorMessage = _phoneErrorMessage(e.code);
                                  });
                                },
                                codeSent: (vId, _) {
                                  setDialogState(() {
                                    verificationId = vId;
                                    isLoading = false;
                                    errorMessage = null;
                                  });
                                },
                                codeAutoRetrievalTimeout: (_) {},
                              );
                            },
                      child: const Text(
                        'Resend',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                // Change number link
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          otpController.clear();
                          setDialogState(() {
                            isOtpStep = false;
                            errorMessage = null;
                          });
                        },
                  child: const Text(
                    'Change Phone Number',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
              // Inline error banner
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            if (!isOtpStep)
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final cleaned = _validateMalaysianPhone(
                          phoneController.text,
                        );
                        if (cleaned == null) {
                          setDialogState(() {
                            errorMessage =
                                'Invalid Malaysian phone number. Must start with 01 and be 10-11 digits.';
                          });
                          return;
                        }

                        // Check if same as current
                        if ('+60$cleaned' == _phoneController.text) {
                          setDialogState(() {
                            errorMessage =
                                'This is already your current phone number.';
                          });
                          return;
                        }

                        setDialogState(() {
                          isLoading = true;
                          errorMessage = null;
                          pendingPhone = cleaned;
                        });

                        // Check if phone number is already registered by another user
                        try {
                          final existingUsers = await FirebaseFirestore.instance
                              .collection('profiles')
                              .where('phone', isEqualTo: '+60$cleaned')
                              .limit(1)
                              .get();
                          if (existingUsers.docs.isNotEmpty) {
                            final existingUserId = existingUsers.docs.first.id;
                            if (existingUserId != user.uid) {
                              setDialogState(() {
                                isLoading = false;
                                errorMessage =
                                    'This phone number is already registered to another account.';
                              });
                              return;
                            }
                          }
                        } catch (e) {
                          debugPrint('[Phone] Error checking duplicate: $e');
                        }

                        FirebaseAuth.instance.verifyPhoneNumber(
                          phoneNumber: '+60$cleaned',
                          verificationCompleted: (credential) async {
                            // Auto-verify (Android)
                            try {
                              await user.updatePhoneNumber(credential);
                              await _profileService.updateProfile(
                                userId: widget.profile.id,
                                phone: '+60$cleaned',
                              );

                              // Award credibility score for phone verification (only once)
                              try {
                                final profileDoc = await FirebaseFirestore
                                    .instance
                                    .collection('profiles')
                                    .doc(widget.profile.id)
                                    .get();
                                final verifications =
                                    profileDoc.data()?['verifications']
                                        as Map<String, dynamic>? ??
                                    {};
                                if (verifications['phone'] != true) {
                                  // Score awarded by AuthProvider._awardVerificationScore
                                  await FirebaseFirestore.instance
                                      .collection('profiles')
                                      .doc(widget.profile.id)
                                      .update({'verifications.phone': true});
                                }
                              } catch (e) {
                                debugPrint(
                                  '[AccountSettings] Error updating phone verification: $e',
                                );
                              }

                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                setState(() {
                                  _phoneController.text = '+60$cleaned';
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Phone number verified and updated!',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } on FirebaseAuthException catch (e) {
                              setDialogState(() {
                                isLoading = false;
                                errorMessage = _phoneErrorMessage(e.code);
                              });
                            }
                          },
                          verificationFailed: (e) {
                            setDialogState(() {
                              isLoading = false;
                              errorMessage = _phoneErrorMessage(e.code);
                            });
                          },
                          codeSent: (vId, _) {
                            setDialogState(() {
                              verificationId = vId;
                              isOtpStep = true;
                              isLoading = false;
                            });
                          },
                          codeAutoRetrievalTimeout: (_) {},
                        );
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send OTP'),
              ),
            if (isOtpStep)
              FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final otp = otpController.text.trim();
                        if (otp.length != 6) {
                          setDialogState(() {
                            errorMessage = 'Please enter the 6-digit code.';
                          });
                          return;
                        }
                        if (verificationId == null) {
                          setDialogState(() {
                            errorMessage =
                                'Verification session expired. Please resend the code.';
                          });
                          return;
                        }

                        setDialogState(() {
                          isLoading = true;
                          errorMessage = null;
                        });

                        try {
                          final credential = PhoneAuthProvider.credential(
                            verificationId: verificationId!,
                            smsCode: otp,
                          );
                          await user.updatePhoneNumber(credential);
                          await _profileService.updateProfile(
                            userId: widget.profile.id,
                            phone: '+60$pendingPhone',
                          );

                          // Award credibility score for phone verification (only once)
                          try {
                            final profileDoc = await FirebaseFirestore.instance
                                .collection('profiles')
                                .doc(widget.profile.id)
                                .get();
                            final verifications =
                                profileDoc.data()?['verifications']
                                    as Map<String, dynamic>? ??
                                {};
                            if (verifications['phone'] != true) {
                              // Score awarded by AuthProvider._awardVerificationScore
                              await FirebaseFirestore.instance
                                  .collection('profiles')
                                  .doc(widget.profile.id)
                                  .update({'verifications.phone': true});
                            }
                          } catch (e) {
                            debugPrint(
                              '[AccountSettings] Error updating phone verification: $e',
                            );
                          }

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            setState(() {
                              _phoneController.text = '+60$pendingPhone';
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Phone number verified and updated!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            errorMessage = _phoneErrorMessage(e.code);
                          });
                        } catch (e) {
                          setDialogState(() {
                            isLoading = false;
                            errorMessage =
                                'Something went wrong. Please try again.';
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Verify'),
              ),
          ],
        ),
      ),
    );
  }

  /// Map Firebase phone-auth error codes to user-friendly messages.
  String _phoneErrorMessage(String code) {
    switch (code) {
      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';
      case 'invalid-phone-number':
        return 'Invalid phone number format.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-verification-code':
        return 'Incorrect verification code. Please try again.';
      case 'session-expired':
        return 'Verification session expired. Please resend the code.';
      case 'provider-already-linked':
        return 'A phone number is already linked to this account.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_currentAvatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );

      if (image != null && mounted) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: AppColors.primary,
              toolbarWidgetColor: Colors.white,
              backgroundColor: Colors.white,
              activeControlsWidgetColor: AppColors.primary,
              hideBottomControls: true,
            ),
            IOSUiSettings(
              title: 'Crop Photo',
              rotateButtonsHidden: true,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _uploadAvatar(File imageFile) async {
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
      final userId = widget.profile.id;
      final ref = FirebaseStorage.instance.ref().child('avatars/$userId.jpg');
      await ref.putFile(imageFile);
      final url = await ref.getDownloadURL();

      await _profileService.updateProfile(userId: userId, photoUrl: url);

      setState(() {
        _currentAvatarUrl = url;
        _isUploadingAvatar = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Photo updated!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUploadingAvatar = true);

    try {
      final userId = widget.profile.id;

      // Delete from storage
      try {
        await FirebaseStorage.instance
            .ref()
            .child('avatars/$userId.jpg')
            .delete();
      } catch (_) {}

      // Update profile
      await _profileService.updateProfile(userId: userId, photoUrl: '');

      setState(() {
        _currentAvatarUrl = null;
        _isUploadingAvatar = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo removed')));
      }
    } catch (e) {
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
          ),
        );
      }
    }
  }
}
