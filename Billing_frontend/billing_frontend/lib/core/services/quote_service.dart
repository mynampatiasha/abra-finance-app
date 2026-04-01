// ============================================================================
// QUOTE SERVICE - Frontend Service Layer WITH BULK IMPORT
// ============================================================================
// File: lib/core/services/quote_service.dart
// Connects Flutter frontend with Node.js backend for quote operations
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

class Quote {
  final String id;
  final String quoteNumber;
  final String? referenceNumber;
  final String customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final DateTime quoteDate;
  final DateTime expiryDate;
  final String? salesperson;
  final String? projectName;
  final String? subject;
  final List<QuoteItem> items;
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
  final String? customerNotes;
  final String? termsAndConditions;
  final String status;
  final DateTime? sentDate;
  final DateTime? acceptedDate;
  final DateTime? declinedDate;
  final String? declineReason;
  final DateTime? convertedDate;
  final bool? convertedToInvoice;
  final bool? convertedToSalesOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  Quote({
    required this.id,
    required this.quoteNumber,
    this.referenceNumber,
    required this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    required this.quoteDate,
    required this.expiryDate,
    this.salesperson,
    this.projectName,
    this.subject,
    required this.items,
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
    this.customerNotes,
    this.termsAndConditions,
    required this.status,
    this.sentDate,
    this.acceptedDate,
    this.declinedDate,
    this.declineReason,
    this.convertedDate,
    this.convertedToInvoice,
    this.convertedToSalesOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      id: json['_id'] ?? json['id'] ?? '',
      quoteNumber: json['quoteNumber'] ?? '',
      referenceNumber: json['referenceNumber'],
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'] ?? '',
      customerEmail: json['customerEmail'],
      customerPhone: json['customerPhone'],
      quoteDate: DateTime.parse(json['quoteDate']),
      expiryDate: DateTime.parse(json['expiryDate']),
      salesperson: json['salesperson'],
      projectName: json['projectName'],
      subject: json['subject'],
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => QuoteItem.fromJson(item))
              .toList() ??
          [],
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
      customerNotes: json['customerNotes'],
      termsAndConditions: json['termsAndConditions'],
      status: json['status'] ?? 'DRAFT',
      sentDate: json['sentDate'] != null ? DateTime.parse(json['sentDate']) : null,
      acceptedDate: json['acceptedDate'] != null ? DateTime.parse(json['acceptedDate']) : null,
      declinedDate: json['declinedDate'] != null ? DateTime.parse(json['declinedDate']) : null,
      declineReason: json['declineReason'],
      convertedDate: json['convertedDate'] != null ? DateTime.parse(json['convertedDate']) : null,
      convertedToInvoice: json['convertedToInvoice'],
      convertedToSalesOrder: json['convertedToSalesOrder'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'quoteNumber': quoteNumber,
      'referenceNumber': referenceNumber,
      'customerId': customerId,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'customerPhone': customerPhone,
      'quoteDate': quoteDate.toIso8601String(),
      'expiryDate': expiryDate.toIso8601String(),
      'salesperson': salesperson,
      'projectName': projectName,
      'subject': subject,
      'items': items.map((item) => item.toJson()).toList(),
      'subTotal': subTotal,
      'tdsRate': tdsRate,
      'tdsAmount': tdsAmount,
      'tcsRate': tcsRate,
      'tcsAmount': tcsAmount,
      'gstRate': gstRate,
      'cgst': cgst,
      'sgst': sgst,
      'igst': igst,
      'totalAmount': totalAmount,
      'customerNotes': customerNotes,
      'termsAndConditions': termsAndConditions,
      'status': status,
    };
  }
}

class QuoteItem {
  final String itemDetails;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  QuoteItem({
    required this.itemDetails,
    required this.quantity,
    required this.rate,
    this.discount = 0,
    this.discountType = 'percentage',
    required this.amount,
  });

