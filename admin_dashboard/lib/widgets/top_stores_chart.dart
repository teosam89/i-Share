import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import '../services/analytics_service.dart';
import 'chart_override_menu.dart';

class TopStoresChart extends StatelessWidget {
  final List<StoreCount> data;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const TopStoresChart({
    super.key,
    required this.data,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = data.isEmpty
        ? 1
        : data.map((s) => s.count).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TOP STORES', style: kLabelCaps),
                      const SizedBox(height: 4),
                      Text(
                        'Most-used locations for co-requests',
                        style: kCardBody,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kAmber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Top 5',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: kAmber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ChartOverrideMenu(
                  current: dateOverride,
                  masterDays: masterDays,
                  onSelected: onOverrideChange,
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (data.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No store data',
                    style: GoogleFonts.inter(fontSize: 13, color: kN400),
                  ),
                ),
              )
            else
              ..._buildBars(maxCount),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBars(int maxCount) {
    return data.asMap().entries.map((e) {
      final rank = e.key + 1;
      final store = e.value;
      final ratio = maxCount == 0 ? 0.0 : store.count / maxCount;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '#$rank',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kN400,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          store.name,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: kN700,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${store.count}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kN900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 8, color: kN100),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  kAmber.withValues(alpha: 0.7),
                                  kAmber,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
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
        ),
      );
    }).toList();
  }
}
