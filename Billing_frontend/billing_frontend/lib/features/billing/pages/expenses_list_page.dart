// ============================================================================
// EXPENSES LIST PAGE — with Proof Upload feature
// Changes vs original:
//   1. ProofFile model added
//   2. Expense model gains proofFile field
//   3. _proofFilter state + "Proof" filter chip in all 3 top-bar breakpoints
//   4. _uploadProof()  — bottom sheet: Camera | Choose File (10 MB, img/pdf)
//                        confirmation dialog if proof already exists
//   5. 3-dot PopupMenu gains "Upload Proof" item (after View Details)
//   6. ExpenseDetailsDialog gains a "Proof" section at the bottom
//   7. ExpenseService gets uploadProof() + getProofUrl() helpers
// ============================================================================
// File: lib/screens/billing/expenses_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/expenses_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../core/services/billing_customers_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_expenses.dart';
import 'expense_detail_page.dart';

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

class ExpensesListPage extends StatefulWidget {
  const ExpensesListPage({Key? key}) : super(key: key);
  @override
  State<ExpensesListPage> createState() => _ExpensesListPageState();
}

class _ExpensesListPageState extends State<ExpensesListPage> {

  final ExpenseService _expenseService = ExpenseService();
  final ApiService     _apiService     = ApiService();

  // ── data ──────────────────────────────────────────────────────────────────
  List<Expense>  _expenses     = [];
  List<Expense>  _filtered     = [];
  ExpenseStats?  _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String _selectedStatus  = 'All';
  String _selectedAccount = 'All';
  // NEW: proof filter
  String _proofFilter = 'All'; // 'All' | 'With Proof' | 'Without Proof'
  DateTime? _fromDate;
  DateTime? _toDate;

