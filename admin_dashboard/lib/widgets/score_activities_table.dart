import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'table_utils.dart';

class ScoreActivitiesTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const ScoreActivitiesTable({super.key, required this.rows});

  @override
  State<ScoreActivitiesTable> createState() => _ScoreActivitiesTableState();
}

class _ScoreActivitiesTableState extends State<ScoreActivitiesTable> {
  String _query = '';
  String _polarity = 'all'; // all / positive / negative
  int _sortCol = 3;
  bool _sortAsc = false;

  static const _fields = ['__userId', 'event', 'points', 'createdAt'];

  List<Map<String, dynamic>> get _filtered {
    var rows = widget.rows.where((r) {
      final pts = (r['points'] as num?) ?? 0;
      if (_polarity == 'positive' && pts <= 0) return false;
      if (_polarity == 'negative' && pts >= 0) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return fmtStr(r['__userId']).toLowerCase().contains(q) ||
          fmtStr(r['event']).toLowerCase().contains(q);
    }).toList();
    rows.sort((a, b) {
      final field = _fields[_sortCol.clamp(0, _fields.length - 1)];
      final cmp = compareValues(a[field], b[field]);
      return _sortAsc ? cmp : -cmp;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final source = _ScoreSource(filtered, (r) => showJsonDialog(context, r));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            buildSearchField(
              hint: 'Search user ID or event…',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 6,
              children: [
                buildFilterChip(
                  label: 'All',
                  selected: _polarity == 'all',
                  onTap: () => setState(() => _polarity = 'all'),
                ),
                buildFilterChip(
                  label: 'Positive',
                  selected: _polarity == 'positive',
                  onTap: () => setState(() => _polarity = 'positive'),
                  accent: kGreen,
                ),
                buildFilterChip(
                  label: 'Negative',
                  selected: _polarity == 'negative',
                  onTap: () => setState(() => _polarity = 'negative'),
                  accent: kRed,
                ),
              ],
            ),
            const Spacer(),
            Text(
              '${filtered.length} of ${widget.rows.length}',
              style: GoogleFonts.inter(fontSize: 12, color: kN500),
            ),
          ],
        ),
        const SizedBox(height: 14),
        buildTableCard(
          child: PaginatedDataTable(
            rowsPerPage: 25,
            showCheckboxColumn: false,
            sortColumnIndex: _sortCol,
            sortAscending: _sortAsc,
            columns: [
              _col('USER ID', 0),
              _col('EVENT', 1),
              _col('POINTS', 2),
              _col('DATE', 3),
            ],
            source: source,
            arrowHeadColor: kN500,
          ),
        ),
      ],
    );
  }

  DataColumn _col(String label, int idx) => DataColumn(
        label: Text(label),
        onSort: (i, asc) => setState(() {
          _sortCol = i;
          _sortAsc = asc;
        }),
      );
}

class _ScoreSource extends DataTableSource {
  final List<Map<String, dynamic>> _rows;
  final void Function(Map<String, dynamic>) _onTap;

  _ScoreSource(this._rows, this._onTap);

  @override
  DataRow? getRow(int index) {
    if (index >= _rows.length) return null;
    final r = _rows[index];
    final pts = r['points'] as num?;
    final userId = fmtStr(r['__userId']);
    final shortId =
        userId.length > 12 ? '…${userId.substring(userId.length - 12)}' : userId;

    return DataRow(
      color: alternatingRowColor(index),
      onSelectChanged: (_) => _onTap(r),
      cells: [
        DataCell(Tooltip(
          message: userId,
          child: Text(
            shortId,
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: kN700),
          ),
        )),
        DataCell(Text(
          fmtStr(r['event']),
          style: GoogleFonts.inter(fontSize: 13, color: kN900, fontWeight: FontWeight.w500),
        )),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: pts == null
                  ? kN100
                  : (pts > 0
                      ? kGreen.withValues(alpha: 0.1)
                      : pts < 0
                          ? kRed.withValues(alpha: 0.1)
                          : kN100),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              pts == null ? '-' : '${pts > 0 ? '+' : ''}${pts.toInt()}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: pts == null
                    ? kN500
                    : (pts > 0
                        ? kGreen
                        : pts < 0
                            ? kRed
                            : kN500),
              ),
            ),
          ),
        ),
        DataCell(Text(fmtDate(r['createdAt']), style: GoogleFonts.inter(fontSize: 12, color: kN500))),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => _rows.length;
  @override
  int get selectedRowCount => 0;
}
