// ============================================================================
// TIMESHEET SERVICE — UPDATED (Submit + Bulk + Weekly + Utilization)
// ============================================================================
// File: lib/core/services/timesheet_service.dart
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';
import 'project_service.dart' show Project;

// ── Models ────────────────────────────────────────────────────────────────────

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
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? rejectedBy;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final String? billedInvoiceId;
  final String? timerId;

  TimeEntry({
    required this.id,
    required this.entryNumber,
    required this.projectId,
    required this.projectName,
    required this.taskId,
    required this.taskName,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.date,
    required this.hours,
    required this.isBillable,
    required this.notes,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.rejectedBy,
    this.rejectionReason,
    this.submittedAt,
    this.billedInvoiceId,
    this.timerId,
  });

  factory TimeEntry.fromJson(Map<String, dynamic> j) => TimeEntry(
    id:              j['_id']?.toString() ?? '',
    entryNumber:     j['entryNumber']?.toString() ?? '',
    projectId:       j['projectId']?.toString() ?? '',
    projectName:     j['projectName']?.toString() ?? '',
    taskId:          j['taskId']?.toString() ?? '',
    taskName:        j['taskName']?.toString() ?? '',
    userId:          j['userId']?.toString() ?? '',
    userName:        j['userName']?.toString() ?? '',
    userEmail:       j['userEmail']?.toString() ?? '',
    date:            j['date'] != null ? DateTime.parse(j['date']) : DateTime.now(),
    hours:           (j['hours'] ?? 0).toDouble(),
    isBillable:      j['isBillable'] == true,
    notes:           j['notes']?.toString() ?? '',
    status:          j['status']?.toString() ?? 'Unbilled',
    approvedBy:      j['approvedBy']?.toString(),
    approvedAt:      j['approvedAt'] != null ? DateTime.tryParse(j['approvedAt']) : null,
    rejectedBy:      j['rejectedBy']?.toString(),
    rejectionReason: j['rejectionReason']?.toString(),
    submittedAt:     j['submittedAt'] != null ? DateTime.tryParse(j['submittedAt']) : null,
    billedInvoiceId: j['billedInvoiceId']?.toString(),
    timerId:         j['timerId']?.toString(),
  );
}

class TimesheetStats {
  final int total;
  final int unbilled;
  final int submitted;
  final int approved;
  final int billed;
  final int rejected;
  final double totalHours;
  final double billableHours;

  TimesheetStats({
    required this.total,
    required this.unbilled,
    required this.submitted,
    required this.approved,
    required this.billed,
    required this.rejected,
    required this.totalHours,
    required this.billableHours,
  });

  factory TimesheetStats.fromJson(Map<String, dynamic> j) => TimesheetStats(
    total:         (j['total']    ?? 0) as int,
    unbilled:      (j['unbilled'] ?? 0) as int,
    submitted:     (j['submitted'] ?? 0) as int,
    approved:      (j['approved'] ?? 0) as int,
    billed:        (j['billed']   ?? 0) as int,
    rejected:      (j['rejected'] ?? 0) as int,
    totalHours:    (j['totalHours']    ?? 0).toDouble(),
    billableHours: (j['billableHours'] ?? 0).toDouble(),
  );
}

class TimesheetListResult {
  final List<TimeEntry> timesheets;
  final _Pagination pagination;
  TimesheetListResult({required this.timesheets, required this.pagination});
}

class _Pagination {
  final int total, page, limit, pages;
  _Pagination({required this.total, required this.page, required this.limit, required this.pages});
  factory _Pagination.fromJson(Map<String, dynamic> j) => _Pagination(
    total: (j['total'] ?? 0) as int, page: (j['page'] ?? 1) as int,
    limit: (j['limit'] ?? 20) as int, pages: (j['pages'] ?? 1) as int,
  );
}

