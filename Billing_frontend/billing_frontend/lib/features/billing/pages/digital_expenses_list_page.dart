import 'package:abra_finance/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';
import '../../../../core/finance_secure_storage.dart';
import '../../../../core/utils/export_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import '../app_top_bar.dart';
import 'new_digital_expense.dart';
import 'bulk_import_digital_expenses_dialog.dart';
import '../../../../core/permissions_finance.dart';

const Color _navy = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green = Color(0xFF27AE60);
const Color _blue = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red = Color(0xFFE74C3C);

class _StatCardData {
  final String label;
  final String value;
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

class DigitalExpensesListPage extends StatefulWidget {
  const DigitalExpensesListPage({Key? key}) : super(key: key);

  @override
  State<DigitalExpensesListPage> createState() =>
      _DigitalExpensesListPageState();
}

class _DigitalExpensesListPageState extends State<DigitalExpensesListPage> {
  // ── Data ───────────────────────────────────────────────────────────────────
  List<dynamic> _allExpenses = [];
  List<dynamic> _filteredExpenses = [];
  bool _isLoading = true;
  String? _errorMessage;

  // ── Filters ────────────────────────────────────────────────────────────────
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'Pending',
    'Approved',
    'Declined',
    'Response Submitted'
  ];
  DateTime? _fromDate;
  DateTime? _toDate;

  // ── Search ─────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── View mode ──────────────────────────────────────────────────────────────
  bool _isTableView = true;

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  String _currentRole = '';

  @override
  void initState() {
    super.initState();
    _initRoleAndFetch();
  }

  Future<void> _initRoleAndFetch() async {
    _currentRole = await FinanceSecureStorage.getRole() ?? '';
    if (mounted) _fetchExpenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  //  DATA
  // ==========================================================================

  Future<void> _fetchExpenses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      var url = '${ApiConfig.baseUrl}/api/finance/digital-expenses';
      if (_selectedStatus != 'All') {
        url += '?status=$_selectedStatus';
      }

      final uri = Uri.parse(url);
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'x-branch-ids': branchHdr,
        'x-org-ids': orgHdr,
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _allExpenses = data['data'] ?? [];
        _applyFilters();
      } else {
        throw Exception('Failed to load expenses');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredExpenses = _allExpenses.where((exp) {
        // Date Filter
        if (_fromDate != null || _toDate != null) {
          try {
            final expDateStr = exp['date'];
            if (expDateStr != null) {
              final expDate = DateTime.parse(expDateStr);
              if (_fromDate != null && expDate.isBefore(_fromDate!))
                return false;
              if (_toDate != null && expDate.isAfter(_toDate!)) return false;
            }
          } catch (_) {}
        }

        // Status Filter
        if (_selectedStatus != 'All') {
          final expStatus = (exp['status'] ?? 'Pending').toString();
          if (expStatus.toLowerCase() != _selectedStatus.toLowerCase())
            return false;
        }
        // Search Filter
        if (_searchQuery.isNotEmpty) {
          final q = _searchQuery.toLowerCase();
          final category = (exp['expenseCategory'] ?? '').toLowerCase();
          final onAccountOf = (exp['onAccountOf'] ?? '').toLowerCase();
          final paidTo = (exp['amountPaidTo'] ?? '').toLowerCase();
          if (!category.contains(q) &&
              !onAccountOf.contains(q) &&
              !paidTo.contains(q)) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  Future<void> _updateStatus(String id, String status, [String? reason]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/finance/digital-expenses/$id/status');
      final response = await http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
          'x-org-ids': orgHdr,
          'Content-Type': 'application/json'
        },
        body: json.encode({'status': status, 'reason': reason}),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success']) {
        _snackSuccess('Status updated to $status');
        _fetchExpenses();
      } else {
        throw Exception(data['message']);
      }
    } catch (e) {
      _snackError(e.toString());
    }
  }

  Future<void> _deleteExpense(String id) async {
    final canDelete = await FinancePermissions.checkCanDelete(context, 'digital_expenses');
    if (!canDelete) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Voucher',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'Are you sure you want to delete this expense voucher? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      final uri =
          Uri.parse('${ApiConfig.baseUrl}/api/finance/digital-expenses/$id');
      final response = await http.delete(uri, headers: {
        'Authorization': 'Bearer $token',
        'x-branch-ids': branchHdr,
        'x-org-ids': orgHdr,
      });

      if (response.statusCode == 200) {
        _snackSuccess('Expense deleted successfully');
        _fetchExpenses();
      } else {
        throw Exception('Failed to delete expense');
      }
    } catch (e) {
      _snackError(e.toString());
    }
  }

  void _filterByStatus(String status) {
    setState(() {
      _selectedStatus = status;
    });
    _fetchExpenses();
  }

