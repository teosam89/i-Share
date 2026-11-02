import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import '../services/analytics_service.dart';
import 'chart_override_menu.dart';

class UsersLineChart extends StatelessWidget {
  final List<UserMonthPoint> data;
  final int totalUsers;
  final int? days;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const UsersLineChart({
    super.key,
    required this.data,
    required this.totalUsers,
    required this.days,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  String get _windowLabel {
    if (days == null) return '6 months';
    if (days! <= 14) return 'Last $days days';
    if (days! <= 90) return 'Last $days days';
    return 'Last ${(days! / 30).round()} months';
  }

  @override
  Widget build(BuildContext context) {
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
                      Text('USER GROWTH', style: kLabelCaps),
                      const SizedBox(height: 8),
                      Text(
                        '$totalUsers',
                        style: GoogleFonts.inter(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: kBlue,
                          letterSpacing: -1.5,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'New registrations — $_windowLabel',
                        style: kCardBody,
                      ),
                    ],
                  ),
                ),
                ChartOverrideMenu(
                  current: dateOverride,
                  masterDays: masterDays,
                  onSelected: onOverrideChange,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 160,
              child: data.isEmpty
                  ? Center(child: Text('No data', style: kCardBody))
                  : LineChart(_buildData()),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildData() {
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.count.toDouble()))
        .toList();

    final maxVal = data
        .map((d) => d.count.toDouble())
        .reduce((a, b) => a > b ? a : b);
    final maxY = (maxVal * 1.3 + 2).clamp(5.0, double.infinity);
    final interval = (maxY / 4).ceilToDouble().clamp(1.0, double.infinity);

    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => kN900,
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.x.toInt();
            final label = idx < data.length ? data[idx].label : '';
            return LineTooltipItem(
              '$label\n',
              GoogleFonts.inter(fontSize: 11, color: kN400),
              children: [
                TextSpan(
                  text: '${s.y.toInt()} users',
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
          color: kBlue,
          barWidth: 2.5,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
              radius: 3,
              color: Colors.white,
              strokeWidth: 2,
              strokeColor: kBlue,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                kBlue.withValues(alpha: 0.15),
                kBlue.withValues(alpha: 0.01),
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
            interval: data.length > 8 ? (data.length / 6).ceilToDouble() : 1,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= data.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  data[idx].label,
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
      maxX: (data.length - 1).toDouble().clamp(0, double.infinity),
      minY: 0,
      maxY: maxY,
    );
  }
}
