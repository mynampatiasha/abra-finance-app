// ============================================================================
// BILL LIST PAGE
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat cards,
//   dark navy #0D1B3E table header, drag-to-scroll, ellipsis pagination)
// - Import  → BulkImportBillsDialog (template download + upload + validation)
// - Export  → Excel export
// - Share   → share_plus (web + mobile)
// - WhatsApp→ vendorPhone directly from Bill model → wa.me link
// - Raise Ticket → _RaiseTicketOverlay (employee search + assign)
// - Record Payment → opens NewPaymentMadeScreen
// - Lifecycle → asset image dialog with fallback diagram
// ============================================================================
// File: lib/screens/billing/bill_list_page.dart
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
import '../../../../core/services/bill_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_bill.dart';
import 'bill_detail_page.dart';
import 'new_payment_made.dart';

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

class BillListPage extends StatefulWidget {
  const BillListPage({Key? key}) : super(key: key);
  @override
  State<BillListPage> createState() => _BillListPageState();
}

class _BillListPageState extends State<BillListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<Bill>  _bills = [];
  BillStats?  _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String    _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;

  final List<String> _statusFilters = [
    'All','DRAFT','OPEN','PARTIALLY_PAID','PAID','OVERDUE','VOID',
  ];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage = 1;
  int _totalPages  = 1;
  int _totalBills  = 0;
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
    await Future.wait([_loadBills(), _loadStats()]);
  }

  Future<void> _loadBills() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final resp = await BillService.getBills(
        status:   _selectedStatus == 'All' ? null : _selectedStatus,
        page:     _currentPage,
        limit:    _itemsPerPage,
        search:   _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate:   _toDate,
      );
      setState(() {
        _bills      = resp.bills;
        _totalPages = resp.pagination.pages;
        _totalBills = resp.pagination.total;
        _isLoading  = false;
        _selectedIds.clear();
        _selectAll = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await BillService.getStats();
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
        _selectedIds.addAll(_bills.map((b) => b.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  void _toggleRow(String id) {
    setState(() {
      _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
      _selectAll = _selectedIds.length == _bills.length;
    });
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NewBillScreen()));
    if (ok == true) _loadAll();
  }

  void _openEdit(String id) async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewBillScreen(billId: id)));
    if (ok == true) _loadAll();
  }

  // ── view details ──────────────────────────────────────────────────────────

  void _viewDetails(Bill bill) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillDetailPage(billId: bill.id)),
    ).then((result) { if (result == true) _loadBills(); });
  }

  // ── bill actions ──────────────────────────────────────────────────────────

  Future<void> _submit(Bill bill) async {
    try {
      await BillService.submitBill(bill.id);
      _showSuccess('Bill submitted successfully');
      _loadAll();
    } catch (e) { _showError('Failed to submit: $e'); }
  }

  Future<void> _void(Bill bill) async {
    final ok = await _confirmDialog(
      title: 'Void Bill',
      message: 'Void bill ${bill.billNumber}? This cannot be undone.',
      confirmLabel: 'Void', confirmColor: _orange,
    );
    if (ok != true) return;
    try {
      await BillService.voidBill(bill.id);
      _showSuccess('Bill voided');
      _loadAll();
    } catch (e) { _showError('Failed to void: $e'); }
  }

  Future<void> _delete(Bill bill) async {
    final ok = await _confirmDialog(
      title: 'Delete Bill',
      message: 'Delete bill ${bill.billNumber}? This cannot be undone.',
      confirmLabel: 'Delete', confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await BillService.deleteBill(bill.id);
      _showSuccess('Bill deleted');
      _loadAll();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  Future<void> _downloadPDF(Bill bill) async {
    try {
      _showSuccess('Preparing PDF…');
      final pdfUrl = await BillService.downloadPDF(bill.id);
      if (kIsWeb) {
        final token = html.window.localStorage['flutter.jwt_token'] ?? '';
        if (token.isEmpty) { _showError('Authentication required. Please login again.'); return; }
        final response = await html.HttpRequest.request(
          pdfUrl, method: 'GET',
          requestHeaders: {'Authorization': 'Bearer $token', 'Content-Type': 'application/pdf'},
          responseType: 'blob',
        );
        if (response.status == 200) {
          final blob = response.response as html.Blob;
          final url  = html.Url.createObjectUrlFromBlob(blob);
          html.AnchorElement(href: url)
            ..setAttribute('download', '${bill.billNumber}.pdf')
            ..click();
          html.Url.revokeObjectUrl(url);
          _showSuccess('✅ PDF downloaded: ${bill.billNumber}');
        } else { throw 'Server returned ${response.status}'; }
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication); }
        else { throw 'Could not launch PDF viewer'; }
      }
    } catch (e) { _showError('PDF failed: $e'); }
  }

  // ── record payment — opens NewPaymentMadeScreen ───────────────────────────

  Future<void> _showRecordPaymentDialog(Bill bill) async {
    // Opens the full NewPaymentMadeScreen so the user can record
    // payment with all vendor bill details available on that screen.
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewPaymentMadeScreen()),
    );
    // Refresh bills list if a payment was recorded
    if (result == true) _loadAll();
  }

  Widget _paymentSummaryCol(String label, String value, Color valueColor) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: valueColor)),
    ]);
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _share(Bill bill) async {
    final text = 'Bill Details\n'
        '─────────────────────────\n'
        'Bill #  : ${bill.billNumber}\n'
        'Vendor  : ${bill.vendorName}\n'
        'Date    : ${DateFormat('dd MMM yyyy').format(bill.billDate)}\n'
        'Due Date: ${DateFormat('dd MMM yyyy').format(bill.dueDate)}\n'
        'Amount  : ₹${bill.totalAmount.toStringAsFixed(2)}\n'
        'Paid    : ₹${bill.amountPaid.toStringAsFixed(2)}\n'
        'Due     : ₹${bill.amountDue.toStringAsFixed(2)}\n'
        'Status  : ${bill.status}\n'
        'Terms   : ${bill.paymentTerms}';
    try {
      await Share.share(text, subject: 'Bill: ${bill.billNumber}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(Bill bill) async {
    final phone = (bill.vendorPhone ?? '').trim();
    if (phone.isEmpty) {
      _showError('Vendor phone not available on this bill. Please update the vendor profile.');
      return;
    }
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final msg = Uri.encodeComponent(
      'Hello ${bill.vendorName},\n\n'
      'Please find details of Bill ${bill.billNumber}:\n\n'
      'Bill Date : ${DateFormat('dd MMM yyyy').format(bill.billDate)}\n'
      'Due Date  : ${DateFormat('dd MMM yyyy').format(bill.dueDate)}\n'
      'Amount    : ₹${bill.totalAmount.toStringAsFixed(2)}\n'
      'Amount Due: ₹${bill.amountDue.toStringAsFixed(2)}\n'
      'Status    : ${bill.status}\n'
      '${bill.purchaseOrderNumber != null ? 'PO #      : ${bill.purchaseOrderNumber}\n' : ''}'
      '\nPlease feel free to contact us for any queries.\n'
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

  void _raiseTicket([Bill? bill]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        bill: bill,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError:        (msg) => _showError(msg),
      ),
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
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85, maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: _red,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
                  child: const Text('Bill Lifecycle Process',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                Expanded(child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  child: InteractiveViewer(
                    panEnabled: true, minScale: 0.5, maxScale: 4.0,
                    child: Center(child: Image.asset('assets/bill.png', fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => SingleChildScrollView(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.account_tree_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('Bill Lifecycle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                          const SizedBox(height: 20),
                          _buildFallbackDiagram(),
                        ])))),
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

  Widget _buildFallbackDiagram() {
    final stages = [
      {'label': 'DRAFT',          'color': Colors.grey,              'icon': Icons.edit_note},
      {'label': 'OPEN',           'color': Colors.blue,              'icon': Icons.description},
      {'label': 'PARTIALLY\nPAID','color': Colors.orange,            'icon': Icons.payment},
      {'label': 'PAID',           'color': Colors.green,             'icon': Icons.check_circle},
      {'label': 'OVERDUE',        'color': Colors.red,               'icon': Icons.warning},
      {'label': 'VOID',           'color': Colors.blueGrey,          'icon': Icons.cancel},
    ];
    return Column(children: [
      Wrap(
        alignment: WrapAlignment.center, spacing: 8, runSpacing: 8,
        children: [
          for (int i = 0; i < stages.length; i++) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (stages[i]['color'] as Color).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: stages[i]['color'] as Color, width: 2),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(stages[i]['icon'] as IconData, color: stages[i]['color'] as Color, size: 24),
                const SizedBox(height: 4),
                Text(stages[i]['label'] as String, style: TextStyle(color: stages[i]['color'] as Color, fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center),
              ]),
            ),
            if (i < stages.length - 1)
              Icon(Icons.arrow_forward, color: Colors.grey[400], size: 18),
          ],
        ],
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue[200]!)),
        child: const Text('Draft → Submit → Open → Record Payment → Partially Paid / Paid\nOverdue (past due date) | Void (cancel at any stage)',
            style: TextStyle(fontSize: 11), textAlign: TextAlign.center),
      ),
    ]);
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      if (_bills.isEmpty) { _showError('Nothing to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Date','Bill #','PO #','Vendor Name','Vendor Email','Status','Due Date','Payment Terms','Sub Total','TDS','TCS','CGST','SGST','Total Amount','Amount Paid','Amount Due','Notes'],
        ..._bills.map((b) => [
          DateFormat('dd/MM/yyyy').format(b.billDate),
          b.billNumber, b.purchaseOrderNumber ?? '',
          b.vendorName, b.vendorEmail ?? '',
          b.status,
          DateFormat('dd/MM/yyyy').format(b.dueDate),
          b.paymentTerms,
          b.subTotal.toStringAsFixed(2),
          b.tdsAmount.toStringAsFixed(2),
          b.tcsAmount.toStringAsFixed(2),
          b.cgst.toStringAsFixed(2),
          b.sgst.toStringAsFixed(2),
          b.totalAmount.toStringAsFixed(2),
          b.amountPaid.toStringAsFixed(2),
          b.amountDue.toStringAsFixed(2),
          b.notes ?? '',
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'bills_${DateFormat('yyyyMMdd').format(DateTime.now())}');
      _showSuccess('✅ Excel downloaded (${_bills.length} bills)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(context: context, builder: (_) => BulkImportBillsDialog(onImportComplete: _loadAll));
  }

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context, initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _fromDate = d; _currentPage = 1; }); _loadBills(); }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context, initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _toDate = d; _currentPage = 1; }); _loadBills(); }
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

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Bills', showBack: true),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _bills.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _bills.isNotEmpty) _buildPagination(),
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
    const SizedBox(width: 12),
    _searchField(width: 220),
    const SizedBox(width: 10),
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _loadBills(); }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _red, bg: _red.withOpacity(0.08)),
    const Spacer(),
    _actionBtn('New Bill', Icons.add_rounded, _red, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _bills.isEmpty ? null : _exportExcel),
    const SizedBox(width: 8),
    _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 190),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From', isActive: _fromDate != null, onTap: _pickFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To', isActive: _toDate != null, onTap: _pickToDate),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _loadBills(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _red, bg: _red.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Bill', Icons.add_rounded, _red, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _bills.isEmpty ? null : _exportExcel),
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
      _actionBtn('New', Icons.add_rounded, _red, _openNew),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _loadBills(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _red, bg: _red.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _bills.isEmpty ? null : _exportExcel),
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
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Bills' : s.replaceAll('_', ' ')))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _loadBills(); } },
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
          if (_searchQuery == v.toLowerCase()) _loadBills();
        });
      },
      decoration: InputDecoration(
        hintText: 'Search bill #, vendor, PO #…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchController.clear(); setState(() { _searchQuery = ''; _currentPage = 1; }); _loadBills(); })
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
    return Tooltip(message: tooltip, child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(width: 42, height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color)),
    ));
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
    final totalBills    = _stats?.totalBills    ?? 0;
    final totalPayable  = _stats?.totalPayable  ?? 0;
    final totalPaid     = _stats?.totalPaid     ?? 0;
    final totalDue      = _stats?.totalDue      ?? 0;

    final cards = [
      _StatCardData(label: 'Total Bills',    value: totalBills.toString(),        icon: Icons.receipt_long_rounded,       color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Total Payable',  value: '₹${_fmt(totalPayable)}',     icon: Icons.account_balance_wallet,     color: _red,    gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'Total Paid',     value: '₹${_fmt(totalPaid)}',        icon: Icons.check_circle_outline,       color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Amount Due',     value: '₹${_fmt(totalDue)}',         icon: Icons.warning_amber_rounded,      color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
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

  String _fmt(double v) {
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
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E), onChanged: _toggleSelectAll))),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('DATE'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('BILL #'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('PO #'))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('VENDOR'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('DUE DATE'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('AMOUNT'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('DUE'))),
                    const DataColumn(label: SizedBox(width: 150, child: Text('ACTIONS'))),
                  ],
                  rows: _bills.map((b) => _buildRow(b)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(Bill bill) {
    final isSel = _selectedIds.contains(bill.id);
    final isOverdue = bill.dueDate.isBefore(DateTime.now()) && bill.status != 'PAID' && bill.status != 'VOID';

    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleRow(bill.id))),

        // Date
        DataCell(SizedBox(width: 90, child: Text(DateFormat('dd/MM/yyyy').format(bill.billDate), style: const TextStyle(fontSize: 12)))),

        // Bill #
        DataCell(SizedBox(width: 130, child: InkWell(
          onTap: () => _openEdit(bill.id),
          child: Text(bill.billNumber, style: const TextStyle(color: _red, fontWeight: FontWeight.w600, fontSize: 12, decoration: TextDecoration.underline)),
        ))),

        // PO #
        DataCell(SizedBox(width: 100, child: Text(bill.purchaseOrderNumber ?? '-', style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis))),

        // Vendor
        DataCell(SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(bill.vendorName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
          if (bill.vendorEmail != null) Text(bill.vendorEmail!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),

        // Status
        DataCell(SizedBox(width: 110, child: _statusBadge(bill.status))),

        // Due Date
        DataCell(SizedBox(width: 90, child: Text(
          DateFormat('dd/MM/yyyy').format(bill.dueDate),
          style: TextStyle(fontSize: 12, color: isOverdue ? _red : null, fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal),
        ))),

        // Amount
        DataCell(SizedBox(width: 100, child: Text('₹${bill.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))),

        // Amount Due
        DataCell(SizedBox(width: 100, child: Text(
          '₹${bill.amountDue.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: bill.amountDue > 0 ? Colors.red[700] : Colors.green),
        ))),

        // Actions
        DataCell(SizedBox(width: 150, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _share(bill),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(bill),
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
              _menuItem('view',    Icons.visibility_outlined,           _blue,   'View Details'),
              _menuItem('edit',    Icons.edit_outlined,                 _navy,   'Edit'),
              if (bill.status == 'DRAFT')
                _menuItem('submit', Icons.send_outlined,                _green,  'Submit Bill'),
              if (['OPEN','PARTIALLY_PAID','OVERDUE'].contains(bill.status))
                _menuItem('payment', Icons.payment,                     _green,  'Record Payment'),
              _menuItem('pdf',     Icons.download_outlined,             _blue,   'Download PDF'),
              if (bill.status != 'PAID' && bill.status != 'VOID')
                _menuItem('void',  Icons.block_outlined,                _orange, 'Void Bill'),
              _menuItem('ticket',  Icons.confirmation_number_outlined,  _orange, 'Raise Ticket'),
              if (bill.status == 'DRAFT')
                _menuItem('delete', Icons.delete_outline,               _red,    'Delete', textColor: _red),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'view':    _viewDetails(bill);                 break;
                case 'edit':    _openEdit(bill.id);                 break;
                case 'submit':  _submit(bill);                      break;
                case 'payment': _showRecordPaymentDialog(bill);     break;
                case 'pdf':     _downloadPDF(bill);                 break;
                case 'void':    _void(bill);                        break;
                case 'ticket':  _raiseTicket(bill);                 break;
                case 'delete':  _delete(bill);                      break;
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
      'PAID':           [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'PARTIALLY_PAID': [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'OVERDUE':        [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'OPEN':           [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'DRAFT':          [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'VOID':           [Color(0xFFE2E8F0), Color(0xFF475569)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status.replaceAll('_', ' '), style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _totalBills)} of $_totalBills bills',
            style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _pageNavBtn(icon: Icons.chevron_left,  enabled: _currentPage > 1,           onTap: () { setState(() => _currentPage--); _loadBills(); }),
            const SizedBox(width: 4),
            if (pages.first > 1) ...[_pageNumBtn(1), if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400])))],
            ...pages.map((p) => _pageNumBtn(p)),
            if (pages.last < _totalPages) ...[if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))), _pageNumBtn(_totalPages)],
            const SizedBox(width: 4),
            _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _loadBills(); }),
          ]),
        ],
      ),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _loadBills(); } },
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
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _red.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.receipt_long_outlined, size: 64, color: _red.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Bills Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text('Create your first bill to get started', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(onPressed: _openNew, icon: const Icon(Icons.add),
          label: const Text('Create Bill', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Bills', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(onPressed: _loadAll, icon: const Icon(Icons.refresh),
          label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final Bill? bill;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.bill, required this.onTicketRaised, required this.onError});

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
    if (widget.bill == null) return 'A ticket has been raised regarding a bill and requires your attention.';
    final b = widget.bill!;
    return 'Bill "${b.billNumber}" from vendor "${b.vendorName}" requires attention.\n\n'
        'Bill Details:\n'
        '• Bill #     : ${b.billNumber}\n'
        '• Vendor     : ${b.vendorName}\n'
        '• Bill Date  : ${DateFormat('dd MMM yyyy').format(b.billDate)}\n'
        '• Due Date   : ${DateFormat('dd MMM yyyy').format(b.dueDate)}\n'
        '• Total      : ₹${b.totalAmount.toStringAsFixed(2)}\n'
        '• Amount Due : ₹${b.amountDue.toStringAsFixed(2)}\n'
        '• Status     : ${b.status}\n'
        '${b.purchaseOrderNumber != null ? '• PO #       : ${b.purchaseOrderNumber}\n' : ''}'
        '\nPlease review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    widget.bill != null ? 'Bill: ${widget.bill!.billNumber}' : 'Bills — Action Required',
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
                if (widget.bill != null) Text('Bill: ${widget.bill!.billNumber}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          // Body
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.bill != null) ...[
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: isSel ? color : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isSel ? color : Colors.grey[300]!),
                      boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : []),
                  child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700]))),
                ),
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
//  BULK IMPORT BILLS DIALOG
// =============================================================================

class BulkImportBillsDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportBillsDialog({Key? key, required this.onImportComplete}) : super(key: key);
  @override
  State<BulkImportBillsDialog> createState() => _BulkImportBillsDialogState();
}

class _BulkImportBillsDialogState extends State<BulkImportBillsDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = <List<dynamic>>[
        ['Bill Date* (dd/MM/yyyy)','Bill Number','PO Number','Vendor Name*','Vendor Email*','Vendor GSTIN','Due Date (dd/MM/yyyy)','Payment Terms*','Status*','Subject','Sub Total*','TDS Amount','TCS Amount','CGST','SGST','Total Amount*','Notes'],
        ['01/01/2025','BILL-2501-001','PO-001','ABC Supplies Pvt Ltd','accounts@abcsupplies.com','29XXXXX1234X1Z5','31/01/2025','Net 30','DRAFT','Office Supplies - Jan','100000.00','0.00','0.00','9000.00','9000.00','118000.00','Monthly supplies'],
        ['02/01/2025','BILL-2501-002','PO-002','XYZ Vendors Ltd','billing@xyzvendors.com','','28/02/2025','Net 15','DRAFT','Equipment Purchase','250000.00','0.00','0.00','22500.00','22500.00','295000.00','Bulk equipment order'],
        ['INSTRUCTIONS:','1. Fields marked * are required','2. Date format: dd/MM/yyyy','3. Status: DRAFT or OPEN','4. Payment Terms: Due on Receipt / Net 15 / Net 30 / Net 45 / Net 60','5. Total = SubTotal + CGST + SGST + TCS - TDS','6. Delete this row before uploading'],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'bills_import_template');
      setState(() => _downloading = false);
      _snack('Template downloaded!', _green);
    } catch (e) {
      setState(() => _downloading = false);
      _snack('Download failed: $e', _red);
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx','xls','csv'], allowMultiple: false, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) { _snack('Could not read file', _red); return; }
      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      List<List<dynamic>> rows;
      final ext = file.extension?.toLowerCase() ?? '';
      rows = ext == 'csv' ? _parseCSV(file.bytes!) : _parseExcel(file.bytes!);
      if (rows.length < 2) throw Exception('File needs header + data rows');

      final List<Map<String, dynamic>> valid  = [];
      final List<String>               errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty || _sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors   = <String>[];
        final billDate    = _parseDate(_gv(row, 0));
        final billNumber  = _sv(row, 1);
        final poNumber    = _sv(row, 2);
        final vendorName  = _sv(row, 3);
        final vendorEmail = _sv(row, 4);
        final gstin       = _sv(row, 5);
        final dueDate     = _parseDate(_gv(row, 6));
        final terms       = _sv(row, 7, 'Net 30');
        final status      = _sv(row, 8, 'DRAFT');
        final subject     = _sv(row, 9);
        final subTotal    = _pd(_gv(row, 10));
        final tds         = _pd(_gv(row, 11));
        final tcs         = _pd(_gv(row, 12));
        final cgst        = _pd(_gv(row, 13));
        final sgst        = _pd(_gv(row, 14));
        final total       = _pd(_gv(row, 15));
        final notes       = _sv(row, 16);

        if (billDate == null)    rowErrors.add('Bill Date required (dd/MM/yyyy)');
        if (vendorName.isEmpty)  rowErrors.add('Vendor Name required');
        if (vendorEmail.isEmpty) rowErrors.add('Vendor Email required');
        if (subTotal <= 0)       rowErrors.add('Sub Total must be > 0');
        if (total <= 0)          rowErrors.add('Total Amount must be > 0');
        if (!['DRAFT','OPEN'].contains(status.toUpperCase())) rowErrors.add('Status must be DRAFT or OPEN');

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        valid.add({
          'billDate':             billDate!.toIso8601String(),
          'billNumber':           billNumber,
          'purchaseOrderNumber':  poNumber,
          'vendorName':           vendorName,
          'vendorEmail':          vendorEmail,
          'vendorGSTIN':          gstin,
          'dueDate':              dueDate?.toIso8601String(),
          'paymentTerms':         terms,
          'status':               status.toUpperCase(),
          'subject':              subject,
          'subTotal':             subTotal,
          'tdsAmount':            tds,
          'tcsAmount':            tcs,
          'cgst':                 cgst,
          'sgst':                 sgst,
          'totalAmount':          total,
          'notes':                notes,
          'items':                [],
        });
      }

      if (valid.isEmpty) throw Exception('No valid rows found');

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valid.length} bill(s) will be imported.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${errors.length} row(s) skipped:', style: const TextStyle(color: _red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(constraints: const BoxConstraints(maxHeight: 160), decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red[200]!)), padding: const EdgeInsets.all(10),
                  child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 11, color: _red)))),
            ],
            const SizedBox(height: 12),
            const Text('Proceed with import?'),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
                child: const Text('Import')),
          ],
        ),
      );

      if (confirmed != true) { setState(() { _uploading = false; _fileName = null; }); return; }

      final importResult = await BillService.bulkImportBills(valid);
      setState(() {
        _uploading = false;
        _results = {
          'success': importResult['data']?['successCount'] ?? valid.length,
          'failed':  importResult['data']?['failedCount']  ?? 0,
          'total':   importResult['data']?['totalProcessed'] ?? valid.length,
          'errors':  importResult['data']?['errors'] ?? [],
        };
      });
      if (importResult['success'] == true) {
        _snack('✅ Import completed!', _green);
        await widget.onImportComplete();
      }
    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _snack('Import failed: $e', _red);
    }
  }

  dynamic _gv(List<dynamic> row, int i) => i < row.length ? row[i] : null;
  String _sv(List<dynamic> row, int i, [String def = '']) {
    if (i >= row.length || row[i] == null) return def;
    return row[i].toString().trim();
  }
  double _pd(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    try { return double.parse(v.toString().trim()); } catch (_) { return 0.0; }
  }
  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    for (final fmt in ['dd/MM/yyyy','dd-MM-yyyy','yyyy-MM-dd','MM/dd/yyyy']) {
      try { return DateFormat(fmt).parse(s); } catch (_) {}
    }
    return null;
  }
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
    return utf8.decode(bytes, allowMalformed: true).split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).map(_parseCSVLine).toList();
  }
  List<String> _parseCSVLine(String line) {
    final fields = <String>[]; final buf = StringBuffer(); bool inQ = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') { if (inQ && i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; } else { inQ = !inQ; } }
      else if (ch == ',' && !inQ) { fields.add(buf.toString().trim()); buf.clear(); }
      else { buf.write(ch); }
    }
    fields.add(buf.toString().trim());
    return fields;
  }
  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(width: MediaQuery.of(context).size.width > 620
          ? 580
          : MediaQuery.of(context).size.width * 0.92, padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
            const SizedBox(width: 14),
            const Text('Import Bills', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),
          _importStep(step: '1', color: _blue, icon: Icons.download_rounded, title: 'Download Template',
              subtitle: 'Get the Excel template with all required columns.', buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
              onPressed: _downloading || _uploading ? null : _downloadTemplate),
          const SizedBox(height: 16),
          _importStep(step: '2', color: _green, icon: Icons.upload_rounded, title: 'Upload Filled File',
              subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).', buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'),
              onPressed: _downloading || _uploading ? null : _uploadFile),
          if (_fileName != null) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
                child: Row(children: [Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)))])),
          ],
          if (_results != null) ...[
            const Divider(height: 28),
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                _resultRow('Total Processed',      '${_results!['total']}',   _blue),
                const SizedBox(height: 8),
                _resultRow('Successfully Imported', '${_results!['success']}', _green),
                const SizedBox(height: 8),
                _resultRow('Failed',                '${_results!['failed']}',  _red),
                if ((_results!['errors'] as List).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: _red)),
                  const SizedBox(height: 6),
                  Container(constraints: const BoxConstraints(maxHeight: 120), child: SingleChildScrollView(
                      child: Text((_results!['errors'] as List).join('\n'), style: const TextStyle(fontSize: 11, color: _red)))),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)))),
          ],
        ]),
      ),
    );
  }

  Widget _importStep({required String step, required Color color, required IconData icon, required String title, required String subtitle, required String buttonLabel, required VoidCallback? onPressed}) {
    final circle = Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 4),
      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
    final button = ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 16), label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, disabledBackgroundColor: color.withOpacity(0.5), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
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
      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
    ]);
  }
}

