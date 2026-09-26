import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// REPORT VIEWER PAGE — COMPLETE (Zoho Books exact functionality)
// ============================================================================
// File: lib/screens/billing/pages/report_viewer_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../app/config/api_config.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/finance_secure_storage.dart';
import '../../../../core/services/reports_service.dart';
import '../../../../core/services/tms_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'report_detail_page.dart';
import 'pl_expense_drilldown_page.dart';
import 'account_detail_page.dart';
import 'new_expenses.dart';
import 'new_invoice.dart';
import 'new_bill.dart';
import 'new_credit_note.dart';
import 'new_payment_page.dart';
import 'new_payment_made.dart';
import 'new_manual_journal.dart';

// ─── Scroll behaviour ────────────────────────────────────────────────────────
class _AllDeviceScroll extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

// ─── Colours ─────────────────────────────────────────────────────────────────
const _navy = Color(0xFF1E3A8A);
const _green = Color(0xFF27AE60);
const _blue = Color(0xFF2980B9);
const _orange = Color(0xFFE67E22);
const _red = Color(0xFFE74C3C);
const _teal = Color(0xFF1ABC9C);
const _purple = Color(0xFF9B59B6);

// ─── Periods ─────────────────────────────────────────────────────────────────
class _P {
  final String key, label;
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

enum _ChartType { bar, line, pie }

// ─── Report type classification ───────────────────────────────────────────────
const _financialStatementKeys = {
  'profit-loss',
  'balance-sheet',
  'cash-flow',
  'profit-loss-horizontal',
  'balance-sheet-horizontal',
  'movement-of-equity',
};

const _agingKeys = {
  'ar-aging-summary',
  'ap-aging-summary',
};

const _trialBalanceKeys = {
  'trial-balance',
  'account-transactions',
  'account-type-summary',
  'account-type-transactions',
  'day-book',
  'journal-report',
};

// ─── Related reports map ──────────────────────────────────────────────────────
const Map<String, List<Map<String, String>>> _relatedReports = {
  'profit-loss': [
    {'key': 'balance-sheet', 'name': 'Balance Sheet'},
    {'key': 'cash-flow', 'name': 'Cash Flow Statement'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'movement-of-equity', 'name': 'Movement of Equity'},
  ],
  'balance-sheet': [
    {'key': 'profit-loss', 'name': 'Profit and Loss'},
    {'key': 'cash-flow', 'name': 'Cash Flow Statement'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
  ],
  'cash-flow': [
    {'key': 'profit-loss', 'name': 'Profit and Loss'},
    {'key': 'balance-sheet', 'name': 'Balance Sheet'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
  ],
  'movement-of-equity': [
    {'key': 'balance-sheet', 'name': 'Balance Sheet'},
    {'key': 'profit-loss', 'name': 'Profit and Loss'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'journal-report', 'name': 'Journal Report'},
  ],
  'sales-by-customer': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
  ],
  'sales-by-item': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'purchases-by-item', 'name': 'Purchases by Item'},
    {'key': 'sales-by-customer', 'name': 'Sales by Customer'},
    {'key': 'sales-summary', 'name': 'Sales Summary'},
  ],
  'sales-by-salesperson': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'sales-by-customer', 'name': 'Sales by Customer'},
    {'key': 'sales-by-item', 'name': 'Sales by Item'},
    {'key': 'payments-received', 'name': 'Payments Received'},
  ],
  'sales-summary': [
    {'key': 'sales-by-customer', 'name': 'Sales by Customer'},
    {'key': 'sales-by-item', 'name': 'Sales by Item'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'receivable-summary', 'name': 'Receivable Summary'},
  ],
  'invoice-details': [
    {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'credit-note-details', 'name': 'Credit Note Details'},
  ],
  'ar-aging-summary': [
    {'key': 'ar-aging-details', 'name': 'AR Aging Details'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
    {'key': 'payments-received', 'name': 'Payments Received'},
  ],
  'ar-aging-details': [
    {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
    {'key': 'payments-received', 'name': 'Payments Received'},
  ],
  'customer-balance': [
    {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'sales-by-customer', 'name': 'Sales by Customer'},
  ],
  'receivable-summary': [
    {'key': 'receivable-details', 'name': 'Receivable Details'},
    {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
  ],
  'receivable-details': [
    {'key': 'receivable-summary', 'name': 'Receivable Summary'},
    {'key': 'ar-aging-details', 'name': 'AR Aging Details'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'payments-received', 'name': 'Payments Received'},
  ],
  'payments-received': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'credit-note-details', 'name': 'Credit Note Details'},
    {'key': 'refund-history', 'name': 'Refund History'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
  ],
  'credit-note-details': [
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'refund-history', 'name': 'Refund History'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
  ],
  'refund-history': [
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'credit-note-details', 'name': 'Credit Note Details'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
  ],
  'time-to-get-paid': [
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
  ],
  'vendor-balance': [
    {'key': 'ap-aging-summary', 'name': 'AP Aging Summary'},
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'payments-made', 'name': 'Payments Made'},
    {'key': 'purchases-by-vendor', 'name': 'Purchases by Vendor'},
  ],
  'ap-aging-summary': [
    {'key': 'ap-aging-details', 'name': 'AP Aging Details'},
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance Summary'},
    {'key': 'payments-made', 'name': 'Payments Made'},
  ],
  'ap-aging-details': [
    {'key': 'ap-aging-summary', 'name': 'AP Aging Summary'},
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance Summary'},
    {'key': 'payments-made', 'name': 'Payments Made'},
  ],
  'bill-details': [
    {'key': 'ap-aging-summary', 'name': 'AP Aging Summary'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance Summary'},
    {'key': 'payments-made', 'name': 'Payments Made'},
    {'key': 'purchase-order-details', 'name': 'Purchase Order Details'},
  ],
  'payments-made': [
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance Summary'},
    {'key': 'ap-aging-summary', 'name': 'AP Aging Summary'},
    {'key': 'vendor-credit-details', 'name': 'Vendor Credit Details'},
  ],
  'vendor-credit-details': [
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'payments-made', 'name': 'Payments Made'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance Summary'},
  ],
  'purchase-order-details': [
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'purchases-by-vendor', 'name': 'Purchases by Vendor'},
    {'key': 'purchases-by-item', 'name': 'Purchases by Item'},
    {'key': 'payable-summary', 'name': 'Payable Summary'},
  ],
  'purchases-by-vendor': [
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'purchase-order-details', 'name': 'Purchase Order Details'},
    {'key': 'purchases-by-item', 'name': 'Purchases by Item'},
    {'key': 'vendor-balance', 'name': 'Vendor Balance Summary'},
  ],
  'purchases-by-item': [
    {'key': 'purchases-by-vendor', 'name': 'Purchases by Vendor'},
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'sales-by-item', 'name': 'Sales by Item'},
    {'key': 'expense-details', 'name': 'Expense Details'},
  ],
  'expense-details': [
    {'key': 'expenses-by-category', 'name': 'Expenses by Category'},
    {'key': 'billable-expense-details', 'name': 'Billable Expense Details'},
    {'key': 'purchases-by-vendor', 'name': 'Purchases by Vendor'},
    {'key': 'tax-summary', 'name': 'Tax Summary'},
  ],
  'expenses-by-category': [
    {'key': 'expense-details', 'name': 'Expense Details'},
    {'key': 'billable-expense-details', 'name': 'Billable Expense Details'},
    {'key': 'expenses-by-customer', 'name': 'Expenses by Customer'},
    {'key': 'expenses-by-project', 'name': 'Expenses by Project'},
  ],
  'expenses-by-customer': [
    {'key': 'expense-details', 'name': 'Expense Details'},
    {'key': 'expenses-by-category', 'name': 'Expenses by Category'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'billable-expense-details', 'name': 'Billable Expense Details'},
  ],
  'expenses-by-project': [
    {'key': 'expense-details', 'name': 'Expense Details'},
    {'key': 'project-summary', 'name': 'Project Summary'},
    {'key': 'timesheet-details', 'name': 'Timesheet Details'},
    {'key': 'billable-expense-details', 'name': 'Billable Expense Details'},
  ],
  'expenses-by-employee': [
    {'key': 'expense-details', 'name': 'Expense Details'},
    {'key': 'expenses-by-category', 'name': 'Expenses by Category'},
    {'key': 'payments-made', 'name': 'Payments Made'},
  ],
  'billable-expense-details': [
    {'key': 'expense-details', 'name': 'Expense Details'},
    {'key': 'expenses-by-customer', 'name': 'Expenses by Customer'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'project-summary', 'name': 'Project Summary'},
  ],
  'tax-summary': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'bill-details', 'name': 'Bill Details'},
    {'key': 'expense-details', 'name': 'Expense Details'},
    {'key': 'profit-loss', 'name': 'Profit and Loss'},
  ],
  'reconciliation-status': [
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
  ],
  'general-ledger': [
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'journal-report', 'name': 'Journal Report'},
    {'key': 'day-book', 'name': 'Day Book'},
  ],
  'detailed-general-ledger': [
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'journal-report', 'name': 'Journal Report'},
  ],
  'trial-balance': [
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'balance-sheet', 'name': 'Balance Sheet'},
    {'key': 'profit-loss', 'name': 'Profit and Loss'},
  ],
  'account-transactions': [
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'journal-report', 'name': 'Journal Report'},
    {'key': 'day-book', 'name': 'Day Book'},
  ],
  'account-type-summary': [
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'account-type-transactions', 'name': 'Account Type Transactions'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
  ],
  'account-type-transactions': [
    {'key': 'account-type-summary', 'name': 'Account Type Summary'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
  ],
  'journal-report': [
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
    {'key': 'trial-balance', 'name': 'Trial Balance'},
    {'key': 'day-book', 'name': 'Day Book'},
  ],
  'day-book': [
    {'key': 'journal-report', 'name': 'Journal Report'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
  ],
  'project-summary': [
    {'key': 'project-details', 'name': 'Project Details'},
    {'key': 'timesheet-details', 'name': 'Timesheet Details'},
    {'key': 'projects-cost-summary', 'name': 'Projects Cost Summary'},
    {'key': 'projects-revenue-summary', 'name': 'Projects Revenue Summary'},
  ],
  'project-details': [
    {'key': 'project-summary', 'name': 'Project Summary'},
    {'key': 'timesheet-details', 'name': 'Timesheet Details'},
    {'key': 'timesheet-profitability', 'name': 'Timesheet Profitability'},
    {'key': 'expenses-by-project', 'name': 'Expenses by Project'},
  ],
  'timesheet-details': [
    {'key': 'project-summary', 'name': 'Project Summary'},
    {'key': 'timesheet-profitability', 'name': 'Timesheet Profitability'},
    {'key': 'expenses-by-project', 'name': 'Expenses by Project'},
    {'key': 'project-details', 'name': 'Project Details'},
  ],
  'timesheet-profitability': [
    {'key': 'timesheet-details', 'name': 'Timesheet Details'},
    {'key': 'project-summary', 'name': 'Project Summary'},
    {'key': 'projects-revenue-summary', 'name': 'Projects Revenue Summary'},
    {'key': 'projects-cost-summary', 'name': 'Projects Cost Summary'},
  ],
  'projects-cost-summary': [
    {'key': 'projects-revenue-summary', 'name': 'Projects Revenue Summary'},
    {
      'key': 'projects-performance-summary',
      'name': 'Projects Performance Summary'
    },
    {'key': 'project-summary', 'name': 'Project Summary'},
    {'key': 'expense-details', 'name': 'Expense Details'},
  ],
  'projects-revenue-summary': [
    {'key': 'projects-cost-summary', 'name': 'Projects Cost Summary'},
    {
      'key': 'projects-performance-summary',
      'name': 'Projects Performance Summary'
    },
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'project-summary', 'name': 'Project Summary'},
  ],
  'projects-performance-summary': [
    {'key': 'projects-cost-summary', 'name': 'Projects Cost Summary'},
    {'key': 'projects-revenue-summary', 'name': 'Projects Revenue Summary'},
    {'key': 'timesheet-details', 'name': 'Timesheet Details'},
    {'key': 'project-summary', 'name': 'Project Summary'},
  ],
  'realized-gain-loss': [
    {'key': 'unrealized-gain-loss', 'name': 'Unrealized Gain or Loss'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
  ],
  'unrealized-gain-loss': [
    {'key': 'realized-gain-loss', 'name': 'Realized Gain or Loss'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
    {'key': 'account-transactions', 'name': 'Account Transactions'},
  ],
  'activity-logs': [
    {'key': 'exception-report', 'name': 'Exception Report'},
    {'key': 'system-mails', 'name': 'System Mails'},
    {'key': 'portal-activities', 'name': 'Portal Activities'},
  ],
  'system-mails': [
    {'key': 'activity-logs', 'name': 'Activity Logs & Audit Trail'},
    {'key': 'exception-report', 'name': 'Exception Report'},
  ],
  'exception-report': [
    {'key': 'activity-logs', 'name': 'Activity Logs & Audit Trail'},
    {'key': 'system-mails', 'name': 'System Mails'},
    {'key': 'general-ledger', 'name': 'General Ledger'},
  ],
  'recurring-invoice-details': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'payments-received', 'name': 'Payments Received'},
    {'key': 'customer-balance', 'name': 'Customer Balance Summary'},
  ],
  'sales-order-details': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'sales-by-customer', 'name': 'Sales by Customer'},
    {'key': 'payments-received', 'name': 'Payments Received'},
  ],
  'quote-details': [
    {'key': 'sales-order-details', 'name': 'Sales Order Details'},
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'sales-by-customer', 'name': 'Sales by Customer'},
  ],
  'delivery-challan-details': [
    {'key': 'invoice-details', 'name': 'Invoice Details'},
    {'key': 'sales-order-details', 'name': 'Sales Order Details'},
  ],
};

