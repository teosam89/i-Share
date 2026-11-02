import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/dashboard_theme.dart';

String fmtDate(dynamic ts) {
  if (ts == null) return '-';
  if (ts is Timestamp) return DateFormat('dd MMM yy HH:mm').format(ts.toDate());
  return ts.toString();
}

String fmtStr(dynamic v) => v?.toString() ?? '-';

String fmtNum(dynamic v, {int decimals = 0}) {
  if (v == null) return '-';
  if (v is num) {
    return decimals > 0 ? v.toStringAsFixed(decimals) : v.toInt().toString();
  }
  return v.toString();
}

int compareValues(dynamic a, dynamic b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is Timestamp && b is Timestamp) return a.compareTo(b);
  return a.toString().compareTo(b.toString());
}

void showJsonDialog(BuildContext context, Map<String, dynamic> row) {
  final json = const JsonEncoder.withIndent('  ').convert(_jsonify(row));
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 540),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Document Inspector',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: kN900,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                  color: kN500,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kN100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kN300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: kN900,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

dynamic _jsonify(dynamic value) {
  if (value is Timestamp) return value.toDate().toIso8601String();
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), _jsonify(v)));
  }
  if (value is List) return value.map(_jsonify).toList();
  return value;
}

/// Styled search input matching the dashboard design system.
Widget buildSearchField({
  required String hint,
  required ValueChanged<String> onChanged,
}) {
  return SizedBox(
    width: 320,
    height: 38,
    child: TextField(
      onChanged: onChanged,
      style: GoogleFonts.inter(fontSize: 13, color: kN900),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: kN400),
        prefixIcon: const Icon(Icons.search, size: 16, color: kN500),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kN300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: kBlue.withValues(alpha: 0.5), width: 1.5),
        ),
      ),
    ),
  );
}

/// Pill-style filter chip used above tables.
Widget buildFilterChip({
  required String label,
  required bool selected,
  required VoidCallback onTap,
  Color? accent,
}) {
  final color = accent ?? kBlue;
  return Material(
    color: selected ? color : Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      hoverColor: color.withValues(alpha: 0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : kN300,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : kN700,
          ),
        ),
      ),
    ),
  );
}

/// Wraps a DataTable in the dashboard's standard styled card.
Widget buildTableCard({required Widget child}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kN300),
    ),
    clipBehavior: Clip.hardEdge,
    child: Theme(
      data: ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        textTheme: GoogleFonts.interTextTheme(),
        dividerColor: kN100,
        dataTableTheme: DataTableThemeData(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFFAFBFC)),
          headingTextStyle: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: kN500,
            letterSpacing: 0.4,
          ),
          dataTextStyle: GoogleFonts.inter(
            fontSize: 13,
            color: kN900,
          ),
          dividerThickness: 1,
          horizontalMargin: 18,
          columnSpacing: 28,
          headingRowHeight: 44,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 48,
        ),
      ),
      child: child,
    ),
  );
}

WidgetStateProperty<Color?> alternatingRowColor(int index) {
  return WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.hovered)) {
      return kBlue.withValues(alpha: 0.04);
    }
    return index.isEven ? Colors.white : const Color(0xFFFAFBFC);
  });
}

/// Status badge widget shared across tables.
Widget statusBadge(String value, {Color? color}) {
  final c = color ?? _statusColor(value);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.withValues(alpha: 0.25)),
    ),
    child: Text(
      value,
      style: GoogleFonts.inter(
        fontSize: 11,
        color: c,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

Color _statusColor(String status) {
  switch (status) {
    case 'active':
    case 'waiting':
      return kGreen;
    case 'completed':
    case 'matched':
      return kBlue;
    case 'expired':
    case 'closed':
      return kCyan;
    case 'cancelled':
      return kRed;
    default:
      return kN500;
  }
}