  final List<String> _statusFilters  = ['All','Pending','Approved','Rejected','Paid'];
  final List<String> _accountFilters = [
    'All','Fuel','Office Supplies','Travel & Conveyance',
    'Advertising & Marketing','Meals & Entertainment',
    'Utilities','Rent','Professional Fees','Insurance','Other Expenses',
  ];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
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
    await Future.wait([_loadExpenses(), _loadStats()]);
  }

  Future<void> _loadExpenses() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final resp = await _expenseService.getAllExpenses();
      if (resp['success'] == true) {
        setState(() {
          _expenses  = (resp['data'] as List).map((e) => Expense.fromJson(e)).toList();
          _isLoading = false;
          _selectedIds.clear();
          _selectAll = false;
        });
        _applyFilters();
      } else {
        throw Exception(resp['message'] ?? 'Failed to load expenses');
      }
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _loadStats() async {
    try {
      final resp = await _expenseService.getExpenseStatistics();
      if (resp['success'] == true) {
        setState(() => _stats = ExpenseStats.fromJson(resp['data']));
      }
    } catch (_) {}
  }

  Future<void> _refresh() async {
    await _loadAll();
    _showSuccess('Data refreshed');
  }

  // ── filtering ─────────────────────────────────────────────────────────────

  void _applyFilters() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _expenses.where((e) {
        // text search
        if (q.isNotEmpty &&
            !e.expenseAccount.toLowerCase().contains(q) &&
            !(e.vendor?.toLowerCase().contains(q) ?? false) &&
            !(e.customerName?.toLowerCase().contains(q) ?? false) &&
            !(e.invoiceNumber?.toLowerCase().contains(q) ?? false)) return false;
        // account filter
        if (_selectedAccount != 'All' && e.expenseAccount != _selectedAccount) return false;
        // date filters
        if (_fromDate != null) {
          try { if (DateTime.parse(e.date).isBefore(_fromDate!)) return false; } catch (_) {}
        }
        if (_toDate != null) {
          try { if (DateTime.parse(e.date).isAfter(_toDate!.add(const Duration(days: 1)))) return false; } catch (_) {}
        }
        // NEW: proof filter
        if (_proofFilter == 'With Proof'    && e.proofFile == null) return false;
        if (_proofFilter == 'Without Proof' && e.proofFile != null) return false;
        return true;
      }).toList();
      _totalPages = (_filtered.length / _itemsPerPage).ceil().clamp(1, 9999);
      if (_currentPage > _totalPages) _currentPage = _totalPages;
      _selectedIds.clear();
      _selectAll = false;
    });
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _selectedStatus  = 'All';
      _selectedAccount = 'All';
      _proofFilter     = 'All';
      _fromDate = null;
      _toDate   = null;
      _currentPage = 1;
    });
    _applyFilters();
  }

  bool get _hasAnyFilter =>
      _selectedStatus != 'All' || _selectedAccount != 'All' ||
      _proofFilter != 'All' ||
      _fromDate != null || _toDate != null || _searchController.text.isNotEmpty;

  List<Expense> get _currentPageItems {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end   = (start + _itemsPerPage).clamp(0, _filtered.length);
    return _filtered.sublist(start, end);
  }

  // ── selection ─────────────────────────────────────────────────────────────

  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll = v ?? false;
      if (_selectAll) _selectedIds.addAll(_currentPageItems.map((e) => e.id));
      else _selectedIds.clear();
    });
  }

  void _toggleRow(String id) {
    setState(() {
      _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
      _selectAll = _selectedIds.length == _currentPageItems.length;
    });
  }

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewExpensePage()));
    if (ok == true) _loadAll();
  }

  void _openEdit(String id) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewExpensePage(expenseId: id)));
    if (ok == true) _loadAll();
  }

  // ── view details ──────────────────────────────────────────────────────────

  void _viewDetails(Expense expense) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExpenseDetailPage(expenseId: expense.id)),
    ).then((result) { if (result == true) _loadExpenses(); });
  }

  // ── delete ────────────────────────────────────────────────────────────────

  Future<void> _delete(Expense expense) async {
    final ok = await _confirmDialog(
      title: 'Delete Expense',
      message: 'Delete this expense (${expense.expenseAccount})? This cannot be undone.',
      confirmLabel: 'Delete', confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await _expenseService.deleteExpense(expense.id);
      _showSuccess('Expense deleted');
      _loadAll();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  // ── download receipt ──────────────────────────────────────────────────────

  Future<void> _downloadReceipt(Expense expense) async {
    if (expense.receiptFile == null) { _showError('No receipt attached'); return; }
    try {
      _showSuccess('Downloading receipt…');
      final url = await _expenseService.downloadReceipt(expense.id);
      final headers = await _apiService.getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        if (kIsWeb) {
          final blob = html.Blob([response.bodyBytes]);
          final blobUrl = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: blobUrl)
            ..setAttribute('download', expense.receiptFile!.originalName)
            ..click();
          html.Url.revokeObjectUrl(blobUrl);
        } else {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        _showError('Download failed (${response.statusCode})');
      }
    } catch (e) { _showError('Failed to download receipt: $e'); }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _share(Expense expense) async {
    DateTime? expDate;
    try { expDate = DateTime.parse(expense.date); } catch (_) {}
    final text = 'Expense Record\n'
        '─────────────────────────\n'
        'Account : ${expense.expenseAccount}\n'
        'Date    : ${expDate != null ? DateFormat('dd MMM yyyy').format(expDate) : expense.date}\n'
        'Vendor  : ${expense.vendor ?? '-'}\n'
        'Invoice : ${expense.invoiceNumber ?? '-'}\n'
        'Amount  : ₹${expense.amount.toStringAsFixed(2)}\n'
        'Tax     : ₹${expense.tax.toStringAsFixed(2)}\n'
        'Total   : ₹${expense.total.toStringAsFixed(2)}\n'
        'Paid Via: ${expense.paidThrough}\n'
        'Customer: ${expense.customerName ?? '-'}\n'
        'Billable: ${expense.isBillable ? 'Yes' : 'No'}\n'
        'Proof   : ${expense.proofFile != null ? '✅ Attached (${expense.proofFile!.originalName})' : '❌ Not uploaded'}';
    try {
      await Share.share(text, subject: 'Expense: ${expense.expenseAccount}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── PROOF UPLOAD (NEW) ────────────────────────────────────────────────────

  Future<void> _uploadProof(Expense expense) async {
    // If proof already exists → confirm replacement
    if (expense.proofFile != null) {
      final replace = await _confirmDialog(
        title: 'Replace Existing Proof',
        message: 'A proof file "${expense.proofFile!.originalName}" is already attached. '
                 'Do you want to replace it with a new file?',
        confirmLabel: 'Replace',
        confirmColor: _orange,
      );
      if (replace != true) return;
    }

    // Show centered dialog: Camera or File
    if (!mounted) return;
    final source = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: _ProofSourceSheet(hasExisting: expense.proofFile != null),
      ),
    );
    if (source == null) return;

    Uint8List? bytes;
    String?    fileName;
    String?    mimeType;

    if (source == 'camera') {
      // Camera — only available on mobile
      if (kIsWeb) { _showError('Camera not supported on web. Please use "Choose File".'); return; }
      try {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2048,
          maxHeight: 2048,
        );
        if (picked == null) return;
        bytes    = await picked.readAsBytes();
        fileName = picked.name.isNotEmpty ? picked.name : 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
        mimeType = 'image/jpeg';
      } catch (e) {
        _showError('Could not open camera: $e');
        return;
      }
    } else {
      // File picker — image or PDF
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf'],
          allowMultiple: false,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        bytes    = file.bytes;
        fileName = file.name;
        // Determine mime type from extension
        final ext = (file.extension ?? '').toLowerCase();
        mimeType = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
        if (bytes == null) { _showError('Could not read file'); return; }
      } catch (e) {
        _showError('File picker error: $e');
        return;
      }
    }

    // Size check — 10 MB
    const maxBytes = 10 * 1024 * 1024;
    if (bytes!.length > maxBytes) {
      _showError('File is too large (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). Maximum allowed is 10 MB.');
      return;
    }

    // Upload to backend
    setState(() => _isLoading = true);
    try {
      final headers = await _apiService.getHeaders();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_apiService.baseUrl}/api/finance/expenses/${expense.id}/proof'),
      );
      headers.forEach((k, v) {
        if (k.toLowerCase() != 'content-type') request.headers[k] = v;
      });
      request.files.add(http.MultipartFile.fromBytes(
        'proof', bytes,
        filename: fileName,
        // contentType is inferred from filename by the backend multer filter
      ));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        _showSuccess('✅ Proof uploaded: ${body['data']?['originalName'] ?? fileName}');
        _loadAll(); // Reload to reflect proofFile in list
      } else {
        final err = json.decode(response.body);
        _showError('Upload failed: ${err['message'] ?? response.statusCode}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Upload error: $e');
    }
  }

  // ── whatsapp (unchanged) ──────────────────────────────────────────────────

  Future<void> _whatsApp(Expense expense) async {
    String phone = '', recipient = '';
    if (expense.vendor != null && expense.vendor!.isNotEmpty) {
      try {
        final resp = await BillingVendorsService.getAllVendors(limit: 500);
        if (resp['success'] == true) {
          for (final v in (resp['data'] as List? ?? [])) {
            final name = (v['vendorName'] ?? v['companyName'] ?? '').toString();
            if (name.toLowerCase() == expense.vendor!.toLowerCase()) {
              phone     = (v['phoneNumber'] ?? v['phone'] ?? v['primaryPhone'] ?? '').toString().trim();
              recipient = name;
              break;
            }
          }
        }
      } catch (_) {}
    }
    if (phone.isEmpty && expense.customerName != null && expense.customerName!.isNotEmpty) {
      try {
        final resp = await BillingCustomersService.getAllCustomers(limit: 200);
        if (resp['success'] == true) {
          for (final c in (resp['data'] as List? ?? [])) {
            final name = (c['customerName'] ?? c['companyName'] ?? '').toString();
            if (name.toLowerCase() == expense.customerName!.toLowerCase()) {
              phone     = (c['primaryPhone'] ?? c['phone'] ?? c['mobilePhone'] ?? '').toString().trim();
              recipient = name;
              break;
            }
          }
        }
      } catch (_) {}
    }
    if (phone.isEmpty) {
      _showError(expense.vendor != null && expense.vendor!.isNotEmpty
          ? 'Phone not found for vendor "${expense.vendor}".'
          : 'No vendor or customer linked to this expense.');
      return;
    }
    DateTime? expDate;
    try { expDate = DateTime.parse(expense.date); } catch (_) {}
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final msg = Uri.encodeComponent(
      'Hello $recipient,\n\nExpense details:\n'
      'Account : ${expense.expenseAccount}\n'
      'Date    : ${expDate != null ? DateFormat('dd MMM yyyy').format(expDate) : expense.date}\n'
      'Amount  : ₹${expense.total.toStringAsFixed(2)}\n'
      'Paid Via: ${expense.paidThrough}\n\nThank you!',
    );
    final url = Uri.parse('https://wa.me/$cleaned?text=$msg');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
    else _showError('Could not open WhatsApp');
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket([Expense? expense]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        expense: expense,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError:        (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      if (_filtered.isEmpty) { _showError('Nothing to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Date','Expense Account','Vendor','Invoice #','Customer','Amount','Tax','Total','Paid Through','Billable','Project','Notes','Proof Attached'],
        ..._filtered.map((e) {
          DateTime? d; try { d = DateTime.parse(e.date); } catch (_) {}
          return [
            d != null ? DateFormat('dd/MM/yyyy').format(d) : e.date,
            e.expenseAccount, e.vendor ?? '', e.invoiceNumber ?? '',
            e.customerName ?? '', e.amount.toStringAsFixed(2),
            e.tax.toStringAsFixed(2), e.total.toStringAsFixed(2),
            e.paidThrough, e.isBillable ? 'Yes' : 'No',
            e.project ?? '', e.notes ?? '',
            e.proofFile != null ? 'Yes (${e.proofFile!.originalName})' : 'No',
          ];
        }),
      ];
      await ExportHelper.exportToExcel(
        data: rows,
        filename: 'expenses_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
      _showSuccess('✅ Excel downloaded (${_filtered.length} expenses)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportExpensesDialog(
        apiService: _apiService,
        onImportComplete: _loadAll,
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
            constraints: BoxConstraints(
              maxWidth:  MediaQuery.of(context).size.width  * 0.85,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: Color(0xFF3498DB),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
                  child: const Text('Expense Lifecycle Process',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                Expanded(child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  child: InteractiveViewer(
                    panEnabled: true, minScale: 0.5, maxScale: 4.0,
                    child: Center(child: Image.asset('assets/expense.png', fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.broken_image_outlined, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('Image not found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                        ]))),
                  ),
                )),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  color: Colors.grey[100],
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

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context, initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _fromDate = d; _currentPage = 1; }); _applyFilters(); }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context, initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (d != null) { setState(() { _toDate = d; _currentPage = 1; }); _applyFilters(); }
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
      appBar: AppTopBar(title: 'Expenses'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
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

  // ── Proof filter chip ─────────────────────────────────────────────────────

  Widget _proofFilterChip() {
    return PopupMenuButton<String>(
      tooltip: 'Filter by Proof',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      offset: const Offset(0, 44),
      onSelected: (v) {
        setState(() { _proofFilter = v; _currentPage = 1; });
        _applyFilters();
      },
      itemBuilder: (_) => [
        _proofMenuItem('All',           Icons.receipt_long,      Colors.grey),
        _proofMenuItem('With Proof',    Icons.verified_outlined,  _teal),
        _proofMenuItem('Without Proof', Icons.report_gmailerrorred_outlined, _orange),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _proofFilter != 'All' ? _teal.withOpacity(0.08) : const Color(0xFFF7F9FC),
          border: Border.all(color: _proofFilter != 'All' ? _teal : const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified_outlined, size: 15, color: _proofFilter != 'All' ? _teal : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(
            _proofFilter == 'All' ? 'Proof' : _proofFilter,
            style: TextStyle(fontSize: 13, fontWeight: _proofFilter != 'All' ? FontWeight.w600 : FontWeight.normal, color: _proofFilter != 'All' ? _teal : Colors.grey[600]),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 14, color: _proofFilter != 'All' ? _teal : Colors.grey[500]),
        ]),
      ),
    );
  }

  PopupMenuItem<String> _proofMenuItem(String value, IconData icon, Color color) {
    final isSelected = _proofFilter == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Text(value, style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal, color: isSelected ? color : null)),
        if (isSelected) ...[const Spacer(), Icon(Icons.check, size: 16, color: color)],
      ]),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 10),
    _accountDropdown(),
    const SizedBox(width: 10),
    _proofFilterChip(), // NEW
    const SizedBox(width: 10),
    _searchField(width: 200),
    const SizedBox(width: 10),
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _applyFilters(); }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    const Spacer(),
    _actionBtn('New Expense', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _filtered.isEmpty ? null : _exportExcel),
    const SizedBox(width: 8),
    _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      _accountDropdown(),
      const SizedBox(width: 8),
      _proofFilterChip(), // NEW
      const SizedBox(width: 8),
      _searchField(width: 150),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From', isActive: _fromDate != null, onTap: _pickFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To', isActive: _toDate != null, onTap: _pickToDate),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _applyFilters(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Expense', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _filtered.isEmpty ? null : _exportExcel),
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
      _accountDropdown(),
      const SizedBox(width: 8),
      _proofFilterChip(), // NEW
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFromDate),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickToDate),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _applyFilters(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showLifecycleDialog, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _filtered.isEmpty ? null : _exportExcel),
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
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Expenses' : s))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFilters(); } },
      ),
    ),
  );

  Widget _accountDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedAccount,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
        items: _accountFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Accounts' : s))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedAccount = v; _currentPage = 1; }); _applyFilters(); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search expenses…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchController.clear(); _applyFilters(); })
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
    final total     = _stats?.totalExpenses ?? 0;
    final billable  = _stats?.totalBillable ?? 0;
    final count     = _stats?.expenseCount  ?? 0;
    final thisMonth = total * 0.3;

    final cards = [
      _StatCardData(label: 'Total Expenses', value: '₹${_fmtAmt(total)}', icon: Icons.receipt_long_rounded, color: _navy, gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Total Billable', value: '₹${_fmtAmt(billable)}', icon: Icons.attach_money_rounded, color: _green, gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Expense Count', value: count.toString(), icon: Icons.list_alt_rounded, color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'This Month', value: '₹${_fmtAmt(thisMonth)}', icon: Icons.calendar_month_rounded, color: _purple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
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
          child: Padding(padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0), child: _buildStatCard(e.value, compact: false)),
        )).toList());
      }),
    );
  }

  String _fmtAmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(2);
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
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
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
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  headingRowHeight: 56, dataRowMinHeight: 60, dataRowMaxHeight: 74,
                  dataTextStyle: const TextStyle(fontSize: 16),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 18, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E), onChanged: _toggleSelectAll))),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('DATE'))),
                    const DataColumn(label: SizedBox(width: 150, child: Text('EXPENSE ACCOUNT'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('VENDOR'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('CUSTOMER'))),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('AMOUNT'))),
                    const DataColumn(label: SizedBox(width: 80,  child: Text('TAX'))),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('TOTAL'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('PAID THROUGH'))),
                    const DataColumn(label: SizedBox(width: 70,  child: Text('RECEIPT'))),
                    // NEW column
                    const DataColumn(label: SizedBox(width: 60,  child: Text('PROOF'))),
                    const DataColumn(label: SizedBox(width: 80,  child: Text('BILLABLE'))),
                    const DataColumn(label: SizedBox(width: 150, child: Text('ACTIONS'))),
                  ],
                  rows: items.map((e) => _buildRow(e)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(Expense expense) {
    final isSel = _selectedIds.contains(expense.id);
    DateTime? expDate;
    try { expDate = DateTime.parse(expense.date); } catch (_) {}

    return DataRow(
      selected: isSel,
      color: WidgetStateProperty.resolveWith((s) {
        if (isSel) return _navy.withOpacity(0.06);
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(Checkbox(value: isSel, onChanged: (_) => _toggleRow(expense.id))),
        DataCell(SizedBox(width: 90, child: Text(expDate != null ? DateFormat('dd/MM/yyyy').format(expDate) : expense.date, style: const TextStyle(fontSize: 12)))),
        DataCell(SizedBox(width: 150, child: InkWell(
          onTap: () => _openEdit(expense.id),
          child: Text(expense.expenseAccount,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 12, decoration: TextDecoration.underline),
              overflow: TextOverflow.ellipsis),
        ))),
        DataCell(SizedBox(width: 120, child: Text(expense.vendor ?? '-', style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(width: 130, child: Text(expense.customerName ?? '-', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(width: 90, child: Text('₹${expense.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)))),
        DataCell(SizedBox(width: 80, child: Text('₹${expense.tax.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)))),
        DataCell(SizedBox(width: 90, child: Text('₹${expense.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))),
        DataCell(SizedBox(width: 120, child: Text(expense.paidThrough, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))),

        // Receipt
        DataCell(SizedBox(width: 70, child: Center(
          child: expense.receiptFile != null
              ? Tooltip(
                  message: 'Download: ${expense.receiptFile!.originalName}',
                  child: InkWell(
                    onTap: () => _downloadReceipt(expense),
                    child: Container(width: 30, height: 30,
                        decoration: BoxDecoration(color: _green.withOpacity(0.10), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.attach_file, color: _green, size: 16)),
                  ))
              : Icon(Icons.attach_file_outlined, color: Colors.grey[400], size: 18),
        ))),

        // NEW: Proof column
        DataCell(SizedBox(width: 60, child: Center(
          child: expense.proofFile != null
              ? Tooltip(
                  message: 'Proof: ${expense.proofFile!.originalName}',
                  child: InkWell(
                    onTap: () => _openProof(expense),
                    child: Container(width: 30, height: 30,
                        decoration: BoxDecoration(color: _teal.withOpacity(0.10), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.verified_outlined, color: _teal, size: 16)),
                  ))
              : Tooltip(
                  message: 'No proof — tap to upload',
                  child: InkWell(
                    onTap: () => _uploadProof(expense),
                    child: Container(width: 30, height: 30,
                        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(6), border: Border.all(color: _orange.withOpacity(0.3))),
                        child: Icon(Icons.upload_outlined, color: _orange.withOpacity(0.7), size: 16)),
                  )),
        ))),

        // Billable
        DataCell(SizedBox(width: 80, child: Center(
          child: expense.isBillable
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green[300]!)),
                  child: Text('Yes', style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w600, fontSize: 11)),
                )
              : Text('No', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ))),

        // Actions
        DataCell(SizedBox(width: 150, child: Row(children: [
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _share(expense),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('view',    Icons.visibility_outlined,          _blue,   'View Details'),
              _menuItem('proof',   Icons.verified_outlined,             _teal,   // NEW
                  expense.proofFile != null ? 'View / Replace Proof' : 'Upload Proof'),
              _menuItem('edit',    Icons.edit_outlined,                _navy,   'Edit'),
              if (expense.receiptFile != null)
                _menuItem('receipt', Icons.download_outlined,          _green,  'Download Receipt'),
              _menuItem('ticket',  Icons.confirmation_number_outlined, _orange, 'Raise Ticket'),
              _menuItem('delete',  Icons.delete_outline,               _red,    'Delete', textColor: _red),
            ],
            onSelected: (v) {
              switch (v) {
                case 'view':    _viewDetails(expense);       break;
                case 'proof':   _uploadProof(expense);       break; // NEW
                case 'edit':    _openEdit(expense.id);       break;
                case 'receipt': _downloadReceipt(expense);   break;
                case 'ticket':  _raiseTicket(expense);       break;
                case 'delete':  _delete(expense);            break;
              }
            },
          ),
        ]))),
      ],
    );
  }

  /// Open / view the proof (image inline, PDF in browser/external)
  Future<void> _openProof(Expense expense) async {
    if (expense.proofFile == null) { _uploadProof(expense); return; }
    final url = '${_apiService.baseUrl}/api/finance/expenses/${expense.id}/proof';
    if (expense.proofFile!.isImage) {
      showDialog(
        context: context,
        builder: (_) => _ProofPreviewDialog(
          proofFile: expense.proofFile!,
          proofUrl: url,
          apiService: _apiService,
          onReplace: () { Navigator.pop(context); _uploadProof(expense); },
        ),
      );
    } else {
      // PDF — fetch with auth then open as blob
      try {
        setState(() => _isLoading = true);
        final headers = await _apiService.getHeaders();
        final response = await http.get(Uri.parse(url), headers: headers);
        setState(() => _isLoading = false);
        if (response.statusCode == 200) {
          if (kIsWeb) {
            final blob = html.Blob([response.bodyBytes], 'application/pdf');
            final blobUrl = html.Url.createObjectUrlFromBlob(blob);
            html.window.open(blobUrl, '_blank');
            Future.delayed(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(blobUrl));
          } else {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } else {
          _showError('Could not open proof (${response.statusCode})');
        }
      } catch (e) {
        setState(() => _isLoading = false);
        _showError('Could not open proof: $e');
      }
    }
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color iconColor, String label, {Color? textColor}) {
    return PopupMenuItem(value: value, child: ListTile(
      leading: Icon(icon, size: 17, color: iconColor),
      title: Text(label, style: TextStyle(color: textColor, fontSize: 13)),
      contentPadding: EdgeInsets.zero, dense: true,
    ));
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
              '${_filtered.length != _expenses.length ? ' (filtered from ${_expenses.length})' : ''}',
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

  // ── empty / error ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.receipt_long_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Expenses Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasAnyFilter ? 'Try adjusting your filters' : 'Record your first expense to get started', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasAnyFilter ? _clearFilters : _openNew,
        icon: Icon(_hasAnyFilter ? Icons.filter_list_off : Icons.add),
        label: Text(_hasAnyFilter ? 'Clear Filters' : 'New Expense', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Expenses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
//  PROOF SOURCE BOTTOM SHEET
// =============================================================================

class _ProofSourceSheet extends StatelessWidget {
  final bool hasExisting;
  const _ProofSourceSheet({required this.hasExisting});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Title row — matches logout card style
        Row(children: [
          const Icon(Icons.verified_outlined, color: _teal, size: 22),
          const SizedBox(width: 10),
          Text(
            hasExisting ? 'Replace Proof' : 'Upload Proof',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1A202C)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Choose how to add your proof document',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 20),
        if (!kIsWeb) ...[
          _SourceTile(
            icon: Icons.camera_alt_rounded,
            color: _navy,
            title: 'Take Photo',
            subtitle: 'Use camera to capture the receipt',
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          const SizedBox(height: 10),
        ],
        _SourceTile(
          icon: Icons.folder_open_rounded,
          color: _purple,
          title: 'Choose File',
          subtitle: 'Images (JPG, PNG, WEBP) or PDF — max 10 MB',
          onTap: () => Navigator.pop(context, 'file'),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
        ]),
      ]),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _SourceTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withOpacity(0.8), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ]),
      ),
    );
  }
}

// =============================================================================
//  PROOF PREVIEW DIALOG (image)
// =============================================================================

class _ProofPreviewDialog extends StatefulWidget {
  final ProofFile  proofFile;
  final String     proofUrl;
  final ApiService apiService;
  final VoidCallback onReplace;
  const _ProofPreviewDialog({required this.proofFile, required this.proofUrl, required this.apiService, required this.onReplace});

  @override
  State<_ProofPreviewDialog> createState() => _ProofPreviewDialogState();
}

class _ProofPreviewDialogState extends State<_ProofPreviewDialog> {
  Uint8List? _imageBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final headers = await widget.apiService.getHeaders();
      final response = await http.get(Uri.parse(widget.proofUrl), headers: headers);
      if (response.statusCode == 200) {
        setState(() { _imageBytes = response.bodyBytes; _loading = false; });
      } else {
        setState(() { _error = 'Could not load image (${response.statusCode})'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(children: [
        Center(child: Container(
          constraints: BoxConstraints(
            maxWidth:  MediaQuery.of(context).size.width  * 0.90,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_teal, Color(0xFF1ABC9C)]),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(children: [
                  const Icon(Icons.verified_outlined, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Expense Proof', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(widget.proofFile.originalName,
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ])),
                  Text('${(widget.proofFile.size / 1024).toStringAsFixed(1)} KB',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                ]),
              ),
              // Image area
              Flexible(child: Container(
                constraints: const BoxConstraints(minHeight: 200, maxHeight: 500),
                color: Colors.grey[100],
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _teal))
                    : _error != null
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.broken_image_outlined, size: 56, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(_error!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                          ])))
                        : InteractiveViewer(
                            panEnabled: true, minScale: 0.5, maxScale: 4.0,
                            child: Center(child: Image.memory(_imageBytes!, fit: BoxFit.contain)),
                          ),
              )),
              // Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(color: Color(0xFFF7F9FC), border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
                child: Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: widget.onReplace,
                    icon: const Icon(Icons.upload_outlined, size: 16),
                    label: const Text('Replace Proof'),
                    style: OutlinedButton.styleFrom(foregroundColor: _orange, side: const BorderSide(color: _orange), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Close'),
                    style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  )),
                ]),
              ),
            ]),
          ),
        )),
        Positioned(top: 30, right: 20, child: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
          style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.5), padding: const EdgeInsets.all(8)),
        )),
      ]),
    );
  }
}