// ─── Row drill-down target mapping ───────────────────────────────────────────
String _drillDownKey(String reportKey) {
  if (reportKey.contains('reconciliation')) return '';
  // Payable Summary is now a combined Bills/Vendor Credits/Expenses list in
  // its own right (matches Zoho's real definition) — it's already a details
  // level report, not a summary that drills further into bill-details.
  if (reportKey.contains('payable-summary')) return '';
  if (reportKey.contains('sales-by-customer') ||
      reportKey.contains('customer-balance') ||
      reportKey.contains('ar-aging') ||
      reportKey.contains('receivable')) return 'invoice-details';
  if (reportKey.contains('vendor-balance') ||
      reportKey.contains('purchases-by-vendor') ||
      reportKey.contains('ap-aging') ||
      reportKey.contains('payable')) return 'bill-details';
  if (reportKey.contains('sales-by-item') ||
      reportKey.contains('purchases-by-item')) return 'invoice-details';
  if (reportKey.contains('sales-by-salesperson')) return 'invoice-details';
  if (reportKey.contains('expenses-by-category') ||
      reportKey.contains('expenses-by-customer') ||
      reportKey.contains('expenses-by-project') ||
      reportKey.contains('expenses-by-employee')) return 'expense-details';
  if (reportKey.contains('project-summary') ||
      reportKey.contains('projects-cost') ||
      reportKey.contains('projects-revenue') ||
      reportKey.contains('projects-performance')) return 'project-details';
  if (reportKey.contains('account-type-summary'))
    return 'account-type-transactions';
  if (reportKey.contains('trial-balance') ||
      reportKey.contains('account-type-transactions'))
    return 'account-transactions';
  if (reportKey.contains('general-ledger') ||
      reportKey.contains('day-book') ||
      reportKey.contains('journal')) return 'account-transactions';
  return '';
}

// =============================================================================
class ReportViewerPage extends StatefulWidget {
  final ReportMeta report;
  final String orgName;
  final Map<String, String>? initialParams;
  const ReportViewerPage(
      {Key? key,
      required this.report,
      required this.orgName,
      this.initialParams})
      : super(key: key);
  @override
  State<ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<ReportViewerPage> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _rows = [];
  List<String> _headers = [];

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  String _periodKey = 'this_fy';
  DateTime? _fromDate;
  DateTime? _toDate;

  bool _chartMode = false;
  _ChartType _chartType = _ChartType.bar;

