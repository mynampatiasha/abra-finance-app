// ============================================================================
// INVOICE SERVICE — ZOHO BOOKS STYLE (COMPLETE)
// ============================================================================
// File: lib/core/services/invoice_service.dart
// NEW FEATURES:
// ✅ Per-item GST (itemGstRate, cgstAmount, sgstAmount, igstAmount per item)
// ✅ Place of Supply + isInterState flag
// ✅ HSN/SAC code + Unit per item
// ✅ Taxable amount per item
// ✅ customerGSTIN, customerPAN, gstRegistrationType
// ✅ referenceNumber, currency (default INR)
// ✅ invoiceLevelDiscount, shippingCharges, adjustment
// ✅ Nested billingAddress + shippingAddress (CustomerAddress)
// ✅ getOrgState() method
// ✅ All existing features preserved
// ============================================================================

import 'dart:convert';
import '../../core/services/api_service.dart';
// Import the CustomerAddress model from billing_customers_service
import 'billing_customers_service.dart' show CustomerAddress, BillingCustomer, kIndianStates;

export 'billing_customers_service.dart' show CustomerAddress, BillingCustomer, kIndianStates;

class InvoiceService {
  static final ApiService _api = ApiService();

  static const String _baseEndpoint    = '/api/finance/invoices';
  static const String _accountsEndpoint = '/api/finance/banking';

  // ==========================================================================
  // ORG STATE
  // ==========================================================================

  /// Fetch org's state — used to determine CGST+SGST vs IGST
  static Future<OrgStateResponse> getOrgState() async {
    try {
      print('📤 GET: $_baseEndpoint/org-state');
      final data = await _api.get('$_baseEndpoint/org-state');
      print('✅ Org state fetched: ${data['data']['state']}');
      return OrgStateResponse.fromJson(data['data']);
    } catch (e) {
      print('❌ Error fetching org state: $e');
      return const OrgStateResponse(state: '', orgName: '', gstNumber: '');
    }
  }

  // ==========================================================================
  // PAYMENT ACCOUNTS
  // ==========================================================================

  static Future<List<PaymentAccount>> getPaymentAccounts() async {
    try {
      final data = await _api.get(_accountsEndpoint, queryParams: {'isActive': 'true'});
      final List<dynamic> accountsList = (data['data'] is List)
          ? data['data'] as List<dynamic>
          : (data['data'] as Map<String, dynamic>?)?['accounts'] ?? [];
      return accountsList.map((a) => PaymentAccount.fromJson(a)).toList();
    } catch (e) {
      print('❌ Error fetching payment accounts: $e');
      rethrow;
    }
  }

  static Future<PaymentAccount> getPaymentAccount(String accountId) async {
    final data = await _api.get('$_accountsEndpoint/$accountId');
    return PaymentAccount.fromJson(data['data']);
  }

  // ==========================================================================
  // BILLABLE EXPENSES
  // ==========================================================================

  static Future<List<BillableExpense>> getBillableExpenses(String customerName) async {
    try {
      final data = await _api.get('/api/finance/expenses/billable/$customerName');
      return (data['data'] as List).map((e) => BillableExpense.fromJson(e)).toList();
    } catch (e) {
      print('❌ Error fetching billable expenses: $e');
      return [];
    }
  }

  // ==========================================================================
  // INVOICE CRUD
  // ==========================================================================

  static Future<InvoiceListResponse> getInvoices({
    String? status, String? customerId,
    DateTime? fromDate, DateTime? toDate,
    int page = 1, int limit = 20,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(), 'limit': limit.toString(),
    };
    if (status     != null) queryParams['status']     = status;
    if (customerId != null) queryParams['customerId'] = customerId;
    if (fromDate   != null) queryParams['fromDate']   = fromDate.toIso8601String();
    if (toDate     != null) queryParams['toDate']     = toDate.toIso8601String();
    final data = await _api.get(_baseEndpoint, queryParams: queryParams);
    return InvoiceListResponse.fromJson(data);
  }

  static Future<InvoiceStats> getStats() async {
    final data = await _api.get('$_baseEndpoint/stats');
    return InvoiceStats.fromJson(data['data']);
  }

  static Future<Invoice> getInvoice(String invoiceId) async {
    final data = await _api.get('$_baseEndpoint/$invoiceId');
    return Invoice.fromJson(data['data']);
  }

