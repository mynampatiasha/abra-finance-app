// ============================================================================
// CREDIT NOTE SERVICE - COMPLETE FLUTTER SERVICE (FIXED)
// ============================================================================
// File: lib/core/services/credit_note_service.dart
// Features:
// ✅ Complete CRUD operations
// ✅ Refund tracking
// ✅ Credit application to invoices
// ✅ Import/Export functionality
// ✅ PDF download
// ✅ Email sending
// ✅ NO DUPLICATE CLASSES - imports from invoice_service.dart
// ============================================================================

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

// ✅ IMPORT shared classes from invoice_service.dart
import '../../../../core/services/invoice_service.dart' show Address, BillingCustomer, BillingCustomerListResponse, Pagination;

class CreditNoteService {
  static final ApiService _api = ApiService();
  static const String _baseEndpoint = '/api/finance/credit-notes';

  // ============================================================================
  // CRUD OPERATIONS
  // ============================================================================

  /// Get all credit notes with optional filters
  static Future<CreditNoteListResponse> getCreditNotes({
    String? status,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (status != null) queryParams['status'] = status;
      if (customerId != null) queryParams['customerId'] = customerId;
      if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      print('📤 GET: $_baseEndpoint with filters: $queryParams');

      final data = await _api.get(_baseEndpoint, queryParams: queryParams);

      print('✅ Credit notes fetched: ${data['data'].length}');

      return CreditNoteListResponse.fromJson(data);
    } catch (e) {
      print('❌ Error fetching credit notes: $e');
      rethrow;
    }
  }

  /// Get credit note statistics
  static Future<CreditNoteStats> getStats() async {
    try {
      print('📤 GET: $_baseEndpoint/stats');

      final data = await _api.get('$_baseEndpoint/stats');

      print('✅ Stats fetched');

      return CreditNoteStats.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching stats: $e');
      rethrow;
    }
  }

  /// Get single credit note by ID
  static Future<CreditNote> getCreditNote(String creditNoteId) async {
    try {
      print('📤 GET: $_baseEndpoint/$creditNoteId');

      final data = await _api.get('$_baseEndpoint/$creditNoteId');

      print('✅ Credit note fetched: ${data['data']['creditNoteNumber']}');

      return CreditNote.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching credit note: $e');
      rethrow;
    }
  }

  /// Create new credit note
  static Future<CreditNote> createCreditNote(Map<String, dynamic> creditNoteData) async {
    try {
      print('📤 POST: $_baseEndpoint');
      print('📦 Data: ${json.encode(creditNoteData)}');

      final data = await _api.post(_baseEndpoint, body: creditNoteData);

      print('✅ Credit note created: ${data['data']['creditNoteNumber']}');

      return CreditNote.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating credit note: $e');
      rethrow;
    }
  }

  /// Update existing credit note
  static Future<CreditNote> updateCreditNote(
      String creditNoteId, Map<String, dynamic> creditNoteData) async {
    try {
      print('📤 PUT: $_baseEndpoint/$creditNoteId');
      print('📦 Data: ${json.encode(creditNoteData)}');

      final data = await _api.put('$_baseEndpoint/$creditNoteId', body: creditNoteData);

      print('✅ Credit note updated: ${data['data']['creditNoteNumber']}');

      return CreditNote.fromJson(data['data']);
    } catch (e) {
      print('❌ Error updating credit note: $e');
      rethrow;
    }
  }

  /// Send credit note via email
  static Future<CreditNote> sendCreditNote(String creditNoteId) async {
    try {
      print('📤 POST: $_baseEndpoint/$creditNoteId/send');

      final data = await _api.post('$_baseEndpoint/$creditNoteId/send');

      print('✅ Credit note sent: ${data['data']['creditNoteNumber']}');

      return CreditNote.fromJson(data['data']);
    } catch (e) {
      print('❌ Error sending credit note: $e');
      rethrow;
    }
  }

  /// Record refund for credit note
  static Future<RefundResponse> recordRefund(
    String creditNoteId,
    Map<String, dynamic> refundData,
  ) async {
    try {
      print('📤 POST: $_baseEndpoint/$creditNoteId/refund');
      print('📦 Refund: ${json.encode(refundData)}');

      final data = await _api.post('$_baseEndpoint/$creditNoteId/refund', body: refundData);

      print('✅ Refund recorded: ₹${refundData['amount']}');

      return RefundResponse.fromJson(data['data']);
    } catch (e) {
      print('❌ Error recording refund: $e');
      rethrow;
    }
  }

