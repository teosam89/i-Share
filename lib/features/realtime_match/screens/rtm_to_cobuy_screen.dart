import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../realtime_match/models/realtime_match_model.dart';
import '../../realtime_match/services/realtime_match_service.dart';
import '../../co_request/models/co_request_model.dart';
import '../../co_request/providers/co_request_provider.dart';

/// RtmToCoBuyScreen - Specialized screen for converting a Real-Time Match to a Co-Buy Request
/// Category, location, and partners are locked based on the RTM data
/// Participants are automatically added from the RTM
class RtmToCoBuyScreen extends StatefulWidget {
  final RealtimeMatch match;

  const RtmToCoBuyScreen({super.key, required this.match});

  @override
  State<RtmToCoBuyScreen> createState() => _RtmToCoBuyScreenState();
}

class _RtmToCoBuyScreenState extends State<RtmToCoBuyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _productNameController = TextEditingController();
  final _dealDescriptionController = TextEditingController();
  final _totalPriceController = TextEditingController();

  String? _capturedImagePath;
  int _totalQuantity = 2;
  bool _isSubmitting = false;
  int _expiryHours = 2;

  final ImagePicker _imagePicker = ImagePicker();

  // Locked values from RTM
  late final String _lockedCategory;
  late final String _lockedLocation;
  late final double _lockedLatitude;
  late final double _lockedLongitude;
  late final int _lockedPartnersNeeded;
  late final List<String> _lockedParticipants;

  // Common deal types for quick selection
  final List<String> _dealSuggestions = [
    'Buy 2 Free 1',
    'Buy 1 Get 50% Off',
    'Bulk Discount',
  ];

  @override
  void initState() {
    super.initState();
    // Lock values from RTM - these cannot be changed
    _lockedCategory = widget.match.category;
    _lockedLocation = widget.match.locationName;
    _lockedLatitude = widget.match.latitude;
    _lockedLongitude = widget.match.longitude;
    // Partners needed = participants - 1 (because initiator is counted separately)
    _lockedPartnersNeeded = widget.match.participantCount - 1;
    _lockedParticipants = List.from(widget.match.participants);

    // Pre-fill product name from owner's intent
    final ownerIntent =
        widget.match.participantIntents[widget.match.ownerId];
    if (ownerIntent != null && ownerIntent.isNotEmpty) {
      _productNameController.text = ownerIntent;
    }
  }

  @override
  void dispose() {
    _productNameController.dispose();
    _dealDescriptionController.dispose();
    _totalPriceController.dispose();
    super.dispose();
  }

  String _getCategoryLabel(String category) {
    return RequestCategories.labels[category] ?? category;
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_capturedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please take a photo of the product'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final provider = context.read<CoRequestProvider>();
      final matchService = RealtimeMatchService();

      // Calculate price per person (used for logging/debugging)
      final totalPrice = double.parse(_totalPriceController.text);
      final totalPeople = _lockedPartnersNeeded + 1;
      final _ =
          (totalPrice / totalPeople * 100).round() /
          100; // pricePerPerson for future use

      // 1. Create the Co-Buy Request
      final requestId = await provider.createRequest(
        productName: _productNameController.text.trim(),
        productPhotoPath: _capturedImagePath,
        dealDescription: _dealDescriptionController.text.trim(),
        totalPrice: totalPrice,
        totalQuantity: _totalQuantity,
        partnersNeeded: _lockedPartnersNeeded,
        category: _lockedCategory,
        storeName: _lockedLocation,
        latitude: _lockedLatitude,
        longitude: _lockedLongitude,
        expiryHours: _expiryHours,
      );

      if (requestId == null) {
        throw Exception('Failed to create request');
      }

      // 2. Add all RTM participants to the new Co-Buy Request (best-effort)
      final allAdded = await _addParticipantsToRequest(requestId);

      // 3. Close the RTM match — must run even if participant adds partially failed,
      // to prevent the match from being stuck in 'matched' status indefinitely.
      final matchClosed = await matchService.closeMatchForConversion(
        widget.match.id,
        requestId,
      );

      if (!mounted) return;

      if (!allAdded || !matchClosed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !allAdded
                  ? 'Co-Buy created. Some partners may need to re-join manually.'
                  : 'Co-Buy created, but the match room could not be closed. It will be cleaned up automatically.',
            ),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Co-Buy Request created! All partners have been added.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Something went wrong. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Add all RTM participants (except initiator) to the Co-Buy request.
  /// Returns true only if every participant was added successfully.
  Future<bool> _addParticipantsToRequest(String requestId) async {
    final currentUserId = context.read<CoRequestProvider>().currentUserId;
    if (currentUserId == null) return false;

    bool allAdded = true;
    for (final participantId in _lockedParticipants) {
      if (participantId != currentUserId) {
        final success = await _addParticipantDirectly(requestId, participantId);
        if (!success) allAdded = false;
      }
    }
    return allAdded;
  }

  /// Add a single participant to the Co-Buy request.
  /// Returns true if successful, false on any failure.
  Future<bool> _addParticipantDirectly(
    String requestId,
    String participantId,
  ) async {
    try {
      return await context.read<CoRequestProvider>().addParticipantFromRtm(
        requestId: requestId,
        participantId: participantId,
      );
    } catch (e) {
      debugPrint('[RtmToCoBuy] Error adding participant $participantId: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Co-Buy from Match')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // RTM Info Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flash_on, color: AppColors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Converting from Real-Time Match',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.info,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_lockedParticipants.length} partners will be automatically added',
                            style: TextStyle(
                              fontSize: 12,
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

              // ============ LOCKED FIELDS SECTION ============
              _buildSectionTitle('Match Details', isLocked: true),
              const SizedBox(height: 8),
              _buildLockedField(
                icon: Icons.category_outlined,
                label: 'Category',
                value: _getCategoryLabel(_lockedCategory),
              ),
              _buildLockedField(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: _lockedLocation,
              ),
              _buildLockedField(
                icon: Icons.group_outlined,
                label: 'Partners',
                value: '$_lockedPartnersNeeded partner(s) from match',
              ),
              const SizedBox(height: 24),

              // ============ PRODUCT PHOTO SECTION ============
              _buildSectionTitle('Product Photo', isRequired: true),
              const SizedBox(height: 8),
              _buildCameraCapture(),
              const SizedBox(height: 24),

              // ============ PRODUCT INFO SECTION ============
              _buildSectionTitle('Product Details', isRequired: true),
              const SizedBox(height: 8),

              // Product Name
              TextFormField(
                controller: _productNameController,
                decoration: const InputDecoration(
                  labelText: 'Product Name',
                  hintText: 'e.g., Detergent 3L Pack',
                  prefixIcon: Icon(Icons.shopping_bag_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter product name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Deal Description with suggestions
              _buildSectionTitle('Deal Description', isRequired: true),
              const SizedBox(height: 8),
              _buildDealSuggestions(),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dealDescriptionController,
                decoration: const InputDecoration(
                  labelText: 'Deal Description',
                  hintText: 'e.g., Buy 2 Free 1',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please describe the deal';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // ============ SPLIT LOGIC SECTION ============
              _buildSectionTitle('Split Details', isRequired: true),
              const SizedBox(height: 8),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Total Price
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _totalPriceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Total Price',
                        hintText: '0.00',
                        prefixIcon: Container(
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          alignment: Alignment.center,
                          width: 48,
                          child: Text(
                            'RM',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter price';
                        }
                        final price = double.tryParse(value);
                        if (price == null || price <= 0) {
                          return 'Invalid price';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Total Quantity
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Qty',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildQuantitySelector(),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Price per person preview
              if (_totalPriceController.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people, color: AppColors.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Price per person',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              'RM ${_calculatePricePerPerson().toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${_lockedPartnersNeeded + 1} people',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // ============ EXPIRY SECTION ============
              _buildSectionTitle('Request Expires In'),
              const SizedBox(height: 8),
              _buildExpirySelector(),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submitRequest,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _isSubmitting
                        ? 'Creating...'
                        : 'Create Co-Buy & Close Match',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  double _calculatePricePerPerson() {
    final price = double.tryParse(_totalPriceController.text) ?? 0;
    final totalPeople = _lockedPartnersNeeded + 1;
    return (price / totalPeople * 100).round() / 100;
  }

  Widget _buildSectionTitle(
    String title, {
    bool isRequired = false,
    bool isLocked = false,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (isRequired) Text(' *', style: TextStyle(color: AppColors.error)),
        if (isLocked) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.textTertiary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Locked',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLockedField({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lock, size: 14, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildCameraCapture() {
    return GestureDetector(
      onTap: _capturePhoto,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _capturedImagePath != null
                ? AppColors.primary
                : AppColors.border,
            width: 2,
          ),
        ),
        child: _capturedImagePath == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 32,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to take photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(_capturedImagePath!),
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      onPressed: _capturePhoto,
                      icon: const Icon(Icons.camera_alt),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _capturePhoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.camera_alt, color: AppColors.primary),
                ),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.photo_library, color: AppColors.secondary),
                ),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );

      if (pickedFile != null && mounted) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Photo',
              toolbarColor: AppColors.primary,
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: false,
              hideBottomControls: true,
            ),
            IOSUiSettings(
              title: 'Crop Photo',
              rotateButtonsHidden: true,
              resetButtonHidden: true,
              aspectRatioPickerButtonHidden: true,
            ),
          ],
        );

        if (croppedFile != null && mounted) {
          setState(() => _capturedImagePath = croppedFile.path);
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

  Widget _buildDealSuggestions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _dealSuggestions.map((deal) {
        return ActionChip(
          label: Text(deal, style: const TextStyle(fontSize: 12)),
          onPressed: () {
            _dealDescriptionController.text = deal;
            setState(() {});
          },
          backgroundColor: AppColors.surfaceVariant,
        );
      }).toList(),
    );
  }

  Widget _buildQuantitySelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _totalQuantity > 1
                ? () => setState(() => _totalQuantity--)
                : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.remove,
                size: 20,
                color: _totalQuantity <= 1
                    ? AppColors.textTertiary
                    : AppColors.primary,
              ),
            ),
          ),
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '$_totalQuantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          InkWell(
            onTap: _totalQuantity < 10
                ? () => setState(() => _totalQuantity++)
                : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.add,
                size: 20,
                color: _totalQuantity >= 10
                    ? AppColors.textTertiary
                    : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpirySelector() {
    final options = [1, 2, 4, 8, 24];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((hours) {
        final isSelected = _expiryHours == hours;
        return ChoiceChip(
          label: Text(hours == 24 ? '24h' : '${hours}h'),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) setState(() => _expiryHours = hours);
          },
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        );
      }).toList(),
    );
  }
}
