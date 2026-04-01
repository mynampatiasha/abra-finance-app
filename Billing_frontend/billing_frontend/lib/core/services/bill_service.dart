// ============================================================================
// BILL SERVICE - COMPLETE WITH ALL FEATURES
// ============================================================================
// File: lib/core/services/bill_service.dart
// Bridge between Flutter frontend and Node.js backend
// Mirrors invoice_service.dart structure but for Bills
// Features: CRUD, Payment, PDF, Vendors, Recurring Bills, Bulk Import
// ============================================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class BillService {
  static final ApiService _api = ApiService();

  static const String _baseEndpoint = '/api/finance/bills';

  // ============================================================================
  // BILL METHODS
  // ============================================================================

  /// Get all bills with optional filters
  static Future<BillListResponse> getBills({
    String? status,
    String? vendorId,
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

      if (status != null && status != 'All') queryParams['status'] = status;
      if (vendorId != null) queryParams['vendorId'] = vendorId;
      if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      print('📤 GET: $_baseEndpoint with filters: $queryParams');
      final data = await _api.get(_baseEndpoint, queryParams: queryParams);
      print('✅ Bills fetched: ${data['data'].length}');

      return BillListResponse.fromJson(data);
    } catch (e) {
      print('❌ Error fetching bills: $e');
      rethrow;
    }
  }

  /// Get bill statistics
  static Future<BillStats> getStats() async {
    try {
      print('📤 GET: $_baseEndpoint/stats');
      final data = await _api.get('$_baseEndpoint/stats');
      print('✅ Bill stats fetched');
      return BillStats.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching bill stats: $e');
      rethrow;
    }
  }

  /// Get single bill by ID
  static Future<Bill> getBill(String billId) async {
    try {
      print('📤 GET: $_baseEndpoint/$billId');
      final data = await _api.get('$_baseEndpoint/$billId');
      print('✅ Bill fetched: ${data['data']['billNumber']}');
      return Bill.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching bill: $e');
      rethrow;
    }
  }

  /// Create new bill
  static Future<Bill> createBill(Map<String, dynamic> billData) async {
    try {
      print('📤 POST: $_baseEndpoint');
      print('📦 Data: ${json.encode(billData)}');
      final data = await _api.post(_baseEndpoint, body: billData);
      print('✅ Bill created: ${data['data']['billNumber']}');
      return Bill.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating bill: $e');
      rethrow;
    }
  }

  /// Update existing bill
  static Future<Bill> updateBill(String billId, Map<String, dynamic> billData) async {
    try {
      print('📤 PUT: $_baseEndpoint/$billId');
      final data = await _api.put('$_baseEndpoint/$billId', body: billData);
      print('✅ Bill updated: ${data['data']['billNumber']}');
      return Bill.fromJson(data['data']);
    } catch (e) {
      print('❌ Error updating bill: $e');
      rethrow;
    }
  }

  /// Submit draft bill to Open status
  static Future<Bill> submitBill(String billId) async {
    try {
      print('📤 POST: $_baseEndpoint/$billId/submit');
      final data = await _api.post('$_baseEndpoint/$billId/submit');
      print('✅ Bill submitted: ${data['data']['billNumber']}');
      return Bill.fromJson(data['data']);
    } catch (e) {
      print('❌ Error submitting bill: $e');
      rethrow;
    }
  }

  /// Void a bill
  static Future<Bill> voidBill(String billId) async {
    try {
      print('📤 POST: $_baseEndpoint/$billId/void');
      final data = await _api.post('$_baseEndpoint/$billId/void');
      print('✅ Bill voided');
      return Bill.fromJson(data['data']);
    } catch (e) {
      print('❌ Error voiding bill: $e');
      rethrow;
    }
  }

  /// Send bill notification email
  static Future<Bill> sendBill(String billId) async {
    try {
      print('📤 POST: $_baseEndpoint/$billId/send');
      final data = await _api.post('$_baseEndpoint/$billId/send');
      print('✅ Bill sent');
      return Bill.fromJson(data['data']);
    } catch (e) {
      print('❌ Error sending bill: $e');
      rethrow;
    }
  }

  /// Record payment against a bill
  static Future<BillPaymentResponse> recordPayment(
    String billId,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      print('📤 POST: $_baseEndpoint/$billId/payment');
      print('📦 Payment: ${json.encode(paymentData)}');
      final data = await _api.post('$_baseEndpoint/$billId/payment', body: paymentData);
      print('✅ Payment recorded: ₹${paymentData['amount']}');
      return BillPaymentResponse.fromJson(data['data']);
    } catch (e) {
      print('❌ Error recording payment: $e');
      rethrow;
    }
  }

  /// Download bill PDF — returns authenticated URL with token in query param
  static Future<String> downloadPDF(String billId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final url = '${_api.baseUrl}$_baseEndpoint/$billId/pdf?token=$token';
      print('✅ Bill PDF URL: $url');
      return url;
    } catch (e) {
      print('❌ Error getting PDF URL: $e');
      rethrow;
    }
  }

  /// Clone a bill
  static Future<Bill> cloneBill(String billId) async {
    try {
      print('📤 POST: $_baseEndpoint/$billId/clone');
      final data = await _api.post('$_baseEndpoint/$billId/clone');
      print('✅ Bill cloned: ${data['data']['billNumber']}');
      return Bill.fromJson(data['data']);
    } catch (e) {
      print('❌ Error cloning bill: $e');
      rethrow;
    }
  }

  /// Delete bill (only drafts)
  static Future<void> deleteBill(String billId) async {
    try {
      print('📤 DELETE: $_baseEndpoint/$billId');
      await _api.delete('$_baseEndpoint/$billId');
      print('✅ Bill deleted');
    } catch (e) {
      print('❌ Error deleting bill: $e');
      rethrow;
    }
  }

  /// Bulk import bills
  static Future<Map<String, dynamic>> bulkImportBills(
    List<Map<String, dynamic>> bills,
  ) async {
    try {
      print('📤 POST: $_baseEndpoint/bulk-import (${bills.length} bills)');
      final data = await _api.post('$_baseEndpoint/bulk-import', body: {'bills': bills});
      print('✅ Bulk import complete');
      return data;
    } catch (e) {
      print('❌ Error bulk importing bills: $e');
      rethrow;
    }
  }

  // ============================================================================
  // VENDOR METHODS
  // ============================================================================

  /// Get all vendors
  static Future<VendorListResponse> getVendors({
    String? search,
    int page = 1,
    int limit = 50,
    bool activeOnly = true,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (activeOnly) queryParams['active'] = 'true';
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      print('📤 GET: $_baseEndpoint/vendors');
      final data = await _api.get('$_baseEndpoint/vendors', queryParams: queryParams);
      print('✅ Vendors fetched: ${data['data'].length}');

      return VendorListResponse.fromJson(data);
    } catch (e) {
      print('❌ Error fetching vendors: $e');
      rethrow;
    }
  }

  /// Get single vendor
  static Future<Vendor> getVendor(String vendorId) async {
    try {
      final data = await _api.get('$_baseEndpoint/vendors/$vendorId');
      return Vendor.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching vendor: $e');
      rethrow;
    }
  }

  /// Create new vendor
  static Future<Vendor> createVendor(Map<String, dynamic> vendorData) async {
    try {
      print('📤 POST: $_baseEndpoint/vendors');
      final data = await _api.post('$_baseEndpoint/vendors', body: vendorData);
      print('✅ Vendor created: ${data['data']['vendorName']}');
      return Vendor.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating vendor: $e');
      rethrow;
    }
  }

  /// Update vendor
  static Future<Vendor> updateVendor(
    String vendorId,
    Map<String, dynamic> vendorData,
  ) async {
    try {
      final data = await _api.put('$_baseEndpoint/vendors/$vendorId', body: vendorData);
      return Vendor.fromJson(data['data']);
    } catch (e) {
      print('❌ Error updating vendor: $e');
      rethrow;
    }
  }

  /// Deactivate vendor
  static Future<void> deactivateVendor(String vendorId) async {
    try {
      await _api.delete('$_baseEndpoint/vendors/$vendorId');
      print('✅ Vendor deactivated');
    } catch (e) {
      print('❌ Error deactivating vendor: $e');
      rethrow;
    }
  }

  // ============================================================================
  // RECURRING BILL PROFILE METHODS
  // ============================================================================

  /// Get all recurring profiles
  static Future<List<RecurringBillProfile>> getRecurringProfiles({
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;

      final data = await _api.get('$_baseEndpoint/recurring-profiles', queryParams: queryParams);
      return (data['data'] as List).map((p) => RecurringBillProfile.fromJson(p)).toList();
    } catch (e) {
      print('❌ Error fetching recurring profiles: $e');
      rethrow;
    }
  }

  /// Create recurring profile
  static Future<RecurringBillProfile> createRecurringProfile(
    Map<String, dynamic> profileData,
  ) async {
    try {
      final data = await _api.post('$_baseEndpoint/recurring-profiles', body: profileData);
      return RecurringBillProfile.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating recurring profile: $e');
      rethrow;
    }
  }

  /// Pause recurring profile
  static Future<void> pauseRecurringProfile(String profileId) async {
    try {
      await _api.put('$_baseEndpoint/recurring-profiles/$profileId/pause', body: {});
    } catch (e) {
      rethrow;
    }
  }

  /// Resume recurring profile
  static Future<void> resumeRecurringProfile(String profileId) async {
    try {
      await _api.put('$_baseEndpoint/recurring-profiles/$profileId/resume', body: {});
    } catch (e) {
      rethrow;
    }
  }

  /// Stop recurring profile
  static Future<void> stopRecurringProfile(String profileId) async {
    try {
      await _api.delete('$_baseEndpoint/recurring-profiles/$profileId');
    } catch (e) {
      rethrow;
    }
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

/// Bill Model
class Bill {
  final String id;
  final String billNumber;
  final String vendorId;
  final String vendorName;
  final String? vendorEmail;
  final String? vendorPhone;
  final String? vendorGSTIN;
  final BillAddress? billingAddress;
  final String? purchaseOrderNumber;
  final DateTime billDate;
  final DateTime dueDate;
  final String paymentTerms;
  final String? subject;
  final String? notes;
  final String? termsAndConditions;
  final List<BillItem> items;

  // Financials
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

  // Status & Payments
  final String status;
  final double amountPaid;
  final double amountDue;
  final List<BillPayment> payments;

  // Recurring
  final bool isRecurring;

  final DateTime createdAt;
  final DateTime updatedAt;

  Bill({
    required this.id,
    required this.billNumber,
    required this.vendorId,
    required this.vendorName,
    this.vendorEmail,
    this.vendorPhone,
    this.vendorGSTIN,
    this.billingAddress,
    this.purchaseOrderNumber,
    required this.billDate,
    required this.dueDate,
    required this.paymentTerms,
    this.subject,
    this.notes,
    this.termsAndConditions,
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
    required this.status,
    required this.amountPaid,
    required this.amountDue,
    required this.payments,
    required this.isRecurring,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: json['_id'] ?? json['id'] ?? '',
      billNumber: json['billNumber'] ?? '',
      vendorId: json['vendorId']?.toString() ?? '',
      vendorName: json['vendorName'] ?? '',
      vendorEmail: json['vendorEmail'],
      vendorPhone: json['vendorPhone'],
      vendorGSTIN: json['vendorGSTIN'],
      billingAddress: json['billingAddress'] != null
          ? BillAddress.fromJson(json['billingAddress'])
          : null,
      purchaseOrderNumber: json['purchaseOrderNumber'],
      billDate: DateTime.parse(json['billDate'] ?? DateTime.now().toIso8601String()),
      dueDate: DateTime.parse(json['dueDate'] ?? DateTime.now().toIso8601String()),
      paymentTerms: json['paymentTerms'] ?? 'Net 30',
      subject: json['subject'],
      notes: json['notes'],
      termsAndConditions: json['termsAndConditions'],
      items: (json['items'] as List? ?? []).map((i) => BillItem.fromJson(i)).toList(),
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
      amountPaid: (json['amountPaid'] ?? 0).toDouble(),
      amountDue: (json['amountDue'] ?? 0).toDouble(),
      payments: (json['payments'] as List? ?? []).map((p) => BillPayment.fromJson(p)).toList(),
      isRecurring: json['isRecurring'] ?? false,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Bill Item
class BillItem {
  final String itemDetails;
  final String? account;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  BillItem({
    required this.itemDetails,
    this.account,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.discountType,
    required this.amount,
  });

  factory BillItem.fromJson(Map<String, dynamic> json) {
    return BillItem(
      itemDetails: json['itemDetails'] ?? '',
      account: json['account'],
      quantity: (json['quantity'] ?? 0).toDouble(),
      rate: (json['rate'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      discountType: json['discountType'] ?? 'percentage',
      amount: (json['amount'] ?? 0).toDouble(),
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

/// Bill Payment
class BillPayment {
  final String paymentId;
  final double amount;
  final DateTime paymentDate;
  final String paymentMode;
  final String? referenceNumber;
  final String? notes;
  final DateTime recordedAt;

  BillPayment({
    required this.paymentId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMode,
    this.referenceNumber,
    this.notes,
    required this.recordedAt,
  });

  factory BillPayment.fromJson(Map<String, dynamic> json) {
    return BillPayment(
      paymentId: json['paymentId']?.toString() ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      paymentDate: DateTime.parse(json['paymentDate'] ?? DateTime.now().toIso8601String()),
      paymentMode: json['paymentMode'] ?? 'Cash',
      referenceNumber: json['referenceNumber'],
      notes: json['notes'],
      recordedAt: DateTime.parse(json['recordedAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Bill Address
class BillAddress {
  final String? street;
  final String? city;
  final String? state;
  final String? pincode;
  final String? country;

  BillAddress({this.street, this.city, this.state, this.pincode, this.country});

  factory BillAddress.fromJson(Map<String, dynamic> json) {
    return BillAddress(
      street: json['street'],
      city: json['city'],
      state: json['state'],
      pincode: json['pincode'],
      country: json['country'],
    );
  }

  Map<String, dynamic> toJson() => {
    'street': street,
    'city': city,
    'state': state,
    'pincode': pincode,
    'country': country,
  };
}

/// Bill List Response
class BillListResponse {
  final List<Bill> bills;
  final BillPagination pagination;

  BillListResponse({required this.bills, required this.pagination});

  factory BillListResponse.fromJson(Map<String, dynamic> json) {
    return BillListResponse(
      bills: (json['data'] as List? ?? []).map((b) => Bill.fromJson(b)).toList(),
      pagination: BillPagination.fromJson(json['pagination'] ?? {}),
    );
  }
}

/// Pagination
class BillPagination {
  final int total;
  final int page;
  final int limit;
  final int pages;

  BillPagination({required this.total, required this.page, required this.limit, required this.pages});

  factory BillPagination.fromJson(Map<String, dynamic> json) {
    return BillPagination(
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 20,
      pages: json['pages'] ?? 1,
    );
  }
}

/// Bill Statistics
class BillStats {
  final int totalBills;
  final double totalPayable;
  final double totalPaid;
  final double totalDue;
  final Map<String, dynamic> byStatus;

  BillStats({
    required this.totalBills,
    required this.totalPayable,
    required this.totalPaid,
    required this.totalDue,
    required this.byStatus,
  });

  factory BillStats.fromJson(Map<String, dynamic> json) {
    return BillStats(
      totalBills: json['totalBills'] ?? 0,
      totalPayable: (json['totalPayable'] ?? 0).toDouble(),
      totalPaid: (json['totalPaid'] ?? 0).toDouble(),
      totalDue: (json['totalDue'] ?? 0).toDouble(),
      byStatus: json['byStatus'] ?? {},
    );
  }
}

/// Bill Payment Response
class BillPaymentResponse {
  final Bill bill;
  final BillPayment payment;

  BillPaymentResponse({required this.bill, required this.payment});

  factory BillPaymentResponse.fromJson(Map<String, dynamic> json) {
    return BillPaymentResponse(
      bill: Bill.fromJson(json['bill'] ?? {}),
      payment: BillPayment.fromJson(json['payment'] ?? {}),
    );
  }
}

/// Vendor Model
class Vendor {
  final String id;
  final String vendorName;
  final String vendorEmail;
  final String vendorPhone;
  final String? companyName;
  final String? gstNumber;
  final String? panNumber;
  final BillAddress? billingAddress;
  final String paymentTerms;
  final VendorBankDetails? bankDetails;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Vendor({
    required this.id,
    required this.vendorName,
    required this.vendorEmail,
    required this.vendorPhone,
    this.companyName,
    this.gstNumber,
    this.panNumber,
    this.billingAddress,
    required this.paymentTerms,
    this.bankDetails,
    this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    return Vendor(
      id: json['_id'] ?? json['id'] ?? '',
      vendorName: json['vendorName'] ?? '',
      vendorEmail: json['vendorEmail'] ?? '',
      vendorPhone: json['vendorPhone'] ?? '',
      companyName: json['companyName'],
      gstNumber: json['gstNumber'],
      panNumber: json['panNumber'],
      billingAddress: json['billingAddress'] != null
          ? BillAddress.fromJson(json['billingAddress'])
          : null,
      paymentTerms: json['paymentTerms'] ?? 'Net 30',
      bankDetails: json['bankDetails'] != null
          ? VendorBankDetails.fromJson(json['bankDetails'])
          : null,
      notes: json['notes'],
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
    'vendorName': vendorName,
    'vendorEmail': vendorEmail,
    'vendorPhone': vendorPhone,
    'companyName': companyName,
    'gstNumber': gstNumber,
    'panNumber': panNumber,
    'paymentTerms': paymentTerms,
    'notes': notes,
  };
}

/// Vendor Bank Details
class VendorBankDetails {
  final String? accountHolder;
  final String? accountNumber;
  final String? ifscCode;
  final String? bankName;
  final String? upiId;

  VendorBankDetails({
    this.accountHolder,
    this.accountNumber,
    this.ifscCode,
    this.bankName,
    this.upiId,
  });

  factory VendorBankDetails.fromJson(Map<String, dynamic> json) {
    return VendorBankDetails(
      accountHolder: json['accountHolder'],
      accountNumber: json['accountNumber'],
      ifscCode: json['ifscCode'],
      bankName: json['bankName'],
      upiId: json['upiId'],
    );
  }
}

/// Vendor List Response
class VendorListResponse {
  final List<Vendor> vendors;
  final BillPagination pagination;

  VendorListResponse({required this.vendors, required this.pagination});

  factory VendorListResponse.fromJson(Map<String, dynamic> json) {
    return VendorListResponse(
      vendors: (json['data'] as List? ?? []).map((v) => Vendor.fromJson(v)).toList(),
      pagination: BillPagination.fromJson(json['pagination'] ?? {}),
    );
  }
}

/// Recurring Bill Profile
class RecurringBillProfile {
  final String id;
  final String profileName;
  final String vendorId;
  final String vendorName;
  final int repeatEvery;
  final String repeatUnit;
  final DateTime startDate;
  final DateTime? endDate;
  final int? maxOccurrences;
  final int occurrencesCount;
  final String status;
  final DateTime? nextBillDate;
  final DateTime? lastBillDate;
  final List<GeneratedBillRef> generatedBills;
  final DateTime createdAt;

  RecurringBillProfile({
    required this.id,
    required this.profileName,
    required this.vendorId,
    required this.vendorName,
    required this.repeatEvery,
    required this.repeatUnit,
    required this.startDate,
    this.endDate,
    this.maxOccurrences,
    required this.occurrencesCount,
    required this.status,
    this.nextBillDate,
    this.lastBillDate,
    required this.generatedBills,
    required this.createdAt,
  });

  factory RecurringBillProfile.fromJson(Map<String, dynamic> json) {
    return RecurringBillProfile(
      id: json['_id'] ?? json['id'] ?? '',
      profileName: json['profileName'] ?? '',
      vendorId: json['vendorId']?.toString() ?? '',
      vendorName: json['vendorName'] ?? '',
      repeatEvery: json['repeatEvery'] ?? 1,
      repeatUnit: json['repeatUnit'] ?? 'months',
      startDate: DateTime.parse(json['startDate'] ?? DateTime.now().toIso8601String()),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      maxOccurrences: json['maxOccurrences'],
      occurrencesCount: json['occurrencesCount'] ?? 0,
      status: json['status'] ?? 'ACTIVE',
      nextBillDate: json['nextBillDate'] != null ? DateTime.parse(json['nextBillDate']) : null,
      lastBillDate: json['lastBillDate'] != null ? DateTime.parse(json['lastBillDate']) : null,
      generatedBills: (json['generatedBills'] as List? ?? []).map((b) => GeneratedBillRef.fromJson(b)).toList(),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Generated Bill Reference
class GeneratedBillRef {
  final String billId;
  final String billNumber;
  final DateTime createdDate;

  GeneratedBillRef({required this.billId, required this.billNumber, required this.createdDate});

  factory GeneratedBillRef.fromJson(Map<String, dynamic> json) {
    return GeneratedBillRef(
      billId: json['billId']?.toString() ?? '',
      billNumber: json['billNumber'] ?? '',
      createdDate: DateTime.parse(json['createdDate'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Mutable Bill Item (for form)
class MutableBillItem {
  String itemDetails;
  String? account;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  MutableBillItem({
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

  factory MutableBillItem.fromBillItem(BillItem item) {
    return MutableBillItem(
      itemDetails: item.itemDetails,
      account: item.account,
      quantity: item.quantity,
      rate: item.rate,
      discount: item.discount,
      discountType: item.discountType,
      amount: item.amount,
    );
  }
}