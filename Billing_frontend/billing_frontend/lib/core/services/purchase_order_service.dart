// ============================================================================
// PURCHASE ORDER SERVICE - Complete with all endpoints
// ============================================================================
// File: lib/core/services/purchase_order_service.dart
// Features: Full CRUD, Send, PDF, Bulk Import, Convert to Bill
// Reference: invoice_service.dart pattern
// ============================================================================

import 'dart:convert';
import '../../core/services/api_service.dart';

class PurchaseOrderService {
  static final ApiService _api = ApiService();

  static const String _baseEndpoint = '/api/finance/purchase-orders';

  // ============================================================================
  // PURCHASE ORDER CRUD
  // ============================================================================

  /// Get all purchase orders with optional filters
  static Future<PurchaseOrderListResponse> getPurchaseOrders({
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (status != null) queryParams['status'] = status;
      if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      print('📤 GET: $_baseEndpoint with filters: $queryParams');

      final data = await _api.get(_baseEndpoint, queryParams: queryParams);

      print('✅ Purchase orders fetched: ${data['data'].length}');

      return PurchaseOrderListResponse.fromJson(data);
    } catch (e) {
      print('❌ Error fetching purchase orders: $e');
      rethrow;
    }
  }

  /// Get purchase order statistics
  static Future<PurchaseOrderStats> getStats() async {
    try {
      print('📤 GET: $_baseEndpoint/stats');
      final data = await _api.get('$_baseEndpoint/stats');
      print('✅ Stats fetched');
      return PurchaseOrderStats.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching stats: $e');
      rethrow;
    }
  }

  /// Get single purchase order by ID
  static Future<PurchaseOrder> getPurchaseOrder(String purchaseOrderId) async {
    try {
      print('📤 GET: $_baseEndpoint/$purchaseOrderId');
      final data = await _api.get('$_baseEndpoint/$purchaseOrderId');
      print('✅ Purchase order fetched: ${data['data']['purchaseOrderNumber']}');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching purchase order: $e');
      rethrow;
    }
  }

  /// Create new purchase order
  static Future<PurchaseOrder> createPurchaseOrder(
      Map<String, dynamic> purchaseOrderData) async {
    try {
      print('📤 POST: $_baseEndpoint');
      print('📦 Data: ${json.encode(purchaseOrderData)}');
      final data =
          await _api.post(_baseEndpoint, body: purchaseOrderData);
      print('✅ Purchase order created: ${data['data']['purchaseOrderNumber']}');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating purchase order: $e');
      rethrow;
    }
  }

  /// Update existing purchase order
  static Future<PurchaseOrder> updatePurchaseOrder(
      String purchaseOrderId, Map<String, dynamic> purchaseOrderData) async {
    try {
      print('📤 PUT: $_baseEndpoint/$purchaseOrderId');
      final data = await _api.put('$_baseEndpoint/$purchaseOrderId',
          body: purchaseOrderData);
      print('✅ Purchase order updated: ${data['data']['purchaseOrderNumber']}');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error updating purchase order: $e');
      rethrow;
    }
  }

  /// Send purchase order via email to vendor
  static Future<PurchaseOrder> sendPurchaseOrder(
      String purchaseOrderId) async {
    try {
      print('📤 POST: $_baseEndpoint/$purchaseOrderId/send');
      final data =
          await _api.post('$_baseEndpoint/$purchaseOrderId/send');
      print(
          '✅ Purchase order sent: ${data['data']['purchaseOrderNumber']}');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error sending purchase order: $e');
      rethrow;
    }
  }

  /// Mark purchase order as issued/confirmed
  static Future<PurchaseOrder> issuePurchaseOrder(
      String purchaseOrderId) async {
    try {
      print('📤 POST: $_baseEndpoint/$purchaseOrderId/issue');
      final data =
          await _api.post('$_baseEndpoint/$purchaseOrderId/issue');
      print('✅ Purchase order issued');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error issuing purchase order: $e');
      rethrow;
    }
  }

  /// Record purchase receive for a purchase order
  static Future<PurchaseOrder> recordReceive(
      String purchaseOrderId, Map<String, dynamic> receiveData) async {
    try {
      print('📤 POST: $_baseEndpoint/$purchaseOrderId/receive');
      final data = await _api.post(
          '$_baseEndpoint/$purchaseOrderId/receive',
          body: receiveData);
      print('✅ Purchase receive recorded');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error recording receive: $e');
      rethrow;
    }
  }

