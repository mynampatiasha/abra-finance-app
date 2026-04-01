// ============================================================================
// RECURRING EXPENSES LIST PAGE
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat cards,
//   dark navy table, ellipsis pagination, drag-to-scroll)
// - Import button  → BulkImportExpensesDialog (template download + upload +
//   row validation + createRecurringExpense per row)
// - Export button  → Excel export
// - Raise Ticket   → top bar + each row PopupMenu → overlay card with
//                    employee search + assign + auto message
// - Share button   → share_plus (web + mobile)
// - WhatsApp       → live vendor phone lookup via BillingVendorsService
// - View Process   → Lifecycle Dialog (preserved from original)
// - Advanced Date Filter Dialog (preserved from original)
// ============================================================================
// File: lib/screens/expenses/recurring_expenses_list_page.dart
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
import '../../../../core/services/recurring_expense_service.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_recurring_expense.dart';
import 'recurring_expense_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';


// ─── colour palette (same as recurring_invoices_list_page) ───────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);

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

class RecurringExpensesListPage extends StatefulWidget {
  const RecurringExpensesListPage({Key? key}) : super(key: key);
  @override
  State<RecurringExpensesListPage> createState() => _RecurringExpensesListPageState();
}

class _RecurringExpensesListPageState extends State<RecurringExpensesListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<RecurringExpense> _profiles = [];
  RecurringExpenseStats? _stats;
  bool    _isLoading    = true;
  String? _errorMessage;

  // ── filters ───────────────────────────────────────────────────────────────
  String   _selectedStatus = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  DateTime? _particularDate;
  String    _dateFilterType = 'All';
  bool      _showAdvancedFilters = false;

  final List<String> _statusFilters = ['All', 'ACTIVE', 'PAUSED', 'STOPPED'];

  // ── search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();

  // ── pagination ────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  final int _itemsPerPage = 20;
  List<RecurringExpense> _filtered = [];

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
      final resp = await RecurringExpenseService.getRecurringExpenses(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        fromDate: _fromDate?.toIso8601String(),
        toDate: _toDate?.toIso8601String(),
        limit: 1000,
      );
      final data = resp['data'];
      setState(() {
        _profiles  = data is List ? data.cast<RecurringExpense>() : [];
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await RecurringExpenseService.getStats();
      if (s != null) setState(() => _stats = s);
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
            !p.vendorName.toLowerCase().contains(q)) return false;
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
      _particularDate      = null;
      _dateFilterType      = 'All';
      _currentPage         = 1;
      _showAdvancedFilters = false;
    });
    _applyFilters();
  }

  bool get _hasAnyFilter =>
      _selectedStatus != 'All' || _dateFilterType != 'All' ||
      _fromDate != null || _toDate != null || _searchController.text.isNotEmpty;

  List<RecurringExpense> get _currentPageItems {
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
        MaterialPageRoute(builder: (_) => const NewRecurringExpenseScreen()));
    if (ok == true) _loadAll();
  }

  void _openEdit(RecurringExpense p) async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewRecurringExpenseScreen(recurringExpenseId: p.id)));
    if (ok == true) _loadAll();
  }

  // ── profile actions ───────────────────────────────────────────────────────

  Future<void> _pause(RecurringExpense p) async {
    if (p.status != 'ACTIVE') { _showError('Only active profiles can be paused'); return; }
    final ok = await RecurringExpenseService.pauseRecurringExpense(p.id);
    ok ? _showSuccess('"${p.profileName}" paused') : _showError('Failed to pause');
    if (ok) _loadAll();
  }

  Future<void> _resume(RecurringExpense p) async {
    if (p.status != 'PAUSED') { _showError('Only paused profiles can be resumed'); return; }
    final ok = await RecurringExpenseService.resumeRecurringExpense(p.id);
    ok ? _showSuccess('"${p.profileName}" resumed') : _showError('Failed to resume');
    if (ok) _loadAll();
  }

  Future<void> _stop(RecurringExpense p) async {
    final ok = await _confirmDialog(
      title: 'Stop Profile',
      message: 'Permanently stop "${p.profileName}"? No future expenses will be generated.',
      confirmLabel: 'Stop', confirmColor: _red,
    );
    if (ok != true) return;
    final result = await RecurringExpenseService.stopRecurringExpense(p.id);
    result ? _showSuccess('"${p.profileName}" stopped') : _showError('Failed to stop');
    if (result) _loadAll();
  }

  Future<void> _delete(RecurringExpense p) async {
    final ok = await _confirmDialog(
      title: 'Delete Profile',
      message: 'Delete "${p.profileName}"? This cannot be undone.',
      confirmLabel: 'Delete', confirmColor: _red,
    );
    if (ok != true) return;
    final result = await RecurringExpenseService.deleteRecurringExpense(p.id);
    result ? _showSuccess('Profile deleted') : _showError('Failed to delete');
    if (result) _loadAll();
  }

  Future<void> _generate(RecurringExpense p) async {
    final ok = await _confirmDialog(
      title: 'Generate Expense',
      message: 'Generate a new expense from "${p.profileName}"?',
      confirmLabel: 'Generate', confirmColor: _blue,
    );
    if (ok != true) return;
    final result = await RecurringExpenseService.generateManualExpense(p.id);
    result ? _showSuccess('Expense generated successfully') : _showError('Failed to generate expense');
    if (result) _loadAll();
  }
