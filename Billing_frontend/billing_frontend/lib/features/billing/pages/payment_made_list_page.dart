// ============================================================================
// PAYMENT MADE LIST PAGE - Credit Notes / Recurring Invoices UI Pattern
// ============================================================================
// File: lib/features/admin/Billing/pages/payment_made_list_page.dart
//
// UI Pattern matches recurring_invoices_list_page.dart exactly:
// ✅ 3-breakpoint top bar (Desktop ≥1100 / Tablet 700–1100 / Mobile <700)
// ✅ 4 gradient stat cards with h-scroll on mobile
// ✅ Dark navy #0D1B3E table header, drag-to-scroll, visible scrollbar
// ✅ Ellipsis pagination, same empty/error states
// ✅ Color system: Navy #1e3a8a, Purple #9B59B6, Green #27AE60, Blue #2980B9
// ✅ Import → embedded BulkImportPaymentsDialog (2-step, no new page)
// ✅ Export → Excel
// ✅ Share button per row → share_plus (web + mobile)
// ✅ Raise Ticket → row popup → overlay card with employee list + assign
// ✅ All original functionality preserved
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/config/api_config.dart';
import '../../../../core/services/payment_made_service.dart';
import '../../../../core/services/tms_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'new_payment_made.dart';
import 'payment_made_detail_page.dart';

// ─── colour palette (matches recurring_invoices_list_page) ──────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);

// ─── stat card data ──────────────────────────────────────────────────────────
class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.gradientColors,
  });
}

// =============================================================================
//  MAIN PAGE
// =============================================================================

class PaymentMadeListPage extends StatefulWidget {
  const PaymentMadeListPage({Key? key}) : super(key: key);
  @override
  State<PaymentMadeListPage> createState() => _PaymentMadeListPageState();
}

class _PaymentMadeListPageState extends State<PaymentMadeListPage> {
  // ── data ──────────────────────────────────────────────────────────────────
  List<PaymentMade> _payments = [];
  PaymentMadeStats? _stats;
  bool    _isLoading = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String   _statusFilter = 'All';
  String?  _modeFilter;
  String?  _typeFilter;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showAdvancedFilters = false;

  static const _statusFilters = [
    'All', 'DRAFT', 'RECORDED', 'PARTIALLY_APPLIED', 'APPLIED', 'REFUNDED', 'VOIDED',
  ];
  static const _modeOptions = [
    'Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online', 'NEFT', 'RTGS', 'IMPS',
  ];
  static const _typeOptions = ['PAYMENT', 'ADVANCE', 'EXCESS'];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage = 1;
  int _totalPages  = 1;
  int _totalCount  = 0;
  static const int _pageSize = 20;

