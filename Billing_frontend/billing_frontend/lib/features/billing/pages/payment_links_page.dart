// ============================================================================
// PAYMENT LINKS LIST PAGE
// ============================================================================
// File: lib/screens/billing/payment_links/payment_links_list_page.dart
//
// Complete Payment Links module — Zoho Books style
// ✅ Stat cards (Total, Generated, Paid, Expired, Canceled, Total Collected)
// ✅ 3-breakpoint top bar (desktop / tablet / mobile)
// ✅ Dark navy DataTable with horizontal scroll + ellipsis pagination
// ✅ Copy Link → clipboard
// ✅ Share → share_plus
// ✅ Send Email → POST /links/:id/send
// ✅ Change Expiry → date picker dialog
// ✅ Cancel → PUT /links/:id/cancel
// ✅ Delete → DELETE /links/:id
// ✅ Mark as Paid → navigates to new_payment_page.dart (pre-filled)
// ✅ New Link Dialog — auto-detects org gateway, customer dropdown with
//    searchable popup (fetched from /api/finance/customers)
// ✅ Export to Excel
// ✅ orgId isolated — reads from JWT via backend
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/config/api_config.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'finance_profile_page.dart';
import 'new_payment_page.dart';   // for Mark as Paid navigation

// ─── colour palette (matches recurring_invoices_list_page) ────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);

// ─── Base URL helper ──────────────────────────────────────────────────────────
String get _base => ApiConfig.baseUrl;

// ─── JWT helper ───────────────────────────────────────────────────────────────
Future<Map<String, String>> _authHeaders() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('jwt_token') ?? '';
  return {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };
}

// ─── API helpers ──────────────────────────────────────────────────────────────
Future<Map<String, dynamic>> _get(String path) async {
  final r = await http.get(Uri.parse('$_base$path'), headers: await _authHeaders());
  final body = jsonDecode(r.body);
  if (r.statusCode >= 400) throw Exception(body['message'] ?? 'Request failed');
  return body;
}

Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) async {
  final r = await http.post(
    Uri.parse('$_base$path'),
    headers: await _authHeaders(),
    body: jsonEncode(body ?? {}),
  );
  final decoded = jsonDecode(r.body);
  if (r.statusCode >= 400) throw Exception(decoded['message'] ?? 'Request failed');
  return decoded;
}

Future<Map<String, dynamic>> _put(String path, [Map<String, dynamic>? body]) async {
  final r = await http.put(
    Uri.parse('$_base$path'),
    headers: await _authHeaders(),
    body: jsonEncode(body ?? {}),
  );
  final decoded = jsonDecode(r.body);
  if (r.statusCode >= 400) throw Exception(decoded['message'] ?? 'Request failed');
  return decoded;
}

Future<Map<String, dynamic>> _delete(String path) async {
  final r = await http.delete(Uri.parse('$_base$path'), headers: await _authHeaders());
  final decoded = jsonDecode(r.body);
  if (r.statusCode >= 400) throw Exception(decoded['message'] ?? 'Request failed');
  return decoded;
}

// ─── Models ───────────────────────────────────────────────────────────────────

class PaymentLink {
  final String id;
  final String referenceNumber;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final double amount;
  final String currency;
  final String description;
  final DateTime expirationDate;
  final String status;
  final String gateway;
  final String shortUrl;
  final String token;
  final double paidAmount;
  final DateTime? paidAt;
  final DateTime? emailSentAt;
  final DateTime createdAt;

  const PaymentLink({
    required this.id,
    required this.referenceNumber,
    required this.customerId,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.amount,
    required this.currency,
    required this.description,
    required this.expirationDate,
    required this.status,
    required this.gateway,
    required this.shortUrl,
    required this.token,
    required this.paidAmount,
    this.paidAt,
    this.emailSentAt,
    required this.createdAt,
  });

