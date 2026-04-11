// ============================================================================
// BILLING VENDORS SERVICE - COMPLETE (ZOHO BOOKS STYLE)
// ============================================================================
// File: lib/core/services/billing_vendors_service.dart
//
// NEW in this version:
// ✅ VendorAddress model (attention, street, city, state, zip, country,
//    phone, fax)
// ✅ VendorContactPerson model (full Zoho fields + portalAccess)
// ✅ VendorComment model
// ✅ BillingVendor model fully updated with all new Zoho fields
// ✅ VendorTransaction model (Bills, POs, Payments Made, Vendor Credits)
// ✅ VendorOverviewData model
// ✅ VendorStatementEntry model
// ✅ VendorMail model
// ✅ MonthlyExpense model (for bar chart)
// ✅ New service methods: getVendorOverview, getVendorTransactions,
//    getVendorMails, getVendorStatement, addComment, deleteComment
// ✅ All existing CRUD methods preserved — nothing removed
// ============================================================================

import 'package:flutter/foundation.dart';
import 'api_service.dart';

// ============================================================================
// CUSTOM EXCEPTION
// ============================================================================

class BillingVendorsException implements Exception {
  final String      message;
  final int?        statusCode;
  final List<String>? errors;

  BillingVendorsException(this.message, [this.statusCode, this.errors]);

  String toUserMessage() {
    if (errors != null && errors!.isNotEmpty) return errors!.join('\n');
    switch (statusCode) {
      case 400: return message.isNotEmpty ? message : 'Invalid vendor data.';
      case 401: return 'Authentication failed. Please login again.';
      case 403: return 'You do not have permission for this action.';
      case 404: return 'Vendor not found.';
      case 409: return 'A vendor with this email already exists.';
      case 500: return 'Server error. Please try again later.';
      default : return message.isNotEmpty ? message : 'An unexpected error occurred.';
    }
  }

  @override
  String toString() => 'BillingVendorsException: $message (Status: $statusCode)';
}

// ============================================================================
// VENDOR ADDRESS MODEL
// ============================================================================

class VendorAddress {
  final String attention;
  final String street;
  final String city;
  final String state;
  final String zip;
  final String country;
  final String phone;
  final String fax;

  const VendorAddress({
    this.attention = '',
    this.street    = '',
    this.city      = '',
    this.state     = '',
    this.zip       = '',
    this.country   = 'India',
    this.phone     = '',
    this.fax       = '',
  });

  factory VendorAddress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const VendorAddress();
    return VendorAddress(
      attention: json['attention'] ?? '',
      street   : json['street']    ?? '',
      city     : json['city']      ?? '',
      state    : json['state']     ?? '',
      zip      : json['zip']       ?? '',
      country  : json['country']   ?? 'India',
      phone    : json['phone']     ?? '',
      fax      : json['fax']       ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'attention': attention,
    'street'   : street,
    'city'     : city,
    'state'    : state,
    'zip'      : zip,
    'country'  : country,
    'phone'    : phone,
    'fax'      : fax,
  };

  bool get isEmpty =>
      attention.isEmpty && street.isEmpty && city.isEmpty &&
      state.isEmpty     && zip.isEmpty    && country == 'India' &&
      phone.isEmpty     && fax.isEmpty;

  String get formatted {
    final parts = <String>[
      if (attention.isNotEmpty) attention,
      if (street.isNotEmpty)    street,
      if (city.isNotEmpty)      city,
      if (state.isNotEmpty)     state,
      if (zip.isNotEmpty)       zip,
      if (country.isNotEmpty)   country,
    ];
    return parts.join(', ');
  }
}

// ============================================================================
// VENDOR CONTACT PERSON MODEL
// ============================================================================

class VendorContactPerson {
  final String  id;
  final String  salutation;
  final String  firstName;
  final String  lastName;
  final String  email;
  final String  workPhone;
  final String  mobile;
  final String  designation;
  final String  department;
  final bool    portalAccess;

  const VendorContactPerson({
    this.id           = '',
    this.salutation   = '',
    this.firstName    = '',
    this.lastName     = '',
    this.email        = '',
    this.workPhone    = '',
    this.mobile       = '',
    this.designation  = '',
    this.department   = '',
    this.portalAccess = false,
  });

