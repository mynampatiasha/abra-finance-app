// finance_secure_storage.dart
// Stores finance JWT separately from fleet JWT using flutter_secure_storage

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FinanceSecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _keyToken = 'finance_jwt_token';
  static const _keyUserId = 'finance_user_id';
  static const _keyName = 'finance_user_name';
  static const _keyEmail = 'finance_user_email';
  static const _keyPhone = 'finance_user_phone';
  static const _keyRole = 'finance_user_role';
  static const _keyOrgId = 'finance_org_id';
  static const _keyOrgName = 'finance_org_name';
  static const _keyOrgLogoUrl = 'finance_org_logo_url'; // ✅ NEW
  static const _keyEntityName =
      'finance_entity_name'; // ✅ NEW: Entity/Group name
  static const _keyTempToken = 'finance_temp_token';
  static const _keyPermissions = 'finance_permissions';
  static const _keyOrganizations = 'finance_organizations';
  // ── Branch keys ─────────────────────────────────────────────────────────────
  static const _keyBranches =
      'finance_branches'; // available branches for current org
  static const _keySelectedBranchIds =
      'finance_selected_branch_ids'; // JSON list of selected branchIds
  static const _keyAllowedBranchIds =
      'finance_allowed_branch_ids'; // JSON list of branches this user is permitted to access
  // ── Organization keys (NEW - Multi-org support) ─────────────────────────────
  static const _keySelectedOrgIds =
      'finance_selected_org_ids'; // JSON list of selected orgIds (empty = current org only)

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
    String? orgLogoUrl, // ✅ NEW — optional so existing callers don't break
    String? entityName, // ✅ NEW — optional entity/group name
  }) async {
    await Future.wait([
      _storage.write(key: _keyToken, value: token),
      _storage.write(key: _keyUserId, value: userId),
      _storage.write(key: _keyName, value: name),
      _storage.write(key: _keyEmail, value: email),
      _storage.write(key: _keyPhone, value: phone),
      _storage.write(key: _keyRole, value: role),
      _storage.write(key: _keyOrgId, value: orgId),
      _storage.write(key: _keyOrgName, value: orgName),
      // ✅ Save orgLogoUrl — write empty string if null so we can still read it
      _storage.write(key: _keyOrgLogoUrl, value: orgLogoUrl ?? ''),
      // ✅ Save entityName — write empty string if null
      _storage.write(key: _keyEntityName, value: entityName ?? ''),
    ]);
// Mirror JWT to SharedPreferences with org-specific key
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    await prefs.setString('finance_jwt_token', token); // ← change key name
  }

  // ── Save permissions (JSON map) ─────────────────────────────────────────────
  static Future<void> savePermissions(Map<String, dynamic> permissions) async {
    await _storage.write(
      key: _keyPermissions,
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
      key: _keyOrganizations,
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

  static Future<String?> getTempToken() => _storage.read(key: _keyTempToken);

  static Future<void> clearTempToken() => _storage.delete(key: _keyTempToken);

  // ── Read ────────────────────────────────────────────────────────────────────
  static Future<String?> getToken() => _storage.read(key: _keyToken);
  static Future<String?> getUserId() => _storage.read(key: _keyUserId);
  static Future<String?> getName() => _storage.read(key: _keyName);
  static Future<String?> getEmail() => _storage.read(key: _keyEmail);
  static Future<String?> getPhone() => _storage.read(key: _keyPhone);
  static Future<String?> getRole() => _storage.read(key: _keyRole);
  static Future<String?> getOrgId() => _storage.read(key: _keyOrgId);
  static Future<String?> getOrgName() => _storage.read(key: _keyOrgName);

  /// Returns the org logo URL (relative path like /uploads/org-logos/xxx.jpg)
  /// or null if not set.
  static Future<String?> getOrgLogoUrl() async {
    final val = await _storage.read(key: _keyOrgLogoUrl);
    if (val == null || val.isEmpty) return null;
    return val;
  }

  /// Save entity/group name (display label only)
  static Future<void> saveEntityName(String entityName) async {
    await _storage.write(key: _keyEntityName, value: entityName);
  }

  /// Returns the entity/group name or null if not set
  static Future<String?> getEntityName() async {
    final val = await _storage.read(key: _keyEntityName);
    if (val == null || val.isEmpty) return null;
    return val;
  }

  /// Returns true only if a token exists AND has not expired.
  /// If the token is expired, the session is cleared automatically so the
  /// user is sent back to the welcome screen on next app start / reload.
  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;

    try {
      // JWT is three base64url parts separated by '.'
      final parts = token.split('.');
      if (parts.length != 3) {
        await clearSession();
        return false;
      }

      // Decode the payload (second part) — add padding if needed
      String payload = parts[1];
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
        default:
          break;
      }

      final decoded = jsonDecode(utf8.decode(base64Decode(payload)))
          as Map<String, dynamic>;
      final exp = decoded['exp'];
      if (exp == null) return true; // no expiry claim — treat as valid

      final expiryDate =
          DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
      if (DateTime.now().isAfter(expiryDate)) {
        debugPrint(
            '⚠️ Finance token expired at $expiryDate — clearing session');
        await clearSession();
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('❌ isLoggedIn token decode error: $e — clearing session');
      await clearSession();
      return false;
    }
  }

  // ── Branch storage ──────────────────────────────────────────────────────────
  /// Save available branches for the current org
  static Future<void> saveBranches(List<dynamic> branches) async {
    await _storage.write(key: _keyBranches, value: jsonEncode(branches));
  }

  /// Read available branches
  static Future<List<Map<String, dynamic>>> getBranches() async {
    try {
      final raw = await _storage.read(key: _keyBranches);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Save selected branch IDs (empty list = ALL branches)
  static Future<void> saveSelectedBranchIds(List<String> ids) async {
    await _storage.write(key: _keySelectedBranchIds, value: jsonEncode(ids));
  }

  /// Read selected branch IDs
  static Future<List<String>> getSelectedBranchIds() async {
    try {
      final raw = await _storage.read(key: _keySelectedBranchIds);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Build the x-branch-ids header value
  /// Returns 'ALL' when no specific branches selected (show everything)
  static Future<String> getBranchHeader() async {
    try {
      final ids = await getSelectedBranchIds();
      debugPrint('🔧 getBranchHeader: selectedBranchIds = $ids');
      if (ids.isEmpty) {
        debugPrint(
            '🔧 getBranchHeader: returning ALL (no specific branches selected)');
        return 'ALL';
      }
      final header = ids.join(',');
      debugPrint('🔧 getBranchHeader: returning $header');
      return header;
    } catch (e, stackTrace) {
      debugPrint('❌ getBranchHeader error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('🔧 getBranchHeader: returning ALL (due to error)');
      return 'ALL';
    }
  }

  // ── Allowed branches (set by admin/owner per user) ──────────────────────────
  /// Save the list of branch IDs this user is permitted to access.
  /// Empty list = no restriction (all branches allowed).
  static Future<void> saveAllowedBranchIds(List<String> ids) async {
    await _storage.write(key: _keyAllowedBranchIds, value: jsonEncode(ids));
  }

  /// Read the allowed branch IDs for this user.
  /// Empty list means the user has access to all branches.
  static Future<List<String>> getAllowedBranchIds() async {
    try {
      final raw = await _storage.read(key: _keyAllowedBranchIds);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns true if the user has an explicit branch restriction.
  static Future<bool> hasBranchRestriction() async {
    final ids = await getAllowedBranchIds();
    return ids.isNotEmpty;
  }

  // ── Organization selection (NEW - Multi-org support) ────────────────────────
  /// Save selected organization IDs (empty list = current org only from token)
  /// Special value: ["ALL"] = all organizations user belongs to
  static Future<void> saveSelectedOrgIds(List<String> ids) async {
    await _storage.write(key: _keySelectedOrgIds, value: jsonEncode(ids));
  }

  /// Read selected organization IDs
  /// Empty list = use current org from token (default/backward compatible)
  static Future<List<String>> getSelectedOrgIds() async {
    try {
      final raw = await _storage.read(key: _keySelectedOrgIds);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Build the x-org-ids header value
  /// Returns:
  /// - 'ALL' when user selected all organizations
  /// - 'orgId1,orgId2' when specific orgs selected
  /// - current orgId when no selection (backward compatible)
  static Future<String> getOrgHeader() async {
    final ids = await getSelectedOrgIds();

    // Special case: ["ALL"] means all organizations
    if (ids.length == 1 && ids[0] == 'ALL') {
      return 'ALL';
    }

    // Specific orgs selected
    if (ids.isNotEmpty) {
      return ids.join(',');
    }

    // Default: use current org from token (backward compatible)
    final currentOrgId = await getOrgId();
    return currentOrgId ?? '';
  }

  /// Returns true if multi-org mode is active (user selected multiple orgs or ALL)
  static Future<bool> isMultiOrgMode() async {
    final ids = await getSelectedOrgIds();
    if (ids.isEmpty) return false;
    if (ids.length == 1 && ids[0] == 'ALL') return true;
    return ids.length > 1;
  }

  /// Clear organization selection (revert to single org mode)
  static Future<void> clearOrgSelection() async {
    await _storage.delete(key: _keySelectedOrgIds);
  }

  // ── Clear (logout) ──────────────────────────────────────────────────────────
  static Future<void> clearSession() async {
    // ✅ FIX: deleteAll() is atomic and future-proof — no missed keys
    await _storage.deleteAll();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('finance_jwt_token');
  }
}