// =============================================================================
//  RAISE TICKET OVERLAY (unchanged from original)
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final Expense? expense;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.expense, required this.onTicketRaised, required this.onError});

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filteredEmps = [];
  Map<String, dynamic>?       _selectedEmp;
  bool _loading   = true;
  bool _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() { super.initState(); _loadEmployees(); _searchCtrl.addListener(_filterEmps); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() { _employees = List<Map<String, dynamic>>.from(resp['data']); _filteredEmps = _employees; _loading = false; });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filterEmps() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() { _filteredEmps = q.isEmpty ? _employees : _employees.where((e) =>
        (e['name_parson'] ?? '').toLowerCase().contains(q) ||
        (e['email'] ?? '').toLowerCase().contains(q) ||
        (e['role'] ?? '').toLowerCase().contains(q)).toList(); });
  }

  String _buildMessage() {
    if (widget.expense == null) return 'A ticket has been raised regarding an expense and requires your attention.';
    final e = widget.expense!;
    DateTime? d; try { d = DateTime.parse(e.date); } catch (_) {}
    return 'Expense "${e.expenseAccount}" requires attention.\n\n'
           'Account  : ${e.expenseAccount}\n'
           'Date     : ${d != null ? DateFormat('dd MMM yyyy').format(d) : e.date}\n'
           'Vendor   : ${e.vendor ?? '-'}\n'
           'Amount   : ₹${e.amount.toStringAsFixed(2)}\n'
           'Total    : ₹${e.total.toStringAsFixed(2)}\n'
           'Paid Via : ${e.paidThrough}\n'
           'Proof    : ${e.proofFile != null ? '✅ Attached' : '❌ Missing'}\n\n'
           'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    widget.expense != null ? 'Expense: ${widget.expense!.expenseAccount}' : 'Expenses — Action Required',
        message:    _buildMessage(),
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)]),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (widget.expense != null) Text('Expense: ${widget.expense!.expenseAccount}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.expense != null) ...[
                const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                    child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5))),
                const SizedBox(height: 20),
              ],
              const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Row(children: ['Low', 'Medium', 'High'].map((pr) {
                final isSel = _priority == pr;
                final color = pr == 'High' ? _red : pr == 'Medium' ? _orange : _green;
                return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8),
                  child: InkWell(onTap: () => setState(() => _priority = pr), borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: isSel ? color : Colors.white, borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSel ? color : Colors.grey[300]!),
                          boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : []),
                      child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700])))),
                  )));
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
                  : _filteredEmps.isEmpty
                      ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                      : Container(
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filteredEmps.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                            itemBuilder: (_, i) {
                              final emp   = _filteredEmps[i];
                              final isSel = _selectedEmp?['_id'] == emp['_id'];
                              return InkWell(
                                onTap: () => setState(() => _selectedEmp = isSel ? null : emp),
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(radius: 18, backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
                                        child: Text((emp['name_parson'] ?? 'U')[0].toUpperCase(),
                                            style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13))),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (emp['email'] != null) Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                      if (emp['role'] != null) Container(margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                                          child: Text(emp['role'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy))),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ]),
                                ),
                              );
                            },
                          )),
            ]),
          )),
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
                    : Text(_selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee',
                        style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  BULK IMPORT DIALOG (unchanged from original)
// =============================================================================

class BulkImportExpensesDialog extends StatefulWidget {
  final ApiService apiService;
  final Future<void> Function() onImportComplete;
  const BulkImportExpensesDialog({Key? key, required this.apiService, required this.onImportComplete}) : super(key: key);
  @override
  State<BulkImportExpensesDialog> createState() => _BulkImportExpensesDialogState();
}

class _BulkImportExpensesDialogState extends State<BulkImportExpensesDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final headers  = await widget.apiService.getHeaders();
      final response = await http.get(Uri.parse('${widget.apiService.baseUrl}/api/finance/expenses/import/template'), headers: headers);
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        if (kIsWeb) {
          final blob = html.Blob([bytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
          final url  = html.Url.createObjectUrlFromBlob(blob);
          html.AnchorElement(href: url)..setAttribute('download', 'expenses_import_template.xlsx')..click();
          html.Url.revokeObjectUrl(url);
        } else {
          final templateUrl = '${widget.apiService.baseUrl}/api/finance/expenses/import/template';
          final uri = Uri.parse(templateUrl);
          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        setState(() => _downloading = false);
        _showSnack('Template downloaded!', _green);
      } else throw Exception('Server returned ${response.statusCode}');
    } catch (e) { setState(() => _downloading = false); _showSnack('Download failed: $e', _red); }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv'], allowMultiple: false, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null && file.path == null) { _showSnack('Could not read file', _red); return; }
      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      final headers = await widget.apiService.getHeaders();
      final request = http.MultipartRequest('POST', Uri.parse('${widget.apiService.baseUrl}/api/finance/expenses/import/bulk'));
      headers.forEach((k, v) { if (k.toLowerCase() != 'content-type') request.headers[k] = v; });
      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', file.path!, filename: file.name));
      }

      final streamed  = await request.send();
      final response  = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        setState(() { _uploading = false; _results = body['data']; });
        _showSnack('✅ Import completed!', _green);
        await widget.onImportComplete();
      } else {
        final err = json.decode(response.body);
        throw Exception(err['message'] ?? 'Import failed (${response.statusCode})');
      }
    } catch (e) { setState(() { _uploading = false; _fileName = null; }); _showSnack('Import failed: $e', _red); }
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
        width: MediaQuery.of(context).size.width > 620
            ? 580
            : MediaQuery.of(context).size.width * 0.92,
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
            const SizedBox(width: 14),
            const Text('Import Expenses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),
          _importStep(step: '1', color: _blue, icon: Icons.download_rounded, title: 'Download Template', subtitle: 'Get the official Excel template with correct columns from the server.', buttonLabel: _downloading ? 'Downloading…' : 'Download Template', onPressed: _downloading || _uploading ? null : _downloadTemplate),
          const SizedBox(height: 16),
          _importStep(step: '2', color: _green, icon: Icons.upload_rounded, title: 'Upload Filled File', subtitle: 'Fill in the template and upload your file (XLSX / XLS / CSV).', buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'), onPressed: _downloading || _uploading ? null : _uploadFile),
          if (_fileName != null) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
                child: Row(children: [Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)))])),
          ],
          if (_results != null) ...[
            const Divider(height: 28),
            Container(padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  _resultRow('Total Processed',       '${(_results!['imported'] ?? 0) + (_results!['errors'] ?? 0)}', _blue),
                  const SizedBox(height: 8),
                  _resultRow('Successfully Imported', '${_results!['imported'] ?? 0}', _green),
                  const SizedBox(height: 8),
                  _resultRow('Failed',                '${_results!['errors'] ?? 0}',   _red),
                ])),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
    ]);
  }
}

