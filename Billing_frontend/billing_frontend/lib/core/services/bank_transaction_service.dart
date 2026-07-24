// ============================================================================
// BANK TRANSACTION SERVICE — COMPLETE WITH ALL NEW API CALLS
// ============================================================================
// File: lib/core/services/bank_transaction_service.dart
//
// New methods added:
//   getAllTransactions()      — for "All Transactions" sub-tab
//   getPossibleMatches()      — for right panel "Match Transactions" tab
//   matchToRecord()           — generic match
//   getDepositableTransactions() — for Record Deposit dialog
//   recordDeposit()           — save deposit
//   downloadBytes()           — CSV template download helper
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

// ── COA option model ──────────────────────────────────────────────────────────
class COAOption {
  final String id;
  final String accountCode;
  final String accountName;
  final String accountType;

  const COAOption({
    required this.id,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
  });

  /// Convenience getter used in dropdowns
  String get name => accountName;

  @override
  bool operator ==(Object other) => other is COAOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ── Smart match suggestion model ─────────────────────────────────────────────
class SmartMatchSuggestion {
  final String type; // 'many_to_one' | 'one_to_many'
  final List<String> bankTransactionIds;
  final double bankTotal;
  final String? systemRecordId;
  final List<String> systemRecordIds;
  final double systemAmount;
  final double difference;
  final int confidence;

  SmartMatchSuggestion({
    required this.type,
    required this.bankTransactionIds,
    required this.bankTotal,
    this.systemRecordId,
    required this.systemRecordIds,
    required this.systemAmount,
    required this.difference,
    required this.confidence,
  });
}

// ── Split line model ──────────────────────────────────────────────────────────
class SplitLine {
  final String coaAccountId;
  final double amount;
  final String? vendorName;

  const SplitLine({
    required this.coaAccountId,
    required this.amount,
    this.vendorName,
  });

  Map<String, dynamic> toJson() => {
        'coaAccountId': coaAccountId,
        'amount': amount,
        if (vendorName != null) 'vendorName': vendorName,
      };
}

// =============================================================================
//  SERVICE
// =============================================================================

class BankTransactionService {
  final ApiService _api = ApiService();

  // Convenience wrappers
  Future<Map<String, dynamic>> _get(String path,
      {Map<String, String>? params}) async {
    try {
      final headers = await _api.getHeaders();
      var uri = Uri.parse('${_api.baseUrl}$path');
      if (params != null) uri = uri.replace(queryParameters: params);
      final res = await http.get(uri, headers: headers);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    try {
      final headers = await _api.getHeaders();
      debugPrint('🔧 POST $path');
      debugPrint('  Headers: $headers');
      debugPrint('  Body: ${jsonEncode(body)}');

      final res = await http.post(
        Uri.parse('${_api.baseUrl}$path'),
        headers: headers,
        body: jsonEncode(body),
      );

      debugPrint('  Response status: ${res.statusCode}');
      debugPrint('  Response body: ${res.body}');

      if (res.statusCode >= 400) {
        final errorBody = jsonDecode(res.body) as Map<String, dynamic>;
        debugPrint('❌ Error response: $errorBody');
        return errorBody;
      }

      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e, stackTrace) {
      debugPrint('❌ POST error: $e');
      debugPrint('Stack trace: $stackTrace');
      return {'success': false, 'message': e.toString()};
    }
  }

  // ── Stats ───────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStats(String accountId) =>
      _get('/api/finance/banking/transactions/stats/$accountId');

  // ── Ledger ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getLedger({
    required String accountId,
    required String startDate,
    required String endDate,
    int page = 1,
    int limit = 50,
  }) =>
      _get('/api/finance/banking/transactions/ledger', params: {
        'accountId': accountId,
        'startDate': startDate,
        'endDate': endDate,
        'page': '$page',
        'limit': '$limit',
      });

