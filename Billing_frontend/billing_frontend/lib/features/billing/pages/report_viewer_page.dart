// ============================================================================
// REPORT VIEWER PAGE — COMPLETE FIX
// ============================================================================
// File: lib/screens/billing/pages/report_viewer_page.dart
// Fixes:
//  1. Row drill-down passes correct _id as customerId/vendorId
//  2. PDF uses ExportHelper locally (no backend call, no broken Rs symbol)
//  3. Row action buttons: View, PDF, Share, Details on each row
//  4. Trial Balance column widths fixed
//  5. Charts fixed: labels non-overlapping, tooltips white+navy, negative values handled
//  6. P&L / Balance Sheet / Cash Flow hierarchical renderer (sections + totals)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../../core/finance_secure_storage.dart';
import '../../../../core/services/reports_service.dart';
import '../../../../core/services/tms_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'report_detail_page.dart';

// Allows mouse + touch drag on horizontal scroll tables
class _AllDeviceScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

const Color _navy   = Color(0xFF1e3a8a);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF1ABC9C);
const Color _purple = Color(0xFF9B59B6);

enum ChartType { bar, line, pie }

class _Period { final String key, label; const _Period(this.key, this.label); }
const _periods = [
  _Period('this_month',   'This Month'),
  _Period('last_month',   'Last Month'),
  _Period('this_quarter', 'This Quarter'),
  _Period('this_fy',      'This Financial Year'),
  _Period('last_fy',      'Last Financial Year'),
  _Period('custom',       'Custom Range'),
];

const _hierarchicalReports = {
  'profit-loss', 'balance-sheet', 'cash-flow',
  'profit-loss-horizontal', 'balance-sheet-horizontal', 'movement-of-equity',
};

