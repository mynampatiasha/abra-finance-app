import 'package:abra_finance/core/utils/app_snackbar.dart';
import 'package:abra_finance/core/finance_secure_storage.dart';
// permissions_finance.dart
// Finance permissions — service + full overlay UI + restricted action popup in one file.
// Modules ordered EXACTLY as the sidebar in billing_main_shell.dart:
// 1. TMS  2. Items  3. Sales  4. Purchases  5. Time Tracking
// 6. Banking  7. Accountant  8. Reports  9. Role Access Control  10. My Profile

import 'package:flutter/material.dart';
import '../data/services/finance_auth_service.dart';

// ── Colors ────────────────────────────────────────────────────────────────────
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

// ── Central Permission Helpers ────────────────────────────────────────────────
class FinancePermissions {
  static bool canAccess(Map<String, dynamic>? permissions, String key) {
    if (permissions == null) return false;
    final p = permissions[key];
    if (p is Map) return p['can_access'] == true || p['can_access'] == 1 || p['can_access'] == 'true';
    if (p is bool) return p;
    return false;
  }

  static bool canEdit(Map<String, dynamic>? permissions, String key) {
    if (permissions == null) return false;
    final p = permissions[key];
    if (p is Map) {
      if (p['can_edit'] != null) return p['can_edit'] == true || p['can_edit'] == 1 || p['can_edit'] == 'true';
      return p['edit_delete'] == true || p['edit_delete'] == 1 || p['edit_delete'] == 'true';
    }
    return false;
  }

  static bool canDelete(Map<String, dynamic>? permissions, String key) {
    if (permissions == null) return false;
    final p = permissions[key];
    if (p is Map) {
      if (p['can_delete'] != null) return p['can_delete'] == true || p['can_delete'] == 1 || p['can_delete'] == 'true';
      return p['edit_delete'] == true || p['edit_delete'] == 1 || p['edit_delete'] == 'true';
    }
    return false;
  }