Future<void> _viewChildExpenses(RecurringExpense p) async {
  try {
    final resp = await RecurringExpenseService.getChildExpenses(p.id);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _navy.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long, color: _navy, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Child Expenses', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(p.profileName, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.normal)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${resp.length} expense(s)',
                style: const TextStyle(color: _blue, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        content: SizedBox(
          width: 650,
          height: 450,
          child: resp.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.receipt_outlined, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text('No expenses generated yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                    const SizedBox(height: 8),
                    Text('Use "Generate Expense" to create one',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  ]),
                )
              : Column(children: [
                  // Header row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1B3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(children: [
                      SizedBox(width: 36),
                      Expanded(flex: 3, child: Text('EXPENSE #', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('DATE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 80, child: Text('STATUS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 90, child: Text('ACTIONS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  // Expense rows
                  Expanded(
                    child: ListView.separated(
                      itemCount: resp.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final exp    = resp[i] as Map<String, dynamic>;
                        final status = exp['status'] ?? 'DRAFT';
                        final color  = status == 'RECORDED'
                            ? _green : status == 'DRAFT'
                            ? const Color(0xFF64748B) : _orange;

                        String dateStr = 'N/A';
                        final rawDate = exp['date'] ?? exp['expenseDate'];
                        if (rawDate != null) {
                          try {
                            dateStr = DateFormat('dd MMM yyyy')
                                .format(DateTime.parse(rawDate.toString()));
                          } catch (_) {}
                        }

                        final amount = (exp['totalAmount'] ?? exp['total'] ?? 0);
                        final expId  = exp['_id']?.toString() ?? '';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: i.isOdd ? Colors.grey[50] : Colors.white,
                          child: Row(children: [
                            // Recurring badge
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: _purple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.repeat, size: 14, color: _purple),
                            ),
                            const SizedBox(width: 8),
                            // Expense number + account
                            Expanded(flex: 3, child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(exp['expenseNumber'] ?? 'N/A',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
                                Text(exp['expenseAccount'] ?? '',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              ],
                            )),
                            // Date
                            Expanded(flex: 2, child: Text(dateStr,
                                style: const TextStyle(fontSize: 13))),
                            // Amount
                            Expanded(flex: 2, child: Text(
                              '₹${(amount is num ? amount.toDouble() : 0.0).toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            )),
                            // Status badge
                            SizedBox(width: 80, child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(status,
                                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 10),
                                  textAlign: TextAlign.center),
                            )),
                            // Action buttons
                            SizedBox(width: 90, child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // View button
                                Tooltip(
                                  message: 'View Expense',
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      // Navigate to expense detail
                                      // Navigator.push(context, MaterialPageRoute(
                                      //   builder: (_) => ExpenseDetailPage(expenseId: expId)));
                                      _showExpenseDetail(exp);
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      width: 30, height: 30,
                                      decoration: BoxDecoration(
                                        color: _blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.visibility_outlined, size: 15, color: _blue),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Download button
                                Tooltip(
                                  message: 'Download PDF',
                                  child: InkWell(
                                    onTap: () => _downloadExpensePdf(expId, exp['expenseNumber'] ?? 'expense'),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      width: 30, height: 30,
                                      decoration: BoxDecoration(
                                        color: _green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.download_outlined, size: 15, color: _green),
                                    ),
                                  ),
                                ),
                              ],
                            )),
                          ]),
                        );
                      },
                    ),
                  ),
                ]),
        ),
        actions: [
          // Export all button
          if (resp.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _exportChildExpenses(resp, p.profileName),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Export All'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: const BorderSide(color: _green),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  } catch (e) {
    _showError('Failed to load child expenses: $e');
  }
}

// Show expense detail inline
void _showExpenseDetail(Map<String, dynamic> exp) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.receipt_long, color: _navy, size: 20),
        const SizedBox(width: 10),
        Text(exp['expenseNumber'] ?? 'Expense Detail',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _detailRow('Expense Account', exp['expenseAccount'] ?? '—'),
          _detailRow('Paid Through',    exp['paidThrough']    ?? '—'),
          _detailRow('Vendor',          exp['vendorName']     ?? exp['vendor'] ?? '—'),
          _detailRow('Amount',          '₹${(exp['amount'] ?? 0).toStringAsFixed(2)}'),
          if ((exp['tax'] ?? 0) > 0)
            _detailRow('Tax',           '₹${(exp['tax'] ?? 0).toStringAsFixed(2)}'),
          if ((exp['gstAmount'] ?? 0) > 0)
            _detailRow('GST Amount',    '₹${(exp['gstAmount'] ?? 0).toStringAsFixed(2)}'),
          const Divider(height: 20),
          _detailRow('Total Amount',    '₹${(exp['totalAmount'] ?? exp['total'] ?? 0).toStringAsFixed(2)}', bold: true),
          _detailRow('Status',          exp['status'] ?? '—'),
          if (exp['notes'] != null && exp['notes'].toString().isNotEmpty)
            _detailRow('Notes',         exp['notes'].toString()),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}

Widget _detailRow(String label, String value, {bool bold = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Text(value, style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: bold ? _navy : const Color(0xFF2C3E50),
        )),
      ],
    ),
  );
}

