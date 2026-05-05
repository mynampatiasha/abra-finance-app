// ============================================================================
// E-WAY BILL SERVICE — COMPLETE
// ============================================================================
// File: lib/core/services/eway_bill_service.dart
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/config/api_config.dart';
import '../../core/finance_secure_storage.dart';

class EWayBillService {
  static const String _base = '/api/finance/eway-bills';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('finance_jwt_token') ?? prefs.getString('jwt_token') ?? '';
    final branchHdr = await FinanceSecureStorage.getBranchHeader();
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'x-branch-ids': branchHdr,
    };
  }

  static Map<String, dynamic> _decode(http.Response r) =>
      json.decode(r.body) as Map<String, dynamic>;

  // ── Setup ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> connectPortal({
    required String gstin,
    required String username,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base/setup/connect'),
      headers: await _headers(),
      body: json.encode({'gstin': gstin, 'username': username, 'password': password}),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> getConnectionStatus() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/setup/status'),
      headers: await _headers(),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> disconnectPortal() async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}$_base/setup/disconnect'),
      headers: await _headers(),
    );
    return _decode(res);
  }

  // ── Smart notification ─────────────────────────────────────────────────────

  /// Returns count of invoices with totalAmount > ₹50,000 and no active EWB
  static Future<Map<String, dynamic>> getPendingCount() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/pending-count'),
      headers: await _headers(),
    );
    return _decode(res);
  }

  // ── List ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getEWayBills({
    String? status,
    String? sourceType,
    String? fromDate,
    String? toDate,
    String? search,
    int page  = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{
      'page': '$page', 'limit': '$limit',
      if (status     != null) 'status':     status,
      if (sourceType != null) 'sourceType': sourceType,
      if (fromDate   != null) 'fromDate':   fromDate,
      if (toDate     != null) 'toDate':     toDate,
      if (search     != null) 'search':     search,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base').replace(queryParameters: params);
    final res = await http.get(uri, headers: await _headers());
    return _decode(res);
  }

  static Future<Map<String, dynamic>> getEWayBillById(String id) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
      headers: await _headers(),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> getEWBsBySource(String sourceType, String sourceId) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/by-source/$sourceType/$sourceId'),
      headers: await _headers(),
    );
    return _decode(res);
  }

  // ── Generate ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> generateEWayBill(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base/generate'),
      headers: await _headers(),
      body: json.encode(data),
    );
    return _decode(res);
  }

  // ── PDF Print / Download ───────────────────────────────────────────────────

  /// Opens the EWB PDF download URL in the browser / triggers download
  static Future<Map<String, dynamic>> downloadEWBPdf(String ewbId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('finance_jwt_token') ?? prefs.getString('jwt_token') ?? '';
      final url   = '${ApiConfig.baseUrl}$_base/$ewbId/print?token=$token';
      final uri   = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return {'success': true, 'message': 'PDF opened in browser'};
      } else {
        return {'success': false, 'message': 'Cannot open PDF. Please try again.'};
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> updatePartB(String id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/update-part-b'),
      headers: await _headers(),
      body: json.encode(data),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> extendValidity(String id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/extend'),
      headers: await _headers(),
      body: json.encode(data),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> cancelEWayBill(String id, String cancelReason) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/cancel'),
      headers: await _headers(),
      body: json.encode({'cancelReason': cancelReason}),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> generateConsolidatedEWB(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base/consolidated'),
      headers: await _headers(),
      body: json.encode(data),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> associateEWB(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base/associate'),
      headers: await _headers(),
      body: json.encode(data),
    );
    return _decode(res);
  }
}

// ============================================================================
// MODELS
// ============================================================================

class EWayBillModel {
  final String   id;
  final String   orgId;
  final String   sourceType;
  final String   sourceId;
  final String   sourceNumber;
  final String?  ewbNumber;
  final DateTime? ewbDate;
  final DateTime? validUntil;
  final String   ewbStatus;
  final String   supplyType;
  final String   subType;
  final String   documentType;
  final String   documentNumber;
  final DateTime documentDate;
  final String   fromGstin;
  final String   fromTradeName;
  final String   fromPlace;
  final String   fromState;
  final String   toGstin;
  final String   toTradeName;
  final String   toPlace;
  final String   toState;
  final String   hsnCode;
  final String   productName;
  final double   quantity;
  final String   unit;
  final double   taxableAmount;
  final double   cgstRate;
  final double   sgstRate;
  final double   igstRate;
  final double   totalInvoiceValue;
  final String   transportMode;
  final double   approximateDistance;
  final String   transporterName;
  final String   transporterId;
  final String   vehicleNumber;
  final String   vehicleType;
  final String   fromPlacePartB;
  final bool     isConsolidated;
  final String?  consolidatedEwbNumber;
  final bool     isManuallyAssociated;
  final String?  cancelReason;
  final DateTime? cancelledAt;
  final DateTime createdAt;

  EWayBillModel({
    required this.id,
    required this.orgId,
    required this.sourceType,
    required this.sourceId,
    required this.sourceNumber,
    this.ewbNumber,
    this.ewbDate,
    this.validUntil,
    required this.ewbStatus,
    required this.supplyType,
    required this.subType,
    required this.documentType,
    required this.documentNumber,
    required this.documentDate,
    required this.fromGstin,
    required this.fromTradeName,
    required this.fromPlace,
    required this.fromState,
    required this.toGstin,
    required this.toTradeName,
    required this.toPlace,
    required this.toState,
    required this.hsnCode,
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.taxableAmount,
    required this.cgstRate,
    required this.sgstRate,
    required this.igstRate,
    required this.totalInvoiceValue,
    required this.transportMode,
    required this.approximateDistance,
    required this.transporterName,
    required this.transporterId,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.fromPlacePartB,
    required this.isConsolidated,
    this.consolidatedEwbNumber,
    required this.isManuallyAssociated,
    this.cancelReason,
    this.cancelledAt,
    required this.createdAt,
  });

  factory EWayBillModel.fromJson(Map<String, dynamic> j) => EWayBillModel(
    id:                  j['_id']             ?? '',
    orgId:               j['orgId']           ?? '',
    sourceType:          j['sourceType']      ?? '',
    sourceId:            j['sourceId']?.toString() ?? '',
    sourceNumber:        j['sourceNumber']    ?? '',
    ewbNumber:           j['ewbNumber'],
    ewbDate:             j['ewbDate']     != null ? DateTime.tryParse(j['ewbDate'])     : null,
    validUntil:          j['validUntil']  != null ? DateTime.tryParse(j['validUntil'])  : null,
    ewbStatus:           j['ewbStatus']      ?? 'DRAFT',
    supplyType:          j['supplyType']     ?? 'OUTWARD',
    subType:             j['subType']        ?? 'SUPPLY',
    documentType:        j['documentType']   ?? 'INV',
    documentNumber:      j['documentNumber'] ?? '',
    documentDate:        DateTime.tryParse(j['documentDate'] ?? '') ?? DateTime.now(),
    fromGstin:           j['fromGstin']      ?? '',
    fromTradeName:       j['fromTradeName']  ?? '',
    fromPlace:           j['fromPlace']      ?? '',
    fromState:           j['fromState']      ?? '',
    toGstin:             j['toGstin']        ?? '',
    toTradeName:         j['toTradeName']    ?? '',
    toPlace:             j['toPlace']        ?? '',
    toState:             j['toState']        ?? '',
    hsnCode:             j['hsnCode']        ?? '',
    productName:         j['productName']    ?? '',
    quantity:            (j['quantity']      ?? 0).toDouble(),
    unit:                j['unit']           ?? 'NOS',
    taxableAmount:       (j['taxableAmount'] ?? 0).toDouble(),
    cgstRate:            (j['cgstRate']      ?? 0).toDouble(),
    sgstRate:            (j['sgstRate']      ?? 0).toDouble(),
    igstRate:            (j['igstRate']      ?? 0).toDouble(),
    totalInvoiceValue:   (j['totalInvoiceValue'] ?? 0).toDouble(),
    transportMode:       j['transportMode']  ?? 'ROAD',
    approximateDistance: (j['approximateDistance'] ?? 0).toDouble(),
    transporterName:     j['transporterName'] ?? '',
    transporterId:       j['transporterId']  ?? '',
    vehicleNumber:       j['vehicleNumber']  ?? '',
    vehicleType:         j['vehicleType']    ?? 'REGULAR',
    fromPlacePartB:      j['fromPlacePartB'] ?? '',
    isConsolidated:      j['isConsolidated'] ?? false,
    consolidatedEwbNumber: j['consolidatedEwbNumber'],
    isManuallyAssociated: j['isManuallyAssociated'] ?? false,
    cancelReason:        j['cancelReason'],
    cancelledAt:         j['cancelledAt'] != null ? DateTime.tryParse(j['cancelledAt']) : null,
    createdAt:           DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
  );

  // ── Computed helpers ───────────────────────────────────────────────────────

  bool get isActive    => ewbStatus == 'GENERATED' || ewbStatus == 'EXTENDED';
  bool get isExpired   => ewbStatus == 'EXPIRED';
  bool get isCancelled => ewbStatus == 'CANCELLED';
  bool get isPartA     => ewbStatus == 'PART_A';

  bool get canCancel {
    if (ewbDate == null) return false;
    return isActive && DateTime.now().difference(ewbDate!).inHours < 24;
  }

  bool get canExtend {
    if (validUntil == null) return false;
    final diff        = validUntil!.difference(DateTime.now()).inHours;
    final sinceExpiry = DateTime.now().difference(validUntil!).inHours;
    return (diff >= 0 && diff <= 4) || (sinceExpiry >= 0 && sinceExpiry <= 4);
  }

  String get validityText {
    if (validUntil == null) return 'No validity';
    final diff = validUntil!.difference(DateTime.now());
    if (diff.isNegative)    return 'Expired';
    if (diff.inHours < 4)   return '⚠️ ${diff.inHours}h left';
    if (diff.inDays == 0)   return '${diff.inHours}h left';
    if (diff.inDays == 1)   return '1 day left';
    return '${diff.inDays} days left';
  }
}

class EWBConnectionStatus {
  final bool      isConnected;
  final String?   gstin;
  final String?   username;
  final DateTime? connectedAt;
  final DateTime? lastValidatedAt;
  final bool      mockMode;

  EWBConnectionStatus({
    required this.isConnected,
    this.gstin,
    this.username,
    this.connectedAt,
    this.lastValidatedAt,
    this.mockMode = true,
  });

  factory EWBConnectionStatus.fromJson(Map<String, dynamic> j) => EWBConnectionStatus(
    isConnected:     j['isConnected']     ?? false,
    gstin:           j['gstin'],
    username:        j['username'],
    connectedAt:     j['connectedAt']     != null ? DateTime.tryParse(j['connectedAt'])     : null,
    lastValidatedAt: j['lastValidatedAt'] != null ? DateTime.tryParse(j['lastValidatedAt']) : null,
    mockMode:        j['mockMode']        ?? true,
  );
}