  // ── selection ─────────────────────────────────────────────────────────────
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  // ── scroll controllers ────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final res = await PaymentMadeService.getPayments(
        status:      _statusFilter == 'All' ? null : _statusFilter,
        paymentMode: _modeFilter,
        paymentType: _typeFilter,
        fromDate:    _fromDate,
        toDate:      _toDate,
        search:      _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        page:        _currentPage,
        limit:       _pageSize,
      );
      setState(() {
        _payments    = res.payments;
        _totalPages  = res.pagination.pages;
        _totalCount  = res.pagination.total;
        _isLoading   = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await PaymentMadeService.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    _currentPage = 1;
    await Future.wait([_load(), _loadStats()]);
    _showSuccess('Refreshed');
  }

  // ── navigation ────────────────────────────────────────────────────────────

  Future<void> _openNew() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NewPaymentMadeScreen()),
    );
    if (ok == true) _refresh();
  }

  Future<void> _openEdit(String id) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewPaymentMadeScreen(paymentId: id)),
    );
    if (ok == true) _refresh();
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _delete(PaymentMade p) async {
    final ok = await _confirmDialog(
      title: 'Delete ${p.paymentNumber}?',
      message: 'This cannot be undone. Only Draft/Recorded payments can be deleted.',
      confirmLabel: 'Delete',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await PaymentMadeService.deletePayment(p.id);
      _showSuccess('${p.paymentNumber} deleted');
      _refresh();
    } catch (e) { _showError('Delete failed: $e'); }
  }

  Future<void> _downloadPDF(PaymentMade p) async {
    try {
      _showSuccess('Generating PDF…');
      final url = await PaymentMadeService.downloadPDF(p.id);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      _showSuccess('PDF downloaded');
    } catch (e) { _showError('PDF failed: $e'); }
  }

  Future<void> _sharePayment(PaymentMade p) async {
    final text = 'Payment Made\n'
        '─────────────────────────\n'
        'Payment # : ${p.paymentNumber}\n'
        'Vendor    : ${p.vendorName}\n'
        'Date      : ${DateFormat('dd MMM yyyy').format(p.paymentDate)}\n'
        'Mode      : ${p.paymentMode}\n'
        'Type      : ${p.paymentType}\n'
        'Amount    : ₹${p.totalAmount.toStringAsFixed(2)}\n'
        'Applied   : ₹${p.amountApplied.toStringAsFixed(2)}\n'
        'Unused    : ₹${p.amountUnused.toStringAsFixed(2)}\n'
        'Status    : ${p.status}';
    try {
      await Share.share(text, subject: 'Payment: ${p.paymentNumber}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  Future<void> _whatsApp(PaymentMade p) async {
    try {
      _showSuccess('Looking up vendor phone…');
      final phone = await PaymentMadeService.getVendorPhone(p.id);

      if (phone.isEmpty) {
        _showError('Vendor phone not available. Please update the vendor profile.');
        return;
      }

      // Strip any non-digit characters except leading +
      final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');

      final msg = Uri.encodeComponent(
        'Hello ${p.vendorName},\n\n'
        'Payment ${p.paymentNumber} of ₹${p.totalAmount.toStringAsFixed(2)} '
        'via ${p.paymentMode} has been recorded on '
        '${DateFormat('dd MMM yyyy').format(p.paymentDate)}.\n\n'
        'Status: ${p.status}\n'
        'Thank you!',
      );

      final url = Uri.parse('https://wa.me/$cleaned?text=$msg');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showError('Could not open WhatsApp');
      }
    } catch (e) {
      _showError('Failed to fetch vendor phone: $e');
    }
  }

  void _raiseTicket(PaymentMade p) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        payment: p,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError: (msg) => _showError(msg),
      ),
    );
  }

  // ── filters ───────────────────────────────────────────────────────────────

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _statusFilter        = 'All';
      _modeFilter          = null;
      _typeFilter          = null;
      _fromDate            = null;
      _toDate              = null;
      _currentPage         = 1;
      _showAdvancedFilters = false;
      _searchQuery         = '';
    });
    _load();
  }

  bool get _hasAnyFilter =>
      _statusFilter != 'All' || _modeFilter != null || _typeFilter != null ||
      _fromDate != null || _toDate != null || _searchQuery.isNotEmpty;

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _handleExport() async {
    try {
      _showSuccess('Preparing export…');
      final all = await PaymentMadeService.getAllPayments();
      if (all.isEmpty) { _showError('Nothing to export'); return; }
      final rows = <List<dynamic>>[
        ['Payment #', 'Vendor', 'Email', 'Date', 'Mode', 'Type', 'Ref #',
         'Status', 'Amount', 'Sub Total', 'TDS', 'TCS', 'CGST', 'SGST',
         'Total', 'Applied', 'Unused', 'Refunded', 'Notes'],
        ...all.map((p) => [
          p.paymentNumber, p.vendorName, p.vendorEmail ?? '',
          DateFormat('dd/MM/yyyy').format(p.paymentDate),
          p.paymentMode, p.paymentType, p.referenceNumber ?? '', p.status,
          p.amount.toStringAsFixed(2), p.subTotal.toStringAsFixed(2),
          p.tdsAmount.toStringAsFixed(2), p.tcsAmount.toStringAsFixed(2),
          p.cgst.toStringAsFixed(2), p.sgst.toStringAsFixed(2),
          p.totalAmount.toStringAsFixed(2), p.amountApplied.toStringAsFixed(2),
          p.amountUnused.toStringAsFixed(2), p.totalRefunded.toStringAsFixed(2),
          p.notes ?? '',
        ]),
      ];
      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'payments_made_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
      );
      _showSuccess('✅ Excel downloaded (${all.length} payments)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportPaymentsDialog(onImportComplete: _refresh),
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
    if (d != null) { setState(() { _fromDate = d; _currentPage = 1; }); _load(); }
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
    if (d != null) { setState(() { _toDate = d; _currentPage = 1; }); _load(); }
  }

  // ── snackbars ─────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
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

  // ── detail dialog ─────────────────────────────────────────────────────────

  void _showDetail(PaymentMade p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaymentMadeDetailPage(payment: p)),
    ).then((result) { if (result == true) _refresh(); });
  }

  Widget _detailCard(String title, List<Widget> rows) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FA),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.grey[200]!),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navy)),
      const SizedBox(height: 10),
      ...rows,
    ]),
  );

  Widget _dRow(String label, String? value, {bool bold = false, Color? color}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
        Expanded(child: Text(value, style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          color: color ?? const Color(0xFF2C3E50),
        ))),
      ]),
    );
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Payments Made'),
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
                  : _payments.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _payments.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // ── TOP BAR ───────────────────────────────────────────────────────────────

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
    _dateChip(
      label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date',
      isActive: _fromDate != null, onTap: _pickFromDate,
    ),
    const SizedBox(width: 8),
    _dateChip(
      label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date',
      isActive: _toDate != null, onTap: _pickToDate,
    ),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, () {
        setState(() { _fromDate = null; _toDate = null; _currentPage = 1; });
        _load();
      }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(
      Icons.filter_list,
      () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
      tooltip: 'Filters',
      color: _showAdvancedFilters ? _navy : const Color(0xFF7F8C8D),
      bg: _showAdvancedFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1),
    ),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const Spacer(),
    _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _blue, _payments.isEmpty ? null : _handleExport),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 190),
      const SizedBox(width: 8),
      _dateChip(
        label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date',
        isActive: _fromDate != null, onTap: _pickFromDate,
      ),
      const SizedBox(width: 6),
      _dateChip(
        label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date',
        isActive: _toDate != null, onTap: _pickToDate,
      ),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () {
          setState(() { _fromDate = null; _toDate = null; _currentPage = 1; });
          _load();
        }, tooltip: 'Clear', color: _red, bg: Colors.red[50]!),
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
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _blue, _payments.isEmpty ? null : _handleExport),
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
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _dateChip(
          label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date',
          isActive: _fromDate != null, onTap: _pickFromDate,
        ),
        const SizedBox(width: 6),
        _dateChip(
          label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date',
          isActive: _toDate != null, onTap: _pickToDate,
        ),
        if (_fromDate != null || _toDate != null) ...[
          const SizedBox(width: 6),
          _iconBtn(Icons.close, () {
            setState(() { _fromDate = null; _toDate = null; _currentPage = 1; });
            _load();
          }, color: _red, bg: Colors.red[50]!),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters)),
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
        const SizedBox(width: 6),
        _compactBtn('Import', _purple, _handleImport),
        const SizedBox(width: 6),
        _compactBtn('Export', _blue, _payments.isEmpty ? null : _handleExport),
      ]),
    ),
  ]);

  // ── ADVANCED FILTERS ──────────────────────────────────────────────────────

  Widget _buildAdvancedFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: LayoutBuilder(builder: (_, c) {
        final modeDD = _advDropdown<String?>(
          _modeFilter,
          [null, ..._modeOptions],
          (v) { setState(() { _modeFilter = v; _currentPage = 1; }); _load(); },
          hint: 'All Modes',
          display: (v) => v ?? 'All Modes',
        );
        final typeDD = _advDropdown<String?>(
          _typeFilter,
          [null, ..._typeOptions],
          (v) { setState(() { _typeFilter = v; _currentPage = 1; }); _load(); },
          hint: 'All Types',
          display: (v) => v ?? 'All Types',
        );
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
            modeDD,
            const SizedBox(height: 8),
            typeDD,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: clearBtn),
          ]);
        }
        return Row(children: [
          const Text('Filters:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(width: 12),
          SizedBox(width: 180, child: modeDD),
          const SizedBox(width: 12),
          SizedBox(width: 160, child: typeDD),
          const Spacer(),
          if (_hasAnyFilter) clearBtn,
        ]);
      }),
    );
  }

  Widget _advDropdown<T>(
    T value,
    List<T> items,
    ValueChanged<T?> onChanged, {
    required String hint,
    required String Function(T) display,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE3EE)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50)),
          hint: Text(hint),
          items: items.map((i) => DropdownMenuItem<T>(value: i, child: Text(display(i)))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── REUSABLE WIDGETS (identical to recurring_invoices_list_page) ──────────

  Widget _statusDropdown() => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      border: Border.all(color: const Color(0xFFDDE3EE)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _statusFilter,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(
          value: s,
          child: Text(s == 'All' ? 'All Payments' : s.replaceAll('_', ' ')),
        )).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() { _statusFilter = v; _currentPage = 1; });
            _load();
          }
        },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search payment #, vendor, ref…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() { _searchQuery = ''; _currentPage = 1; });
                  _load();
                })
            : null,
        filled: true, fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
      onChanged: (v) {
        setState(() { _searchQuery = v; _currentPage = 1; });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_searchQuery == v) _load();
        });
      },
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _dateChip({required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? _navy.withOpacity(0.08) : const Color(0xFFF7F9FC),
          border: Border.all(color: isActive ? _navy : const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today, size: 15, color: isActive ? _navy : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? _navy : Colors.grey[600],
          )),
        ]),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    VoidCallback? onTap, {
    String tooltip = '',
    Color color = const Color(0xFF7F8C8D),
    Color bg = const Color(0xFFF1F1F1),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
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

  // ── STATS CARDS ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final totalPayments = _stats?.totalPayments ?? 0;
    final totalAmount   = _stats?.totalAmount   ?? 0.0;
    final totalApplied  = _stats?.totalApplied  ?? 0.0;
    final totalUnused   = _stats?.totalUnused   ?? 0.0;

    final cards = [
      _StatCardData(
        label: 'Total Payments', value: totalPayments.toString(),
        icon: Icons.payments_outlined, color: _navy,
        gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)],
      ),
      _StatCardData(
        label: 'Total Amount', value: '₹${_fmt(totalAmount)}',
        icon: Icons.account_balance_wallet_outlined, color: _green,
        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'Applied', value: '₹${_fmt(totalApplied)}',
        icon: Icons.check_circle_outline, color: _teal,
        gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)],
      ),
      _StatCardData(
        label: 'Unused', value: '₹${_fmt(totalUnused)}',
        icon: Icons.pending_outlined, color: _orange,
        gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)],
      ),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(
              width: 160,
              margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
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
      padding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(d.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: d.color), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
    );
  }

  // ── TABLE ─────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl,
          thumbVisibility: true, trackVisibility: true,
          thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
            ),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4,
                  ),
                  headingRowHeight: 52,
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 74,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1,
                  columnSpacing: 18,
                  horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(
                      value: _selectAll,
                      fillColor: WidgetStateProperty.all(Colors.white),
                      checkColor: const Color(0xFF0D1B3E),
                      onChanged: (v) {
                        setState(() {
                          _selectAll = v!;
                          if (_selectAll) _selectedIds.addAll(_payments.map((p) => p.id));
                          else _selectedIds.clear();
                        });
                      },
                    ))),
                    const DataColumn(label: SizedBox(width: 140, child: Text('PAYMENT #'))),
                    const DataColumn(label: SizedBox(width: 170, child: Text('VENDOR'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('DATE'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('MODE'))),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('TYPE'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('AMOUNT'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('APPLIED'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('UNUSED'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('ACTIONS'))),
                  ],
                  rows: _payments.map(_buildRow).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(PaymentMade p) {
    final isSel = _selectedIds.contains(p.id);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(Checkbox(value: isSel, onChanged: (_) {
          setState(() {
            isSel ? _selectedIds.remove(p.id) : _selectedIds.add(p.id);
            _selectAll = _selectedIds.length == _payments.length;
          });
        })),

        // Payment #
        DataCell(SizedBox(width: 140, child: InkWell(
          onTap: () => _showDetail(p),
          child: Text(p.paymentNumber, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
        ))),

        // Vendor
        DataCell(SizedBox(width: 170, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(p.vendorName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            if (p.vendorEmail != null && p.vendorEmail!.isNotEmpty)
              Text(p.vendorEmail!, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ))),

        // Date
        DataCell(SizedBox(width: 110, child: Text(
          DateFormat('dd MMM yyyy').format(p.paymentDate),
          style: const TextStyle(fontSize: 13),
        ))),

        // Mode
        DataCell(SizedBox(width: 110, child: Text(p.paymentMode, style: const TextStyle(fontSize: 13)))),

        // Type
        DataCell(SizedBox(width: 90, child: _typeBadge(p.paymentType))),

        // Status
        DataCell(SizedBox(width: 130, child: _statusBadge(p.status))),

        // Amount
        DataCell(SizedBox(width: 120, child: Text(
          '₹${_fmt(p.totalAmount)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ))),

        // Applied
        DataCell(SizedBox(width: 110, child: Text(
          '₹${_fmt(p.amountApplied)}',
          style: TextStyle(fontSize: 13, color: Colors.teal[700]),
        ))),

        // Unused
        DataCell(SizedBox(width: 110, child: Text(
          '₹${_fmt(p.amountUnused)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: p.amountUnused > 0.01 ? FontWeight.w600 : FontWeight.normal,
            color: p.amountUnused > 0.01 ? Colors.orange[700] : Colors.grey[500],
          ),
        ))),

        // Actions
        DataCell(SizedBox(width: 130, child: Row(children: [
          // Share button
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _sharePayment(p),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.share, size: 16, color: _blue),
            ),
          )),
          const SizedBox(width: 4),
          // WhatsApp button
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(p),
          //   child: Container(
          //     width: 32, height: 32,
          //     decoration: BoxDecoration(
          //       color: const Color(0xFF25D366).withOpacity(0.10),
          //       borderRadius: BorderRadius.circular(8),
          //     ),
          //     child: const Icon(Icons.chat, size: 16, color: Color(0xFF25D366)),
          //   ),
          // )),
          // const SizedBox(width: 4),
          // More popup
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (v) {
              switch (v) {
                case 'view':   _showDetail(p); break;
                case 'edit':   _openEdit(p.id); break;
                case 'pdf':    _downloadPDF(p); break;
                case 'ticket': _raiseTicket(p); break;
                case 'delete': _delete(p); break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('view',   Icons.visibility_outlined,              _blue,   'View Details'),
              _menuItem('edit',   Icons.edit_outlined,                    _orange, 'Edit Payment'),
              _menuItem('pdf',    Icons.picture_as_pdf_outlined,          _red,    'Download PDF'),
              _menuItem('ticket', Icons.confirmation_number_outlined,     _orange, 'Raise Ticket'),
              const PopupMenuDivider(),
              _menuItem('delete', Icons.delete_outline,                   _red,    'Delete', textColor: _red),
            ],
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

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'APPLIED':           [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'PARTIALLY_APPLIED': [Color(0xFFCCFBF1), Color(0xFF0F766E)],
      'RECORDED':          [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'REFUNDED':          [Color(0xFFF3E8FF), Color(0xFF7E22CE)],
      'VOIDED':            [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'DRAFT':             [Color(0xFFF1F5F9), Color(0xFF64748B)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    final displayLabel = status.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c[0],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c[1].withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(displayLabel, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  Widget _typeBadge(String type) {
    final colors = <String, List<Color>>{
      'ADVANCE': [const Color(0xFFF3E8FF), const Color(0xFF7E22CE)],
      'EXCESS':  [const Color(0xFFFEF3C7), const Color(0xFFB45309)],
      'PAYMENT': [const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)],
    };
    final c = colors[type] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(6)),
      child: Text(type, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  // ── PAGINATION (same as recurring_invoices_list_page) ─────────────────────

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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
      ),
      child: LayoutBuilder(builder: (_, c) {
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            Text(
              'Showing ${((_currentPage - 1) * _pageSize + 1).clamp(0, _totalCount)}'
              '–${(_currentPage * _pageSize).clamp(0, _totalCount)} of $_totalCount',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1,
                  onTap: () { setState(() => _currentPage--); _load(); }),
              const SizedBox(width: 4),
              if (pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text('…', style: TextStyle(color: Colors.grey[400]))),
              ],
              ...pages.map((p) => _pageNumBtn(p)),
              if (pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text('…', style: TextStyle(color: Colors.grey[400]))),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages,
                  onTap: () { setState(() => _currentPage++); _load(); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _load(); } },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: isActive ? _navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? _navy : Colors.grey[300]!),
        ),
        child: Center(child: Text('$page', style: TextStyle(
          fontSize: 13,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive ? Colors.white : Colors.grey[700],
        ))),
      ),
    );
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ── EMPTY / ERROR ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.payments_outlined, size: 64, color: _navy.withOpacity(0.4)),
        ),
        const SizedBox(height: 20),
        const Text('No Payments Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
        const SizedBox(height: 8),
        Text(
          _hasAnyFilter ? 'Try adjusting your filters' : 'Record your first payment',
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _hasAnyFilter ? _clearFilters : _openNew,
          icon: Icon(_hasAnyFilter ? Icons.filter_list_off : Icons.add),
          label: Text(_hasAnyFilter ? 'Clear Filters' : 'Record Payment',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    )));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400]),
        ),
        const SizedBox(height: 20),
        const Text('Failed to Load Payments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_errorMessage ?? 'Unknown error',
              style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    )));
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final PaymentMade payment;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({
    required this.payment,
    required this.onTicketRaised,
    required this.onError,
  });

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
    try {
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
    } catch (e) {
      setState(() => _loading = false);
      widget.onError('Failed to load employees: $e');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty ? _employees : _employees.where((e) =>
        (e['name_parson'] ?? '').toLowerCase().contains(q) ||
        (e['email'] ?? '').toLowerCase().contains(q) ||
        (e['role'] ?? '').toLowerCase().contains(q)
      ).toList();
    });
  }

  String _buildTicketMessage() {
    final p = widget.payment;
    return 'Payment Made "${p.paymentNumber}" for vendor "${p.vendorName}" requires attention.\n\n'
        'Payment Details:\n'
        '• Date: ${DateFormat('dd MMM yyyy').format(p.paymentDate)}\n'
        '• Mode: ${p.paymentMode}\n'
        '• Type: ${p.paymentType}\n'
        '• Amount: ₹${p.totalAmount.toStringAsFixed(2)}\n'
        '• Applied: ₹${p.amountApplied.toStringAsFixed(2)}\n'
        '• Unused: ₹${p.amountUnused.toStringAsFixed(2)}\n'
        '• Status: ${p.status}\n\n'
        'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: 'Payment: ${widget.payment.paymentNumber} — ${widget.payment.vendorName}',
        message:  _buildTicketMessage(),
        priority: _priority,
        timeline: 1440,
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
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
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
                Text('Payment: ${widget.payment.paymentNumber}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Body
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Message preview
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDDE3EE)),
                ),
                child: Text(_buildTicketMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5)),
              ),
              const SizedBox(height: 20),

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
                      child: Center(child: Text(pr, style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: isSel ? Colors.white : Colors.grey[700],
                      ))),
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
                      ? Container(height: 80, alignment: Alignment.center,
                          child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFDDE3EE)),
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                                        style: TextStyle(
                                          color: isSel ? Colors.white : _navy,
                                          fontWeight: FontWeight.bold, fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(emp['name_parson'] ?? 'Unknown',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (emp['email'] != null)
                                        Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                            overflow: TextOverflow.ellipsis),
                                      if (emp['role'] != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _navy.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(emp['role'].toString().toUpperCase(),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy)),
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

          // Footer
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
//  BULK IMPORT PAYMENTS DIALOG — embedded, no new page
// =============================================================================

class BulkImportPaymentsDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportPaymentsDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportPaymentsDialog> createState() => _BulkImportPaymentsDialogState();
}