  static Future<Invoice> createInvoice(Map<String, dynamic> invoiceData) async {
    final data = await _api.post(_baseEndpoint, body: invoiceData);
    return Invoice.fromJson(data['data']);
  }

  static Future<Invoice> updateInvoice(String invoiceId, Map<String, dynamic> invoiceData) async {
    final data = await _api.put('$_baseEndpoint/$invoiceId', body: invoiceData);
    return Invoice.fromJson(data['data']);
  }

  static Future<Invoice> sendInvoice(String invoiceId) async {
    final data = await _api.post('$_baseEndpoint/$invoiceId/send');
    return Invoice.fromJson(data['data']);
  }

  static Future<void> markInvoiceAsSent(String invoiceId) async {
    await _api.patch('$_baseEndpoint/$invoiceId/mark-as-sent');
  }

  static Future<PaymentResponse> recordPayment(
    String invoiceId, Map<String, dynamic> paymentData,
  ) async {
    final data = await _api.post('$_baseEndpoint/$invoiceId/payment', body: paymentData);
    return PaymentResponse.fromJson(data['data']);
  }

  static Future<String> downloadPDF(String invoiceId) async {
    final headers = await _api.getHeaders();
    final token   = headers['Authorization']?.replaceFirst('Bearer ', '') ?? '';
    return '${_api.baseUrl}$_baseEndpoint/$invoiceId/pdf?token=$token';
  }

  static Future<void> deleteInvoice(String invoiceId) async {
    await _api.delete('$_baseEndpoint/$invoiceId');
  }

  // ==========================================================================
  // BILLING CUSTOMERS
  // ==========================================================================

  static Future<BillingCustomerListResponse> getBillingCustomers({
    String? search, int page = 1, int limit = 1000,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(), 'limit': limit.toString(),
      'sortBy': 'createdDate', 'sortOrder': 'desc',
    };
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    final data = await _api.get('/api/finance/customers', queryParams: queryParams);
    return BillingCustomerListResponse.fromJson(data);
  }

  static Future<BillingCustomer> getBillingCustomer(String customerId) async {
    final data = await _api.get('/api/finance/customers/$customerId');
    return BillingCustomer.fromJson(data['data']);
  }

  static Future<BillingCustomer> createBillingCustomer(Map<String, dynamic> customerData) async {
    final data = await _api.post('/api/finance/customers', body: customerData);
    return BillingCustomer.fromJson(data['data']);
  }

  static Future<BillingCustomer> updateBillingCustomer(String customerId, Map<String, dynamic> customerData) async {
    final data = await _api.put('/api/finance/customers/$customerId', body: customerData);
    return BillingCustomer.fromJson(data['data']);
  }

  static Future<void> deactivateBillingCustomer(String customerId) async {
    await _api.delete('/api/finance/customers/$customerId');
  }
}

// ============================================================================
// ORG STATE RESPONSE
// ============================================================================

class OrgStateResponse {
  final String state;
  final String orgName;
  final String gstNumber;

  const OrgStateResponse({
    required this.state,
    required this.orgName,
    required this.gstNumber,
  });

  factory OrgStateResponse.fromJson(Map<String, dynamic> json) {
    return OrgStateResponse(
      state:     json['state']     ?? '',
      orgName:   json['orgName']   ?? '',
      gstNumber: json['gstNumber'] ?? '',
    );
  }
}

// ============================================================================
// INVOICE ITEM MODEL — ZOHO BOOKS STYLE
// ============================================================================

class InvoiceItem {
  String itemDetails;
  String hsnCode;       // HSN code for goods
  String sacCode;       // SAC code for services
  String unit;          // Nos/Hrs/Kg/Pcs/Box/Mtr/Ltr
  double quantity;
  double rate;
  double discount;
  String discountType;  // percentage / amount
  double taxableAmount; // qty × rate − discount (auto-calculated)
  double itemGstRate;   // 0/5/12/18/28
  double cgstRate;      // itemGstRate/2
  double sgstRate;      // itemGstRate/2
  double igstRate;      // itemGstRate (inter-state)
  double cgstAmount;
  double sgstAmount;
  double igstAmount;
  double amount;        // taxableAmount + tax
  String? expenseId;

