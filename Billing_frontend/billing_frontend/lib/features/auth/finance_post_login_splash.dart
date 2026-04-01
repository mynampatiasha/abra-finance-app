// ============================================================================
// ABRA FINANCE SUITE — POST-LOGIN SPLASH SCREEN
// ============================================================================
// File: lib/features/finance_auth/presentation/pages/finance_post_login_splash.dart
//
// Finance-themed splash — chart/coin icon with expanding ripple rings
// Auto-navigates to destination after animation completes
//
// Usage:
//   Navigator.pushReplacement(
//     context,
//     MaterialPageRoute(
//       builder: (_) => FinancePostLoginSplash(
//         userName: 'Ravi',
//         orgName:  'ABRA Exports Pvt Ltd',
//         destination: FinanceDashboard(),
//       ),
//     ),
//   );
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Finance navy color system ─────────────────────────────────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _goldAccent = Color(0xFFFBBF24);
const Color _greenAccent = Color(0xFF00C896);

class FinancePostLoginSplash extends StatefulWidget {
  final String userName;
  final String orgName;
  final Widget destination;

  const FinancePostLoginSplash({
    Key? key,
    required this.userName,
    required this.orgName,
    required this.destination,
  }) : super(key: key);

  @override
  State<FinancePostLoginSplash> createState() =>
      _FinancePostLoginSplashState();
}