class ReportViewerPage extends StatefulWidget {
  final ReportMeta report;
  final String     orgName;
  const ReportViewerPage({Key? key, required this.report, required this.orgName}) : super(key: key);
  @override State<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<ReportViewerPage> {
  Map<String, dynamic>? _data;
  bool    _loading   = true;
  bool    _exporting = false;
  String? _error;

  String    _periodKey = 'this_fy';
  DateTime? _fromDate;
  DateTime? _toDate;

  bool      _chartMode = false;
  ChartType _chartType = ChartType.bar;

  List<Map<String, dynamic>> _rows    = [];
  List<String>               _headers = [];
  Map<String, dynamic>       _totals  = {};

  String _search = '';
  final _searchCtrl   = TextEditingController();
  final _tableHScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.toLowerCase()));
    _loadReport();
  }

  @override
  void dispose() { _searchCtrl.dispose(); _tableHScroll.dispose(); super.dispose(); }

  bool get _isHierarchical => _hierarchicalReports.contains(widget.report.key);

  Map<String, String> get _params {
    if (_periodKey != 'custom') return {'period': _periodKey};
    final p = <String, String>{};
    if (_fromDate != null) p['fromDate'] = _fromDate!.toIso8601String();
    if (_toDate   != null) p['toDate']   = _toDate!.toIso8601String();
    return p;
  }

  Future<void> _loadReport() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ReportsService.fetchReport(widget.report.key, _params);
      _parse(d);
      setState(() { _data = d; _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _parse(Map<String, dynamic> d) {
    _rows = []; _headers = []; _totals = {};
    if (_isHierarchical) return;
    const listKeys = [
      'customers','vendors','items','salespersons','invoices','bills',
      'payments','refunds','expenses','categories','transactions',
      'creditNotes','vendorCredits','journals','logs','dailySummary',
      'buckets','accountTypes','accounts',
    ];
    List<dynamic>? list;
    for (final k in listKeys) {
      if (d[k] is List && (d[k] as List).isNotEmpty) { list = d[k]; break; }
    }
    if (list != null) {
      final hSet = <String>{};
      for (final r in list) { if (r is Map) hSet.addAll(r.keys.cast<String>().where((k) => !k.startsWith('_'))); }
      _headers = hSet.toList();
      _rows = list.map<Map<String, dynamic>>((r) {
        if (r is Map<String, dynamic>) return r;
        if (r is Map) return Map<String, dynamic>.from(r);
        return {'value': r.toString()};
      }).toList();
    }
    for (final k in ['totals','total','grandTotal']) {
      if (d[k] != null) _totals[k] = d[k];
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _rows;
    return _rows.where((r) => r.values.any((v) => v.toString().toLowerCase().contains(_search))).toList();
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(context: context, initialDate: _fromDate ?? DateTime.now(),
        firstDate: DateTime(2020), lastDate: DateTime(2100),
        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!));
    if (d != null) { setState(() { _fromDate = d; _periodKey = 'custom'; }); _loadReport(); }
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(context: context, initialDate: _toDate ?? DateTime.now(),
        firstDate: DateTime(2020), lastDate: DateTime(2100),
        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!));
    if (d != null) { setState(() { _toDate = d; _periodKey = 'custom'; }); _loadReport(); }
  }

  // ── Export PDF — fully local, Rs. instead of ₹ ─────────────────────────
  Future<void> _exportPDF({List<Map<String, dynamic>>? customRows, List<String>? customHeaders}) async {
    final rows = customRows ?? _rows;
    final hdrs = customHeaders ?? _headers;
    if (rows.isEmpty) { _snackErr('No data to export'); return; }
    setState(() => _exporting = true);
    try {
      final period = _data?['period'];
      String pl = '';
      if (period is Map) {
        try {
          final s = period['start'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(period['start'].toString())) : '';
          final e = period['end']   != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(period['end'].toString()))   : '';
          pl = '$s - $e';
        } catch (_) {}
      }
      final title = '${widget.orgName}\n${widget.report.name}${pl.isNotEmpty ? '\n$pl' : ''}';
      await ExportHelper.exportToPDF(
        title:   title,
        headers: hdrs.map(_colLabel).toList(),
        data:    rows.map((r) => hdrs.map((h) => _displayVal(h, r[h]).replaceAll('₹', 'Rs.')).toList()).toList(),
        filename: widget.report.name.replaceAll(' ', '_'),
      );
      setState(() => _exporting = false);
      _snackOk('PDF downloaded');
    } catch (e) { setState(() => _exporting = false); _snackErr('PDF failed: $e'); }
  }

  Future<void> _exportExcel({List<Map<String, dynamic>>? customRows, List<String>? customHeaders}) async {
    final rows = customRows ?? _rows;
    final hdrs = customHeaders ?? _headers;
    if (rows.isEmpty) { _snackErr('No data to export'); return; }
    setState(() => _exporting = true);
    try {
      final period = _data?['period'];
      String pl = '';
      if (period is Map) {
        try {
          final s = period['start'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(period['start'].toString())) : '';
          final e = period['end']   != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(period['end'].toString()))   : '';
          pl = '$s - $e';
        } catch (_) {}
      }
      final excelRows = <List<dynamic>>[
        [widget.orgName], [widget.report.name],
        if (pl.isNotEmpty) ['Period: $pl'], [],
        hdrs.map(_colLabel).toList(),
        ...rows.map((r) => hdrs.map((h) => _rawVal(h, r[h])).toList()),
      ];
      await ExportHelper.exportToExcel(data: excelRows, filename: widget.report.name.replaceAll(' ', '_'));
      setState(() => _exporting = false);
      _snackOk('Excel downloaded');
    } catch (e) { setState(() => _exporting = false); _snackErr('Excel failed: $e'); }
  }

  Future<void> _share() async {
    final text = '${widget.report.name}\n${widget.orgName.isNotEmpty ? "Company: ${widget.orgName}\n" : ""}Records: ${_filtered.length}\n\nGenerated from Finance Module';
    try { await Share.share(text, subject: widget.report.name); }
    catch (e) { _snackErr('Share failed: $e'); }
  }

  void _raiseTicket() => showDialog(context: context, builder: (_) =>
      _TicketDialog(reportName: widget.report.name, orgName: widget.orgName, onSuccess: _snackOk, onError: _snackErr));

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

  String _colLabel(String h) => h
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}').trim()
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

  dynamic _rawVal(String h, dynamic v) {
    if (v == null) return '';
    final hl = h.toLowerCase();
    if (hl.contains('amount') || hl.contains('total') || hl.contains('paid') ||
        hl.contains('due') || hl.contains('balance') || hl.contains('debit') || hl.contains('credit')) {
      return double.tryParse(v.toString()) ?? v.toString();
    }
    return v.toString();
  }

  // ── Correct drill-down: passes _id from aggregated row ──────────────────
  void _openRowDetail(Map<String, dynamic> row) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReportDetailPage(
      parentReport: widget.report, rowData: row, orgName: widget.orgName, periodParams: _params)));
  }

  void _viewRow(Map<String, dynamic> row) {
    showDialog(context: context, builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 560,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: _navy,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14))),
            child: Row(children: [
              const Icon(Icons.visibility_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(child: Text('Record Details', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 18), padding: EdgeInsets.zero),
            ])),
          Flexible(child: ListView(padding: const EdgeInsets.all(16),
              children: row.entries.where((e) => !e.key.startsWith('_')).map((e) =>
                Padding(padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 160, child: Text(_colLabel(e.key),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy))),
                    Expanded(child: Text(_displayVal(e.key, e.value),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF374151)))),
                  ]))).toList())),
          Container(padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: Color(0xFFF7F9FC),
                border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14))),
            child: Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); _exportPDF(customRows: [row], customHeaders: row.keys.where((k) => !k.startsWith('_')).toList()); },
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 15),
                label: const Text('PDF', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(foregroundColor: _red, side: const BorderSide(color: _red),
                    padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); _exportExcel(customRows: [row], customHeaders: row.keys.where((k) => !k.startsWith('_')).toList()); },
                icon: const Icon(Icons.table_chart_rounded, size: 15),
                label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(foregroundColor: _green, side: const BorderSide(color: _green),
                    padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(context); _openRowDetail(row); },
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('Details', style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
            ])),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: widget.report.name),
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(children: [
        _buildTopBar(),
        _buildFilterBar(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: _navy)))
        else if (_error != null)
          Expanded(child: _buildError())
        else if (_isHierarchical)
          Expanded(child: _buildHierarchical())
        else ...[
          if (_totals.isNotEmpty) _buildSummaryCards(),
          Expanded(child: _chartMode ? _buildChartView() : _buildTable()),
        ],
      ]),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 900) return _topDesktop();
        if (c.maxWidth >= 600) return _topTablet();
        return _topMobile();
      }),
    );
  }

  Widget _topDesktop() => Row(children: [
    _searchBox(220), const SizedBox(width: 8),
    _iconBtn(Icons.refresh_rounded, _loading ? null : _loadReport),
    const Spacer(),
    if (widget.orgName.isNotEmpty) ...[
      Text(widget.orgName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
      const SizedBox(width: 14),
    ],
    if (!_isHierarchical) ...[_toggleView(), const SizedBox(width: 10)],
    _btn('PDF',    Icons.picture_as_pdf_rounded,     _red,    _exporting ? null : () => _exportPDF()),
    const SizedBox(width: 6),
    _btn('Excel',  Icons.table_chart_rounded,         _green,  _exporting ? null : () => _exportExcel()),
    const SizedBox(width: 6),
    _btn('Share',  Icons.share_rounded,               _blue,   _share),
    const SizedBox(width: 6),
    _btn('Ticket', Icons.confirmation_number_rounded, _orange, _raiseTicket),
  ]);

  Widget _topTablet() => Column(children: [
    Row(children: [Expanded(child: _searchBox(double.infinity)), const SizedBox(width: 8), _iconBtn(Icons.refresh_rounded, _loading ? null : _loadReport)]),
    const SizedBox(height: 8),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      if (!_isHierarchical) ...[_toggleView(), const SizedBox(width: 10)],
      _btn('PDF',    Icons.picture_as_pdf_rounded,     _red,    _exporting ? null : () => _exportPDF()),
      const SizedBox(width: 6),
      _btn('Excel',  Icons.table_chart_rounded,         _green,  _exporting ? null : () => _exportExcel()),
      const SizedBox(width: 6),
      _btn('Share',  Icons.share_rounded,               _blue,   _share),
      const SizedBox(width: 6),
      _btn('Ticket', Icons.confirmation_number_rounded, _orange, _raiseTicket),
    ])),
  ]);

  Widget _topMobile() => Column(children: [
    _searchBox(double.infinity), const SizedBox(height: 8),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _iconBtn(Icons.refresh_rounded, _loading ? null : _loadReport), const SizedBox(width: 6),
      if (!_isHierarchical) ...[_toggleView(), const SizedBox(width: 6)],
      _smBtn('PDF',    _red,    _exporting ? null : () => _exportPDF()), const SizedBox(width: 6),
      _smBtn('Excel',  _green,  _exporting ? null : () => _exportExcel()), const SizedBox(width: 6),
      _smBtn('Share',  _blue,   _share), const SizedBox(width: 6),
      _smBtn('Ticket', _orange, _raiseTicket),
    ])),
  ]);

  Widget _toggleView() => Container(
    height: 38,
    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDDE3EE))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _viewBtn(Icons.table_rows_rounded, 'Table', !_chartMode, () => setState(() => _chartMode = false)),
      _viewBtn(Icons.bar_chart_rounded,  'Chart', _chartMode,  () => setState(() => _chartMode = true)),
    ]),
  );

  Widget _viewBtn(IconData icon, String label, bool active, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: active ? _navy : Colors.transparent, borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: active ? Colors.white : Colors.grey[500]),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.grey[500])),
      ])),
  );

  Widget _searchBox(double w) {
    final f = TextField(
      controller: _searchCtrl, style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search in report…', hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey[400]),
        suffixIcon: _search.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 14), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); }) : null,
        filled: true, fillColor: const Color(0xFFF7F9FC), isDense: true, contentPadding: EdgeInsets.zero,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (w == double.infinity) return SizedBox(height: 40, child: f);
    return SizedBox(width: w, height: 40, child: f);
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8),
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
          minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));

  Widget _buildFilterBar() {
    final label = _periods.firstWhere((p) => p.key == _periodKey, orElse: () => const _Period('custom', 'Custom Range')).label;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(children: [
        PopupMenuButton<String>(
          initialValue: _periodKey,
          onSelected: (v) { setState(() => _periodKey = v); if (v != 'custom') _loadReport(); },
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (_) => _periods.map((p) => PopupMenuItem(value: p.key,
            child: Row(children: [
              Icon(p.key == _periodKey ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16, color: p.key == _periodKey ? _navy : Colors.grey[400]),
              const SizedBox(width: 8),
              Text(p.label, style: TextStyle(fontSize: 13, fontWeight: p.key == _periodKey ? FontWeight.w600 : FontWeight.normal)),
            ]))).toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: _navy.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: _navy.withOpacity(0.25))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.date_range_rounded, size: 15, color: _navy),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 16, color: _navy),
            ])),
        ),
        if (_periodKey == 'custom') ...[
          const SizedBox(width: 8),
          _datePill(_fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', _fromDate != null, _pickFrom),
          const SizedBox(width: 6),
          _datePill(_toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', _toDate != null, _pickTo),
          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(width: 6),
            InkWell(onTap: () { setState(() { _fromDate = null; _toDate = null; _periodKey = 'this_fy'; }); _loadReport(); },
              child: Container(padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red[200]!)),
                child: const Icon(Icons.close, size: 13, color: _red))),
          ],
        ],
        const Spacer(),
        if (_chartMode && !_isHierarchical) _chartTypePicker(),
      ]),
    );
  }

  Widget _datePill(String label, bool active, VoidCallback onTap) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? _navy.withOpacity(0.08) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? _navy : const Color(0xFFDDE3EE))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.calendar_today, size: 11, color: active ? _navy : Colors.grey[500]),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.normal, color: active ? _navy : Colors.grey[600])),
      ])),
  );

  Widget _chartTypePicker() => Container(
    height: 34,
    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDDE3EE))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _ctBtn(ChartType.bar,  Icons.bar_chart_rounded,  'Bar'),
      _ctBtn(ChartType.line, Icons.show_chart_rounded, 'Line'),
      _ctBtn(ChartType.pie,  Icons.pie_chart_rounded,  'Pie'),
    ]),
  );

  Widget _ctBtn(ChartType t, IconData icon, String label) {
    final active = _chartType == t;
    return GestureDetector(
      onTap: () => setState(() => _chartType = t),
      child: AnimatedContainer(duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: active ? _navy : Colors.transparent, borderRadius: BorderRadius.circular(7)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? Colors.white : Colors.grey[500]),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? Colors.white : Colors.grey[500])),
        ])),
    );
  }

  Widget _buildSummaryCards() {
    final totals = _data?['totals'] ?? _data?['total'];
    if (totals == null) return const SizedBox.shrink();
    final items = <Map<String, String>>[];
    if (totals is Map) {
      totals.forEach((k, v) { if (v != null) items.add({'label': _colLabel(k.toString()), 'value': v.toString()}); });
    } else if (totals is num) { items.add({'label': 'Total', 'value': totals.toStringAsFixed(2)}); }
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
            width: 155, margin: EdgeInsets.only(right: e.key < items.length - 1 ? 10 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.22)),
              boxShadow: [BoxShadow(color: color.withOpacity(0.07), blurRadius: 6, offset: const Offset(0, 2))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value['label'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(n != null ? '₹${n.toStringAsFixed(2)}' : (e.value['value'] ?? ''),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            ]));
        }).toList())),
    );
  }

  // =========================================================================
  //  HIERARCHICAL RENDERER
  // =========================================================================
  Widget _buildHierarchical() {
    if (_data == null) return const Center(child: Text('No data'));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Color(0xFF0D1B3E),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10))),
            child: Column(children: [
              Text(widget.orgName, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(widget.report.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              _periodLabel(),
            ])),
          Padding(padding: const EdgeInsets.all(16), child: _buildHierarchicalContent()),
        ]),
      ),
    );
  }

  Widget _periodLabel() {
    final p = _data?['period'];
    if (p == null) return const SizedBox.shrink();
    try {
      final s = p['start'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(p['start'].toString())) : '';
      final e = p['end']   != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(p['end'].toString())) : '';
      return Text('$s – $e', style: const TextStyle(color: Colors.white54, fontSize: 11));
    } catch (_) { return const SizedBox.shrink(); }
  }

  Widget _buildHierarchicalContent() {
    switch (widget.report.key) {
      case 'profit-loss':             return _buildPL(_data!);
      case 'balance-sheet':           return _buildBS(_data!);
      case 'cash-flow':               return _buildCF(_data!);
      case 'profit-loss-horizontal':  return _buildPLH(_data!);
      case 'balance-sheet-horizontal':return _buildBSH(_data!);
      case 'movement-of-equity':      return _buildMOE(_data!);
      default: return const Text('Layout not defined');
    }
  }

  Widget _buildPL(Map<String, dynamic> d) {
    final income = d['income']            as Map? ?? {};
    final cogs   = d['costOfGoods']       as Map? ?? {};
    final opEx   = d['operatingExpenses'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secHead('Operating Income', _green),
      ..._secItems(income['items']),
      _secTotal('Total for Operating Income', income['total']),
      const SizedBox(height: 12),
      _secHead('Cost of Goods Sold', _orange),
      ..._secItems(cogs['items']),
      _secTotal('Total for Cost of Goods Sold', cogs['total']),
      const SizedBox(height: 4),
      _grossRow('Gross Profit', d['grossProfit']),
      const SizedBox(height: 12),
      _secHead('Operating Expenses', _red),
      ..._secItems(opEx['items']),
      _secTotal('Total for Operating Expenses', opEx['total']),
      const Divider(height: 24),
      _netRow('Net Profit / Loss', d['netProfit']),
    ]);
  }

  Widget _buildBS(Map<String, dynamic> d) {
    final assets = d['assets']      as Map? ?? {};
    final liabs  = d['liabilities'] as Map? ?? {};
    final eq     = d['equity']      as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secHead('Assets', _blue),
      ..._secItems(assets['items']),
      _secTotal('Total Assets', assets['total']),
      const SizedBox(height: 12),
      _secHead('Liabilities', _red),
      ..._secItems(liabs['items']),
      _secTotal('Total Liabilities', liabs['total']),
      const SizedBox(height: 12),
      _secHead('Equity', _purple),
      ..._secItems(eq['items']),
      _secTotal('Total Equity', eq['total']),
      const Divider(height: 24),
      _netRow('Total Liabilities + Equity', d['totalLiabilitiesAndEquity']),
      if (d['balanced'] == true) ...[
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: _green.withOpacity(0.3))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: _green, size: 14), const SizedBox(width: 6),
            const Text('Balance Sheet is Balanced', style: TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w600)),
          ])),
      ],
    ]);
  }

  Widget _buildCF(Map<String, dynamic> d) {
    final op  = d['operating'] as Map? ?? {};
    final inv = d['investing'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _secHead('Operating Activities', _green),
      _kv('Cash Inflows',  op['inflows']),
      _kv('Cash Outflows', op['outflows']),
      _secTotal('Net Operating Cash', op['net']),
      const SizedBox(height: 12),
      _secHead('Investing Activities', _blue),
      _kv('Investing Inflows',  inv['inflows']),
      _kv('Investing Outflows', inv['outflows']),
      _secTotal('Net Investing Cash', inv['net']),
      const Divider(height: 24),
      _netRow('Net Cash Change', d['netCashChange']),
    ]);
  }

  Widget _buildPLH(Map<String, dynamic> d) {
    final curr = d['current']  as Map? ?? {};
    final prev = d['previous'] as Map? ?? {};
    final chg  = d['changes']  as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(flex: 2, child: Text('Current Period', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 12), textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('Previous Period', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 12), textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('Change %', style: const TextStyle(fontWeight: FontWeight.bold, color: _orange, fontSize: 12), textAlign: TextAlign.right)),
      ]),
      const Divider(),
      _hRow('Revenue',    curr['income'],   prev['income'],   chg['income']?['percent']),
      _hRow('Expenses',   curr['expenses'], prev['expenses'], chg['expenses']?['percent']),
      _hRow('Net Profit', curr['netProfit'],prev['netProfit'],chg['netProfit']?['percent']),
    ]);
  }

  Widget _buildBSH(Map<String, dynamic> d) {
    final curr = d['current']  as Map? ?? {};
    final prev = d['previous'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(flex: 2, child: Text('Current', style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 12), textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('Previous', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 12), textAlign: TextAlign.right)),
      ]),
      const Divider(),
      _hRow2('Total Assets',      curr['assets'],      prev['assets']),
      _hRow2('Total Liabilities', curr['liabilities'], prev['liabilities']),
      _hRow2('Total Equity',      curr['equity'],      prev['equity']),
    ]);
  }

  Widget _buildMOE(Map<String, dynamic> d) {
    final accounts = d['accounts'] as List? ?? [];
    final totals   = d['totals']   as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(flex: 3, child: Text('Account', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        Expanded(child: Text('Opening', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700]), textAlign: TextAlign.right)),
        Expanded(child: Text('Change',  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[700]), textAlign: TextAlign.right)),
        Expanded(child: Text('Closing', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _navy), textAlign: TextAlign.right)),
      ]),
      const Divider(),
      ...accounts.map<Widget>((acc) {
        final a = acc as Map;
        return Padding(padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(flex: 3, child: Text(a['accountName']?.toString() ?? '', style: const TextStyle(fontSize: 12))),
            Expanded(child: Text('Rs.${_fmtNum(a['opening'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
            Expanded(child: Text('Rs.${_fmtNum(a['change'])}',  textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: _amtColor(a['change'])))),
            Expanded(child: Text('Rs.${_fmtNum(a['closing'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy))),
          ]));
      }),
      const Divider(),
      Row(children: [
        const Expanded(flex: 3, child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        Expanded(child: Text('Rs.${_fmtNum(totals['opening'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        Expanded(child: Text('Rs.${_fmtNum(totals['change'])}',  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        Expanded(child: Text('Rs.${_fmtNum(totals['closing'])}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy))),
      ]),
    ]);
  }

  Widget _secHead(String title, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
    child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)));

  List<Widget> _secItems(dynamic items) {
    if (items == null || items is! List) return [const SizedBox(height: 4)];
    if (items.isEmpty) return [Padding(padding: const EdgeInsets.only(left: 12, bottom: 4),
        child: Text('No transactions', style: TextStyle(fontSize: 11, color: Colors.grey[400])))];
    return items.map<Widget>((item) {
      final i = item as Map;
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(children: [
          Expanded(child: Text(i['accountName']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF374151)))),
          Text('₹${_fmtNum(i['amount'])}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _amtColor(i['amount']))),
        ]));
    }).toList();
  }

  Widget _secTotal(String label, dynamic val) => Container(
    margin: const EdgeInsets.only(top: 4, bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE8EEF4)))),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      Text('₹${_fmtNum(val)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
    ]));

  Widget _grossRow(String label, dynamic val) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: _green.withOpacity(0.07), borderRadius: BorderRadius.circular(6)),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
      Text('₹${_fmtNum(val)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (val is num && val < 0) ? _red : _green)),
    ]));

  Widget _netRow(String label, dynamic val) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(color: _navy.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy))),
      Text('₹${_fmtNum(val)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: (val is num && val < 0) ? _red : _green)),
    ]));

  Widget _kv(String label, dynamic val) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF374151)))),
      Text('₹${_fmtNum(val)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _amtColor(val))),
    ]));

  Widget _hRow(String label, dynamic curr, dynamic prev, dynamic pct) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(flex: 2, child: Text('₹${_fmtNum(curr)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy))),
      Expanded(flex: 2, child: Text('₹${_fmtNum(prev)}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
      Expanded(flex: 2, child: Text('${_fmtNum(pct)}%',  textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: (pct is num && pct >= 0) ? _green : _red))),
    ]));

  Widget _hRow2(String label, dynamic curr, dynamic prev) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(flex: 2, child: Text('₹${_fmtNum(curr)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy))),
      Expanded(flex: 2, child: Text('₹${_fmtNum(prev)}', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
    ]));

  String _fmtNum(dynamic v) {
    if (v == null) return '0.00';
    final n = double.tryParse(v.toString());
    return n != null ? n.toStringAsFixed(2) : v.toString();
  }

  Color _amtColor(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    return (n != null && n < 0) ? _red : const Color(0xFF374151);
  }

  // =========================================================================
  //  TABLE — with row action buttons
  // =========================================================================
  Widget _buildTable() {
    final rows = _filtered;
    if (rows.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.table_chart_outlined, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(_search.isNotEmpty ? 'No results match "$_search"' : 'No data for this period',
            style: TextStyle(fontSize: 15, color: Colors.grey[500])),
      ]));
    }
    if (_headers.isEmpty) return SingleChildScrollView(padding: const EdgeInsets.all(16),
        child: Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Text(_data.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11))));

    final colW = widget.report.key == 'trial-balance' ? 175.0
        : _headers.length <= 4 ? 180.0
        : _headers.length <= 7 ? 150.0 : 130.0;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (ctx, c) => Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('${rows.length} record${rows.length != 1 ? 's' : ''}${_search.isNotEmpty ? ' (filtered)' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            const Spacer(),
            if (_exporting) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _navy)),
          ])),
        const Divider(height: 1),
        Expanded(child: Scrollbar(
          controller: _tableHScroll, thumbVisibility: true, trackVisibility: true, thickness: 7, radius: const Radius.circular(4),
          child: SingleChildScrollView(
            controller: _tableHScroll,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.3),
                  headingRowHeight: 46, dataRowMinHeight: 52, dataRowMaxHeight: 68,
                  dataTextStyle: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
                  dividerThickness: 1, columnSpacing: 14, horizontalMargin: 14,
                  columns: [
                    ..._headers.map((h) => DataColumn(label: SizedBox(width: colW, child: Text(_colLabel(h).toUpperCase(), overflow: TextOverflow.ellipsis)))),
                    const DataColumn(label: Text('ACTIONS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                  ],
                  rows: rows.asMap().entries.map((e) => DataRow(
                    color: WidgetStateProperty.resolveWith((s) {
                      if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                      return e.key % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC);
                    }),
                    cells: [
                      ..._headers.map((h) {
                        final v = e.value[h];
                        return DataCell(SizedBox(width: colW, child: Text(_displayVal(h, v), overflow: TextOverflow.ellipsis, style: _cellStyle(h, v))));
                      }),
                      DataCell(SizedBox(width: 148, child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _rowAct(Icons.visibility_outlined,     _navy,  'View',    () => _viewRow(e.value)),
                        const SizedBox(width: 4),
                        _rowAct(Icons.picture_as_pdf_outlined, _red,   'PDF',     () => _exportPDF(customRows: [e.value], customHeaders: _headers)),
                        const SizedBox(width: 4),
                        _rowAct(Icons.share_outlined,          _blue,  'Share',   () => _shareRow(e.value)),
                        const SizedBox(width: 4),
                        _rowAct(Icons.open_in_new_rounded,     _green, 'Details', () => _openRowDetail(e.value)),
                      ]))),
                    ],
                  )).toList(),
                )))))
      ])),
    );
  }

  Widget _rowAct(IconData icon, Color color, String tooltip, VoidCallback onTap) => Tooltip(
    message: tooltip,
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6),
      child: Container(width: 30, height: 30,
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, size: 14, color: color))));

  Future<void> _shareRow(Map<String, dynamic> row) async {
    final text = _headers.map((h) => '${_colLabel(h)}: ${_displayVal(h, row[h])}').join('\n');
    try { await Share.share('${widget.report.name}\n\n$text', subject: widget.report.name); }
    catch (e) { _snackErr('Share failed: $e'); }
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

  // =========================================================================
  //  CHART VIEW
  // =========================================================================
  Widget _buildChartView() {
    final rows = _filtered;
    if (rows.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.bar_chart_outlined, size: 52, color: Colors.grey[300]),
      const SizedBox(height: 12),
      Text('No data to chart', style: TextStyle(fontSize: 15, color: Colors.grey[500])),
    ]));

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.report.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy)),
        const SizedBox(height: 4),
        Text('${rows.length} records', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 20),
        Expanded(child: _chartType == ChartType.pie ? _buildPie(rows) : _buildBarLine(rows)),
      ]),
    );
  }

  String _labelField(List<Map<String, dynamic>> rows) {
    const k = ['customerName','vendorName','itemName','accountName','category','salesperson','date','invoiceNumber','billNumber','name'];
    for (final key in k) { if (rows.first.containsKey(key)) return key; }
    return _headers.isNotEmpty ? _headers.first : 'label';
  }

  String _valueField(List<Map<String, dynamic>> rows) {
    const k = ['totalAmount','amount','total','totalSales','balance','amountDue','totalPaid','credit','debit','totalInvoiced','totalBilled'];
    for (final key in k) { if (rows.first.containsKey(key)) return key; }
    for (final h in _headers) { if (double.tryParse(rows.first[h]?.toString() ?? '') != null) return h; }
    return _headers.length > 1 ? _headers[1] : _headers.first;
  }

  final List<Color> _cc = [_navy,_blue,_green,_orange,_purple,_teal,_red,
    const Color(0xFF6366F1),const Color(0xFFF59E0B),const Color(0xFFEC4899),const Color(0xFF14B8A6),const Color(0xFF8B5CF6)];

  Widget _buildBarLine(List<Map<String, dynamic>> rows) {
    final lf = _labelField(rows);
    final vf = _valueField(rows);
    final limited = rows.take(12).toList();
    final vals = limited.map((r) => double.tryParse(r[vf]?.toString() ?? '') ?? 0.0).toList();
    final absMax = vals.isEmpty ? 100.0 : (vals.map((v) => v.abs()).reduce((a, b) => a > b ? a : b) * 1.3);
    final maxY = absMax == 0 ? 100.0 : absMax;
    final minY = vals.any((v) => v < 0) ? vals.reduce((a, b) => a < b ? a : b) * 1.3 : 0.0;
    final step = limited.length <= 6 ? 1 : limited.length <= 10 ? 2 : 3;

    Widget bottomTitle(double v, TitleMeta _) {
      final i = v.toInt();
      if (i < 0 || i >= limited.length || i % step != 0) return const SizedBox.shrink();
      final label = limited[i][lf]?.toString() ?? '';
      final short = label.length > 10 ? '${label.substring(0, 9)}…' : label;
      return Padding(padding: const EdgeInsets.only(top: 4), child: Text(short, style: TextStyle(fontSize: 9, color: Colors.grey[600])));
    }

    Widget leftTitle(double v, TitleMeta _) =>
        Text('₹${_shortNum(v)}', style: TextStyle(fontSize: 9, color: Colors.grey[600]));

    final titlesData = FlTitlesData(
      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 58, getTitlesWidget: leftTitle)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: bottomTitle)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );

    if (_chartType == ChartType.bar) {
      return BarChart(BarChartData(
        minY: minY, maxY: maxY,
        gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
        titlesData: titlesData,
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
          tooltipBgColor: Colors.white,
          tooltipBorder: const BorderSide(color: Color(0xFFE8EEF4)),
          getTooltipItem: (group, _, rod, __) {
            final label = limited[group.x][lf]?.toString() ?? '';
            return BarTooltipItem('$label\n',
              const TextStyle(color: _navy, fontWeight: FontWeight.bold, fontSize: 11),
              children: [TextSpan(text: '₹${rod.toY.toStringAsFixed(2)}',
                  style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 12))]);
          })),
        barGroups: limited.asMap().entries.map((e) => BarChartGroupData(x: e.key,
          barRods: [BarChartRodData(toY: vals[e.key], color: _cc[e.key % _cc.length], width: 20,
            borderRadius: BorderRadius.vertical(top: const Radius.circular(4), bottom: vals[e.key] < 0 ? const Radius.circular(4) : Radius.zero))])).toList(),
      ));
    }

    return LineChart(LineChartData(
      minY: minY, maxY: maxY,
      gridData: FlGridData(show: true, drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
      titlesData: titlesData,
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
        tooltipBgColor: Colors.white,
        tooltipBorder: const BorderSide(color: Color(0xFFE8EEF4)),
        getTooltipItems: (spots) => spots.map((s) {
          final i = s.x.toInt();
          final label = (i >= 0 && i < limited.length) ? (limited[i][lf]?.toString() ?? '') : '';
          return LineTooltipItem('$label\n₹${s.y.toStringAsFixed(2)}',
              const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 11));
        }).toList())),
      lineBarsData: [LineChartBarData(
        spots: vals.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
        isCurved: true, color: _navy, barWidth: 2.5,
        dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) =>
            FlDotCirclePainter(radius: 4, color: _navy, strokeWidth: 2, strokeColor: Colors.white)),
        belowBarData: BarAreaData(show: true, color: _navy.withOpacity(0.07)))],
    ));
  }

  Widget _buildPie(List<Map<String, dynamic>> rows) {
    final lf = _labelField(rows);
    final vf = _valueField(rows);
    final limited = rows.take(8).toList();
    final vals = limited.map((r) => (double.tryParse(r[vf]?.toString() ?? '') ?? 0.0).abs()).toList();
    final total = vals.fold(0.0, (a, b) => a + b);
    if (total == 0) return const Center(child: Text('No positive values to chart'));

    return Row(children: [
      Expanded(child: PieChart(PieChartData(
        sectionsSpace: 2, centerSpaceRadius: 50,
        sections: limited.asMap().entries.map((e) {
          final pct = vals[e.key] / total * 100;
          return PieChartSectionData(
            color: _cc[e.key % _cc.length], value: vals[e.key], radius: 85,
            title: '${pct.toStringAsFixed(1)}%',
            titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white));
        }).toList()))),
      const SizedBox(width: 16),
      SizedBox(width: 150, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: limited.asMap().entries.map((e) {
        final label = limited[e.key][lf]?.toString() ?? '';
        final pct   = vals[e.key] / total * 100;
        return Padding(padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _cc[e.key % _cc.length], borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.length > 14 ? '${label.substring(0, 13)}…' : label, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
              Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 9, color: Colors.grey[500])),
            ])),
          ]));
      }).toList())),
    ]);
  }

  String _shortNum(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 52, color: Colors.red[400]),
    const SizedBox(height: 12),
    Text('Failed to load report', style: TextStyle(fontSize: 15, color: Colors.grey[700])),
    const SizedBox(height: 8),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(_error ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500]), textAlign: TextAlign.center)),
    const SizedBox(height: 20),
    ElevatedButton.icon(onPressed: _loadReport, icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
  ]));
}

