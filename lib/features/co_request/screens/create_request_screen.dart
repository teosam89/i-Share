import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../models/co_request_model.dart';
import '../providers/co_request_provider.dart';
import '../services/location_service.dart';
import '../widgets/common_widgets.dart';
import '../../chat/services/chat_service.dart';
import 'location_picker_screen.dart';

/// Create Request Screen - Form for creating a new co-request
/// Supports both creating new requests and editing existing ones
/// Also supports pre-filling from Real-Time Match
class CreateRequestScreen extends StatefulWidget {
  final dynamic editRequest; // CoRequest to edit (null for new request)

  // Optional prefilled data from Real-Time Match
  final String? prefilledCategory;
  final String? prefilledLocation;
  final double? prefilledLatitude;
  final double? prefilledLongitude;
  final int? prefilledPartnersNeeded;
  final bool fromRealtimeMatch;
  final String? realtimeMatchId;

  const CreateRequestScreen({
    super.key,
    this.editRequest,
    this.prefilledCategory,
    this.prefilledLocation,
    this.prefilledLatitude,
    this.prefilledLongitude,
    this.prefilledPartnersNeeded,
    this.fromRealtimeMatch = false,
    this.realtimeMatchId,
  });

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _productNameController = TextEditingController();
  final _dealDescriptionController = TextEditingController();
  final _totalPriceController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _notesController = TextEditingController();

  // Section keys for auto-scroll on validation failure
  final _photoSectionKey = GlobalKey();
  final _productNameKey = GlobalKey();
  final _dealDescriptionKey = GlobalKey();
  final _priceSectionKey = GlobalKey();
  final _locationSectionKey = GlobalKey();

  String? _capturedImagePath; // Will store camera image path
  String? _existingPhotoUrl; // Existing photo URL for edit mode
  int _totalQuantity = 1;
  int _partnersNeeded = 1;
  String _selectedCategory = 'groceries';
  bool _isSubmitting = false;

  bool get _isEditMode => widget.editRequest != null;

  // GPS Location state
  double? _latitude;
  double? _longitude;
  String? _locationAddress;
  bool _isLoadingLocation = false;
  final LocationService _locationService = LocationService();

  // Common deal types for quick selection
  final List<String> _dealSuggestions = [
    'Buy 2 Free 1',
    'Buy 1 Get 50% Off',
    'Bulk Discount',
  ];

