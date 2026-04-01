// lib/core/services/tms_service.dart
// ============================================================================
// 🎫 TMS SERVICE - Finance Backend (org-scoped, billing_users)
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../app/config/finance_api_config.dart';
import '../finance_secure_storage.dart';

class TMSService {
  static String get _base => FinanceApiConfig.baseUrl;
  static const String _prefix = '/api/finance/tickets';

  Future<Map<String, String>> _headers() async {
    final token = await FinanceSecureStorage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? params}) async {
    try {
      var uri = Uri.parse('$_base$path');
      if (params != null && params.isNotEmpty) {
        uri = uri.replace(queryParameters: params);
      }
      debugPrint('📤 TMS GET: $uri');
      final response = await http.get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 30));
      return _parse(response);
    } catch (e) {
      debugPrint('❌ TMS GET error: $e');
      return {'success': false, 'message': e.toString(), 'data': []};
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_base$path');
      debugPrint('📤 TMS POST: $uri');
      final response = await http.post(uri, headers: await _headers(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return _parse(response);
    } catch (e) {
      debugPrint('❌ TMS POST error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_base$path');
      final response = await http.put(uri, headers: await _headers(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return _parse(response);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    try {
      final uri = Uri.parse('$_base$path');
      final response = await http.delete(uri, headers: await _headers())
          .timeout(const Duration(seconds: 30));
      return _parse(response);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Map<String, dynamic> _parse(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) return data;
      return {'success': false, 'message': data['message'] ?? data['error'] ?? 'Request failed'};
    } catch (_) {
      return {'success': false, 'message': 'Invalid response'};
    }
  }

  // ========================================================================
  // 📦 FETCH BILLING USERS IN ORG (for "Assign To" dropdown)
  // ========================================================================
  Future<Map<String, dynamic>> fetchEmployees() async {
    return await _get('$_prefix/employees');
  }

  // ========================================================================
  // ➕ CREATE NEW TICKET
  // ========================================================================
  Future<Map<String, dynamic>> createTicket({
    required String subject,
    required String message,
    required String priority,
    required int timeline,
    required String assignedTo,
    String status = 'Open',
    File? attachment,
  }) async {
    if (attachment != null) {
      return await _uploadTicketWithAttachment(
        subject: subject, message: message, priority: priority,
        timeline: timeline, assignedTo: assignedTo, status: status,
        attachment: attachment,
      );
    }
    return await _post(_prefix, {
      'subject': subject, 'message': message, 'priority': priority,
      'timeline': timeline, 'assigned_to': assignedTo, 'status': status,
    });
  }

  Future<Map<String, dynamic>> _uploadTicketWithAttachment({
    required String subject, required String message, required String priority,
    required int timeline, required String assignedTo, required String status,
    required File attachment,
  }) async {
    try {
      final token = await FinanceSecureStorage.getToken();
      if (token == null) return {'success': false, 'message': 'Not authenticated'};

      final uri = Uri.parse('$_base$_prefix');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['subject'] = subject
        ..fields['message'] = message
        ..fields['priority'] = priority
        ..fields['timeline'] = timeline.toString()
        ..fields['assigned_to'] = assignedTo
        ..fields['status'] = status
        ..files.add(await http.MultipartFile.fromPath('attachment', attachment.path));

      final response = await request.send();
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'message': 'Ticket created successfully'};
      }
      return {'success': false, 'message': 'Upload failed: ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'message': 'Upload failed: $e'};
    }
  }

  // ========================================================================
  // 📋 FETCH MY TICKETS
  // ========================================================================
  Future<Map<String, dynamic>> fetchMyTickets({
    String? status, String? priority, String? dateFrom, String? dateTo,
  }) async {
    final params = <String, String>{};
    if (status != null) params['status'] = status;
    if (priority != null) params['priority'] = priority;
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;
    return await _get(_prefix, params: params);
  }

  // ========================================================================
  // 📋 FETCH TICKETS RAISED BY ME
  // ========================================================================
  Future<Map<String, dynamic>> fetchRaisedByMe({
    String? status, String? priority, String? dateFrom, String? dateTo,
  }) async {
    final params = <String, String>{'raisedByMe': 'true'};
    if (status != null) params['status'] = status;
    if (priority != null) params['priority'] = priority;
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;
    return await _get(_prefix, params: params);
  }

  // ========================================================================
  // 📋 FETCH ALL TICKETS (admin)
  // ========================================================================
  Future<Map<String, dynamic>> fetchAllTicketsAdmin({
    String? status, String? priority, String? dateFrom, String? dateTo, String? assignedTo,
  }) async {
    final params = <String, String>{'admin': 'true'};
    if (status != null) params['status'] = status;
    if (priority != null) params['priority'] = priority;
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;
    if (assignedTo != null) params['assignedTo'] = assignedTo;
    return await _get(_prefix, params: params);
  }

  // ========================================================================
  // 📋 FETCH CLOSED TICKETS
  // ========================================================================
  Future<Map<String, dynamic>> fetchClosedTickets({
    String? dateFrom, String? dateTo, String? assignedTo,
  }) async {
    final params = <String, String>{};
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;
    if (assignedTo != null) params['assignedTo'] = assignedTo;
    return await _get('$_prefix/closed', params: params);
  }

  // ========================================================================
  // 🔍 FETCH SINGLE TICKET
  // ========================================================================
  Future<Map<String, dynamic>> fetchTicket(String ticketId) async {
    return await _get('$_prefix/$ticketId');
  }

  // ========================================================================
  // ✏️ UPDATE TICKET
  // ========================================================================
  Future<Map<String, dynamic>> updateTicketStatus(
    String ticketId,
    String status, {
    String? replySubject,
    String? replyMessage,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (replySubject != null) body['replySubject'] = replySubject;
    if (replyMessage != null) body['replyMessage'] = replyMessage;
    return await _put('$_prefix/$ticketId', body);
  }

  Future<Map<String, dynamic>> updateTicket(String ticketId, Map<String, dynamic> updates) async {
    return await _put('$_prefix/$ticketId', updates);
  }

  // ========================================================================
  // 🔄 REASSIGN / REOPEN / DELETE
  // ========================================================================
  Future<Map<String, dynamic>> reassignTicket(String ticketId, String newEmployeeId) async {
    return await _post('$_prefix/$ticketId/reassign', {'new_employee_id': newEmployeeId});
  }

  Future<Map<String, dynamic>> reopenTicket(String ticketId) async {
    return await _post('$_prefix/$ticketId/reopen', {});
  }

  Future<Map<String, dynamic>> deleteTicket(String ticketId) async {
    return await _delete('$_prefix/$ticketId');
  }

  // ========================================================================
  // 📊 FETCH TICKET STATISTICS
  // ========================================================================
  Future<Map<String, dynamic>> fetchStatistics() async {
    return await _get('$_prefix/stats');
  }
}
