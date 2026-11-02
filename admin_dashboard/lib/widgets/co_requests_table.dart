import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/dashboard_theme.dart';
import 'table_utils.dart';

class CoRequestsTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  const CoRequestsTable({super.key, required this.rows});

  @override
  State<CoRequestsTable> createState() => _CoRequestsTableState();
}

class _CoRequestsTableState extends State<CoRequestsTable> {
  String _query = '';
  String _status = 'all';
  int _sortCol = 6;
  bool _sortAsc = false;

  static const _fields = [
    'productName', 'category', 'status',
    'totalPrice', 'partnersNeeded', 'storeName', 'createdAt',
  ];

  static const _statuses = ['all', 'active', 'completed', 'expired', 'cancelled'];

  static Color _statusColor(String s) {
    switch (s) {
      case 'active': return kGreen;
      case 'completed': return kBlue;
      case 'expired': return kCyan;
      case 'cancelled': return kRed;
      default: return kN500;
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var rows = widget.rows.where((r) {
      if (_status != 'all' && fmtStr(r['status']) != _status) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return fmtStr(r['productName']).toLowerCase().contains(q) ||
          fmtStr(r['category']).toLowerCase().contains(q) ||
          fmtStr(r['storeName']).toLowerCase().contains(q);
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
    final source = _CoRequestsSource(filtered, (r) => showJsonDialog(context, r));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            buildSearchField(
              hint: 'Search product, category, store…',
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
              _col('PRODUCT', 0),
              _col('CATEGORY', 1),
              _col('STATUS', 2),
              _col('PRICE (RM)', 3),
              _col('PARTNERS', 4),
              _col('STORE', 5),
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

class _CoRequestsSource extends DataTableSource {
  final List<Map<String, dynamic>> _rows;
  final void Function(Map<String, dynamic>) _onTap;

  _CoRequestsSource(this._rows, this._onTap);

  @override
  DataRow? getRow(int index) {
    if (index >= _rows.length) return null;
    final r = _rows[index];
    return DataRow(
      color: alternatingRowColor(index),
      onSelectChanged: (_) => _onTap(r),
      cells: [
        DataCell(Text(
          fmtStr(r['productName']),
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: kN900),
        )),
        DataCell(Text(fmtStr(r['category']))),
        DataCell(statusBadge(
          fmtStr(r['status']),
          color: _CoRequestsTableState._statusColor(fmtStr(r['status'])),
        )),
        DataCell(Text(
          'RM ${fmtNum(r['totalPrice'], decimals: 2)}',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: kN900),
        )),
        DataCell(Text(fmtNum(r['partnersNeeded']))),
        DataCell(Text(fmtStr(r['storeName']), style: GoogleFonts.inter(fontSize: 13, color: kN700))),
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
