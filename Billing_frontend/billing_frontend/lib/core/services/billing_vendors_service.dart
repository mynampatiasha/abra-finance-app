// ============================================================================
// BILLING VENDORS SERVICE - FLUTTER
// ============================================================================
// File: lib/core/services/billing_vendors_service.dart
//
// Features:
// - Complete CRUD operations for vendors
// - Proper error handling with custom exceptions
// - JWT authentication
// - Search and filter support
// ============================================================================

import 'package:flutter/foundation.dart';
import 'api_service.dart';

// ============================================================================
// CUSTOM EXCEPTION CLASS
// ============================================================================

class BillingVendorsException implements Exception {
  final String message;
  final int? statusCode;
  final List<String>? errors;
  
  BillingVendorsException(this.message, [this.statusCode, this.errors]);
  
  String toUserMessage() {
    if (errors != null && errors!.isNotEmpty) {
      return errors!.join('\n');
    }
    
    switch (statusCode) {
      case 400:
        return message.isNotEmpty ? message : 'Invalid vendor data. Please check your inputs.';
      case 401:
        return 'Authentication failed. Please login again.';
      case 403:
        return 'You do not have permission to perform this action.';
      case 404:
        return 'Vendor not found.';
      case 409:
        return 'A vendor with this email already exists.';
      case 500:
        return 'Server error. Please try again later.';
      default:
        return message.isNotEmpty ? message : 'An unexpected error occurred.';
    }
  }
  
  @override
  String toString() => 'BillingVendorsException: $message (Status: $statusCode)';
}

// ============================================================================
// BILLING VENDOR MODEL
// ============================================================================

class BillingVendor {
  final String id;
  final String vendorName;
  final String email;
  final String phoneNumber;
  final String? companyName;
  final String? vendorType;
  final String? status;

  BillingVendor({
    required this.id,
    required this.vendorName,
    required this.email,
    required this.phoneNumber,
    this.companyName,
    this.vendorType,
    this.status,
  });