  /// Apply credit to future invoice
  static Future<CreditApplicationResponse> applyCredit(
    String creditNoteId,
    Map<String, dynamic> applicationData,
  ) async {
    try {
      print('📤 POST: $_baseEndpoint/$creditNoteId/apply');
      print('📦 Application: ${json.encode(applicationData)}');

      final data = await _api.post('$_baseEndpoint/$creditNoteId/apply', body: applicationData);

      print('✅ Credit applied to ${applicationData['invoiceNumber']}');

      return CreditApplicationResponse.fromJson(data['data']);
    } catch (e) {
      print('❌ Error applying credit: $e');
      rethrow;
    }
  }

  /// Download credit note PDF
  static Future<String> downloadPDF(String creditNoteId) async {
    try {
      print('📤 GET: $_baseEndpoint/$creditNoteId/download-url');

      final data = await _api.get('$_baseEndpoint/$creditNoteId/download-url');

      final url = data['downloadUrl'];

      print('✅ PDF URL: $url');

      return url;
    } catch (e) {
      print('❌ Error getting PDF URL: $e');
      rethrow;
    }
  }

  /// Delete credit note (only drafts)
  static Future<void> deleteCreditNote(String creditNoteId) async {
    try {
      print('📤 DELETE: $_baseEndpoint/$creditNoteId');

      await _api.delete('$_baseEndpoint/$creditNoteId');

      print('✅ Credit note deleted');
    } catch (e) {
      print('❌ Error deleting credit note: $e');
      rethrow;
    }
  }

  // ============================================================================
  // IMPORT/EXPORT OPERATIONS
  // ============================================================================

  /// Download CSV import template
  static Future<String> downloadImportTemplate() async {
    try {
      print('📥 Downloading import template...');
 
      // ✅ FIXED: Use _api.get() so auth token is sent in headers
      // Then get a short-lived signed URL from the response — same pattern as downloadPDF()
      final data = await _api.get('$_baseEndpoint/template/download');
 
      // Backend should return { "downloadUrl": "..." } or { "url": "..." }
      final url = data['downloadUrl'] ?? data['url'] ?? data['data'];
 
      print('✅ Template URL: $url');
 
      return url;
    } catch (e) {
      print('❌ Error downloading template: $e');
      rethrow;
    }
  }

  /// Import credit notes from CSV file
  static Future<ImportResult> importCreditNotes(PlatformFile file) async {
    try {
      print('📤 Starting CSV import...');

      final baseUrl = _api.baseUrl;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl$_baseEndpoint/import'),
      );

      // Add authentication headers
      final headers = await _api.getHeaders();
      request.headers.addAll(headers);

      // Add file
      if (file.bytes != null) {
        // Web
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );
      } else if (file.path != null) {
        // Mobile/Desktop
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            file.path!,
            filename: file.name,
          ),
        );
      } else {
        throw Exception('File data not available');
      }

      print('📡 Sending file to server...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ Import completed: ${data['successCount']} successful, ${data['errorCount']} failed');

        return ImportResult.fromJson(data);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to import credit notes');
      }
    } catch (e) {
      print('❌ Import error: $e');
      rethrow;
    }
  }

  /// Export credit notes to CSV
  static Future<String> exportCreditNotes({
    String? status,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      print('📤 Exporting credit notes...');

      final queryParams = <String, String>{};

      if (status != null) queryParams['status'] = status;
      if (customerId != null) queryParams['customerId'] = customerId;
      if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();

      final url = Uri.parse('${_api.baseUrl}$_baseEndpoint/export').replace(
        queryParameters: queryParams,
      );

      print('✅ Export URL: $url');

      return url.toString();
    } catch (e) {
      print('❌ Error exporting: $e');
      rethrow;
    }
  }
}

// ============================================================================
// MODELS - CREDIT NOTE SPECIFIC ONLY
// ============================================================================
// Note: Address, BillingCustomer, Pagination are imported from invoice_service.dart

