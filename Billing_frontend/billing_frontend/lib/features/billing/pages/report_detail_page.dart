// ============================================================================
// REPORT DETAIL PAGE
// ============================================================================
// File: lib/screens/billing/pages/report_detail_page.dart
// Opens when user clicks any row in ReportViewerPage.
// Fetches filtered detail data for that specific record (customer/vendor/item etc.)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/reports_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';

const Color _navy   = Color(0xFF1e3a8a);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF1ABC9C);
const Color _purple = Color(0xFF9B59B6);

class ReportDetailPage extends StatefulWidget {
  final ReportMeta             parentReport;
  final Map<String, dynamic>   rowData;
  final String                 orgName;
  final Map<String, String>    periodParams;

  const ReportDetailPage({
    Key? key,
    required this.parentReport,
    required this.rowData,
    required this.orgName,
    required this.periodParams,
  }) : super(key: key);

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  Map<String, dynamic>?      _data;
  List<Map<String, dynamic>> _rows    = [];
  List<String>               _headers = [];
  Map<String, dynamic>       _totals  = {};
  bool    _loading   = true;
  bool    _exporting = false;
  String? _error;
  String  _search    = '';

  final _searchCtrl   = TextEditingController();
  final _tableHScroll = ScrollController();

  // Detect the entity type from the parent report key and row data
  String get _entityId {
    final r = widget.rowData;
    return r['customerId']?.toString() ??
           r['vendorId']?.toString()   ??
           r['itemId']?.toString()     ??
           r['accountId']?.toString()  ??
           r['_id']?.toString()        ?? '';
  }

  String get _entityName {
    final r = widget.rowData;
    return r['customerName']?.toString() ??
           r['vendorName']?.toString()   ??
           r['itemName']?.toString()     ??
           r['accountName']?.toString()  ??
           r['name']?.toString()         ??
           r['category']?.toString()     ?? 'Detail';
  }

  // Map parent report key → detail endpoint key
  String get _detailKey {
    final k = widget.parentReport.key;
    if (k.contains('sales-by-customer') || k.contains('customer-balance') || k.contains('ar-aging')) {
      return 'invoice-details';
    }
    if (k.contains('vendor-balance') || k.contains('purchases-by-vendor') || k.contains('ap-aging')) {
      return 'bill-details';
    }
    if (k.contains('sales-by-item') || k.contains('purchases-by-item')) {
      return 'invoice-details';
    }
    if (k.contains('payments-received') || k.contains('receivable')) {
      return 'payments-received';
    }
    if (k.contains('payments-made') || k.contains('payable')) {
      return 'payments-made';
    }
    if (k.contains('expense')) {
      return 'expense-details';
    }
    if (k.contains('general-ledger') || k.contains('account-transactions')) {
      return 'account-transactions';
    }
    if (k.contains('sales-by-salesperson')) {
      return 'invoice-details';
    }
    // Default: try invoice-details
    return 'invoice-details';
  }

