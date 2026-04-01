// permissions_finance.dart
// Finance permissions — service + full overlay UI in one file.
// Modules grouped by: Sales, Purchases, Inventory, Accounting, Expenses, Reports, Settings.
// Navy gradient color system from new_credit_note.dart.

import 'package:flutter/material.dart';
import '../data/services/finance_auth_service.dart';

// ── Colors ───────────────────────────────────────────────────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

// ── Service ──────────────────────────────────────────────────────────────────
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

// ── Finance permission modules ────────────────────────────────────────────────
const List<Map<String, dynamic>> _kModules = [
  {
    'group': 'Sales',
    'icon': Icons.point_of_sale,
    'permissions': {
      'invoices':           'Invoices',
      'customers':          'Customers',
      'credit_notes':       'Credit Notes',
      'quotes':             'Quotes',
      'sales_orders':       'Sales Orders',
      'payments_received':  'Payments Received',
      'delivery_challans':  'Delivery Challans',
      'recurring_invoices': 'Recurring Invoices',
    },
  },
  {
    'group': 'Purchases',
    'icon': Icons.shopping_cart_outlined,
    'permissions': {
      'bills':              'Bills',
      'vendors':            'Vendors',
      'purchase_orders':    'Purchase Orders',
      'vendor_credits':     'Vendor Credits',
      'payments_made':      'Payments Made',
      'recurring_bills':    'Recurring Bills',
    },
  },
  {
    'group': 'Inventory',
    'icon': Icons.inventory_2_outlined,
    'permissions': {
      'items': 'Items / Products',
    },
  },
  {
    'group': 'Expenses',
    'icon': Icons.receipt_outlined,
    'permissions': {
      'expenses':           'Expenses',
      'recurring_expenses': 'Recurring Expenses',
    },
  },
  {
    'group': 'Accounting',
    'icon': Icons.account_balance_outlined,
    'permissions': {
      'chart_of_accounts':    'Chart of Accounts',
      'manual_journals':      'Manual Journals',
      'currency_adjustments': 'Currency Adjustments',
      'reconciliation':       'Reconciliation',
      'budgets':              'Budgets',
      'bank_accounts':        'Bank Accounts',
    },
  },
  {
    'group': 'Time Tracking',
    'icon': Icons.access_time_outlined,
    'permissions': {
      'projects':   'Projects',
      'timesheets': 'Timesheets',
    },
  },
  {
    'group': 'TMS',
    'icon': Icons.confirmation_number_outlined,
    'permissions': {
      'raise_ticket':   'Raise a Ticket',
      'my_tickets':     'My Tickets',
      'all_tickets':    'All Tickets',
      'closed_tickets': 'Closed Tickets',
    },
  },
  {
    'group': 'Reports',
    'icon': Icons.analytics_outlined,
    'permissions': {
      'reports':       'All Reports',
      'profit_loss':   'Profit & Loss',
      'balance_sheet': 'Balance Sheet',
      'cash_flow':     'Cash Flow',
      'aging_reports': 'Aging Reports',
    },
  },
  {
    'group': 'Settings',
    'icon': Icons.settings_outlined,
    'permissions': {
      'banking':             'Banking',
      'rate_cards':          'Rate Cards',
      'org_settings':        'Organization Settings',
      'tax_settings':        'Tax Settings',
      'role_access_control': 'Role Access Control',
    },
  },
];

// ── Screen (overlay) ─────────────────────────────────────────────────────────
class FinancePermissionsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const FinancePermissionsScreen({super.key, required this.userId, required this.userName});

  static Future<void> showOverlay(BuildContext context, {required String userId, required String userName}) {
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
  State<FinancePermissionsScreen> createState() => _FinancePermissionsScreenState();
}