  String _search = '';
  final _searchCtrl = TextEditingController();
  final _bodyScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialParams != null) {
      if (widget.initialParams!.containsKey('period')) {
        _periodKey = widget.initialParams!['period']!;
      } else if (widget.initialParams!.containsKey('fromDate') || widget.initialParams!.containsKey('toDate')) {
        _periodKey = 'custom';
      }
      if (widget.initialParams!.containsKey('fromDate')) {
        _fromDate = DateTime.tryParse(widget.initialParams!['fromDate']!);
      }
      if (widget.initialParams!.containsKey('toDate')) {
        _toDate = DateTime.tryParse(widget.initialParams!['toDate']!);
      }
    }
    if (widget.initialParams?.containsKey('search') == true) {
      _searchCtrl.text = widget.initialParams!['search']!;
      _search = _searchCtrl.text.toLowerCase();
    }
    _searchCtrl.addListener(
        () => setState(() => _search = _searchCtrl.text.toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  bool get _isFinancial => _financialStatementKeys.contains(widget.report.key);
  bool get _isAging => _agingKeys.contains(widget.report.key);
  bool get _isTrialBal => _trialBalanceKeys.contains(widget.report.key);

  Map<String, String> get _params {
    final p = <String, String>{};
    if (widget.initialParams != null) {
      p.addAll(widget.initialParams!);
    }
    if (widget.report.accountId != null)
      p['accountId'] = widget.report.accountId!;
    if (_periodKey != 'custom') {
      p['period'] = _periodKey;
      p.remove('fromDate');
      p.remove('toDate');
      return p;
    }
    p.remove('period');
    if (_fromDate != null) p['fromDate'] = _fromDate!.toIso8601String();
    if (_toDate != null) p['toDate'] = _toDate!.toIso8601String();
    return p;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      debugPrint(
          '📊 [REPORT] Loading: ${widget.report.key} | params: $_params');
      final d = await ReportsService.fetchReport(widget.report.key, _params);
      debugPrint('📊 [REPORT] Raw data keys: ${d.keys.toList()}');
      debugPrint(
          '📊 [REPORT] Raw data: ${d.toString().substring(0, d.toString().length.clamp(0, 500))}');

      if (d != null &&
          d['success'] == true &&
          _periodKey == 'custom' &&
          d['data']?['period'] != null) {
        try {
          if (_fromDate == null && d['data']['period']['start'] != null) {
            _fromDate = DateTime.parse(d['data']['period']['start'].toString());
          }
          if (_toDate == null && d['data']['period']['end'] != null) {
            _toDate = DateTime.parse(d['data']['period']['end'].toString());
          }
        } catch (_) {}
      }

      _parse(d);
      debugPrint(
          '📊 [REPORT] After parse → _rows.length=${_rows.length} | _headers=$_headers');
      if (_rows.isEmpty) {
        debugPrint(
            '⚠️ [REPORT] _rows is EMPTY after parse! Checking data keys for lists:');
        d.forEach((k, v) {
          if (v is List)
            debugPrint('  → "$k" is List with ${(v as List).length} items');
          else if (v is Map)
            debugPrint(
                '  → "$k" is Map with keys: ${(v as Map).keys.toList()}');
          else
            debugPrint('  → "$k" = $v');
        });
      }
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('❌ [REPORT] Load error: $e\n$st');
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _parse(Map<String, dynamic> d) {
    _rows = [];
    _headers = [];
    if (_isFinancial) return;

    // ── Performance Ratios: flat object → single-section rows ────────────────
    if (widget.report.key == 'performance-ratios') {
      _headers = ['Metric', 'Value'];
      _rows = [
        {'Metric': 'Total Revenue', 'Value': d['totalRevenue'] ?? 0},
        {'Metric': 'Total Expenses', 'Value': d['totalExpenses'] ?? 0},
        {'Metric': 'Net Profit', 'Value': d['netProfit'] ?? 0},
        {
          'Metric': 'Gross Profit Margin',
          'Value': '${d['grossProfitMargin'] ?? 0}%'
        },
        {
          'Metric': 'Net Profit Margin',
          'Value': '${d['netProfitMargin'] ?? 0}%'
        },
        {'Metric': 'Return on Assets', 'Value': '${d['returnOnAssets'] ?? 0}%'},
        {'Metric': 'Return on Equity', 'Value': '${d['returnOnEquity'] ?? 0}%'},
        {
          'Metric': 'Debt to Equity Ratio',
          'Value': d['debtToEquityRatio'] ?? 0
        },
        {'Metric': 'Current Ratio', 'Value': d['currentRatio'] ?? 0},
      ];
      return;
    }

    // ── TCS Summary: flat object → single-section rows ────────────────────
    if (widget.report.key == 'tcs-summary') {
      _headers = ['Metric', 'Value'];
      _rows = [
        {'Metric': 'TCS from Sales', 'Value': d['tcsFromSales'] ?? 0},
        {'Metric': 'TCS from Purchases', 'Value': d['tcsFromPurchases'] ?? 0},
        {'Metric': 'Sales Count', 'Value': d['salesCount'] ?? 0},
        {'Metric': 'Purchases Count', 'Value': d['purchasesCount'] ?? 0},
        {'Metric': 'Net TCS', 'Value': d['netTCS'] ?? 0},
      ];
      return;
    }

    // ── General Ledger: flatten accounts[].transactions into flat rows ────
    final rk = widget.report.key;
    debugPrint('🔍 [PARSE] report=$rk | top-level keys=${d.keys.toList()}');

    if (rk == 'general-ledger' || rk == 'general-ledger-detailed') {
      final accounts = d['accounts'];
      if (accounts is List && accounts.isNotEmpty) {
        final flat = <Map<String, dynamic>>[];
        for (final acc in accounts) {
          if (acc is! Map) continue;
          final txns = acc['transactions'];
          if (txns is List && txns.isNotEmpty) {
            // Header row for the account
            flat.add({
              'accountCode': acc['accountCode'] ?? '',
              'accountName': acc['accountName'] ?? '',
              'accountType': acc['accountType'] ?? '',
              'date': '',
              'description': '',
              'referenceType': '',
              'referenceNumber': '',
              'debit': '',
              'credit': '',
              'balance': '',
              'accountId': acc['accountId'],
              '_isAccountHeader': true,
            });
            for (final t in txns) {
              if (t is Map) {
                flat.add({
                  'accountCode': '',
                  'accountName': acc['accountName'] ?? '',
                  'accountType': '',
                  'date': t['date'] ?? '',
                  'description': t['description'] ?? '',
                  'referenceType': t['referenceType'] ?? '',
                  'referenceNumber': t['referenceNumber'] ?? '',
                  'debit': t['debit'] ?? 0,
                  'credit': t['credit'] ?? 0,
                  'balance': t['balance'] ?? 0,
                  'accountId': acc['accountId'],
                });
              }
            }
          }
        }
        if (flat.isNotEmpty) {
          _headers = [
            'accountCode',
            'accountName',
            'date',
            'description',
            'referenceType',
            'referenceNumber',
            'debit',
            'credit',
            'balance'
          ];
          _rows = flat;
          return;
        }
      }
    }

    const listKeys = [
      'customers',
      'vendors',
      'salespersons',
      'items',
      'invoices',
      'bills',
      'payments',
      'refunds',
      'expenses',
      'categories',
      'transactions',
      'creditNotes',
      'vendorCredits',
      'journals',
      'logs',
      'dailySummary',
      'buckets',
      'accountTypes',
      'accounts',
      'projects',
      'entries',
      'profiles',
      'purchaseOrders',
      'employees',
      'reconciliations',
      'mails',
      'activities',
      'exceptions',
      'reviews',
      'rows',
      'timesheets',
      'byStatus',
    ];

    List<dynamic>? list;
    for (final k in listKeys) {
      if (d[k] is List && (d[k] as List).isNotEmpty) {
        debugPrint(
            '🔍 [PARSE] Found list under key "$k" with ${(d[k] as List).length} items');
        list = d[k];
        break;
      }
    }
    if (list == null && d['data'] is List && (d['data'] as List).isNotEmpty) {
      debugPrint('🔍 [PARSE] Found list under fallback key "data"');
      list = d['data'] as List;
    }
    if (list == null) {
      debugPrint(
          '⚠️ [PARSE] No list found in any known key! Keys checked: $listKeys');
    }

    if (list != null) {
      final hSet = <String>{};
      bool hasLinks = false;
      for (final r in list) {
        if (r is Map) {
          if (r.containsKey('atId') || r.containsKey('btId')) hasLinks = true;
          hSet.addAll(r.keys.cast<String>().where((k) =>
              !k.startsWith('_') &&
              k != 'id' &&
              k != 'atId' &&
              k != 'atType' &&
              k != 'btId' &&
              k != 'bankAccountId' &&
              r[k] is! List &&
              r[k] is! Map));
        }
      }
      _headers = hSet.toList();
      if (hasLinks) {
        _headers.add('links');
      }
      _rows = list.map<Map<String, dynamic>>((r) {
        if (r is Map<String, dynamic>) return r;
        if (r is Map) return Map<String, dynamic>.from(r);
        return {'value': r.toString()};
      }).toList();
    }
  }

  List<Map<String, dynamic>> get _filtered {
    Iterable<Map<String, dynamic>> result = _rows;

    if (_search.isNotEmpty) {
      result = result.where((r) =>
          r.values.any((v) => v.toString().toLowerCase().contains(_search)));
    }
    
    // Apply local date filtering for non-financial reports
    if (!_isFinancial && _periodKey != 'all' && _fromDate != null && _toDate != null) {
      result = result.where((r) {
        // Find a suitable date field in the row
        String? dateStr;
        if (r.containsKey('date') && r['date'] != null) dateStr = r['date'].toString();
        else if (r.containsKey('invoiceDate') && r['invoiceDate'] != null) dateStr = r['invoiceDate'].toString();
        else if (r.containsKey('billDate') && r['billDate'] != null) dateStr = r['billDate'].toString();
        else if (r.containsKey('createdAt') && r['createdAt'] != null) dateStr = r['createdAt'].toString();
        else if (r.containsKey('paymentDate') && r['paymentDate'] != null) dateStr = r['paymentDate'].toString();
        
        if (dateStr == null || dateStr.isEmpty) return true; // Keep if no date field
        
        try {
          final d = DateTime.parse(dateStr).toLocal();
          // Reset time parts for accurate day comparison
          final rDate = DateTime(d.year, d.month, d.day);
          final sDate = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
          final eDate = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
          return rDate.isAtSameMomentAs(sDate) || rDate.isAtSameMomentAs(eDate) || (rDate.isAfter(sDate) && rDate.isBefore(eDate));
        } catch (_) {
          return true;
        }
      });
    }

    return result.toList();
  }

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
        return DateFormat('dd MMM yyyy').format(DateTime.parse(s).toLocal());
      } catch (_) {}
    }
    final hl = h.toLowerCase();
    if ((hl.contains('day') || hl.contains('bucket')) && !hl.contains('1-15') && !hl.contains('16-30') && !hl.contains('31-45') && !hl.contains('45 days')) return s; // Prevent formatting 'Days Overdue' as currency
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
        hl.contains('loss') ||
        hl.contains('budget') ||
        hl.contains('1-15') ||
        hl.contains('16-30') ||
        hl.contains('31-45') ||
        hl.contains('45 days') ||
        hl.contains('rate') ||
        hl.contains('price') ||
        hl.contains('billed') ||
        hl.contains('invoiced') ||
        hl.contains('billed')) {
      final n = double.tryParse(
          s.replaceAll(',', '').replaceAll('Rs. ', '').replaceAll('Rs.', ''));
      if (n != null) return 'Rs. ${n.toStringAsFixed(2)}';
    }
    return s;
  }

  // ── Date pickers ───────────────────────────────────────────────────────────
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

  // ── Exports ────────────────────────────────────────────────────────────────
  Future<void> _exportPDF(
      {List<Map<String, dynamic>>? customRows,
      List<String>? customHeaders}) async {
    final rows = customRows ?? (_isFinancial ? _flattenFinancial() : _filtered);
    final rawHeaders = customHeaders ??
        (_isFinancial && rows.isNotEmpty
            ? rows.first.keys.where((k) => !k.startsWith('_')).toList()
            : _headers);
    if (rows.isEmpty && !_isFinancial) {
      _snackErr('No data to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      final period = _data?['period'] ?? _data?['data']?['period'];
      final asOf = _data?['asOf'] ?? _data?['data']?['asOf'];
      String pl = '';
      if (period is Map) {
        try {
          final s = period['start'] != null
              ? DateFormat('dd MMM yyyy')
                  .format(DateTime.parse(period['start'].toString()).toLocal())
              : '';
          final e = period['end'] != null
              ? DateFormat('dd MMM yyyy')
                  .format(DateTime.parse(period['end'].toString()).toLocal())
              : '';
          if (s.isNotEmpty || e.isNotEmpty) pl = '$s – $e';
        } catch (_) {}
      } else if (asOf != null) {
        try {
          final d = DateFormat('dd MMM yyyy')
              .format(DateTime.parse(asOf.toString()).toLocal());
          pl = 'As of $d';
        } catch (_) {}
      }

        Uint8List? logoBytes;
        String? orgAddress;
        String? orgPhone;
        String? orgGst;
        String? profileLogoUrl;
        try {
          final profileRes = await ApiService().get('/api/finance/auth/org-profile');
          if (profileRes['success'] == true && profileRes['data'] != null) {
            final data = profileRes['data'];
            orgAddress = data['address']?.toString();
            orgPhone = data['phone']?.toString();
            orgGst = data['gstNumber']?.toString();
            profileLogoUrl = data['logoUrl']?.toString();
          }

          String? logoUrl = profileLogoUrl;
          if (logoUrl == null || logoUrl.isEmpty) {
            logoUrl = await FinanceSecureStorage.getOrgLogoUrl();
          }

          if (logoUrl != null && logoUrl.isNotEmpty) {
            final fullUrl = logoUrl.startsWith('http') 
                ? logoUrl 
                : '${ApiConfig.baseUrl}${logoUrl.startsWith('/') ? logoUrl : '/$logoUrl'}';
            final response = await http.get(Uri.parse(fullUrl));
            if (response.statusCode == 200) {
              logoBytes = response.bodyBytes;
            } else {
              print('Failed to fetch logo. Status: ${response.statusCode}, URL: $fullUrl');
            }
          }
        } catch (e) {
          print('Error fetching org details for PDF: $e');
        }

        final visibleHeaders = rawHeaders.where((h) => h != '_isAccountHeader').toList();
        await ExportHelper.exportToPDF(
          title: [
            widget.report.name,
            if (pl.isNotEmpty) pl
          ].join('\n'),
          orgName: widget.orgName.isNotEmpty ? widget.orgName : null,
          orgLogoBytes: logoBytes,
          orgAddress: orgAddress,
          orgPhone: orgPhone,
          orgGst: orgGst,
          headers: rawHeaders.map(_colLabel).toList(),
          data: rows
            .where((r) => r['_isAccountHeader'] != true)
            .map((r) => rawHeaders
                .map((h) => _displayVal(h, r[h]).replaceAll('Rs. ', 'Rs.'))
                .toList())
            .toList(),
        filename: widget.report.name.replaceAll(' ', '_'),
      );
      _snackOk('PDF downloaded');
    } catch (e) {
      _snackErr('PDF failed: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel(
      {List<Map<String, dynamic>>? customRows,
      List<String>? customHeaders}) async {
    final rows = customRows ?? (_isFinancial ? _flattenFinancial() : _filtered);
    final rawHeaders = customHeaders ??
        (_isFinancial && rows.isNotEmpty
            ? rows.first.keys.where((k) => !k.startsWith('_')).toList()
            : _headers);
    if (rows.isEmpty && !_isFinancial) {
      _snackErr('No data to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      final period = _data?['period'];
      Map<String, dynamic>? periodMap;
      if (period is Map) periodMap = Map<String, dynamic>.from(period);
      await ReportsService.exportExcel(
        reportName: widget.report.name,
        companyName: widget.orgName,
        reportData: rows.where((r) => r['_isAccountHeader'] != true).map((r) {
          final formatted = <String, dynamic>{};
          for (final h in rawHeaders) {
            formatted[_colLabel(h)] = _displayVal(h, r[h]);
          }
          return formatted;
        }).toList(),
        period: periodMap,
        headers: rawHeaders.map(_colLabel).toList(),
      );
      _snackOk('Excel downloaded');
    } catch (e) {
      _snackErr('Excel failed: $e');
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<void> _share() async {
    final text =
        '${widget.report.name}\n${widget.orgName.isNotEmpty ? "Company: ${widget.orgName}\n" : ""}Records: ${_filtered.length}\n\nGenerated from Abra Finance';
    try {
      await Share.share(text, subject: widget.report.name);
    } catch (e) {
      _snackErr('Share failed: $e');
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

  // ── Row drill-down ─────────────────────────────────────────────────────────
  void _onRowTap(Map<String, dynamic> row) {
    if (row['_isAccountHeader'] == true) return;
    final dk = _drillDownKey(widget.report.key);
    if (dk.isEmpty) {
      _viewRowDialog(row);
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReportDetailPage(
                parentReport: widget.report,
                rowData: row,
                orgName: widget.orgName,
                periodParams: _params)));
  }

  void _viewRowDialog(Map<String, dynamic> row) {
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
                        const Icon(Icons.visibility_outlined,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Record Details',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold))),
                        IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                            padding: EdgeInsets.zero),
                      ])),
                  Flexible(
                      child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: row.entries
                              .where((e) => !e.key.startsWith('_'))
                              .map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                            width: 160,
                                            child: Text(_colLabel(e.key),
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: _navy))),
                                        Expanded(
                                            child: Text(
                                                _displayVal(e.key, e.value),
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Color(0xFF374151)))),
                                      ])))
                              .toList())),
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
                            _exportPDF(
                              customRows: [row],
                              customHeaders: row.keys
                                  .where((k) => !k.startsWith('_'))
                                  .toList(),
                            );
                          },
                          icon: const Icon(Icons.picture_as_pdf_rounded,
                              size: 15),
                          label: const Text('PDF',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _red,
                            side: const BorderSide(color: _red),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _onRowTap(row);
                          },
                          icon: const Icon(Icons.open_in_new_rounded, size: 15),
                          label: const Text('Details',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ));
  }

  // ── Ticket dialog ──────────────────────────────────────────────────────────
  void _raiseTicket() => showDialog(
      context: context,
      builder: (_) => _TicketDialog(
          reportName: widget.report.name,
          orgName: widget.orgName,
          onSuccess: _snackOk,
          onError: _snackErr));

  // ── Navigate to related report ─────────────────────────────────────────────
  void _openRelatedReport(Map<String, String> rel) async {
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
    if (target == null) {
      target = ReportMeta(key: rel['key']!, name: rel['name']!);
    }
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) =>
                ReportViewerPage(report: target!, orgName: widget.orgName)));
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: widget.report.name),
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
        if (c.maxWidth >= 900) return _topDesktop();
        if (c.maxWidth >= 600) return _topTablet();
        return _topMobile();
      }),
    );
  }

  Widget _topDesktop() => Row(children: [
        _searchBox(220),
        const SizedBox(width: 8),
        _iconBtn(Icons.refresh_rounded, _loading ? null : _load),
        const Spacer(),
        if (widget.orgName.isNotEmpty) ...[
          Text(widget.orgName,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _navy)),
          const SizedBox(width: 14),
        ],
        if (!_isFinancial) ...[_toggleView(), const SizedBox(width: 10)],
        _btn('PDF', Icons.picture_as_pdf_rounded, _red,
            _exporting ? null : _exportPDF),
        const SizedBox(width: 6),
        _btn('Excel', Icons.table_chart_rounded, _green,
            _exporting ? null : _exportExcel),
        const SizedBox(width: 6),
        _btn('Share', Icons.share_rounded, _blue, _share),
        const SizedBox(width: 6),
        _btn(
            'Ticket', Icons.confirmation_number_rounded, _orange, _raiseTicket),
      ]);

  Widget _topTablet() => Column(children: [
        Row(children: [
          Expanded(child: _searchBox(double.infinity)),
          const SizedBox(width: 8),
          _iconBtn(Icons.refresh_rounded, _loading ? null : _load)
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              if (!_isFinancial) ...[_toggleView(), const SizedBox(width: 10)],
              _btn('PDF', Icons.picture_as_pdf_rounded, _red,
                  _exporting ? null : _exportPDF),
              const SizedBox(width: 6),
              _btn('Excel', Icons.table_chart_rounded, _green,
                  _exporting ? null : _exportExcel),
              const SizedBox(width: 6),
              _btn('Share', Icons.share_rounded, _blue, _share),
              const SizedBox(width: 6),
              _btn('Ticket', Icons.confirmation_number_rounded, _orange,
                  _raiseTicket),
            ])),
      ]);

  Widget _topMobile() => Column(children: [
        _searchBox(double.infinity),
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _iconBtn(Icons.refresh_rounded, _loading ? null : _load),
              const SizedBox(width: 6),
              if (!_isFinancial) ...[_toggleView(), const SizedBox(width: 6)],
              _smBtn('PDF', _red, _exporting ? null : _exportPDF),
              const SizedBox(width: 6),
              _smBtn('Excel', _green, _exporting ? null : _exportExcel),
              const SizedBox(width: 6),
              _smBtn('Share', _blue, _share),
              const SizedBox(width: 6),
              _smBtn('Ticket', _orange, _raiseTicket),
            ])),
      ]);

  // ── Filter bar ─────────────────────────────────────────────────────────────
  Widget _buildFilterBar() {
    final label = _periods
        .firstWhere((p) => p.key == _periodKey,
            orElse: () => const _P('custom', 'Custom Range'))
        .label;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: LayoutBuilder(builder: (_, constraints) {
        // On narrow screens wrap everything in horizontal scroll so nothing is cut off
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
          if (_chartMode && !_isFinancial) ...[
            const SizedBox(width: 8),
            _chartTypePicker()
          ],
        ]);

        if (isNarrow) {
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: content);
        }
        return Row(children: [Expanded(child: content)]);
      }),
    );
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
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? _navy : Colors.grey[600])),
          ])));

  Widget _chartTypePicker() => Container(
        height: 34,
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDE3EE))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _ctBtn(_ChartType.bar, Icons.bar_chart_rounded, 'Bar'),
          _ctBtn(_ChartType.line, Icons.show_chart_rounded, 'Line'),
          _ctBtn(_ChartType.pie, Icons.pie_chart_rounded, 'Pie'),
        ]),
      );

  Widget _ctBtn(_ChartType t, IconData icon, String label) {
    final active = _chartType == t;
    return GestureDetector(
        onTap: () => setState(() => _chartType = t),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: active ? _navy : Colors.transparent,
                borderRadius: BorderRadius.circular(7)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 14, color: active ? Colors.white : Colors.grey[500]),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : Colors.grey[500])),
            ])));
  }

  // ==========================================================================
  // BODY — all content + related reports
  // ==========================================================================

  Widget _buildBody() {
    return ScrollConfiguration(
      behavior: _AllDeviceScroll(),
      child: SingleChildScrollView(
        controller: _bodyScroll,
        child: Column(children: [
          // Summary cards (for non-financial)
          if (!_isFinancial && !_loading) _buildSummaryCards(),

          // Report header (printed-doc style for financial)
          if (_isFinancial) _buildReportHeader(),

          // Main content area
          if (_isFinancial)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.65,
              child: _buildFinancialStatement(),
            )
          else if (_chartMode)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: _buildChartView(),
            )
          else
            _ListTableWidget(
              rows: _filtered,
              headers: _headers,
              search: _search,
              exporting: _exporting,
              onRowTap: _onRowTap,
              colLabel: _colLabel,
              displayVal: _displayVal,
              cellStyle: _cellStyle,
              statusBadge: _statusBadge,
            ),

          // Export buttons for financial reports
          if (_isFinancial) _buildFinancialExportBar(),

          // Related Reports Panel
          _buildRelatedReports(),

          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  double _contentHeight() {
    final screenH = MediaQuery.of(context).size.height;
    if (_isFinancial) return screenH * 0.65;
    if (_rows.isEmpty) return 300;
    final rowH =
        _rows.length <= 10 ? (_rows.length * 56.0 + 100) : screenH * 0.55;
    return rowH.clamp(300, screenH * 0.65);
  }

  // ── Report printed header ──────────────────────────────────────────────────
  Widget _buildReportHeader() {
    final period = _data?['period'] ?? _data?['data']?['period'];
    final asOf = _data?['asOf'] ?? _data?['data']?['asOf'];
    String pl = '';
    if (period is Map) {
      try {
        final s = period['start'] != null
            ? DateFormat('dd MMM yyyy')
                .format(DateTime.parse(period['start'].toString()).toLocal())
            : '';
        final e = period['end'] != null
            ? DateFormat('dd MMM yyyy')
                .format(DateTime.parse(period['end'].toString()).toLocal())
            : '';
        if (s.isNotEmpty || e.isNotEmpty) pl = '$s – $e';
      } catch (_) {}
    } else if (asOf != null) {
      try {
        final d = DateFormat('dd MMM yyyy')
            .format(DateTime.parse(asOf.toString()).toLocal());
        pl = 'As of $d';
      } catch (_) {}
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ]),
      child: Column(children: [
        if (widget.orgName.isNotEmpty) ...[
          Text(widget.orgName,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
          const SizedBox(height: 4),
        ],
        Text(widget.report.name,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        if (pl.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(pl, style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ]),
    );
  }

  // ── Summary cards ──────────────────────────────────────────────────────────
  Widget _buildSummaryCards() {
    dynamic totals = _data?['totals'] ?? _data?['total'];
    if (totals == null) return const SizedBox.shrink();

    // Recalculate totals if filtering is active
    if (_rows.isNotEmpty && _filtered.length != _rows.length) {
      if (totals is Map) {
        final newTotals = Map<String, dynamic>.from(totals);
        if (newTotals.containsKey('count')) {
          newTotals['count'] = _filtered.length;
        }
        newTotals.forEach((k, v) {
          if (k == 'count') return;
          String? rowKey;
          if (_rows.first.containsKey('total')) rowKey = 'total';
          else if (_rows.first.containsKey('amount')) rowKey = 'amount';
          else if (_rows.first.containsKey(k)) rowKey = k;
          
          if (rowKey != null) {
            double sum = 0.0;
            for (final r in _filtered) {
              final val = r[rowKey];
              if (val != null) {
                final s = val.toString().replaceAll(RegExp(r'[^\d.\-]'), '');
                sum += double.tryParse(s) ?? 0.0;
              }
            }
            newTotals[k] = sum.toStringAsFixed(2);
          }
        });
        totals = newTotals;
      } else if (totals is num || totals is String) {
        String? rowKey;
        if (_rows.first.containsKey('total')) rowKey = 'total';
        else if (_rows.first.containsKey('amount')) rowKey = 'amount';
        
        if (rowKey != null) {
          double sum = 0.0;
          for (final r in _filtered) {
            final val = r[rowKey];
            if (val != null) {
              final s = val.toString().replaceAll(RegExp(r'[^\d.\-]'), '');
              sum += double.tryParse(s) ?? 0.0;
            }
          }
          totals = sum.toStringAsFixed(2);
        }
      }
    }

    final items = <Map<String, String>>[];
    if (totals is Map) {
      totals.forEach((k, v) {
        if (v != null)
          items.add({'label': _colLabel(k.toString()), 'value': v.toString()});
      });
    } else if (totals is num || totals is String) {
      double n = double.tryParse(totals.toString()) ?? 0.0;
      items.add({'label': 'Total', 'value': n.toStringAsFixed(2)});
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
                    border: Border.all(color: color.withOpacity(0.22)),
                    boxShadow: [
                      BoxShadow(
                          color: color.withOpacity(0.07),
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
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ]));
          }).toList())),
    );
  }

  // ==========================================================================
  // FINANCIAL STATEMENT RENDERER (P&L, Balance Sheet, Cash Flow, MOE)
  // ==========================================================================

  Widget _buildFinancialStatement() {
    if (_data == null) return const Center(child: Text('No data'));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ]),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _buildFinancialContent(),
        ),
      ),
    );
  }

  Widget _buildFinancialContent() {
    switch (widget.report.key) {
      case 'profit-loss':
        return _buildPL(_data!);
      case 'balance-sheet':
        return _buildBS(_data!);
      case 'cash-flow':
        return _buildCF(_data!);
      case 'profit-loss-horizontal':
        return _buildPLH(_data!);
      case 'balance-sheet-horizontal':
        return _buildBSH(_data!);
      case 'movement-of-equity':
        return _buildMOE(_data!);
      default:
        return const Text('Layout not defined for this report');
    }
  }

  Widget _buildFinancialExportBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        _btn('Export PDF', Icons.picture_as_pdf_rounded, _red,
            _exporting ? null : _exportPDF),
        _btn('Export Excel', Icons.table_chart_rounded, _green,
            _exporting ? null : _exportExcel),
        _btn('Share', Icons.share_rounded, _blue, _share),
      ]),
    );
  }

  // P&L
  Widget _buildPL(Map<String, dynamic> d) {
    final income = d['income'] as Map? ?? {};
    final cogs = d['costOfGoods'] as Map? ?? {};
    final opEx = d['operatingExpenses'] as Map? ?? {};
    final nonOpInc = d['nonOperatingIncome'] as Map? ?? {};
    final nonOpEx = d['nonOperatingExpenses'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fsSecHead('Operating Income', _green),
      ..._fsItems(income['items'], 'income'),
      _fsSubtotal('Total for Operating Income', income['total']),
      const SizedBox(height: 16),
      _fsSecHead('Cost of Goods Sold', _orange),
      ..._fsItems(cogs['items'], 'cogs'),
      _fsSubtotal('Total for Cost of Goods Sold', cogs['total']),
      const SizedBox(height: 8),
      _fsGrossRow('Gross Profit', d['grossProfit']),
      const SizedBox(height: 16),
      _fsSecHead('Operating Expenses', _red),
      ..._fsItems(opEx['items'], 'opex'),
      _fsSubtotal('Total for Operating Expenses', opEx['total']),
      if (d.containsKey('operatingProfit')) ...[
        const SizedBox(height: 8),
        _fsGrossRow('Operating Profit', d['operatingProfit']),
      ],
      if ((nonOpInc['items'] as List? ?? []).isNotEmpty) ...[
        const SizedBox(height: 16),
        _fsSecHead('Non Operating Income', _blue),
        ..._fsItems(nonOpInc['items'], 'noninc'),
        _fsSubtotal('Total for Non Operating Income', nonOpInc['total']),
      ],
      if ((nonOpEx['items'] as List? ?? []).isNotEmpty) ...[
        const SizedBox(height: 16),
        _fsSecHead('Non Operating Expense', _purple),
        ..._fsItems(nonOpEx['items'], 'nonex'),
        _fsSubtotal('Total for Non Operating Expense', nonOpEx['total']),
      ],
      const Divider(height: 28, thickness: 1, color: Color(0xFFE2E8F0)),
      _fsNetRow('Net Profit / Loss', d['netProfit']),
    ]);
  }

  // Balance Sheet
  Widget _buildBS(Map<String, dynamic> d) {
    final tree = d['nestedTree'] as Map? ?? {};
    if (tree.isEmpty)
      return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No balance sheet data available.'));

    final assets = tree['assets'] as Map? ?? {};
    final liabs = tree['liabilities'] as Map? ?? {};
    final eqs = tree['equities'] as Map? ?? {};

    Widget header(String title, int depth) => Padding(
        padding: EdgeInsets.only(left: 12.0 + (depth * 16), top: 12, bottom: 6),
        child: Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))));

    Widget itemRow(Map item, int depth) => InkWell(
        onTap: () => _openAccountTransactions(item),
        child: Padding(
            padding: EdgeInsets.only(
                left: 12.0 + (depth * 16), top: 6, bottom: 6, right: 12),
            child: Row(children: [
              Expanded(
                  child: Text(item['accountName']?.toString() ?? '',
                      style: const TextStyle(fontSize: 15, color: _blue))),
              Text('Rs. ${_fmtNum(item['amount'] ?? 0)}',
                  style:
                      const TextStyle(fontSize: 15, color: Color(0xFF374151))),
            ])));

    Widget subtotal(String title, dynamic total, int depth) => Padding(
        padding: EdgeInsets.only(
            left: 12.0 + (depth * 16), top: 6, bottom: 12, right: 12),
        child: Row(children: [
          Expanded(
              child: Text('Total for $title',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF374151)))),
          Text('Rs. ${_fmtNum(total)}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151))),
        ]));

    Widget renderGroup(Map group, String title, int depth) {
      final items = group['items'] as List? ?? [];
      if (items.isEmpty && group['total'] == 0) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header(title, depth),
        ...items.map((i) => itemRow(i, depth + 1)),
        subtotal(title, group['total'], depth)
      ]);
    }

    Widget renderCashBank(Map group, int depth) {
      final cash = group['cash'] as List? ?? [];
      final bank = group['bank'] as List? ?? [];
      if (cash.isEmpty && bank.isEmpty) return const SizedBox.shrink();
      final c = <Widget>[header('Cash and Cash Equivalents', depth)];
      if (cash.isNotEmpty) {
        c.add(header('Cash', depth + 1));
        c.addAll(cash.map((i) => itemRow(i, depth + 2)));
        c.add(subtotal('Cash',
            cash.fold(0.0, (s, i) => s + (i['amount'] as num)), depth + 1));
      }
      if (bank.isNotEmpty) {
        c.add(header('Bank', depth + 1));
        c.addAll(bank.map((i) => itemRow(i, depth + 2)));
        c.add(subtotal('Bank',
            bank.fold(0.0, (s, i) => s + (i['amount'] as num)), depth + 1));
      }
      c.add(subtotal('Cash and Cash Equivalents', group['total'], depth));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: c);
    }

    Widget renderCurrentLiabilities(Map cl, int depth) {
      final ap = cl['accountsPayable'] as Map? ?? {};
      final ocl = cl['otherCurrentLiabilities'] as Map? ?? {};
      if (cl['total'] == 0 &&
          (ap['items'] as List? ?? []).isEmpty &&
          (ocl['items'] as List? ?? []).isEmpty) return const SizedBox.shrink();

      final c = <Widget>[header('Current Liabilities', depth)];
      if ((ap['items'] as List? ?? []).isNotEmpty || ap['total'] != 0) {
        c.add(renderGroup(ap, 'Accounts Payable', depth + 1));
      }

      final oclItems = ocl['items'] as List? ?? [];
      final gst = ocl['gstPayable'] as Map? ?? {};
      if (oclItems.isNotEmpty ||
          (gst['items'] as List? ?? []).isNotEmpty ||
          ocl['total'] != 0) {
        c.add(header('Other Current Liabilities', depth + 1));
        c.addAll(oclItems.map((i) => itemRow(i, depth + 2)));
        if ((gst['items'] as List? ?? []).isNotEmpty) {
          c.add(header('GST Payable', depth + 2));
          c.addAll((gst['items'] as List).map((i) => itemRow(i, depth + 3)));
          c.add(subtotal('GST Payable', gst['total'], depth + 2));
        }
        c.add(subtotal('Other Current Liabilities', ocl['total'], depth + 1));
      }
      c.add(subtotal('Current Liabilities', cl['total'], depth));
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: c);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── ASSETS ──
      _fsSecHead('Assets', _blue),
      if (assets['currentAssets'] != null) ...[
        header('Current Assets', 0),
        renderCashBank(
            assets['currentAssets']['cashAndCashEquivalents'] ?? {}, 1),
        renderGroup(assets['currentAssets']['accountsReceivable'] ?? {},
            'Accounts Receivable', 1),
        renderGroup(assets['currentAssets']['otherCurrentAssets'] ?? {},
            'Other current assets', 1),
        subtotal('Current Assets', assets['currentAssets']['total'], 0),
      ],
      renderGroup(assets['fixedAssets'] ?? {}, 'Fixed Assets', 0),
      renderGroup(assets['nonCurrentAssets'] ?? {}, 'Non Current Assets', 0),
      renderGroup(assets['otherAssets'] ?? {}, 'Other Assets', 0),
      _fsSubtotal('Total for Assets', assets['total']),
      const SizedBox(height: 20),

      // ── LIABILITIES ──
      _fsSecHead('Liabilities', _red),
      if (liabs['currentLiabilities'] != null)
        renderCurrentLiabilities(liabs['currentLiabilities'], 0),
      renderGroup(
          liabs['nonCurrentLiabilities'] ?? {}, 'Non Current Liabilities', 0),
      renderGroup(liabs['otherLiabilities'] ?? {}, 'Other Liabilities', 0),
      _fsSubtotal('Total for Liabilities', liabs['total']),
      const SizedBox(height: 20),

      // ── EQUITIES ──
      _fsSecHead('Equities', _purple),
      ...((eqs['items'] as List? ?? []).map((i) => itemRow(i, 0))),
      if (eqs['currentYearEarnings'] != null && eqs['currentYearEarnings'] != 0)
        Padding(
            padding:
                const EdgeInsets.only(left: 12.0, top: 6, bottom: 6, right: 12),
            child: Row(children: [
              const Expanded(
                  child: Text('Current Year Earnings',
                      style: TextStyle(fontSize: 15, color: _blue))),
              Text('Rs. ${_fmtNum(eqs['currentYearEarnings'])}',
                  style:
                      const TextStyle(fontSize: 15, color: Color(0xFF374151))),
            ])),
      _fsSubtotal('Total for Equities', eqs['total']),
      const Divider(height: 28, thickness: 1, color: Color(0xFFE2E8F0)),
      _fsNetRow(
          'Total for Liabilities & Equities', d['totalLiabilitiesAndEquity']),

      if (d['balanced'] == true) ...[
        const SizedBox(height: 10),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: _green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _green.withOpacity(0.3))),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, color: _green, size: 14),
              SizedBox(width: 6),
              Text('Balance Sheet is Balanced',
                  style: TextStyle(
                      fontSize: 14,
                      color: _green,
                      fontWeight: FontWeight.w600)),
            ])),
      ],
    ]);
  }

  // Cash Flow
  Widget _buildCF(Map<String, dynamic> d) {
    final op = d['operating'] as Map? ?? {};
    final inv = d['investing'] as Map? ?? {};
    final fin = d['financing'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fsSecHead('Operating Activities', _green),
      ..._fsItems(op['items'], 'op'),
      _fsKV('Cash Inflows', op['inflows']),
      _fsKV('Cash Outflows', op['outflows']),
      _fsSubtotal('Net Cash from Operating Activities', op['net']),
      const SizedBox(height: 16),
      _fsSecHead('Investing Activities', _blue),
      ..._fsItems(inv['items'], 'inv'),
      _fsKV('Investing Inflows', inv['inflows']),
      _fsKV('Investing Outflows', inv['outflows']),
      _fsSubtotal('Net Cash from Investing Activities', inv['net']),
      const SizedBox(height: 16),
      _fsSecHead('Financing Activities', _purple),
      ..._fsItems(fin['items'], 'fin'),
      _fsSubtotal('Net Cash from Financing Activities', fin['net']),
      const Divider(height: 28, thickness: 1, color: Color(0xFFE2E8F0)),
      _fsNetRow('Net Cash Change', d['netCashChange']),
    ]);
  }

  // P&L Horizontal (comparative)
  Widget _buildPLH(Map<String, dynamic> d) {
    final curr = d['current'] as Map? ?? {};
    final prev = d['previous'] as Map? ?? {};
    final chg = d['changes'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fsCompHeader(['Current Period', 'Previous Period', 'Change %']),
      _fsCompRow('Operating Income', curr['income'], prev['income'],
          chg['income']?['percent'],
          isAmount: true),
      _fsCompRow('COGS', curr['cogs'], prev['cogs'], chg['cogs']?['percent'],
          isAmount: true),
      _fsCompRow('Gross Profit', curr['grossProfit'], prev['grossProfit'],
          chg['grossProfit']?['percent'],
          isAmount: true, isBold: true),
      _fsCompRow('Operating Expenses', curr['expenses'], prev['expenses'],
          chg['expenses']?['percent'],
          isAmount: true),
      _fsCompRow('Operating Profit', curr['operatingProfit'],
          prev['operatingProfit'], chg['operatingProfit']?['percent'],
          isAmount: true, isBold: true),
      if (curr.containsKey('nonOpInc')) ...[
        _fsCompRow('Non Operating Income', curr['nonOpInc'], prev['nonOpInc'],
            chg['nonOpInc']?['percent'],
            isAmount: true),
      ],
      if (curr.containsKey('nonOpEx')) ...[
        _fsCompRow('Non Operating Expense', curr['nonOpEx'], prev['nonOpEx'],
            chg['nonOpEx']?['percent'],
            isAmount: true),
      ],
      const Divider(height: 24),
      _fsCompRow('Net Profit / Loss', curr['netProfit'], prev['netProfit'],
          chg['netProfit']?['percent'],
          isAmount: true, isBold: true, isNet: true),
    ]);
  }

  // Balance Sheet Horizontal (comparative)
  Widget _buildBSH(Map<String, dynamic> d) {
    final curr = d['current'] as Map? ?? {};
    final prev = d['previous'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fsCompHeader(['Current', 'Previous']),
      _fsCompRow2('Total Assets', curr['assets'], prev['assets'], isBold: true),
      _fsCompRow2('Total Liabilities', curr['liabilities'], prev['liabilities'],
          isBold: true),
      _fsCompRow2('Total Equity', curr['equity'], prev['equity'], isBold: true),
    ]);
  }

  // Movement of Equity
  Widget _buildMOE(Map<String, dynamic> d) {
    final accounts = d['accounts'] as List? ?? [];
    final totals = d['totals'] as Map? ?? {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Column headers
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
              color: Color(0xFF0D1B3E),
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6), topRight: Radius.circular(6))),
          child: Row(children: [
            const Expanded(
                flex: 3,
                child: Text('ACCOUNT',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3))),
            for (final lbl in ['OPENING', 'CHANGE', 'CLOSING'])
              Expanded(
                  child: Text(lbl,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3))),
          ])),
      // Rows
      ...accounts.asMap().entries.map<Widget>((e) {
        final a = e.value as Map;
        return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: e.key % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
            child: Row(children: [
              Expanded(
                  flex: 3,
                  child: Text(a['accountName']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF374151)))),
              Expanded(
                  child: Text('Rs. ${_fmtNum(a['opening'])}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14))),
              Expanded(
                  child: Text('Rs. ${_fmtNum(a['change'])}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 14, color: _amtColor(a['change'])))),
              Expanded(
                  child: Text('Rs. ${_fmtNum(a['closing'])}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _navy))),
            ]));
      }),
      // Totals row
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0xFF1E3A8A), width: 1.5))),
          child: Row(children: [
            const Expanded(
                flex: 3,
                child: Text('Total',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
            Expanded(
                child: Text('Rs. ${_fmtNum(totals['opening'])}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold))),
            Expanded(
                child: Text('Rs. ${_fmtNum(totals['change'])}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold))),
            Expanded(
                child: Text('Rs. ${_fmtNum(totals['closing'])}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _navy))),
          ])),
    ]);
  }

  // ── Financial statement helpers ────────────────────────────────────────────
  Widget _fsSecHead(String title, Color color) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: color, width: 3))),
      child: Text(title,
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: color)));

  List<Widget> _fsItems(dynamic items, String tag) {
    if (items == null || items is! List || items.isEmpty)
      return [
        Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4, top: 2),
            child: Text('No transactions',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[400],
                    fontStyle: FontStyle.italic)))
      ];

    final filtered = items.where((i) {
      if (i is! Map) return false;
      final amt = double.tryParse(i['amount']?.toString() ?? '0') ?? 0;
      return amt != 0;
    }).toList();
    if (filtered.isEmpty) return [];

    return filtered.asMap().entries.map<Widget>(
      (e) {
        final item = e.value as Map;
        final accountName = item['accountName']?.toString() ?? '';
        final amount = item['amount'];
        return InkWell(
          onTap: () => _openAccountTransactions(item),
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
              color: e.key % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
              child: Row(children: [
                Expanded(
                    child: Row(children: [
                  Text(accountName,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF374151))),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 10, color: Colors.grey[400]),
                ])),
                Text('${_fmtNum(amount)}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _amtColor(amount))),
              ])),
        );
      },
    ).toList();
  }

  List<Widget> _fsGroupedItems(Map section) {
    // Try grouped sub-sections first, then fall back to flat items
    final groups = section['groups'] as List? ?? [];
    if (groups.isNotEmpty) {
      return groups.map<Widget>((g) {
        final grp = g as Map;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(grp['name']?.toString() ?? '',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                      letterSpacing: 0.3))),
          ..._fsItems(grp['items'], grp['name'] ?? ''),
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(children: [
                Expanded(
                    child: Text('Total ${grp['name'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151)))),
                Text('${_fmtNum(grp['total'])}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _navy)),
              ])),
        ]);
      }).toList();
    }
    return _fsItems(section['items'], 'items');
  }

  Widget _fsSubtotal(String label, dynamic val) => Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151)))),
        Text('${_fmtNum(val)}',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: _navy)),
      ]));

  Widget _fsGrossRow(String label, dynamic val) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
          color: _green.withOpacity(0.07),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _green.withOpacity(0.2))),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF374151)))),
        Text('${_fmtNum(val)}',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: (val is num && val < 0) ? _red : _green)),
      ]));

  Widget _fsNetRow(String label, dynamic val) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
          color: _navy.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: _navy))),
        Text('${_fmtNum(val)}',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: (val is num && val < 0) ? _red : _green)),
      ]));

  Widget _fsKV(String label, dynamic val) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
        Text('${_fmtNum(val)}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _amtColor(val))),
      ]));

  Widget _fsCompHeader(List<String> cols) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
          color: Color(0xFF0D1B3E),
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(6), topRight: Radius.circular(6))),
      child: Row(children: [
        const Expanded(flex: 3, child: SizedBox()),
        ...cols.map((c) => Expanded(
            flex: 2,
            child: Text(c,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3)))),
      ]));

  Widget _fsCompRow(String label, dynamic curr, dynamic prev, dynamic pct,
      {bool isAmount = false, bool isBold = false, bool isNet = false}) {
    final style = TextStyle(
        fontSize: isNet ? 14 : 12,
        fontWeight: (isBold || isNet) ? FontWeight.bold : FontWeight.normal,
        color: isNet ? _navy : const Color(0xFF374151));
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isNet ? _navy.withOpacity(0.05) : Colors.transparent,
        child: Row(children: [
          Expanded(flex: 3, child: Text(label, style: style)),
          Expanded(
              flex: 2,
              child: Text(isAmount ? 'Rs. ${_fmtNum(curr)}' : _fmtNum(curr),
                  textAlign: TextAlign.right,
                  style: style.copyWith(color: _navy))),
          Expanded(
              flex: 2,
              child: Text(isAmount ? 'Rs. ${_fmtNum(prev)}' : _fmtNum(prev),
                  textAlign: TextAlign.right,
                  style: style.copyWith(color: Colors.grey[600]))),
          Expanded(
              flex: 2,
              child: Text('${_fmtNum(pct)}%',
                  textAlign: TextAlign.right,
                  style: style.copyWith(
                      color: (pct is num && pct >= 0) ? _green : _red))),
        ]));
  }

  Widget _fsCompRow2(String label, dynamic curr, dynamic prev,
      {bool isBold = false}) {
    final style = TextStyle(
        fontSize: 14,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        color: const Color(0xFF374151));
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label, style: style)),
          Expanded(
              flex: 2,
              child: Text('Rs. ${_fmtNum(curr)}',
                  textAlign: TextAlign.right,
                  style: style.copyWith(color: _navy))),
          Expanded(
              flex: 2,
              child: Text('Rs. ${_fmtNum(prev)}',
                  textAlign: TextAlign.right,
                  style: style.copyWith(color: Colors.grey[600]))),
        ]));
  }

  void _openAccountTransactions(Map item) {
    final accountName = item['accountName']?.toString() ?? '';
    if (accountName.isEmpty) return;

    // For expense/COGS items from P&L — show bank transaction drill-down
    if (widget.report.key == 'profit-loss' ||
        widget.report.key == 'profit-loss-horizontal') {
      // Pass the date range filters through to the drilldown
      final pPeriod = _data?['period'] ?? _data?['data']?['period'];
      final startDate = _params['fromDate'] ?? pPeriod?['start']?.toString();
      final endDate = _params['toDate'] ?? pPeriod?['end']?.toString();
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlExpenseDrilldownPage(
              accountName: accountName,
              orgName: widget.orgName,
              startDate: startDate,
              endDate: endDate,
            ),
          ));
      return;
    }

    // For all other reports — original COA journal view
    final meta = ReportMeta(
        key: 'account-transactions',
        name: 'Account Transactions — $accountName',
        accountId: item['accountId']?.toString());
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReportViewerPage(
                  report: meta,
                  orgName: widget.orgName,
                  initialParams: _params,
                )));
  }

  // Flatten financial data for export
  List<Map<String, dynamic>> _flattenFinancial() {
    if (_data == null) return [];
    final rows = <Map<String, dynamic>>[];
    final k = widget.report.key;

    if (k == 'profit-loss') {
      for (final sec in ['income', 'costOfGoods', 'operatingExpenses']) {
        final s = _data![sec] as Map? ?? {};
        rows.add({
          'Section': sec == 'income'
              ? 'Operating Income'
              : sec == 'costOfGoods'
                  ? 'Cost of Goods Sold'
                  : 'Operating Expenses',
          'Account': '',
          'Amount': ''
        });
        for (final i in (s['items'] as List? ?? [])) {
          final amt = double.tryParse((i as Map)['amount']?.toString() ?? '0') ?? 0;
          if (amt == 0) continue;
          rows.add({
            'Section': '',
            'Account': i['accountName'],
            'Amount': i['amount']
          });
        }
        rows.add({'Section': 'Subtotal', 'Account': '', 'Amount': s['total']});
      }
      rows.add({
        'Section': 'Net Profit / Loss',
        'Account': '',
        'Amount': _data!['netProfit']
      });
    } else if (k == 'profit-loss-horizontal') {
      final curr = _data!['current'] as Map? ?? {};
      final prev = _data!['previous'] as Map? ?? {};
      final chg = _data!['changes'] as Map? ?? {};
      rows.add({
        'Metric': 'Income',
        'Current': curr['income'],
        'Previous': prev['income'],
        'Change': (chg['income'] as Map?)?['absolute'],
        'Change %': (chg['income'] as Map?)?['percent']
      });
      rows.add({
        'Metric': 'Expenses',
        'Current': curr['expenses'],
        'Previous': prev['expenses'],
        'Change': (chg['expenses'] as Map?)?['absolute'],
        'Change %': (chg['expenses'] as Map?)?['percent']
      });
      rows.add({
        'Metric': 'Net Profit',
        'Current': curr['netProfit'],
        'Previous': prev['netProfit'],
        'Change': (chg['netProfit'] as Map?)?['absolute'],
        'Change %': (chg['netProfit'] as Map?)?['percent']
      });
    } else if (k == 'balance-sheet') {
      final tree = _data!['nestedTree'] as Map? ?? {};
      if (tree.isNotEmpty) {
        void addGroup(Map group, String title) {
          rows.add({'Section': title, 'Account': '', 'Amount': ''});
          final items = group['items'] as List? ?? [];
          for (final i in items) {
            rows.add({
              'Section': '',
              'Account': (i as Map)['accountName'],
              'Amount': i['amount']
            });
          }
          for (final key in group.keys) {
            if (key != 'items' && key != 'total' && group[key] is Map) {
              addGroup(group[key], _colLabel(key));
            }
          }
          rows.add({'Section': 'Total $title', 'Account': '', 'Amount': group['total'] ?? 0});
        }

        final assets = tree['assets'] as Map? ?? {};
        final liabs = tree['liabilities'] as Map? ?? {};
        final eqs = tree['equities'] as Map? ?? {};

        addGroup(assets, 'ASSETS');
        addGroup(liabs, 'LIABILITIES');
        addGroup(eqs, 'EQUITY');
      }
    } else if (k == 'balance-sheet-horizontal') {
      final curr = _data!['current'] as Map? ?? {};
      final prev = _data!['previous'] as Map? ?? {};
      rows.add({
        'Item': 'Total Assets',
        'Current': curr['assets'],
        'Previous': prev['assets']
      });
      rows.add({
        'Item': 'Total Liabilities',
        'Current': curr['liabilities'],
        'Previous': prev['liabilities']
      });
      rows.add({
        'Item': 'Total Equity',
        'Current': curr['equity'],
        'Previous': prev['equity']
      });
    } else if (k == 'cash-flow') {
      // Backend returns summary + monthlyBreakdown (items[] is always empty)
      final summary = _data!['summary'] as Map? ?? {};
      rows.add({
        'Item': 'Opening Balance',
        'Amount': summary['openingBalance'] ?? 0
      });
      rows.add(
          {'Item': 'Total Incoming', 'Amount': summary['totalIncoming'] ?? 0});
      rows.add(
          {'Item': 'Total Outgoing', 'Amount': summary['totalOutgoing'] ?? 0});
      rows.add({
        'Item': 'Closing Balance',
        'Amount': summary['closingBalance'] ?? 0
      });
      final monthly = _data!['monthlyBreakdown'] as List? ?? [];
      if (monthly.isNotEmpty) {
        rows.add({'Item': '── Monthly Breakdown ──', 'Amount': ''});
        for (final m in monthly) {
          if (m is Map)
            rows.add({
              'Item': m['month']?.toString() ?? '',
              'Amount': m['endingBalance'] ?? m['balance'] ?? 0,
              'Incoming': m['incoming'] ?? 0,
              'Outgoing': m['outgoing'] ?? 0
            });
        }
      }
    } else if (k == 'movement-of-equity') {
      final accounts = _data!['accounts'] as List? ?? [];
      rows.add({
        'Account': 'Account',
        'Opening': 'Opening',
        'Change': 'Change',
        'Closing': 'Closing'
      });
      for (final a in accounts) {
        if (a is Map)
          rows.add({
            'Account': a['accountName'] ?? '',
            'Opening': a['opening'] ?? 0,
            'Change': a['change'] ?? 0,
            'Closing': a['closing'] ?? 0
          });
      }
      final t = _data!['totals'] as Map? ?? {};
      rows.add({
        'Account': 'TOTAL',
        'Opening': t['opening'] ?? 0,
        'Change': t['change'] ?? 0,
        'Closing': t['closing'] ?? 0
      });
    } else {
      rows.addAll(_rows);
    }
    return rows;
  }

  // ==========================================================================
  // LEDGER / TRIAL BALANCE TABLE RENDERER (no Expanded — inside scroll view)
  // ==========================================================================

  Widget _buildLedgerTable() {
    final rows = _filtered;
    if (rows.isEmpty) return _emptyState();

    final hasDebitCredit =
        _headers.contains('debit') || _headers.contains('credit');
    final colW = 140.0;

    // ── header row widget ──────────────────────────────────────────────────
    final visibleHeaders =
        _headers.where((h) => h != '_isAccountHeader').toList();
    final headerRow = Container(
      color: const Color(0xFF0D1B3E),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        ...visibleHeaders.map((h) {
          final isAmt = h.toLowerCase().contains('debit') ||
              h.toLowerCase().contains('credit') ||
              h.toLowerCase().contains('balance') ||
              h.toLowerCase().contains('amount');
          return SizedBox(
              width: colW,
              child: Text(_colLabel(h).toUpperCase(),
                  textAlign: isAmt ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3)));
        }),
      ]),
    );

    // ── data rows widget ───────────────────────────────────────────────────
    final dataRows = SizedBox(
      height: (rows.length * 48.0 + 20)
          .clamp(80.0, MediaQuery.of(context).size.height * 0.55),
      child: ScrollConfiguration(
        behavior: _AllDeviceScroll(),
        child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[i];
            final isAccountRow = r['_isAccountHeader'] == true ||
                (r['accountCode'] != null &&
                    r['accountCode'].toString().isNotEmpty &&
                    r['date'].toString().isEmpty);
            return InkWell(
              onTap: isAccountRow ? null : () => _onRowTap(r),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                color: isAccountRow
                    ? const Color(0xFFF0F4FF)
                    : (i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC)),
                child: Row(children: [
                  ..._headers.where((h) => h != '_isAccountHeader').map((h) {
                    final v = r[h];
                    final hl = h.toLowerCase();
                    final isAmt = hl.contains('debit') ||
                        hl.contains('credit') ||
                        hl.contains('balance') ||
                        hl.contains('amount');
                    final isName =
                        hl.contains('account') && hl.contains('name');
                    Color? c;
                    if (hl.contains('debit')) c = _orange;
                    if (hl.contains('credit')) c = _green;
                    if (hl == 'balance' || hl == 'closingbalance') c = _navy;
                    // For account header rows, show account name spanning
                    if (isAccountRow && h == 'accountName') {
                      return SizedBox(
                          width: colW * 3,
                          child: Text(v?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _navy)));
                    }
                    if (isAccountRow && h != 'accountName')
                      return SizedBox(width: colW);
                    if (hl == 'links') {
                      return SizedBox(
                          width: colW,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _buildLinksCell(r),
                          ));
                    }
                    return SizedBox(
                        width: colW,
                        child: Text(_displayVal(h, v),
                            textAlign: isAmt ? TextAlign.right : TextAlign.left,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                color: c ?? const Color(0xFF374151),
                                fontWeight: isAccountRow || hl.contains('total')
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                decoration: isName
                                    ? TextDecoration.underline
                                    : TextDecoration.none)));
                  }),
                ]),
              ),
            );
          },
        ),
      ),
    );

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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // record count bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('${rows.length} record${rows.length != 1 ? 's' : ''}',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        const Divider(height: 1),
        // horizontal scroll wraps header + data + totals
        ScrollConfiguration(
          behavior: _AllDeviceScroll(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                headerRow,
                dataRows,
                if (hasDebitCredit) _buildLedgerTotals(rows),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildLedgerTotals(List<Map<String, dynamic>> rows) {
    final totalDebit = rows.fold(0.0,
        (s, r) => s + (double.tryParse(r['debit']?.toString() ?? '') ?? 0.0));
    final totalCredit = rows.fold(0.0,
        (s, r) => s + (double.tryParse(r['credit']?.toString() ?? '') ?? 0.0));
    final balanced = (totalDebit - totalCredit).abs() < 0.01;
    final colW = 140.0;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
            border:
                Border(top: BorderSide(color: Color(0xFF1E3A8A), width: 1.5))),
        child: Row(children: [
          ..._headers.map((h) {
            final hl = h.toLowerCase();
            final isDebit = hl.contains('debit');
            final isCredit = hl.contains('credit');
            if (!isDebit && !isCredit)
              return SizedBox(
                  width: colW,
                  child: h == _headers.first
                      ? Row(children: [
                          const Text('TOTAL',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _navy)),
                          const SizedBox(width: 8),
                          if (balanced)
                            const Icon(Icons.check_circle,
                                size: 14, color: _green)
                        ])
                      : const SizedBox.shrink());
            return SizedBox(
                width: colW,
                child: Text(
                    isDebit
                        ? 'Rs. ${totalDebit.toStringAsFixed(2)}'
                        : 'Rs. ${totalCredit.toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDebit ? _orange : _green)));
          }),
        ]));
  }

  // ==========================================================================
  // LIST TABLE RENDERER (default — Invoice Details, Expense Details, etc.)
  // ==========================================================================

  Widget _buildListTable() {
    final rows = _filtered;
    if (rows.isEmpty) return _emptyState();
    if (_headers.isEmpty)
      return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(8)),
              child: Text(_data.toString(),
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13))));

    final colW = _headers.length <= 4
        ? 180.0
        : _headers.length <= 7
            ? 155.0
            : 130.0;
    final tableW = _headers.length * colW + 28;

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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        // Horizontal scroll wrapper
        ScrollConfiguration(
          behavior: _AllDeviceScroll(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header row
                Container(
                  height: 46,
                  color: const Color(0xFF0D1B3E),
                  child: Row(children: [
                    const SizedBox(width: 14),
                    ..._headers.map((h) {
                      final hl = h.toLowerCase();
                      final isAmt = hl.contains('amount') ||
                          hl.contains('total') ||
                          hl.contains('balance') ||
                          hl.contains('due') ||
                          hl.contains('paid');
                      return SizedBox(
                          width: colW,
                          child: Text(_colLabel(h).toUpperCase(),
                              textAlign:
                                  isAmt ? TextAlign.right : TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 0.3)));
                    }),
                    const SizedBox(width: 14),
                  ]),
                ),
                // Vertical scroll for data rows
                SizedBox(
                  height: (rows.length * 56.0 + 20)
                      .clamp(100.0, MediaQuery.of(context).size.height * 0.55),
                  child: ScrollConfiguration(
                    behavior: _AllDeviceScroll(),
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        return InkWell(
                          onTap: () => _onRowTap(r),
                          child: Container(
                            height: 56,
                            color: i % 2 == 0
                                ? Colors.white
                                : const Color(0xFFF8FAFC),
                            child: Row(children: [
                              const SizedBox(width: 14),
                              ..._headers.map((h) {
                                final v = r[h];
                                final hl = h.toLowerCase();
                                final isAmt = hl.contains('amount') ||
                                    hl.contains('total') ||
                                    hl.contains('balance') ||
                                    hl.contains('due') ||
                                    hl.contains('paid');
                                return SizedBox(
                                    width: colW,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: hl == 'links'
                                        ? _buildLinksCell(r)
                                        : hl == 'status'
                                          ? _statusBadge(v?.toString() ?? '')
                                          : Text(_displayVal(h, v),
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: isAmt
                                                  ? TextAlign.right
                                                  : TextAlign.left,
                                            style: _cellStyle(h, v) ??
                                                const TextStyle(
                                                    fontSize: 14,
                                                    color: Color(0xFF374151))),
                                    ));
                              }),
                              const SizedBox(width: 14),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildLinksCell(Map<String, dynamic> r) {
    final btId = r['btId']?.toString();
    final atId = r['atId']?.toString();
    final bAcctId = r['bankAccountId']?.toString();
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (btId != null && bAcctId != null)
          InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailPage(
                accountId: bAcctId,
                accountName: 'Bank Account',
                accountType: 'bank',
                highlightTransactionId: btId,
              )));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF90CAF9))),
              child: const Text('BT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
            ),
          ),
        if (btId != null && atId != null) const SizedBox(width: 6),
        if (atId != null)
          InkWell(
            onTap: () {
              final type = r['atType']?.toString() ?? 'Expense';
              Widget? page;
              switch (type) {
                case 'Expense': page = NewExpensePage(expenseId: atId, showAppBar: true); break;
                case 'Invoice': page = NewInvoiceScreen(invoiceId: atId); break;
                case 'Bill': page = NewBillScreen(billId: atId); break;
                case 'CreditNote': page = NewCreditNoteScreen(creditNoteId: atId); break;
                case 'PaymentReceived': page = NewPaymentPage(paymentId: atId, showAppBar: true); break;
                case 'PaymentMade': page = NewPaymentMadeScreen(paymentId: atId); break;
                case 'JournalEntry': page = NewManualJournalPage(journalId: atId); break;
              }
              if (page != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFFFCC80))),
              child: const Text('AT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
            ),
          ),
        if (btId == null && atId == null)
          const Text('—', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  // Status badge chip
  Widget _statusBadge(String status) {
    final s = status.toUpperCase();
    Color bg, fg;
    if (s == 'PAID' ||
        s == 'APPROVED' ||
        s == 'BILLED' ||
        s == 'RECEIVED' ||
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
        s == 'PARTIALLY PAID' ||
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
    return null;
  }

  // ==========================================================================
  // CHART VIEW
  // ==========================================================================

  Widget _buildChartView() {
    final rows = _filtered;
    if (rows.isEmpty)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bar_chart_outlined, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text('No data to chart',
            style: TextStyle(fontSize: 17, color: Colors.grey[500])),
      ]));
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.report.name,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: _navy)),
        const SizedBox(height: 4),
        Text('${rows.length} records',
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 20),
        Expanded(
            child: _chartType == _ChartType.pie
                ? _buildPie(rows)
                : _buildBarLine(rows)),
      ]),
    );
  }

  String _labelField(List<Map<String, dynamic>> rows) {
    const k = [
      'customerName',
      'vendorName',
      'itemName',
      'accountName',
      'category',
      'salesperson',
      'date',
      'invoiceNumber',
      'billNumber',
      'name',
      'projectName',
      'entryNumber',
      'range'
    ];
    for (final key in k) {
      if (rows.first.containsKey(key)) return key;
    }
    return _headers.isNotEmpty ? _headers.first : 'label';
  }

  String _valueField(List<Map<String, dynamic>> rows) {
    const k = [
      'totalAmount',
      'amount',
      'total',
      'totalSales',
      'balance',
      'amountDue',
      'totalPaid',
      'credit',
      'debit',
      'totalInvoiced',
      'totalBilled',
      'totalHours',
      'hours'
    ];
    for (final key in k) {
      if (rows.first.containsKey(key)) return key;
    }
    for (final h in _headers) {
      if (double.tryParse(rows.first[h]?.toString() ?? '') != null) return h;
    }
    return _headers.length > 1 ? _headers[1] : _headers.first;
  }

  final List<Color> _cc = [
    _navy,
    _blue,
    _green,
    _orange,
    _purple,
    _teal,
    _red,
    const Color(0xFF6366F1),
    const Color(0xFFF59E0B),
    const Color(0xFFEC4899),
    const Color(0xFF14B8A6)
  ];

  Widget _buildBarLine(List<Map<String, dynamic>> rows) {
    final lf = _labelField(rows);
    final vf = _valueField(rows);
    final lim = rows.take(12).toList();
    final vals = lim
        .map((r) => double.tryParse(r[vf]?.toString() ?? '') ?? 0.0)
        .toList();
    final absMax = vals.isEmpty
        ? 100.0
        : (vals.map((v) => v.abs()).reduce((a, b) => a > b ? a : b) * 1.3);
    final maxY = absMax == 0 ? 100.0 : absMax;
    final minY = vals.any((v) => v < 0)
        ? vals.reduce((a, b) => a < b ? a : b) * 1.3
        : 0.0;
    final step = lim.length <= 6
        ? 1
        : lim.length <= 10
            ? 2
            : 3;

    Widget bottomTitle(double v, TitleMeta _) {
      final i = v.toInt();
      if (i < 0 || i >= lim.length || i % step != 0)
        return const SizedBox.shrink();
      final label = lim[i][lf]?.toString() ?? '';
      final short = label.length > 10 ? '${label.substring(0, 9)}…' : label;
      return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(short,
              style: TextStyle(fontSize: 11, color: Colors.grey[600])));
    }

    Widget leftTitle(double v, TitleMeta _) => Text('Rs. ${_shortNum(v)}',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]));

    final titlesData = FlTitlesData(
      leftTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true, reservedSize: 58, getTitlesWidget: leftTitle)),
      bottomTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: bottomTitle)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );

    if (_chartType == _ChartType.bar) {
      return BarChart(BarChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
        titlesData: titlesData,
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
                tooltipBgColor: Colors.white,
                tooltipBorder: const BorderSide(color: Color(0xFFE8EEF4)),
                getTooltipItem: (group, _, rod, __) {
                  final label = lim[group.x][lf]?.toString() ?? '';
                  return BarTooltipItem(
                      '$label\n',
                      const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      children: [
                        TextSpan(
                            text: 'Rs. ${rod.toY.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: _navy,
                                fontWeight: FontWeight.w600,
                                fontSize: 14))
                      ]);
                })),
        barGroups: lim
            .asMap()
            .entries
            .map((e) => BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(
                      toY: vals[e.key],
                      color: _cc[e.key % _cc.length],
                      width: 20,
                      borderRadius: BorderRadius.vertical(
                          top: const Radius.circular(4),
                          bottom: vals[e.key] < 0
                              ? const Radius.circular(4)
                              : Radius.zero))
                ]))
            .toList(),
      ));
    }

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.grey[200]!, strokeWidth: 1)),
      titlesData: titlesData,
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
            spots: vals
                .asMap()
                .entries
                .map((e) => FlSpot(e.key.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: _navy,
            barWidth: 2.5,
            dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 4,
                    color: _navy,
                    strokeWidth: 2,
                    strokeColor: Colors.white)),
            belowBarData:
                BarAreaData(show: true, color: _navy.withOpacity(0.07)))
      ],
    ));
  }

  Widget _buildPie(List<Map<String, dynamic>> rows) {
    final lf = _labelField(rows);
    final vf = _valueField(rows);
    final lim = rows.take(8).toList();
    final vals = lim
        .map((r) => (double.tryParse(r[vf]?.toString() ?? '') ?? 0.0).abs())
        .toList();
    final total = vals.fold(0.0, (a, b) => a + b);
    if (total == 0)
      return const Center(child: Text('No positive values to chart'));
    return Row(children: [
      Expanded(
          child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: lim.asMap().entries.map((e) {
                final pct = vals[e.key] / total * 100;
                return PieChartSectionData(
                    color: _cc[e.key % _cc.length],
                    value: vals[e.key],
                    radius: 85,
                    title: '${pct.toStringAsFixed(1)}%',
                    titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white));
              }).toList()))),
      const SizedBox(width: 16),
      SizedBox(
          width: 150,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: lim.asMap().entries.map((e) {
                final label = lim[e.key][lf]?.toString() ?? '';
                final pct = vals[e.key] / total * 100;
                return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: _cc[e.key % _cc.length],
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                label.length > 14
                                    ? '${label.substring(0, 13)}…'
                                    : label,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                            Text('${pct.toStringAsFixed(1)}%',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500])),
                          ])),
                    ]));
              }).toList())),
    ]);
  }

  // ── Fallback related reports for keys not in the map ─────────────────────
  List<Map<String, String>> _fallbackRelated() {
    final k = widget.report.key;
    if (k.contains('receivable') ||
        k.contains('ar-') ||
        k.contains('customer')) {
      return [
        {'key': 'ar-aging-summary', 'name': 'AR Aging Summary'},
        {'key': 'invoice-details', 'name': 'Invoice Details'},
        {'key': 'payments-received', 'name': 'Payments Received'},
        {'key': 'customer-balance', 'name': 'Customer Balance'},
      ];
    }
    if (k.contains('payable') || k.contains('ap-') || k.contains('vendor')) {
      return [
        {'key': 'ap-aging-summary', 'name': 'AP Aging Summary'},
        {'key': 'bill-details', 'name': 'Bill Details'},
        {'key': 'payments-made', 'name': 'Payments Made'},
        {'key': 'vendor-balance', 'name': 'Vendor Balance'},
      ];
    }
    if (k.contains('expense') || k.contains('purchase')) {
      return [
        {'key': 'expense-details', 'name': 'Expense Details'},
        {'key': 'expenses-by-category', 'name': 'Expenses by Category'},
        {'key': 'purchases-by-vendor', 'name': 'Purchases by Vendor'},
        {'key': 'bill-details', 'name': 'Bill Details'},
      ];
    }
    if (k.contains('account') ||
        k.contains('ledger') ||
        k.contains('journal') ||
        k.contains('trial')) {
      return [
        {'key': 'trial-balance', 'name': 'Trial Balance'},
        {'key': 'general-ledger', 'name': 'General Ledger'},
        {'key': 'account-transactions', 'name': 'Account Transactions'},
        {'key': 'journal-report', 'name': 'Journal Report'},
      ];
    }
    if (k.contains('project') || k.contains('timesheet')) {
      return [
        {'key': 'project-summary', 'name': 'Project Summary'},
        {'key': 'timesheet-details', 'name': 'Timesheet Details'},
        {'key': 'expense-details', 'name': 'Expense Details'},
      ];
    }
    // Generic fallback
    return [
      {'key': 'profit-loss', 'name': 'Profit and Loss'},
      {'key': 'balance-sheet', 'name': 'Balance Sheet'},
      {'key': 'cash-flow', 'name': 'Cash Flow Statement'},
      {'key': 'trial-balance', 'name': 'Trial Balance'},
    ];
  }

  // ==========================================================================
  // RELATED REPORTS PANEL
  // ==========================================================================

  Widget _buildRelatedReports() {
    final related = _relatedReports[widget.report.key] ?? _fallbackRelated();
    if (related.isEmpty) return const SizedBox.shrink();

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
              final colors = [_navy, _blue, _green, _orange, _purple, _teal];
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

  // ==========================================================================
  // EMPTY STATE + ERROR
  // ==========================================================================

  Widget _emptyState() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.table_chart_outlined, size: 52, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(
            _search.isNotEmpty
                ? 'No results match "$_search"'
                : 'No data for this period',
            style: TextStyle(fontSize: 17, color: Colors.grey[500])),
      ]));

  Widget _buildError() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, size: 52, color: Colors.red[400]),
        const SizedBox(height: 12),
        Text('Failed to load report',
            style: TextStyle(fontSize: 17, color: Colors.grey[700])),
        const SizedBox(height: 8),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(_error ?? '',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)))),
      ]));

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  String _fmtNum(dynamic v) {
    if (v == null) return '0.00';
    final n = double.tryParse(v.toString());
    return n != null ? n.toStringAsFixed(2) : v.toString();
  }

  Color _amtColor(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    return (n != null && n < 0) ? _red : const Color(0xFF374151);
  }

  String _shortNum(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _toggleView() => Container(
        height: 38,
        decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDE3EE))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _viewBtn(Icons.table_rows_rounded, 'Table', !_chartMode,
              () => setState(() => _chartMode = false)),
          _viewBtn(Icons.bar_chart_rounded, 'Chart', _chartMode,
              () => setState(() => _chartMode = true)),
        ]),
      );

  Widget _viewBtn(
          IconData icon, String label, bool active, VoidCallback onTap) =>
      GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: active ? _navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(7)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    size: 15, color: active ? Colors.white : Colors.grey[500]),
                const SizedBox(width: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : Colors.grey[500])),
              ])));

  Widget _searchBox(double w) {
    final f = TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Search in report…',
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
    );
    if (w == double.infinity) return SizedBox(height: 40, child: f);
    return SizedBox(width: w, height: 40, child: f);
  }

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
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      child: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)));
}