// =============================================================================
//  BILL DETAILS DIALOG  (preserved from original — full implementation)
// =============================================================================

class BillDetailsDialog extends StatelessWidget {
  final Bill bill;
  const BillDetailsDialog({Key? key, required this.bill}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.88,
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long, color: _red, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bill.billNumber, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text('Bill Details', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ])),
            _statusChip(bill.status),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 28),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section('Vendor Information', [
              _row('Vendor Name', bill.vendorName),
              _row('Email', bill.vendorEmail),
              _row('Phone', bill.vendorPhone),
              _row('GSTIN', bill.vendorGSTIN),
            ]),
            const SizedBox(height: 20),
            _section('Bill Information', [
              _row('Bill Number', bill.billNumber),
              _row('PO Number', bill.purchaseOrderNumber),
              _row('Bill Date', DateFormat('dd MMM yyyy').format(bill.billDate)),
              _row('Due Date', DateFormat('dd MMM yyyy').format(bill.dueDate)),
              _row('Payment Terms', bill.paymentTerms),
              _row('Subject', bill.subject),
            ]),
            const SizedBox(height: 20),
            if (bill.items.isNotEmpty) ...[_lineItemsSection(bill.items), const SizedBox(height: 20)],
            _section('Amount Details', [
              _row('Sub Total',     '₹${bill.subTotal.toStringAsFixed(2)}'),
              if (bill.tdsAmount > 0) _row('TDS', '₹${bill.tdsAmount.toStringAsFixed(2)}'),
              if (bill.tcsAmount > 0) _row('TCS', '₹${bill.tcsAmount.toStringAsFixed(2)}'),
              _row('CGST', '₹${bill.cgst.toStringAsFixed(2)}'),
              _row('SGST', '₹${bill.sgst.toStringAsFixed(2)}'),
              _row('Total Amount', '₹${bill.totalAmount.toStringAsFixed(2)}', isBold: true),
              _row('Amount Paid',  '₹${bill.amountPaid.toStringAsFixed(2)}'),
              _row('Amount Due',   '₹${bill.amountDue.toStringAsFixed(2)}', isBold: true, color: bill.amountDue > 0 ? Colors.red[700] : Colors.green),
            ]),
            if (bill.payments.isNotEmpty) ...[const SizedBox(height: 20), _paymentsSection(bill.payments)],
            if (bill.notes != null && bill.notes!.isNotEmpty) ...[
              const SizedBox(height: 20),
              _section('Notes', [Padding(padding: const EdgeInsets.all(8), child: Text(bill.notes!, style: TextStyle(fontSize: 14, color: Colors.grey[800])))]),
            ],
          ]))),
          const Divider(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]),
        ]),
      ),
    );
  }

  Widget _statusChip(String status) {
    const map = <String, List<Color>>{
      'PAID':           [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'PARTIALLY_PAID': [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'OVERDUE':        [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'OPEN':           [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
      'DRAFT':          [Color(0xFFF1F5F9), Color(0xFF64748B)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(12)),
        child: Text(status, style: TextStyle(color: c[1], fontSize: 12, fontWeight: FontWeight.w600)));
  }

  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
          child: Column(children: children)),
    ]);
  }

  Widget _row(String label, dynamic value, {bool isBold = false, Color? color}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 160, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2C3E50), fontSize: 13))),
      Expanded(child: Text(value.toString(), style: TextStyle(color: color ?? Colors.grey[800], fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
    ]));
  }

  Widget _lineItemsSection(List<BillItem> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Line Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 10),
      Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!, width: 1),
          columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1)},
          children: [
            TableRow(decoration: BoxDecoration(color: Colors.grey[200]), children: const [
              Padding(padding: EdgeInsets.all(10), child: Text('Item',   style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(10), child: Text('Qty',    style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(10), child: Text('Rate',   style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(10), child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
            ...items.map((item) => TableRow(children: [
              Padding(padding: const EdgeInsets.all(10), child: Text(item.itemDetails)),
              Padding(padding: const EdgeInsets.all(10), child: Text(item.quantity.toString())),
              Padding(padding: const EdgeInsets.all(10), child: Text('₹${item.rate.toStringAsFixed(2)}')),
              Padding(padding: const EdgeInsets.all(10), child: Text('₹${item.amount.toStringAsFixed(2)}')),
            ])),
          ],
        )),
    ]);
  }

  Widget _paymentsSection(List<BillPayment> payments) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Payment History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 10),
      Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!, width: 1),
          columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(1)},
          children: [
            TableRow(decoration: BoxDecoration(color: Colors.grey[200]), children: const [
              Padding(padding: EdgeInsets.all(10), child: Text('Date',      style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(10), child: Text('Mode',      style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(10), child: Text('Reference', style: TextStyle(fontWeight: FontWeight.bold))),
              Padding(padding: EdgeInsets.all(10), child: Text('Amount',    style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
            ...payments.map((p) => TableRow(children: [
              Padding(padding: const EdgeInsets.all(10), child: Text(DateFormat('dd MMM yyyy').format(p.paymentDate))),
              Padding(padding: const EdgeInsets.all(10), child: Text(p.paymentMode)),
              Padding(padding: const EdgeInsets.all(10), child: Text(p.referenceNumber ?? '-')),
              Padding(padding: const EdgeInsets.all(10), child: Text('₹${p.amount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600))),
            ])),
          ],
        )),
    ]);
  }
}