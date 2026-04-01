// ============================================================================
// RECURRING EXPENSE SERVICE - FLUTTER (UPDATED WITH TAX SUPPORT)
// ============================================================================
// File: lib/core/services/recurring_expense_service.dart
// Features:
// - Complete CRUD operations for recurring expenses
// - Tax support: General Tax + GST with rates
// - Proper error handling
// - JWT authentication
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

// ============================================================================
// RECURRING EXPENSE MODEL (UPDATED WITH TAX)
// ============================================================================

class RecurringExpense {
  final String id;
  final String profileName;
  final String vendorId;
  final String vendorName;
  final String? vendorEmail;
  final String expenseAccount;
  final String paidThrough;
  final double amount;
  final bool? isBillable;  // NEW FIELD
  final double tax;
  final double? gstRate;
  final int repeatEvery;
  final String repeatUnit;
  final DateTime startDate;
  final DateTime? endDate;
  final int? maxOccurrences;
  final DateTime nextExpenseDate;
  final String status;
  final int totalExpensesGenerated;
  final DateTime? lastGeneratedDate;
  final String expenseCreationMode;
  final String? notes;

  RecurringExpense({
    required this.id,
    required this.profileName,
    required this.vendorId,
    required this.vendorName,
    this.vendorEmail,
    required this.expenseAccount,
    required this.paidThrough,
    required this.amount,
    this.isBillable,  // NEW FIELD
    required this.tax,
    this.gstRate,
    required this.repeatEvery,
    required this.repeatUnit,
    required this.startDate,
    this.endDate,
    this.maxOccurrences,
    required this.nextExpenseDate,
    required this.status,
    required this.totalExpensesGenerated,
    this.lastGeneratedDate,
    required this.expenseCreationMode,
    this.notes,
  });

  factory RecurringExpense.fromJson(Map<String, dynamic> json) {
    return RecurringExpense(
      id: json['_id'] ?? '',
      profileName: json['profileName'] ?? '',
      vendorId: json['vendorId'] ?? '',
      vendorName: json['vendorName'] ?? '',
      vendorEmail: json['vendorEmail'],
      expenseAccount: json['expenseAccount'] ?? '',
      paidThrough: json['paidThrough'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      isBillable: json['isBillable'],  // NEW FIELD
      tax: (json['tax'] ?? 0).toDouble(),
      gstRate: json['gstRate'] != null ? (json['gstRate'] as num).toDouble() : null,
      repeatEvery: json['repeatEvery'] ?? 1,
      repeatUnit: json['repeatUnit'] ?? 'month',
      startDate: DateTime.parse(json['startDate']),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      maxOccurrences: json['maxOccurrences'],
      nextExpenseDate: DateTime.parse(json['nextExpenseDate']),
      status: json['status'] ?? 'ACTIVE',
      totalExpensesGenerated: json['totalExpensesGenerated'] ?? 0,
      lastGeneratedDate: json['lastGeneratedDate'] != null 
          ? DateTime.parse(json['lastGeneratedDate']) 
          : null,
      expenseCreationMode: json['expenseCreationMode'] ?? 'auto_create',
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profileName': profileName,
      'vendorId': vendorId,
      'vendorName': vendorName,
      'vendorEmail': vendorEmail,
      'expenseAccount': expenseAccount,
      'paidThrough': paidThrough,
      'amount': amount,
      'isBillable': isBillable,  // NEW FIELD
      'tax': tax,
      'gstRate': gstRate,
      'repeatEvery': repeatEvery,
      'repeatUnit': repeatUnit,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'maxOccurrences': maxOccurrences,
      'nextExpenseDate': nextExpenseDate.toIso8601String(),
      'status': status,
      'expenseCreationMode': expenseCreationMode,
      'notes': notes,
    };
  }
}

// ============================================================================
// RECURRING EXPENSE STATS MODEL
// ============================================================================

class RecurringExpenseStats {
  final int totalProfiles;
  final int activeProfiles;
  final int pausedProfiles;
  final int stoppedProfiles;
  final int totalExpensesGenerated;
  final double totalAmountGenerated;

  RecurringExpenseStats({
    required this.totalProfiles,
    required this.activeProfiles,
    required this.pausedProfiles,
    required this.stoppedProfiles,
    required this.totalExpensesGenerated,
    required this.totalAmountGenerated,
  });