  factory QuoteItem.fromJson(Map<String, dynamic> json) {
    return QuoteItem(
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

class QuoteStats {
  final int totalQuotes;
  final int draftQuotes;
  final int sentQuotes;
  final int acceptedQuotes;
  final int declinedQuotes;
  final int expiredQuotes;
  final int convertedQuotes;
  final double totalValue;

  QuoteStats({
    required this.totalQuotes,
    required this.draftQuotes,
    required this.sentQuotes,
    required this.acceptedQuotes,
    required this.declinedQuotes,
    required this.expiredQuotes,
    required this.convertedQuotes,
    required this.totalValue,
  });

  factory QuoteStats.fromJson(Map<String, dynamic> json) {
    return QuoteStats(
      totalQuotes: json['totalQuotes'] ?? 0,
      draftQuotes: json['draftQuotes'] ?? 0,
      sentQuotes: json['sentQuotes'] ?? 0,
      acceptedQuotes: json['acceptedQuotes'] ?? 0,
      declinedQuotes: json['declinedQuotes'] ?? 0,
      expiredQuotes: json['expiredQuotes'] ?? 0,
      convertedQuotes: json['convertedQuotes'] ?? 0,
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}

class QuoteListResponse {
  final List<Quote> quotes;
  final QuotePagination pagination;

  QuoteListResponse({
    required this.quotes,
    required this.pagination,
  });

  factory QuoteListResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    return QuoteListResponse(
      quotes: (data['quotes'] as List<dynamic>?)
              ?.map((quote) => Quote.fromJson(quote))
              .toList() ??
          [],
      pagination: QuotePagination.fromJson(data['pagination'] ?? {}),
    );
  }
}

class QuotePagination {
  final int page;
  final int limit;
  final int total;
  final int pages;

  QuotePagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory QuotePagination.fromJson(Map<String, dynamic> json) {
    return QuotePagination(
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 20,
      total: json['total'] ?? 0,
      pages: json['pages'] ?? 1,
    );
  }
}

// ============================================================================
// QUOTE SERVICE
// ============================================================================

class QuoteService {
  static final ApiService _apiService = ApiService();

  // Get all quotes with filtering and pagination
  static Future<QuoteListResponse> getQuotes({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      debugPrint('🔍 QuoteService: Fetching quotes...');
      debugPrint('   Status: $status');
      debugPrint('   Page: $page, Limit: $limit');
      debugPrint('   Search: $search');
      debugPrint('   Date Range: $fromDate to $toDate');

      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (status != null && status != 'All') {
        queryParams['status'] = status;
      }

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      if (fromDate != null) {
        queryParams['fromDate'] = fromDate.toIso8601String();
      }

      if (toDate != null) {
        queryParams['toDate'] = toDate.toIso8601String();
      }

      debugPrint('📡 Making API request to /api/quotes');
      final response = await _apiService.get('/api/finance/quotes', queryParams: queryParams);

      debugPrint('✅ QuoteService: Successfully fetched quotes');
      debugPrint('   Response keys: ${response.keys.toList()}');

      return QuoteListResponse.fromJson(response);
    } catch (e) {
      debugPrint('❌ QuoteService: Error fetching quotes: $e');
      rethrow;
    }
  }

  // Get quote statistics
  static Future<QuoteStats> getStats() async {
    try {
      debugPrint('📊 QuoteService: Fetching quote statistics...');

      final response = await _apiService.get('/api/finance/quotes/stats');

      debugPrint('✅ QuoteService: Successfully fetched stats');

      final data = response['data'] ?? response;
      return QuoteStats.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error fetching stats: $e');
      rethrow;
    }
  }

  // Get single quote by ID
  static Future<Quote> getQuote(String quoteId) async {
    try {
      debugPrint('🔍 QuoteService: Fetching quote $quoteId...');

      final response = await _apiService.get('/api/finance/quotes/$quoteId');

      debugPrint('✅ QuoteService: Successfully fetched quote');

      final data = response['data'] ?? response;
      return Quote.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error fetching quote: $e');
      rethrow;
    }
  }

  // Create new quote
  static Future<Quote> createQuote(Map<String, dynamic> quoteData) async {
    try {
      debugPrint('➕ QuoteService: Creating new quote...');
      debugPrint('   Customer: ${quoteData['customerName']}');
      debugPrint('   Items: ${(quoteData['items'] as List).length}');

      final response = await _apiService.post('/api/finance/quotes', body: quoteData);

      debugPrint('✅ QuoteService: Successfully created quote');

      final data = response['data'] ?? response;
      return Quote.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error creating quote: $e');
      rethrow;
    }
  }

  // Update existing quote
  static Future<Quote> updateQuote(String quoteId, Map<String, dynamic> quoteData) async {
    try {
      debugPrint('✏️ QuoteService: Updating quote $quoteId...');

      final response = await _apiService.put('/api/finance/quotes/$quoteId', body: quoteData);

      debugPrint('✅ QuoteService: Successfully updated quote');

      final data = response['data'] ?? response;
      return Quote.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error updating quote: $e');
      rethrow;
    }
  }

  // Delete quote (only drafts)
  static Future<void> deleteQuote(String quoteId) async {
    try {
      debugPrint('🗑️ QuoteService: Deleting quote $quoteId...');

      await _apiService.delete('/api/finance/quotes/$quoteId');

      debugPrint('✅ QuoteService: Successfully deleted quote');
    } catch (e) {
      debugPrint('❌ QuoteService: Error deleting quote: $e');
      rethrow;
    }
  }

  // Send quote to customer
  static Future<Quote> sendQuote(String quoteId) async {
    try {
      debugPrint('📧 QuoteService: Sending quote $quoteId...');

      final response = await _apiService.post('/api/finance/quotes/$quoteId/send');

      debugPrint('✅ QuoteService: Successfully sent quote');

      final data = response['data'] ?? response;
      return Quote.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error sending quote: $e');
      rethrow;
    }
  }

  // Download quote PDF
static Future<String> downloadPDF(String quoteId) async {
  try {
    debugPrint('📄 QuoteService: Getting PDF download URL for quote $quoteId...');

    final headers = await _apiService.getHeaders();
    final token = headers['Authorization']?.replaceFirst('Bearer ', '') ?? '';
    final url = '${_apiService.baseUrl}/api/finance/quotes/$quoteId/download?token=$token';

    debugPrint('✅ QuoteService: PDF URL generated: $url');
    return url;
  } catch (e) {
    debugPrint('❌ QuoteService: Error generating PDF URL: $e');
    rethrow;
  }
}

  // Accept quote
  static Future<Quote> acceptQuote(String quoteId) async {
    try {
      debugPrint('✅ QuoteService: Accepting quote $quoteId...');

      final response = await _apiService.post('/api/finance/quotes/$quoteId/accept');

      debugPrint('✅ QuoteService: Successfully accepted quote');

      final data = response['data'] ?? response;
      return Quote.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error accepting quote: $e');
      rethrow;
    }
  }

  // Decline quote
  static Future<Quote> declineQuote(String quoteId, String? reason) async {
    try {
      debugPrint('❌ QuoteService: Declining quote $quoteId...');

      final body = reason != null && reason.isNotEmpty ? {'declineReason': reason} : <String, dynamic>{};

      final response = await _apiService.post('/api/finance/quotes/$quoteId/decline', body: body);

      debugPrint('✅ QuoteService: Successfully declined quote');

      final data = response['data'] ?? response;
      return Quote.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error declining quote: $e');
      rethrow;
    }
  }

  // Clone/duplicate quote
  static Future<Quote> cloneQuote(String quoteId) async {
    try {
      debugPrint('📋 QuoteService: Cloning quote $quoteId...');

      final response = await _apiService.post('/api/finance/quotes/$quoteId/clone');

      debugPrint('✅ QuoteService: Successfully cloned quote');

      final data = response['data'] ?? response;
      return Quote.fromJson(data);
    } catch (e) {
      debugPrint('❌ QuoteService: Error cloning quote: $e');
      rethrow;
    }
  }

  // Convert quote to invoice
  static Future<Quote> convertToInvoice(String quoteId) async {
    try {
      debugPrint('🧾 QuoteService: Converting quote $quoteId to invoice...');

      final response = await _apiService.post('/api/finance/quotes/$quoteId/convert-to-invoice');

      debugPrint('✅ QuoteService: Successfully converted quote to invoice');

 final data = response['data'] ?? response;
  // Backend returns {quote, invoice} — extract quote
  final quoteData = data is Map && data.containsKey('quote') 
      ? data['quote'] 
      : data;
  return Quote.fromJson(quoteData);
    } catch (e) {
      debugPrint('❌ QuoteService: Error converting quote to invoice: $e');
      rethrow;
    }
  }

  // Convert quote to sales order
  static Future<Quote> convertToSalesOrder(String quoteId) async {
    try {
      debugPrint('📦 QuoteService: Converting quote $quoteId to sales order...');

      final response = await _apiService.post('/api/finance/quotes/$quoteId/convert-to-sales-order');

      debugPrint('✅ QuoteService: Successfully converted quote to sales order');

      final data = response['data'] ?? response;
      return Quote.fromJson(data['quote']);
    } catch (e) {
      debugPrint('❌ QuoteService: Error converting quote to sales order: $e');
      rethrow;
    }
  }

  // ============================================================================
  // 🆕 BULK IMPORT QUOTES
  // ============================================================================
  
  static Future<Map<String, dynamic>> bulkImportQuotes(List<Map<String, dynamic>> quotesData) async {
    try {
      debugPrint('📦 QuoteService: Starting bulk import of ${quotesData.length} quotes...');

      final response = await _apiService.post(
        '/api/finance/quotes/bulk-import',
        body: {'quotes': quotesData},
      );

      debugPrint('✅ QuoteService: Bulk import completed');
      debugPrint('   Success: ${response['data']['successCount']}');
      debugPrint('   Failed: ${response['data']['failedCount']}');

      return response;
    } catch (e) {
      debugPrint('❌ QuoteService: Error in bulk import: $e');
      rethrow;
    }
  }
}
