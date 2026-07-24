// ============================================================================
// ABRA FINANCE SUITE — ORG SELECTOR PAGE
// ============================================================================
// File: lib/features/finance_auth/presentation/pages/finance_org_selector_page.dart
// ✅ Splash screen wired after org selection
// ✅ Navy glassmorphism theme — matches login/register pages
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/finance_secure_storage.dart';
import '../../data/services/finance_auth_service.dart';
import 'finance_login_page.dart';
import 'finance_post_login_splash.dart';
import 'finance_branch_selector_page.dart';
import '../billing/billing_main_shell.dart';

// ── Finance navy color system ─────────────────────────────────────────────────
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class FinanceOrgSelectorPage extends StatefulWidget {
  final List<Map<String, dynamic>> organizations;
  final Map<String, dynamic> user;
  final String?
      tempToken; // passed directly from login to avoid storage read issues on web

  const FinanceOrgSelectorPage({
    super.key,
    required this.organizations,
    required this.user,
    this.tempToken,
  });

  @override
  State<FinanceOrgSelectorPage> createState() => _FinanceOrgSelectorPageState();
}

class _FinanceOrgSelectorPageState extends State<FinanceOrgSelectorPage>
    with SingleTickerProviderStateMixin {
  String? _selectedOrgId; // Keep for single-select backward compatibility
  Set<String> _selectedOrgIds = {}; // NEW: Multi-select support
  bool _selectAll = false; // NEW: All organizations checkbox
  bool _loading = false;
  String? _error;

  // Background orbit
  late final AnimationController _orbitCtrl;

  @override
  void initState() {
    super.initState();
    _orbitCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 16))
          ..repeat();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    super.dispose();
  }

  // ── Org selection logic ────────────────────────────────────────────────────
  Future<void> _selectOrg(String orgId, String orgName) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedOrgId = orgId;
    });

    final res = await FinanceAuthService.selectOrg(orgId,
        directToken: widget.tempToken);
    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;

      await FinanceSecureStorage.clearTempToken();
      await FinanceSecureStorage.saveSession(
        token: data['token'],
        userId: user['id'].toString(),
        name: user['name'] ?? '',
        email: user['email'] ?? '',
        phone: user['phone'] ?? '',
        role: user['role'] ?? '',
        orgId: user['orgId'] ?? '',
        orgName: user['orgName'] ?? '',
      );

      if (!mounted) return;

      // ✅ Navigate to branch selector — it will go to splash+shell after branch pick
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => FinanceBranchSelectorPage(
            orgId: user['orgId'] ?? orgId,
            orgName: user['orgName'] ?? orgName,
            userName: user['name'] ?? widget.user['name'] ?? 'User',
            isInitialLogin: true,
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      setState(() {
        _error = res['message'] ?? 'Failed to select organisation';
        _selectedOrgId = null;
      });
    }
  }

  // ── NEW: Multi-org selection logic ─────────────────────────────────────────
  void _toggleOrgSelection(String orgId) {
    setState(() {
      if (_selectedOrgIds.contains(orgId)) {
        _selectedOrgIds.remove(orgId);
        _selectAll = false; // Uncheck "All" if user deselects an org
      } else {
        _selectedOrgIds.add(orgId);
        // Check if all orgs are now selected
        if (_selectedOrgIds.length == widget.organizations.length) {
          _selectAll = true;
        }
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        // Select all organizations
        _selectedOrgIds =
            widget.organizations.map((org) => org['orgId'] as String).toSet();
      } else {
        // Deselect all
        _selectedOrgIds.clear();
      }
    });
  }

  Future<void> _applyMultiOrgSelection() async {
    if (_selectedOrgIds.isEmpty) {
      setState(() => _error = 'Please select at least one organisation');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // Save selected org IDs to storage
    if (_selectAll) {
      await FinanceSecureStorage.saveSelectedOrgIds(['ALL']);
    } else {
      await FinanceSecureStorage.saveSelectedOrgIds(_selectedOrgIds.toList());
    }

    // For multi-org, automatically select ALL branches (no branch selector needed)
    await FinanceSecureStorage.saveSelectedBranchIds(
        []); // Empty = ALL branches

    // For multi-org, we still need to select one org for the token
    // Use the first selected org
    final firstOrgId = _selectedOrgIds.first;
    final firstOrg = widget.organizations.firstWhere(
      (org) => org['orgId'] == firstOrgId,
    );

    final res = await FinanceAuthService.selectOrg(firstOrgId,
        directToken: widget.tempToken);
    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;

      await FinanceSecureStorage.clearTempToken();
      await FinanceSecureStorage.saveSession(
        token: data['token'],
        userId: user['id'].toString(),
        name: user['name'] ?? '',
        email: user['email'] ?? '',
        phone: user['phone'] ?? '',
        role: user['role'] ?? '',
        orgId: user['orgId'] ?? '',
        orgName: user['orgName'] ?? '',
      );

      if (!mounted) return;

      // ✅ MULTI-ORG: Skip branch selector, go directly to splash+main app
      if (_selectedOrgIds.length > 1 || _selectAll) {
        // Multi-org mode - skip branch selector
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => FinancePostLoginSplash(
              userName: user['name'] ?? widget.user['name'] ?? 'User',
              orgName: _selectAll
                  ? 'All Organizations'
                  : '${_selectedOrgIds.length} Organizations',
              destination: const BillingMainShell(),
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        // Single org mode - show branch selector (existing behavior)
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => FinanceBranchSelectorPage(
              orgId: user['orgId'] ?? firstOrgId,
              orgName: user['orgName'] ?? firstOrg['orgName'],
              userName: user['name'] ?? widget.user['name'] ?? 'User',
              isInitialLogin: true,
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } else {
      setState(() {
        _error = res['message'] ?? 'Failed to select organisation';
      });
    }
  }

  // ── Role helpers ───────────────────────────────────────────────────────────
  Color _roleColor(String role) {
    switch (role) {
      case 'owner':
        return const Color(0xFFFBBF24);
      case 'admin':
        return _navyAccent;
      case 'accountant':
        return const Color(0xFF00C896);
      default:
        return Colors.white54;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'owner':
        return Icons.star_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'accountant':
        return Icons.calculate_outlined;
      default:
        return Icons.person_outline_rounded;
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated navy background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _orbitCtrl,
              builder: (_, __) => CustomPaint(
                painter: _OrgSelectorBgPainter(_orbitCtrl.value),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: LayoutBuilder(builder: (ctx, constraints) {
              final isWide = constraints.maxWidth > 700;
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isWide ? 40 : 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: isWide ? 580 : double.infinity),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ── Header ────────────────────────────────────────
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_navyAccent, _navyLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                  color: _navyAccent.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2),
                            ],
                          ),
                          child: const Icon(Icons.corporate_fare_rounded,
                              color: Colors.white, size: 34),
                        ),
                        const SizedBox(height: 20),

                        // ── Entity Name (if set) ──────────────────────────
                        if (widget.user['entityName'] != null &&
                            (widget.user['entityName'] as String)
                                .isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _navyAccent.withOpacity(0.15),
                                  _navyLight.withOpacity(0.10),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _navyAccent.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.business_center_rounded,
                                    color: _navyAccent, size: 18),
                                const SizedBox(width: 10),
                                Text(
                                  widget.user['entityName'] as String,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        const Text(
                          'Select Organisation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Welcome message
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.12)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_outline_rounded,
                                  color: Colors.white70, size: 14),
                              const SizedBox(width: 8),
                              Text(
                                'Welcome back, ${widget.user['name'] ?? ''}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Select one or more organisations to view data',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13),
                        ),
                        const SizedBox(height: 32),

                        // ── "All Organizations" checkbox ──────────────────
                        GestureDetector(
                          onTap: _loading ? null : _toggleSelectAll,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: _selectAll
                                  ? _navyAccent.withOpacity(0.18)
                                  : Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _selectAll
                                    ? _navyAccent
                                    : Colors.white.withOpacity(0.12),
                                width: _selectAll ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: _selectAll
                                        ? _navyAccent
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: _selectAll
                                          ? _navyAccent
                                          : Colors.white.withOpacity(0.3),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: _selectAll
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 16)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'All Organizations',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _navyAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${widget.organizations.length} orgs',
                                    style: TextStyle(
                                      color: _navyAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Error box ─────────────────────────────────────
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.error_outline,
                                  color: Color(0xFFFF6B6B), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(_error!,
                                      style: const TextStyle(
                                          color: Color(0xFFFF6B6B),
                                          fontSize: 13))),
                            ]),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Org cards with checkboxes ─────────────────────────────────────
                        ...widget.organizations.map((org) {
                          final orgId = org['orgId'] as String? ?? '';
                          final orgName = org['orgName'] as String? ?? '';
                          final role = org['role'] as String? ?? 'staff';
                          final isSelected = _selectedOrgIds.contains(orgId);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: _loading
                                  ? null
                                  : () => _toggleOrgSelection(orgId),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _navyAccent.withOpacity(0.18)
                                      : Colors.white.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? _navyAccent
                                        : Colors.white.withOpacity(0.12),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color:
                                                _navyAccent.withOpacity(0.25),
                                            blurRadius: 20,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.15),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          )
                                        ],
                                ),
                                child: Row(
                                  children: [
                                    // Checkbox
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? _navyAccent
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? _navyAccent
                                              : Colors.white.withOpacity(0.3),
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check,
                                              color: Colors.white, size: 16)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),

                                    // Org avatar
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: isSelected
                                              ? [_navyAccent, _navyLight]
                                              : [_navyMid, _navyLight],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Center(
                                        child: Text(
                                          orgName.isNotEmpty
                                              ? orgName[0].toUpperCase()
                                              : 'O',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),

                                    // Org info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            orgName,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Row(children: [
                                            Icon(_roleIcon(role),
                                                size: 13,
                                                color: _roleColor(role)),
                                            const SizedBox(width: 5),
                                            Text(
                                              role[0].toUpperCase() +
                                                  role.substring(1),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _roleColor(role),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ]),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 24),

                        // ── Apply button ──────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading || _selectedOrgIds.isEmpty
                                ? null
                                : _applyMultiOrgSelection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _navyAccent,
                              disabledBackgroundColor:
                                  Colors.white.withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _selectedOrgIds.isEmpty
                                            ? 'Select at least one organisation'
                                            : _selectAll
                                                ? 'Continue with All Organizations'
                                                : 'Continue with ${_selectedOrgIds.length} organisation${_selectedOrgIds.length != 1 ? 's' : ''}',
                                        style: TextStyle(
                                          color: _selectedOrgIds.isEmpty
                                              ? Colors.white38
                                              : Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (_selectedOrgIds.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.arrow_forward_rounded,
                                            color: Colors.white, size: 18),
                                      ],
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── Org count info ────────────────────────────────
                        Text(
                          '${widget.organizations.length} organisation${widget.organizations.length != 1 ? 's' : ''} available',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.35),
                              fontSize: 12),
                        ),

                        const SizedBox(height: 20),

                        // ── Sign out ──────────────────────────────────────
                        TextButton.icon(
                          onPressed: () async {
                            await FinanceSecureStorage.clearSession();
                            if (!mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FinanceLoginPage()),
                            );
                          },
                          icon: const Icon(Icons.logout_rounded,
                              color: Colors.white38, size: 15),
                          label: const Text('Sign out',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Background painter ─────────────────────────────────────────────────────────
class _OrgSelectorBgPainter extends CustomPainter {
  final double progress;
  _OrgSelectorBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0D1B3E), Color(0xFF0F2350), Color(0xFF1A3A6B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()
      ..color = Colors.white.withOpacity(0.022)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final cx = size.width / 2;
    final cy = size.height * 0.3;
    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final r = size.width * 0.22;
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
        ..color = const Color(0xFF3D8EFF).withOpacity(0.09);
      canvas.drawCircle(
          Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)), 70, glow);
    }

    final line = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF3D8EFF).withOpacity(0.5),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), line);
  }

  @override
  bool shouldRepaint(_OrgSelectorBgPainter old) => old.progress != progress;
}

// ── Temporary placeholder — replace with your real FinanceDashboard widget ────
class _FinanceDashboardPlaceholder extends StatelessWidget {
  const _FinanceDashboardPlaceholder();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Finance Dashboard')),
    );
  }
}
