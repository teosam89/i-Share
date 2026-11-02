import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'chart_override_menu.dart';

class StatusDonut extends StatelessWidget {
  final Map<String, int> data;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const StatusDonut({
    super.key,
    required this.data,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  static const _ordered = <String, ({String label, Color color})>{
    'active': (label: 'Active', color: kGreen),
    'completed': (label: 'Completed', color: kBlue),
    'expired': (label: 'Expired', color: kCyan),
    'cancelled': (label: 'Cancelled', color: kRed),
  };

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (a, b) => a + b);
    final completed = data['completed'] ?? 0;
    final completionRate =
        total == 0 ? 0.0 : (completed / total * 100);

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
                      Text('REQUEST STATUS', style: kLabelCaps),
                      const SizedBox(height: 4),
                      Text(
                        '$total total · ${completionRate.toStringAsFixed(1)}% completed',
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
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  height: 150,
                  width: 150,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: _buildSections(total),
                          centerSpaceRadius: 42,
                          sectionsSpace: 2,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: kN900,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'requests',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: kN500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(child: _buildLegend(total)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildSections(int total) {
    return _ordered.entries.where((e) => (data[e.key] ?? 0) > 0).map((e) {
      final count = data[e.key] ?? 0;
      final pct = total == 0 ? 0.0 : count / total * 100;
      return PieChartSectionData(
        value: count.toDouble(),
        color: e.value.color,
        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
        radius: 30,
        titleStyle: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildLegend(int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _ordered.entries.map((e) {
        final count = data[e.key] ?? 0;
        final pct = total == 0 ? 0 : (count / total * 100).round();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: e.value.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.value.label,
                  style: GoogleFonts.inter(fontSize: 12, color: kN700),
                ),
              ),
              Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kN900,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 32,
                child: Text(
                  '$pct%',
                  style: GoogleFonts.inter(fontSize: 11, color: kN400),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