class _FinancePostLoginSplashState extends State<FinancePostLoginSplash>
    with TickerProviderStateMixin {

  // Ripple rings — 4 staggered expanding rings
  late final AnimationController _rippleCtrl;
  late final List<Animation<double>> _rippleScales;
  late final List<Animation<double>> _rippleOpacities;

  // Central icon panel pop-in
  late final AnimationController _iconCtrl;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconFade;

  // Orbiting chart bars (decorative)
  late final AnimationController _orbitCtrl;

  // Text reveal
  late final AnimationController _textCtrl;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  // Gold checkmark
  late final AnimationController _checkCtrl;
  late final Animation<double> _checkScale;

  // Ticker tally (count-up animation)
  late final AnimationController _tickerCtrl;
  late final Animation<double> _tickerAnim;

  // Exit fade
  late final AnimationController _exitCtrl;
  late final Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    // Orbiting bg
    _orbitCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 10))
      ..repeat();

    // Ripple — 4 rings staggered
    _rippleCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400));

    _rippleScales = List.generate(
        4,
        (i) => Tween<double>(begin: 0.2, end: 4.0).animate(
              CurvedAnimation(
                parent: _rippleCtrl,
                curve: Interval(i * 0.14, 0.82 + i * 0.05,
                    curve: Curves.easeOut),
              ),
            ));

    _rippleOpacities = List.generate(
        4,
        (i) => Tween<double>(begin: 0.4, end: 0.0).animate(
              CurvedAnimation(
                parent: _rippleCtrl,
                curve: Interval(i * 0.14, 0.88 + i * 0.04,
                    curve: Curves.easeOut),
              ),
            ));

    // Central icon
    _iconCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700));
    _iconScale = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut));
    _iconFade =
        CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut);

    // Text
    _textCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600));
    _textFade =
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut);
    _textSlide =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _textCtrl, curve: Curves.easeOutCubic));

    // Check
    _checkCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500));
    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _checkCtrl, curve: Curves.elasticOut));

    // Ticker count-up
    _tickerCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200));
    _tickerAnim =
        CurvedAnimation(parent: _tickerCtrl, curve: Curves.easeOut);

    // Exit
    _exitCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700));
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic));

    _runSequence();
  }

  Future<void> _runSequence() async {
    // 1 — Ripple starts immediately
    _rippleCtrl.forward();

    // 2 — Icon pops in
    await Future.delayed(const Duration(milliseconds: 280));
    _iconCtrl.forward();

    // 3 — Text slides up
    await Future.delayed(const Duration(milliseconds: 480));
    _textCtrl.forward();
    _tickerCtrl.forward();

    // 4 — Checkmark badge
    await Future.delayed(const Duration(milliseconds: 320));
    _checkCtrl.forward();

    // 5 — Hold
    await Future.delayed(const Duration(milliseconds: 1500));

    // 6 — Fade out and navigate
    _exitCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 700));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => widget.destination,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    _rippleCtrl.dispose();
    _iconCtrl.dispose();
    _textCtrl.dispose();
    _checkCtrl.dispose();
    _tickerCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _exitCtrl,
        builder: (_, __) => FadeTransition(
          opacity: _exitFade,
          child: Stack(
            children: [
              // Navy animated background
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _orbitCtrl,
                  builder: (_, __) => CustomPaint(
                    painter: _SplashBgPainter(_orbitCtrl.value),
                  ),
                ),
              ),

              // Ripple rings centred
              Center(
                child: AnimatedBuilder(
                  animation: _rippleCtrl,
                  builder: (_, __) => SizedBox(
                    width: 320,
                    height: 320,
                    child: Stack(
                      alignment: Alignment.center,
                      children: List.generate(
                        4,
                        (i) => Transform.scale(
                          scale: _rippleScales[i].value,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _navyAccent.withOpacity(
                                    _rippleOpacities[i].value),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Main content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Central finance icon panel ────────────────────────
                    ScaleTransition(
                      scale: _iconScale,
                      child: FadeTransition(
                        opacity: _iconFade,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer glow
                            Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _navyAccent.withOpacity(0.35),
                                    blurRadius: 70,
                                    spreadRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                            // Main circle — dark navy with gradient border
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const RadialGradient(
                                  colors: [
                                    Color(0xFF1A3A6B),
                                    Color(0xFF0D1B3E),
                                  ],
                                ),
                                border: Border.all(
                                    color: _navyAccent.withOpacity(0.5),
                                    width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withOpacity(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  // Chart bars icon (finance-themed)
                                  _FinanceIconWidget(),
                                ],
                              ),
                            ),

                            // Gold checkmark badge
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: ScaleTransition(
                                scale: _checkScale,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: _greenAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: _navyDark, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _greenAccent
                                            .withOpacity(0.6),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Welcome text ──────────────────────────────────────
                    FadeTransition(
                      opacity: _textFade,
                      child: SlideTransition(
                        position: _textSlide,
                        child: Column(
                          children: [
                            Text(
                              'Welcome back,',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withOpacity(0.6),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              widget.userName,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Org name pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _navyAccent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                    color: _navyAccent.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                      Icons.corporate_fare_rounded,
                                      color: _navyAccent,
                                      size: 13),
                                  const SizedBox(width: 7),
                                  Text(
                                    widget.orgName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 28),

                            // ── Count-up stat ticker ──────────────────────
                            AnimatedBuilder(
                              animation: _tickerAnim,
                              builder: (_, __) {
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _statTile(
                                      icon: Icons.receipt_long_rounded,
                                      label: 'Invoices',
                                      value:
                                          '${(_tickerAnim.value * 248).toInt()}',
                                      color: _greenAccent,
                                    ),
                                    const SizedBox(width: 12),
                                    _statTile(
                                      icon: Icons.store_rounded,
                                      label: 'Bills',
                                      value:
                                          '${(_tickerAnim.value * 134).toInt()}',
                                      color: const Color(0xFFFF8C42),
                                    ),
                                    const SizedBox(width: 12),
                                    _statTile(
                                      icon: Icons.analytics_rounded,
                                      label: 'Reports',
                                      value:
                                          '${(_tickerAnim.value * 36).toInt()}',
                                      color: _navyAccent,
                                    ),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 28),

                            // Brand tagline pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius:
                                    BorderRadius.circular(50),
                                border: Border.all(
                                    color:
                                        Colors.white.withOpacity(0.1)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.account_balance_rounded,
                                      color: _navyAccent, size: 13),
                                  SizedBox(width: 8),
                                  Text(
                                    'ABRA Finance Suite  ·  Enterprise Finance Platform',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      letterSpacing: 0.4,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 28),

                            // Loading dots
                            _LoadingDots(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 10)),
        ],
      ),
    );
  }
}

// ── Finance icon (animated bar chart) ─────────────────────────────────────────
class _FinanceIconWidget extends StatefulWidget {
  @override
  State<_FinanceIconWidget> createState() => _FinanceIconWidgetState();
}

class _FinanceIconWidgetState extends State<_FinanceIconWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _bars;

  final List<double> _heights = [0.4, 0.75, 0.55, 0.9, 0.65];
  final List<Color> _colors = [
    Color(0xFF3D8EFF),
    Color(0xFF00C896),
    Color(0xFF3D8EFF),
    Color(0xFFFBBF24),
    Color(0xFF00C896),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _bars = List.generate(
        5,
        (i) => Tween<double>(begin: 0, end: _heights[i]).animate(
              CurvedAnimation(
                parent: _ctrl,
                curve: Interval(i * 0.1, 0.6 + i * 0.08,
                    curve: Curves.elasticOut),
              ),
            ));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => SizedBox(
        width: 56,
        height: 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(5, (i) {
            return Container(
              width: 7,
              height: 44 * _bars[i].value,
              decoration: BoxDecoration(
                color: _colors[i],
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ── Loading dots ──────────────────────────────────────────────────────────────
class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ctrls;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(
        3,
        (_) => AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 500)));
    _anims = _ctrls
        .map((c) => Tween<double>(begin: 0.25, end: 1.0).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 170), () {
        if (mounted) _ctrls[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
          3,
          (i) => AnimatedBuilder(
                animation: _anims[i],
                builder: (_, __) => Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _navyAccent.withOpacity(_anims[i].value),
                  ),
                ),
              )),
    );
  }
}

// ── Background painter ─────────────────────────────────────────────────────────
class _SplashBgPainter extends CustomPainter {
  final double progress;
  _SplashBgPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF0D1B3E),
          Color(0xFF0F2350),
          Color(0xFF1A3A6B),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    // Grid
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.022)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 55) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 55) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Orbiting glow blobs from centre
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (int i = 0; i < 3; i++) {
      final angle =
          (progress * math.pi * 2) + (i * math.pi * 2 / 3);
      final r = size.width * 0.32;
      final glow = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70)
        ..color = [
          const Color(0xFF3D8EFF).withOpacity(0.11),
          const Color(0xFF00C896).withOpacity(0.07),
          const Color(0xFF2463AE).withOpacity(0.09),
        ][i];
      canvas.drawCircle(
          Offset(cx + r * math.cos(angle),
                 cy + r * math.sin(angle)),
          90, glow);
    }

    // Top accent line
    final line = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF3D8EFF).withOpacity(0.55),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), line);
  }

  @override
  bool shouldRepaint(_SplashBgPainter old) =>
      old.progress != progress;
}