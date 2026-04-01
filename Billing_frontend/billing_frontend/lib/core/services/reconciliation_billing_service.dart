// ============================================================================
// RECONCILIATION BILLING SERVICE - Flutter API Client
// ============================================================================
// File: lib/core/services/reconciliation_billing_service.dart
// Purpose: Handle all API calls for reconciliation functionality
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class ReconciliationBillingService {
  final ApiService _apiService = ApiService();

  // ============================================================================
  // IMPORT & COLUMN MAPPING
  // ============================================================================

  /// Upload and import provider statement (Excel/CSV)
  Future<Map<String, dynamic>> importProviderStatement({
    required String accountId,
    required File file,
    String? mappingId,
    Map<String, String>? columnMappings,
    String? dateFormat,
  }) async {
    try {
      print('📤 Uploading statement file...');

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/import');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      final headers = await _apiService.getHeaders();
      headers.forEach((key, value) {
        if (key.toLowerCase() != 'content-type') {
          request.headers[key] = value;
        }
      });

      // Add file
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      // Add form fields
      request.fields['accountId'] = accountId;
      if (mappingId != null) {
        request.fields['mappingId'] = mappingId;
      }
      if (columnMappings != null) {
        request.fields['columnMappings'] = jsonEncode(columnMappings);
      }
      if (dateFormat != null) {
        request.fields['dateFormat'] = dateFormat;
      }

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['message'] ?? 'Import failed');
      }
    } catch (e) {
      print('❌ Import error: $e');
      throw Exception('Failed to import statement: $e');
    }
  }

  /// Upload and import provider statement using bytes (for web)
  Future<Map<String, dynamic>> importProviderStatementBytes({
    required String accountId,
    required List<int> fileBytes,
    required String fileName,
    String? mappingId,
    Map<String, String>? columnMappings,
    String? dateFormat,
  }) async {
    try {
      print('📤 Uploading statement file (bytes)...');

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/import');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      final headers = await _apiService.getHeaders();
      headers.forEach((key, value) {
        if (key.toLowerCase() != 'content-type') {
          request.headers[key] = value;
        }
      });

      // Add file from bytes
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ));

      // Add form fields
      request.fields['accountId'] = accountId;
      if (mappingId != null) {
        request.fields['mappingId'] = mappingId;
      }
      if (columnMappings != null) {
        request.fields['columnMappings'] = jsonEncode(columnMappings);
      }
      if (dateFormat != null) {
        request.fields['dateFormat'] = dateFormat;
      }

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final errorBody = jsonDecode(response.body);
        throw Exception(errorBody['message'] ?? 'Import failed');
      }
    } catch (e) {
      print('❌ Import error: $e');
      throw Exception('Failed to import statement: $e');
    }
  }

  /// Save column mapping for future use
  Future<Map<String, dynamic>> saveColumnMapping({
    required String accountId,
    required String mappingName,
    required String fileFormat,
    required Map<String, String> columnMappings,
    String? dateFormat,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/save-mapping',
        body: {
          'accountId': accountId,
          'mappingName': mappingName,
          'fileFormat': fileFormat,
          'columnMappings': columnMappings,
          'dateFormat': dateFormat ?? 'DD/MM/YYYY',
        },
      );

      return response;
    } catch (e) {
      print('❌ Error saving mapping: $e');
      throw Exception('Failed to save column mapping: $e');
    }
  }

  /// Get saved column mappings for an account
  Future<List<ColumnMappingModel>> getColumnMappings(String accountId) async {
    try {
      final response = await _apiService.get(
        '/api/finance/reconciliation/mappings/$accountId',
      );

      if (response['success']) {
        final List<dynamic> data = response['data'];
        return data.map((json) => ColumnMappingModel.fromJson(json)).toList();
      }

      return [];
    } catch (e) {
      print('❌ Error fetching mappings: $e');
      return [];
    }
  }

  // ============================================================================
  // PROVIDER TRANSACTIONS
  // ============================================================================

  /// Get provider transactions
  Future<List<ProviderTransactionModel>> getProviderTransactions({
    String? accountId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (accountId != null) queryParams['accountId'] = accountId;
      if (status != null) queryParams['status'] = status;
      if (startDate != null) {
        queryParams['startDate'] = startDate.toIso8601String().split('T')[0];
      }
      if (endDate != null) {
        queryParams['endDate'] = endDate.toIso8601String().split('T')[0];
      }

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/provider-transactions')
          .replace(queryParameters: queryParams);

      final response = await _apiService.get(
        '/api/finance/reconciliation/provider-transactions',
        queryParams: queryParams,
      );

      if (response['success']) {
        final List<dynamic> data = response['data'];
        return data.map((json) => ProviderTransactionModel.fromJson(json)).toList();
      }

      return [];
    } catch (e) {
      print('❌ Error fetching provider transactions: $e');
      return [];
    }
  }

  /// Get system expenses for reconciliation
  Future<List<Map<String, dynamic>>> getSystemExpenses({
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    bool? matched,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (accountId != null) queryParams['accountId'] = accountId;
      if (startDate != null) {
        queryParams['startDate'] = startDate.toIso8601String().split('T')[0];
      }
      if (endDate != null) {
        queryParams['endDate'] = endDate.toIso8601String().split('T')[0];
      }
      if (matched != null) queryParams['matched'] = matched.toString();

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/system-expenses')
          .replace(queryParameters: queryParams);

      final response = await _apiService.get(
        '/api/finance/reconciliation/system-expenses',
        queryParams: queryParams,
      );

      if (response['success']) {
        return List<Map<String, dynamic>>.from(response['data']);
      }

      return [];
    } catch (e) {
      print('❌ Error fetching system expenses: $e');
      return [];
    }
  }

  /// Delete provider transaction
  Future<bool> deleteProviderTransaction(String transactionId) async {
    try {
      final response = await _apiService.delete(
        '/api/finance/reconciliation/provider-transactions/$transactionId',
      );

      return response['success'] == true;
    } catch (e) {
      print('❌ Error deleting provider transaction: $e');
      return false;
    }
  }

  // ============================================================================
  // MATCHING
  // ============================================================================

  /// Run auto-match algorithm
  Future<Map<String, dynamic>> runAutoMatch({
    required String accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/auto-match',
        body: {
          'accountId': accountId,
          'startDate': startDate.toIso8601String().split('T')[0],
          'endDate': endDate.toIso8601String().split('T')[0],
        },
      );

      return response;
    } catch (e) {
      print('❌ Error running auto-match: $e');
      throw Exception('Failed to run auto-match: $e');
    }
  }

  /// Manual match (user selects both)
