// ============================================================================
// CURRENCY ADJUSTMENTS LIST PAGE
// ============================================================================
// File: lib/screens/billing/pages/currency_adjustments_list_page.dart
// Pattern: Exact match of recurring_bills_list_page.dart
//   3-breakpoint top bar | gradient stat cards | dark navy table | pagination
// NOTE: No Share / No WhatsApp "” internal accounting page
//       Raise Ticket in row PopupMenu
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/currency_adjustment_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_currency_adjustment.dart';

// â”€â”€â”€ colours â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF0891B2);

class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({ required this.label, required this.value, required this.icon, required this.color, required this.gradientColors });
}

// =============================================================================
class CurrencyAdjustmentsListPage extends StatefulWidget {
  const CurrencyAdjustmentsListPage({Key? key}) : super(key: key);
  @override
  State<CurrencyAdjustmentsListPage> createState() => _CurrencyAdjustmentsListPageState();
}

class _CurrencyAdjustmentsListPageState extends State<CurrencyAdjustmentsListPage> {
  List<CurrencyAdjustment> _adjustments = [];
  AdjustmentStats? _stats;
  bool    _isLoading   = true;
  String? _errorMessage;

  String   _selectedStatus   = 'All';
  String   _selectedCurrency = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  String   _dateFilterType   = 'All';

  final _statusFilters   = ['All', 'Draft', 'Published', 'Void'];
  List<String> _currencies = ['All'];

  final _searchCtrl      = TextEditingController();
  String _searchQuery    = '';

  int _currentPage = 1;
  int _totalPages  = 1;
  int _total       = 0;
  static const _perPage = 50;

