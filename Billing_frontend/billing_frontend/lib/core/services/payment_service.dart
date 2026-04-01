// ============================================================================
// PAYMENT SERVICE - COMPLETE WITH ZOHO BOOKS WORKFLOW
// ============================================================================
// File: lib/core/services/payment_service.dart
// Handles payment recording with invoice integration
// Implements exact Zoho Books workflow: Record Payment → Update Invoice → Send Email with Proofs
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../core/services/api_service.dart';
import '../../core/services/invoice_service.dart';

class PaymentService {
  static final ApiService _api = ApiService();
  static const String _baseEndpoint = '/api/finance/payments-received';

  // ============================================================================
  // PAYMENT CRUD OPERATIONS
  // ============================================================================

  /// Get all payments received with optional filters
  static Future<List<Map<String, dynamic>>> getPaymentsReceived({
    String? filter,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{};
      
      if (filter != null) queryParams['filter'] = filter;
      if (sortBy != null) queryParams['sortBy'] = sortBy;
      if (sortOrder != null) queryParams['sortOrder'] = sortOrder;
      
      print('📤 GET: $_baseEndpoint');
      
      final data = await _api.get(_baseEndpoint, queryParams: queryParams);
      
      print('✅ Response received: $data');
      
      // Handle different response structures
      if (data == null) {
        print('⚠️ Null response received');
        return [];
      }
      
      // Check if data has a 'data' field
      if (data.containsKey('data')) {
        final paymentsData = data['data'];
        
        // Ensure it's a list
        if (paymentsData is List) {
          print('✅ Payments fetched: ${paymentsData.length}');
          final List<dynamic> paymentsList = paymentsData as List;
          return List<Map<String, dynamic>>.from(
            paymentsList.map((item) => Map<String, dynamic>.from(item as Map))
          );
        } else {
          print('⚠️ data field is not a List: ${paymentsData.runtimeType}');
          return [];
        }
      }
      
      // If response is directly a list
      if (data is List) {
        print('✅ Payments fetched (direct list): ${data.length}');
        final List<dynamic> dataList = data as List;
        return List<Map<String, dynamic>>.from(
          dataList.map((item) => Map<String, dynamic>.from(item as Map))
        );
      }
      
      print('⚠️ Unexpected response structure: ${data.runtimeType}');
      return [];
    } catch (e) {
      print('❌ Error fetching payments: $e');
      print('❌ Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Get single payment by ID
  static Future<Map<String, dynamic>> getPayment(String paymentId) async {
    try {
      print('📤 GET: $_baseEndpoint/$paymentId');
      
      final data = await _api.get('$_baseEndpoint/$paymentId');
      
      print('✅ Payment fetched');
      
      return data['data'];
    } catch (e) {
      print('❌ Error fetching payment: $e');
      rethrow;
    }
  }

  /// Create new payment with proof files
  /// This follows Zoho Books workflow:
  /// 1. Record payment with proofs
  /// 2. Link to invoices and update status
  /// 3. Send payment receipt email ONLY if payment is recorded (not just marking as paid)
  static Future<Map<String, dynamic>> createPayment(
    Map<String, dynamic> paymentData,
    List<PlatformFile> proofFiles,
  ) async {
    try {
      print('\n' + '💰' * 50);
      print('CREATING PAYMENT WITH ZOHO BOOKS WORKFLOW');
      print('💰' * 50);
      print('📤 POST: $_baseEndpoint (with file upload)');
      print('📦 Payment data: ${json.encode(paymentData)}');
      print('📎 Proof files: ${proofFiles.length}');
      
      // Create multipart request
      final uri = Uri.parse('${_api.baseUrl}$_baseEndpoint');
      final request = http.MultipartRequest('POST', uri);
      
      // Add auth headers - ApiService will handle token automatically
      final headers = await _api.getHeaders();
      request.headers.addAll(headers);
      
      // Add payment data as JSON field
      request.fields['paymentData'] = json.encode(paymentData);
      
      // Add proof files - Handle web vs mobile/desktop differently
      for (var file in proofFiles) {
        http.MultipartFile multipartFile;
        
        if (kIsWeb) {
          // Web: Use bytes instead of path
          if (file.bytes != null) {
            // Determine content type from file extension
            String contentType = 'application/octet-stream';
            final extension = file.name.toLowerCase().split('.').last;
            
            if (extension == 'pdf') {
              contentType = 'application/pdf';
            } else if (['jpg', 'jpeg'].contains(extension)) {
              contentType = 'image/jpeg';
            } else if (extension == 'png') {
              contentType = 'image/png';
            } else if (extension == 'gif') {
              contentType = 'image/gif';
            }
            
            // Parse content type into MediaType
            final parts = contentType.split('/');
            final mediaType = MediaType(parts[0], parts[1]);
            
            multipartFile = http.MultipartFile.fromBytes(
              'paymentProofs',
              file.bytes!,
              filename: file.name,
              contentType: mediaType,
            );
            request.files.add(multipartFile);
            print('📎 Added file (web): ${file.name} (${(file.size / 1024).toStringAsFixed(1)} KB) - Type: $contentType');
          } else {
            print('⚠️ Skipping file ${file.name}: bytes not available on web');
          }
        } else {
          // Mobile/Desktop: Use path
          if (file.path != null) {
            multipartFile = await http.MultipartFile.fromPath(
              'paymentProofs',
              file.path!,
              filename: file.name,
            );
            request.files.add(multipartFile);
            print('📎 Added file (mobile): ${file.name} (${(file.size / 1024).toStringAsFixed(1)} KB)');
          } else {
            print('⚠️ Skipping file ${file.name}: path not available');
          }
        }
      }
      
      // Send request
      print('🚀 Sending payment recording request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ Payment recorded successfully');
        print('   Payment #: ${data['data']['paymentNumber']}');
        print('   Amount: ₹${data['data']['amountReceived']}');
        print('   Proofs uploaded: ${data['data']['proofsUploaded'] ?? proofFiles.length}');
        print('   Invoices updated: ${(data['data']['invoicePayments'] as Map?)?.keys.length ?? 0}');
        if (data['data']['emailSent'] == true) {
          print('   📧 Payment receipt email sent');
        }
        print('💰' * 50 + '\n');
        return data['data'];
      } else {
        print('❌ Payment creation failed: ${response.body}');
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to create payment');
      }
    } catch (e) {
      print('❌ Error creating payment: $e');
      print('💰' * 50 + '\n');
      rethrow;
    }
  }

  /// Update existing payment
  static Future<Map<String, dynamic>> updatePayment(
    String paymentId,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      print('📤 PUT: $_baseEndpoint/$paymentId');
      
      final data = await _api.put('$_baseEndpoint/$paymentId', body: paymentData);
      
      print('✅ Payment updated');
      
      return data['data'];
    } catch (e) {
      print('❌ Error updating payment: $e');
      rethrow;
    }
  }

  /// Delete payment
  static Future<void> deletePayment(String paymentId) async {
    try {
      print('📤 DELETE: $_baseEndpoint/$paymentId');
      
      await _api.delete('$_baseEndpoint/$paymentId');
      
      print('✅ Payment deleted');
    } catch (e) {
      print('❌ Error deleting payment: $e');
      rethrow;
    }
  }

  // ============================================================================
  // PAYMENT PROOFS MANAGEMENT
  // ============================================================================

  /// Get payment proofs for a payment
  static Future<List<PaymentProof>> getPaymentProofs(String paymentId) async {
    try {
      print('📤 GET: $_baseEndpoint/$paymentId/proofs');
      
      final data = await _api.get('$_baseEndpoint/$paymentId/proofs');
      
      print('✅ Payment proofs fetched: ${data['data'].length}');
      
      return (data['data'] as List)
          .map((proof) => PaymentProof.fromJson(proof))
          .toList();
    } catch (e) {
      print('❌ Error fetching payment proofs: $e');
      rethrow;
    }
  }

  /// Download payment proof
  static Future<String> downloadPaymentProof(String paymentId, String proofId) async {
    try {
      print('📤 GET: $_baseEndpoint/$paymentId/proofs/$proofId/download');
      
      // Return the URL for download
      final url = '${_api.baseUrl}$_baseEndpoint/$paymentId/proofs/$proofId/download';
      
      print('✅ Proof download URL: $url');
      
      return url;
    } catch (e) {
      print('❌ Error getting proof download URL: $e');
      rethrow;
    }
  }

  // ============================================================================
  // UNPAID INVOICES
  // ============================================================================

  /// Get unpaid invoices for a customer
  /// Returns only SENT/UNPAID/OVERDUE/PARTIALLY_PAID invoices with amountDue > 0
  static Future<List<Invoice>> getUnpaidInvoices(String customerId) async {
    try {
      print('📤 GET: $_baseEndpoint/customer/$customerId/unpaid-invoices');
      
      final data = await _api.get('$_baseEndpoint/customer/$customerId/unpaid-invoices');
      
      print('✅ Unpaid invoices fetched: ${data['data'].length}');
      
      return (data['data'] as List)
          .map((invoice) => Invoice.fromJson(invoice))
          .toList();
    } catch (e) {
      print('❌ Error fetching unpaid invoices: $e');
      rethrow;
    }
  }

  // ============================================================================
  // STATISTICS
  // ============================================================================

  /// Get payment statistics
  static Future<Map<String, dynamic>> getPaymentStats({
    String? startDate,
    String? endDate,
    String? customerName,
  }) async {
    try {
      final queryParams = <String, String>{};
      
      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      if (customerName != null) queryParams['customerName'] = customerName;
      
      print('📤 GET: $_baseEndpoint/stats/summary');
      
      final data = await _api.get('$_baseEndpoint/stats/summary', queryParams: queryParams);
      
      print('✅ Payment stats fetched');
      
      return data['data'];
    } catch (e) {
      print('❌ Error fetching payment stats: $e');
      rethrow;
    }
  }

  // ============================================================================
  // UTILITIES
  // ============================================================================

  /// Get next payment number
  static Future<String> getNextPaymentNumber() async {
    try {
      print('📤 GET: $_baseEndpoint/next-payment-number');
      
      final data = await _api.get('$_baseEndpoint/next-payment-number');
      
      final nextNumber = data['data']['nextPaymentNumber'];
      print('✅ Next payment number: $nextNumber');
      
      return nextNumber;
    } catch (e) {
      print('❌ Error getting next payment number: $e');
      rethrow;
    }
  }

  /// Export payments to CSV
  static Future<String> exportPaymentsCSV({
    String? filter,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      
      if (filter != null) queryParams['filter'] = filter;
      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      
      print('📤 GET: $_baseEndpoint/export/csv');
      
      // Return the URL for download
      final url = '${_api.baseUrl}$_baseEndpoint/export/csv';
      
      print('✅ CSV export URL: $url');
      
      return url;
    } catch (e) {
      print('❌ Error exporting CSV: $e');
      rethrow;
    }
  }
}

// ============================================================================
// PAYMENT PROOF MODEL
// ============================================================================

class PaymentProof {
  final String id;
  final String filename;
  final String filepath;
  final String fileType;
  final int fileSize;
  final DateTime uploadedAt;

  PaymentProof({
    required this.id,
    required this.filename,
    required this.filepath,
    required this.fileType,
    required this.fileSize,
    required this.uploadedAt,
  });

  factory PaymentProof.fromJson(Map<String, dynamic> json) {
    return PaymentProof(
      id: json['_id'] ?? json['id'],
      filename: json['filename'],
      filepath: json['filepath'],
      fileType: json['fileType'] ?? 'unknown',
      fileSize: json['fileSize'] ?? 0,
      uploadedAt: DateTime.parse(json['uploadedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'filepath': filepath,
      'fileType': fileType,
      'fileSize': fileSize,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }
}
