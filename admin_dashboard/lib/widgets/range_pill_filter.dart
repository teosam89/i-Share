import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';

/// Segmented pill control for date-range filtering. Used as the master filter
/// in the top bar and inside chart override menus.
class RangePillFilter extends StatelessWidget {
  final int? value; // null = all time
  final ValueChanged<int?> onChanged;
  final bool dense;

  const RangePillFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  static const _options = <({String label, int? days})>[
    (label: '7d', days: 7),
    (label: '30d', days: 30),
    (label: '90d', days: 90),
    (label: 'All', days: null),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kN100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kN300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _options.map((opt) {
          final selected = opt.days == value;
          return Material(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            elevation: selected ? 1 : 0,
            shadowColor: Colors.black.withValues(alpha: 0.06),
            child: InkWell(
              onTap: () => onChanged(opt.days),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 9 : 12,
                  vertical: dense ? 4 : 5,
                ),
                child: Text(
                  opt.label,
                  style: GoogleFonts.inter(
                    fontSize: dense ? 11 : 12,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? kN900 : kN500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Human-readable label for a window. e.g. `7 → "last 7 days"`, `null → "all time"`.
String windowLabel(int? days) =>
    days == null ? 'all time' : 'last $days days';