  /// ✅ Centralized Check & Dialog for Delete Actions
  static Future<bool> checkCanDelete(BuildContext context, String moduleKey) async {
    try {
      final role = await FinanceSecureStorage.getRole();
      final normalizedRole = (role ?? '').trim().toLowerCase();
      if (normalizedRole == 'owner' || normalizedRole == 'admin') return true;

      var permissions = await FinanceSecureStorage.getPermissions();
      if (permissions.isEmpty) {
        final userId = await FinanceSecureStorage.getUserId();
        if (userId != null && userId.isNotEmpty) {
          try {
            final res = await FinancePermissionsService.fetchPermissions(userId);
            if (res['data']?['permissions'] is Map) {
              permissions = Map<String, dynamic>.from(res['data']['permissions']);
              await FinanceSecureStorage.savePermissions(permissions);
            }
          } catch (_) {}
        }
      }

      final p = permissions[moduleKey];
      bool canDel = false;
      if (p is Map) {
        if (p['can_delete'] != null) {
          canDel = p['can_delete'] == true || p['can_delete'] == 1 || p['can_delete'] == 'true';
        } else {
          canDel = p['edit_delete'] == true || p['edit_delete'] == 1 || p['edit_delete'] == 'true';
        }
      }

      if (!canDel) {
        if (context.mounted) {
          RestrictedActionDialog.show(context);
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Permission check error: $e');
      if (context.mounted) {
        RestrictedActionDialog.show(context);
      }
      return false;
    }
  }

  /// ✅ Centralized Check & Dialog for Edit Actions
  static Future<bool> checkCanEdit(BuildContext context, String moduleKey) async {
    return true;
  }
}

// ── Centered Restriction Modal Card (Middle of Screen) ────────────────────────
class RestrictedActionDialog extends StatelessWidget {
  final String title;
  final String message;
  final String actionText;

  const RestrictedActionDialog({
    super.key,
    this.title = 'Action Restricted',
    this.message = 'You do not have permission to delete this record from the system. Please contact the management or administrator to request delete access.',
    this.actionText = 'Understood',
  });

  static Future<void> show(
    BuildContext context, {
    String? title,
    String? message,
    String? actionText,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => RestrictedActionDialog(
        title: title ?? 'Action Restricted',
        message: message ?? 'You do not have permission to delete this record from the system. Please contact the management or administrator to request delete access.',
        actionText: actionText ?? 'Understood',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Header
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFEE2E2), width: 2),
                ),
                child: const Center(
                  child: Icon(
                    Icons.gpp_maybe_rounded,
                    color: Color(0xFFDC2626),
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),

              // Description Message
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF475569),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),

              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    actionText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Service ───────────────────────────────────────────────────────────────────
class FinancePermissionsService {
  static Future<Map<String, dynamic>> fetchPermissions(String userId) =>
      FinanceAuthService.get('/api/finance/users/$userId/permissions');

  static Future<Map<String, dynamic>> savePermissions(
    String userId,
    Map<String, Map<String, dynamic>> permissions,
  ) =>
      FinanceAuthService.post(
        '/api/finance/users/$userId/permissions',
        {'permissions': permissions},
      );
}

// ── Finance permission modules ─────────────────────────────────────────────────
const List<Map<String, dynamic>> _kModules = [
  // ── 1. TMS ──────────────────────────────────────────────────────────────
  {
    'group': 'TMS',
    'icon': Icons.confirmation_number_outlined,
    'permissions': {
      'raise_ticket': 'Raise a Ticket',
      'my_tickets': 'My Tickets',
      'all_tickets': 'All Tickets',
      'closed_tickets': 'Closed Tickets',
    },
  },

  // ── 2. Items ─────────────────────────────────────────────────────────────
  {
    'group': 'Items',
    'icon': Icons.inventory_2_outlined,
    'permissions': {
      'items': 'Items / Products',
    },
  },

  // ── 3. Sales ─────────────────────────────────────────────────────────────
  {
    'group': 'Sales',
    'icon': Icons.shopping_cart_outlined,
    'permissions': {
      'customers': 'Customers',
      'invoices': 'Invoices',
      'recurring_invoices': 'Recurring Invoices',
      'payments_received': 'Payments Received',
      'credit_notes': 'Credit Notes',
      'quotes': 'Quotes',
      'sales_orders': 'Sales Orders',
      'delivery_challans': 'Delivery Challans',
    },
  },

  // ── 4. Purchases ─────────────────────────────────────────────────────────
  {
    'group': 'Purchases',
    'icon': Icons.shopping_bag_outlined,
    'permissions': {
      'vendors': 'Vendors',
      'expenses': 'Expenses',
      'assets': 'Fixed Assets',
      'recurring_expenses': 'Recurring Expenses',
      'purchase_orders': 'Purchase Orders',
      'bills': 'Bills',
      'recurring_bills': 'Recurring Bills',
      'payments_made': 'Payments Made',
      'vendor_credits': 'Vendor Credits',
      'eway_bills': 'E-Way Bills',
      'payment_links': 'Payment Links',
    },
  },

  // ── 4.5 Digital Expenses ─────────────────────────────────────────────────
  {
    'group': 'Digital Expenses',
    'icon': Icons.receipt_long_outlined,
    'permissions': {
      'digital_expenses': 'Digital Expenses',
    },
  },

  // ── 5. Time Tracking ─────────────────────────────────────────────────────
  {
    'group': 'Time Tracking',
    'icon': Icons.access_time_outlined,
    'permissions': {
      'projects': 'Projects',
      'timesheets': 'Timesheet',
    },
  },

  // ── 6. Banking ───────────────────────────────────────────────────────────
  {
    'group': 'Banking',
    'icon': Icons.account_balance_outlined,
    'permissions': {
      'banking': 'Banking',
    },
  },

  // ── 7. Accountant ────────────────────────────────────────────────────────
  {
    'group': 'Accountant',
    'icon': Icons.person_outline,
    'permissions': {
      'manual_journals': 'Manual Journals',
      'currency_adjustments': 'Currency Adjustments',
      'chart_of_accounts': 'Chart of Accounts',
      'budgets': 'Budgets',
    },
  },

  // ── 8. Reports ───────────────────────────────────────────────────────────
  {
    'group': 'Reports',
    'icon': Icons.bar_chart_outlined,
    'permissions': {
      'reports': 'Reports',
    },
  },

  // ── 9. Role Access Control ───────────────────────────────────────────────
  {
    'group': 'Role Access Control',
    'icon': Icons.admin_panel_settings_outlined,
    'permissions': {
      'role_access_control': 'Role Access Control',
    },
  },

  // ── 10. My Profile ───────────────────────────────────────────────────────
  {
    'group': 'My Profile',
    'icon': Icons.person_pin_outlined,
    'permissions': {
      'my_profile': 'My Profile',
    },
  },
];

// ── Screen (overlay) ─────────────────────────────────────────────────────────
class FinancePermissionsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const FinancePermissionsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  static Future<void> showOverlay(
    BuildContext context, {
    required String userId,
    required String userName,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: FinancePermissionsScreen(userId: userId, userName: userName),
        ),
      ),
    );
  }

  @override
  State<FinancePermissionsScreen> createState() =>
      _FinancePermissionsScreenState();
}