Future<Map<String, dynamic>> manualMatch({
  required String providerTxnId,
  required String expenseId,
  bool forceMatch = false, // ← ADD THIS PARAMETER
}) async {
  try {
    final response = await _apiService.post(
      '/api/finance/reconciliation/manual-match',
      body: {
        'providerTxnId': providerTxnId,
        'expenseId': expenseId,
        'forceMatch': forceMatch, // ← SEND TO BACKEND
      },
    );

    // ✅ RETURN THE FULL RESPONSE (not just success boolean)
    return response;
  } catch (e) {
    print('❌ Error manual matching: $e');
    rethrow; // ← CHANGE: Rethrow instead of wrapping in Exception
  }
}


/// Verify opening balance against statement
Future<Map<String, dynamic>> verifyOpeningBalance({
  required String accountId,
  required double statementOpeningBalance,
}) async {
  try {
    final response = await _apiService.post(
      '/api/finance/reconciliation/sessions/verify-opening-balance',
      body: {
        'accountId': accountId,
        'statementOpeningBalance': statementOpeningBalance,
      },
    );
    return response;
  } catch (e) {
    print('❌ Error verifying opening balance: $e');
    throw Exception('Failed to verify opening balance: $e');
  }
}

  /// Accept pending match
  Future<bool> acceptMatch(String providerTxnId) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/accept-match/$providerTxnId',
        body: {},
      );

      return response['success'] == true;
    } catch (e) {
      print('❌ Error accepting match: $e');
      throw Exception('Failed to accept match: $e');
    }
  }

  /// Reject pending match
  Future<bool> rejectMatch(String providerTxnId) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/reject-match/$providerTxnId',
        body: {},
      );

      return response['success'] == true;
    } catch (e) {
      print('❌ Error rejecting match: $e');
      throw Exception('Failed to reject match: $e');
    }
  }

  /// Unmatch already matched transaction
  Future<bool> unmatchTransaction(String providerTxnId) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/unmatch/$providerTxnId',
        body: {},
      );

      return response['success'] == true;
    } catch (e) {
      print('❌ Error unmatching: $e');
      throw Exception('Failed to unmatch transaction: $e');
    }
  }

  // ============================================================================
  // RECONCILIATION SESSIONS
  // ============================================================================

  /// Start new reconciliation session
  Future<ReconciliationSessionModel> startReconciliationSession({
    required String accountId,
    required String accountName,
    required String accountType,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/sessions/start',
        body: {
          'accountId': accountId,
          'accountName': accountName,
          'accountType': accountType,
          'periodStart': periodStart.toIso8601String().split('T')[0],
          'periodEnd': periodEnd.toIso8601String().split('T')[0],
        },
      );

      if (response['success']) {
        return ReconciliationSessionModel.fromJson(response['data']);
      }

      throw Exception(response['message'] ?? 'Failed to start session');
    } catch (e) {
      print('❌ Error starting session: $e');
      throw Exception('Failed to start reconciliation session: $e');
    }
  }

  /// Get all reconciliation sessions
  Future<List<ReconciliationSessionModel>> getAllSessions({
    String? accountId,
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (accountId != null) queryParams['accountId'] = accountId;
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/sessions')
          .replace(queryParameters: queryParams);

      final response = await _apiService.get(
        '/api/finance/reconciliation/sessions',
        queryParams: queryParams,
      );

      if (response['success']) {
        final List<dynamic> data = response['data'];
        return data.map((json) => ReconciliationSessionModel.fromJson(json)).toList();
      }

      return [];
    } catch (e) {
      print('❌ Error fetching sessions: $e');
      return [];
    }
  }

  /// Get session details
  Future<ReconciliationSessionModel?> getSessionDetails(String sessionId) async {
    try {
      final response = await _apiService.get(
        '/api/finance/reconciliation/sessions/$sessionId',
      );

      if (response['success']) {
        return ReconciliationSessionModel.fromJson(response['data']);
      }

      return null;
    } catch (e) {
      print('❌ Error fetching session details: $e');
      return null;
    }
  }

  /// Finalize and lock session
