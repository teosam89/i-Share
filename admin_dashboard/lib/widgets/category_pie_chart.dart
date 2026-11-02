import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'chart_override_menu.dart';

class CategoryPieChart extends StatelessWidget {
  final Map<String, int> data;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const CategoryPieChart({
    super.key,
    required this.data,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  // Fixed 8-category order — matches RequestCategories in the main app.
  static const _ordered = <String, ({String label, Color color})>{
    'groceries': (label: 'Groceries', color: Color(0xFF3B82F6)),
    'fresh': (label: 'Fresh Foods', color: kGreen),
    'snacks': (label: 'Snacks & Drinks', color: Color(0xFFF97316)),
    'household': (label: 'Household', color: kPurple),
    'personal': (label: 'Personal Care', color: Color(0xFFEC4899)),
    'baby_pets': (label: 'Baby & Pets', color: Color(0xFFD946EF)),
    'electronics': (label: 'Electronics', color: kBlue),
    'others': (label: 'Others', color: Color(0xFFCA8A04)),
  };

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (a, b) => a + b);

    // Only show categories with non-zero count
    final entries = _ordered.entries
        .where((e) => (data[e.key] ?? 0) > 0)
        .toList();

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
                      Text('CATEGORY BREAKDOWN', style: kLabelCaps),
                      const SizedBox(height: 4),
                      Text('$total co-requests total', style: kCardBody),
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
                  child: PieChart(
                    PieChartData(
                      sections: _buildSections(entries, total),
                      centerSpaceRadius: 42,
                      sectionsSpace: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: _buildLegend(entries, total)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildSections(
    List<MapEntry<String, ({String label, Color color})>> entries,
    int total,
  ) {
    return entries.map((e) {
      final count = data[e.key] ?? 0;
      final pct = total == 0 ? 0.0 : count / total * 100;
      return PieChartSectionData(
        value: count.toDouble(),
        color: e.value.color,
        title: pct >= 6 ? '${pct.toStringAsFixed(0)}%' : '',
        radius: 30,
        titleStyle: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildLegend(
    List<MapEntry<String, ({String label, Color color})>> entries,
    int total,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: entries.map((e) {
        final count = data[e.key] ?? 0;
        final pct = total == 0 ? 0 : (count / total * 100).round();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: e.value.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.value.label,
                  style: GoogleFonts.inter(fontSize: 11, color: kN700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: kN900,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 28,
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
