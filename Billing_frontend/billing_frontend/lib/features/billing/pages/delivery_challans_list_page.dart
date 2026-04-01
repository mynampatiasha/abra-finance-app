// ============================================================================
// DELIVERY CHALLANS LIST PAGE
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat cards,
//   dark navy table, ellipsis pagination, drag-to-scroll)
// - Import button  → BulkImportChallansDialog (template download + upload +
//   row validation + createDeliveryChallan per row)
// - Export button  → Excel export
// - Raise Ticket   → top bar + each row PopupMenu → overlay card with
//                    employee search + assign + auto message
// - Share button   → share_plus (web + mobile)
// - WhatsApp       → url_launcher wa.me link (customerPhone, web + mobile)
// ============================================================================
// File: lib/screens/billing/delivery_challans_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/delivery_challan_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_delivery_challan.dart';
import 'delivery_challan_detail_page.dart';

// ─── colour palette (same as recurring_invoices_list_page) ───────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);

// ─── stat card data helper ────────────────────────────────────────────────────
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

class DeliveryChallansListPage extends StatefulWidget {
  const DeliveryChallansListPage({Key? key}) : super(key: key);
  @override
  State<DeliveryChallansListPage> createState() => _DeliveryChallansListPageState();
}

class _DeliveryChallansListPageState extends State<DeliveryChallansListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<DeliveryChallan> _challans = [];
  ChallanStats? _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String   _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showAdvancedFilters = false;

  final List<String> _statusFilters = [
    'All', 'DRAFT', 'OPEN', 'DELIVERED', 'INVOICED',
    'PARTIALLY_INVOICED', 'RETURNED', 'PARTIALLY_RETURNED', 'CANCELLED',
  ];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  final int _itemsPerPage = 20;
  List<DeliveryChallan> _filtered = [];

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
    await Future.wait([_loadChallans(), _loadStats()]);
  }

  Future<void> _loadChallans() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final resp = await DeliveryChallanService.getDeliveryChallans(limit: 1000);
      setState(() {
        _challans  = resp.challans;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await DeliveryChallanService.getStats();
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
      _filtered = _challans.where((c) {
        if (q.isNotEmpty &&
            !c.challanNumber.toLowerCase().contains(q) &&
            !c.customerName.toLowerCase().contains(q) &&
            !(c.referenceNumber?.toLowerCase().contains(q) ?? false)) return false;
        if (_selectedStatus != 'All' && c.status != _selectedStatus) return false;
        if (_fromDate != null && c.challanDate.isBefore(_fromDate!)) return false;
        if (_toDate   != null && c.challanDate.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
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

  List<DeliveryChallan> get _currentPageItems {
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
        MaterialPageRoute(builder: (_) => const NewDeliveryChallanScreen()));
    if (ok == true) _loadAll();
  }

  void _openEdit(String challanId) async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewDeliveryChallanScreen(challanId: challanId)));
    if (ok == true) _loadAll();
  }

  // ── challan actions ───────────────────────────────────────────────────────

  void _viewChallanDetails(DeliveryChallan challan) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeliveryChallanDetailPage(challanId: challan.id)),
    ).then((result) { if (result == true) _loadAll(); });
  }

  Future<void> _dispatchChallan(DeliveryChallan challan) async {
    if (challan.status != 'DRAFT') { _showError('Only draft challans can be dispatched'); return; }
    try {
      await DeliveryChallanService.dispatchChallan(challan.id);
      _showSuccess('Challan dispatched');
      _loadAll();
    } catch (e) { _showError('Failed to dispatch: $e'); }
  }

  Future<void> _markAsDelivered(DeliveryChallan challan) async {
    if (challan.status != 'OPEN') { _showError('Only dispatched challans can be marked as delivered'); return; }
    try {
      await DeliveryChallanService.markAsDelivered(challan.id);
      _showSuccess('Challan marked as delivered');
      _loadAll();
    } catch (e) { _showError('Failed to mark as delivered: $e'); }
  }

  Future<void> _convertToInvoice(DeliveryChallan challan) async {
    if (challan.status != 'DELIVERED' && challan.status != 'PARTIALLY_INVOICED') {
      _showError('Only delivered challans can be converted to invoice'); return;
    }
    try {
      await DeliveryChallanService.convertToInvoice(challan.id);
      _showSuccess('Challan converted to invoice');
      _loadAll();
    } catch (e) { _showError('Failed to convert to invoice: $e'); }
  }

  Future<void> _markAsReturned(DeliveryChallan challan) async {
    final ok = await _confirmDialog(
      title: 'Mark as Returned',
      message: 'Mark challan ${challan.challanNumber} as returned?',
      confirmLabel: 'Return',
      confirmColor: _orange,
    );
    if (ok != true) return;
    try {
      await DeliveryChallanService.markAsReturned(challan.id);
      _showSuccess('Challan marked as returned');
      _loadAll();
    } catch (e) { _showError('Failed to mark as returned: $e'); }
  }

  Future<void> _sendChallan(DeliveryChallan challan) async {
    if (challan.customerEmail == null || challan.customerEmail!.isEmpty) {
      _showError('Customer email required to send challan'); return;
    }
    try {
      await DeliveryChallanService.sendChallan(challan.id);
      _showSuccess('Challan sent to ${challan.customerEmail}');
      _loadAll();
    } catch (e) { _showError('Failed to send challan: $e'); }
  }

  Future<void> _downloadPDF(DeliveryChallan challan) async {
    try {
      _showSuccess('Preparing PDF…');
      final pdfUrl = await DeliveryChallanService.downloadPDF(challan.id);
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${challan.challanNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        _showSuccess('✅ PDF download started');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) { _showError('Failed to download PDF: $e'); }
  }

  Future<void> _deleteChallan(DeliveryChallan challan) async {
    if (challan.status != 'DRAFT') { _showError('Only draft challans can be deleted'); return; }
    final ok = await _confirmDialog(
      title: 'Delete Challan',
      message: 'Delete challan ${challan.challanNumber}? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await DeliveryChallanService.deleteDeliveryChallan(challan.id);
      _showSuccess('Challan deleted');
      _loadAll();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _shareChallan(DeliveryChallan challan) async {
    final text = _buildShareText(challan);
    try {
      await Share.share(text, subject: 'Delivery Challan: ${challan.challanNumber}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  String _buildShareText(DeliveryChallan challan) {
    final totalQty = challan.items.fold(0.0, (sum, item) => sum + item.quantity);
    return 'Delivery Challan\n'
        '─────────────────────────\n'
        'Challan# : ${challan.challanNumber}\n'
        'Customer : ${challan.customerName}\n'
        'Date     : ${DateFormat('dd MMM yyyy').format(challan.challanDate)}\n'
        'Status   : ${challan.status}\n'
        'Items    : ${challan.items.length}\n'
        'Total Qty: ${totalQty.toStringAsFixed(0)}\n'
        '${challan.referenceNumber != null ? 'Reference: ${challan.referenceNumber}\n' : ''}'
        '${challan.transportMode.isNotEmpty ? 'Transport: ${challan.transportMode}\n' : ''}'
        '${challan.vehicleNumber != null ? 'Vehicle  : ${challan.vehicleNumber}\n' : ''}';
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(DeliveryChallan challan) async {
    final phone = (challan.customerPhone ?? '').trim();
    if (phone.isEmpty) {
      _showError('Customer phone not available on this challan.');
      return;
    }
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final totalQty = challan.items.fold(0.0, (s, i) => s + i.quantity);
    final msg = Uri.encodeComponent(
      'Hello ${challan.customerName},\n\n'
      'Your delivery challan ${challan.challanNumber} has been ${challan.status.toLowerCase().replaceAll('_', ' ')}.\n\n'
      'Date: ${DateFormat('dd MMM yyyy').format(challan.challanDate)}\n'
      'Items: ${challan.items.length} | Total Qty: ${totalQty.toStringAsFixed(0)}\n'
      '${challan.referenceNumber != null ? 'Reference: ${challan.referenceNumber}\n' : ''}'
      '${challan.vehicleNumber != null ? 'Vehicle: ${challan.vehicleNumber}\n' : ''}'
      '\nPlease contact us for any queries. Thank you!',
    );
    final url = Uri.parse('https://wa.me/$cleaned?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket([DeliveryChallan? challan]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        challan: challan,
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
        title: const Text('Export Delivery Challans', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.table_chart, color: _green),
            title: const Text('Excel (XLSX)'),
            onTap: () { Navigator.pop(context); _exportExcel(); },
          ),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _exportExcel() async {
    try {
      if (_filtered.isEmpty) { _showError('Nothing to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Date','Challan#','Reference','Customer','Email','Status','Transport','Vehicle','Items','Total Qty'],
        ..._filtered.map((c) {
          final totalQty = c.items.fold(0.0, (s, i) => s + i.quantity);
          return [
            DateFormat('dd/MM/yyyy').format(c.challanDate),
            c.challanNumber,
            c.referenceNumber ?? '',
            c.customerName,
            c.customerEmail ?? '',
            c.status,
            c.transportMode,
            c.vehicleNumber ?? '',
            c.items.length.toString(),
            totalQty.toStringAsFixed(0),
          ];
        }),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'delivery_challans');
      _showSuccess('✅ Excel downloaded (${_filtered.length} challans)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportChallansDialog(onImportComplete: _loadAll),
    );
  }

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
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
      firstDate: DateTime(2020), lastDate: DateTime(2100),
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

  Future<bool?> _confirmDialog({
    required String title, required String message,
    required String confirmLabel, Color confirmColor = _navy,
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
      appBar: AppTopBar(title: 'Delivery Challans'),
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
          items: items.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Challans' : s.replaceAll('_', ' ')))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── reusable widgets ──────────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Challans' : s.replaceAll('_', ' ')))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFilters(); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search challans, customers…',
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  // ── stats cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final total     = _challans.length;
    final draft     = _challans.where((c) => c.status == 'DRAFT').length;
    final open      = _challans.where((c) => c.status == 'OPEN').length;
    final delivered = _challans.where((c) => c.status == 'DELIVERED').length;
    final invoiced  = _challans.where((c) => c.status == 'INVOICED' || c.status == 'PARTIALLY_INVOICED').length;

    final cards = [
      _StatCardData(label: 'Total Challans', value: total.toString(), icon: Icons.local_shipping_rounded, color: _navy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Draft', value: draft.toString(), icon: Icons.drafts_outlined, color: const Color(0xFF7F8C8D), gradientColors: const [Color(0xFF95A5A6), Color(0xFF7F8C8D)]),
      _StatCardData(label: 'Open / Dispatched', value: open.toString(), icon: Icons.local_shipping_outlined, color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Delivered', value: delivered.toString(), icon: Icons.check_circle_outline, color: _green, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Invoiced', value: invoiced.toString(), icon: Icons.receipt_long_outlined, color: _blue, gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)]),
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
                  dividerThickness: 1, columnSpacing: 16, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E), onChanged: _toggleSelectAll))),
                    const DataColumn(label: Text('DATE')),
                    const DataColumn(label: Text('CHALLAN #')),
                    const DataColumn(label: Text('REFERENCE')),
                    const DataColumn(label: Text('CUSTOMER')),
                    const DataColumn(label: Text('STATUS')),
                    const DataColumn(label: Text('ITEMS')),
                    const DataColumn(label: Text('QTY')),
                    const DataColumn(label: Text('ACTIONS')),
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

  DataRow _buildRow(int index, DeliveryChallan challan) {
    final isSel = _selectedRows.contains(index);
    final totalQty = challan.items.fold(0.0, (sum, item) => sum + item.quantity);

    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleRow(index))),

        // Date
        DataCell(SizedBox(width: 110, child: Text(DateFormat('dd/MM/yyyy').format(challan.challanDate), style: const TextStyle(fontSize: 13)))),

        // Challan number (clickable)
        DataCell(SizedBox(width: 160, child: InkWell(
          onTap: () => _viewChallanDetails(challan),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(challan.challanNumber,
                style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
            const SizedBox(height: 3),
            Text(challan.purpose, style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
          ]),
        ))),

        // Reference
        DataCell(SizedBox(width: 130, child: Text(challan.referenceNumber ?? '-',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])))),

        // Customer
        DataCell(SizedBox(width: 180, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(challan.customerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          if (challan.customerEmail != null)
            Text(challan.customerEmail!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),

        // Status badge
        DataCell(SizedBox(width: 120, child: _statusBadge(challan.status))),

        // Items count
        DataCell(SizedBox(width: 70, child: Text(challan.items.length.toString(),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))),

        // Total qty
        DataCell(SizedBox(width: 80, child: Text(totalQty.toStringAsFixed(0),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))),

        // Actions
        DataCell(SizedBox(width: 150, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _shareChallan(challan),
            child: Container(width: 30, height: 30,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 15, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(challan),
          //   child: Container(width: 30, height: 30,
          //       decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
          //       child: const Icon(Icons.chat, size: 15, color: Color(0xFF25D366))),
          // )),
          // const SizedBox(width: 4),
          // More popup
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('view',     Icons.visibility_outlined,     _blue,   'View Details'),
              _menuItem('edit',     Icons.edit_outlined,           _navy,   'Edit'),
              if (challan.status == 'DRAFT')
                _menuItem('dispatch', Icons.local_shipping_outlined, _orange, 'Dispatch'),
              if (challan.status == 'OPEN')
                _menuItem('delivered', Icons.check_circle_outline,  _green,  'Mark as Delivered'),
              if (challan.status == 'DELIVERED' || challan.status == 'PARTIALLY_INVOICED')
                _menuItem('convert', Icons.receipt_long_outlined,   _blue,   'Convert to Invoice'),
              _menuItem('send',     Icons.send_outlined,            _purple, 'Send via Email'),
              _menuItem('download', Icons.download_outlined,        _navy,   'Download PDF'),
              if (challan.status != 'DRAFT' && challan.status != 'CANCELLED')
                _menuItem('return', Icons.keyboard_return_outlined, _orange, 'Mark as Returned'),
              _menuItem('ticket',   Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
              if (challan.status == 'DRAFT')
                _menuItem('delete', Icons.delete_outline,           _red,   'Delete', textColor: _red),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'view':      _viewChallanDetails(challan); break;
                case 'edit':      _openEdit(challan.id);        break;
                case 'dispatch':  _dispatchChallan(challan);    break;
                case 'delivered': _markAsDelivered(challan);    break;
                case 'convert':   _convertToInvoice(challan);   break;
                case 'send':      _sendChallan(challan);        break;
                case 'download':  _downloadPDF(challan);        break;
                case 'return':    _markAsReturned(challan);     break;
                case 'ticket':    _raiseTicket(challan);        break;
                case 'delete':    _deleteChallan(challan);      break;
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
      'DRAFT':               [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'OPEN':                [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'DELIVERED':           [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'INVOICED':            [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'PARTIALLY_INVOICED':  [Color(0xFFF3E8FF), Color(0xFF7C3AED)],
      'RETURNED':            [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'PARTIALLY_RETURNED':  [Color(0xFFFFEDD5), Color(0xFFEA580C)],
      'CANCELLED':           [Color(0xFFF1F5F9), Color(0xFF94A3B8)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Flexible(child: Text(status.replaceAll('_', ' '), style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 10), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── pagination ────────────────────────────────────────────────────────────

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
              '${_filtered.length != _challans.length ? ' (filtered from ${_challans.length})' : ''}',
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
          child: Icon(Icons.local_shipping_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Delivery Challans Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasAnyFilter ? 'Try adjusting your filters' : 'Create your first delivery challan', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasAnyFilter ? _clearFilters : _openNew,
        icon: Icon(_hasAnyFilter ? Icons.filter_list_off : Icons.add),
        label: Text(_hasAnyFilter ? 'Clear Filters' : 'Create Challan', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Challans', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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

  // ── details dialog (kept from original) ───────────────────────────────────

  Widget _buildDetailsDialog(DeliveryChallan challan) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.local_shipping, color: _blue, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(challan.challanNumber, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text('Delivery Challan Details', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ])),
            _statusBadge(challan.status),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 32),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detailSection('Customer Information', [
              _detailRow('Customer Name', challan.customerName),
              _detailRow('Email', challan.customerEmail),
              _detailRow('Phone', challan.customerPhone),
              if (challan.deliveryAddress != null)
                _detailRow('Address',
                    '${challan.deliveryAddress!.street ?? ''}, ${challan.deliveryAddress!.city ?? ''}, ${challan.deliveryAddress!.state ?? ''} ${challan.deliveryAddress!.pincode ?? ''}'),
            ]),
            const SizedBox(height: 20),
            _detailSection('Challan Information', [
              _detailRow('Challan Number', challan.challanNumber),
              _detailRow('Date', DateFormat('dd MMM yyyy').format(challan.challanDate)),
              _detailRow('Reference', challan.referenceNumber),
              _detailRow('Purpose', challan.purpose),
            ]),
            const SizedBox(height: 20),
            if (challan.transportMode.isNotEmpty)
              _detailSection('Transport Details', [
                _detailRow('Mode', challan.transportMode),
                _detailRow('Vehicle', challan.vehicleNumber),
                _detailRow('Driver', challan.driverName),
                _detailRow('Transporter', challan.transporterName),
              ]),
            const SizedBox(height: 20),
            _itemsSection(challan.items),
            if (challan.customerNotes != null && challan.customerNotes!.isNotEmpty) ...[
              const SizedBox(height: 20),
              _detailSection('Notes', [Padding(padding: const EdgeInsets.all(8), child: Text(challan.customerNotes!, style: TextStyle(fontSize: 13, color: Colors.grey[800])))]),
            ],
          ]))),
        ]),
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _detailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2C3E50), fontSize: 13))),
        Expanded(child: Text(value, style: TextStyle(color: Colors.grey[800], fontSize: 13))),
      ]),
    );
  }

  Widget _itemsSection(List<ChallanItem> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!, width: 1),
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
          children: [
            TableRow(decoration: BoxDecoration(color: Colors.grey[200]), children: const [
              Padding(padding: EdgeInsets.all(10), child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              Padding(padding: EdgeInsets.all(10), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              Padding(padding: EdgeInsets.all(10), child: Text('Unit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            ]),
            ...items.map((item) => TableRow(children: [
              Padding(padding: const EdgeInsets.all(10), child: Text(item.itemDetails, style: const TextStyle(fontSize: 13))),
              Padding(padding: const EdgeInsets.all(10), child: Text(item.quantity.toString(), style: const TextStyle(fontSize: 13))),
              Padding(padding: const EdgeInsets.all(10), child: Text(item.unit, style: const TextStyle(fontSize: 13))),
            ])),
          ],
        ),
      ),
    ]);
  }
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final DeliveryChallan? challan;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.challan, required this.onTicketRaised, required this.onError});

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
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

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
    if (widget.challan == null) {
      return 'A delivery challan ticket has been raised and requires your attention.';
    }
    final c = widget.challan!;
    final totalQty = c.items.fold(0.0, (s, i) => s + i.quantity);
    return 'Delivery Challan "${c.challanNumber}" for customer "${c.customerName}" requires attention.\n\n'
           'Challan Details:\n'
           '• Date: ${DateFormat('dd MMM yyyy').format(c.challanDate)}\n'
           '• Status: ${c.status.replaceAll('_', ' ')}\n'
           '• Customer: ${c.customerName}\n'
           '${c.customerEmail != null ? '• Email: ${c.customerEmail}\n' : ''}'
           '• Items: ${c.items.length} | Total Qty: ${totalQty.toStringAsFixed(0)}\n'
           '• Purpose: ${c.purpose}\n'
           '${c.referenceNumber != null ? '• Reference: ${c.referenceNumber}\n' : ''}'
           '${c.vehicleNumber != null ? '• Vehicle: ${c.vehicleNumber}\n' : ''}'
           '\nPlease review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: widget.challan != null
            ? 'Delivery Challan: ${widget.challan!.challanNumber}'
            : 'Delivery Challans — Action Required',
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
                if (widget.challan != null)
                  Text('Challan: ${widget.challan!.challanNumber}',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Body
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Auto-message preview
              if (widget.challan != null) ...[
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
                                      child: Text((emp['name_parson'] ?? 'U')[0].toUpperCase(),
                                          style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13)),
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
                style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
//  BULK IMPORT CHALLANS DIALOG
// =============================================================================

class BulkImportChallansDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportChallansDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportChallansDialog> createState() => _BulkImportChallansDialogState();
}

