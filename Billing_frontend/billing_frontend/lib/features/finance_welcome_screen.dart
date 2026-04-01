// ============================================================================
// FINANCE WELCOME SCREEN
// ============================================================================
// Features:
//   ✅ Hero welcome with ABRA Finance Suite branding
//   ✅ "Explore the Suite" CTA button
//   ✅ 5-step animated progress stepper tour
//   ✅ Skip / Get Started → finance_login_page.dart
//   ✅ Fully responsive — laptop (two-column) & mobile (single-column)
// ============================================================================

import 'package:flutter/material.dart';
import 'auth/finance_login_page.dart';

// ── Navy color system (matches new_vendor_credit.dart) ──────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

// ── Tour step model ──────────────────────────────────────────────────────────
class _TourStep {
  final IconData icon;
  final IconData secondaryIcon;
  final String stepLabel;
  final String title;
  final String subtitle;
  final String description;
  final List<String> highlights;
  final Color accentColor;

  const _TourStep({
    required this.icon,
    required this.secondaryIcon,
    required this.stepLabel,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.highlights,
    required this.accentColor,
  });
}

const List<_TourStep> _steps = [
  _TourStep(
    icon: Icons.corporate_fare_rounded,
    secondaryIcon: Icons.swap_horiz_rounded,
    stepLabel: 'STEP 01',
    title: 'Multi-Entity Command',
    subtitle: 'One login. Every organisation.',
    description:
        'Operate across multiple legal entities from a single, unified account. '
        'Seamlessly switch between organisations — each with its own isolated '
        'ledger, GSTIN, fiscal calendar, and access controls. No logout required.',
    highlights: [
      'Unlimited organisations per account',
      'Isolated ledgers per entity',
      'Instant context switching',
    ],
    accentColor: Color(0xFF3D8EFF),
  ),
  _TourStep(
    icon: Icons.receipt_long_rounded,
    secondaryIcon: Icons.payments_rounded,
    stepLabel: 'STEP 02',
    title: 'Revenue & Receivables',
    subtitle: 'Invoice. Collect. Reconcile.',
    description:
        'Create GST-compliant sales invoices in seconds. Track payment statuses, '
        'apply credit notes, set recurring billing, and monitor ageing receivables — '
        'all from a single consolidated dashboard.',
    highlights: [
      'GST / TDS / TCS auto-calculation',
      'Ageing receivables dashboard',
      'Credit note & advance management',
    ],
    accentColor: Color(0xFF00C896),
  ),
  _TourStep(
    icon: Icons.store_rounded,
    secondaryIcon: Icons.account_balance_wallet_rounded,
    stepLabel: 'STEP 03',
    title: 'Procurement & Payables',
    subtitle: 'Control every rupee spent.',
    description:
        'Capture vendor bills, raise purchase orders, record vendor credits, '
        'and manage payables with full audit trails. '
        'Know exactly what you owe and when — before it becomes a liability.',
    highlights: [
      'Purchase order lifecycle',
      'Vendor credit management',
      'Payables ageing & cash flow view',
    ],
    accentColor: Color(0xFFFF8C42),
  ),
  _TourStep(
    icon: Icons.account_balance_rounded,
    secondaryIcon: Icons.analytics_rounded,
    stepLabel: 'STEP 04',
    title: 'Accounting & Compliance',
    subtitle: 'Books that close on time.',
    description:
        'Maintain a structured chart of accounts, post manual journals, '
        'reconcile bank statements, and generate audit-ready financial reports — '
        'Profit & Loss, Balance Sheet, Trial Balance and more.',
    highlights: [
      'Double-entry general ledger',
      'Bank reconciliation engine',
      'P&L, Balance Sheet, Trial Balance',
    ],
    accentColor: Color(0xFFA78BFA),
  ),
  _TourStep(
    icon: Icons.verified_user_rounded,
    secondaryIcon: Icons.tune_rounded,
    stepLabel: 'STEP 05',
    title: 'Access & Governance',
    subtitle: 'The right access. For the right people.',
    description:
        'Assign granular roles — Owner, Admin, Accountant, Staff — per organisation. '
        'Define module-level permissions: who can view, who can edit, '
        'who can delete. Your data never leaks across entity boundaries.',
    highlights: [
      'Role-based access per organisation',
      'Module-level permission matrix',
      'Complete data isolation between entities',
    ],
    accentColor: Color(0xFFFF5C8A),
  ),
];

// ============================================================================
// SCREEN
// ============================================================================

