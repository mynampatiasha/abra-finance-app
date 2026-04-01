// ============================================================================
// SALES ORDERS LIST PAGE
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat cards,
//   dark navy table, ellipsis pagination)
// - Import button  → BulkImportSalesOrdersDialog (template download + upload +
//   row validation + bulkImportSalesOrders)
// - Export button  → Excel export
// - Raise Ticket   → top bar + each row PopupMenu → overlay card with
//                    employee search + assign + auto message
// - Share button   → share_plus (web + mobile)
// - WhatsApp       → url_launcher wa.me link (customerPhone on SO, web + mobile)
// ============================================================================
// File: lib/screens/billing/sales_orders_list_page.dart
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
import 'package:universal_html/html.dart' as html;
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/sales_order_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_sales_order.dart';
import 'sales_order_detail_page.dart';

// ─── colour palette ───────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);

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

class SalesOrdersListPage extends StatefulWidget {
  const SalesOrdersListPage({Key? key}) : super(key: key);
  @override
  State<SalesOrdersListPage> createState() => _SalesOrdersListPageState();
}

class _SalesOrdersListPageState extends State<SalesOrdersListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<SalesOrder> _salesOrders = [];
  SalesOrderStats? _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String   _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;

  final List<String> _statusFilters = [
    'All','DRAFT','OPEN','CONFIRMED','PACKED','SHIPPED','INVOICED','CLOSED','CANCELLED',
  ];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  int _totalCount   = 0;
  final int _itemsPerPage = 20;

  // ── selection ─────────────────────────────────────────────────────────────
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAll();
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
    await Future.wait([_loadOrders(), _loadStats()]);
  }

  Future<void> _loadOrders() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final resp = await SalesOrderService.getSalesOrders(
        status:   _selectedStatus == 'All' ? null : _selectedStatus,
        page:     _currentPage,
        limit:    _itemsPerPage,
        search:   _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate:   _toDate,
      );
      setState(() {
        _salesOrders = resp.salesOrders;
        _totalPages  = resp.pagination.pages;
        _totalCount  = resp.pagination.total;
        _isLoading   = false;
        _selectedIds.clear();
        _selectAll = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await SalesOrderService.getStats();
      setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _loadAll();
    _showSuccess('Data refreshed');
  }

  // ── selection ─────────────────────────────────────────────────────────────

  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      if (_selectAll) {
        _selectedIds.addAll(_salesOrders.map((s) => s.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleRow(String id) {
    setState(() {
      _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
      _selectAll = _selectedIds.length == _salesOrders.length;
    });
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NewSalesOrderScreen()));
    if (ok == true) _loadAll();
  }

  void _openEdit(String id) async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewSalesOrderScreen(salesOrderId: id)));
    if (ok == true) _loadAll();
  }

  // ── view details ──────────────────────────────────────────────────────────

  void _viewDetails(SalesOrder so) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SalesOrderDetailPage(salesOrderId: so.id)),
    ).then((result) { if (result == true) _loadAll(); });
  }

  // ── delete ────────────────────────────────────────────────────────────────

  Future<void> _delete(SalesOrder so) async {
    final ok = await _confirmDialog(
      title: 'Delete Sales Order',
      message: 'Delete ${so.salesOrderNumber}? This cannot be undone.',
      confirmLabel: 'Delete', confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await SalesOrderService.deleteSalesOrder(so.id);
      _showSuccess('Sales order deleted');
      _loadAll();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  // ── send ──────────────────────────────────────────────────────────────────

  Future<void> _send(SalesOrder so) async {
    try {
      await SalesOrderService.sendSalesOrder(so.id);
      _showSuccess('Sales order sent to ${so.customerEmail}');
      _loadAll();
    } catch (e) { _showError('Failed to send: $e'); }
  }

  // ── download pdf ──────────────────────────────────────────────────────────

  Future<void> _downloadPDF(SalesOrder so) async {
    try {
      _showSuccess('Preparing PDF…');
      final pdfUrl = await SalesOrderService.downloadPDF(so.id);
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${so.salesOrderNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else { throw 'Could not launch PDF viewer'; }
      }
      _showSuccess('✅ PDF ready for ${so.salesOrderNumber}');
    } catch (e) { _showError('PDF failed: $e'); }
  }

  // ── confirm ───────────────────────────────────────────────────────────────

  Future<void> _confirm(SalesOrder so) async {
    final ok = await _confirmDialog(
      title: 'Confirm Order',
      message: 'Mark ${so.salesOrderNumber} as CONFIRMED?',
      confirmLabel: 'Confirm', confirmColor: _green,
    );
    if (ok != true) return;
    try {
      await SalesOrderService.confirmSalesOrder(so.id);
      _showSuccess('Order confirmed');
      _loadAll();
    } catch (e) { _showError('Failed to confirm: $e'); }
  }

  // ── convert to invoice ────────────────────────────────────────────────────

  Future<void> _convertToInvoice(SalesOrder so) async {
    final ok = await _confirmDialog(
      title: 'Convert to Invoice',
      message: 'Convert ${so.salesOrderNumber} to an invoice?',
      confirmLabel: 'Convert', confirmColor: _green,
    );
    if (ok != true) return;
    try {
      await SalesOrderService.convertToInvoice(so.id);
      _showSuccess('Converted to invoice successfully');
      _loadAll();
      if (mounted) Navigator.pushReplacementNamed(context, '/admin/billing/invoices');
    } catch (e) { _showError('Failed to convert: $e'); }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _share(SalesOrder so) async {
    final text = 'Sales Order\n'
        '─────────────────────────\n'
        'SO #   : ${so.salesOrderNumber}\n'
        'Customer: ${so.customerName}\n'
        'Email   : ${so.customerEmail ?? '-'}\n'
        'Date    : ${DateFormat('dd MMM yyyy').format(so.salesOrderDate)}\n'
        'Amount  : ₹${so.totalAmount.toStringAsFixed(2)}\n'
        'Status  : ${so.status}\n'
        '${so.expectedShipmentDate != null ? 'Shipment: ${DateFormat('dd MMM yyyy').format(so.expectedShipmentDate!)}\n' : ''}'
        'Terms   : ${so.paymentTerms}';
    try {
      await Share.share(text, subject: 'Sales Order: ${so.salesOrderNumber}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(SalesOrder so) async {
    final phone = (so.customerPhone ?? '').trim();
    if (phone.isEmpty) {
      _showError('Customer phone not available on this sales order. Add the phone when creating the order.');
      return;
    }
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final msg = Uri.encodeComponent(
      'Hello ${so.customerName},\n\n'
      'Your Sales Order ${so.salesOrderNumber} has been created.\n\n'
      'Amount  : ₹${so.totalAmount.toStringAsFixed(2)}\n'
      'Date    : ${DateFormat('dd MMM yyyy').format(so.salesOrderDate)}\n'
      'Status  : ${so.status}\n'
      '${so.expectedShipmentDate != null ? 'Expected Shipment: ${DateFormat('dd MMM yyyy').format(so.expectedShipmentDate!)}\n' : ''}'
      'Payment Terms: ${so.paymentTerms}\n\n'
      'Please feel free to contact us for any queries.\n'
      'Thank you!',
    );
    final url = Uri.parse('https://wa.me/$cleaned?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket([SalesOrder? so]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        salesOrder: so,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError:        (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      if (_salesOrders.isEmpty) { _showError('Nothing to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Date','SO Number','Reference#','Customer Name','Customer Email','Status','Expected Shipment','Payment Terms','Sub Total','CGST','SGST','IGST','Total Amount'],
        ..._salesOrders.map((so) => [
          DateFormat('dd/MM/yyyy').format(so.salesOrderDate),
          so.salesOrderNumber,
          so.referenceNumber ?? '',
          so.customerName,
          so.customerEmail ?? '',
          so.status,
          so.expectedShipmentDate != null ? DateFormat('dd/MM/yyyy').format(so.expectedShipmentDate!) : '',
          so.paymentTerms,
          so.subTotal.toStringAsFixed(2),
          so.cgst.toStringAsFixed(2),
          so.sgst.toStringAsFixed(2),
          so.igst.toStringAsFixed(2),
          so.totalAmount.toStringAsFixed(2),
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'sales_orders');
      _showSuccess('✅ Excel downloaded (${_salesOrders.length} orders)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportSalesOrdersDialog(onImportComplete: _loadAll),
    );
  }

  // ── lifecycle dialog ──────────────────────────────────────────────────────

  void _showLifecycleDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(children: [
          Center(child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Color(0xFF3498DB),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
                  child: const Text('Sales Order Lifecycle Process',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                Expanded(child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  child: InteractiveViewer(
                    panEnabled: true, minScale: 0.5, maxScale: 4.0,
                    child: Center(child: Image.asset('assets/sales_order.png', fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.broken_image_outlined, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('Image not found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                          const SizedBox(height: 8),
                          Text('Please ensure "assets/sales_order.png" exists', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                        ]))),
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
          Positioned(
            top: 40, right: 40,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.6), padding: const EdgeInsets.all(14)),
              tooltip: 'Close',
            ),
          ),
        ]),
      ),
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
    if (d != null) { setState(() { _fromDate = d; _currentPage = 1; }); _loadOrders(); }
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
    if (d != null) { setState(() { _toDate = d; _currentPage = 1; }); _loadOrders(); }
  }

  void _clearDateFilters() {
    setState(() { _fromDate = null; _toDate = null; _currentPage = 1; });
    _loadOrders();
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
      appBar: AppTopBar(title: 'Sales Orders'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _salesOrders.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _salesOrders.isNotEmpty) _buildPagination(),
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
      _iconBtn(Icons.close, _clearDateFilters, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    const Spacer(),
    _actionBtn('New Sales Order', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _salesOrders.isEmpty ? null : _exportExcel),
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
        _iconBtn(Icons.close, _clearDateFilters, tooltip: 'Clear', color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Sales Order', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _salesOrders.isEmpty ? null : _exportExcel),
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
        _iconBtn(Icons.close, _clearDateFilters, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _salesOrders.isEmpty ? null : _exportExcel),
      const SizedBox(width: 6),
      _compactBtn('Ticket', _orange, () => _raiseTicket()),
    ])),
  ]);

  // ── reusable widgets ──────────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Sales Orders' : s))).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() { _selectedStatus = v; _currentPage = 1; });
            _loadOrders();
          }
        },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      onChanged: (v) {
        setState(() { _searchQuery = v.toLowerCase(); _currentPage = 1; });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_searchQuery == v.toLowerCase()) _loadOrders();
        });
      },
      decoration: InputDecoration(
        hintText: 'Search orders, customers…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchController.clear(); setState(() { _searchQuery = ''; _currentPage = 1; }); _loadOrders(); })
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
    final total     = _stats?.totalSalesOrders ?? 0;
    final confirmed = _stats?.confirmedSalesOrders ?? 0;
    final shipped   = _stats?.shippedSalesOrders ?? 0;
    final invoiced  = _stats?.invoicedSalesOrders ?? 0;
    final value     = _stats?.totalValue ?? 0;

    final cards = [
      _StatCardData(label: 'Total Orders', value: total.toString(), icon: Icons.shopping_cart_rounded, color: _navy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Confirmed', value: confirmed.toString(), icon: Icons.check_circle_outline, color: _green, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Shipped', value: shipped.toString(), icon: Icons.local_shipping_outlined, color: _purple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
      _StatCardData(label: 'Invoiced', value: invoiced.toString(), icon: Icons.receipt_long_outlined, color: _blue, gradientColors: const [Color(0xFF5DADE2), Color(0xFF2980B9)]),
      _StatCardData(label: 'Total Value', value: '₹${_formatValue(value)}', icon: Icons.currency_rupee_rounded, color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
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

  String _formatValue(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
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
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
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
                      onChanged: _toggleSelectAll,
                    ))),
                    const DataColumn(label: Text('DATE')),
                    const DataColumn(label: Text('SO #')),
                    const DataColumn(label: Text('REFERENCE #')),
                    const DataColumn(label: Text('CUSTOMER')),
                    const DataColumn(label: Text('STATUS')),
                    const DataColumn(label: Text('SHIPMENT')),
                    const DataColumn(label: Text('AMOUNT')),
                    const DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _salesOrders.map((so) => _buildRow(so)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(SalesOrder so) {
    final isSel = _selectedIds.contains(so.id);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleRow(so.id))),

        // Date
        DataCell(SizedBox(width: 100, child: Text(DateFormat('dd/MM/yyyy').format(so.salesOrderDate),
            style: const TextStyle(fontSize: 12)))),

        // SO#
        DataCell(SizedBox(width: 130, child: InkWell(
          onTap: () => _openEdit(so.id),
          child: Text(so.salesOrderNumber,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 12, decoration: TextDecoration.underline)),
        ))),

        // Reference#
        DataCell(SizedBox(width: 110, child: Text(so.referenceNumber ?? '-',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis))),

        // Customer
        DataCell(SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(so.customerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
          if (so.customerEmail != null)
            Text(so.customerEmail!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),

        // Status
        DataCell(SizedBox(width: 110, child: _statusBadge(so.status))),

        // Shipment
        DataCell(SizedBox(width: 100, child: Text(
          so.expectedShipmentDate != null ? DateFormat('dd/MM/yyyy').format(so.expectedShipmentDate!) : '-',
          style: const TextStyle(fontSize: 12),
        ))),

        // Amount
        DataCell(SizedBox(width: 110, child: Text('₹${so.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))),

        // Actions
        DataCell(SizedBox(width: 150, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _share(so),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          // // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(so),
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
              _menuItem('view',    Icons.visibility_outlined,    _blue,   'View Details'),
              _menuItem('edit',    Icons.edit_outlined,          _navy,   'Edit'),
              if (so.status == 'DRAFT' || so.status == 'OPEN')
                _menuItem('send',  Icons.send_outlined,          _blue,   'Send'),
              _menuItem('pdf',     Icons.download_outlined,      _green,  'Download PDF'),
              if (so.status == 'DRAFT' || so.status == 'OPEN')
                _menuItem('confirm', Icons.check_circle_outline, _green,  'Confirm Order'),
              if (['CONFIRMED','OPEN','PACKED','SHIPPED'].contains(so.status))
                _menuItem('convert', Icons.receipt_long_outlined, _green, 'Convert to Invoice'),
              _menuItem('ticket',  Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
              _menuItem('delete',  Icons.delete_outline,         _red,    'Delete', textColor: _red),
            ],
            onSelected: (v) {
              switch (v) {
                case 'view':    _viewDetails(so);        break;
                case 'edit':    _openEdit(so.id);        break;
                case 'send':    _send(so);               break;
                case 'pdf':     _downloadPDF(so);        break;
                case 'confirm': _confirm(so);            break;
                case 'convert': _convertToInvoice(so);  break;
                case 'ticket':  _raiseTicket(so);        break;
                case 'delete':  _delete(so);             break;
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

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'CONFIRMED': [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'DRAFT':     [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'OPEN':      [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'PACKED':    [Color(0xFFCFFAFE), Color(0xFF0E7490)],
      'SHIPPED':   [Color(0xFFF3E8FF), Color(0xFF7E22CE)],
      'INVOICED':  [Color(0xFFCCFBF1), Color(0xFF0F766E)],
      'CLOSED':    [Color(0xFFE2E8F0), Color(0xFF475569)],
      'CANCELLED': [Color(0xFFFEE2E2), Color(0xFFDC2626)],
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
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _totalCount)} of $_totalCount',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); _loadOrders(); }),
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
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _loadOrders(); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _loadOrders(); } },
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
          child: Icon(Icons.shopping_cart_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Sales Orders Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text('Create your first sales order to get started', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('Create Sales Order', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Sales Orders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
  final SalesOrder? salesOrder;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.salesOrder, required this.onTicketRaised, required this.onError});

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _employees  = [];
  List<Map<String, dynamic>> _filtered   = [];
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
               (e['email']      ?? '').toLowerCase().contains(q) ||
               (e['role']       ?? '').toLowerCase().contains(q);
      }).toList();
    });
  }

  String _buildTicketMessage() {
    if (widget.salesOrder == null) {
      return 'A ticket has been raised regarding a sales order and requires your attention.';
    }
    final so = widget.salesOrder!;
    return 'Sales Order "${so.salesOrderNumber}" for customer "${so.customerName}" requires attention.\n\n'
           'Sales Order Details:\n'
           '• SO Number  : ${so.salesOrderNumber}\n'
           '• Customer   : ${so.customerName}\n'
           '• Email      : ${so.customerEmail ?? '-'}\n'
           '• Amount     : ₹${so.totalAmount.toStringAsFixed(2)}\n'
           '• Status     : ${so.status}\n'
           '• Date       : ${DateFormat('dd MMM yyyy').format(so.salesOrderDate)}\n'
           '${so.expectedShipmentDate != null ? '• Shipment   : ${DateFormat('dd MMM yyyy').format(so.expectedShipmentDate!)}\n' : ''}'
           '• Terms      : ${so.paymentTerms}\n\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    widget.salesOrder != null
            ? 'Sales Order: ${widget.salesOrder!.salesOrderNumber}'
            : 'Sales Orders — Action Required',
        message:    _buildTicketMessage(),
        priority:   _priority,
        timeline:   1440,
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
                if (widget.salesOrder != null)
                  Text('SO: ${widget.salesOrder!.salesOrderNumber}',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Body
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Auto message preview
              if (widget.salesOrder != null) ...[
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
                  foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!),
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
//  BULK IMPORT SALES ORDERS DIALOG
// =============================================================================

class BulkImportSalesOrdersDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportSalesOrdersDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportSalesOrdersDialog> createState() => _BulkImportSalesOrdersDialogState();
}

class _BulkImportSalesOrdersDialogState extends State<BulkImportSalesOrdersDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = <List<dynamic>>[
        [
          'SO Date* (dd/MM/yyyy)', 'SO Number', 'Reference Number',
          'Customer Name*', 'Customer Email*', 'Customer Phone*',
          'Expected Shipment (dd/MM/yyyy)', 'Payment Terms*',
          'Delivery Method', 'Status*', 'Salesperson', 'Subject',
          'Sub Total*', 'CGST', 'SGST', 'IGST', 'TDS Amount', 'TCS Amount',
          'Total Amount*', 'Customer Notes', 'Terms and Conditions',
        ],
        [
          '01/01/2025', 'SO-2025-001', 'PO-ABC-001',
          'ABC Corporation', 'contact@abccorp.com', '9876543210',
          '15/01/2025', 'Net 30', 'Express Delivery', 'DRAFT', 'John Sales',
          'Order for Office Supplies', '100000.00', '9000.00', '9000.00',
          '0.00', '0.00', '0.00', '118000.00',
          'Please prepare for shipment by next week.',
          'Payment due within 30 days.',
        ],
        [
          '02/01/2025', 'SO-2025-002', 'PO-XYZ-002',
          'XYZ Enterprises', 'info@xyzent.com', '9123456789',
          '20/01/2025', 'Net 15', 'Standard Delivery', 'CONFIRMED', 'Jane Sales',
          'Bulk Order - Equipment', '250000.00', '22500.00', '22500.00',
          '0.00', '0.00', '0.00', '295000.00',
          'Rush order - priority handling required.',
          'Payment: 50% advance, 50% on delivery.',
        ],
        [
          'INSTRUCTIONS:', '1. Fields marked * are required',
          '2. Date format: dd/MM/yyyy (e.g. 31/12/2025)',
          '3. Status: DRAFT / OPEN / CONFIRMED / PACKED / SHIPPED / INVOICED / CLOSED / CANCELLED',
          '4. Payment Terms: Due on Receipt / Net 15 / Net 30 / Net 45 / Net 60',
          '5. Phone: 10 digits', '6. Email: valid format',
          '7. Amounts are numbers (decimals allowed)',
          '8. Total = SubTotal + CGST + SGST + IGST + TCS - TDS',
          '9. Delete this instruction row before uploading',
        ],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'sales_orders_import_template');
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
      rows = ext == 'csv' ? _parseCSV(bytes) : _parseExcel(bytes);

      if (rows.length < 2) throw Exception('File must contain header row + at least one data row');

      final List<Map<String, dynamic>> valid  = [];
      final List<String>               errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty) continue;
        if (_sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors     = <String>[];
        final soDateStr     = _sv(row, 0);
        final soNumber      = _sv(row, 1);
        final referenceNum  = _sv(row, 2);
        final customerName  = _sv(row, 3);
        final customerEmail = _sv(row, 4);
        final customerPhone = _parsePhone(_gv(row, 5));
        final shipDateStr   = _sv(row, 6);
        final terms         = _sv(row, 7, 'Net 30');
        final delivery      = _sv(row, 8);
        final status        = _sv(row, 9, 'DRAFT');
        final salesperson   = _sv(row, 10);
        final subject       = _sv(row, 11);
        final subTotal      = _parseDouble(_gv(row, 12));
        final cgst          = _parseDouble(_gv(row, 13));
        final sgst          = _parseDouble(_gv(row, 14));
        final igst          = _parseDouble(_gv(row, 15));
        final tdsAmount     = _parseDouble(_gv(row, 16));
        final tcsAmount     = _parseDouble(_gv(row, 17));
        final totalAmount   = _parseDouble(_gv(row, 18));
        final notes         = _sv(row, 19);
        final tncText       = _sv(row, 20);

        DateTime? soDate;
        DateTime? shipDate;
        try { soDate = DateFormat('dd/MM/yyyy').parse(soDateStr); } catch (_) { rowErrors.add('Invalid SO Date (dd/MM/yyyy)'); }
        if (shipDateStr.isNotEmpty) {
          try { shipDate = DateFormat('dd/MM/yyyy').parse(shipDateStr); } catch (_) { rowErrors.add('Invalid Shipment Date'); }
        }

        if (customerName.isEmpty)  rowErrors.add('Customer Name required');
        if (customerEmail.isEmpty) rowErrors.add('Customer Email required');
        else if (!RegExp(r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(customerEmail)) rowErrors.add('Invalid email');
        if (customerPhone.isEmpty) rowErrors.add('Customer Phone required');
        else if (customerPhone.length < 10) rowErrors.add('Phone must be at least 10 digits');
        if (subTotal <= 0)    rowErrors.add('Sub Total must be > 0');
        if (totalAmount <= 0) rowErrors.add('Total Amount must be > 0');

        const validStatuses = ['DRAFT','OPEN','CONFIRMED','PACKED','SHIPPED','INVOICED','CLOSED','CANCELLED'];
        if (!validStatuses.contains(status.toUpperCase())) rowErrors.add('Invalid status');

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        valid.add({
          'salesOrderDate':      soDate!.toIso8601String(),
          'salesOrderNumber':    soNumber,
          'referenceNumber':     referenceNum,
          'customerName':        customerName,
          'customerEmail':       customerEmail,
          'customerPhone':       customerPhone,
          'expectedShipmentDate': shipDate?.toIso8601String(),
          'paymentTerms':        terms,
          'deliveryMethod':      delivery,
          'status':              status.toUpperCase(),
          'salesperson':         salesperson,
          'subject':             subject,
          'subTotal':            subTotal,
          'cgst':                cgst,
          'sgst':                sgst,
          'igst':                igst,
          'tdsAmount':           tdsAmount,
          'tcsAmount':           tcsAmount,
          'totalAmount':         totalAmount,
          'customerNotes':       notes,
          'termsConditions':     tncText,
        });
      }

      if (valid.isEmpty) throw Exception('No valid rows found');

      // Confirm dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valid.length} sales order(s) will be imported.',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('${errors.length} row(s) skipped:', style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12, color: _red))),
              ),
            ],
            const SizedBox(height: 14),
            const Text('Proceed with import?'),
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

      final importResult = await SalesOrderService.bulkImportSalesOrders(valid);

      setState(() {
        _uploading = false;
        _results = {
          'success': importResult['data']['successCount'],
          'failed':  importResult['data']['failedCount'],
          'total':   importResult['data']['totalProcessed'],
          'errors':  importResult['data']['errors'] ?? [],
        };
      });

      if (importResult['success'] == true) {
        _showSnack('✅ Import completed!', _green);
        await widget.onImportComplete();
      }

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
    }
  }

  String _parsePhone(dynamic v) {
    if (v == null) return '';
    String s = v.toString().trim();
    if (s.toUpperCase().contains('E')) {
      try { return double.parse(s).round().toString(); } catch (_) { return s; }
    }
    if (s.contains('.')) {
      try { return double.parse(s).round().toString(); } catch (_) { return s; }
    }
    return s;
  }

  double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    try { return double.parse(v.toString().trim()); } catch (_) { return 0.0; }
  }

  dynamic _gv(List<dynamic> row, int i) => i < row.length ? row[i] : null;
  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
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

  void _showSnack(String msg, Color color) {
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
      child: Container(
        width: MediaQuery.of(context).size.width > 620
            ? 580
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
            const Text('Import Sales Orders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),

          // Step 1
          _importStep(
            step: '1', color: _blue, icon: Icons.download_rounded,
            title: 'Download Template',
            subtitle: 'Get the Excel template with all required columns and example rows.',
            buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
            onPressed: _downloading || _uploading ? null : _downloadTemplate,
          ),
          const SizedBox(height: 16),

          // Step 2
          _importStep(
            step: '2', color: _green, icon: Icons.upload_rounded,
            title: 'Upload Filled File',
            subtitle: 'Fill in the template and upload your file (XLSX / XLS / CSV).',
            buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'),
            onPressed: _downloading || _uploading ? null : _uploadFile,
          ),

          // File name
          if (_fileName != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600))),
              ]),
            ),
          ],

          // Results
          if (_results != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                _resultRow('Total Processed',     _results!['total'].toString(),   _blue),
                const SizedBox(height: 8),
                _resultRow('Successfully Imported', _results!['success'].toString(), _green),
                const SizedBox(height: 8),
                _resultRow('Failed',               _results!['failed'].toString(),  _red),
                if ((_results!['errors'] as List).isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: _red)),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Text((_results!['errors'] as List).join('\n'), style: const TextStyle(fontSize: 12, color: _red)),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
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

  Widget _resultRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

