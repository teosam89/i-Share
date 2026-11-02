import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';

class PillTabItem {
  final String label;
  final IconData icon;
  final int? count;

  const PillTabItem({
    required this.label,
    required this.icon,
    this.count,
  });
}

class PillTabs extends StatelessWidget {
  final List<PillTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const PillTabs({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kN100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kN300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.asMap().entries.map((e) {
          final selected = e.key == selectedIndex;
          return Material(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            elevation: selected ? 1 : 0,
            shadowColor: Colors.black.withValues(alpha: 0.08),
            child: InkWell(
              onTap: () => onChanged(e.key),
              borderRadius: BorderRadius.circular(7),
              hoverColor: Colors.white.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      e.value.icon,
                      size: 15,
                      color: selected ? kBlue : kN500,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      e.value.label,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? kN900 : kN500,
                      ),
                    ),
                    if (e.value.count != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? kBlue.withValues(alpha: 0.12)
                              : kN300.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${e.value.count}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: selected ? kBlue : kN500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
