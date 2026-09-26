import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// REPORT DETAIL PAGE — COMPLETE
// ============================================================================
// File: lib/screens/billing/pages/report_detail_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/reports_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'report_viewer_page.dart';

const _navy = Color(0xFF1E3A8A);
const _green = Color(0xFF27AE60);
const _blue = Color(0xFF2980B9);
const _orange = Color(0xFFE67E22);
const _red = Color(0xFFE74C3C);
const _teal = Color(0xFF1ABC9C);
const _purple = Color(0xFF9B59B6);

// ─── Scroll behaviour ─────────────────────────────────────────────────────────
class _AllDeviceScroll extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _P {
  final String key;
  final String label;
  const _P(this.key, this.label);
}

const _periods = [
  _P('today', 'Today'),
  _P('this_week', 'This Week'),
  _P('this_month', 'This Month'),
  _P('last_month', 'Last Month'),
  _P('this_quarter', 'This Quarter'),
  _P('last_quarter', 'Last Quarter'),
  _P('this_fy', 'This Financial Year'),
  _P('last_fy', 'Last Financial Year'),
  _P('custom', 'Custom Range'),
];

// ─── Related reports for detail page ─────────────────────────────────────────
const Map<String, List<Map<String, String>>> _detailRelated = {
  'invoice-details': [
    {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'customer-balance', 'name': 'Customer Balance'},
    {'key': 'credit-note-details', 'name': 'Credit Notes'},
  ],
  'bill-details': [
    {'key': 'ap-aging-summary', 'name': 'AP Aging Summary'},
    {'key': 'payments-made', 'name': 'Payments Made'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance'},
    {'key': 'purchase-order-details', 'name': 'Purchase Orders'},
  ],
  'expense-details': [
    {'key': 'expenses-by-category', 'name': 'Expenses by Category'},
    {'key': 'billable-expense-details', 'name': 'Billable Expenses'},
    {'key': 'purchases-by-vendor', 'name': 'Purchases by Vendor'},
  ],
  'account-transactions': [
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'journal-report', 'name': 'Journal Report'},
  ],
  'project-details': [
    {'key': 'timesheet-details', 'name': 'Timesheet Details'},
    {'key': 'projects-cost-summary', 'name': 'Projects Cost Summary'},
    {'key': 'projects-revenue-summary', 'name': 'Projects Revenue Summary'},
  ],
  'timesheet-details': [
    {'key': 'project-summary', 'name': 'Project Summary'},
    {'key': 'timesheet-profitability', 'name': 'Timesheet Profitability'},
    {'key': 'expenses-by-project', 'name': 'Expenses by Project'},
  ],
  'payments-received': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'credit-note-details', 'name': 'Credit Notes'},
    {'key': 'refund-history', 'name': 'Refund History'},
  ],
  'payments-made': [
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'vendor-credit-details', 'name': 'Vendor Credits'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance'},
  ],
};

// =============================================================================
class ReportDetailPage extends StatefulWidget {
  final ReportMeta parentReport;
  final Map<String, dynamic> rowData;
  final String orgName;
  final Map<String, String> periodParams;

  const ReportDetailPage({
    Key? key,
    required this.parentReport,
    required this.rowData,
    required this.orgName,
    required this.periodParams,
  }) : super(key: key);

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _rows = [];
  List<String> _headers = [];
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _search = '';

  late String _periodKey;
  DateTime? _fromDate;
  DateTime? _toDate;

  final _searchCtrl = TextEditingController();
  final _tableHScroll = ScrollController();
  final _tableVScroll = ScrollController();
  final _bodyScroll = ScrollController();

  // ── Entity name ────────────────────────────────────────────────────────────
  String get _entityName {
    final r = widget.rowData;
    return r['section']?.toString() ??
        r['customerName']?.toString() ??
        r['vendorName']?.toString() ??
        r['projectName']?.toString() ??
        r['itemName']?.toString() ??
        r['accountName']?.toString() ??
        r['salesperson']?.toString() ??
        r['category']?.toString() ??
        r['employee']?.toString() ??
        r['name']?.toString() ??
        r['_id']?.toString() ??
        'Details';
  }

