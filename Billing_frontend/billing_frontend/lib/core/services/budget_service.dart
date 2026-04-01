// ============================================================================
// BUDGET SERVICE
// ============================================================================
// File: lib/core/services/budget_service.dart
// All API calls — NO hardcoded URLs — uses ApiConfig.baseUrl
// Token: SharedPreferences jwt_token
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';

// ============================================================================
// MODELS
// ============================================================================

class BudgetAccountLine {
  final String? accountId;
  final String accountName;
  final String accountType;
  // Monthly amounts [Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec, Jan, Feb, Mar]
  final List<double> monthlyAmounts;
  // Actual amounts from COA (read-only, returned from backend)
  final List<double> actualMonthly;
  final double totalBudgeted;
  final double totalActual;
  final double variance;
  final double percentUsed;

  BudgetAccountLine({
    this.accountId,
    required this.accountName,
    required this.accountType,
    required this.monthlyAmounts,
    this.actualMonthly = const [],
    this.totalBudgeted = 0,
    this.totalActual = 0,
    this.variance = 0,
    this.percentUsed = 0,
  });

  factory BudgetAccountLine.fromJson(Map<String, dynamic> j) => BudgetAccountLine(
        accountId: j['accountId'],
        accountName: j['accountName'] ?? '',
        accountType: j['accountType'] ?? '',
        monthlyAmounts: List<double>.from(
            (j['monthlyAmounts'] as List? ?? List.filled(12, 0))
                .map((v) => (v ?? 0).toDouble())),
        actualMonthly: List<double>.from(
            (j['actualMonthly'] as List? ?? [])
                .map((v) => (v ?? 0).toDouble())),
        totalBudgeted: (j['totalBudgeted'] ?? 0).toDouble(),
        totalActual: (j['totalActual'] ?? 0).toDouble(),
        variance: (j['variance'] ?? 0).toDouble(),
        percentUsed: (j['percentUsed'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'accountName': accountName,
        'accountType': accountType,
        'monthlyAmounts': monthlyAmounts,
      };

  BudgetAccountLine copyWith({List<double>? monthlyAmounts}) => BudgetAccountLine(
        accountId: accountId,
        accountName: accountName,
        accountType: accountType,
        monthlyAmounts: monthlyAmounts ?? this.monthlyAmounts,
        actualMonthly: actualMonthly,
        totalBudgeted: totalBudgeted,
        totalActual: totalActual,
        variance: variance,
        percentUsed: percentUsed,
      );
}

class Budget {
  final String id;
  final String budgetName;
  final String financialYear; // e.g. "2025-26"
  final String budgetPeriod; // "Monthly" | "Quarterly" | "Yearly"
  final String currency;
  final bool isActive;
  final String? notes;
  final List<BudgetAccountLine> accountLines;
  final double totalBudgeted;
  final double totalActual;
  final double totalVariance;
  final DateTime createdAt;
  final DateTime updatedAt;

  Budget({
    required this.id,
    required this.budgetName,
    required this.financialYear,
    required this.budgetPeriod,
    required this.currency,
    required this.isActive,
    this.notes,
    required this.accountLines,
    this.totalBudgeted = 0,
    this.totalActual = 0,
    this.totalVariance = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        id: j['_id'] ?? j['id'] ?? '',
        budgetName: j['budgetName'] ?? '',
        financialYear: j['financialYear'] ?? '',
        budgetPeriod: j['budgetPeriod'] ?? 'Monthly',
        currency: j['currency'] ?? 'INR',
        isActive: j['isActive'] ?? true,
        notes: j['notes'],
        accountLines: (j['accountLines'] as List? ?? [])
            .map((l) => BudgetAccountLine.fromJson(l))
            .toList(),
        totalBudgeted: (j['totalBudgeted'] ?? 0).toDouble(),
        totalActual: (j['totalActual'] ?? 0).toDouble(),
        totalVariance: (j['totalVariance'] ?? 0).toDouble(),
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
      );
}

class BudgetStats {
  final int totalBudgets;
  final int activeBudgets;
  final int inactiveBudgets;
  final double totalBudgeted;
  final double totalActual;

  BudgetStats({
    required this.totalBudgets,
    required this.activeBudgets,
    required this.inactiveBudgets,
    required this.totalBudgeted,
    required this.totalActual,
  });

  factory BudgetStats.fromJson(Map<String, dynamic> j) => BudgetStats(
        totalBudgets: j['totalBudgets'] ?? 0,
        activeBudgets: j['activeBudgets'] ?? 0,
        inactiveBudgets: j['inactiveBudgets'] ?? 0,
        totalBudgeted: (j['totalBudgeted'] ?? 0).toDouble(),
        totalActual: (j['totalActual'] ?? 0).toDouble(),
      );
}

class BudgetListResult {
  final List<Budget> budgets;
  final int total;
  final int page;
  final int pages;

  BudgetListResult({
    required this.budgets,
    required this.total,
    required this.page,
    required this.pages,
  });
}

// ============================================================================
// SERVICE
// ============================================================================

class BudgetService {
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static String get _base => '${ApiConfig.baseUrl}/api/finance/budgets';

  // ── Stats ─────────────────────────────────────────────────────────────────

  static Future<BudgetStats> getStats() async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/stats'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load stats');
    return BudgetStats.fromJson(body['data']);
  }

  // ── List ──────────────────────────────────────────────────────────────────

  static Future<BudgetListResult> getBudgets({
    bool? isActive,
    String? financialYear,
    String? budgetPeriod,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (isActive != null) params['isActive'] = isActive.toString();
    if (financialYear != null && financialYear != 'All') params['financialYear'] = financialYear;
    if (budgetPeriod != null && budgetPeriod != 'All') params['budgetPeriod'] = budgetPeriod;
    if (search != null && search.isNotEmpty) params['search'] = search;

    final uri = Uri.parse(_base).replace(queryParameters: params);
    final res = await http.get(uri, headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load budgets');

    final data = body['data'];
    return BudgetListResult(
      budgets: (data['budgets'] as List).map((j) => Budget.fromJson(j)).toList(),
      total: data['pagination']?['total'] ?? 0,
      page: data['pagination']?['page'] ?? 1,
      pages: data['pagination']?['pages'] ?? 1,
    );
  }

  // ── All for export ────────────────────────────────────────────────────────

  static Future<List<Budget>> getAllBudgets() async {
    final result = await getBudgets(limit: 1000);
    return result.budgets;
  }

  // ── Single ────────────────────────────────────────────────────────────────

  static Future<Budget> getBudget(String id) async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/$id'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load budget');
    return Budget.fromJson(body['data']);
  }

  // ── Actuals (with COA comparison) ─────────────────────────────────────────

  static Future<Budget> getBudgetWithActuals(String id) async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/$id/actuals'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load actuals');
    return Budget.fromJson(body['data']);
  }

  // ── Create ────────────────────────────────────────────────────────────────

  static Future<Budget> createBudget(Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final res = await http.post(
      Uri.parse(_base),
      headers: headers,
      body: jsonEncode(data),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['message'] ?? 'Failed to create budget');
    return Budget.fromJson(body['data']);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  static Future<Budget> updateBudget(String id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final res = await http.put(
      Uri.parse('$_base/$id'),
      headers: headers,
      body: jsonEncode(data),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to update budget');
    return Budget.fromJson(body['data']);
  }

  // ── Toggle Active ─────────────────────────────────────────────────────────

  static Future<Budget> toggleActive(String id, bool isActive) async {
    final headers = await _getHeaders();
    final res = await http.patch(
      Uri.parse('$_base/$id/toggle-active'),
      headers: headers,
      body: jsonEncode({'isActive': isActive}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to update budget');
    return Budget.fromJson(body['data']);
  }

  // ── Clone ─────────────────────────────────────────────────────────────────

  static Future<Budget> cloneBudget(String id, String newName, String newYear) async {
    final headers = await _getHeaders();
    final res = await http.post(
      Uri.parse('$_base/$id/clone'),
      headers: headers,
      body: jsonEncode({'budgetName': newName, 'financialYear': newYear}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['message'] ?? 'Failed to clone budget');
    return Budget.fromJson(body['data']);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteBudget(String id) async {
    final headers = await _getHeaders();
    final res = await http.delete(Uri.parse('$_base/$id'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to delete budget');
  }

  // ── Bulk Import ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> bulkImport(
    List<Map<String, dynamic>> budgets,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';

    final request = http.MultipartRequest('POST', Uri.parse('$_base/import'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
    request.fields['budgets'] = jsonEncode(budgets);

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Import failed');
    return body;
  }
}
