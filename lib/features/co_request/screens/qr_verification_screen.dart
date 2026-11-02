import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import 'package:app_settings/app_settings.dart';
import '../services/qr_verification_service.dart';
import '../../profile/services/profile_service.dart';
import 'review_screen.dart';

/// QR Verification Screen
/// - Owner mode: Shows QR code for participants to scan
/// - Participant mode: Scans QR code to verify presence
class QrVerificationScreen extends StatefulWidget {
  final String requestId;
  final List<String> participantIds;
  final String ownerId; // SECURITY: Owner ID to prevent self-verification
  final bool isOwner;
  final VoidCallback onAllVerified;

  const QrVerificationScreen({
    super.key,
    required this.requestId,
    required this.participantIds,
    required this.ownerId,
    required this.isOwner,
    required this.onAllVerified,
  });

  @override
  State<QrVerificationScreen> createState() => _QrVerificationScreenState();
}

class _QrVerificationScreenState extends State<QrVerificationScreen> {
  final _qrService = QrVerificationService();
  final _profileService = ProfileService();

  String? _qrData;
  bool _isLoading = true;
  bool _isScanning = false;
  bool _isVerified = false;
  bool _cameraPermissionDenied = false;
  bool _cameraPermissionPermanentlyDenied = false;
  MobileScannerController? _scannerController;
  StreamSubscription<VerificationStatus>? _statusSubscription;
  VerificationStatus? _status;
  final Map<String, String> _participantNames = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Load participant names
    for (final id in widget.participantIds) {
      final profile = await _profileService.getProfile(id);
      if (profile != null) {
        _participantNames[id] = profile.displayName;
      }
    }

    if (widget.isOwner) {
      // Generate QR code
      _qrData = await _qrService.generateQrCode(
        requestId: widget.requestId,
        participantIds: widget.participantIds,
        ownerId: widget.ownerId,
      );
    }