  InvoiceItem({
    this.itemDetails  = '',
    this.hsnCode      = '',
    this.sacCode      = '',
    this.unit         = 'Nos',
    this.quantity     = 0,
    this.rate         = 0,
    this.discount     = 0,
    this.discountType = 'percentage',
    this.taxableAmount= 0,
    this.itemGstRate  = 0,
    this.cgstRate     = 0,
    this.sgstRate     = 0,
    this.igstRate     = 0,
    this.cgstAmount   = 0,
    this.sgstAmount   = 0,
    this.igstAmount   = 0,
    this.amount       = 0,
    this.expenseId,
  });

  /// Calculate taxable amount from qty, rate, discount
  double get calculatedTaxableAmount {
    double val = quantity * rate;
    if (discount > 0) {
      val = discountType == 'percentage'
          ? val - (val * discount / 100)
          : val - discount;
    }
    return val < 0 ? 0 : val;
  }

  /// Recalculate per-item tax based on isInterState
  void recalculateTax({required bool isInterState}) {
    taxableAmount = calculatedTaxableAmount;
    if (isInterState) {
      igstRate   = itemGstRate;
      cgstRate   = 0;
      sgstRate   = 0;
      igstAmount = double.parse((taxableAmount * itemGstRate / 100).toStringAsFixed(2));
      cgstAmount = 0;
      sgstAmount = 0;
    } else {
      cgstRate   = itemGstRate / 2;
      sgstRate   = itemGstRate / 2;
      igstRate   = 0;
      cgstAmount = double.parse((taxableAmount * (itemGstRate / 2) / 100).toStringAsFixed(2));
      sgstAmount = double.parse((taxableAmount * (itemGstRate / 2) / 100).toStringAsFixed(2));
      igstAmount = 0;
    }
    amount = double.parse((taxableAmount + cgstAmount + sgstAmount + igstAmount).toStringAsFixed(2));
  }

  Map<String, dynamic> toJson() => {
    'itemDetails':   itemDetails,
    'hsnCode':       hsnCode,
    'sacCode':       sacCode,
    'unit':          unit,
    'quantity':      quantity,
    'rate':          rate,
    'discount':      discount,
    'discountType':  discountType,
    'taxableAmount': taxableAmount,
    'itemGstRate':   itemGstRate,
    'cgstRate':      cgstRate,
    'sgstRate':      sgstRate,
    'igstRate':      igstRate,
    'cgstAmount':    cgstAmount,
    'sgstAmount':    sgstAmount,
    'igstAmount':    igstAmount,
    'amount':        amount,
    if (expenseId != null) 'expenseId': expenseId,
  };

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      itemDetails:   json['itemDetails']   ?? '',
      hsnCode:       json['hsnCode']       ?? '',
      sacCode:       json['sacCode']       ?? '',
      unit:          json['unit']          ?? 'Nos',
      quantity:      (json['quantity']     ?? 0).toDouble(),
      rate:          (json['rate']         ?? 0).toDouble(),
      discount:      (json['discount']     ?? 0).toDouble(),
      discountType:  json['discountType']  ?? 'percentage',
      taxableAmount: (json['taxableAmount']?? 0).toDouble(),
      itemGstRate:   (json['itemGstRate']  ?? 0).toDouble(),
      cgstRate:      (json['cgstRate']     ?? 0).toDouble(),
      sgstRate:      (json['sgstRate']     ?? 0).toDouble(),
      igstRate:      (json['igstRate']     ?? 0).toDouble(),
      cgstAmount:    (json['cgstAmount']   ?? 0).toDouble(),
      sgstAmount:    (json['sgstAmount']   ?? 0).toDouble(),
      igstAmount:    (json['igstAmount']   ?? 0).toDouble(),
      amount:        (json['amount']       ?? 0).toDouble(),
      expenseId:     json['expenseId']?.toString(),
    );
  }
}

// ============================================================================
// TAX SLAB MODEL (for summary display)
// ============================================================================

class TaxSlab {
  final double gstRate;
  final double taxableAmount;
  final double cgst;
  final double sgst;
  final double igst;
  final double totalTax;

  const TaxSlab({
    required this.gstRate,
    required this.taxableAmount,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.totalTax,
  });
}

