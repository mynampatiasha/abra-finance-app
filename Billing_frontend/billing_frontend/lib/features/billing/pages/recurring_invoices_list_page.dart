// ============================================================================
// RECURRING INVOICES LIST PAGE
// - Credit Notes / Customers UI pattern (3-breakpoint top bar, gradient stat
//   cards, dark navy table, ellipsis pagination)
// - Import button  → BulkImportRecurringDialog (template download + upload +
//   row validation + loop createRecurringInvoice per row)
// - Export button  → Excel export
// - Raise Ticket   → top bar + each row PopupMenu → overlay card with
//                    employee search + assign + auto message
// - Share button   → share_plus (web + mobile)
// - WhatsApp       → url_launcher wa.me link (customer phone, web + mobile)
// ============================================================================
// File: lib/screens/billing/recurring_invoices_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/recurring_invoice_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_recurring_invoice.dart';

// ─── colour palette (same as customers_list_page) ────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);

// ─── small helper ─────────────────────────────────────────────────────────────
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

class RecurringInvoicesListPage extends StatefulWidget {
  const RecurringInvoicesListPage({Key? key}) : super(key: key);
  @override
  State<RecurringInvoicesListPage> createState() => _RecurringInvoicesListPageState();
}

class _RecurringInvoicesListPageState extends State<RecurringInvoicesListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<RecurringInvoice> _profiles = [];
  RecurringInvoiceStats? _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String   _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showAdvancedFilters = false;

  final List<String> _statusFilters = ['All','ACTIVE','PAUSED','STOPPED'];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  final int _itemsPerPage = 20;
  List<RecurringInvoice> _filtered = [];

  // ── selection ─────────────────────────────────────────────────────────────
  Set<int> _selectedRows = {};
  bool _selectAll = false;

  // ── scroll controllers ────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([_loadProfiles(), _loadStats()]);
  }

  Future<void> _loadProfiles() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final resp = await RecurringInvoiceService.getRecurringInvoices(limit: 1000);
      setState(() {
        _profiles  = resp.recurringInvoices;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await RecurringInvoiceService.getStats();
      setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _loadAll();
    _showSuccess('Data refreshed');
  }

  // ── filtering / search ────────────────────────────────────────────────────

  void _applyFilters() {
    setState(() {
      final q = _searchController.text.toLowerCase();
      _filtered = _profiles.where((p) {
        if (q.isNotEmpty &&
            !p.profileName.toLowerCase().contains(q) &&
            !p.customerName.toLowerCase().contains(q) &&
            !p.customerEmail.toLowerCase().contains(q)) return false;
        if (_selectedStatus != 'All' && p.status != _selectedStatus) return false;
        if (_fromDate != null && p.startDate.isBefore(_fromDate!)) return false;
        if (_toDate   != null && p.startDate.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();
      _totalPages  = (_filtered.length / _itemsPerPage).ceil().clamp(1, 9999);
      if (_currentPage > _totalPages) _currentPage = _totalPages;
      _selectedRows.clear();
      _selectAll = false;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus      = 'All';
      _fromDate            = null;
      _toDate              = null;
      _currentPage         = 1;
      _showAdvancedFilters = false;
    });
    _applyFilters();
  }

  bool get _hasAnyFilter =>
      _selectedStatus != 'All' || _fromDate != null || _toDate != null ||
      _searchController.text.isNotEmpty;

  List<RecurringInvoice> get _currentPageItems {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end   = (start + _itemsPerPage).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  // ── selection helpers ─────────────────────────────────────────────────────

  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      _selectedRows = _selectAll
          ? Set.from(List.generate(_currentPageItems.length, (i) => i))
          : {};
    });
  }

  void _toggleRow(int i) {
    setState(() {
      _selectedRows.contains(i) ? _selectedRows.remove(i) : _selectedRows.add(i);
      _selectAll = _selectedRows.length == _currentPageItems.length;
    });
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NewRecurringInvoiceScreen()));
    if (ok == true) _loadAll();
  }

  void _openEdit(RecurringInvoice p) async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewRecurringInvoiceScreen(recurringInvoiceId: p.id)));
    if (ok == true) _loadAll();
  }

  // ── profile actions ───────────────────────────────────────────────────────

  Future<void> _pause(RecurringInvoice p) async {
    try {
      await RecurringInvoiceService.pauseRecurringInvoice(p.id);
      _showSuccess('"${p.profileName}" paused');
      _loadAll();
    } catch (e) { _showError('Failed to pause: $e'); }
  }

  Future<void> _resume(RecurringInvoice p) async {
    try {
      await RecurringInvoiceService.resumeRecurringInvoice(p.id);
      _showSuccess('"${p.profileName}" resumed');
      _loadAll();
    } catch (e) { _showError('Failed to resume: $e'); }
  }

  Future<void> _stop(RecurringInvoice p) async {
    final ok = await _confirmDialog(
      title: 'Stop Profile',
      message: 'Permanently stop "${p.profileName}"? No future invoices will be generated.',
      confirmLabel: 'Stop',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await RecurringInvoiceService.stopRecurringInvoice(p.id);
      _showSuccess('"${p.profileName}" stopped');
      _loadAll();
    } catch (e) { _showError('Failed to stop: $e'); }
  }

  Future<void> _delete(RecurringInvoice p) async {
    final ok = await _confirmDialog(
      title: 'Delete Profile',
      message: 'Delete "${p.profileName}"? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await RecurringInvoiceService.deleteRecurringInvoice(p.id);
      _showSuccess('Profile deleted');
      _loadAll();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  Future<void> _generate(RecurringInvoice p) async {
    final ok = await _confirmDialog(
      title: 'Generate Invoice',
      message: 'Generate invoice now from "${p.profileName}"?',
      confirmLabel: 'Generate',
      confirmColor: _blue,
    );
    if (ok != true) return;
    try {
      final r = await RecurringInvoiceService.generateManualInvoice(p.id);
      _showSuccess('Invoice ${r.invoiceNumber} generated');
      _loadAll();
    } catch (e) { _showError('Failed to generate: $e'); }
  }

  Future<void> _viewChildInvoices(RecurringInvoice p) async {
    try {
      final r = await RecurringInvoiceService.getChildInvoices(p.id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => _ChildInvoicesDialog(profile: p, response: r),
      );
    } catch (e) { _showError('Failed to load child invoices: $e'); }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _shareProfile(RecurringInvoice p) async {
    final text = _buildShareText(p);
    try {
      await Share.share(text, subject: 'Recurring Profile: ${p.profileName}');
    } catch (e) {
      _showError('Share failed: $e');
    }
  }

  String _buildShareText(RecurringInvoice p) =>
      'Recurring Invoice Profile\n'
      '─────────────────────────\n'
      'Profile : ${p.profileName}\n'
      'Customer: ${p.customerName}\n'
      'Email   : ${p.customerEmail}\n'
      'Freq    : every ${p.repeatEvery} ${p.repeatUnit}(s)\n'
      'Amount  : ₹${p.totalAmount.toStringAsFixed(2)}\n'
      'Status  : ${p.status}\n'
      'Next    : ${DateFormat('dd MMM yyyy').format(p.nextInvoiceDate)}\n'
      'Generated: ${p.totalInvoicesGenerated} invoice(s)';

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(RecurringInvoice p) async {
    // customerEmail stored; phone not directly on RecurringInvoice model from
    // the backend.  We use customerEmail field; if a phone field is available
    // it can be substituted.  For now we show a snackbar to clarify and open
    // with a prompt if phone is available, else show info.
    //
    // NOTE: The RecurringInvoice model from the service does NOT include the
    // customer phone.  To make WhatsApp work we need to fetch the customer or
    // store phone on the profile.  We handle gracefully here:

    // Try to get phone from profile if it exists (future-proof)
    final phone = _extractPhone(p);
    if (phone.isEmpty) {
      _showError('Customer phone not available on this profile. '
                 'Add customerPhone field to the recurring invoice schema to enable WhatsApp.');
      return;
    }
    final msg = Uri.encodeComponent(
      'Hello ${p.customerName},\n\n'
      'This is a reminder regarding your recurring invoice profile '
      '"${p.profileName}".\n\n'
      'Amount: ₹${p.totalAmount.toStringAsFixed(2)}\n'
      'Next invoice date: ${DateFormat('dd MMM yyyy').format(p.nextInvoiceDate)}\n\n'
      'Please feel free to contact us for any queries.\n'
      'Thank you!',
    );
    final url = Uri.parse('https://wa.me/$phone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

String _extractPhone(RecurringInvoice p) {
  return p.customerPhone.isNotEmpty ? p.customerPhone : '';
}

  // ── raise ticket (overlay) ────────────────────────────────────────────────

  void _raiseTicket([RecurringInvoice? profile]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        profile: profile,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError: (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  void _handleExport() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Export Recurring Profiles', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.table_chart, color: _green),
            title: const Text('Excel (XLSX)'),
            onTap: () { Navigator.pop(context); _exportExcel(); },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _exportExcel() async {
    try {
      if (_filtered.isEmpty) { _showError('Nothing to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Profile Name','Customer','Email','Frequency','Next Invoice','Status','Amount','Generated','Mode'],
        ..._filtered.map((p) => [
          p.profileName, p.customerName, p.customerEmail,
          'Every ${p.repeatEvery} ${p.repeatUnit}(s)',
          DateFormat('dd/MM/yyyy').format(p.nextInvoiceDate),
          p.status,
          p.totalAmount.toStringAsFixed(2),
          p.totalInvoicesGenerated.toString(),
          p.invoiceCreationMode,
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'recurring_invoices');
      _showSuccess('✅ Excel downloaded (${_filtered.length} profiles)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportRecurringDialog(onImportComplete: _loadAll),
    );
  }

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!,
      ),
    );
    if (d != null) { setState(() => _fromDate = d); _applyFilters(); }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!,
      ),
    );
    if (d != null) { setState(() => _toDate = d); _applyFilters(); }
  }

  // ── snackbars ─────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    Color confirmColor = _navy,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Recurring Invoices'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          if (_showAdvancedFilters) _buildAdvancedFiltersBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _filtered.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _filtered.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 220),
    const SizedBox(width: 10),
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _applyFilters(); }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
        tooltip: 'Filters', color: _showAdvancedFilters ? _navy : const Color(0xFF7F8C8D),
        bg: _showAdvancedFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const Spacer(),
    _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _blue, _filtered.isEmpty ? null : _handleExport),
    const SizedBox(width: 8),
    _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 190),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _applyFilters(); }, tooltip: 'Clear', color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters), tooltip: 'Filters'),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _blue, _filtered.isEmpty ? null : _handleExport),
      const SizedBox(width: 8),
      _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _applyFilters(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters)),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _blue, _filtered.isEmpty ? null : _handleExport),
      const SizedBox(width: 6),
      _compactBtn('Ticket', _orange, () => _raiseTicket()),
    ])),
  ]);

  // ── advanced filters ──────────────────────────────────────────────────────

  Widget _buildAdvancedFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: LayoutBuilder(builder: (_, c) {
        final statusDD = _advDropdown(_selectedStatus, _statusFilters,
            (v) { setState(() { _selectedStatus = v!; _currentPage = 1; }); _applyFilters(); });
        final clearBtn = TextButton.icon(
          onPressed: _clearFilters,
          icon: const Icon(Icons.clear, size: 16),
          label: const Text('Clear All'),
          style: TextButton.styleFrom(foregroundColor: _red),
        );
        if (c.maxWidth < 700) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Filters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
            const SizedBox(height: 8),
            statusDD,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: clearBtn),
          ]);
        }
        return Row(children: [
          const Text('Filters:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(width: 12),
          SizedBox(width: 200, child: statusDD),
          const Spacer(),
          if (_hasAnyFilter) clearBtn,
        ]);
      }),
    );
  }

  Widget _advDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50)),
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── reusable widgets (identical to customers_list_page) ───────────────────

  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Profiles' : s))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFilters(); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search profiles, customers…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchController.clear(); setState(() => _currentPage = 1); _applyFilters(); })
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

  Widget _dateChip({required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? _navy.withOpacity(0.08) : const Color(0xFFF7F9FC),
          border: Border.all(color: isActive ? _navy : const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today, size: 15, color: isActive ? _navy : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: isActive ? _navy : Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  // ── stats cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final total     = _profiles.length;
    final active    = _profiles.where((p) => p.status == 'ACTIVE').length;
    final paused    = _profiles.where((p) => p.status == 'PAUSED').length;
    final stopped   = _profiles.where((p) => p.status == 'STOPPED').length;
    final generated = _profiles.fold<int>(0, (sum, p) => sum + p.totalInvoicesGenerated);

    final cards = [
      _StatCardData(label: 'Total Profiles', value: total.toString(), icon: Icons.repeat_rounded, color: _navy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Active', value: active.toString(), icon: Icons.check_circle_outline, color: _green, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Paused', value: paused.toString(), icon: Icons.pause_circle_outline, color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Stopped', value: stopped.toString(), icon: Icons.stop_circle_outlined, color: _red, gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'Total Generated', value: generated.toString(), icon: Icons.description_outlined, color: _purple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
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
          child: Padding(
            padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
            child: _buildStatCard(e.value, compact: false),
          ),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                child: Icon(d.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Icon(d.icon, color: Colors.white, size: 24),
              ),
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
    final items = _currentPageItems;
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
                  dividerThickness: 1, columnSpacing: 18, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E), onChanged: _toggleSelectAll))),
                    const DataColumn(label: SizedBox(width: 180, child: Text('PROFILE NAME'))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('CUSTOMER'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('FREQUENCY'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('NEXT INVOICE'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 80,  child: Text('GENERATED'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('AMOUNT'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('ACTIONS'))),
                  ],
                  rows: items.asMap().entries.map((e) => _buildRow(e.key, e.value)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(int index, RecurringInvoice p) {
    final isSel = _selectedRows.contains(index);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleRow(index))),

        // Profile name
        DataCell(SizedBox(width: 180, child: InkWell(
          onTap: () => _openEdit(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(p.profileName, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
            const SizedBox(height: 3),
            Text(p.invoiceCreationMode == 'auto_send' ? '🚀 Auto-Send' : '📝 Draft',
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ]),
        ))),

        // Customer
        DataCell(SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(p.customerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(p.customerEmail, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),

        // Frequency
        DataCell(SizedBox(width: 120, child: Text('Every ${p.repeatEvery} ${p.repeatUnit}(s)', style: const TextStyle(fontSize: 13)))),

        // Next invoice
        DataCell(SizedBox(width: 120, child: Text(DateFormat('dd MMM yyyy').format(p.nextInvoiceDate),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))),

        // Status
        DataCell(SizedBox(width: 100, child: _statusBadge(p.status))),

        // Generated count (clickable)
        DataCell(SizedBox(width: 80, child: InkWell(
          onTap: () => _viewChildInvoices(p),
          child: Text(p.totalInvoicesGenerated.toString(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _blue, decoration: TextDecoration.underline),
              textAlign: TextAlign.center),
        ))),

        // Amount
        DataCell(SizedBox(width: 110, child: Text('₹${p.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right))),

        // Actions
        DataCell(SizedBox(width: 130, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _shareProfile(p),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(p),
          //   child: Container(width: 32, height: 32,
          //       decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
          //       child: const Icon(Icons.chat, size: 16, color: Color(0xFF25D366))),
          // )),
          // const SizedBox(width: 4),
          // More
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('edit',          Icons.edit_outlined,               _blue,   'Edit'),
              _menuItem('generate',      Icons.add_circle_outline,          _green,  'Generate Invoice'),
              _menuItem('view_invoices', Icons.list_alt_outlined,           _navy,   'Child Invoices'),
              _menuItem('ticket',        Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
              if (p.status == 'ACTIVE')
                _menuItem('pause',  Icons.pause_outlined,       _orange, 'Pause'),
              if (p.status == 'PAUSED')
                _menuItem('resume', Icons.play_arrow_outlined,  _green,  'Resume'),
              _menuItem('stop',   Icons.stop_outlined,          _red,    'Stop', textColor: _red),
              _menuItem('delete', Icons.delete_outline,         _red,    'Delete', textColor: _red),
            ],
            onSelected: (v) {
              switch (v) {
                case 'edit':          _openEdit(p);           break;
                case 'generate':      _generate(p);           break;
                case 'view_invoices': _viewChildInvoices(p);  break;
                case 'ticket':        _raiseTicket(p);        break;
                case 'pause':         _pause(p);              break;
                case 'resume':        _resume(p);             break;
                case 'stop':          _stop(p);               break;
                case 'delete':        _delete(p);             break;
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
      title: Text(label, style: TextStyle(color: textColor)),
      contentPadding: EdgeInsets.zero, dense: true,
    ));
  }

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'ACTIVE':  [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'PAUSED':  [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'STOPPED': [Color(0xFFFEE2E2), Color(0xFFDC2626)],
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

  // ── pagination (same as customers_list_page) ──────────────────────────────

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final start = (_currentPage - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: LayoutBuilder(builder: (_, c) {
        return Wrap(
          alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
          children: [
            Text(
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _filtered.length)} of ${_filtered.length}'
              '${_filtered.length != _profiles.length ? ' (filtered from ${_profiles.length})' : ''}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); _applyFilters(); }),
              const SizedBox(width: 4),
              if (pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))),
              ],
              ...pages.map((p) => _pageNumBtn(p)),
              if (pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _applyFilters(); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _applyFilters(); } },
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
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(color: enabled ? Colors.white : Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
        child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ── empty / error states ──────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.repeat_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Recurring Profiles Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasAnyFilter ? 'Try adjusting your filters' : 'Create your first recurring profile', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasAnyFilter ? _clearFilters : _openNew,
        icon: Icon(_hasAnyFilter ? Icons.filter_list_off : Icons.add),
        label: Text(_hasAnyFilter ? 'Clear Filters' : 'Create Profile', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Profiles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _loadAll, icon: const Icon(Icons.refresh),
        label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final RecurringInvoice? profile;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.profile, required this.onTicketRaised, required this.onError});

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _employees     = [];
  List<Map<String, dynamic>> _filtered      = [];
  Map<String, dynamic>?       _selectedEmp;
  bool _loading   = true;
  bool _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(resp['data']);
        _filtered  = _employees;
        _loading   = false;
      });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty ? _employees : _employees.where((e) {
        return (e['name_parson'] ?? '').toLowerCase().contains(q) ||
               (e['email'] ?? '').toLowerCase().contains(q) ||
               (e['role'] ?? '').toLowerCase().contains(q);
      }).toList();
    });
  }

  String _buildTicketMessage() {
    if (widget.profile == null) {
      return 'A ticket has been raised and requires your attention.';
    }
    final p = widget.profile!;
    return 'Recurring Invoice Profile "${p.profileName}" for customer '
           '"${p.customerName}" (${p.customerEmail}) requires attention.\n\n'
           'Profile Details:\n'
           '• Frequency: Every ${p.repeatEvery} ${p.repeatUnit}(s)\n'
           '• Amount: ₹${p.totalAmount.toStringAsFixed(2)}\n'
           '• Status: ${p.status}\n'
           '• Next Invoice: ${DateFormat('dd MMM yyyy').format(p.nextInvoiceDate)}\n'
           '• Generated so far: ${p.totalInvoicesGenerated} invoice(s)\n\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: widget.profile != null
            ? 'Recurring Profile: ${widget.profile!.profileName}'
            : 'Recurring Invoices — Action Required',
        message:  _buildTicketMessage(),
        priority: _priority,
        timeline: 1440, // 24 hours default
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised('Ticket assigned to ${_selectedEmp!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else {
        widget.onError(resp['message'] ?? 'Failed to create ticket');
      }
    } catch (e) {
      setState(() => _assigning = false);
      widget.onError('Failed to assign ticket: $e');
    }
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
          // ── header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (widget.profile != null)
                  Text('Profile: ${widget.profile!.profileName}',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // ── body ────────────────────────────────────────────────────────
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Auto message preview
              if (widget.profile != null) ...[
                const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                  child: Text(_buildTicketMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5)),
                ),
                const SizedBox(height: 20),
              ],

              // Priority
              const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Row(children: ['Low', 'Medium', 'High'].map((pr) {
                final isSel = _priority == pr;
                final color = pr == 'High' ? _red : pr == 'Medium' ? _orange : _green;
                return Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _priority = pr),
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
                      child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700]))),
                    ),
                  ),
                ));
              }).toList()),

              const SizedBox(height: 20),

              // Employee search
              const Text('Assign To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
                  filled: true, fillColor: const Color(0xFFF7F9FC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),

              // Employee list
              _loading
                  ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _navy)))
                  : _filtered.isEmpty
                      ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                            itemBuilder: (_, i) {
                              final emp   = _filtered[i];
                              final isSel = _selectedEmp?['_id'] == emp['_id'];
                              return InkWell(
                                onTap: () => setState(() => _selectedEmp = isSel ? null : emp),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
                                      child: Text(
                                        (emp['name_parson'] ?? 'U')[0].toUpperCase(),
                                        style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (emp['email'] != null)
                                        Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                      if (emp['role'] != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                                          child: Text(emp['role'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy)),
                                        ),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ]),
                                ),
                              );
                            },
                          ),
                        ),
            ]),
          )),

          // ── footer ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FC),
              border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white,
                  disabledBackgroundColor: _navy.withOpacity(0.4),
                  elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _assigning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  BULK IMPORT RECURRING DIALOG
