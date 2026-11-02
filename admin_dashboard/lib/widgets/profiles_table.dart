import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'table_utils.dart';

class ProfilesTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const ProfilesTable({super.key, required this.rows});

  @override
  State<ProfilesTable> createState() => _ProfilesTableState();
}

class _ProfilesTableState extends State<ProfilesTable> {
  String _query = '';
  String _level = 'all'; // all / User / Trusted / Elite
  int _sortCol = 2; // score
  bool _sortAsc = false;

  static const _fields = [
    'displayName', 'email', 'score', 'score',
    'rating', 'totalRequests', 'createdAt',
  ];

  static String _tier(dynamic score) {
    final s = (score ?? 0) as num;
    if (s >= 700) return 'Elite';
    if (s >= 300) return 'Trusted';
    return 'User';
  }

  static Color _tierColor(String level) {
    switch (level) {
      case 'Elite': return kAmber;
      case 'Trusted': return kBlue;
      default: return kN500;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var rows = widget.rows.where((r) {
      if (_level != 'all' && _tier(r['score']) != _level) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return fmtStr(r['displayName']).toLowerCase().contains(q) ||
          fmtStr(r['email']).toLowerCase().contains(q);
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
    final source = _ProfilesSource(filtered, (r) => showJsonDialog(context, r));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            buildSearchField(
              hint: 'Search by name or email…',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 6,
              children: [
                buildFilterChip(
                  label: 'All',
                  selected: _level == 'all',
                  onTap: () => setState(() => _level = 'all'),
                ),
                buildFilterChip(
                  label: 'User',
                  selected: _level == 'User',
                  onTap: () => setState(() => _level = 'User'),
                  accent: kN500,
                ),
                buildFilterChip(
                  label: 'Trusted',
                  selected: _level == 'Trusted',
                  onTap: () => setState(() => _level = 'Trusted'),
                  accent: kBlue,
                ),
                buildFilterChip(
                  label: 'Elite',
                  selected: _level == 'Elite',
                  onTap: () => setState(() => _level = 'Elite'),
                  accent: kAmber,
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
              _col('NAME', 0),
              _col('EMAIL', 1),
              _col('SCORE', 2),
              const DataColumn(label: Text('LEVEL')),
              _col('RATING', 4),
              _col('REQUESTS', 5),
              _col('CREATED', 6),
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

class _ProfilesSource extends DataTableSource {
  final List<Map<String, dynamic>> _rows;
  final void Function(Map<String, dynamic>) _onTap;

  _ProfilesSource(this._rows, this._onTap);

  @override
  DataRow? getRow(int index) {
    if (index >= _rows.length) return null;
    final r = _rows[index];
    final tier = _ProfilesTableState._tier(r['score']);
    final tierColor = _ProfilesTableState._tierColor(tier);
    return DataRow(
      color: alternatingRowColor(index),
      onSelectChanged: (_) => _onTap(r),
      cells: [
        DataCell(Text(
          fmtStr(r['displayName']),
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: kN900),
        )),
        DataCell(Text(fmtStr(r['email']))),
        DataCell(Text(
          fmtNum(r['score']),
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kN900),
        )),
        DataCell(statusBadge(tier, color: tierColor)),
        DataCell(Row(
          children: [
            const Icon(Icons.star, size: 13, color: kAmber),
            const SizedBox(width: 3),
            Text(fmtNum(r['rating'], decimals: 1)),
          ],
        )),
        DataCell(Text(fmtNum(r['totalRequests']))),
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