class _BulkImportPaymentsDialogState extends State<BulkImportPaymentsDialog> {
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
          'Vendor Name *',
          'Vendor Email *',
          'Payment Date * (dd/MM/yyyy)',
          'Payment Mode * (Cash/Cheque/Bank Transfer/UPI/Card/Online/NEFT/RTGS/IMPS)',
          'Payment Type (PAYMENT/ADVANCE/EXCESS)',
          'Reference Number',
          'Amount *',
          'Notes',
          'Bill Number (apply to)',
          'Bill Amount Applied',
        ],
        // Example row 1
        [
          'ABC Supplies Ltd', 'accounts@abc.com', '01/03/2025',
          'Bank Transfer', 'PAYMENT', 'NEFT-2025-001',
          '75000.00', 'March payment', 'BILL-2503-0001', '75000.00',
        ],
        // Example row 2
        [
          'XYZ Logistics', 'billing@xyz.com', '15/03/2025',
          'UPI', 'ADVANCE', 'UPI-98765',
          '25000.00', 'Advance for April', '', '',
        ],
        // Instructions
        [
          'INSTRUCTIONS:',
          '* = required fields',
          'Date format: dd/MM/yyyy',
          'Modes: Cash/Cheque/Bank Transfer/UPI/Card/Online/NEFT/RTGS/IMPS',
          'Types: PAYMENT/ADVANCE/EXCESS',
          'Bill Number and Amount Applied are optional — link payment to bill',
          'Delete this instructions row before uploading',
        ],
      ];
      await ExportHelper.exportToExcel(
        data: data,
        filename: 'payments_made_import_template',
      );
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

      final List<Map<String, dynamic>> valid  = [];
      final List<String>               errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty) continue;
        if (_sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors   = <String>[];
        final vendorName  = _sv(row, 0);
        final vendorEmail = _sv(row, 1);
        final dateStr     = _sv(row, 2);
        final mode        = _sv(row, 3, 'Bank Transfer');
        final type        = _sv(row, 4, 'PAYMENT').toUpperCase();
        final refNum      = _sv(row, 5);
        final amountStr   = _sv(row, 6);
        final notes       = _sv(row, 7);
        final billNum     = _sv(row, 8);
        final billAmtStr  = _sv(row, 9);

        if (vendorName.isEmpty)  rowErrors.add('Vendor Name required');
        if (vendorEmail.isEmpty) rowErrors.add('Vendor Email required');

        DateTime? date;
        try {
          date = DateFormat('dd/MM/yyyy').parse(dateStr);
        } catch (_) { rowErrors.add('Invalid date "$dateStr" (use dd/MM/yyyy)'); }

        final amount = double.tryParse(amountStr.replaceAll(',', ''));
        if (amount == null || amount <= 0) rowErrors.add('Invalid amount "$amountStr"');

        const validModes = ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online', 'NEFT', 'RTGS', 'IMPS'];
        if (!validModes.any((m) => m.toLowerCase() == mode.toLowerCase())) {
          rowErrors.add('Invalid mode "$mode"');
        }

        if (rowErrors.isNotEmpty) {
          errors.add('Row ${i + 1}: ${rowErrors.join(', ')}');
          continue;
        }

        valid.add({
          'vendorName': vendorName,
          'vendorEmail': vendorEmail,
          'paymentDate': date!.toIso8601String(),
          'paymentMode': mode,
          'paymentType': type,
          'referenceNumber': refNum,
          'amount': amount,
          'notes': notes,
          'status': 'RECORDED',
          'billsApplied': billNum.isNotEmpty
              ? [{
                  'billNumber':    billNum,
                  'amountApplied': double.tryParse(billAmtStr.replaceAll(',', '')) ?? 0,
                }]
              : [],
        });
      }

      if (valid.isEmpty && errors.isNotEmpty) {
        setState(() { _uploading = false; _fileName = null; });
        _showSnack('No valid rows found. ${errors.length} row(s) had errors.', _red);
        return;
      }

      if (valid.isEmpty) throw Exception('No valid rows found');

      // Confirm dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${valid.length} payment(s) will be imported.',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('${errors.length} row(s) skipped:',
                    style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: SingleChildScrollView(
                    child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12, color: _red)),
                  ),
                ),
              ],
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white),
              child: Text('Import ${valid.length} Payments'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        setState(() { _uploading = false; _fileName = null; });
        return;
      }

      // Import via existing bulkImport method in PaymentMadeService
      // The backend POST /bulk-import expects multipart with paymentsData field
      final res = await PaymentMadeService.bulkImport(valid, bytes, file.name);

      setState(() {
        _uploading = false;
        _results   = res['data'] ?? {'successCount': 0, 'failedCount': 0, 'totalProcessed': 0};
      });

      final successCount = _results!['successCount'] ?? 0;
      final failedCount  = _results!['failedCount'] ?? 0;

      if (successCount > 0) {
        _showSnack('✅ $successCount payment(s) imported!', _green);
        await widget.onImportComplete();
      }
      if (failedCount > 0) {
        _showSnack('⚠ $failedCount payment(s) failed', _orange);
      }

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
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

  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
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
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24),
            ),
            const SizedBox(width: 14),
            const Text('Import Payments Made', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),

          // Step 1 — Download template
          _importStep(
            step: '1',
            color: _blue,
            icon: Icons.download_rounded,
            title: 'Download Template',
            subtitle: 'Get the Excel template with required columns and an example row.',
            buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
            onPressed: _downloading || _uploading ? null : _downloadTemplate,
          ),
          const SizedBox(height: 16),

          // Step 2 — Upload file
          _importStep(
            step: '2',
            color: _green,
            icon: Icons.upload_rounded,
            title: 'Upload Filled File',
            subtitle: 'Fill the template and upload (XLSX / XLS / CSV).',
            buttonLabel: _uploading
                ? 'Processing…'
                : (_fileName != null ? 'Change File' : 'Select File'),
            onPressed: _downloading || _uploading ? null : _uploadFile,
          ),

          // File name indicator
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_fileName!, style: TextStyle(
                  color: Colors.green[700], fontWeight: FontWeight.w600, fontSize: 13,
                ), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ],

          // Results
          if (_results != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                _resultRow('Total Processed', _results!['totalProcessed']?.toString() ?? '0', Colors.blue),
                const SizedBox(height: 6),
                _resultRow('Successfully Imported', _results!['successCount']?.toString() ?? '0', _green),
                if ((_results!['failedCount'] ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  _resultRow('Failed', _results!['failedCount']?.toString() ?? '0', _red),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
            )),
          ],
        ]),
      ),
    );
  }

  Widget _importStep({
    required String step,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback? onPressed,
  }) {
    final circle = Container(
      width: 36, height: 36,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: Text(step,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
    );
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
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
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

  Widget _resultRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    ]);
  }
}