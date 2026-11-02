import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'chart_override_menu.dart';

class ScoreDistribution extends StatelessWidget {
  final Map<String, int> data;
  final OverrideValue dateOverride;
  final int? masterDays;
  final ValueChanged<OverrideValue> onOverrideChange;

  const ScoreDistribution({
    super.key,
    required this.data,
    required this.dateOverride,
    required this.masterDays,
    required this.onOverrideChange,
  });

  static const _tiers = <String, ({Color color, String range, IconData icon})>{
    'User':    (color: kN500,  range: '0 – 299',   icon: Icons.person_outline),
    'Trusted': (color: kBlue,  range: '300 – 699', icon: Icons.verified_user_outlined),
    'Elite':   (color: kAmber, range: '700+',      icon: Icons.workspace_premium_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0, (a, b) => a + b);

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
                      Text('SCORE DISTRIBUTION', style: kLabelCaps),
                      const SizedBox(height: 4),
                      Text(
                        '$total users across 3 credibility tiers',
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
                    color: kBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Tiers',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: kBlue,
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
            const SizedBox(height: 20),
            _buildStackedBar(total),
            const SizedBox(height: 14),
            ..._tiers.entries.map((entry) {
              final count = data[entry.key] ?? 0;
              final pct = total == 0 ? 0 : (count / total * 100).round();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: entry.value.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        entry.value.icon,
                        size: 16,
                        color: entry.value.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kN900,
                            ),
                          ),
                          Text(
                            'Score ${entry.value.range}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: kN500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$count',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: entry.value.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$pct%',
                        style: GoogleFonts.inter(fontSize: 11, color: kN400),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStackedBar(int total) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 14,
        color: kN100,
        child: Row(
          children: _tiers.entries.map((entry) {
            final count = data[entry.key] ?? 0;
            final flex = total == 0 ? 0 : count;
            if (flex == 0) return const SizedBox.shrink();
            return Expanded(
              flex: flex,
              child: Container(color: entry.value.color),
            );
          }).toList(),
        ),
      ),
    );
  }
}