  // ── Detail endpoint & params ───────────────────────────────────────────────
  String get _detailKey {
    final k = widget.parentReport.key;
    if (k.contains('tds-receivable')) return 'tds-receivable-details';
    if (k.contains('sales-by-customer') ||
        k.contains('customer-balance') ||
        k.contains('ar-aging') ||
        k.contains('receivable')) return 'invoice-details';
    if (k.contains('vendor-balance') ||
        k.contains('purchases-by-vendor') ||
        k.contains('ap-aging') ||
        k.contains('payable')) return 'bill-details';
    if (k.contains('sales-by-item') || k.contains('purchases-by-item'))
      return 'invoice-details';
    if (k.contains('sales-by-salesperson')) return 'invoice-details';
    if (k.contains('expense')) return 'expense-details';
    if (k.contains('payments-received') ||
        k.contains('credit-note') ||
        k.contains('refund')) return 'payments-received';
    if (k.contains('payments-made')) return 'payments-made';
    if (k.contains('account-type-summary')) return 'account-type-transactions';
    if (k.contains('trial-balance') ||
        k.contains('general-ledger') ||
        k.contains('account-type-transactions')) return 'account-transactions';
    if (k.contains('project-summary') ||
        k.contains('projects-cost') ||
        k.contains('projects-revenue') ||
        k.contains('projects-performance')) return 'project-details';
    if (k.contains('project') || k.contains('timesheet'))
      return 'timesheet-details';
    if (k.contains('reconciliation')) return 'reconciliation-status';
    return 'invoice-details';
  }