  factory VendorContactPerson.fromJson(Map<String, dynamic> json) {
    return VendorContactPerson(
      id          : json['_id']         ?? '',
      salutation  : json['salutation']  ?? '',
      firstName   : json['firstName']   ?? '',
      lastName    : json['lastName']    ?? '',
      email       : json['email']       ?? '',
      workPhone   : json['workPhone']   ?? '',
      mobile      : json['mobile']      ?? '',
      designation : json['designation'] ?? '',
      department  : json['department']  ?? '',
      portalAccess: json['portalAccess'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'salutation'  : salutation,
    'firstName'   : firstName,
    'lastName'    : lastName,
    'email'       : email,
    'workPhone'   : workPhone,
    'mobile'      : mobile,
    'designation' : designation,
    'department'  : department,
    'portalAccess': portalAccess,
  };

  String get fullName => '$salutation $firstName $lastName'.trim();
}

// ============================================================================
// VENDOR COMMENT MODEL
// ============================================================================

class VendorComment {
  final String   id;
  final String   text;
  final String   createdBy;
  final DateTime createdAt;

  const VendorComment({
    required this.id,
    required this.text,
    required this.createdBy,
    required this.createdAt,
  });

  factory VendorComment.fromJson(Map<String, dynamic> json) {
    return VendorComment(
      id       : json['_id']       ?? '',
      text     : json['text']      ?? '',
      createdBy: json['createdBy'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

// ============================================================================
// MONTHLY EXPENSE MODEL (for bar chart)
// ============================================================================

class MonthlyExpense {
  final int    year;
  final int    month;
  final String label;
  final double total;

  const MonthlyExpense({
    required this.year,
    required this.month,
    required this.label,
    required this.total,
  });

  factory MonthlyExpense.fromJson(Map<String, dynamic> json) {
    return MonthlyExpense(
      year : json['year']  ?? 0,
      month: json['month'] ?? 0,
      label: json['label'] ?? '',
      total: (json['total'] ?? 0).toDouble(),
    );
  }
}

// ============================================================================
// VENDOR OVERVIEW DATA
// ============================================================================

class VendorOverviewData {
  final String        currency;
  final double        outstandingPayables;
  final double        unusedCredits;
  final List<MonthlyExpense> monthlyExpenses;

  const VendorOverviewData({
    this.currency            = 'INR',
    this.outstandingPayables = 0,
    this.unusedCredits       = 0,
    this.monthlyExpenses     = const [],
  });

  factory VendorOverviewData.fromJson(Map<String, dynamic> json) {
    final payables = json['payables'] as Map<String, dynamic>? ?? {};
    final monthly  = (json['monthlyExpenses'] as List? ?? [])
        .map((e) => MonthlyExpense.fromJson(e))
        .toList();
    return VendorOverviewData(
      currency            : payables['currency']            ?? 'INR',
      outstandingPayables : (payables['outstandingPayables'] ?? 0).toDouble(),
      unusedCredits       : (payables['unusedCredits']       ?? 0).toDouble(),
      monthlyExpenses     : monthly,
    );
  }
}

// ============================================================================
// VENDOR TRANSACTION MODEL
// ============================================================================

class VendorTransaction {
  final String   type;   // Bill | PurchaseOrder | PaymentMade | VendorCredit
  final String   id;
  final String   number;
  final DateTime date;
  final String   status;
  final double   amount;
  final double?  amountDue;
  final double?  amountPaid;
  final double?  balanceAmount;
  final DateTime? dueDate;

  const VendorTransaction({
    required this.type,
    required this.id,
    required this.number,
    required this.date,
    required this.status,
    required this.amount,
    this.amountDue,
    this.amountPaid,
    this.balanceAmount,
    this.dueDate,
  });

  factory VendorTransaction.fromJson(Map<String, dynamic> json) {
    return VendorTransaction(
      type         : json['type']          ?? '',
      id           : json['id']            ?? '',
      number       : json['number']        ?? '',
      date         : json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      status       : json['status']        ?? '',
      amount       : (json['amount']       ?? 0).toDouble(),
      amountDue    : json['amountDue']    != null ? (json['amountDue'] as num).toDouble()    : null,
      amountPaid   : json['amountPaid']   != null ? (json['amountPaid'] as num).toDouble()   : null,
      balanceAmount: json['balanceAmount'] != null ? (json['balanceAmount'] as num).toDouble(): null,
      dueDate      : json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
    );
  }
}

// ============================================================================
// VENDOR MAIL MODEL
// ============================================================================

class VendorMail {
  final String   source;
  final String   documentNumber;
  final String   sentTo;
  final DateTime sentAt;
  final String   subject;
  final String   emailType;

  const VendorMail({
    required this.source,
    required this.documentNumber,
    required this.sentTo,
    required this.sentAt,
    required this.subject,
    required this.emailType,
  });

  factory VendorMail.fromJson(Map<String, dynamic> json) {
    return VendorMail(
      source        : json['source']         ?? '',
      documentNumber: json['documentNumber'] ?? '',
      sentTo        : json['sentTo']         ?? '',
      sentAt        : json['sentAt'] != null
          ? DateTime.parse(json['sentAt'])
          : DateTime.now(),
      subject       : json['subject']   ?? '',
      emailType     : json['emailType'] ?? '',
    );
  }
}

// ============================================================================
// VENDOR STATEMENT ENTRY
// ============================================================================

class VendorStatementEntry {
  final DateTime date;
  final String   type;
  final String   number;
  final double   debit;
  final double   credit;
  final double   balance;
  final String   description;

  const VendorStatementEntry({
    required this.date,
    required this.type,
    required this.number,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.description,
  });

  factory VendorStatementEntry.fromJson(Map<String, dynamic> json) {
    return VendorStatementEntry(
      date       : json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      type       : json['type']        ?? '',
      number     : json['number']      ?? '',
      debit      : (json['debit']      ?? 0).toDouble(),
      credit     : (json['credit']     ?? 0).toDouble(),
      balance    : (json['balance']    ?? 0).toDouble(),
      description: json['description'] ?? '',
    );
  }
}

// ============================================================================
// BILLING VENDOR MODEL
// ============================================================================

class BillingVendor {
  final String id;
  final String vendorId;
  final String vendorName;
  final String companyName;
  final String email;
  final String phoneNumber;
  final String alternatePhone;
  final String vendorType;
  final String status;

  // Other Details
  final String  defaultCurrency;
  final String  paymentTerms;
  final String  portalLanguage;
  final bool    portalEnabled;
  final String  facebook;
  final String  twitter;
  final double  openingBalance;
  final DateTime? openingBalanceAsOf;

  // Tax Info
  final String gstNumber;
  final String gstRegistrationType;
  final String placeOfSupply;
  final String panNumber;
  final String taxPreference;
  final String exemptionReason;
  final bool   tdsApplicable;
  final String tdsSection;
  final double tdsRate;

  // Address
  final VendorAddress billingAddress;
  final VendorAddress shippingAddress;

  // Bank Details
  final bool   bankDetailsProvided;
  final String accountHolderName;
  final String bankName;
  final String accountNumber;
  final String ifscCode;

  // Legacy flat address (backward compat)
  final bool   addressProvided;
  final String addressLine1;
  final String addressLine2;
  final String city;
  final String state;
  final String postalCode;
  final String country;

  // Contact Persons
  final List<VendorContactPerson> contactPersons;

  // Remarks / Comments
  final String             remarks;
  final List<VendorComment> comments;

  // Additional
  final String serviceCategory;
  final String notes;

  // Audit
  final DateTime? createdDate;

  const BillingVendor({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    this.companyName        = '',
    required this.email,
    required this.phoneNumber,
    this.alternatePhone     = '',
    this.vendorType         = 'External Vendor',
    this.status             = 'Active',
    this.defaultCurrency    = 'INR',
    this.paymentTerms       = 'Net 30',
    this.portalLanguage     = 'English',
    this.portalEnabled      = false,
    this.facebook           = '',
    this.twitter            = '',
    this.openingBalance     = 0,
    this.openingBalanceAsOf,
    this.gstNumber          = '',
    this.gstRegistrationType = '',
    this.placeOfSupply      = '',
    this.panNumber          = '',
    this.taxPreference      = 'Taxable',
    this.exemptionReason    = '',
    this.tdsApplicable      = false,
    this.tdsSection         = '',
    this.tdsRate            = 0,
    this.billingAddress     = const VendorAddress(),
    this.shippingAddress    = const VendorAddress(),
    this.bankDetailsProvided = false,
    this.accountHolderName  = '',
    this.bankName           = '',
    this.accountNumber      = '',
    this.ifscCode           = '',
    this.addressProvided    = false,
    this.addressLine1       = '',
    this.addressLine2       = '',
    this.city               = '',
    this.state              = '',
    this.postalCode         = '',
    this.country            = 'India',
    this.contactPersons     = const [],
    this.remarks            = '',
    this.comments           = const [],
    this.serviceCategory    = '',
    this.notes              = '',
    this.createdDate,
  });

  factory BillingVendor.fromJson(Map<String, dynamic> json) {
    return BillingVendor(
      id              : json['_id']           ?? '',
      vendorId        : json['vendorId']       ?? '',
      vendorName      : json['vendorName']     ?? '',
      companyName     : json['companyName']    ?? '',
      email           : json['email']          ?? '',
      phoneNumber     : json['phoneNumber']    ?? '',
      alternatePhone  : json['alternatePhone'] ?? '',
      vendorType      : json['vendorType']     ?? 'External Vendor',
      status          : json['status']         ?? 'Active',
      defaultCurrency : json['defaultCurrency']     ?? 'INR',
      paymentTerms    : json['paymentTerms']        ?? 'Net 30',
      portalLanguage  : json['portalLanguage']      ?? 'English',
      portalEnabled   : json['portalEnabled']       == true,
      facebook        : json['facebook']            ?? '',
      twitter         : json['twitter']             ?? '',
      openingBalance  : (json['openingBalance']     ?? 0).toDouble(),
      openingBalanceAsOf: json['openingBalanceAsOf'] != null
          ? DateTime.parse(json['openingBalanceAsOf'])
          : null,
      gstNumber           : json['gstNumber']            ?? '',
      gstRegistrationType : json['gstRegistrationType']  ?? '',
      placeOfSupply       : json['placeOfSupply']         ?? '',
      panNumber           : json['panNumber']             ?? '',
      taxPreference       : json['taxPreference']         ?? 'Taxable',
      exemptionReason     : json['exemptionReason']       ?? '',
      tdsApplicable       : json['tdsApplicable']         == true,
      tdsSection          : json['tdsSection']            ?? '',
      tdsRate             : (json['tdsRate']              ?? 0).toDouble(),
      billingAddress      : VendorAddress.fromJson(json['billingAddress']),
      shippingAddress     : VendorAddress.fromJson(json['shippingAddress']),
      bankDetailsProvided : json['bankDetailsProvided']   == true,
      accountHolderName   : json['accountHolderName']     ?? '',
      bankName            : json['bankName']              ?? '',
      accountNumber       : json['accountNumber']         ?? '',
      ifscCode            : json['ifscCode']              ?? '',
      addressProvided     : json['addressProvided']       == true,
      addressLine1        : json['addressLine1']          ?? '',
      addressLine2        : json['addressLine2']          ?? '',
      city                : json['city']                  ?? '',
      state               : json['state']                 ?? '',
      postalCode          : json['postalCode']            ?? '',
      country             : json['country']               ?? 'India',
      contactPersons      : (json['contactPersons'] as List? ?? [])
          .map((e) => VendorContactPerson.fromJson(e))
          .toList(),
      remarks  : json['remarks']  ?? '',
      comments : (json['comments'] as List? ?? [])
          .map((e) => VendorComment.fromJson(e))
          .toList(),
      serviceCategory: json['serviceCategory'] ?? '',
      notes          : json['notes']           ?? '',
      createdDate    : json['createdDate'] != null
          ? DateTime.parse(json['createdDate'])
          : null,
    );
  }

  // Backward-compat getters used by existing UI code
  String get vendorDisplayName      => vendorName;
  String get primaryEmail           => email;
  String get primaryPhone           => phoneNumber;
  String get gstRegistrationTypeLeg => gstRegistrationType;
}

// ============================================================================
// BILLING VENDORS SERVICE
// ============================================================================

class BillingVendorsService {
  static final ApiService _api = ApiService();

  // ── CREATE ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> createVendor({
    required String vendorType,
    required String vendorName,
    String? companyName,
    required String email,
    required String phoneNumber,
    String? alternatePhone,
    String  status           = 'Active',
    // Other Details
    String  defaultCurrency  = 'INR',
    String  paymentTerms     = 'Net 30',
    String? portalLanguage,
    bool    portalEnabled    = false,
    String? facebook,
    String? twitter,
    double  openingBalance   = 0,
    String? openingBalanceAsOf,
    // Tax Info
    String? gstNumber,
    String? gstRegistrationType,
    String? placeOfSupply,
    String? panNumber,
    String  taxPreference    = 'Taxable',
    String? exemptionReason,
    bool    tdsApplicable    = false,
    String? tdsSection,
    double  tdsRate          = 0,
    // Address
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddress,
    // Bank Details (legacy)
    bool    bankDetailsProvided = false,
    String? accountHolderName,
    String? bankName,
    String? accountNumber,
    String? accountNumberConfirm,
    String? ifscCode,
    // Flat address (legacy)
    bool    addressProvided  = false,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    // Contact Persons
    List<Map<String, dynamic>>? contactPersons,
    // Remarks
    String? remarks,
    String? serviceCategory,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        'vendorType'    : vendorType,
        'vendorName'    : vendorName,
        'companyName'   : companyName    ?? '',
        'email'         : email,
        'phoneNumber'   : phoneNumber,
        'alternatePhone': alternatePhone ?? '',
        'status'        : status,
        'defaultCurrency'   : defaultCurrency,
        'paymentTerms'      : paymentTerms,
        'portalLanguage'    : portalLanguage    ?? 'English',
        'portalEnabled'     : portalEnabled,
        'facebook'          : facebook          ?? '',
        'twitter'           : twitter           ?? '',
        'openingBalance'    : openingBalance,
        'openingBalanceAsOf': openingBalanceAsOf,
        'gstNumber'          : gstNumber           ?? '',
        'gstRegistrationType': gstRegistrationType ?? '',
        'placeOfSupply'      : placeOfSupply        ?? '',
        'panNumber'          : panNumber            ?? '',
        'taxPreference'      : taxPreference,
        'exemptionReason'    : exemptionReason      ?? '',
        'tdsApplicable'      : tdsApplicable,
        'tdsSection'         : tdsSection           ?? '',
        'tdsRate'            : tdsRate,
        'billingAddress'     : billingAddress        ?? {},
        'shippingAddress'    : shippingAddress       ?? {},
        'bankDetailsProvided': bankDetailsProvided,
        'accountHolderName'  : accountHolderName     ?? '',
        'bankName'           : bankName              ?? '',
        'accountNumber'      : accountNumber         ?? '',
        'accountNumberConfirm': accountNumberConfirm ?? '',
        'ifscCode'           : ifscCode              ?? '',
        'addressProvided'    : addressProvided,
        'addressLine1'       : addressLine1          ?? '',
        'addressLine2'       : addressLine2          ?? '',
        'city'               : city                  ?? '',
        'state'              : state                 ?? '',
        'postalCode'         : postalCode            ?? '',
        'country'            : country               ?? 'India',
        'contactPersons'     : contactPersons        ?? [],
        'remarks'            : remarks               ?? '',
        'serviceCategory'    : serviceCategory       ?? '',
        'notes'              : notes                 ?? '',
      };

      return await _api.post('/api/finance/vendors', body: body);
    } on ApiException catch (e) {
      final errs = e.details?['errors'] != null
          ? List<String>.from(e.details!['errors'])
          : null;
      throw BillingVendorsException(e.message, e.statusCode, errs);
    } catch (e) {
      throw BillingVendorsException('Failed to create vendor: $e');
    }
  }

  // ── GET ALL ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAllVendors({
    String? search,
    String? vendorType,
    String? status,
    int     page      = 1,
    int     limit     = 1000,
    String  sortBy    = 'createdDate',
    String  sortOrder = 'desc',
  }) async {
    try {
      final q = <String, String>{};
      if (search     != null && search.isNotEmpty)     q['search']     = search;
      if (vendorType != null && vendorType.isNotEmpty) q['vendorType'] = vendorType;
      if (status     != null && status.isNotEmpty)     q['status']     = status;
      q['page']      = page.toString();
      q['limit']     = limit.toString();
      q['sortBy']    = sortBy;
      q['sortOrder'] = sortOrder;

      return await _api.get('/api/finance/vendors', queryParams: q);
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to fetch vendors: $e');
    }
  }

  // ── GET SIMPLE LIST (for dropdowns) ────────────────────────────────────────

  static Future<List<BillingVendor>> getVendors() async {
    try {
      final response = await getAllVendors(limit: 1000);
      final raw      = response['data'];
      final list     = raw is List
          ? raw
          : (raw['vendors'] as List? ?? []);
      return list.map((v) => BillingVendor.fromJson(v)).toList();
    } catch (e) {
      debugPrint('❌ Error in getVendors: $e');
      return [];
    }
  }

  // ── GET BY ID ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getVendorById(String vendorId) async {
    try {
      return await _api.get('/api/finance/vendors/$vendorId');
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to fetch vendor: $e');
    }
  }

