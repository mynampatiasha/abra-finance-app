// ============================================================================
// DELIVERY CHALLAN SERVICE - FRONTEND TO BACKEND CONNECTION
// ============================================================================
// File: lib/core/services/delivery_challan_service.dart
// All API calls for delivery challan operations
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

// ============================================================================
// MODELS
// ============================================================================

class DeliveryChallan {
  final String id;
  final String challanNumber;
  final String customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final Address? deliveryAddress;
  final DateTime challanDate;
  final DateTime? expectedDeliveryDate;
  final DateTime? actualDeliveryDate;
  final String? referenceNumber;
  final String? orderNumber;
  final String purpose;
  final String transportMode;
  final String? vehicleNumber;
  final String? driverName;
  final String? driverPhone;
  final String? transporterName;
  final String? lrNumber;
  final List<ChallanItem> items;
  final String? customerNotes;
  final String? internalNotes;
  final String? termsAndConditions;
  final String status;
  final List<LinkedInvoice> linkedInvoices;
  final String? pdfPath;
  final DateTime? pdfGeneratedAt;
  final List<EmailRecord> emailsSent;
  final String createdBy;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  DeliveryChallan({
    required this.id,
    required this.challanNumber,
    required this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.deliveryAddress,
    required this.challanDate,
    this.expectedDeliveryDate,
    this.actualDeliveryDate,
    this.referenceNumber,
    this.orderNumber,
    required this.purpose,
    required this.transportMode,
    this.vehicleNumber,
    this.driverName,
    this.driverPhone,
    this.transporterName,
    this.lrNumber,
    required this.items,
    this.customerNotes,
    this.internalNotes,
    this.termsAndConditions,
    required this.status,
    required this.linkedInvoices,
    this.pdfPath,
    this.pdfGeneratedAt,
    required this.emailsSent,
    required this.createdBy,
    this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeliveryChallan.fromJson(Map<String, dynamic> json) {
    return DeliveryChallan(
      id: json['_id'] ?? '',
      challanNumber: json['challanNumber'] ?? '',
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'] ?? '',
      customerEmail: json['customerEmail'],
      customerPhone: json['customerPhone'],
      deliveryAddress: json['deliveryAddress'] != null
          ? Address.fromJson(json['deliveryAddress'])
          : null,
      challanDate: DateTime.parse(json['challanDate']),
      expectedDeliveryDate: json['expectedDeliveryDate'] != null
          ? DateTime.parse(json['expectedDeliveryDate'])
          : null,
      actualDeliveryDate: json['actualDeliveryDate'] != null
          ? DateTime.parse(json['actualDeliveryDate'])
          : null,
      referenceNumber: json['referenceNumber'],
      orderNumber: json['orderNumber'],
      purpose: json['purpose'] ?? 'Sales',
      transportMode: json['transportMode'] ?? 'Road',
      vehicleNumber: json['vehicleNumber'],
      driverName: json['driverName'],
      driverPhone: json['driverPhone'],
      transporterName: json['transporterName'],
      lrNumber: json['lrNumber'],
      items: (json['items'] as List?)
              ?.map((item) => ChallanItem.fromJson(item))
              .toList() ??
          [],
      customerNotes: json['customerNotes'],
      internalNotes: json['internalNotes'],
      termsAndConditions: json['termsAndConditions'],
      status: json['status'] ?? 'DRAFT',
      linkedInvoices: (json['linkedInvoices'] as List?)
              ?.map((invoice) => LinkedInvoice.fromJson(invoice))
              .toList() ??
          [],
      pdfPath: json['pdfPath'],
      pdfGeneratedAt: json['pdfGeneratedAt'] != null
          ? DateTime.parse(json['pdfGeneratedAt'])
          : null,
      emailsSent: (json['emailsSent'] as List?)
              ?.map((email) => EmailRecord.fromJson(email))
              .toList() ??
          [],
      createdBy: json['createdBy'] ?? 'system',
      updatedBy: json['updatedBy'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'challanNumber': challanNumber,
      'customerId': customerId,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'customerPhone': customerPhone,
      if (deliveryAddress != null) 'deliveryAddress': deliveryAddress!.toJson(),
      'challanDate': challanDate.toIso8601String(),
      if (expectedDeliveryDate != null)
        'expectedDeliveryDate': expectedDeliveryDate!.toIso8601String(),
      'referenceNumber': referenceNumber,
      'orderNumber': orderNumber,
      'purpose': purpose,
      'transportMode': transportMode,
      'vehicleNumber': vehicleNumber,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'transporterName': transporterName,
      'lrNumber': lrNumber,
      'items': items.map((item) => item.toJson()).toList(),
      'customerNotes': customerNotes,
      'internalNotes': internalNotes,
      'termsAndConditions': termsAndConditions,
      'status': status,
    };
  }
}

class Address {
  final String? street;
  final String? city;
  final String? state;
  final String? pincode;
  final String country;

  Address({
    this.street,
    this.city,
    this.state,
    this.pincode,
    this.country = 'India',
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      street: json['street'],
      city: json['city'],
      state: json['state'],
      pincode: json['pincode'],
      country: json['country'] ?? 'India',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'street': street,
      'city': city,
      'state': state,
      'pincode': pincode,
      'country': country,
    };
  }
}

class ChallanItem {
  final String? id;
  final String itemDetails;
  final double quantity;
  final String unit;
  final String? hsnCode;
  final String? notes;
  final double quantityDispatched;
  final double quantityDelivered;
  final double quantityInvoiced;
  final double quantityReturned;

  ChallanItem({
    this.id,
    required this.itemDetails,
    required this.quantity,
    this.unit = 'Pcs',
    this.hsnCode,
    this.notes,
    this.quantityDispatched = 0,
    this.quantityDelivered = 0,
    this.quantityInvoiced = 0,
    this.quantityReturned = 0,
  });

  factory ChallanItem.fromJson(Map<String, dynamic> json) {
    return ChallanItem(
      id: json['_id'],
      itemDetails: json['itemDetails'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      unit: json['unit'] ?? 'Pcs',
      hsnCode: json['hsnCode'],
      notes: json['notes'],
      quantityDispatched: (json['quantityDispatched'] ?? 0).toDouble(),
      quantityDelivered: (json['quantityDelivered'] ?? 0).toDouble(),
      quantityInvoiced: (json['quantityInvoiced'] ?? 0).toDouble(),
      quantityReturned: (json['quantityReturned'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemDetails': itemDetails,
      'quantity': quantity,
      'unit': unit,
      'hsnCode': hsnCode,
      'notes': notes,
    };
  }
}

class LinkedInvoice {
  final String invoiceId;
  final String invoiceNumber;
  final DateTime invoicedDate;
  final double amount;

  LinkedInvoice({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoicedDate,
    required this.amount,
  });

  factory LinkedInvoice.fromJson(Map<String, dynamic> json) {
    return LinkedInvoice(
      invoiceId: json['invoiceId'] ?? '',
      invoiceNumber: json['invoiceNumber'] ?? '',
      invoicedDate: DateTime.parse(json['invoicedDate']),
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }
}

class EmailRecord {
  final String sentTo;
  final DateTime sentAt;
  final String emailType;

  EmailRecord({
    required this.sentTo,
    required this.sentAt,
    required this.emailType,
  });

  factory EmailRecord.fromJson(Map<String, dynamic> json) {
    return EmailRecord(
      sentTo: json['sentTo'] ?? '',
      sentAt: DateTime.parse(json['sentAt']),
      emailType: json['emailType'] ?? '',
    );
  }
}

class ChallanStats {
  final int totalChallans;
  final Map<String, int> byStatus;

  ChallanStats({
    required this.totalChallans,
    required this.byStatus,
  });

  factory ChallanStats.fromJson(Map<String, dynamic> json) {
    return ChallanStats(
      totalChallans: json['totalChallans'] ?? 0,
      byStatus: Map<String, int>.from(json['byStatus'] ?? {}),
    );
  }
}

class ChallansResponse {
  final List<DeliveryChallan> challans;
  final Pagination pagination;

  ChallansResponse({
    required this.challans,
    required this.pagination,
  });

  factory ChallansResponse.fromJson(Map<String, dynamic> json) {
    return ChallansResponse(
      challans: (json['data'] as List)
          .map((challan) => DeliveryChallan.fromJson(challan))
          .toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

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
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 20,
      pages: json['pages'] ?? 1,
    );
  }
}

// ============================================================================
// DELIVERY CHALLAN SERVICE
// ============================================================================

class DeliveryChallanService {
  static final String _baseUrl = ApiConfig.baseUrl;
  static const String _endpoint = '/api/finance/delivery-challans';

  // Get auth headers
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ============================================================================
  // GET ALL DELIVERY CHALLANS
  // ============================================================================

  static Future<ChallansResponse> getDeliveryChallans({
    String? status,
    String? customerId,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (status != null && status != 'All') {
        queryParams['status'] = status;
      }
      if (customerId != null) {
        queryParams['customerId'] = customerId;
      }
      if (fromDate != null) {
        queryParams['fromDate'] = fromDate.toIso8601String();
      }
      if (toDate != null) {
        queryParams['toDate'] = toDate.toIso8601String();
      }

      final uri = Uri.parse('$_baseUrl$_endpoint').replace(
        queryParameters: queryParams,
      );

      final response = await http.get(uri, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ChallansResponse.fromJson(data);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch delivery challans');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // GET SINGLE DELIVERY CHALLAN
  // ============================================================================

  static Future<DeliveryChallan> getDeliveryChallan(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id');
      final response = await http.get(uri, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DeliveryChallan.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch delivery challan');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // GET STATISTICS
  // ============================================================================

  static Future<ChallanStats> getStats() async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/stats');
      final response = await http.get(uri, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ChallanStats.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to fetch stats');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // CREATE DELIVERY CHALLAN
  // ============================================================================

  static Future<DeliveryChallan> createDeliveryChallan(
      Map<String, dynamic> challanData) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint');
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: json.encode(challanData),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return DeliveryChallan.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to create delivery challan');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // UPDATE DELIVERY CHALLAN
  // ============================================================================

  static Future<DeliveryChallan> updateDeliveryChallan(
      String id, Map<String, dynamic> challanData) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id');
      final response = await http.put(
        uri,
        headers: await _getHeaders(),
        body: json.encode(challanData),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DeliveryChallan.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to update delivery challan');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // DELETE DELIVERY CHALLAN
  // ============================================================================

  static Future<void> deleteDeliveryChallan(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id');
      final response = await http.delete(uri, headers: await _getHeaders());

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to delete delivery challan');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // DISPATCH (MARK AS OPEN)
  // ============================================================================

  static Future<DeliveryChallan> dispatchChallan(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id/dispatch');
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DeliveryChallan.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to dispatch challan');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // MARK AS DELIVERED
  // ============================================================================

  static Future<DeliveryChallan> markAsDelivered(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id/delivered');
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DeliveryChallan.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to mark as delivered');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // CONVERT TO INVOICE (AUTOMATIC)
  // ============================================================================

  static Future<Map<String, dynamic>> convertToInvoice(
    String id, {
    List<Map<String, dynamic>>? items,
    bool createInvoice = true,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id/convert-to-invoice');
      
      final body = <String, dynamic>{
        'createInvoice': createInvoice,
      };
      
      if (items != null) {
        body['items'] = items;
      }
      
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'challan': DeliveryChallan.fromJson(data['data']['challan']),
          'invoiceData': data['data']['invoiceData'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to convert to invoice');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // RECORD PARTIAL RETURN
  // ============================================================================

  static Future<DeliveryChallan> recordPartialReturn(
    String id,
    List<Map<String, dynamic>> returnedItems,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id/partial-return');
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: json.encode({'items': returnedItems}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DeliveryChallan.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to record return');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // MARK AS RETURNED (FULL)
  // ============================================================================

  static Future<DeliveryChallan> markAsReturned(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id/returned');
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DeliveryChallan.fromJson(data['data']);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to mark as returned');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // SEND VIA EMAIL
  // ============================================================================

  static Future<void> sendChallan(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id/send');
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to send challan');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }

  // ============================================================================
  // DOWNLOAD PDF
  // ============================================================================

  static Future<String> downloadPDF(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl$_endpoint/$id/download-url');
      final response = await http.get(uri, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['downloadUrl'];
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to get PDF URL');
      }
    } catch (e) {
      throw Exception('Network error: ${e.toString()}');
    }
  }
}