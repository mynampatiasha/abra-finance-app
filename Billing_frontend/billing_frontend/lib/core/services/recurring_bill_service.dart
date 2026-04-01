// ============================================================================
// RECURRING BILL SERVICE
// ============================================================================
// File: lib/core/services/recurring_bill_service.dart
// All API calls for Recurring Bills - NO hardcoded URLs
// Uses ApiConfig.baseUrl for all endpoints
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

class RecurringBill {
  final String id;
  final String profileName;
  final String vendorId;
  final String vendorName;
  final String vendorEmail;
  final String status;
  final int repeatEvery;
  final String repeatUnit;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextBillDate;
  final int totalBillsGenerated;
  final String billCreationMode;
  final double subTotal;
  final double totalAmount;
  final DateTime? lastGeneratedDate;
  final List<RecurringBillItem> items;
  final double tdsRate;
  final double tcsRate;
  final double gstRate;
  final String? paymentTerms;
  final String? notes;

  RecurringBill({
    required this.id,
    required this.profileName,
    required this.vendorId,
    required this.vendorName,
    required this.vendorEmail,
    required this.status,
    required this.repeatEvery,
    required this.repeatUnit,
    required this.startDate,
    this.endDate,
    required this.nextBillDate,
    required this.totalBillsGenerated,
    required this.billCreationMode,
    required this.subTotal,
    required this.totalAmount,
    this.lastGeneratedDate,
    required this.items,
    this.tdsRate = 0,
    this.tcsRate = 0,
    this.gstRate = 18,
    this.paymentTerms,
    this.notes,
  });

  factory RecurringBill.fromJson(Map<String, dynamic> json) {
    return RecurringBill(
      id: json['_id'] ?? json['id'] ?? '',
      profileName: json['profileName'] ?? '',
      vendorId: json['vendorId'] ?? '',
      vendorName: json['vendorName'] ?? '',
      vendorEmail: json['vendorEmail'] ?? '',
      status: json['status'] ?? 'ACTIVE',
      repeatEvery: json['repeatEvery'] ?? 1,
      repeatUnit: json['repeatUnit'] ?? 'months',
      startDate: json['startDate'] != null ? DateTime.parse(json['startDate']) : DateTime.now(),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      nextBillDate: json['nextBillDate'] != null ? DateTime.parse(json['nextBillDate']) : DateTime.now(),
      totalBillsGenerated: json['totalBillsGenerated'] ?? 0,
      billCreationMode: json['billCreationMode'] ?? 'save_as_draft',
      subTotal: (json['subTotal'] ?? 0).toDouble(),
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
      lastGeneratedDate: json['lastGeneratedDate'] != null ? DateTime.parse(json['lastGeneratedDate']) : null,
      items: (json['items'] as List<dynamic>? ?? []).map((item) => RecurringBillItem.fromJson(item)).toList(),
      tdsRate: (json['tdsRate'] ?? 0).toDouble(),
      tcsRate: (json['tcsRate'] ?? 0).toDouble(),
      gstRate: (json['gstRate'] ?? 18).toDouble(),
      paymentTerms: json['paymentTerms'],
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id, 'profileName': profileName, 'vendorId': vendorId,
    'vendorName': vendorName, 'vendorEmail': vendorEmail, 'status': status,
    'repeatEvery': repeatEvery, 'repeatUnit': repeatUnit,
    'startDate': startDate.toIso8601String(), 'endDate': endDate?.toIso8601String(),
    'nextBillDate': nextBillDate.toIso8601String(),
    'totalBillsGenerated': totalBillsGenerated, 'billCreationMode': billCreationMode,
    'subTotal': subTotal, 'totalAmount': totalAmount,
    'lastGeneratedDate': lastGeneratedDate?.toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
    'tdsRate': tdsRate, 'tcsRate': tcsRate, 'gstRate': gstRate,
    'paymentTerms': paymentTerms, 'notes': notes,
  };
}

class RecurringBillItem {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;
  String? itemId;

  RecurringBillItem({
    this.itemDetails = '', this.quantity = 0, this.rate = 0,
    this.discount = 0, this.discountType = 'percentage', this.amount = 0, this.itemId,
  });

  factory RecurringBillItem.fromJson(Map<String, dynamic> json) => RecurringBillItem(
    itemDetails: json['itemDetails'] ?? '',
    quantity: (json['quantity'] ?? 0).toDouble(),
    rate: (json['rate'] ?? 0).toDouble(),
    discount: (json['discount'] ?? 0).toDouble(),
    discountType: json['discountType'] ?? 'percentage',
    amount: (json['amount'] ?? 0).toDouble(),
    itemId: json['itemId'],
  );

