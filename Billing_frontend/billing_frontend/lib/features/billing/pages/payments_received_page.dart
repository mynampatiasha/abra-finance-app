// ============================================================================
// PAYMENTS RECEIVED PAGE — Credit Notes / Payment Made UI Pattern
// ============================================================================
// File: lib/features/admin/Billing/pages/payments_received_page.dart
//
// ✅ 3-breakpoint top bar (Desktop ≥1100 / Tablet 700–1100 / Mobile <700)
// ✅ 7 gradient stat cards in ONE single row (h-scroll on tablet/mobile)
// ✅ Client-side pagination (20 per page) — zero backend changes needed
// ✅ Dark navy #0D1B3E table header, drag-to-scroll, visible scrollbar
// ✅ Ellipsis pagination widget (same as payment_made_list_page)
// ✅ Share button per row → share_plus (web + mobile)
// ✅ WhatsApp → live lookup via BillingCustomersService.getCustomerById()
// ✅ Raise Ticket → row popup → overlay with employee list + assign
// ✅ All original functionality preserved (View Details, Proofs, Delete, Export, Process)
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/billing_customers_service.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/services/tms_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'new_payment_page.dart';
import 'payment_received_detail_page.dart';

// ─── colour palette ───────────────────────────────────────────────────────────
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
    required this.label, required this.value,
    required this.icon,  required this.color,
    required this.gradientColors,
  });
}

// =============================================================================
//  MAIN PAGE
// =============================================================================

class PaymentsReceivedPage extends StatefulWidget {
  const PaymentsReceivedPage({Key? key}) : super(key: key);
  @override
  State<PaymentsReceivedPage> createState() => _PaymentsReceivedPageState();
}

