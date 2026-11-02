import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/dashboard_theme.dart';
import '../services/analytics_service.dart';
import 'chart_override_menu.dart';

class CoRequestMap extends StatefulWidget {
  final List<MapPoint> points;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const CoRequestMap({
    super.key,
    required this.points,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  @override
  State<CoRequestMap> createState() => _CoRequestMapState();
}

class _CoRequestMapState extends State<CoRequestMap> {
  String? _activeCategory;
  Map<String, BitmapDescriptor>? _icons;

  // Centered on West Malaysia (between KL and Kuantan) at a zoom that fits
  // Penang in the north to Johor Bahru in the south.
  static const _westMalaysiaCenter = LatLng(4.0, 102.0);

  // Stable per-category color palette — also drives the legend chips and
  // the colors painted into each marker bitmap below.
  static const _categoryColors = <String, Color>{
    'groceries': Color(0xFF3B82F6),
    'fresh': kGreen,
    'snacks': Color(0xFFF97316),
    'household': kPurple,
    'personal': Color(0xFFEC4899),
    'baby_pets': Color(0xFFD946EF),
    'electronics': kBlue,
    'others': Color(0xFFCA8A04),
  };

  static const _categoryLabels = <String, String>{
    'groceries': 'Groceries',
    'fresh': 'Fresh Foods',
    'snacks': 'Snacks & Drinks',
    'household': 'Household',
    'personal': 'Personal Care',
    'baby_pets': 'Baby & Pets',
    'electronics': 'Electronics',
    'others': 'Others',
  };

  @override
  void initState() {
    super.initState();
    _buildIcons();
  }

  Future<void> _buildIcons() async {
    final out = <String, BitmapDescriptor>{};
    for (final entry in _categoryColors.entries) {
      out[entry.key] = await _drawPinMarker(entry.value);
    }
    if (mounted) setState(() => _icons = out);
  }

  // Custom-drawn pin marker — circle with white border + soft drop shadow.
  // Rendered at 2x device pixels for crispness on retina displays.
  Future<BitmapDescriptor> _drawPinMarker(Color color) async {
    const size = 72.0;
    const radius = 22.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final center = const Offset(size / 2, size / 2);

    // Drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center.translate(0, 2), radius, shadowPaint);

    // White ring (outer)
    final ringPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius, ringPaint);

    // Colored fill (inner)
    final fillPaint = Paint()..color = color;
    canvas.drawCircle(center, radius - 4, fillPaint);

    // Small white dot in the centre to read like a target
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawCircle(center, 5, dotPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _activeCategory == null
        ? widget.points
        : widget.points.where((p) => p.category == _activeCategory).toList();

    final markers = (_icons == null)
        ? <Marker>{}
        : filtered.asMap().entries.map((e) {
            final p = e.value;
            final icon = _icons![p.category] ?? _icons!['others']!;
            final categoryLabel = _categoryLabels[p.category] ?? p.category;
            final statusLabel = p.status.isEmpty
                ? ''
                : p.status[0].toUpperCase() + p.status.substring(1);
            return Marker(
              markerId: MarkerId('m${e.key}'),
              position: LatLng(p.lat, p.lng),
              icon: icon,
              infoWindow: InfoWindow(
                title: p.productName.isEmpty ? categoryLabel : p.productName,
                snippet:
                    '$categoryLabel  •  $statusLabel  •  ${p.storeName}',
              ),
            );
          }).toSet();

    final counts = <String, int>{};
    for (final p in widget.points) {
      counts[p.category] = (counts[p.category] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CO-REQUEST LOCATIONS', style: kLabelCaps),
                      const SizedBox(height: 4),
                      Text(
                        _activeCategory == null
                            ? '${widget.points.length} requests across Klang Valley'
                            : '${filtered.length} ${_categoryLabels[_activeCategory] ?? ''} requests',
                        style: kCardBody,
                      ),
                    ],
                  ),
                ),
                if (_activeCategory != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _activeCategory = null),
                    icon: const Icon(Icons.clear, size: 14),
                    label: Text(
                      'Clear filter',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: kN700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                    ),
                  ),
                const SizedBox(width: 8),
                ChartOverrideMenu(
                  current: widget.dateOverride,
                  masterDays: widget.masterDays,
                  onSelected: widget.onOverrideChange,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categoryLabels.keys.map((key) {
                final color = _categoryColors[key] ?? kN500;
                final label = _categoryLabels[key] ?? key;
                final count = counts[key] ?? 0;
                final selected = _activeCategory == key;
                return Material(
                  color: selected ? color : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () => setState(
                      () => _activeCategory = selected ? null : key,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? color
                              : color.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: selected ? Colors.white : color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: selected ? Colors.white : color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$count',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: selected ? Colors.white : color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 440,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: _westMalaysiaCenter,
                        zoom: 6.8,
                      ),
                      markers: markers,
                      zoomControlsEnabled: true,
                      mapToolbarEnabled: false,
                      myLocationButtonEnabled: false,
                    ),
                    if (_icons == null)
                      Container(
                        color: kN100.withValues(alpha: 0.4),
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(strokeWidth: 2),
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
}