  factory PaymentLink.fromJson(Map<String, dynamic> j) => PaymentLink(
    id:              j['_id'] ?? '',
    referenceNumber: j['referenceNumber'] ?? '',
    customerId:      j['customerId'] ?? '',
    customerName:    j['customerName'] ?? '',
    customerEmail:   j['customerEmail'] ?? '',
    customerPhone:   j['customerPhone'] ?? '',
    amount:          (j['amount'] ?? 0).toDouble(),
    currency:        j['currency'] ?? 'INR',
    description:     j['description'] ?? '',
    expirationDate:  DateTime.tryParse(j['expirationDate'] ?? '') ?? DateTime.now(),
    status:          j['status'] ?? 'GENERATED',
    gateway:         j['gateway'] ?? 'razorpay',
    shortUrl:        j['shortUrl'] ?? '',
    token:           j['token'] ?? '',
    paidAmount:      (j['paidAmount'] ?? 0).toDouble(),
    paidAt:          j['paidAt'] != null ? DateTime.tryParse(j['paidAt']) : null,
    emailSentAt:     j['emailSentAt'] != null ? DateTime.tryParse(j['emailSentAt']) : null,
    createdAt:       DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );
}

class _Stats {
  final int total, generated, paid, expired, canceled;
  final double totalPaid;
  const _Stats({
    required this.total, required this.generated, required this.paid,
    required this.expired, required this.canceled, required this.totalPaid,
  });
  factory _Stats.empty() =>
      const _Stats(total: 0, generated: 0, paid: 0, expired: 0, canceled: 0, totalPaid: 0);
  factory _Stats.fromJson(Map<String, dynamic> j) => _Stats(
    total:     j['total']     ?? 0,
    generated: j['generated'] ?? 0,
    paid:      j['paid']      ?? 0,
    expired:   j['expired']   ?? 0,
    canceled:  j['canceled']  ?? 0,
    totalPaid: (j['totalPaid'] ?? 0).toDouble(),
  );
}

class _CustomerItem {
  final String id, name, email, phone;
  const _CustomerItem({required this.id, required this.name, required this.email, required this.phone});
  factory _CustomerItem.fromJson(Map<String, dynamic> j) => _CustomerItem(
    id:    j['_id'] ?? '',
    name:  j['customerDisplayName'] ?? j['customerName'] ?? '',
    email: j['primaryEmail'] ?? j['customerEmail'] ?? '',
    phone: j['primaryPhone'] ?? j['customerPhone'] ?? '',
  );
}

// ─── Stat card helper ─────────────────────────────────────────────────────────
class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradient;
  const _StatCardData({
    required this.label, required this.value,
    required this.icon,  required this.color,
    required this.gradient,
  });
}

// =============================================================================
//  MAIN PAGE
// =============================================================================

class PaymentLinksListPage extends StatefulWidget {
  const PaymentLinksListPage({Key? key}) : super(key: key);
  @override
  State<PaymentLinksListPage> createState() => _PaymentLinksListPageState();
}