// Download expense PDF
Future<void> _downloadExpensePdf(String expenseId, String expenseNumber) async {
  if (expenseId.isEmpty) {
    _showError('Expense ID not available');
    return;
  }
  try {
    _showSuccess('Preparing PDF...');
    // Use the same pattern as invoice PDF download with token
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final url   = '${ApiConfig.baseUrl}/api/finance/expenses/$expenseId/pdf?token=$token';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open PDF');
    }
  } catch (e) {
    _showError('Failed to download PDF: $e');
  }
}

// Export child expenses to Excel
Future<void> _exportChildExpenses(List<dynamic> expenses, String profileName) async {
  try {
    final rows = <List<dynamic>>[
      ['Expense #', 'Date', 'Expense Account', 'Paid Through', 'Vendor', 'Amount', 'Tax', 'GST', 'Total', 'Status'],
      ...expenses.map((exp) {
        String dateStr = 'N/A';
        final rawDate = exp['date'] ?? exp['expenseDate'];
        if (rawDate != null) {
          try { dateStr = DateFormat('dd/MM/yyyy').format(DateTime.parse(rawDate.toString())); } catch (_) {}
        }
        return [
          exp['expenseNumber'] ?? '',
          dateStr,
          exp['expenseAccount'] ?? '',
          exp['paidThrough'] ?? '',
          exp['vendorName'] ?? exp['vendor'] ?? '',
          (exp['amount'] ?? 0).toString(),
          (exp['tax'] ?? 0).toString(),
          (exp['gstAmount'] ?? 0).toString(),
          (exp['totalAmount'] ?? exp['total'] ?? 0).toString(),
          exp['status'] ?? '',
        ];
      }),
    ];
    await ExportHelper.exportToExcel(
      data: rows,
      filename: 'child_expenses_${profileName.replaceAll(' ', '_')}',
    );
    _showSuccess('✅ Exported ${expenses.length} expenses');
  } catch (e) {
    _showError('Export failed: $e');
  }
}

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _shareProfile(RecurringExpense p) async {
    final text = _buildShareText(p);
    try {
      await Share.share(text, subject: 'Recurring Expense: ${p.profileName}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  String _buildShareText(RecurringExpense p) {
    final total = p.amount + p.tax;
    return 'Recurring Expense Profile\n'
        '─────────────────────────\n'
        'Profile : ${p.profileName}\n'
        'Vendor  : ${p.vendorName}\n'
        'Account : ${p.expenseAccount}\n'
        'Freq    : Every ${p.repeatEvery} ${p.repeatUnit}(s)\n'
        'Amount  : ₹${total.toStringAsFixed(2)}\n'
        'Status  : ${p.status}\n'
        'Next    : ${DateFormat('dd MMM yyyy').format(p.nextExpenseDate)}\n'
        'Generated: ${p.totalExpensesGenerated} expense(s)\n'
        '${p.isBillable == true ? 'Billable: Yes' : 'Billable: No'}';
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────

  Future<void> _whatsApp(RecurringExpense p) async {
    try {
      _showSuccess('Looking up vendor phone…');
      final resp = await BillingVendorsService.getVendorById(p.vendorId);
      final vendor = resp['data'];
      final phone = (vendor?['phoneNumber'] ?? vendor?['phone'] ?? vendor?['primaryPhone'] ?? '').toString().trim();
      if (phone.isEmpty) {
        _showError('Vendor phone not available. Please update the vendor profile.');
        return;
      }
      final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
      final total   = p.amount + p.tax;
      final msg = Uri.encodeComponent(
        'Hello ${p.vendorName},\n\n'
        'This is regarding your recurring expense profile "${p.profileName}".\n\n'
        'Amount   : ₹${total.toStringAsFixed(2)}\n'
        'Frequency: Every ${p.repeatEvery} ${p.repeatUnit}(s)\n'
        'Status   : ${p.status}\n'
        'Next Date: ${DateFormat('dd MMM yyyy').format(p.nextExpenseDate)}\n\n'
        'Please contact us for any queries. Thank you!',
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

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket([RecurringExpense? profile]) {
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
        title: const Text('Export Recurring Expenses', style: TextStyle(fontWeight: FontWeight.bold)),
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
        ['Profile Name','Vendor','Account','Paid Through','Status','Repeat Every','Repeat Unit',
         'Start Date','End Date','Next Expense','Generated','Mode','Amount','Tax','Total','Last Generated'],
        ..._filtered.map((p) {
          final total = p.amount + p.tax;
          return [
            p.profileName, p.vendorName, p.expenseAccount, p.paidThrough, p.status,
            p.repeatEvery.toString(), p.repeatUnit,
            DateFormat('dd/MM/yyyy').format(p.startDate),
            p.endDate != null ? DateFormat('dd/MM/yyyy').format(p.endDate!) : 'Never',
            DateFormat('dd/MM/yyyy').format(p.nextExpenseDate),
            p.totalExpensesGenerated.toString(), p.expenseCreationMode,
            p.amount.toStringAsFixed(2), p.tax.toStringAsFixed(2), total.toStringAsFixed(2),
            p.lastGeneratedDate != null ? DateFormat('dd/MM/yyyy').format(p.lastGeneratedDate!) : 'Not yet',
          ];
        }),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'recurring_expenses');
      _showSuccess('✅ Excel downloaded (${_filtered.length} profiles)');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => BulkImportExpensesDialog(onImportComplete: _loadAll),
    );
  }

  // ── view process dialog (preserved from original) ─────────────────────────

  void _showLifecycleDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 800,
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Life cycle of a Recurring Expense',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 32),
            _buildLifecycleDiagram(),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.info_outline, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Text('How it Works:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue[900])),
                ]),
                const SizedBox(height: 16),
                _buildExplanationPoint('1. Create Recurring Expense', 'Set up a recurring profile with vendor, amount, and frequency'),
                _buildExplanationPoint('2. Billable or Non-Billable', 'Choose if this expense can be invoiced to customers'),
                _buildExplanationPoint('3. Automatic Generation', 'System automatically creates expenses based on schedule'),
                _buildExplanationPoint('4. Invoice & Reimbursement', 'Billable expenses can be converted to invoices and reimbursed'),
              ]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16)),
              child: const Text('Got it!'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildLifecycleDiagram() {
    return SizedBox(height: 200, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _buildLifecycleStep(icon: Icons.add_circle_outline, label: 'CREATE RECURRING\nEXPENSE', color: _blue),
      _buildArrow(),
      SizedBox(width: 350, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(children: [
          _buildLifecycleStep(icon: Icons.receipt_long, label: 'BILLABLE', color: _green, compact: true),
          _buildSmallArrow(),
          _buildLifecycleStep(icon: Icons.description, label: 'CONVERT TO\nINVOICE', color: _blue, compact: true),
          _buildSmallArrow(),
          _buildLifecycleStep(icon: Icons.attach_money, label: 'GET\nREIMBURSED', color: _green, compact: true),
        ]),
        const SizedBox(height: 16),
        _buildLifecycleStep(icon: Icons.cancel_outlined, label: 'NON-BILLABLE', color: _red, compact: true),
      ])),
    ]));
  }

  Widget _buildLifecycleStep({required IconData icon, required String label, required Color color, bool compact = false}) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(color: color.withOpacity(0.1), border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: compact ? 24 : 32),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: compact ? 10 : 12, fontWeight: FontWeight.bold, color: color, height: 1.2)),
      ]),
    );
  }

  Widget _buildArrow() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(children: [Container(width: 40, height: 2, color: Colors.grey[400]), Icon(Icons.arrow_forward, color: Colors.grey[600], size: 24)]),
  );

  Widget _buildSmallArrow() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(children: [Container(width: 20, height: 2, color: Colors.grey[400]), Icon(Icons.arrow_forward, color: Colors.grey[600], size: 16)]),
  );

  Widget _buildExplanationPoint(String title, String description) {
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(margin: const EdgeInsets.only(top: 4), width: 6, height: 6, decoration: BoxDecoration(color: Colors.blue[700], shape: BoxShape.circle)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text(description, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      ])),
    ]));
  }

  // ── advanced date filter dialog (preserved from original) ─────────────────

  void _showFilterDialog() {
    DateTime? tempFromDate = _fromDate;
    DateTime? tempToDate   = _toDate;
    DateTime? tempParticular = _particularDate;
    String tempType = _dateFilterType;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Filter by Date'),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Filter Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
              child: DropdownButton<String>(
                value: tempType, isExpanded: true, underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All Dates')),
                  DropdownMenuItem(value: 'Within Date Range', child: Text('Within Date Range')),
                  DropdownMenuItem(value: 'Particular Date', child: Text('Particular Date')),
                  DropdownMenuItem(value: 'Today', child: Text('Today')),
                  DropdownMenuItem(value: 'This Week', child: Text('This Week')),
                  DropdownMenuItem(value: 'This Month', child: Text('This Month')),
                  DropdownMenuItem(value: 'Last Month', child: Text('Last Month')),
                  DropdownMenuItem(value: 'This Year', child: Text('This Year')),
                ],
                onChanged: (v) {
                  setDs(() {
                    tempType = v ?? 'All';
                    final now = DateTime.now();
                    if (v == 'Today')      { tempFromDate = now; tempToDate = now; }
                    else if (v == 'This Week') { tempFromDate = now.subtract(Duration(days: now.weekday - 1)); tempToDate = now.add(Duration(days: 7 - now.weekday)); }
                    else if (v == 'This Month') { tempFromDate = DateTime(now.year, now.month, 1); tempToDate = DateTime(now.year, now.month + 1, 0); }
                    else if (v == 'Last Month') { tempFromDate = DateTime(now.year, now.month - 1, 1); tempToDate = DateTime(now.year, now.month, 0); }
                    else if (v == 'This Year')  { tempFromDate = DateTime(now.year, 1, 1); tempToDate = DateTime(now.year, 12, 31); }
                    else if (v == 'All') { tempFromDate = null; tempToDate = null; tempParticular = null; }
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            if (tempType == 'Within Date Range') ...[
              const Text('From Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              _datePicker(tempFromDate, 'Select from date', (d) => setDs(() => tempFromDate = d), ctx),
              const SizedBox(height: 20),
              const Text('To Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              _datePicker(tempToDate, 'Select to date', (d) => setDs(() => tempToDate = d), ctx),
            ],
            if (tempType == 'Particular Date') ...[
              const Text('Select Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              _datePicker(tempParticular, 'Select date', (d) => setDs(() => tempParticular = d), ctx),
            ],
            if (tempType != 'All' && tempType != 'Within Date Range' && tempType != 'Particular Date') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue[200]!)),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    tempFromDate != null && tempToDate != null
                        ? 'From ${DateFormat('dd/MM/yyyy').format(tempFromDate!)} to ${DateFormat('dd/MM/yyyy').format(tempToDate!)}'
                        : 'Date range will be applied automatically',
                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                  )),
                ]),
              ),
            ],
          ]))),
          actions: [
            TextButton(
              onPressed: () => setDs(() { tempFromDate = null; tempToDate = null; tempParticular = null; tempType = 'All'; }),
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _dateFilterType = tempType;
                  _fromDate = tempFromDate;
                  _toDate = tempToDate;
                  _particularDate = tempParticular;
                  _currentPage = 1;
                });
                Navigator.pop(ctx);
                _loadProfiles();
              },
              style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
              child: const Text('Apply Filter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _datePicker(DateTime? value, String hint, ValueChanged<DateTime> onPicked, BuildContext ctx) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(context: ctx, initialDate: value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (d != null) onPicked(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.calendar_today, size: 20),
          const SizedBox(width: 12),
          Text(value != null ? DateFormat('dd/MM/yyyy').format(value) : hint,
              style: TextStyle(color: value != null ? Colors.black : Colors.grey[600])),
        ]),
      ),
    );
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
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
                child: Text(confirmLabel)),
          ],
        ),
      );

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Recurring Expenses'),
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
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: () => _showFilterDialog()),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: () => _showFilterDialog()),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; _dateFilterType = 'All'; }); _applyFilters(); }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    Stack(children: [
      _iconBtn(Icons.filter_list, _showFilterDialog, tooltip: 'Date Filters',
          color: _hasAnyFilter && _dateFilterType != 'All' ? _navy : const Color(0xFF7F8C8D),
          bg: _hasAnyFilter && _dateFilterType != 'All' ? _navy.withOpacity(0.08) : const Color(0xFFF1F1F1)),
      if (_hasAnyFilter && _dateFilterType != 'All')
        Positioned(right: 6, top: 6, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle))),
    ]),
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const Spacer(),
    _outlinedBtn('View Process', Icons.info_outline, _blue, _showLifecycleDialog),
    const SizedBox(width: 8),
    _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _filtered.isEmpty ? null : _handleExport),
    const SizedBox(width: 8),
    _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 180),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From', isActive: _fromDate != null, onTap: _showFilterDialog),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To', isActive: _toDate != null, onTap: _showFilterDialog),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; _dateFilterType = 'All'; }); _applyFilters(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.filter_list, _showFilterDialog, tooltip: 'Filters'),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _outlinedBtn('View Process', Icons.info_outline, _blue, _showLifecycleDialog),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _filtered.isEmpty ? null : _handleExport),
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
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: _showFilterDialog),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: _showFilterDialog),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; _dateFilterType = 'All'; }); _applyFilters(); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.filter_list, _showFilterDialog),
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh),
      const SizedBox(width: 6),
      _compactBtn('Process', _blue, _showLifecycleDialog),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _filtered.isEmpty ? null : _handleExport),
      const SizedBox(width: 6),
      _compactBtn('Ticket', _orange, () => _raiseTicket()),
    ])),
  ]);

  // ── advanced filters bar ──────────────────────────────────────────────────

  Widget _buildAdvancedFiltersBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF7F9FC),
      child: Row(children: [
        const Text('Filters:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(width: 12),
        SizedBox(width: 200, child: Container(
          height: 40, padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedStatus, isExpanded: true, icon: const Icon(Icons.expand_more, size: 18),
              style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50)),
              items: _statusFilters.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) { if (v != null) { setState(() { _selectedStatus = v; _currentPage = 1; }); _applyFilters(); } },
            ),
          ),
        )),
        const Spacer(),
        if (_hasAnyFilter) TextButton.icon(onPressed: _clearFilters, icon: const Icon(Icons.clear, size: 16), label: const Text('Clear All'), style: TextButton.styleFrom(foregroundColor: _red)),
      ]),
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
        hintText: 'Search profiles, vendors…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchController.clear(); setState(() => _currentPage = 1); _applyFilters(); })
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

  Widget _outlinedBtn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color, side: BorderSide(color: color),
        minimumSize: const Size(0, 42),
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
    final total     = _stats?.totalProfiles ?? _profiles.length;
    final active    = _stats?.activeProfiles ?? _profiles.where((p) => p.status == 'ACTIVE').length;
    final paused    = _stats?.pausedProfiles ?? _profiles.where((p) => p.status == 'PAUSED').length;
    final stopped   = _stats?.stoppedProfiles ?? _profiles.where((p) => p.status == 'STOPPED').length;
    final generated = _stats?.totalExpensesGenerated ?? _profiles.fold<int>(0, (s, p) => s + p.totalExpensesGenerated);
    final totalAmt  = _stats?.totalAmountGenerated ?? _profiles.fold<double>(0, (s, p) => s + p.amount + p.tax);

    final cards = [
      _StatCardData(label: 'Total Profiles',   value: total.toString(),  icon: Icons.repeat_rounded,         color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Active',           value: active.toString(), icon: Icons.check_circle_outline,   color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Paused',           value: paused.toString(), icon: Icons.pause_circle_outline,   color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Stopped',          value: stopped.toString(),icon: Icons.stop_circle_outlined,   color: _red,    gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'Total Generated',  value: generated.toString(), icon: Icons.receipt_outlined,    color: _purple, gradientColors: const [Color(0xFFBB8FCE), Color(0xFF9B59B6)]),
      _StatCardData(label: 'Total Amount',     value: '₹${totalAmt.toStringAsFixed(0)}', icon: Icons.currency_rupee_rounded, color: _teal, gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)]),
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
              Text(d.value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: d.color), overflow: TextOverflow.ellipsis),
            ])
          : Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: Icon(d.icon, color: Colors.white, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(d.value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: d.color), overflow: TextOverflow.ellipsis),
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
                  headingRowHeight: 52, dataRowMinHeight: 62, dataRowMaxHeight: 78,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 16, horizontalMargin: 16,
                  columns: [
                    DataColumn(label: SizedBox(width: 36, child: Checkbox(value: _selectAll, fillColor: WidgetStateProperty.all(Colors.white), checkColor: const Color(0xFF0D1B3E), onChanged: _toggleSelectAll))),
                    const DataColumn(label: SizedBox(width: 190, child: Text('PROFILE NAME'))),
                    const DataColumn(label: SizedBox(width: 160, child: Text('VENDOR'))),
                    const DataColumn(label: SizedBox(width: 130, child: Text('FREQUENCY'))),
                    const DataColumn(label: SizedBox(width: 120, child: Text('NEXT EXPENSE'))),
                    const DataColumn(label: SizedBox(width: 100, child: Text('STATUS'))),
                    const DataColumn(label: SizedBox(width: 90,  child: Text('GENERATED'))),
                    const DataColumn(label: SizedBox(width: 110, child: Text('AMOUNT'))),
                    const DataColumn(label: SizedBox(width: 140, child: Text('ACTIONS'))),
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

  DataRow _buildRow(int index, RecurringExpense p) {
    final isSel  = _selectedRows.contains(index);
    final total  = p.amount + p.tax;

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
        DataCell(SizedBox(width: 190, child: InkWell(
          onTap: () => _openEdit(p),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(p.profileName, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
            const SizedBox(height: 3),
            Row(children: [
              Text(p.expenseCreationMode == 'auto_create' ? '🚀 Auto-Create' : '📝 Draft',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              if (p.isBillable == true) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: _green.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Billable', style: TextStyle(fontSize: 10, color: _green, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ]),
        ))),

        // Vendor
        DataCell(SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(p.vendorName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(p.expenseAccount, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]))),

        // Frequency
        DataCell(SizedBox(width: 130, child: Text('Every ${p.repeatEvery} ${p.repeatUnit}(s)', style: const TextStyle(fontSize: 13)))),

        // Next expense
        DataCell(SizedBox(width: 120, child: Text(DateFormat('dd MMM yyyy').format(p.nextExpenseDate),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))),

        // Status
        DataCell(SizedBox(width: 100, child: _statusBadge(p.status))),

        // Generated (clickable)
        DataCell(SizedBox(width: 90, child: InkWell(
          onTap: () => _viewChildExpenses(p),
          child: Text(p.totalExpensesGenerated.toString(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _blue, decoration: TextDecoration.underline),
              textAlign: TextAlign.center),
        ))),

        // Amount
        DataCell(SizedBox(width: 110, child: Text('₹${total.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right))),

        // Actions
        DataCell(SizedBox(width: 140, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _shareProfile(p),
            child: Container(width: 30, height: 30,
                decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.share, size: 15, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          // Tooltip(message: 'WhatsApp', child: InkWell(
          //   onTap: () => _whatsApp(p),
          //   child: Container(width: 30, height: 30,
          //       decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
          //       child: const Icon(Icons.chat, size: 15, color: Color(0xFF25D366))),
          // )),
          // const SizedBox(width: 4),
          // More
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('view',          Icons.visibility,                  const Color(0xFF3D8EFF), 'View Details'),
              _menuItem('edit',          Icons.edit_outlined,               _blue,   'Edit'),
              _menuItem('generate',      Icons.add_circle_outline,          _green,  'Generate Expense'),
              _menuItem('view_expenses', Icons.list_alt_outlined,           _navy,   'View Child Expenses'),
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
                case 'view':          Navigator.push(context, MaterialPageRoute(builder: (_) => RecurringExpenseDetailPage(expense: p))); break;
                case 'edit':          _openEdit(p);             break;
                case 'generate':      _generate(p);             break;
                case 'view_expenses': _viewChildExpenses(p);    break;
                case 'ticket':        _raiseTicket(p);          break;
                case 'pause':         _pause(p);                break;
                case 'resume':        _resume(p);               break;
                case 'stop':          _stop(p);                 break;
                case 'delete':        _delete(p);               break;
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
      const Text('No Recurring Expense Profiles Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text(_hasAnyFilter ? 'Try adjusting your filters' : 'Create your first recurring expense profile', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
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
  final RecurringExpense? profile;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.profile, required this.onTicketRaised, required this.onError});

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
        _employees    = List<Map<String, dynamic>>.from(resp['data']);
        _filteredEmps = _employees;
        _loading      = false;
      });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredEmps = q.isEmpty ? _employees : _employees.where((e) {
        return (e['name_parson'] ?? '').toLowerCase().contains(q) ||
               (e['email'] ?? '').toLowerCase().contains(q) ||
               (e['role']  ?? '').toLowerCase().contains(q);
      }).toList();
    });
  }

  String _buildTicketMessage() {
    if (widget.profile == null) return 'A recurring expense ticket has been raised and requires your attention.';
    final p = widget.profile!;
    final total = p.amount + p.tax;
    return 'Recurring Expense Profile "${p.profileName}" for vendor "${p.vendorName}" requires attention.\n\n'
           'Profile Details:\n'
           '• Frequency  : Every ${p.repeatEvery} ${p.repeatUnit}(s)\n'
           '• Amount     : ₹${total.toStringAsFixed(2)}\n'
           '• Status     : ${p.status}\n'
           '• Next Date  : ${DateFormat('dd MMM yyyy').format(p.nextExpenseDate)}\n'
           '• Generated  : ${p.totalExpensesGenerated} expense(s)\n'
           '• Account    : ${p.expenseAccount}\n'
           '${p.isBillable == true ? '• Billable   : Yes\n' : ''}'
           '\nPlease review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: widget.profile != null
            ? 'Recurring Expense: ${widget.profile!.profileName}'
            : 'Recurring Expenses — Action Required',
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
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (widget.profile != null)
                  Text('Profile: ${widget.profile!.profileName}', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),

          // Body
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.profile != null) ...[
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                  child: Text(_buildTicketMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5))),
              const SizedBox(height: 20),
            ],
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
            const SizedBox(height: 8),
            Row(children: ['Low', 'Medium', 'High'].map((pr) {
              final isSel = _priority == pr;
              final color = pr == 'High' ? _red : pr == 'Medium' ? _orange : _green;
              return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: InkWell(
                onTap: () => setState(() => _priority = pr),
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: isSel ? color : Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: isSel ? color : Colors.grey[300]!),
                        boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : []),
                    child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700])))),
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
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                child: Row(children: [
                                  CircleAvatar(radius: 18,
                                      backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
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
                        ),
                      ),
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
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, disabledBackgroundColor: _navy.withOpacity(0.4),
                    elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
//  BULK IMPORT EXPENSES DIALOG
// =============================================================================

class BulkImportExpensesDialog extends StatefulWidget {
  final Future<void> Function() onImportComplete;
  const BulkImportExpensesDialog({Key? key, required this.onImportComplete}) : super(key: key);

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
      final data = <List<dynamic>>[
        [
          'Profile Name*',
          'Vendor ID*',
          'Vendor Name*',
          'Vendor Email',
          'Expense Account*',
          'Paid Through*',
          'Amount*',
          'Tax (number, default 0)',
          'GST Rate (number, default 0)',
          'Repeat Every* (number)',
          'Repeat Unit* (day/week/month/year)',
          'Start Date* (dd/MM/yyyy)',
          'End Date (dd/MM/yyyy or blank)',
          'Max Occurrences (number or blank)',
          'Creation Mode* (auto_create/save_as_draft)',
          'Is Billable (true/false)',
          'Notes',
        ],
        [
          'Monthly Office Rent',
          '64f2a1b3e4c5d6789012ef01',
          'ABC Landlords',
          'rent@abc.com',
          'Rent',
          'HDFC Bank',
          '50000',
          '0',
          '0',
          '1',
          'month',
          '01/01/2025',
          '',
          '',
          'auto_create',
          'false',
          'Office rent payment',
        ],
        [
          'INSTRUCTIONS:',
          '* = required fields',
          'Vendor ID must be a valid MongoDB ObjectId',
          'Repeat Unit: day / week / month / year',
          'Creation Mode: auto_create or save_as_draft',
          'Dates in dd/MM/yyyy format',
          'Delete this row before uploading',
        ],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'recurring_expenses_import_template');
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

      if (rows.length < 2) throw Exception('File must contain header + at least one data row');

      final List<Map<String, dynamic>> valid  = [];
      final List<String>               errors = [];

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty || _sv(row, 0).isEmpty) continue;
        if (_sv(row, 0).toUpperCase().startsWith('INSTRUCTION')) continue;

        final rowErrors = <String>[];
        final profileName  = _sv(row, 0);
        final vendorId     = _sv(row, 1);
        final vendorName   = _sv(row, 2);
        final vendorEmail  = _sv(row, 3);
        final account      = _sv(row, 4);
        final paidThrough  = _sv(row, 5);
        final amount       = double.tryParse(_sv(row, 6)) ?? 0;
        final tax          = double.tryParse(_sv(row, 7, '0')) ?? 0;
        final gstRate      = double.tryParse(_sv(row, 8, '0')) ?? 0;
        final repeatEvery  = int.tryParse(_sv(row, 9)) ?? 0;
        final repeatUnit   = _sv(row, 10).toLowerCase();
        final startDateStr = _sv(row, 11);
        final endDateStr   = _sv(row, 12);
        final maxOccStr    = _sv(row, 13);
        final mode         = _sv(row, 14, 'auto_create');
        final billable     = _sv(row, 15, 'false').toLowerCase() == 'true';
        final notes        = _sv(row, 16);

        if (profileName.isEmpty)  rowErrors.add('Profile Name required');
        if (vendorId.isEmpty)     rowErrors.add('Vendor ID required');
        if (vendorName.isEmpty)   rowErrors.add('Vendor Name required');
        if (account.isEmpty)      rowErrors.add('Expense Account required');
        if (paidThrough.isEmpty)  rowErrors.add('Paid Through required');
        if (amount <= 0)          rowErrors.add('Amount must be > 0');
        if (repeatEvery <= 0)     rowErrors.add('Repeat Every must be > 0');
        if (!['day','week','month','year'].contains(repeatUnit)) rowErrors.add('Invalid Repeat Unit');
        if (!['auto_create','save_as_draft'].contains(mode))     rowErrors.add('Invalid Creation Mode');

        DateTime? startDate;
        DateTime? endDate;
        try { startDate = DateFormat('dd/MM/yyyy').parse(startDateStr); }
        catch (_) { rowErrors.add('Invalid Start Date (use dd/MM/yyyy)'); }
        if (endDateStr.isNotEmpty) {
          try { endDate = DateFormat('dd/MM/yyyy').parse(endDateStr); } catch (_) { rowErrors.add('Invalid End Date'); }
        }

        if (rowErrors.isNotEmpty) { errors.add('Row ${i + 1}: ${rowErrors.join(', ')}'); continue; }

        final nextDate = _calcNextDate(startDate!, repeatEvery, repeatUnit);

        valid.add({
          'profileName':          profileName,
          'vendorId':             vendorId,
          'vendorName':           vendorName,
          if (vendorEmail.isNotEmpty) 'vendorEmail': vendorEmail,
          'expenseAccount':       account,
          'paidThrough':          paidThrough,
          'amount':               amount,
          'tax':                  tax,
          'gstRate':              gstRate,
          'repeatEvery':          repeatEvery,
          'repeatUnit':           repeatUnit,
          'startDate':            startDate.toIso8601String(),
          if (endDate != null)    'endDate': endDate.toIso8601String(),
          if (maxOccStr.isNotEmpty) 'maxOccurrences': int.tryParse(maxOccStr),
          'nextExpenseDate':      nextDate.toIso8601String(),
          'expenseCreationMode':  mode,
          'isBillable':           billable,
          if (notes.isNotEmpty)   'notes': notes,
          'status':               'ACTIVE',
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
              Container(constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(child: Text(errors.join('\n'), style: const TextStyle(fontSize: 12)))),
            ],
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white), child: const Text('Import')),
          ],
        ),
      );

      if (confirmed != true) { setState(() { _uploading = false; _fileName = null; }); return; }

      int success = 0, failed = 0;
      for (final profile in valid) {
        final ok = await RecurringExpenseService.createRecurringExpense(profile);
        ok ? success++ : failed++;
      }

      setState(() {
        _uploading = false;
        _results = {'success': success, 'failed': failed, 'total': valid.length};
      });

      if (success > 0) { _showSnack('✅ $success profile(s) imported!', _green); await widget.onImportComplete(); }
      if (failed > 0)  _showSnack('⚠ $failed profile(s) failed', _orange);

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
        .split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty)
        .map(_parseCSVLine).toList();
  }

  List<String> _parseCSVLine(String line) {
    final fields = <String>[]; final buf = StringBuffer(); bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') { if (inQuotes && i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; } else { inQuotes = !inQuotes; } }
      else if (ch == ',' && !inQuotes) { fields.add(buf.toString().trim()); buf.clear(); }
      else { buf.write(ch); }
    }
    fields.add(buf.toString().trim()); return fields;
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
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
            const SizedBox(width: 14),
            const Text('Import Recurring Expenses', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 24),
          _importStep(step: '1', color: _blue, icon: Icons.download_rounded, title: 'Download Template',
              subtitle: 'Get the Excel template with all required columns and an example row.',
              buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
              onPressed: _downloading || _uploading ? null : _downloadTemplate),
          const SizedBox(height: 16),
          _importStep(step: '2', color: _green, icon: Icons.upload_rounded, title: 'Upload Filled File',
              subtitle: 'Fill in the template and upload (XLSX / XLS / CSV).',
              buttonLabel: _uploading ? 'Uploading…' : (_fileName != null ? 'Change File' : 'Select File'),
              onPressed: _downloading || _uploading ? null : _uploadFile),
          if (_results != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                Row(children: [const Icon(Icons.check_circle, color: _green, size: 18), const SizedBox(width: 8), Text('Successfully created: ${_results!['success']}')]),
                if ((_results!['failed'] ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  Row(children: [const Icon(Icons.cancel, color: _red, size: 18), const SizedBox(width: 8), Text('Failed: ${_results!['failed']}', style: const TextStyle(color: _red))]),
                ],
              ]),
            ),
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
    final button = ElevatedButton.icon(
      onPressed: onPressed, icon: Icon(icon, size: 16),
      label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, disabledBackgroundColor: color.withOpacity(0.5),
          elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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