  Map<String, dynamic> toJson() => {
    'itemDetails': itemDetails, 'quantity': quantity, 'rate': rate,
    'discount': discount, 'discountType': discountType, 'amount': amount,
    if (itemId != null) 'itemId': itemId,
  };
}

class RecurringBillStats {
  final int totalProfiles, activeProfiles, pausedProfiles, stoppedProfiles, totalBillsGenerated;
  RecurringBillStats({required this.totalProfiles, required this.activeProfiles,
    required this.pausedProfiles, required this.stoppedProfiles, required this.totalBillsGenerated});
  factory RecurringBillStats.fromJson(Map<String, dynamic> json) => RecurringBillStats(
    totalProfiles: json['totalProfiles'] ?? 0, activeProfiles: json['activeProfiles'] ?? 0,
    pausedProfiles: json['pausedProfiles'] ?? 0, stoppedProfiles: json['stoppedProfiles'] ?? 0,
    totalBillsGenerated: json['totalBillsGenerated'] ?? 0,
  );
}

class PaginationInfo {
  final int total, pages, page, limit;
  PaginationInfo({required this.total, required this.pages, required this.page, required this.limit});
  factory PaginationInfo.fromJson(Map<String, dynamic> json) => PaginationInfo(
    total: json['total'] ?? 0, pages: json['pages'] ?? 1,
    page: json['page'] ?? 1, limit: json['limit'] ?? 20,
  );
}

class RecurringBillsResponse {
  final List<RecurringBill> recurringBills;
  final PaginationInfo pagination;
  RecurringBillsResponse({required this.recurringBills, required this.pagination});
}

class ChildBillsResponse {
  final List<ChildBill> bills;
  ChildBillsResponse({required this.bills});
}

class ChildBill {
  final String id, billNumber, status;
  final DateTime billDate;
  final double totalAmount;
  ChildBill({required this.id, required this.billNumber, required this.billDate,
    required this.totalAmount, required this.status});
  factory ChildBill.fromJson(Map<String, dynamic> json) => ChildBill(
    id: json['_id'] ?? json['id'] ?? '',
    billNumber: json['billNumber'] ?? '',
    billDate: json['billDate'] != null ? DateTime.parse(json['billDate']) : DateTime.now(),
    totalAmount: (json['totalAmount'] ?? 0).toDouble(),
    status: json['status'] ?? 'OPEN',
  );
}

class GeneratedBillResult {
  final String billId, billNumber;
  GeneratedBillResult({required this.billId, required this.billNumber});
  factory GeneratedBillResult.fromJson(Map<String, dynamic> json) => GeneratedBillResult(
    billId: json['billId'] ?? '', billNumber: json['billNumber'] ?? '',
  );
}

class BillItem {
  final String id, name, description, unit, type;
  final double rate;
  BillItem({required this.id, required this.name, required this.description,
    required this.rate, required this.unit, required this.type});
  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
    id: json['_id'] ?? json['id'] ?? '',
    name: json['name'] ?? json['itemName'] ?? '',
    description: json['description'] ?? '',
    rate: (json['rate'] ?? json['purchaseRate'] ?? 0).toDouble(),
    unit: json['unit'] ?? '',
    type: json['type'] ?? 'service',
  );
}

class RecurringBillException implements Exception {
  final String message;
  final int? statusCode;
  RecurringBillException(this.message, {this.statusCode});
  String toUserMessage() {
    if (statusCode == 401) return 'Session expired. Please login again.';
    if (statusCode == 403) return 'You do not have permission to perform this action.';
    if (statusCode == 404) return 'Recurring bill profile not found.';
    if (statusCode == 409) return 'A profile with this name already exists.';
    if (statusCode != null && statusCode! >= 500) return 'Server error. Please try again later.';
    return message;
  }
  @override
  String toString() => 'RecurringBillException: $message';
}

// ============================================================================
// SERVICE CLASS
// ============================================================================

class RecurringBillService {
  static String get _base => '${ApiConfig.baseUrl}/api/finance/recurring-bills';

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    return {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    final data = json.decode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final message = data['message'] ?? data['error'] ?? 'Request failed';
    throw RecurringBillException(message, statusCode: response.statusCode);
  }