  factory BillingVendor.fromJson(Map<String, dynamic> json) {
    return BillingVendor(
      id: json['_id'] ?? '',
      vendorName: json['vendorName'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      companyName: json['companyName'],
      vendorType: json['vendorType'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'vendorName': vendorName,
      'email': email,
      'phoneNumber': phoneNumber,
      'companyName': companyName,
      'vendorType': vendorType,
      'status': status,
    };
  }
}

// ============================================================================
// BILLING VENDORS SERVICE
// ============================================================================

class BillingVendorsService {
  static final ApiService _apiService = ApiService();
  
  // ============================================================================
  // CREATE VENDOR
  // ============================================================================
  
  static Future<Map<String, dynamic>> createVendor({
    required String vendorType,
    required String vendorName,
    String? companyName,
    required String email,
    required String phoneNumber,
    String? alternatePhone,
    String status = 'Active',
    bool bankDetailsProvided = false,
    String? accountHolderName,
    String? bankName,
    String? accountNumber,
    String? accountNumberConfirm,
    String? ifscCode,
    bool addressProvided = false,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? gstNumber,
    String? panNumber,
    String? serviceCategory,
    String? notes,
  }) async {
    try {
      debugPrint('\n' + '=' * 80);
      debugPrint('📝 CREATE VENDOR REQUEST');
      debugPrint('=' * 80);
      
      final requestBody = {
        'vendorType': vendorType,
        'vendorName': vendorName,
        'companyName': companyName ?? '',
        'email': email,
        'phoneNumber': phoneNumber,
        'alternatePhone': alternatePhone ?? '',
        'status': status,
        'bankDetailsProvided': bankDetailsProvided,
        'accountHolderName': accountHolderName ?? '',
        'bankName': bankName ?? '',
        'accountNumber': accountNumber ?? '',
        'accountNumberConfirm': accountNumberConfirm ?? '',
        'ifscCode': ifscCode ?? '',
        'addressProvided': addressProvided,
        'addressLine1': addressLine1 ?? '',
        'addressLine2': addressLine2 ?? '',
        'city': city ?? '',
        'state': state ?? '',
        'postalCode': postalCode ?? '',
        'country': country ?? 'India',
        'gstNumber': gstNumber ?? '',
        'panNumber': panNumber ?? '',
        'serviceCategory': serviceCategory ?? '',
        'notes': notes ?? '',
      };
      
      debugPrint('Request body: $requestBody');
      
      final response = await _apiService.post(
        '/api/finance/vendors',
        body: requestBody,
      );
      
      debugPrint('✅ Vendor created successfully');
      debugPrint('=' * 80 + '\n');
      
      return response;
      
    } on ApiException catch (e) {
      debugPrint('❌ ApiException in createVendor: ${e.message}');
      
      // Extract errors from details
      List<String>? errors;
      if (e.details != null && e.details!['errors'] != null) {
        errors = List<String>.from(e.details!['errors']);
      }
      
      throw BillingVendorsException(
        e.message,
        e.statusCode,
        errors,
      );
    } catch (e) {
      debugPrint('❌ Unexpected error in createVendor: $e');
      throw BillingVendorsException('Failed to create vendor: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // GET ALL VENDORS
  // ============================================================================
  
  static Future<Map<String, dynamic>> getAllVendors({
    String? search,
    String? vendorType,
    String? status,
    int page = 1,
    int limit = 1000,
    String sortBy = 'createdDate',
    String sortOrder = 'desc',
  }) async {
    try {
      debugPrint('\n' + '=' * 80);
      debugPrint('📋 GET ALL VENDORS REQUEST');
      debugPrint('=' * 80);
      debugPrint('Search: $search');
      debugPrint('Type: $vendorType');
      debugPrint('Status: $status');
      debugPrint('Page: $page, Limit: $limit');
      debugPrint('Sort: $sortBy $sortOrder');
      
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (vendorType != null && vendorType.isNotEmpty) queryParams['vendorType'] = vendorType;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      queryParams['page'] = page.toString();
      queryParams['limit'] = limit.toString();
      queryParams['sortBy'] = sortBy;
      queryParams['sortOrder'] = sortOrder;
      
      final response = await _apiService.get(
        '/api/finance/vendors',
        queryParams: queryParams,
      );
      
      debugPrint('✅ Vendors fetched successfully');
      debugPrint('=' * 80 + '\n');
      
      return response;
      
    } on ApiException catch (e) {
      debugPrint('❌ ApiException in getAllVendors: ${e.message}');
      throw BillingVendorsException(
        e.message,
        e.statusCode,
      );
    } catch (e) {
      debugPrint('❌ Unexpected error in getAllVendors: $e');
      throw BillingVendorsException('Failed to fetch vendors: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // GET VENDORS (Simple list for dropdowns)
  // ============================================================================
  
  static Future<List<BillingVendor>> getVendors() async {
    try {
      final response = await getAllVendors(limit: 1000);
      final raw = response['data'];
      final List<dynamic> data =
          raw is List ? raw : (raw['vendors'] as List? ?? []);
      return data.map((v) => BillingVendor.fromJson(v)).toList();
    } catch (e) {
      debugPrint('❌ Error in getVendors: $e');
      return [];
    }
  }
  
  // ============================================================================
  // GET VENDOR BY ID
  // ============================================================================
  
  static Future<Map<String, dynamic>> getVendorById(String vendorId) async {
    try {
      debugPrint('\n' + '=' * 80);
      debugPrint('📄 GET VENDOR BY ID REQUEST');
      debugPrint('=' * 80);
      debugPrint('Vendor ID: $vendorId');
      
      final response = await _apiService.get('/api/finance/vendors/$vendorId');
      
      debugPrint('✅ Vendor fetched successfully');
      debugPrint('=' * 80 + '\n');
      
      return response;
      
    } on ApiException catch (e) {
      debugPrint('❌ ApiException in getVendorById: ${e.message}');
      throw BillingVendorsException(
        e.message,
        e.statusCode,
      );
    } catch (e) {
      debugPrint('❌ Unexpected error in getVendorById: $e');
      throw BillingVendorsException('Failed to fetch vendor: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // UPDATE VENDOR
  // ============================================================================
  
  static Future<Map<String, dynamic>> updateVendor({
    required String vendorId,
    String? vendorType,
    String? vendorName,
    String? companyName,
    String? email,
    String? phoneNumber,
    String? alternatePhone,
    String? status,
    bool? bankDetailsProvided,
    String? accountHolderName,
    String? bankName,
    String? accountNumber,
    String? accountNumberConfirm,
    String? ifscCode,
    bool? addressProvided,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? gstNumber,
    String? panNumber,
    String? serviceCategory,
    String? notes,
  }) async {
    try {
      debugPrint('\n' + '=' * 80);
      debugPrint('✏️ UPDATE VENDOR REQUEST');
      debugPrint('=' * 80);
      debugPrint('Vendor ID: $vendorId');
      
      final requestBody = <String, dynamic>{};
      
      if (vendorType != null) requestBody['vendorType'] = vendorType;
      if (vendorName != null) requestBody['vendorName'] = vendorName;
      if (companyName != null) requestBody['companyName'] = companyName;
      if (email != null) requestBody['email'] = email;
      if (phoneNumber != null) requestBody['phoneNumber'] = phoneNumber;
      if (alternatePhone != null) requestBody['alternatePhone'] = alternatePhone;
      if (status != null) requestBody['status'] = status;
      
      if (bankDetailsProvided != null) {
        requestBody['bankDetailsProvided'] = bankDetailsProvided;
      }
      if (accountHolderName != null) requestBody['accountHolderName'] = accountHolderName;
      if (bankName != null) requestBody['bankName'] = bankName;
      if (accountNumber != null) requestBody['accountNumber'] = accountNumber;
      if (accountNumberConfirm != null) requestBody['accountNumberConfirm'] = accountNumberConfirm;
      if (ifscCode != null) requestBody['ifscCode'] = ifscCode;
      
      if (addressProvided != null) {
        requestBody['addressProvided'] = addressProvided;
      }
      if (addressLine1 != null) requestBody['addressLine1'] = addressLine1;
      if (addressLine2 != null) requestBody['addressLine2'] = addressLine2;
      if (city != null) requestBody['city'] = city;
      if (state != null) requestBody['state'] = state;
      if (postalCode != null) requestBody['postalCode'] = postalCode;
      if (country != null) requestBody['country'] = country;
      
      if (gstNumber != null) requestBody['gstNumber'] = gstNumber;
      if (panNumber != null) requestBody['panNumber'] = panNumber;
      if (serviceCategory != null) requestBody['serviceCategory'] = serviceCategory;
      if (notes != null) requestBody['notes'] = notes;
      
      debugPrint('Request body: $requestBody');
      
      final response = await _apiService.put(
        '/api/finance/vendors/$vendorId',
        body: requestBody,
      );
      
      debugPrint('✅ Vendor updated successfully');
      debugPrint('=' * 80 + '\n');
      
      return response;
      
    } on ApiException catch (e) {
      debugPrint('❌ ApiException in updateVendor: ${e.message}');
      
      // Extract errors from details
      List<String>? errors;
      if (e.details != null && e.details!['errors'] != null) {
        errors = List<String>.from(e.details!['errors']);
      }
      
      throw BillingVendorsException(
        e.message,
        e.statusCode,
        errors,
      );
    } catch (e) {
      debugPrint('❌ Unexpected error in updateVendor: $e');
      throw BillingVendorsException('Failed to update vendor: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // DELETE VENDOR
  // ============================================================================
  
  static Future<Map<String, dynamic>> deleteVendor(String vendorId) async {
    try {
      debugPrint('\n' + '=' * 80);
      debugPrint('🗑️ DELETE VENDOR REQUEST');
      debugPrint('=' * 80);
      debugPrint('Vendor ID: $vendorId');
      
      final response = await _apiService.delete('/api/finance/vendors/$vendorId');
      
      debugPrint('✅ Vendor deleted successfully');
      debugPrint('=' * 80 + '\n');
      
      return response;
      
    } on ApiException catch (e) {
      debugPrint('❌ ApiException in deleteVendor: ${e.message}');
      throw BillingVendorsException(
        e.message,
        e.statusCode,
      );
    } catch (e) {
      debugPrint('❌ Unexpected error in deleteVendor: $e');
      throw BillingVendorsException('Failed to delete vendor: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // BULK IMPORT VENDORS
  // ============================================================================
  
  static Future<Map<String, dynamic>> bulkImportVendors(
    List<Map<String, dynamic>> vendors,
  ) async {
    try {
      debugPrint('\n' + '=' * 80);
      debugPrint('📦 BULK IMPORT VENDORS REQUEST');
      debugPrint('=' * 80);
      debugPrint('Number of vendors: ${vendors.length}');
      
      final requestBody = {
        'vendors': vendors,
      };
      
      final response = await _apiService.post(
        '/api/finance/vendors/bulk-import',
        body: requestBody,
      );
      
      debugPrint('✅ Bulk import completed');
      debugPrint('Success: ${response['data']['successCount']}');
      debugPrint('Failed: ${response['data']['failedCount']}');
      debugPrint('=' * 80 + '\n');
      
      return response;
      
    } on ApiException catch (e) {
      debugPrint('❌ ApiException in bulkImportVendors: ${e.message}');
      throw BillingVendorsException(
        e.message,
        e.statusCode,
      );
    } catch (e) {
      debugPrint('❌ Unexpected error in bulkImportVendors: $e');
      throw BillingVendorsException('Failed to import vendors: ${e.toString()}');
    }
  }
}