// =============================================================================

class BulkImportRecurringDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportRecurringDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportRecurringDialog> createState() => _BulkImportRecurringDialogState();
}

class _BulkImportRecurringDialogState extends State<BulkImportRecurringDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = <List<dynamic>>[
        // Headers
        [
          'Profile Name*',
          'Customer ID*',
          'Customer Name*',
          'Customer Email*',
          'Repeat Every* (number)',
          'Repeat Unit* (day/week/month/year)',
          'Start Date* (dd/MM/yyyy)',
          'End Date (dd/MM/yyyy or leave blank)',
          'Terms (Due on Receipt/Net 15/Net 30/Net 45/Net 60)',
          'Item Details*',
          'Quantity*',
          'Rate*',
          'GST Rate (default 18)',
          'Invoice Mode* (draft/auto_send)',
          'Auto Apply Payments (true/false)',
        ],
        // Example row
        [
          'Monthly Maintenance',
          '64f2a1b3e4c5d6789012ef01',
          'Acme Corporation',
          'billing@acme.com',
          '1',
          'month',
          '01/01/2025',
          '31/12/2025',
          'Net 30',
          'Monthly fleet maintenance service',
          '1',
          '5000',
          '18',
          'draft',
          'false',
        ],
        // Instructions
        [
          'INSTRUCTIONS:',
          '* = required fields',
          'Customer ID must be a valid MongoDB ObjectId from your system',
          'Dates in dd/MM/yyyy format',
          'Repeat Unit: day / week / month / year',
          'Invoice Mode: draft or auto_send',
          'Delete this instructions row before uploading',
        ],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'recurring_invoices_import_template');
      setState(() => _downloading = false);
      _showSnack('Template downloaded!', _green);
    } catch (e) {
      setState(() => _downloading = false);
      _showSnack('Download failed: $e', _red);
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file  = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) { _showSnack('Could not read file', _red); return; }

      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      List<List<dynamic>> rows;
      final ext = file.extension?.toLowerCase() ?? '';
      if (ext == 'csv') {
        rows = _parseCSV(bytes);
      } else {
        rows = _parseExcel(bytes);
      }

      if (rows.length < 2) throw Exception('File must contain header row + at least one data row');

      final List<Map<String, dynamic>> valid   = [];
      final List<String>               errors  = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty) continue;
        // Skip instruction row
        if (_sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors = <String>[];
        final profileName   = _sv(row, 0);
        final customerId    = _sv(row, 1);
        final customerName  = _sv(row, 2);
        final customerEmail = _sv(row, 3);
        final repeatEvery   = int.tryParse(_sv(row, 4)) ?? 0;
        final repeatUnit    = _sv(row, 5).toLowerCase();
        final startDateStr  = _sv(row, 6);
        final endDateStr    = _sv(row, 7);
        final terms         = _sv(row, 8, 'Net 30');
        final itemDetails   = _sv(row, 9);
        final qty           = double.tryParse(_sv(row, 10)) ?? 0;
        final rate          = double.tryParse(_sv(row, 11)) ?? 0;
        final gstRate       = double.tryParse(_sv(row, 12, '18')) ?? 18;
        final mode          = _sv(row, 13, 'draft');
        final autoApply     = _sv(row, 14, 'false').toLowerCase() == 'true';

        if (profileName.isEmpty)   rowErrors.add('Profile Name required');
        if (customerId.isEmpty)    rowErrors.add('Customer ID required');
        if (customerName.isEmpty)  rowErrors.add('Customer Name required');
        if (customerEmail.isEmpty) rowErrors.add('Customer Email required');
        if (repeatEvery <= 0)      rowErrors.add('Repeat Every must be > 0');
        if (!['day','week','month','year'].contains(repeatUnit)) rowErrors.add('Invalid Repeat Unit');
        if (itemDetails.isEmpty)   rowErrors.add('Item Details required');
        if (qty <= 0)              rowErrors.add('Quantity must be > 0');
        if (rate <= 0)             rowErrors.add('Rate must be > 0');
        if (!['draft','auto_send'].contains(mode)) rowErrors.add('Invalid Invoice Mode');

        DateTime? startDate;
        DateTime? endDate;
        try { startDate = DateFormat('dd/MM/yyyy').parse(startDateStr); } catch (_) { rowErrors.add('Invalid Start Date (use dd/MM/yyyy)'); }
        if (endDateStr.isNotEmpty) {
          try { endDate = DateFormat('dd/MM/yyyy').parse(endDateStr); } catch (_) { rowErrors.add('Invalid End Date'); }
        }

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        final amount = qty * rate;
        final subTotal = amount;
        final totalAmount = subTotal + (subTotal * gstRate / 100);

        final nextInvoiceDate = _calcNextDate(startDate!, repeatEvery, repeatUnit);

        valid.add({
          'profileName':         profileName,
          'customerId':          customerId,
          'customerName':        customerName,
          'customerEmail':       customerEmail,
          'repeatEvery':         repeatEvery,
          'repeatUnit':          repeatUnit,
          'startDate':           startDate.toIso8601String(),
          'endDate':             endDate?.toIso8601String(),
          'nextInvoiceDate':     nextInvoiceDate.toIso8601String(),
          'terms':               terms,
          'items': [{
            'itemDetails': itemDetails,
            'quantity':    qty,
            'rate':        rate,
            'discount':    0,
            'discountType': 'percentage',
            'amount':      amount,
          }],
          'gstRate':             gstRate,
          'invoiceCreationMode': mode,
          'autoApplyPayments':   autoApply,
          'autoApplyCreditNotes': false,
          'createdBy':           'import',
        });
      }

      if (valid.isEmpty) throw Exception('No valid rows found');

      // Confirm dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Import'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valid.length} profile(s) will be created.'),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${errors.length} row(s) skipped:', style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12))),
              ),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() { _uploading = false; _fileName = null; });
        return;
      }

      // Create profiles one by one via the existing POST endpoint
      int success = 0, failed = 0;
      final List<String> failedNames = [];
      for (final profile in valid) {
        try {
          await RecurringInvoiceService.createRecurringInvoice(profile);
          success++;
        } catch (e) {
          failed++;
          failedNames.add(profile['profileName'] ?? 'unknown');
        }
      }

      setState(() {
        _uploading = false;
        _results = {'success': success, 'failed': failed, 'total': valid.length, 'failedNames': failedNames};
      });

      if (success > 0) {
        _showSnack('✅ $success profile(s) imported!', _green);
        await widget.onImportComplete();
      }
      if (failed > 0) {
        _showSnack('⚠ $failed profile(s) failed to import', _orange);
      }

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
    }
  }

  DateTime _calcNextDate(DateTime from, int every, String unit) {
    switch (unit) {
      case 'day':   return from.add(Duration(days: every));
      case 'week':  return from.add(Duration(days: every * 7));
      case 'month': return DateTime(from.year, from.month + every, from.day);
      case 'year':  return DateTime(from.year + every, from.month, from.day);
      default:      return from.add(const Duration(days: 30));
    }
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex    = excel_pkg.Excel.decodeBytes(bytes);
    final sheet = ex.tables.keys.first;
    return (ex.tables[sheet]?.rows ?? []).map((row) => row.map((cell) {
      if (cell?.value == null) return '';
      if (cell!.value is excel_pkg.TextCellValue) return (cell.value as excel_pkg.TextCellValue).value;
      return cell.value;
    }).toList()).toList();
  }

  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true)
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .map(_parseCSVLine)
        .toList();
  }

  List<String> _parseCSVLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; }
        else { inQuotes = !inQuotes; }
      } else if (ch == ',' && !inQuotes) {
        fields.add(buf.toString().trim()); buf.clear();
      } else { buf.write(ch); }
    }
    fields.add(buf.toString().trim());
    return fields;
  }

  dynamic _gv(List<dynamic> row, int i) => i < row.length ? row[i] : null;
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
      child: Container(
        width: MediaQuery.of(context).size.width > 600
            ? 560
            : MediaQuery.of(context).size.width * 0.92,
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24),
            ),
            const SizedBox(width: 14),
            const Text('Import Recurring Profiles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),

          // Step 1
          _importStep(
            step: '1', color: _blue, icon: Icons.download_rounded,
            title: 'Download Template',
            subtitle: 'Get the Excel template with required columns and an example row.',
            buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
            onPressed: _downloading || _uploading ? null : _downloadTemplate,
          ),
          const SizedBox(height: 16),

          // Step 2
          _importStep(
            step: '2', color: _green, icon: Icons.upload_rounded,
            title: 'Upload Filled File',
            subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).',
            buttonLabel: _uploading ? 'Uploading…' : (_fileName != null ? 'Change File' : 'Select File'),
            onPressed: _downloading || _uploading ? null : _uploadFile,
          ),

          // Results
          if (_results != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.check_circle, color: _green, size: 18),
                  const SizedBox(width: 8),
                  Text('Successfully created: ${_results!['success']}'),
                ]),
                if ((_results!['failed'] ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.cancel, color: _red, size: 18),
                    const SizedBox(width: 8),
                    Text('Failed: ${_results!['failed']}', style: const TextStyle(color: _red)),
                  ]),
                ],
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _importStep({
    required String step, required Color color, required IconData icon,
    required String title, required String subtitle,
    required String buttonLabel, required VoidCallback? onPressed,
  }) {
    final circle = Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        disabledBackgroundColor: color.withOpacity(0.5),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 12), button]);
      }),
    );
  }
}