  Map<String, String> get _detailParams {
    final params = Map<String, String>.from(widget.periodParams);
    final r = widget.rowData;

    // _id from aggregated rows (sales-by-customer, vendor-balance etc.) IS the entity ID
    final rawId = r['_id']?.toString();

    final pk = widget.parentReport.key;

    if (pk.contains('sales-by-customer') || pk.contains('customer-balance') || pk.contains('ar-aging')) {
      // _id = customerId in these aggregations
      if (rawId != null && rawId.isNotEmpty && rawId != 'null') params['customerId'] = rawId;
    } else if (pk.contains('vendor-balance') || pk.contains('purchases-by-vendor') || pk.contains('ap-aging')) {
      // _id = vendorId
      if (rawId != null && rawId.isNotEmpty && rawId != 'null') params['vendorId'] = rawId;
    } else if (pk.contains('sales-by-salesperson')) {
      // _id = salesperson name string
      if (rawId != null && rawId.isNotEmpty && rawId != 'null') params['salesperson'] = rawId;
    } else if (pk.contains('sales-by-item') || pk.contains('purchases-by-item')) {
      // _id = item name string
      if (rawId != null && rawId.isNotEmpty && rawId != 'null') params['itemName'] = rawId;
    }

    // Also pass explicit fields if present (non-aggregated rows)
    if (r['customerId'] != null)   params['customerId']  = r['customerId'].toString();
    if (r['vendorId'] != null)     params['vendorId']    = r['vendorId'].toString();
    if (r['accountId'] != null)    params['accountId']   = r['accountId'].toString();
    if (r['salesperson'] != null)  params['salesperson'] = r['salesperson'].toString();
    if (r['category'] != null)     params['category']    = r['category'].toString();
    return params;
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ReportsService.fetchReport(_detailKey, _detailParams);
      _parse(d);
      setState(() { _data = d; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _parse(Map<String, dynamic> d) {
    _rows    = [];
    _headers = [];
    _totals  = {};

    const listKeys = [
      'invoices', 'bills', 'payments', 'expenses', 'transactions',
      'creditNotes', 'journals', 'items', 'accounts',
    ];

    List<dynamic>? list;
    for (final k in listKeys) {
      if (d[k] is List && (d[k] as List).isNotEmpty) { list = d[k]; break; }
    }

    if (list != null) {
      final hSet = <String>{};
      for (final row in list) {
        if (row is Map) hSet.addAll(row.keys.cast<String>().where((k) => !k.startsWith('_')));
      }
      _headers = hSet.toList();
      _rows = list.map<Map<String, dynamic>>((r) {
        if (r is Map<String, dynamic>) return r;
        if (r is Map) return Map<String, dynamic>.from(r);
        return {'value': r.toString()};
      }).toList();
    }

    for (final k in ['totals', 'total', 'grandTotal']) {
      if (d[k] != null) _totals[k] = d[k];
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _rows;
    return _rows.where((r) => r.values.any((v) => v.toString().toLowerCase().contains(_search))).toList();
  }

  String _colLabel(String h) =>
      h.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}').trim()
       .split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  String _displayVal(String h, dynamic v) {
    if (v == null) return '-';
    final s = v.toString();
    if (s == 'null' || s.isEmpty) return '-';
    if (s.contains('T') && s.contains(':') && s.length > 10) {
      try { return DateFormat('dd MMM yyyy').format(DateTime.parse(s)); } catch (_) {}
    }
    final hl = h.toLowerCase();
    if (hl.contains('amount') || hl.contains('total') || hl.contains('paid') ||
        hl.contains('due') || hl.contains('balance') || hl.contains('debit') || hl.contains('credit')) {
      final n = double.tryParse(s);
      if (n != null) return '₹${n.toStringAsFixed(2)}';
    }
    return s;
  }

  Future<void> _exportPDF() async {
    if (_rows.isEmpty) { _snackErr('No data to export'); return; }
    setState(() => _exporting = true);
    try {
      final title = '${widget.orgName}\n${widget.parentReport.name} — $_entityName';
      await ExportHelper.exportToPDF(
        title:    title,
        headers:  _headers.map(_colLabel).toList(),
        data:     _rows.map((r) => _headers.map((h) => _displayVal(h, r[h])).toList()).toList(),
        filename: '${widget.parentReport.name.replaceAll(' ', '_')}_$_entityName',
      );
      setState(() => _exporting = false);
      _snackOk('PDF downloaded');
    } catch (e) {
      setState(() => _exporting = false);
      _snackErr('PDF failed: $e');
    }
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) { _snackErr('No data to export'); return; }
    setState(() => _exporting = true);
    try {
      final rows = <List<dynamic>>[
        [widget.orgName],
        ['${widget.parentReport.name} — $_entityName'],
        [],
        _headers.map(_colLabel).toList(),
        ..._rows.map((r) => _headers.map((h) => _displayVal(h, r[h])).toList()),
      ];
      await ExportHelper.exportToExcel(
        data:     rows,
        filename: '${widget.parentReport.name.replaceAll(' ', '_')}_$_entityName',
      );
      setState(() => _exporting = false);
      _snackOk('Excel downloaded');
    } catch (e) {
      setState(() => _exporting = false);
      _snackErr('Excel failed: $e');
    }
  }

  void _snackOk(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 16), const SizedBox(width: 8), Expanded(child: Text(m))]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), duration: const Duration(seconds: 2)));
  }

  void _snackErr(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 16), const SizedBox(width: 8), Expanded(child: Text(m))]),
      backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), duration: const Duration(seconds: 4)));
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: '${widget.parentReport.name} — $_entityName'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(children: [
        _buildTopBar(),
        if (!_loading && _totals.isNotEmpty) _buildSummaryCards(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: _navy)))
        else if (_error != null)
          Expanded(child: _buildError())
        else
          Expanded(child: _buildTable()),
      ]),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 700) return Row(children: [
          // Entity info badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _navy.withOpacity(0.07), borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.person_outline, size: 13, color: _navy),
              const SizedBox(width: 5),
              Text(_entityName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(child: _searchBox(double.infinity)),
          const SizedBox(width: 8),
          _iconBtn(Icons.refresh_rounded, _loading ? null : _load),
          const SizedBox(width: 8),
          _btn('PDF',   Icons.picture_as_pdf_rounded, _red,   _exporting ? null : _exportPDF),
          const SizedBox(width: 6),
          _btn('Excel', Icons.table_chart_rounded,     _green, _exporting ? null : _exportExcel),
        ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(color: _navy.withOpacity(0.07), borderRadius: BorderRadius.circular(6)),
            child: Text(_entityName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _navy))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _searchBox(double.infinity)),
            const SizedBox(width: 8),
            _iconBtn(Icons.refresh_rounded, _loading ? null : _load),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _smBtn('PDF',   _red,   _exporting ? null : _exportPDF),
            const SizedBox(width: 6),
            _smBtn('Excel', _green, _exporting ? null : _exportExcel),
          ]),
        ]);
      }),
    );
  }

  Widget _searchBox(double w) {
    final f = TextField(
      controller: _searchCtrl, style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search…', hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey[400]),
        suffixIcon: _search.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 14), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
            : null,
        filled: true, fillColor: const Color(0xFFF7F9FC),
        isDense: true, contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (w == double.infinity) return SizedBox(height: 40, child: f);
    return SizedBox(width: w, height: 40, child: f);
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap) => InkWell(onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(width: 40, height: 40,
        decoration: BoxDecoration(color: const Color(0xFFF1F1F1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
        child: Icon(icon, size: 18, color: onTap == null ? Colors.grey[300] : const Color(0xFF7F8C8D))));

  Widget _btn(String label, IconData icon, Color bg, VoidCallback? onTap) =>
      ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withOpacity(0.4), elevation: 0,
          minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));

  Widget _smBtn(String label, Color bg, VoidCallback? onTap) =>
      ElevatedButton(onPressed: onTap,
        style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withOpacity(0.4), elevation: 0,
          minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));

  Widget _buildSummaryCards() {
    final totals = _data?['totals'] ?? _data?['total'];
    if (totals == null || totals is! Map) return const SizedBox.shrink();
    final items = <Map<String, String>>[];
    (totals as Map).forEach((k, v) {
      if (v == null) return;
      items.add({'label': _colLabel(k.toString()), 'value': v.toString()});
    });
    if (items.isEmpty) return const SizedBox.shrink();

    final colors = [_navy, _green, _blue, _orange, _purple, _teal];
    return Container(
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Row(children: items.asMap().entries.map((e) {
          final color = colors[e.key % colors.length];
          final n = double.tryParse(e.value['value'] ?? '');
          return Container(
            width: 150, margin: EdgeInsets.only(right: e.key < items.length - 1 ? 10 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.2)),
              boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value['label'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(n != null ? '₹${n.toStringAsFixed(2)}' : (e.value['value'] ?? ''),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            ]),
          );
        }).toList()),
      ),
    );
  }

  Widget _buildTable() {
    final rows = _filtered;
    if (rows.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(_search.isNotEmpty ? 'No results match "$_search"' : 'No detail records found',
            style: TextStyle(fontSize: 15, color: Colors.grey[500])),
      ]));
    }

    if (_headers.isEmpty) {
      return SingleChildScrollView(padding: const EdgeInsets.all(16),
          child: Container(padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Text(_data.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11))));
    }

    final colW = _headers.length <= 4 ? 180.0 : _headers.length <= 7 ? 140.0 : 120.0;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (_, c) => Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('${rows.length} record${rows.length != 1 ? 's' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            const Spacer(),
            if (_exporting) const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: _navy)),
          ])),
        const Divider(height: 1),
        Expanded(child: Scrollbar(
          controller: _tableHScroll, thumbVisibility: true, trackVisibility: true,
          thickness: 7, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(_).copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScroll, scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.3),
                  headingRowHeight: 46, dataRowMinHeight: 50, dataRowMaxHeight: 62,
                  dataTextStyle: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                  dividerThickness: 1, columnSpacing: 16, horizontalMargin: 16,
                  columns: _headers.map((h) => DataColumn(
                      label: SizedBox(width: colW, child: Text(_colLabel(h).toUpperCase(), overflow: TextOverflow.ellipsis)))).toList(),
                  rows: rows.asMap().entries.map((e) => DataRow(
                    color: WidgetStateProperty.resolveWith((s) {
                      if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                      return e.key % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC);
                    }),
                    cells: _headers.map((h) {
                      final v = e.value[h];
                      return DataCell(SizedBox(width: colW,
                          child: Text(_displayVal(h, v), overflow: TextOverflow.ellipsis,
                              style: _cellStyle(h, v))));
                    }).toList(),
                  )).toList(),
                ),
              ),
            ),
          ),
        )),
      ])),
    );
  }

  TextStyle? _cellStyle(String h, dynamic v) {
    final hl = h.toLowerCase();
    if (hl.contains('amount') || hl.contains('total') || hl.contains('due') || hl.contains('balance')) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n != null && n < 0) return const TextStyle(fontSize: 12, color: _red, fontWeight: FontWeight.w500);
      if (n != null && n > 0) return const TextStyle(fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.w500);
    }
    if (h.toLowerCase() == 'status') return const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    return null;
  }

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 52, color: Colors.red[400]),
    const SizedBox(height: 12),
    Text('Failed to load details', style: TextStyle(fontSize: 15, color: Colors.grey[700])),
    const SizedBox(height: 8),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(_error ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500]), textAlign: TextAlign.center)),
    const SizedBox(height: 20),
    ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
  ]));
}