    // Listen to verification status
    _statusSubscription = _qrService
        .getVerificationStatus(widget.requestId)
        .listen((status) {
          setState(() => _status = status);
          if (status.isComplete) {
            widget.onAllVerified();
          }
        });

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOwner ? 'Verify Participants' : 'Scan to Verify'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.isOwner
          ? _buildOwnerView()
          : _buildParticipantView(),
    );
  }

  Widget _buildOwnerView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ask all participants to scan this QR code to confirm their presence.',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // QR Code
          if (_qrData != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrData!,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.primary,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          const SizedBox(height: 32),

          // Verification Status
          _buildVerificationStatus(),
        ],
      ),
    );
  }

  Widget _buildVerificationStatus() {
    final total = _status?.totalCount ?? 0;
    final verified = _status?.verifiedCount ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Verification Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: verified == total && total > 0
                      ? AppColors.success
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$verified / $total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? verified / total : 0,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(
                verified == total && total > 0
                    ? AppColors.success
                    : AppColors.primary,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),

          // Participant list
          ...widget.participantIds.map((id) {
            final isVerified = _status?.verifiedIds.contains(id) ?? false;
            final name = _participantNames[id] ?? 'Loading...';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isVerified
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isVerified ? AppColors.success : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: isVerified
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: isVerified
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isVerified)
                    Text(
                      'Verified',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            );
          }),

          // Complete button when all verified
          if (_status?.isComplete == true) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // Navigate to ReviewScreen to rate participants
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReviewScreen(
                        requestId: widget.requestId,
                        participantIds: widget.participantIds,
                        isHost: widget.isOwner, // P0 #3: Pass host status
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.check),
                label: const Text('Complete Request'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _startScanner() async {
    final status = await Permission.camera.request();

    if (status.isPermanentlyDenied) {
      setState(() {
        _cameraPermissionDenied = false;
        _cameraPermissionPermanentlyDenied = true;
      });
      return;
    }

    if (!status.isGranted) {
      setState(() {
        _cameraPermissionDenied = true;
        _cameraPermissionPermanentlyDenied = false;
      });
      return;
    }

    // mobile_scanner v7: do NOT call controller.start() manually before the
    // MobileScanner widget is in the tree — CameraX needs the widget's
    // lifecycle owner first. Setting _isScanning=true mounts the widget,
    // which auto-starts via autoStart:true (default).
    _scannerController?.dispose();
    _scannerController = MobileScannerController();
    setState(() {
      _isScanning = true;
      _cameraPermissionDenied = false;
      _cameraPermissionPermanentlyDenied = false;
    });
  }

  Widget _buildCameraPermissionDenied() {
    final isPermanent = _cameraPermissionPermanentlyDenied;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.no_photography_outlined,
              size: 80,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Camera Access Required',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isPermanent
                ? 'Camera permission was denied. Please enable it in your device settings to scan QR codes.'
                : 'Camera access is needed to scan QR codes for verification.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 40),
          if (isPermanent) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => AppSettings.openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _startScanner,
              icon: const Icon(Icons.refresh),
              label: Text(isPermanent ? 'Try Again' : 'Grant Permission'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantView() {
    if (_isVerified) {
      return _buildVerifiedSuccess();
    }

    if (_cameraPermissionDenied || _cameraPermissionPermanentlyDenied) {
      return _buildCameraPermissionDenied();
    }

    if (_isScanning) {
      return _buildScanner();
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.qr_code_scanner,
              size: 80,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Verify Your Presence',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scan the QR code shown by the host to confirm you are present for this split.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startScanner,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan QR Code'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onQrDetected,
          errorBuilder: (context, error) {
            // Called when CameraX fails to start after the widget mounts.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _scannerController?.dispose();
              _scannerController = null;
              setState(() {
                _isScanning = false;
                _cameraPermissionDenied = false;
                _cameraPermissionPermanentlyDenied =
                    error.errorCode == MobileScannerErrorCode.permissionDenied;
                if (!_cameraPermissionPermanentlyDenied) {
                  _cameraPermissionDenied = true;
                }
              });
            });
            return const Center(child: CircularProgressIndicator());
          },
        ),
        // Overlay
        Container(
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5)),
          child: Center(
            child: Builder(
              builder: (context) {
                final scannerSize = MediaQuery.of(context).size.width * 0.65;
                return Container(
              width: scannerSize,
              height: scannerSize,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
                );
              },
            ),
          ),
        ),
        // Close button
        Positioned(
          top: 40,
          left: 16,
          child: IconButton(
            onPressed: () {
              _scannerController?.stop();
              setState(() => _isScanning = false);
            },
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
          ),
        ),
        // Instructions
        Positioned(
          bottom: 100,
          left: 40,
          right: 40,
          child: Text(
            'Point your camera at the QR code',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerifiedSuccess() {
    final size = MediaQuery.of(context).size;
    final shortest = size.shortestSide;
    final iconBoxPadding = (shortest * 0.08).clamp(24.0, 40.0);
    final iconSize = (shortest * 0.20).clamp(64.0, 96.0);
    final gapIconToTitle = size.height * 0.04;
    final gapTitleToBody = size.height * 0.015;
    final gapBodyToButton = size.height * 0.05;
    final buttonHPadding = (size.width * 0.10).clamp(24.0, 48.0);

    return SafeArea(
      // MIUI reports a bogus horizontal inset after the camera closes,
      // which shifts the whole column left. Only the vertical insets matter here.
      left: false,
      right: false,
      child: MediaQuery(
        // Cap accessibility scaling so 200% system font doesn't blow out the layout.
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(maxScaleFactor: 1.3),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(iconBoxPadding),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  size: iconSize,
                  color: AppColors.success,
                ),
              ),
              SizedBox(height: gapIconToTitle),
              Text(
                'Verified!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
              SizedBox(height: gapTitleToBody),
              Text(
                'Your presence has been confirmed.\nWaiting for host to complete the request.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: gapBodyToButton),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: buttonHPadding,
                    vertical: 14,
                  ),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onQrDetected(BarcodeCapture capture) async {
    if (_isVerified) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() => _isScanning = false);

    final result = await _qrService.verifyParticipant(
      qrData: barcode!.rawValue!,
      participantId: userId,
    );

    if (mounted) {
      if (result.success) {
        setState(() => _isVerified = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
