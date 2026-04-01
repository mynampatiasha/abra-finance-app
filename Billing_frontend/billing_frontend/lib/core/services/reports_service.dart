// ============================================================================
// REPORTS SERVICE
// ============================================================================
// File: lib/core/services/reports_service.dart
// All API calls via ApiService — no hardcoded URLs or tokens
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/api_service.dart';
import '../../app/config/api_config.dart';

class ReportsService {
  static final ApiService _api = ApiService();
  static const String _base = '/api/finance/reports';
  static String get _baseUrl => '${ApiConfig.baseUrl}$_base';

  // ── Meta ──────────────────────────────────────────────────────────────────
  static Future<List<ReportCategory>> getMeta() async {
    final data = await _api.get('$_base/meta');
    return (data['data'] as List)
        .map((c) => ReportCategory.fromJson(c))
        .toList();
  }

  // ── Business Overview ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getProfitLoss(Map<String, String> params) async {
    final data = await _api.get('$_base/profit-loss', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getBalanceSheet(Map<String, String> params) async {
    final data = await _api.get('$_base/balance-sheet', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getCashFlow(Map<String, String> params) async {
    final data = await _api.get('$_base/cash-flow', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getTrialBalance(Map<String, String> params) async {
    final data = await _api.get('$_base/trial-balance', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getPerformanceRatios(Map<String, String> params) async {
    final data = await _api.get('$_base/performance-ratios', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getProfitLossHorizontal(Map<String, String> params) async {
    final data = await _api.get('$_base/profit-loss-horizontal', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getBalanceSheetHorizontal(Map<String, String> params) async {
    final data = await _api.get('$_base/balance-sheet-horizontal', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getMovementOfEquity(Map<String, String> params) async {
    final data = await _api.get('$_base/movement-of-equity', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getDayBook(Map<String, String> params) async {
    final data = await _api.get('$_base/day-book', queryParams: params);
    return data['data'];
  }

  // ── Sales ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getSalesByCustomer(Map<String, String> params) async {
    final data = await _api.get('$_base/sales-by-customer', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getSalesByItem(Map<String, String> params) async {
    final data = await _api.get('$_base/sales-by-item', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getSalesSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/sales-summary', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getSalesBySalesperson(Map<String, String> params) async {
    final data = await _api.get('$_base/sales-by-salesperson', queryParams: params);
    return data['data'];
  }

  // ── Receivables ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getARAgingSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/ar-aging-summary', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getARAgingDetails(Map<String, String> params) async {
    final data = await _api.get('$_base/ar-aging-details', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getCustomerBalance(Map<String, String> params) async {
    final data = await _api.get('$_base/customer-balance', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getInvoiceDetails(Map<String, String> params) async {
    final data = await _api.get('$_base/invoice-details', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getPaymentsReceived(Map<String, String> params) async {
    final data = await _api.get('$_base/payments-received', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getCreditNoteDetails(Map<String, String> params) async {
    final data = await _api.get('$_base/credit-note-details', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getReceivableSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/receivable-summary', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getRefundHistoryReceivables(Map<String, String> params) async {
    final data = await _api.get('$_base/refund-history-receivables', queryParams: params);
    return data['data'];
  }

  // ── Payables ──────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getAPAgingSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/ap-aging-summary', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getAPAgingDetails(Map<String, String> params) async {
    final data = await _api.get('$_base/ap-aging-details', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getVendorBalance(Map<String, String> params) async {
    final data = await _api.get('$_base/vendor-balance', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getBillDetails(Map<String, String> params) async {
    final data = await _api.get('$_base/bill-details', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getPaymentsMade(Map<String, String> params) async {
    final data = await _api.get('$_base/payments-made', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getVendorCreditDetails(Map<String, String> params) async {
    final data = await _api.get('$_base/vendor-credit-details', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getPayableSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/payable-summary', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getRefundHistoryPayables(Map<String, String> params) async {
    final data = await _api.get('$_base/refund-history-payables', queryParams: params);
    return data['data'];
  }

  // ── Purchases & Expenses ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getPurchasesByVendor(Map<String, String> params) async {
    final data = await _api.get('$_base/purchases-by-vendor', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getPurchasesByItem(Map<String, String> params) async {
    final data = await _api.get('$_base/purchases-by-item', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getExpenseDetails(Map<String, String> params) async {
    final data = await _api.get('$_base/expense-details', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getExpensesByCategory(Map<String, String> params) async {
    final data = await _api.get('$_base/expenses-by-category', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getBillableExpenses(Map<String, String> params) async {
    final data = await _api.get('$_base/billable-expenses', queryParams: params);
    return data['data'];
  }

  // ── Taxes ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getTDSSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/tds-summary', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getTDSReceivable(Map<String, String> params) async {
    final data = await _api.get('$_base/tds-receivable', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getTCSSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/tcs-summary', queryParams: params);
    return data['data'];
  }

  // ── Accountant ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getGeneralLedger(Map<String, String> params) async {
    final data = await _api.get('$_base/general-ledger', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getGeneralLedgerDetailed(Map<String, String> params) async {
    final data = await _api.get('$_base/general-ledger-detailed', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getAccountTransactions(Map<String, String> params) async {
    final data = await _api.get('$_base/account-transactions', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getAccountTypeSummary(Map<String, String> params) async {
    final data = await _api.get('$_base/account-type-summary', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getJournalReport(Map<String, String> params) async {
    final data = await _api.get('$_base/journal-report', queryParams: params);
    return data['data'];
  }

  static Future<Map<String, dynamic>> getActivityLogs(Map<String, String> params) async {
    final data = await _api.get('$_base/activity-logs', queryParams: params);
    return data['data'];
  }

  // ── Universal fetch by report key ─────────────────────────────────────────
  static Future<Map<String, dynamic>> fetchReport(
      String reportKey, Map<String, String> params) async {
    final endpointMap = {
      'profit-loss':               '/profit-loss',
      'balance-sheet':             '/balance-sheet',
      'cash-flow':                 '/cash-flow',
      'trial-balance':             '/trial-balance',
      'performance-ratios':        '/performance-ratios',
      'profit-loss-horizontal':    '/profit-loss-horizontal',
      'balance-sheet-horizontal':  '/balance-sheet-horizontal',
      'movement-of-equity':        '/movement-of-equity',
      'day-book':                  '/day-book',
      'sales-by-customer':         '/sales-by-customer',
      'sales-by-item':             '/sales-by-item',
      'sales-summary':             '/sales-summary',
      'sales-by-salesperson':      '/sales-by-salesperson',
      'ar-aging-summary':          '/ar-aging-summary',
      'ar-aging-details':          '/ar-aging-details',
      'customer-balance':          '/customer-balance',
      'invoice-details':           '/invoice-details',
      'payments-received':         '/payments-received',
      'credit-note-details':       '/credit-note-details',
      'receivable-summary':        '/receivable-summary',
      'refund-history-receivables':'/refund-history-receivables',
      'ap-aging-summary':          '/ap-aging-summary',
      'ap-aging-details':          '/ap-aging-details',
      'vendor-balance':            '/vendor-balance',
      'bill-details':              '/bill-details',
      'payments-made':             '/payments-made',
      'vendor-credit-details':     '/vendor-credit-details',
      'payable-summary':           '/payable-summary',
      'refund-history-payables':   '/refund-history-payables',
      'purchases-by-vendor':       '/purchases-by-vendor',
      'purchases-by-item':         '/purchases-by-item',
      'expense-details':           '/expense-details',
      'expenses-by-category':      '/expenses-by-category',
      'billable-expenses':         '/billable-expenses',
      'tds-summary':               '/tds-summary',
      'tds-receivable':            '/tds-receivable',
      'tcs-summary':               '/tcs-summary',
      'general-ledger':            '/general-ledger',
      'general-ledger-detailed':   '/general-ledger-detailed',
      'account-transactions':      '/account-transactions',
      'account-type-summary':      '/account-type-summary',
      'journal-report':            '/journal-report',
      'activity-logs':             '/activity-logs',
    };

    final endpoint = endpointMap[reportKey];
    if (endpoint == null) throw Exception('Unknown report: $reportKey');

    final data = await _api.get('$_base$endpoint', queryParams: params);
    return data['data'];
  }

  // ── Export PDF (sends data to backend, downloads PDF) ────────────────────
  static Future<String> exportPDF({
    required String reportName,
    required List<Map<String, dynamic>> reportData,
    required String companyName,
    Map<String, dynamic>? period,
  }) async {
    final data = await _api.post('$_base/export/pdf', body: {
      'reportName': reportName,
      'reportData': reportData,
      'companyName': companyName,
      if (period != null) 'period': period,
    });
    return data['downloadUrl'] ?? '';
  }

  // ── Export Excel (sends data to backend, downloads Excel) ────────────────
  static Future<Uint8List> exportExcel({
    required String reportName,
    required List<Map<String, dynamic>> reportData,
    required String companyName,
    Map<String, dynamic>? period,
    List<String>? headers,
  }) async {
    // Use raw HTTP to get binary response
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final uri = Uri.parse('$_baseUrl/export/excel');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'reportName': reportName,
        'reportData': reportData,
        'companyName': companyName,
        if (period  != null) 'period': period,
        if (headers != null) 'headers': headers,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Export failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}

// ============================================================================
// MODELS
// ============================================================================

class ReportCategory {
  final String category;
  final List<ReportMeta> reports;

  ReportCategory({required this.category, required this.reports});

  factory ReportCategory.fromJson(Map<String, dynamic> json) => ReportCategory(
    category: json['category'],
    reports:  (json['reports'] as List).map((r) => ReportMeta.fromJson(r)).toList(),
  );
}

class ReportMeta {
  final String key;
  final String name;
  final String endpoint;

  ReportMeta({required this.key, required this.name, required this.endpoint});

  factory ReportMeta.fromJson(Map<String, dynamic> json) => ReportMeta(
    key:      json['key'],
    name:     json['name'],
    endpoint: json['endpoint'],
  );
}