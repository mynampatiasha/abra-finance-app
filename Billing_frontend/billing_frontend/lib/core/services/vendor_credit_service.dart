// ============================================================================
// VENDOR CREDIT SERVICE
// ============================================================================
// File: lib/core/services/vendor_credit_service.dart
// All API calls - NO hardcoded URLs - uses ApiConfig.baseUrl
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/config/api_config.dart';

// ============================================================================
// MODELS
// ============================================================================

class VendorCredit {
  final String id;
  final String creditNumber;
  final String vendorId;
  final String vendorName;
  final String? vendorEmail;
  final String? vendorGSTIN;
  final String? vendorPhone;
  final DateTime creditDate;
  final String? billId;
  final String? billNumber;
  final String reason;
  final String status; // OPEN, PARTIALLY_APPLIED, CLOSED, VOID
  final double subTotal;
  final double gstRate;
  final double cgst;
  final double sgst;
  final double tdsAmount;
  final double tcsAmount;
  final double totalAmount;
  final double appliedAmount;
  final double balanceAmount;
  final String? notes;
  final List<VendorCreditItem> items;
  final List<CreditApplication> applications;
  final List<CreditRefund> refunds;
  final DateTime createdAt;

  VendorCredit({
    required this.id,
    required this.creditNumber,
    required this.vendorId,
    required this.vendorName,
    this.vendorEmail,
    this.vendorGSTIN,
    this.vendorPhone,
    required this.creditDate,
    this.billId,
    this.billNumber,
    required this.reason,
    required this.status,
    required this.subTotal,
    required this.gstRate,
    required this.cgst,
    required this.sgst,
    required this.tdsAmount,
    required this.tcsAmount,
    required this.totalAmount,
    required this.appliedAmount,
    required this.balanceAmount,
    this.notes,
    required this.items,
    required this.applications,
    required this.refunds,
    required this.createdAt,
  });