// =============================================================================
//  SALES ORDER DETAILS DIALOG  (preserved from original)
// =============================================================================

class SalesOrderDetailsDialog extends StatelessWidget {
  final SalesOrder salesOrder;
  const SalesOrderDetailsDialog({Key? key, required this.salesOrder}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.shopping_cart, color: Color(0xFF3498DB), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(salesOrder.salesOrderNumber, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text('Sales Order Details', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ])),
            _statusBadge(salesOrder.status),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 32),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section('Customer Information', [
              _row('Customer Name', salesOrder.customerName),
              _row('Email', salesOrder.customerEmail),
              _row('Phone', salesOrder.customerPhone),
            ]),
            const SizedBox(height: 24),
            _section('Sales Order Information', [
              _row('SO Number', salesOrder.salesOrderNumber),
              _row('Reference Number', salesOrder.referenceNumber),
              _row('SO Date', DateFormat('dd MMM yyyy').format(salesOrder.salesOrderDate)),
              _row('Expected Shipment', salesOrder.expectedShipmentDate != null ? DateFormat('dd MMM yyyy').format(salesOrder.expectedShipmentDate!) : 'Not Set'),
              _row('Payment Terms', salesOrder.paymentTerms),
              _row('Delivery Method', salesOrder.deliveryMethod),
              _row('Salesperson', salesOrder.salesperson),
              _row('Subject', salesOrder.subject),
            ]),
            const SizedBox(height: 24),
            if (salesOrder.items.isNotEmpty) ...[
              _lineItemsSection(salesOrder.items),
              const SizedBox(height: 24),
            ],
            _section('Amount Details', [
              _row('Subtotal', '₹${salesOrder.subTotal.toStringAsFixed(2)}'),
              if (salesOrder.tdsAmount > 0) _row('TDS', '₹${salesOrder.tdsAmount.toStringAsFixed(2)}'),
              if (salesOrder.tcsAmount > 0) _row('TCS', '₹${salesOrder.tcsAmount.toStringAsFixed(2)}'),
              _row('CGST', '₹${salesOrder.cgst.toStringAsFixed(2)}'),
              _row('SGST', '₹${salesOrder.sgst.toStringAsFixed(2)}'),
              _row('IGST', '₹${salesOrder.igst.toStringAsFixed(2)}'),
              _row('Total Amount', '₹${salesOrder.totalAmount.toStringAsFixed(2)}', isBold: true),
            ]),
            if (salesOrder.customerNotes != null && salesOrder.customerNotes!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _section('Customer Notes', [
                Padding(padding: const EdgeInsets.all(8), child: Text(salesOrder.customerNotes!, style: TextStyle(fontSize: 14, color: Colors.grey[800]))),
              ]),
            ],
          ]))),
          const Divider(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ]),
        ]),
      ),
    );
  }

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'CONFIRMED': [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'OPEN':      [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'PACKED':    [Color(0xFFCFFAFE), Color(0xFF0E7490)],
      'SHIPPED':   [Color(0xFFF3E8FF), Color(0xFF7E22CE)],
      'INVOICED':  [Color(0xFFCCFBF1), Color(0xFF0F766E)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: TextStyle(color: c[1], fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _row(String label, dynamic value, {bool isBold = false}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 180, child: Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: const Color(0xFF2C3E50), fontSize: 14))),
        Expanded(child: Text(value.toString(), style: TextStyle(color: Colors.grey[800], fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
      ]),
    );
  }

  Widget _lineItemsSection(List<SalesOrderItem> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Line Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!, width: 1),
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[200]),
              children: const [
                Padding(padding: EdgeInsets.all(12), child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(12), child: Text('Qty',  style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(12), child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(12), child: Text('Amt',  style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...items.map((item) => TableRow(children: [
              Padding(padding: const EdgeInsets.all(12), child: Text(item.itemDetails)),
              Padding(padding: const EdgeInsets.all(12), child: Text(item.quantity.toString())),
              Padding(padding: const EdgeInsets.all(12), child: Text('₹${item.rate.toStringAsFixed(2)}')),
              Padding(padding: const EdgeInsets.all(12), child: Text('₹${item.amount.toStringAsFixed(2)}')),
            ])),
          ],
        ),
      ),
    ]);
  }
}