  // ── GET OVERVIEW ───────────────────────────────────────────────────────────

  static Future<VendorOverviewData> getVendorOverview(String vendorId) async {
    try {
      final response = await _api.get('/api/finance/vendors/$vendorId/overview');
      return VendorOverviewData.fromJson(response['data'] ?? {});
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to fetch vendor overview: $e');
    }
  }

  // ── GET TRANSACTIONS ───────────────────────────────────────────────────────

  static Future<List<VendorTransaction>> getVendorTransactions(
    String vendorId, {
    String? fromDate,
    String? toDate,
    String? type,
  }) async {
    try {
      final q = <String, String>{};
      if (fromDate != null) q['fromDate'] = fromDate;
      if (toDate   != null) q['toDate']   = toDate;
      if (type     != null) q['type']     = type;

      final response = await _api.get(
        '/api/finance/vendors/$vendorId/transactions',
        queryParams: q,
      );
      final list = response['data'] as List? ?? [];
      return list.map((e) => VendorTransaction.fromJson(e)).toList();
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to fetch transactions: $e');
    }
  }

  // ── GET MAILS ──────────────────────────────────────────────────────────────

  static Future<List<VendorMail>> getVendorMails(String vendorId) async {
    try {
      final response = await _api.get('/api/finance/vendors/$vendorId/mails');
      final list     = response['data'] as List? ?? [];
      return list.map((e) => VendorMail.fromJson(e)).toList();
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to fetch mails: $e');
    }
  }

