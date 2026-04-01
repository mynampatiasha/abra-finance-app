// ============================================================================
// QUOTES LIST PAGE
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat
//   cards, dark navy table, ellipsis pagination)
// - Import button  → BulkImportQuotesDialog (template download + upload +
//   row validation + QuoteService.bulkImportQuotes)
// - Export button  → Excel export
// - Raise Ticket   → row PopupMenu → overlay card with employee search +
//                    assign + auto message
// - Share button   → share_plus (web + mobile)
// - WhatsApp       → url_launcher wa.me link (customerPhone, web + mobile)
// ============================================================================
// File: lib/screens/billing/quotes_list_page.dart
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
import '../../../../core/services/quote_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_quote.dart';
import 'quote_detail_page.dart';

// ─── colour palette ──────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);

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

class QuotesListPage extends StatefulWidget {
  const QuotesListPage({Key? key}) : super(key: key);
  @override
  State<QuotesListPage> createState() => _QuotesListPageState();
}

class _QuotesListPageState extends State<QuotesListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<Quote> _quotes   = [];
  QuoteStats? _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String   _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;

  final List<String> _statusFilters = [
    'All', 'DRAFT', 'SENT', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'CONVERTED'
  ];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  int _totalQuotes  = 0;
  final int _itemsPerPage = 20;

  // ── selection ─────────────────────────────────────────────────────────────
  final Set<String> _selectedQuotes = {};
  bool _selectAll = false;

  // ── scroll controllers ────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadQuotes();
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

  Future<void> _loadQuotes() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await QuoteService.getQuotes(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage,
        limit: _itemsPerPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate: _toDate,
      );
      setState(() {
        _quotes     = response.quotes;
        _totalPages = response.pagination.pages;
        _totalQuotes = response.pagination.total;
        _isLoading  = false;
        _selectedQuotes.clear();
        _selectAll = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await QuoteService.getStats();
      setState(() => _stats = s);
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await Future.wait([_loadQuotes(), _loadStats()]);
    _showSuccess('Data refreshed');
  }

  // ── filters / search ──────────────────────────────────────────────────────

  void _filterByStatus(String status) {
    setState(() { _selectedStatus = status; _currentPage = 1; });
    _loadQuotes();
  }

  void _clearDateFilters() {
    setState(() { _fromDate = null; _toDate = null; });
    _loadQuotes();
  }

  // ── selection ─────────────────────────────────────────────────────────────

  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      if (_selectAll) {
        _selectedQuotes.addAll(_quotes.map((q) => q.id));
      } else {
        _selectedQuotes.clear();
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      _selectedQuotes.contains(id) ? _selectedQuotes.remove(id) : _selectedQuotes.add(id);
      _selectAll = _selectedQuotes.length == _quotes.length;
    });
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NewQuoteScreen()));
    if (ok == true) _refresh();
  }

  void _openEdit(String quoteId) async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewQuoteScreen(quoteId: quoteId)));
    if (ok == true) _refresh();
  }

  // ── quote actions ─────────────────────────────────────────────────────────

  void _viewDetails(Quote q) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuoteDetailPage(quoteId: q.id)),
    ).then((result) { if (result == true) _refresh(); });
  }

  Future<void> _sendQuote(Quote q) async {
    try {
      await QuoteService.sendQuote(q.id);
      _showSuccess('Quote sent to ${q.customerEmail}');
      _refresh();
    } catch (e) { _showError('Failed to send: $e'); }
  }

  Future<void> _downloadPDF(Quote q) async {
    try {
      _showSuccess('Preparing PDF…');
      final url = await QuoteService.downloadPDF(q.id);
      if (kIsWeb) {
        html.AnchorElement(href: url)
          ..setAttribute('download', '${q.quoteNumber}.pdf')
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

  Future<void> _convertToInvoice(Quote q) async {
    if (q.status == 'CONVERTED') { _showError('Already converted'); return; }
    if (q.status != 'ACCEPTED' && q.status != 'SENT') {
      _showError('Only ACCEPTED or SENT quotes can be converted');
      return;
    }
    final ok = await _confirmDialog(
      title: 'Convert to Invoice',
      message: 'Convert ${q.quoteNumber} to an invoice?',
      confirmLabel: 'Convert',
      confirmColor: _green,
    );
    if (ok != true) return;
    try {
      await QuoteService.convertToInvoice(q.id);
      _showSuccess('Quote converted to invoice');
      _refresh();
      if (mounted) Navigator.pushReplacementNamed(context, '/admin/billing/invoices');
    } catch (e) { _showError('Failed to convert: $e'); }
  }

  Future<void> _convertToSalesOrder(Quote q) async {
    if (q.status == 'CONVERTED') { _showError('Already converted'); return; }
    if (q.status != 'ACCEPTED' && q.status != 'SENT') {
      _showError('Only ACCEPTED or SENT quotes can be converted');
      return;
    }
    final ok = await _confirmDialog(
      title: 'Convert to Sales Order',
      message: 'Convert ${q.quoteNumber} to a sales order?',
      confirmLabel: 'Convert',
      confirmColor: _blue,
    );
    if (ok != true) return;
    try {
      await QuoteService.convertToSalesOrder(q.id);
      _showSuccess('Quote converted to sales order');
      _refresh();
    } catch (e) { _showError('Failed to convert: $e'); }
  }

  Future<void> _acceptQuote(Quote q) async {
    try {
      await QuoteService.acceptQuote(q.id);
      _showSuccess('Quote marked as accepted');
      _refresh();
    } catch (e) { _showError('Failed to accept: $e'); }
  }

  Future<void> _declineQuote(Quote q) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline Quote', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Decline ${q.quoteNumber}?'),
          const SizedBox(height: 16),
          TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()),
            maxLines: 3,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await QuoteService.declineQuote(q.id, reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim());
        _showSuccess('Quote declined');
        _refresh();
      } catch (e) { _showError('Failed to decline: $e'); }
    }
  }

  Future<void> _cloneQuote(Quote q) async {
    try {
      await QuoteService.cloneQuote(q.id);
      _showSuccess('Quote duplicated');
      _refresh();
    } catch (e) { _showError('Failed to duplicate: $e'); }
  }

  Future<void> _deleteQuote(Quote q) async {
    final ok = await _confirmDialog(
      title: 'Delete Quote',
      message: 'Delete ${q.quoteNumber}? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await QuoteService.deleteQuote(q.id);
      _showSuccess('Quote deleted');
      _refresh();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _shareQuote(Quote q) async {
    final text = 'Quote Details\n'
        '─────────────────────────\n'
        'Quote # : ${q.quoteNumber}\n'
        'Customer: ${q.customerName}\n'
        'Email   : ${q.customerEmail ?? '-'}\n'
        'Subject : ${q.subject ?? '-'}\n'
        'Amount  : ₹${q.totalAmount.toStringAsFixed(2)}\n'
        'Status  : ${q.status}\n'
        'Expiry  : ${DateFormat('dd MMM yyyy').format(q.expiryDate)}\n'
        'Date    : ${DateFormat('dd MMM yyyy').format(q.quoteDate)}';
    try {
      await Share.share(text, subject: 'Quote: ${q.quoteNumber}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(Quote q) async {
    final phone = (q.customerPhone ?? '').trim();
    if (phone.isEmpty) {
      _showError('Customer phone not available for this quote.');
      return;
    }
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final msg = Uri.encodeComponent(
      'Hello ${q.customerName},\n\n'
      'Please find below your quote details from Abra Travels:\n\n'
      'Quote Number : ${q.quoteNumber}\n'
      'Amount       : ₹${q.totalAmount.toStringAsFixed(2)}\n'
      'Valid Until  : ${DateFormat('dd MMM yyyy').format(q.expiryDate)}\n'
      'Status       : ${q.status}\n\n'
      '${q.subject != null ? 'Subject: ${q.subject}\n\n' : ''}'
      'Please contact us for any queries.\nThank you!',
    );
    final url = Uri.parse('https://wa.me/$cleaned?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket(Quote q) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        quote: q,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError: (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _exportToExcel() async {
    try {
      if (_quotes.isEmpty) { _showError('No quotes to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Date','Quote#','Reference#','Customer','Email','Status','Expiry','Sub Total','CGST','SGST','IGST','Total Amount'],
        ..._quotes.map((q) => [
          DateFormat('dd/MM/yyyy').format(q.quoteDate),
          q.quoteNumber,
          q.referenceNumber ?? '',
          q.customerName,
          q.customerEmail ?? '',
          q.status,
          DateFormat('dd/MM/yyyy').format(q.expiryDate),
          q.subTotal.toStringAsFixed(2),
          q.cgst.toStringAsFixed(2),
          q.sgst.toStringAsFixed(2),
          q.igst.toStringAsFixed(2),
          q.totalAmount.toStringAsFixed(2),
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'quotes');
      _showSuccess('✅ Excel downloaded (${_quotes.length} quotes)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportQuotesDialog(onImportComplete: _refresh),
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
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF3498DB),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                ),
                child: const Text('Quote Lifecycle Process',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              ),
              Expanded(child: Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                child: InteractiveViewer(
                  panEnabled: true, minScale: 0.5, maxScale: 4.0,
                  child: Center(child: Image.asset('assets/qoute.png', fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.broken_image_outlined, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('Image not found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    ]),
                  )),
                ),
              )),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.grey[100],
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                child: Text('Tip: Pinch to zoom, drag to pan',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center),
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

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _fromDate = d; _currentPage = 1; }); _loadQuotes(); }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _toDate = d; _currentPage = 1; }); _loadQuotes(); }
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
      appBar: AppTopBar(title: 'Quotes'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _quotes.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _quotes.isNotEmpty) _buildPagination(),
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
      _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _loadQuotes(); }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_rounded, _showLifecycleDialog, tooltip: 'View Quote Process', color: _navy, bg: _navy.withOpacity(0.08)),
    const Spacer(),
    _actionBtn('New Quote', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _quotes.isEmpty ? null : _exportToExcel),
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
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _loadQuotes(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_rounded, _showLifecycleDialog, tooltip: 'Lifecycle', color: _navy, bg: _navy.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Quote', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _quotes.isEmpty ? null : _exportToExcel),
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
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _loadQuotes(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_rounded, _showLifecycleDialog, color: _navy, bg: _navy.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _quotes.isEmpty ? null : _exportToExcel),
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
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Quotes' : s))).toList(),
        onChanged: (v) { if (v != null) _filterByStatus(v); },
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
          if (_searchQuery == v.toLowerCase()) _loadQuotes();
        });
      },
      decoration: InputDecoration(
        hintText: 'Search quotes…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchController.clear(); setState(() { _searchQuery = ''; _currentPage = 1; }); _loadQuotes(); })
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
    final total     = _stats?.totalQuotes ?? 0;
    final accepted  = _stats?.acceptedQuotes ?? 0;
    final pending   = _stats?.sentQuotes ?? 0;
    final value     = _stats?.totalValue ?? 0.0;
    final converted = _stats?.convertedQuotes ?? 0;

    final cards = [
      _StatCardData(label: 'Total Quotes',  value: total.toString(),    icon: Icons.description_outlined,  color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Accepted',      value: accepted.toString(), icon: Icons.check_circle_outline,  color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Sent / Pending',value: pending.toString(),  icon: Icons.send_outlined,         color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Converted',     value: converted.toString(),icon: Icons.swap_horiz_rounded,    color: _purple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
      _StatCardData(label: 'Total Value',   value: '₹${(value / 1000).toStringAsFixed(0)}K', icon: Icons.currency_rupee, color: _blue, gradientColors: const [Color(0xFF5DADE2), Color(0xFF2980B9)]),
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
                    const DataColumn(label: Text('DATE')),
                    const DataColumn(label: Text('QUOTE #')),
                    const DataColumn(label: Text('REFERENCE #')),
                    const DataColumn(label: Text('CUSTOMER')),
                    const DataColumn(label: Text('STATUS')),
                    const DataColumn(label: Text('EXPIRY')),
                    const DataColumn(label: Text('AMOUNT')),
                    const DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _quotes.map((q) => _buildRow(q)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(Quote q) {
    final isSel = _selectedQuotes.contains(q.id);
    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        // Checkbox
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleSelection(q.id))),

        // Date
        DataCell(SizedBox(width: 100, child: Text(DateFormat('dd/MM/yyyy').format(q.quoteDate), style: const TextStyle(fontSize: 13)))),

        // Quote number (clickable)
        DataCell(SizedBox(width: 130, child: InkWell(
          onTap: () => _openEdit(q.id),
          child: Text(q.quoteNumber,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
        ))),

        // Reference
        DataCell(SizedBox(width: 120, child: Text(q.referenceNumber ?? '-', style: TextStyle(fontSize: 13, color: Colors.grey[600])))),

        // Customer
        DataCell(SizedBox(width: 170, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(q.customerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          if (q.customerEmail != null)
            Text(q.customerEmail!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),

        // Status
DataCell(SizedBox(width: 160, child: _statusBadge(
  q.status,
  convertedToInvoice: q.convertedToInvoice,
  convertedToSalesOrder: q.convertedToSalesOrder,
))),

        // Expiry
        DataCell(SizedBox(width: 100, child: Text(DateFormat('dd/MM/yyyy').format(q.expiryDate), style: const TextStyle(fontSize: 13)))),

        // Amount
        DataCell(SizedBox(width: 115, child: Text('₹${q.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right))),

        // Actions
        DataCell(SizedBox(width: 150, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _shareQuote(q),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(q),
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
              _menuItem('view',    Icons.visibility_outlined,      _blue,   'View Details'),
              _menuItem('edit',    Icons.edit_outlined,            _navy,   'Edit'),
              if (q.status == 'SENT' || q.status == 'DRAFT')
                _menuItem('send',  Icons.send_outlined,            _orange, 'Send Quote'),
              _menuItem('download', Icons.download_outlined,       _green,  'Download PDF'),
if (q.status == 'ACCEPTED' || q.status == 'SENT') ...[
  if (q.convertedToInvoice != true)
    _menuItem('convert_invoice', Icons.receipt_long_outlined, _green, 'Convert to Invoice'),
  if (q.convertedToSalesOrder != true)
    _menuItem('convert_so', Icons.shopping_cart_outlined, _navy, 'Convert to Sales Order'),
],
              if (q.status == 'SENT') ...[
                _menuItem('accept',  Icons.check_circle_outline, _green, 'Mark as Accepted'),
                _menuItem('decline', Icons.cancel_outlined,      _red,   'Mark as Declined', textColor: _red),
              ],
              _menuItem('clone',  Icons.copy_outlined,            const Color(0xFF7F8C8D), 'Duplicate'),
              _menuItem('ticket', Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
              _menuItem('delete', Icons.delete_outline,           _red,   'Delete', textColor: _red),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'view':             _viewDetails(q);       break;
                case 'edit':             _openEdit(q.id);       break;
                case 'send':             _sendQuote(q);         break;
                case 'download':         _downloadPDF(q);       break;
                case 'convert_invoice':  _convertToInvoice(q);  break;
                case 'convert_so':       _convertToSalesOrder(q); break;
                case 'accept':           _acceptQuote(q);       break;
                case 'decline':          _declineQuote(q);      break;
                case 'clone':            _cloneQuote(q);        break;
                case 'ticket':           _raiseTicket(q);       break;
                case 'delete':           _deleteQuote(q);       break;
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
Widget _statusBadge(String status, {bool? convertedToInvoice, bool? convertedToSalesOrder}) {
  const map = <String, List<Color>>{
    'ACCEPTED':  [Color(0xFFDCFCE7), Color(0xFF15803D)],
    'SENT':      [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
    'DRAFT':     [Color(0xFFF1F5F9), Color(0xFF64748B)],
    'DECLINED':  [Color(0xFFFEE2E2), Color(0xFFDC2626)],
    'EXPIRED':   [Color(0xFFFEF3C7), Color(0xFFB45309)],
    'CONVERTED': [Color(0xFFF3E8FF), Color(0xFF7C3AED)],
  };
  final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];

  final chips = <Widget>[
    // Main status chip
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c[0],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c[1].withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 10)),
      ]),
    ),
  ];

  if (status == 'CONVERTED') {
    if (convertedToInvoice == true)
      chips.add(_subBadge('Inv', const Color(0xFFDCFCE7), const Color(0xFF15803D), Icons.receipt_long));
    if (convertedToSalesOrder == true)
      chips.add(_subBadge('SO', const Color(0xFFDBEAFE), const Color(0xFF1D4ED8), Icons.shopping_cart));
  }

  return Wrap(
    spacing: 4,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: chips,
  );
}

Widget _subBadge(String label, Color bg, Color textColor, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: textColor.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 9, color: textColor),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 9)),
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
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–${(_currentPage * _itemsPerPage).clamp(0, _totalQuotes)} of $_totalQuotes',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); _loadQuotes(); }),
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
              _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); _loadQuotes(); }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _currentPage = page); _loadQuotes(); } },
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
          child: Icon(Icons.description_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Quotes Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text('Create your first quote to get started', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _openNew,
        icon: const Icon(Icons.add),
        label: const Text('Create Quote', style: TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Quotes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
  final Quote quote;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({required this.quote, required this.onTicketRaised, required this.onError});

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
    final q = widget.quote;
    return 'Quote "${q.quoteNumber}" for customer "${q.customerName}" '
           '(${q.customerEmail ?? 'N/A'}) requires attention.\n\n'
           'Quote Details:\n'
           '• Subject: ${q.subject ?? 'N/A'}\n'
           '• Amount: ₹${q.totalAmount.toStringAsFixed(2)}\n'
           '• Status: ${q.status}\n'
           '• Quote Date: ${DateFormat('dd MMM yyyy').format(q.quoteDate)}\n'
           '• Expiry Date: ${DateFormat('dd MMM yyyy').format(q.expiryDate)}\n'
           '${q.referenceNumber != null ? '• Reference: ${q.referenceNumber}\n' : ''}'
           '\nPlease review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: 'Quote: ${widget.quote.quoteNumber}',
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
                Text('Quote: ${widget.quote.quoteNumber}',
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
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5)),
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
//  BULK IMPORT QUOTES DIALOG
// =============================================================================

class BulkImportQuotesDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportQuotesDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportQuotesDialog> createState() => _BulkImportQuotesDialogState();
}

class _BulkImportQuotesDialogState extends State<BulkImportQuotesDialog> {
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
          'Quote Date* (dd/MM/yyyy)',
          'Quote Number*',
          'Reference Number',
          'Customer Name*',
          'Customer Email*',
          'Customer Phone*',
          'Expiry Date* (dd/MM/yyyy)',
          'Status* (DRAFT/SENT/ACCEPTED/DECLINED/EXPIRED)',
          'Salesperson',
          'Project Name',
          'Subject*',
          'Sub Total*',
          'CGST',
          'SGST',
          'IGST',
          'TDS Amount',
          'TCS Amount',
          'Total Amount*',
          'Customer Notes',
          'Terms and Conditions',
        ],
        // Example row 1
        [
          '01/01/2025',
          'QT-2025-001',
          'REF-001',
          'ABC Corporation',
          'contact@abccorp.com',
          '9876543210',
          '31/01/2025',
          'DRAFT',
          'John Sales',
          'Website Development',
          'Quotation for Website Development Services',
          '100000.00',
          '9000.00',
          '9000.00',
          '0.00',
          '0.00',
          '0.00',
          '118000.00',
          'Please review and let us know if you have any questions.',
          'Payment terms: 50% advance, 50% on completion. Validity: 30 days.',
        ],
        // Example row 2
        [
          '02/01/2025',
          'QT-2025-002',
          'REF-002',
          'XYZ Enterprises',
          'info@xyz.com',
          '9123456789',
          '15/02/2025',
          'SENT',
          'Jane Sales',
          'Mobile App',
          'Quote for Mobile Application Development',
          '250000.00',
          '22500.00',
          '22500.00',
          '0.00',
          '0.00',
          '0.00',
          '295000.00',
          'Looking forward to working with you.',
          'Payment: 30% advance, 40% on milestone, 30% on delivery.',
        ],
        // Instructions
        [
          'INSTRUCTIONS:',
          '* = required fields',
          'Date format must be dd/MM/yyyy',
          'Status: DRAFT, SENT, ACCEPTED, DECLINED, EXPIRED, CONVERTED',
          'Phone must be 10 digits',
          'Email must be valid format',
          'All amounts must be numbers',
          'Total = SubTotal + CGST + SGST + IGST + TCS - TDS',
          'Delete this instruction row before uploading',
        ],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'quotes_import_template');
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

      List<List<dynamic>> rows;
      final ext = file.extension?.toLowerCase() ?? '';
      rows = (ext == 'csv') ? _parseCSV(bytes) : _parseExcel(bytes);

      if (rows.length < 2) throw Exception('File must have a header row + at least one data row');

      final List<Map<String, dynamic>> valid  = [];
      final List<String>               errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty) continue;
        if (_sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors = <String>[];

        final quoteDate    = _parseDate(_sv(row, 0));
        final quoteNumber  = _sv(row, 1);
        final refNumber    = _sv(row, 2);
        final custName     = _sv(row, 3);
        final custEmail    = _sv(row, 4);
        final custPhone    = _parsePhone(_sv(row, 5));
        final expiryDate   = _parseDate(_sv(row, 6));
        final status       = _sv(row, 7, 'DRAFT').toUpperCase();
        final salesperson  = _sv(row, 8);
        final projectName  = _sv(row, 9);
        final subject      = _sv(row, 10);
        final subTotal     = _parseDouble(_sv(row, 11));
        final cgst         = _parseDouble(_sv(row, 12));
        final sgst         = _parseDouble(_sv(row, 13));
        final igst         = _parseDouble(_sv(row, 14));
        final tdsAmount    = _parseDouble(_sv(row, 15));
        final tcsAmount    = _parseDouble(_sv(row, 16));
        final totalAmount  = _parseDouble(_sv(row, 17));
        final custNotes    = _sv(row, 18);
        final terms        = _sv(row, 19);

        if (quoteDate == null)   rowErrors.add('Quote Date required (dd/MM/yyyy)');
        if (quoteNumber.isEmpty) rowErrors.add('Quote Number required');
        if (custName.isEmpty)    rowErrors.add('Customer Name required');
        if (custEmail.isEmpty)   rowErrors.add('Customer Email required');
        else if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(custEmail)) rowErrors.add('Invalid email');
        if (custPhone.isEmpty)   rowErrors.add('Customer Phone required');
        else if (custPhone.length < 10) rowErrors.add('Phone must be 10 digits');
        if (expiryDate == null)  rowErrors.add('Expiry Date required (dd/MM/yyyy)');
        if (subject.isEmpty)     rowErrors.add('Subject required');
        if (subTotal <= 0)       rowErrors.add('Sub Total must be > 0');
        if (totalAmount <= 0)    rowErrors.add('Total Amount must be > 0');
        final validStatuses = ['DRAFT','SENT','ACCEPTED','DECLINED','EXPIRED','CONVERTED'];
        if (!validStatuses.contains(status)) rowErrors.add('Invalid status');

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        valid.add({
          'quoteDate':      quoteDate!.toIso8601String(),
          'quoteNumber':    quoteNumber,
          'referenceNumber': refNumber,
          'customerName':   custName,
          'customerEmail':  custEmail,
          'customerPhone':  custPhone,
          'expiryDate':     expiryDate!.toIso8601String(),
          'status':         status,
          'salesperson':    salesperson,
          'projectName':    projectName,
          'subject':        subject,
          'subTotal':       subTotal,
          'cgst':           cgst,
          'sgst':           sgst,
          'igst':           igst,
          'tdsAmount':      tdsAmount,
          'tcsAmount':      tcsAmount,
          'totalAmount':    totalAmount,
          'customerNotes':  custNotes,
          'termsConditions': terms,
        });
      }

      if (valid.isEmpty) throw Exception('No valid quote data found');

      // Confirm dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Import', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${valid.length} quote(s) will be imported.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
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

      // Call bulk import API
      final importResult = await QuoteService.bulkImportQuotes(valid);

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
        _showSnack('✅ ${_results!['success']} quote(s) imported!', _green);
        await widget.onImportComplete();
      }
      if ((_results!['failed'] ?? 0) > 0) {
        _showSnack('⚠ ${_results!['failed']} failed to import', _orange);
      }

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

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

  double _parseDouble(String s) {
    if (s.isEmpty) return 0.0;
    return double.tryParse(s.replaceAll(',', '')) ?? 0.0;
  }

  String _parsePhone(String s) {
    if (s.isEmpty) return '';
    // Handle scientific notation (e.g. 9.88E+09)
    if (s.toUpperCase().contains('E')) {
      try { return double.parse(s).round().toString(); } catch (_) {}
    }
    // Remove decimal if any
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
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24),
            ),
            const SizedBox(width: 14),
            const Text('Import Quotes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),

          // Step 1
          _importStep(
            step: '1', color: _blue, icon: Icons.download_rounded,
            title: 'Download Template',
            subtitle: 'Get the Excel template with required columns and example rows.',
            buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
            onPressed: _downloading || _uploading ? null : _downloadTemplate,
          ),
          const SizedBox(height: 16),

          // Step 2
          _importStep(
            step: '2', color: _green, icon: Icons.upload_rounded,
            title: 'Upload Filled File',
            subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).',
            buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'),
            onPressed: _downloading || _uploading ? null : _uploadFile,
          ),

          // File name indicator
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
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
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(child: Text((_results!['errors'] as List).join('\n'), style: const TextStyle(fontSize: 12, color: _red))),
                  ),
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
//  QUOTE DETAILS DIALOG (preserved from original)
// =============================================================================

