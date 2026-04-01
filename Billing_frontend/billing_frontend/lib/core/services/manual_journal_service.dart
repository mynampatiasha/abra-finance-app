// ============================================================================
// MANUAL JOURNAL SERVICE
// ============================================================================
// File: lib/core/services/manual_journal_service.dart
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';
import '../../../../app/config/finance_api_config.dart';
import '../finance_secure_storage.dart';

// ============================================================================
// MODELS
// ============================================================================

class JournalLineItem {
  final String id;
  String accountId;
  String accountName;
  String accountCode;
  String description;
  String? contactId;
  String? contactName;
  String? contactType; // 'vendor' | 'customer'
  double debit;
  double credit;

  JournalLineItem({
    required this.id,
    required this.accountId,
    required this.accountName,
    this.accountCode = '',
    this.description = '',
    this.contactId,
    this.contactName,
    this.contactType,
    this.debit = 0,
    this.credit = 0,
  });

  factory JournalLineItem.empty() => JournalLineItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        accountId: '',
        accountName: '',
      );

  factory JournalLineItem.fromJson(Map<String, dynamic> j) => JournalLineItem(
        id: j['_id'] ?? j['id'] ?? '',
        accountId: j['accountId']?.toString() ?? '',
        accountName: j['accountName'] ?? '',
        accountCode: j['accountCode'] ?? '',
        description: j['description'] ?? '',
        contactId: j['contactId']?.toString(),
        contactName: j['contactName'],
        contactType: j['contactType'],
        debit: (j['debit'] ?? 0).toDouble(),
        credit: (j['credit'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'accountName': accountName,
        'accountCode': accountCode,
        'description': description,
        'contactId': contactId,
        'contactName': contactName,
        'contactType': contactType,
        'debit': debit,
        'credit': credit,
      };
}

class AppliedCredit {
  final String type; // 'Invoice' | 'Bill'
  final String referenceId;
  final String referenceNumber;
  final double amount;
  final DateTime appliedDate;

  AppliedCredit({
    required this.type,
    required this.referenceId,
    required this.referenceNumber,
    required this.amount,
    required this.appliedDate,
  });

  factory AppliedCredit.fromJson(Map<String, dynamic> j) => AppliedCredit(
        type: j['type'] ?? '',
        referenceId: j['referenceId']?.toString() ?? '',
        referenceNumber: j['referenceNumber'] ?? '',
        amount: (j['amount'] ?? 0).toDouble(),
        appliedDate: DateTime.tryParse(j['appliedDate'] ?? '') ?? DateTime.now(),
      );
}

class JournalAttachment {
  final String id;
  final String filename;
  final String filepath;
  final int size;
  final DateTime uploadedAt;

  JournalAttachment({
    required this.id,
    required this.filename,
    required this.filepath,
    required this.size,
    required this.uploadedAt,
  });

  factory JournalAttachment.fromJson(Map<String, dynamic> j) => JournalAttachment(
        id: j['_id']?.toString() ?? '',
        filename: j['filename'] ?? '',
        filepath: j['filepath'] ?? '',
        size: j['size'] ?? 0,
        uploadedAt: DateTime.tryParse(j['uploadedAt'] ?? '') ?? DateTime.now(),
      );
}

class ManualJournal {
  final String id;
  final String journalNumber;
  final DateTime date;
  final String referenceNumber;
  final String notes;
  final String reportingMethod;
  final String currency;
  final List<JournalLineItem> lineItems;
  final double totalDebit;
  final double totalCredit;
  final double difference;
  final String status; // Draft | Published | Void
  final List<AppliedCredit> appliedCredits;
  final List<JournalAttachment> attachments;
  final String? voidReason;
  final DateTime? voidedAt;
  final String? clonedFromNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;

  ManualJournal({
    required this.id,
    required this.journalNumber,
    required this.date,
    this.referenceNumber = '',
    this.notes = '',
    this.reportingMethod = 'Accrual and Cash',
    this.currency = 'INR',
    required this.lineItems,
    required this.totalDebit,
    required this.totalCredit,
    required this.difference,
    required this.status,
    this.appliedCredits = const [],
    this.attachments = const [],
    this.voidReason,
    this.voidedAt,
    this.clonedFromNumber,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
  });

  factory ManualJournal.fromJson(Map<String, dynamic> j) => ManualJournal(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        journalNumber: j['journalNumber'] ?? '',
        date: DateTime.tryParse(j['date'] ?? '') ?? DateTime.now(),
        referenceNumber: j['referenceNumber'] ?? '',
        notes: j['notes'] ?? '',
        reportingMethod: j['reportingMethod'] ?? 'Accrual and Cash',
        currency: j['currency'] ?? 'INR',
        lineItems: (j['lineItems'] as List? ?? [])
            .map((l) => JournalLineItem.fromJson(l))
            .toList(),
        totalDebit: (j['totalDebit'] ?? 0).toDouble(),
        totalCredit: (j['totalCredit'] ?? 0).toDouble(),
        difference: (j['difference'] ?? 0).toDouble(),
        status: j['status'] ?? 'Draft',
        appliedCredits: (j['appliedCredits'] as List? ?? [])
            .map((c) => AppliedCredit.fromJson(c))
            .toList(),
        attachments: (j['attachments'] as List? ?? [])
            .map((a) => JournalAttachment.fromJson(a))
            .toList(),
        voidReason: j['voidReason'],
        voidedAt: DateTime.tryParse(j['voidedAt'] ?? ''),
        clonedFromNumber: j['clonedFromNumber'],
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
        publishedAt: DateTime.tryParse(j['publishedAt'] ?? ''),
      );
}

class JournalTemplate {
  final String id;
  final String templateName;
  final String notes;
  final String reportingMethod;
  final String currency;
  final List<JournalLineItem> lineItems;

  JournalTemplate({
    required this.id,
    required this.templateName,
    this.notes = '',
    this.reportingMethod = 'Accrual and Cash',
    this.currency = 'INR',
    required this.lineItems,
  });

  factory JournalTemplate.fromJson(Map<String, dynamic> j) => JournalTemplate(
        id: j['_id']?.toString() ?? '',
        templateName: j['templateName'] ?? '',
        notes: j['notes'] ?? '',
        reportingMethod: j['reportingMethod'] ?? 'Accrual and Cash',
        currency: j['currency'] ?? 'INR',
        lineItems: (j['lineItems'] as List? ?? [])
            .map((l) => JournalLineItem.fromJson(l))
            .toList(),
      );
}

class JournalStats {
  final int total;
  final int draft;
  final int published;
  final int voided;
  final double totalDebit;
  final double totalCredit;

  JournalStats({
    required this.total,
    required this.draft,
    required this.published,
    required this.voided,
    required this.totalDebit,
    required this.totalCredit,
  });

  factory JournalStats.fromJson(Map<String, dynamic> j) => JournalStats(
        total: j['total'] ?? 0,
        draft: j['draft'] ?? 0,
        published: j['published'] ?? 0,
        voided: j['voided'] ?? 0,
        totalDebit: (j['totalDebit'] ?? 0).toDouble(),
        totalCredit: (j['totalCredit'] ?? 0).toDouble(),
      );
}

class JournalListResult {
  final List<ManualJournal> journals;
  final int total;
  final int page;
  final int pages;

  JournalListResult({
    required this.journals,
    required this.total,
    required this.page,
    required this.pages,
  });
}

// ============================================================================
// SERVICE
// ============================================================================

class ManualJournalService {
  static Future<Map<String, String>> _getHeaders() async {
    final token = await FinanceSecureStorage.getToken() ?? '';
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static String get _base => '${FinanceApiConfig.baseUrl}/api/finance/manual-journals';

  // ── Stats ─────────────────────────────────────────────────────────────────

  static Future<JournalStats> getStats() async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/stats'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed');
    return JournalStats.fromJson(body['data']);
  }

  // ── List ──────────────────────────────────────────────────────────────────

  static Future<JournalListResult> getJournals({
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
    String? search,
    int page = 1,
    int limit = 50,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (status != null && status != 'All') params['status'] = status;
    if (fromDate != null) params['fromDate'] = fromDate.toIso8601String();
    if (toDate != null) params['toDate'] = toDate.toIso8601String();
    if (search != null && search.isNotEmpty) params['search'] = search;

    final uri = Uri.parse(_base).replace(queryParameters: params);
    final res = await http.get(uri, headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed');

    final data = body['data'];
    return JournalListResult(
      journals: (data['journals'] as List).map((j) => ManualJournal.fromJson(j)).toList(),
      total: data['pagination']?['total'] ?? 0,
      page: data['pagination']?['page'] ?? 1,
      pages: data['pagination']?['pages'] ?? 1,
    );
  }

  // ── Single ────────────────────────────────────────────────────────────────

  static Future<ManualJournal> getJournal(String id) async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/$id'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed');
    return ManualJournal.fromJson(body['data']);
  }

  // ── Create ────────────────────────────────────────────────────────────────

  static Future<ManualJournal> createJournal(Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final res = await http.post(Uri.parse(_base), headers: headers, body: jsonEncode(data));
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['message'] ?? 'Failed to create');
    return ManualJournal.fromJson(body['data']);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  static Future<ManualJournal> updateJournal(String id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final res = await http.put(Uri.parse('$_base/$id'), headers: headers, body: jsonEncode(data));
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to update');
    return ManualJournal.fromJson(body['data']);
  }

  // ── Publish ───────────────────────────────────────────────────────────────

  static Future<ManualJournal> publishJournal(String id) async {
    final headers = await _getHeaders();
    final res = await http.post(Uri.parse('$_base/$id/publish'), headers: headers, body: '{}');
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to publish');
    return ManualJournal.fromJson(body['data']);
  }

  // ── Void ──────────────────────────────────────────────────────────────────

  static Future<ManualJournal> voidJournal(String id, {String reason = ''}) async {
    final headers = await _getHeaders();
    final res = await http.post(
      Uri.parse('$_base/$id/void'),
      headers: headers,
      body: jsonEncode({'reason': reason}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to void');
    return ManualJournal.fromJson(body['data']);
  }

  // ── Clone ─────────────────────────────────────────────────────────────────

  static Future<ManualJournal> cloneJournal(String id) async {
    final headers = await _getHeaders();
    final res = await http.post(Uri.parse('$_base/$id/clone'), headers: headers, body: '{}');
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['message'] ?? 'Failed to clone');
    return ManualJournal.fromJson(body['data']);
  }

  // ── Apply Credits ─────────────────────────────────────────────────────────

  static Future<ManualJournal> applyCredits(
    String id, {
    required String type,
    required String referenceId,
    required String referenceNumber,
    required double amount,
  }) async {
    final headers = await _getHeaders();
    final res = await http.post(
      Uri.parse('$_base/$id/apply-credits'),
      headers: headers,
      body: jsonEncode({
        'type': type,
        'referenceId': referenceId,
        'referenceNumber': referenceNumber,
        'amount': amount,
      }),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to apply credits');
    return ManualJournal.fromJson(body['data']);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  static Future<void> deleteJournal(String id) async {
    final headers = await _getHeaders();
    final res = await http.delete(Uri.parse('$_base/$id'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed to delete');
  }

  // ── Templates ─────────────────────────────────────────────────────────────

  static Future<List<JournalTemplate>> getTemplates() async {
    final headers = await _getHeaders();
    final res = await http.get(Uri.parse('$_base/templates/list'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed');
    return (body['data'] as List).map((t) => JournalTemplate.fromJson(t)).toList();
  }

  static Future<JournalTemplate> saveTemplate(Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final res = await http.post(
      Uri.parse('$_base/templates'),
      headers: headers,
      body: jsonEncode(data),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(body['message'] ?? 'Failed');
    return JournalTemplate.fromJson(body['data']);
  }

  static Future<void> deleteTemplate(String id) async {
    final headers = await _getHeaders();
    final res = await http.delete(Uri.parse('$_base/templates/$id'), headers: headers);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Failed');
  }

  // ── Upload Attachments ────────────────────────────────────────────────────

  static Future<List<JournalAttachment>> uploadAttachments(
    String id,
    List<Uint8List> fileBytes,
    List<String> fileNames,
  ) async {
    final token = await FinanceSecureStorage.getToken() ?? '';

    final request = http.MultipartRequest('POST', Uri.parse('$_base/$id/attachments'));
    request.headers['Authorization'] = 'Bearer $token';

    for (int i = 0; i < fileBytes.length; i++) {
      request.files.add(http.MultipartFile.fromBytes(
        'files',
        fileBytes[i],
        filename: fileNames[i],
      ));
    }

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Upload failed');
    return (body['data'] as List).map((a) => JournalAttachment.fromJson(a)).toList();
  }

  // ── Import ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> importJournals(
    List<Map<String, dynamic>> journals,
    Uint8List fileBytes,
    String fileName,
  ) async {
    final token = await FinanceSecureStorage.getToken() ?? '';

    final request = http.MultipartRequest('POST', Uri.parse('$_base/import'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
    request.fields['journals'] = jsonEncode(journals);

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['message'] ?? 'Import failed');
    return body;
  }

  // ── PDF URL ───────────────────────────────────────────────────────────────

  /// Returns a PDF URL with the finance JWT appended as ?token=...
  /// so the backend's verifyFinanceJWT can authenticate the download.
  static Future<String> getPdfUrl(String id) async {
    final token = await FinanceSecureStorage.getToken() ?? '';
    final base  = FinanceApiConfig.baseUrl;
    return '$base/api/finance/manual-journals/$id/pdf?token=$token';
  }
}