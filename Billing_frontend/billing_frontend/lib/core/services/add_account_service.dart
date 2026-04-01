// ============================================================================
// ADD ACCOUNT SERVICE - WITH CUSTOM TYPE SUPPORT & JWT AUTH
// ============================================================================
// File: lib/services/add_account_service.dart
// Purpose: Bridge between frontend and backend for account operations
// Features:
// - Support for custom account types
// - Fetch custom types from backend
// - All standard CRUD operations
// - JWT Authentication
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../../app/config/api_config.dart';

class AddAccountService {
  // Uses centralized API configuration
  String get baseUrl => '${ApiConfig.baseUrl}/api/finance';
  
  // Timeout duration
  final Duration timeout = const Duration(seconds: 30);

  /// Get JWT token from SharedPreferences
  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      debugPrint('🔑 Retrieved JWT token: ${token != null ? "Present (${token.length} chars)" : "Missing"}');
      return token;
    } catch (e) {
      debugPrint('❌ Error retrieving JWT token: $e');
      return null;
    }
  }

  /// Get headers with JWT token
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    final headers = {
      'Content-Type': 'application/json',
    };
    
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
      debugPrint('✅ Authorization header added');
    } else {
      debugPrint('⚠️ No JWT token available - request may fail');
    }
    
    return headers;
  }

  /// Add a new account (supports custom types)
  Future<Map<String, dynamic>> addAccount(Map<String, dynamic> accountData) async {
    try {
      debugPrint('📡 Making HTTP request...');
      final headers = await _getHeaders();
      
      final response = await http
          .post(
            Uri.parse('$baseUrl/accounts/add'),
            headers: headers,
            body: jsonEncode(accountData),
          )
          .timeout(timeout);

      debugPrint('🔧 Response received in ${response.contentLength}ms, status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        debugPrint('❌ Failed to add account: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to add account: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error adding account: $e');
      throw Exception('Error adding account: $e');
    }
  }

  /// Get all custom account types
  Future<List<Map<String, dynamic>>> getCustomAccountTypes() async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .get(
            Uri.parse('$baseUrl/accounts/custom-types'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final List<dynamic> data = jsonResponse['data'];
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to fetch custom types: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching custom types: $e');
    }
  }

  /// Get all accounts
  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .get(
            Uri.parse('$baseUrl/accounts'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final List<dynamic> data = jsonResponse['data'];
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to fetch accounts: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching accounts: $e');
    }
  }

  /// Get account by ID
  Future<Map<String, dynamic>> getAccountById(String accountId) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .get(
            Uri.parse('$baseUrl/accounts/$accountId'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return jsonResponse['data'];
      } else {
        throw Exception('Failed to fetch account: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching account: $e');
    }
  }

  /// Update an existing account
  Future<Map<String, dynamic>> updateAccount(
    String accountId,
    Map<String, dynamic> accountData,
  ) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .put(
            Uri.parse('$baseUrl/accounts/$accountId'),
            headers: headers,
            body: jsonEncode(accountData),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update account: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating account: $e');
    }
  }

  /// Delete an account
  Future<bool> deleteAccount(String accountId) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .delete(
            Uri.parse('$baseUrl/accounts/$accountId'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200 || response.statusCode == 204) {
        return true;
      } else {
        throw Exception('Failed to delete account: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting account: $e');
    }
  }

  /// Get accounts by type
  Future<List<Map<String, dynamic>>> getAccountsByType(String accountType) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .get(
            Uri.parse('$baseUrl/accounts/type/$accountType'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final List<dynamic> data = jsonResponse['data'];
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to fetch accounts by type: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching accounts by type: $e');
    }
  }

  /// Get account balance
  Future<double> getAccountBalance(String accountId) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .get(
            Uri.parse('$baseUrl/accounts/$accountId/balance'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final data = jsonResponse['data'];
        return (data['balance'] as num).toDouble();
      } else {
        throw Exception('Failed to fetch account balance: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching account balance: $e');
    }
  }

  /// Update account status (active/inactive)
  Future<Map<String, dynamic>> updateAccountStatus(
    String accountId,
    bool isActive,
  ) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http
          .patch(
            Uri.parse('$baseUrl/accounts/$accountId/status'),
            headers: headers,
            body: jsonEncode({'isActive': isActive}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to update account status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating account status: $e');
    }
  }
}