// ============================================================================
// BUDGET DETAIL PAGE
// ============================================================================
// File: lib/screens/billing/pages/budget_detail.dart
// Shows full Actual vs Budgeted comparison with color indicators
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/budget_service.dart';
import 'new_budget.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class BudgetDetailPage extends StatefulWidget {
  final String budgetId;
  const BudgetDetailPage({Key? key, required this.budgetId}) : super(key: key);

  @override
  State<BudgetDetailPage> createState() => _BudgetDetailPageState();
}

class _BudgetDetailPageState extends State<BudgetDetailPage> {
  Budget? _budget;
  bool _isLoading = true;
  String? _error;

  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  static const _monthLabels = [
    'Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec','Jan','Feb','Mar'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final b = await BudgetService.getBudgetWithActuals(widget.budgetId);
      setState(() { _budget = b; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _goEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewBudgetScreen(budgetId: widget.budgetId)),
    );
    if (result == true) _load();
  }

  Future<void> _toggleActive() async {
    if (_budget == null) return;
    try {
      await BudgetService.toggleActive(widget.budgetId, !_budget!.isActive);
      _load();
      _snack(_budget!.isActive ? 'Budget deactivated' : 'Budget activated',
          _budget!.isActive ? Colors.orange : Colors.green);
    } catch (e) {
      _snack('Failed: $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navyDark, _navyMid, _navyLight],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _budget?.budgetName ?? 'Budget Detail',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (_budget != null) ...[
            IconButton(
              icon: Icon(
                _budget!.isActive ? Icons.toggle_on : Icons.toggle_off,
                size: 28,
              ),
              tooltip: _budget!.isActive ? 'Deactivate' : 'Activate',
              onPressed: _toggleActive,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _goEdit,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _load,
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
    ),
  );

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
    const SizedBox(height: 16),
    Text('Failed to load', style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
    const SizedBox(height: 8),
    Text(_error ?? '', style: TextStyle(color: Colors.grey.shade500)),
    const SizedBox(height: 20),
    ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white)),
  ]));

  Widget _buildBody() {
    final b = _budget!;
    return SingleChildScrollView(
      controller: _vScroll,
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(b),
        _buildSummaryCards(b),
        _buildComparisonTable(b),
        _buildMonthlyBreakdown(b),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(Budget b) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    color: Colors.white,
    child: LayoutBuilder(builder: (_, cs) {
      final wide = cs.maxWidth > 600;
      final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.budgetName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _navyDark)),
            const SizedBox(height: 4),
            Text('${b.financialYear}  •  ${b.budgetPeriod}  •  ${b.currency}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ])),
          _badge(b.isActive ? 'Active' : 'Inactive',
              b.isActive ? Colors.green.shade100 : Colors.grey.shade200,
              b.isActive ? Colors.green.shade700 : Colors.grey.shade600),
        ]),
        if (b.notes != null && b.notes!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(b.notes!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ]);
      return info;
    }),
  );

  // ── Summary Cards ─────────────────────────────────────────────────────────

  Widget _buildSummaryCards(Budget b) {
    final variance   = b.totalBudgeted - b.totalActual;
    final pctUsed    = b.totalBudgeted > 0 ? (b.totalActual / b.totalBudgeted * 100) : 0.0;
    final overBudget = variance < 0;

    final cards = [
      _CardData('Total Budgeted', '₹${_fmt(b.totalBudgeted)}', Icons.account_balance_wallet_outlined, Colors.blue),
      _CardData('Total Actual', '₹${_fmt(b.totalActual)}', Icons.receipt_long_outlined, Colors.teal),
      _CardData('Variance', '${overBudget ? '-' : ''}₹${_fmt(variance.abs())}', Icons.swap_vert_circle_outlined, overBudget ? Colors.red : Colors.green),
      _CardData('% Utilised', '${pctUsed.toStringAsFixed(1)}%', Icons.pie_chart_outline, pctUsed > 100 ? Colors.red : pctUsed > 80 ? Colors.orange : Colors.green),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 1),
      child: LayoutBuilder(builder: (_, cs) {
        if (cs.maxWidth < 600) {
          return Wrap(spacing: 12, runSpacing: 12,
              children: cards.map((c) => SizedBox(width: (cs.maxWidth - 12) / 2, child: _summCard(c))).toList());
        }
        return Row(children: cards.map((c) =>
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _summCard(c)))).toList());
      }),
    );
  }

  Widget _summCard(_CardData c) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: c.color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.color.withOpacity(0.25)),
    ),
    child: Row(children: [
      Icon(c.icon, size: 30, color: c.color),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(c.value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.color), overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );

  // ── Comparison Table ──────────────────────────────────────────────────────

  Widget _buildComparisonTable(Budget b) => Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_navyDark, _navyMid]),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
        ),
        child: Row(children: [
          const Icon(Icons.compare_arrows, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Budget vs Actual Comparison',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
          Text('${b.accountLines.length} accounts',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
      Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        trackVisibility: true,
        thickness: 6,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
          ),
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF0F4FF)),
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _navyDark, letterSpacing: 0.4),
              headingRowHeight: 44,
              dataRowMinHeight: 52,
              dataTextStyle: const TextStyle(fontSize: 13, color: _navyDark),
              dividerThickness: 0.8,
              columnSpacing: 20,
              horizontalMargin: 16,
              columns: const [
                DataColumn(label: SizedBox(width: 200, child: Text('ACCOUNT'))),
                DataColumn(label: SizedBox(width: 100, child: Text('TYPE'))),
                DataColumn(label: SizedBox(width: 130, child: Text('BUDGETED')), numeric: true),
                DataColumn(label: SizedBox(width: 130, child: Text('ACTUAL')),   numeric: true),
                DataColumn(label: SizedBox(width: 130, child: Text('VARIANCE')), numeric: true),
                DataColumn(label: SizedBox(width: 100, child: Text('% USED')),   numeric: true),
                DataColumn(label: SizedBox(width: 180, child: Text('PROGRESS'))),
              ],
              rows: b.accountLines.map((line) {
                final over = line.variance < 0;
                final pct  = line.percentUsed;
                return DataRow(cells: [
                  DataCell(SizedBox(width: 200, child: Text(line.accountName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis))),
                  DataCell(SizedBox(width: 100, child: Text(line.accountType, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                  DataCell(SizedBox(width: 130, child: Text('₹${_fmt(line.totalBudgeted)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)))),
                  DataCell(SizedBox(width: 130, child: Text('₹${_fmt(line.totalActual)}', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.teal.shade700)))),
                  DataCell(SizedBox(width: 130, child: Text(
                    '${over ? '-' : ''}₹${_fmt(line.variance.abs())}',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.bold, color: over ? Colors.red : Colors.green.shade700),
                  ))),
                  DataCell(SizedBox(width: 100, child: _pctBadge(pct))),
                  DataCell(SizedBox(width: 180, child: _progressBar(pct))),
                ]);
              }).toList()
                ..add(_totalRow(b)),
            ),
          ),
        ),
      ),
    ]),
  );

  DataRow _totalRow(Budget b) {
    final variance  = b.totalBudgeted - b.totalActual;
    final pct       = b.totalBudgeted > 0 ? b.totalActual / b.totalBudgeted * 100 : 0.0;
    final over      = variance < 0;
    return DataRow(
      color: WidgetStateProperty.all(const Color(0xFFF0F4FF)),
      cells: [
        const DataCell(SizedBox(width: 200, child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _navyDark)))),
        const DataCell(SizedBox(width: 100, child: Text(''))),
        DataCell(SizedBox(width: 130, child: Text('₹${_fmt(b.totalBudgeted)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, color: _navyDark)))),
        DataCell(SizedBox(width: 130, child: Text('₹${_fmt(b.totalActual)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)))),
        DataCell(SizedBox(width: 130, child: Text(
          '${over ? '-' : ''}₹${_fmt(variance.abs())}',
          textAlign: TextAlign.right,
          style: TextStyle(fontWeight: FontWeight.bold, color: over ? Colors.red : Colors.green),
        ))),
        DataCell(SizedBox(width: 100, child: _pctBadge(pct))),
        DataCell(SizedBox(width: 180, child: _progressBar(pct))),
      ],
    );
  }

  // ── Monthly Breakdown ─────────────────────────────────────────────────────

  Widget _buildMonthlyBreakdown(Budget b) {
    if (b.accountLines.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_navyMid, _navyLight]),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_month, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('Monthly Breakdown (Budgeted vs Actual)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
        ),
        Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F9FA)),
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _navyDark),
              headingRowHeight: 42,
              dataRowMinHeight: 52,
              dataTextStyle: const TextStyle(fontSize: 11),
              dividerThickness: 0.8,
              columnSpacing: 12,
              horizontalMargin: 12,
              columns: [
                const DataColumn(label: SizedBox(width: 160, child: Text('ACCOUNT'))),
                ...List.generate(12, (i) => DataColumn(
                  label: SizedBox(width: 75,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_monthLabels[i], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  numeric: true,
                )),
                const DataColumn(label: SizedBox(width: 110, child: Text('ANNUAL')), numeric: true),
              ],
              rows: b.accountLines.map((line) => DataRow(cells: [
                DataCell(SizedBox(width: 160, child: Text(line.accountName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis))),
                ...List.generate(12, (m) {
                  final budg = m < line.monthlyAmounts.length ? line.monthlyAmounts[m] : 0.0;
                  final act  = m < line.actualMonthly.length  ? line.actualMonthly[m]  : 0.0;
                  final over = act > budg && budg > 0;
                  return DataCell(SizedBox(width: 75, child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_fmtShort(budg), style: const TextStyle(fontSize: 11, color: _navyDark)),
                      Text(_fmtShort(act), style: TextStyle(fontSize: 10, color: over ? Colors.red : Colors.teal.shade700)),
                    ],
                  )));
                }),
                DataCell(SizedBox(width: 110, child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_fmt(line.totalBudgeted), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _navyDark)),
                    Text(_fmt(line.totalActual), style: TextStyle(fontSize: 11, color: Colors.teal.shade700)),
                  ],
                ))),
              ])).toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _legendDot(Colors.teal.shade700), const SizedBox(width: 4), const Text('Actual', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 12),
            _legendDot(_navyDark), const SizedBox(width: 4), const Text('Budgeted', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 12),
            _legendDot(Colors.red), const SizedBox(width: 4), const Text('Over budget', style: TextStyle(fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _pctBadge(double pct) {
    Color bg, fg;
    String icon;
    if (pct > 100) { bg = Colors.red.shade50;    fg = Colors.red;              icon = '🔴'; }
    else if (pct > 80) { bg = Colors.orange.shade50; fg = Colors.orange.shade700; icon = '🟡'; }
    else { bg = Colors.green.shade50;  fg = Colors.green.shade700;  icon = '🟢'; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('$icon ${pct.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _progressBar(double pct) {
    final clamped = pct.clamp(0.0, 150.0);
    final fraction = (clamped / 150).clamp(0.0, 1.0);
    final color = pct > 100 ? Colors.red : pct > 80 ? Colors.orange : Colors.green;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: fraction,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 8,
        ),
      ),
    ]);
  }

  Widget _badge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
  );

  Widget _legendDot(Color color) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);
  String _fmtShort(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _CardData {
  final String label, value;
  final IconData icon;
  final Color color;
  const _CardData(this.label, this.value, this.icon, this.color);
}