  @override
  void initState() {
    super.initState();

    if (_isEditMode) {
      // Pre-fill form with existing request data
      final req = widget.editRequest;
      _productNameController.text = req.productName ?? '';
      _dealDescriptionController.text = req.dealDescription ?? '';
      _totalPriceController.text = req.totalPrice?.toString() ?? '';
      _storeNameController.text = req.storeName ?? '';
      _totalQuantity = req.totalQuantity ?? 1;
      _partnersNeeded = req.partnersNeeded ?? 1;
      _selectedCategory = req.category ?? 'groceries';
      _latitude = req.latitude;
      _longitude = req.longitude;
      _locationAddress = req.storeName;
      // Preserve existing photo URL
      _existingPhotoUrl = req.productPhotoUrl;
      // Pre-fill notes if available
      _notesController.text = req.notes ?? '';
    } else if (widget.fromRealtimeMatch) {
      // Pre-fill from Real-Time Match data
      _selectedCategory = widget.prefilledCategory ?? 'groceries';
      _partnersNeeded = widget.prefilledPartnersNeeded ?? 1;
      _latitude = widget.prefilledLatitude;
      _longitude = widget.prefilledLongitude;
      _locationAddress = widget.prefilledLocation;
      _storeNameController.text = widget.prefilledLocation ?? '';
      // Don't fetch GPS location since we have it from RTM
    } else {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _productNameController.dispose();
    _dealDescriptionController.dispose();
    _totalPriceController.dispose();
    _storeNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Smoothly scroll to the widget with the given key
  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.1, // show near top with some padding
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Request' : 'Create Split Request'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ============ CAMERA CAPTURE SECTION ============
              Container(
                key: _photoSectionKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Product Photo', isRequired: true),
                    const SizedBox(height: 8),
                    _buildCameraCapture(),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ============ PRODUCT INFO SECTION ============

              // Product Name
              TextFormField(
                key: _productNameKey,
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
                key: _dealDescriptionKey,
                controller: _dealDescriptionController,
                decoration: const InputDecoration(
                  labelText: 'Describe the deal',
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
                      key: _priceSectionKey,
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

              // Partners Needed
              _buildSectionTitle('Split With'),
              const SizedBox(height: 2),
              Text(
                'How many people to split with (excluding you)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              _buildPartnersSelector(),
              const SizedBox(height: 16),

              // Price Protection Preview
              if (_totalPriceController.text.isNotEmpty)
                PriceProtectionDisplay(
                  totalPrice: double.tryParse(_totalPriceController.text) ?? 0,
                  partnersNeeded: _partnersNeeded,
                ),
              const SizedBox(height: 24),

              // ============ CATEGORY SECTION ============
              _buildSectionTitle('Category'),
              const SizedBox(height: 8),
              _buildCategorySelector(),
              const SizedBox(height: 24),

              // ============ NOTES SECTION ============
              _buildSectionTitle('Additional Notes'),
              const SizedBox(height: 4),
              Text(
                'Optional — add any details for potential partners',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                maxLength: 300,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText:
                      'e.g. Need 1 more person urgently, will be at the store until 5pm, prefer to meet at entrance...',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 24),

              // ============ LOCATION SECTION ============
              Container(
                key: _locationSectionKey,
                child: _buildSectionTitle('Meetup Location', isRequired: true),
              ),
              const SizedBox(height: 8),

              // GPS Location indicator
              GestureDetector(
                onTap: _getCurrentLocation,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _latitude != null
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _latitude != null
                          ? AppColors.success.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      _isLoadingLocation
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.info,
                              ),
                            )
                          : Icon(
                              _latitude != null
                                  ? Icons.check_circle
                                  : Icons.my_location,
                              color: _latitude != null
                                  ? AppColors.success
                                  : AppColors.info,
                              size: 20,
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _latitude != null
                                  ? 'Location captured'
                                  : 'Getting your location...',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: _latitude != null
                                    ? AppColors.success
                                    : AppColors.info,
                              ),
                            ),
                            Text(
                              _locationAddress ??
                                  (_isLoadingLocation
                                      ? 'Please wait...'
                                      : 'Tap to refresh location'),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (_latitude != null && !_isLoadingLocation)
                        IconButton(
                          icon: Icon(
                            Icons.refresh,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                          onPressed: _getCurrentLocation,
                          tooltip: 'Refresh location',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Mini Map Preview (shown when location is set)
              if (_latitude != null && _longitude != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: _openLocationPicker,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 150,
                        width: double.infinity,
                        child: AbsorbPointer(
                          child: GoogleMap(
                            key: ValueKey('map_${_latitude}_${_longitude}'),
                            initialCameraPosition: CameraPosition(
                              target: LatLng(_latitude!, _longitude!),
                              zoom: 15,
                            ),
                            markers: {
                              Marker(
                                markerId: const MarkerId('selected'),
                                position: LatLng(_latitude!, _longitude!),
                              ),
                            },
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                            myLocationButtonEnabled: false,
                            scrollGesturesEnabled: false,
                            zoomGesturesEnabled: false,
                            rotateGesturesEnabled: false,
                            tiltGesturesEnabled: false,
                            liteModeEnabled: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Open Map Picker button
              OutlinedButton.icon(
                onPressed: _openLocationPicker,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Select on Map'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
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
                  icon: const Icon(Icons.send),
                  label: Text(_isEditMode ? 'Save Changes' : 'Post Request'),
                  style: ElevatedButton.styleFrom(
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

  Widget _buildSectionTitle(String title, {bool isRequired = false}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (isRequired) Text(' *', style: TextStyle(color: AppColors.error)),
      ],
    );
  }

  Widget _buildCameraCapture() {
    // Determine which image to show
    final hasLocalImage = _capturedImagePath != null;
    final hasNetworkImage = _existingPhotoUrl != null && !hasLocalImage;
    final hasAnyImage = hasLocalImage || hasNetworkImage;

    return GestureDetector(
      onTap: _capturePhoto,
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasAnyImage ? AppColors.primary : AppColors.border,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: !hasAnyImage
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap to take photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Take a photo of the product',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  // Display image (local file or network)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: hasLocalImage
                        ? Image.file(
                            File(_capturedImagePath!),
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildImageError(),
                          )
                        : CachedNetworkImage(
                            imageUrl: _existingPhotoUrl!,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (_, __, ___) => _buildImageError(),
                          ),
                  ),
                  // Change photo button
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
                  // Status indicator
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: hasLocalImage
                            ? AppColors.success
                            : AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasLocalImage ? Icons.check : Icons.photo,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasLocalImage ? 'New Photo' : 'Current Photo',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildImageError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 8),
          const Text('Failed to load image'),
        ],
      ),
    );
  }

  final ImagePicker _imagePicker = ImagePicker();

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
              Text(
                'Add Product Photo',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
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
                subtitle: const Text('Use camera to capture product'),
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
                subtitle: const Text('Select an existing photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
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
        // Simple crop - minimal UI
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: pickedFile.path,
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
          setState(() {
            _capturedImagePath = croppedFile.path;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                source == ImageSource.camera
                    ? 'Photo captured!'
                    : 'Photo selected!',
              ),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to process image. Please try again.'),
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
          // Decrease button
          InkWell(
            onTap: _totalQuantity > 1
                ? () => setState(() => _totalQuantity--)
                : null,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(7),
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _totalQuantity <= 1
                    ? AppColors.surfaceVariant
                    : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(7),
                ),
              ),
              child: Icon(
                Icons.remove,
                size: 20,
                color: _totalQuantity <= 1
                    ? AppColors.textTertiary
                    : AppColors.primary,
              ),
            ),
          ),
          // Value display
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: AppColors.border),
              ),
            ),
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
          // Increase button
          InkWell(
            onTap: _totalQuantity < 10
                ? () => setState(() => _totalQuantity++)
                : null,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(7),
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _totalQuantity >= 10
                    ? AppColors.surfaceVariant
                    : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(7),
                ),
              ),
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

  Widget _buildPartnersSelector() {
    final presetCounts = [1, 2, 3, 4];
    final isCustomSelected = _partnersNeeded > 4;

    return Column(
      children: [
        Row(
          children: presetCounts.map((count) {
            final isSelected = _partnersNeeded == count;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: count < 4 ? 8 : 0),
                child: InkWell(
                  onTap: () => setState(() => _partnersNeeded = count),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.person_add,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Custom stepper (5-10)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCustomSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCustomSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.group_add,
                color: isCustomSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'More (5-10)',
                  style: TextStyle(
                    color: isCustomSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: isCustomSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
              // Stepper controls
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Decrease button
                    InkWell(
                      onTap: () {
                        if (_partnersNeeded > 5) {
                          setState(() => _partnersNeeded--);
                        } else if (_partnersNeeded == 5) {
                          setState(() => _partnersNeeded = 4);
                        }
                      },
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(7),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_partnersNeeded <= 4)
                              ? AppColors.surfaceVariant
                              : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(7),
                          ),
                        ),
                        child: Icon(
                          Icons.remove,
                          size: 20,
                          color: (_partnersNeeded <= 4)
                              ? AppColors.textTertiary
                              : AppColors.primary,
                        ),
                      ),
                    ),
                    // Value display
                    Container(
                      width: 48,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          vertical: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Text(
                        isCustomSelected ? '$_partnersNeeded' : '5',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isCustomSelected
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                    // Increase button
                    InkWell(
                      onTap: () {
                        if (_partnersNeeded < 5) {
                          setState(() => _partnersNeeded = 5);
                        } else if (_partnersNeeded < 10) {
                          setState(() => _partnersNeeded++);
                        }
                      },
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(7),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_partnersNeeded >= 10)
                              ? AppColors.surfaceVariant
                              : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(7),
                          ),
                        ),
                        child: Icon(
                          Icons.add,
                          size: 20,
                          color: (_partnersNeeded >= 10)
                              ? AppColors.textTertiary
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RequestCategories.all.map((category) {
        final isSelected = _selectedCategory == category;
        return ChoiceChip(
          selected: isSelected,
          showCheckmark: false,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                RequestCategories.icons[category] ??
                    'assets/icons/CateOthers.png',
                width: RequestCategories.iconSizes[category] ?? 24,
                height: RequestCategories.iconSizes[category] ?? 24,
              ),
              const SizedBox(width: 6),
              Text(RequestCategories.labels[category] ?? category),
            ],
          ),
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
          onSelected: (_) => setState(() => _selectedCategory = category),
        );
      }).toList(),
    );
  }

  int _selectedExpiryHours = 2;

  // Custom expiry: separate days/hours state for the D/H UI
  int _customDays = 1;
  int _customHours = 0;

  Widget _buildExpirySelector() {
    final presetOptions = [1, 2, 4, 8, 12];
    // Custom is active when not matching any preset (or explicitly set)
    final isCustomSelected = !([1, 2, 4, 8, 12].contains(_selectedExpiryHours));

    return Column(
      children: [
        // Preset options (1h - 12h)
        Row(
          children: presetOptions.map((hours) {
            final isSelected = _selectedExpiryHours == hours;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: hours != 12 ? 6 : 0),
                child: InkWell(
                  onTap: () => setState(() => _selectedExpiryHours = hours),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${hours}h',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Custom D/H stepper section
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isCustomSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCustomSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    color: isCustomSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom (max 7 days)',
                          style: TextStyle(
                            color: isCustomSelected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontWeight: isCustomSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (isCustomSelected)
                          Text(
                            _formatExpiryTime(_selectedExpiryHours),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isCustomSelected)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _customDays = 0;
                          _customHours = 13;
                          _selectedExpiryHours = 13;
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Set'),
                    ),
                ],
              ),
              // D/H steppers - only shown when custom is active
              if (isCustomSelected) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    // ─── Days stepper ───
                    Expanded(
                      child: _buildDHStepper(
                        label: 'Days',
                        value: _customDays,
                        // Can decrease if days > 0 (will borrow hours if needed)
                        canDecrease: _customDays > 0,
                        canIncrease: _customDays < 7,
                        onDecrease: () {
                          setState(() {
                            _customDays--;
                            // If total < 1h after decrease, set hours to 1
                            if (_customDays == 0 && _customHours < 1) {
                              _customHours = 1;
                            }
                            _syncExpiryFromDH();
                          });
                        },
                        onIncrease: () {
                          setState(() {
                            if (_customDays < 7) {
                              _customDays++;
                              // If reached 7 days, lock hours to 0
                              if (_customDays == 7) {
                                _customHours = 0;
                              }
                            }
                            _syncExpiryFromDH();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ─── Hours stepper ───
                    Expanded(
                      child: _buildDHStepper(
                        label: 'Hours',
                        value: _customHours,
                        // Can't go below 1h when 0 days; can't decrease below 0h otherwise
                        canDecrease: _customDays > 0
                            ? _customHours > 0
                            : _customHours > 1,
                        // Can't increase if 7 days
                        canIncrease: _customDays < 7 && _customHours < 23,
                        onDecrease: () {
                          setState(() {
                            if (_customDays == 0 && _customHours <= 1) {
                              // Floor: 0d 1h minimum
                              return;
                            }
                            _customHours--;
                            _syncExpiryFromDH();
                          });
                        },
                        onIncrease: () {
                          setState(() {
                            if (_customDays >= 7) return; // 7d → hours locked
                            if (_customHours < 23) {
                              _customHours++;
                            } else {
                              // 23h → roll over to next day, hours = 0
                              _customHours = 0;
                              _customDays++;
                              if (_customDays == 7) {
                                _customHours = 0;
                              }
                            }
                            _syncExpiryFromDH();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Sync _selectedExpiryHours from D/H values
  void _syncExpiryFromDH() {
    _selectedExpiryHours = (_customDays * 24) + _customHours;
  }

  /// Build a single D or H stepper widget
  Widget _buildDHStepper({
    required String label,
    required int value,
    required bool canDecrease,
    required bool canIncrease,
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Decrease
              InkWell(
                onTap: canDecrease ? onDecrease : null,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: canDecrease
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.remove,
                    size: 16,
                    color: canDecrease
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              // Value
              SizedBox(
                width: 36,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              // Increase
              InkWell(
                onTap: canIncrease ? onIncrease : null,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: canIncrease
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: canIncrease
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatExpiryTime(int hours) {
    if (hours < 24) return '$hours hours';
    final days = hours ~/ 24;
    final remainingHours = hours % 24;
    if (remainingHours == 0) {
      return '$days day${days > 1 ? 's' : ''}';
    }
    return '$days day${days > 1 ? 's' : ''} ${remainingHours}h';
  }

  Future<void> _submitRequest() async {
    // ── 1. Check photo first (before form validate, since photo isn't a FormField)
    final hasImage =
        _capturedImagePath != null ||
        (_isEditMode && _existingPhotoUrl != null);
    if (!hasImage) {
      _scrollToKey(_photoSectionKey);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please take a photo of the product'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // ── 2. Validate text form fields — and scroll to first invalid field
    if (!_formKey.currentState!.validate()) {
      // Find the first field that failed validation and scroll to it
      if (_productNameController.text.trim().isEmpty) {
        _scrollToKey(_productNameKey);
      } else if (_dealDescriptionController.text.trim().isEmpty) {
        _scrollToKey(_dealDescriptionKey);
      } else if (_totalPriceController.text.isEmpty ||
          (double.tryParse(_totalPriceController.text) ?? 0) <= 0) {
        _scrollToKey(_priceSectionKey);
      }
      return;
    }

    // ── 3. Require location to be set
    if (_latitude == null || _longitude == null) {
      _scrollToKey(_locationSectionKey);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a location for this deal'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final provider = context.read<CoRequestProvider>();

      if (_isEditMode) {
        // Build changes list
        final changes = _getChanges();
        if (changes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No changes detected.')),
            );
          }
          setState(() => _isSubmitting = false);
          return;
        }

        // Show confirmation dialog
        setState(() => _isSubmitting = false);
        final hasMembers = (widget.editRequest?.participants.length ?? 0) > 1;
        final confirmed = await _showEditConfirmationDialog(
          changes,
          hasMembers: hasMembers,
        );
        if (confirmed != true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Changes were not saved.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        if (!mounted) return;

        setState(() => _isSubmitting = true);

        // Update existing request — only send fields that actually changed
        // to minimize Firestore write operations
        final requestId = widget.editRequest.id;
        final orig = widget.editRequest;

        final newProductName = _productNameController.text.trim();
        final newDeal = _dealDescriptionController.text.trim();
        final newPrice = double.parse(_totalPriceController.text);
        final newStore = _storeNameController.text.trim();
        final newNotes = _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim();

        final success = await provider.updateRequest(
          requestId: requestId,
          productName: newProductName != orig.productName
              ? newProductName
              : null,
          productPhotoPath: _capturedImagePath,
          existingPhotoUrl: _capturedImagePath == null
              ? _existingPhotoUrl
              : null,
          dealDescription: newDeal != orig.dealDescription ? newDeal : null,
          totalPrice: newPrice != orig.totalPrice ? newPrice : null,
          totalQuantity: _totalQuantity != orig.totalQuantity
              ? _totalQuantity
              : null,
          partnersNeeded: _partnersNeeded != orig.partnersNeeded
              ? _partnersNeeded
              : null,
          category: _selectedCategory != orig.category
              ? _selectedCategory
              : null,
          storeName: newStore != orig.storeName ? newStore : null,
          latitude: _latitude ?? 3.1390,
          longitude: _longitude ?? 101.6869,
          expiryHours: _selectedExpiryHours,
          notes: newNotes,
        );

        if (mounted && success) {
          // Build system message content (sanitize long values)
          final changeLines = changes
              .map((c) {
                final oldVal = _truncate(c['old'] ?? '-', 40);
                final newVal = _truncate(c['new'] ?? '-', 40);
                return '• ${c['label']}: $oldVal → $newVal';
              })
              .join('\n');

          // Only send chat notification if there are other participants
          final hasMembers = (widget.editRequest?.participants.length ?? 0) > 1;
          if (hasMembers) {
            try {
              await ChatService().sendSystemMessage(
                chatRoomId: requestId,
                content: '📝 Host updated the request:\n$changeLines',
              );
              // Update lastMessage to a short summary (not full multi-line)
              await FirebaseFirestore.instance
                  .collection('chat_rooms')
                  .doc(requestId)
                  .update({
                    'lastMessage':
                        '📝 Host updated the request (${changes.length} changes)',
                    'lastMessageAt': FieldValue.serverTimestamp(),
                  });
            } catch (_) {
              // Chat room may not exist yet, ignore
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  hasMembers
                      ? 'Request updated & members notified!'
                      : 'Request updated successfully!',
                ),
                backgroundColor: AppColors.success,
              ),
            );
            Navigator.pop(context, true);
          }
        }
      } else {
        // Create new request
        final requestId = await provider.createRequest(
          productName: _productNameController.text.trim(),
          productPhotoPath: _capturedImagePath,
          dealDescription: _dealDescriptionController.text.trim(),
          totalPrice: double.parse(_totalPriceController.text),
          totalQuantity: _totalQuantity,
          partnersNeeded: _partnersNeeded,
          category: _selectedCategory,
          storeName: _storeNameController.text.trim(),
          latitude: _latitude ?? 3.1390,
          longitude: _longitude ?? 101.6869,
          expiryHours: _selectedExpiryHours,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );

        if (mounted && requestId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Request posted successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context);
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
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Truncate text for display in messages
  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  /// Build list of changes between original request and current form values
  List<Map<String, String>> _getChanges() {
    final req = widget.editRequest;
    if (req == null) return [];
    final changes = <Map<String, String>>[];

    final newName = _productNameController.text.trim();
    if (newName != (req.productName ?? '')) {
      changes.add({
        'label': 'Product',
        'old': req.productName ?? '-',
        'new': newName,
      });
    }

    final newDeal = _dealDescriptionController.text.trim();
    if (newDeal != (req.dealDescription ?? '')) {
      changes.add({
        'label': 'Deal',
        'old': req.dealDescription ?? '-',
        'new': newDeal,
      });
    }

    final newPrice = double.tryParse(_totalPriceController.text) ?? 0;
    if (newPrice != (req.totalPrice ?? 0)) {
      changes.add({
        'label': 'Price',
        'old': 'RM${req.totalPrice?.toStringAsFixed(2)}',
        'new': 'RM${newPrice.toStringAsFixed(2)}',
      });
    }

    if (_totalQuantity != (req.totalQuantity ?? 2)) {
      changes.add({
        'label': 'Quantity',
        'old': '${req.totalQuantity}',
        'new': '$_totalQuantity',
      });
    }

    if (_partnersNeeded != (req.partnersNeeded ?? 1)) {
      changes.add({
        'label': 'Partners Needed',
        'old': '${req.partnersNeeded}',
        'new': '$_partnersNeeded',
      });
    }

    final newLocation = _storeNameController.text.trim();
    if (newLocation != (req.storeName ?? '')) {
      changes.add({
        'label': 'Location',
        'old': req.storeName ?? '-',
        'new': newLocation,
      });
    }

    if (_selectedCategory != (req.category ?? 'groceries')) {
      changes.add({
        'label': 'Category',
        'old': RequestCategories.labels[req.category] ?? req.category ?? '-',
        'new': RequestCategories.labels[_selectedCategory] ?? _selectedCategory,
      });
    }

    final newNotes = _notesController.text.trim();
    if (newNotes != (req.notes ?? '')) {
      changes.add({
        'label': 'Notes',
        'old': req.notes ?? '-',
        'new': newNotes.isEmpty ? '-' : newNotes,
      });
    }

    if (_capturedImagePath != null) {
      changes.add({'label': 'Photo', 'old': 'Previous', 'new': 'Updated'});
    }

    return changes;
  }

  /// Show confirmation dialog with specific changes
  Future<bool?> _showEditConfirmationDialog(
    List<Map<String, String>> changes, {
    bool hasMembers = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Review Your Changes',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasMembers
                  ? 'The following changes will be saved and all members will be notified:'
                  : 'The following changes will be saved:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Column(
                  children: changes
                      .map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 6,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '${c['label']}: ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextSpan(
                                        text: c['old'],
                                        style: TextStyle(
                                          color: AppColors.error,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                      const TextSpan(text: ' → '),
                                      TextSpan(
                                        text: c['new'],
                                        style: TextStyle(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Discard'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 18),
            label: Text(hasMembers ? 'Save & Notify' : 'Save Changes'),
          ),
        ],
      ),
    );
  }

  /// Get current GPS location
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      final position = await _locationService.getCurrentPosition();

      if (position != null && mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });

        // Get address for display
        final address = await _locationService.getShortAddress(
          position.latitude,
          position.longitude,
        );

        if (mounted && address != null) {
          setState(() {
            _locationAddress = address;
            // Also update the store name controller for Firestore save
            _storeNameController.text = address;
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  /// Open map picker to select location
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          initialAddress: _locationAddress,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _latitude = result['latitude'] as double;
        _longitude = result['longitude'] as double;
        _locationAddress = result['address'] as String?;
        // Also update the store name controller so it gets saved to Firestore
        _storeNameController.text = _locationAddress ?? '';
      });
    }
  }
}
