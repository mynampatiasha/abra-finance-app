// ============================================================================
// BUDGETS LIST PAGE
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat cards,
//   dark navy #0D1B3E table, drag-to-scroll, ellipsis pagination)
// - Share    → share_plus with budget details (web + mobile)
// - WhatsApp → wa.me/?text=<details> (no phone — user picks contact)
// - Raise Ticket → _RaiseTicketOverlay (employee search + assign)
// - Import   → 2-step dialog (download template + BudgetService.bulkImport)
// - Export   → Excel via ExportHelper
// ============================================================================
// File: lib/screens/billing/pages/budgets_list_page.dart
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/budget_service.dart';
import '../../../../core/services/tms_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'new_budget.dart';
import 'budget_detail.dart';

// ─── colour palette ───────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);

// ─── stat card data ───────────────────────────────────────────────────────────
class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label, required this.value,
    required this.icon,  required this.color,
    required this.gradientColors,
  });
}

// =============================================================================
//  MAIN PAGE
// =============================================================================

class BudgetsListPage extends StatefulWidget {
  const BudgetsListPage({Key? key}) : super(key: key);
  @override
  State<BudgetsListPage> createState() => _BudgetsListPageState();
}

class _BudgetsListPageState extends State<BudgetsListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<Budget>  _budgets = [];
  BudgetStats?  _stats;
  bool    _isLoading = true;
  String? _error;

  // ── filters ───────────────────────────────────────────────────────────────
  String _statusFilter = 'All';
  String _fyFilter     = 'All';
  String _periodFilter = 'All';

  static const _periods = ['All', 'Monthly', 'Quarterly', 'Yearly'];

  // ── search ────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _page       = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  static const int _pageSize = 20;

  // ── selection ─────────────────────────────────────────────────────────────
  final Set<String> _selected = {};
  bool _selectAll = false;

  // ── scroll ────────────────────────────────────────────────────────────────
  final _tableHScrollCtrl = ScrollController();
  final _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
    _searchCtrl.addListener(() {
      setState(() { _searchQuery = _searchCtrl.text; _page = 1; });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_searchQuery == _searchCtrl.text) _load();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      bool? isActive;
      if (_statusFilter == 'Active')   isActive = true;
      if (_statusFilter == 'Inactive') isActive = false;

      final res = await BudgetService.getBudgets(
        isActive:      isActive,
        financialYear: _fyFilter    == 'All' ? null : _fyFilter,
        budgetPeriod:  _periodFilter == 'All' ? null : _periodFilter,
        search:        _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        page:          _page,
        limit:         _pageSize,
      );
      setState(() {
        _budgets    = res.budgets;
        _totalPages = res.pages;
        _totalCount = res.total;
        _isLoading  = false;
        _selected.clear();
        _selectAll = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await BudgetService.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    _page = 1;
    await Future.wait([_load(), _loadStats()]);
    _showSuccess('Data refreshed');
  }

  // ── navigation ────────────────────────────────────────────────────────────

  Future<void> _goToNew() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const NewBudgetScreen()));
    if (ok == true) _refresh();
  }

  Future<void> _goToEdit(String id) async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => NewBudgetScreen(budgetId: id)));
    if (ok == true) _refresh();
  }

  void _goToDetail(String id) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BudgetDetailPage(budgetId: id)));
  }

  // ── budget actions ────────────────────────────────────────────────────────

  Future<void> _delete(Budget b) async {
    final ok = await _confirmDialog(
      title: 'Delete Budget',
      message: 'Delete "${b.budgetName}"? This cannot be undone.',
      confirmLabel: 'Delete', confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await BudgetService.deleteBudget(b.id);
      _showSuccess('"${b.budgetName}" deleted');
      _refresh();
    } catch (e) { _showError('Delete failed: $e'); }
  }

  Future<void> _toggle(Budget b) async {
    try {
      await BudgetService.toggleActive(b.id, !b.isActive);
      _showSuccess(b.isActive ? 'Budget deactivated' : 'Budget activated');
      _refresh();
    } catch (e) { _showError('Failed: $e'); }
  }

  Future<void> _clone(Budget b) async {
    final nameCtrl = TextEditingController(text: '${b.budgetName} (Copy)');
    final fyCtrl   = TextEditingController(text: _nextFY(b.financialYear));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clone Budget', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'New Budget Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: fyCtrl,
              decoration: const InputDecoration(labelText: 'Financial Year (e.g. 2026-27)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
              child: const Text('Clone')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BudgetService.cloneBudget(b.id, nameCtrl.text.trim(), fyCtrl.text.trim());
      _showSuccess('Budget cloned');
      _refresh();
    } catch (e) { _showError('Clone failed: $e'); }
  }

  String _nextFY(String fy) {
    final parts = fy.split('-');
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final ny = y + 1;
    return '$ny-${(ny + 1).toString().substring(2)}';
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _share(Budget b) async {
    final variance = b.totalBudgeted - b.totalActual;
    final text = 'Budget: ${b.budgetName}\n'
        '─────────────────────────\n'
        'Financial Year : ${b.financialYear}\n'
        'Period         : ${b.budgetPeriod}\n'
        'Currency       : ${b.currency}\n'
        'Status         : ${b.isActive ? 'Active' : 'Inactive'}\n'
        'Total Budgeted : ₹${_fmt(b.totalBudgeted)}\n'
        'Total Actual   : ₹${_fmt(b.totalActual)}\n'
        'Variance       : ${variance < 0 ? '-' : ''}₹${_fmt(variance.abs())}\n'
        'Accounts       : ${b.accountLines.length} account line(s)\n'
        '${b.notes != null && b.notes!.isNotEmpty ? 'Notes          : ${b.notes}\n' : ''}';
    try {
      await Share.share(text, subject: 'Budget: ${b.budgetName}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(Budget b) async {
    final variance = b.totalBudgeted - b.totalActual;
    final msg = Uri.encodeComponent(
      'Budget: ${b.budgetName}\n\n'
      'Financial Year : ${b.financialYear}\n'
      'Period         : ${b.budgetPeriod}\n'
      'Status         : ${b.isActive ? 'Active' : 'Inactive'}\n'
      'Total Budgeted : ₹${_fmt(b.totalBudgeted)}\n'
      'Total Actual   : ₹${_fmt(b.totalActual)}\n'
      'Variance       : ${variance < 0 ? '-' : ''}₹${_fmt(variance.abs())}\n'
      'Accounts       : ${b.accountLines.length} line(s)\n\n'
      'Please review and revert.',
    );
    // No phone — user selects contact in WhatsApp
    final url = Uri.parse('https://wa.me/?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket([Budget? b]) {
    showDialog(
      context: context, barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        budget: b,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError:        (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      _showSuccess('Preparing export…');
      final all = await BudgetService.getAllBudgets();
      if (all.isEmpty) { _showError('No data to export'); return; }
      final rows = <List<dynamic>>[
        ['Budget Name','Financial Year','Period','Currency','Status',
         'Total Budgeted','Total Actual','Variance','Account Count','Notes'],
        ...all.map((b) {
          final v = b.totalBudgeted - b.totalActual;
          return [
            b.budgetName, b.financialYear, b.budgetPeriod, b.currency,
            b.isActive ? 'Active' : 'Inactive',
            b.totalBudgeted.toStringAsFixed(2),
            b.totalActual.toStringAsFixed(2),
            v.toStringAsFixed(2),
            b.accountLines.length.toString(),
            b.notes ?? '',
          ];
        }),
      ];
      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'budgets_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
      _showSuccess('✅ Exported ${all.length} budgets');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(context: context, builder: (_) => _ImportDialog(onSuccess: _refresh));
  }

  // ── view process ──────────────────────────────────────────────────────────

  void _showProcessDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(children: [
          Center(child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85, maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: _navy,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
                  child: const Text('Budget — Process Flow',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                Expanded(child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(16),
                  child: InteractiveViewer(
                    panEnabled: true, minScale: 0.5, maxScale: 4.0,
                    child: Center(child: Image.asset('assets/budget.png', fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => _buildFallbackProcess())),
                  ),
                )),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.grey[100],
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                  child: Text('Tip: Pinch to zoom, drag to pan', style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center),
                ),
              ]),
            ),
          )),
          Positioned(top: 40, right: 40, child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 32),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.6), padding: const EdgeInsets.all(14)),
          )),
        ]),
      ),
    );
  }

  Widget _buildFallbackProcess() {
    final steps = [
      ('Create Budget', 'Set budget name, FY and period', Icons.add_chart, _blue),
      ('Add Account Lines', 'Link accounts and set monthly amounts', Icons.list_alt, _navy),
      ('Set Amounts', 'Monthly, quarterly or yearly targets', Icons.edit_calendar, _purple),
      ('Activate', 'Mark budget as active', Icons.check_circle, _green),
      ('Track Actuals', 'Compare budgeted vs actual from COA', Icons.compare_arrows, _teal),
      ('View Reports', 'Analyse variance and performance', Icons.bar_chart, _orange),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(children: steps.asMap().entries.map((e) {
        final idx = e.key; final s = e.value;
        return Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: s.$4.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: s.$4.withOpacity(0.3))),
            child: Row(children: [
              CircleAvatar(backgroundColor: s.$4, radius: 20, child: Icon(s.$3, color: Colors.white, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$1, style: TextStyle(fontWeight: FontWeight.bold, color: s.$4, fontSize: 14)),
                const SizedBox(height: 3),
                Text(s.$2, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              ])),
            ]),
          ),
          if (idx < steps.length - 1)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Icon(Icons.arrow_downward, color: Colors.grey[400])),
        ]);
      }).toList()),
    );
  }

  // ── filter helpers ────────────────────────────────────────────────────────

  bool get _hasFilters => _statusFilter != 'All' || _fyFilter != 'All' || _periodFilter != 'All' || _searchQuery.isNotEmpty;

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() { _statusFilter = 'All'; _fyFilter = 'All'; _periodFilter = 'All'; _searchQuery = ''; _page = 1; });
    _load();
  }

  List<String> _fyOptions() {
    final now  = DateTime.now();
    final base = now.month >= 4 ? now.year : now.year - 1;
    return List.generate(5, (i) {
      final y = base - 2 + i;
      return '$y-${(y + 1).toString().substring(2)}';
    });
  }

  // ── snackbars ─────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _confirmDialog({required String title, required String message, required String confirmLabel, Color confirmColor = _navy}) =>
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

  // ── formatters ────────────────────────────────────────────────────────────

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);
  String _fmtShort(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Budgets'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _error != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _budgets.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _budgets.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
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
    _fyDropdown(),
    const SizedBox(width: 8),
    _periodDropdown(),
    const SizedBox(width: 10),
    _searchField(width: 200),
    if (_hasFilters) ...[const SizedBox(width: 8), _clearBtn()],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    const Spacer(),
    _actionBtn('New Budget', Icons.add_rounded, _navy, _goToNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _exportExcel),
    const SizedBox(width: 8),
    _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(), const SizedBox(width: 8),
      _fyDropdown(), const SizedBox(width: 8),
      _searchField(width: 170),
      const Spacer(),
      if (_hasFilters) ...[_clearBtn(), const SizedBox(width: 6)],
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Budget', Icons.add_rounded, _navy, _goToNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _exportExcel),
      const SizedBox(width: 8),
      _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: _statusDropdown()),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _goToNew),
    ]),
    const SizedBox(height: 10),
    _searchField(width: double.infinity),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _fyDropdown(), const SizedBox(width: 6),
      _periodDropdown(), const SizedBox(width: 6),
      if (_hasFilters) ...[_clearBtn(), const SizedBox(width: 6)],
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog, tooltip: 'Process', color: _navy, bg: _navy.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _exportExcel),
      const SizedBox(width: 6),
      _compactBtn('Ticket', _orange, () => _raiseTicket()),
    ])),
  ]);

  // ── reusable widgets ──────────────────────────────────────────────────────

  Widget _statusDropdown() => _filterDrop(
    value: _statusFilter,
    items: ['All', 'Active', 'Inactive'],
    labels: ['All Budgets', 'Active', 'Inactive'],
    onChanged: (v) { setState(() { _statusFilter = v!; _page = 1; }); _load(); },
  );

  Widget _fyDropdown() => _filterDrop(
    value: _fyFilter,
    items: ['All', ..._fyOptions()],
    labels: ['All Years', ..._fyOptions()],
    onChanged: (v) { setState(() { _fyFilter = v!; _page = 1; }); _load(); },
  );

  Widget _periodDropdown() => _filterDrop(
    value: _periodFilter,
    items: _periods,
    labels: _periods.map((p) => p == 'All' ? 'All Periods' : p).toList(),
    onChanged: (v) { setState(() { _periodFilter = v!; _page = 1; }); _load(); },
  );

  Widget _filterDrop({
    required String value,
    required List<String> items,
    required List<String> labels,
    required void Function(String?) onChanged,
  }) => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
        items: List.generate(items.length, (i) => DropdownMenuItem(value: items[i], child: Text(labels[i]))),
        onChanged: onChanged,
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search budgets…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); })
            : null,
        filled: true, fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _clearBtn() => TextButton.icon(
    onPressed: _clearFilters,
    icon: const Icon(Icons.clear, size: 14),
    label: const Text('Clear', style: TextStyle(fontSize: 12)),
    style: TextButton.styleFrom(foregroundColor: _red, padding: const EdgeInsets.symmetric(horizontal: 8)),
  );

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
    return Tooltip(message: tooltip, child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(width: 42, height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color)),
    ));
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _compactBtn(String label, Color bg, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  // ── stats cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final cards = [
      _StatCardData(label: 'Total Budgets',  value: (_stats?.totalBudgets    ?? 0).toString(),    icon: Icons.account_balance_outlined,      color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Active',         value: (_stats?.activeBudgets   ?? 0).toString(),    icon: Icons.check_circle_outline,          color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Inactive',       value: (_stats?.inactiveBudgets ?? 0).toString(),    icon: Icons.pause_circle_outline,          color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Total Budgeted', value: '₹${_fmtShort(_stats?.totalBudgeted ?? 0)}', icon: Icons.account_balance_wallet_outlined, color: _blue,   gradientColors: const [Color(0xFF5DADE2), Color(0xFF2980B9)]),
      _StatCardData(label: 'Total Actual',   value: '₹${_fmtShort(_stats?.totalActual   ?? 0)}', icon: Icons.receipt_long_outlined,         color: _teal,   gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)]),
    ];

    return Container(
      width: double.infinity, color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl, scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(
              width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _buildStatCard(e.value, compact: true),
            )).toList()),
          );
        }
        return Row(children: cards.asMap().entries.map((e) => Expanded(
          child: Padding(padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0), child: _buildStatCard(e.value, compact: false)),
        )).toList());
      }),
    );
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                  child: Icon(d.icon, color: Colors.white, size: 20)),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: Icon(d.icon, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: d.color)),
              ])),
            ]),
    );
  }

  // ── table ─────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl, scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                  headingRowHeight: 52, dataRowMinHeight: 60, dataRowMaxHeight: 76,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 16, horizontalMargin: 14,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(
                      value: _selectAll,
                      fillColor: WidgetStateProperty.all(Colors.white),
                      checkColor: const Color(0xFF0D1B3E),
                      onChanged: (v) => setState(() {
                        _selectAll = v!;
                        if (_selectAll) _selected.addAll(_budgets.map((b) => b.id));
                        else _selected.clear();
                      }),
                    ))),
                    const DataColumn(label: SizedBox(width: 220, child: Text('BUDGET NAME'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('FINANCIAL YEAR'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('PERIOD'))),
                    const DataColumn(label: SizedBox(width: 80,  child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('TOTAL BUDGETED')), numeric: true),
                    const DataColumn(label: SizedBox(width: 120, child: Text('TOTAL ACTUAL')),   numeric: true),
                    const DataColumn(label: SizedBox(width: 120, child: Text('VARIANCE')),       numeric: true),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('ACCOUNTS'))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('ACTIONS'))),
                  ],
                  rows: _budgets.map((b) => _buildRow(b)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(Budget b) {
    final isSel    = _selected.contains(b.id);
    final variance = b.totalBudgeted - b.totalActual;
    final over     = variance < 0;

    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(SizedBox(width: 36, child: Checkbox(
          value: isSel,
          onChanged: (_) => setState(() {
            if (isSel) _selected.remove(b.id); else _selected.add(b.id);
            _selectAll = _selected.length == _budgets.length;
          }),
        ))),

        // Budget name
        DataCell(SizedBox(width: 220, child: InkWell(
          onTap: () => _goToDetail(b.id),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(b.budgetName, style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis, maxLines: 2),
            if (b.notes != null && b.notes!.isNotEmpty)
              Text(b.notes!, style: TextStyle(fontSize: 11, color: Colors.grey[500]), overflow: TextOverflow.ellipsis),
          ]),
        ))),

        // Financial Year
        DataCell(SizedBox(width: 110, child: Text(b.financialYear, style: const TextStyle(fontSize: 13)))),

        // Period
        DataCell(SizedBox(width: 100, child: _periodBadge(b.budgetPeriod))),

        // Status
        DataCell(SizedBox(width: 80, child: _statusBadge(b.isActive))),

        // Total Budgeted
        DataCell(SizedBox(width: 130, child: Text('₹${_fmt(b.totalBudgeted)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right))),

        // Total Actual
        DataCell(SizedBox(width: 120, child: Text('₹${_fmt(b.totalActual)}',
            style: TextStyle(fontSize: 13, color: Colors.teal[700]), textAlign: TextAlign.right))),

        // Variance
        DataCell(SizedBox(width: 120, child: Text(
          '${over ? '-' : ''}₹${_fmt(variance.abs())}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: over ? _red : _green),
          textAlign: TextAlign.right,
        ))),

        // Accounts
        DataCell(SizedBox(width: 90, child: Row(children: [
          Icon(Icons.list_alt, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text('${b.accountLines.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ]))),

        // Actions
        DataCell(SizedBox(width: 160, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _share(b),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.share, size: 15, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          Tooltip(message: 'WhatsApp', child: InkWell(
            onTap: () => _whatsApp(b),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.chat, size: 15, color: Color(0xFF25D366))),
          )),
          const SizedBox(width: 4),
          // View
          Tooltip(message: 'View Details', child: InkWell(
            onTap: () => _goToDetail(b.id),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.visibility_outlined, size: 15, color: _navy)),
          )),
          const SizedBox(width: 4),
          // More
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('edit',   Icons.edit_outlined,                 _orange,  'Edit'),
              _menuItem('clone',  Icons.copy_outlined,                 _purple,  'Clone'),
              _menuItem('toggle', b.isActive ? Icons.toggle_off : Icons.toggle_on,
                  b.isActive ? _orange : _green, b.isActive ? 'Deactivate' : 'Activate'),
              _menuItem('ticket', Icons.confirmation_number_outlined,  _orange,  'Raise Ticket'),
              _menuItem('delete', Icons.delete_outline,                _red,     'Delete', textColor: _red),
            ],
            onSelected: (v) {
              switch (v) {
                case 'edit':   _goToEdit(b.id);  break;
                case 'clone':  _clone(b);         break;
                case 'toggle': _toggle(b);        break;
                case 'ticket': _raiseTicket(b);   break;
                case 'delete': _delete(b);        break;
              }
            },
          ),
        ]))),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color iconColor, String label, {Color? textColor}) {
    return PopupMenuItem(value: value, child: ListTile(
      leading: Icon(icon, size: 17, color: iconColor),
      title: Text(label, style: TextStyle(color: textColor, fontSize: 13)),
      contentPadding: EdgeInsets.zero, dense: true,
    ));
  }

  Widget _statusBadge(bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (active ? _green : Colors.grey).withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: active ? _green : Colors.grey, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(active ? 'Active' : 'Inactive', style: TextStyle(color: active ? const Color(0xFF15803D) : Colors.grey[600], fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  Widget _periodBadge(String period) {
    const map = <String, List<Color>>{
      'Monthly':   [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'Quarterly': [Color(0xFFF3E8FF), Color(0xFF7E22CE)],
      'Yearly':    [Color(0xFFCCFBF1), Color(0xFF0F766E)],
    };
    final c = map[period] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Text(period, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  // ── pagination ────────────────────────────────────────────────────────────

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final start = (_page - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
        children: [
          Text('Showing ${((_page - 1) * _pageSize + 1).clamp(0, _totalCount)}–${(_page * _pageSize).clamp(0, _totalCount)} of $_totalCount budgets',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _pageNavBtn(icon: Icons.chevron_left, enabled: _page > 1, onTap: () { setState(() => _page--); _load(); }),
            const SizedBox(width: 4),
            if (pages.first > 1) ...[_pageNumBtn(1), if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400])))],
            ...pages.map((p) => _pageNumBtn(p)),
            if (pages.last < _totalPages) ...[if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))), _pageNumBtn(_totalPages)],
            const SizedBox(width: 4),
            _pageNavBtn(icon: Icons.chevron_right, enabled: _page < _totalPages, onTap: () { setState(() => _page++); _load(); }),
          ]),
        ],
      ),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _page == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _page = page); _load(); } },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2), width: 34, height: 34,
        decoration: BoxDecoration(color: isActive ? _navy : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? _navy : Colors.grey[300]!)),
        child: Center(child: Text('$page', style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.white : Colors.grey[700]))),
      ),
    );
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: enabled ? Colors.white : Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
          child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300])),
    );
  }

  // ── empty / error ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.account_balance_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Budgets Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasFilters ? 'Try adjusting your filters' : 'Create your first budget to get started', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasFilters ? _clearFilters : _goToNew,
        icon: Icon(_hasFilters ? Icons.filter_list_off : Icons.add),
        label: Text(_hasFilters ? 'Clear Filters' : 'New Budget', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Budgets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_error ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh),
          label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final Budget? budget;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.budget, required this.onTicketRaised, required this.onError});

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered  = [];
  Map<String, dynamic>?       _selectedEmp;
  bool _loading   = true;
  bool _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() { super.initState(); _loadEmployees(); _searchCtrl.addListener(_filter); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() { _employees = List<Map<String, dynamic>>.from(resp['data']); _filtered = _employees; _loading = false; });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() { _filtered = q.isEmpty ? _employees : _employees.where((e) =>
        (e['name_parson'] ?? '').toLowerCase().contains(q) || (e['email'] ?? '').toLowerCase().contains(q) || (e['role'] ?? '').toLowerCase().contains(q)).toList(); });
  }

  String _buildMessage() {
    if (widget.budget == null) return 'A ticket has been raised regarding a budget and requires your attention.';
    final b = widget.budget!;
    final v = b.totalBudgeted - b.totalActual;
    return 'Budget "${b.budgetName}" requires attention.\n\n'
        'Budget Details:\n'
        '• Budget Name    : ${b.budgetName}\n'
        '• Financial Year : ${b.financialYear}\n'
        '• Period         : ${b.budgetPeriod}\n'
        '• Status         : ${b.isActive ? 'Active' : 'Inactive'}\n'
        '• Total Budgeted : ₹${b.totalBudgeted.toStringAsFixed(2)}\n'
        '• Total Actual   : ₹${b.totalActual.toStringAsFixed(2)}\n'
        '• Variance       : ${v < 0 ? '-' : ''}₹${v.abs().toStringAsFixed(2)}\n'
        '• Accounts       : ${b.accountLines.length} line(s)\n'
        '${b.notes != null && b.notes!.isNotEmpty ? '• Notes          : ${b.notes}\n' : ''}'
        '\nPlease review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    widget.budget != null ? 'Budget: ${widget.budget!.budgetName}' : 'Budgets — Action Required',
        message:    _buildMessage(),
        priority:   _priority,
        timeline:   1440,
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised('Ticket assigned to ${_selectedEmp!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else { widget.onError(resp['message'] ?? 'Failed to create ticket'); }
    } catch (e) { setState(() => _assigning = false); widget.onError('Failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (widget.budget != null) Text('Budget: ${widget.budget!.budgetName}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          // Body
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.budget != null) ...[
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                  child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5))),
              const SizedBox(height: 20),
            ],
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
            const SizedBox(height: 8),
            Row(children: ['Low','Medium','High'].map((pr) {
              final isSel = _priority == pr;
              final color = pr == 'High' ? _red : pr == 'Medium' ? _orange : _green;
              return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: InkWell(
                onTap: () => setState(() => _priority = pr), borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: isSel ? color : Colors.white, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSel ? color : Colors.grey[300]!),
                        boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : []),
                    child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700])))),
              )));
            }).toList()),
            const SizedBox(height: 20),
            const Text('Assign To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
            const SizedBox(height: 8),
            TextField(controller: _searchCtrl, decoration: InputDecoration(
              hintText: 'Search employees…', prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
              filled: true, fillColor: const Color(0xFFF7F9FC), contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
            )),
            const SizedBox(height: 8),
            _loading
                ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _navy)))
                : _filtered.isEmpty
                    ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                        child: ListView.separated(
                          shrinkWrap: true, itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                          itemBuilder: (_, i) {
                            final emp = _filtered[i]; final isSel = _selectedEmp?['_id'] == emp['_id'];
                            return InkWell(
                              onTap: () => setState(() => _selectedEmp = isSel ? null : emp),
                              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(radius: 18, backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
                                        child: Text((emp['name_parson'] ?? 'U')[0].toUpperCase(), style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13))),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (emp['email'] != null) Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                      if (emp['role'] != null) Container(margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                                          child: Text(emp['role'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy))),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ])),
                            );
                          },
                        )),
          ]))),
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Color(0xFFF7F9FC), border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, disabledBackgroundColor: _navy.withOpacity(0.4), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _assigning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  IMPORT DIALOG — 2-step: download template + BudgetService.bulkImport
// =============================================================================