// Build tax slabs from items — mirrors backend buildTaxSummaryBySlabs()
List<TaxSlab> buildTaxSlabs(List<InvoiceItem> items, {required bool isInterState}) {
  final Map<double, Map<String, double>> slabs = {};
  for (final item in items) {
    final rate = item.itemGstRate;
    slabs.putIfAbsent(rate, () => {'taxable': 0, 'cgst': 0, 'sgst': 0, 'igst': 0});
    slabs[rate]!['taxable'] = slabs[rate]!['taxable']! + item.taxableAmount;
    if (isInterState) {
      slabs[rate]!['igst'] = slabs[rate]!['igst']! + item.igstAmount;
    } else {
      slabs[rate]!['cgst'] = slabs[rate]!['cgst']! + item.cgstAmount;
      slabs[rate]!['sgst'] = slabs[rate]!['sgst']! + item.sgstAmount;
    }
  }
  return slabs.entries.map((e) {
    final m = e.value;
    return TaxSlab(
      gstRate:      e.key,
      taxableAmount: double.parse((m['taxable']!).toStringAsFixed(2)),
      cgst:          double.parse((m['cgst']!).toStringAsFixed(2)),
      sgst:          double.parse((m['sgst']!).toStringAsFixed(2)),
      igst:          double.parse((m['igst']!).toStringAsFixed(2)),
      totalTax:      double.parse(((m['cgst']! + m['sgst']! + m['igst']!)).toStringAsFixed(2)),
    );
  }).toList()..sort((a, b) => a.gstRate.compareTo(b.gstRate));
}

// ============================================================================
// INVOICE MODEL — ZOHO BOOKS STYLE (COMPLETE)
// ============================================================================

class Invoice {
  final String id;
  final String invoiceNumber;
  final String customerId;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;

  // ── GST / Customer tax info ──────────────────────────────────────────────
  final String customerGSTIN;
  final String customerPAN;
  final String gstRegistrationType;

  // ── Addresses ────────────────────────────────────────────────────────────
  final CustomerAddress billingAddress;
  final CustomerAddress shippingAddress;

  // ── Place of Supply ──────────────────────────────────────────────────────
  final String placeOfSupply;
  final String sourceState;
  final bool   isInterState;

  // ── Header ───────────────────────────────────────────────────────────────
  final String?   orderNumber;
  final String    referenceNumber;
  final String    currency;
  final DateTime  invoiceDate;
  final String    terms;
  final DateTime  dueDate;
  final String?   salesperson;
  final String?   subject;

  // ── Items ─────────────────────────────────────────────────────────────────
  final List<InvoiceItem> items;

  // ── Notes ────────────────────────────────────────────────────────────────
  final String? customerNotes;
  final String? termsAndConditions;

  // ── Payment account ───────────────────────────────────────────────────────
  final SelectedPaymentAccount? selectedPaymentAccount;

  // ── Totals ────────────────────────────────────────────────────────────────
  final double subTotal;
  final double invoiceLevelDiscount;
  final String invoiceLevelDiscountType;
  final double invoiceDiscountAmount;
  final double taxableTotal;

  // Tax by slab totals
  final double totalCGST;
  final double totalSGST;
  final double totalIGST;
  final double totalTax;

  // Legacy fields (backward compat)
  final double gstRate;
  final double cgst;
  final double sgst;
  final double igst;

  // TDS / TCS
  final double tdsRate;
  final double tdsAmount;
  final double tcsRate;
  final double tcsAmount;

  // Adjustments
  final double shippingCharges;
  final double adjustment;