class _FinancePermissionsScreenState extends State<FinancePermissionsScreen> {
  Map<String, Map<String, dynamic>> _perms = {};
  bool _loading = true;
  bool _saving  = false;

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
      final raw = (res['data']?['permissions'] ?? res['permissions'] ?? {}) as Map<String, dynamic>;
      final converted = <String, Map<String, dynamic>>{};
      raw.forEach((k, v) {
        if (v is Map) {
          converted[k] = {
            'can_access':  v['can_access']  == true || v['can_access']  == 1,
            'edit_delete': v['edit_delete'] == true || v['edit_delete'] == 1,
          };
        } else if (v is bool) {
          converted[k] = {'can_access': v, 'edit_delete': false};
        }
      });
      setState(() => _perms = converted);
    }
    setState(() => _loading = false);
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await FinancePermissionsService.savePermissions(widget.userId, _perms);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      _toast('Permissions saved!');
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context);
    } else {
      _toast(res['message'] ?? 'Failed to save', error: true);
    }
  }

  // ── Permission helpers ─────────────────────────────────────────────────────
  bool _access(String k) => _perms[k]?['can_access']  == true;
  bool _edit(String k)   => _perms[k]?['edit_delete'] == true;

  void _toggle(String k, String type, bool v) {
    setState(() {
      _perms[k] ??= {};
      _perms[k]![type] = v;
      if (type == 'can_access' && !v) _perms[k]!['edit_delete'] = false;
    });
  }

  void _setGroup(Map<String, String> perms, bool v) {
    setState(() {
      for (final k in perms.keys) {
        _perms[k] = {'can_access': v, 'edit_delete': v};
      }
    });
  }

  void _setAll(bool v) {
    setState(() {
      for (final m in _kModules) {
        final p = m['permissions'] as Map<String, String>;
        for (final k in p.keys) {
          _perms[k] = {'can_access': v, 'edit_delete': v};
        }
      }
    });
  }

  int _enabled(Map<String, String> perms) => perms.keys.where(_access).length;

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(builder: (ctx, constraints) {
        final isWide = constraints.maxWidth > 700;
        return Center(
          child: Container(
            margin: EdgeInsets.all(isWide ? 24 : 8),
            constraints: BoxConstraints(maxWidth: isWide ? 720 : double.infinity, maxHeight: constraints.maxHeight - 32),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40, offset: const Offset(0, 16))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Column(children: [
                _buildHero(),
                _buildQuickActions(),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: _navyLight))
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
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_navyDark, _navyMid]),
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_navyAccent, _navyLight]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.security, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.13), borderRadius: BorderRadius.circular(50), border: Border.all(color: Colors.white.withOpacity(0.25))),
            child: const Text('Finance Permissions', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
          const SizedBox(height: 5),
          const Text('Manage Access', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          Text('for ${widget.userName}', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
        ])),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
            child: const Icon(Icons.close, color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }

  // ── Quick action buttons ───────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        _qBtn('Select All',  Icons.check_circle_outline, const Color(0xFF16A34A), const Color(0xFFF0FDF4), const Color(0xFF86EFAC), () => _setAll(true)),
        const SizedBox(width: 8),
        _qBtn('Edit All',    Icons.edit_outlined,        _navyLight,               const Color(0xFFEFF6FF), const Color(0xFFBFDBFE), () {
          setState(() {
            for (final m in _kModules) {
              for (final k in (m['permissions'] as Map<String, String>).keys) {
                _perms[k] ??= {};
                _perms[k]!['edit_delete'] = true;
              }
            }
          });
        }),
        const SizedBox(width: 8),
        _qBtn('Clear All',   Icons.clear_all,            const Color(0xFFDC2626), const Color(0xFFFEF2F2), const Color(0xFFFECACA), () => _setAll(false)),
      ]),
    );
  }

  Widget _qBtn(String label, IconData icon, Color color, Color bg, Color border, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: bg, border: Border.all(color: border, width: 1.5), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  // ── Group card ────────────────────────────────────────────────────────────
  Widget _buildGroupCard(Map<String, dynamic> module) {
    final group = module['group'] as String;
    final icon  = module['icon'] as IconData;
    final perms = module['permissions'] as Map<String, String>;
    final en    = _enabled(perms);
    final total = perms.length;
    final hasAny = en > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasAny ? _navyAccent.withOpacity(0.4) : const Color(0xFFE2E8F0), width: hasAny ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // Card header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)]),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
            border: Border(bottom: BorderSide(color: hasAny ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0), width: hasAny ? 1.5 : 1)),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_navyDark, _navyLight]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(group, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _navyDark))),
            if (hasAny) Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: _navyDark, borderRadius: BorderRadius.circular(20)),
              child: Text('$en/$total', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 6),
            _mBtn('All',   const Color(0xFF16A34A), () => _setGroup(perms, true)),
            const SizedBox(width: 4),
            _mBtn('Clear', const Color(0xFFDC2626), () => _setGroup(perms, false)),
          ]),
        ),
        // Permissions list
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(children: [
            // Column headers
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Expanded(child: SizedBox()),
                _colHdr('Access',       const Color(0xFF16A34A)),
                const SizedBox(width: 4),
                _colHdr('Edit/Delete',  _navyLight),
              ]),
            ),
            ...perms.entries.map((e) => _permRow(e.key, e.value)).toList(),
          ]),
        ),
      ]),
    );
  }

  Widget _mBtn(String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.08), border: Border.all(color: color.withOpacity(0.35)), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    ),
  );

  Widget _colHdr(String label, Color color) => SizedBox(
    width: 80,
    child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.3)),
  );

  Widget _permRow(String key, String label) {
    final canAccess = _access(key);
    final canEdit   = _edit(key);
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: canAccess ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: canAccess ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: canAccess ? FontWeight.w700 : FontWeight.w500,
          color: canAccess ? const Color(0xFF1E293B) : const Color(0xFF64748B),
        ))),
        SizedBox(width: 80, child: Center(child: _checkbox(canAccess, const Color(0xFF16A34A), (v) => _toggle(key, 'can_access', v ?? false)))),
        SizedBox(width: 80, child: Center(child: _checkbox(canEdit, _navyLight, canAccess ? (v) => _toggle(key, 'edit_delete', v ?? false) : null, enabled: canAccess))),
      ]),
    );
  }

  Widget _checkbox(bool value, Color color, ValueChanged<bool?>? onChange, {bool enabled = true}) {
    return Transform.scale(
      scale: 1.1,
      child: Checkbox(
        value: value,
        onChanged: enabled ? onChange : null,
        activeColor: color,
        checkColor: Colors.white,
        side: BorderSide(color: enabled ? (value ? color : const Color(0xFFCBD5E1)) : const Color(0xFFE2E8F0), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ── Submit bar ─────────────────────────────────────────────────────────────
  Widget _buildSubmitBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [_navyDark, _navyMid]),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
      ),
      child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: _saving ? null : () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5), borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
          ),
        )),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: GestureDetector(
          onTap: _saving ? null : _save,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_navyAccent, _navyLight]),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: _navyAccent.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(_saving ? 'Saving...' : 'Save Permissions',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
            ]),
          ),
        )),
      ]),
    );
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: error ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: Duration(milliseconds: error ? 3000 : 1500),
    ));
  }
}