  factory VendorCredit.fromJson(Map<String, dynamic> json) {
    return VendorCredit(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      creditNumber: json['creditNumber']?.toString() ?? '',
      vendorId: json['vendorId']?.toString() ?? '',
      vendorName: json['vendorName']?.toString() ?? '',
      vendorEmail: json['vendorEmail']?.toString(),
      vendorGSTIN: json['vendorGSTIN']?.toString(),
      vendorPhone: json['vendorPhone']?.toString(),
      creditDate: json['creditDate'] != null
          ? DateTime.parse(json['creditDate'].toString())
          : DateTime.now(),
      billId: json['billId']?.toString(),
      billNumber: json['billNumber']?.toString(),
      reason: json['reason']?.toString() ?? '',
      status: json['status']?.toString() ?? 'OPEN',
      subTotal: _toDouble(json['subTotal']),
      gstRate: _toDouble(json['gstRate']),
      cgst: _toDouble(json['cgst']),
      sgst: _toDouble(json['sgst']),
      tdsAmount: _toDouble(json['tdsAmount']),
      tcsAmount: _toDouble(json['tcsAmount']),
      totalAmount: _toDouble(json['totalAmount']),
      appliedAmount: _toDouble(json['appliedAmount']),
      balanceAmount: _toDouble(json['balanceAmount']),
      notes: json['notes']?.toString(),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((i) => VendorCreditItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      applications: (json['applications'] as List<dynamic>? ?? [])
          .map((a) => CreditApplication.fromJson(a as Map<String, dynamic>))
          .toList(),
      refunds: (json['refunds'] as List<dynamic>? ?? [])
          .map((r) => CreditRefund.fromJson(r as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
    );
  }

  static double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
}

class VendorCreditItem {
  final String itemDetails;
  final String? account;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  VendorCreditItem({
    required this.itemDetails,
    this.account,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.discountType,
    required this.amount,
  });

  factory VendorCreditItem.fromJson(Map<String, dynamic> json) {
    return VendorCreditItem(
      itemDetails: json['itemDetails']?.toString() ?? '',
      account: json['account']?.toString(),
      quantity: VendorCredit._toDouble(json['quantity']),
      rate: VendorCredit._toDouble(json['rate']),
      discount: VendorCredit._toDouble(json['discount']),
      discountType: json['discountType']?.toString() ?? 'percentage',
      amount: VendorCredit._toDouble(json['amount']),
    );
  }

  Map<String, dynamic> toJson() => {
    'itemDetails': itemDetails,
    'account': account,
    'quantity': quantity,
    'rate': rate,
    'discount': discount,
    'discountType': discountType,
    'amount': amount,
  };
}

class CreditApplication {
  final String id;
  final String billId;
  final String billNumber;
  final double amount;
  final DateTime appliedDate;

  CreditApplication({
    required this.id,
    required this.billId,
    required this.billNumber,
    required this.amount,
    required this.appliedDate,
  });

  factory CreditApplication.fromJson(Map<String, dynamic> json) {
    return CreditApplication(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      billId: json['billId']?.toString() ?? '',
      billNumber: json['billNumber']?.toString() ?? '',
      amount: VendorCredit._toDouble(json['amount']),
      appliedDate: json['appliedDate'] != null
          ? DateTime.parse(json['appliedDate'].toString())
          : DateTime.now(),
    );
  }
}

class CreditRefund {
  final String id;
  final double amount;
  final DateTime refundDate;
  final String paymentMode;
  final String? referenceNumber;
  final String? notes;

  CreditRefund({
    required this.id,
    required this.amount,
    required this.refundDate,
    required this.paymentMode,
    this.referenceNumber,
    this.notes,
  });

  factory CreditRefund.fromJson(Map<String, dynamic> json) {
    return CreditRefund(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      amount: VendorCredit._toDouble(json['amount']),
      refundDate: json['refundDate'] != null
          ? DateTime.parse(json['refundDate'].toString())
          : DateTime.now(),
      paymentMode: json['paymentMode']?.toString() ?? 'Bank Transfer',
      referenceNumber: json['referenceNumber']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}

class VendorCreditStats {
  final int totalCredits;
  final double totalCreditAmount;
  final double totalApplied;
  final double totalBalance;
  final int openCredits;
  final int partiallyApplied;
  final int closedCredits;

  VendorCreditStats({
    required this.totalCredits,
    required this.totalCreditAmount,
    required this.totalApplied,
    required this.totalBalance,
    required this.openCredits,
    required this.partiallyApplied,
    required this.closedCredits,
  });

  factory VendorCreditStats.fromJson(Map<String, dynamic> json) {
    return VendorCreditStats(
      totalCredits: (json['totalCredits'] as num?)?.toInt() ?? 0,
      totalCreditAmount: VendorCredit._toDouble(json['totalCreditAmount']),
      totalApplied: VendorCredit._toDouble(json['totalApplied']),
      totalBalance: VendorCredit._toDouble(json['totalBalance']),
      openCredits: (json['openCredits'] as num?)?.toInt() ?? 0,
      partiallyApplied: (json['partiallyApplied'] as num?)?.toInt() ?? 0,
      closedCredits: (json['closedCredits'] as num?)?.toInt() ?? 0,
    );
  }
}

class VendorCreditsResponse {
  final List<VendorCredit> credits;
  final PaginationInfo pagination;

  VendorCreditsResponse({required this.credits, required this.pagination});
}

class PaginationInfo {
  final int total;
  final int pages;
  final int page;
  final int limit;

  PaginationInfo({
    required this.total,
    required this.pages,
    required this.page,
    required this.limit,
  });

  factory PaginationInfo.fromJson(Map<String, dynamic> json) {
    return PaginationInfo(
      total: (json['total'] as num?)?.toInt() ?? 0,
      pages: (json['pages'] as num?)?.toInt() ?? 1,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
    );
  }
}

// ============================================================================
// SERVICE
// ============================================================================

class VendorCreditService {
  static String get _base => '${ApiConfig.baseUrl}/api/finance/vendor-credits';

  // ✅ FIXED - with token from SharedPreferences
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // GET all vendor credits with filters
  static Future<VendorCreditsResponse> getVendorCredits({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? fromDate,
    String? toDate,
    String? vendorId,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (status != null && status.isNotEmpty) 'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
      if (fromDate != null) 'fromDate': fromDate,
      if (toDate != null) 'toDate': toDate,
      if (vendorId != null) 'vendorId': vendorId,
    };

    final headers = await _getHeaders();
    final uri = Uri.parse(_base).replace(queryParameters: params);
    final response = await http.get(uri, headers: headers);
    final data = jsonDecode(response.body);

    if (response.statusCode == 200 && data['success'] == true) {
      final list = (data['data']['credits'] as List<dynamic>)
          .map((e) => VendorCredit.fromJson(e as Map<String, dynamic>))
          .toList();
      return VendorCreditsResponse(
        credits: list,
        pagination: PaginationInfo.fromJson(data['data']['pagination'] ?? {}),
      );
    }
    throw Exception(data['message'] ?? 'Failed to load vendor credits');
  }

  // GET single vendor credit
  static Future<VendorCredit> getVendorCredit(String id) async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$_base/$id'), headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return VendorCredit.fromJson(data['data']);
    }
    throw Exception(data['message'] ?? 'Failed to load vendor credit');
  }

  // CREATE vendor credit
  static Future<VendorCredit> createVendorCredit(Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse(_base),
      headers: headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if ((response.statusCode == 200 || response.statusCode == 201) && data['success'] == true) {
      return VendorCredit.fromJson(data['data']);
    }
    throw Exception(data['message'] ?? 'Failed to create vendor credit');
  }

  // UPDATE vendor credit
  static Future<VendorCredit> updateVendorCredit(String id, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$_base/$id'),
      headers: headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return VendorCredit.fromJson(data['data']);
    }
    throw Exception(data['message'] ?? 'Failed to update vendor credit');
  }

  // DELETE vendor credit
  static Future<void> deleteVendorCredit(String id) async {
    final headers = await _getHeaders();
    final response = await http.delete(Uri.parse('$_base/$id'), headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to delete vendor credit');
    }
  }

  // VOID vendor credit
  static Future<void> voidVendorCredit(String id) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$_base/$id/void'),
      headers: headers,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to void vendor credit');
    }
  }

