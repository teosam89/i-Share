import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';

enum KpiDisplay { number, line, donut, bar }

const kpiDisplayLabels = <KpiDisplay, String>{
  KpiDisplay.number: 'Number',
  KpiDisplay.line: 'Line',
  KpiDisplay.donut: 'Donut',
  KpiDisplay.bar: 'Bar',
};

const kpiDisplayIcons = <KpiDisplay, IconData>{
  KpiDisplay.number: Icons.tag,
  KpiDisplay.line: Icons.show_chart,
  KpiDisplay.donut: Icons.donut_large,
  KpiDisplay.bar: Icons.bar_chart,
};

class KpiCard extends StatelessWidget {
  final String kpiId;
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;

  /// Which display modes this KPI supports (always includes Number).
  final List<KpiDisplay> availableDisplays;
  final KpiDisplay display;
  final ValueChanged<KpiDisplay> onDisplayChange;

  /// Data inputs for non-Number displays. Provide what's applicable.
  final List<double>? lineData; // for KpiDisplay.line
  final Map<String, ({int count, Color color})>? donutSegments; // for donut
  final double? gaugePercent; // 0–1, for donut-as-gauge
  final Map<String, ({int count, Color color})>? barData; // for bar

  const KpiCard({
    super.key,
    required this.kpiId,
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.availableDisplays,
    required this.display,
    required this.onDisplayChange,
    this.lineData,
    this.donutSegments,
    this.gaugePercent,
    this.barData,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                _buildDisplaySwitcher(),
              ],
            ),
            const SizedBox(height: 14),
            // Body adapts to display type
            SizedBox(
              height: 96,
              child: _buildBody(),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: kN700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: 12, color: kN500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisplaySwitcher() {
    if (availableDisplays.length <= 1) return const SizedBox();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: availableDisplays.map((d) {
        final selected = d == display;
        return Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Tooltip(
            message: kpiDisplayLabels[d] ?? '',
            child: Material(
              color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => onDisplayChange(d),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  child: Icon(
                    kpiDisplayIcons[d],
                    size: 13,
                    color: selected ? color : kN400,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody() {
    switch (display) {
      case KpiDisplay.number:
        return _buildNumber();
      case KpiDisplay.line:
        return _buildLine();
      case KpiDisplay.donut:
        return _buildDonut();
      case KpiDisplay.bar:
        return _buildBar();
    }
  }

  Widget _buildNumber() {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: kN900,
          letterSpacing: -1.0,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildLine() {
    final data = lineData ?? [];
    if (data.isEmpty) return _emptyState('No data');
    final spots = data
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final maxY = data.reduce((a, b) => a > b ? a : b);
    final adjMax = (maxY * 1.2).clamp(1.0, double.infinity);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: kN900,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: 0.25),
                        color.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ],
              titlesData: const FlTitlesData(show: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: adjMax,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDonut() {
    // Two modes: gauge (single percent) OR segmented donut
    if (donutSegments != null && donutSegments!.isNotEmpty) {
      final total =
          donutSegments!.values.fold<int>(0, (a, s) => a + s.count);
      if (total == 0) return _emptyState('No data');
      final sections = donutSegments!.entries.map((e) {
        return PieChartSectionData(
          value: e.value.count.toDouble(),
          color: e.value.color,
          radius: 14,
          showTitle: false,
        );
      }).toList();
      return Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(PieChartData(
                  sections: sections,
                  centerSpaceRadius: 22,
                  sectionsSpace: 2,
                )),
                Text(
                  '$total',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kN900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: donutSegments!.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: e.value.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          e.key,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: kN700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${e.value.count}',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: kN900,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    // Gauge mode (percent)
    final pct = gaugePercent ?? 0;
    return Center(
      child: SizedBox(
        width: 90,
        height: 90,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(PieChartData(
              sections: [
                PieChartSectionData(
                  value: pct.clamp(0.001, 1.0),
                  color: color,
                  radius: 12,
                  showTitle: false,
                ),
                PieChartSectionData(
                  value: (1 - pct).clamp(0.001, 1.0),
                  color: kN100,
                  radius: 12,
                  showTitle: false,
                ),
              ],
              centerSpaceRadius: 28,
              sectionsSpace: 0,
              startDegreeOffset: -90,
            )),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kN900,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar() {
    final data = barData ?? {};
    if (data.isEmpty) return _emptyState('No data');
    final maxCount =
        data.values.map((e) => e.count).reduce((a, b) => a > b ? a : b);

    // Compact 2-column grid when >4 entries — fits 8 in the body height.
    if (data.length > 4) {
      return _buildBarGrid(data, maxCount);
    }

    // Original 3-row layout with sidekick big number (used by Total Users tiers)
    final rows = data.entries.map((e) {
      final ratio = maxCount == 0 ? 0.0 : e.value.count / maxCount;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              child: Text(
                e.key,
                style: GoogleFonts.inter(fontSize: 10.5, color: kN700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  children: [
                    Container(height: 8, color: kN100),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(height: 8, color: e.value.color),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 22,
              child: Text(
                '${e.value.count}',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: kN900,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }).toList();

    return Row(
      children: [
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: kN900,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: rows,
          ),
        ),
      ],
    );
  }

  /// 2-column grid layout for bar mode when there are >4 entries.
  /// Column-major fill: first half goes down the left column, second half
  /// goes down the right column (so reading order matches the source data).
  Widget _buildBarGrid(
    Map<String, ({int count, Color color})> data,
    int maxCount,
  ) {
    final entries = data.entries.toList();
    final rowCount = (entries.length / 2).ceil();
    final leftCol = entries.sublist(0, rowCount);
    final rightCol = entries.length > rowCount
        ? entries.sublist(rowCount)
        : <MapEntry<String, ({int count, Color color})>>[];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(rowCount, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            children: [
              Expanded(child: _buildBarCell(leftCol[i], maxCount)),
              const SizedBox(width: 10),
              Expanded(
                child: i < rightCol.length
                    ? _buildBarCell(rightCol[i], maxCount)
                    : const SizedBox(),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildBarCell(
    MapEntry<String, ({int count, Color color})> e,
    int maxCount,
  ) {
    final ratio = maxCount == 0 ? 0.0 : e.value.count / maxCount;
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: e.value.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 46,
          child: Text(
            e.key,
            style: GoogleFonts.inter(fontSize: 9.5, color: kN700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(height: 5, color: kN100),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(height: 5, color: e.value.color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 12,
          child: Text(
            '${e.value.count}',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: kN900,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Text(
        msg,
        style: GoogleFonts.inter(fontSize: 11, color: kN400),
      ),
    );
  }
}