  final _tableHScroll = ScrollController();
  final _statsHScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCurrencies();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScroll.dispose();
    _statsHScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCurrencies() async {
    try {
      final list = await CurrencyAdjustmentService.getSupportedCurrencies();
      if (mounted) setState(() => _currencies = ['All', ...list]);
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      String? fromStr, toStr;
      if (_dateFilterType == 'Within Date Range') { fromStr = _fromDate?.toIso8601String(); toStr = _toDate?.toIso8601String(); }
      else if (_dateFilterType == 'Particular Date') { fromStr = _fromDate?.toIso8601String(); toStr = _fromDate?.toIso8601String(); }
      else if (_fromDate != null && _toDate != null) { fromStr = _fromDate?.toIso8601String(); toStr = _toDate?.toIso8601String(); }

      final res = await Future.wait([
        CurrencyAdjustmentService.getAdjustments(
          status:   _selectedStatus   == 'All' ? null : _selectedStatus,
          currency: _selectedCurrency == 'All' ? null : _selectedCurrency,
          fromDate: fromStr != null ? DateTime.parse(fromStr) : null,
          toDate:   toStr   != null ? DateTime.parse(toStr)   : null,
          search:   _searchQuery.isNotEmpty ? _searchQuery : null,
          page:     _currentPage, limit: _perPage,
        ),
        CurrencyAdjustmentService.getStats(),
      ]);
      if (!mounted) return;
      final list  = res[0] as AdjustmentListResult;
      final stats = res[1] as AdjustmentStats;
      setState(() {
        _adjustments = list.adjustments;
        _totalPages  = list.pages;
        _total       = list.total;
        _stats       = stats;
        _isLoading   = false;
      });
    } catch (e) {
      if (mounted) setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _refresh() async { await _loadData(); _showSuccess('Refreshed'); }

  bool get _hasFilters => _dateFilterType != 'All' || _selectedStatus != 'All' || _selectedCurrency != 'All';

  void _clearFilters() {
    setState(() { _fromDate = null; _toDate = null; _dateFilterType = 'All'; _selectedStatus = 'All'; _selectedCurrency = 'All'; _currentPage = 1; });
    _loadData();
  }

  // â”€â”€ snacks â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showSuccess(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(m))]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(m))]),
      backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _confirmDialog({ required String title, required String message, required String confirmLabel, Color confirmColor = _navy }) =>
    showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
          child: Text(confirmLabel)),
      ],
    ));

  // â”€â”€ actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _openNew() async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewCurrencyAdjustmentPage()));
    if (ok == true) _refresh();
  }

  void _openEdit(CurrencyAdjustment a) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewCurrencyAdjustmentPage(adjustmentId: a.id)));
    if (ok == true) _refresh();
  }

  Future<void> _publish(CurrencyAdjustment a) async {
    final ok = await _confirmDialog(title: 'Publish Adjustment', message: 'Publish "${a.adjustmentNumber}"? This will post entries to Chart of Accounts and create an audit journal.', confirmLabel: 'Publish', confirmColor: _green);
    if (ok != true) return;
    try {
      await CurrencyAdjustmentService.publishAdjustment(a.id);
      _showSuccess('"${a.adjustmentNumber}" published and posted to COA');
      _refresh();
    } catch (e) { _showError('Failed: $e'); }
  }

  Future<void> _void(CurrencyAdjustment a) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Void Adjustment', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Voiding will reverse all COA entries. This cannot be undone.'),
        const SizedBox(height: 14),
        TextField(controller: reasonCtrl, decoration: InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), maxLines: 2),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
          child: const Text('Void')),
      ],
    ));
    if (ok != true) return;
    try {
      await CurrencyAdjustmentService.voidAdjustment(a.id, reason: reasonCtrl.text.trim());
      _showSuccess('"${a.adjustmentNumber}" voided');
      _refresh();
    } catch (e) { _showError('Failed: $e'); }
  }

  Future<void> _delete(CurrencyAdjustment a) async {
    final ok = await _confirmDialog(title: 'Delete Adjustment', message: 'Delete "${a.adjustmentNumber}"? This cannot be undone.', confirmLabel: 'Delete', confirmColor: _red);
    if (ok != true) return;
    try {
      await CurrencyAdjustmentService.deleteAdjustment(a.id);
      _showSuccess('Adjustment deleted');
      _refresh();
    } catch (e) { _showError('Failed: $e'); }
  }

  void _viewDetail(CurrencyAdjustment a) {
    showDialog(context: context, builder: (_) => _AdjustmentDetailDialog(adjustment: a));
  }

  void _raiseTicket(CurrencyAdjustment a) {
    showDialog(context: context, barrierDismissible: true, builder: (_) => _RaiseTicketOverlay(
      adjustment: a,
      onTicketRaised: (msg) => _showSuccess(msg),
      onError: (msg) => _showError(msg),
    ));
  }

  // â”€â”€ export â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _exportExcel() async {
    try {
      _showSuccess('Preparing export...');
      final all = await CurrencyAdjustmentService.getAllForExport(
        status:   _selectedStatus   == 'All' ? null : _selectedStatus,
        currency: _selectedCurrency == 'All' ? null : _selectedCurrency,
      );
      if (all.isEmpty) { _showError('No data to export'); return; }

      final rows = <List<dynamic>>[
        ['Adj Number','Date','Currency','New Rate','Total Transactions','Total Gain (â‚¹)','Total Loss (â‚¹)','Net Adjustment (â‚¹)','Status','Notes','Journal Number'],
        ...all.map((a) => [
          a.adjustmentNumber,
          DateFormat('dd/MM/yyyy').format(a.adjustmentDate),
          a.currency,
          a.newExchangeRate.toStringAsFixed(4),
          a.totalTransactions.toString(),
          a.totalGain.toStringAsFixed(2),
          a.totalLoss.toStringAsFixed(2),
          a.netAdjustment.toStringAsFixed(2),
          a.status,
          a.notes,
          a.journalNumber ?? '',
        ]),
      ];

      await ExportHelper.exportToExcel(data: rows, filename: 'currency_adjustments');
      _showSuccess('âœ… Exported ${all.length} adjustments');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // â”€â”€ import â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _handleImport() {
    showDialog(context: context, builder: (_) => _BulkImportDialog(onImportComplete: _refresh));
  }

  // â”€â”€ lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showLifecycle() {
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(children: [
        Center(child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85, maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: double.infinity, padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: _teal, borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
              child: const Text('Currency Adjustment Process', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            Expanded(child: InteractiveViewer(panEnabled: true, minScale: 0.5, maxScale: 4.0,
              child: Center(child: Image.asset('assets/currency_adjustment.png', fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.currency_exchange, size: 80, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text('Currency Adjustment Flow', style: TextStyle(fontSize: 18, color: Colors.grey[700], fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text('1. Select currency + new rate\n2. System fetches open invoices + bills\n3. Calculates gain/loss per transaction\n4. Publish â†’ posts to COA + creates journal\n5. Void â†’ reverses all COA entries',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.7), textAlign: TextAlign.center),
                  ]),
                ),
              )),
            )),
          ])),
        )),
        Positioned(top: 40, right: 40,
          child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 32), onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.6), padding: const EdgeInsets.all(14)))),
      ]),
    ));
  }

  // â”€â”€ filter dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showFilterDialog() {
    DateTime? tFrom = _fromDate, tTo = _toDate;
    String tType = _dateFilterType;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Filter', style: TextStyle(color: _navy, fontWeight: FontWeight.bold)),
        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
      ]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Currency', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: DropdownButton<String>(
            value: _selectedCurrency, isExpanded: true, underline: const SizedBox(),
            items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) { if (v != null) setState(() => _selectedCurrency = v); },
          ),
        ),
        const SizedBox(height: 16),
        const Text('Date Filter Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: DropdownButton<String>(
            value: tType, isExpanded: true, underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'All',               child: Text('All Dates')),
              DropdownMenuItem(value: 'Within Date Range', child: Text('Within Date Range')),
              DropdownMenuItem(value: 'Particular Date',   child: Text('Particular Date')),
              DropdownMenuItem(value: 'Today',             child: Text('Today')),
              DropdownMenuItem(value: 'This Week',         child: Text('This Week')),
              DropdownMenuItem(value: 'This Month',        child: Text('This Month')),
              DropdownMenuItem(value: 'Last Month',        child: Text('Last Month')),
              DropdownMenuItem(value: 'This Year',         child: Text('This Year')),
            ],
            onChanged: (v) {
              setS(() {
                tType = v ?? 'All';
                final now = DateTime.now();
                if (v == 'Today')       { tFrom = now; tTo = now; }
                else if (v == 'This Week')  { tFrom = now.subtract(Duration(days: now.weekday - 1)); tTo = now.add(Duration(days: 7 - now.weekday)); }
                else if (v == 'This Month') { tFrom = DateTime(now.year, now.month, 1); tTo = DateTime(now.year, now.month + 1, 0); }
                else if (v == 'Last Month') { tFrom = DateTime(now.year, now.month - 1, 1); tTo = DateTime(now.year, now.month, 0); }
                else if (v == 'This Year')  { tFrom = DateTime(now.year, 1, 1); tTo = DateTime(now.year, 12, 31); }
                else if (v == 'All')    { tFrom = null; tTo = null; }
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        if (tType == 'Within Date Range') ...[
          _datePicker(ctx, 'From Date', tFrom, (d) => setS(() => tFrom = d)),
          const SizedBox(height: 12),
          _datePicker(ctx, 'To Date', tTo, (d) => setS(() => tTo = d)),
        ],
        if (tType == 'Particular Date')
          _datePicker(ctx, 'Select Date', tFrom, (d) => setS(() => tFrom = d)),
      ]))),
      actions: [
        TextButton(onPressed: () => setS(() { tFrom = null; tTo = null; tType = 'All'; setState(() => _selectedCurrency = 'All'); }), child: const Text('Clear', style: TextStyle(color: _red))),
        ElevatedButton(
          onPressed: () {
            setState(() { _dateFilterType = tType; _fromDate = tFrom; _toDate = tTo; _currentPage = 1; });
            Navigator.pop(ctx); _loadData();
          },
          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
          child: const Text('Apply'),
        ),
      ],
    )));
  }

  Widget _datePicker(BuildContext ctx, String label, DateTime? value, Function(DateTime) onPick) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 8),
      InkWell(
        onTap: () async {
          final d = await showDatePicker(context: ctx, initialDate: value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (d != null) onPick(d);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.calendar_today, size: 18, color: _navy), const SizedBox(width: 8),
            Text(value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Select date', style: TextStyle(color: value != null ? _navy : Colors.grey[600])),
          ]),
        ),
      ),
    ]);

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Currency Adjustments'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _adjustments.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _adjustments.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // â”€â”€ top bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 10),
    _currencyDropdown(),
    const SizedBox(width: 10),
    _searchField(width: 220),
    const SizedBox(width: 8),
    _filterIconBtn(),
    if (_hasFilters) ...[const SizedBox(width: 4), _iconBtn(Icons.clear, _clearFilters, color: _red, bg: Colors.red[50]!)],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_rounded, _showLifecycle, color: _teal, bg: _teal.withOpacity(0.08), tooltip: 'View Process'),
    const Spacer(),
    _actionBtn('New Adjustment', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _adjustments.isEmpty ? null : _exportExcel),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(), const SizedBox(width: 8),
      _currencyDropdown(), const SizedBox(width: 8),
      _filterIconBtn(),
      if (_hasFilters) ...[const SizedBox(width: 4), _iconBtn(Icons.clear, _clearFilters, color: _red, bg: Colors.red[50]!)],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_rounded, _showLifecycle, color: _teal, bg: _teal.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _adjustments.isEmpty ? null : _exportExcel),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(), const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _currencyDropdown(), const SizedBox(width: 6),
      _filterIconBtn(),
      if (_hasFilters) ...[const SizedBox(width: 4), _iconBtn(Icons.clear, _clearFilters, color: _red, bg: Colors.red[50]!)],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_rounded, _showLifecycle, color: _teal, bg: _teal.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _adjustments.isEmpty ? null : _exportExcel),
    ])),
  ]);

  // â”€â”€ reusable widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _statusDropdown() => _dropdown(
    value: _selectedStatus,
    items: _statusFilters,
    onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _loadData(); } },
    labelPrefix: 'Status: ',
  );

  Widget _currencyDropdown() => _dropdown(
    value: _selectedCurrency,
    items: _currencies,
    onChanged: (v) { if (v != null) { setState(() { _selectedCurrency = v; _currentPage = 1; }); _loadData(); } },
    labelPrefix: '',
  );

  Widget _dropdown({ required String value, required List<String> items, required ValueChanged<String?> onChanged, String labelPrefix = '' }) =>
    Container(
      height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: value,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: items.map((s) => DropdownMenuItem(value: s, child: Text('$labelPrefix$s'))).toList(),
        onChanged: onChanged,
      )),
    );

  Widget _filterIconBtn() => Stack(children: [
    _iconBtn(Icons.filter_list, _showFilterDialog, tooltip: 'Filters', color: _hasFilters ? _navy : const Color(0xFF7F8C8D), bg: _hasFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
    if (_hasFilters) Positioned(right: 4, top: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: _navy, shape: BoxShape.circle))),
  ]);

  Widget _searchField({ required double width }) {
    final f = TextField(
      controller: _searchCtrl, style: const TextStyle(fontSize: 14),
      onChanged: (v) {
        setState(() { _searchQuery = v; _currentPage = 1; });
        Future.delayed(const Duration(milliseconds: 500), () { if (_searchQuery == v) _loadData(); });
      },
      decoration: InputDecoration(
        hintText: 'Search adjustments...', hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); setState(() { _searchQuery = ''; _currentPage = 1; }); _loadData(); }) : null,
        filled: true, fillColor: const Color(0xFFF7F9FC), contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (width == double.infinity) return f;
    return SizedBox(width: width, height: 44, child: f);
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) =>
    Tooltip(message: tooltip, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(width: 42, height: 42, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
        child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color))));

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) =>
    ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, disabledBackgroundColor: bg.withOpacity(0.5), elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) =>
    ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, disabledBackgroundColor: bg.withOpacity(0.5), elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));

  // â”€â”€ stats cards â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildStatsCards() {
    final fmt = NumberFormat('#,##0.00');
    final cards = [
      _StatCardData(label: 'Total Adjustments', value: (_stats?.total     ?? 0).toString(), icon: Icons.currency_exchange,      color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Published',          value: (_stats?.published ?? 0).toString(), icon: Icons.check_circle_outline,   color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Draft',              value: (_stats?.draft     ?? 0).toString(), icon: Icons.edit_note,              color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Total Gain (â‚¹)',     value: 'â‚¹${fmt.format(_stats?.totalGain ?? 0)}', icon: Icons.trending_up,      color: _teal,   gradientColors: const [Color(0xFF0BC5EA), Color(0xFF0891B2)]),
      _StatCardData(label: 'Total Loss (â‚¹)',     value: 'â‚¹${fmt.format(_stats?.totalLoss ?? 0)}', icon: Icons.trending_down,    color: _red,    gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
    ];

    return Container(
      width: double.infinity, color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth < 700) {
          return SingleChildScrollView(
            controller: _statsHScroll, scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0), child: _buildStatCard(e.value, compact: true))).toList()),
          );
        }
        return Row(children: cards.asMap().entries.map((e) => Expanded(child: Padding(padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0), child: _buildStatCard(e.value, compact: false)))).toList());
      }),
    );
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12), border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)), child: Icon(d.icon, color: Colors.white, size: 20)),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))]),
                child: Icon(d.icon, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(d.value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: d.color)),
              ])),
            ]),
    );
  }

  // â”€â”€ table â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScroll, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScroll, scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                  headingRowHeight: 52, dataRowMinHeight: 60, dataRowMaxHeight: 76,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) { if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04); return null; }),
                  dividerThickness: 1, columnSpacing: 18, horizontalMargin: 16,
                  columns: const [
                    DataColumn(label: SizedBox(width: 150, child: Text('ADJ NUMBER'))),
                    DataColumn(label: SizedBox(width: 115, child: Text('DATE'))),
                    DataColumn(label: SizedBox(width: 80,  child: Text('CURRENCY'))),
                    DataColumn(label: SizedBox(width: 100, child: Text('NEW RATE'))),
                    DataColumn(label: SizedBox(width: 90,  child: Text('TRANSACTIONS'))),
                    DataColumn(label: SizedBox(width: 120, child: Text('GAIN (â‚¹)'))),
                    DataColumn(label: SizedBox(width: 120, child: Text('LOSS (â‚¹)'))),
                    DataColumn(label: SizedBox(width: 130, child: Text('NET (â‚¹)'))),
                    DataColumn(label: SizedBox(width: 110, child: Text('STATUS'))),
                    DataColumn(label: SizedBox(width: 150, child: Text('ACTIONS'))),
                  ],
                  rows: _adjustments.map(_buildRow).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(CurrencyAdjustment a) {
    final fmt = NumberFormat('#,##0.00');
    return DataRow(cells: [
      DataCell(SizedBox(width: 150, child: InkWell(onTap: () => _viewDetail(a), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(a.adjustmentNumber, style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
        if (a.journalNumber != null) Text('J: ${a.journalNumber}', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      ])))),
      DataCell(SizedBox(width: 115, child: Text(DateFormat('dd MMM yyyy').format(a.adjustmentDate)))),
      DataCell(SizedBox(width: 80,  child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(a.currency, style: const TextStyle(color: _teal, fontWeight: FontWeight.w700, fontSize: 12))))),
      DataCell(SizedBox(width: 100, child: Text(a.newExchangeRate.toStringAsFixed(4), style: const TextStyle(fontWeight: FontWeight.w500)))),
      DataCell(SizedBox(width: 90,  child: Text(a.totalTransactions.toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)))),
      DataCell(SizedBox(width: 120, child: Text('â‚¹${fmt.format(a.totalGain)}',  style: const TextStyle(color: _green, fontWeight: FontWeight.w600)))),
      DataCell(SizedBox(width: 120, child: Text('â‚¹${fmt.format(a.totalLoss)}',  style: const TextStyle(color: _red,   fontWeight: FontWeight.w600)))),
      DataCell(SizedBox(width: 130, child: Text('â‚¹${fmt.format(a.netAdjustment)}', style: TextStyle(color: a.netAdjustment >= 0 ? _green : _red, fontWeight: FontWeight.bold)))),
      DataCell(SizedBox(width: 110, child: _statusBadge(a.status))),
      DataCell(SizedBox(width: 150, child: Row(children: [
        Tooltip(message: 'View Details', child: InkWell(onTap: () => _viewDetail(a), child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.visibility_outlined, size: 16, color: _blue)))),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (_) => [
            if (a.status == 'Draft') ...[
              _menuItem('edit',    Icons.edit_outlined,               _navy,   'Edit'),
              _menuItem('publish', Icons.publish_outlined,             _green,  'Publish'),
            ],
            if (a.status == 'Published')
              _menuItem('void',    Icons.block_outlined,               _red,    'Void', textColor: _red),
            _menuItem('ticket',    Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
            if (a.status == 'Draft')
              _menuItem('delete',  Icons.delete_outline,               _red,    'Delete', textColor: _red),
          ],
          onSelected: (v) {
            switch (v) {
              case 'edit':    _openEdit(a);   break;
              case 'publish': _publish(a);    break;
              case 'void':    _void(a);       break;
              case 'ticket':  _raiseTicket(a); break;
              case 'delete':  _delete(a);     break;
            }
          },
        ),
      ]))),
    ]);
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color iconColor, String label, {Color? textColor}) =>
    PopupMenuItem(value: value, child: ListTile(
      leading: Icon(icon, size: 17, color: iconColor),
      title: Text(label, style: TextStyle(color: textColor)),
      contentPadding: EdgeInsets.zero, dense: true,
    ));

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'Draft':     [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'Published': [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'Void':      [Color(0xFFFEE2E2), Color(0xFFDC2626)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  // â”€â”€ pagination â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) { pages = List.generate(_totalPages, (i) => i + 1); }
    else { final s = (_currentPage - 2).clamp(1, _totalPages - 4); pages = List.generate(5, (i) => s + i); }

    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: LayoutBuilder(builder: (_, c) => Wrap(
        alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
        children: [
          Text('Showing ${(_currentPage - 1) * _perPage + 1} - ${(_currentPage * _perPage).clamp(0, _total)} of $_total', style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); _loadData(); }),
            const SizedBox(width: 4),
            if (pages.first > 1) ...[_pageNumBtn(1), if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('...', style: TextStyle(color: Colors.grey[400])))],
            ...pages.map(_pageNumBtn),
            if (pages.last < _totalPages) ...[if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('...', style: TextStyle(color: Colors.grey[400]))), _pageNumBtn(_totalPages)],
            const SizedBox(width: 4),
            _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _loadData(); }),
          ]),
        ],
      )),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _loadData(); } },
      child: AnimatedContainer(duration: const Duration(milliseconds: 150), margin: const EdgeInsets.symmetric(horizontal: 2), width: 34, height: 34,
        decoration: BoxDecoration(color: isActive ? _navy : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? _navy : Colors.grey[300]!)),
        child: Center(child: Text('$page', style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.white : Colors.grey[700])))),
    );
  }

  Widget _pageNavBtn({ required IconData icon, required bool enabled, required VoidCallback onTap }) =>
    GestureDetector(onTap: enabled ? onTap : null, child: Container(width: 34, height: 34,
      decoration: BoxDecoration(color: enabled ? Colors.white : Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
      child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300])));

  // â”€â”€ empty / error â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildEmptyState() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _teal.withOpacity(0.06), shape: BoxShape.circle), child: Icon(Icons.currency_exchange, size: 64, color: _teal.withOpacity(0.4))),
    const SizedBox(height: 20),
    const Text('No Currency Adjustments Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Text('Create an adjustment to revalue open foreign currency transactions', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
    const SizedBox(height: 28),
    ElevatedButton.icon(onPressed: _openNew, icon: const Icon(Icons.add), label: const Text('New Adjustment', style: TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
  ])));

  Widget _buildErrorState() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle), child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
    const SizedBox(height: 20),
    const Text('Failed to Load Adjustments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center),
    const SizedBox(height: 28),
    ElevatedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
  ])));
}

