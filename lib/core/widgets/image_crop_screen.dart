import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import '../constants/app_colors.dart';

/// Pure Flutter image cropping screen with better UX
class ImageCropScreen extends StatefulWidget {
  final String imagePath;
  final String title;

  const ImageCropScreen({
    super.key,
    required this.imagePath,
    this.title = 'Edit Photo',
  });

  /// Show the crop screen and return the cropped image path
  static Future<String?> show(
    BuildContext context,
    String imagePath, {
    String title = 'Edit Photo',
  }) async {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageCropScreen(imagePath: imagePath, title: title),
      ),
    );
  }

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final _cropController = CropController();
  Uint8List? _imageData;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCircle = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = File(widget.imagePath);
    final bytes = await file.readAsBytes();
    setState(() {
      _imageData = bytes;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _saveCroppedImage,
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading || _imageData == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Crop area
                Expanded(
                  child: Container(
                    color: Colors.grey.shade100,
                    padding: const EdgeInsets.all(16),
                    child: Crop(
                      controller: _cropController,
                      image: _imageData!,
                      onCropped: _onCropped,
                      withCircleUi: _isCircle,
                      baseColor: Colors.grey.shade200,
                      maskColor: Colors.black45,
                      cornerDotBuilder: (size, edgeAlignment) => Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      interactive: true,
                      fixCropRect: false,
                      progressIndicator: const CircularProgressIndicator(),
                    ),
                  ),
                ),
                // Bottom controls
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(15),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: _isCircle
                            ? Icons.crop_square_rounded
                            : Icons.circle_outlined,
                        label: _isCircle ? 'Square' : 'Circle',
                        onTap: () => setState(() => _isCircle = !_isCircle),
                      ),
                      _buildControlButton(
                        icon: Icons.check_circle,
                        label: 'Confirm',
                        isPrimary: true,
                        onTap: _saveCroppedImage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary ? AppColors.primary : AppColors.textSecondary,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
                color: isPrimary ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveCroppedImage() {
    setState(() => _isSaving = true);
    _cropController.crop();
  }

  Future<void> _onCropped(CropResult result) async {
    try {
      if (result is CropSuccess) {
        // Save to temp file
        final tempDir = await path_provider.getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final croppedPath = '${tempDir.path}/cropped_$timestamp.jpg';
        final file = File(croppedPath);
        await file.writeAsBytes(result.croppedImage);

        if (mounted) {
          Navigator.pop(context, croppedPath);
        }
      } else {
        throw Exception('Crop failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving image: $e')));
      }
    }
  }
}
