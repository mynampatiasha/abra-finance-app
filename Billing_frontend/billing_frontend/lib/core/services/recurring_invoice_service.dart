// lib/core/services/recurring_invoice_service.dart
import 'dart:convert';
import '../../app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class RecurringInvoiceService {
  static const String _base = '/api/finance/recurring-invoices';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('finance_jwt_token') ?? prefs.getString('jwt_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response r) =>
      json.decode(r.body) as Map<String, dynamic>;

  static Future<RecurringInvoiceListResponse> getRecurringInvoices({
    String? status, String? customerId, int page = 1, int limit = 20,
  }) async {
    final q = <String, String>{'page': '$page', 'limit': '$limit',
      if (status != null) 'status': status,
      if (customerId != null) 'customerId': customerId};
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base').replace(queryParameters: q);
    final res = await http.get(uri, headers: await _headers());
    return RecurringInvoiceListResponse.fromJson(_decode(res));
  }

  static Future<RecurringInvoice> getRecurringInvoice(String id) async {
    final res = await http.get(Uri.parse('${ApiConfig.baseUrl}$_base/$id'), headers: await _headers());
    return RecurringInvoice.fromJson(_decode(res)['data']);
  }

  static Future<RecurringInvoice> createRecurringInvoice(Map<String, dynamic> data) async {
    final res = await http.post(Uri.parse('${ApiConfig.baseUrl}$_base'),
        headers: await _headers(), body: json.encode(data));
    return RecurringInvoice.fromJson(_decode(res)['data']);
  }

  static Future<RecurringInvoice> updateRecurringInvoice(String id, Map<String, dynamic> data) async {
    final res = await http.put(Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
        headers: await _headers(), body: json.encode(data));
    return RecurringInvoice.fromJson(_decode(res)['data']);
  }

  static Future<RecurringInvoice> pauseRecurringInvoice(String id) async {
    final res = await http.post(Uri.parse('${ApiConfig.baseUrl}$_base/$id/pause'), headers: await _headers());
    return RecurringInvoice.fromJson(_decode(res)['data']);
  }

  static Future<RecurringInvoice> resumeRecurringInvoice(String id) async {
    final res = await http.post(Uri.parse('${ApiConfig.baseUrl}$_base/$id/resume'), headers: await _headers());
    return RecurringInvoice.fromJson(_decode(res)['data']);
  }

  static Future<RecurringInvoice> stopRecurringInvoice(String id) async {
    final res = await http.post(Uri.parse('${ApiConfig.baseUrl}$_base/$id/stop'), headers: await _headers());
    return RecurringInvoice.fromJson(_decode(res)['data']);
  }

  static Future<ManualInvoiceResponse> generateManualInvoice(String id) async {
    final res = await http.post(Uri.parse('${ApiConfig.baseUrl}$_base/$id/generate'), headers: await _headers());
    return ManualInvoiceResponse.fromJson(_decode(res)['data']);
  }

  static Future<ChildInvoicesResponse> getChildInvoices(String id) async {
    final res = await http.get(Uri.parse('${ApiConfig.baseUrl}$_base/$id/child-invoices'), headers: await _headers());
    return ChildInvoicesResponse.fromJson(_decode(res)['data']);
  }

  static Future<void> deleteRecurringInvoice(String id) async {
    await http.delete(Uri.parse('${ApiConfig.baseUrl}$_base/$id'), headers: await _headers());
  }

  static Future<RecurringInvoiceStats> getStats() async {
    final res = await http.get(Uri.parse('${ApiConfig.baseUrl}$_base/stats'), headers: await _headers());
    return RecurringInvoiceStats.fromJson(_decode(res)['data']);
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class RecurringInvoice {
  final String id;
  final String profileName;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final int repeatEvery;
  final String repeatUnit;
  final DateTime startDate;
  final DateTime? endDate;
  final int? maxOccurrences;
  final DateTime nextInvoiceDate;
  final String? orderNumber;
  final String terms;
  final String? salesperson;
  final String? subject;
  final List<RecurringInvoiceItem> items;
  final String? customerNotes;
  final String? termsAndConditions;
  final double tdsRate;
  final double tcsRate;
  final double gstRate;
  final String invoiceCreationMode;
  final bool autoApplyPayments;
  final bool autoApplyCreditNotes;
  final bool suspendOnFailure;
  final bool disableAutoSaveCard;
  final double subTotal;
  final double totalAmount;
  final String status;
  final List<String> childInvoiceIds;
  final DateTime? lastGeneratedDate;
  final int totalInvoicesGenerated;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  RecurringInvoice({
    required this.id, required this.profileName, required this.customerId,
    required this.customerName, required this.customerEmail, this.customerPhone = '',
    required this.repeatEvery, required this.repeatUnit, required this.startDate,
    this.endDate, this.maxOccurrences, required this.nextInvoiceDate,
    this.orderNumber, required this.terms, this.salesperson, this.subject,
    required this.items, this.customerNotes, this.termsAndConditions,
    required this.tdsRate, required this.tcsRate, required this.gstRate,
    required this.invoiceCreationMode, required this.autoApplyPayments,
    required this.autoApplyCreditNotes, required this.suspendOnFailure,
    required this.disableAutoSaveCard, required this.subTotal,
    required this.totalAmount, required this.status, required this.childInvoiceIds,
    this.lastGeneratedDate, required this.totalInvoicesGenerated,
    required this.createdAt, required this.updatedAt, required this.createdBy,
  });

  factory RecurringInvoice.fromJson(Map<String, dynamic> json) => RecurringInvoice(
    id: json['_id'] ?? json['id'] ?? '',
    profileName: json['profileName'] ?? '',
    customerId: json['customerId'] ?? '',
    customerName: json['customerName'] ?? '',
    customerEmail: json['customerEmail'] ?? '',
    customerPhone: json['customerPhone'] ?? '',
    repeatEvery: json['repeatEvery'] ?? 1,
    repeatUnit: json['repeatUnit'] ?? 'month',
    startDate: DateTime.tryParse(json['startDate'] ?? '') ?? DateTime.now(),
    endDate: json['endDate'] != null ? DateTime.tryParse(json['endDate']) : null,
    maxOccurrences: json['maxOccurrences'],
    nextInvoiceDate: DateTime.tryParse(json['nextInvoiceDate'] ?? '') ?? DateTime.now(),
    orderNumber: json['orderNumber'],
    terms: json['terms'] ?? '',
    salesperson: json['salesperson'],
    subject: json['subject'],
    items: (json['items'] as List? ?? []).map((i) => RecurringInvoiceItem.fromJson(i)).toList(),
    customerNotes: json['customerNotes'],
    termsAndConditions: json['termsAndConditions'],
    tdsRate: (json['tdsRate'] ?? 0).toDouble(),
    tcsRate: (json['tcsRate'] ?? 0).toDouble(),
    gstRate: (json['gstRate'] ?? 18).toDouble(),
    invoiceCreationMode: json['invoiceCreationMode'] ?? 'draft',
    autoApplyPayments: json['autoApplyPayments'] ?? false,
    autoApplyCreditNotes: json['autoApplyCreditNotes'] ?? false,
    suspendOnFailure: json['suspendOnFailure'] ?? false,
    disableAutoSaveCard: json['disableAutoSaveCard'] ?? true,
    subTotal: (json['subTotal'] ?? 0).toDouble(),
    totalAmount: (json['totalAmount'] ?? 0).toDouble(),
    status: json['status'] ?? 'ACTIVE',
    childInvoiceIds: List<String>.from(json['childInvoices'] ?? []),
    lastGeneratedDate: json['lastGeneratedDate'] != null ? DateTime.tryParse(json['lastGeneratedDate']) : null,
    totalInvoicesGenerated: json['totalInvoicesGenerated'] ?? 0,
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
    createdBy: json['createdBy'] ?? '',
  );
}

class RecurringInvoiceItem {
  final String itemDetails;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  RecurringInvoiceItem({required this.itemDetails, required this.quantity,
    required this.rate, required this.discount, required this.discountType, required this.amount});

  factory RecurringInvoiceItem.fromJson(Map<String, dynamic> json) => RecurringInvoiceItem(
    itemDetails: json['itemDetails'] ?? '',
    quantity: (json['quantity'] ?? 0).toDouble(),
    rate: (json['rate'] ?? 0).toDouble(),
    discount: (json['discount'] ?? 0).toDouble(),
    discountType: json['discountType'] ?? 'percentage',
    amount: (json['amount'] ?? 0).toDouble(),
  );

  Map<String, dynamic> toJson() => {'itemDetails': itemDetails, 'quantity': quantity,
    'rate': rate, 'discount': discount, 'discountType': discountType, 'amount': amount};
}

class RecurringInvoiceListResponse {
  final List<RecurringInvoice> recurringInvoices;
  final Pagination pagination;
  RecurringInvoiceListResponse({required this.recurringInvoices, required this.pagination});
  factory RecurringInvoiceListResponse.fromJson(Map<String, dynamic> json) =>
    RecurringInvoiceListResponse(
      recurringInvoices: (json['data'] as List? ?? []).map((p) => RecurringInvoice.fromJson(p)).toList(),
      pagination: Pagination.fromJson(json['pagination'] ?? {}),
    );
}

class Pagination {
  final int total, page, limit, pages;
  Pagination({required this.total, required this.page, required this.limit, required this.pages});
  factory Pagination.fromJson(Map<String, dynamic> json) => Pagination(
    total: json['total'] ?? 0, page: json['page'] ?? 1,
    limit: json['limit'] ?? 20, pages: json['pages'] ?? 1);
}

class ManualInvoiceResponse {
  final String invoiceId, invoiceNumber, message;
  ManualInvoiceResponse({required this.invoiceId, required this.invoiceNumber, required this.message});
  factory ManualInvoiceResponse.fromJson(Map<String, dynamic> json) => ManualInvoiceResponse(
    invoiceId: json['invoiceId'] ?? '', invoiceNumber: json['invoiceNumber'] ?? '',
    message: json['message'] ?? 'Invoice generated');
}

class ChildInvoicesResponse {
  final List<ChildInvoice> invoices;
  final int total;
  ChildInvoicesResponse({required this.invoices, required this.total});
  factory ChildInvoicesResponse.fromJson(Map<String, dynamic> json) => ChildInvoicesResponse(
    invoices: (json['invoices'] as List? ?? []).map((i) => ChildInvoice.fromJson(i)).toList(),
    total: json['total'] ?? 0);
}

class ChildInvoice {
  final String id, invoiceNumber, status;
  final DateTime invoiceDate, dueDate, createdAt;
  final double totalAmount;
  ChildInvoice({required this.id, required this.invoiceNumber, required this.invoiceDate,
    required this.dueDate, required this.totalAmount, required this.status, required this.createdAt});
  factory ChildInvoice.fromJson(Map<String, dynamic> json) => ChildInvoice(
    id: json['_id'] ?? '', invoiceNumber: json['invoiceNumber'] ?? '',
    invoiceDate: DateTime.tryParse(json['invoiceDate'] ?? '') ?? DateTime.now(),
    dueDate: DateTime.tryParse(json['dueDate'] ?? '') ?? DateTime.now(),
    totalAmount: (json['totalAmount'] ?? 0).toDouble(),
    status: json['status'] ?? '', createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
}

class RecurringInvoiceStats {
  final int totalProfiles, activeProfiles, pausedProfiles, stoppedProfiles, totalInvoicesGenerated;
  final double totalRecurringRevenue;
  RecurringInvoiceStats({required this.totalProfiles, required this.activeProfiles,
    required this.pausedProfiles, required this.stoppedProfiles,
    required this.totalInvoicesGenerated, required this.totalRecurringRevenue});
  factory RecurringInvoiceStats.fromJson(Map<String, dynamic> json) => RecurringInvoiceStats(
    totalProfiles: json['totalProfiles'] ?? 0, activeProfiles: json['activeProfiles'] ?? 0,
    pausedProfiles: json['pausedProfiles'] ?? 0, stoppedProfiles: json['stoppedProfiles'] ?? 0,
    totalInvoicesGenerated: json['totalInvoicesGenerated'] ?? 0,
    totalRecurringRevenue: (json['totalRecurringRevenue'] ?? 0).toDouble());
}
