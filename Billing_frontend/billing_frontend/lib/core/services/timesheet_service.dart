// ============================================================================
// TIMESHEET SERVICE — Time Tracking Module
// ============================================================================
// File: lib/core/services/timesheet_service.dart
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class TimesheetService {
  static const String _base = '/api/finance/timesheets';

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('finance_jwt_token') ??
        prefs.getString('jwt_token') ??
        prefs.getString('token') ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decode(http.Response r) =>
      json.decode(r.body) as Map<String, dynamic>;

  // ── Stats ──────────────────────────────────────────────────────────────────
  static Future<TimesheetStats> getStats({String? projectId}) async {
    final q = <String, String>{if (projectId != null) 'projectId': projectId};
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base/stats').replace(queryParameters: q);
    final res = await http.get(uri, headers: await _headers());
    return TimesheetStats.fromJson(_decode(res)['data'] ?? {});
  }

  // ── List ───────────────────────────────────────────────────────────────────
  static Future<TimesheetListResponse> getTimesheets({
    String? status, String? projectId, String? userId,
    bool? isBillable, String? search,
    String? fromDate, String? toDate,
    int page = 1, int limit = 20,
  }) async {
    final q = <String, String>{
      'page': '$page', 'limit': '$limit',
      if (status    != null) 'status':    status,
      if (projectId != null) 'projectId': projectId,
      if (userId    != null) 'userId':    userId,
      if (isBillable != null) 'isBillable': '$isBillable',
      if (search    != null) 'search':    search,
      if (fromDate  != null) 'fromDate':  fromDate,
      if (toDate    != null) 'toDate':    toDate,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base').replace(queryParameters: q);
    final res = await http.get(uri, headers: await _headers());
    return TimesheetListResponse.fromJson(_decode(res));
  }

  // ── By Project ─────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getByProject(String projectId, {String? status}) async {
    final q = <String, String>{if (status != null) 'status': status};
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base/by-project/$projectId').replace(queryParameters: q);
    final res = await http.get(uri, headers: await _headers());
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed');
    return decoded['data'] ?? {};
  }

  // ── Single ─────────────────────────────────────────────────────────────────
  static Future<TimeEntry> getTimesheet(String id) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
      headers: await _headers(),
    );
    return TimeEntry.fromJson(_decode(res)['data'] ?? {});
  }

  // ── Create ─────────────────────────────────────────────────────────────────
  static Future<TimeEntry> createTimeEntry(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base'),
      headers: await _headers(),
      body: json.encode(data),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to create time entry');
    return TimeEntry.fromJson(decoded['data'] ?? {});
  }

  // ── Update ─────────────────────────────────────────────────────────────────
  static Future<TimeEntry> updateTimeEntry(String id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
      headers: await _headers(),
      body: json.encode(data),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to update time entry');
    return TimeEntry.fromJson(decoded['data'] ?? {});
  }

  // ── Approve ────────────────────────────────────────────────────────────────
  static Future<void> approveEntry(String id) async {
    final res = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/approve'),
      headers: await _headers(),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to approve');
  }

  // ── Reject ─────────────────────────────────────────────────────────────────
  static Future<void> rejectEntry(String id, {String reason = ''}) async {
    final res = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/reject'),
      headers: await _headers(),
      body: json.encode({'reason': reason}),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to reject');
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  static Future<void> deleteEntry(String id) async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
      headers: await _headers(),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to delete');
  }

  // ── Bulk Import ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> bulkImport(List<Map<String, dynamic>> timesheets) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base/import'),
      headers: await _headers(),
      body: json.encode({'timesheets': timesheets}),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Import failed');
    return decoded;
  }

  // ── Export All ─────────────────────────────────────────────────────────────
  static Future<List<TimeEntry>> getAllForExport({String? status, String? projectId}) async {
    final q = <String, String>{
      if (status    != null) 'status':    status,
      if (projectId != null) 'projectId': projectId,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base/export/all').replace(queryParameters: q);
    final res = await http.get(uri, headers: await _headers());
    final decoded = _decode(res);
    final data = decoded['data'] as List? ?? [];
    return data.map((e) => TimeEntry.fromJson(e as Map<String, dynamic>)).toList();
  }
}

