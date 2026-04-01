// ============================================================================
// INVOICE SERVICE - COMPLETE WITH PAYMENT ACCOUNT SUPPORT
// ============================================================================
// File: lib/core/services/invoice_service.dart
// NEW FEATURES:
// ✅ Get payment accounts (bank accounts, UPI, fuel cards, etc.)
// ✅ Support for selectedPaymentAccount in invoice creation
// ✅ All existing invoice features preserved
// ============================================================================

import 'dart:convert';
import '../../core/services/api_service.dart';

class InvoiceService {
  static final ApiService _api = ApiService();
  
  static const String _baseEndpoint = '/api/finance/invoices';
static const String _accountsEndpoint = '/api/finance/banking';
  
  // ============================================================================
  // ✅ NEW: PAYMENT ACCOUNT METHODS
  // ============================================================================
  

/// Get all unbilled billable expenses for a customer
static Future<List<BillableExpense>> getBillableExpenses(String customerName) async {
  try {
    print('📤 GET: /api/finance/expenses/billable/$customerName');
    final data = await _api.get('/api/finance/expenses/billable/$customerName');
    final expenses = (data['data'] as List)
        .map((e) => BillableExpense.fromJson(e))
        .toList();
    print('✅ Billable expenses fetched: ${expenses.length}');
    return expenses;
  } catch (e) {
    print('❌ Error fetching billable expenses: $e');
    return [];
  }
}

  /// Get all active payment accounts for invoice payment selection
  static Future<List<PaymentAccount>> getPaymentAccounts() async {
    try {
      print('📤 GET: $_accountsEndpoint?isActive=true');
      
      final data = await _api.get(_accountsEndpoint, queryParams: {'isActive': 'true'});
      
      // Backend returns { success: true, count: N, data: [...] }
      final List<dynamic> accountsList = (data['data'] is List) 
          ? data['data'] as List<dynamic>
          : (data['data'] as Map<String, dynamic>?)?['accounts'] ?? [];
      
      final accounts = accountsList
          .map((account) => PaymentAccount.fromJson(account))
          .toList();
      
      print('✅ Payment accounts fetched: ${accounts.length}');
      
      return accounts;
    } catch (e) {
      print('❌ Error fetching payment accounts: $e');
      rethrow;
    }
  }
  