  // ── GET STATEMENT ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getVendorStatement(
    String vendorId, {
    String? fromDate,
    String? toDate,
  }) async {
    try {
      final q = <String, String>{};
      if (fromDate != null) q['fromDate'] = fromDate;
      if (toDate   != null) q['toDate']   = toDate;

      final response = await _api.get(
        '/api/finance/vendors/$vendorId/statement',
        queryParams: q,
      );
      return response['data'] ?? {};
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to fetch statement: $e');
    }
  }

  // ── ADD COMMENT ────────────────────────────────────────────────────────────

  static Future<List<VendorComment>> addComment(
      String vendorId, String text) async {
    try {
      final response = await _api.post(
        '/api/finance/vendors/$vendorId/comments',
        body: {'text': text},
      );
      final list = response['data'] as List? ?? [];
      return list.map((e) => VendorComment.fromJson(e)).toList();
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to add comment: $e');
    }
  }

  // ── DELETE COMMENT ─────────────────────────────────────────────────────────

  static Future<List<VendorComment>> deleteComment(
      String vendorId, String commentId) async {
    try {
      final response = await _api.delete(
        '/api/finance/vendors/$vendorId/comments/$commentId',
      );
      final list = response['data'] as List? ?? [];
      return list.map((e) => VendorComment.fromJson(e)).toList();
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to delete comment: $e');
    }
  }

  // ── UPDATE ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> updateVendor({
    required String vendorId,
    String? vendorType,
    String? vendorName,
    String? companyName,
    String? email,
    String? phoneNumber,
    String? alternatePhone,
    String? status,
    String? defaultCurrency,
    String? paymentTerms,
    String? portalLanguage,
    bool?   portalEnabled,
    String? facebook,
    String? twitter,
    double? openingBalance,
    String? openingBalanceAsOf,
    String? gstNumber,
    String? gstRegistrationType,
    String? placeOfSupply,
    String? panNumber,
    String? taxPreference,
    String? exemptionReason,
    bool?   tdsApplicable,
    String? tdsSection,
    double? tdsRate,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddress,
    bool?   bankDetailsProvided,
    String? accountHolderName,
    String? bankName,
    String? accountNumber,
    String? accountNumberConfirm,
    String? ifscCode,
    bool?   addressProvided,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    List<Map<String, dynamic>>? contactPersons,
    String? remarks,
    String? serviceCategory,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (vendorType          != null) body['vendorType']           = vendorType;
      if (vendorName          != null) body['vendorName']           = vendorName;
      if (companyName         != null) body['companyName']          = companyName;
      if (email               != null) body['email']                = email;
      if (phoneNumber         != null) body['phoneNumber']          = phoneNumber;
      if (alternatePhone      != null) body['alternatePhone']       = alternatePhone;
      if (status              != null) body['status']               = status;
      if (defaultCurrency     != null) body['defaultCurrency']      = defaultCurrency;
      if (paymentTerms        != null) body['paymentTerms']         = paymentTerms;
      if (portalLanguage      != null) body['portalLanguage']       = portalLanguage;
      if (portalEnabled       != null) body['portalEnabled']        = portalEnabled;
      if (facebook            != null) body['facebook']             = facebook;
      if (twitter             != null) body['twitter']              = twitter;
      if (openingBalance      != null) body['openingBalance']       = openingBalance;
      if (openingBalanceAsOf  != null) body['openingBalanceAsOf']   = openingBalanceAsOf;
      if (gstNumber           != null) body['gstNumber']            = gstNumber;
      if (gstRegistrationType != null) body['gstRegistrationType']  = gstRegistrationType;
      if (placeOfSupply       != null) body['placeOfSupply']        = placeOfSupply;
      if (panNumber           != null) body['panNumber']            = panNumber;
      if (taxPreference       != null) body['taxPreference']        = taxPreference;
      if (exemptionReason     != null) body['exemptionReason']      = exemptionReason;
      if (tdsApplicable       != null) body['tdsApplicable']        = tdsApplicable;
      if (tdsSection          != null) body['tdsSection']           = tdsSection;
      if (tdsRate             != null) body['tdsRate']              = tdsRate;
      if (billingAddress      != null) body['billingAddress']       = billingAddress;
      if (shippingAddress     != null) body['shippingAddress']      = shippingAddress;
      if (bankDetailsProvided != null) body['bankDetailsProvided']  = bankDetailsProvided;
      if (accountHolderName   != null) body['accountHolderName']    = accountHolderName;
      if (bankName            != null) body['bankName']             = bankName;
      if (accountNumber       != null) body['accountNumber']        = accountNumber;
      if (accountNumberConfirm != null) body['accountNumberConfirm'] = accountNumberConfirm;
      if (ifscCode            != null) body['ifscCode']             = ifscCode;
      if (addressProvided     != null) body['addressProvided']      = addressProvided;
      if (addressLine1        != null) body['addressLine1']         = addressLine1;
      if (addressLine2        != null) body['addressLine2']         = addressLine2;
      if (city                != null) body['city']                 = city;
      if (state               != null) body['state']               = state;
      if (postalCode          != null) body['postalCode']           = postalCode;
      if (country             != null) body['country']              = country;
      if (contactPersons      != null) body['contactPersons']       = contactPersons;
      if (remarks             != null) body['remarks']              = remarks;
      if (serviceCategory     != null) body['serviceCategory']      = serviceCategory;
      if (notes               != null) body['notes']                = notes;

      return await _api.put('/api/finance/vendors/$vendorId', body: body);
    } on ApiException catch (e) {
      final errs = e.details?['errors'] != null
          ? List<String>.from(e.details!['errors'])
          : null;
      throw BillingVendorsException(e.message, e.statusCode, errs);
    } catch (e) {
      throw BillingVendorsException('Failed to update vendor: $e');
    }
  }

  // ── DELETE ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> deleteVendor(String vendorId) async {
    try {
      return await _api.delete('/api/finance/vendors/$vendorId');
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to delete vendor: $e');
    }
  }

  // ── BULK IMPORT ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> bulkImportVendors(
    List<Map<String, dynamic>> vendors,
  ) async {
    try {
      return await _api.post(
        '/api/finance/vendors/bulk-import',
        body: {'vendors': vendors},
      );
    } on ApiException catch (e) {
      throw BillingVendorsException(e.message, e.statusCode);
    } catch (e) {
      throw BillingVendorsException('Failed to import vendors: $e');
    }
  }
}