  void _onSearchChanged(String val) {
    _searchQuery = val;
    _applyFilters();
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (_) =>
          BulkImportDigitalExpensesDialog(onImportComplete: _fetchExpenses),
    );
  }

  Future<void> _exportToExcel() async {
    if (_filteredExpenses.isEmpty) {
      _snackError('No expenses to export');
      return;
    }
    try {
      _snackSuccess('Preparing Excel export...');
      List<List<dynamic>> csvData = [
        [
          'Voucher #',
          'Date',
          'Category',
          'Amount',
          'Payment Method',
          'Paid To',
          'On Account Of',
          'Status'
        ],
      ];
      for (var exp in _filteredExpenses) {
        csvData.add([
          exp['voucherNumber'] ?? '-',
          exp['date'] ?? '-',
          exp['expenseCategory'] ?? '-',
          exp['amount'].toString(),
          exp['paymentMethod'] ?? '-',
          exp['amountPaidTo'] ?? '-',
          exp['onAccountOf'] ?? '-',
          exp['status'] ?? 'Pending',
        ]);
      }
      await ExportHelper.exportToExcel(
          data: csvData, filename: 'digital_expenses');
      _snackSuccess('Excel exported successfully');
    } catch (e) {
      _snackError('Failed to export: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Step 1: Show dialog to pick start date + time before sending
  // ---------------------------------------------------------------------------
  Future<void> _showWhatsAppReportDialog() async {
    DateTime startDate = DateTime.now();
    TimeOfDay startTime =
        const TimeOfDay(hour: 0, minute: 0); // midnight = full day default
    final DateTime endDateTime = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)]),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.send, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('WhatsApp Report',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white70, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('Report Range',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF1e3a8a))),
                    const SizedBox(height: 16),

                    // --- Start Date ---
                    const Text('Start Date',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null)
                          setDialogState(() => startDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_rounded,
                                size: 16, color: Color(0xFF1e3a8a)),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('dd MMM yyyy').format(startDate),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // --- Start Time ---
                    const Text('Start Time',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: startTime,
                        );
                        if (picked != null)
                          setDialogState(() => startTime = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 16, color: Color(0xFF1e3a8a)),
                            const SizedBox(width: 10),
                            Text(
                              startTime.format(context),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // --- End Date+Time (read-only = now) ---
                    const Text('End Date & Time',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_clock,
                              size: 16, color: Colors.green[700]),
                          const SizedBox(width: 10),
                          Text(
                            'Now  (${DateFormat('dd MMM yyyy, hh:mm a').format(endDateTime)})',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.green[800]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Build full start DateTime combining picked date + time
                    final startDateTime = DateTime(
                      startDate.year,
                      startDate.month,
                      startDate.day,
                      startTime.hour,
                      startTime.minute,
                    );
                    _sendWhatsAppReport(
                        startDateTime: startDateTime, endDateTime: endDateTime);
                  },
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Send Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366), // WhatsApp green
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2: Updated _sendWhatsAppReport — accepts date range + clean formatting
  // ---------------------------------------------------------------------------
  Future<void> _sendWhatsAppReport(
      {DateTime? startDateTime, DateTime? endDateTime}) async {
    // Filter expenses by date range if provided
    List<dynamic> expensesToReport = _filteredExpenses;

    if (startDateTime != null || endDateTime != null) {
      expensesToReport = _filteredExpenses.where((exp) {
        // Fallback to 'date' if 'createdAt' is inexplicably missing, but 'createdAt' gives us time precision
        final String dateString =
            exp['createdAt']?.toString() ?? exp['date']?.toString() ?? '';
        if (dateString.isEmpty) return true;

        DateTime? expDate;
        try {
          if (dateString.contains('/')) {
            expDate = DateFormat('dd/MM/yyyy').parse(dateString);
          } else {
            expDate = DateTime.parse(dateString);
          }
        } catch (_) {}

        if (expDate != null) {
          expDate = expDate.toLocal(); // Ensure local timezone comparison
          if (startDateTime != null && expDate.isBefore(startDateTime))
            return false;
          if (endDateTime != null &&
              expDate.isAfter(endDateTime.add(const Duration(hours: 12))))
            return false;
        }

        return true;
      }).toList();
    }

    if (expensesToReport.isEmpty) {
      _snackError('No expenses found in the selected date/time range.');
      return;
    }

    // Log report generation
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();
      await http.post(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/finance/digital-expenses/log-report'),
        headers: {
          'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
          'x-org-ids': orgHdr,
        },
      );
    } catch (_) {}

    // Compute stats
    double totalAmount = 0;
    int approved = 0, declined = 0, pending = 0;
    List<String> approvedList = [], declinedList = [], pendingList = [];

    for (var exp in expensesToReport) {
      final status = (exp['status'] ?? 'Pending').toString().toUpperCase();
      final vNo = exp['voucherNumber'] ?? '-';
      final amount = double.tryParse(exp['amount']?.toString() ?? '0') ?? 0;
      totalAmount += amount;

      final paidTo = (exp['amountPaidTo'] ?? '').toString().trim();
      final paidToStr = paidTo.isNotEmpty ? ' ($paidTo)' : '';
      final line = '$vNo - Rs.${amount.toStringAsFixed(2)}$paidToStr';

      if (status == 'APPROVED') {
        approved++;
        approvedList.add(line);
      } else if (status == 'DECLINED') {
        declined++;
        declinedList.add(line);
      } else {
        pending++;
        pendingList.add(line);
      }
    }

    final now = DateFormat('dd MMM yyyy').format(DateTime.now());

    // Build plain-text clean WhatsApp message exactly matching the requested format
    final buf = StringBuffer();
    buf.write('*Digital Expenses Report* Generated: $now\n');
    buf.write('*Summary*\n');
    buf.write('Total Vouchers : ${expensesToReport.length}\n');
    buf.write('Total Amount : Rs.${totalAmount.toStringAsFixed(2)}\n');
    buf.write('Approved : $approved\n');
    buf.write('Declined : $declined\n');
    buf.write('Pending : $pending\n');

    if (approvedList.isNotEmpty) {
      buf.write('*Approved Vouchers*\n');
      for (final v in approvedList) buf.write('$v\n');
    }

    if (declinedList.isNotEmpty) {
      buf.write('*Declined Vouchers*\n');
      for (final v in declinedList) buf.write('$v\n');
    }

    if (pendingList.isNotEmpty) {
      buf.write('*Pending Vouchers*\n');
      for (final v in pendingList) buf.write('$v\n');
    }

    buf.write('\nPlease review and approve on the Abra Finance portal.');

    final msg = Uri.encodeComponent(buf.toString());
    final url = Uri.parse('https://wa.me/?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _snackError('Could not open WhatsApp');
    }
  }

  // ==========================================================================
  //  DIALOGS & ACTIONS
  // ==========================================================================

  Future<void> _editExpense(Map<String, dynamic> exp) async {
    final result = await showDialog(
        context: context,
        builder: (_) => Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 1000, maxHeight: 850),
                child: NewDigitalExpensePage(
                    expenseData: exp, showAppBar: false))));
    if (result == true) _fetchExpenses();
  }

  void _openVoucherDocument(Map<String, dynamic> exp, {bool isPrint = false}) {
    // Collect proof image URLs
    final List<String> proofUrls = [];
    if (exp['proofFiles'] != null && (exp['proofFiles'] as List).isNotEmpty) {
      for (var p in (exp['proofFiles'] as List)) {
        if (p['path'] != null) {
          final cleanPath = p['path'].toString().replaceAll('\\', '/');
          if (cleanPath.startsWith('/dashboard') || cleanPath.startsWith('dashboard')) {
            final legacyUrl = 'https://crm.abra-logistic.com${cleanPath.startsWith('/') ? '' : '/'}$cleanPath';
            proofUrls.add('${ApiConfig.baseUrl}/api/finance/legacy-image?url=${Uri.encodeComponent(legacyUrl)}');
          } else {
            proofUrls.add('${ApiConfig.baseUrl}/${cleanPath.startsWith('/') ? cleanPath.substring(1) : cleanPath}');
          }
        }
      }
    } else if (exp['proofFile'] != null && exp['proofFile']['path'] != null) {
      final cleanPath = exp['proofFile']['path'].toString().replaceAll('\\', '/');
      if (cleanPath.startsWith('/dashboard') || cleanPath.startsWith('dashboard')) {
        final legacyUrl = 'https://crm.abra-logistic.com${cleanPath.startsWith('/') ? '' : '/'}$cleanPath';
        proofUrls.add('${ApiConfig.baseUrl}/api/finance/legacy-image?url=${Uri.encodeComponent(legacyUrl)}');
      } else {
        proofUrls.add('${ApiConfig.baseUrl}/${cleanPath.startsWith('/') ? cleanPath.substring(1) : cleanPath}');
      }
    }

    // Collect rebuttal proof image URLs
    final List<String> rebuttalProofUrls = [];
    if (exp['rebuttalProofFiles'] != null && (exp['rebuttalProofFiles'] as List).isNotEmpty) {
      for (var p in (exp['rebuttalProofFiles'] as List)) {
        if (p['path'] != null) {
          final cleanPath = p['path'].toString().replaceAll('\\', '/');
          if (cleanPath.startsWith('/dashboard') || cleanPath.startsWith('dashboard')) {
            final legacyUrl = 'https://crm.abra-logistic.com${cleanPath.startsWith('/') ? '' : '/'}$cleanPath';
            rebuttalProofUrls.add('${ApiConfig.baseUrl}/api/finance/legacy-image?url=${Uri.encodeComponent(legacyUrl)}');
          } else {
            rebuttalProofUrls.add('${ApiConfig.baseUrl}/${cleanPath.startsWith('/') ? cleanPath.substring(1) : cleanPath}');
          }
        }
      }
    }

    // Format date nicely
    String formattedDate = exp['date'] ?? '-';
    try {
      final d = DateTime.parse(exp['date']);
      formattedDate = DateFormat('dd/MM/yyyy').format(d);
    } catch (_) {}

    final status = (exp['status'] ?? 'Pending').toString();
    final isApproved = status.toLowerCase() == 'approved';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)]),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'Payment Voucher — ${exp['voucherNumber'] ?? '-'}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold))),
                    if (isPrint)
                      TextButton.icon(
                        onPressed: () {
                          // Trigger browser print of the content below
                          _doPrint(exp, proofUrls);
                        },
                        icon: const Icon(Icons.print,
                            color: Colors.white70, size: 18),
                        label: const Text('Print',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(_)),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: isApproved
                              ? const Color(0xFFE8F5E9)
                              : status.toLowerCase() == 'declined'
                                  ? const Color(0xFFFFEBEE)
                                  : const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Icon(
                              isApproved
                                  ? Icons.check_circle
                                  : status.toLowerCase() == 'declined'
                                      ? Icons.cancel
                                      : Icons.hourglass_empty,
                              color: isApproved
                                  ? Colors.green
                                  : status.toLowerCase() == 'declined'
                                      ? Colors.red
                                      : Colors.orange,
                              size: 18),
                          const SizedBox(width: 8),
                          Text('Status: $status',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isApproved
                                      ? Colors.green[800]
                                      : status.toLowerCase() == 'declined'
                                          ? Colors.red[800]
                                          : Colors.orange[800])),
                        ]),
                      ),
                      if (status.toLowerCase() == 'declined' &&
                          exp['managerReason'] != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                              'Reason for Decline: ${exp['managerReason']}',
                              style: TextStyle(
                                  color: Colors.red[800],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                        ),
                      if (exp['employeeResponse'] != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.purple[50],
                              border: Border.all(color: Colors.purple[100]!),
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.forum, size: 16, color: Colors.purple),
                                  SizedBox(width: 8),
                                  Text('Employee Explanation',
                                      style: TextStyle(
                                          color: Colors.purple,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                exp['employeeResponse'],
                                style: TextStyle(
                                    color: Colors.purple[900], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),
                      // Fields
                      _vRow('Voucher No', exp['voucherNumber'] ?? '-'),
                      _vRow('Date', formattedDate),
                      _vRow('Amount', '₹ ${exp['amount']}'),
                      _vRow('Payment Method', exp['paymentMethod'] ?? '-'),
                      _vRow('Amount Paid To', exp['amountPaidTo'] ?? '-',
                          highlight: true),
                      _vRow('Amount in Words', exp['amountInWords'] ?? '-'),
                      _vRow('On Account Of', exp['onAccountOf'] ?? '-'),
                      _vRow('Received By', exp['receivedBy'] ?? '-'),
                      _vRow('Expense Category', exp['expenseCategory'] ?? '-'),
                      const SizedBox(height: 24),
                      // Signature row
                      Row(
                        children: [
                          Expanded(
                              child: _signBox('Prepared By',
                                  exp['addedByName'] ?? exp['addedBy'] ?? 'Accountant', null)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: _signBox(
                                  'Manager Approval',
                                  isApproved
                                      ? 'Approved Digitally'
                                      : status.toLowerCase() == 'declined'
                                          ? 'Declined'
                                          : status.toLowerCase() == 'response submitted'
                                              ? 'Response Submitted'
                                              : 'Pending Approval',
                                  isApproved
                                      ? Colors.green
                                      : status.toLowerCase() == 'declined'
                                          ? Colors.red
                                          : status.toLowerCase() == 'response submitted'
                                              ? Colors.purple
                                              : Colors.orange)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: _signBox('Receiver Sign',
                                  exp['receivedBy'] ?? '-', null)),
                        ],
                      ),
                      // Proof images
                      if (proofUrls.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Attached Proofs',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        ...proofUrls.map((url) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 80,
                                    decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.grey[300]!)),
                                    child: const Center(
                                        child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                          Icon(Icons.broken_image,
                                              color: Colors.grey),
                                          SizedBox(width: 8),
                                          Text('Could not load image',
                                              style: TextStyle(
                                                  color: Colors.grey)),
                                        ])),
                                  ),
                                  loadingBuilder:
                                      (ctx, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox(
                                        height: 80,
                                        child: Center(
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)));
                                  },
                                ),
                              ),
                            )),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Row(children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text('No proof attachments found',
                                style: TextStyle(color: Colors.orange)),
                          ]),
                        ),
                      // Rebuttal Proof images
                      if (rebuttalProofUrls.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Divider(),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Rebuttal Proofs (Added by Employee)',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple)),
                        ),
                        ...rebuttalProofUrls.map((url) => Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 80,
                                    decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.grey[300]!)),
                                    child: const Center(
                                        child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                          Icon(Icons.broken_image,
                                              color: Colors.grey),
                                          SizedBox(width: 8),
                                          Text('Could not load image',
                                              style: TextStyle(
                                                  color: Colors.grey)),
                                        ])),
                                  ),
                                  loadingBuilder:
                                      (ctx, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const SizedBox(
                                        height: 80,
                                        child: Center(
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)));
                                  },
                                ),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              if ((_currentRole == 'owner' || _currentRole == 'admin') && 
                  (status == 'Pending' || status == 'Response Submitted'))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(top: BorderSide(color: Colors.grey[200]!)),
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showDeclineDialog(exp['_id']);
                        },
                        icon: const Icon(Icons.cancel, size: 16),
                        label: const Text('Decline'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red)),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showApproveConfirmation(exp['_id']);
                        },
                        icon: const Icon(Icons.check_circle, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 160,
              child: Text(label,
                  style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      fontWeight: FontWeight.w500))),
          const Text(': ', style: TextStyle(color: Colors.grey)),
          Expanded(
            child: value.length > 80
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value,
                          style: TextStyle(
                              fontWeight:
                                  highlight ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                              color: highlight ? _navy : Colors.black87),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () {
                          showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                    title: Text(label,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    content: SingleChildScrollView(
                                        child: Text(value)),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Close'))
                                    ],
                                  ));
                        },
                        child: const Text('Read more',
                            style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      )
                    ],
                  )
                : Text(value,
                    style: TextStyle(
                        fontWeight:
                            highlight ? FontWeight.bold : FontWeight.w600,
                        fontSize: 14,
                        color: highlight ? _navy : Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _signBox(String label, String value, Color? color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[400]!, width: 1.5)),
      ),
      child: Column(
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(fontSize: 12, color: color ?? Colors.grey[700]),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Future<void> _doPrint(
      Map<String, dynamic> exp, List<String> proofUrls) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      _snackSuccess('Generating PDF securely from backend...');

      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/finance/digital-expenses/${exp['_id']}/pdf'),
        headers: {
          'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
          'x-org-ids': orgHdr,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['pdfUrl'] != null) {
          final url = '${ApiConfig.baseUrl}${data['pdfUrl']}';
          if (kIsWeb) {
            try {
              final pdfRes = await http.get(Uri.parse(url));
              if (pdfRes.statusCode == 200) {
                await Printing.layoutPdf(
                  onLayout: (PdfPageFormat format) async => pdfRes.bodyBytes,
                  name: 'Expense_${exp['voucherNumber']}',
                );
              } else {
                html.window.open(url, '_blank', 'noopener,noreferrer');
              }
            } catch (e) {
               html.window.open(url, '_blank', 'noopener,noreferrer');
            }
          }
        } else {
          _snackError(data['error'] ?? 'Failed to generate PDF');
        }
      } else {
        _snackError('Server error generating PDF');
      }
    } catch (e) {
      _snackError('Failed to generate PDF: $e');
    }
  }

  void _showDeclineDialog(String id) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Expense'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
              labelText: 'Reason for declining', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) {
                _snackError('Reason is required');
                return;
              }
              Navigator.pop(ctx);
              _updateStatus(id, 'Declined', reasonCtrl.text.trim());
            },
            child: const Text('Decline', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showApproveConfirmation(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Expense'),
        content: const Text(
            'Are you sure you want to approve this digital expense voucher?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(id, 'Approved', null);
            },
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  Future<void> _submitRebuttal(String id) async {
    final TextEditingController responseCtrl = TextEditingController();
    List<PlatformFile> selectedFiles = [];

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Submit Explanation & Proofs'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Provide an explanation for the expense to be re-reviewed by the admin.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: responseCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Explanation (Required)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            allowMultiple: true,
                            type: FileType.custom,
                            allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                          );
                          if (result != null) {
                            setDialogState(() {
                              selectedFiles.addAll(result.files);
                            });
                          }
                        },
                        icon: const Icon(Icons.attach_file, size: 16),
                        label: const Text('Attach New Proofs'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black87,
                        ),
                      ),
                      if (selectedFiles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: selectedFiles.map((f) {
                            return Chip(
                              label: Text(
                                f.name,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () {
                                setDialogState(() {
                                  selectedFiles.remove(f);
                                });
                              },
                            );
                          }).toList(),
                        )
                      ]
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _navy),
                  onPressed: () {
                    if (responseCtrl.text.trim().isEmpty) {
                      _snackError('Explanation is required.');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Submit', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      setState(() => _isLoading = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('jwt_token') ?? '';
        final branchHdr = await FinanceSecureStorage.getBranchHeader();
        final orgHdr = await FinanceSecureStorage.getOrgHeader();

        final uri = Uri.parse('${ApiConfig.baseUrl}/api/finance/digital-expenses/$id/rebuttal');
        final request = http.MultipartRequest('PUT', uri);

        request.headers['Authorization'] = 'Bearer $token';
        request.headers['x-branch-ids'] = branchHdr;
        request.headers['x-org-ids'] = orgHdr;

        request.fields['employeeResponse'] = responseCtrl.text.trim();

        for (var file in selectedFiles) {
          if (kIsWeb) {
            request.files.add(http.MultipartFile.fromBytes(
              'rebuttalProofFiles',
              file.bytes!,
              filename: file.name,
            ));
          } else {
            request.files.add(await http.MultipartFile.fromPath(
              'rebuttalProofFiles',
              file.path!,
            ));
          }
        }

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success']) {
            _snackSuccess('Explanation submitted successfully.');
            _fetchExpenses();
          } else {
            throw Exception(data['message']);
          }
        } else {
          throw Exception('Failed to submit response.');
        }
      } catch (e) {
        _snackError(e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked;
      });
      _applyFilters();
    }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _toDate = picked;
      });
      _applyFilters();
    }
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _applyFilters();
  }

  bool get _hasDateFilters => _fromDate != null || _toDate != null;

  void _snackSuccess(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  void _snackError(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  // ==========================================================================
  //  BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Digital Expenses'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildTopBar(),
          _buildStatsCards(),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _navy))
                : _errorMessage != null
                    ? Center(
                        child: Text('Error: $_errorMessage',
                            style: const TextStyle(color: Colors.red)))
                    : _filteredExpenses.isEmpty
                        ? const Center(
                            child: Text(
                                'No digital expenses found matching the criteria.'))
                        : _isTableView
                            ? _buildTableView()
                            : _buildListView(),
          )
        ],
      ),
    );
  }

  // ==========================================================================
  //  TOP BAR
  // ==========================================================================

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: LayoutBuilder(builder: (_, constraints) {
        final w = constraints.maxWidth;
        if (w >= 1100) return _topBarDesktop();
        if (w >= 700) return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  // ==========================================================================
  //  STATS CARDS
  // ==========================================================================

  Widget _buildStatsCards() {
    if (_filteredExpenses.isEmpty && _allExpenses.isEmpty)
      return const SizedBox.shrink();

    double totalAmt = 0;
    int approved = 0;
    int declined = 0;
    int pending = 0;
    int withProofs = 0;
    int withoutProofs = 0;

    for (var exp in _filteredExpenses) {
      final status = (exp['status'] ?? 'Pending').toString().toUpperCase();
      final amt = double.tryParse((exp['amount'] ?? '0').toString()) ?? 0.0;
      totalAmt += amt;

      if (status == 'APPROVED')
        approved++;
      else if (status == 'DECLINED')
        declined++;
      else
        pending++;

      bool hasProofs = false;
      if (exp['proofFiles'] != null && (exp['proofFiles'] as List).isNotEmpty) {
        hasProofs = true;
      } else if (exp['proofFile'] != null) {
        hasProofs = true;
      }

      if (hasProofs)
        withProofs++;
      else
        withoutProofs++;
    }

    final List<_StatCardData> cards = [
      _StatCardData(
        label: 'Total Amount',
        value: '₹${totalAmt.toStringAsFixed(2)}',
        icon: Icons.account_balance_wallet_rounded,
        color: _blue,
        gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
      ),
      _StatCardData(
        label: 'Approved',
        value: approved.toString(),
        icon: Icons.check_circle_outline_rounded,
        color: _green,
        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'Declined / Pending',
        value: '$declined / $pending',
        icon: Icons.warning_amber_rounded,
        color: _orange,
        gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)],
      ),
      _StatCardData(
        label: 'With / Without Proofs',
        value: '$withProofs / $withoutProofs',
        icon: Icons.attachment_rounded,
        color: _navy,
        gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)],
      ),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, constraints) {
        final isMobile = constraints.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: cards
                  .asMap()
                  .entries
                  .map((e) => Container(
                        width: 170,
                        margin: EdgeInsets.only(
                            right: e.key < cards.length - 1 ? 10 : 0),
                        child: _buildStatCard(e.value, compact: true),
                      ))
                  .toList(),
            ),
          );
        }
        return Row(
          children: cards
              .asMap()
              .entries
              .map((e) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: e.key < cards.length - 1 ? 10 : 0),
                      child: _buildStatCard(e.value, compact: false),
                    ),
                  ))
              .toList(),
        );
      }),
    );
  }

  Widget _buildStatCard(_StatCardData data, {required bool compact}) {
    return Container(
      padding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            data.gradientColors[0].withOpacity(0.15),
            data.gradientColors[1].withOpacity(0.08)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.color.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
              color: data.color.withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: data.gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(data.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(height: 10),
                  Text(data.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(data.value,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: data.color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ])
          : Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: data.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: data.color.withOpacity(0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Icon(data.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(data.label,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Text(data.value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: data.color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
            ]),
    );
  }

  Widget _topBarDesktop() => Row(children: [
        _statusDropdown(),
        const SizedBox(width: 12),
        _searchField(width: 240),
        const SizedBox(width: 10),
        _dateChip(
            label: _fromDate != null
                ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                : 'From Date',
            isActive: _fromDate != null,
            onTap: _selectFromDate),
        const SizedBox(width: 8),
        _dateChip(
            label: _toDate != null
                ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                : 'To Date',
            isActive: _toDate != null,
            onTap: _selectToDate),
        if (_hasDateFilters) ...[
          const SizedBox(width: 6),
          _iconBtn(Icons.close, _clearDateFilters,
              tooltip: 'Clear Dates',
              color: Colors.red[600]!,
              bg: Colors.red[50]!),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _isLoading ? null : _fetchExpenses,
            tooltip: 'Refresh'),
        const SizedBox(width: 8),
        _actionBtn(Icons.upload_file, 'Import', _showImportDialog,
            color: _purple, bg: _purple.withOpacity(0.1)),
        const SizedBox(width: 8),
        _actionBtn(Icons.download, 'Export', _isLoading ? null : _exportToExcel,
            color: _green, bg: _green.withOpacity(0.1)),
        const SizedBox(width: 8),
        _iconBtn(Icons.wechat, _showWhatsAppReportDialog,
            tooltip: 'WhatsApp Report',
            color: Colors.green[700]!,
            bg: Colors.green[50]!),
        if (_currentRole == 'admin' || _currentRole == 'owner') ...[
          const SizedBox(width: 8),
          _iconBtn(Icons.history, _showHistoryDialog,
              tooltip: 'View History',
              color: _navy,
              bg: _navy.withOpacity(0.08)),
        ],
        const Spacer(),
        _buildViewToggle(),
        const SizedBox(width: 12),
        _newVoucherButton(),
      ]);

  Widget _topBarTablet() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _statusDropdown(),
          const SizedBox(width: 10),
          _searchField(width: 200),
          const SizedBox(width: 8),
          _dateChip(
              label: _fromDate != null
                  ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                  : 'From Date',
              isActive: _fromDate != null,
              onTap: _selectFromDate),
          const SizedBox(width: 6),
          _dateChip(
              label: _toDate != null
                  ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                  : 'To Date',
              isActive: _toDate != null,
              onTap: _selectToDate),
          if (_hasDateFilters) ...[
            const SizedBox(width: 6),
            _iconBtn(Icons.close, _clearDateFilters,
                tooltip: 'Clear', color: Colors.red[600]!, bg: Colors.red[50]!),
          ],
          const SizedBox(width: 6),
          _iconBtn(Icons.refresh_rounded, _isLoading ? null : _fetchExpenses,
              tooltip: 'Refresh'),
          const SizedBox(width: 8),
          _actionBtn(Icons.upload_file, 'Import', _showImportDialog,
              color: _purple, bg: _purple.withOpacity(0.1)),
          const SizedBox(width: 8),
          _actionBtn(
              Icons.download, 'Export', _isLoading ? null : _exportToExcel,
              color: _green, bg: _green.withOpacity(0.1)),
          const SizedBox(width: 8),
          _iconBtn(Icons.wechat, _showWhatsAppReportDialog,
              tooltip: 'WhatsApp Report',
              color: Colors.green[700]!,
              bg: Colors.green[50]!),
          if (_currentRole == 'admin' || _currentRole == 'owner') ...[
            const SizedBox(width: 8),
            _iconBtn(Icons.history, _showHistoryDialog,
                tooltip: 'View History',
                color: _navy,
                bg: _navy.withOpacity(0.08)),
          ],
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _buildViewToggle(),
          const SizedBox(width: 10),
          _newVoucherButton(),
        ]),
      ]);

  Widget _topBarMobile() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _statusDropdown(),
          const SizedBox(width: 8),
          Expanded(child: _searchField(width: double.infinity)),
          const SizedBox(width: 8),
          _newVoucherButton(compact: true),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _buildViewToggle(),
            const SizedBox(width: 8),
            _dateChip(
                label: _fromDate != null
                    ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                    : 'From Date',
                isActive: _fromDate != null,
                onTap: _selectFromDate),
            const SizedBox(width: 6),
            _dateChip(
                label: _toDate != null
                    ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                    : 'To Date',
                isActive: _toDate != null,
                onTap: _selectToDate),
            if (_hasDateFilters) ...[
              const SizedBox(width: 6),
              _iconBtn(Icons.close, _clearDateFilters,
                  tooltip: 'Clear',
                  color: Colors.red[600]!,
                  bg: Colors.red[50]!),
            ],
            const SizedBox(width: 6),
            _iconBtn(Icons.refresh_rounded, _isLoading ? null : _fetchExpenses,
                tooltip: 'Refresh'),
            const SizedBox(width: 8),
            _actionBtn(Icons.upload_file, 'Import', _showImportDialog,
                color: _purple, bg: _purple.withOpacity(0.1)),
            const SizedBox(width: 8),
            _actionBtn(
                Icons.download, 'Export', _isLoading ? null : _exportToExcel,
                color: _green, bg: _green.withOpacity(0.1)),
            const SizedBox(width: 8),
            _iconBtn(Icons.wechat, _showWhatsAppReportDialog,
                tooltip: 'WhatsApp Report',
                color: Colors.green[700]!,
                bg: Colors.green[50]!),
            if (_currentRole == 'admin' || _currentRole == 'owner') ...[
              const SizedBox(width: 8),
              _iconBtn(Icons.history, _showHistoryDialog,
                  tooltip: 'View History',
                  color: _navy,
                  bg: _navy.withOpacity(0.08)),
            ],
          ]),
        ),
      ]);

  Widget _newVoucherButton({bool compact = false}) {
    return GestureDetector(
      onTap: () async {
        final result = await showDialog(
            context: context,
            builder: (_) => Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 1000, maxHeight: 850),
                    child: const NewDigitalExpensePage(showAppBar: false))));
        if (result == true) _fetchExpenses();
      },
      child: Container(
        height: 42,
        padding:
            EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 11),
        decoration: BoxDecoration(
            color: _navy, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_rounded, color: Colors.white, size: 20),
          if (!compact) ...[
            const SizedBox(width: 6),
            const Text('New Voucher',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13))
          ],
        ]),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback? onPressed,
      {Color? color, Color? bg}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        foregroundColor: color ?? _navy,
        backgroundColor: bg ?? Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color: color?.withOpacity(0.3) ?? Colors.grey.shade300)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _statusDropdown() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[300]!)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedStatus,
          icon:
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
          style: const TextStyle(
              color: _navy, fontWeight: FontWeight.w600, fontSize: 13),
          onChanged: (v) {
            if (v != null) _filterByStatus(v);
          },
          items: _statusFilters
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
        ),
      ),
    );
  }

  Widget _searchField({required double width}) {
    return SizedBox(
      width: width,
      height: 42,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Search voucher...',
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _navy)),
        ),
      ),
    );
  }

  Widget _dateChip(
      {required String label,
      required bool isActive,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? _navy.withOpacity(0.05) : Colors.grey[100],
          border: Border.all(
              color: isActive ? _navy.withOpacity(0.3) : Colors.grey[300]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_rounded,
              size: 16, color: isActive ? _navy : Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: isActive ? _navy : Colors.grey[700],
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap,
      {String? tooltip, Color? color, Color? bg}) {
    final c = color ?? Colors.grey[700]!;
    final b = bg ?? Colors.grey[100]!;
    Widget btn = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        width: 42,
        decoration: BoxDecoration(
            color: b,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[300]!)),
        child: Icon(icon, size: 20, color: c),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }

  Widget _buildViewToggle() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
          color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(Icons.format_list_bulleted_rounded, true, _isTableView),
          _toggleBtn(Icons.grid_view_rounded, false, !_isTableView),
        ],
      ),
    );
  }

  Widget _toggleBtn(IconData icon, bool forTable, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => _isTableView = forTable),
      child: Container(
        width: 44,
        height: 42,
        decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05), blurRadius: 4)
                  ]
                : null),
        child: Icon(icon, size: 20, color: isActive ? _navy : Colors.grey[500]),
      ),
    );
  }

  // ==========================================================================
  //  TABLE VIEW
  // ==========================================================================

  Widget _buildTableView() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: RawScrollbar(
            controller: _tableHScrollCtrl,
            thumbColor: _navy.withOpacity(0.3),
            thickness: 8,
            radius: const Radius.circular(4),
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 40),
                child: DataTable(
                  headingRowColor:
                      MaterialStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      letterSpacing: 0.4),
                  dataRowHeight: 64,
                  headingRowHeight: 52,
                  horizontalMargin: 24,
                  columnSpacing: 24,
                  columns: const [
                    DataColumn(label: Text('VOUCHER')),
                    DataColumn(label: Text('DATE')),
                    DataColumn(label: Text('PREPARED BY')),
                    DataColumn(label: Text('CATEGORY / DESC')),
                    DataColumn(label: Text('AMOUNT (₹)')),
                    DataColumn(label: Text('PAID TO')),
                    DataColumn(label: Text('PROOF')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _filteredExpenses.map((exp) {
                    final status = exp['status'] ?? 'Pending';
                    final hasProof = (exp['proofFiles'] != null &&
                            (exp['proofFiles'] as List).isNotEmpty) ||
                        exp['proofFile'] != null;
                    return DataRow(
                      cells: [
                        DataCell(Text(exp['voucherNumber'] ?? '-',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: _navy))),
                        DataCell(Text(() {
                          try {
                            return DateFormat('dd/MM/yyyy')
                                .format(DateTime.parse(exp['date']));
                          } catch (_) {
                            return exp['date'] ?? '-';
                          }
                        }(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w500))),
                        DataCell(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(exp['addedByName'] ?? exp['addedBy'] ?? 'Accountant',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: _navy),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: exp['orgId'] == null ? Colors.blue[50] : Colors.purple[50],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: exp['orgId'] == null ? Colors.blue[200]! : Colors.purple[200]!),
                              ),
                              child: Text(exp['orgId'] == null ? 'Abra FlowX.AI' : 'Finance Suite',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: exp['orgId'] == null ? Colors.blue[700] : Colors.purple[700])),
                            )
                          ],
                        )),
                        DataCell(SizedBox(
                          width: 250,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(exp['expenseCategory'] ?? '-',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _navy)),
                              if (exp['onAccountOf'] != null &&
                                  exp['onAccountOf'].toString().isNotEmpty) ...[
                                Text(exp['onAccountOf'],
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600]),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                if (exp['onAccountOf'].toString().length > 30)
                                  InkWell(
                                    onTap: () {
                                      showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                                title: const Text('Description',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16)),
                                                content: SingleChildScrollView(
                                                    child: Text(
                                                        exp['onAccountOf'])),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context),
                                                      child:
                                                          const Text('Close'))
                                                ],
                                              ));
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Text('Read more',
                                          style: TextStyle(
                                              color: Colors.blue,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500)),
                                    ),
                                  )
                              ]
                            ],
                          ),
                        )),
                        DataCell(Text(exp['amount'].toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14))),
                        DataCell(Text(exp['amountPaidTo'] ?? '-')),
                        DataCell(hasProof
                            ? const Icon(Icons.attachment,
                                color: Colors.green, size: 20)
                            : Tooltip(
                                message: 'Proof Missing',
                                child: const Icon(Icons.warning_amber_rounded,
                                    color: Colors.red, size: 20))),
                        DataCell(
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStatusBadge(status),
                              if (status == 'Declined' && exp['managerReason'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Tooltip(
                                    message: exp['managerReason'],
                                    child: SizedBox(
                                      width: 80,
                                      child: Text(
                                        exp['managerReason'],
                                        style: const TextStyle(fontSize: 10, color: Colors.red),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        ),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                icon: const Icon(Icons.visibility,
                                    color: Colors.blue, size: 20),
                                tooltip: 'View',
                                onPressed: () =>
                                    _openVoucherDocument(exp, isPrint: false)),
                            if (status == 'Pending' || status == 'Declined')
                              IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.orange, size: 20),
                                  tooltip: 'Edit',
                                  onPressed: () => _editExpense(exp)),
                            if (status == 'Declined')
                              IconButton(
                                  icon: const Icon(Icons.reply,
                                      color: Colors.purple, size: 20),
                                  tooltip: 'Submit Explanation',
                                  onPressed: () => _submitRebuttal(exp['_id'])),
                            IconButton(
                                icon: const Icon(Icons.print,
                                    color: Colors.grey, size: 20),
                                tooltip: 'Print Voucher',
                                onPressed: () =>
                                    _openVoucherDocument(exp, isPrint: true)),
                            if (_currentRole == 'owner' ||
                                _currentRole == 'admin') ...[
                              if (status == 'Pending' || status == 'Response Submitted') ...[
                                IconButton(
                                    icon: const Icon(Icons.check_circle,
                                        color: Colors.green, size: 20),
                                    tooltip: 'Approve',
                                    onPressed: () =>
                                        _showApproveConfirmation(exp['_id'])),
                                IconButton(
                                    icon: const Icon(Icons.cancel,
                                        color: Colors.red, size: 20),
                                    tooltip: 'Decline',
                                    onPressed: () =>
                                        _showDeclineDialog(exp['_id'])),
                              ] else ...[
                                IconButton(
                                    icon: const Icon(Icons.undo_rounded,
                                        color: Colors.orange, size: 20),
                                    tooltip: 'Revert to Pending',
                                    onPressed: () =>
                                        _updateStatus(exp['_id'], 'Pending')),
                              ],
                            ],
                            if (status == 'Pending' ||
                                _currentRole == 'owner' ||
                                _currentRole == 'admin')
                              IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red, size: 20),
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteExpense(exp['_id'])),
                          ],
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  //  LIST VIEW
  // ==========================================================================

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _filteredExpenses.length,
      itemBuilder: (ctx, i) {
        final exp = _filteredExpenses[i];
        final status = exp['status'] ?? 'Pending';
        final hasProof = (exp['proofFiles'] != null &&
                (exp['proofFiles'] as List).isNotEmpty) ||
            exp['proofFile'] != null;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(exp['voucherNumber'] ?? '-',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _navy)),
                              const SizedBox(width: 8),
                              if (!hasProof)
                                Tooltip(
                                    message: 'Proof Missing',
                                    child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                            color: Colors.red[50],
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: const Icon(
                                            Icons.warning_amber_rounded,
                                            size: 14,
                                            color: Colors.red))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(exp['expenseCategory'] ?? 'Digital Expense',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                          const SizedBox(height: 4),
                          Text('Date: ${exp['date'] ?? '-'}',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    _buildStatusBadge(status),
                  ],
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(height: 1)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Amount',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                        Text('₹${exp['amount']}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Paid To',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                        Text(exp['amountPaidTo'] ?? '-',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
                if (exp['managerReason'] != null && status == 'Declined')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('Reason: ${exp['managerReason']}',
                          style:
                              TextStyle(color: Colors.red[800], fontSize: 13)),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility, color: Colors.blue),
                      onPressed: () =>
                          _openVoucherDocument(exp, isPrint: false),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.blue[50]),
                    ),
                    const SizedBox(width: 8),
                    if (status == 'Pending' || status == 'Declined') ...[
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        onPressed: () => _editExpense(exp),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.orange[50]),
                      ),
                    ],
                    if (status == 'Declined') ...[
                      IconButton(
                        icon: const Icon(Icons.reply, color: Colors.purple),
                        tooltip: 'Submit Explanation',
                        onPressed: () => _submitRebuttal(exp['_id']),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.purple[50]),
                      ),
                      const SizedBox(width: 8),
                    ],
                    IconButton(
                      icon: const Icon(Icons.print, color: Colors.grey),
                      onPressed: () => _openVoucherDocument(exp, isPrint: true),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[200]),
                    ),
                    const SizedBox(width: 8),
                    if (_currentRole == 'owner' || _currentRole == 'admin') ...[
                      if (status == 'Pending' || status == 'Response Submitted') ...[
                        OutlinedButton.icon(
                          onPressed: () => _showDeclineDialog(exp['_id']),
                          icon: const Icon(Icons.cancel, size: 16),
                          label: const Text('Decline'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showApproveConfirmation(exp['_id']),
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        OutlinedButton.icon(
                          onPressed: () => _updateStatus(exp['_id'], 'Pending'),
                          icon: const Icon(Icons.undo_rounded, size: 16),
                          label: const Text('Revert'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange,
                              side: const BorderSide(color: Colors.orange)),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                    if (status == 'Pending' ||
                        _currentRole == 'owner' ||
                        _currentRole == 'admin')
                      IconButton(
                        icon:
                            const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteExpense(exp['_id']),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.red[50]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg, text;
    switch (status.toUpperCase()) {
      case 'APPROVED':
        bg = const Color(0xFFE8F5E9);
        text = const Color(0xFF2E7D32);
        break;
      case 'PENDING':
        bg = const Color(0xFFFFF3E0);
        text = const Color(0xFFEF6C00);
        break;
      case 'DECLINED':
        bg = const Color(0xFFFFEBEE);
        text = const Color(0xFFC62828);
        break;
      case 'RESPONSE SUBMITTED':
        bg = const Color(0xFFF3E5F5); // Light purple
        text = const Color(0xFF7B1FA2); // Dark purple
        break;
      default:
        bg = Colors.grey[200]!;
        text = Colors.grey[800]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status,
          style: TextStyle(
              color: text,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 0.5)),
    );
  }

  Future<void> _showHistoryDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/finance/digital-expenses/history');
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'x-branch-ids': branchHdr,
        'x-org-ids': orgHdr,
      });

      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> historyData = data['data'] ?? [];

        showDialog(
          context: context,
          builder: (_) => Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 600,
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF0D1B3E), Color(0xFF1A3A6B)]),
                      borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Activity History',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: historyData.isEmpty
                        ? const Center(
                            child: Text('No history found.',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: historyData.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final h = historyData[i];
                              final dateStr = h['createdAt'] != null
                                  ? DateFormat('dd MMM yyyy, hh:mm a').format(
                                      DateTime.parse(h['createdAt']).toLocal())
                                  : '-';
                              final action = h['action'] ?? 'Unknown';

                              Color iconColor = Colors.grey;
                              IconData iconData = Icons.info_outline;
                              if (action == 'Created' ||
                                  action == 'Bulk Imported') {
                                iconColor = Colors.blue;
                                iconData = Icons.add_circle_outline;
                              } else if (action == 'Updated') {
                                iconColor = Colors.orange;
                                iconData = Icons.edit;
                              } else if (action == 'Deleted') {
                                iconColor = Colors.red;
                                iconData = Icons.delete_outline;
                              } else if (action == 'Approved') {
                                iconColor = Colors.green;
                                iconData = Icons.check_circle_outline;
                              } else if (action == 'Declined') {
                                iconColor = Colors.red;
                                iconData = Icons.cancel_outlined;
                              } else if (action == 'Reverted') {
                                iconColor = Colors.orange;
                                iconData = Icons.undo;
                              } else if (action == 'Report Generated') {
                                iconColor = Colors.purple;
                                iconData = Icons.picture_as_pdf;
                              }

                              return ListTile(
                                leading: CircleAvatar(
                                    backgroundColor: iconColor.withOpacity(0.1),
                                    child: Icon(iconData,
                                        color: iconColor, size: 20)),
                                title: Text(h['details'] ?? 'No details',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('By: ${h['performedBy'] ?? 'Unknown'}',
                                        style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 12)),
                                    if (h['voucherNumber'] != null)
                                      Text('Voucher: ${h['voucherNumber']}',
                                          style: TextStyle(
                                              color: Colors.grey[700],
                                              fontSize: 12)),
                                    Text(dateStr,
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 11)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        _snackError('Failed to load history');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading dialog if open
      _snackError('Error fetching history: $e');
    }
  }
}