// =============================================================================
// ADJUSTMENT DETAIL DIALOG
// =============================================================================

class _AdjustmentDetailDialog extends StatelessWidget {
  final CurrencyAdjustment adjustment;
  const _AdjustmentDetailDialog({ required this.adjustment });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final a   = adjustment;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 700,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(children: [
          // header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0891B2), Color(0xFF0369A1)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.currency_exchange, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.adjustmentNumber, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${a.currency} @ ${a.newExchangeRate.toStringAsFixed(4)} Â· ${DateFormat('dd MMM yyyy').format(a.adjustmentDate)}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
              ])),
              _statusBadge(a.status),
              const SizedBox(width: 8),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          // body
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // summary row
            Row(children: [
              Expanded(child: _infoCard('Total Gain', 'â‚¹${fmt.format(a.totalGain)}', Colors.green[700]!)),
              const SizedBox(width: 12),
              Expanded(child: _infoCard('Total Loss', 'â‚¹${fmt.format(a.totalLoss)}', Colors.red[700]!)),
              const SizedBox(width: 12),
              Expanded(child: _infoCard('Net Adjustment', 'â‚¹${fmt.format(a.netAdjustment)}', a.netAdjustment >= 0 ? Colors.green[700]! : Colors.red[700]!)),
              const SizedBox(width: 12),
              Expanded(child: _infoCard('Transactions', a.totalTransactions.toString(), const Color(0xFF0891B2))),
            ]),
            const SizedBox(height: 16),
            if (a.notes.isNotEmpty) Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber[200]!)),
              child: Row(children: [Icon(Icons.notes, color: Colors.amber[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(a.notes, style: TextStyle(color: Colors.amber[900])))]),
            ),
            if (a.notes.isNotEmpty) const SizedBox(height: 16),
            if (a.journalNumber != null) Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green[200]!)),
              child: Row(children: [Icon(Icons.book_outlined, color: Colors.green[700], size: 18), const SizedBox(width: 8), Text('Audit Journal: ${a.journalNumber}', style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w600))]),
            ),
            if (a.journalNumber != null) const SizedBox(height: 16),
            const Text('Transaction Lines', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (a.lineItems.isEmpty)
              Center(child: Text('No lines', style: TextStyle(color: Colors.grey[500])))
            else
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                headingRowHeight: 44, dataRowMinHeight: 48, dataRowMaxHeight: 56,
                columnSpacing: 16, horizontalMargin: 12,
                columns: const [
                  DataColumn(label: Text('TYPE')), DataColumn(label: Text('REF NUMBER')), DataColumn(label: Text('PARTY')),
                  DataColumn(label: Text('AMT DUE')), DataColumn(label: Text('OLD RATE')), DataColumn(label: Text('NEW RATE')), DataColumn(label: Text('GAIN/LOSS (â‚¹)')),
                ],
                rows: a.lineItems.map((l) => DataRow(cells: [
                  DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: l.transactionType == 'Invoice' ? Colors.blue[50] : Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                    child: Text(l.transactionType, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: l.transactionType == 'Invoice' ? Colors.blue[700] : Colors.orange[700])))),
                  DataCell(Text(l.transactionNumber, style: const TextStyle(fontWeight: FontWeight.w500))),
                  DataCell(Text(l.partyName, overflow: TextOverflow.ellipsis)),
                  DataCell(Text('${a.currency} ${fmt.format(l.amountDue)}')),
                  DataCell(Text(l.originalRate.toStringAsFixed(4))),
                  DataCell(Text(l.newRate.toStringAsFixed(4))),
                  DataCell(Text('â‚¹${fmt.format(l.gainLoss)}', style: TextStyle(fontWeight: FontWeight.w600, color: l.gainLoss >= 0 ? Colors.green[700] : Colors.red[700]))),
                ])).toList(),
              )),
            if (a.voidReason != null && a.voidReason!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red[200]!)),
                child: Row(children: [Icon(Icons.block_outlined, color: Colors.red[700], size: 18), const SizedBox(width: 8), Expanded(child: Text('Void reason: ${a.voidReason}', style: TextStyle(color: Colors.red[800])))]))
            ],
          ]))),
          // footer
          Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFF7F9FC), border: Border(top: BorderSide(color: Color(0xFFEEF2F7))), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0891B2), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Close')),
            ])),
        ]),
      ),
    );
  }

  Widget _infoCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{ 'Draft': [Color(0xFFFEF3C7), Color(0xFFB45309)], 'Published': [Color(0xFFDCFCE7), Color(0xFF15803D)], 'Void': [Color(0xFFFEE2E2), Color(0xFFDC2626)] };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(12)), child: Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 12)));
  }
}