  /// Convert purchase order to bill
  static Future<Map<String, dynamic>> convertToBill(
      String purchaseOrderId) async {
    try {
      print('📤 POST: $_baseEndpoint/$purchaseOrderId/convert-to-bill');
      final data = await _api
          .post('$_baseEndpoint/$purchaseOrderId/convert-to-bill');
      print('✅ Purchase order converted to bill');
      return data;
    } catch (e) {
      print('❌ Error converting to bill: $e');
      rethrow;
    }
  }

  /// Cancel a purchase order
  static Future<PurchaseOrder> cancelPurchaseOrder(
      String purchaseOrderId) async {
    try {
      print('📤 POST: $_baseEndpoint/$purchaseOrderId/cancel');
      final data =
          await _api.post('$_baseEndpoint/$purchaseOrderId/cancel');
      print('✅ Purchase order cancelled');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error cancelling purchase order: $e');
      rethrow;
    }
  }

  /// Close a purchase order manually
  static Future<PurchaseOrder> closePurchaseOrder(
      String purchaseOrderId) async {
    try {
      print('📤 POST: $_baseEndpoint/$purchaseOrderId/close');
      final data =
          await _api.post('$_baseEndpoint/$purchaseOrderId/close');
      print('✅ Purchase order closed');
      return PurchaseOrder.fromJson(data['data']);
    } catch (e) {
      print('❌ Error closing purchase order: $e');
      rethrow;
    }
  }

  /// Download purchase order PDF - returns URL
  static Future<String> downloadPDF(String purchaseOrderId) async {
    try {
      print(
          '📤 GET: $_baseEndpoint/$purchaseOrderId/pdf (PDF download URL)');
      final url = '${_api.baseUrl}$_baseEndpoint/$purchaseOrderId/pdf';
      print('✅ PDF URL: $url');
      return url;
    } catch (e) {
      print('❌ Error getting PDF URL: $e');
      rethrow;
    }
  }

  /// Delete purchase order (only drafts)
  static Future<void> deletePurchaseOrder(String purchaseOrderId) async {
    try {
      print('📤 DELETE: $_baseEndpoint/$purchaseOrderId');
      await _api.delete('$_baseEndpoint/$purchaseOrderId');
      print('✅ Purchase order deleted');
    } catch (e) {
      print('❌ Error deleting purchase order: $e');
      rethrow;
    }
  }

  /// Bulk import purchase orders
  static Future<Map<String, dynamic>> bulkImportPurchaseOrders(
      List<Map<String, dynamic>> purchaseOrders) async {
    try {
      print(
          '📤 POST: $_baseEndpoint/bulk-import (${purchaseOrders.length} records)');
      final data = await _api.post('$_baseEndpoint/bulk-import',
          body: {'purchaseOrders': purchaseOrders});
      print('✅ Bulk import completed');
      return data;
    } catch (e) {
      print('❌ Error bulk importing: $e');
      rethrow;
    }
  }

  // ============================================================================
  // VENDOR MANAGEMENT
  // ============================================================================

  /// Get all vendors for PO creation
  static Future<VendorListResponse> getVendors({
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      print('📤 GET: /api/finance/vendors');
      final data =
          await _api.get('/api/finance/vendors', queryParams: queryParams);
      print(
          '✅ Vendors fetched: ${data['data']?['vendors']?.length ?? 0}');
      return VendorListResponse.fromJson(data);
    } catch (e) {
      print('❌ Error fetching vendors: $e');
      rethrow;
    }
  }

  /// Create new vendor
  static Future<Vendor> createVendor(
      Map<String, dynamic> vendorData) async {
    try {
      print('📤 POST: /api/finance/vendors');
      final data = await _api.post('/api/finance/vendors', body: vendorData);
      print('✅ Vendor created: ${data['data']['vendorName']}');
      return Vendor.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating vendor: $e');
      rethrow;
    }
  }
}

// ============================================================================
// PURCHASE ORDER MODEL
// ============================================================================