class _PaymentLinksListPageState extends State<PaymentLinksListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<PaymentLink> _links    = [];
  _Stats            _stats    = _Stats.empty();
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String    _selectedStatus = 'ALL';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showAdvancedFilters = false;
  final List<String> _statusFilters = ['ALL', 'GENERATED', 'VIEWED', 'PAID', 'EXPIRED', 'CANCELED'];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchCtrl = TextEditingController();

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  final int _perPage = 20;
  List<PaymentLink> _filtered = [];

  // ── selection ─────────────────────────────────────────────────────────────
  Set<int> _selectedRows = {};
  bool _selectAll = false;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableHScroll = ScrollController();
  final ScrollController _statsHScroll = ScrollController();
  Timer? _autoRefreshTimer;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchCtrl.addListener(_applyFilters);
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadAll();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchCtrl.dispose();
    _tableHScroll.dispose();
    _statsHScroll.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final data = await _get('/api/finance/payment-gateway/links?limit=1000');
      final raw  = data['data'];
      setState(() {
        _links   = (raw['links'] as List? ?? []).map((l) => PaymentLink.fromJson(l)).toList();
        _stats   = _Stats.fromJson(raw['stats'] ?? {});
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _refresh() async {
    await _loadAll();
    _showSuccess('Data refreshed');
  }

  // ── filtering ─────────────────────────────────────────────────────────────

  void _applyFilters() {
    setState(() {
      final q = _searchCtrl.text.toLowerCase();
      _filtered = _links.where((l) {
        if (q.isNotEmpty &&
            !l.customerName.toLowerCase().contains(q) &&
            !l.referenceNumber.toLowerCase().contains(q) &&
            !l.description.toLowerCase().contains(q)) return false;
        if (_selectedStatus != 'ALL' && l.status != _selectedStatus) return false;
        if (_fromDate != null && l.createdAt.isBefore(_fromDate!)) return false;
        if (_toDate   != null && l.createdAt.isAfter(_toDate!.add(const Duration(days: 1)))) return false;
        return true;
      }).toList();
      _totalPages  = (_filtered.length / _perPage).ceil().clamp(1, 99999);
      if (_currentPage > _totalPages) _currentPage = _totalPages;
      _selectedRows.clear();
      _selectAll = false;
    });
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _selectedStatus      = 'ALL';
      _fromDate            = null;
      _toDate              = null;
      _currentPage         = 1;
      _showAdvancedFilters = false;
    });
    _applyFilters();
  }

  bool get _hasFilter =>
      _selectedStatus != 'ALL' || _fromDate != null || _toDate != null || _searchCtrl.text.isNotEmpty;

  List<PaymentLink> get _pageItems {
    final s = (_currentPage - 1) * _perPage;
    final e = (s + _perPage).clamp(0, _filtered.length);
    return _filtered.sublist(s, e);
  }

  // ── selection ─────────────────────────────────────────────────────────────

  void _toggleSelectAll(bool? v) {
    setState(() {
      _selectAll    = v ?? false;
      _selectedRows = _selectAll
          ? Set.from(List.generate(_pageItems.length, (i) => i))
          : {};
    });
  }

  void _toggleRow(int i) {
    setState(() {
      _selectedRows.contains(i) ? _selectedRows.remove(i) : _selectedRows.add(i);
      _selectAll = _selectedRows.length == _pageItems.length;
    });
  }

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context, initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!),
    );
    if (d != null) { setState(() => _fromDate = d); _applyFilters(); }
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context, initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!),
    );
    if (d != null) { setState(() => _toDate = d); _applyFilters(); }
  }

  // ── actions ───────────────────────────────────────────────────────────────

  void _copyLink(PaymentLink l) {
    Clipboard.setData(ClipboardData(text: l.shortUrl));
    _showSuccess('Link copied to clipboard');
  }

  Future<void> _shareLink(PaymentLink l) async {
    await Share.share(
      'Payment request of ₹${l.amount.toStringAsFixed(2)} — ${l.referenceNumber}\n${l.shortUrl}',
      subject: 'Payment Request — ${l.referenceNumber}',
    );
  }

  Future<void> _sendEmail(PaymentLink l) async {
    if (l.customerEmail.isEmpty) {
      _showError('No email address on this link');
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => _EmailPreviewDialog(
        link: l,
        onSent: () {
          _loadAll();
          _showSuccess('Email sent to ${l.customerEmail}');
        },
        onError: (msg) => _showError(msg),
      ),
    );
  }

  Future<void> _changeExpiry(PaymentLink l) async {
    final d = await showDatePicker(
      context: context,
      initialDate: l.expirationDate.isAfter(DateTime.now())
          ? l.expirationDate : DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!),
    );
    if (d == null) return;
    try {
      final r = await _put('/api/finance/payment-gateway/links/${l.id}/expiry', {
        'expirationDate': d.toIso8601String(),
      });
      _showSuccess(r['message'] ?? 'Expiry updated');
      _loadAll();
    } catch (e) { _showError('Failed to update expiry: $e'); }
  }

  Future<void> _cancelLink(PaymentLink l) async {
    final ok = await _confirmDialog(
      title: 'Cancel Payment Link',
      message: 'Cancel link ${l.referenceNumber}? Customer will no longer be able to pay.',
      confirmLabel: 'Cancel Link',
      confirmColor: _orange,
    );
    if (ok != true) return;
    try {
      await _put('/api/finance/payment-gateway/links/${l.id}/cancel');
      _showSuccess('Link canceled');
      _loadAll();
    } catch (e) { _showError('Failed to cancel: $e'); }
  }

  Future<void> _deleteLink(PaymentLink l) async {
    final ok = await _confirmDialog(
      title: 'Delete Payment Link',
      message: 'Delete link ${l.referenceNumber}? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await _delete('/api/finance/payment-gateway/links/${l.id}');
      _showSuccess('Link deleted');
      _loadAll();
    } catch (e) { _showError('Failed to delete: $e'); }
  }

  void _markAsPaid(PaymentLink l) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewPaymentPage(
          prefilledCustomerName: l.customerName,
          prefilledAmount:       l.amount,
          prefilledReference:    l.referenceNumber,
          showAppBar:            true,
          onSavedCallback: (_) {
            // After payment saved, also mark link as paid via backend
            _post('/api/finance/payment-gateway/links/${l.id}/mark-paid').then((_) {
              _loadAll();
            }).catchError((_) {});
          },
        ),
      ),
    ).then((ok) { if (ok == true) _loadAll(); });
  }

  void _openNewLinkDialog() {
    showDialog(
      context: context,
      builder: (_) => _NewLinkDialog(
        onCreated: () {
          _loadAll();
          _showSuccess('Payment link created successfully');
        },
        onError: (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _exportExcel() async {
    try {
      if (_filtered.isEmpty) { _showError('Nothing to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Reference #', 'Customer', 'Email', 'Amount', 'Status', 'Expiry Date', 'Created', 'Short URL'],
        ..._filtered.map((l) => [
          l.referenceNumber,
          l.customerName,
          l.customerEmail,
          l.amount.toStringAsFixed(2),
          l.status,
          DateFormat('dd/MM/yyyy').format(l.expirationDate),
          DateFormat('dd/MM/yyyy').format(l.createdAt),
          l.shortUrl,
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'payment_links');
      _showSuccess('✅ Excel downloaded (${_filtered.length} links)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── snackbars / dialogs ───────────────────────────────────────────────────

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
      appBar: AppTopBar(title: 'Payment Links'),
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
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFrom),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickTo),
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
    _actionBtn('New Link', Icons.add_rounded, _navy, _openNewLinkDialog),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _blue, _filtered.isEmpty ? null : _exportExcel),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 190),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFrom),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickTo),
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
      _actionBtn('New Link', Icons.add_rounded, _navy, _openNewLinkDialog),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _blue, _filtered.isEmpty ? null : _exportExcel),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _openNewLinkDialog),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _pickFrom),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _pickTo),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _applyFilters(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.filter_list, () => setState(() => _showAdvancedFilters = !_showAdvancedFilters)),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
      const SizedBox(width: 6),
      _compactBtn('Export', _blue, _filtered.isEmpty ? null : _exportExcel),
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
          if (_hasFilter) clearBtn,
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

  // ── stat cards ────────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final cards = [
      _StatCardData(label: 'Total Links',       value: _stats.total.toString(),     icon: Icons.link_rounded,        color: _navy,   gradient: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Generated',         value: _stats.generated.toString(), icon: Icons.pending_outlined,    color: _blue,   gradient: const [Color(0xFF3498DB), Color(0xFF2980B9)]),
      _StatCardData(label: 'Paid',              value: _stats.paid.toString(),      icon: Icons.check_circle_outline,color: _green,  gradient: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Expired',           value: _stats.expired.toString(),   icon: Icons.timer_off_outlined,  color: _orange, gradient: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Canceled',          value: _stats.canceled.toString(),  icon: Icons.cancel_outlined,     color: _red,    gradient: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'Total Collected',   value: '₹${_fmt(_stats.totalPaid)}',icon: Icons.currency_rupee,      color: _teal,   gradient: const [Color(0xFF1ABC9C), Color(0xFF16A085)]),
    ];

    return Container(
      width: double.infinity, color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScroll, scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(
              width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _statCard(e.value, compact: true),
            )).toList()),
          );
        }
        return Row(children: cards.asMap().entries.map((e) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
            child: _statCard(e.value, compact: false),
          ),
        )).toList());
      }),
    );
  }

  Widget _statCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [d.gradient[0].withOpacity(0.15), d.gradient[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                child: Icon(d.icon, color: Colors.white, size: 20)),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12),
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
    final items = _pageItems;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (ctx, constraints) {
        return Scrollbar(
          controller: _tableHScroll, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(ctx).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScroll, scrollDirection: Axis.horizontal,
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
                    const DataColumn(label: SizedBox(width: 120, child: Text('REFERENCE #'))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('CUSTOMER'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('AMOUNT'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('EXPIRY DATE'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('CREATED'))),
                    const DataColumn(label: SizedBox(width: 200, child: Text('ACTIONS'))),
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

  DataRow _buildRow(int index, PaymentLink l) {
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

        // Reference #
        DataCell(SizedBox(width: 120, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(l.referenceNumber, style: const TextStyle(color: _navy, fontWeight: FontWeight.w700, fontSize: 13)),
          if (l.emailSentAt != null)
            Text('Emailed ${DateFormat('dd MMM').format(l.emailSentAt!)}', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ]))),

        // Customer
        DataCell(SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(l.customerName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (l.description.isNotEmpty)
            Text(l.description, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          if (l.customerEmail.isNotEmpty)
            Text(l.customerEmail, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ]))),

        // Amount
        DataCell(SizedBox(width: 110, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('₹${_fmt(l.amount)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          if (l.status == 'PAID')
            Text('Paid: ₹${_fmt(l.paidAmount)}', style: const TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
        ]))),

        // Status
        DataCell(SizedBox(width: 100, child: _statusBadge(l.status))),

        // Expiry Date
        DataCell(SizedBox(width: 120, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(DateFormat('dd MMM yyyy').format(l.expirationDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          if (l.expirationDate.isBefore(DateTime.now()) && l.status != 'PAID' && l.status != 'CANCELED')
            const Text('Expired', style: TextStyle(fontSize: 10, color: _red, fontWeight: FontWeight.w600)),
        ]))),

        // Created
        DataCell(SizedBox(width: 120, child: Text(DateFormat('dd MMM yyyy').format(l.createdAt), style: const TextStyle(fontSize: 13)))),

        // Actions
        DataCell(SizedBox(width: 200, child: Row(children: [
          // Copy
          Tooltip(message: 'Copy Link', child: InkWell(
            onTap: () => _copyLink(l),
            child: Container(width: 30, height: 30, margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: _navy.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.copy, size: 15, color: _navy)),
          )),
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _shareLink(l),
            child: Container(width: 30, height: 30, margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.share, size: 15, color: _blue)),
          )),
          // Email
          Tooltip(message: 'Send Email', child: InkWell(
            onTap: l.status == 'PAID' || l.status == 'CANCELED' ? null : () => _sendEmail(l),
            child: Container(width: 30, height: 30, margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: l.status == 'PAID' || l.status == 'CANCELED' ? Colors.grey[100] : _teal.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                child: Icon(Icons.email_outlined, size: 15, color: l.status == 'PAID' || l.status == 'CANCELED' ? Colors.grey[300] : _teal)),
          )),
          // More menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              if (l.status != 'PAID' && l.status != 'CANCELED')
                _menuItem('mark_paid', Icons.check_circle_outline, _green, 'Mark as Paid'),
              if (l.status != 'PAID' && l.status != 'CANCELED')
                _menuItem('change_expiry', Icons.event_outlined, _blue, 'Change Expiry'),
              if (l.status != 'PAID' && l.status != 'CANCELED')
                _menuItem('cancel', Icons.cancel_outlined, _orange, 'Cancel Link', textColor: _orange),
              _menuItem('delete', Icons.delete_outline, _red, 'Delete', textColor: _red),
            ],
            onSelected: (v) {
              switch (v) {
                case 'mark_paid':     _markAsPaid(l);      break;
                case 'change_expiry': _changeExpiry(l);    break;
                case 'cancel':        _cancelLink(l);      break;
                case 'delete':        _deleteLink(l);      break;
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
      'GENERATED': [Color(0xFFEFF6FF), Color(0xFF2563EB)],
      'VIEWED':    [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'PAID':      [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'EXPIRED':   [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'CANCELED':  [Color(0xFFF1F5F9), Color(0xFF64748B)],
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
      child: LayoutBuilder(builder: (_, c) => Wrap(
        alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
        children: [
          Text(
            'Showing ${(_currentPage - 1) * _perPage + 1}–${(_currentPage * _perPage).clamp(0, _filtered.length)} of ${_filtered.length}${_filtered.length != _links.length ? ' (filtered from ${_links.length})' : ''}',
            style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1, onTap: () { setState(() => _currentPage--); }),
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
            _pageNavBtn(icon: Icons.chevron_right, enabled: _currentPage < _totalPages, onTap: () { setState(() => _currentPage++); }),
          ]),
        ],
      )),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () { if (!isActive) setState(() => _currentPage = page); },
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
          child: Icon(Icons.link_off_rounded, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Payment Links Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasFilter ? 'Try adjusting your filters' : 'Create your first payment link', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        onPressed: _hasFilter ? _clearFilters : _openNewLinkDialog,
        icon: Icon(_hasFilter ? Icons.filter_list_off : Icons.add),
        label: Text(_hasFilter ? 'Clear Filters' : 'New Link', style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      ),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Payment Links', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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

  // ── reusable widgets ──────────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s == 'ALL' ? 'All Links' : s))).toList(),
        onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFilters(); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search by customer, ref…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16),
                onPressed: () { _searchCtrl.clear(); setState(() => _currentPage = 1); _applyFilters(); })
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

  // ── helpers ───────────────────────────────────────────────────────────────

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(2);
  }
}

// =============================================================================
//  NEW LINK DIALOG
// =============================================================================

class _NewLinkDialog extends StatefulWidget {
  final VoidCallback onCreated;
  final void Function(String) onError;
  const _NewLinkDialog({required this.onCreated, required this.onError});
  @override
  State<_NewLinkDialog> createState() => _NewLinkDialogState();
}

class _NewLinkDialogState extends State<_NewLinkDialog> {

  // Gateway check
  bool   _checkingGateway = true;
  bool   _gatewayOk       = false;
  String _gatewayName     = '';
  String _gatewayMsg      = '';

  // Customer data
  List<_CustomerItem> _allCustomers      = [];
  List<_CustomerItem> _filteredCustomers = [];
  bool _loadingCustomers = true;
  _CustomerItem? _selectedCustomer;
  final TextEditingController _customerSearchCtrl = TextEditingController();

  // Form
  final _amountCtrl      = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  DateTime _expiryDate   = DateTime.now().add(const Duration(days: 15));
  bool _saving           = false;

  @override
  void initState() {
    super.initState();
    _checkGateway();
    _loadCustomers();
    _customerSearchCtrl.addListener(_filterCustomers);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    _customerSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkGateway() async {
    try {
      final data = await _get('/api/finance/payment-gateway/gateway/status');
      final d    = data['data'];
      setState(() {
        _checkingGateway = false;
        _gatewayOk   = d['configured'] == true;
        _gatewayName = d['gateway'] ?? '';
        _gatewayMsg  = _gatewayOk
            ? 'Using ${_gatewayName.toUpperCase()} · ${d['keyId'] ?? ''}'
            : 'No payment gateway configured. Go to Profile → Payment Gateway first.';
      });
    } catch (e) {
      setState(() { _checkingGateway = false; _gatewayOk = false; _gatewayMsg = 'Failed to check gateway: $e'; });
    }
  }

  Future<void> _loadCustomers() async {
    try {
      final data = await _get('/api/finance/customers?limit=1000&skipStats=true');
      final list = (data['data']?['customers'] as List? ?? [])
          .map((c) => _CustomerItem.fromJson(c))
          .toList();
      setState(() {
        _allCustomers      = list;
        _filteredCustomers = list;
        _loadingCustomers  = false;
      });
    } catch (e) {
      setState(() { _loadingCustomers = false; });
    }
  }

  void _filterCustomers() {
    final q = _customerSearchCtrl.text.toLowerCase();
    setState(() {
      _filteredCustomers = q.isEmpty
          ? _allCustomers
          : _allCustomers.where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.email.toLowerCase().contains(q) ||
              c.phone.toLowerCase().contains(q)).toList();
    });
  }

  Future<void> _pickExpiry() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _expiryDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!),
    );
    if (d != null) setState(() => _expiryDate = d);
  }

  // ── customer popup ────────────────────────────────────────────────────────

  void _showCustomerPicker() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 480,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF0D1B3E), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_search, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Select Customer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    controller: _customerSearchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search by name, email or phone…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _customerSearchCtrl.text.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _customerSearchCtrl.clear(); })
                          : null,
                      filled: true, fillColor: const Color(0xFFF7F9FC),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                    ),
                    onChanged: (_) => setDlg(() => _filterCustomers()),
                  ),
                ),
                // List
                Flexible(child: _loadingCustomers
                    ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: _navy)))
                    : _filteredCustomers.isEmpty
                        ? Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No customers found', style: TextStyle(color: Colors.grey[500]))))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filteredCustomers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                            itemBuilder: (_, i) {
                              final c = _filteredCustomers[i];
                              final isSel = _selectedCustomer?.id == c.id;
                              return InkWell(
                                onTap: () {
                                  setState(() => _selectedCustomer = c);
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 18, backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
                                      child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                          style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      if (c.email.isNotEmpty)
                                        Text(c.email, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                      if (c.phone.isNotEmpty)
                                        Text(c.phone, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ]),
                                ),
                              );
                            },
                          )),
                // Footer count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F9FC),
                    border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Text('${_filteredCustomers.length} customer(s)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedCustomer == null) { widget.onError('Please select a customer'); return; }
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) { widget.onError('Please enter a valid amount'); return; }

    setState(() => _saving = true);
    try {
      await _post('/api/finance/payment-gateway/links', {
        'customerId':    _selectedCustomer!.id,
        'customerName':  _selectedCustomer!.name,
        'customerEmail': _selectedCustomer!.email,
        'customerPhone': _selectedCustomer!.phone,
        'amount':        amount,
        'description':   _descriptionCtrl.text.trim(),
        'expirationDate': _expiryDate.toIso8601String(),
      });
      setState(() => _saving = false);
      Navigator.pop(context);
      widget.onCreated();
    } catch (e) {
      setState(() => _saving = false);
      widget.onError('Failed to create link: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: 540,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0D1B3E), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.link_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Create Payment Link', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Send a payment request to your customer', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // ── body ────────────────────────────────────────────────────────
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Gateway status
              _checkingGateway
                  ? Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10)),
                      child: const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _navy)), SizedBox(width: 12), Text('Checking gateway…')]),
                    )
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _gatewayOk ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: (_gatewayOk ? _green : _red).withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        Icon(_gatewayOk ? Icons.check_circle : Icons.error_outline, color: _gatewayOk ? _green : _red, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_gatewayMsg, style: TextStyle(fontSize: 13, color: _gatewayOk ? const Color(0xFF065F46) : const Color(0xFF991B1B)))),
                      ]),
                    ),

              if (!_checkingGateway && !_gatewayOk) ...[
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceProfilePage()));
                  },
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Go to Profile'),
                  style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                )),
              ],

              if (!_checkingGateway && _gatewayOk) ...[
                const SizedBox(height: 20),

                // Customer selector
                const Text('Customer *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D1B3E))),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _showCustomerPicker,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      border: Border.all(color: _selectedCustomer != null ? _navy : const Color(0xFFDDE3EE)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.person_outline, size: 18, color: _selectedCustomer != null ? _navy : Colors.grey[400]),
                      const SizedBox(width: 10),
                      Expanded(child: _selectedCustomer == null
                          ? Text('Tap to select customer…', style: TextStyle(fontSize: 14, color: Colors.grey[500]))
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_selectedCustomer!.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF0D1B3E))),
                              if (_selectedCustomer!.email.isNotEmpty)
                                Text(_selectedCustomer!.email, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            ])),
                      Icon(Icons.search, size: 18, color: Colors.grey[400]),
                    ]),
                  ),
                ),

                const SizedBox(height: 16),

                // Amount
                const Text('Amount (₹) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D1B3E))),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                    filled: true, fillColor: const Color(0xFFF7F9FC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),

                const SizedBox(height: 16),

                // Description
                const Text('Description (optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D1B3E))),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'e.g. Invoice #1234, Logistics charges…',
                    filled: true, fillColor: const Color(0xFFF7F9FC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),

                const SizedBox(height: 16),

                // Expiry Date
                const Text('Expiry Date *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D1B3E))),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickExpiry,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      border: Border.all(color: const Color(0xFFDDE3EE)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.event_outlined, size: 18, color: _navy),
                      const SizedBox(width: 10),
                      Expanded(child: Text(DateFormat('dd MMM yyyy').format(_expiryDate), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14))),
                      Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
                    ]),
                  ),
                ),

                // Days remaining note
                Builder(builder: (_) {
                  final days = _expiryDate.difference(DateTime.now()).inDays;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Link expires in $days day(s)', style: TextStyle(fontSize: 12, color: days < 3 ? _red : Colors.grey[500])),
                  );
                }),

                const SizedBox(height: 16),

                // Info note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber[300]!)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline, color: Colors.amber[700], size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'The payment link will be created on ${_gatewayName.toUpperCase()} using your connected account. Customer can pay via UPI, card, net banking, or wallet.',
                      style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                    )),
                  ]),
                ),
              ],
            ]),
          )),

          // ── footer ──────────────────────────────────────────────────────
          if (!_checkingGateway && _gatewayOk)
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
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy, foregroundColor: Colors.white,
                    disabledBackgroundColor: _navy.withOpacity(0.4),
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Create Link', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                )),
              ]),
            ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  EMAIL PREVIEW DIALOG