// =============================================================================
// MODELS
// =============================================================================

class TimeEntry {
  final String id;
  final String entryNumber;
  final String projectId;
  final String projectName;
  final String taskId;
  final String taskName;
  final String userId;
  final String userName;
  final String userEmail;
  final DateTime date;
  final double hours;
  final bool isBillable;
  final String notes;
  final String status;
  final String? billedInvoiceId;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final String? rejectionReason;
  final DateTime createdAt;

  TimeEntry({
    required this.id, required this.entryNumber,
    required this.projectId, required this.projectName,
    required this.taskId, required this.taskName,
    required this.userId, required this.userName, required this.userEmail,
    required this.date, required this.hours, required this.isBillable,
    required this.notes, required this.status,
    this.billedInvoiceId, this.approvedBy, this.approvedAt,
    this.rejectedBy, this.rejectionReason, required this.createdAt,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> j) => TimeEntry(
    id:            j['_id']?.toString()         ?? j['id']?.toString() ?? '',
    entryNumber:   j['entryNumber']?.toString() ?? '',
    projectId:     j['projectId']?.toString()   ?? '',
    projectName:   j['projectName']?.toString() ?? '',
    taskId:        j['taskId']?.toString()       ?? '',
    taskName:      j['taskName']?.toString()     ?? '',
    userId:        j['userId']?.toString()       ?? '',
    userName:      j['userName']?.toString()     ?? '',
    userEmail:     j['userEmail']?.toString()    ?? '',
    date:          DateTime.tryParse(j['date']?.toString() ?? '') ?? DateTime.now(),
    hours:         (j['hours'] ?? 0).toDouble(),
    isBillable:    j['isBillable'] == true || j['isBillable'] == 1,
    notes:         j['notes']?.toString()        ?? '',
    status:        j['status']?.toString()       ?? 'Unbilled',
    billedInvoiceId: j['billedInvoiceId']?.toString(),
    approvedBy:    j['approvedBy']?.toString(),
    approvedAt:    j['approvedAt'] != null ? DateTime.tryParse(j['approvedAt'].toString()) : null,
    rejectedBy:    j['rejectedBy']?.toString(),
    rejectionReason: j['rejectionReason']?.toString(),
    createdAt:     DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
  );
}

class TimesheetStats {
  final int total, unbilled, approved, billed, rejected;
  final double totalHours, billableHours;

  TimesheetStats({
    required this.total, required this.unbilled, required this.approved,
    required this.billed, required this.rejected,
    required this.totalHours, required this.billableHours,
  });

  factory TimesheetStats.fromJson(Map<String, dynamic> j) => TimesheetStats(
    total:         j['total']    ?? 0,
    unbilled:      j['unbilled'] ?? 0,
    approved:      j['approved'] ?? 0,
    billed:        j['billed']   ?? 0,
    rejected:      j['rejected'] ?? 0,
    totalHours:    (j['totalHours']    ?? 0).toDouble(),
    billableHours: (j['billableHours'] ?? 0).toDouble(),
  );
}

class TimesheetListResponse {
  final List<TimeEntry> timesheets;
  final TimesheetPagination pagination;

  TimesheetListResponse({required this.timesheets, required this.pagination});

  factory TimesheetListResponse.fromJson(Map<String, dynamic> j) => TimesheetListResponse(
    timesheets:  (j['data'] as List? ?? []).map((e) => TimeEntry.fromJson(e as Map<String, dynamic>)).toList(),
    pagination:  TimesheetPagination.fromJson(j['pagination'] as Map<String, dynamic>? ?? {}),
  );
}

class TimesheetPagination {
  final int total, page, limit, pages;
  TimesheetPagination({required this.total, required this.page, required this.limit, required this.pages});
  factory TimesheetPagination.fromJson(Map<String, dynamic> j) => TimesheetPagination(
    total: j['total'] ?? 0, page: j['page'] ?? 1,
    limit: j['limit'] ?? 20, pages: j['pages'] ?? 1,
  );
}