/// Finalize and lock session with closing balance verification
  Future<Map<String, dynamic>> finalizeSession(
    String sessionId, {
    required double statementClosingBalance,
    String? notes,
    bool forceFinalize = false,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/sessions/$sessionId/finalize',
        body: {
          'statementClosingBalance': statementClosingBalance,
          'notes': notes,
          'forceFinalize': forceFinalize,
        },
      );

      return response;
    } catch (e) {
      print('❌ Error finalizing session: $e');
      throw Exception('Failed to finalize session: $e');
    }
  }


  /// Carry forward an unmatched transaction to next period
  Future<Map<String, dynamic>> carryForwardTransaction(
    String providerTxnId, {
    String? notes,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/carry-forward/$providerTxnId',
        body: {
          'notes': notes ?? 'Carried forward to next reconciliation period',
        },
      );
      return response;
    } catch (e) {
      print('❌ Error carrying forward transaction: $e');
      throw Exception('Failed to carry forward transaction: $e');
    }
  }

  /// Mark unmatched transaction as adjustment and create expense entry
  Future<Map<String, dynamic>> createAdjustment(
    String providerTxnId, {
    required String reason,
    String? notes,
    String adjustmentType = 'WRITE_OFF',
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/adjustment/$providerTxnId',
        body: {
          'reason': reason,
          'notes': notes,
          'adjustmentType': adjustmentType,
        },
      );
      return response;
    } catch (e) {
      print('❌ Error creating adjustment: $e');
      throw Exception('Failed to create adjustment: $e');
    }
  }

  /// Bulk resolve multiple unmatched transactions
  Future<Map<String, dynamic>> bulkResolve({
    required List<String> transactionIds,
    required String action,
    String? reason,
    String? notes,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/bulk-resolve',
        body: {
          'transactionIds': transactionIds,
          'action': action,
          'reason': reason,
          'notes': notes,
        },
      );
      return response;
    } catch (e) {
      print('❌ Error bulk resolving: $e');
      throw Exception('Failed to bulk resolve transactions: $e');
    }
  }

  /// Get reconciliation report data for PDF generation
  Future<Map<String, dynamic>> getReconciliationReport(String sessionId) async {
    try {
      final response = await _apiService.get(
        '/api/finance/reconciliation/sessions/$sessionId/report',
      );
      return response;
    } catch (e) {
      print('❌ Error fetching report: $e');
      throw Exception('Failed to fetch reconciliation report: $e');
    }
  }

  /// Submit reconciliation for approval (maker step)
  Future<Map<String, dynamic>> submitForApproval(
    String sessionId, {
    String? submittedBy,
    String? notes,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/sessions/$sessionId/submit-for-approval',
        body: {
          'submittedBy': submittedBy ?? 'system',
          'notes': notes,
        },
      );
      return response;
    } catch (e) {
      print('❌ Error submitting for approval: $e');
      throw Exception('Failed to submit for approval: $e');
    }
  }

  /// Approve or reject a submitted reconciliation (checker step)
  Future<Map<String, dynamic>> processApproval(
    String sessionId, {
    required String action,
    String? approvedBy,
    String? approvalNotes,
    String? rejectionReason,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/sessions/$sessionId/approve',
        body: {
          'action': action,
          'approvedBy': approvedBy ?? 'system',
          'approvalNotes': approvalNotes,
          'rejectionReason': rejectionReason,
        },
      );
      return response;
    } catch (e) {
      print('❌ Error processing approval: $e');
      throw Exception('Failed to process approval: $e');
    }
  }