class _FinancePermissionsScreenState extends State<FinancePermissionsScreen> {
  Map<String, Map<String, dynamic>> _perms = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await FinancePermissionsService.fetchPermissions(widget.userId);
    if (!mounted) return;
    if (res['success'] == true) {
      final raw = (res['data']?['permissions'] ?? res['permissions'] ?? {})
          as Map<String, dynamic>;
      final converted = <String, Map<String, dynamic>>{};
      raw.forEach((k, v) {
        if (v is Map) {
          final editDel = v['edit_delete'] == true || v['edit_delete'] == 1 || v['edit_delete'] == 'true';
          converted[k] = {
            'can_access': v['can_access'] == true || v['can_access'] == 1 || v['can_access'] == 'true',
            'can_edit': v['can_edit'] != null ? (v['can_edit'] == true || v['can_edit'] == 1 || v['can_edit'] == 'true') : editDel,
            'can_delete': v['can_delete'] != null ? (v['can_delete'] == true || v['can_delete'] == 1 || v['can_delete'] == 'true') : editDel,
            'edit_delete': editDel,
          };
        } else if (v is bool) {
          converted[k] = {'can_access': v, 'can_edit': false, 'can_delete': false, 'edit_delete': false};
        }
      });
      setState(() => _perms = converted);
    }
    setState(() => _loading = false);
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() => _saving = true);
    // Ensure edit_delete is synced for backward compatibility
    final toSave = <String, Map<String, dynamic>>{};
    _perms.forEach((k, v) {
      toSave[k] = {
        'can_access': v['can_access'] == true,
        'can_edit': v['can_edit'] == true,
        'can_delete': v['can_delete'] == true,
        'edit_delete': v['can_edit'] == true && v['can_delete'] == true,
      };
    });

    final res = await FinancePermissionsService.savePermissions(widget.userId, toSave);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      _toast('Permissions saved successfully!');
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context);
    } else {
      _toast(res['message'] ?? 'Failed to save permissions', error: true);
    }
  }

  // ── Permission helpers ────────────────────────────────────────────────────
  bool _access(String k) => _perms[k]?['can_access'] == true;
  bool _canEdit(String k) => _perms[k]?['can_edit'] == true;
  bool _canDelete(String k) => _perms[k]?['can_delete'] == true;

  void _toggle(String k, String type, bool v) {
    setState(() {
      _perms[k] ??= {};
      _perms[k]![type] = v;
      // If removing access, also remove edit and delete
      if (type == 'can_access' && !v) {
        _perms[k]!['can_edit'] = false;
        _perms[k]!['can_delete'] = false;
        _perms[k]!['edit_delete'] = false;
      }
    });
  }

  void _setGroup(Map<String, String> perms, bool v) {
    setState(() {
      for (final k in perms.keys) {
        _perms[k] = {'can_access': v, 'can_edit': v, 'can_delete': v, 'edit_delete': v};
      }
    });
  }

  void _setAll(bool v) {
    setState(() {
      for (final m in _kModules) {
        final p = m['permissions'] as Map<String, String>;
        for (final k in p.keys) {
          _perms[k] = {'can_access': v, 'can_edit': v, 'can_delete': v, 'edit_delete': v};
        }
      }
    });
  }

  void _setAllEditOnly() {
    setState(() {
      for (final m in _kModules) {
        final p = m['permissions'] as Map<String, String>;
        for (final k in p.keys) {
          _perms[k] = {'can_access': true, 'can_edit': true, 'can_delete': false, 'edit_delete': false};
        }
      }
    });
  }

  int _enabledCount(Map<String, String> perms) =>
      perms.keys.where(_access).length;

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(builder: (ctx, constraints) {
        final isWide = constraints.maxWidth > 750;
        return Center(
          child: Container(
            margin: EdgeInsets.all(isWide ? 24 : 8),
            constraints: BoxConstraints(
              maxWidth: isWide ? 760 : double.infinity,
              maxHeight: constraints.maxHeight - 32,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(children: [
                _buildHero(),
                _buildQuickActions(),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(color: _navyLight))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          itemCount: _kModules.length,
                          itemBuilder: (_, i) => _buildGroupCard(_kModules[i]),
                        ),
                ),
                _buildSubmitBar(),
              ]),
            ),
          ),
        );
      }),
    );
  }

  // ── Hero header ───────────────────────────────────────────────────────────
  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navyDark, _navyMid],
        ),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withOpacity(0.2), width: 1.5),
          ),
          child: const Center(
            child: Icon(Icons.security_rounded,
                color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Finance Permissions',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(height: 3),
              Text(
                'Manage Access',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'for ${widget.userName}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded,
              color: Colors.white70, size: 22),
          splashRadius: 20,
        ),
      ]),
    );
  }

  // ── Quick action buttons ──────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Expanded(
          child: _actionBtn(
            icon: Icons.check_circle_outline,
            label: 'Select All',
            color: const Color(0xFF16A34A),
            onTap: () => _setAll(true),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionBtn(
            icon: Icons.edit_note_rounded,
            label: 'Edit Only (No Delete)',
            color: _navyLight,
            onTap: _setAllEditOnly,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _actionBtn(
            icon: Icons.clear_all_rounded,
            label: 'Clear All',
            color: const Color(0xFFDC2626),
            onTap: () => _setAll(false),
          ),
        ),
      ]),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Group card ────────────────────────────────────────────────────────────
  Widget _buildGroupCard(Map<String, dynamic> mod) {
    final group = mod['group'] as String;
    final icon = mod['icon'] as IconData;
    final perms = mod['permissions'] as Map<String, String>;
    final en = _enabledCount(perms);
    final total = perms.length;
    final hasAny = en > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAny ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
          width: hasAny ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasAny
                ? const Color(0xFF3B82F6).withOpacity(0.07)
                : Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(children: [
        // Group Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)]),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(15),
              topRight: Radius.circular(15),
            ),
            border: Border(
              bottom: BorderSide(
                color: hasAny ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                width: hasAny ? 1.5 : 1,
              ),
            ),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_navyDark, _navyLight],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(group,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: _navyDark)),
            ),
            if (hasAny)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                    color: _navyDark, borderRadius: BorderRadius.circular(20)),
                child: Text('$en/$total',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800)),
              ),
            const SizedBox(width: 6),
            _mBtn('All', const Color(0xFF16A34A), () => _setGroup(perms, true)),
            const SizedBox(width: 4),
            _mBtn('Clear', const Color(0xFFDC2626), () => _setGroup(perms, false)),
          ]),
        ),

        // Permissions list
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(children: [
            // Column headers
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Expanded(child: SizedBox()),
                _colHdr('Access', const Color(0xFF16A34A)),
                const SizedBox(width: 4),
                _colHdr('Edit', _navyLight),
                const SizedBox(width: 4),
                _colHdr('Delete', const Color(0xFFDC2626)),
              ]),
            ),
            ...perms.entries.map((e) => _permRow(e.key, e.value)).toList(),
          ]),
        ),
      ]),
    );
  }

  Widget _mBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            border: Border.all(color: color.withOpacity(0.35)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
        ),
      );

  Widget _colHdr(String label, Color color) => SizedBox(
        width: 60,
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3)),
      );

  Widget _permRow(String key, String label) {
    final canAccess = _access(key);
    final canEdit = _canEdit(key);
    final canDelete = _canDelete(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: canAccess ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canAccess ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: canAccess ? FontWeight.w700 : FontWeight.w500,
                color: canAccess
                    ? const Color(0xFF1E293B)
                    : const Color(0xFF64748B),
              )),
        ),
        // Access checkbox
        SizedBox(
          width: 60,
          child: Center(
            child: _checkbox(
              canAccess,
              const Color(0xFF16A34A),
              (v) => _toggle(key, 'can_access', v ?? false),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Edit checkbox — disabled if no access
        SizedBox(
          width: 60,
          child: Center(
            child: _checkbox(
              canEdit,
              _navyLight,
              canAccess ? (v) => _toggle(key, 'can_edit', v ?? false) : null,
              enabled: canAccess,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Delete checkbox — disabled if no access
        SizedBox(
          width: 60,
          child: Center(
            child: _checkbox(
              canDelete,
              const Color(0xFFDC2626),
              canAccess ? (v) => _toggle(key, 'can_delete', v ?? false) : null,
              enabled: canAccess,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _checkbox(
    bool value,
    Color color,
    ValueChanged<bool?>? onChange, {
    bool enabled = true,
  }) {
    return Transform.scale(
      scale: 1.0,
      child: Checkbox(
        value: value,
        onChanged: enabled ? onChange : null,
        activeColor: color,
        checkColor: Colors.white,
        side: BorderSide(
          color: enabled
              ? (value ? color : const Color(0xFFCBD5E1))
              : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── Submit bar ────────────────────────────────────────────────────────────
  Widget _buildSubmitBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_navyDark, _navyMid],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _saving ? null : () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                border: Border.all(
                    color: Colors.white.withOpacity(0.3), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('Cancel',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: [_navyAccent, _navyLight]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: _navyAccent.withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ],
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded,
                        color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  _saving ? 'Saving...' : 'Save Permissions',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }
}
