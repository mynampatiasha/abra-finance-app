// ============================================================================
// SALES ORDER SERVICE - Flutter API Integration
// ============================================================================
// File: lib/core/services/sales_order_service.dart
// Complete API integration for Sales Order management
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class SalesOrderService {
  static String get baseUrl => ApiConfig.baseUrl;
  
  // Get JWT token from SharedPreferences
  static Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      return null;
    }
  }
  
  // ============================================================================
  // GET ALL SALES ORDERS WITH FILTERS
  // ============================================================================
  
  static Future<SalesOrderListResponse> getSalesOrders({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final token = await _getToken();
      
      final queryParams = {
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
      
      final uri = Uri.parse('$baseUrl/api/finance/sales-orders').replace(queryParameters: queryParams);
      
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SalesOrderListResponse.fromJson(data['data']);
      } else {
        throw Exception('Failed to fetch sales orders: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching sales orders: $e');
    }
  }
  
  // ============================================================================
  // GET SALES ORDER STATISTICS
  // ============================================================================
  
  static Future<SalesOrderStats> getStats() async {
    try {
      final token = await _getToken();
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/finance/sales-orders/stats'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SalesOrderStats.fromJson(data['data']);
      } else {
        throw Exception('Failed to fetch stats: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching stats: $e');
    }
  }
  
  // ============================================================================
  // GET SINGLE SALES ORDER
  // ============================================================================
  
  static Future<SalesOrder> getSalesOrder(String id) async {
    try {
      final token = await _getToken();
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/finance/sales-orders/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SalesOrder.fromJson(data['data']);
      } else {
        throw Exception('Failed to fetch sales order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching sales order: $e');
    }
  }
  
  // ============================================================================
  // CREATE NEW SALES ORDER
  // ============================================================================
  
  static Future<SalesOrder> createSalesOrder(Map<String, dynamic> salesOrderData) async {
    try {
      final token = await _getToken();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/finance/sales-orders'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(salesOrderData),
      );
      
      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return SalesOrder.fromJson(data['data']);
      } else {
        throw Exception('Failed to create sales order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating sales order: $e');
    }
  }
  
  // ============================================================================
  // UPDATE SALES ORDER
  // ============================================================================
  
  static Future<SalesOrder> updateSalesOrder(String id, Map<String, dynamic> salesOrderData) async {
    try {
      final token = await _getToken();
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/finance/sales-orders/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(salesOrderData),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SalesOrder.fromJson(data['data']);
      } else {
        throw Exception('Failed to update sales order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating sales order: $e');
    }
  }
  
  // ============================================================================
  // DELETE SALES ORDER
  // ============================================================================
  
  static Future<void> deleteSalesOrder(String id) async {
    try {
      final token = await _getToken();
      
      final response = await http.delete(
        Uri.parse('$baseUrl/api/finance/sales-orders/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to delete sales order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting sales order: $e');
    }
  }
  
  // ============================================================================
  // SEND SALES ORDER VIA EMAIL
  // ============================================================================
  
  static Future<void> sendSalesOrder(String id) async {
    try {
      final token = await _getToken();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/finance/sales-orders/$id/send'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to send sales order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error sending sales order: $e');
    }
  }
  
  // ============================================================================
  // DOWNLOAD PDF
  // ============================================================================
  
  static Future<String> downloadPDF(String id) async {
    try {
      final token = await _getToken();
      
      return '$baseUrl/api/finance/sales-orders/$id/download?token=$token';
    } catch (e) {
      throw Exception('Error preparing PDF download: $e');
    }
  }
  
  // ============================================================================
  // CONFIRM SALES ORDER
  // ============================================================================
  
  static Future<void> confirmSalesOrder(String id) async {
    try {
      final token = await _getToken();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/finance/sales-orders/$id/confirm'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode != 200) {
        throw Exception('Failed to confirm sales order: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error confirming sales order: $e');
    }
  }
  
  // ============================================================================
  // CONVERT TO INVOICE
  // ============================================================================
  
  static Future<Map<String, dynamic>> convertToInvoice(String id) async {
    try {
      final token = await _getToken();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/finance/sales-orders/$id/convert-to-invoice'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        throw Exception('Failed to convert to invoice: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error converting to invoice: $e');
    }
  }
  
  // ============================================================================
  // BULK IMPORT SALES ORDERS
  // ============================================================================
  
  static Future<Map<String, dynamic>> bulkImportSalesOrders(List<Map<String, dynamic>> salesOrders) async {
    try {
      final token = await _getToken();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/finance/sales-orders/bulk-import'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'salesOrders': salesOrders,
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to import sales orders: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error importing sales orders: $e');
    }
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

class SalesOrder {
  final String id;
  final String salesOrderNumber;
  final String? referenceNumber;
  final String customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final DateTime salesOrderDate;
  final DateTime? expectedShipmentDate;
  final String paymentTerms;
  final String? deliveryMethod;
  final String? salesperson;
  final String? subject;
  final List<SalesOrderItem> items;
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
  final String? convertedFromQuoteNumber;
  final bool convertedToInvoice;
  final String? convertedToInvoiceNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  SalesOrder({
    required this.id,
    required this.salesOrderNumber,
    this.referenceNumber,
    required this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    required this.salesOrderDate,
    this.expectedShipmentDate,
    required this.paymentTerms,
    this.deliveryMethod,
    this.salesperson,
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
    this.convertedFromQuoteNumber,
    required this.convertedToInvoice,
    this.convertedToInvoiceNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SalesOrder.fromJson(Map<String, dynamic> json) {
    return SalesOrder(
      id: json['_id'],
      salesOrderNumber: json['salesOrderNumber'],
      referenceNumber: json['referenceNumber'],
      customerId: json['customerId'],
      customerName: json['customerName'],
      customerEmail: json['customerEmail'],
      customerPhone: json['customerPhone'],
      salesOrderDate: DateTime.parse(json['salesOrderDate']),
      expectedShipmentDate: json['expectedShipmentDate'] != null 
          ? DateTime.parse(json['expectedShipmentDate']) 
          : null,
      paymentTerms: json['paymentTerms'] ?? 'Net 30',
      deliveryMethod: json['deliveryMethod'],
      salesperson: json['salesperson'],
      subject: json['subject'],
      items: (json['items'] as List)
          .map((item) => SalesOrderItem.fromJson(item))
          .toList(),
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
      convertedFromQuoteNumber: json['convertedFromQuoteNumber'],
      convertedToInvoice: json['convertedToInvoice'] ?? false,
      convertedToInvoiceNumber: json['convertedToInvoiceNumber'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

class SalesOrderItem {
  final String itemDetails;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;
  final double quantityPacked;
  final double quantityShipped;
  final double quantityInvoiced;

  SalesOrderItem({
    required this.itemDetails,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.discountType,
    required this.amount,
    this.quantityPacked = 0,
    this.quantityShipped = 0,
    this.quantityInvoiced = 0,
  });

  factory SalesOrderItem.fromJson(Map<String, dynamic> json) {
    return SalesOrderItem(
      itemDetails: json['itemDetails'],
      quantity: (json['quantity'] ?? 0).toDouble(),
      rate: (json['rate'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      discountType: json['discountType'] ?? 'percentage',
      amount: (json['amount'] ?? 0).toDouble(),
      quantityPacked: (json['quantityPacked'] ?? 0).toDouble(),
      quantityShipped: (json['quantityShipped'] ?? 0).toDouble(),
      quantityInvoiced: (json['quantityInvoiced'] ?? 0).toDouble(),
    );
  }
}

class SalesOrderListResponse {
  final List<SalesOrder> salesOrders;
  final PaginationInfo pagination;

  SalesOrderListResponse({
    required this.salesOrders,
    required this.pagination,
  });

  factory SalesOrderListResponse.fromJson(Map<String, dynamic> json) {
    return SalesOrderListResponse(
      salesOrders: (json['salesOrders'] as List)
          .map((so) => SalesOrder.fromJson(so))
          .toList(),
      pagination: PaginationInfo.fromJson(json['pagination']),
    );
  }
}

class PaginationInfo {
  final int page;
  final int limit;
  final int total;
  final int pages;

  PaginationInfo({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory PaginationInfo.fromJson(Map<String, dynamic> json) {
    return PaginationInfo(
      page: json['page'],
      limit: json['limit'],
      total: json['total'],
      pages: json['pages'],
    );
  }
}

class SalesOrderStats {
  final int totalSalesOrders;
  final int draftSalesOrders;
  final int openSalesOrders;
  final int confirmedSalesOrders;
  final int shippedSalesOrders;
  final int invoicedSalesOrders;
  final double totalValue;

  SalesOrderStats({
    required this.totalSalesOrders,
    required this.draftSalesOrders,
    required this.openSalesOrders,
    required this.confirmedSalesOrders,
    required this.shippedSalesOrders,
    required this.invoicedSalesOrders,
    required this.totalValue,
  });

  factory SalesOrderStats.fromJson(Map<String, dynamic> json) {
    return SalesOrderStats(
      totalSalesOrders: json['totalSalesOrders'] ?? 0,
      draftSalesOrders: json['draftSalesOrders'] ?? 0,
      openSalesOrders: json['openSalesOrders'] ?? 0,
      confirmedSalesOrders: json['confirmedSalesOrders'] ?? 0,
      shippedSalesOrders: json['shippedSalesOrders'] ?? 0,
      invoicedSalesOrders: json['invoicedSalesOrders'] ?? 0,
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}