/// Get alerts for an account
  Future<List<Map<String, dynamic>>> getAlerts(String accountId) async {
    try {
      final response = await _apiService.get('/api/finance/reconciliation/alerts/$accountId');
      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
      return [];
    } catch (e) {
      print('❌ Error fetching alerts: $e');
      return [];
    }
  }

  /// Get audit log for a session or account
  Future<List<Map<String, dynamic>>> getAuditLog({
    String? sessionId,
    String? accountId,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{'limit': limit.toString()};
      if (sessionId != null) queryParams['sessionId'] = sessionId;
      if (accountId != null) queryParams['accountId'] = accountId;

      final response = await _apiService.get(
        '/api/finance/reconciliation/audit-log',
        queryParams: queryParams,
      );
      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
      return [];
    } catch (e) {
      print('❌ Error fetching audit log: $e');
      return [];
    }
  }

  /// Get reconciliation history for an account
  Future<Map<String, dynamic>> getReconciliationHistory(
    String accountId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final response = await _apiService.get(
        '/api/finance/reconciliation/history/$accountId',
        queryParams: {'page': page.toString(), 'limit': limit.toString()},
      );
      return response;
    } catch (e) {
      print('❌ Error fetching history: $e');
      throw Exception('Failed to fetch reconciliation history: $e');
    }
  }

  /// Reopen locked session
  Future<bool> reopenSession(String sessionId) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/sessions/$sessionId/reopen',
        body: {},
      );

      return response['success'] == true;
    } catch (e) {
      print('❌ Error reopening session: $e');
      throw Exception('Failed to reopen session: $e');
    }
  }

  // ============================================================================
  // PETTY CASH
  // ============================================================================

  /// Submit petty cash physical count
  Future<ReconciliationSessionModel> submitPettyCashCount({
    required String accountId,
    required String accountName,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double physicalCashCount,
    List<CashDenomination>? denominations,
    String? countedBy,
    String? notes,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/finance/reconciliation/petty-cash/count',
        body: {
          'accountId': accountId,
          'accountName': accountName,
          'periodStart': periodStart.toIso8601String().split('T')[0],
          'periodEnd': periodEnd.toIso8601String().split('T')[0],
          'physicalCashCount': physicalCashCount,
          'denominations': denominations?.map((d) => d.toJson()).toList() ?? [],
          'countedBy': countedBy ?? 'system',
          'notes': notes,
        },
      );

      if (response['success']) {
        return ReconciliationSessionModel.fromJson(response['data']);
      }

      throw Exception(response['message'] ?? 'Failed to submit count');
    } catch (e) {
      print('❌ Error submitting petty cash count: $e');
      throw Exception('Failed to submit petty cash count: $e');
    }
  }

  /// Get petty cash summary
  Future<Map<String, dynamic>> getPettyCashSummary({
    required String accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final queryParams = {
        'accountId': accountId,
        'startDate': startDate.toIso8601String().split('T')[0],
        'endDate': endDate.toIso8601String().split('T')[0],
      };

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/petty-cash/summary')
          .replace(queryParameters: queryParams);

      final response = await _apiService.get(
        '/api/finance/reconciliation/petty-cash/summary',
        queryParams: queryParams,
      );

      return response;
    } catch (e) {
      print('❌ Error fetching petty cash summary: $e');
      throw Exception('Failed to fetch petty cash summary: $e');
    }
  }

  // ============================================================================
  // STATISTICS
  // ============================================================================

  /// Get reconciliation statistics
  Future<Map<String, dynamic>> getReconciliationStats({
    required String accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final queryParams = {
        'startDate': startDate.toIso8601String().split('T')[0],
        'endDate': endDate.toIso8601String().split('T')[0],
      };

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/stats/$accountId')
          .replace(queryParameters: queryParams);

      final response = await _apiService.get(
        '/api/finance/reconciliation/stats/$accountId',
        queryParams: queryParams,
      );

      return response;
    } catch (e) {
      print('❌ Error fetching stats: $e');
      throw Exception('Failed to fetch statistics: $e');
    }
  }

  /// Get import history
  Future<List<Map<String, dynamic>>> getImportHistory({String? accountId}) async {
    try {
      final queryParams = <String, String>{};
      if (accountId != null) queryParams['accountId'] = accountId;

      final uri = Uri.parse('${_apiService.baseUrl}/api/finance/reconciliation/import-history')
          .replace(queryParameters: queryParams);

      final response = await _apiService.get(
        '/api/finance/reconciliation/import-history',
        queryParams: queryParams,
      );

      if (response['success']) {
        return List<Map<String, dynamic>>.from(response['data']);
      }

      return [];
    } catch (e) {
      print('❌ Error fetching import history: $e');
      return [];
    }
  }
}