class PurchaseOrder {
  final String id;
  final String purchaseOrderNumber;
  final String vendorId;
  final String vendorName;
  final String? vendorEmail;
  final String? vendorPhone;
  final String? referenceNumber;
  final DateTime purchaseOrderDate;
  final DateTime? expectedDeliveryDate;
  final String paymentTerms;
  final String? deliveryAddress;
  final String? shipmentPreference;
  final String? subject;
  final String? salesperson;
  final List<PurchaseOrderItem> items;
  final String? vendorNotes;
  final String? termsAndConditions;
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
  final String? receiveStatus;
  final String? billingStatus;
  final List<PurchaseReceive> receives;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchaseOrder({
    required this.id,
    required this.purchaseOrderNumber,
    required this.vendorId,
    required this.vendorName,
    this.vendorEmail,
    this.vendorPhone,
    this.referenceNumber,
    required this.purchaseOrderDate,
    this.expectedDeliveryDate,
    required this.paymentTerms,
    this.deliveryAddress,
    this.shipmentPreference,
    this.subject,
    this.salesperson,
    required this.items,
    this.vendorNotes,
    this.termsAndConditions,
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
    this.receiveStatus,
    this.billingStatus,
    required this.receives,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: json['_id'] ?? json['id'] ?? '',
      purchaseOrderNumber: json['purchaseOrderNumber'] ?? '',
      vendorId: json['vendorId']?.toString() ?? '',
      vendorName: json['vendorName'] ?? '',
      vendorEmail: json['vendorEmail'],
      vendorPhone: json['vendorPhone'],
      referenceNumber: json['referenceNumber'],
      purchaseOrderDate: json['purchaseOrderDate'] != null
          ? DateTime.parse(json['purchaseOrderDate'])
          : DateTime.now(),
      expectedDeliveryDate: json['expectedDeliveryDate'] != null
          ? DateTime.parse(json['expectedDeliveryDate'])
          : null,
      paymentTerms: json['paymentTerms'] ?? 'Net 30',
      deliveryAddress: json['deliveryAddress'],
      shipmentPreference: json['shipmentPreference'],
      subject: json['subject'],
      salesperson: json['salesperson'],
      items: (json['items'] as List? ?? [])
          .map((item) => PurchaseOrderItem.fromJson(item))
          .toList(),
      vendorNotes: json['vendorNotes'],
      termsAndConditions: json['termsAndConditions'],
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
      status: json['status'] ?? 'DRAFT',
      receiveStatus: json['receiveStatus'],
      billingStatus: json['billingStatus'],
      receives: (json['receives'] as List? ?? [])
          .map((r) => PurchaseReceive.fromJson(r))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }
}

// ============================================================================
// PURCHASE ORDER ITEM MODEL
// ============================================================================

class PurchaseOrderItem {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  PurchaseOrderItem({
    this.itemDetails = '',
    this.quantity = 0,
    this.rate = 0,
    this.discount = 0,
    this.discountType = 'percentage',
    this.amount = 0,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
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

// ============================================================================
// PURCHASE RECEIVE MODEL
// ============================================================================

class PurchaseReceive {
  final String receiveId;
  final DateTime receiveDate;
  final List<ReceivedItem> items;
  final String? notes;
  final DateTime recordedAt;

  PurchaseReceive({
    required this.receiveId,
    required this.receiveDate,
    required this.items,
    this.notes,
    required this.recordedAt,
  });

  factory PurchaseReceive.fromJson(Map<String, dynamic> json) {
    return PurchaseReceive(
      receiveId: json['receiveId']?.toString() ?? '',
      receiveDate: json['receiveDate'] != null
          ? DateTime.parse(json['receiveDate'])
          : DateTime.now(),
      items: (json['items'] as List? ?? [])
          .map((item) => ReceivedItem.fromJson(item))
          .toList(),
      notes: json['notes'],
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'])
          : DateTime.now(),
    );
  }
}

class ReceivedItem {
  final String itemDetails;
  final double quantityOrdered;
  final double quantityReceived;

  ReceivedItem({
    required this.itemDetails,
    required this.quantityOrdered,
    required this.quantityReceived,
  });

  factory ReceivedItem.fromJson(Map<String, dynamic> json) {
    return ReceivedItem(
      itemDetails: json['itemDetails'] ?? '',
      quantityOrdered: (json['quantityOrdered'] ?? 0).toDouble(),
      quantityReceived: (json['quantityReceived'] ?? 0).toDouble(),
    );
  }
}

// ============================================================================
// PURCHASE ORDER LIST RESPONSE
// ============================================================================

class PurchaseOrderListResponse {
  final List<PurchaseOrder> purchaseOrders;
  final Pagination pagination;

  PurchaseOrderListResponse({
    required this.purchaseOrders,
    required this.pagination,
  });

  factory PurchaseOrderListResponse.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List? ?? [];
    return PurchaseOrderListResponse(
      purchaseOrders:
          dataList.map((po) => PurchaseOrder.fromJson(po)).toList(),
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'])
          : Pagination(total: dataList.length, page: 1, limit: 20, pages: 1),
    );
  }
}

// ============================================================================
// PURCHASE ORDER STATS MODEL
// ============================================================================

class PurchaseOrderStats {
  final int totalPurchaseOrders;
  final int draftPurchaseOrders;
  final int issuedPurchaseOrders;
  final int receivedPurchaseOrders;
  final int billedPurchaseOrders;
  final double totalValue;

  PurchaseOrderStats({
    required this.totalPurchaseOrders,
    required this.draftPurchaseOrders,
    required this.issuedPurchaseOrders,
    required this.receivedPurchaseOrders,
    required this.billedPurchaseOrders,
    required this.totalValue,
  });

  factory PurchaseOrderStats.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderStats(
      totalPurchaseOrders: json['totalPurchaseOrders'] ?? 0,
      draftPurchaseOrders: json['draftPurchaseOrders'] ?? 0,
      issuedPurchaseOrders: json['issuedPurchaseOrders'] ?? 0,
      receivedPurchaseOrders: json['receivedPurchaseOrders'] ?? 0,
      billedPurchaseOrders: json['billedPurchaseOrders'] ?? 0,
      totalValue: (json['totalValue'] ?? 0).toDouble(),
    );
  }
}

// ============================================================================
// VENDOR MODEL
// ============================================================================

class Vendor {
  final String id;
  final String vendorName;
  final String vendorEmail;
  final String vendorPhone;
  final String? companyName;
  final String? gstNumber;
  final String? vendorStatus;