// =============================================================================
// TICKET DIALOG
// =============================================================================

class _TicketDialog extends StatefulWidget {
  final String reportName, orgName;
  final void Function(String) onSuccess, onError;
  const _TicketDialog(
      {required this.reportName,
      required this.orgName,
      required this.onSuccess,
      required this.onError});
  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  final _tms = TMSService();
  final _sc = TextEditingController();
  List<Map<String, dynamic>> _all = [], _f = [];
  Map<String, dynamic>? _sel;
  bool _loading = true, _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() {
    super.initState();
    _loadEmps();
    _sc.addListener(_filter);
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<void> _loadEmps() async {
    final r = await _tms.fetchEmployees();
    if (r['success'] == true && r['data'] != null) {
      setState(() {
        _all = List<Map<String, dynamic>>.from(r['data']);
        _f = _all;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _sc.text.toLowerCase();
    setState(() {
      _f = q.isEmpty
          ? _all
          : _all
              .where((e) =>
                  (e['name_parson'] ?? '').toLowerCase().contains(q) ||
                  (e['email'] ?? '').toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _assign() async {
    if (_sel == null) return;
    setState(() => _assigning = true);
    try {
      final r = await _tms.createTicket(
          subject: 'Report Review: ${widget.reportName}',
          message:
              'Please review the ${widget.reportName} report for ${widget.orgName}.',
          priority: _priority,
          timeline: 1440,
          assignedTo: _sel!['_id'].toString());
      setState(() => _assigning = false);
      if (r['success'] == true) {
        widget.onSuccess('Ticket assigned to ${_sel!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else {
        widget.onError(r['message'] ?? 'Failed');
      }
    } catch (e) {
      setState(() => _assigning = false);
      widget.onError('Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
            width: 500,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)]),
                      borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16))),
                  child: Row(children: [
                    const Icon(Icons.confirmation_number_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Raise a Ticket',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text(widget.reportName,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 13),
                              overflow: TextOverflow.ellipsis),
                        ])),
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 18)),
                  ])),
              Flexible(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Priority',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _navy)),
                            const SizedBox(height: 8),
                            Row(
                                children: ['Low', 'Medium', 'High'].map((p) {
                              final sel = _priority == p;
                              final c = p == 'High'
                                  ? _red
                                  : p == 'Medium'
                                      ? _orange
                                      : _green;
                              return Expanded(
                                  child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: GestureDetector(
                                          onTap: () =>
                                              setState(() => _priority = p),
                                          child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 150),
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 9),
                                              decoration: BoxDecoration(
                                                  color: sel ? c : Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color: sel
                                                          ? c
                                                          : Colors.grey[300]!)),
                                              child: Center(
                                                  child: Text(p,
                                                      style:
                                                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.grey[700])))))));
                            }).toList()),
                            const SizedBox(height: 16),
                            const Text('Assign To',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _navy)),
                            const SizedBox(height: 8),
                            TextField(
                                controller: _sc,
                                style: const TextStyle(fontSize: 15),
                                decoration: InputDecoration(
                                    hintText: 'Search employees…',
                                    prefixIcon: Icon(Icons.search,
                                        size: 16, color: Colors.grey[400]),
                                    filled: true,
                                    fillColor: const Color(0xFFF7F9FC),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFDDE3EE))),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFDDE3EE))),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: _navy, width: 1.5)))),
                            const SizedBox(height: 8),
                            _loading
                                ? const SizedBox(
                                    height: 100,
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            color: _navy)))
                                : Container(
                                    constraints:
                                        const BoxConstraints(maxHeight: 220),
                                    decoration: BoxDecoration(
                                        border: Border.all(
                                            color: const Color(0xFFDDE3EE)),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: ListView.separated(
                                        shrinkWrap: true,
                                        itemCount: _f.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(
                                                height: 1,
                                                color: Color(0xFFEEF2F7)),
                                        itemBuilder: (_, i) {
                                          final e = _f[i];
                                          final sel = _sel?['_id'] == e['_id'];
                                          return InkWell(
                                              onTap: () => setState(
                                                  () => _sel = sel ? null : e),
                                              child: Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 9),
                                                  color: sel
                                                      ? _navy.withOpacity(0.06)
                                                      : Colors.transparent,
                                                  child: Row(children: [
                                                    CircleAvatar(
                                                        radius: 16,
                                                        backgroundColor: sel
                                                            ? _navy
                                                            : _navy.withOpacity(
                                                                0.1),
                                                        child: Text(
                                                            (e['name_parson'] ??
                                                                    'U')[0]
                                                                .toUpperCase(),
                                                            style: TextStyle(
                                                                color: sel
                                                                    ? Colors
                                                                        .white
                                                                    : _navy,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 14))),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                          Text(
                                                              e['name_parson'] ??
                                                                  '',
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize:
                                                                      14)),
                                                          if (e[
                                                                  'email'] !=
                                                              null)
                                                            Text(e['email'],
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                            .grey[
                                                                        600]),
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis),
                                                        ])),
                                                    if (sel)
                                                      const Icon(
                                                          Icons.check_circle,
                                                          color: _navy,
                                                          size: 18),
                                                  ])));
                                        })),
                          ]))),
              Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                      color: Color(0xFFF7F9FC),
                      border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
                      borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16))),
                  child: Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey[700],
                                side: BorderSide(color: Colors.grey[300]!),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            child: const Text('Cancel',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600)))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: ElevatedButton(
                            onPressed:
                                (_sel == null || _assigning) ? null : _assign,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _navy,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    _navy.withOpacity(0.35),
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8))),
                            child: _assigning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : Text(
                                    _sel != null
                                        ? 'Assign to ${_sel!['name_parson'] ?? ''}'
                                        : 'Select Employee',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                    overflow: TextOverflow.ellipsis))),
                  ])),
            ])),
      );
}

