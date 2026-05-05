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
import '../billing/billing_main_shell.dart';

// ── Finance navy color system ─────────────────────────────────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class FinanceOrgSelectorPage extends StatefulWidget {
  final List<Map<String, dynamic>> organizations;
  final Map<String, dynamic> user;
  final String? tempToken; // passed directly from login to avoid storage read issues on web

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
  String? _selectedOrgId;
  bool _loading = false;
  String? _error;

  // Background orbit
  late final AnimationController _orbitCtrl;

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 16))
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

    final res = await FinanceAuthService.selectOrg(orgId);
    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;

      await FinanceSecureStorage.clearTempToken();
      await FinanceSecureStorage.saveSession(
        token:   data['token'],
        userId:  user['id'].toString(),
        name:    user['name'] ?? '',
        email:   user['email'] ?? '',
        phone:   user['phone'] ?? '',
        role:    user['role'] ?? '',
        orgId:   user['orgId'] ?? '',
        orgName: user['orgName'] ?? '',
      );

      if (!mounted) return;

      // ✅ Splash injected here after org selection
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => FinancePostLoginSplash(
            userName:    user['name'] ?? widget.user['name'] ?? 'User',
            orgName:     user['orgName'] ?? orgName,
            destination: const BillingMainShell(),
            // ↑ Replace _FinanceDashboardPlaceholder() with your actual
            //   finance dashboard widget, e.g. FinanceDashboard()
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

  // ── Role helpers ───────────────────────────────────────────────────────────
  Color _roleColor(String role) {
    switch (role) {
      case 'owner':      return const Color(0xFFFBBF24);
      case 'admin':      return _navyAccent;
      case 'accountant': return const Color(0xFF00C896);
      default:           return Colors.white54;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'owner':      return Icons.star_rounded;
      case 'admin':      return Icons.admin_panel_settings_rounded;
      case 'accountant': return Icons.calculate_outlined;
      default:           return Icons.person_outline_rounded;
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
                          'Choose an organisation to continue',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 13),
                        ),
                        const SizedBox(height: 32),

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

                        // ── Org cards ─────────────────────────────────────
                        ...widget.organizations.map((org) {
                          final orgId   = org['orgId']   as String? ?? '';
                          final orgName = org['orgName'] as String? ?? '';
                          final role    = org['role']    as String? ?? 'staff';
                          final isSelected = _selectedOrgId == orgId;
                          final isThisLoading = _loading && isSelected;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: _loading
                                  ? null
                                  : () => _selectOrg(orgId, orgName),
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
                                            color: _navyAccent
                                                .withOpacity(0.25),
                                            blurRadius: 20,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black
                                                .withOpacity(0.15),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          )
                                        ],
                                ),
                                child: Row(
                                  children: [
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
                                        borderRadius:
                                            BorderRadius.circular(13),
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

                                    // Arrow / loader / check
                                    isThisLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: _navyAccent))
                                        : AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isSelected
                                                  ? _navyAccent
                                                      .withOpacity(0.2)
                                                  : Colors.white
                                                      .withOpacity(0.06),
                                              border: Border.all(
                                                color: isSelected
                                                    ? _navyAccent
                                                    : Colors.white
                                                        .withOpacity(0.15),
                                              ),
                                            ),
                                            child: Icon(
                                              isSelected
                                                  ? Icons.check_rounded
                                                  : Icons
                                                      .arrow_forward_rounded,
                                              color: isSelected
                                                  ? _navyAccent
                                                  : Colors.white54,
                                              size: 16,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

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
          Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)),
          70, glow);
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