// ============================================================================
// CURRENCY ADJUSTMENT SERVICE
// ============================================================================
// File: lib/core/services/currency_adjustment_service.dart
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';

// ============================================================================
// MODELS
// ============================================================================

class AdjustmentLineItem {
  final String id;
  final String transactionType;
  final String transactionId;
  final String transactionNumber;
  final String partyName;
  final String? partyId;
  final double amountDue;
  final double originalRate;
  final double newRate;
  final double gainLoss;
  final double baseCurrencyGainLoss;
  final DateTime? dueDate;
  final String status;

  AdjustmentLineItem({
    required this.id,
    required this.transactionType,
    required this.transactionId,
    required this.transactionNumber,
    required this.partyName,
    this.partyId,
    required this.amountDue,
    required this.originalRate,
    required this.newRate,
    required this.gainLoss,
    required this.baseCurrencyGainLoss,
    this.dueDate,
    required this.status,
  });

  factory AdjustmentLineItem.fromJson(Map<String, dynamic> j) => AdjustmentLineItem(
    id:                   j['_id']?.toString() ?? j['id']?.toString() ?? '',
    transactionType:      j['transactionType'] ?? '',
    transactionId:        j['transactionId']?.toString() ?? '',
    transactionNumber:    j['transactionNumber'] ?? '',
    partyName:            j['partyName'] ?? '',
    partyId:              j['partyId']?.toString(),
    amountDue:            (j['amountDue'] ?? 0).toDouble(),
    originalRate:         (j['originalRate'] ?? 1).toDouble(),
    newRate:              (j['newRate'] ?? 1).toDouble(),
    gainLoss:             (j['gainLoss'] ?? 0).toDouble(),
    baseCurrencyGainLoss: (j['baseCurrencyGainLoss'] ?? 0).toDouble(),
    dueDate:              j['dueDate'] != null ? DateTime.tryParse(j['dueDate']) : null,
    status:               j['status'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'transactionType':      transactionType,
    'transactionId':        transactionId,
    'transactionNumber':    transactionNumber,
    'partyName':            partyName,
    'partyId':              partyId,
    'amountDue':            amountDue,
    'originalRate':         originalRate,
    'newRate':              newRate,
    'gainLoss':             gainLoss,
    'baseCurrencyGainLoss': baseCurrencyGainLoss,
    'dueDate':              dueDate?.toIso8601String(),
    'status':               status,
  };
}

class CurrencyAdjustment {
  final String id;
  final String adjustmentNumber;
  final DateTime adjustmentDate;
  final String currency;
  final double newExchangeRate;
  final String notes;
  final List<AdjustmentLineItem> lineItems;
  final double totalGain;
  final double totalLoss;
  final double netAdjustment;
  final int totalTransactions;
  final String status;
  final bool coaEntriesCreated;
  final String? journalId;
  final String? journalNumber;
  final String? voidReason;
  final DateTime? voidedAt;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  CurrencyAdjustment({
    required this.id,
    required this.adjustmentNumber,
    required this.adjustmentDate,
    required this.currency,
    required this.newExchangeRate,
    required this.notes,
    required this.lineItems,
    required this.totalGain,
    required this.totalLoss,
    required this.netAdjustment,
    required this.totalTransactions,
    required this.status,
    required this.coaEntriesCreated,
    this.journalId,
    this.journalNumber,
    this.voidReason,
    this.voidedAt,
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CurrencyAdjustment.fromJson(Map<String, dynamic> j) => CurrencyAdjustment(
    id:                 j['_id']?.toString() ?? j['id']?.toString() ?? '',
    adjustmentNumber:   j['adjustmentNumber'] ?? '',
    adjustmentDate:     DateTime.tryParse(j['adjustmentDate'] ?? '') ?? DateTime.now(),
    currency:           j['currency'] ?? '',
    newExchangeRate:    (j['newExchangeRate'] ?? 1).toDouble(),
    notes:              j['notes'] ?? '',
    lineItems:          (j['lineItems'] as List? ?? []).map((l) => AdjustmentLineItem.fromJson(l)).toList(),
    totalGain:          (j['totalGain'] ?? 0).toDouble(),
    totalLoss:          (j['totalLoss'] ?? 0).toDouble(),
    netAdjustment:      (j['netAdjustment'] ?? 0).toDouble(),
    totalTransactions:  j['totalTransactions'] ?? 0,
    status:             j['status'] ?? 'Draft',
    coaEntriesCreated:  j['coaEntriesCreated'] ?? false,
    journalId:          j['journalId']?.toString(),
    journalNumber:      j['journalNumber'],
    voidReason:         j['voidReason'],
    voidedAt:           j['voidedAt']    != null ? DateTime.tryParse(j['voidedAt'])    : null,
    publishedAt:        j['publishedAt'] != null ? DateTime.tryParse(j['publishedAt']) : null,
    createdAt:          DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    updatedAt:          DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
  );
}

class AdjustmentStats {
  final int total;
  final int draft;
  final int published;
  final int voided;
  final double totalGain;
  final double totalLoss;
  final double netAdjustment;

  AdjustmentStats({
    required this.total,    required this.draft,
    required this.published, required this.voided,
    required this.totalGain, required this.totalLoss,
    required this.netAdjustment,
  });

  factory AdjustmentStats.fromJson(Map<String, dynamic> j) => AdjustmentStats(
    total:         j['total']          ?? 0,
    draft:         j['draft']          ?? 0,
    published:     j['published']      ?? 0,
    voided:        j['voided']         ?? 0,
    totalGain:     (j['totalGain']     ?? 0).toDouble(),
    totalLoss:     (j['totalLoss']     ?? 0).toDouble(),
    netAdjustment: (j['netAdjustment'] ?? 0).toDouble(),
  );
}

class AdjustmentListResult {
  final List<CurrencyAdjustment> adjustments;
  final int total, page, pages;
  AdjustmentListResult({ required this.adjustments, required this.total, required this.page, required this.pages });
}

class OpenTransaction {
  final String transactionType;
  final String transactionId;
  final String transactionNumber;
  final String partyName;
  final double amountDue;
  final double originalRate;
  final DateTime? dueDate;
  final String status;
  final String currency;

  OpenTransaction({
    required this.transactionType, required this.transactionId,
    required this.transactionNumber, required this.partyName,
    required this.amountDue, required this.originalRate,
    this.dueDate, required this.status, required this.currency,
  });

  factory OpenTransaction.fromJson(Map<String, dynamic> j) => OpenTransaction(
    transactionType:   j['transactionType']   ?? '',
    transactionId:     j['transactionId']?.toString() ?? '',
    transactionNumber: j['transactionNumber'] ?? '',
    partyName:         j['partyName']         ?? '',
    amountDue:         (j['amountDue']        ?? 0).toDouble(),
    originalRate:      (j['originalRate']     ?? 1).toDouble(),
    dueDate:           j['dueDate'] != null ? DateTime.tryParse(j['dueDate']) : null,
    status:            j['status']            ?? '',
    currency:          j['currency']          ?? '',
  );

  double calculateGainLoss(double newRate) {
    if (transactionType == 'Invoice') return (newRate - originalRate) * amountDue;
    return (originalRate - newRate) * amountDue;
  }
}

// ============================================================================
// SERVICE
// ============================================================================

class CurrencyAdjustmentService {
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final keys  = ['jwt_token','token','auth_token','accessToken','access_token'];
    String token = '';
    for (final k in keys) { token = prefs.getString(k) ?? ''; if (token.isNotEmpty) break; }
    return {
      'Content-Type': 'application/json',
      'Accept':       'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static String get _base => '${ApiConfig.baseUrl}/api/finance/currency-adjustments';

  static Future<AdjustmentStats> getStats() async {
    final h = await _getHeaders();
    final r = await http.get(Uri.parse('$_base/stats'), headers: h);
    final b = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed');
    return AdjustmentStats.fromJson(b['data']);
  }

  static Future<List<String>> getSupportedCurrencies() async {
    final h = await _getHeaders();
    final r = await http.get(Uri.parse('$_base/supported-currencies'), headers: h);
    final b = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed');
    return List<String>.from(b['data'] ?? []);
  }

  static Future<List<OpenTransaction>> getOpenTransactions(String currency) async {
    final h   = await _getHeaders();
    final uri = Uri.parse('$_base/open-transactions').replace(queryParameters: {'currency': currency});
    final r   = await http.get(uri, headers: h);
    final b   = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed to load transactions');
    return (b['data'] as List).map((t) => OpenTransaction.fromJson(t)).toList();
  }

  static Future<AdjustmentListResult> getAdjustments({
    String? status, String? currency,
    DateTime? fromDate, DateTime? toDate,
    String? search, int page = 1, int limit = 50,
  }) async {
    final h      = await _getHeaders();
    final params = <String, String>{ 'page': page.toString(), 'limit': limit.toString() };
    if (status   != null && status   != 'All') params['status']   = status;
    if (currency != null && currency != 'All') params['currency'] = currency;
    if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
    if (toDate   != null) params['toDate']   = toDate.toIso8601String();
    if (search   != null && search.isNotEmpty) params['search']   = search;

    final uri = Uri.parse(_base).replace(queryParameters: params);
    final r   = await http.get(uri, headers: h);
    final b   = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed');

    final data = b['data'];
    return AdjustmentListResult(
      adjustments: (data['adjustments'] as List).map((a) => CurrencyAdjustment.fromJson(a)).toList(),
      total: data['pagination']?['total'] ?? 0,
      page:  data['pagination']?['page']  ?? 1,
      pages: data['pagination']?['pages'] ?? 1,
    );
  }

  static Future<List<CurrencyAdjustment>> getAllForExport({ String? status, String? currency }) async {
    final r = await getAdjustments(status: status, currency: currency, limit: 10000);
    return r.adjustments;
  }

  static Future<CurrencyAdjustment> getAdjustment(String id) async {
    final h = await _getHeaders();
    final r = await http.get(Uri.parse('$_base/$id'), headers: h);
    final b = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed');
    return CurrencyAdjustment.fromJson(b['data']);
  }

  static Future<CurrencyAdjustment> createAdjustment(Map<String, dynamic> data) async {
    final h = await _getHeaders();
    final r = await http.post(Uri.parse(_base), headers: h, body: jsonEncode(data));
    final b = jsonDecode(r.body);
    if (r.statusCode != 201) throw Exception(b['message'] ?? 'Failed to create');
    return CurrencyAdjustment.fromJson(b['data']);
  }

  static Future<CurrencyAdjustment> updateAdjustment(String id, Map<String, dynamic> data) async {
    final h = await _getHeaders();
    final r = await http.put(Uri.parse('$_base/$id'), headers: h, body: jsonEncode(data));
    final b = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed to update');
    return CurrencyAdjustment.fromJson(b['data']);
  }

  static Future<CurrencyAdjustment> publishAdjustment(String id) async {
    final h = await _getHeaders();
    final r = await http.post(Uri.parse('$_base/$id/publish'), headers: h, body: '{}');
    final b = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed to publish');
    return CurrencyAdjustment.fromJson(b['data']);
  }

  static Future<CurrencyAdjustment> voidAdjustment(String id, {String reason = ''}) async {
    final h = await _getHeaders();
    final r = await http.post(Uri.parse('$_base/$id/void'), headers: h, body: jsonEncode({'reason': reason}));
    final b = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed to void');
    return CurrencyAdjustment.fromJson(b['data']);
  }

  static Future<void> deleteAdjustment(String id) async {
    final h = await _getHeaders();
    final r = await http.delete(Uri.parse('$_base/$id'), headers: h);
    final b = jsonDecode(r.body);
    if (r.statusCode != 200) throw Exception(b['message'] ?? 'Failed to delete');
  }

  static Future<Map<String, dynamic>> bulkImport(
    List<Map<String, dynamic>> adjustments,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final keys  = ['jwt_token','token','auth_token','accessToken','access_token'];
    String token = '';
    for (final k in keys) { token = prefs.getString(k) ?? ''; if (token.isNotEmpty) break; }

    final request = http.MultipartRequest('POST', Uri.parse('$_base/import'));
    if (token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
    request.fields['adjustments'] = jsonEncode(adjustments);

    final streamed = await request.send();
    final res  = await http.Response.fromStream(streamed);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Import failed');
    return body;
  }
}