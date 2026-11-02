import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'table_utils.dart';

class RtmTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const RtmTable({super.key, required this.rows});

  @override
  State<RtmTable> createState() => _RtmTableState();
}

class _RtmTableState extends State<RtmTable> {
  String _query = '';
  String _status = 'all';
  int _sortCol = 5;
  bool _sortAsc = false;

  static const _fields = [
    'ownerName', 'category', 'status',
    'participants', 'convertedToCoBuyId', 'createdAt',
  ];

  static const _statuses = ['all', 'waiting', 'matched', 'closed'];

  static Color _statusColor(String s) {
    switch (s) {
      case 'waiting': return kGreen;
      case 'matched': return kBlue;
      case 'closed': return kCyan;
      default: return kN500;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var rows = widget.rows.where((r) {
      if (_status != 'all' && fmtStr(r['status']) != _status) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return fmtStr(r['ownerName']).toLowerCase().contains(q) ||
          fmtStr(r['category']).toLowerCase().contains(q);
    }).toList();
    rows.sort((a, b) {
      final field = _fields[_sortCol.clamp(0, _fields.length - 1)];
      final va = field == 'participants'
          ? (a[field] as List?)?.length ?? 0
          : a[field];
      final vb = field == 'participants'
          ? (b[field] as List?)?.length ?? 0
          : b[field];
      final cmp = compareValues(va, vb);
      return _sortAsc ? cmp : -cmp;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final source = _RtmSource(filtered, (r) => showJsonDialog(context, r));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            buildSearchField(
              hint: 'Search owner, category…',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 6,
              children: _statuses.map((s) {
                return buildFilterChip(
                  label: s == 'all' ? 'All' : '${s[0].toUpperCase()}${s.substring(1)}',
                  selected: _status == s,
                  onTap: () => setState(() => _status = s),
                  accent: s == 'all' ? kBlue : _statusColor(s),
                );
              }).toList(),
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
              _col('OWNER', 0),
              _col('CATEGORY', 1),
              _col('STATUS', 2),
              _col('PARTICIPANTS', 3),
              _col('→ CO-BUY?', 4),
              _col('CREATED', 5),
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

class _RtmSource extends DataTableSource {
  final List<Map<String, dynamic>> _rows;
  final void Function(Map<String, dynamic>) _onTap;

  _RtmSource(this._rows, this._onTap);

  @override
  DataRow? getRow(int index) {
    if (index >= _rows.length) return null;
    final r = _rows[index];
    final participants = r['participants'] as List? ?? [];
    final converted = r['convertedToCoBuyId'] != null;

    return DataRow(
      color: alternatingRowColor(index),
      onSelectChanged: (_) => _onTap(r),
      cells: [
        DataCell(Text(
          fmtStr(r['ownerName']),
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: kN900),
        )),
        DataCell(Text(fmtStr(r['category']))),
        DataCell(statusBadge(
          fmtStr(r['status']),
          color: _RtmTableState._statusColor(fmtStr(r['status'])),
        )),
        DataCell(Row(
          children: [
            const Icon(Icons.people_outline, size: 13, color: kN500),
            const SizedBox(width: 4),
            Text('${participants.length}'),
          ],
        )),
        DataCell(
          converted
              ? statusBadge('Converted', color: kGreen)
              : Text('—', style: GoogleFonts.inter(fontSize: 13, color: kN400)),
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