// =============================================================================
// AGING TABLE — StatefulWidget so ScrollControllers have proper lifecycle
// =============================================================================
class _AgingTableWidget extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final List<String> headers;
  final void Function(Map<String, dynamic>) onRowTap;
  const _AgingTableWidget(
      {required this.rows, required this.headers, required this.onRowTap});
  @override
  State<_AgingTableWidget> createState() => _AgingTableWidgetState();
}

class _AgingTableWidgetState extends State<_AgingTableWidget> {
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    const agingCols = [
      'Current',
      '1-15 Days',
      '16-30 Days',
      '31-45 Days',
      '> 45 Days',
      'Total'
    ];
    const agingKeys = [
      'current',
      'days1_15',
      'days16_30',
      'days31_45',
      'days45Plus',
      'total'
    ];

    final nameKey = widget.headers.contains('customerName')
        ? 'customerName'
        : widget.headers.contains('vendorName')
            ? 'vendorName'
            : (widget.headers.isNotEmpty ? widget.headers.first : 'name');

    final totals = <String, double>{};
    for (final ak in agingKeys) {
      totals[ak] = rows.fold(
          0.0, (s, r) => s + (double.tryParse(r[ak]?.toString() ?? '') ?? 0.0));
    }

    final headerRow = Container(
      color: const Color(0xFF0D1B3E),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        const SizedBox(
            width: 180,
            child: Text('NAME',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3))),
        ...agingCols.map((c) => SizedBox(
            width: 110,
            child: Text(c.toUpperCase(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3)))),
      ]),
    );

    final dataRows = SizedBox(
      height: (rows.length * 52.0 + 20)
          .clamp(80.0, MediaQuery.of(context).size.height * 0.55),
      child: Scrollbar(
        controller: _vScroll,
        thumbVisibility: true,
        child: ScrollConfiguration(
          behavior: _AllDeviceScroll(),
          child: ListView.builder(
            controller: _vScroll,
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final name = r[nameKey]?.toString() ?? '-';
              return InkWell(
                onTap: () => widget.onRowTap(r),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  color: i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                  child: Row(children: [
                    SizedBox(
                        width: 180,
                        child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                color: _navy,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline))),
                    ...agingKeys.map((ak) {
                      final val =
                          double.tryParse(r[ak]?.toString() ?? '') ?? 0.0;
                      Color c = const Color(0xFF374151);
                      if (ak == 'days16_30' && val > 0)
                        c = _orange.withOpacity(0.8);
                      if (ak == 'days31_45' && val > 0) c = _orange;
                      if (ak == 'days45Plus' && val > 0) c = _red;
                      if (ak == 'total') c = _navy;
                      return SizedBox(
                          width: 110,
                          child: Text(
                              val > 0 ? 'Rs. ${val.toStringAsFixed(2)}' : '-',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: c,
                                  fontWeight: ak == 'total'
                                      ? FontWeight.bold
                                      : FontWeight.normal)));
                    }),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );

    final totalsRow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
          border:
              Border(top: BorderSide(color: Color(0xFF1E3A8A), width: 1.5))),
      child: Row(children: [
        const SizedBox(
            width: 180,
            child: Text('TOTAL',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: _navy))),
        ...agingKeys.map((ak) => SizedBox(
            width: 110,
            child: Text('Rs. ${totals[ak]!.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: _navy)))),
      ]),
    );

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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('${rows.length} record${rows.length != 1 ? 's' : ''}',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        const Divider(height: 1),
        Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 7,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                headerRow,
                dataRows,
                totalsRow,
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// LEDGER TABLE — StatefulWidget so ScrollControllers have proper lifecycle
// =============================================================================
class _LedgerTableWidget extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final List<String> headers;
  final void Function(Map<String, dynamic>) onRowTap;
  const _LedgerTableWidget(
      {required this.rows, required this.headers, required this.onRowTap});
  @override
  State<_LedgerTableWidget> createState() => _LedgerTableWidgetState();
}

class _LedgerTableWidgetState extends State<_LedgerTableWidget> {
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

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
        return DateFormat('dd MMM yyyy').format(DateTime.parse(s).toLocal());
      } catch (_) {}
    }
    final hl = h.toLowerCase();
    if (hl.contains('day') || hl.contains('bucket')) return s; // Prevent formatting 'Days Overdue' as currency
    if (hl.contains('debit') ||
        hl.contains('credit') ||
        hl.contains('balance') ||
        hl.contains('amount')) {
      final n = double.tryParse(s.replaceAll(',', '').replaceAll('Rs. ', ''));
      if (n != null) return 'Rs. ${n.toStringAsFixed(2)}';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    final hasDebitCredit =
        widget.headers.contains('debit') || widget.headers.contains('credit');
    const colW = 140.0;
    final visibleHeaders =
        widget.headers.where((h) => h != '_isAccountHeader').toList();

    final headerRow = Container(
      color: const Color(0xFF0D1B3E),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        ...visibleHeaders.map((h) {
          final isAmt = h.toLowerCase().contains('debit') ||
              h.toLowerCase().contains('credit') ||
              h.toLowerCase().contains('balance') ||
              h.toLowerCase().contains('amount');
          return SizedBox(
              width: colW,
              child: Text(_colLabel(h).toUpperCase(),
                  textAlign: isAmt ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3)));
        }),
      ]),
    );

    final dataRows = SizedBox(
      height: (rows.length * 48.0 + 20)
          .clamp(80.0, MediaQuery.of(context).size.height * 0.55),
      child: Scrollbar(
        controller: _vScroll,
        thumbVisibility: true,
        child: ScrollConfiguration(
          behavior: _AllDeviceScroll(),
          child: ListView.builder(
            controller: _vScroll,
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final isAccountRow = r['_isAccountHeader'] == true ||
                  (r['accountCode'] != null &&
                      r['accountCode'].toString().isNotEmpty &&
                      r['date'].toString().isEmpty);
              return InkWell(
                onTap: isAccountRow ? null : () => widget.onRowTap(r),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: isAccountRow
                      ? const Color(0xFFF0F4FF)
                      : (i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC)),
                  child: Row(children: [
                    ...visibleHeaders.map((h) {
                      final v = r[h];
                      final hl = h.toLowerCase();
                      final isAmt = hl.contains('debit') ||
                          hl.contains('credit') ||
                          hl.contains('balance') ||
                          hl.contains('amount');
                      final isName =
                          hl.contains('account') && hl.contains('name');
                      Color? c;
                      if (hl.contains('debit')) c = _orange;
                      if (hl.contains('credit')) c = _green;
                      if (hl == 'balance' || hl == 'closingbalance') c = _navy;
                      if (isAccountRow && h == 'accountName') {
                        return SizedBox(
                            width: colW * 3,
                            child: Text(v?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _navy)));
                      }
                      if (isAccountRow && h != 'accountName')
                        return SizedBox(width: colW);
                      return SizedBox(
                          width: colW,
                          child: Text(_displayVal(h, v),
                              textAlign:
                                  isAmt ? TextAlign.right : TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: c ?? const Color(0xFF374151),
                                  fontWeight:
                                      isAccountRow || hl.contains('total')
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                  decoration: isName
                                      ? TextDecoration.underline
                                      : TextDecoration.none)));
                    }),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Totals row
    final totalDebit = rows.fold(0.0,
        (s, r) => s + (double.tryParse(r['debit']?.toString() ?? '') ?? 0.0));
    final totalCredit = rows.fold(0.0,
        (s, r) => s + (double.tryParse(r['credit']?.toString() ?? '') ?? 0.0));
    final balanced = (totalDebit - totalCredit).abs() < 0.01;

    Widget totalsRow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
          border:
              Border(top: BorderSide(color: Color(0xFF1E3A8A), width: 1.5))),
      child: Row(children: [
        ...visibleHeaders.map((h) {
          final hl = h.toLowerCase();
          final isDebit = hl.contains('debit');
          final isCredit = hl.contains('credit');
          if (!isDebit && !isCredit) {
            return SizedBox(
                width: colW,
                child: h == visibleHeaders.first
                    ? Row(children: [
                        const Text('TOTAL',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _navy)),
                        const SizedBox(width: 8),
                        if (balanced)
                          const Icon(Icons.check_circle,
                              size: 14, color: _green),
                      ])
                    : const SizedBox.shrink());
          }
          return SizedBox(
              width: colW,
              child: Text(
                  isDebit
                      ? 'Rs. ${totalDebit.toStringAsFixed(2)}'
                      : 'Rs. ${totalCredit.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDebit ? _orange : _green)));
        }),
      ]),
    );

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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text('${rows.length} record${rows.length != 1 ? 's' : ''}',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        const Divider(height: 1),
        Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 7,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                headerRow,
                dataRows,
                if (hasDebitCredit) totalsRow,
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// =============================================================================
// LIST TABLE — StatefulWidget so ScrollControllers have proper lifecycle
// =============================================================================
class _ListTableWidget extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final List<String> headers;
  final String search;
  final bool exporting;
  final void Function(Map<String, dynamic>) onRowTap;
  final String Function(String) colLabel;
  final String Function(String, dynamic) displayVal;
  final TextStyle? Function(String, dynamic) cellStyle;
  final Widget Function(String) statusBadge;
  const _ListTableWidget({
    required this.rows,
    required this.headers,
    required this.search,
    required this.exporting,
    required this.onRowTap,
    required this.colLabel,
    required this.displayVal,
    required this.cellStyle,
    required this.statusBadge,
  });
  @override
  State<_ListTableWidget> createState() => _ListTableWidgetState();
}

class _ListTableWidgetState extends State<_ListTableWidget> {
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    if (widget.headers.isEmpty) return const SizedBox.shrink();

    final colW = widget.headers.length <= 4
        ? 240.0
        : widget.headers.length <= 7
            ? 200.0
            : 170.0;
    final tableW = widget.headers.length * colW + 28;

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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text(
                '${rows.length} record${rows.length != 1 ? 's' : ''}${widget.search.isNotEmpty ? " (filtered)" : ""}',
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            if (widget.exporting)
              const SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: _navy)),
          ]),
        ),
        const Divider(height: 1),
        Scrollbar(
          controller: _hScroll,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 7,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableW,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header
                Container(
                  height: 46,
                  color: const Color(0xFF0D1B3E),
                  child: Row(children: [
                    const SizedBox(width: 14),
                    ...widget.headers.map((h) {
                      final hl = h.toLowerCase();
                      final isAmt = hl.contains('amount') ||
                          hl.contains('total') ||
                          hl.contains('balance') ||
                          hl.contains('due') ||
                          hl.contains('paid') ||
                          hl.contains('1-15') ||
                          hl.contains('16-30') ||
                          hl.contains('31-45') ||
                          hl.contains('45 days');
                      return SizedBox(
                          width: colW,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(widget.colLabel(h).toUpperCase(),
                                textAlign:
                                    isAmt ? TextAlign.right : TextAlign.left,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 0.3)),
                          ));
                    }),
                    const SizedBox(width: 14),
                  ]),
                ),
                // Data rows
                SizedBox(
                  height: (rows.length * 56.0 + 20)
                      .clamp(100.0, MediaQuery.of(context).size.height * 0.55),
                  child: Scrollbar(
                    controller: _vScroll,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 7,
                    child: ScrollConfiguration(
                      behavior: _AllDeviceScroll(),
                      child: ListView.builder(
                        controller: _vScroll,
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          final isAccountHeader = r['_isAccountHeader'] == true;
                          return InkWell(
                            onTap: isAccountHeader
                                ? null
                                : () => widget.onRowTap(r),
                            child: Container(
                              constraints: BoxConstraints(
                                  minHeight: isAccountHeader ? 44 : 56),
                              decoration: BoxDecoration(
                                color: isAccountHeader
                                    ? const Color(0xFFEEF2FF)
                                    : (i % 2 == 0
                                        ? Colors.white
                                        : const Color(0xFFF8FAFC)),
                                border: isAccountHeader
                                    ? const Border(
                                        left:
                                            BorderSide(color: _navy, width: 3),
                                        bottom: BorderSide(
                                            color: Color(0xFFDDE3EE)))
                                    : null,
                              ),
                              child: Row(children: [
                                const SizedBox(width: 14),
                                ...widget.headers.map((h) {
                                  final v = r[h];
                                  final hl = h.toLowerCase();
                                  final isAmt = hl.contains('amount') ||
                                      hl.contains('total') ||
                                      hl.contains('balance') ||
                                      hl.contains('due') ||
                                      hl.contains('paid') ||
                                      hl.contains('debit') ||
                                      hl.contains('credit') ||
                                      hl.contains('1-15') ||
                                      hl.contains('16-30') ||
                                      hl.contains('31-45') ||
                                      hl.contains('45 days');
                                  if (isAccountHeader) {
                                    if (h == 'accountName') {
                                      return SizedBox(
                                          width: colW * 2,
                                          child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                              child: Text(v?.toString() ?? '',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _navy))));
                                    }
                                    if (h == 'accountType') {
                                      return SizedBox(
                                          width: colW,
                                          child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                              child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 3),
                                                  decoration: BoxDecoration(
                                                      color: _navy
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10)),
                                                  child: Text(
                                                      v?.toString() ?? '',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: _navy)))));
                                    }
                                    return SizedBox(width: colW);
                                  }
                                  return SizedBox(
                                      width: colW,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: h.toLowerCase() == 'status'
                                            ? Align(
                                                alignment: isAmt ? Alignment.centerRight : Alignment.centerLeft,
                                                child: widget.statusBadge(v?.toString() ?? ''))
                                            : Text(widget.displayVal(h, v),
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: isAmt
                                                    ? TextAlign.right
                                                    : TextAlign.left,
                                                style: widget.cellStyle(h, v) ??
                                                    const TextStyle(
                                                        fontSize: 14,
                                                        color: Color(0xFF374151))),
                                      ));
                                }),
                                const SizedBox(width: 14),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