/// Credit Note Model
class CreditNote {
  final String id;
  final String creditNoteNumber;
  final String customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final Address? billingAddress;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? referenceNumber;
  final DateTime creditNoteDate;
  final String reason;
  final String? reasonDescription;
  final List<CreditNoteItem> items;
  final String? customerNotes;
  final String? internalNotes;
  final double subTotal;
  final double tdsRate;
  final double tdsAmount;
  final double tcsRate;
  final double tcsAmount;
  final double gstRate;
  final double cgst;
  final double sgst;
  final double igst;
  final double totalAmount;
  final String status;
  final double creditBalance;
  final double creditUsed;
  final List<Refund> refunds;
  final List<CreditApplication> creditApplications;
  final DateTime createdAt;
  final DateTime updatedAt;

  CreditNote({
    required this.id,
    required this.creditNoteNumber,
    required this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.billingAddress,
    this.invoiceId,
    this.invoiceNumber,
    this.referenceNumber,
    required this.creditNoteDate,
    required this.reason,
    this.reasonDescription,
    required this.items,
    this.customerNotes,
    this.internalNotes,
    required this.subTotal,
    required this.tdsRate,
    required this.tdsAmount,
    required this.tcsRate,
    required this.tcsAmount,
    required this.gstRate,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.totalAmount,
    required this.status,
    required this.creditBalance,
    required this.creditUsed,
    required this.refunds,
    required this.creditApplications,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CreditNote.fromJson(Map<String, dynamic> json) {
    return CreditNote(
      id: json['_id'] ?? json['id'],
      creditNoteNumber: json['creditNoteNumber'],
      customerId: json['customerId'],
      customerName: json['customerName'],
      customerEmail: json['customerEmail'],
      customerPhone: json['customerPhone'],
      billingAddress: json['billingAddress'] != null
          ? Address.fromJson(json['billingAddress'])
          : null,
      invoiceId: json['invoiceId'],
      invoiceNumber: json['invoiceNumber'],
      referenceNumber: json['referenceNumber'],
      creditNoteDate: DateTime.parse(json['creditNoteDate']),
      reason: json['reason'],
      reasonDescription: json['reasonDescription'],
      items: (json['items'] as List)
          .map((item) => CreditNoteItem.fromJson(item))
          .toList(),
      customerNotes: json['customerNotes'],
      internalNotes: json['internalNotes'],
      subTotal: (json['subTotal'] ?? 0).toDouble(),
      tdsRate: (json['tdsRate'] ?? 0).toDouble(),
      tdsAmount: (json['tdsAmount'] ?? 0).toDouble(),
      tcsRate: (json['tcsRate'] ?? 0).toDouble(),
      tcsAmount: (json['tcsAmount'] ?? 0).toDouble(),
      gstRate: (json['gstRate'] ?? 18).toDouble(),
      cgst: (json['cgst'] ?? 0).toDouble(),
      sgst: (json['sgst'] ?? 0).toDouble(),
      igst: (json['igst'] ?? 0).toDouble(),
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
      status: json['status'],
      creditBalance: (json['creditBalance'] ?? 0).toDouble(),
      creditUsed: (json['creditUsed'] ?? 0).toDouble(),
      refunds: (json['refunds'] as List?)
              ?.map((refund) => Refund.fromJson(refund))
              .toList() ??
          [],
      creditApplications: (json['creditApplications'] as List?)
              ?.map((app) => CreditApplication.fromJson(app))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

/// Credit Note Item Model
class CreditNoteItem {
  final String itemDetails;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  CreditNoteItem({
    required this.itemDetails,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.discountType,
    required this.amount,
  });

  factory CreditNoteItem.fromJson(Map<String, dynamic> json) {
    return CreditNoteItem(
      itemDetails: json['itemDetails'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      rate: (json['rate'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      discountType: json['discountType'] ?? 'percentage',
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemDetails': itemDetails,
      'quantity': quantity,
      'rate': rate,
      'discount': discount,
      'discountType': discountType,
      'amount': amount,
    };
  }
}

/// Refund Model
class Refund {
  final String refundId;
  final double amount;
  final DateTime refundDate;
  final String refundMethod;
  final String? referenceNumber;
  final String? notes;
  final DateTime recordedAt;

  Refund({
    required this.refundId,
    required this.amount,
    required this.refundDate,
    required this.refundMethod,
    this.referenceNumber,
    this.notes,
    required this.recordedAt,
  });

  factory Refund.fromJson(Map<String, dynamic> json) {
    return Refund(
      refundId: json['refundId'],
      amount: (json['amount'] ?? 0).toDouble(),
      refundDate: DateTime.parse(json['refundDate']),
      refundMethod: json['refundMethod'],
      referenceNumber: json['referenceNumber'],
      notes: json['notes'],
      recordedAt: DateTime.parse(json['recordedAt']),
    );
  }
}

/// Credit Application Model
class CreditApplication {
  final String? invoiceId;
  final String invoiceNumber;
  final double amount;
  final DateTime appliedDate;
  final String appliedBy;

  CreditApplication({
    this.invoiceId,
    required this.invoiceNumber,
    required this.amount,
    required this.appliedDate,
    required this.appliedBy,
  });

  factory CreditApplication.fromJson(Map<String, dynamic> json) {
    return CreditApplication(
      invoiceId: json['invoiceId'],
      invoiceNumber: json['invoiceNumber'],
      amount: (json['amount'] ?? 0).toDouble(),
      appliedDate: DateTime.parse(json['appliedDate']),
      appliedBy: json['appliedBy'],
    );
  }
}

/// Credit Note List Response
class CreditNoteListResponse {
  final List<CreditNote> creditNotes;
  final Pagination pagination;

  CreditNoteListResponse({
    required this.creditNotes,
    required this.pagination,
  });

  factory CreditNoteListResponse.fromJson(Map<String, dynamic> json) {
    return CreditNoteListResponse(
      creditNotes: (json['data'] as List)
          .map((creditNote) => CreditNote.fromJson(creditNote))
          .toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

/// Credit Note Statistics
class CreditNoteStats {
  final int totalCreditNotes;
  final double totalCreditAmount;
  final double totalCreditBalance;
  final double totalCreditUsed;
  final Map<String, StatusStats> byStatus;

  CreditNoteStats({
    required this.totalCreditNotes,
    required this.totalCreditAmount,
    required this.totalCreditBalance,
    required this.totalCreditUsed,
    required this.byStatus,
  });

  factory CreditNoteStats.fromJson(Map<String, dynamic> json) {
    final byStatusMap = <String, StatusStats>{};

    if (json['byStatus'] != null) {
      (json['byStatus'] as Map<String, dynamic>).forEach((key, value) {
        byStatusMap[key] = StatusStats.fromJson(value);
      });
    }

    return CreditNoteStats(
      totalCreditNotes: json['totalCreditNotes'] ?? 0,
      totalCreditAmount: (json['totalCreditAmount'] ?? 0).toDouble(),
      totalCreditBalance: (json['totalCreditBalance'] ?? 0).toDouble(),
      totalCreditUsed: (json['totalCreditUsed'] ?? 0).toDouble(),
      byStatus: byStatusMap,
    );
  }
}

/// Status Statistics
class StatusStats {
  final int count;
  final double amount;

  StatusStats({
    required this.count,
    required this.amount,
  });

  factory StatusStats.fromJson(Map<String, dynamic> json) {
    return StatusStats(
      count: json['count'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }
}

/// Refund Response
class RefundResponse {
  final CreditNote creditNote;
  final Refund refund;

  RefundResponse({
    required this.creditNote,
    required this.refund,
  });

  factory RefundResponse.fromJson(Map<String, dynamic> json) {
    return RefundResponse(
      creditNote: CreditNote.fromJson(json['creditNote']),
      refund: Refund.fromJson(json['refund']),
    );
  }
}

/// Credit Application Response
class CreditApplicationResponse {
  final CreditNote creditNote;
  final CreditApplication application;

  CreditApplicationResponse({
    required this.creditNote,
    required this.application,
  });

  factory CreditApplicationResponse.fromJson(Map<String, dynamic> json) {
    return CreditApplicationResponse(
      creditNote: CreditNote.fromJson(json['creditNote']),
      application: CreditApplication.fromJson(json['application']),
    );
  }
}

/// Import Result
class ImportResult {
  final bool success;
  final String message;
  final int successCount;
  final int errorCount;
  final List<dynamic> results;
  final List<dynamic> errors;

  ImportResult({
    required this.success,
    required this.message,
    required this.successCount,
    required this.errorCount,
    required this.results,
    required this.errors,
  });

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      success: json['success'] ?? true,
      message: json['message'] ?? '',
      successCount: json['successCount'] ?? 0,
      errorCount: json['errorCount'] ?? 0,
      results: json['results'] ?? [],
      errors: json['errors'] ?? [],
    );
  }
}