class WeeklySummaryDay {
  final String date;
  final double totalHours;
  final double billableHours;
  final List<dynamic> entries;
  WeeklySummaryDay({required this.date, required this.totalHours, required this.billableHours, required this.entries});
  factory WeeklySummaryDay.fromJson(Map<String, dynamic> j) => WeeklySummaryDay(
    date:           j['date']?.toString() ?? '',
    totalHours:     (j['totalHours']    ?? 0).toDouble(),
    billableHours:  (j['billableHours'] ?? 0).toDouble(),
    entries:        j['entries'] as List? ?? [],
  );
}

class WeeklySummary {
  final List<WeeklySummaryDay> days;
  final double weekTotal;
  final double weekBillable;
  final double weekNonBillable;
  WeeklySummary({required this.days, required this.weekTotal, required this.weekBillable, required this.weekNonBillable});
  factory WeeklySummary.fromJson(Map<String, dynamic> j) => WeeklySummary(
    days:            (j['days'] as List? ?? []).map((d) => WeeklySummaryDay.fromJson(d)).toList(),
    weekTotal:       (j['weekTotal']       ?? 0).toDouble(),
    weekBillable:    (j['weekBillable']    ?? 0).toDouble(),
    weekNonBillable: (j['weekNonBillable'] ?? 0).toDouble(),
  );
}

// ── Service ───────────────────────────────────────────────────────────────────

class TimesheetService {
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('finance_jwt_token') ?? prefs.getString('jwt_token') ?? '';
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  static String get _base => ApiConfig.baseUrl;

  // ── Stats ──────────────────────────────────────────────────────────────────
  static Future<TimesheetStats> getStats({String? projectId}) async {
    final uri = Uri.parse('$_base/api/finance/timesheets/stats${projectId != null ? '?projectId=$projectId' : ''}');
    final res  = await http.get(uri, headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return TimesheetStats.fromJson(body['data']);
    throw Exception(body['message'] ?? 'Failed to load stats');
  }

  // ── List ───────────────────────────────────────────────────────────────────
  static Future<TimesheetListResult> getTimesheets({
    String? status, String? projectId, bool? isBillable,
    String? search, String? fromDate, String? toDate,
    int page = 1, int limit = 20,
  }) async {
    final params = <String, String>{
      'page': '$page', 'limit': '$limit',
      if (status    != null) 'status':    status,
      if (projectId != null) 'projectId': projectId,
      if (isBillable != null) 'isBillable': '$isBillable',
      if (search    != null) 'search':    search,
      if (fromDate  != null) 'fromDate':  fromDate,
      if (toDate    != null) 'toDate':    toDate,
    };
    final res  = await http.get(Uri.parse('$_base/api/finance/timesheets').replace(queryParameters: params), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) {
      return TimesheetListResult(
        timesheets: (body['data'] as List).map((j) => TimeEntry.fromJson(j)).toList(),
        pagination: _Pagination.fromJson(body['pagination'] ?? {}),
      );
    }
    throw Exception(body['message'] ?? 'Failed to load timesheets');
  }

  // ── Get one ────────────────────────────────────────────────────────────────
  static Future<TimeEntry> getTimesheet(String id) async {
    final res  = await http.get(Uri.parse('$_base/api/finance/timesheets/$id'), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return TimeEntry.fromJson(body['data']);
    throw Exception(body['message'] ?? 'Failed to load timesheet');
  }

  // ── Create ─────────────────────────────────────────────────────────────────
  static Future<TimeEntry> createTimeEntry(Map<String, dynamic> data) async {
    final res  = await http.post(Uri.parse('$_base/api/finance/timesheets'), headers: await _headers(), body: json.encode(data));
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return TimeEntry.fromJson(body['data']);
    throw Exception(body['message'] ?? 'Failed to create time entry');
  }

  // ── Update ─────────────────────────────────────────────────────────────────
  static Future<TimeEntry> updateTimeEntry(String id, Map<String, dynamic> data) async {
    final res  = await http.put(Uri.parse('$_base/api/finance/timesheets/$id'), headers: await _headers(), body: json.encode(data));
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return TimeEntry.fromJson(body['data']);
    throw Exception(body['message'] ?? 'Failed to update time entry');
  }

  // ── Submit for approval ────────────────────────────────────────────────────
  static Future<void> submitEntry(String id) async {
    final res  = await http.patch(Uri.parse('$_base/api/finance/timesheets/$id/submit'), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) throw Exception(body['message'] ?? 'Failed to submit');
  }

  // ── Bulk submit ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> bulkSubmit(List<String> ids) async {
    final res  = await http.post(Uri.parse('$_base/api/finance/timesheets/bulk-submit'), headers: await _headers(), body: json.encode({'ids': ids}));
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return body['data'] ?? {};
    throw Exception(body['message'] ?? 'Failed to bulk submit');
  }

  // ── Approve ────────────────────────────────────────────────────────────────
  static Future<void> approveEntry(String id) async {
    final res  = await http.patch(Uri.parse('$_base/api/finance/timesheets/$id/approve'), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) throw Exception(body['message'] ?? 'Failed to approve');
  }

  // ── Reject ─────────────────────────────────────────────────────────────────
  static Future<void> rejectEntry(String id, {String? reason}) async {
    final res  = await http.patch(Uri.parse('$_base/api/finance/timesheets/$id/reject'), headers: await _headers(), body: json.encode({'reason': reason ?? ''}));
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) throw Exception(body['message'] ?? 'Failed to reject');
  }