// =============================================================================
//  EXPENSE DETAILS DIALOG — with Proof section
// =============================================================================

class ExpenseDetailsDialog extends StatelessWidget {
  final Expense   expense;
  final String?   proofUrl;
  final ApiService apiService;

  const ExpenseDetailsDialog({
    Key? key,
    required this.expense,
    this.proofUrl,
    required this.apiService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    DateTime? expDate;
    try { expDate = DateTime.parse(expense.date); } catch (_) {}

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            const Icon(Icons.receipt_long, color: _navy, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(expense.expenseAccount, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              Text('Expense Details', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ])),
            // Proof badge
            if (expense.proofFile != null)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: _teal.withOpacity(0.35))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.verified_outlined, size: 14, color: _teal),
                  const SizedBox(width: 5),
                  Text('Proof Attached', style: TextStyle(color: _teal, fontWeight: FontWeight.w600, fontSize: 12)),
                ]),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: expense.isBillable ? Colors.green[50] : Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: Text(expense.isBillable ? 'Billable' : 'Non-Billable',
                  style: TextStyle(color: expense.isBillable ? Colors.green[800] : Colors.grey[700], fontWeight: FontWeight.w600, fontSize: 12)),
            ),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const Divider(height: 28),

          Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _section('Expense Information', [
              _row('Date',            expDate != null ? DateFormat('dd MMM yyyy').format(expDate) : expense.date),
              _row('Expense #',       expense.expenseNumber),
              _row('Expense Account', expense.expenseAccount),
              _row('Paid Through',    expense.paidThrough),
              _row('Invoice Number',  expense.invoiceNumber),
              _row('Vendor',          expense.vendor),
              _row('Project',         expense.project),
            ]),
            const SizedBox(height: 20),
            _section('Customer', [
              _row('Customer Name', expense.customerName),
              _row('Billable',      expense.isBillable ? 'Yes' : 'No'),
              if (expense.isBillable) _row('Markup %', '${expense.markupPercentage}%'),
            ]),
            const SizedBox(height: 20),
            _section('Amounts', [
              _row('Amount',  '₹${expense.amount.toStringAsFixed(2)}'),
              _row('Tax',     '₹${expense.tax.toStringAsFixed(2)}'),
              _row('Total',   '₹${expense.total.toStringAsFixed(2)}', isBold: true),
            ]),
            if (expense.notes != null && expense.notes!.isNotEmpty) ...[
              const SizedBox(height: 20),
              _section('Notes', [
                Padding(padding: const EdgeInsets.all(8), child: Text(expense.notes!, style: TextStyle(fontSize: 14, color: Colors.grey[800]))),
              ]),
            ],
            if (expense.receiptFile != null) ...[
              const SizedBox(height: 20),
              _section('Receipt', [
                _row('File Name', expense.receiptFile!.originalName),
                _row('Size', '${(expense.receiptFile!.size / 1024).toStringAsFixed(1)} KB'),
              ]),
            ],

            // ── NEW: Proof Section ─────────────────────────────────────────
            const SizedBox(height: 20),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.verified_outlined, size: 16, color: _teal),
                const SizedBox(width: 8),
                const Text('Expense Proof', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              ]),
              const SizedBox(height: 10),
              expense.proofFile == null
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _orange.withOpacity(0.35)),
                      ),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded, color: _orange, size: 28),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('No Proof Uploaded', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange[800])),
                          const SizedBox(height: 4),
                          Text('A proof document (receipt, invoice screenshot) has not been attached to this expense.',
                              style: TextStyle(fontSize: 12, color: Colors.orange[700])),
                        ])),
                      ]),
                    )
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _teal.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _teal.withOpacity(0.30)),
                      ),
                      child: Column(children: [
                        Row(children: [
                          Container(padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: _teal.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                              child: Icon(
                                expense.proofFile!.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
                                color: _teal, size: 26,
                              )),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(expense.proofFile!.originalName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text('${(expense.proofFile!.size / 1024).toStringAsFixed(1)} KB  •  ${expense.proofFile!.isImage ? 'Image' : 'PDF'}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            if (expense.proofFile!.uploadedAt != null) ...[
                              const SizedBox(height: 2),
                              Builder(builder: (_) {
                                DateTime? ua; try { ua = DateTime.parse(expense.proofFile!.uploadedAt!); } catch (_) {}
                                return Text(ua != null ? 'Uploaded ${DateFormat('dd MMM yyyy, hh:mm a').format(ua)}' : '',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]));
                              }),
                            ],
                          ])),
                        ]),
                        if (proofUrl != null) ...[
                          const SizedBox(height: 14),
                          Row(children: [
                            // View Proof button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final headers = await apiService.getHeaders();
                                    final response = await http.get(Uri.parse(proofUrl!), headers: headers);
                                    if (response.statusCode == 200) {
                                      if (expense.proofFile!.isImage) {
                                        showDialog(
                                          context: context,
                                          builder: (_) => _ProofPreviewDialog(
                                            proofFile: expense.proofFile!,
                                            proofUrl: proofUrl!,
                                            apiService: apiService,
                                            onReplace: () => Navigator.pop(context),
                                          ),
                                        );
                                      } else if (kIsWeb) {
                                        final blob = html.Blob([response.bodyBytes], 'application/pdf');
                                        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
                                        html.window.open(blobUrl, '_blank');
                                        Future.delayed(const Duration(seconds: 30), () => html.Url.revokeObjectUrl(blobUrl));
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Could not open proof (${response.statusCode})'), backgroundColor: _red),
                                      );
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), backgroundColor: _red),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.visibility_outlined, size: 15),
                                label: const Text('View', style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _teal,
                                  side: const BorderSide(color: _teal),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Download button — small
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    final headers = await apiService.getHeaders();
                                    final response = await http.get(Uri.parse(proofUrl!), headers: headers);
                                    if (response.statusCode == 200 && kIsWeb) {
                                      final blob = html.Blob([response.bodyBytes]);
                                      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
                                      final anchor = html.AnchorElement(href: blobUrl)
                                        ..setAttribute('download', expense.proofFile!.originalName)
                                        ..click();
                                      html.Url.revokeObjectUrl(blobUrl);
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Download failed: $e'), backgroundColor: _red),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.download_outlined, size: 15),
                                label: const Text('Download', style: TextStyle(fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _teal, foregroundColor: Colors.white,
                                  elevation: 0, padding: const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ]),
                        ],
                      ]),
                    ),
            ]),
            // ── END Proof Section ─────────────────────────────────────────
          ]))),

          const Divider(height: 28),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ]),
        ]),
      ),
    );
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

  Widget _row(String label, dynamic value, {bool isBold = false}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: const Color(0xFF2C3E50), fontSize: 13))),
          Expanded(child: Text(value.toString(), style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
        ]));
  }
}