  Vendor({
    required this.id,
    required this.vendorName,
    required this.vendorEmail,
    required this.vendorPhone,
    this.companyName,
    this.gstNumber,
    this.vendorStatus,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    return Vendor(
      id: json['_id'] ?? json['id'] ?? '',
      vendorName: json['vendorName'] ?? json['vendorDisplayName'] ?? '',
      vendorEmail: json['email'] ?? json['vendorEmail'] ?? json['primaryEmail'] ?? '',
      vendorPhone: json['phoneNumber'] ?? json['vendorPhone'] ?? json['primaryPhone'] ?? '',
      companyName: json['companyName'],
      gstNumber: json['gstNumber'],
      vendorStatus: json['status'] ?? json['vendorStatus'] ?? 'Active',
    );
  }
}

class VendorListResponse {
  final List<Vendor> vendors;
  final Pagination pagination;

  VendorListResponse({
    required this.vendors,
    required this.pagination,
  });

  factory VendorListResponse.fromJson(Map<String, dynamic> json) {
    final vendorsData =
        json['data']?['vendors'] ?? json['data'] ?? [];
    final paginationData = json['data']?['pagination'] ??
        json['pagination'] ??
        {
          'total': vendorsData.length,
          'page': 1,
          'limit': 50,
          'pages': 1,
        };

    return VendorListResponse(
      vendors: (vendorsData as List)
          .map((v) => Vendor.fromJson(v))
          .toList(),
      pagination: Pagination.fromJson(paginationData),
    );
  }
}

// ============================================================================
// SHARED PAGINATION MODEL
// ============================================================================

class Pagination {
  final int total;
  final int page;
  final int limit;
  final int pages;

  Pagination({
    required this.total,
    required this.page,
    required this.limit,
    required this.pages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      total: json['totalCount'] ?? json['total'] ?? 0,
      page: json['currentPage'] ?? json['page'] ?? 1,
      limit: json['limit'] ?? 20,
      pages: json['totalPages'] ?? json['pages'] ?? 1,
    );
  }
}