  final double totalAmount;
  final String status;
  final double amountPaid;
  final double amountDue;
  final List<Payment> payments;
  final List<EmailSent> emailsSent;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerId,
    required this.customerName,
    this.customerEmail,
    this.customerPhone,
    this.customerGSTIN          = '',
    this.customerPAN            = '',
    this.gstRegistrationType    = '',
    this.billingAddress         = const CustomerAddress(),
    this.shippingAddress        = const CustomerAddress(),
    this.placeOfSupply          = '',
    this.sourceState            = '',
    this.isInterState           = false,
    this.orderNumber,
    this.referenceNumber        = '',
    this.currency               = 'INR',
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
    this.invoiceLevelDiscount     = 0,
    this.invoiceLevelDiscountType = 'percentage',
    this.invoiceDiscountAmount    = 0,
    this.taxableTotal             = 0,
    this.totalCGST                = 0,
    this.totalSGST                = 0,
    this.totalIGST                = 0,
    this.totalTax                 = 0,
    this.gstRate                  = 0,
    this.cgst                     = 0,
    this.sgst                     = 0,
    this.igst                     = 0,
    this.tdsRate                  = 0,
    this.tdsAmount                = 0,
    this.tcsRate                  = 0,
    this.tcsAmount                = 0,
    this.shippingCharges          = 0,
    this.adjustment               = 0,
    required this.totalAmount,
    required this.status,
    required this.amountPaid,
    required this.amountDue,
    required this.payments,
    this.emailsSent               = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Build tax slabs from items for display
  List<TaxSlab> get taxSlabs => buildTaxSlabs(items, isInterState: isInterState);

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id:                       json['_id'] ?? json['id'] ?? '',
      invoiceNumber:            json['invoiceNumber'] ?? '',
      customerId:               json['customerId'] ?? '',
      customerName:             json['customerName'] ?? '',
      customerEmail:            json['customerEmail'],
      customerPhone:            json['customerPhone'],
      customerGSTIN:            json['customerGSTIN']          ?? '',
      customerPAN:              json['customerPAN']            ?? '',
      gstRegistrationType:      json['gstRegistrationType']    ?? '',
      billingAddress:           CustomerAddress.fromJson(json['billingAddress']),
      shippingAddress:          CustomerAddress.fromJson(json['shippingAddress']),
      placeOfSupply:            json['placeOfSupply']          ?? '',
      sourceState:              json['sourceState']            ?? '',
      isInterState:             json['isInterState']           ?? false,
      orderNumber:              json['orderNumber'],
      referenceNumber:          json['referenceNumber']        ?? '',
      currency:                 json['currency']               ?? 'INR',
      invoiceDate:              DateTime.parse(json['invoiceDate']),
      terms:                    json['terms'] ?? 'Net 30',
      dueDate:                  DateTime.parse(json['dueDate']),
      salesperson:              json['salesperson'],
      subject:                  json['subject'],
      items: (json['items'] as List? ?? [])
          .map((item) => InvoiceItem.fromJson(item))
          .toList(),
      customerNotes:            json['customerNotes'],
      termsAndConditions:       json['termsAndConditions'],
      selectedPaymentAccount:   json['selectedPaymentAccount'] != null
          ? SelectedPaymentAccount.fromJson(json['selectedPaymentAccount'])
          : null,
      subTotal:                 (json['subTotal']              ?? 0).toDouble(),
      invoiceLevelDiscount:     (json['invoiceLevelDiscount']  ?? 0).toDouble(),
      invoiceLevelDiscountType: json['invoiceLevelDiscountType'] ?? 'percentage',
      invoiceDiscountAmount:    (json['invoiceDiscountAmount'] ?? 0).toDouble(),
      taxableTotal:             (json['taxableTotal']          ?? 0).toDouble(),
      totalCGST:                (json['totalCGST']             ?? json['cgst'] ?? 0).toDouble(),
      totalSGST:                (json['totalSGST']             ?? json['sgst'] ?? 0).toDouble(),
      totalIGST:                (json['totalIGST']             ?? json['igst'] ?? 0).toDouble(),
      totalTax:                 (json['totalTax']              ?? 0).toDouble(),
      gstRate:                  (json['gstRate']               ?? 0).toDouble(),
      cgst:                     (json['cgst']                  ?? 0).toDouble(),
      sgst:                     (json['sgst']                  ?? 0).toDouble(),
      igst:                     (json['igst']                  ?? 0).toDouble(),
      tdsRate:                  (json['tdsRate']               ?? 0).toDouble(),
      tdsAmount:                (json['tdsAmount']             ?? 0).toDouble(),
      tcsRate:                  (json['tcsRate']               ?? 0).toDouble(),
      tcsAmount:                (json['tcsAmount']             ?? 0).toDouble(),
      shippingCharges:          (json['shippingCharges']       ?? 0).toDouble(),
      adjustment:               (json['adjustment']            ?? 0).toDouble(),
      totalAmount:              (json['totalAmount']           ?? 0).toDouble(),
      status:                   json['status'] ?? 'DRAFT',
      amountPaid:               (json['amountPaid']            ?? 0).toDouble(),
      amountDue:                (json['amountDue']             ?? 0).toDouble(),
      payments: (json['payments'] as List? ?? [])
          .map((p) => Payment.fromJson(p))
          .toList(),
      emailsSent: (json['emailsSent'] as List? ?? [])
          .map((e) => EmailSent.fromJson(e))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

// ============================================================================
// ADDRESS MODEL (re-export via CustomerAddress from billing_customers_service)
// Keep a local InvoiceAddress for backward compat with existing detail page
// ============================================================================

class Address {
  final String? attention;
  final String? street;
  final String? city;
  final String? state;
  final String? zip;
  final String? pincode; // legacy alias for zip
  final String? country;
  final String? phone;
  final String? fax;