class _BulkImportChallansDialogState extends State<BulkImportChallansDialog> {
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
          'Customer ID*',
          'Customer Name*',
          'Customer Email',
          'Customer Phone',
          'Challan Date* (dd/MM/yyyy)',
          'Expected Delivery Date (dd/MM/yyyy)',
          'Reference Number',
          'Purpose* (Sales/Job Work/Stock Transfer/Exhibition/Replacement/Other)',
          'Transport Mode* (Road/Rail/Air/Ship)',
          'Vehicle Number',
          'Driver Name',
          'Transporter Name',
          'Item Details* (item1|item2|...)',
          'Quantities* (qty1|qty2|...)',
          'Units (Pcs|Kg|... defaults to Pcs)',
          'Customer Notes',
          'Created By',
        ],
        // Example row
        [
          '64f2a1b3e4c5d6789012ef01',
          'Acme Corporation',
          'billing@acme.com',
          '+91 9876543210',
          '01/01/2025',
          '05/01/2025',
          'PO-2025-001',
          'Sales',
          'Road',
          'KA-01-AB-1234',
          'Ravi Kumar',
          'FastTrack Logistics',
          'Product A|Product B|Product C',
          '10|5|2',
          'Pcs|Kg|Box',
          'Handle with care',
          'admin@company.com',
        ],
        // Instructions row
        [
          'INSTRUCTIONS:',
          '* = required fields',
          'Customer ID must be a valid MongoDB ObjectId',
          'Dates in dd/MM/yyyy format',
          'For multiple items use pipe | separator',
          'Quantities and Units must match item count',
          'Delete this instructions row before uploading',
        ],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'delivery_challans_import_template');
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

        final rowErrors = <String>[];
        final customerId    = _sv(row, 0);
        final customerName  = _sv(row, 1);
        final customerEmail = _sv(row, 2);
        final customerPhone = _sv(row, 3);
        final challanDateStr = _sv(row, 4);
        final expDateStr    = _sv(row, 5);
        final refNumber     = _sv(row, 6);
        final purpose       = _sv(row, 7, 'Sales');
        final transportMode = _sv(row, 8, 'Road');
        final vehicleNumber = _sv(row, 9);
        final driverName    = _sv(row, 10);
        final transporterName = _sv(row, 11);
        final itemsRaw      = _sv(row, 12);
        final qtysRaw       = _sv(row, 13);
        final unitsRaw      = _sv(row, 14, 'Pcs');
        final notes         = _sv(row, 15);
        final createdBy     = _sv(row, 16, 'import');

        if (customerId.isEmpty)   rowErrors.add('Customer ID required');
        if (customerName.isEmpty) rowErrors.add('Customer Name required');
        if (itemsRaw.isEmpty)     rowErrors.add('Item Details required');
        if (qtysRaw.isEmpty)      rowErrors.add('Quantities required');

        final validPurposes = ['Sales', 'Job Work', 'Stock Transfer', 'Exhibition/Display', 'Replacement/Repair', 'Supply on Approval', 'Other'];
        if (!validPurposes.any((p) => purpose.toLowerCase().contains(p.toLowerCase().split('/')[0].toLowerCase()))) {
          rowErrors.add('Invalid Purpose (use: ${validPurposes.join('/')})');
        }

        DateTime? challanDate;
        DateTime? expDate;
        try { challanDate = DateFormat('dd/MM/yyyy').parse(challanDateStr); }
        catch (_) { rowErrors.add('Invalid Challan Date (use dd/MM/yyyy)'); }
        if (expDateStr.isNotEmpty) {
          try { expDate = DateFormat('dd/MM/yyyy').parse(expDateStr); } catch (_) { rowErrors.add('Invalid Expected Delivery Date'); }
        }

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        // Parse items
        final itemNames = itemsRaw.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        final qtys      = qtysRaw.split('|').map((s) => double.tryParse(s.trim()) ?? 0.0).toList();
        final units     = unitsRaw.split('|').map((s) => s.trim()).toList();

        if (itemNames.isEmpty) { errors.add('Row ${i + 1}: No valid items found'); continue; }

        final items = <Map<String, dynamic>>[];
        for (int j = 0; j < itemNames.length; j++) {
          items.add({
            'itemDetails': itemNames[j],
            'quantity':    j < qtys.length ? qtys[j] : 1.0,
            'unit':        j < units.length && units[j].isNotEmpty ? units[j] : 'Pcs',
          });
        }

        valid.add({
          'customerId':    customerId,
          'customerName':  customerName,
          'customerEmail': customerEmail,
          'customerPhone': customerPhone,
          'challanDate':   challanDate!.toIso8601String(),
          if (expDate != null) 'expectedDeliveryDate': expDate.toIso8601String(),
          'referenceNumber': refNumber.isNotEmpty ? refNumber : null,
          'purpose':       purpose,
          'transportMode': transportMode,
          if (vehicleNumber.isNotEmpty)    'vehicleNumber':    vehicleNumber,
          if (driverName.isNotEmpty)       'driverName':       driverName,
          if (transporterName.isNotEmpty)  'transporterName':  transporterName,
          'items':         items,
          if (notes.isNotEmpty) 'customerNotes': notes,
          'createdBy':     createdBy,
          'status':        'DRAFT',
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
            Text('${valid.length} challan(s) will be created.'),
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

      // Create challans one by one via the existing service
      int success = 0, failed = 0;
      for (final challan in valid) {
        try {
          await DeliveryChallanService.createDeliveryChallan(challan);
          success++;
        } catch (e) {
          failed++;
        }
      }

      setState(() {
        _uploading = false;
        _results = {'success': success, 'failed': failed, 'total': valid.length};
      });

      if (success > 0) {
        _showSnack('✅ $success challan(s) imported!', _green);
        await widget.onImportComplete();
      }
      if (failed > 0) _showSnack('⚠ $failed challan(s) failed to import', _orange);

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
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

  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
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
              decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24),
            ),
            const SizedBox(width: 14),
            const Text('Import Delivery Challans', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
            subtitle: 'Fill the template and upload (XLSX / XLS / CSV).',
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