class QuoteDetailsDialog extends StatelessWidget {
  final Quote quote;
  const QuoteDetailsDialog({Key? key, required this.quote}) : super(key: key);

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
            const Icon(Icons.description, color: Color(0xFF3498DB), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(quote.quoteNumber, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text('Quote Details', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ])),
_statusBadge(
  quote.status,
  convertedToInvoice: quote.convertedToInvoice,
  convertedToSalesOrder: quote.convertedToSalesOrder,
),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 32),
          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section('Customer Information', [
              _infoRow('Customer Name', quote.customerName),
              _infoRow('Email', quote.customerEmail),
              _infoRow('Phone', quote.customerPhone),
            ]),
            const SizedBox(height: 24),
            _section('Quote Information', [
              _infoRow('Quote Number', quote.quoteNumber),
              _infoRow('Reference Number', quote.referenceNumber),
              _infoRow('Quote Date', DateFormat('dd MMM yyyy').format(quote.quoteDate)),
              _infoRow('Expiry Date', DateFormat('dd MMM yyyy').format(quote.expiryDate)),
              _infoRow('Salesperson', quote.salesperson),
              _infoRow('Project Name', quote.projectName),
              _infoRow('Subject', quote.subject),
            ]),
            const SizedBox(height: 24),
            if (quote.items.isNotEmpty) ...[
              _lineItemsSection(quote.items),
              const SizedBox(height: 24),
            ],
            _section('Amount Details', [
              _infoRow('Subtotal', '₹${quote.subTotal.toStringAsFixed(2)}'),
              if (quote.tdsAmount > 0) _infoRow('TDS', '₹${quote.tdsAmount.toStringAsFixed(2)}'),
              if (quote.tcsAmount > 0) _infoRow('TCS', '₹${quote.tcsAmount.toStringAsFixed(2)}'),
              _infoRow('CGST', '₹${quote.cgst.toStringAsFixed(2)}'),
              _infoRow('SGST', '₹${quote.sgst.toStringAsFixed(2)}'),
              _infoRow('IGST', '₹${quote.igst.toStringAsFixed(2)}'),
              _infoRow('Total Amount', '₹${quote.totalAmount.toStringAsFixed(2)}', isBold: true),
            ]),
            if (quote.customerNotes != null && quote.customerNotes!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _section('Customer Notes', [
                Padding(padding: const EdgeInsets.all(8), child: Text(quote.customerNotes!, style: TextStyle(fontSize: 14, color: Colors.grey[800]))),
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

Widget _statusBadge(String status, {bool? convertedToInvoice, bool? convertedToSalesOrder}) {
  const map = <String, List<Color>>{
    'ACCEPTED':  [Color(0xFFDCFCE7), Color(0xFF15803D)],
    'SENT':      [Color(0xFFDBEAFE), Color(0xFF1D4ED8)],
    'DRAFT':     [Color(0xFFF1F5F9), Color(0xFF64748B)],
    'DECLINED':  [Color(0xFFFEE2E2), Color(0xFFDC2626)],
    'EXPIRED':   [Color(0xFFFEF3C7), Color(0xFFB45309)],
    'CONVERTED': [Color(0xFFF3E8FF), Color(0xFF7C3AED)],
  };
  final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];

  final chips = <Widget>[
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c[0],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c[1].withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 10)),
      ]),
    ),
  ];

  if (status == 'CONVERTED') {
    if (convertedToInvoice == true)
      chips.add(_subBadge('Inv', const Color(0xFFDCFCE7), const Color(0xFF15803D), Icons.receipt_long));
    if (convertedToSalesOrder == true)
      chips.add(_subBadge('SO', const Color(0xFFDBEAFE), const Color(0xFF1D4ED8), Icons.shopping_cart));
  }

  return Wrap(
    spacing: 4,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: chips,
  );
}

Widget _subBadge(String label, Color bg, Color textColor, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: textColor.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 9, color: textColor),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 9)),
    ]),
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

  Widget _infoRow(String label, dynamic value, {bool isBold = false}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 180, child: Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: const Color(0xFF2C3E50), fontSize: 14))),
        Expanded(child: Text(value.toString(), style: TextStyle(color: Colors.grey[800], fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
      ]),
    );
  }

  Widget _lineItemsSection(List<QuoteItem> items) {
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