  // ── Bulk reject ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> bulkReject(List<String> ids, String reason) async {
    final res  = await http.post(Uri.parse('$_base/api/finance/timesheets/bulk-reject'), headers: await _headers(), body: json.encode({'ids': ids, 'reason': reason}));
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return body['data'] ?? {};
    throw Exception(body['message'] ?? 'Failed to bulk reject');
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  static Future<void> deleteEntry(String id) async {
    final res  = await http.delete(Uri.parse('$_base/api/finance/timesheets/$id'), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) throw Exception(body['message'] ?? 'Failed to delete');
  }

  // ── Weekly summary ─────────────────────────────────────────────────────────
  static Future<WeeklySummary> getWeeklySummary({String? projectId, String? fromDate, String? toDate}) async {
    final params = <String, String>{
      if (projectId != null) 'projectId': projectId,
      if (fromDate  != null) 'fromDate':  fromDate,
      if (toDate    != null) 'toDate':    toDate,
    };
    final res  = await http.get(Uri.parse('$_base/api/finance/timesheets/weekly-summary').replace(queryParameters: params), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return WeeklySummary.fromJson(body['data']);
    throw Exception(body['message'] ?? 'Failed to load weekly summary');
  }

  // ── Staff utilization ──────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getStaffUtilization({String? fromDate, String? toDate}) async {
    final params = <String, String>{
      if (fromDate != null) 'fromDate': fromDate,
      if (toDate   != null) 'toDate':   toDate,
    };
    final res  = await http.get(Uri.parse('$_base/api/finance/timesheets/staff-utilization').replace(queryParameters: params), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return List<Map<String, dynamic>>.from(body['data'] ?? []);
    throw Exception(body['message'] ?? 'Failed to load utilization');
  }

  // ── Unbilled report ────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getUnbilledReport() async {
    final res  = await http.get(Uri.parse('$_base/api/finance/timesheets/unbilled-report'), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return body['data'] ?? {};
    throw Exception(body['message'] ?? 'Failed to load unbilled report');
  }

  // ── Bulk import ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> bulkImport(List<Map<String, dynamic>> timesheets) async {
    final res  = await http.post(Uri.parse('$_base/api/finance/timesheets/import'), headers: await _headers(), body: json.encode({'timesheets': timesheets}));
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return body;
    throw Exception(body['message'] ?? 'Import failed');
  }

  // ── Export all ─────────────────────────────────────────────────────────────
  static Future<List<TimeEntry>> getAllForExport({String? status, String? projectId}) async {
    final params = <String, String>{
      if (status    != null) 'status':    status,
      if (projectId != null) 'projectId': projectId,
    };
    final res  = await http.get(Uri.parse('$_base/api/finance/timesheets/export/all').replace(queryParameters: params), headers: await _headers());
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return (body['data'] as List).map((j) => TimeEntry.fromJson(j)).toList();
    throw Exception(body['message'] ?? 'Failed to export');
  }
}