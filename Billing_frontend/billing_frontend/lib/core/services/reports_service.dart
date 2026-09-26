// ============================================================================
// REPORTS SERVICE — COMPLETE (79 REPORTS)
// ============================================================================
// File: lib/core/services/reports_service.dart
//
// - All 79 reports wired to /api/finance/reports/*
// - exportExcel() calls backend → returns real .xlsx binary → saves/downloads
// - exportPDF()   calls backend → returns real PDF binary  → saves/downloads
// - Token read from SharedPreferences key 'jwt_token' (matches ApiService)
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

import '../../app/config/api_config.dart';
import '../services/api_service.dart';
import '../finance_secure_storage.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class ReportCategory {
  final String category;
  final List<ReportMeta> reports;
  ReportCategory({required this.category, required this.reports});
  factory ReportCategory.fromJson(Map<String, dynamic> j) => ReportCategory(
        category: j['category'] as String,
        reports: (j['reports'] as List)
            .map((r) => ReportMeta.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

class ReportMeta {
  final String key;
  final String name;
  final String? accountId;
  ReportMeta({required this.key, required this.name, this.accountId});
  factory ReportMeta.fromJson(Map<String, dynamic> j) => ReportMeta(
        key: j['key'] as String,
        name: j['name'] as String,
        accountId: j['accountId'] as String?,
      );
}

// ─── Service ─────────────────────────────────────────────────────────────────

class ReportsService {
  static final ApiService _api = ApiService();
  static const String _base = '/api/finance/reports';
  static const String _tokenKey =
      'jwt_token'; // must match ApiService._tokenKey

  // ── Private helpers ───────────────────────────────────────────────────────

  static String get _baseUrl => '${ApiConfig.baseUrl}$_base';

  static Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Calls a GET endpoint and returns data['data'].
  static Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? params,
  ]) async {
    final res = await _api.get('$_base$path', queryParams: params);
    return (res['data'] ?? res) as Map<String, dynamic>;
  }

  // ── Meta ──────────────────────────────────────────────────────────────────

  static Future<List<ReportCategory>> getMeta() async {
    final res = await _api.get('$_base/meta');
    return (res['data'] as List)
        .map((c) => ReportCategory.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  // =========================================================================
  // UNIVERSAL FETCH — called by ReportViewerPage for every report
  // =========================================================================

  static Future<Map<String, dynamic>> fetchReport(
    String reportKey,
    Map<String, String> params,
  ) async {
    const endpoints = {
      // ── Business Overview (9) ─────────────────────────────────────────────
      'profit-loss': '/profit-loss',
      'profit-loss-horizontal': '/profit-loss-horizontal',
      'balance-sheet': '/balance-sheet',
      'balance-sheet-horizontal': '/balance-sheet-horizontal',
      'cash-flow': '/cash-flow',
      'movement-of-equity': '/movement-of-equity',
      'performance-ratios': '/performance-ratios',
      'trial-balance': '/trial-balance',
      'day-book': '/day-book',
      // ── Sales (4) ─────────────────────────────────────────────────────────
      'sales-by-customer': '/sales-by-customer',
      'sales-by-item': '/sales-by-item',
      'sales-by-salesperson': '/sales-by-salesperson',
      'sales-summary': '/sales-summary',
      // ── Receivables (8) ───────────────────────────────────────────────────
      'ar-aging-summary': '/ar-aging-summary',
      'ar-aging-details': '/ar-aging-details',
      'invoice-details': '/invoice-details',
      'customer-balance': '/customer-balance',
      'receivable-summary': '/receivable-summary',
      'receivable-details': '/receivable-details',
      'credit-note-details': '/credit-note-details',
      'refund-history-receivables': '/refund-history-receivables',
      // ── Payments Received (4) ─────────────────────────────────────────────
      'payments-received': '/payments-received',
      'time-to-get-paid': '/time-to-get-paid',
      'refund-history': '/refund-history',
      'recurring-invoice-details': '/recurring-invoice-details',
      // ── Payables (11) ────────────────────────────────────────────────────
      'vendor-balance': '/vendor-balance',
      'ap-aging-summary': '/ap-aging-summary',
      'ap-aging-details': '/ap-aging-details',
      'bill-details': '/bill-details',
      'vendor-credit-details': '/vendor-credit-details',
      'payments-made': '/payments-made',
      'refund-history-payables': '/refund-history-payables',
      'purchase-order-details': '/purchase-order-details',
      'purchase-orders-by-vendor': '/purchase-orders-by-vendor',
      'payable-summary': '/payable-summary',
      'payable-details': '/payable-details',
      // ── Purchases & Expenses (8) ─────────────────────────────────────────
      'purchases-by-vendor': '/purchases-by-vendor',
      'purchases-by-item': '/purchases-by-item',
      'expense-details': '/expense-details',
      'expenses-by-category': '/expenses-by-category',
      'expenses-by-customer': '/expenses-by-customer',
      'expenses-by-project': '/expenses-by-project',
      'expenses-by-employee': '/expenses-by-employee',
      'billable-expenses': '/billable-expenses',
      // ── Taxes (3) ────────────────────────────────────────────────────────
      'tds-summary': '/tds-summary',
      'tds-receivable': '/tds-receivable',
      'tds-receivable-details': '/tds-receivable-details',
      'tcs-summary': '/tcs-summary',
      // ── Banking (1) ──────────────────────────────────────────────────────
      'reconciliation-status': '/reconciliation-status',
      // ── Projects & Timesheet (7) ─────────────────────────────────────────
      'timesheet-details': '/timesheet-details',
      'timesheet-profitability': '/timesheet-profitability',
      'project-summary': '/project-summary',
      'project-details': '/project-details',
      'projects-cost-summary': '/projects-cost-summary',
      'projects-revenue-summary': '/projects-revenue-summary',
      'projects-performance': '/projects-performance',
      // ── Accountant (6) ───────────────────────────────────────────────────
      'account-transactions': '/account-transactions',
      'account-type-summary': '/account-type-summary',
      'account-type-transactions': '/account-type-transactions',
      'general-ledger': '/general-ledger',
      'general-ledger-detailed': '/general-ledger-detailed',
      'journal-report': '/journal-report',
      'journal-entries-by-reference': '/journal-entries-by-reference',
      'activity-logs': '/activity-logs',
      // ── Budgets (1) ──────────────────────────────────────────────────────
      'budget-vs-actuals': '/budget-vs-actuals',
      // ── Currency (2) ─────────────────────────────────────────────────────
      'realized-gain-loss': '/realized-gain-loss',
      'unrealized-gain-loss': '/unrealized-gain-loss',
      // ── Activity (5) ─────────────────────────────────────────────────────
      'system-mails': '/system-mails',
      'audit-trail': '/audit-trail',
      'exception-report': '/exception-report',
      'portal-activities': '/portal-activities',
      'customer-reviews': '/customer-reviews',
      // ── Automation (2) ───────────────────────────────────────────────────
      'api-usage': '/api-usage',
      'workflow-logs': '/workflow-logs',
    };

    final path = endpoints[reportKey];
    if (path == null) throw Exception('Unknown report key: $reportKey');

    final res = await _api.get('$_base$path', queryParams: params);
    return (res['data'] ?? res) as Map<String, dynamic>;
  }

  // =========================================================================
  // EXPORT PDF — backend renders, Flutter downloads binary
  // =========================================================================

  /// Sends report data to backend → backend returns a real PDF binary.
  /// Saves to device (mobile) or triggers browser download (web).
  static Future<String> exportPDF({
    required String reportName,
    required String companyName,
    required List<Map<String, dynamic>> reportData,
    Map<String, dynamic>? period,
    List<String>? headers,
  }) async {
    if (reportData.isEmpty) throw Exception('No data to export');

    final token = await _getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated');

    final uri = Uri.parse('$_baseUrl/export/pdf');
    debugPrint('📤 POST PDF export → $uri');

    final branchHeader = await FinanceSecureStorage.getBranchHeader();

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'x-branch-ids': branchHeader,
          },
          body: jsonEncode({
            'reportName': reportName,
            'companyName': companyName,
            'reportData': reportData,
            if (period != null) 'period': period,
            if (headers != null) 'headers': headers,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception(
          'PDF export failed: ${response.statusCode} ${response.body}');
    }

    return _saveOrDownloadBytes(
      bytes: response.bodyBytes,
      filename: '${reportName.replaceAll(' ', '_')}_${_ts()}.pdf',
      mimeType: 'application/pdf',
    );
  }

  // =========================================================================
  // EXPORT EXCEL — backend builds real .xlsx, Flutter downloads binary
  // =========================================================================

  /// Sends report data to backend → backend returns a real .xlsx binary.
  /// Saves to device (mobile) or triggers browser download (web).
  static Future<String> exportExcel({
    required String reportName,
    required String companyName,
    required List<Map<String, dynamic>> reportData,
    Map<String, dynamic>? period,
    List<String>? headers,
  }) async {
    if (reportData.isEmpty) throw Exception('No data to export');

    final token = await _getToken();
    if (token == null || token.isEmpty) throw Exception('Not authenticated');

    final uri = Uri.parse('$_baseUrl/export/excel');
    debugPrint('📤 POST Excel export → $uri');

    final branchHeader = await FinanceSecureStorage.getBranchHeader();

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'x-branch-ids': branchHeader,
          },
          body: jsonEncode({
            'reportName': reportName,
            'companyName': companyName,
            'reportData': reportData,
            if (period != null) 'period': period,
            if (headers != null) 'headers': headers,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception(
          'Excel export failed: ${response.statusCode} ${response.body}');
    }

    return _saveOrDownloadBytes(
      bytes: response.bodyBytes,
      filename: '${reportName.replaceAll(' ', '_')}_${_ts()}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  // ─── Private: save bytes on mobile or trigger download on web ─────────────

  static Future<String> _saveOrDownloadBytes({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      // Web: trigger browser download
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
      debugPrint('✅ Web download triggered: $filename');
      return filename;
    } else {
      // Mobile / Desktop: save to documents folder
      Directory dir;
      try {
        dir = await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = Directory.systemTemp;
      }
      final filePath = '${dir.path}/$filename';
      await File(filePath).writeAsBytes(bytes);
      debugPrint('✅ File saved: $filePath');
      return filePath;
    }
  }

  static String _ts() => DateTime.now().millisecondsSinceEpoch.toString();
}
