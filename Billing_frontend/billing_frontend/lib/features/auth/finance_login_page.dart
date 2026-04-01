// ============================================================================
// ABRA FINANCE SUITE — PREMIUM LOGIN PAGE
// ============================================================================
// File: lib/features/finance_auth/presentation/pages/finance_login_page.dart
// ✅ No left panel — centred layout on all screen sizes
// ✅ Logo + title centred at top
// ✅ Horizontal 4-step row above card
// ✅ Navy glassmorphism card — pure white text everywhere
// ✅ Splash screen wired after single-org login
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/finance_secure_storage.dart';
import '../../data/services/finance_auth_service.dart';
import 'finance_register_page.dart';
import 'finance_org_selector_page.dart';
import 'finance_post_login_splash.dart';
import '../billing/billing_main_shell.dart';

// ── Finance navy color system ─────────────────────────────────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _goldAccent = Color(0xFFFBBF24);

class FinanceLoginPage extends StatefulWidget {
  const FinanceLoginPage({super.key});

  @override
  State<FinanceLoginPage> createState() => _FinanceLoginPageState();
}

class _FinanceLoginPageState extends State<FinanceLoginPage>
    with TickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl    = TextEditingController();
  bool _loading    = false;
  bool _obscure    = true;
  String? _error;

  late final AnimationController _orbitCtrl;
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _entranceFade;
  late final Animation<Offset>   _entranceSlide;
  late final AnimationController _btnCtrl;
  late final Animation<double>   _btnScale;

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 18))
      ..repeat();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _entranceFade  = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _btnCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _btnScale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeInOut));
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _orbitCtrl.dispose();
    _entranceCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  // ── Login logic ────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final res = await FinanceAuthService.login(
      email:    _emailCtrl.text.trim(),
      password: _pwCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>;
      if (res['requireOrgSelect'] == true) {
        await FinanceSecureStorage.saveTempToken(data['tempToken'] ?? '');
        final orgs = List<Map<String, dynamic>>.from(data['organizations'] ?? []);
        final user = data['user'] as Map<String, dynamic>;
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FinanceOrgSelectorPage(organizations: orgs, user: user),
          ),
        );
      } else {
        final user = data['user'] as Map<String, dynamic>;
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
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => FinancePostLoginSplash(
              userName:    user['name'] ?? 'User',
              orgName:     user['orgName'] ?? 'Your Organisation',
              destination: const BillingMainShell(),
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } else {
      setState(() => _error = res['message'] ?? 'Login failed');
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _orbitCtrl,
              builder: (_, __) => CustomPaint(
                painter: _FinanceLoginBgPainter(_orbitCtrl.value),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _entranceFade,
              child: SlideTransition(
                position: _entranceSlide,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoBadge(),
                          const SizedBox(height: 24),
                          const Text(
                            'Welcome Back.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1.1,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to your finance command centre.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: Colors.white, height: 1.5),
                          ),
                          const SizedBox(height: 32),
                          _buildHorizontalSteps(),
                          const SizedBox(height: 32),
                          _buildCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo badge ─────────────────────────────────────────────────────────────
  Widget _buildLogoBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_navyAccent, _navyLight],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: _navyAccent.withOpacity(0.4), blurRadius: 18, spreadRadius: 2)],
          ),
          child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ABRA Finance Suite',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            Text('Enterprise Finance Platform',
                style: TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 0.8)),
          ],
        ),
      ],
    );
  }

  // ── Horizontal 4-step row ──────────────────────────────────────────────────
  Widget _buildHorizontalSteps() {
    final steps = [
      (Icons.lock_outline_rounded,   '01', 'Secure Login'),
      (Icons.corporate_fare_rounded, '02', 'Org Selected'),
      (Icons.verified_user_rounded,  '03', 'Access Granted'),
      (Icons.dashboard_rounded,      '04', 'Dashboard Ready'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.15),
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.15),
                  ],
                ),
              ),
            ),
          );
        }
        final s = steps[i ~/ 2];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_navyAccent, _navyLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: _navyAccent.withOpacity(0.4), blurRadius: 12, spreadRadius: 1),
                ],
              ),
              child: Icon(s.$1, color: Colors.white, size: 17),
            ),
            const SizedBox(height: 6),
            Text(s.$2,
                style: const TextStyle(
                    color: _navyAccent, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 3),
            Text(s.$3,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        );
      }),
    );
  }

  // ── Navy glassmorphism card ────────────────────────────────────────────────
  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 40, offset: const Offset(0, 16)),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sign In',
                style: TextStyle(color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            const Text('Enter your credentials to continue',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            const SizedBox(height: 24),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF6B6B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            _buildField(
              ctrl: _emailCtrl, label: 'Email Address',
              hint: 'you@company.com', icon: Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),

            _buildField(
              ctrl: _pwCtrl, label: 'Password',
              hint: '••••••••', icon: Icons.lock_outline_rounded,
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.white, size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
            ),
            const SizedBox(height: 28),

            ScaleTransition(
              scale: _btnScale,
              child: GestureDetector(
                onTapDown: (_) => _btnCtrl.forward(),
                onTapUp: (_) => _btnCtrl.reverse(),
                onTapCancel: () => _btnCtrl.reverse(),
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyAccent,
                    disabledBackgroundColor: _navyAccent.withOpacity(0.5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Sign In',
                                style: TextStyle(fontSize: 16,
                                    fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(children: [
              Expanded(child: Divider(color: Colors.white.withOpacity(0.12))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: const Text('or', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
              Expanded(child: Divider(color: Colors.white.withOpacity(0.12))),
            ]),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account?",
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.pushReplacement(
                          context, MaterialPageRoute(builder: (_) => const FinanceRegisterPage())),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(left: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Register',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w700, color: _goldAccent)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield_outlined, color: _navyAccent, size: 13),
                  const SizedBox(width: 8),
                  const Text('Secured with JWT authentication',
                      style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 0.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Field — pure white text ────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.white, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _navyAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFB3B3)),
      ),
    );
  }
}

// ── Background painter ─────────────────────────────────────────────────────────
class _FinanceLoginBgPainter extends CustomPainter {
  final double progress;
  _FinanceLoginBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0D1B3E), Color(0xFF0F2350), Color(0xFF1A3A6B)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()..color = Colors.white.withOpacity(0.025)..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final cx = size.width * 0.5;
    final cy = size.height * 0.4;
    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final r = size.width * 0.18;
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55)
        ..color = [
          const Color(0xFF3D8EFF).withOpacity(0.14),
          const Color(0xFF2463AE).withOpacity(0.10),
          const Color(0xFF1A3A6B).withOpacity(0.18),
        ][i];
      canvas.drawCircle(
          Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)), 65, glow);
    }

    final line = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, const Color(0xFF3D8EFF).withOpacity(0.6), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), line);
  }

  @override
  bool shouldRepaint(_FinanceLoginBgPainter old) => old.progress != progress;
}