// ============================================================================
// MODELS
// ============================================================================

class ProviderTransactionModel {
  final String id;
  final String accountId;
  final DateTime transactionDate;
  final double amount;
  final String? description;
  final String? location;
  final String? merchantName;
  final String? cardNumber;
  final String? vehicleNumber;
  final String? referenceNumber;
  final String transactionType;
  final String reconciliationStatus;
  final String? matchedExpenseId;
  final int? matchConfidence;
  final String? matchedBy;
  final DateTime? matchedAt;
  final double variance;
  final String? varianceReason;
  final String importBatchId;
  final DateTime importedAt;
  final Map<String, dynamic>? rawData;
  // Phase 5 fields
  final bool? isCarriedForward;
  final String? carriedForwardNotes;
  final bool? isAdjustment;
  final String? adjustmentReason;

  ProviderTransactionModel({
    required this.id,
    required this.accountId,
    required this.transactionDate,
    required this.amount,
    this.description,
    this.location,
    this.merchantName,
    this.cardNumber,
    this.vehicleNumber,
    this.referenceNumber,
    required this.transactionType,
    required this.reconciliationStatus,
    this.matchedExpenseId,
    this.matchConfidence,
    this.matchedBy,
    this.matchedAt,
    required this.variance,
    this.varianceReason,
    required this.importBatchId,
    required this.importedAt,
    this.rawData,
    this.isCarriedForward,
    this.carriedForwardNotes,
    this.isAdjustment,
    this.adjustmentReason,
  });