// =============================================================================

class _EmailPreviewDialog extends StatefulWidget {
  final PaymentLink link;
  final VoidCallback onSent;
  final void Function(String) onError;
  const _EmailPreviewDialog({required this.link, required this.onSent, required this.onError});

  @override
  State<_EmailPreviewDialog> createState() => _EmailPreviewDialogState();
}

class _EmailPreviewDialogState extends State<_EmailPreviewDialog> {
  late TextEditingController _toCtrl;
  late TextEditingController _subjectCtrl;
  late TextEditingController _bodyCtrl;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final l = widget.link;
    _toCtrl      = TextEditingController(text: l.customerEmail);
    _subjectCtrl = TextEditingController(
      text: 'Payment Request — ₹${l.amount.toStringAsFixed(2)} — ${l.referenceNumber}',
    );
    _bodyCtrl = TextEditingController(text: _buildEmailBody(l));
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  String _buildEmailBody(PaymentLink l) {
    final expiry   = DateFormat('dd MMM yyyy').format(l.expirationDate);
    final created  = DateFormat('dd MMM yyyy').format(l.createdAt);
    return '''Dear ${l.customerName},

We hope this message finds you well.

Please find below your payment request details:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PAYMENT REQUEST DETAILS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Reference #     : ${l.referenceNumber}
Amount Due      : ₹${l.amount.toStringAsFixed(2)}
${l.description.isNotEmpty ? 'Description     : ${l.description}\n' : ''}Date Created    : $created
Expiry Date     : $expiry
Gateway         : ${l.gateway.toUpperCase()}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Please click the link below to complete your payment:

${l.shortUrl}

You can pay using UPI, Credit/Debit Card, Net Banking, or Wallet.

Important: This payment link expires on $expiry. Please complete your payment before the expiry date.

If you have already made the payment, please ignore this email.

For any queries, please reply to this email.

Thank you for your business.

Warm regards,
Accounts & Finance Team''';
  }

