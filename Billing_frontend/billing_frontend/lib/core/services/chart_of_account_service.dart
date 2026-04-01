// ============================================================================
// CHART OF ACCOUNTS SERVICE
// ============================================================================
// File: lib/core/services/chart_of_account_service.dart
// All API calls - NO hardcoded URLs - uses ApiConfig.baseUrl
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';

// ============================================================================
// MODELS
// ============================================================================

class ChartOfAccount {
  final String id;
  final String accountCode;
  final String accountName;
  final String accountType;
  final String accountSubType;
  final String? parentAccountId;
  final String? parentAccountName;
  final String? description;
  final String currency;
  final bool isActive;
  final bool isSystemAccount;
  final double closingBalance;
  final String balanceType; // 'Dr' or 'Cr'
  final int transactionCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChartOfAccount({
    required this.id,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.accountSubType,
    this.parentAccountId,
    this.parentAccountName,
    this.description,
    required this.currency,
    required this.isActive,
    required this.isSystemAccount,
    required this.closingBalance,
    required this.balanceType,
    required this.transactionCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChartOfAccount.fromJson(Map<String, dynamic> j) => ChartOfAccount(
    id: j['_id'] ?? j['id'] ?? '',
    accountCode: j['accountCode'] ?? '',
    accountName: j['accountName'] ?? '',
    accountType: j['accountType'] ?? '',
    accountSubType: j['accountSubType'] ?? '',
    parentAccountId: j['parentAccountId'],
    parentAccountName: j['parentAccountName'],
    description: j['description'],
    currency: j['currency'] ?? 'INR',
    isActive: j['isActive'] ?? true,
    isSystemAccount: j['isSystemAccount'] ?? false,
    closingBalance: (j['closingBalance'] ?? 0).toDouble(),
    balanceType: j['balanceType'] ?? 'Dr',
    transactionCount: j['transactionCount'] ?? 0,
    createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'accountCode': accountCode,
    'accountName': accountName,
    'accountType': accountType,
    'accountSubType': accountSubType,
    'parentAccountId': parentAccountId,
    'description': description,
    'currency': currency,
    'isActive': isActive,
  };
}

class AccountTransaction {
  final String id;
  final DateTime date;
  final String description;
  final String referenceType;
  final String referenceNumber;
  final double debit;
  final double credit;
  final double balance;

  AccountTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.referenceType,
    required this.referenceNumber,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  factory AccountTransaction.fromJson(Map<String, dynamic> j) => AccountTransaction(
    id: j['_id'] ?? j['id'] ?? '',
    date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
    description: j['description'] ?? '',
    referenceType: j['referenceType'] ?? '',
    referenceNumber: j['referenceNumber'] ?? '',
    debit: (j['debit'] ?? 0).toDouble(),
    credit: (j['credit'] ?? 0).toDouble(),
    balance: (j['balance'] ?? 0).toDouble(),
  );
}

class CoaStats {
  final int totalAccounts;
  final int activeAccounts;
  final int inactiveAccounts;
  final Map<String, int> byType;

  CoaStats({
    required this.totalAccounts,
    required this.activeAccounts,
    required this.inactiveAccounts,
    required this.byType,
  });

  factory CoaStats.fromJson(Map<String, dynamic> j) => CoaStats(
    totalAccounts: j['totalAccounts'] ?? 0,
    activeAccounts: j['activeAccounts'] ?? 0,
    inactiveAccounts: j['inactiveAccounts'] ?? 0,
    byType: Map<String, int>.from(j['byType'] ?? {}),
  );
}

class CoaListResult {
  final List<ChartOfAccount> accounts;
  final int total;
  final int page;
  final int pages;

  CoaListResult({
    required this.accounts,
    required this.total,
    required this.page,
    required this.pages,
  });
}

// ============================================================================
// SERVICE
// ============================================================================

class ChartOfAccountService {
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static String get _base => '${ApiConfig.baseUrl}/api/finance/chart-of-accounts';

  // ── List ──────────────────────────────────────────────────────────────────

  static Future<CoaListResult> getAccounts({
    String? accountType,
    bool? isActive,
    String? search,
    int page = 1,
    int limit = 200,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (accountType != null) params['accountType'] = accountType;
    if (isActive != null) params['isActive'] = isActive.toString();
    if (search != null && search.isNotEmpty) params['search'] = search;

    final uri = Uri.parse(_base).replace(queryParameters: params);
    final res = await http.get(uri, headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load accounts');

    final data = body['data'];
    return CoaListResult(
      accounts: (data['accounts'] as List).map((j) => ChartOfAccount.fromJson(j)).toList(),
      total: data['pagination']?['total'] ?? 0,
      page: data['pagination']?['page'] ?? 1,
      pages: data['pagination']?['pages'] ?? 1,
    );
  }

  // ── All for export ────────────────────────────────────────────────────────

  static Future<List<ChartOfAccount>> getAllAccounts() async {
    final result = await getAccounts(limit: 10000);
    return result.accounts;
  }

  // ── Single ────────────────────────────────────────────────────────────────

  static Future<ChartOfAccount> getAccount(String id) async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/$id'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load account');
    return ChartOfAccount.fromJson(body['data']);
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  static Future<List<AccountTransaction>> getTransactions(
    String id, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{};
    if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
    if (toDate != null) params['toDate'] = toDate.toIso8601String();

    final uri = Uri.parse('$_base/$id/transactions').replace(queryParameters: params);
    final res = await http.get(uri, headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load transactions');
    return (body['data'] as List).map((j) => AccountTransaction.fromJson(j)).toList();
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  static Future<CoaStats> getStats() async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/stats'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to load stats');
    return CoaStats.fromJson(body['data']);
  }

  // ── Create ────────────────────────────────────────────────────────────────

  static Future<ChartOfAccount> createAccount(Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final res = await http.post(
      Uri.parse(_base),
      headers: headers,
      body: jsonEncode(data),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['message'] ?? 'Failed to create account');
    return ChartOfAccount.fromJson(body['data']);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  static Future<ChartOfAccount> updateAccount(String id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final res = await http.put(
      Uri.parse('$_base/$id'),
      headers: headers,
      body: jsonEncode(data),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to update account');
    return ChartOfAccount.fromJson(body['data']);
  }

  // ── Toggle Active ─────────────────────────────────────────────────────────

  static Future<ChartOfAccount> toggleActive(String id, bool isActive) async {
    final headers = await _getHeaders();
    final res = await http.patch(
      Uri.parse('$_base/$id/toggle-active'),
      headers: headers,
      body: jsonEncode({'isActive': isActive}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to update account');
    return ChartOfAccount.fromJson(body['data']);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteAccount(String id) async {
    final headers = await _getHeaders();
    final res = await http.delete(Uri.parse('$_base/$id'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to delete account');
  }

  // ── Bulk Import ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> bulkImport(
    List<Map<String, dynamic>> accounts,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/import'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
    request.fields['accounts'] = jsonEncode(accounts);

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Import failed');
    return body;
  }

  // ── Parent accounts for dropdown ──────────────────────────────────────────

  static Future<List<ChartOfAccount>> getParentAccounts() async {
    final result = await getAccounts(isActive: true, limit: 500);
    return result.accounts;
  }
}