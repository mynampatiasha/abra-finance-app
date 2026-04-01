// ============================================================================
// PROJECT SERVICE — Time Tracking Module
// ============================================================================
// File: lib/core/services/project_service.dart
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class ProjectService {
  static const String _base = '/api/finance/projects';

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
  static Future<ProjectStats> getStats() async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/stats'),
      headers: await _headers(),
    );
    return ProjectStats.fromJson(_decode(res)['data'] ?? {});
  }

  // ── List ───────────────────────────────────────────────────────────────────
  static Future<ProjectListResponse> getProjects({
    String? status,
    String? billingMethod,
    String? customerId,
    String? search,
    String? fromDate,
    String? toDate,
    int page = 1,
    int limit = 20,
  }) async {
    final q = <String, String>{
      'page': '$page', 'limit': '$limit',
      if (status != null)        'status':        status,
      if (billingMethod != null) 'billingMethod': billingMethod,
      if (customerId != null)    'customerId':    customerId,
      if (search != null)        'search':        search,
      if (fromDate != null)      'fromDate':      fromDate,
      if (toDate != null)        'toDate':        toDate,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base').replace(queryParameters: q);
    final res = await http.get(uri, headers: await _headers());
    return ProjectListResponse.fromJson(_decode(res));
  }

  // ── Single ─────────────────────────────────────────────────────────────────
  static Future<Project> getProject(String id) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
      headers: await _headers(),
    );
    return Project.fromJson(_decode(res)['data'] ?? {});
  }

  // ── Create ─────────────────────────────────────────────────────────────────
  static Future<Project> createProject(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base'),
      headers: await _headers(),
      body: json.encode(data),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to create project');
    return Project.fromJson(decoded['data'] ?? {});
  }

  // ── Update ─────────────────────────────────────────────────────────────────
  static Future<Project> updateProject(String id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
      headers: await _headers(),
      body: json.encode(data),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to update project');
    return Project.fromJson(decoded['data'] ?? {});
  }

  // ── Status ─────────────────────────────────────────────────────────────────
  static Future<void> updateStatus(String id, String status) async {
    final res = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/status'),
      headers: await _headers(),
      body: json.encode({'status': status}),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to update status');
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  static Future<void> deleteProject(String id) async {
    final res = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id'),
      headers: await _headers(),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to delete project');
  }

  // ── Unbilled Hours ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getUnbilledHours(String id) async {
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/unbilled-hours'),
      headers: await _headers(),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to fetch unbilled hours');
    return decoded['data'] ?? {};
  }

  // ── Generate Invoice ───────────────────────────────────────────────────────
  static Future<GenerateInvoiceResult> generateInvoice(String id, {double gstRate = 18}) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base/$id/generate-invoice'),
      headers: await _headers(),
      body: json.encode({'gstRate': gstRate}),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Failed to generate invoice');
    return GenerateInvoiceResult.fromJson(decoded['data'] ?? {});
  }

  // ── Bulk Import ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> bulkImport(List<Map<String, dynamic>> projects) async {
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}$_base/import'),
      headers: await _headers(),
      body: json.encode({'projects': projects}),
    );
    final decoded = _decode(res);
    if (decoded['success'] != true) throw Exception(decoded['message'] ?? 'Import failed');
    return decoded;
  }

  // ── Export All ─────────────────────────────────────────────────────────────
  static Future<List<Project>> getAllForExport({String? status, String? billingMethod}) async {
    final q = <String, String>{
      if (status != null)        'status':        status,
      if (billingMethod != null) 'billingMethod': billingMethod,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}$_base/export/all').replace(queryParameters: q);
    final res = await http.get(uri, headers: await _headers());
    final decoded = _decode(res);
    final data = decoded['data'] as List? ?? [];
    return data.map((e) => Project.fromJson(e as Map<String, dynamic>)).toList();
  }
}

// =============================================================================
// MODELS
// =============================================================================

class Project {
  final String id;
  final String projectNumber;
  final String projectName;
  final String customerId;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final String description;
  final String billingMethod;
  final double fixedAmount;
  final double hourlyRate;
  final String budgetType;
  final double budgetAmount;
  final String currency;
  final DateTime startDate;
  final DateTime? endDate;
  final String status;
  final List<ProjectTask> tasks;
  final List<ProjectStaff> staff;
  final String notes;
  final double totalLoggedHours;
  final double totalBilledAmount;
  final double unbilledHours;
  final List<String> invoicesGenerated;
  final DateTime createdAt;
  final DateTime updatedAt;