  Future<void> _send() async {
    if (_toCtrl.text.trim().isEmpty) {
      widget.onError('Please enter an email address');
      return;
    }
    setState(() => _sending = true);
    try {
      await _post('/api/finance/payment-gateway/links/${widget.link.id}/send', {
        'emails':  [_toCtrl.text.trim()],
        'subject': _subjectCtrl.text.trim(),
        'body':    _bodyCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context);
      widget.onSent();
    } catch (e) {
      setState(() => _sending = false);
      widget.onError('Failed to send email: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: Container(
        width: 600,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.90),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D1B3E), Color(0xFF2463AE)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20), topRight: Radius.circular(20),
              ),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.email_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Send Payment Request Email',
                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                Text('Review and edit before sending',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ]),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Link info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _navy.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.link, color: _navy, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${widget.link.referenceNumber} — ₹${widget.link.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _navy),
                    ),
                    Text(
                      widget.link.shortUrl,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ])),
                ]),
              ),

              const SizedBox(height: 16),

              // To field
              const Text('To *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D1B3E))),
              const SizedBox(height: 6),
              TextField(
                controller: _toCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'customer@email.com',
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                  filled: true, fillColor: const Color(0xFFF7F9FC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),

              const SizedBox(height: 14),

              // Subject field
              const Text('Subject', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D1B3E))),
              const SizedBox(height: 6),
              TextField(
                controller: _subjectCtrl,
                decoration: InputDecoration(
                  hintText: 'Email subject…',
                  prefixIcon: const Icon(Icons.subject, size: 18),
                  filled: true, fillColor: const Color(0xFFF7F9FC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),

              const SizedBox(height: 14),

              // Body field
              Row(children: [
                const Text('Message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D1B3E))),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _bodyCtrl.text = _buildEmailBody(widget.link)),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Reset to default', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: _navy),
                ),
              ]),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                maxLines: 18,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  filled: true, fillColor: const Color(0xFFFAFBFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),

              const SizedBox(height: 12),

              // Info note
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[300]!),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, color: Colors.amber[700], size: 15),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'The payment link will be included in the email. Customer can click it to pay directly.',
                    style: TextStyle(fontSize: 12, color: Colors.amber[900]),
                  )),
                ]),
              ),
            ]),
          )),

          // ── Footer ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FC),
              border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
              ),
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
              Expanded(child: ElevatedButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(_sending ? 'Sending…' : 'Send Email',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _navy.withOpacity(0.4),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}