  factory ProviderTransactionModel.fromJson(Map<String, dynamic> json) {
    return ProviderTransactionModel(
      id: json['_id'] ?? json['id'] ?? '',
      accountId: json['accountId'] ?? '',
      transactionDate: DateTime.parse(json['transactionDate']),
      amount: (json['amount'] ?? 0).toDouble(),
      description: json['description'],
      location: json['location'],
      merchantName: json['merchantName'],
      cardNumber: json['cardNumber'],
      vehicleNumber: json['vehicleNumber'],
      referenceNumber: json['referenceNumber'],
      transactionType: json['transactionType'] ?? 'DEBIT',
      reconciliationStatus: json['reconciliationStatus'] ?? 'UNMATCHED',
      matchedExpenseId: json['matchedExpenseId'],
      matchConfidence: json['matchConfidence'],
      matchedBy: json['matchedBy'],
      matchedAt: json['matchedAt'] != null ? DateTime.parse(json['matchedAt']) : null,
      variance: (json['variance'] ?? 0).toDouble(),
      varianceReason: json['varianceReason'],
      importBatchId: json['importBatchId'] ?? '',
      importedAt: DateTime.parse(json['importedAt']),
      rawData: json['rawData'],
      isCarriedForward: json['isCarriedForward'],
      carriedForwardNotes: json['carriedForwardNotes'],
      isAdjustment: json['isAdjustment'],
      adjustmentReason: json['adjustmentReason'],
    );
  }
}

class ReconciliationSessionModel {
  final String id;
  final String accountId;
  final String accountName;
  final String accountType;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String status;
  final int totalProviderTransactions;
  final int totalSystemExpenses;
  final int totalMatched;
  final int totalUnmatched;
  final int totalPending;
  final double providerBalance;
  final double systemBalance;
  final double balanceDifference;
  final double totalVariance;
  final double? physicalCashCount;
  final List<CashDenomination> denominations;
  final String startedBy;
  final DateTime startedAt;
  final String? completedBy;
  final DateTime? completedAt;
  final bool isLocked;
  final DateTime? lockedAt;
  final String? lockedBy;
  final String? reconciliationNotes;
  // Phase 7: Maker-Checker
  final bool requiresApproval;
  final bool submittedForApproval;
  final String? submittedBy;
  final DateTime? submittedAt;
  final String approvalStatus;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? approvalNotes;
  final String? rejectedBy;
  final DateTime? rejectedAt;
  final String? rejectionReason;

  ReconciliationSessionModel({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.accountType,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.totalProviderTransactions,
    required this.totalSystemExpenses,
    required this.totalMatched,
    required this.totalUnmatched,
    required this.totalPending,
    required this.providerBalance,
    required this.systemBalance,
    required this.balanceDifference,
    required this.totalVariance,
    this.physicalCashCount,
    required this.denominations,
    required this.startedBy,
    required this.startedAt,
    this.completedBy,
    this.completedAt,
    required this.isLocked,
    this.lockedAt,
    this.lockedBy,
    this.reconciliationNotes,
    this.requiresApproval = false,
    this.submittedForApproval = false,
    this.submittedBy,
    this.submittedAt,
    this.approvalStatus = 'NOT_REQUIRED',
    this.approvedBy,
    this.approvedAt,
    this.approvalNotes,
    this.rejectedBy,
    this.rejectedAt,
    this.rejectionReason,
  });