  // APPLY credit to a bill
  static Future<void> applyToBill(String creditId, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_base/$creditId/apply'),
      headers: headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to apply credit to bill');
    }
  }

  // REFUND vendor credit
  static Future<void> refundCredit(String creditId, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_base/$creditId/refund'),
      headers: headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to process refund');
    }
  }

  // GET stats
  static Future<VendorCreditStats> getStats() async {
    final headers = await _getHeaders();
    final response = await http.get(Uri.parse('$_base/stats'), headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return VendorCreditStats.fromJson(data['data']);
    }
    throw Exception(data['message'] ?? 'Failed to load stats');
  }

  // GET all for export
  static Future<List<VendorCredit>> getAllForExport({String? status}) async {
    final params = <String, String>{
      'page': '1',
      'limit': '10000',
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final headers = await _getHeaders();
    final uri = Uri.parse(_base).replace(queryParameters: params);
    final response = await http.get(uri, headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return (data['data']['credits'] as List<dynamic>)
          .map((e) => VendorCredit.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(data['message'] ?? 'Failed to load data for export');
  }

  // BULK IMPORT
  static Future<Map<String, dynamic>> bulkImport(List<Map<String, dynamic>> credits) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_base/bulk-import'),
      headers: headers,
      body: jsonEncode({'credits': credits}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data;
    }
    throw Exception(data['message'] ?? 'Import failed');
  }

// GET open bills for a vendor (for applying credits)
  static Future<List<Map<String, dynamic>>> getOpenBillsForVendor(String vendorId) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/finance/bills')
        .replace(queryParameters: {'vendorId': vendorId, 'status': 'OPEN', 'limit': '100'});
    final response = await http.get(uri, headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return List<Map<String, dynamic>>.from(data['data']['bills'] ?? []);
    }
    return [];
  }

  // ── Vendor Phone (backend route GET /vendor-credits/:id/vendor-phone) ─────
  static Future<String> getVendorPhone(String creditId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$_base/$creditId/vendor-phone'),
      headers: headers,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return (data['phone'] as String? ?? '').trim();
    }
    throw Exception(data['message'] ?? 'Failed to fetch vendor phone');
  }
}

// ============================================================================
// MUTABLE ITEM for form
// ============================================================================

class MutableCreditItem {
  String itemDetails;
  String? account;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  MutableCreditItem({
    this.itemDetails = '',
    this.account,
    this.quantity = 0,
    this.rate = 0,
    this.discount = 0,
    this.discountType = 'percentage',
    this.amount = 0,
  });

  Map<String, dynamic> toJson() => {
    'itemDetails': itemDetails,
    'account': account,
    'quantity': quantity,
    'rate': rate,
    'discount': discount,
    'discountType': discountType,
    'amount': amount,
  };
}