  const Address({
    this.attention, this.street, this.city,
    this.state, this.zip, this.pincode,
    this.country, this.phone, this.fax,
  });

  String get formatted {
    final parts = [attention, street, city, state, zip ?? pincode, country].where((s) => s != null && s.isNotEmpty).toList();
    return parts.join(', ');
  }

  factory Address.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Address();
    return Address(
      attention: json['attention'],
      street:    json['street'],
      city:      json['city'],
      state:     json['state'],
      zip:       json['zip'],
      pincode:   json['pincode'],
      country:   json['country'],
      phone:     json['phone'],
      fax:       json['fax'],
    );
  }

  Map<String, dynamic> toJson() => {
    if (attention != null) 'attention': attention,
    if (street    != null) 'street':    street,
    if (city      != null) 'city':      city,
    if (state     != null) 'state':     state,
    if (zip       != null) 'zip':       zip,
    if (country   != null) 'country':   country,
    if (phone     != null) 'phone':     phone,
    if (fax       != null) 'fax':       fax,
  };
}

// ============================================================================
// PAYMENT MODEL
// ============================================================================

class Payment {
  final String   paymentId;
  final double   amount;
  final DateTime paymentDate;
  final String   paymentMethod;
  final String?  referenceNumber;
  final String?  notes;
  final String?  recordedBy;
  final DateTime recordedAt;

