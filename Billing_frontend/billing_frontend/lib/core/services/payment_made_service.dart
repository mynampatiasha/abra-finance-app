// ============================================================================
// PAYMENT MADE SERVICE — UPDATED
// ============================================================================
// File: lib/core/services/payment_made_service.dart
// NEW METHOD: getVendorOutstandingBills(vendorId)
//   → GET /api/payments-made/vendor-bills/:vendorId
//   → Returns OPEN + OVERDUE + PARTIALLY_PAID bills for that vendor
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

// ============================================================================
// MODELS
// ============================================================================

class PaymentItem {
  final String id;
  final String itemDetails;
  final String itemType;
  final String? itemId;
  final String? account;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  PaymentItem({
    required this.id,
    required this.itemDetails,
    this.itemType = 'MANUAL',
    this.itemId,
    this.account,
    this.quantity = 1,
    this.rate = 0,
    this.discount = 0,
    this.discountType = 'percentage',
    this.amount = 0,
  });

  factory PaymentItem.fromJson(Map<String, dynamic> json) => PaymentItem(
        id: json['_id'] ?? '',
        itemDetails: json['itemDetails'] ?? '',
        itemType: json['itemType'] ?? 'MANUAL',
        itemId: json['itemId'],
        account: json['account'],
        quantity: (json['quantity'] ?? 1).toDouble(),
        rate: (json['rate'] ?? 0).toDouble(),
        discount: (json['discount'] ?? 0).toDouble(),
        discountType: json['discountType'] ?? 'percentage',
        amount: (json['amount'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'itemDetails': itemDetails,
        'itemType': itemType,
        if (itemId != null) 'itemId': itemId,
        if (account != null) 'account': account,
        'quantity': quantity,
        'rate': rate,
        'discount': discount,
        'discountType': discountType,
        'amount': amount,
      };
}

class BillApplied {
  final String billId;
  final String billNumber;
  final double amountApplied;
  final DateTime appliedDate;

  BillApplied({
    required this.billId,
    required this.billNumber,
    required this.amountApplied,
    required this.appliedDate,
  });

  factory BillApplied.fromJson(Map<String, dynamic> json) => BillApplied(
        billId: json['billId'] ?? '',
        billNumber: json['billNumber'] ?? '',
        amountApplied: (json['amountApplied'] ?? 0).toDouble(),
        appliedDate: json['appliedDate'] != null
            ? DateTime.parse(json['appliedDate'])
            : DateTime.now(),
      );
}

class PaymentRefund {
  final String refundId;
  final double amount;
  final DateTime refundDate;
  final String refundMode;
  final String? referenceNumber;
  final String? notes;

  PaymentRefund({
    required this.refundId,
    required this.amount,
    required this.refundDate,
    required this.refundMode,
    this.referenceNumber,
    this.notes,
  });

  factory PaymentRefund.fromJson(Map<String, dynamic> json) => PaymentRefund(
        refundId: json['refundId'] ?? '',
        amount: (json['amount'] ?? 0).toDouble(),
        refundDate: json['refundDate'] != null
            ? DateTime.parse(json['refundDate'])
            : DateTime.now(),
        refundMode: json['refundMode'] ?? '',
        referenceNumber: json['referenceNumber'],
        notes: json['notes'],
      );
}

class PaymentMade {
  final String id;
  final String paymentNumber;
  final String vendorId;
  final String vendorName;
  final String? vendorEmail;
  final DateTime paymentDate;
  final String paymentMode;
  final String? referenceNumber;
  final double amount;
  final String? notes;
  final String paymentType;
  final String status;
  final List<BillApplied> billsApplied;
  final double amountApplied;
  final double amountUnused;
  final List<PaymentItem> items;
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
  final List<PaymentRefund> refunds;
  final double totalRefunded;
  final String? paidFromAccountId;
  final String? paidFromAccountName;
  final String? pdfPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentMade({
    required this.id,
    required this.paymentNumber,
    required this.vendorId,
    required this.vendorName,
    this.vendorEmail,
    required this.paymentDate,
    required this.paymentMode,
    this.referenceNumber,
    this.paidFromAccountId,
    this.paidFromAccountName,
    required this.amount,
    this.notes,
    this.paymentType = 'PAYMENT',
    this.status = 'RECORDED',
    this.billsApplied = const [],
    this.amountApplied = 0,
    this.amountUnused = 0,
    this.items = const [],
    this.subTotal = 0,
    this.tdsRate = 0,
    this.tdsAmount = 0,
    this.tcsRate = 0,
    this.tcsAmount = 0,
    this.gstRate = 18,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.totalAmount = 0,
    this.refunds = const [],
    this.totalRefunded = 0,
    this.pdfPath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentMade.fromJson(Map<String, dynamic> json) => PaymentMade(
        id: json['_id'] ?? '',
        paymentNumber: json['paymentNumber'] ?? '',
        vendorId: json['vendorId'] ?? '',
        vendorName: json['vendorName'] ?? '',
        vendorEmail: json['vendorEmail'],
        paymentDate: json['paymentDate'] != null
            ? DateTime.parse(json['paymentDate'])
            : DateTime.now(),
        paymentMode: json['paymentMode'] ?? '',
        referenceNumber: json['referenceNumber'],
        paidFromAccountId: json['paidFromAccountId'],
        paidFromAccountName: json['paidFromAccountName'],
        amount: (json['amount'] ?? 0).toDouble(),
        notes: json['notes'],
        paymentType: json['paymentType'] ?? 'PAYMENT',
        status: json['status'] ?? 'RECORDED',
        billsApplied: (json['billsApplied'] as List? ?? [])
            .map((b) => BillApplied.fromJson(b))
            .toList(),
        amountApplied: (json['amountApplied'] ?? 0).toDouble(),
        amountUnused: (json['amountUnused'] ?? 0).toDouble(),
        items: (json['items'] as List? ?? [])
            .map((i) => PaymentItem.fromJson(i))
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
        refunds: (json['refunds'] as List? ?? [])
            .map((r) => PaymentRefund.fromJson(r))
            .toList(),
        totalRefunded: (json['totalRefunded'] ?? 0).toDouble(),
        pdfPath: json['pdfPath'],
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'])
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'])
            : DateTime.now(),
      );
}

class PaymentMadeStats {
  final int totalPayments;
  final double totalAmount;
  final double totalApplied;
  final double totalUnused;
  final Map<String, dynamic> byStatus;

  PaymentMadeStats({
    this.totalPayments = 0,
    this.totalAmount = 0,
    this.totalApplied = 0,
    this.totalUnused = 0,
    this.byStatus = const {},
  });

  factory PaymentMadeStats.fromJson(Map<String, dynamic> json) =>
      PaymentMadeStats(
        totalPayments: json['totalPayments'] ?? 0,
        totalAmount: (json['totalAmount'] ?? 0).toDouble(),
        totalApplied: (json['totalApplied'] ?? 0).toDouble(),
        totalUnused: (json['totalUnused'] ?? 0).toDouble(),
        byStatus: json['byStatus'] ?? {},
      );
}

class PaymentMadeListResponse {
  final List<PaymentMade> payments;
  final PaymentMadePagination pagination;

  PaymentMadeListResponse(
      {required this.payments, required this.pagination});
}

class PaymentMadePagination {
  final int total;
  final int page;
  final int limit;
  final int pages;

  PaymentMadePagination(
      {required this.total,
      required this.page,
      required this.limit,
      required this.pages});

  factory PaymentMadePagination.fromJson(Map<String, dynamic> json) =>
      PaymentMadePagination(
        total: json['total'] ?? 0,
        page: json['page'] ?? 1,
        limit: json['limit'] ?? 20,
        pages: json['pages'] ?? 1,
      );
}

// ============================================================================
// SERVICE
// ============================================================================

class PaymentMadeService {
  static String get _baseUrl => ApiConfig.baseUrl;
  static String get _endpoint => '$_baseUrl/api/finance/payments-made';

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── NEW: Get outstanding bills for a vendor ───────────────────────────────
  // Returns list of bills with status OPEN | OVERDUE | PARTIALLY_PAID
  // sorted oldest first so auto-allocation works correctly
  static Future<List<Map<String, dynamic>>> getVendorOutstandingBills(
      String vendorId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$_endpoint/vendor-bills/$vendorId'),
      headers: headers,
    );
    _checkStatus(response);
    final body = jsonDecode(response.body);
    final data = body['data'] as List? ?? [];
    return data.map<Map<String, dynamic>>((b) => Map<String, dynamic>.from(b)).toList();
  }

  // ── List ──────────────────────────────────────────────────────────────────

  static Future<PaymentMadeListResponse> getPayments({
    String? status,
    String? vendorId,
    DateTime? fromDate,
    DateTime? toDate,
    String? paymentMode,
    String? paymentType,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (status != null && status != 'All') 'status': status,
      if (vendorId != null) 'vendorId': vendorId,
      if (paymentMode != null) 'paymentMode': paymentMode,
      if (paymentType != null) 'paymentType': paymentType,
      if (search != null && search.isNotEmpty) 'search': search,
      if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
      if (toDate != null) 'toDate': toDate.toIso8601String(),
    };

    final uri =
        Uri.parse(_endpoint).replace(queryParameters: params);
    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers);
    _checkStatus(response);
    final body = jsonDecode(response.body);
    final data = body['data'] as List;
    return PaymentMadeListResponse(
      payments: data.map((j) => PaymentMade.fromJson(j)).toList(),
      pagination:
          PaymentMadePagination.fromJson(body['pagination'] ?? {}),
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  static Future<PaymentMadeStats> getStats() async {
    final headers = await _getHeaders();
    final response = await http.get(
        Uri.parse('$_endpoint/stats'),
        headers: headers);
    _checkStatus(response);
    final body = jsonDecode(response.body);
    return PaymentMadeStats.fromJson(body['data'] ?? {});
  }

  // ── Single ────────────────────────────────────────────────────────────────

  static Future<PaymentMade> getPayment(String id) async {
    final headers = await _getHeaders();
    final response = await http.get(
        Uri.parse('$_endpoint/$id'),
        headers: headers);
    _checkStatus(response);
    return PaymentMade.fromJson(
        jsonDecode(response.body)['data']);
  }

  // ── Create ────────────────────────────────────────────────────────────────

  static Future<PaymentMade> createPayment(
      Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final response = await http.post(Uri.parse(_endpoint),
        headers: headers, body: jsonEncode(data));
    _checkStatus(response);
    return PaymentMade.fromJson(
        jsonDecode(response.body)['data']);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  static Future<PaymentMade> updatePayment(
      String id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final response = await http.put(
        Uri.parse('$_endpoint/$id'),
        headers: headers,
        body: jsonEncode(data));
    _checkStatus(response);
    return PaymentMade.fromJson(
        jsonDecode(response.body)['data']);
  }

// ── Vendor Phone (live lookup from DB) ────────────────────────────────────
static Future<String> getVendorPhone(String paymentId) async {
  final headers = await _getHeaders();
  final response = await http.get(
    Uri.parse('$_endpoint/$paymentId/vendor-phone'),
    headers: headers,
  );
  _checkStatus(response);
  final body = jsonDecode(response.body);
  return (body['phone'] as String? ?? '').trim();
}


  // ── Apply to Bills ────────────────────────────────────────────────────────

  static Future<PaymentMade> applyToBills(
      String id, List<Map<String, dynamic>> bills) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_endpoint/$id/apply'),
      headers: headers,
      body: jsonEncode({'bills': bills}),
    );
    _checkStatus(response);
    return PaymentMade.fromJson(
        jsonDecode(response.body)['data']);
  }

  // ── Refund ────────────────────────────────────────────────────────────────

  static Future<PaymentMade> recordRefund(
      String id, Map<String, dynamic> refundData) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_endpoint/$id/refund'),
      headers: headers,
      body: jsonEncode(refundData),
    );
    _checkStatus(response);
    return PaymentMade.fromJson(
        jsonDecode(response.body)['data']);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deletePayment(String id) async {
    final headers = await _getHeaders();
    final response = await http.delete(
        Uri.parse('$_endpoint/$id'),
        headers: headers);
    _checkStatus(response);
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  static Future<String> downloadPDF(String id) async {
    final headers = await _getHeaders();
    final response = await http.get(
        Uri.parse('$_endpoint/$id/download-url'),
        headers: headers);
    _checkStatus(response);
    final body = jsonDecode(response.body);
    return body['downloadUrl'] as String;
  }

  // ── Bulk Import ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> bulkImport(
      List<Map<String, dynamic>> paymentsData,
      Uint8List fileBytes,
      String fileName) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('$_endpoint/bulk-import'));
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes,
        filename: fileName));
    request.fields['paymentsData'] = jsonEncode(paymentsData);
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkStatus(response);
    return jsonDecode(response.body);
  }

  // ── All (for export) ──────────────────────────────────────────────────────

  static Future<List<PaymentMade>> getAllPayments(
      {String? status,
      DateTime? fromDate,
      DateTime? toDate}) async {
    final result = await getPayments(
        status: status,
        fromDate: fromDate,
        toDate: toDate,
        limit: 10000);
    return result.payments;
  }

  // ── Helper ────────────────────────────────────────────────────────────────

  static void _checkStatus(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Request failed (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        message = body['error'] ?? body['message'] ?? message;
      } catch (_) {}
      throw Exception(message);
    }
  }
}