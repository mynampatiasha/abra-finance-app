// ============================================================================
// BILLING CUSTOMERS SERVICE - FLUTTER
// ============================================================================
// File: lib/services/billing_customers_service.dart
// 
// Complete service layer to connect Flutter frontend with Node.js backend
// Handles all API calls for billing customers module
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../app/config/api_config.dart';

class BillingCustomersService {
  // ============================================================================
  // CONFIGURATION
  // ============================================================================
  
  static String get _baseUrl => ApiConfig.baseUrl; // Use centralized API config
  static const String _apiPath = '/api/finance/customers';
  
  // Full API endpoint
  static String get _endpoint => '$_baseUrl$_apiPath';
  
  // ============================================================================
  // AUTHENTICATION
  // ============================================================================
  
  /// Get JWT token from SharedPreferences
  static Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      print('❌ Failed to get auth token: $e');
      return null;
    }
  }
  
  /// Get headers with authentication
  static Future<Map<String, String>> _getHeaders({bool isMultipart = false}) async {
    final token = await _getAuthToken();
    
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    
    if (!isMultipart) {
      headers['Content-Type'] = 'application/json';
    }
    
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    return headers;
  }
  
  // ============================================================================
  // ERROR HANDLING
  // ============================================================================
  
  static Map<String, dynamic> _handleResponse(http.Response response) {
    print('\n📡 API Response:');
    print('   Status: ${response.statusCode}');
    print('   Body: ${response.body}');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return json.decode(response.body);
      } catch (e) {
        return {
          'success': true,
          'data': response.body,
        };
      }
    } else {
      try {
        final errorData = json.decode(response.body);
        throw BillingCustomersException(
          message: errorData['message'] ?? errorData['error'] ?? 'Request failed',
          statusCode: response.statusCode,
          details: errorData,
        );
      } catch (e) {
        if (e is BillingCustomersException) rethrow;
        throw BillingCustomersException(
          message: 'Request failed with status ${response.statusCode}',
          statusCode: response.statusCode,
          details: {'body': response.body},
        );
      }
    }
  }
  
  // ============================================================================
  // CREATE CUSTOMER
  // ============================================================================
  
  /// Create a new billing customer
  static Future<Map<String, dynamic>> createCustomer(
    Map<String, dynamic> customerData,
  ) async {
    try {
      print('\n➕ CREATE BILLING CUSTOMER');
      print('─' * 80);
      print('   Endpoint: $_endpoint');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: headers,
        body: json.encode(customerData),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Customer created successfully');
      
      return result;
    } catch (e) {
      print('   ❌ Create customer failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // GET CUSTOMERS
  // ============================================================================
  
  /// Get all billing customers with optional filters
  static Future<Map<String, dynamic>> getAllCustomers({
    String? customerType,
    String? customerStatus,
    String? salesTerritory,
    String? customerTier,
    String? search,
    int page = 1,
    int limit = 50,
    String sortBy = 'createdDate',
    String sortOrder = 'desc',
    bool skipStats = false,
  }) async {
    try {
      print('\n📋 GET ALL BILLING CUSTOMERS');
      print('─' * 80);
      
      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'sortBy': sortBy,
        'sortOrder': sortOrder,
      };
      
      if (customerType != null) queryParams['customerType'] = customerType;
      if (customerStatus != null) queryParams['customerStatus'] = customerStatus;
      if (salesTerritory != null) queryParams['salesTerritory'] = salesTerritory;
      if (customerTier != null) queryParams['customerTier'] = customerTier;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (skipStats) queryParams['skipStats'] = 'true';
      
      final uri = Uri.parse(_endpoint).replace(queryParameters: queryParams);
      print('   Endpoint: $uri');
      
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Retrieved ${result['data']?['customers']?.length ?? 0} customers');
      
      return result;
    } catch (e) {
      print('   ❌ Get customers failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // GET CUSTOMER BY ID
  // ============================================================================
  
  /// Get a single billing customer by ID
  static Future<Map<String, dynamic>> getCustomerById(String customerId) async {
    try {
      print('\n🔍 GET BILLING CUSTOMER BY ID');
      print('─' * 80);
      print('   ID: $customerId');
      
      final uri = Uri.parse('$_endpoint/$customerId');
      final headers = await _getHeaders();
      
      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Customer retrieved successfully');
      
      return result;
    } catch (e) {
      print('   ❌ Get customer failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // UPDATE CUSTOMER
  // ============================================================================
  
  /// Update an existing billing customer
  static Future<Map<String, dynamic>> updateCustomer(
    String customerId,
    Map<String, dynamic> customerData,
  ) async {
    try {
      print('\n✏️  UPDATE BILLING CUSTOMER');
      print('─' * 80);
      print('   ID: $customerId');
      
      final uri = Uri.parse('$_endpoint/$customerId');
      final headers = await _getHeaders();
      
      final response = await http.put(
        uri,
        headers: headers,
        body: json.encode(customerData),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Customer updated successfully');
      
      return result;
    } catch (e) {
      print('   ❌ Update customer failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // DELETE CUSTOMER
  // ============================================================================
  
  /// Delete a billing customer (soft delete)
  static Future<Map<String, dynamic>> deleteCustomer(String customerId) async {
    try {
      print('\n🗑️  DELETE BILLING CUSTOMER');
      print('─' * 80);
      print('   ID: $customerId');
      
      final uri = Uri.parse('$_endpoint/$customerId');
      final headers = await _getHeaders();
      
      final response = await http.delete(uri, headers: headers).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Customer deleted successfully');
      
      return result;
    } catch (e) {
      print('   ❌ Delete customer failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // UPLOAD DOCUMENTS
  // ============================================================================
  
static Future<Map<String, dynamic>> uploadDocuments(
  String customerId,
  String category,
  List<PlatformFile> files,
) async {
  try {
    print('\n📤 UPLOAD DOCUMENTS');
    print('─' * 80);
    print('   Customer ID: $customerId');
    print('   Category: $category');
    print('   Files: ${files.length}');

    final uri = Uri.parse('$_endpoint/$customerId/upload-documents');
    final headers = await _getHeaders(isMultipart: true);

    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(headers);
    request.fields['category'] = category;

    for (final file in files) {
      if (kIsWeb) {
        // Web: use bytes — file.path is null on web
        if (file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'documents',
              file.bytes!,
              filename: file.name,
            ),
          );
          print('   Added file (web): ${file.name} (${file.bytes!.length} bytes)');
        } else {
          print('   ⚠️ Skipping ${file.name} — no bytes available');
        }
      } else {
        // Mobile/Desktop: use path
        if (file.path != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'documents',
              file.path!,
              filename: file.name,
            ),
          );
          print('   Added file (mobile): ${file.name}');
        } else {
          print('   ⚠️ Skipping ${file.name} — no path available');
        }
      }
    }

    print('📡 Sending files to server...');
    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw BillingCustomersException(
          message: 'Upload timed out',
          statusCode: 408,
        );
      },
    );

    final response = await http.Response.fromStream(streamedResponse);
    final result = _handleResponse(response);

    print('   ✅ Documents uploaded successfully');
    return result;

  } catch (e) {
    print('   ❌ Upload failed: $e');
    rethrow;
  }
}
  // ============================================================================
  // BULK IMPORT CUSTOMERS
  // ============================================================================
  
  /// Bulk import customers from Excel/CSV
  static Future<Map<String, dynamic>> bulkImportCustomers(
    List<Map<String, dynamic>> customersData,
  ) async {
    try {
      print('\n📤 BULK IMPORT CUSTOMERS');
      print('─' * 80);
      print('   Endpoint: $_endpoint/bulk-import');
      print('   Customers: ${customersData.length}');
      
      final headers = await _getHeaders();
      
      final response = await http.post(
        Uri.parse('$_endpoint/bulk-import'),
        headers: headers,
        body: json.encode({'customers': customersData}),
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Bulk import completed');
      
      return result;
    } catch (e) {
      print('   ❌ Bulk import failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // GET CUSTOMERS BY TYPE
  // ============================================================================
  
  /// Get customers filtered by type
  static Future<Map<String, dynamic>> getCustomersByType(String customerType) async {
    try {
      print('\n📊 GET CUSTOMERS BY TYPE');
      print('─' * 80);
      print('   Type: $customerType');
      
      final uri = Uri.parse('$_endpoint/type/$customerType');
      final headers = await _getHeaders();
      
      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Retrieved ${result['data']?['count'] ?? 0} customers');
      
      return result;
    } catch (e) {
      print('   ❌ Get customers by type failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // GET STATISTICS
  // ============================================================================
  
  /// Get customer statistics and analytics
  static Future<Map<String, dynamic>> getStatistics() async {
    try {
      print('\n📊 GET CUSTOMER STATISTICS');
      print('─' * 80);
      
      final uri = Uri.parse('$_endpoint/statistics/overview');
      final headers = await _getHeaders();
      
      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw BillingCustomersException(
            message: 'Request timed out',
            statusCode: 408,
          );
        },
      );
      
      final result = _handleResponse(response);
      print('   ✅ Statistics retrieved successfully');
      
      return result;
    } catch (e) {
      print('   ❌ Get statistics failed: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // HELPER METHOD - BUILD CUSTOMER DATA
  // ============================================================================
  
  /// Build customer data map from form controllers
  static Map<String, dynamic> buildCustomerDataFromControllers({
    required String customerType,
    required String customerDisplayName,
    required String primaryEmail,
    required String primaryPhone,
    required String addressLine1,
    required String city,
    required String state,
    required String salesTerritory,
    String? primaryContactPerson,
    String? alternatePhone,
    String? addressLine2,
    String? postalCode,
    String country = 'India',
    String? companyRegistration,
    String? panNumber,
    String? gstNumber,
    String? tanNumber,
    String? industryType,
    String? employeeStrength,
    String? annualContractValue,
    List<Map<String, dynamic>>? contactPersons,
    String customerStatus = 'Active',
    String? reasonForBlocking,
    String? customerTier,
    List<String>? tags,
    String? rateCard,
    String? contractType,
    String? contractStartDate,
    String? contractEndDate,
    bool autoRenewal = false,
    String? renewalNoticePeriod,
    String? vendorCommissionType,
    String? commissionRate,
    String? fixedAmountPerTrip,
    String? revenueShare,
    String? minimumGuarantee,
    String? paymentCycle,
    List<String>? vehicleTypesProvided,
    String? numberOfVehiclesProvided,
    String paymentTerms = 'Immediate/COD',
    String? preferredPaymentMethod,
    String? creditLimit,
    String? securityDeposit,
    String? securityDepositStatus,
    bool blockBookingIfCreditExceeded = false,
    String billingFrequency = 'Per-trip',
    String? billingEmail,
    String? billingAddress,
    bool sameAsPrimaryAddress = true,
    bool poNumberRequired = false,
    List<String>? invoiceDeliveryMethods,
    String invoiceLanguage = 'English',
    String? taxRegistrationType,
    String? vendorVehiclesAvailable,
    List<String>? vendorVehicleTypes,
    String? vendorAgreementStart,
    String? vendorAgreementEnd,
    double vendorPerformanceRating = 0,
    String? insuranceValidUntil,
    String? bankName,
    String? bankAccountNumber,
    String? ifscCode,
    String? accountHolderName,
    String? branchName,
    String? upiId,
    String? internalNotes,
    String? customerInstructions,
    String? specialRequirements,
    List<Map<String, dynamic>>? customFields,
  }) {
    // Generate unique customer ID
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final customerId = 'CUST-$timestamp';
    
    final data = <String, dynamic>{
      'customerId': customerId, // ✅ ADDED: Required by backend schema
      'customerType': customerType,
      'customerDisplayName': customerDisplayName,
      'primaryEmail': primaryEmail,
      'primaryPhone': primaryPhone,
      'addressLine1': addressLine1,
      'city': city,
      'state': state,
      'country': country,
      'customerStatus': customerStatus,
      'salesTerritory': salesTerritory,
      'paymentTerms': paymentTerms,
      'billingFrequency': billingFrequency,
      'sameAsPrimaryAddress': sameAsPrimaryAddress,
      'poNumberRequired': poNumberRequired,
      'invoiceLanguage': invoiceLanguage,
      'autoRenewal': autoRenewal,
      'blockBookingIfCreditExceeded': blockBookingIfCreditExceeded,
      'vendorPerformanceRating': vendorPerformanceRating,
    };
    
    // Add optional string fields
    void addIfNotEmpty(String key, String? value) {
      if (value != null && value.isNotEmpty) {
        data[key] = value;
      }
    }
    
    addIfNotEmpty('primaryContactPerson', primaryContactPerson);
    addIfNotEmpty('alternatePhone', alternatePhone);
    addIfNotEmpty('addressLine2', addressLine2);
    addIfNotEmpty('postalCode', postalCode);
    addIfNotEmpty('companyRegistration', companyRegistration);
    addIfNotEmpty('panNumber', panNumber);
    addIfNotEmpty('gstNumber', gstNumber);
    addIfNotEmpty('tanNumber', tanNumber);
    addIfNotEmpty('industryType', industryType);
    addIfNotEmpty('reasonForBlocking', reasonForBlocking);
    addIfNotEmpty('customerTier', customerTier);
    addIfNotEmpty('rateCard', rateCard);
    addIfNotEmpty('contractType', contractType);
    addIfNotEmpty('contractStartDate', contractStartDate);
    addIfNotEmpty('contractEndDate', contractEndDate);
    addIfNotEmpty('vendorCommissionType', vendorCommissionType);
    addIfNotEmpty('paymentCycle', paymentCycle);
    addIfNotEmpty('preferredPaymentMethod', preferredPaymentMethod);
    addIfNotEmpty('securityDepositStatus', securityDepositStatus);
    addIfNotEmpty('billingEmail', billingEmail);
    addIfNotEmpty('billingAddress', billingAddress);
    addIfNotEmpty('taxRegistrationType', taxRegistrationType);
    addIfNotEmpty('vendorAgreementStart', vendorAgreementStart);
    addIfNotEmpty('vendorAgreementEnd', vendorAgreementEnd);
    addIfNotEmpty('insuranceValidUntil', insuranceValidUntil);
    addIfNotEmpty('bankName', bankName);
    addIfNotEmpty('bankAccountNumber', bankAccountNumber);
    addIfNotEmpty('ifscCode', ifscCode);
    addIfNotEmpty('accountHolderName', accountHolderName);
    addIfNotEmpty('branchName', branchName);
    addIfNotEmpty('upiId', upiId);
    addIfNotEmpty('internalNotes', internalNotes);
    addIfNotEmpty('customerInstructions', customerInstructions);
    addIfNotEmpty('specialRequirements', specialRequirements);
    
    // Add numeric fields
    if (employeeStrength != null && employeeStrength.isNotEmpty) {
      data['employeeStrength'] = int.tryParse(employeeStrength);
    }
    if (annualContractValue != null && annualContractValue.isNotEmpty) {
      data['annualContractValue'] = double.tryParse(annualContractValue);
    }
    if (renewalNoticePeriod != null && renewalNoticePeriod.isNotEmpty) {
      data['renewalNoticePeriod'] = int.tryParse(renewalNoticePeriod);
    }
    if (commissionRate != null && commissionRate.isNotEmpty) {
      data['commissionRate'] = double.tryParse(commissionRate);
    }
    if (fixedAmountPerTrip != null && fixedAmountPerTrip.isNotEmpty) {
      data['fixedAmountPerTrip'] = double.tryParse(fixedAmountPerTrip);
    }
    if (revenueShare != null && revenueShare.isNotEmpty) {
      data['revenueShare'] = double.tryParse(revenueShare);
    }
    if (minimumGuarantee != null && minimumGuarantee.isNotEmpty) {
      data['minimumGuarantee'] = double.tryParse(minimumGuarantee);
    }
    if (numberOfVehiclesProvided != null && numberOfVehiclesProvided.isNotEmpty) {
      data['numberOfVehiclesProvided'] = int.tryParse(numberOfVehiclesProvided);
    }
    if (creditLimit != null && creditLimit.isNotEmpty) {
      data['creditLimit'] = double.tryParse(creditLimit) ?? 0;
    }
    if (securityDeposit != null && securityDeposit.isNotEmpty) {
      data['securityDeposit'] = double.tryParse(securityDeposit);
    }
    if (vendorVehiclesAvailable != null && vendorVehiclesAvailable.isNotEmpty) {
      data['vendorVehiclesAvailable'] = int.tryParse(vendorVehiclesAvailable);
    }
    
    // Add array fields
    if (contactPersons != null && contactPersons.isNotEmpty) {
      data['contactPersons'] = contactPersons;
    }
    if (tags != null && tags.isNotEmpty) {
      data['tags'] = tags;
    }
    if (vehicleTypesProvided != null && vehicleTypesProvided.isNotEmpty) {
      data['vehicleTypesProvided'] = vehicleTypesProvided;
    }
    if (invoiceDeliveryMethods != null && invoiceDeliveryMethods.isNotEmpty) {
      data['invoiceDeliveryMethods'] = invoiceDeliveryMethods;
    }
    if (vendorVehicleTypes != null && vendorVehicleTypes.isNotEmpty) {
      data['vendorVehicleTypes'] = vendorVehicleTypes;
    }
    if (customFields != null && customFields.isNotEmpty) {
      data['customFields'] = customFields;
    }
    
    return data;
  }
  
  // ============================================================================
  // VALIDATION
  // ============================================================================
  
  /// Validate customer data before submission
  static String? validateCustomerData(Map<String, dynamic> data) {
    if (data['customerType'] == null || data['customerType'].toString().isEmpty) {
      return 'Customer type is required';
    }
    
    if (data['customerDisplayName'] == null || data['customerDisplayName'].toString().isEmpty) {
      return 'Customer name is required';
    }
    
    if (data['primaryEmail'] == null || data['primaryEmail'].toString().isEmpty) {
      return 'Primary email is required';
    }
    
    if (data['primaryPhone'] == null || data['primaryPhone'].toString().isEmpty) {
      return 'Primary phone is required';
    }
    
    if (data['addressLine1'] == null || data['addressLine1'].toString().isEmpty) {
      return 'Address is required';
    }
    
    if (data['city'] == null || data['city'].toString().isEmpty) {
      return 'City is required';
    }
    
    if (data['state'] == null || data['state'].toString().isEmpty) {
      return 'State is required';
    }
    
    if (data['salesTerritory'] == null || data['salesTerritory'].toString().isEmpty) {
      return 'Sales territory is required';
    }
    
    final customerType = data['customerType'];
    if (customerType == 'Organization' || customerType == 'Vendor') {
      if (data['gstNumber'] == null || data['gstNumber'].toString().isEmpty) {
        return 'GST Number is required for $customerType customers';
      }
    }
    
    if (customerType == 'Vendor') {
      if (data['vendorCommissionType'] == null || data['vendorCommissionType'].toString().isEmpty) {
        return 'Commission type is required for Vendor customers';
      }
    }
    
    if (data['customerStatus'] == 'Blocked') {
      if (data['reasonForBlocking'] == null || data['reasonForBlocking'].toString().isEmpty) {
        return 'Reason for blocking is required when status is Blocked';
      }
    }
    
    return null;
  }
}

// ============================================================================
// CUSTOM EXCEPTION
// ============================================================================

class BillingCustomersException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;
  
  BillingCustomersException({
    required this.message,
    required this.statusCode,
    this.details,
  });
  
  @override
  String toString() {
    return 'BillingCustomersException: $message (Status: $statusCode)';
  }
  
  String toUserMessage() {
    if (statusCode == 401) {
      return 'Authentication failed. Please login again.';
    } else if (statusCode == 403) {
      return 'You do not have permission to perform this action.';
    } else if (statusCode == 404) {
      return 'Customer not found.';
    } else if (statusCode == 408) {
      return 'Request timed out. Please check your internet connection.';
    } else if (statusCode == 409) {
      return 'A customer with this information already exists.';
    } else if (statusCode >= 500) {
      return 'Server error. Please try again later.';
    } else {
      return message;
    }
  }
}