  Map<String, String> get _detailParams {
    final params = Map<String, String>.from(widget.periodParams);
    if (_periodKey != 'custom') {
      params['period'] = _periodKey;
      params.remove('fromDate');
      params.remove('toDate');
    } else {
      params.remove('period');
      if (_fromDate != null) params['fromDate'] = _fromDate!.toIso8601String();
      if (_toDate != null) params['toDate'] = _toDate!.toIso8601String();
    }
    
    final r = widget.rowData;
    final pk = widget.parentReport.key;
    final rawId = r['_id']?.toString();

    if (pk.contains('tds-receivable')) {
      if (r['section'] != null) params['section'] = r['section'].toString();
    } else if (pk.contains('sales-by-customer') ||
        pk.contains('customer-balance') ||
        pk.contains('ar-aging') ||
        pk.contains('receivable-details')) {
      if (rawId != null && rawId.isNotEmpty && rawId != 'null') {
        if (RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(rawId)) {
          params['customerId'] = rawId;
        } else {
          params['customerName'] = rawId;
        }
      }
      if (r['customerName'] != null) {
        params['customerName'] = r['customerName'].toString();
      }
    } else if (pk.contains('vendor-balance') ||
        pk.contains('purchases-by-vendor') ||
        pk.contains('ap-aging')) {
      if (rawId != null && rawId.isNotEmpty && rawId != 'null') {
        if (RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(rawId)) {
          params['vendorId'] = rawId;
        } else {
          params['vendorName'] = rawId;
        }
      }
      if (r['vendorName'] != null) {
        params['vendorName'] = r['vendorName'].toString();
      }
    } else if (pk.contains('receivable-summary')) {
      // Grouped by status, not by customer — forward the status itself.
      if (r['status'] != null) params['status'] = r['status'].toString();
    } else if (pk.contains('sales-by-salesperson')) {
      final salesperson = r['salesperson']?.toString() ?? rawId;
      if (salesperson != null && salesperson.isNotEmpty && salesperson != 'null')
        params['salesperson'] = salesperson;
    } else if (pk.contains('sales-by-item') ||
        pk.contains('purchases-by-item')) {
      final itemName = r['itemName']?.toString() ?? rawId;
      if (itemName != null && itemName.isNotEmpty && itemName != 'null')
        params['itemName'] = itemName;
    } else if (pk.contains('expenses-by-category')) {
      final category = r['category']?.toString() ?? rawId;
      if (category != null && category.isNotEmpty && category != 'null')
        params['expenseAccount'] = category;
    } else if (pk.contains('expenses-by-customer')) {
      final customerName = r['customerName']?.toString() ?? rawId;
      if (customerName != null && customerName.isNotEmpty && customerName != 'null')
        params['customerName'] = customerName;
    } else if (pk.contains('expenses-by-project')) {
      final project = r['project']?.toString() ?? rawId;
      if (project != null && project.isNotEmpty && project != 'null')
        params['project'] = project;
    } else if (pk.contains('expenses-by-employee')) {
      final employee = r['employee']?.toString() ?? rawId;
      if (employee != null && employee.isNotEmpty && employee != 'null')
        params['paidThrough'] = employee;
    } else if (pk.contains('account-type-summary')) {
      final accountType = r['accountType']?.toString() ?? rawId;
      if (accountType != null && accountType.isNotEmpty && accountType != 'null')
        params['accountType'] = accountType;
    } else if (pk.contains('project-summary') ||
        pk.contains('projects-cost') ||
        pk.contains('projects-revenue') ||
        pk.contains('projects-performance')) {
      final projectId = r['projectId']?.toString() ?? rawId;
      if (projectId != null && projectId.isNotEmpty && projectId != 'null')
        params['projectId'] = projectId;
    } else if (pk.contains('trial-balance') ||
        pk.contains('general-ledger') ||
        pk.contains('account-type-transactions')) {
      final accountId = r['accountId']?.toString() ?? rawId;
      if (accountId != null && accountId.isNotEmpty && accountId != 'null')
        params['accountId'] = accountId;
    }

    // Forward explicit IDs from row data
    if (r['customerId'] != null)
      params['customerId'] = r['customerId'].toString();
    if (r['vendorId'] != null) params['vendorId'] = r['vendorId'].toString();
    if (r['accountId'] != null) params['accountId'] = r['accountId'].toString();
    if (r['projectId'] != null) params['projectId'] = r['projectId'].toString();

    return params;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    if (widget.periodParams['fromDate'] != null || widget.periodParams['toDate'] != null) {
      _periodKey = 'custom';
    } else {
      _periodKey = widget.periodParams['period'] ?? 'this_fy';
    }
    if (widget.periodParams['fromDate'] != null) {
      _fromDate = DateTime.tryParse(widget.periodParams['fromDate']!);
    }
    if (widget.periodParams['toDate'] != null) {
      _toDate = DateTime.tryParse(widget.periodParams['toDate']!);
    }
    _searchCtrl.addListener(
        () => setState(() => _search = _searchCtrl.text.toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScroll.dispose();
    _tableVScroll.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  // ── Load ───────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ReportsService.fetchReport(_detailKey, _detailParams);
      _parse(d);
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ── Parse ──────────────────────────────────────────────────────────────────
  void _parse(Map<String, dynamic> d) {
    _rows = [];
    _headers = [];
    const listKeys = [
      'rows',
      'invoices',
      'bills',
      'payments',
      'expenses',
      'transactions',
      'entries',
      'creditNotes',
      'journals',
      'items',
      'profiles',
      'purchaseOrders',
      'refunds',
      'accounts',
      'projects',
      'timesheets',
      'logs',
      'mails',
      'activities',
      'categories',
      'vendors',
      'customers',
      'reconciliations',
      'exceptions',
      'salespersons',
      'employees',
      'reviews',
    ];
    List<dynamic>? list;
    for (final k in listKeys) {
      if (d[k] is List && (d[k] as List).isNotEmpty) {
        list = d[k];
        break;
      }
    }
    if (list == null && d['data'] is List && (d['data'] as List).isNotEmpty) {
      list = d['data'] as List;
    }
    if (list != null) {
      final hSet = <String>{};
      for (final row in list) {
        if (row is Map)
          hSet.addAll(row.keys
              .cast<String>()
              .where((k) => !k.startsWith('_') && k != 'id'));
      }
      _headers = hSet.toList();
      _rows = list.map<Map<String, dynamic>>((r) {
        if (r is Map<String, dynamic>) return r;
        if (r is Map) return Map<String, dynamic>.from(r);
        return {'value': r.toString()};
      }).toList();
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _rows;
    return _rows
        .where((r) =>
            r.values.any((v) => v.toString().toLowerCase().contains(_search)))
        .toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _colLabel(String h) => h
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
      .trim()
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _displayVal(String h, dynamic v) {
    if (v == null) return '-';
    final s = v.toString();
    if (s == 'null' || s.isEmpty) return '-';
    if (s.length >= 10 &&
        (s.contains('T') || RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s))) {
      try {
        return DateFormat('dd MMM yyyy').format(DateTime.parse(s));
      } catch (_) {}
    }
    final hl = h.toLowerCase();
    if (hl.contains('amount') ||
        hl.contains('total') ||
        hl.contains('paid') ||
        hl.contains('due') ||
        hl.contains('balance') ||
        hl.contains('debit') ||
        hl.contains('credit') ||
        hl.contains('cost') ||
        hl.contains('revenue') ||
        hl.contains('profit') ||
        hl.contains('budget') ||
        hl.contains('rate')) {
      final n = double.tryParse(s.replaceAll(',', '').replaceAll('₹', ''));
      if (n != null) return '₹${n.toStringAsFixed(2)}';
    }
    return s;
  }

  // ── Exports ────────────────────────────────────────────────────────────────
  Future<void> _exportPDF() async {
    if (_rows.isEmpty) {
      _snackErr('No data to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      await ExportHelper.exportToPDF(
        title: '${widget.orgName}\n${widget.parentReport.name} — $_entityName',
        headers: _headers.map(_colLabel).toList(),
        data: _rows
            .map((r) => _headers
                .map((h) => _displayVal(h, r[h]).replaceAll('₹', 'Rs.'))
                .toList())
            .toList(),
        filename:
            '${widget.parentReport.name.replaceAll(' ', '_')}_$_entityName',
      );
      _snackOk('PDF downloaded');
    } catch (e) {
      _snackErr('PDF failed: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) {
      _snackErr('No data to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      await ReportsService.exportExcel(
        reportName: '${widget.parentReport.name} — $_entityName',
        companyName: widget.orgName,
        reportData: _rows,
        headers: _headers.map(_colLabel).toList(),
      );
      _snackOk('Excel downloaded');
    } catch (e) {
      _snackErr('Excel failed: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  void _snackOk(String m) {
    if (!mounted) return;
    AppSnackbar.show(context, message: m);
  }

  void _snackErr(String m) {
    if (!mounted) return;
    AppSnackbar.show(context, message: m);
  }

  // ── Row tap — go one level deeper ─────────────────────────────────────────
  void _onRowTap(Map<String, dynamic> row) {
    // Determine if there's a next-level detail
    final dk = _detailKey;
    final nextKey = _nextDrillKey(dk);
    if (nextKey.isEmpty) {
      _showRowDialog(row);
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReportDetailPage(
                parentReport: ReportMeta(key: dk, name: _titleFor(dk)),
                rowData: row,
                orgName: widget.orgName,
                periodParams: widget.periodParams)));
  }

  String _nextDrillKey(String currentKey) {
    if (currentKey == 'invoice-details' ||
        currentKey == 'bill-details' ||
        currentKey == 'expense-details' ||
        currentKey == 'payments-received' ||
        currentKey == 'payments-made')
      return ''; // Already at leaf level — show dialog only
    if (currentKey == 'account-type-transactions')
      return 'account-transactions';
    if (currentKey == 'project-details') return 'timesheet-details';
    return '';
  }

  String _titleFor(String key) {
    const titles = {
      'invoice-details': 'Invoice Details',
      'bill-details': 'Bill Details',
      'expense-details': 'Expense Details',
      'payments-received': 'Payments Received',
      'payments-made': 'Payments Made',
      'account-transactions': 'Account Transactions',
      'account-type-transactions': 'Account Type Transactions',
      'project-details': 'Project Details',
      'timesheet-details': 'Timesheet Details',
      'reconciliation-status': 'Reconciliation Status',
    };
    return titles[key] ?? key;
  }

  void _showRowDialog(Map<String, dynamic> row) {
    showDialog(
        context: context,
        builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Container(
                width: 560,
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(14),
                              topRight: Radius.circular(14))),
                      child: Row(children: [
                        const Icon(Icons.receipt_long_outlined,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Transaction Details',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                            padding: EdgeInsets.zero),
                      ])),
                  Flexible(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            // Status badge if present
                            if (row['status'] != null) ...[
                              _statusBadge(row['status'].toString()),
                              const SizedBox(height: 12),
                            ],
                            // Key-value pairs
                            ...row.entries
                                .where((e) =>
                                    !e.key.startsWith('_') && e.key != 'status')
                                .map((e) => Container(
                                    margin: const EdgeInsets.only(bottom: 1),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 9),
                                    decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(4)),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                              width: 160,
                                              child: Text(_colLabel(e.key),
                                                  style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: _navy))),
                                          Expanded(
                                              child: Text(
                                                  _displayVal(e.key, e.value),
                                                  style: const TextStyle(
                                                      fontSize: 14,
                                                      color:
                                                          Color(0xFF374151)))),
                                        ]))),
                          ]))),
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                          color: Color(0xFFF7F9FC),
                          border:
                              Border(top: BorderSide(color: Color(0xFFEEF2F7))),
                          borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(14),
                              bottomRight: Radius.circular(14))),
                      child: Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _exportPDF();
                                },
                                icon: const Icon(Icons.picture_as_pdf_rounded,
                                    size: 15),
                                label: const Text('PDF',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: _red,
                                    side: const BorderSide(color: _red),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8))))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _exportExcel();
                                },
                                icon: const Icon(Icons.table_chart_rounded,
                                    size: 15),
                                label: const Text('Excel',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: _green,
                                    side: const BorderSide(color: _green),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8))))),
                      ])),
                ]),
              ),
            ));
  }

  // ── Navigate to related report ─────────────────────────────────────────────
  void _openRelatedReport(Map<String, String> rel) async {
    try {
      final cats = await ReportsService.getMeta();
      ReportMeta? target;
      for (final cat in cats) {
        for (final r in cat.reports) {
          if (r.key == rel['key']) {
            target = r;
            break;
          }
        }
        if (target != null) break;
      }
      target ??= ReportMeta(key: rel['key']!, name: rel['name']!);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ReportViewerPage(report: target!, orgName: widget.orgName)));
    } catch (_) {
      final target = ReportMeta(key: rel['key']!, name: rel['name']!);
      if (!mounted) return;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ReportViewerPage(report: target, orgName: widget.orgName)));
    }
  }

  // ── Filters ────────────────────────────────────────────────────────────────
  Future<void> _pickFrom() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _fromDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        builder: (c, child) => Theme(
            data: Theme.of(c)
                .copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
            child: child!));
    if (d != null) {
      setState(() {
        _fromDate = d;
        _periodKey = 'custom';
      });
      _load();
    }
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _toDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        builder: (c, child) => Theme(
            data: Theme.of(c)
                .copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
            child: child!));
    if (d != null) {
      setState(() {
        _toDate = d;
        _periodKey = 'custom';
      });
      _load();
    }
  }

  Widget _datePill(String label, bool active, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              color: active ? _navy.withOpacity(0.08) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: active ? _navy : const Color(0xFFDDE3EE))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today,
                size: 11, color: active ? _navy : Colors.grey[500]),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? _navy : Colors.grey[700])),
          ])));

  Widget _buildFilterBar() {
    final label = _periods
        .firstWhere((p) => p.key == _periodKey,
            orElse: () => const _P('custom', 'Custom Range'))
        .label;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LayoutBuilder(builder: (_, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final content = Row(mainAxisSize: MainAxisSize.min, children: [
          PopupMenuButton<String>(
            initialValue: _periodKey,
            onSelected: (v) {
              setState(() => _periodKey = v);
              if (v != 'custom') _load();
            },
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => _periods
                .map((p) => PopupMenuItem(
                    value: p.key,
                    child: Row(children: [
                      Icon(
                          p.key == _periodKey
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 16,
                          color:
                              p.key == _periodKey ? _navy : Colors.grey[400]),
                      const SizedBox(width: 8),
                      Text(p.label,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: p.key == _periodKey
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ])))
                .toList(),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: _navy.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _navy.withOpacity(0.25))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.date_range_rounded, size: 15, color: _navy),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _navy)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 16, color: _navy),
                ])),
          ),
          if (_periodKey == 'custom') ...[
            const SizedBox(width: 8),
            _datePill(
                _fromDate != null
                    ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                    : 'From Date',
                _fromDate != null,
                _pickFrom),
            const SizedBox(width: 6),
            _datePill(
                _toDate != null
                    ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                    : 'To Date',
                _toDate != null,
                _pickTo),
            if (_fromDate != null || _toDate != null) ...[
              const SizedBox(width: 6),
              InkWell(
                  onTap: () {
                    setState(() {
                      _fromDate = null;
                      _toDate = null;
                      _periodKey = 'this_fy';
                    });
                    _load();
                  },
                  child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red[200]!)),
                      child: const Icon(Icons.close, size: 13, color: _red))),
            ],
          ],
        ]);

        if (isNarrow) {
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 5),
              child: content);
        }
        return content;
      }),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: '${widget.parentReport.name} — $_entityName'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(children: [
        _buildTopBar(),
        _buildFilterBar(),
        if (_loading)
          const Expanded(
              child: Center(child: CircularProgressIndicator(color: _navy)))
        else if (_error != null)
          Expanded(child: _buildError())
        else
          Expanded(child: _buildBody()),
      ]),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 700) {
          return Row(children: [
            _entityBadge(),
            const SizedBox(width: 12),
            Expanded(child: _searchBox()),
            const SizedBox(width: 8),
            _iconBtn(Icons.refresh_rounded, _loading ? null : _load),
            const SizedBox(width: 8),
            _btn('PDF', Icons.picture_as_pdf_rounded, _red,
                _exporting ? null : _exportPDF),
            const SizedBox(width: 6),
            _btn('Excel', Icons.table_chart_rounded, _green,
                _exporting ? null : _exportExcel),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _entityBadge(),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _searchBox()),
            const SizedBox(width: 8),
            _iconBtn(Icons.refresh_rounded, _loading ? null : _load)
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _smBtn('PDF', _red, _exporting ? null : _exportPDF),
            const SizedBox(width: 6),
            _smBtn('Excel', _green, _exporting ? null : _exportExcel),
          ]),
        ]);
      }),
    );
  }

  Widget _entityBadge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: _navy.withOpacity(0.07),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_outline, size: 13, color: _navy),
        const SizedBox(width: 5),
        Text(_entityName,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: _navy)),
      ]));

  Widget _searchBox() => SizedBox(
      height: 40,
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search…',
          hintStyle: TextStyle(fontSize: 15, color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey[400]),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  })
              : null,
          filled: true,
          fillColor: const Color(0xFFF7F9FC),
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _navy, width: 1.5)),
        ),
      ));

  // ==========================================================================
  // BODY — table + summary + related
  // ==========================================================================

  Widget _buildBody() {
    return ScrollConfiguration(
      behavior: _AllDeviceScroll(),
      child: SingleChildScrollView(
        controller: _bodyScroll,
        child: Column(children: [
          _buildSummaryCards(),
          SizedBox(
            height: _tableHeight(),
            child: _buildTable(),
          ),
          _buildRelatedReports(),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  double _tableHeight() {
    if (_rows.isEmpty) return 280;
    final screenH = MediaQuery.of(context).size.height;
    final rowH =
        _rows.length <= 8 ? (_rows.length * 56.0 + 100) : screenH * 0.52;
    return rowH.clamp(280, screenH * 0.60);
  }

  // ── Summary cards ──────────────────────────────────────────────────────────
  Widget _buildSummaryCards() {
    if (_data == null) return const SizedBox.shrink();
    final totalsRaw = _data!['totals'] ?? _data!['total'];
    if (totalsRaw == null) return const SizedBox.shrink();
    final items = <Map<String, String>>[];
    if (totalsRaw is Map) {
      totalsRaw.forEach((k, v) {
        if (v != null && v.toString().isNotEmpty)
          items.add({'label': _colLabel(k.toString()), 'value': v.toString()});
      });
    } else if (totalsRaw is num) {
      items.add({'label': 'Total', 'value': totalsRaw.toStringAsFixed(2)});
    }
    if (items.isEmpty) return const SizedBox.shrink();
    final colours = [_navy, _green, _blue, _orange, _purple, _teal];
    return Container(
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
              children: items.asMap().entries.map((e) {
            final color = colours[e.key % colours.length];
            final n = double.tryParse(e.value['value'] ?? '');
            return Container(
                width: 155,
                margin:
                    EdgeInsets.only(right: e.key < items.length - 1 ? 10 : 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                          color: color.withOpacity(0.06),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ]),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.value['label'] ?? '',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                          n != null
                              ? ((e.value['label'] ?? '').toLowerCase().contains('count') || (e.value['label'] ?? '').toLowerCase().contains('quantity') || (e.value['label'] ?? '').toLowerCase().contains('percent')
                                  ? (n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2))
                                  : '₹${n.toStringAsFixed(2)}')
                              : (e.value['value'] ?? ''),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ]));
          }).toList())),
    );
  }

  // ── Table ──────────────────────────────────────────────────────────────────
  Widget _buildTable() {
    final rows = _filtered;

    if (rows.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(
            _search.isNotEmpty
                ? 'No results match "$_search"'
                : 'No records found for $_entityName',
            style: TextStyle(fontSize: 17, color: Colors.grey[500]),
            textAlign: TextAlign.center),
        if (_search.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton(
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _search = '');
              },
              child: const Text('Clear search')),
        ],
      ]));
    }

    if (_headers.isEmpty) {
      return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Text(_data.toString(),
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13))));
    }

    final colW = _headers.length <= 4
        ? 180.0
        : _headers.length <= 7
            ? 145.0
            : 120.0;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ]),
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Text(
                  '${rows.length} record${rows.length != 1 ? 's' : ''}${_search.isNotEmpty ? " (filtered)" : ''}',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              if (_exporting)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _navy)),
            ])),
        const Divider(height: 1),
        // ── FIXED SCROLLING: horizontal scroll wraps ENTIRE DataTable ─────
        Expanded(
          child: ScrollConfiguration(
            behavior: _AllDeviceScroll(),
            child: Scrollbar(
              controller: _tableHScroll,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 7,
              radius: const Radius.circular(4),
              child: SingleChildScrollView(
                controller: _tableHScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  // Give explicit width so vertical scroll works inside
                  width: (_headers.length * colW + 28).clamp(
                      MediaQuery.of(context).size.width - 32, double.infinity),
                  child: ScrollConfiguration(
                    behavior: _AllDeviceScroll(),
                    child: Scrollbar(
                      controller: _tableVScroll,
                      child: SingleChildScrollView(
                        controller: _tableVScroll,
                        scrollDirection: Axis.vertical,
                        child: DataTable(
                          showCheckboxColumn: false,
                          headingRowColor:
                              WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                          headingTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.3),
                          headingRowHeight: 46,
                          dataRowMinHeight: 50,
                          dataRowMaxHeight: 64,
                          dataTextStyle: const TextStyle(
                              fontSize: 14, color: Color(0xFF374151)),
                          dividerThickness: 1,
                          columnSpacing: 14,
                          horizontalMargin: 14,
                          columns: _headers.map((h) {
                            final hl = h.toLowerCase();
                            final isAmt = hl.contains('amount') ||
                                hl.contains('total') ||
                                hl.contains('balance') ||
                                hl.contains('due') ||
                                hl.contains('paid');
                            return DataColumn(
                                numeric: isAmt,
                                label: SizedBox(
                                    width: colW,
                                    child: Text(_colLabel(h).toUpperCase(),
                                        overflow: TextOverflow.ellipsis)));
                          }).toList(),
                          rows: rows
                              .asMap()
                              .entries
                              .map((e) => DataRow(
                                    color: WidgetStateProperty.resolveWith((s) {
                                      if (s.contains(WidgetState.hovered))
                                        return _navy.withOpacity(0.04);
                                      return e.key % 2 == 0
                                          ? Colors.white
                                          : const Color(0xFFF8FAFC);
                                    }),
                                    onSelectChanged: (_) => _onRowTap(e.value),
                                    cells: _headers.map((h) {
                                      final v = e.value[h];
                                      return DataCell(SizedBox(
                                          width: colW,
                                          child: h.toLowerCase() == 'status'
                                              ? _statusBadge(
                                                  v?.toString() ?? '')
                                              : Text(_displayVal(h, v),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: _cellStyle(h, v))));
                                    }).toList(),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // Status badge
  Widget _statusBadge(String status) {
    final s = status.toUpperCase();
    Color bg, fg;
    if (s == 'PAID' ||
        s == 'APPROVED' ||
        s == 'BILLED' ||
        s == 'COMPLETED' ||
        s == 'ACTIVE' ||
        s == 'PUBLISHED') {
      bg = _green.withOpacity(0.12);
      fg = _green;
    } else if (s == 'OVERDUE' ||
        s == 'CANCELLED' ||
        s == 'VOID' ||
        s == 'REJECTED') {
      bg = _red.withOpacity(0.12);
      fg = _red;
    } else if (s == 'PARTIALLY_PAID' ||
        s == 'PARTIAL' ||
        s == 'OPEN' ||
        s == 'UNBILLED') {
      bg = _orange.withOpacity(0.12);
      fg = _orange;
    } else if (s == 'DRAFT' || s == 'PENDING') {
      bg = Colors.grey.withOpacity(0.15);
      fg = Colors.grey[600]!;
    } else if (s == 'SENT' || s == 'ISSUED') {
      bg = _blue.withOpacity(0.12);
      fg = _blue;
    } else {
      bg = _navy.withOpacity(0.08);
      fg = _navy;
    }
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(status,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: fg)));
  }

  TextStyle? _cellStyle(String h, dynamic v) {
    final hl = h.toLowerCase();
    if (hl.contains('amount') ||
        hl.contains('total') ||
        hl.contains('due') ||
        hl.contains('balance')) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n != null && n < 0)
        return const TextStyle(
            fontSize: 14, color: _red, fontWeight: FontWeight.w500);
      if (n != null && n > 0)
        return const TextStyle(
            fontSize: 14,
            color: Color(0xFF374151),
            fontWeight: FontWeight.w500);
    }
    if (h.toLowerCase() == 'status')
      return const TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    return null;
  }

  // ==========================================================================
  // RELATED REPORTS PANEL
  // ==========================================================================

  Widget _buildRelatedReports() {
    final related = _detailRelated[_detailKey];
    if (related == null || related.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                      color: _navy, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              const Text('Related Reports',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
            ])),
        GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 3.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10),
            itemCount: related.length,
            itemBuilder: (_, i) {
              final rel = related[i];
              final colors = [_navy, _blue, _green, _orange];
              final color = colors[i % colors.length];
              return InkWell(
                onTap: () => _openRelatedReport(rel),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                            color: color.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2))
                      ]),
                  child: Row(children: [
                    Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(6)),
                        child: Icon(Icons.description_outlined,
                            size: 15, color: color)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(rel['name'] ?? '',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 10, color: color.withOpacity(0.6)),
                  ]),
                ),
              );
            }),
      ]),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────
  Widget _buildError() => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.error_outline_rounded, size: 52, color: Colors.red[400]),
            const SizedBox(height: 12),
            Text('Failed to load details',
                style: TextStyle(fontSize: 17, color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text(_error ?? '',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)))),
          ])));

  // ── Widget helpers ─────────────────────────────────────────────────────────
  Widget _iconBtn(IconData icon, VoidCallback? onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: const Color(0xFFF1F1F1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!)),
          child: Icon(icon,
              size: 18,
              color:
                  onTap == null ? Colors.grey[300] : const Color(0xFF7F8C8D))));

  Widget _btn(String label, IconData icon, Color bg, VoidCallback? onTap) =>
      ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 14),
          label: Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: Colors.white,
              disabledBackgroundColor: bg.withOpacity(0.4),
              elevation: 0,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))));

  Widget _smBtn(String label, Color bg, VoidCallback? onTap) => ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withOpacity(0.4),
          elevation: 0,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
}