  /// Get single payment account by ID
  static Future<PaymentAccount> getPaymentAccount(String accountId) async {
    try {
      print('📤 GET: $_accountsEndpoint/$accountId');
      
      final data = await _api.get('$_accountsEndpoint/$accountId');
      
      print('✅ Payment account fetched');
      
      return PaymentAccount.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching payment account: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // INVOICE METHODS (EXISTING - PRESERVED)
  // ============================================================================
  
  /// Get all invoices with optional filters
  static Future<InvoiceListResponse> getInvoices({
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
      
      if (status != null) queryParams['status'] = status;
      if (customerId != null) queryParams['customerId'] = customerId;
      if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();
      
      print('📤 GET: $_baseEndpoint with filters: $queryParams');
      
      final data = await _api.get(_baseEndpoint, queryParams: queryParams);
      
      print('✅ Invoices fetched: ${data['data'].length}');
      
      return InvoiceListResponse.fromJson(data);
    } catch (e) {
      print('❌ Error fetching invoices: $e');
      rethrow;
    }
  }
  
  /// Get invoice statistics
  static Future<InvoiceStats> getStats() async {
    try {
      print('📤 GET: $_baseEndpoint/stats');
      
      final data = await _api.get('$_baseEndpoint/stats');
      
      print('✅ Stats fetched');
      
      return InvoiceStats.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching stats: $e');
      rethrow;
    }
  }
  
  /// Get single invoice by ID
  static Future<Invoice> getInvoice(String invoiceId) async {
    try {
      print('📤 GET: $_baseEndpoint/$invoiceId');
      
      final data = await _api.get('$_baseEndpoint/$invoiceId');
      
      print('✅ Invoice fetched: ${data['data']['invoiceNumber']}');
      
      return Invoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching invoice: $e');
      rethrow;
    }
  }
  
  /// Create new invoice
  static Future<Invoice> createInvoice(Map<String, dynamic> invoiceData) async {
    try {
      print('📤 POST: $_baseEndpoint');
      print('📦 Data: ${json.encode(invoiceData)}');
      
      final data = await _api.post(_baseEndpoint, body: invoiceData);
      
      print('✅ Invoice created: ${data['data']['invoiceNumber']}');
      
      return Invoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating invoice: $e');
      rethrow;
    }
  }
  
  /// Update existing invoice
  static Future<Invoice> updateInvoice(String invoiceId, Map<String, dynamic> invoiceData) async {
    try {
      print('📤 PUT: $_baseEndpoint/$invoiceId');
      print('📦 Data: ${json.encode(invoiceData)}');
      
      final data = await _api.put('$_baseEndpoint/$invoiceId', body: invoiceData);
      
      print('✅ Invoice updated: ${data['data']['invoiceNumber']}');
      
      return Invoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error updating invoice: $e');
      rethrow;
    }
  }
  
  /// Send invoice via email
  static Future<Invoice> sendInvoice(String invoiceId) async {
    try {
      print('📤 POST: $_baseEndpoint/$invoiceId/send');
      
      final data = await _api.post('$_baseEndpoint/$invoiceId/send');
      
      print('✅ Invoice sent: ${data['data']['invoiceNumber']}');
      
      return Invoice.fromJson(data['data']);
    } catch (e) {
      print('❌ Error sending invoice: $e');
      rethrow;
    }
  }
  
  /// Record payment for invoice
  static Future<PaymentResponse> recordPayment(
    String invoiceId,
    Map<String, dynamic> paymentData,
  ) async {
    try {
      print('📤 POST: $_baseEndpoint/$invoiceId/payment');
      print('📦 Payment: ${json.encode(paymentData)}');
      
      final data = await _api.post('$_baseEndpoint/$invoiceId/payment', body: paymentData);
      
      print('✅ Payment recorded: ₹${paymentData['amount']}');
      
      return PaymentResponse.fromJson(data['data']);
    } catch (e) {
      print('❌ Error recording payment: $e');
      rethrow;
    }
  }
  
  /// Download invoice PDF
static Future<String> downloadPDF(String invoiceId) async {
  try {
    print('📤 GET: $_baseEndpoint/$invoiceId/pdf (PDF download)');

    final headers = await _api.getHeaders();
    final token = headers['Authorization']?.replaceFirst('Bearer ', '') ?? '';
    final url = '${_api.baseUrl}$_baseEndpoint/$invoiceId/pdf?token=$token';

    print('✅ PDF URL: $url');
    return url;
  } catch (e) {
    print('❌ Error getting PDF URL: $e');
    rethrow;
  }
}
  /// Delete invoice (only drafts)
  static Future<void> deleteInvoice(String invoiceId) async {
    try {
      print('📤 DELETE: $_baseEndpoint/$invoiceId');
      
      await _api.delete('$_baseEndpoint/$invoiceId');
      
      print('✅ Invoice deleted');
    } catch (e) {
      print('❌ Error deleting invoice: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // BILLING CUSTOMERS MANAGEMENT
  // ============================================================================
  
  /// Get all billing customers with optional search and pagination
static Future<BillingCustomerListResponse> getBillingCustomers({
  String? search,
  int page = 1,
  int limit = 1000,
  bool activeOnly = false,  // ← changed to false so all customers show
}) async {
  try {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      'sortBy': 'createdDate',
      'sortOrder': 'desc',
    };

    if (activeOnly) {
      queryParams['customerStatus'] = 'Active';
    }

    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    print('📤 GET: /api/finance/customers with search: $search');

    // ← FIXED: correct endpoint matching your backend registration
    final data = await _api.get('/api/finance/customers', queryParams: queryParams);

    final count = data['data']?['customers']?.length ?? 0;
    print('✅ Billing customers fetched: $count');

    return BillingCustomerListResponse.fromJson(data);
  } catch (e) {
    print('❌ Error fetching billing customers: $e');
    rethrow;
  }
}
  
  /// Get single billing customer by ID
  static Future<BillingCustomer> getBillingCustomer(String customerId) async {
    try {
      print('📤 GET: $_baseEndpoint/customers/$customerId');
      
      final data = await _api.get('$_baseEndpoint/customers/$customerId');
      
      print('✅ Billing customer fetched: ${data['data']['customerName']}');
      
      return BillingCustomer.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching billing customer: $e');
      rethrow;
    }
  }
  
  /// Create new billing customer
  static Future<BillingCustomer> createBillingCustomer(Map<String, dynamic> customerData) async {
    try {
      print('📤 POST: $_baseEndpoint/customers');
      print('📦 Data: ${json.encode(customerData)}');
      
      final data = await _api.post('$_baseEndpoint/customers', body: customerData);
      
      print('✅ Billing customer created: ${data['data']['customerName']}');
      
      return BillingCustomer.fromJson(data['data']);
    } catch (e) {
      print('❌ Error creating billing customer: $e');
      rethrow;
    }
  }
  
  /// Update existing billing customer
  static Future<BillingCustomer> updateBillingCustomer(String customerId, Map<String, dynamic> customerData) async {
    try {
      print('📤 PUT: $_baseEndpoint/customers/$customerId');
      print('📦 Data: ${json.encode(customerData)}');
      
      final data = await _api.put('$_baseEndpoint/customers/$customerId', body: customerData);
      
      print('✅ Billing customer updated: ${data['data']['customerName']}');
      
      return BillingCustomer.fromJson(data['data']);
    } catch (e) {
      print('❌ Error updating billing customer: $e');
      rethrow;
    }
  }
  
  /// Deactivate billing customer (soft delete)
  static Future<void> deactivateBillingCustomer(String customerId) async {
    try {
      print('📤 DELETE: $_baseEndpoint/customers/$customerId');
      
      await _api.delete('$_baseEndpoint/customers/$customerId');
      
      print('✅ Billing customer deactivated');
    } catch (e) {
      print('❌ Error deactivating billing customer: $e');
      rethrow;
    }
  }
}

// ============================================================================
// ✅ NEW: PAYMENT ACCOUNT MODEL
// ============================================================================

class PaymentAccount {
  final String id;
  final String accountType;
  final String accountName;
  final String? holderName;
  final double openingBalance;
  final double currentBalance;
  final bool isActive;
  
  // Bank Account fields
  final String? bankName;
  final String? accountNumber;
  final String? ifscCode;
  
  // UPI fields
  final String? upiId;
  
  // Fuel Card fields
  final String? providerName;
  final String? cardNumber;
  
  // FASTag fields
  final String? fastagNumber;
  final String? vehicleNumber;
  
  // Custom type name (for OTHER type)
  final String? customTypeName;
  
  // Custom fields
  final List<CustomField>? customFields;
  
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentAccount({
    required this.id,
    required this.accountType,
    required this.accountName,
    this.holderName,
    required this.openingBalance,
    required this.currentBalance,
    required this.isActive,
    this.bankName,
    this.accountNumber,
    this.ifscCode,
    this.upiId,
    this.providerName,
    this.cardNumber,
    this.fastagNumber,
    this.vehicleNumber,
    this.customTypeName,
    this.customFields,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentAccount.fromJson(Map<String, dynamic> json) {
    return PaymentAccount(
      id: json['_id'] ?? json['id'],
      accountType: json['accountType'] ?? 'BANK_ACCOUNT',
      accountName: json['accountName'] ?? '',
      holderName: json['holderName'],
      openingBalance: (json['openingBalance'] ?? 0).toDouble(),
      currentBalance: (json['currentBalance'] ?? 0).toDouble(),
      isActive: json['isActive'] ?? true,
      bankName: json['bankName'],
      accountNumber: json['accountNumber'],
      ifscCode: json['ifscCode'],
      upiId: json['upiId'],
      providerName: json['providerName'],
      cardNumber: json['cardNumber'],
      fastagNumber: json['fastagNumber'],
      vehicleNumber: json['vehicleNumber'],
      customTypeName: json['customTypeName'],
      customFields: json['customFields'] != null
          ? (json['customFields'] as List)
              .map((field) => CustomField.fromJson(field))
              .toList()
          : null,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accountId': id,
      'accountType': accountType,
      'accountName': accountName,
      'holderName': holderName,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'ifscCode': ifscCode,
      'upiId': upiId,
      'providerName': providerName,
      'cardNumber': cardNumber,
      'fastagNumber': fastagNumber,
      'vehicleNumber': vehicleNumber,
      'customTypeName': customTypeName,
      'customFields': customFields?.map((field) => field.toJson()).toList(),
    };
  }
  
  // Helper method to get display text for dropdown
String getDisplayText() {
  switch (accountType) {
    case 'BANK':              // ← match what dialog saves
      return '$accountName - ${bankName ?? "Bank"} (****${accountNumber?.substring(accountNumber!.length - 4) ?? "****"})';
    case 'FUEL_CARD':
      return '$accountName - ${providerName ?? "Fuel Card"}';
    case 'FASTAG':
      return '$accountName - FASTag ($vehicleNumber)';
    case 'PETTY_CASH':
      return '$accountName - Petty Cash';
    case 'DRIVER_ADVANCE':
      return '$accountName - Driver Advance';
    default:
      return accountName;
  }
}
  
  // Helper method to get icon for account type
String getIconName() {
  switch (accountType) {
    case 'BANK':              // ← match what dialog saves
      return 'account_balance';
    case 'FUEL_CARD':
      return 'local_gas_station';
    case 'FASTAG':
      return 'toll';
    case 'PETTY_CASH':
      return 'payment';
    case 'DRIVER_ADVANCE':
      return 'person';
    default:
      return 'payment';
  }
}
}

class CustomField {
  final String fieldName;
  final String? fieldValue;

  CustomField({
    required this.fieldName,
    this.fieldValue,
  });

  factory CustomField.fromJson(Map<String, dynamic> json) {
    return CustomField(
      fieldName: json['fieldName'] ?? '',
      fieldValue: json['fieldValue'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fieldName': fieldName,
      'fieldValue': fieldValue,
    };
  }
}

// ============================================================================
// EXISTING MODELS (PRESERVED)
// ============================================================================

/// Invoice Model
class Invoice {
  final String id;
  final String invoiceNumber;
  final String customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final Address? billingAddress;
  final Address? shippingAddress;
  final String? orderNumber;
  final DateTime invoiceDate;
  final String terms;
  final DateTime dueDate;
  final String? salesperson;
  final String? subject;
  final List<InvoiceItem> items;
  final String? customerNotes;
  final String? termsAndConditions;
  
  // ✅ NEW: Selected payment account
  final SelectedPaymentAccount? selectedPaymentAccount;
  
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
  final double amountPaid;
  final double amountDue;
  final List<Payment> payments;
  final DateTime createdAt;
  final DateTime updatedAt;

  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.billingAddress,
    this.shippingAddress,
    this.orderNumber,
    required this.invoiceDate,
    required this.terms,
    required this.dueDate,
    this.salesperson,
    this.subject,
    required this.items,
    this.customerNotes,
    this.termsAndConditions,
    this.selectedPaymentAccount,
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
    required this.createdAt,
    required this.updatedAt,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['_id'] ?? json['id'],
      invoiceNumber: json['invoiceNumber'],
      customerId: json['customerId'],
      customerName: json['customerName'],
      customerEmail: json['customerEmail'],
      customerPhone: json['customerPhone'],
      billingAddress: json['billingAddress'] != null
          ? Address.fromJson(json['billingAddress'])
          : null,
      shippingAddress: json['shippingAddress'] != null
          ? Address.fromJson(json['shippingAddress'])
          : null,
      orderNumber: json['orderNumber'],
      invoiceDate: DateTime.parse(json['invoiceDate']),
      terms: json['terms'],
      dueDate: DateTime.parse(json['dueDate']),
      salesperson: json['salesperson'],
      subject: json['subject'],
      items: (json['items'] as List)
          .map((item) => InvoiceItem.fromJson(item))
          .toList(),
      customerNotes: json['customerNotes'],
      termsAndConditions: json['termsAndConditions'],
      selectedPaymentAccount: json['selectedPaymentAccount'] != null
          ? SelectedPaymentAccount.fromJson(json['selectedPaymentAccount'])
          : null,
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
      status: json['status'],
      amountPaid: (json['amountPaid'] ?? 0).toDouble(),
      amountDue: (json['amountDue'] ?? 0).toDouble(),
      payments: (json['payments'] as List?)
              ?.map((payment) => Payment.fromJson(payment))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

/// ✅ NEW: Selected Payment Account Model
class SelectedPaymentAccount {
  final String? accountId;
  final String? accountType;
  final String? accountName;
  final String? bankName;
  final String? accountNumber;
  final String? ifscCode;
  final String? accountHolder;
  final String? upiId;
  final String? providerName;
  final String? cardNumber;
  final String? fastagNumber;
  final String? vehicleNumber;
  final List<CustomField>? customFields;

  SelectedPaymentAccount({
    this.accountId,
    this.accountType,
    this.accountName,
    this.bankName,
    this.accountNumber,
    this.ifscCode,
    this.accountHolder,
    this.upiId,
    this.providerName,
    this.cardNumber,
    this.fastagNumber,
    this.vehicleNumber,
    this.customFields,
  });

  factory SelectedPaymentAccount.fromJson(Map<String, dynamic> json) {
    return SelectedPaymentAccount(
      accountId: json['accountId'],
      accountType: json['accountType'],
      accountName: json['accountName'],
      bankName: json['bankName'],
      accountNumber: json['accountNumber'],
      ifscCode: json['ifscCode'],
      accountHolder: json['accountHolder'],
      upiId: json['upiId'],
      providerName: json['providerName'],
      cardNumber: json['cardNumber'],
      fastagNumber: json['fastagNumber'],
      vehicleNumber: json['vehicleNumber'],
      customFields: json['customFields'] != null
          ? (json['customFields'] as List)
              .map((field) => CustomField.fromJson(field))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accountId': accountId,
      'accountType': accountType,
      'accountName': accountName,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'ifscCode': ifscCode,
      'accountHolder': accountHolder,
      'upiId': upiId,
      'providerName': providerName,
      'cardNumber': cardNumber,
      'fastagNumber': fastagNumber,
      'vehicleNumber': vehicleNumber,
      'customFields': customFields?.map((field) => field.toJson()).toList(),
    };
  }
}

/// Invoice Item Model
class InvoiceItem {
  final String itemDetails;
  final double quantity;
  final double rate;
  final double discount;
  final String discountType;
  final double amount;

  InvoiceItem({
    required this.itemDetails,
    required this.quantity,
    required this.rate,
    required this.discount,
    required this.discountType,
    required this.amount,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
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

/// Address Model
class Address {
  final String? street;
  final String? city;
  final String? state;
  final String? pincode;
  final String? country;

  Address({
    this.street,
    this.city,
    this.state,
    this.pincode,
    this.country,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      street: json['street'],
      city: json['city'],
      state: json['state'],
      pincode: json['pincode'],
      country: json['country'],
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

/// Payment Model
class Payment {
  final String paymentId;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod;
  final String? referenceNumber;
  final String? notes;
  final DateTime recordedAt;

  Payment({
    required this.paymentId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.referenceNumber,
    this.notes,
    required this.recordedAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      paymentId: json['paymentId'],
      amount: (json['amount'] ?? 0).toDouble(),
      paymentDate: DateTime.parse(json['paymentDate']),
      paymentMethod: json['paymentMethod'],
      referenceNumber: json['referenceNumber'],
      notes: json['notes'],
      recordedAt: DateTime.parse(json['recordedAt']),
    );
  }
}

/// Invoice List Response
class InvoiceListResponse {
  final List<Invoice> invoices;
  final Pagination pagination;

  InvoiceListResponse({
    required this.invoices,
    required this.pagination,
  });

  factory InvoiceListResponse.fromJson(Map<String, dynamic> json) {
    return InvoiceListResponse(
      invoices: (json['data'] as List)
          .map((invoice) => Invoice.fromJson(invoice))
          .toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

/// Pagination Model
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
      total: json['total'],
      page: json['page'],
      limit: json['limit'],
      pages: json['pages'],
    );
  }
}

/// Invoice Statistics
class InvoiceStats {
  final int totalInvoices;
  final double totalRevenue;
  final double totalPaid;
  final double totalDue;
  final Map<String, StatusStats> byStatus;

  InvoiceStats({
    required this.totalInvoices,
    required this.totalRevenue,
    required this.totalPaid,
    required this.totalDue,
    required this.byStatus,
  });

  factory InvoiceStats.fromJson(Map<String, dynamic> json) {
    final byStatusMap = <String, StatusStats>{};
    
    if (json['byStatus'] != null) {
      (json['byStatus'] as Map<String, dynamic>).forEach((key, value) {
        byStatusMap[key] = StatusStats.fromJson(value);
      });
    }
    
    return InvoiceStats(
      totalInvoices: json['totalInvoices'] ?? 0,
      totalRevenue: (json['totalRevenue'] ?? 0).toDouble(),
      totalPaid: (json['totalPaid'] ?? 0).toDouble(),
      totalDue: (json['totalDue'] ?? 0).toDouble(),
      byStatus: byStatusMap,
    );
  }
}

/// Status Statistics
class StatusStats {
  final int count;
  final double amount;

  StatusStats({
    required this.count,
    required this.amount,
  });

  factory StatusStats.fromJson(Map<String, dynamic> json) {
    return StatusStats(
      count: json['count'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }
}

/// Payment Response
class PaymentResponse {
  final Invoice invoice;
  final Payment payment;

  PaymentResponse({
    required this.invoice,
    required this.payment,
  });

  factory PaymentResponse.fromJson(Map<String, dynamic> json) {
    return PaymentResponse(
      invoice: Invoice.fromJson(json['invoice']),
      payment: Payment.fromJson(json['payment']),
    );
  }
}

// ============================================================================
// BILLING CUSTOMER MODELS
// ============================================================================

class BillingCustomer {
  final String id;
  final String customerId;
  final String customerType;
  final String customerDisplayName;
  final String primaryEmail;
  final String primaryPhone;
  final String? companyName;
  final String? gstNumber;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? contactPerson;
  final String? website;
  final String? notes;
  final String customerStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  BillingCustomer({
    required this.id,
    required this.customerId,
    required this.customerType,
    required this.customerDisplayName,
    required this.primaryEmail,
    required this.primaryPhone,
    this.companyName,
    this.gstNumber,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.contactPerson,
    this.website,
    this.notes,
    required this.customerStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BillingCustomer.fromJson(Map<String, dynamic> json) {
    return BillingCustomer(
      id: json['_id'] ?? json['id'],
      customerId: json['customerId'] ?? '',
      customerType: json['customerType'] ?? 'Individual',
      customerDisplayName: json['customerDisplayName'] ?? '',
      primaryEmail: json['primaryEmail'] ?? '',
      primaryPhone: json['primaryPhone'] ?? '',
      companyName: json['companyName'],
      gstNumber: json['gstNumber'],
      addressLine1: json['addressLine1'],
      addressLine2: json['addressLine2'],
      city: json['city'],
      state: json['state'],
      postalCode: json['postalCode'],
      country: json['country'] ?? 'India',
      contactPerson: json['primaryContactPerson'],
      website: json['website'],
      notes: json['internalNotes'],
      customerStatus: json['customerStatus'] ?? 'Active',
      createdAt: DateTime.parse(json['createdDate'] ?? json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['lastModifiedDate'] ?? json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'customerId': customerId,
      'customerType': customerType,
      'customerDisplayName': customerDisplayName,
      'primaryEmail': primaryEmail,
      'primaryPhone': primaryPhone,
      'companyName': companyName,
      'gstNumber': gstNumber,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'postalCode': postalCode,
      'country': country,
      'primaryContactPerson': contactPerson,
      'website': website,
      'internalNotes': notes,
      'customerStatus': customerStatus,
    };
  }
  
  String get customerName => customerDisplayName;
  String get customerEmail => primaryEmail;
  String get customerPhone => primaryPhone;
  bool get isActive => customerStatus == 'Active';
}

// ============================================================================
// BILLABLE EXPENSE MODEL
// ============================================================================

class BillableExpense {
  final String id;
  final String date;
  final String expenseAccount;
  final double amount;
  final double tax;
  final double total;
  final double billableAmount;
  final double markupPercentage;
  final String paidThrough;
  final String? vendor;
  final String? customerName;
  final String? project;
  final String? notes;
  bool isSelected;

  BillableExpense({
    required this.id,
    required this.date,
    required this.expenseAccount,
    required this.amount,
    required this.tax,
    required this.total,
    required this.billableAmount,
    required this.markupPercentage,
    required this.paidThrough,
    this.vendor,
    this.customerName,
    this.project,
    this.notes,
    this.isSelected = false,
  });

  factory BillableExpense.fromJson(Map<String, dynamic> json) {
    return BillableExpense(
      id: json['_id'] ?? json['id'] ?? '',
      date: json['date'] ?? '',
      expenseAccount: json['expenseAccount'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      tax: (json['tax'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      billableAmount: (json['billableAmount'] ?? 0).toDouble(),
      markupPercentage: (json['markupPercentage'] ?? 0).toDouble(),
      paidThrough: json['paidThrough'] ?? '',
      vendor: json['vendor'],
      customerName: json['customerName'],
      project: json['project'],
      notes: json['notes'],
      isSelected: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'date': date,
      'expenseAccount': expenseAccount,
      'amount': amount,
      'tax': tax,
      'total': total,
      'billableAmount': billableAmount,
      'markupPercentage': markupPercentage,
      'paidThrough': paidThrough,
      'vendor': vendor,
      'customerName': customerName,
      'project': project,
      'notes': notes,
    };
  }

  // Convert to invoice line item
  Map<String, dynamic> toInvoiceItem() {
    final description = markupPercentage > 0
        ? 'Expense: $expenseAccount${vendor != null ? ' ($vendor)' : ''} + ${markupPercentage.toStringAsFixed(0)}% markup'
        : 'Expense: $expenseAccount${vendor != null ? ' ($vendor)' : ''}';
    return {
      'itemDetails': description,
      'quantity': 1.0,
      'rate': billableAmount,
      'discount': 0.0,
      'discountType': 'percentage',
      'amount': billableAmount,
      'expenseId': id,
    };
  }
}

class BillingCustomerListResponse {
  final List<BillingCustomer> customers;
  final Pagination pagination;

  BillingCustomerListResponse({
    required this.customers,
    required this.pagination,
  });

  factory BillingCustomerListResponse.fromJson(Map<String, dynamic> json) {
    final customersData = json['data']?['customers'] ?? json['data'] ?? [];
    final rawPagination = json['data']?['pagination'] ?? json['pagination'] ?? {};
    
    // Backend uses currentPage/totalPages/totalCount/pageSize
    // Normalise to total/page/limit/pages
    final normalisedPagination = {
      'total': rawPagination['totalCount'] ?? rawPagination['total'] ?? (customersData as List).length,
      'page': rawPagination['currentPage'] ?? rawPagination['page'] ?? 1,
      'limit': rawPagination['pageSize'] ?? rawPagination['limit'] ?? 50,
      'pages': rawPagination['totalPages'] ?? rawPagination['pages'] ?? 1,
    };
    
    return BillingCustomerListResponse(
      customers: (customersData as List)
          .map((customer) => BillingCustomer.fromJson(customer))
          .toList(),
      pagination: Pagination.fromJson(normalisedPagination),
    );
  }
}