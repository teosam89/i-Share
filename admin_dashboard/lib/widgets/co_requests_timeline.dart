import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/dashboard_theme.dart';
import '../services/analytics_service.dart';
import 'chart_override_menu.dart';

class CoRequestsTimeline extends StatelessWidget {
  final List<DayPoint> data;
  final int? days;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const CoRequestsTimeline({
    super.key,
    required this.data,
    required this.days,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  @override
  Widget build(BuildContext context) {
    final total = data.fold<int>(0, (a, p) => a + p.count);
    final peak = data.isEmpty
        ? 0
        : data.map((d) => d.count).reduce((a, b) => a > b ? a : b);

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
                      Text('CO-REQUESTS TIMELINE', style: kLabelCaps),
                      const SizedBox(height: 4),
                      Text(
                        '$total requests · peak $peak / day',
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
                    color: kPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    days == null ? '30 days' : '$days days',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: kPurple,
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
            const SizedBox(height: 16),
            SizedBox(height: 180, child: LineChart(_buildChart())),
          ],
        ),
      ),
    );
  }

  LineChartData _buildChart() {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.count.toDouble()))
        .toList();

    final maxVal = data.isEmpty
        ? 0.0
        : data.map((d) => d.count.toDouble()).reduce((a, b) => a > b ? a : b);
    final maxY = (maxVal * 1.3 + 1).clamp(4.0, double.infinity);
    final interval = (maxY / 4).ceilToDouble().clamp(1.0, double.infinity);

    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => kN900,
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.x.toInt();
            final label = idx < data.length
                ? DateFormat('d MMM').format(data[idx].date)
                : '';
            return LineTooltipItem(
              '$label\n',
              GoogleFonts.inter(fontSize: 11, color: kN400),
              children: [
                TextSpan(
                  text: '${s.y.toInt()} requests',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.25,
          color: kPurple,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                kPurple.withValues(alpha: 0.18),
                kPurple.withValues(alpha: 0.01),
              ],
            ),
          ),
        ),
      ],
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: interval,
            getTitlesWidget: (value, meta) {
              if (value == meta.max) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  value.toInt().toString(),
                  style: GoogleFonts.inter(fontSize: 10, color: kN400),
                  textAlign: TextAlign.right,
                ),
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 6,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= data.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  DateFormat('d MMM').format(data[idx].date),
                  style: GoogleFonts.inter(fontSize: 10, color: kN500),
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
      minX: 0,
      maxX: (data.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
    );
  }
}