// =============================================================================
//  TICKET DIALOG
// =============================================================================
class _TicketDialog extends StatefulWidget {
  final String reportName, orgName;
  final void Function(String) onSuccess, onError;
  const _TicketDialog({required this.reportName, required this.orgName, required this.onSuccess, required this.onError});
  @override State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  final _tms = TMSService();
  final _sc  = TextEditingController();
  List<Map<String, dynamic>> _all = [], _f = [];
  Map<String, dynamic>? _sel;
  bool _loading = true, _assigning = false;
  String _priority = 'Medium';

  @override void initState() { super.initState(); _loadEmps(); _sc.addListener(_filter); }
  @override void dispose()   { _sc.dispose(); super.dispose(); }

  Future<void> _loadEmps() async {
    final r = await _tms.fetchEmployees();
    if (r['success'] == true && r['data'] != null) {
      setState(() { _all = List<Map<String, dynamic>>.from(r['data']); _f = _all; _loading = false; });
    } else { setState(() => _loading = false); widget.onError('Failed to load employees'); }
  }

  void _filter() {
    final q = _sc.text.toLowerCase();
    setState(() { _f = q.isEmpty ? _all : _all.where((e) =>
        (e['name_parson'] ?? '').toLowerCase().contains(q) || (e['email'] ?? '').toLowerCase().contains(q)).toList(); });
  }