class _PaymentsReceivedPageState extends State<PaymentsReceivedPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allPayments  = []; // full unfiltered list
  List<Map<String, dynamic>> _pagePayments = []; // current page slice
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── stats (computed from _allPayments) ────────────────────────────────────
  double _totalReceived = 0;
  double _thisMonth     = 0;
  int    _totalCount    = 0;
  int    _withProofs    = 0;
  int    _paidCount     = 0;
  int    _draftCount    = 0;
  int    _voidCount     = 0;

  // ── filters ───────────────────────────────────────────────────────────────
  String    _statusFilter = 'All Payments';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showAdvancedFilters = false;

  static const _filterOptions = ['All Payments', 'Draft', 'Paid', 'Void'];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  int _grandTotal   = 0;
  static const int _pageSize = 20;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── load ──────────────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final all = await PaymentService.getPaymentsReceived(
        filter: _statusFilter == 'All Payments' ? null : _statusFilter,
      );
      setState(() => _allPayments = all);
      _computeStats();
      _applyFiltersAndPaginate();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _refresh() async {
    _currentPage = 1;
    await _loadAll();
    _showSuccess('Refreshed');
  }

  // ── stats ─────────────────────────────────────────────────────────────────

  void _computeStats() {
    double totalReceived = 0, thisMonth = 0;
    int withProofs = 0, paid = 0, draft = 0, voidCount = 0;
    final now = DateTime.now();

    for (final p in _allPayments) {
      final amt = ((p['amount'] ?? 0) as num).toDouble();
      totalReceived += amt;
      if (p['hasProofs'] == true) withProofs++;

      final status = (p['status'] ?? '').toString().toLowerCase();
      if (status == 'paid')  paid++;
      if (status == 'draft') draft++;
      if (status == 'void')  voidCount++;

      try {
        final parts = (p['date'] ?? '').split('/');
        if (parts.length == 3 &&
            int.parse(parts[1]) == now.month &&
            int.parse(parts[2]) == now.year) {
          thisMonth += amt;
        }
      } catch (_) {}
    }

    setState(() {
      _totalReceived = totalReceived;
      _thisMonth     = thisMonth;
      _totalCount    = _allPayments.length;
      _withProofs    = withProofs;
      _paidCount     = paid;
      _draftCount    = draft;
      _voidCount     = voidCount;
    });
  }

  // ── client-side filter + paginate ─────────────────────────────────────────

  void _applyFiltersAndPaginate() {
    final q = _searchQuery.toLowerCase().trim();

    // Search
    List<Map<String, dynamic>> result = q.isEmpty
        ? List.from(_allPayments)
        : _allPayments.where((p) =>
            (p['paymentNumber']   ?? '').toString().toLowerCase().contains(q) ||
            (p['customerName']    ?? '').toString().toLowerCase().contains(q) ||
            (p['referenceNumber'] ?? '').toString().toLowerCase().contains(q) ||
            (p['invoiceNumber']   ?? '').toString().toLowerCase().contains(q) ||
            (p['mode']            ?? '').toString().toLowerCase().contains(q)
          ).toList();

    // Date filter
    if (_fromDate != null || _toDate != null) {
      result = result.where((p) {
        try {
          final parts = (p['date'] ?? '').split('/');
          if (parts.length != 3) return true;
          final d = DateTime(
              int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          if (_fromDate != null && d.isBefore(_fromDate!)) return false;
          if (_toDate   != null && d.isAfter(_toDate!))   return false;
          return true;
        } catch (_) { return true; }
      }).toList();
    }

    // Paginate
    final total = result.length;
    final pages = (total / _pageSize).ceil().clamp(1, 9999);
    if (_currentPage > pages) _currentPage = pages;
    final start = (_currentPage - 1) * _pageSize;
    final end   = (start + _pageSize).clamp(0, total);

    setState(() {
      _grandTotal   = total;
      _totalPages   = pages;
      _pagePayments = result.sublist(start, end);
    });
  }

  void _onSearchChanged() {
    setState(() { _searchQuery = _searchController.text; _currentPage = 1; });
    _applyFiltersAndPaginate();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _statusFilter        = 'All Payments';
      _fromDate            = null;
      _toDate              = null;
      _searchQuery         = '';
      _currentPage         = 1;
      _showAdvancedFilters = false;
    });
    _loadAll();
  }

  bool get _hasAnyFilter =>
      _statusFilter != 'All Payments' || _fromDate != null ||
      _toDate != null || _searchQuery.isNotEmpty;

  // ── navigation ────────────────────────────────────────────────────────────

  void _openNew() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewPaymentPage()))
        .then((_) => _refresh());
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await _confirmDialog(
      title: 'Delete Payment #${p['paymentNumber']}?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await PaymentService.deletePayment(p['id']);
      _showSuccess('Payment deleted');
      _refresh();
    } catch (e) { _showError('Delete failed: $e'); }
  }

  void _viewDetails(Map<String, dynamic> p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaymentReceivedDetailPage(payment: p)),
    );
  }

  Future<void> _viewProofs(Map<String, dynamic> p) async {
    try {
      final proofs = await PaymentService.getPaymentProofs(p['id']);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Proofs — #${p['paymentNumber']}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: proofs.isEmpty
                ? const Text('No proofs attached')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: proofs.length,
                    itemBuilder: (_, i) {
                      final proof = proofs[i];
                      return ListTile(
                        leading: Icon(
                          proof.fileType.contains('pdf')
                              ? Icons.picture_as_pdf_outlined
                              : Icons.image_outlined,
                          color: _green, size: 28,
                        ),
                        title: Text(proof.filename,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${(proof.fileSize / 1024).toStringAsFixed(1)} KB',
                            style: TextStyle(color: Colors.grey[600])),
                        trailing: IconButton(
                          icon: const Icon(Icons.download_rounded, color: _blue),
                          onPressed: () async {
                            try {
                              final url = await PaymentService.downloadPaymentProof(
                                  p['id'], i.toString());
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            } catch (e) { _showError('Download failed: $e'); }
                          },
                        ),
                      );
                    }),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) { _showError('Failed to load proofs: $e'); }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _sharePayment(Map<String, dynamic> p) async {
    final amount = ((p['amount'] ?? 0.0) as num).toStringAsFixed(2);
    final text =
        'Payment Received\n'
        '─────────────────────────\n'
        'Payment # : ${p['paymentNumber'] ?? ''}\n'
        'Customer  : ${p['customerName'] ?? ''}\n'
        'Date      : ${p['date'] ?? ''}\n'
        'Mode      : ${p['mode'] ?? ''}\n'
        'Amount    : ₹$amount\n'
        'Reference : ${p['referenceNumber'] ?? '-'}\n'
        'Invoice # : ${p['invoiceNumber'] ?? '-'}\n'
        'Status    : ${p['status'] ?? 'paid'}';
    try {
      await Share.share(text, subject: 'Payment Receipt: ${p['paymentNumber']}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(Map<String, dynamic> p) async {
    final customerId = p['customerId']?.toString() ?? '';
    if (customerId.isEmpty) {
      _showError('Customer ID not available on this payment.');
      return;
    }
    try {
      _showSuccess('Looking up customer phone…');
      final res      = await BillingCustomersService.getCustomerById(customerId);
      final customer = res['data'];
      final phone =
          (customer?['primaryPhone'] ?? customer?['phone'] ?? '').toString().trim();

      if (phone.isEmpty) {
        _showError('Customer phone not available. Please update the customer profile.');
        return;
      }

      final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
      final amount  = ((p['amount'] ?? 0.0) as num).toStringAsFixed(2);
      final msg     = Uri.encodeComponent(
        'Hello ${p['customerName'] ?? ''},\n\n'
        'We have received your payment of ₹$amount '
        'for Payment #${p['paymentNumber'] ?? ''} on ${p['date'] ?? ''}.\n\n'
        'Payment Mode: ${p['mode'] ?? ''}\n'
        '${(p['referenceNumber'] ?? '').toString().isNotEmpty
            ? 'Reference: ${p['referenceNumber']}\n' : ''}'
        '\nThank you!',
      );

      final url = Uri.parse('https://wa.me/$cleaned?text=$msg');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showError('Could not open WhatsApp');
      }
    } catch (e) { _showError('Failed to fetch customer phone: $e'); }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket(Map<String, dynamic> p) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        payment: p,
        onTicketRaised: _showSuccess,
        onError:        _showError,
      ),
    );
  }

  // ── view process ──────────────────────────────────────────────────────────

  void _showProcessDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      builder: (ctx) {
        final sw = MediaQuery.of(context).size.width;
        final sh = MediaQuery.of(context).size.height;
        return Center(child: Material(color: Colors.transparent, child: Container(
          width: (sw * 0.88).clamp(320.0, 1000.0),
          height: sh * 0.85,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35),
                blurRadius: 30, offset: const Offset(0, 12))],
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              ),
              child: Row(children: [
                const Icon(Icons.account_tree_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Payments Received — Process Flow',
                    style: TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w600))),
                InkWell(onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: Colors.white, size: 20)),
              ]),
            ),
            Expanded(child: ClipRRect(
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
              child: Image.asset(
                'assets/payment_received.png',
                width: double.infinity, height: double.infinity, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _fallbackFlow(),
              ),
            )),
          ]),
        )));
      },
    );
  }

  Widget _fallbackFlow() {
    final steps = [
      {'icon': Icons.drafts_outlined, 'label': 'DRAFT', 'color': Colors.grey},
      {'icon': Icons.check_circle,    'label': 'PAID',  'color': _green},
      {'icon': Icons.cancel_outlined, 'label': 'VOID',  'color': _red},
    ];
    return Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 16,
          children: steps.expand((s) => [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (s['color'] as Color).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: s['color'] as Color, width: 2),
                ),
                child: Column(children: [
                  Icon(s['icon'] as IconData, color: s['color'] as Color, size: 28),
                  const SizedBox(height: 6),
                  Text(s['label'] as String, style: TextStyle(
                      color: s['color'] as Color,
                      fontWeight: FontWeight.bold, fontSize: 10)),
                ]),
              ),
            ]),
            if (s != steps.last)
              Padding(padding: const EdgeInsets.only(top: 20),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.grey[400])),
          ]).toList(),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200)),
          child: const Text('Draft → Paid → Void',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
        ),
      ],
    ));
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _handleExport() async {
    try {
      if (_allPayments.isEmpty) { _showError('Nothing to export'); return; }
      _showSuccess('Preparing export…');
      final rows = <List<dynamic>>[
        ['Date', 'Payment #', 'Reference', 'Customer', 'Invoice #', 'Mode',
         'Amount', 'Bank Charges', 'Net Amount', 'Deposit To',
         'Tax Deduction', 'Status', 'Has Proofs', 'Proofs Count', 'Notes', 'Created At'],
        ..._allPayments.map((p) {
          final amt = ((p['amountReceived'] ?? p['amount'] ?? 0) as num).toDouble();
          final chg = ((p['bankCharges'] ?? 0) as num).toDouble();
          final net = ((p['netAmount']   ?? amt - chg) as num).toDouble();
          return [
            p['paymentDate'] ?? p['date'] ?? '',
            p['paymentNumber'] ?? '',
            p['reference'] ?? p['referenceNumber'] ?? '',
            p['customerName'] ?? '',
            p['invoiceNumber'] ?? '',
            p['paymentMode'] ?? p['mode'] ?? '',
            amt.toStringAsFixed(2), chg.toStringAsFixed(2), net.toStringAsFixed(2),
            p['depositTo'] ?? '',
            p['taxDeduction'] ?? 'No Tax deducted',
            p['status'] ?? 'paid',
            (p['paymentProofs'] != null &&
                    (p['paymentProofs'] as List).isNotEmpty) ||
                p['hasProofs'] == true ? 'Yes' : 'No',
            (p['proofsCount'] ?? (p['paymentProofs'] != null
                ? (p['paymentProofs'] as List).length : 0)).toString(),
            p['notes'] ?? '',
            p['createdAt'] ?? '',
          ];
        }),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'payments_received');
      _showSuccess('✅ Excel downloaded (${_allPayments.length} payments)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
            colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!,
      ),
    );
    if (d != null) {
      setState(() { _fromDate = d; _currentPage = 1; });
      _applyFiltersAndPaginate();
    }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020), lastDate: DateTime(2100),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
            colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!,
      ),
    );
    if (d != null) {
      setState(() { _toDate = d; _currentPage = 1; });
      _applyFiltersAndPaginate();
    }
  }

  // ── snackbars ─────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8), Expanded(child: Text(msg)),
      ]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8), Expanded(child: Text(msg)),
      ]),
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
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor, foregroundColor: Colors.white),
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
      appBar: AppTopBar(title: 'Payments Received'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          if (_showAdvancedFilters) _buildAdvancedFiltersBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400,
                  child: Center(child: CircularProgressIndicator(color: _navy)))
              : _errorMessage != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _pagePayments.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _pagePayments.isNotEmpty) _buildPagination(),
          const SizedBox(height: 24),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 6, offset: const Offset(0, 2))],
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
      label: _fromDate != null ? 'From: ${_fmtD(_fromDate!)}' : 'From Date',
      isActive: _fromDate != null, onTap: _pickFromDate,
    ),
    const SizedBox(width: 8),
    _dateChip(
      label: _toDate != null ? 'To: ${_fmtD(_toDate!)}' : 'To Date',
      isActive: _toDate != null, onTap: _pickToDate,
    ),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, () {
        setState(() { _fromDate = null; _toDate = null; _currentPage = 1; });
        _applyFiltersAndPaginate();
      }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.filter_list,
        () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
        tooltip: 'Filters',
        color: _showAdvancedFilters ? _navy : const Color(0xFF7F8C8D),
        bg: _showAdvancedFilters ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh,
        tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree_outlined, _showProcessDialog,
        tooltip: 'View Process', color: _green),
    const Spacer(),
    _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _blue,
        _allPayments.isEmpty ? null : _handleExport),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 190),
      const SizedBox(width: 8),
      _dateChip(
        label: _fromDate != null ? 'From: ${_fmtD(_fromDate!)}' : 'From Date',
        isActive: _fromDate != null, onTap: _pickFromDate,
      ),
      const SizedBox(width: 6),
      _dateChip(
        label: _toDate != null ? 'To: ${_fmtD(_toDate!)}' : 'To Date',
        isActive: _toDate != null, onTap: _pickToDate,
      ),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () {
          setState(() { _fromDate = null; _toDate = null; _currentPage = 1; });
          _applyFiltersAndPaginate();
        }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.filter_list,
          () => setState(() => _showAdvancedFilters = !_showAdvancedFilters),
          tooltip: 'Filters'),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh,
          tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree_outlined, _showProcessDialog,
          tooltip: 'View Process', color: _green),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _blue,
          _allPayments.isEmpty ? null : _handleExport),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          label: _fromDate != null ? 'From: ${_fmtD(_fromDate!)}' : 'From Date',
          isActive: _fromDate != null, onTap: _pickFromDate,
        ),
        const SizedBox(width: 6),
        _dateChip(
          label: _toDate != null ? 'To: ${_fmtD(_toDate!)}' : 'To Date',
          isActive: _toDate != null, onTap: _pickToDate,
        ),
        if (_fromDate != null || _toDate != null) ...[
          const SizedBox(width: 6),
          _iconBtn(Icons.close, () {
            setState(() { _fromDate = null; _toDate = null; _currentPage = 1; });
            _applyFiltersAndPaginate();
          }, color: _red, bg: Colors.red[50]!),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.filter_list,
            () => setState(() => _showAdvancedFilters = !_showAdvancedFilters)),
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh,
            tooltip: 'Refresh'),
        const SizedBox(width: 6),
        _iconBtn(Icons.account_tree_outlined, _showProcessDialog, color: _green),
        const SizedBox(width: 6),
        _compactBtn('Export', _blue,
            _allPayments.isEmpty ? null : _handleExport),
      ]),
    ),
  ]);

  // ── ADVANCED FILTERS ──────────────────────────────────────────────────────

  Widget _buildAdvancedFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: Row(children: [
        const Text('Filters:', style: TextStyle(fontSize: 13,
            fontWeight: FontWeight.w600, color: _navy)),
        const Spacer(),
        if (_hasAnyFilter)
          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Clear All'),
            style: TextButton.styleFrom(foregroundColor: _red),
          ),
      ]),
    );
  }

  // ── REUSABLE WIDGETS ──────────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      border: Border.all(color: const Color(0xFFDDE3EE)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _statusFilter,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w600, color: _navy),
        items: _filterOptions.map((s) =>
            DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() { _statusFilter = v; _currentPage = 1; });
            _loadAll();
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
        hintText: 'Search payment #, customer, ref…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() { _searchQuery = ''; _currentPage = 1; });
                  _applyFiltersAndPaginate();
                })
            : null,
        filled: true, fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _dateChip({required String label, required bool isActive,
      required VoidCallback onTap}) {
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
          Icon(Icons.calendar_today, size: 15,
              color: isActive ? _navy : Colors.grey[500]),
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

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {
    String tooltip = '',
    Color color = const Color(0xFF7F8C8D),
    Color bg = const Color(0xFFF1F1F1),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20,
              color: onTap == null ? Colors.grey[300] : color),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
      child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  // ── STATS CARDS — 7 in ONE row ────────────────────────────────────────────

  Widget _buildStatsCards() {
    final cards = [
      _StatCardData(
        label: 'Total Received', value: '₹${_fmtNum(_totalReceived)}',
        icon: Icons.account_balance_wallet_outlined, color: _green,
        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'This Month', value: '₹${_fmtNum(_thisMonth)}',
        icon: Icons.calendar_today_outlined, color: _blue,
        gradientColors: const [Color(0xFF5DADE2), Color(0xFF2980B9)],
      ),
      _StatCardData(
        label: 'Total Payments', value: _totalCount.toString(),
        icon: Icons.payments_outlined, color: _navy,
        gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)],
      ),
      _StatCardData(
        label: 'With Proofs', value: _withProofs.toString(),
        icon: Icons.attach_file_rounded, color: _purple,
        gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)],
      ),
      _StatCardData(
        label: 'Paid', value: _paidCount.toString(),
        icon: Icons.check_circle_outline, color: _teal,
        gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)],
      ),
      _StatCardData(
        label: 'Draft', value: _draftCount.toString(),
        icon: Icons.drafts_outlined, color: _orange,
        gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)],
      ),
      _StatCardData(
        label: 'Void', value: _voidCount.toString(),
        icon: Icons.cancel_outlined, color: _red,
        gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)],
      ),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        // Desktop ≥1100: all 7 expanded in a single row
        if (c.maxWidth >= 1100) {
          return Row(children: cards.asMap().entries.map((e) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 8 : 0),
              child: _buildStatCard(e.value, compact: false),
            ),
          )).toList());
        }
        // Tablet + mobile: scrollable strip
        return SingleChildScrollView(
          controller: _statsHScrollCtrl,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards.asMap().entries.map((e) => Container(
              width: c.maxWidth < 700 ? 148 : 172,
              margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _buildStatCard(e.value, compact: true),
            )).toList(),
          ),
        );
      }),
    );
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact
          ? const EdgeInsets.all(11)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [d.gradientColors[0].withOpacity(0.15),
                   d.gradientColors[1].withOpacity(0.08)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: d.gradientColors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(d.icon, color: Colors.white, size: 17),
              ),
              const SizedBox(height: 8),
              Text(d.label, style: TextStyle(fontSize: 10, color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(d.value, style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.bold, color: d.color),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: d.gradientColors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: d.color.withOpacity(0.28),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Icon(d.icon, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(d.label, style: TextStyle(fontSize: 10,
                    color: Colors.grey[600], fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(d.value, style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.bold, color: d.color),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
    );
  }

  // ── TABLE ─────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl,
          thumbVisibility: true, trackVisibility: true,
          thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad},
            ),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                  headingRowHeight: 52,
                  dataRowMinHeight: 58, dataRowMaxHeight: 74,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered))
                      return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 18, horizontalMargin: 16,
                  columns: const [
                    const DataColumn(label: Text('DATE')),
                    const DataColumn(label: Text('PAYMENT #')),
                    const DataColumn(label: Text('REFERENCE')),
                    const DataColumn(label: Text('CUSTOMER')),
                    const DataColumn(label: Text('INVOICE #')),
                    const DataColumn(label: Text('MODE')),
                    const DataColumn(label: Text('AMOUNT')),
                    const DataColumn(label: Text('PROOFS')),
                    const DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _pagePayments.map(_buildRow).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(Map<String, dynamic> p) {
    return DataRow(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(SizedBox(width: 100,
            child: Text(p['date'] ?? '', style: const TextStyle(fontSize: 13)))),

        DataCell(SizedBox(width: 140, child: InkWell(
          onTap: () => _viewDetails(p),
          child: Text(p['paymentNumber']?.toString() ?? '',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w600,
                  fontSize: 13, decoration: TextDecoration.underline)),
        ))),

        DataCell(SizedBox(width: 120, child: Text(p['referenceNumber'] ?? '-',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            overflow: TextOverflow.ellipsis))),

        DataCell(SizedBox(width: 160, child: Text(p['customerName'] ?? '',
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis))),

        DataCell(SizedBox(width: 120, child: Text(p['invoiceNumber'] ?? '-',
            style: const TextStyle(color: _blue, fontWeight: FontWeight.w500,
                fontSize: 13),
            overflow: TextOverflow.ellipsis))),

        DataCell(SizedBox(width: 110,
            child: Text(p['mode'] ?? '',
                style: const TextStyle(fontSize: 13)))),

        DataCell(SizedBox(width: 120, child: Text(
          '₹${_fmtNum((p['amount'] ?? 0.0) as num)}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ))),

        DataCell(SizedBox(width: 80, child: p['hasProofs'] == true
            ? InkWell(
                onTap: () => _viewProofs(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _green.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.attach_file, size: 14, color: _green),
                    const SizedBox(width: 4),
                    Text('${p['proofsCount'] ?? 0}', style: const TextStyle(
                        color: _green, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              )
            : Text('-', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        )),

        DataCell(SizedBox(width: 140, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _sharePayment(p),
            child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 16, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(p),
          //   child: Container(width: 32, height: 32,
          //       decoration: BoxDecoration(
          //           color: const Color(0xFF25D366).withOpacity(0.10),
          //           borderRadius: BorderRadius.circular(8)),
          //       child: const Icon(Icons.chat, size: 16,
          //           color: Color(0xFF25D366))),
          // )),
          // const SizedBox(width: 4),
          // More
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            onSelected: (v) {
              switch (v) {
                case 'view':   _viewDetails(p); break;
                case 'proofs': _viewProofs(p);  break;
                case 'ticket': _raiseTicket(p); break;
                case 'delete': _delete(p);      break;
              }
            },
            itemBuilder: (_) => [
              _menuItem('view',   Icons.visibility_outlined,
                  _blue,   'View Details'),
              if (p['hasProofs'] == true)
                _menuItem('proofs', Icons.attach_file,
                    _green,  'View Proofs'),
              _menuItem('ticket', Icons.confirmation_number_outlined,
                  _orange, 'Raise Ticket'),
              const PopupMenuDivider(),
              _menuItem('delete', Icons.delete_outline,
                  _red, 'Delete', textColor: _red),
            ],
          ),
        ]))),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color iconColor,
      String label, {Color? textColor}) {
    return PopupMenuItem(value: value, child: ListTile(
      leading: Icon(icon, size: 17, color: iconColor),
      title: Text(label, style: TextStyle(color: textColor, fontSize: 13)),
      contentPadding: EdgeInsets.zero, dense: true,
    ));
  }

  // ── PAGINATION ────────────────────────────────────────────────────────────

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
              'Showing ${((_currentPage - 1) * _pageSize + 1).clamp(0, _grandTotal)}'
              '–${(_currentPage * _pageSize).clamp(0, _grandTotal)} of $_grandTotal',
              style: TextStyle(fontSize: 13, color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(icon: Icons.chevron_left, enabled: _currentPage > 1,
                  onTap: () {
                    setState(() => _currentPage--);
                    _applyFiltersAndPaginate();
                  }),
              const SizedBox(width: 4),
              if (pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text('…',
                          style: TextStyle(color: Colors.grey[400]))),
              ],
              ...pages.map((p) => _pageNumBtn(p)),
              if (pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text('…',
                          style: TextStyle(color: Colors.grey[400]))),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(icon: Icons.chevron_right,
                  enabled: _currentPage < _totalPages,
                  onTap: () {
                    setState(() => _currentPage++);
                    _applyFiltersAndPaginate();
                  }),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _currentPage == page;
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          setState(() => _currentPage = page);
          _applyFiltersAndPaginate();
        }
      },
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

  Widget _pageNavBtn({required IconData icon, required bool enabled,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon, size: 18,
            color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ── EMPTY / ERROR ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: _navy.withOpacity(0.06),
                shape: BoxShape.circle),
            child: Icon(Icons.payments_outlined, size: 64,
                color: _navy.withOpacity(0.4))),
        const SizedBox(height: 20),
        const Text('No Payments Found', style: TextStyle(fontSize: 20,
            fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
        const SizedBox(height: 8),
        Text(_hasAnyFilter
            ? 'Try adjusting your filters'
            : 'Record your first payment',
            style: TextStyle(fontSize: 14, color: Colors.grey[500])),
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
        Container(padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
            child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
        const SizedBox(height: 20),
        const Text('Failed to Load Payments',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(_errorMessage ?? 'Unknown error',
                style: TextStyle(color: Colors.grey[500]),
                textAlign: TextAlign.center)),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry',
              style: TextStyle(fontWeight: FontWeight.w600)),
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

  String _fmtNum(num v) => NumberFormat('#,##0.00').format(v.toDouble());
  String _fmtD(DateTime d) => DateFormat('dd/MM/yy').format(d);
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final Map<String, dynamic> payment;
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
  bool   _loading   = true;
  bool   _assigning = false;
  String _priority  = 'Medium';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

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
        (e['email']       ?? '').toLowerCase().contains(q) ||
        (e['role']        ?? '').toLowerCase().contains(q)
      ).toList();
    });
  }

  String _buildMessage() {
    final p      = widget.payment;
    final amount = ((p['amount'] ?? 0.0) as num).toStringAsFixed(2);
    return 'Payment Received "#${p['paymentNumber'] ?? ''}" '
        'for customer "${p['customerName'] ?? ''}" requires attention.\n\n'
        'Payment Details:\n'
        '• Date      : ${p['date'] ?? ''}\n'
        '• Mode      : ${p['mode'] ?? ''}\n'
        '• Amount    : ₹$amount\n'
        '• Reference : ${p['referenceNumber'] ?? '-'}\n'
        '• Invoice # : ${p['invoiceNumber'] ?? '-'}\n'
        '• Status    : ${p['status'] ?? 'paid'}\n\n'
        'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    'Payment Received: ${widget.payment['paymentNumber']} '
                    '— ${widget.payment['customerName']}',
        message:    _buildMessage(),
        priority:   _priority,
        timeline:   1440,
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised(
            'Ticket assigned to ${_selectedEmp!['name_parson']}');
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
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.confirmation_number_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Payment: ${widget.payment['paymentNumber'] ?? ''}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8),
                        fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ])),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Body
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Auto-generated message', style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFDDE3EE))),
                child: Text(_buildMessage(), style: TextStyle(
                    fontSize: 12, color: Colors.grey[700], height: 1.5)),
              ),
              const SizedBox(height: 20),

              const Text('Priority', style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Row(children: ['Low', 'Medium', 'High'].map((pr) {
                final isSel = _priority == pr;
                final color = pr == 'High' ? _red
                    : pr == 'Medium' ? _orange : _green;
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
                        border: Border.all(
                            color: isSel ? color : Colors.grey[300]!),
                        boxShadow: isSel ? [BoxShadow(
                            color: color.withOpacity(0.3), blurRadius: 8,
                            offset: const Offset(0, 3))] : [],
                      ),
                      child: Center(child: Text(pr, style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : Colors.grey[700]))),
                    ),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 20),

              const Text('Assign To', style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search employees…',
                  prefixIcon: Icon(Icons.search, size: 18,
                      color: Colors.grey[400]),
                  filled: true, fillColor: const Color(0xFFF7F9FC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: _navy, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),

              _loading
                  ? const SizedBox(height: 120, child: Center(
                      child: CircularProgressIndicator(color: _navy)))
                  : _filtered.isEmpty
                      ? Container(height: 80, alignment: Alignment.center,
                          child: Text('No employees found',
                              style: TextStyle(color: Colors.grey[500])))
                      : Container(
                          constraints:
                              const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFFDDE3EE)),
                              borderRadius: BorderRadius.circular(10)),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: Color(0xFFEEF2F7)),
                            itemBuilder: (_, i) {
                              final emp   = _filtered[i];
                              final isSel =
                                  _selectedEmp?['_id'] == emp['_id'];
                              return InkWell(
                                onTap: () => setState(() =>
                                    _selectedEmp = isSel ? null : emp),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  color: isSel
                                      ? _navy.withOpacity(0.06)
                                      : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: isSel
                                          ? _navy
                                          : _navy.withOpacity(0.10),
                                      child: Text(
                                          (emp['name_parson'] ??
                                              'U')[0].toUpperCase(),
                                          style: TextStyle(
                                              color: isSel
                                                  ? Colors.white
                                                  : _navy,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(emp['name_parson'] ?? 'Unknown',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      if (emp['email'] != null)
                                        Text(emp['email'],
                                            style: TextStyle(fontSize: 11,
                                                color: Colors.grey[600]),
                                            overflow:
                                                TextOverflow.ellipsis),
                                      if (emp['role'] != null)
                                        Container(
                                          margin: const EdgeInsets.only(
                                              top: 3),
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2),
                                          decoration: BoxDecoration(
                                              color: _navy.withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(4)),
                                          child: Text(
                                              emp['role']
                                                  .toString()
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color: _navy)),
                                        ),
                                    ])),
                                    if (isSel)
                                      const Icon(Icons.check_circle,
                                          color: _navy, size: 20),
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
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed:
                    (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white,
                  disabledBackgroundColor: _navy.withOpacity(0.4),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _assigning
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        _selectedEmp != null
                            ? 'Assign to '
                              '${_selectedEmp!['name_parson'] ?? ''}'
                            : 'Select Employee',
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
//  PAYMENT DETAIL DIALOG
// =============================================================================

class _PaymentDetailDialog extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentDetailDialog({required this.payment});

  @override
  Widget build(BuildContext context) {
    final amount = ((payment['amount'] ?? 0.0) as num).toStringAsFixed(2);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.payments_outlined,
                    color: _green, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Payment #${payment['paymentNumber'] ?? ''}',
                    style: const TextStyle(fontSize: 18,
                        fontWeight: FontWeight.bold)),
                Text(payment['date'] ?? '',
                    style: TextStyle(fontSize: 13,
                        color: Colors.grey[600])),
              ])),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    shape: const CircleBorder()),
              ),
            ]),
            const Divider(height: 24),
            _row('Customer',  payment['customerName']    ?? ''),
            _row('Amount',    '₹$amount', bold: true, color: _green),
            _row('Date',      payment['date']            ?? ''),
            _row('Mode',      payment['mode']            ?? ''),
            _row('Reference', payment['referenceNumber'] ?? '-'),
            _row('Invoice #', payment['invoiceNumber']   ?? '-'),
            _row('Status',
                (payment['status'] ?? 'paid').toString().toUpperCase()),
            if (payment['hasProofs'] == true)
              _row('Proofs',
                  '${payment['proofsCount'] ?? 0} file(s) attached'),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 100,
            child: Text('$label:', style: TextStyle(
                fontSize: 13, color: Colors.grey[600]))),
        Expanded(child: Text(value, style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          color: color ?? const Color(0xFF2C3E50),
        ))),
      ]),
    );
  }
}