  factory ReconciliationSessionModel.fromJson(Map<String, dynamic> json) {
    return ReconciliationSessionModel(
      id: json['_id'] ?? json['id'] ?? '',
      accountId: json['accountId'] ?? '',
      accountName: json['accountName'] ?? '',
      accountType: json['accountType'] ?? '',
      periodStart: DateTime.parse(json['periodStart']),
      periodEnd: DateTime.parse(json['periodEnd']),
      status: json['status'] ?? 'IN_PROGRESS',
      totalProviderTransactions: json['totalProviderTransactions'] ?? 0,
      totalSystemExpenses: json['totalSystemExpenses'] ?? 0,
      totalMatched: json['totalMatched'] ?? 0,
      totalUnmatched: json['totalUnmatched'] ?? 0,
      totalPending: json['totalPending'] ?? 0,
      providerBalance: (json['providerBalance'] ?? 0).toDouble(),
      systemBalance: (json['systemBalance'] ?? 0).toDouble(),
      balanceDifference: (json['balanceDifference'] ?? 0).toDouble(),
      totalVariance: (json['totalVariance'] ?? 0).toDouble(),
      physicalCashCount: json['physicalCashCount'] != null
          ? (json['physicalCashCount']).toDouble()
          : null,
      denominations: json['denominations'] != null
          ? (json['denominations'] as List)
              .map((d) => CashDenomination.fromJson(d))
              .toList()
          : [],
      startedBy: json['startedBy'] ?? 'system',
      startedAt: DateTime.parse(json['startedAt']),
      completedBy: json['completedBy'],
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
      isLocked: json['isLocked'] ?? false,
      lockedAt: json['lockedAt'] != null ? DateTime.parse(json['lockedAt']) : null,
      lockedBy: json['lockedBy'],
      reconciliationNotes: json['reconciliationNotes'],
      requiresApproval: json['requiresApproval'] ?? false,
      submittedForApproval: json['submittedForApproval'] ?? false,
      submittedBy: json['submittedBy'],
      submittedAt: json['submittedAt'] != null ? DateTime.parse(json['submittedAt']) : null,
      approvalStatus: json['approvalStatus'] ?? 'NOT_REQUIRED',
      approvedBy: json['approvedBy'],
      approvedAt: json['approvedAt'] != null ? DateTime.parse(json['approvedAt']) : null,
      approvalNotes: json['approvalNotes'],
      rejectedBy: json['rejectedBy'],
      rejectedAt: json['rejectedAt'] != null ? DateTime.parse(json['rejectedAt']) : null,
      rejectionReason: json['rejectionReason'],
    );
  }
}

class ColumnMappingModel {
  final String id;
  final String accountId;
  final String mappingName;
  final String fileFormat;
  final Map<String, String> columnMappings;
  final String dateFormat;
  final int usageCount;
  final DateTime? lastUsedAt;

  ColumnMappingModel({
    required this.id,
    required this.accountId,
    required this.mappingName,
    required this.fileFormat,
    required this.columnMappings,
    required this.dateFormat,
    required this.usageCount,
    this.lastUsedAt,
  });

  factory ColumnMappingModel.fromJson(Map<String, dynamic> json) {
    return ColumnMappingModel(
      id: json['_id'] ?? json['id'] ?? '',
      accountId: json['accountId'] ?? '',
      mappingName: json['mappingName'] ?? '',
      fileFormat: json['fileFormat'] ?? 'EXCEL',
      columnMappings: Map<String, String>.from(json['columnMappings'] ?? {}),
      dateFormat: json['dateFormat'] ?? 'DD/MM/YYYY',
      usageCount: json['usageCount'] ?? 0,
      lastUsedAt: json['lastUsedAt'] != null ? DateTime.parse(json['lastUsedAt']) : null,
    );
  }
}

class CashDenomination {
  final int denomination;
  final int count;
  final double total;

  CashDenomination({
    required this.denomination,
    required this.count,
    required this.total,
  });

  factory CashDenomination.fromJson(Map<String, dynamic> json) {
    return CashDenomination(
      denomination: json['denomination'] ?? 0,
      count: json['count'] ?? 0,
      total: (json['total'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'denomination': denomination,
      'count': count,
      'total': total,
    };
  }
}
