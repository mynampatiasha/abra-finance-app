// finance_auth_service.dart
// All API calls for finance auth — completely separate from SafeApiService
// ✅ Now persists orgLogoUrl per organisation on login / select-org

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../core/finance_secure_storage.dart';
import '../../app/config/finance_api_config.dart';

class FinanceAuthService {
  // ── Finance backend base URL ─────────────────────────────────────────────────
  static String get _baseUrl => FinanceApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await FinanceSecureStorage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, String>> _tempAuthHeaders() async {
    final token = await FinanceSecureStorage.getTempToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── HELPER: persist full session from a login/select-org response data ───────
  static Future<void> _persistSession(Map<String, dynamic> data) async {
    try {
      final user  = data['user']  as Map<String, dynamic>? ?? {};
      final token = data['token'] as String? ?? '';

      // ✅ Extract orgLogoUrl from user object
      final orgLogoUrl = user['orgLogoUrl']?.toString();

      await FinanceSecureStorage.saveSession(
        token:      token,
        userId:     user['id']?.toString()      ?? '',
        name:       user['name']?.toString()    ?? '',
        email:      user['email']?.toString()   ?? '',
        phone:      user['phone']?.toString()   ?? '',
        role:       user['role']?.toString()    ?? '',
        orgId:      user['orgId']?.toString()   ?? '',
        orgName:    user['orgName']?.toString() ?? '',
        orgLogoUrl: orgLogoUrl,                         // ✅ NEW
      );

      debugPrint('✅ Finance session saved (logo: ${orgLogoUrl ?? 'none'})');

      // ── Save permissions ─────────────────────────────────────────────────────
      final rawPerms = user['permissions'];
      if (rawPerms is Map) {
        await FinanceSecureStorage.savePermissions(
          Map<String, dynamic>.from(rawPerms),
        );
        debugPrint('✅ Finance permissions saved: ${rawPerms.keys.toList()}');
      } else {
        await FinanceSecureStorage.savePermissions({});
        debugPrint('⚠️  No permissions in response — saved empty map');
      }

      // ── Save organizations array (each item now has logoUrl from backend) ─────
      final rawOrgs = user['organizations'];
      if (rawOrgs is List && rawOrgs.isNotEmpty) {
        await FinanceSecureStorage.saveOrganizations(rawOrgs);
        debugPrint('✅ Finance organizations saved: ${rawOrgs.length} org(s)');
      } else {
        final orgId      = user['orgId']?.toString()   ?? '';
        final orgName    = user['orgName']?.toString() ?? '';
        final role       = user['role']?.toString()    ?? '';
        if (orgId.isNotEmpty) {
          await FinanceSecureStorage.saveOrganizations([
            {
              'orgId':   orgId,
              'orgName': orgName,
              'role':    role,
              'logoUrl': orgLogoUrl, // ✅
            },
          ]);
          debugPrint('✅ Finance organizations saved (fallback 1 org)');
        } else {
          await FinanceSecureStorage.saveOrganizations([]);
          debugPrint('⚠️  No organizations found — saved empty list');
        }
      }
    } catch (e) {
      debugPrint('❌ _persistSession error: $e');
    }
  }

  // ── Register ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String orgName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/finance/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':     name,
          'email':    email,
          'password': password,
          'phone':    phone,
          'orgName':  orgName,
        }),
      );
      final result = jsonDecode(response.body) as Map<String, dynamic>;

      if (result['success'] == true && result['data'] != null) {
        await _persistSession(result['data'] as Map<String, dynamic>);
      }

      return result;
    } catch (e) {
      debugPrint('❌ Finance register error: $e');
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/finance/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final result = jsonDecode(response.body) as Map<String, dynamic>;

      if (result['success'] == true) {
        final requireOrgSelect = result['requireOrgSelect'] == true;

        if (!requireOrgSelect && result['data'] != null) {
          await _persistSession(result['data'] as Map<String, dynamic>);
          debugPrint('✅ Finance login: single org — session persisted');
        } else if (requireOrgSelect && result['data'] != null) {
          final data    = result['data'] as Map<String, dynamic>;
          final tempTok = data['tempToken'] as String? ?? '';
          if (tempTok.isNotEmpty) {
            await FinanceSecureStorage.saveTempToken(tempTok);
            debugPrint('✅ Finance login: multi-org — temp token saved');
          }

          // ✅ Organizations now include logoUrl from backend
          final orgs = data['organizations'];
          if (orgs is List) {
            await FinanceSecureStorage.saveOrganizations(orgs);
            debugPrint('✅ Finance login: organizations list saved (${orgs.length})');
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ Finance login error: $e');
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  // ── Select Org ────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> selectOrg(String orgId) async {
    try {
      final mainToken  = await FinanceSecureStorage.getToken();
      final tempToken  = await FinanceSecureStorage.getTempToken();
      final activeToken = (mainToken != null && mainToken.isNotEmpty)
          ? mainToken
          : tempToken;

      final headers = {
        'Content-Type': 'application/json',
        if (activeToken != null && activeToken.isNotEmpty)
          'Authorization': 'Bearer $activeToken',
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/api/finance/auth/select-org'),
        headers: headers,
        body: jsonEncode({'orgId': orgId}),
      );
      final result = jsonDecode(response.body) as Map<String, dynamic>;

      if (result['success'] == true && result['data'] != null) {
        final data      = result['data'] as Map<String, dynamic>;
        final savedOrgs = await FinanceSecureStorage.getOrganizations();

        // ✅ _persistSession now saves orgLogoUrl for the selected org
        await _persistSession(data);

        // Preserve full org list (backend returns enriched list with logos)
        final returnedOrgs = (data['user'] as Map?)
            ?['organizations'] as List?;
        if (returnedOrgs != null && returnedOrgs.isNotEmpty) {
          await FinanceSecureStorage.saveOrganizations(returnedOrgs);
          debugPrint('✅ Finance select-org: enriched org list saved (${returnedOrgs.length})');
        } else if (savedOrgs.isNotEmpty) {
          await FinanceSecureStorage.saveOrganizations(savedOrgs);
          debugPrint('✅ Finance select-org: preserved existing org list (${savedOrgs.length})');
        }

        await FinanceSecureStorage.clearTempToken();
        debugPrint('✅ Finance select-org: session persisted for orgId=$orgId');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Finance select-org error: $e');
      return {'success': false, 'message': 'Network error. Please try again.'};
    }
  }

  // ── Upload Org Logo ───────────────────────────────────────────────────────────
  /// Uploads a logo image for the current organisation.
  /// [imageFile]  — File from image_picker (mobile / desktop)
  /// [imageBytes] — Uint8List from image_picker (web)
  /// [filename]   — original filename (e.g. "logo.png")
  static Future<Map<String, dynamic>> uploadOrgLogo({
    File? imageFile,
    Uint8List? imageBytes,
    required String filename,
  }) async {
    try {
      final token = await FinanceSecureStorage.getToken();
      final uri   = Uri.parse('$_baseUrl/api/finance/auth/upload-org-logo');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${token ?? ''}';

      final ext      = filename.split('.').last.toLowerCase();
      final mimeType = ext == 'png'  ? 'image/png'  :
                       ext == 'webp' ? 'image/webp' : 'image/jpeg';

      if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'logo',
          imageFile.path,
          contentType: MediaType.parse(mimeType),
        ));
      } else if (imageBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'logo',
          imageBytes,
          filename:    filename,
          contentType: MediaType.parse(mimeType),
        ));
      } else {
        return {'success': false, 'message': 'No image provided'};
      }

      final streamed  = await request.send();
      final response  = await http.Response.fromStream(streamed);
      final result    = jsonDecode(response.body) as Map<String, dynamic>;

      // ✅ Update stored orgLogoUrl immediately on success
      if (result['success'] == true) {
        final logoUrl = result['data']?['logoUrl']?.toString();
        if (logoUrl != null && logoUrl.isNotEmpty) {
          // Re-save session with updated logo URL
          final orgId   = await FinanceSecureStorage.getOrgId()   ?? '';
          final orgName = await FinanceSecureStorage.getOrgName() ?? '';

          // Update organizations list with new logo
          final orgs = await FinanceSecureStorage.getOrganizations();
          final updatedOrgs = orgs.map((o) {
            if (o['orgId'] == orgId) return {...o, 'logoUrl': logoUrl};
            return o;
          }).toList();
          await FinanceSecureStorage.saveOrganizations(updatedOrgs);

          // Update the stored orgLogoUrl directly
          final token2 = await FinanceSecureStorage.getToken()  ?? '';
          final userId = await FinanceSecureStorage.getUserId() ?? '';
          final name   = await FinanceSecureStorage.getName()   ?? '';
          final email  = await FinanceSecureStorage.getEmail()  ?? '';
          final phone  = await FinanceSecureStorage.getPhone()  ?? '';
          final role   = await FinanceSecureStorage.getRole()   ?? '';
          await FinanceSecureStorage.saveSession(
            token:      token2,
            userId:     userId,
            name:       name,
            email:      email,
            phone:      phone,
            role:       role,
            orgId:      orgId,
            orgName:    orgName,
            orgLogoUrl: logoUrl,   // ✅
          );
          debugPrint('✅ orgLogoUrl updated in storage: $logoUrl');
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ uploadOrgLogo error: $e');
      return {'success': false, 'message': 'Upload failed: $e'};
    }
  }

  // ── Delete Org Logo ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> deleteOrgLogo() async {
    try {
      final result = await delete('/api/finance/auth/delete-org-logo');
      if (result['success'] == true) {
        // Clear the stored logo URL
        final orgId   = await FinanceSecureStorage.getOrgId()   ?? '';
        final token2  = await FinanceSecureStorage.getToken()   ?? '';
        final userId  = await FinanceSecureStorage.getUserId()  ?? '';
        final name    = await FinanceSecureStorage.getName()    ?? '';
        final email   = await FinanceSecureStorage.getEmail()   ?? '';
        final phone   = await FinanceSecureStorage.getPhone()   ?? '';
        final role    = await FinanceSecureStorage.getRole()    ?? '';
        final orgName = await FinanceSecureStorage.getOrgName() ?? '';

        final orgs = await FinanceSecureStorage.getOrganizations();
        final updatedOrgs = orgs.map((o) {
          if (o['orgId'] == orgId) return {...o, 'logoUrl': null};
          return o;
        }).toList();
        await FinanceSecureStorage.saveOrganizations(updatedOrgs);

        await FinanceSecureStorage.saveSession(
          token:      token2,
          userId:     userId,
          name:       name,
          email:      email,
          phone:      phone,
          role:       role,
          orgId:      orgId,
          orgName:    orgName,
          orgLogoUrl: null,
        );
        debugPrint('✅ orgLogoUrl cleared from storage');
      }
      return result;
    } catch (e) {
      debugPrint('❌ deleteOrgLogo error: $e');
      return {'success': false, 'message': 'Delete failed: $e'};
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────────
  static Future<void> logout() async {
    await FinanceSecureStorage.clearSession();
  }

  // ── Generic authenticated GET ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final headers  = await _authHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: headers,
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // ── Generic authenticated POST ────────────────────────────────────────────────
  static Future<Map<String, dynamic>> post(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final headers  = await _authHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode(body),
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // ── Generic authenticated PUT ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> put(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final headers  = await _authHeaders();
      final response = await http.put(
        Uri.parse('$_baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode(body),
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // ── Generic authenticated DELETE ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final headers  = await _authHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl$endpoint'),
        headers: headers,
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }
}

// ── Extension: Banking / Document methods ─────────────────────────────────────
extension FinanceAuthServiceBanking on FinanceAuthService {
  // These are static helpers — call as FinanceAuthService.uploadOrgQr(...)
}

// Standalone static helpers added outside the class to avoid the strReplace issue:

class FinanceAuthServiceExtra {
  static String get _baseUrl => FinanceApiConfig.baseUrl;

  static Future<Map<String, String>> _authHeaders() async {
    final token = await FinanceSecureStorage.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Upload Org QR Code ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> uploadOrgQr({
    File? imageFile,
    Uint8List? imageBytes,
    required String filename,
  }) async {
    try {
      final token = await FinanceSecureStorage.getToken();
      final uri   = Uri.parse('$_baseUrl/api/finance/auth/upload-org-qr');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${token ?? ''}';
      final ext      = filename.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
      if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('qr', imageFile.path, contentType: MediaType.parse(mimeType)));
      } else if (imageBytes != null) {
        request.files.add(http.MultipartFile.fromBytes('qr', imageBytes, filename: filename, contentType: MediaType.parse(mimeType)));
      } else {
        return {'success': false, 'message': 'No image provided'};
      }
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'QR upload failed: $e'};
    }
  }

  // ── Upload Org Document ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> uploadOrgDocument({
    File? docFile,
    Uint8List? docBytes,
    required String filename,
    required String label,
  }) async {
    try {
      final token = await FinanceSecureStorage.getToken();
      final uri   = Uri.parse('$_baseUrl/api/finance/auth/upload-org-document');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${token ?? ''}'
        ..fields['label'] = label;
      if (docFile != null) {
        request.files.add(await http.MultipartFile.fromPath('document', docFile.path));
      } else if (docBytes != null) {
        request.files.add(http.MultipartFile.fromBytes('document', docBytes, filename: filename));
      } else {
        return {'success': false, 'message': 'No file provided'};
      }
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Document upload failed: $e'};
    }
  }

  // ── Delete Org Document ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> deleteOrgDocument(String docId) async {
    try {
      final headers  = await _authHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/finance/auth/org-document/$docId'),
        headers: headers,
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Delete failed: $e'};
    }
  }
}