  static Future<RecurringBillsResponse> getRecurringBills({
    String? status, int page = 1, int limit = 20,
    String? fromDate, String? toDate, String? search,
  }) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{
      'page': page.toString(), 'limit': limit.toString(),
      if (status != null && status.isNotEmpty) 'status': status,
      if (fromDate != null) 'fromDate': fromDate,
      if (toDate != null) 'toDate': toDate,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri = Uri.parse(_base).replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      final billsList = (data['data']['recurringBills'] as List<dynamic>? ?? [])
          .map((b) => RecurringBill.fromJson(b)).toList();
      final pagination = PaginationInfo.fromJson(
          data['data']['pagination'] ?? {'total': 0, 'pages': 1, 'page': 1, 'limit': limit});
      return RecurringBillsResponse(recurringBills: billsList, pagination: pagination);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to load recurring bills: $e');
    }
  }

  static Future<RecurringBill> getRecurringBillById(String id) async {
    final headers = await _getHeaders();
    try {
      final response = await http.get(Uri.parse('$_base/$id'), headers: headers)
          .timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      return RecurringBill.fromJson(data['data']);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to load recurring bill: $e');
    }
  }

  static Future<RecurringBill> createRecurringBill(Map<String, dynamic> billData) async {
    final headers = await _getHeaders();
    try {
      final response = await http.post(Uri.parse(_base), headers: headers,
          body: json.encode(billData)).timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      return RecurringBill.fromJson(data['data']);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to create recurring bill: $e');
    }
  }

  static Future<RecurringBill> updateRecurringBill(String id, Map<String, dynamic> billData) async {
    final headers = await _getHeaders();
    try {
      final response = await http.put(Uri.parse('$_base/$id'), headers: headers,
          body: json.encode(billData)).timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      return RecurringBill.fromJson(data['data']);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to update recurring bill: $e');
    }
  }

  static Future<void> deleteRecurringBill(String id) async {
    final headers = await _getHeaders();
    try {
      final response = await http.delete(Uri.parse('$_base/$id'), headers: headers)
          .timeout(const Duration(seconds: 30));
      _handleResponse(response);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to delete recurring bill: $e');
    }
  }

  static Future<void> pauseRecurringBill(String id) async {
    final headers = await _getHeaders();
    try {
      final response = await http.patch(Uri.parse('$_base/$id/pause'), headers: headers)
          .timeout(const Duration(seconds: 30));
      _handleResponse(response);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to pause recurring bill: $e');
    }
  }

  static Future<void> resumeRecurringBill(String id) async {
    final headers = await _getHeaders();
    try {
      final response = await http.patch(Uri.parse('$_base/$id/resume'), headers: headers)
          .timeout(const Duration(seconds: 30));
      _handleResponse(response);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to resume recurring bill: $e');
    }
  }

  static Future<void> stopRecurringBill(String id) async {
    final headers = await _getHeaders();
    try {
      final response = await http.patch(Uri.parse('$_base/$id/stop'), headers: headers)
          .timeout(const Duration(seconds: 30));
      _handleResponse(response);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to stop recurring bill: $e');
    }
  }

  static Future<GeneratedBillResult> generateManualBill(String id) async {
    final headers = await _getHeaders();
    try {
      final response = await http.post(Uri.parse('$_base/$id/generate'), headers: headers)
          .timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      return GeneratedBillResult.fromJson(data['data']);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to generate bill: $e');
    }
  }

  static Future<ChildBillsResponse> getChildBills(String profileId) async {
    final headers = await _getHeaders();
    try {
      final response = await http.get(Uri.parse('$_base/$profileId/child-bills'), headers: headers)
          .timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      final bills = (data['data']['bills'] as List<dynamic>? ?? [])
          .map((b) => ChildBill.fromJson(b)).toList();
      return ChildBillsResponse(bills: bills);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to load child bills: $e');
    }
  }

  static Future<RecurringBillStats> getStats() async {
    final headers = await _getHeaders();
    try {
      final response = await http.get(Uri.parse('$_base/stats'), headers: headers)
          .timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      return RecurringBillStats.fromJson(data['data']);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to load stats: $e');
    }
  }

  static Future<List<BillItem>> getItems({String? search}) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{
      if (search != null && search.isNotEmpty) 'search': search,
      'limit': '100',
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/finance/items')
        .replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      final data = _handleResponse(response);
      final itemsList = data['data']['items'] as List<dynamic>? ??
          data['data'] as List<dynamic>? ?? [];
      return itemsList.map((i) => BillItem.fromJson(i)).toList();
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to load items: $e');
    }
  }

  static Future<Map<String, dynamic>> bulkImportRecurringBills(
      List<Map<String, dynamic>> bills) async {
    final headers = await _getHeaders();
    try {
      final response = await http.post(Uri.parse('$_base/bulk-import'), headers: headers,
          body: json.encode({'recurringBills': bills})).timeout(const Duration(seconds: 60));
      return _handleResponse(response);
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to import recurring bills: $e');
    }
  }

  static Future<List<RecurringBill>> getAllForExport({String? status}) async {
    final headers = await _getHeaders();
    final queryParams = <String, String>{
      'limit': '10000',
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final uri = Uri.parse(_base).replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 60));
      final data = _handleResponse(response);
      return (data['data']['recurringBills'] as List<dynamic>? ?? [])
          .map((b) => RecurringBill.fromJson(b)).toList();
    } catch (e) {
      if (e is RecurringBillException) rethrow;
      throw RecurringBillException('Failed to export recurring bills: $e');
    }
  }
}
