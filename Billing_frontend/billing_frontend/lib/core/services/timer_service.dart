// ============================================================================
// TIMER SERVICE — Flutter
// ============================================================================
// File: lib/core/services/timer_service.dart
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class ActiveTimer {
  final String id;
  final String projectId;
  final String projectName;
  final String taskId;
  final String taskName;
  final String userId;
  final String userName;
  final bool isBillable;
  final String notes;
  final String status; // running | paused
  final DateTime startedAt;
  final int elapsedSeconds;
  final String elapsedFormatted;

  ActiveTimer({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.taskId,
    required this.taskName,
    required this.userId,
    required this.userName,
    required this.isBillable,
    required this.notes,
    required this.status,
    required this.startedAt,
    required this.elapsedSeconds,
    required this.elapsedFormatted,
  });

  factory ActiveTimer.fromJson(Map<String, dynamic> j) => ActiveTimer(
    id:              j['_id']?.toString() ?? '',
    projectId:       j['projectId']?.toString() ?? '',
    projectName:     j['projectName']?.toString() ?? '',
    taskId:          j['taskId']?.toString() ?? '',
    taskName:        j['taskName']?.toString() ?? '',
    userId:          j['userId']?.toString() ?? '',
    userName:        j['userName']?.toString() ?? '',
    isBillable:      j['isBillable'] == true,
    notes:           j['notes']?.toString() ?? '',
    status:          j['status']?.toString() ?? 'running',
    startedAt:       j['startedAt'] != null ? DateTime.parse(j['startedAt']) : DateTime.now(),
    elapsedSeconds:  (j['currentElapsedSeconds'] ?? j['elapsedSeconds'] ?? 0) as int,
    elapsedFormatted: j['currentElapsedFormatted']?.toString() ?? '00:00:00',
  );

  bool get isRunning => status == 'running';
  bool get isPaused  => status == 'paused';
}

class TimerStopResult {
  final int elapsedSeconds;
  final String elapsedFormatted;
  final double hours;
  final Map<String, dynamic> timesheetEntry;

  TimerStopResult({
    required this.elapsedSeconds,
    required this.elapsedFormatted,
    required this.hours,
    required this.timesheetEntry,
  });

  factory TimerStopResult.fromJson(Map<String, dynamic> j) => TimerStopResult(
    elapsedSeconds:   (j['elapsedSeconds'] ?? 0) as int,
    elapsedFormatted: j['elapsedFormatted']?.toString() ?? '00:00:00',
    hours:            (j['hours'] ?? 0).toDouble(),
    timesheetEntry:   (j['timesheetEntry'] as Map<String, dynamic>?) ?? {},
  );
}

class TimerService {
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('finance_jwt_token') ?? prefs.getString('jwt_token') ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Content-Type':  'application/json',
    };
  }

  static String get _base => ApiConfig.baseUrl;

  // ── GET /active ────────────────────────────────────────────────────────────
  static Future<List<ActiveTimer>> getActiveTimers() async {
    final res = await http.get(
      Uri.parse('$_base/api/finance/timers/active'),
      headers: await _headers(),
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) {
      return (body['data'] as List).map((j) => ActiveTimer.fromJson(j)).toList();
    }
    return [];
  }

  // ── POST /start ────────────────────────────────────────────────────────────
  static Future<ActiveTimer> startTimer({
    required String projectId,
    required String projectName,
    String taskId = '',
    String taskName = '',
    String userId = '',
    String userName = '',
    String userEmail = '',
    bool isBillable = true,
    String notes = '',
  }) async {
    final res = await http.post(
      Uri.parse('$_base/api/finance/timers/start'),
      headers: await _headers(),
      body: json.encode({
        'projectId':   projectId,
        'projectName': projectName,
        'taskId':      taskId,
        'taskName':    taskName,
        'userId':      userId,
        'userName':    userName,
        'userEmail':   userEmail,
        'isBillable':  isBillable,
        'notes':       notes,
      }),
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return ActiveTimer.fromJson(body['data']);
    throw Exception(body['message'] ?? 'Failed to start timer');
  }

  // ── POST /:id/pause ────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> pauseTimer(String timerId) async {
    final res = await http.post(
      Uri.parse('$_base/api/finance/timers/$timerId/pause'),
      headers: await _headers(),
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return body['data'] ?? {};
    throw Exception(body['message'] ?? 'Failed to pause timer');
  }

  // ── POST /:id/resume ───────────────────────────────────────────────────────
  static Future<void> resumeTimer(String timerId) async {
    final res = await http.post(
      Uri.parse('$_base/api/finance/timers/$timerId/resume'),
      headers: await _headers(),
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) throw Exception(body['message'] ?? 'Failed to resume timer');
  }

  // ── POST /:id/stop ─────────────────────────────────────────────────────────
  static Future<TimerStopResult> stopTimer(
    String timerId, {
    String? notes,
    bool? isBillable,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/api/finance/timers/$timerId/stop'),
      headers: await _headers(),
      body: json.encode({
        if (notes != null)      'notes':      notes,
        if (isBillable != null) 'isBillable': isBillable,
      }),
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] == true) return TimerStopResult.fromJson(body['data']);
    throw Exception(body['message'] ?? 'Failed to stop timer');
  }

  // ── DELETE /:id — discard timer ────────────────────────────────────────────
  static Future<void> discardTimer(String timerId) async {
    final res = await http.delete(
      Uri.parse('$_base/api/finance/timers/$timerId'),
      headers: await _headers(),
    );
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['success'] != true) throw Exception(body['message'] ?? 'Failed to discard timer');
  }

  // ── Format duration helper ─────────────────────────────────────────────────
  static String formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static double secondsToHours(int seconds) {
    return (seconds / 3600 * 100).roundToDouble() / 100;
  }
}