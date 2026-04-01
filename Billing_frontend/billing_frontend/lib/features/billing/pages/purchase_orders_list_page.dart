// ============================================================================
// PURCHASE ORDERS LIST PAGE
// - Recurring Invoices / Quotes / Vendors UI pattern (3-breakpoint top bar,
//   gradient stat cards, dark navy table, ellipsis pagination)
// - Import button  → BulkImportPurchaseOrdersDialog (2-step pattern)
// - Export button  → Excel export
// - Raise Ticket   → row PopupMenu → overlay with employee search + assign
// - Share button   → share_plus (web + mobile)
// - WhatsApp       → url_launcher wa.me (po.vendorPhone, web + mobile)
// ============================================================================
// File: lib/screens/billing/purchase_orders_list_page.dart
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
import '../../../../core/services/purchase_order_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_purchase_order.dart';
import 'purchase_order_detail_page.dart';

// ─── colour palette ──────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);

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

class PurchaseOrdersListPage extends StatefulWidget {
  const PurchaseOrdersListPage({Key? key}) : super(key: key);
  @override
  State<PurchaseOrdersListPage> createState() => _PurchaseOrdersListPageState();
}

class _PurchaseOrdersListPageState extends State<PurchaseOrdersListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<PurchaseOrder> _purchaseOrders = [];
  PurchaseOrderStats? _stats;
  bool    _isLoading   = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String   _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;

  final List<String> _statusFilters = [
    'All', 'DRAFT', 'ISSUED', 'PARTIALLY_RECEIVED', 'RECEIVED',
    'PARTIALLY_BILLED', 'BILLED', 'CLOSED', 'CANCELLED',
  ];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage = 1;
  int _totalPages  = 1;
  int _totalPOs    = 0;
  final int _perPage = 20;

  // ── selection ─────────────────────────────────────────────────────────────
  final Set<String> _selectedPOs = {};
  bool _selectAll = false;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadPOs();
    _loadStats();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadPOs() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final resp = await PurchaseOrderService.getPurchaseOrders(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage, limit: _perPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate, toDate: _toDate,
      );
      setState(() {
        _purchaseOrders = resp.purchaseOrders;
        _totalPages     = resp.pagination.pages;
        _totalPOs       = resp.pagination.total;
        _isLoading      = false;
        _selectedPOs.clear();
        _selectAll = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await PurchaseOrderService.getStats();
      setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([_loadPOs(), _loadStats()]);
    _showSuccess('Data refreshed');
  }

  // ── filters ───────────────────────────────────────────────────────────────

  void _filterByStatus(String s) {
    setState(() { _selectedStatus = s; _currentPage = 1; });
    _loadPOs();
  }

  void _clearDates() {
    setState(() { _fromDate = null; _toDate = null; });
    _loadPOs();
  }

  // ── selection ─────────────────────────────────────────────────────────────

  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      if (_selectAll) _selectedPOs.addAll(_purchaseOrders.map((p) => p.id));
      else _selectedPOs.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      _selectedPOs.contains(id) ? _selectedPOs.remove(id) : _selectedPOs.add(id);
      _selectAll = _selectedPOs.length == _purchaseOrders.length;
    });
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewPurchaseOrderScreen()));
    if (ok == true) _refresh();
  }

  void _openEdit(String id) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewPurchaseOrderScreen(purchaseOrderId: id)));
    if (ok == true) _refresh();
  }

  // ── PO actions ────────────────────────────────────────────────────────────

  void _viewDetails(PurchaseOrder po) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PurchaseOrderDetailPage(purchaseOrderId: po.id)),
    ).then((result) { if (result == true) _loadPOs(); });
  }

  Future<void> _deletePO(PurchaseOrder po) async {
    final ok = await _confirmDialog(
      title: 'Delete Purchase Order',
      message: 'Delete ${po.purchaseOrderNumber}? This cannot be undone.',
      confirmLabel: 'Delete', confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await PurchaseOrderService.deletePurchaseOrder(po.id);
      _showSuccess('Purchase order deleted');
      _refresh();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  Future<void> _sendPO(PurchaseOrder po) async {
    try {
      await PurchaseOrderService.sendPurchaseOrder(po.id);
      _showSuccess('Purchase order sent to ${po.vendorEmail ?? po.vendorName}');
      _refresh();
    } catch (e) { _showError('Failed to send: $e'); }
  }

  Future<void> _downloadPDF(PurchaseOrder po) async {
    try {
      _showSuccess('Preparing PDF…');
      final url = await PurchaseOrderService.downloadPDF(po.id);
      if (kIsWeb) {
        html.AnchorElement(href: url)
          ..setAttribute('download', '${po.purchaseOrderNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        _showSuccess('✅ PDF download started');
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open PDF';
        }
      }
    } catch (e) { _showError('Failed to download PDF: $e'); }
  }

  Future<void> _issuePO(PurchaseOrder po) async {
    final ok = await _confirmDialog(
      title: 'Issue Purchase Order',
      message: 'Mark ${po.purchaseOrderNumber} as ISSUED and send to vendor?',
      confirmLabel: 'Issue', confirmColor: _green,
    );
    if (ok != true) return;
    try {
      await PurchaseOrderService.issuePurchaseOrder(po.id);
      _showSuccess('Purchase order issued');
      _refresh();
    } catch (e) { _showError('Failed to issue: $e'); }
  }

  void _recordReceive(PurchaseOrder po) {
    showDialog(
      context: context,
      builder: (_) => RecordReceiveDialog(purchaseOrder: po, onReceived: _refresh),
    );
  }

  Future<void> _convertToBill(PurchaseOrder po) async {
    final ok = await _confirmDialog(
      title: 'Convert to Bill',
      message: 'Convert ${po.purchaseOrderNumber} to a Bill? This creates a bill for all received items.',
      confirmLabel: 'Convert to Bill', confirmColor: _green,
    );
    if (ok != true) return;
    try {
      await PurchaseOrderService.convertToBill(po.id);
      _showSuccess('${po.purchaseOrderNumber} converted to bill');
      _refresh();
      if (mounted) Navigator.pushReplacementNamed(context, '/admin/billing/bills');
    } catch (e) { _showError('Failed to convert: $e'); }
  }

  Future<void> _cancelPO(PurchaseOrder po) async {
    final ok = await _confirmDialog(
      title: 'Cancel Purchase Order',
      message: 'Cancel ${po.purchaseOrderNumber}? This cannot be undone.',
      confirmLabel: 'Cancel PO', confirmColor: _orange,
    );
    if (ok != true) return;
    try {
      await PurchaseOrderService.cancelPurchaseOrder(po.id);
      _showSuccess('Purchase order cancelled');
      _refresh();
    } catch (e) { _showError('Failed to cancel: $e'); }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _sharePO(PurchaseOrder po) async {
    final text = 'Purchase Order Details\n'
        '─────────────────────────\n'
        'PO Number : ${po.purchaseOrderNumber}\n'
        'Vendor    : ${po.vendorName}\n'
        'Email     : ${po.vendorEmail ?? '-'}\n'
        'Amount    : ₹${po.totalAmount.toStringAsFixed(2)}\n'
        'Status    : ${po.status}\n'
        'PO Date   : ${DateFormat('dd MMM yyyy').format(po.purchaseOrderDate)}\n'
        '${po.expectedDeliveryDate != null ? 'Delivery  : ${DateFormat('dd MMM yyyy').format(po.expectedDeliveryDate!)}\n' : ''}'
        'Terms     : ${po.paymentTerms}';
    try {
      await Share.share(text, subject: 'PO: ${po.purchaseOrderNumber}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(PurchaseOrder po) async {
    final raw   = (po.vendorPhone ?? '').trim();
    if (raw.isEmpty) {
      _showError('Vendor phone not available on this purchase order.');
      return;
    }
    final phone = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) {
      _showError('Vendor phone not available on this purchase order.');
      return;
    }
    final msg = Uri.encodeComponent(
      'Hello ${po.vendorName},\n\n'
      'Please find below your Purchase Order details from Abra Travels:\n\n'
      'PO Number : ${po.purchaseOrderNumber}\n'
      'Amount    : ₹${po.totalAmount.toStringAsFixed(2)}\n'
      'Status    : ${po.status}\n'
      'PO Date   : ${DateFormat('dd MMM yyyy').format(po.purchaseOrderDate)}\n'
      '${po.expectedDeliveryDate != null ? 'Expected Delivery: ${DateFormat('dd MMM yyyy').format(po.expectedDeliveryDate!)}\n' : ''}'
      'Payment Terms: ${po.paymentTerms}\n\n'
      'Please contact us for any queries.\nThank you!',
    );
    final url = Uri.parse('https://wa.me/$phone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket(PurchaseOrder po) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        purchaseOrder: po,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError: (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      if (_purchaseOrders.isEmpty) { _showError('No purchase orders to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Date', 'PO Number', 'Reference#', 'Vendor Name', 'Vendor Email', 'Status', 'Expected Delivery', 'Payment Terms', 'Sub Total', 'CGST', 'SGST', 'IGST', 'Total Amount'],
        ..._purchaseOrders.map((po) => [
          DateFormat('dd/MM/yyyy').format(po.purchaseOrderDate),
          po.purchaseOrderNumber,
          po.referenceNumber ?? '',
          po.vendorName,
          po.vendorEmail ?? '',
          po.status,
          po.expectedDeliveryDate != null ? DateFormat('dd/MM/yyyy').format(po.expectedDeliveryDate!) : '',
          po.paymentTerms,
          po.subTotal.toStringAsFixed(2),
          po.cgst.toStringAsFixed(2),
          po.sgst.toStringAsFixed(2),
          po.igst.toStringAsFixed(2),
          po.totalAmount.toStringAsFixed(2),
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'purchase_orders');
      _showSuccess('✅ Excel downloaded (${_purchaseOrders.length} records)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportPurchaseOrdersDialog(onImportComplete: _refresh),
    );
  }

  // ── lifecycle dialog ──────────────────────────────────────────────────────

  void _showLifecycle() {
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
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF3498DB),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                ),
                child: const Text('Purchase Order Lifecycle Process',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              ),
              Expanded(child: Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                child: InteractiveViewer(
                  panEnabled: true, minScale: 0.5, maxScale: 4.0,
                  child: Center(child: Image.asset('assets/purchase_order.png', fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => SingleChildScrollView(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _lifecycleStep('1', 'Business Need',           Colors.blue,   Icons.lightbulb),
                      _lifecycleArrow(),
                      _lifecycleStep('2', 'Create PO (Draft)',       Colors.orange, Icons.edit_document),
                      _lifecycleArrow(),
                      _lifecycleStep('3', 'Issue & Send to Vendor',  Colors.teal,   Icons.send),
                      _lifecycleArrow(),
                      _lifecycleStep('4', 'Vendor Delivers',         Colors.indigo, Icons.local_shipping),
                      _lifecycleArrow(),
                      _lifecycleStep('5', 'Record Purchase Receive', Colors.cyan,   Icons.inventory_2),
                      _lifecycleArrow(),
                      _lifecycleStep('6', 'Convert PO → Bill',       _green,        Icons.receipt_long),
                      _lifecycleArrow(),
                      _lifecycleStep('7', 'Record Payment',          Colors.amber,  Icons.payment),
                      _lifecycleArrow(),
                      _lifecycleStep('✅', 'PO Closed',              _green,        Icons.check_circle),
                    ])),
                  )),
                ),
              )),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                child: Text('Tip: Pinch to zoom, drag to pan', style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center),
              ),
            ])),
          )),
          Positioned(
            top: 40, right: 40,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.6), padding: const EdgeInsets.all(14)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _lifecycleStep(String step, String label, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 16, backgroundColor: color,
            child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
        const SizedBox(width: 12),
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
      ]),
    );
  }

  Widget _lifecycleArrow() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Icon(Icons.arrow_downward, color: Colors.grey[400], size: 20),
  );

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _fromDate = d; _currentPage = 1; }); _loadPOs(); }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _toDate = d; _currentPage = 1; }); _loadPOs(); }
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
      appBar: AppTopBar(title: 'Purchase Orders'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _purchaseOrders.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _purchaseOrders.isNotEmpty) _buildPagination(),
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
    _searchField(width: 240),
    const SizedBox(width: 10),
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, _clearDates, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_rounded, _showLifecycle, tooltip: 'View PO Process', color: _blue, bg: _blue.withOpacity(0.08)),
    const Spacer(),
    _actionBtn('New PO', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _purchaseOrders.isEmpty ? null : _exportExcel),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 180),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, _clearDates, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_rounded, _showLifecycle, tooltip: 'Process', color: _blue, bg: _blue.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New PO', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _purchaseOrders.isEmpty ? null : _exportExcel),
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
        _iconBtn(Icons.close, _clearDates, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_rounded, _showLifecycle, color: _blue, bg: _blue.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _purchaseOrders.isEmpty ? null : _exportExcel),
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
        items: _statusFilters.map((s) => DropdownMenuItem(value: s,
            child: Text(s == 'All' ? 'All Purchase Orders' : s.replaceAll('_', ' ')))).toList(),
        onChanged: (v) { if (v != null) _filterByStatus(v); },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 14),
      onChanged: (v) {
        setState(() { _searchQuery = v.toLowerCase(); _currentPage = 1; });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_searchQuery == v.toLowerCase()) _loadPOs();
        });
      },
      decoration: InputDecoration(
        hintText: 'Search purchase orders…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchCtrl.clear(); setState(() { _searchQuery = ''; _currentPage = 1; }); _loadPOs(); })
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
    final total    = _stats?.totalPurchaseOrders ?? 0;
    final issued   = _stats?.issuedPurchaseOrders ?? 0;
    final received = _stats?.receivedPurchaseOrders ?? 0;
    final value    = _stats?.totalValue ?? 0.0;
    final draft    = _purchaseOrders.where((p) => p.status == 'DRAFT').length;

    final cards = [
      _StatCardData(label: 'Total POs',    value: total.toString(),    icon: Icons.shopping_basket_outlined, color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Draft',        value: draft.toString(),    icon: Icons.edit_outlined,            color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Issued',       value: issued.toString(),   icon: Icons.send_outlined,            color: _teal,   gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)]),
      _StatCardData(label: 'Received',     value: received.toString(), icon: Icons.inventory_2_outlined,     color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Total Value',  value: '₹${(value / 1000).toStringAsFixed(0)}K', icon: Icons.currency_rupee, color: _blue, gradientColors: const [Color(0xFF5DADE2), Color(0xFF2980B9)]),
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
                    const DataColumn(label: SizedBox(width: 100, child: Text('DATE'))),
                    const DataColumn(label: SizedBox(width: 140, child: Text('PO NUMBER'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('REFERENCE #'))),
                    const DataColumn(label: SizedBox(width: 170, child: Text('VENDOR'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('DELIVERY DATE'))),
                    const DataColumn(label: SizedBox(width: 115, child: Text('AMOUNT'))),
                    const DataColumn(label: SizedBox(width: 150, child: Text('ACTIONS'))),
                  ],
                  rows: _purchaseOrders.map((po) => _buildRow(po)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(PurchaseOrder po) {
    final isSel = _selectedPOs.contains(po.id);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleSelection(po.id))),

        // Date
        DataCell(SizedBox(width: 100, child: Text(DateFormat('dd/MM/yyyy').format(po.purchaseOrderDate), style: const TextStyle(fontSize: 13)))),

        // PO Number (clickable)
        DataCell(SizedBox(width: 140, child: InkWell(
          onTap: () => _openEdit(po.id),
          child: Text(po.purchaseOrderNumber,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
        ))),

        // Reference
        DataCell(SizedBox(width: 120, child: Text(po.referenceNumber ?? '-', style: TextStyle(fontSize: 13, color: Colors.grey[600])))),

        // Vendor
        DataCell(SizedBox(width: 170, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(po.vendorName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          if (po.vendorEmail != null)
            Text(po.vendorEmail!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),

        // Status
        DataCell(SizedBox(width: 130, child: _statusBadge(po.status))),

        // Delivery Date
        DataCell(SizedBox(width: 110, child: Text(
          po.expectedDeliveryDate != null ? DateFormat('dd/MM/yyyy').format(po.expectedDeliveryDate!) : '-',
          style: const TextStyle(fontSize: 13),
        ))),

        // Amount
        DataCell(SizedBox(width: 115, child: Text('₹${po.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right))),

        // Actions
        DataCell(SizedBox(width: 150, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _sharePO(po),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(po),
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
              _menuItem('view',    Icons.visibility_outlined,          _blue,   'View Details'),
              _menuItem('edit',    Icons.edit_outlined,                _navy,   'Edit'),
              if (po.status == 'DRAFT')
                _menuItem('issue',  Icons.send_outlined,              _green,  'Issue & Send'),
              if (po.status == 'DRAFT' || po.status == 'ISSUED')
                _menuItem('send',   Icons.email_outlined,             _orange, 'Send Email'),
              _menuItem('download', Icons.download_outlined,          _teal,   'Download PDF'),
              if (po.status == 'ISSUED' || po.status == 'PARTIALLY_RECEIVED')
                _menuItem('receive', Icons.inventory_2_outlined,      _teal,   'Record Receive'),
              if (po.status == 'RECEIVED' || po.status == 'PARTIALLY_RECEIVED' || po.status == 'PARTIALLY_BILLED')
                _menuItem('convert_bill', Icons.receipt_long_outlined, _green, 'Convert to Bill'),
              _menuItem('ticket',  Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
              if (po.status != 'CANCELLED' && po.status != 'CLOSED' && po.status != 'BILLED')
                _menuItem('cancel', Icons.cancel_outlined,            _orange, 'Cancel PO', textColor: _orange),
              if (po.status == 'DRAFT')
                _menuItem('delete', Icons.delete_outline,             _red,    'Delete', textColor: _red),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'view':         _viewDetails(po);   break;
                case 'edit':         _openEdit(po.id);   break;
                case 'issue':        _issuePO(po);       break;
                case 'send':         _sendPO(po);        break;
                case 'download':     _downloadPDF(po);   break;
                case 'receive':      _recordReceive(po); break;
                case 'convert_bill': _convertToBill(po); break;
                case 'ticket':       _raiseTicket(po);   break;
                case 'cancel':       _cancelPO(po);      break;
                case 'delete':       _deletePO(po);      break;
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
      'DRAFT':              [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'ISSUED':             [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'PARTIALLY_RECEIVED': [Color(0xFFCCFBF1), Color(0xFF0F766E)],
      'RECEIVED':           [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'PARTIALLY_BILLED':   [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'BILLED':             [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'CLOSED':             [Color(0xFFE2E8F0), Color(0xFF475569)],
      'CANCELLED':          [Color(0xFFFEE2E2), Color(0xFFDC2626)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    final label = status.replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 10), overflow: TextOverflow.ellipsis),
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
              'Showing ${(_currentPage - 1) * _perPage + 1}–${(_currentPage * _perPage).clamp(0, _totalPOs)} of $_totalPOs',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); _loadPOs(); }),
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
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _loadPOs(); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _loadPOs(); } },
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
          child: Icon(Icons.shopping_basket_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Purchase Orders Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text('Create your first purchase order to get started', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('Create Purchase Order', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Purchase Orders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _refresh, icon: const Icon(Icons.refresh),
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
  final PurchaseOrder purchaseOrder;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({required this.purchaseOrder, required this.onTicketRaised, required this.onError});

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
      _filtered = q.isEmpty ? _employees : _employees.where((e) =>
        (e['name_parson'] ?? '').toLowerCase().contains(q) ||
        (e['email'] ?? '').toLowerCase().contains(q) ||
        (e['role'] ?? '').toLowerCase().contains(q)).toList();
    });
  }

  String _buildMessage() {
    final po = widget.purchaseOrder;
    return 'Purchase Order "${po.purchaseOrderNumber}" for vendor "${po.vendorName}" '
           '(${po.vendorEmail ?? 'N/A'}) requires attention.\n\n'
           'PO Details:\n'
           '• Amount: ₹${po.totalAmount.toStringAsFixed(2)}\n'
           '• Status: ${po.status}\n'
           '• PO Date: ${DateFormat('dd MMM yyyy').format(po.purchaseOrderDate)}\n'
           '${po.expectedDeliveryDate != null ? '• Expected Delivery: ${DateFormat('dd MMM yyyy').format(po.expectedDeliveryDate!)}\n' : ''}'
           '• Payment Terms: ${po.paymentTerms}\n\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: 'Purchase Order: ${widget.purchaseOrder.purchaseOrderNumber}',
        message:  _buildMessage(),
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
      widget.onError('Failed: $e');
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
                Text('PO: ${widget.purchaseOrder.purchaseOrderNumber}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          // Body
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5)),
              ),
              const SizedBox(height: 20),
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
              _loading
                  ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _navy)))
                  : _filtered.isEmpty
                      ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 240),
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
                        style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis,
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
//  BULK IMPORT PURCHASE ORDERS DIALOG (2-step pattern)
// =============================================================================

class BulkImportPurchaseOrdersDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportPurchaseOrdersDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportPurchaseOrdersDialog> createState() => _BulkImportPurchaseOrdersDialogState();
}

class _BulkImportPurchaseOrdersDialogState extends State<BulkImportPurchaseOrdersDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = <List<dynamic>>[
        ['PO Date* (dd/MM/yyyy)', 'PO Number', 'Reference Number', 'Vendor Name*', 'Vendor Email*', 'Vendor Phone*', 'Expected Delivery (dd/MM/yyyy)', 'Payment Terms*', 'Shipment Preference', 'Status*', 'Salesperson', 'Subject', 'Delivery Address', 'Sub Total*', 'CGST', 'SGST', 'IGST', 'TDS Amount', 'TCS Amount', 'Total Amount*', 'Vendor Notes', 'Terms and Conditions'],
        ['01/01/2025', 'PO-2025-001', 'REF-001', 'ABC Suppliers', 'purchase@abc.com', '9876543210', '15/01/2025', 'Net 30', 'Standard', 'DRAFT', 'John Manager', 'Office Supplies', '123, Industrial Area, Bengaluru', '100000.00', '9000.00', '9000.00', '0.00', '0.00', '0.00', '118000.00', 'Please deliver before the date.', 'Payment within 30 days.'],
        ['INSTRUCTIONS:', '* = required', 'Status: DRAFT or ISSUED', 'Payment Terms: Due on Receipt/Net 15/Net 30/Net 45/Net 60', 'Phone: 10 digits', 'Delete this row before uploading'],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'purchase_orders_import_template');
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
        type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false, withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file  = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) { _showSnack('Could not read file', _red); return; }

      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      final ext  = file.extension?.toLowerCase() ?? '';
      final rows = (ext == 'csv') ? _parseCSV(bytes) : _parseExcel(bytes);
      if (rows.length < 2) throw Exception('File needs header + at least one data row');

      final List<Map<String, dynamic>> valid  = [];
      final List<String>               errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty) continue;
        if (_sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors = <String>[];
        final poDate      = _parseDate(_sv(row, 0));
        final poNumber    = _sv(row, 1);
        final refNumber   = _sv(row, 2);
        final vendorName  = _sv(row, 3);
        final vendorEmail = _sv(row, 4);
        final vendorPhone = _parsePhone(_sv(row, 5));
        final deliveryDate = _parseDate(_sv(row, 6));
        final payTerms    = _sv(row, 7, 'Net 30');
        final shipment    = _sv(row, 8);
        final status      = _sv(row, 9, 'DRAFT').toUpperCase();
        final salesperson = _sv(row, 10);
        final subject     = _sv(row, 11);
        final deliveryAddr = _sv(row, 12);
        final subTotal    = _parseDouble(_sv(row, 13));
        final cgst        = _parseDouble(_sv(row, 14));
        final sgst        = _parseDouble(_sv(row, 15));
        final igst        = _parseDouble(_sv(row, 16));
        final tdsAmount   = _parseDouble(_sv(row, 17));
        final tcsAmount   = _parseDouble(_sv(row, 18));
        final totalAmount = _parseDouble(_sv(row, 19));
        final vendorNotes = _sv(row, 20);
        final terms       = _sv(row, 21);

        if (poDate == null)      rowErrors.add('PO Date required (dd/MM/yyyy)');
        if (vendorName.isEmpty)  rowErrors.add('Vendor Name required');
        if (vendorEmail.isEmpty) rowErrors.add('Vendor Email required');
        else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(vendorEmail)) rowErrors.add('Invalid email');
        if (vendorPhone.isEmpty) rowErrors.add('Vendor Phone required');
        else if (vendorPhone.length < 10) rowErrors.add('Phone must be 10 digits');
        if (subTotal <= 0)       rowErrors.add('Sub Total must be > 0');
        if (totalAmount <= 0)    rowErrors.add('Total Amount must be > 0');

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        valid.add({
          'purchaseOrderDate':    poDate!.toIso8601String(),
          'purchaseOrderNumber':  poNumber,
          'referenceNumber':      refNumber,
          'vendorName':           vendorName,
          'vendorEmail':          vendorEmail,
          'vendorPhone':          vendorPhone,
          'expectedDeliveryDate': deliveryDate?.toIso8601String(),
          'paymentTerms':         payTerms,
          'shipmentPreference':   shipment,
          'status':               status,
          'salesperson':          salesperson,
          'subject':              subject,
          'deliveryAddress':      deliveryAddr,
          'subTotal':             subTotal,
          'cgst':                 cgst,
          'sgst':                 sgst,
          'igst':                 igst,
          'tdsAmount':            tdsAmount,
          'tcsAmount':            tcsAmount,
          'totalAmount':          totalAmount,
          'vendorNotes':          vendorNotes,
          'termsAndConditions':   terms,
        });
      }

      if (valid.isEmpty) throw Exception('No valid purchase order data found');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valid.length} purchase order(s) will be imported.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${errors.length} row(s) skipped:', style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)),
                child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12, color: _red))),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Do you want to proceed?'),
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

      if (confirmed != true) { setState(() { _uploading = false; _fileName = null; }); return; }

      final importResult = await PurchaseOrderService.bulkImportPurchaseOrders(valid);

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
        _showSnack('✅ ${_results!['success']} PO(s) imported!', _green);
        await widget.onImportComplete();
      }
      if ((_results!['failed'] ?? 0) > 0) {
        _showSnack('⚠ ${_results!['failed']} failed', _orange);
      }

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final ex = excel_pkg.Excel.decodeBytes(bytes);
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

  double _parseDouble(String s) {
    if (s.isEmpty) return 0.0;
    return double.tryParse(s.replaceAll(',', '')) ?? 0.0;
  }

  String _parsePhone(String s) {
    if (s.isEmpty) return '';
    if (s.toUpperCase().contains('E')) {
      try { return double.parse(s).round().toString(); } catch (_) {}
    }
    if (s.contains('.')) {
      try { return double.parse(s).round().toString(); } catch (_) {}
    }
    return s.replaceAll(RegExp(r'[^\d]'), '');
  }

  DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    for (final fmt in ['dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd', 'MM/dd/yyyy']) {
      try { return DateFormat(fmt).parse(s); } catch (_) {}
    }
    return null;
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
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
            const SizedBox(width: 14),
            const Text('Import Purchase Orders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),
          _importStep(step: '1', color: _blue, icon: Icons.download_rounded, title: 'Download Template', subtitle: 'Get the Excel template with all required columns and an example row.', buttonLabel: _downloading ? 'Downloading…' : 'Download Template', onPressed: _downloading || _uploading ? null : _downloadTemplate),
          const SizedBox(height: 16),
          _importStep(step: '2', color: _green, icon: Icons.upload_rounded, title: 'Upload Filled File', subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).', buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'), onPressed: _downloading || _uploading ? null : _uploadFile),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8),
                Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          if (_results != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
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
                  Container(constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(child: Text((_results!['errors'] as List).join('\n'), style: const TextStyle(fontSize: 12, color: _red)))),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Close'),
            )),
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
        disabledBackgroundColor: color.withOpacity(0.5), elevation: 0,
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
//  RECORD RECEIVE DIALOG (preserved from original)
// =============================================================================

