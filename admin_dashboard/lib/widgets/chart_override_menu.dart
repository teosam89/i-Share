import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';

/// Represents a chart's date-range setting. Either "inherit master" or a local
/// window (int days, or null=all time).
class OverrideValue {
  final bool inherit;
  final int? days;

  const OverrideValue.inherit()
      : inherit = true,
        days = null;
  const OverrideValue.window(this.days) : inherit = false;

  @override
  bool operator ==(Object other) =>
      other is OverrideValue && other.inherit == inherit && other.days == days;

  @override
  int get hashCode => Object.hash(inherit, days);
}

/// Small "≡" icon button in a chart card's header. Opens a popup that lets the
/// admin override the master date filter for just this card.
class ChartOverrideMenu extends StatelessWidget {
  final OverrideValue current;
  final int? masterDays;
  final ValueChanged<OverrideValue> onSelected;

  const ChartOverrideMenu({
    super.key,
    required this.current,
    required this.masterDays,
    required this.onSelected,
  });

  static String _label(int? days) =>
      days == null ? 'All time' : 'Last $days days';

  @override
  Widget build(BuildContext context) {
    final hasOverride = !current.inherit;
    return Tooltip(
      message: hasOverride
          ? 'Overriding: ${_label(current.days)}'
          : 'Override date range',
      child: PopupMenuButton<OverrideValue>(
        tooltip: '',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 4),
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: kN300),
        ),
        color: Colors.white,
        elevation: 4,
        itemBuilder: (_) => [
          PopupMenuItem(
            value: const OverrideValue.inherit(),
            height: 36,
            child: _buildItem(
              icon: Icons.link,
              label: 'Inherit master (${_label(masterDays)})',
              selected: current.inherit,
            ),
          ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: const OverrideValue.window(7),
            height: 36,
            child: _buildItem(
              icon: Icons.calendar_view_week_outlined,
              label: 'Last 7 days',
              selected: !current.inherit && current.days == 7,
            ),
          ),
          PopupMenuItem(
            value: const OverrideValue.window(30),
            height: 36,
            child: _buildItem(
              icon: Icons.calendar_view_month_outlined,
              label: 'Last 30 days',
              selected: !current.inherit && current.days == 30,
            ),
          ),
          PopupMenuItem(
            value: const OverrideValue.window(90),
            height: 36,
            child: _buildItem(
              icon: Icons.calendar_month_outlined,
              label: 'Last 90 days',
              selected: !current.inherit && current.days == 90,
            ),
          ),
          PopupMenuItem(
            value: const OverrideValue.window(null),
            height: 36,
            child: _buildItem(
              icon: Icons.all_inclusive,
              label: 'All time',
              selected: !current.inherit && current.days == null,
            ),
          ),
        ],
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: hasOverride ? kBlue.withValues(alpha: 0.1) : kN100,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: kN300),
          ),
          child: Icon(
            hasOverride ? Icons.filter_alt : Icons.filter_alt_outlined,
            size: 14,
            color: hasOverride ? kBlue : kN500,
          ),
        ),
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    return Row(
      children: [
        Icon(icon, size: 15, color: selected ? kBlue : kN500),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: selected ? kBlue : kN700,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        if (selected) ...[
          const Spacer(),
          const Icon(Icons.check, size: 13, color: kBlue),
        ],
      ],
    );
  }
}
