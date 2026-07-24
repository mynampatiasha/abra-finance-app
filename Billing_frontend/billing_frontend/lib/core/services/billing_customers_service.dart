// ============================================================================
// BILLING CUSTOMERS SERVICE — ZOHO BOOKS STYLE
// ============================================================================
// File: lib/core/services/billing_customers_service.dart
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../app/config/api_config.dart';
import '../finance_secure_storage.dart';

// ============================================================================
// ALL INDIAN STATES
// ============================================================================
const List<String> kIndianStates = [
  'Andaman and Nicobar Islands',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Ladakh',
  'Lakshadweep',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Puducherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

// All 7 Zoho GST Registration Types
const List<String> kGstRegistrationTypes = [
  'Registered Business - Regular',
  'Registered Business - Composition',
  'Unregistered Business',
  'Consumer',
  'Overseas',
  'Special Economic Zone',
  'Deemed Export',
];

// ============================================================================
// ADDRESS MODEL
// ============================================================================
class CustomerAddress {
  final String attention;
  final String street;
  final String street2;
  final String city;
  final String state;
  final String zip;
  final String country;
  final String phone;
  final String fax;

  const CustomerAddress({
    this.attention = '',
    this.street = '',
    this.street2 = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.country = 'India',
    this.phone = '',
    this.fax = '',
  });

  bool get isEmpty =>
      attention.isEmpty &&
      street.isEmpty &&
      city.isEmpty &&
      state.isEmpty &&
      zip.isEmpty;

  factory CustomerAddress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CustomerAddress();
    return CustomerAddress(
      attention: json['attention'] ?? '',
      street: json['street'] ?? '',
      street2: json['street2'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      zip: json['zip'] ?? '',
      country: json['country'] ?? 'India',
      phone: json['phone'] ?? '',
      fax: json['fax'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'attention': attention,
        'street': street,
        'street2': street2,
        'city': city,
        'state': state,
        'zip': zip,
        'country': country,
        'phone': phone,
        'fax': fax,
      };

  String get formatted {
    final parts = [
      if (attention.isNotEmpty) attention,
      if (street.isNotEmpty) street,
      if (street2.isNotEmpty) street2,
      if (city.isNotEmpty) city,
      if (state.isNotEmpty) state,
      if (zip.isNotEmpty) zip,
      if (country.isNotEmpty) country,
    ];
    return parts.join(', ');
  }

  CustomerAddress copyWith({
    String? attention,
    String? street,
    String? street2,
    String? city,
    String? state,
    String? zip,
    String? country,
    String? phone,
    String? fax,
  }) {
    return CustomerAddress(
      attention: attention ?? this.attention,
      street: street ?? this.street,
      street2: street2 ?? this.street2,
      city: city ?? this.city,
      state: state ?? this.state,
      zip: zip ?? this.zip,
      country: country ?? this.country,
      phone: phone ?? this.phone,
      fax: fax ?? this.fax,
    );
  }
}

// ============================================================================
// CONTACT PERSON MODEL
// ============================================================================
class CustomerContactPerson {
  final String id;
  final String salutation;
  final String firstName;
  final String lastName;
  final String email;
  final String workPhone;
  final String mobile;
  final String designation;
  final String department;
  final bool isPrimary;
  final bool portalAccess;

  const CustomerContactPerson({
    this.id = '',
    this.salutation = '',
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.workPhone = '',
    this.mobile = '',
    this.designation = '',
    this.department = '',
    this.isPrimary = false,
    this.portalAccess = false,
  });

  String get fullName =>
      [salutation, firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  factory CustomerContactPerson.fromJson(Map<String, dynamic> json) {
    return CustomerContactPerson(
      id: json['_id'] ?? '',
      salutation: json['salutation'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      email: json['email'] ?? '',
      workPhone: json['workPhone'] ?? '',
      mobile: json['mobile'] ?? '',
      designation: json['designation'] ?? '',
      department: json['department'] ?? '',
      isPrimary: json['isPrimary'] ?? false,
      portalAccess: json['portalAccess'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'salutation': salutation,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'workPhone': workPhone,
        'mobile': mobile,
        'designation': designation,
        'department': department,
        'isPrimary': isPrimary,
        'portalAccess': portalAccess,
      };

  CustomerContactPerson copyWith({
    String? salutation,
    String? firstName,
    String? lastName,
    String? email,
    String? workPhone,
    String? mobile,
    String? designation,
    String? department,
    bool? isPrimary,
    bool? portalAccess,
  }) {
    return CustomerContactPerson(
      id: id,
      salutation: salutation ?? this.salutation,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      workPhone: workPhone ?? this.workPhone,
      mobile: mobile ?? this.mobile,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      isPrimary: isPrimary ?? this.isPrimary,
      portalAccess: portalAccess ?? this.portalAccess,
    );
  }
}

// ============================================================================
// COMMENT MODEL
// ============================================================================
class CustomerComment {
  final String id;
  final String text;
  final String createdBy;
  final DateTime createdAt;

  const CustomerComment({
    this.id = '',
    this.text = '',
    this.createdBy = '',
    required this.createdAt,
  });

  factory CustomerComment.fromJson(Map<String, dynamic> json) {
    return CustomerComment(
      id: json['_id'] ?? '',
      text: json['text'] ?? '',
      createdBy: json['createdBy'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

// ============================================================================
// MONTHLY INCOME MODEL (for chart)
// ============================================================================
class MonthlyIncome {
  final String month;
  final int year;
  final double total;
  final int count;

  const MonthlyIncome({
    required this.month,
    required this.year,
    required this.total,
    required this.count,
  });

  factory MonthlyIncome.fromJson(Map<String, dynamic> json) {
    return MonthlyIncome(
      month: json['month'] ?? '',
      year: json['year'] ?? 0,
      total: (json['total'] ?? 0).toDouble(),
      count: json['count'] ?? 0,
    );
  }
}

// ============================================================================
// CUSTOMER TRANSACTION MODEL
// ============================================================================
class CustomerTransaction {
  final String type;
  final String id;
  final String number;
  final DateTime date;
  final DateTime? dueDate;
  final String status;
  final double amount;
  final double balance;
  final String method;

  const CustomerTransaction({
    required this.type,
    required this.id,
    required this.number,
    required this.date,
    this.dueDate,
    required this.status,
    required this.amount,
    required this.balance,
    this.method = '',
  });

  factory CustomerTransaction.fromJson(Map<String, dynamic> json) {
    return CustomerTransaction(
      type: json['type'] ?? '',
      id: json['id']?.toString() ?? '',
      number: json['number'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      dueDate:
          json['dueDate'] != null ? DateTime.tryParse(json['dueDate']) : null,
      status: json['status'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(),
      method: json['method'] ?? '',
    );
  }
}

// ============================================================================
// CUSTOMER MAIL MODEL
// ============================================================================
// CUSTOMER MAIL MODEL
// ============================================================================
class CustomerMail {
  final String invoiceNumber;
  final String invoiceId;
  final String customerName;
  final String customerPhone;
  final String sentTo;
  final DateTime sentAt;
  final String
      emailType; // 'invoice' | 'reminder' | 'payment_receipt' | 'whatsapp'
  final String channel; // 'email' | 'whatsapp'
  final String subject;
  final double amount;
  final double amountDue;
  final bool success;
  final String? failReason;
  final String? reminderType; // 'overdue' | 'predue' | null

  const CustomerMail({
    required this.invoiceNumber,
    required this.invoiceId,
    this.customerName = '',
    this.customerPhone = '',
    required this.sentTo,
    required this.sentAt,
    required this.emailType,
    this.channel = 'email',
    required this.subject,
    required this.amount,
    this.amountDue = 0,
    this.success = true,
    this.failReason,
    this.reminderType,
  });

  factory CustomerMail.fromJson(Map<String, dynamic> json) {
    return CustomerMail(
      invoiceNumber: json['invoiceNumber'] ?? '',
      invoiceId: json['invoiceId']?.toString() ?? '',
      customerName: json['customerName'] ?? '',
      customerPhone: json['customerPhone'] ?? '',
      sentTo: json['sentTo'] ?? '',
      sentAt:
          (DateTime.tryParse(json['sentAt'] ?? '') ?? DateTime.now()).toLocal(),
      emailType: json['emailType'] ?? 'invoice',
      channel: json['channel'] ?? 'email',
      subject: json['subject'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      amountDue: (json['amountDue'] ?? 0).toDouble(),
      success: json['success'] != false,
      failReason: json['failReason'],
      reminderType: json['reminderType'],
    );
  }
}

// ============================================================================
// STATEMENT ENTRY MODEL
// ============================================================================
class StatementEntry {
  final DateTime date;
  final String type;
  final String number;
  final String details;
  final double? invoices;
  final double? payments;
  final double balance;

  const StatementEntry({
    required this.date,
    required this.type,
    required this.number,
    required this.details,
    this.invoices,
    this.payments,
    required this.balance,
  });

  factory StatementEntry.fromJson(Map<String, dynamic> json) {
    return StatementEntry(
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      type: json['type'] ?? '',
      number: json['number'] ?? '',
      details: json['details'] ?? '',
      invoices: json['invoices'] != null
          ? (json['invoices'] as num).toDouble()
          : null,
      payments: json['payments'] != null
          ? (json['payments'] as num).toDouble()
          : null,
      balance: (json['balance'] ?? 0).toDouble(),
    );
  }
}

// ============================================================================
// MAIN BILLING CUSTOMER MODEL
// ============================================================================
class BillingCustomer {
  final String id;
  final String customerId;
  // Basic
  final String customerType;
  final String salutation;
  final String firstName;
  final String lastName;
  final String customerDisplayName;
  final String companyName;
  // Contact
  final String primaryEmail;
  final String primaryPhone;
  final String workPhone;
  final String mobile;
  final String website;
  final String facebook;
  final String twitter;
  // Address
  final CustomerAddress billingAddress;
  final CustomerAddress shippingAddress;
  // Tax
  final String gstNumber;
  final String gstRegistrationType;
  final String placeOfSupply;
  final String panNumber;
  final String taxPreference;
  final String exemptionReason;
  // Financial
  final String defaultCurrency;
  final double openingBalance;
  final String paymentTerms;
  final double creditLimit;
  // Portal
  final String portalLanguage;
  final bool portalEnabled;
  // Contact persons
  final List<CustomerContactPerson> contactPersons;
  // Remarks / comments
  final String remarks;
  final List<CustomerComment> comments;
  // Status
  final String customerStatus;
  final String customerTier;
  final String salesTerritory;
  final List<String> tags;
  // Dates
  final DateTime createdDate;
  final DateTime? lastModifiedDate;
  // Stats
  final double totalRevenueGenerated;
  final int totalTripsCompleted;
  final double outstandingReceivables;
  final double unusedCredits;

  const BillingCustomer({
    required this.id,
    required this.customerId,
    this.customerType = 'Individual',
    this.salutation = '',
    this.firstName = '',
    this.lastName = '',
    required this.customerDisplayName,
    this.companyName = '',
    required this.primaryEmail,
    required this.primaryPhone,
    this.workPhone = '',
    this.mobile = '',
    this.website = '',
    this.facebook = '',
    this.twitter = '',
    this.billingAddress = const CustomerAddress(),
    this.shippingAddress = const CustomerAddress(),
    this.gstNumber = '',
    this.gstRegistrationType = '',
    this.placeOfSupply = '',
    this.panNumber = '',
    this.taxPreference = 'Taxable',
    this.exemptionReason = '',
    this.defaultCurrency = 'INR',
    this.openingBalance = 0,
    this.paymentTerms = 'Due on Receipt',
    this.creditLimit = 0,
    this.portalLanguage = 'English',
    this.portalEnabled = false,
    this.contactPersons = const [],
    this.remarks = '',
    this.comments = const [],
    this.customerStatus = 'Active',
    this.customerTier = '',
    this.salesTerritory = '',
    this.tags = const [],
    required this.createdDate,
    this.lastModifiedDate,
    this.totalRevenueGenerated = 0,
    this.totalTripsCompleted = 0,
    this.outstandingReceivables = 0,
    this.unusedCredits = 0,
  });

  // Compatibility getters
  String get customerName => customerDisplayName;
  String get customerEmail => primaryEmail;
  String get customerPhone => primaryPhone;
  bool get isActive => customerStatus == 'Active';

  factory BillingCustomer.fromJson(Map<String, dynamic> json) {
    return BillingCustomer(
      id: json['_id'] ?? json['id'] ?? '',
      customerId: json['customerId'] ?? '',
      customerType: json['customerType'] ?? 'Individual',
      salutation: json['salutation'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      customerDisplayName:
          json['customerDisplayName'] ?? json['primaryContactPerson'] ?? '',
      companyName: json['companyName'] ?? json['customerDisplayName'] ?? '',
      primaryEmail: json['primaryEmail'] ?? json['email'] ?? '',
      primaryPhone: json['primaryPhone'] ?? json['phone'] ?? '',
      workPhone: json['workPhone'] ?? '',
      mobile: json['mobile'] ?? '',
      website: json['website'] ?? '',
      facebook: json['facebook'] ?? '',
      twitter: json['twitter'] ?? '',
      billingAddress: CustomerAddress.fromJson(json['billingAddress'] is Map
          ? Map<String, dynamic>.from(json['billingAddress'])
          : null),
      shippingAddress: CustomerAddress.fromJson(json['shippingAddress'] is Map
          ? Map<String, dynamic>.from(json['shippingAddress'])
          : null),
      gstNumber: json['gstNumber'] ?? '',
      gstRegistrationType:
          json['gstRegistrationType'] ?? json['taxRegistrationType'] ?? '',
      placeOfSupply: json['placeOfSupply'] ?? json['state'] ?? '',
      panNumber: json['panNumber'] ?? '',
      taxPreference: json['taxPreference'] ?? 'Taxable',
      exemptionReason: json['exemptionReason'] ?? '',
      defaultCurrency: json['defaultCurrency'] ?? 'INR',
      openingBalance: (json['openingBalance'] ?? 0).toDouble(),
      paymentTerms: json['paymentTerms'] ?? 'Due on Receipt',
      creditLimit: (json['creditLimit'] ?? 0).toDouble(),
      portalLanguage: json['portalLanguage'] ?? 'English',
      portalEnabled: json['portalEnabled'] ?? false,
      contactPersons: (json['contactPersons'] as List? ?? [])
          .map((c) => CustomerContactPerson.fromJson(c))
          .toList(),
      remarks: json['remarks'] ?? json['internalNotes'] ?? '',
      comments: (json['comments'] as List? ?? [])
          .map((c) => CustomerComment.fromJson(c))
          .toList(),
      customerStatus: json['customerStatus'] ?? 'Active',
      customerTier: json['customerTier'] ?? '',
      salesTerritory: json['salesTerritory'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      createdDate:
          DateTime.tryParse(json['createdDate'] ?? json['createdAt'] ?? '') ??
              DateTime.now(),
      lastModifiedDate: json['lastModifiedDate'] != null
          ? DateTime.tryParse(json['lastModifiedDate'])
          : null,
      totalRevenueGenerated: (json['totalRevenueGenerated'] ?? 0).toDouble(),
      totalTripsCompleted: json['totalTripsCompleted'] ?? 0,
      outstandingReceivables: (json['outstandingReceivables'] ?? 0).toDouble(),
      unusedCredits: (json['unusedCredits'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'customerType': customerType,
        'salutation': salutation,
        'firstName': firstName,
        'lastName': lastName,
        'customerDisplayName': customerDisplayName,
        'companyName': companyName,
        'primaryEmail': primaryEmail,
        'primaryPhone': primaryPhone,
        'workPhone': workPhone,
        'mobile': mobile,
        'website': website,
        'facebook': facebook,
        'twitter': twitter,
        'billingAddress': billingAddress.toJson(),
        'shippingAddress': shippingAddress.toJson(),
        'gstNumber': gstNumber,
        'gstRegistrationType': gstRegistrationType,
        'placeOfSupply': placeOfSupply,
        'panNumber': panNumber,
        'taxPreference': taxPreference,
        'exemptionReason': exemptionReason,
        'defaultCurrency': defaultCurrency,
        'openingBalance': openingBalance,
        'paymentTerms': paymentTerms,
        'creditLimit': creditLimit,
        'portalLanguage': portalLanguage,
        'portalEnabled': portalEnabled,
        'contactPersons': contactPersons.map((c) => c.toJson()).toList(),
        'remarks': remarks,
        'customerStatus': customerStatus,
        'customerTier': customerTier,
        'salesTerritory': salesTerritory,
        'tags': tags,
      };
}

// ============================================================================
// RESPONSE MODELS
// ============================================================================
class BillingCustomerListResponse {
  final List<BillingCustomer> customers;
  final int totalCount;
  final int currentPage;
  final int totalPages;

  const BillingCustomerListResponse({
    required this.customers,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
  });

  factory BillingCustomerListResponse.fromJson(Map<String, dynamic> json) {
    final data =
        json['data'] is Map ? json['data'] as Map : <String, dynamic>{};
    final pagination = data['pagination'] is Map
        ? data['pagination'] as Map
        : <String, dynamic>{};
    final rawList = data['customers'] is List ? data['customers'] as List : [];
    return BillingCustomerListResponse(
      customers: rawList
          .whereType<Map>()
          .map((c) => BillingCustomer.fromJson(Map<String, dynamic>.from(c)))
          .toList(),
      totalCount: pagination['totalCount'] ?? rawList.length,
      currentPage: pagination['currentPage'] ?? 1,
      totalPages: pagination['totalPages'] ?? 1,
    );
  }
}

class CustomerOverviewData {
  final BillingCustomer customer;
  final double outstandingReceivables;
  final double unusedCredits;
  final String currency;
  final List<MonthlyIncome> monthlyIncome;

  const CustomerOverviewData({
    required this.customer,
    required this.outstandingReceivables,
    required this.unusedCredits,
    required this.currency,
    required this.monthlyIncome,
  });

  factory CustomerOverviewData.fromJson(Map<String, dynamic> json) {
    final r = json['receivables'] ?? {};
    return CustomerOverviewData(
      customer: BillingCustomer.fromJson(json['customer'] ?? {}),
      outstandingReceivables: (r['outstandingReceivables'] ?? 0).toDouble(),
      unusedCredits: (r['unusedCredits'] ?? 0).toDouble(),
      currency: r['currency'] ?? 'INR',
      monthlyIncome: (json['monthlyIncome'] as List? ?? [])
          .map((m) => MonthlyIncome.fromJson(m))
          .toList(),
    );
  }
}

class CustomerStatementData {
  final String customerName;
  final String customerEmail;
  final double openingBalance;
  final double closingBalance;
  final List<StatementEntry> entries;
  final DateTime fromDate;
  final DateTime toDate;

  const CustomerStatementData({
    required this.customerName,
    required this.customerEmail,
    required this.openingBalance,
    required this.closingBalance,
    required this.entries,
    required this.fromDate,
    required this.toDate,
  });

  factory CustomerStatementData.fromJson(Map<String, dynamic> json) {
    final c = json['customer'] ?? {};
    return CustomerStatementData(
      customerName: c['name'] ?? '',
      customerEmail: c['email'] ?? '',
      openingBalance: (json['openingBalance'] ?? 0).toDouble(),
      closingBalance: (json['closingBalance'] ?? 0).toDouble(),
      entries: (json['entries'] as List? ?? [])
          .map((e) => StatementEntry.fromJson(e))
          .toList(),
      fromDate: DateTime.tryParse(json['fromDate'] ?? '') ??
          DateTime.now().subtract(const Duration(days: 365)),
      toDate: DateTime.tryParse(json['toDate'] ?? '') ?? DateTime.now(),
    );
  }
}

// ============================================================================
// SERVICE
// ============================================================================
class BillingCustomersService {
  static String get _baseUrl => ApiConfig.baseUrl;
  static const String _apiPath = '/api/finance/customers';
  static String get _endpoint => '$_baseUrl$_apiPath';

  static Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, String>> _getHeaders(
      {bool isMultipart = false}) async {
    final token = await _getAuthToken();
    final branchHdr = await FinanceSecureStorage.getBranchHeader();
    final headers = <String, String>{'Accept': 'application/json'};
    if (!isMultipart) headers['Content-Type'] = 'application/json';
    if (token != null && token.isNotEmpty)
      headers['Authorization'] = 'Bearer $token';
    headers['x-branch-ids'] = branchHdr;
    return headers;
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return json.decode(response.body);
      } catch (_) {
        return {'success': true};
      }
    }
    try {
      final err = json.decode(response.body);
      throw BillingCustomersException(
        message: err['message'] ?? err['error'] ?? 'Request failed',
        statusCode: response.statusCode,
      );
    } catch (e) {
      if (e is BillingCustomersException) rethrow;
      throw BillingCustomersException(
          message: 'Request failed (${response.statusCode})',
          statusCode: response.statusCode);
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  static Future<BillingCustomerListResponse> getAllCustomers({
    String? customerType,
    String? customerStatus,
    String? search,
    int page = 1,
    int limit = 100,
    String sortBy = 'createdDate',
    String sortOrder = 'desc',
    bool skipStats = false,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      if (skipStats) 'skipStats': 'true',
      if (customerType != null) 'customerType': customerType,
      if (customerStatus != null) 'customerStatus': customerStatus,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri = Uri.parse(_endpoint).replace(queryParameters: params);
    final headers = await _getHeaders();
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 60));
    final result = _handleResponse(response);
    return BillingCustomerListResponse.fromJson(result);
  }

  static Future<BillingCustomer> getCustomerById(String customerId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(Uri.parse('$_endpoint/$customerId'), headers: headers)
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return BillingCustomer.fromJson(result['data']);
  }

  static Future<BillingCustomer> createCustomer(
      Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final response = await http
        .post(Uri.parse(_endpoint), headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return BillingCustomer.fromJson(result['data']);
  }

  static Future<BillingCustomer> updateCustomer(
      String customerId, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final response = await http
        .put(Uri.parse('$_endpoint/$customerId'),
            headers: headers, body: json.encode(data))
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return BillingCustomer.fromJson(result['data']);
  }

  static Future<void> deleteCustomer(String customerId) async {
    final headers = await _getHeaders();
    final response = await http
        .delete(Uri.parse('$_endpoint/$customerId'), headers: headers)
        .timeout(const Duration(seconds: 30));
    _handleResponse(response);
  }

  // ── Detail tabs ───────────────────────────────────────────────────────────

  static Future<CustomerOverviewData> getCustomerOverview(
      String customerId, {int months = 6}) async {
    final headers = await _getHeaders();
    final response = await http
        .get(Uri.parse('$_endpoint/$customerId/overview?months=$months'), headers: headers)
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return CustomerOverviewData.fromJson(result['data']);
  }

  static Future<List<CustomerTransaction>> getCustomerTransactions(
      String customerId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(Uri.parse('$_endpoint/$customerId/transactions'), headers: headers)
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return (result['data'] as List? ?? [])
        .map((t) => CustomerTransaction.fromJson(t))
        .toList();
  }

  static Future<List<CustomerMail>> getCustomerMails(String customerId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(Uri.parse('$_endpoint/$customerId/mails'), headers: headers)
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return (result['data'] as List? ?? [])
        .map((m) => CustomerMail.fromJson(m))
        .toList();
  }

  static Future<CustomerStatementData> getCustomerStatement(String customerId,
      {DateTime? fromDate, DateTime? toDate}) async {
    final params = <String, String>{
      if (fromDate != null) 'fromDate': fromDate.toIso8601String(),
      if (toDate != null) 'toDate': toDate.toIso8601String(),
    };
    final uri = Uri.parse('$_endpoint/$customerId/statement')
        .replace(queryParameters: params);
    final headers = await _getHeaders();
    final response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return CustomerStatementData.fromJson(result['data']);
  }

  static Future<CustomerComment> addComment(
      String customerId, String text) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$_endpoint/$customerId/comments'),
          headers: headers,
          body: json.encode({'text': text}),
        )
        .timeout(const Duration(seconds: 30));
    final result = _handleResponse(response);
    return CustomerComment.fromJson(result['data']);
  }

  static Future<void> deleteComment(String customerId, String commentId) async {
    final headers = await _getHeaders();
    final response = await http
        .delete(
          Uri.parse('$_endpoint/$customerId/comments/$commentId'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 30));
    _handleResponse(response);
  }

  // ── Documents ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadDocuments(
      String customerId, String category, List<PlatformFile> files) async {
    final uri = Uri.parse('$_endpoint/$customerId/upload-documents');
    final headers = await _getHeaders(isMultipart: true);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields['category'] = category;

    for (final file in files) {
      if (kIsWeb && file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('documents', file.bytes!,
            filename: file.name));
      } else if (!kIsWeb && file.path != null) {
        request.files.add(await http.MultipartFile.fromPath(
            'documents', file.path!,
            filename: file.name));
      }
    }

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response);
  }

  // ── Bulk import ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> bulkImportCustomers(
      List<Map<String, dynamic>> customers) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$_endpoint/bulk-import'),
          headers: headers,
          body: json.encode({'customers': customers}),
        )
        .timeout(const Duration(seconds: 60));
    return _handleResponse(response);
  }

  // ── Legacy compat ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAllCustomersRaw({
    String? search,
    int page = 1,
    int limit = 100,
    String sortBy = 'createdDate',
    String sortOrder = 'desc',
    bool skipStats = false,
  }) async {
    final resp = await getAllCustomers(
        search: search,
        page: page,
        limit: limit,
        sortBy: sortBy,
        sortOrder: sortOrder,
        skipStats: skipStats);
    return {
      'success': true,
      'data': {
        'customers': resp.customers.map((c) => c.toJson()).toList(),
        'pagination': {
          'totalCount': resp.totalCount,
          'currentPage': resp.currentPage,
          'totalPages': resp.totalPages,
        },
      },
    };
  }

  static Future<Map<String, dynamic>> getCustomerByIdRaw(String id) async {
    final c = await getCustomerById(id);
    return {'success': true, 'data': c.toJson()};
  }

  static Future<Map<String, dynamic>> createCustomerRaw(
      Map<String, dynamic> data) async {
    final c = await createCustomer(data);
    return {'success': true, 'data': c.toJson()};
  }

  static Future<Map<String, dynamic>> updateCustomerRaw(
      String id, Map<String, dynamic> data) async {
    final c = await updateCustomer(id, data);
    return {'success': true, 'data': c.toJson()};
  }

  static Future<Map<String, dynamic>> deleteCustomerRaw(String id) async {
    await deleteCustomer(id);
    return {'success': true};
  }

  // Keep legacy buildCustomerDataFromControllers for new_customer.dart
  static Map<String, dynamic> buildCustomerDataFromControllers({
    required String customerType,
    required String customerDisplayName,
    required String primaryEmail,
    required String primaryPhone,
    String salesTerritory = '',
    String salutation = '',
    String firstName = '',
    String lastName = '',
    String companyName = '',
    String workPhone = '',
    String mobile = '',
    String website = '',
    String facebook = '',
    String twitter = '',
    CustomerAddress? billingAddress,
    CustomerAddress? shippingAddress,
    String gstNumber = '',
    String gstRegistrationType = '',
    String placeOfSupply = '',
    String panNumber = '',
    String taxPreference = 'Taxable',
    String exemptionReason = '',
    String defaultCurrency = 'INR',
    double openingBalance = 0,
    String paymentTerms = 'Due on Receipt',
    String? creditLimitInput,
    double creditLimit = 0,
    String portalLanguage = 'English',
    List<Map<String, dynamic>>? contactPersons,
    String remarks = '',
    String customerStatus = 'Active',
    String? customerTier,
    List<String>? tags,
    // Legacy fields kept for backward compat
    String? primaryContactPerson,
    String? alternatePhone,
    String addressLine1 = '',
    String addressLine2 = '',
    String city = '',
    String state = '',
    String postalCode = '',
    String country = 'India',
    String? panNumberLegacy,
    String? gstNumberLegacy,
    String? taxRegistrationType,
    String paymentTermsLegacy = '',
    String billingFrequency = 'Per-trip',
    String? vendorCommissionType,
    String? commissionRate,
    String? fixedAmountPerTrip,
    String? revenueShare,
    String? minimumGuarantee,
    String? paymentCycle,
    List<String>? vehicleTypesProvided,
    String? numberOfVehiclesProvided,
    String? preferredPaymentMethod,
    String? creditLimitStr,
    String? securityDeposit,
    String? securityDepositStatus,
    String? billingEmail,
    String? billingAddressStr,
    String? billingAddress_str,
    bool sameAsPrimaryAddress = true,
    String reasonForBlocking = '',
    String? vendorVehiclesAvailable,
    List<String>? vendorVehicleTypes,
    String? vendorAgreementStart,
    String? vendorAgreementEnd,
    double vendorPerformanceRating = 0,
    String? insuranceValidUntil,
    String? bankName,
    String? bankAccountNumber,
    String? ifscCode,
    String? accountHolderName,
    String? branchName,
    String? upiId,
    String? internalNotes,
    String? customerInstructions,
    String? specialRequirements,
    List<Map<String, dynamic>>? customFields,
    List<Map<String, dynamic>>? contactPersonsLegacy,
    String? rateCard,
    String? contractType,
    String? contractStartDate,
    String? contractEndDate,
    bool autoRenewal = false,
    String? renewalNoticePeriod,
    String? employeeStrength,
    String? annualContractValue,
    String? companyRegistration,
    String? industryType,
    String? tanNumber,
    String? customerTierLegacy,
    bool blockBookingIfCreditExceeded = false,
    bool poNumberRequired = false,
    List<String>? invoiceDeliveryMethods,
    String invoiceLanguage = 'English',
  }) {
    final billingAddr = billingAddress?.toJson() ??
        {
          'street': addressLine1,
          'city': city,
          'state': state,
          'zip': postalCode,
          'country': country,
        };
    final shippingAddr =
        shippingAddress?.toJson() ?? (sameAsPrimaryAddress ? billingAddr : {});

    return {
      'customerType': customerType,
      'salutation': salutation,
      'firstName': firstName,
      'lastName': lastName,
      'customerDisplayName': customerDisplayName,
      'companyName': companyName.isNotEmpty ? companyName : customerDisplayName,
      'primaryEmail': primaryEmail,
      'primaryPhone': primaryPhone,
      'workPhone': workPhone,
      'mobile': mobile,
      'website': website,
      'facebook': facebook,
      'twitter': twitter,
      'billingAddress': billingAddr,
      'shippingAddress': shippingAddr,
      'gstNumber': gstNumber.isNotEmpty ? gstNumber : (gstNumberLegacy ?? ''),
      'gstRegistrationType': gstRegistrationType.isNotEmpty
          ? gstRegistrationType
          : (taxRegistrationType ?? ''),
      'placeOfSupply': placeOfSupply,
      'panNumber': panNumber.isNotEmpty ? panNumber : (panNumberLegacy ?? ''),
      'taxPreference': taxPreference,
      'exemptionReason': exemptionReason,
      'defaultCurrency': defaultCurrency,
      'openingBalance': openingBalance,
      'paymentTerms':
          paymentTerms.isNotEmpty ? paymentTerms : paymentTermsLegacy,
      'creditLimit': creditLimitInput != null
          ? (double.tryParse(creditLimitInput) ?? 0)
          : (creditLimit > 0
              ? creditLimit
              : (double.tryParse(creditLimitStr ?? '') ?? 0)),
      'portalLanguage': portalLanguage,
      'contactPersons': contactPersons ?? contactPersonsLegacy ?? [],
      'remarks': remarks.isNotEmpty ? remarks : (internalNotes ?? ''),
      'customerStatus': customerStatus,
      'customerTier': (customerTier != null && customerTier.isNotEmpty)
          ? customerTier
          : (customerTierLegacy ?? ''),
      'salesTerritory': salesTerritory,
      'tags': tags ?? [],
      // Legacy fields
      'primaryContactPerson': primaryContactPerson ?? firstName,
      'alternatePhone': alternatePhone ?? '',
      'addressLine1': addressLine1.isNotEmpty
          ? addressLine1
          : (billingAddress?.street ?? ''),
      'addressLine2': addressLine2,
      'city': city.isNotEmpty ? city : (billingAddress?.city ?? ''),
      'state': state.isNotEmpty ? state : (billingAddress?.state ?? ''),
      'postalCode':
          postalCode.isNotEmpty ? postalCode : (billingAddress?.zip ?? ''),
      'country': country,
      'billingEmail': billingEmail ?? primaryEmail,
      'sameAsPrimaryAddress': sameAsPrimaryAddress,
      'billingFrequency': billingFrequency,
      'vendorCommissionType': vendorCommissionType,
      'paymentCycle': paymentCycle,
      'preferredPaymentMethod': preferredPaymentMethod,
      'securityDepositStatus': securityDepositStatus,
      'bankName': bankName,
      'bankAccountNumber': bankAccountNumber,
      'ifscCode': ifscCode,
      'accountHolderName': accountHolderName,
      'branchName': branchName,
      'upiId': upiId,
      'internalNotes': internalNotes ?? remarks,
      'customerInstructions': customerInstructions,
      'specialRequirements': specialRequirements,
      'customFields': customFields ?? [],
      'poNumberRequired': poNumberRequired,
      'invoiceDeliveryMethods': invoiceDeliveryMethods ?? [],
      'invoiceLanguage': invoiceLanguage,
      'autoRenewal': autoRenewal,
      'blockBookingIfCreditExceeded': blockBookingIfCreditExceeded,
      if (commissionRate != null && commissionRate.isNotEmpty)
        'commissionRate': double.tryParse(commissionRate),
      if (fixedAmountPerTrip != null && fixedAmountPerTrip.isNotEmpty)
        'fixedAmountPerTrip': double.tryParse(fixedAmountPerTrip),
      if (revenueShare != null && revenueShare.isNotEmpty)
        'revenueShare': double.tryParse(revenueShare),
      if (minimumGuarantee != null && minimumGuarantee.isNotEmpty)
        'minimumGuarantee': double.tryParse(minimumGuarantee),
      if (numberOfVehiclesProvided != null &&
          numberOfVehiclesProvided.isNotEmpty)
        'numberOfVehiclesProvided': int.tryParse(numberOfVehiclesProvided),
      if (securityDeposit != null && securityDeposit.isNotEmpty)
        'securityDeposit': double.tryParse(securityDeposit),
      if (employeeStrength != null && employeeStrength.isNotEmpty)
        'employeeStrength': int.tryParse(employeeStrength),
      if (annualContractValue != null && annualContractValue.isNotEmpty)
        'annualContractValue': double.tryParse(annualContractValue),
      if (vehicleTypesProvided != null)
        'vehicleTypesProvided': vehicleTypesProvided,
      if (vendorVehicleTypes != null) 'vendorVehicleTypes': vendorVehicleTypes,
      if (rateCard != null) 'rateCard': rateCard,
      if (contractType != null) 'contractType': contractType,
      if (companyRegistration != null)
        'companyRegistration': companyRegistration,
      if (industryType != null) 'industryType': industryType,
      if (tanNumber != null) 'tanNumber': tanNumber,
    };
  }

  static String? validateCustomerData(Map<String, dynamic> data) {
    if ((data['customerDisplayName'] ?? '').toString().isEmpty)
      return 'Customer name is required';
    if ((data['primaryEmail'] ?? '').toString().isEmpty)
      return 'Primary email is required';
    if ((data['primaryPhone'] ?? '').toString().isEmpty)
      return 'Primary phone is required';

    if (data['customerStatus'] == 'Blocked' &&
        (data['reasonForBlocking'] ?? '').toString().isEmpty)
      return 'Reason for blocking is required';
    return null;
  }
}

// ============================================================================
// EXCEPTION
// ============================================================================
class BillingCustomersException implements Exception {
  final String message;
  final int statusCode;

  BillingCustomersException({required this.message, required this.statusCode});

  @override
  String toString() => 'BillingCustomersException: $message ($statusCode)';

  String toUserMessage() {
    switch (statusCode) {
      case 401:
        return 'Authentication failed. Please login again.';
      case 403:
        return 'You do not have permission to perform this action.';
      case 404:
        return 'Customer not found.';
      case 408:
        return 'Request timed out. Please check your connection.';
      case 409:
        return 'A customer with this information already exists.';
      default:
        return statusCode >= 500
            ? 'Server error. Please try again later.'
            : message;
    }
  }
}