class RecordReceiveDialog extends StatefulWidget {
  final PurchaseOrder purchaseOrder;
  final VoidCallback onReceived;
  const RecordReceiveDialog({Key? key, required this.purchaseOrder, required this.onReceived}) : super(key: key);

  @override
  State<RecordReceiveDialog> createState() => _RecordReceiveDialogState();
}

class _RecordReceiveDialogState extends State<RecordReceiveDialog> {
  DateTime _receiveDate = DateTime.now();
  final List<Map<String, dynamic>> _receiveItems = [];
  final TextEditingController _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _receiveItems.addAll(widget.purchaseOrder.items.map((item) => {
      'itemDetails':      item.itemDetails,
      'quantityOrdered':  item.quantity,
      'quantityReceived': item.quantity,
      'controller':       TextEditingController(text: item.quantity.toString()),
    }));
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (var item in _receiveItems) { (item['controller'] as TextEditingController).dispose(); }
    super.dispose();
  }

  Future<void> _saveReceive() async {
    setState(() => _isSaving = true);
    try {
      await PurchaseOrderService.recordReceive(widget.purchaseOrder.id, {
        'receiveDate': _receiveDate.toIso8601String(),
        'items': _receiveItems.map((item) => {
          'itemDetails':      item['itemDetails'],
          'quantityOrdered':  item['quantityOrdered'],
          'quantityReceived': item['quantityReceived'],
        }).toList(),
        'notes': _notesCtrl.text.trim(),
      });
      Navigator.pop(context);
      widget.onReceived();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Purchase receive recorded successfully'),
        backgroundColor: _green, behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to record receive: $e'),
        backgroundColor: _red, behavior: SnackBarBehavior.floating,
      ));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.inventory_2, color: _blue, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text('Record Purchase Receive', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          Text('PO: ${widget.purchaseOrder.purchaseOrderNumber}', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const Divider(height: 32),

          // Receive date
          InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _receiveDate, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) setState(() => _receiveDate = d);
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: 'Receive Date *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.calendar_today)),
              child: Text(DateFormat('dd MMM yyyy').format(_receiveDate)),
            ),
          ),
          const SizedBox(height: 16),

          // Items
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Color(0xFF0D1B3E), borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8))),
                child: Row(children: const [
                  Expanded(flex: 3, child: Text('ITEM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                  SizedBox(width: 100, child: Text('ORDERED', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                  SizedBox(width: 120, child: Text('RECEIVED', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                ]),
              ),
              ListView.separated(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                itemCount: _receiveItems.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                itemBuilder: (_, i) {
                  final item = _receiveItems[i];
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(item['itemDetails'], style: const TextStyle(fontSize: 14))),
                      SizedBox(width: 100, child: Text(item['quantityOrdered'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14))),
                      SizedBox(width: 120, child: TextFormField(
                        controller: item['controller'],
                        decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                        keyboardType: TextInputType.number, textAlign: TextAlign.center,
                        onChanged: (v) => setState(() => item['quantityReceived'] = double.tryParse(v) ?? 0),
                      )),
                    ]),
                  );
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesCtrl,
            decoration: InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveReceive,
              icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving…' : 'Record Receive'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  PURCHASE ORDER DETAILS DIALOG (preserved from original)
// =============================================================================

class PurchaseOrderDetailsDialog extends StatelessWidget {
  final PurchaseOrder purchaseOrder;
  const PurchaseOrderDetailsDialog({Key? key, required this.purchaseOrder}) : super(key: key);

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
            const Icon(Icons.shopping_basket, color: _blue, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(purchaseOrder.purchaseOrderNumber, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text('Purchase Order Details', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ])),
            _statusBadgeD(purchaseOrder.status),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 32),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section('Vendor Information', [
              _row('Vendor Name',  purchaseOrder.vendorName),
              _row('Email',        purchaseOrder.vendorEmail),
              _row('Phone',        purchaseOrder.vendorPhone),
            ]),
            const SizedBox(height: 24),
            _section('Purchase Order Information', [
              _row('PO Number',          purchaseOrder.purchaseOrderNumber),
              _row('Reference Number',   purchaseOrder.referenceNumber),
              _row('PO Date',            DateFormat('dd MMM yyyy').format(purchaseOrder.purchaseOrderDate)),
              _row('Expected Delivery',  purchaseOrder.expectedDeliveryDate != null ? DateFormat('dd MMM yyyy').format(purchaseOrder.expectedDeliveryDate!) : 'Not Set'),
              _row('Payment Terms',      purchaseOrder.paymentTerms),
              _row('Shipment Preference', purchaseOrder.shipmentPreference),
              _row('Delivery Address',   purchaseOrder.deliveryAddress),
              _row('Salesperson',        purchaseOrder.salesperson),
              _row('Subject',            purchaseOrder.subject),
            ]),
            const SizedBox(height: 24),
            if (purchaseOrder.items.isNotEmpty) _lineItems(purchaseOrder.items),
            const SizedBox(height: 24),
            _section('Amount Details', [
              _row('Subtotal',     '₹${purchaseOrder.subTotal.toStringAsFixed(2)}'),
              if (purchaseOrder.tdsAmount > 0) _row('TDS', '₹${purchaseOrder.tdsAmount.toStringAsFixed(2)}'),
              if (purchaseOrder.tcsAmount > 0) _row('TCS', '₹${purchaseOrder.tcsAmount.toStringAsFixed(2)}'),
              _row('CGST',         '₹${purchaseOrder.cgst.toStringAsFixed(2)}'),
              _row('SGST',         '₹${purchaseOrder.sgst.toStringAsFixed(2)}'),
              _row('IGST',         '₹${purchaseOrder.igst.toStringAsFixed(2)}'),
              _row('Total Amount', '₹${purchaseOrder.totalAmount.toStringAsFixed(2)}', isBold: true),
            ]),
            if (purchaseOrder.vendorNotes != null && purchaseOrder.vendorNotes!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _section('Vendor Notes', [
                Padding(padding: const EdgeInsets.all(8), child: Text(purchaseOrder.vendorNotes!, style: TextStyle(fontSize: 14, color: Colors.grey[800]))),
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

  static Widget _statusBadgeD(String status) {
    const map = <String, List<Color>>{
      'ISSUED':   [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'RECEIVED': [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'BILLED':   [Color(0xFFDCFCE7), Color(0xFF15803D)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(12)),
      child: Text(status.replaceAll('_', ' '), style: TextStyle(color: c[1], fontSize: 12, fontWeight: FontWeight.w600)),
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

  Widget _lineItems(List<PurchaseOrderItem> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Line Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!, width: 1),
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
          children: [
            TableRow(decoration: BoxDecoration(color: Colors.grey[200]), children: const [
              Padding(padding: EdgeInsets.all(12), child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12), child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(12), child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
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