// =============================================================================
// RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final CurrencyAdjustment adjustment;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({ required this.adjustment, required this.onTicketRaised, required this.onError });
  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _employees = [], _filtered = [];
  Map<String, dynamic>? _selectedEmp;
  bool _loading = true, _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() { super.initState(); _loadEmployees(); _searchCtrl.addListener(_filter); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() { _employees = List<Map<String, dynamic>>.from(resp['data']); _filtered = _employees; _loading = false; });
    } else { setState(() => _loading = false); widget.onError('Failed to load employees'); }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() { _filtered = q.isEmpty ? _employees : _employees.where((e) => (e['name_parson'] ?? '').toLowerCase().contains(q) || (e['email'] ?? '').toLowerCase().contains(q)).toList(); });
  }

  String _buildMessage() {
    final a = widget.adjustment;
    final fmt = NumberFormat('#,##0.00');
    return 'Currency Adjustment "${a.adjustmentNumber}" for ${a.currency} requires attention.\n\n'
           'Adjustment Details:\n'
           '* Currency   : ${a.currency}\n'
           '* New Rate   : ${a.newExchangeRate.toStringAsFixed(4)}\n'
           '* Date       : ${DateFormat('dd MMM yyyy').format(a.adjustmentDate)}\n'
           '* Status     : ${a.status}\n'
           '* Total Gain : â‚¹${fmt.format(a.totalGain)}\n'
           '* Total Loss : â‚¹${fmt.format(a.totalLoss)}\n'
           '* Net Adj    : â‚¹${fmt.format(a.netAdjustment)}\n'
           '* Transactions: ${a.totalTransactions}\n'
           '${a.notes.isNotEmpty ? '* Notes: ${a.notes}\n' : ''}\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: 'Currency Adjustment: ${widget.adjustment.adjustmentNumber}',
        message: _buildMessage(), priority: _priority, timeline: 1440,
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised('Ticket assigned to ${_selectedEmp!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else { widget.onError(resp['message'] ?? 'Failed to create ticket'); }
    } catch (e) { setState(() => _assigning = false); widget.onError('Failed: $e'); }
  }

  Widget _priorityBtn(String label, String current, Color color) {
    final isSel = current == label;
    return Expanded(child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _priority = label),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSel ? color : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSel ? color : Colors.grey[300]!),
            boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : [],
          ),
          child: Center(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700]))),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(width: 520, constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Adj: ${widget.adjustment.adjustmentNumber}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ])),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1e3a8a))),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
              child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5))),
            const SizedBox(height: 20),
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1e3a8a))),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              _priorityBtn('Low',    _priority, _green),
              _priorityBtn('Medium', _priority, _orange),
              _priorityBtn('High',   _priority, _red),
            ]),
            const SizedBox(height: 20),
            const Text('Assign To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1e3a8a))),
            const SizedBox(height: 8),
            TextField(controller: _searchCtrl, decoration: InputDecoration(hintText: 'Search employees...', prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]), filled: true, fillColor: const Color(0xFFF7F9FC), contentPadding: const EdgeInsets.symmetric(vertical: 0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF1e3a8a), width: 1.5)))),
            const SizedBox(height: 8),
            _loading
                ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: Color(0xFF1e3a8a))))
                : _filtered.isEmpty
                    ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 240),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                        child: ListView.separated(
                          shrinkWrap: true, itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                          itemBuilder: (_, i) {
                            final emp   = _filtered[i];
                            final isSel = _selectedEmp != null && _selectedEmp!['_id'] == emp['_id'];
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedEmp = isSel ? null : emp;
                                });
                              },
                              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), color: isSel ? const Color(0xFF1e3a8a).withOpacity(0.06) : Colors.transparent,
                                child: Row(children: [
                                  CircleAvatar(radius: 18, backgroundColor: isSel ? const Color(0xFF1e3a8a) : const Color(0xFF1e3a8a).withOpacity(0.10), child: Text((emp['name_parson'] ?? 'U')[0].toUpperCase(), style: TextStyle(color: isSel ? Colors.white : const Color(0xFF1e3a8a), fontWeight: FontWeight.bold, fontSize: 13))),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    if (emp['email'] != null) Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                  ])),
                                  if (isSel) const Icon(Icons.check_circle, color: Color(0xFF1e3a8a), size: 20),
                                ])));
                          },
                        )),
          ]))),
          Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFF7F9FC), border: Border(top: BorderSide(color: Color(0xFFEEF2F7))), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1e3a8a), foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFF1e3a8a).withOpacity(0.4), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _assigning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(_selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              )),
            ])),
        ]),
      ),
    );
  }
}