  Project({
    required this.id, required this.projectNumber, required this.projectName,
    required this.customerId, required this.customerName,
    required this.customerEmail, required this.customerPhone,
    required this.description, required this.billingMethod,
    required this.fixedAmount, required this.hourlyRate,
    required this.budgetType, required this.budgetAmount,
    required this.currency, required this.startDate, this.endDate,
    required this.status, required this.tasks, required this.staff,
    required this.notes, required this.totalLoggedHours,
    required this.totalBilledAmount, required this.unbilledHours,
    required this.invoicesGenerated, required this.createdAt, required this.updatedAt,
  });

  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id:               j['_id']?.toString()          ?? j['id']?.toString() ?? '',
    projectNumber:    j['projectNumber']?.toString() ?? '',
    projectName:      j['projectName']?.toString()   ?? '',
    customerId:       j['customerId']?.toString()    ?? '',
    customerName:     j['customerName']?.toString()  ?? '',
    customerEmail:    j['customerEmail']?.toString() ?? '',
    customerPhone:    j['customerPhone']?.toString() ?? '',
    description:      j['description']?.toString()  ?? '',
    billingMethod:    j['billingMethod']?.toString() ?? 'Fixed Cost',
    fixedAmount:      (j['fixedAmount']  ?? 0).toDouble(),
    hourlyRate:       (j['hourlyRate']   ?? 0).toDouble(),
    budgetType:       j['budgetType']?.toString()    ?? 'Cost',
    budgetAmount:     (j['budgetAmount'] ?? 0).toDouble(),
    currency:         j['currency']?.toString()      ?? 'INR',
    startDate:        DateTime.tryParse(j['startDate'] ?? '') ?? DateTime.now(),
    endDate:          j['endDate'] != null ? DateTime.tryParse(j['endDate'].toString()) : null,
    status:           j['status']?.toString()        ?? 'Active',
    tasks:            (j['tasks'] as List? ?? []).map((t) => ProjectTask.fromJson(t as Map<String, dynamic>)).toList(),
    staff:            (j['staff'] as List? ?? []).map((s) => ProjectStaff.fromJson(s as Map<String, dynamic>)).toList(),
    notes:            j['notes']?.toString()         ?? '',
    totalLoggedHours: (j['totalLoggedHours'] ?? 0).toDouble(),
    totalBilledAmount:(j['totalBilledAmount'] ?? 0).toDouble(),
    unbilledHours:    (j['unbilledHours'] ?? 0).toDouble(),
    invoicesGenerated: List<String>.from(j['invoicesGenerated'] ?? []),
    createdAt:        DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    updatedAt:        DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
  );
}

class ProjectTask {
  final String taskId;
  final String taskName;
  final double hourlyRate;
  final double estimatedHours;
  final String description;
  final String status;

  ProjectTask({
    required this.taskId, required this.taskName,
    required this.hourlyRate, required this.estimatedHours,
    required this.description, required this.status,
  });

  factory ProjectTask.fromJson(Map<String, dynamic> j) => ProjectTask(
    taskId:         j['taskId']?.toString()     ?? '',
    taskName:       j['taskName']?.toString()   ?? '',
    hourlyRate:     (j['hourlyRate']     ?? 0).toDouble(),
    estimatedHours: (j['estimatedHours'] ?? 0).toDouble(),
    description:    j['description']?.toString() ?? '',
    status:         j['status']?.toString()     ?? 'Active',
  );

  Map<String, dynamic> toJson() => {
    'taskId': taskId, 'taskName': taskName,
    'hourlyRate': hourlyRate, 'estimatedHours': estimatedHours,
    'description': description, 'status': status,
  };
}

class ProjectStaff {
  final String userId;
  final String name;
  final String email;
  final String role;
  final double hourlyRate;

  ProjectStaff({
    required this.userId, required this.name,
    required this.email, required this.role, required this.hourlyRate,
  });

  factory ProjectStaff.fromJson(Map<String, dynamic> j) => ProjectStaff(
    userId:     j['userId']?.toString() ?? '',
    name:       j['name']?.toString()   ?? '',
    email:      j['email']?.toString()  ?? '',
    role:       j['role']?.toString()   ?? 'staff',
    hourlyRate: (j['hourlyRate'] ?? 0).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'userId': userId, 'name': name,
    'email': email, 'role': role, 'hourlyRate': hourlyRate,
  };
}

class ProjectStats {
  final int total, active, completed, inactive, onHold;
  final double totalBillableHours, unbilledHours;

  ProjectStats({
    required this.total, required this.active, required this.completed,
    required this.inactive, required this.onHold,
    required this.totalBillableHours, required this.unbilledHours,
  });

  factory ProjectStats.fromJson(Map<String, dynamic> j) => ProjectStats(
    total:               j['total']     ?? 0,
    active:              j['active']    ?? 0,
    completed:           j['completed'] ?? 0,
    inactive:            j['inactive']  ?? 0,
    onHold:              j['onHold']    ?? 0,
    totalBillableHours: (j['totalBillableHours'] ?? 0).toDouble(),
    unbilledHours:      (j['unbilledHours']      ?? 0).toDouble(),
  );
}

class ProjectListResponse {
  final List<Project> projects;
  final ProjectPagination pagination;

  ProjectListResponse({required this.projects, required this.pagination});

  factory ProjectListResponse.fromJson(Map<String, dynamic> j) => ProjectListResponse(
    projects:   (j['data'] as List? ?? []).map((e) => Project.fromJson(e as Map<String, dynamic>)).toList(),
    pagination: ProjectPagination.fromJson(j['pagination'] as Map<String, dynamic>? ?? {}),
  );
}

class ProjectPagination {
  final int total, page, limit, pages;
  ProjectPagination({required this.total, required this.page, required this.limit, required this.pages});
  factory ProjectPagination.fromJson(Map<String, dynamic> j) => ProjectPagination(
    total: j['total'] ?? 0, page: j['page'] ?? 1,
    limit: j['limit'] ?? 20, pages: j['pages'] ?? 1,
  );
}

class GenerateInvoiceResult {
  final String invoiceId;
  final String invoiceNumber;
  final double totalAmount;
  final int entriesBilled;

  GenerateInvoiceResult({
    required this.invoiceId, required this.invoiceNumber,
    required this.totalAmount, required this.entriesBilled,
  });

  factory GenerateInvoiceResult.fromJson(Map<String, dynamic> j) => GenerateInvoiceResult(
    invoiceId:     j['invoiceId']?.toString()     ?? '',
    invoiceNumber: j['invoiceNumber']?.toString() ?? '',
    totalAmount:   (j['totalAmount']  ?? 0).toDouble(),
    entriesBilled: j['entriesBilled'] ?? 0,
  );
}