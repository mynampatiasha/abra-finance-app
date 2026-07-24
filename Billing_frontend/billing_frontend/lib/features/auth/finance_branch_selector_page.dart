// ============================================================================
// ABRA FINANCE SUITE — BRANCH SELECTOR PAGE
// ============================================================================
// Shown after org selection. User picks one, multiple, or all branches.
// Selected branchIds are stored and sent as x-branch-ids header on every API call.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/finance_secure_storage.dart';
import '../../data/services/finance_auth_service.dart';
import 'finance_post_login_splash.dart';
import '../billing/billing_main_shell.dart';

const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _goldAccent = Color(0xFFFBBF24);

class FinanceBranchSelectorPage extends StatefulWidget {
  final String orgId;
  final String orgName;
  final String userName;

  /// If true, navigates to splash+shell after selection.
  /// If false (in-app switcher), just pops with result.
  final bool isInitialLogin;

  const FinanceBranchSelectorPage({
    super.key,
    required this.orgId,
    required this.orgName,
    required this.userName,
    this.isInitialLogin = true,
  });

  @override
  State<FinanceBranchSelectorPage> createState() =>
      _FinanceBranchSelectorPageState();
}

class _FinanceBranchSelectorPageState extends State<FinanceBranchSelectorPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _branches = [];
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  late final AnimationController _orbitCtrl;

  @override
  void initState() {
    super.initState();
    _orbitCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 16))
          ..repeat();
    _loadBranches();
  }

  @override
  void dispose() {
    _orbitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await FinanceAuthService.get('/api/finance/branches');
      if (res['success'] == true) {
        final list = (res['data']?['branches'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // Pre-load previously selected branches and allowed branches
        final saved = await FinanceSecureStorage.getSelectedBranchIds();
        final allowed = await FinanceSecureStorage.getAllowedBranchIds();

        // If this user has a branch restriction, only show their permitted branches
        final visible = allowed.isEmpty
            ? list
            : list
                .where((b) => allowed.contains(b['branchId'] as String? ?? ''))
                .toList();

        if (!mounted) return;
        setState(() {
          _branches = visible;
          _selectedIds.addAll(
              saved.where((id) => visible.any((b) => b['branchId'] == id)));
          _loading = false;
        });
        // Save full branches list to storage (unfiltered, for display elsewhere)
        await FinanceSecureStorage.saveBranches(list);
      } else {
        if (!mounted) return;
        setState(() {
          _error = res['message'] ?? 'Failed to load branches';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Network error: $e';
        _loading = false;
      });
    }
  }

  void _toggleBranch(String branchId) {
    setState(() {
      if (_selectedIds.contains(branchId)) {
        _selectedIds.remove(branchId);
      } else {
        _selectedIds.add(branchId);
      }
    });
  }

  void _selectAll() => setState(() {
        _selectedIds.addAll(_branches.map((b) => b['branchId'] as String));
      });
  void _clearAll() => setState(() => _selectedIds.clear());

  Future<void> _confirm() async {
    setState(() => _saving = true);
    // Save selection — empty list means ALL
    final ids = _selectedIds.toList();
    await FinanceSecureStorage.saveSelectedBranchIds(ids);

    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.isInitialLogin) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => FinancePostLoginSplash(
            userName: widget.userName,
            orgName: widget.orgName,
            destination: const BillingMainShell(),
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } else {
      Navigator.pop(context, ids);
    }
  }

  String get _selectionLabel {
    if (_selectedIds.isEmpty) return 'All Branches';
    if (_selectedIds.length == _branches.length) return 'All Branches';
    if (_selectedIds.length == 1) {
      final b = _branches.firstWhere((b) => b['branchId'] == _selectedIds.first,
          orElse: () => {});
      return b['branchName'] ?? '1 Branch';
    }
    return '${_selectedIds.length} Branches';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _orbitCtrl,
              builder: (_, __) =>
                  CustomPaint(painter: _BranchBgPainter(_orbitCtrl.value)),
            ),
          ),
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
                        // Header icon
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [_navyAccent, _navyLight],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                  color: _navyAccent.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2)
                            ],
                          ),
                          child: const Icon(Icons.account_tree_rounded,
                              color: Colors.white, size: 34),
                        ),
                        const SizedBox(height: 20),
                        const Text('Select Branch',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.12))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.business_rounded,
                                color: Colors.white70, size: 14),
                            const SizedBox(width: 8),
                            Text(widget.orgName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                            'Select one or more branches, or skip to see all data',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 13)),
                        const SizedBox(height: 24),

                        // Error
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.red.withOpacity(0.3))),
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

                        // Loading
                        if (_loading)
                          const Padding(
                              padding: EdgeInsets.all(32),
                              child:
                                  CircularProgressIndicator(color: _navyAccent))
                        else if (_branches.isEmpty)
                          // No branches — skip straight through
                          _NoBranchesCard(onContinue: _confirm, saving: _saving)
                        else ...[
                          // Select All / Clear All row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: _selectAll,
                                icon: const Icon(Icons.select_all_rounded,
                                    size: 15, color: _navyAccent),
                                label: const Text('Select All',
                                    style: TextStyle(
                                        color: _navyAccent, fontSize: 13)),
                              ),
                              TextButton.icon(
                                onPressed: _clearAll,
                                icon: const Icon(Icons.deselect_rounded,
                                    size: 15, color: Colors.white54),
                                label: const Text('Clear',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Branch cards
                          ..._branches.map((branch) {
                            final branchId =
                                branch['branchId'] as String? ?? '';
                            final branchName =
                                branch['branchName'] as String? ?? '';
                            final city = branch['city'] as String? ?? '';
                            final isSelected = _selectedIds.contains(branchId);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GestureDetector(
                                onTap: () => _toggleBranch(branchId),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _navyAccent.withOpacity(0.18)
                                        : Colors.white.withOpacity(0.07),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: isSelected
                                            ? _navyAccent
                                            : Colors.white.withOpacity(0.12),
                                        width: isSelected ? 1.5 : 1),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                                color: _navyAccent
                                                    .withOpacity(0.25),
                                                blurRadius: 16,
                                                offset: const Offset(0, 4))
                                          ]
                                        : [],
                                  ),
                                  child: Row(children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                            colors: isSelected
                                                ? [_navyAccent, _navyLight]
                                                : [_navyMid, _navyLight],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Center(
                                          child: Text(
                                              branchName.isNotEmpty
                                                  ? branchName[0].toUpperCase()
                                                  : 'B',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight:
                                                      FontWeight.w800))),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(branchName,
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white)),
                                          if (city.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Row(children: [
                                              const Icon(
                                                  Icons.location_on_outlined,
                                                  size: 12,
                                                  color: Colors.white54),
                                              const SizedBox(width: 4),
                                              Text(city,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white54)),
                                            ]),
                                          ],
                                        ])),
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected
                                            ? _navyAccent
                                            : Colors.white.withOpacity(0.06),
                                        border: Border.all(
                                            color: isSelected
                                                ? _navyAccent
                                                : Colors.white
                                                    .withOpacity(0.2)),
                                      ),
                                      child: Icon(
                                          isSelected
                                              ? Icons.check_rounded
                                              : Icons.add_rounded,
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white54,
                                          size: 16),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 20),

                          // Confirm button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _saving ? null : _confirm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _navyAccent,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : Text(
                                      _selectedIds.isEmpty
                                          ? 'Continue with All Branches'
                                          : 'Continue with $_selectionLabel',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700),
                                    ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),
                        if (!_loading && _branches.isNotEmpty)
                          Text(
                            _selectedIds.isEmpty
                                ? 'No filter — showing all branch data'
                                : '${_selectedIds.length} of ${_branches.length} branch${_branches.length != 1 ? 'es' : ''} selected',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 12),
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

// ── No branches card ──────────────────────────────────────────────────────────
class _NoBranchesCard extends StatelessWidget {
  final VoidCallback onContinue;
  final bool saving;
  const _NoBranchesCard({required this.onContinue, required this.saving});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.12))),
        child: Column(children: [
          const Icon(Icons.info_outline_rounded,
              color: Colors.white54, size: 36),
          const SizedBox(height: 12),
          const Text('No branches set up yet',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('You can add branches later from Settings.',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 13)),
        ]),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: saving ? null : onContinue,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3D8EFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0),
          child: saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Continue',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

// ── Background painter ────────────────────────────────────────────────────────
class _BranchBgPainter extends CustomPainter {
  final double progress;
  _BranchBgPainter(this.progress);

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
    for (double x = 0; x < size.width; x += 55)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    for (double y = 0; y < size.height; y += 55)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);

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
  }

  @override
  bool shouldRepaint(_BranchBgPainter old) => old.progress != progress;
}