// =============================================================================
// BULK IMPORT DIALOG
// =============================================================================

class _BulkImportDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const _BulkImportDialog({ required this.onImportComplete });
  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  bool _downloading = false, _uploading = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final rows = <List<dynamic>>[
        ['Adjustment Number (auto if blank)', 'Adjustment Date* (YYYY-MM-DD)', 'Currency* (e.g. USD)', 'New Exchange Rate*', 'Notes*'],
        ['', '2025-06-30', 'USD', '84.50', 'End of quarter forex revaluation'],
        ['', '2025-06-30', 'EUR', '91.20', 'June month-end EUR adjustment'],
        ['--- INSTRUCTIONS ---', 'DELETE THIS ROW BEFORE UPLOADING', '* = required', 'Currency must not be INR', 'Notes are mandatory'],
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'currency_adjustments_import_template');
      setState(() => _downloading = false);
      _showSnack('Template downloaded!', _green);
    } catch (e) { setState(() => _downloading = false); _showSnack('Download failed: $e', _red); }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx','xls','csv'], allowMultiple: false, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file  = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) { _showSnack('Could not read file', _red); return; }
      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      final ext  = file.extension?.toLowerCase() ?? '';
      final rows = (ext == 'csv') ? _parseCSV(bytes) : _parseExcel(bytes);
      if (rows.length < 2) throw Exception('File needs header + at least one data row');

      final List<Map<String, dynamic>> valid = [];
      final List<String> errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 2).isEmpty || _sv(row, 2).startsWith('---')) continue;
        try {
          final currency = _sv(row, 2).toUpperCase();
          final dateStr  = _sv(row, 1);
          final rateStr  = _sv(row, 3);
          final notes    = _sv(row, 4);

          if (currency.isEmpty) throw Exception('Currency required');
          if (currency == 'INR') throw Exception('Cannot adjust INR (base currency)');
          if (dateStr.isEmpty)  throw Exception('Date required (YYYY-MM-DD)');
          DateTime.parse(dateStr);
          final rate = double.tryParse(rateStr);
          if (rate == null || rate <= 0) throw Exception('New Exchange Rate must be > 0');
          if (notes.isEmpty) throw Exception('Notes required');

          valid.add({ 'adjustmentNumber': _sv(row, 0).isNotEmpty ? _sv(row, 0) : null, 'adjustmentDate': dateStr, 'currency': currency, 'newExchangeRate': rate, 'notes': notes, 'lineItems': [], 'status': 'Draft' });
        } catch (e) { errors.add('Row ${i + 1}: $e'); }
      }

      if (valid.isEmpty) throw Exception('No valid rows found');

      final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${valid.length} adjustment(s) will be imported as Draft.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('${errors.length} row(s) skipped:', style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(constraints: const BoxConstraints(maxHeight: 120), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)), child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12, color: _red)))),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white), child: const Text('Import')),
        ],
      ));

      if (confirmed != true) { setState(() { _uploading = false; _fileName = null; }); return; }

      // Pass dummy bytes for import (server will use field data)
      final importResult = await CurrencyAdjustmentService.bulkImport(valid, bytes, file.name);
      setState(() {
        _uploading = false;
        _results   = { 'success': importResult['data']['successCount'], 'failed': importResult['data']['failedCount'], 'total': importResult['data']['totalProcessed'], 'errors': importResult['data']['errors'] ?? [] };
      });
      if ((_results!['success'] ?? 0) > 0) { _showSnack('âœ… ${_results!['success']} imported!', _green); await widget.onImportComplete(); }
      if ((_results!['failed'] ?? 0) > 0)  { _showSnack('âš  ${_results!['failed']} failed', _orange); }
    } catch (e) { setState(() { _uploading = false; _fileName = null; }); _showSnack('Import failed: $e', _red); }
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex = excel_pkg.Excel.decodeBytes(bytes);
    final sh = ex.tables.keys.first;
    return (ex.tables[sh]?.rows ?? []).map((row) => row.map((cell) {
      if (cell?.value == null) return '';
      if (cell!.value is excel_pkg.TextCellValue) return (cell.value as excel_pkg.TextCellValue).value;
      return cell.value;
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) =>
    utf8.decode(bytes, allowMalformed: true).split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).map(_parseCSVLine).toList();

  List<String> _parseCSVLine(String line) {
    final fields = <String>[]; final buf = StringBuffer(); bool inQ = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') { if (inQ && i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; } else { inQ = !inQ; } }
      else if (ch == ',' && !inQ) { fields.add(buf.toString().trim()); buf.clear(); }
      else { buf.write(ch); }
    }
    fields.add(buf.toString().trim());
    return fields.map((f) => f.startsWith('"') && f.endsWith('"') ? f.substring(1, f.length - 1) : f).toList();
  }

  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(width: MediaQuery.of(context).size.width > 600
          ? 560
          : MediaQuery.of(context).size.width * 0.92, padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
          const SizedBox(width: 14),
          const Text('Import Currency Adjustments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 24),
        _importStep(step: '1', color: _blue, icon: Icons.download_rounded, title: 'Download Template', subtitle: 'Get the Excel template with required columns and sample rows.', buttonLabel: _downloading ? 'Downloading...' : 'Download Template', onPressed: _downloading || _uploading ? null : _downloadTemplate),
        const SizedBox(height: 16),
        _importStep(step: '2', color: _green, icon: Icons.upload_rounded, title: 'Upload Filled File', subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).', buttonLabel: _uploading ? 'Processing...' : (_fileName != null ? 'Change File' : 'Select File'), onPressed: _downloading || _uploading ? null : _uploadFile),
        if (_fileName != null) ...[
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
            child: Row(children: [Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)))])),
        ],
        if (_results != null) ...[
          const Divider(height: 28),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              _resultRow('Total Processed',       '${_results!['total']}',   Colors.blue),
              const SizedBox(height: 6),
              _resultRow('Successfully Imported', '${_results!['success']}', _green),
              const SizedBox(height: 6),
              _resultRow('Failed',                '${_results!['failed']}',  _red),
              if ((_results!['errors'] as List).isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: _red)),
                const SizedBox(height: 6),
                Container(constraints: const BoxConstraints(maxHeight: 120), child: SingleChildScrollView(child: Text((_results!['errors'] as List).join('\n'), style: const TextStyle(fontSize: 12, color: _red)))),
              ],
            ])),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Close'))),
        ],
      ])),
    );
  }

  Widget _importStep({ required String step, required Color color, required IconData icon, required String title, required String subtitle, required String buttonLabel, required VoidCallback? onPressed }) {
    final circle = Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 4), Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600]))]);
    final button = ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 16), label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, disabledBackgroundColor: color.withOpacity(0.5), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 12), button]);
      }));
  }

  Widget _resultRow(String label, String value, Color color) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
    Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
  ]);
}