// =============================================================================
//  CHILD INVOICES DIALOG
// =============================================================================

class _ChildInvoicesDialog extends StatelessWidget {
  final RecurringInvoice profile;
  final ChildInvoicesResponse response;
  const _ChildInvoicesDialog({required this.profile, required this.response});

  Color _statusColor(String s) {
    switch (s) {
      case 'PAID':   return Colors.green;
      case 'DRAFT':  return Colors.grey;
      case 'UNPAID':
      case 'SENT':   return Colors.orange;
      case 'OVERDUE':return Colors.red;
      default:       return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Child Invoices — ${profile.profileName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: SizedBox(
        width: 600, height: 400,
        child: response.invoices.isEmpty
            ? const Center(child: Text('No invoices generated yet'))
            : ListView.builder(
                itemCount: response.invoices.length,
                itemBuilder: (_, i) {
                  final inv = response.invoices[i];
                  return ListTile(
                    leading: Icon(Icons.description, color: _statusColor(inv.status)),
                    title: Text(inv.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${DateFormat('dd MMM yyyy').format(inv.invoiceDate)} · ₹${inv.totalAmount.toStringAsFixed(2)}'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: _statusColor(inv.status).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(inv.status, style: TextStyle(color: _statusColor(inv.status), fontWeight: FontWeight.w600, fontSize: 11)),
                    ),
                  );
                },
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}