  Future<void> _assign() async {
    if (_sel == null) return;
    setState(() => _assigning = true);
    try {
      final r = await _tms.createTicket(subject: 'Report Review: ${widget.reportName}',
          message: 'Please review the ${widget.reportName} report for ${widget.orgName}.',
          priority: _priority, timeline: 1440, assignedTo: _sel!['_id'].toString());
      setState(() => _assigning = false);
      if (r['success'] == true) { widget.onSuccess('Ticket assigned to ${_sel!['name_parson']}'); if (mounted) Navigator.pop(context); }
      else { widget.onError(r['message'] ?? 'Failed'); }
    } catch (e) { setState(() => _assigning = false); widget.onError('Failed: $e'); }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Container(width: 500, constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)]),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
          child: Row(children: [
            const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 20), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(widget.reportName, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11), overflow: TextOverflow.ellipsis),
            ])),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 18)),
          ])),
        Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Priority', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
          const SizedBox(height: 8),
          Row(children: ['Low','Medium','High'].map((p) {
            final sel = _priority == p;
            final c = p == 'High' ? _red : p == 'Medium' ? _orange : _green;
            return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(onTap: () => setState(() => _priority = p),
                child: AnimatedContainer(duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(color: sel ? c : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: sel ? c : Colors.grey[300]!)),
                  child: Center(child: Text(p, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.grey[700])))))));
          }).toList()),
          const SizedBox(height: 16),
          const Text('Assign To', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
          const SizedBox(height: 8),
          TextField(controller: _sc, style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(hintText: 'Search employees…', prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey[400]),
              filled: true, fillColor: const Color(0xFFF7F9FC), isDense: true, contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navy, width: 1.5)))),
          const SizedBox(height: 8),
          _loading ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: _navy)))
            : Container(constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(8)),
              child: ListView.separated(shrinkWrap: true, itemCount: _f.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                itemBuilder: (_, i) {
                  final e = _f[i]; final sel = _sel?['_id'] == e['_id'];
                  return InkWell(onTap: () => setState(() => _sel = sel ? null : e),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), color: sel ? _navy.withOpacity(0.06) : Colors.transparent,
                      child: Row(children: [
                        CircleAvatar(radius: 16, backgroundColor: sel ? _navy : _navy.withOpacity(0.1),
                            child: Text((e['name_parson'] ?? 'U')[0].toUpperCase(), style: TextStyle(color: sel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 12))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e['name_parson'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          if (e['email'] != null) Text(e['email'], style: TextStyle(fontSize: 10, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                        ])),
                        if (sel) const Icon(Icons.check_circle, color: _navy, size: 18),
                      ])));
                })),
        ]))),
        Container(padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(color: Color(0xFFF7F9FC), border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: (_sel == null || _assigning) ? null : _assign,
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white,
                  disabledBackgroundColor: _navy.withOpacity(0.35), elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _assigning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_sel != null ? 'Assign to ${_sel!['name_parson'] ?? ''}' : 'Select Employee',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis))),
          ])),
      ])),
  );
}