class _ImportDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  const _ImportDialog({required this.onSuccess});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _result;

  static const _monthLabels = ['Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec','Jan','Feb','Mar'];

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final header = [
        'Budget Name *', 'Financial Year * (e.g. 2025-26)',
        'Budget Period (Monthly/Quarterly/Yearly)',
        'Account Name *', 'Account Type',
        ..._monthLabels.map((m) => '$m Amount'),
        'Annual Amount (if monthly not given)', 'Notes',
      ];
      final data = <List<dynamic>>[
        header,
        ['FY 2025-26 Budget', '2025-26', 'Monthly', 'Sales', 'Income',
          50000, 55000, 60000, 65000, 70000, 75000, 80000, 85000, 90000, 95000, 100000, 110000, '', 'Revenue budget'],
        ['FY 2025-26 Budget', '2025-26', 'Monthly', 'Rent Expense', 'Expense',
          50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, 50000, '', 'Office rent'],
        ['FY 2025-26 Budget', '2025-26', 'Monthly', 'Salary Expense', 'Expense',
          '', '', '', '', '', '', '', '', '', '', '', '', 600000, 'Split equally across 12 months'],
        ['INSTRUCTIONS:', 'Delete rows 3-5 before importing',
          'Period: Monthly / Quarterly / Yearly',
          'Account Name must match your Chart of Accounts',
          'Account Type: Asset / Liability / Equity / Income / Expense',
          ..._monthLabels.map((_) => ''),
          'OR fill Annual Amount and leave monthly blank', ''],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'budget_import_template_${DateFormat('yyyyMMdd').format(DateTime.now())}');
      _snack('Template downloaded ✓', _green);
    } catch (e) { _snack('Download failed: $e', _red); }
    finally { setState(() => _downloading = false); }
  }

  Future<void> _pickAndImport() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      if (file.bytes == null) { _snack('Could not read file', _red); return; }
      setState(() { _uploading = true; _fileName = file.name; _result = null; });

      List<List<dynamic>> rows;
      final ext = (file.extension ?? '').toLowerCase();
      rows = ext == 'csv' ? _parseCSV(file.bytes!) : _parseExcel(file.bytes!);

      if (rows.length < 2) throw Exception('File must have a header row + at least one data row');

      final valid  = <Map<String, dynamic>>[];
      final errors = <String>[];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final budgetName  = _cell(row, 0);
        final fy          = _cell(row, 1);
        final period      = _cell(row, 2, 'Monthly');
        final accountName = _cell(row, 3);
        final accountType = _cell(row, 4, 'Expense');

        if (budgetName.isEmpty || budgetName.toUpperCase().contains('INSTRUCTION')) continue;
        if (fy.isEmpty)          { errors.add('Row ${i+1}: Financial Year required'); continue; }
        if (accountName.isEmpty) { errors.add('Row ${i+1}: Account Name required'); continue; }

        // Parse 12 monthly amounts (cols 5-16)
        List<double> monthly = List.generate(12, (m) {
          return double.tryParse(_cell(row, 5 + m).replaceAll(',', '')) ?? 0;
        });

        // Fallback to annual (col 17)
        final total = monthly.fold<double>(0, (a, b) => a + b);
        if (total == 0) {
          final annual = double.tryParse(_cell(row, 17).replaceAll(',', '')) ?? 0;
          if (annual > 0) monthly = List.filled(12, annual / 12);
        }

        valid.add({
          'budgetName':     budgetName,
          'financialYear':  fy,
          'budgetPeriod':   period,
          'accountName':    accountName,
          'accountType':    accountType,
          'monthlyAmounts': monthly,
          'notes':          _cell(row, 18),
        });
      }

      if (valid.isEmpty) { setState(() => _uploading = false); _snack('No valid rows found', _red); return; }

      // Confirm dialog
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${valid.length} account line(s) ready to import', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${errors.length} row(s) skipped', style: const TextStyle(color: _orange, fontSize: 13)),
            const SizedBox(height: 6),
            Container(constraints: const BoxConstraints(maxHeight: 100), padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(6)),
                child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 11, color: _red)))),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
              child: Text('Import ${valid.length} Lines')),
        ],
      ));

      if (ok != true) { setState(() { _uploading = false; _fileName = null; }); return; }

      final res = await BudgetService.bulkImport(valid, file.bytes!, file.name);
      setState(() { _uploading = false; _result = res['data']; });
      if (res['success'] == true) {
        _snack('✅ Import completed!', _green);
        widget.onSuccess();
      }
    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _snack('Import failed: $e', _red);
    }
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final book  = xl.Excel.decodeBytes(bytes);
    final sheet = book.tables[book.tables.keys.first];
    if (sheet == null) return [];
    return sheet.rows.map((row) => row.map((c) {
      if (c?.value == null) return '';
      if (c!.value is xl.TextCellValue)  return (c.value as xl.TextCellValue).value;
      if (c.value is xl.IntCellValue)    return (c.value as xl.IntCellValue).value.toString();
      if (c.value is xl.DoubleCellValue) return (c.value as xl.DoubleCellValue).value.toString();
      return c.value.toString();
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true)
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map((line) {
      final fields = <String>[]; final cur = StringBuffer(); bool inQ = false;
      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') { if (inQ && i+1 < line.length && line[i+1] == '"') { cur.write('"'); i++; } else inQ = !inQ; }
        else if (ch == ',' && !inQ) { fields.add(cur.toString().trim()); cur.clear(); }
        else cur.write(ch);
      }
      fields.add(cur.toString().trim());
      return fields;
    }).toList();
  }

  String _cell(List row, int i, [String def = '']) =>
      i < row.length ? (row[i]?.toString().trim() ?? def) : def;

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width > 600 ? 560 : MediaQuery.of(context).size.width * 0.92),
        child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
            const SizedBox(width: 14),
            const Expanded(child: Text('Bulk Import Budgets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 16),
          // Info
          Container(padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.info_outline, color: Colors.blue[700], size: 18), const SizedBox(width: 8), Text('How to Import', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[700]))]),
                const SizedBox(height: 8),
                Text('• One row per account line\n• Rows with same Budget Name = same budget\n• Account Name must match Chart of Accounts\n• Debit = Credit per budget\n• Accepted: .xlsx, .xls, .csv', style: TextStyle(fontSize: 13, color: Colors.blue[800], height: 1.6)),
              ])),
          const SizedBox(height: 18),
          // Step 1
          _importStep(step: '1', color: _green, icon: Icons.download_rounded,
              title: 'Download Template',
              subtitle: 'Get the Excel template with month-by-month columns.',
              buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
              onPressed: _downloading || _uploading ? null : _downloadTemplate),
          const SizedBox(height: 12),
          // Step 2
          _importStep(step: '2', color: _blue, icon: Icons.upload_rounded,
              title: 'Upload Filled File',
              subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).',
              buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'),
              onPressed: _downloading || _uploading ? null : _pickAndImport),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
                child: Row(children: [Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8),
                  Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)))])),
          ],
          if (_result != null) ...[
            const Divider(height: 24),
            Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  _resultRow('Total Processed',      '${_result!['totalProcessed'] ?? 0}', _blue),
                  const SizedBox(height: 6),
                  _resultRow('Successfully Imported', '${_result!['successCount']   ?? 0}', _green),
                  const SizedBox(height: 6),
                  _resultRow('Failed',                '${_result!['failedCount']    ?? 0}', _red),
                ])),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
            )),
          ],
        ])),
      ),
    );
  }

  Widget _importStep({required String step, required Color color, required IconData icon, required String title, required String subtitle, required String buttonLabel, required VoidCallback? onPressed}) {
    final circle = Container(width: 34, height: 34, decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
    final button = ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 15), label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, disabledBackgroundColor: color.withOpacity(0.5), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 10), button]);
      }),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
    ]);
  }
}