  // ── Uncategorized ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getUncategorized({
    required String accountId,
    int page = 1,
    int limit = 50,
  }) =>
      _get('/api/finance/banking/transactions/uncategorized', params: {
        'accountId': accountId,
        'page': '$page',
        'limit': '$limit',
      });

  // ── All transactions (for All Transactions sub-tab) ─────────────────────────

  Future<Map<String, dynamic>> getAllTransactions({
    required String accountId,
    int page = 1,
    int limit = 50,
  }) =>
      _get('/api/finance/banking/transactions/all-transactions', params: {
        'accountId': accountId,
        'page': '$page',
        'limit': '$limit',
      });

  // ── COA options ──────────────────────────────────────────────────────────────

  Future<List<COAOption>> getCOAOptions(String context) async {
    final res = await _get('/api/finance/banking/transactions/coa-options',
        params: {'context': context});
    if (res['success'] != true) return [];
    return (res['data'] as List? ?? [])
        .map((a) => COAOption(
              id: a['id']?.toString() ?? '',
              accountCode: a['accountCode']?.toString() ?? '',
              accountName: a['accountName']?.toString() ?? '',
              accountType: a['accountType']?.toString() ?? '',
            ))
        .toList();
  }

  // ── Possible matches for right panel ─────────────────────────────────────────

  Future<Map<String, dynamic>> getPossibleMatches({
    required String accountId,
    required double amount,
    required String txnType,
    required String txnDate,
    double tolerance = 100,
  }) =>
      _get('/api/finance/banking/transactions/possible-matches', params: {
        'accountId': accountId,
        'amount': amount.toStringAsFixed(2),
        'txnType': txnType,
        'txnDate': txnDate,
        'tolerance': tolerance.toStringAsFixed(2),
      });

  // ── Smart match suggestions ──────────────────────────────────────────────────

  Future<List<SmartMatchSuggestion>> getSmartMatchSuggestions({
    required String accountId,
    String? startDate,
    String? endDate,
  }) async {
    final res = await _get(
        '/api/finance/banking/transactions/smart-match-suggestions',
        params: {
          'accountId': accountId,
          if (startDate != null) 'startDate': startDate,
          if (endDate != null) 'endDate': endDate,
        });
    if (res['success'] != true) return [];
    return (res['data'] as List? ?? [])
        .map((s) => SmartMatchSuggestion(
              type: s['type']?.toString() ?? 'many_to_one',
              bankTransactionIds:
                  List<String>.from(s['bankTransactions'] ?? []),
              bankTotal: (s['bankTotal'] ?? 0).toDouble(),
              systemRecordId: s['systemRecord']?.toString(),
              systemRecordIds: List<String>.from(s['systemRecords'] ?? []),
              systemAmount: (s['systemAmount'] ?? 0).toDouble(),
              difference: (s['difference'] ?? 0).toDouble(),
              confidence: (s['confidence'] ?? 0).toInt(),
            ))
        .toList();
  }

  // ── Categorize endpoints ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> categorizeAsExpense({
    required String providerTransactionId,
    required String coaAccountId,
    String? paidThroughId,
    double? amount,
    String? date,
    String? vendorName,
    String? customerId,
    String? notes,
    double? taxRate,
    double? taxAmount,
  }) =>
      _post('/api/finance/banking/transactions/categorize/expense', {
        'providerTransactionId': providerTransactionId,
        'coaAccountId': coaAccountId,
        if (paidThroughId != null) 'paidThroughId': paidThroughId,
        if (amount != null) 'amount': amount,
        if (date != null) 'date': date,
        if (vendorName != null) 'vendorName': vendorName,
        if (customerId != null) 'customerId': customerId,
        if (notes != null) 'notes': notes,
        if (taxRate != null) 'taxRate': taxRate,
        if (taxAmount != null) 'taxAmount': taxAmount,
      });

  Future<Map<String, dynamic>> categorizeAsDeposit({
    required String providerTransactionId,
    String? coaAccountId,
    String? categoryType,
    String? customerName,
    String? notes,
  }) =>
      _post('/api/finance/banking/transactions/categorize/deposit', {
        'providerTransactionId': providerTransactionId,
        if (coaAccountId != null) 'coaAccountId': coaAccountId,
        if (categoryType != null) 'categoryType': categoryType,
        if (customerName != null) 'customerName': customerName,
        if (notes != null) 'notes': notes,
      });

  /// Checks if the COA account for a simple category exists.
  /// Returns { found: true, account: {...} } or
  ///         { found: false, suggestedName, suggestedType, suggestedSubType }
  Future<Map<String, dynamic>> resolveCategoryCoa(String categoryType) =>
      _get('/api/finance/banking/transactions/resolve-category-coa',
          params: {'categoryType': categoryType});

  Future<Map<String, dynamic>> categorizeAsTransfer({
    required String providerTransactionId,
    required String toAccountId,
    String? notes,
  }) =>
      _post('/api/finance/banking/transactions/categorize/transfer', {
        'providerTransactionId': providerTransactionId,
        'toAccountId': toAccountId,
        if (notes != null) 'notes': notes,
      });

  Future<Map<String, dynamic>> categorizeAsSplit({
    required String providerTransactionId,
    required List<SplitLine> splits,
    String? date,
  }) =>
      _post('/api/finance/banking/transactions/categorize/split', {
        'providerTransactionId': providerTransactionId,
        'splits': splits.map((s) => s.toJson()).toList(),
        if (date != null) 'date': date,
      });

  Future<Map<String, dynamic>> excludeTransaction({
    required String providerTransactionId,
    String? reason,
  }) =>
      _post('/api/finance/banking/transactions/categorize/exclude', {
        'providerTransactionId': providerTransactionId,
        if (reason != null) 'reason': reason,
      });

  // ── Match endpoints ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> matchToInvoice({
    required String providerTransactionId,
    required String invoiceId,
    double? amount,
  }) =>
      _post('/api/finance/banking/transactions/categorize/match-invoice', {
        'providerTransactionId': providerTransactionId,
        'invoiceId': invoiceId,
        if (amount != null) 'amount': amount,
      });

  Future<Map<String, dynamic>> matchToBill({
    required String providerTransactionId,
    required String billId,
    double? amount,
  }) =>
      _post('/api/finance/banking/transactions/categorize/match-bill', {
        'providerTransactionId': providerTransactionId,
        'billId': billId,
        if (amount != null) 'amount': amount,
      });

  Future<Map<String, dynamic>> matchToRecord({
    required String providerTransactionId,
    required String recordId,
    required String recordType,
  }) =>
      _post('/api/finance/banking/transactions/match-record', {
        'providerTransactionId': providerTransactionId,
        'recordId': recordId,
        'recordType': recordType,
      });

  // ── Multi-match ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> multiMatchManyToOne({
    required List<String> providerTransactionIds,
    required String expenseId,
  }) =>
      _post(
          '/api/finance/banking/transactions/categorize/multi-match-many-to-one',
          {
            'providerTransactionIds': providerTransactionIds,
            'expenseId': expenseId,
          });

  Future<Map<String, dynamic>> multiMatchOneToMany({
    required String providerTransactionId,
    required List<String> expenseIds,
  }) =>
      _post(
          '/api/finance/banking/transactions/categorize/multi-match-one-to-many',
          {
            'providerTransactionId': providerTransactionId,
            'expenseIds': expenseIds,
          });

  // ── Manual entry ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> addManualEntry({
    required String accountId,
    required String type,
    required String date,
    required double amount,
    String? coaAccountId,
    String? toAccountId,
    String? vendorName,
    String? customerName,
    String? notes,
    double? taxRate,
    double? taxAmount,
  }) =>
      _post('/api/finance/banking/transactions/manual-entry', {
        'accountId': accountId,
        'type': type,
        'date': date,
        'amount': amount,
        if (coaAccountId != null) 'coaAccountId': coaAccountId,
        if (toAccountId != null) 'toAccountId': toAccountId,
        if (vendorName != null) 'vendorName': vendorName,
        if (customerName != null) 'customerName': customerName,
        if (notes != null) 'notes': notes,
        if (taxRate != null) 'taxRate': taxRate,
        if (taxAmount != null) 'taxAmount': taxAmount,
      });

  // ── Open invoices / bills (for match dialog) ─────────────────────────────────

  Future<List<Map<String, dynamic>>> getOpenInvoices({double? amount}) async {
    final res = await _get('/api/finance/banking/transactions/open-invoices',
        params: amount != null ? {'amount': amount.toStringAsFixed(2)} : {});
    return List<Map<String, dynamic>>.from(res['data'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getOpenBills({double? amount}) async {
    final res = await _get('/api/finance/banking/transactions/open-bills',
        params: amount != null ? {'amount': amount.toStringAsFixed(2)} : {});
    return List<Map<String, dynamic>>.from(res['data'] ?? []);
  }

  // ── Record Deposit ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDepositableTransactions({
    required String accountId,
    String? date,
    String? receivedFrom,
    String? entityType,
  }) =>
      _get('/api/finance/banking/transactions/depositable-transactions',
          params: {
            'accountId': accountId,
            if (date != null) 'date': date,
            if (receivedFrom != null) 'receivedFrom': receivedFrom,
            if (entityType != null) 'entityType': entityType,
          });

  Future<Map<String, dynamic>> recordDeposit({
    required String accountId,
    required String depositDate,
    String? paidVia,
    String? reference,
    String? description,
    required List<String> transactionIds,
    required List<Map<String, dynamic>> otherDeposits,
  }) =>
      _post('/api/finance/banking/transactions/record-deposit', {
        'accountId': accountId,
        'depositDate': depositDate,
        'transactionIds': transactionIds,
        'otherDeposits': otherDeposits,
        if (paidVia != null) 'paidVia': paidVia,
        if (reference != null) 'reference': reference,
        if (description != null) 'description': description,
      });

  // ── Undo categorization ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> undoCategorization({
    required String providerTransactionId,
  }) =>
      _post('/api/finance/banking/transactions/categorize/undo', {
        'providerTransactionId': providerTransactionId,
      });

  // ── Vendors & Customers ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> markAsCategorized({
    required String providerTransactionId,
    String? categoryLabel,
    String? linkedRecordId,
    String? linkedRecordType,
    String? journalRef,
  }) =>
      _post('/api/finance/banking/transactions/mark-categorized', {
        'providerTransactionId': providerTransactionId,
        if (categoryLabel != null) 'categoryLabel': categoryLabel,
        if (linkedRecordId != null) 'linkedRecordId': linkedRecordId,
        if (linkedRecordType != null) 'linkedRecordType': linkedRecordType,
        if (journalRef != null) 'journalRef': journalRef,
      });

  Future<Map<String, dynamic>> deleteTransaction(String txnId) async {
    try {
      final headers = await _api.getHeaders();
      final res = await http.delete(
        Uri.parse(
            '${_api.baseUrl}/api/finance/banking/transactions/delete-transaction/$txnId'),
        headers: headers,
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> editTransaction(
    String txnId, {
    String? date,
    String? description,
    double? amount,
    String? referenceNumber,
  }) =>
      publicPut(
        '/api/finance/banking/transactions/edit-transaction/$txnId',
        {
          if (date != null) 'date': date,
          if (description != null) 'description': description,
          if (amount != null) 'amount': amount,
          if (referenceNumber != null) 'referenceNumber': referenceNumber,
        },
      );

  Future<Map<String, dynamic>> uncategorizeTransaction(String txnId) =>
      _post('/api/finance/banking/transactions/uncategorize/$txnId', {});

  Future<Map<String, dynamic>> getVendors() => _get('/api/finance/vendors',
      params: {'limit': '500', 'status': 'Active'});

  Future<Map<String, dynamic>> getCustomers() =>
      _get('/api/finance/customers', params: {'limit': '500'});

  // ── Vendor / Customer payment categorization ──────────────────────────────

  Future<Map<String, dynamic>> categorizeAsVendorPayment({
    required String providerTransactionId,
    String? vendorId,
    required double amount,
    required String date,
    String? reference,
    required String paidThroughId,
    String? notes,
  }) =>
      _post('/api/finance/banking/transactions/categorize/vendor-payment', {
        'providerTransactionId': providerTransactionId,
        'paidThroughId': paidThroughId,
        'amount': amount,
        'date': date,
        if (vendorId != null) 'vendorId': vendorId,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
      });

  Future<Map<String, dynamic>> categorizeAsCustomerPayment({
    required String providerTransactionId,
    String? customerId,
    required double amount,
    required String date,
    String? reference,
    required String depositToId,
    String? notes,
  }) =>
      _post('/api/finance/banking/transactions/categorize/customer-payment', {
        'providerTransactionId': providerTransactionId,
        'depositToId': depositToId,
        'amount': amount,
        'date': date,
        if (customerId != null) 'customerId': customerId,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
      });

  // ── Transaction rules ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getTransactionRules(
          {required String accountId}) =>
      _get('/api/finance/banking/transactions/rules',
          params: {'accountId': accountId});

  Future<Map<String, dynamic>> createTransactionRule(
          Map<String, dynamic> rule) =>
      _post('/api/finance/banking/transactions/rules', rule);

  Future<Map<String, dynamic>> updateTransactionRule(
      String ruleId, Map<String, dynamic> rule) async {
    try {
      final headers = await _api.getHeaders();
      final res = await http.put(
        Uri.parse(
            '${_api.baseUrl}/api/finance/banking/transactions/rules/$ruleId'),
        headers: headers,
        body: jsonEncode(rule),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> deleteTransactionRule(String ruleId) async {
    try {
      final headers = await _api.getHeaders();
      final res = await http.delete(
        Uri.parse(
            '${_api.baseUrl}/api/finance/banking/transactions/rules/$ruleId'),
        headers: headers,
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ── Public HTTP wrappers (used by reconciliation and other modules) ──────────

  Future<Map<String, dynamic>> publicGet(String path,
          {Map<String, String>? params}) =>
      _get(path, params: params);

  Future<Map<String, dynamic>> publicPost(
          String path, Map<String, dynamic> body) =>
      _post(path, body);

  Future<Map<String, dynamic>> publicPut(
      String path, Map<String, dynamic> body) async {
    try {
      final headers = await _api.getHeaders();
      final res = await http.put(
        Uri.parse('${_api.baseUrl}$path'),
        headers: headers,
        body: jsonEncode(body),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> publicDelete(String path) async {
    try {
      final headers = await _api.getHeaders();
      final res = await http.delete(
        Uri.parse('${_api.baseUrl}$path'),
        headers: headers,
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ── Download PDF URL for a linked record ─────────────────────────────────────

  Future<String> getPdfUrl({
    required String linkedRecordId,
    required String linkedRecordType,
  }) async {
    final headers = await _api.getHeaders();
    final token = headers['Authorization']?.replaceFirst('Bearer ', '') ?? '';
    String path;
    switch (linkedRecordType) {
      case 'Expense':
        path = '/api/finance/expenses/$linkedRecordId/pdf';
        break;
      case 'PaymentReceived':
        path = '/api/finance/payments-received/$linkedRecordId/pdf';
        break;
      case 'PaymentMade':
        path = '/api/finance/payments-made/$linkedRecordId/pdf';
        break;
      default:
        path = '/api/finance/expenses/$linkedRecordId/pdf';
    }
    return '${_api.baseUrl}$path?token=$token';
  }

  // ── Fetch linked record details for categorized panel ────────────────────────

  Future<Map<String, dynamic>> getLinkedRecord({
    required String linkedRecordId,
    required String linkedRecordType,
  }) async {
    try {
      String path;
      switch (linkedRecordType) {
        case 'Expense':
          path = '/api/finance/expenses/$linkedRecordId';
          break;
        case 'PaymentReceived':
          path = '/api/finance/payments-received/$linkedRecordId';
          break;
        case 'PaymentMade':
          path = '/api/finance/payments-made/$linkedRecordId';
          break;
        default:
          path = '/api/finance/expenses/$linkedRecordId';
      }
      return await _get(path);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