  factory RecurringExpenseStats.fromJson(Map<String, dynamic> json) {
    return RecurringExpenseStats(
      totalProfiles: json['totalProfiles'] ?? 0,
      activeProfiles: json['activeProfiles'] ?? 0,
      pausedProfiles: json['pausedProfiles'] ?? 0,
      stoppedProfiles: json['stoppedProfiles'] ?? 0,
      totalExpensesGenerated: json['totalExpensesGenerated'] ?? 0,
      totalAmountGenerated: (json['totalAmountGenerated'] ?? 0).toDouble(),
    );
  }
}

// ============================================================================
// RECURRING EXPENSE SERVICE
// ============================================================================

class RecurringExpenseService {
  // Helper method to get JWT token
  static Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      print('❌ Error getting token: $e');
      return null;
    }
  }

  // ============================================================================
  // GET RECURRING EXPENSES
  // ============================================================================
  
  static Future<Map<String, dynamic>> getRecurringExpenses({
    String? status,
    String? fromDate,
    String? toDate,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _getToken();
      
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      
      if (status != null && status != 'All') {
        queryParams['status'] = status;
      }
      if (fromDate != null) {
        queryParams['fromDate'] = fromDate;
      }
      if (toDate != null) {
        queryParams['toDate'] = toDate;
      }
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses')
          .replace(queryParameters: queryParams);
      
      print('🔍 GET Recurring Expenses: $uri');
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': (data['data'] as List)
              .map((item) => RecurringExpense.fromJson(item))
              .toList(),
          'pagination': data['pagination'],
        };
      } else {
        print('❌ Error: ${response.body}');
        return {
          'success': false,
          'error': 'Failed to load recurring expenses',
        };
      }
    } catch (e) {
      print('❌ Exception in getRecurringExpenses: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ============================================================================
  // GET STATS
  // ============================================================================
  
  static Future<RecurringExpenseStats?> getStats() async {
    try {
      final token = await _getToken();
      
      print('📊 GET Stats');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/stats'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RecurringExpenseStats.fromJson(data['data']);
      }
      return null;
    } catch (e) {
      print('❌ Exception in getStats: $e');
      return null;
    }
  }

  // ============================================================================
  // GET SINGLE RECURRING EXPENSE
  // ============================================================================
  
  static Future<RecurringExpense?> getRecurringExpense(String id) async {
    try {
      final token = await _getToken();
      
      print('🔍 GET Recurring Expense: $id');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RecurringExpense.fromJson(data['data']);
      }
      return null;
    } catch (e) {
      print('❌ Exception in getRecurringExpense: $e');
      return null;
    }
  }

  // ============================================================================
  // CREATE RECURRING EXPENSE (UPDATED WITH TAX SUPPORT)
  // ============================================================================
  
  static Future<bool> createRecurringExpense(Map<String, dynamic> data) async {
    try {
      final token = await _getToken();
      
      // Ensure tax fields are properly formatted
      if (data.containsKey('tax')) {
        data['tax'] = (data['tax'] as num).toDouble();
      }
      if (data.containsKey('gstRate')) {
        data['gstRate'] = (data['gstRate'] as num).toDouble();
      }
      
      print('📝 CREATE Recurring Expense');
      print('Data: ${json.encode(data)}');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      print('📡 Response Status: ${response.statusCode}');
      print('📡 Response Body: ${response.body}');
      
      return response.statusCode == 201;
    } catch (e) {
      print('❌ Exception in createRecurringExpense: $e');
      return false;
    }
  }

  // ============================================================================
  // UPDATE RECURRING EXPENSE (UPDATED WITH TAX SUPPORT)
  // ============================================================================
  
  static Future<bool> updateRecurringExpense(String id, Map<String, dynamic> data) async {
    try {
      final token = await _getToken();
      
      // Ensure tax fields are properly formatted
      if (data.containsKey('tax')) {
        data['tax'] = (data['tax'] as num).toDouble();
      }
      if (data.containsKey('gstRate')) {
        data['gstRate'] = (data['gstRate'] as num).toDouble();
      }
      
      print('✏️ UPDATE Recurring Expense: $id');
      print('Data: ${json.encode(data)}');
      
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      print('📡 Response Status: ${response.statusCode}');
      print('📡 Response Body: ${response.body}');
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception in updateRecurringExpense: $e');
      return false;
    }
  }

  // ============================================================================
  // PAUSE RECURRING EXPENSE
  // ============================================================================
  
  static Future<bool> pauseRecurringExpense(String id) async {
    try {
      final token = await _getToken();
      
      print('⏸️ PAUSE Recurring Expense: $id');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id/pause'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception in pauseRecurringExpense: $e');
      return false;
    }
  }

  // ============================================================================
  // RESUME RECURRING EXPENSE
  // ============================================================================
  
  static Future<bool> resumeRecurringExpense(String id) async {
    try {
      final token = await _getToken();
      
      print('▶️ RESUME Recurring Expense: $id');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id/resume'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception in resumeRecurringExpense: $e');
      return false;
    }
  }

  // ============================================================================
  // STOP RECURRING EXPENSE
  // ============================================================================
  
  static Future<bool> stopRecurringExpense(String id) async {
    try {
      final token = await _getToken();
      
      print('⏹️ STOP Recurring Expense: $id');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id/stop'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception in stopRecurringExpense: $e');
      return false;
    }
  }

  // ============================================================================
  // GENERATE EXPENSE MANUALLY
  // ============================================================================
  
  static Future<bool> generateManualExpense(String id) async {
    try {
      final token = await _getToken();
      
      print('🔧 GENERATE Manual Expense: $id');
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id/generate'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      return response.statusCode == 201;
    } catch (e) {
      print('❌ Exception in generateManualExpense: $e');
      return false;
    }
  }

  // ============================================================================
  // GET CHILD EXPENSES
  // ============================================================================
  
  static Future<List<dynamic>> getChildExpenses(String id) async {
    try {
      final token = await _getToken();
      
      print('📋 GET Child Expenses: $id');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id/child-expenses'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'] ?? [];
      }
      return [];
    } catch (e) {
      print('❌ Exception in getChildExpenses: $e');
      return [];
    }
  }

  // ============================================================================
  // DELETE RECURRING EXPENSE
  // ============================================================================
  
  static Future<bool> deleteRecurringExpense(String id) async {
    try {
      final token = await _getToken();
      
      print('🗑️ DELETE Recurring Expense: $id');
      
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/recurring-expenses/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📡 Response Status: ${response.statusCode}');
      
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception in deleteRecurringExpense: $e');
      return false;
    }
  }
}