class FinanceWelcomeScreen extends StatefulWidget {
  const FinanceWelcomeScreen({Key? key}) : super(key: key);

  @override
  State<FinanceWelcomeScreen> createState() => _FinanceWelcomeScreenState();
}

class _FinanceWelcomeScreenState extends State<FinanceWelcomeScreen>
    with TickerProviderStateMixin {
  bool _tourActive = false;
  int _currentStep = 0;

  // Hero animations
  late final AnimationController _heroCtrl;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  // Tour animations
  late final AnimationController _stepCtrl;
  late final Animation<double> _stepFade;
  late final Animation<Offset> _stepSlide;
  late final Animation<double> _iconScale;
  late final AnimationController _iconPulse;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _heroCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));

    _stepCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _stepFade = CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOut);
    _stepSlide = Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _stepCtrl, curve: Curves.easeOutCubic));
    _iconScale = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _stepCtrl, curve: Curves.elasticOut));

    _iconPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _iconPulse, curve: Curves.easeInOut));

    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _stepCtrl.dispose();
    _iconPulse.dispose();
    super.dispose();
  }

  void _startTour() {
    setState(() {
      _tourActive = true;
      _currentStep = 0;
    });
    _stepCtrl.forward(from: 0);
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _stepCtrl.reverse().then((_) {
        setState(() => _currentStep++);
        _stepCtrl.forward(from: 0);
      });
    } else {
      _navigateToLogin();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _stepCtrl.reverse().then((_) {
        setState(() => _currentStep--);
        _stepCtrl.forward(from: 0);
      });
    }
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const FinanceLoginPage(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navyDark,
      body: LayoutBuilder(builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        return _tourActive ? _buildTourView(isWide) : _buildHeroView(isWide);
      }),
    );
  }

  // ── HERO VIEW ──────────────────────────────────────────────────────────────

  Widget _buildHeroView(bool isWide) {
    return Stack(
      children: [
        // Background mesh
        Positioned.fill(child: _BackgroundMesh()),

        // Content
        Center(
          child: FadeTransition(
            opacity: _heroFade,
            child: SlideTransition(
              position: _heroSlide,
              child: isWide ? _buildHeroWide() : _buildHeroMobile(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroWide() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1100),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
      child: Row(
        children: [
          // Left — branding panel
          Expanded(
            flex: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LogoBadge(),
                const SizedBox(height: 36),
                const Text(
                  'Financial\nIntelligence,\nAt Scale.',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'A unified finance command centre built for growing enterprises. '
                  'Multi-entity accounting, compliance-ready reporting, and '
                  'granular access control — all in one platform.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    height: 1.65,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    _PrimaryButton(
                      label: 'Explore the Suite',
                      icon: Icons.explore_outlined,
                      onTap: _startTour,
                    ),
                    const SizedBox(width: 16),
                    _GhostButton(
                      label: 'Sign In',
                      onTap: _navigateToLogin,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 60),
          // Right — feature preview cards
          Expanded(
            flex: 4,
            child: _FeatureCardStack(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMobile() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
      child: Column(
        children: [
          _LogoBadge(),
          const SizedBox(height: 40),
          const Text(
            'Financial\nIntelligence,\nAt Scale.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'A unified finance command centre for growing enterprises. '
            'Multi-entity accounting, compliance reporting, '
            'and granular access control.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: 'Explore the Suite',
              icon: Icons.explore_outlined,
              onTap: _startTour,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _GhostButton(label: 'Sign In', onTap: _navigateToLogin),
          ),
          const SizedBox(height: 48),
          _MobileFeaturePills(),
        ],
      ),
    );
  }

  // ── TOUR VIEW ──────────────────────────────────────────────────────────────

  Widget _buildTourView(bool isWide) {
    final step = _steps[_currentStep];

    return Stack(
      children: [
        Positioned.fill(child: _BackgroundMesh()),

        // Skip button
        Positioned(
          top: 16,
          right: 20,
          child: SafeArea(
            child: TextButton.icon(
              onPressed: _navigateToLogin,
              icon: const Icon(Icons.close, size: 16, color: Colors.white54),
              label: const Text('Skip', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ),
        ),

        // Main content
        Center(
          child: isWide
              ? _buildTourWide(step)
              : _buildTourMobile(step),
        ),
      ],
    );
  }

  Widget _buildTourWide(_TourStep step) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1000),
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress stepper
          _ProgressStepper(current: _currentStep, total: _steps.length),
          const SizedBox(height: 40),

          // Two-column card
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: icon panel
              Expanded(
                flex: 4,
                child: FadeTransition(
                  opacity: _stepFade,
                  child: ScaleTransition(
                    scale: _iconScale,
                    child: _IconPanel(step: step, pulseAnim: _pulseAnim),
                  ),
                ),
              ),
              const SizedBox(width: 48),

              // Right: content
              Expanded(
                flex: 6,
                child: FadeTransition(
                  opacity: _stepFade,
                  child: SlideTransition(
                    position: _stepSlide,
                    child: _StepContent(step: step),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Navigation row
          _TourNavRow(
            current: _currentStep,
            total: _steps.length,
            onPrev: _prevStep,
            onNext: _nextStep,
            step: step,
          ),
        ],
      ),
    );
  }

  Widget _buildTourMobile(_TourStep step) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
      child: Column(
        children: [
          _ProgressStepper(current: _currentStep, total: _steps.length),
          const SizedBox(height: 32),
          FadeTransition(
            opacity: _stepFade,
            child: ScaleTransition(
              scale: _iconScale,
              child: _IconPanel(step: step, pulseAnim: _pulseAnim, compact: true),
            ),
          ),
          const SizedBox(height: 28),
          FadeTransition(
            opacity: _stepFade,
            child: SlideTransition(
              position: _stepSlide,
              child: _StepContent(step: step, centerAlign: true),
            ),
          ),
          const SizedBox(height: 32),
          _TourNavRow(
            current: _currentStep,
            total: _steps.length,
            onPrev: _prevStep,
            onNext: _nextStep,
            step: step,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// COMPONENTS
// ============================================================================

class _LogoBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_navyAccent, Color(0xFF2463AE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ABRA Finance Suite',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              'Enterprise Finance Platform',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Background mesh ──────────────────────────────────────────────────────────

class _BackgroundMesh extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MeshPainter(),
    );
  }
}

class _MeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Base gradient
    final bg = Paint()
      ..shader = LinearGradient(
        colors: [_navyDark, const Color(0xFF0A1628), _navyMid.withOpacity(0.4)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, bg);

    // Decorative circles
    final circlePaint = Paint()
      ..color = _navyAccent.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), size.width * 0.35, circlePaint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), size.width * 0.25, circlePaint);

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1;
    const step = 60.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Top accent line
    final accentLine = Paint()
      ..shader = LinearGradient(
        colors: [Colors.transparent, _navyAccent.withOpacity(0.6), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), accentLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Feature cards (hero right panel) ─────────────────────────────────────────

class _FeatureCardStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cards = [
      _MiniCard(icon: Icons.receipt_long_rounded,    label: 'Invoices',        value: '₹2.4Cr',     color: const Color(0xFF00C896)),
      _MiniCard(icon: Icons.store_rounded,            label: 'Payables',        value: '₹88.2L',     color: const Color(0xFFFF8C42)),
      _MiniCard(icon: Icons.corporate_fare_rounded,   label: 'Organisations',   value: '12 Entities', color: _navyAccent),
      _MiniCard(icon: Icons.analytics_rounded,        label: 'Net Revenue',     value: '+18.4%',     color: const Color(0xFFA78BFA)),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 12),
          Expanded(child: cards[1]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: cards[2]),
          const SizedBox(width: 12),
          Expanded(child: cards[3]),
        ]),
        const SizedBox(height: 16),
        // Compliance badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_rounded, color: const Color(0xFF00C896), size: 16),
              const SizedBox(width: 8),
              Text(
                'GST · TDS · TCS Compliant',
                style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Mobile feature pills ──────────────────────────────────────────────────────

class _MobileFeaturePills extends StatelessWidget {
  final _pills = const [
    (Icons.receipt_long_rounded,     'Invoices',         Color(0xFF00C896)),
    (Icons.store_rounded,            'Procurement',      Color(0xFFFF8C42)),
    (Icons.account_balance_rounded,  'Accounting',       Color(0xFFA78BFA)),
    (Icons.verified_user_rounded,    'Access Control',   Color(0xFFFF5C8A)),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: _pills.map((p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: p.$3.withOpacity(0.12),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: p.$3.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(p.$1, color: p.$3, size: 14),
            const SizedBox(width: 6),
            Text(p.$2, style: TextStyle(color: p.$3, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      )).toList(),
    );
  }
}

// ── Progress stepper ──────────────────────────────────────────────────────────

class _ProgressStepper extends StatelessWidget {
  final int current;
  final int total;

  const _ProgressStepper({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Step indicators
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(total * 2 - 1, (i) {
            if (i.isOdd) {
              // Connector line
              final stepIdx = i ~/ 2;
              final isCompleted = stepIdx < current;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 32,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isCompleted ? _navyAccent : Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }
            final stepIdx = i ~/ 2;
            final isActive    = stepIdx == current;
            final isCompleted = stepIdx < current;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: isActive ? 36 : 28,
              height: isActive ? 36 : 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isActive || isCompleted
                    ? const LinearGradient(
                        colors: [_navyAccent, _navyLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isActive || isCompleted ? null : Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: isActive
                      ? _navyAccent
                      : isCompleted
                          ? _navyAccent.withOpacity(0.5)
                          : Colors.white.withOpacity(0.15),
                  width: 1.5,
                ),
                boxShadow: isActive
                    ? [BoxShadow(color: _navyAccent.withOpacity(0.5), blurRadius: 12, spreadRadius: 1)]
                    : null,
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : Text(
                        '${stepIdx + 1}',
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white,
                          fontSize: isActive ? 13 : 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Text(
          '${current + 1} of $total',
          style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 0.5),
        ),
      ],
    );
  }
}

// ── Icon panel ────────────────────────────────────────────────────────────────

class _IconPanel extends StatelessWidget {
  final _TourStep step;
  final Animation<double> pulseAnim;
  final bool compact;

  const _IconPanel({required this.step, required this.pulseAnim, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final size = compact ? 100.0 : 140.0;
    final iconSize = compact ? 44.0 : 60.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: pulseAnim,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: size + 40,
                height: size + 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: step.accentColor.withOpacity(0.06),
                ),
              ),
              // Mid ring
              Container(
                width: size + 20,
                height: size + 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: step.accentColor.withOpacity(0.1),
                ),
              ),
              // Main circle
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      step.accentColor.withOpacity(0.25),
                      _navyMid.withOpacity(0.6),
                    ],
                  ),
                  border: Border.all(color: step.accentColor.withOpacity(0.4), width: 1.5),
                ),
                child: Icon(step.icon, color: step.accentColor, size: iconSize),
              ),
              // Secondary badge
              Positioned(
                bottom: compact ? 8 : 12,
                right: compact ? 8 : 12,
                child: Container(
                  width: compact ? 28 : 36,
                  height: compact ? 28 : 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _navyDark,
                    border: Border.all(color: step.accentColor.withOpacity(0.5), width: 1.5),
                  ),
                  child: Icon(step.secondaryIcon, color: step.accentColor, size: compact ? 14 : 18),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: step.accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: step.accentColor.withOpacity(0.3)),
          ),
          child: Text(
            step.stepLabel,
            style: TextStyle(
              color: step.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step content ──────────────────────────────────────────────────────────────

class _StepContent extends StatelessWidget {
  final _TourStep step;
  final bool centerAlign;

  const _StepContent({required this.step, this.centerAlign = false});

  @override
  Widget build(BuildContext context) {
    final align = centerAlign ? TextAlign.center : TextAlign.left;
    final crossAxis = centerAlign ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        Text(
          step.title,
          textAlign: align,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          step.subtitle,
          textAlign: align,
          style: TextStyle(
            color: step.accentColor,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          step.description,
          textAlign: align,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 24),
        // Highlights
        ...step.highlights.map((h) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisSize: centerAlign ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: step.accentColor.withOpacity(0.15),
                ),
                child: Icon(Icons.check_rounded, color: step.accentColor, size: 12),
              ),
              const SizedBox(width: 10),
              Text(
                h,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

// ── Tour navigation row ───────────────────────────────────────────────────────

class _TourNavRow extends StatelessWidget {
  final int current;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final _TourStep step;

  const _TourNavRow({
    required this.current,
    required this.total,
    required this.onPrev,
    required this.onNext,
    required this.step,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = current == total - 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (current > 0) ...[
          OutlinedButton.icon(
            onPressed: onPrev,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Previous'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
          ),
          const SizedBox(width: 16),
        ],
        ElevatedButton.icon(
          onPressed: onNext,
          icon: isLast
              ? const Icon(Icons.rocket_launch_rounded, size: 16)
              : const Icon(Icons.arrow_forward_rounded, size: 16),
          label: Text(isLast ? 'Get Started' : 'Continue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: step.accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            elevation: 0,
            shadowColor: step.accentColor.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          ),
        ),
      ],
    );
  }
}

// ── Buttons ──────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PrimaryButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: _navyAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.25)),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}