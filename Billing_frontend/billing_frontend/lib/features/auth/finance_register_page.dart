// ============================================================================
// ABRA FINANCE SUITE — PREMIUM REGISTER PAGE
// ============================================================================
// File: lib/features/finance_auth/presentation/pages/finance_register_page.dart
// ✅ No left panel — centred layout on all screen sizes
// ✅ Logo + title centred at top
// ✅ Horizontal 4-step row above card
// ✅ Navy glassmorphism card — pure white text everywhere including fields
// ✅ All existing register logic preserved
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/finance_secure_storage.dart';
import '../../data/services/finance_auth_service.dart';
import 'finance_login_page.dart';

// ── Finance navy color system ─────────────────────────────────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _goldAccent = Color(0xFFFBBF24);

class FinanceRegisterPage extends StatefulWidget {
  const FinanceRegisterPage({super.key});

  @override
  State<FinanceRegisterPage> createState() => _FinanceRegisterPageState();
}

class _FinanceRegisterPageState extends State<FinanceRegisterPage>
    with TickerProviderStateMixin {
  final _formKey       = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _orgNameCtrl   = TextEditingController();
  final _pwCtrl        = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  bool _loading        = false;
  bool _obscurePw      = true;
  bool _obscureConfirm = true;
  String? _error;

  late final AnimationController _orbitCtrl;
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _entranceFade;
  late final Animation<Offset>   _entranceSlide;

  @override
  void initState() {
    super.initState();
    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850));
    _entranceFade  = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic));
    _entranceCtrl.forward();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _emailCtrl, _phoneCtrl,
      _orgNameCtrl, _pwCtrl, _confirmPwCtrl,
    ]) { c.dispose(); }
    _orbitCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ── Register logic ─────────────────────────────────────────────────────────
  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final res = await FinanceAuthService.register(
      name:     _nameCtrl.text.trim(),
      email:    _emailCtrl.text.trim(),
      password: _pwCtrl.text,
      phone:    _phoneCtrl.text.trim(),
      orgName:  _orgNameCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      await FinanceSecureStorage.saveSession(
        token:   data['token'],
        userId:  user['id'].toString(),
        name:    user['name'] ?? '',
        email:   user['email'] ?? '',
        phone:   user['phone'] ?? '',
        role:    user['role'] ?? 'owner',
        orgId:   user['orgId'] ?? '',
        orgName: user['orgName'] ?? '',
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/finance/dashboard');
    } else {
      setState(() => _error = res['message'] ?? 'Registration failed');
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
                painter: _FinanceRegBgPainter(_orbitCtrl.value),
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
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoBadge(),
                          const SizedBox(height: 24),
                          const Text(
                            'Create Account',
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
                            'Set up your organisation and get started.',
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
      (Icons.person_add_alt_1_rounded, '01', 'Register'),
      (Icons.corporate_fare_rounded,   '02', 'Org Created'),
      (Icons.star_rounded,             '03', "You're Owner"),
      (Icons.group_add_rounded,        '04', 'Add Team'),
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
      padding: const EdgeInsets.all(28),
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
            const Text('Create your account',
                style: TextStyle(color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 4),
            const Text('You will become the Owner of your organisation',
                style: TextStyle(color: Colors.white, fontSize: 12)),
            const SizedBox(height: 22),

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

            LayoutBuilder(builder: (ctx, c) {
              final twoCol = c.maxWidth > 380;
              if (twoCol) {
                return Column(children: [
                  Row(children: [
                    Expanded(child: _field(ctrl: _nameCtrl, label: 'Full Name',
                        icon: Icons.person_outline_rounded, required: true, validator: _req('Name'))),
                    const SizedBox(width: 12),
                    Expanded(child: _field(ctrl: _phoneCtrl, label: 'Phone',
                        icon: Icons.phone_outlined, keyboard: TextInputType.phone,
                        required: true, validator: _req('Phone'))),
                  ]),
                  const SizedBox(height: 14),
                  _field(ctrl: _emailCtrl, label: 'Email Address',
                      icon: Icons.email_outlined, keyboard: TextInputType.emailAddress,
                      required: true, validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Email is required';
                        if (!v.contains('@')) return 'Enter a valid email';
                        return null;
                      }),
                  const SizedBox(height: 14),
                  _field(ctrl: _orgNameCtrl, label: 'Organisation / Company Name',
                      icon: Icons.business_outlined, required: true,
                      validator: _req('Organisation name')),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _pwField(ctrl: _pwCtrl, label: 'Password',
                        obscure: _obscurePw,
                        onToggle: () => setState(() => _obscurePw = !_obscurePw),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Password required';
                          if (v.length < 6) return 'Min 6 characters';
                          return null;
                        })),
                    const SizedBox(width: 12),
                    Expanded(child: _pwField(ctrl: _confirmPwCtrl, label: 'Confirm',
                        obscure: _obscureConfirm,
                        onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        validator: (v) {
                          if (v != _pwCtrl.text) return 'Passwords do not match';
                          return null;
                        })),
                  ]),
                ]);
              }
              return Column(children: [
                _field(ctrl: _nameCtrl, label: 'Full Name',
                    icon: Icons.person_outline_rounded, required: true, validator: _req('Name')),
                const SizedBox(height: 14),
                _field(ctrl: _phoneCtrl, label: 'Phone',
                    icon: Icons.phone_outlined, keyboard: TextInputType.phone,
                    required: true, validator: _req('Phone')),
                const SizedBox(height: 14),
                _field(ctrl: _emailCtrl, label: 'Email Address',
                    icon: Icons.email_outlined, keyboard: TextInputType.emailAddress,
                    required: true, validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    }),
                const SizedBox(height: 14),
                _field(ctrl: _orgNameCtrl, label: 'Organisation / Company Name',
                    icon: Icons.business_outlined, required: true,
                    validator: _req('Organisation name')),
                const SizedBox(height: 14),
                _pwField(ctrl: _pwCtrl, label: 'Password',
                    obscure: _obscurePw,
                    onToggle: () => setState(() => _obscurePw = !_obscurePw),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password required';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    }),
                const SizedBox(height: 14),
                _pwField(ctrl: _confirmPwCtrl, label: 'Confirm Password',
                    obscure: _obscureConfirm,
                    onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) {
                      if (v != _pwCtrl.text) return 'Passwords do not match';
                      return null;
                    }),
              ]);
            }),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _loading ? null : _register,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text(_loading ? 'Creating Account...' : 'Create Account',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                disabledBackgroundColor: _navyAccent.withOpacity(0.5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account?',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.pushReplacement(
                          context, MaterialPageRoute(builder: (_) => const FinanceLoginPage())),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.only(left: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Sign In',
                      style: TextStyle(fontSize: 13,
                          fontWeight: FontWeight.w700, color: _goldAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Field — pure white text ────────────────────────────────────────────────
  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    bool required = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      validator: validator,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.white, size: 17),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _navyAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 11),
      ),
    );
  }

  Widget _pwField({
    required TextEditingController ctrl,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 17),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.white, size: 17,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.07),
        contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _navyAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 11),
      ),
    );
  }

  String? Function(String?) _req(String field) =>
      (v) => (v == null || v.trim().isEmpty) ? '$field is required' : null;
}

// ── Background painter ─────────────────────────────────────────────────────────
class _FinanceRegBgPainter extends CustomPainter {
  final double progress;
  _FinanceRegBgPainter(this.progress);

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

    for (int i = 0; i < 3; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final r = size.width * 0.2;
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60)
        ..color = const Color(0xFF3D8EFF).withOpacity(0.09);
      canvas.drawCircle(
        Offset(size.width * 0.5 + r * math.cos(angle),
            size.height * 0.3 + r * math.sin(angle)),
        75, glow,
      );
    }

    final line = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, const Color(0xFF3D8EFF).withOpacity(0.55), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), line);
  }

  @override
  bool shouldRepaint(_FinanceRegBgPainter old) => old.progress != progress;
}