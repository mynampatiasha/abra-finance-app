// finance_secure_storage.dart
// Stores finance JWT separately from fleet JWT using flutter_secure_storage

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FinanceSecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _keyToken         = 'finance_jwt_token';
  static const _keyUserId        = 'finance_user_id';
  static const _keyName          = 'finance_user_name';
  static const _keyEmail         = 'finance_user_email';
  static const _keyPhone         = 'finance_user_phone';
  static const _keyRole          = 'finance_user_role';
  static const _keyOrgId         = 'finance_org_id';
  static const _keyOrgName       = 'finance_org_name';
  static const _keyOrgLogoUrl    = 'finance_org_logo_url';   // ✅ NEW
  static const _keyTempToken     = 'finance_temp_token';
  static const _keyPermissions   = 'finance_permissions';
  static const _keyOrganizations = 'finance_organizations';

  // ── Save full session after org selected ────────────────────────────────────
  static Future<void> saveSession({
    required String token,
    required String userId,
    required String name,
    required String email,
    required String phone,
    required String role,
    required String orgId,
    required String orgName,
    String? orgLogoUrl,          // ✅ NEW — optional so existing callers don't break
  }) async {
    await Future.wait([
      _storage.write(key: _keyToken,   value: token),
      _storage.write(key: _keyUserId,  value: userId),
      _storage.write(key: _keyName,    value: name),
      _storage.write(key: _keyEmail,   value: email),
      _storage.write(key: _keyPhone,   value: phone),
      _storage.write(key: _keyRole,    value: role),
      _storage.write(key: _keyOrgId,   value: orgId),
      _storage.write(key: _keyOrgName, value: orgName),
      // ✅ Save orgLogoUrl — write empty string if null so we can still read it
      _storage.write(key: _keyOrgLogoUrl, value: orgLogoUrl ?? ''),
    ]);
// Mirror JWT to SharedPreferences with org-specific key
final prefs = await SharedPreferences.getInstance();
await prefs.setString('jwt_token', token);    
await prefs.setString('finance_jwt_token', token);  // ← change key name
  }

  // ── Save permissions (JSON map) ─────────────────────────────────────────────
  static Future<void> savePermissions(Map<String, dynamic> permissions) async {
    await _storage.write(
      key:   _keyPermissions,
      value: jsonEncode(permissions),
    );
  }

  // ── Read permissions ────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getPermissions() async {
    try {
      final raw = await _storage.read(key: _keyPermissions);
      if (raw == null || raw.isEmpty) return {};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ── Save organizations array ────────────────────────────────────────────────
  static Future<void> saveOrganizations(List<dynamic> organizations) async {
    await _storage.write(
      key:   _keyOrganizations,
      value: jsonEncode(organizations),
    );
  }

  // ── Read organizations array ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getOrganizations() async {
    try {
      final raw = await _storage.read(key: _keyOrganizations);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Temp token for org-selector ─────────────────────────────────────────────
  static Future<void> saveTempToken(String token) =>
      _storage.write(key: _keyTempToken, value: token);

  static Future<String?> getTempToken() =>
      _storage.read(key: _keyTempToken);

  static Future<void> clearTempToken() =>
      _storage.delete(key: _keyTempToken);

  // ── Read ────────────────────────────────────────────────────────────────────
  static Future<String?> getToken()      => _storage.read(key: _keyToken);
  static Future<String?> getUserId()     => _storage.read(key: _keyUserId);
  static Future<String?> getName()       => _storage.read(key: _keyName);
  static Future<String?> getEmail()      => _storage.read(key: _keyEmail);
  static Future<String?> getPhone()      => _storage.read(key: _keyPhone);
  static Future<String?> getRole()       => _storage.read(key: _keyRole);
  static Future<String?> getOrgId()      => _storage.read(key: _keyOrgId);
  static Future<String?> getOrgName()    => _storage.read(key: _keyOrgName);

  /// Returns the org logo URL (relative path like /uploads/org-logos/xxx.jpg)
  /// or null if not set.
  static Future<String?> getOrgLogoUrl() async {
    final val = await _storage.read(key: _keyOrgLogoUrl);
    if (val == null || val.isEmpty) return null;
    return val;
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ── Clear (logout) ──────────────────────────────────────────────────────────
  static Future<void> clearSession() async {
    await Future.wait([
      _storage.delete(key: _keyToken),
      _storage.delete(key: _keyUserId),
      _storage.delete(key: _keyName),
      _storage.delete(key: _keyEmail),
      _storage.delete(key: _keyPhone),
      _storage.delete(key: _keyRole),
      _storage.delete(key: _keyOrgId),
      _storage.delete(key: _keyOrgName),
      _storage.delete(key: _keyOrgLogoUrl),    // ✅ NEW
      _storage.delete(key: _keyTempToken),
      _storage.delete(key: _keyPermissions),
      _storage.delete(key: _keyOrganizations),
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('finance_jwt_token');
  }
}