import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'chart_override_menu.dart';

class CredibilityBarChart extends StatelessWidget {
  final Map<String, int> data;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const CredibilityBarChart({
    super.key,
    required this.data,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  static const _orderedKeys = [
    'completeDeal',
    'rating5Star',
    'rating4Star',
    'rating3Below',
    'cancelWithParticipants',
    'cancelNoParticipants',
    'leaveRequest',
    'expiredWithParticipants',
    'verifyEmail',
    'verifyPhone',
  ];

  // Two-line labels (line1\nline2) — keeps each cell narrow yet readable
  static const _shortLabels = {
    'completeDeal': 'Deal\nDone',
    'rating5Star': '5★\nRating',
    'rating4Star': '4★\nRating',
    'rating3Below': '≤3★\nRating',
    'cancelWithParticipants': 'Cancel\n+Users',
    'cancelNoParticipants': 'Cancel\nEmpty',
    'leaveRequest': 'Leave\nRequest',
    'expiredWithParticipants': 'Expired\n+Users',
    'verifyEmail': 'Verify\nEmail',
    'verifyPhone': 'Verify\nPhone',
  };

  static const _fullLabels = {
    'completeDeal': 'Complete Deal',
    'rating5Star': '5-Star Rating',
    'rating4Star': '4-Star Rating',
    'rating3Below': '≤3-Star Rating',
    'cancelWithParticipants': 'Cancel (with participants)',
    'cancelNoParticipants': 'Cancel (no participants)',
    'leaveRequest': 'Leave Request',
    'expiredWithParticipants': 'Expired (with participants)',
    'verifyEmail': 'Email Verified',
    'verifyPhone': 'Phone Verified',
  };

  static const _barColors = [
    kGreen,  // completeDeal
    kBlue,   // rating5Star
    kBlue,   // rating4Star
    kAmber,  // rating3Below
    kRed,    // cancelWithParticipants
    kN400,   // cancelNoParticipants
    kAmber,  // leaveRequest
    kRed,    // expiredWithParticipants
    kGreen,  // verifyEmail
    kGreen,  // verifyPhone
  ];

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (a, b) => a + b);
    final values =
        _orderedKeys.map((k) => (data[k] ?? 0).toDouble()).toList();
    final maxVal =
        values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final maxY = (maxVal * 1.35 + 1).clamp(5.0, double.infinity);
    final interval = (maxY / 4).ceilToDouble().clamp(1.0, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CREDIBILITY EVENTS', style: kLabelCaps),
                    const SizedBox(height: 4),
                    Text(
                      '$total total events across ${_orderedKeys.length} types',
                      style: kCardBody,
                    ),
                  ],
                ),
                const Spacer(),
                _buildLegendChip('Positive', kGreen),
                const SizedBox(width: 8),
                _buildLegendChip('Neutral', kBlue),
                const SizedBox(width: 8),
                _buildLegendChip('Warning', kAmber),
                const SizedBox(width: 8),
                _buildLegendChip('Negative', kRed),
                const SizedBox(width: 12),
                ChartOverrideMenu(
                  current: dateOverride,
                  masterDays: masterDays,
                  onSelected: onOverrideChange,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barGroups: _orderedKeys.asMap().entries.map((e) {
                    final val = values[e.key];
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: val,
                          color: _barColors[e.key],
                          width: 22,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY,
                            color: kN100,
                          ),
                        ),
                      ],
                      showingTooltipIndicators: val > 0 ? [] : [],
                    );
                  }).toList(),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => kN900,
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      getTooltipItem: (group, _, rod, _) {
                        final key = _orderedKeys[group.x];
                        return BarTooltipItem(
                          '${_fullLabels[key]}\n',
                          GoogleFonts.inter(
                            color: kN400,
                            fontSize: 11,
                          ),
                          children: [
                            TextSpan(
                              text: '${rod.toY.toInt()} events',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              value.toInt().toString(),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: kN400,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= values.length) {
                            return const SizedBox();
                          }
                          final v = values[idx].toInt();
                          if (v == 0) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '$v',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _barColors[idx],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _orderedKeys.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _shortLabels[_orderedKeys[idx]] ?? '',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: kN500,
                                height: 1.2,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: kN300, strokeWidth: 0.8),
                  ),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, color: kN500),
        ),
      ],
    );
  }
}