  const Payment({
    required this.paymentId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.referenceNumber,
    this.notes,
    this.recordedBy,
    required this.recordedAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      paymentId:       json['paymentId']?.toString() ?? '',
      amount:          (json['amount']       ?? 0).toDouble(),
      paymentDate:     DateTime.parse(json['paymentDate'] ?? DateTime.now().toIso8601String()),
      paymentMethod:   json['paymentMethod'] ?? 'Bank Transfer',
      referenceNumber: json['referenceNumber'],
      notes:           json['notes'],
      recordedBy:      json['recordedBy'],
      recordedAt:      DateTime.parse(json['recordedAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

// ============================================================================
// EMAIL SENT MODEL
// ============================================================================

class EmailSent {
  final String   sentTo;
  final DateTime sentAt;
  final String   emailType;

  const EmailSent({
    required this.sentTo,
    required this.sentAt,
    required this.emailType,
  });

  factory EmailSent.fromJson(Map<String, dynamic> json) {
    return EmailSent(
      sentTo:    json['sentTo']    ?? '',
      sentAt:    DateTime.parse(json['sentAt'] ?? DateTime.now().toIso8601String()),
      emailType: json['emailType'] ?? 'invoice',
    );
  }
}

// ============================================================================
// PAYMENT ACCOUNT MODELS
// ============================================================================

class PaymentAccount {
  final String  id;
  final String  accountType;
  final String  accountName;
  final String? holderName;
  final double  openingBalance;
  final double  currentBalance;
  final bool    isActive;
  final String? bankName;
  final String? accountNumber;
  final String? ifscCode;
  final String? upiId;
  final String? providerName;
  final String? cardNumber;
  final String? fastagNumber;
  final String? vehicleNumber;
  final String? customTypeName;
  final List<CustomField>? customFields;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PaymentAccount({
    required this.id,
    required this.accountType,
    required this.accountName,
    this.holderName,
    required this.openingBalance,
    required this.currentBalance,
    required this.isActive,
    this.bankName, this.accountNumber, this.ifscCode,
    this.upiId, this.providerName, this.cardNumber,
    this.fastagNumber, this.vehicleNumber, this.customTypeName,
    this.customFields,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentAccount.fromJson(Map<String, dynamic> json) {
    return PaymentAccount(
      id:              json['_id'] ?? json['id'] ?? '',
      accountType:     json['accountType']    ?? 'BANK_ACCOUNT',
      accountName:     json['accountName']    ?? '',
      holderName:      json['holderName'],
      openingBalance:  (json['openingBalance'] ?? 0).toDouble(),
      currentBalance:  (json['currentBalance'] ?? 0).toDouble(),
      isActive:        json['isActive'] ?? true,
      bankName:        json['bankName'],
      accountNumber:   json['accountNumber'],
      ifscCode:        json['ifscCode'],
      upiId:           json['upiId'],
      providerName:    json['providerName'],
      cardNumber:      json['cardNumber'],
      fastagNumber:    json['fastagNumber'],
      vehicleNumber:   json['vehicleNumber'],
      customTypeName:  json['customTypeName'],
      customFields:    json['customFields'] != null
          ? (json['customFields'] as List).map((f) => CustomField.fromJson(f)).toList()
          : null,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
    'accountId':    id,
    'accountType':  accountType,
    'accountName':  accountName,
    'holderName':   holderName,
    'bankName':     bankName,
    'accountNumber':accountNumber,
    'ifscCode':     ifscCode,
    'upiId':        upiId,
    'providerName': providerName,
    'cardNumber':   cardNumber,
    'fastagNumber': fastagNumber,
    'vehicleNumber':vehicleNumber,
    'customFields': customFields?.map((f) => f.toJson()).toList(),
  };

  String getDisplayText() {
    switch (accountType) {
      case 'BANK': return '$accountName - ${bankName ?? "Bank"} (****${accountNumber?.substring((accountNumber?.length ?? 4) - 4) ?? "****"})';
      case 'FUEL_CARD': return '$accountName - ${providerName ?? "Fuel Card"}';
      case 'FASTAG': return '$accountName - FASTag ($vehicleNumber)';
      default: return accountName;
    }
  }

  String getIconName() {
    switch (accountType) {
      case 'BANK': return 'account_balance';
      case 'FUEL_CARD': return 'local_gas_station';
      case 'FASTAG': return 'toll';
      default: return 'payment';
    }
  }
}

class CustomField {
  final String  fieldName;
  final String? fieldValue;

  const CustomField({ required this.fieldName, this.fieldValue });

  factory CustomField.fromJson(Map<String, dynamic> json) =>
      CustomField(fieldName: json['fieldName'] ?? '', fieldValue: json['fieldValue']);

  Map<String, dynamic> toJson() => {'fieldName': fieldName, 'fieldValue': fieldValue};
}

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

  const SelectedPaymentAccount({
    this.accountId, this.accountType, this.accountName,
    this.bankName, this.accountNumber, this.ifscCode,
    this.accountHolder, this.upiId, this.providerName,
    this.cardNumber, this.fastagNumber, this.vehicleNumber,
    this.customFields,
  });

  factory SelectedPaymentAccount.fromJson(Map<String, dynamic> json) {
    return SelectedPaymentAccount(
      accountId:     json['accountId'],
      accountType:   json['accountType'],
      accountName:   json['accountName'],
      bankName:      json['bankName'],
      accountNumber: json['accountNumber'],
      ifscCode:      json['ifscCode'],
      accountHolder: json['accountHolder'],
      upiId:         json['upiId'],
      providerName:  json['providerName'],
      cardNumber:    json['cardNumber'],
      fastagNumber:  json['fastagNumber'],
      vehicleNumber: json['vehicleNumber'],
      customFields:  json['customFields'] != null
          ? (json['customFields'] as List).map((f) => CustomField.fromJson(f)).toList()
          : null,
    );
  }
}

// ============================================================================
// LIST RESPONSE MODELS
// ============================================================================

class InvoiceListResponse {
  final List<Invoice> invoices;
  final Pagination    pagination;

  const InvoiceListResponse({ required this.invoices, required this.pagination });

  factory InvoiceListResponse.fromJson(Map<String, dynamic> json) {
    return InvoiceListResponse(
      invoices:   (json['data'] as List).map((inv) => Invoice.fromJson(inv)).toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

class Pagination {
  final int total, page, limit, pages;
  const Pagination({ required this.total, required this.page, required this.limit, required this.pages });
  factory Pagination.fromJson(Map<String, dynamic> json) =>
      Pagination(total: json['total'] ?? 0, page: json['page'] ?? 1, limit: json['limit'] ?? 20, pages: json['pages'] ?? 1);
}

class InvoiceStats {
  final int    totalInvoices;
  final double totalRevenue;
  final double totalPaid;
  final double totalDue;
  final Map<String, StatusStats> byStatus;

  const InvoiceStats({ required this.totalInvoices, required this.totalRevenue, required this.totalPaid, required this.totalDue, required this.byStatus });

  factory InvoiceStats.fromJson(Map<String, dynamic> json) {
    final byStatusMap = <String, StatusStats>{};
    if (json['byStatus'] != null) {
      (json['byStatus'] as Map<String, dynamic>).forEach((key, value) {
        byStatusMap[key] = StatusStats.fromJson(value);
      });
    }
    return InvoiceStats(
      totalInvoices: json['totalInvoices'] ?? 0,
      totalRevenue:  (json['totalRevenue']  ?? 0).toDouble(),
      totalPaid:     (json['totalPaid']     ?? 0).toDouble(),
      totalDue:      (json['totalDue']      ?? 0).toDouble(),
      byStatus:      byStatusMap,
    );
  }
}

class StatusStats {
  final int    count;
  final double amount;
  const StatusStats({ required this.count, required this.amount });
  factory StatusStats.fromJson(Map<String, dynamic> json) =>
      StatusStats(count: json['count'] ?? 0, amount: (json['amount'] ?? 0).toDouble());
}

class PaymentResponse {
  final Invoice invoice;
  final Payment payment;
  const PaymentResponse({ required this.invoice, required this.payment });
  factory PaymentResponse.fromJson(Map<String, dynamic> json) =>
      PaymentResponse(invoice: Invoice.fromJson(json['invoice']), payment: Payment.fromJson(json['payment']));
}

// ============================================================================
// BILLING CUSTOMER LIST RESPONSE
// ============================================================================

class BillingCustomerListResponse {
  final List<BillingCustomer> customers;
  final Pagination pagination;

  const BillingCustomerListResponse({ required this.customers, required this.pagination });

  factory BillingCustomerListResponse.fromJson(Map<String, dynamic> json) {
    final customersData  = json['data']?['customers'] ?? json['data'] ?? [];
    final rawPagination  = json['data']?['pagination'] ?? json['pagination'] ?? {};
    final normPagination = {
      'total': rawPagination['totalCount']  ?? rawPagination['total']  ?? (customersData as List).length,
      'page':  rawPagination['currentPage'] ?? rawPagination['page']   ?? 1,
      'limit': rawPagination['pageSize']    ?? rawPagination['limit']  ?? 50,
      'pages': rawPagination['totalPages']  ?? rawPagination['pages']  ?? 1,
    };
    return BillingCustomerListResponse(
      customers:  (customersData as List).map((c) => BillingCustomer.fromJson(c)).toList(),
      pagination: Pagination.fromJson(normPagination),
    );
  }
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
    required this.id, required this.date,
    required this.expenseAccount, required this.amount,
    required this.tax, required this.total,
    required this.billableAmount, required this.markupPercentage,
    required this.paidThrough, this.vendor, this.customerName,
    this.project, this.notes, this.isSelected = false,
  });

  factory BillableExpense.fromJson(Map<String, dynamic> json) {
    return BillableExpense(
      id:               json['_id']               ?? json['id'] ?? '',
      date:             json['date']              ?? '',
      expenseAccount:   json['expenseAccount']    ?? '',
      amount:           (json['amount']           ?? 0).toDouble(),
      tax:              (json['tax']              ?? 0).toDouble(),
      total:            (json['total']            ?? 0).toDouble(),
      billableAmount:   (json['billableAmount']   ?? 0).toDouble(),
      markupPercentage: (json['markupPercentage'] ?? 0).toDouble(),
      paidThrough:      json['paidThrough']       ?? '',
      vendor:           json['vendor'],
      customerName:     json['customerName'],
      project:          json['project'],
      notes:            json['notes'],
      isSelected:       false,
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id, 'date': date, 'expenseAccount': expenseAccount,
    'amount': amount, 'tax': tax, 'total': total,
    'billableAmount': billableAmount, 'markupPercentage': markupPercentage,
    'paidThrough': paidThrough, 'vendor': vendor,
    'customerName': customerName, 'project': project, 'notes': notes,
  };
}