// =============================================================================
//  EXPENSE STATS MODEL
// =============================================================================

class ExpenseStats {
  final double totalExpenses;
  final double totalBillable;
  final int    expenseCount;
  final Map<String, double> expensesByAccount;
  final Map<String, double> expensesByVendor;

  ExpenseStats({
    required this.totalExpenses, required this.totalBillable,
    required this.expenseCount,  required this.expensesByAccount,
    required this.expensesByVendor,
  });

  factory ExpenseStats.fromJson(Map<String, dynamic> j) => ExpenseStats(
    totalExpenses:     (j['totalExpenses']  as num).toDouble(),
    totalBillable:     (j['totalBillable']  as num).toDouble(),
    expenseCount:      j['expenseCount']    as int,
    expensesByAccount: Map<String, double>.from(j['expensesByAccount'] ?? {}),
    expensesByVendor:  Map<String, double>.from(j['expensesByVendor']  ?? {}),
  );
}

// =============================================================================
//  NOTE: Update your Expense model (expenses_service.dart) to add:
//
//  final ProofFile? proofFile;         ← add to constructor & fields
//  final String? expenseNumber;        ← already may exist
//
//  In Expense.fromJson():
//    proofFile: j['proofFile'] != null
//        ? ProofFile.fromJson(j['proofFile'] as Map<String, dynamic>)
//        : null,
//
//  In pubspec.yaml, ensure:
//    image_picker: ^1.0.0   (or latest)
// =============================================================================