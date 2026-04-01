// ============================================================================
// HOME BILLING — ZOHO BOOKS EXACT DASHBOARD
// ============================================================================
// File: lib/screens/billing/pages/home_billing.dart
//
// Panels:
//   1. Receivables  — Current | Overdue  (tap → Reports)
//   2. Payables     — Current | Overdue  (tap → Reports)
//   3. Cash Flow    — Line chart with tap tooltip (Opening/Incoming/Outgoing/Ending)
//   4. Income & Expense — Bar chart, Accrual/Cash toggle, period filter
//   5. Top Expenses — Donut chart with legend
//   6. Bank Accounts — balance cards
// ============================================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/services/dashboard_service.dart';
import '../../../core/finance_secure_storage.dart';
import 'reports_list_page.dart';

// ─── COLORS ──────────────────────────────────────────────────────────────────
const _kNavyDark   = Color(0xFF0F172A);
const _kNavy       = Color(0xFF1E3A5F);
const _kBlueAccent = Color(0xFF2563EB);
const _kGreen      = Color(0xFF16A34A);
const _kRed        = Color(0xFFDC2626);
const _kOrange     = Color(0xFFF59E0B);
const _kPageBg     = Color(0xFFF8FAFC);
const _kCardBg     = Color(0xFFFFFFFF);
const _kBorder     = Color(0xFFE2E8F0);

const _kPeriods = [
  'This Month','Last Month','This Quarter',
  'This Fiscal Year','Last Fiscal Year',
];

const _kDonutColors = [
  Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFF59E0B),
  Color(0xFFDC2626), Color(0xFF9333EA), Color(0xFF0891B2),
  Color(0xFFDB2777), Color(0xFF65A30D), Color(0xFF7C3AED),
];

// ============================================================================
class HomeBilling extends StatefulWidget {
  const HomeBilling({Key? key}) : super(key: key);

  @override
  State<HomeBilling> createState() => _HomeBillingState();
}

class _HomeBillingState extends State<HomeBilling> {
  final DashboardService _svc = DashboardService();

  String _orgName = '';
  String _periodGlobal      = 'This Fiscal Year';
  String _periodCashFlow    = 'This Fiscal Year';
  String _periodIncomeExp   = 'This Fiscal Year';
  String _periodTopExpenses = 'This Fiscal Year';
  String _basis = 'Accrual';

  Map<String, dynamic> _receivables   = {};
  Map<String, dynamic> _payables      = {};
  Map<String, dynamic> _cashFlow      = {};
  Map<String, dynamic> _incomeExpense = {};
  Map<String, dynamic> _topExpenses   = {};
  List<Map<String, dynamic>> _banks   = [];

  bool _loadingAR   = true;
  bool _loadingAP   = true;
  bool _loadingCF   = true;
  bool _loadingIE   = true;
  bool _loadingTE   = true;
  bool _loadingBank = true;

  @override
  void initState() {
    super.initState();
    _loadOrgName();
    _loadAll();
  }

  Future<void> _loadOrgName() async {
    final name = await FinanceSecureStorage.getOrgName() ?? '';
    if (mounted) setState(() => _orgName = name);
  }

  void _loadAll() {
    _loadAR(); _loadAP(); _loadCF(); _loadIE(); _loadTE(); _loadBanks();
  }

  Future<void> _loadAR() async {
    setState(() => _loadingAR = true);
    final d = await _svc.fetchReceivables(_periodGlobal);
    if (mounted) setState(() { _receivables = d; _loadingAR = false; });
  }

  Future<void> _loadAP() async {
    setState(() => _loadingAP = true);
    final d = await _svc.fetchPayables(_periodGlobal);
    if (mounted) setState(() { _payables = d; _loadingAP = false; });
  }

  Future<void> _loadCF() async {
    setState(() => _loadingCF = true);
    final d = await _svc.fetchCashFlow(_periodCashFlow);
    if (mounted) setState(() { _cashFlow = d; _loadingCF = false; });
  }

  Future<void> _loadIE() async {
    setState(() => _loadingIE = true);
    final d = await _svc.fetchIncomeExpense(_periodIncomeExp, _basis);
    if (mounted) setState(() { _incomeExpense = d; _loadingIE = false; });
  }

  Future<void> _loadTE() async {
    setState(() => _loadingTE = true);
    final d = await _svc.fetchTopExpenses(_periodTopExpenses);
    if (mounted) setState(() { _topExpenses = d; _loadingTE = false; });
  }

  Future<void> _loadBanks() async {
    setState(() => _loadingBank = true);
    final d = await _svc.fetchBankAccounts();
    if (mounted) setState(() { _banks = d; _loadingBank = false; });
  }

  void _openReports() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsListPage()));
  }

  String _fmt(dynamic v) {
    final val = (v as num?)?.toDouble() ?? 0.0;
    if (val >= 10000000) return '₹${(val/10000000).toStringAsFixed(2)}Cr';
    if (val >= 100000)   return '₹${(val/100000).toStringAsFixed(2)}L';
    if (val >= 1000)     return '₹${(val/1000).toStringAsFixed(1)}K';
    return '₹${val.toStringAsFixed(2)}';
  }

  String _fmtShort(double v) {
    if (v == 0) return '0';
    if (v.abs() >= 100000) return '${(v/100000).toStringAsFixed(0)}L';
    if (v.abs() >= 1000)   return '${(v/1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      body: RefreshIndicator(
        color: _kBlueAccent,
        onRefresh: () async => _loadAll(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildARAPRow(),
                const SizedBox(height: 16),
                _buildCashFlowPanel(),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (_, c) {
                  if (c.maxWidth >= 700) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: _buildIncomeExpPanel()),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _buildTopExpPanel()),
                    ]);
                  }
                  return Column(children: [
                    _buildIncomeExpPanel(),
                    const SizedBox(height: 16),
                    _buildTopExpPanel(),
                  ]);
                }),
                const SizedBox(height: 16),
                _buildBankPanel(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: _kCardBg,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Dashboard',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kNavyDark)),
          if (_orgName.isNotEmpty)
            Text(_orgName, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ]),
        const Spacer(),
        _periodDrop(_periodGlobal, (v) { setState(() => _periodGlobal = v!); _loadAR(); _loadAP(); }),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: _kNavy, size: 20),
          tooltip: 'Refresh',
          onPressed: _loadAll,
        ),
      ]),
    );
  }

  // ── Period Dropdown ────────────────────────────────────────────────────────
  Widget _periodDrop(String value, ValueChanged<String?> onChanged) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _kCardBg,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: _kNavy),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kNavy),
          items: _kPeriods.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── Card wrapper ────────────────────────────────────────────────────────────
  Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _cardTitle(String title, {Widget? trailing, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        GestureDetector(
          onTap: onTap ?? _openReports,
          child: Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kNavyDark)),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _loadingBox() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _kBlueAccent)),
  );

  // ==========================================================================
  // 1. RECEIVABLES + PAYABLES
  // ==========================================================================

  Widget _buildARAPRow() {
    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth >= 600) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _buildARCard()),
          const SizedBox(width: 16),
          Expanded(child: _buildAPCard()),
        ]);
      }
      return Column(children: [_buildARCard(), const SizedBox(height: 12), _buildAPCard()]);
    });
  }

  Widget _buildARCard() {
    final cur = (_receivables['current'] as num?)?.toDouble() ?? 0;
    final ov  = (_receivables['overdue']  as num?)?.toDouble() ?? 0;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Total Receivables'),
      _loadingAR ? _loadingBox() : Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _amtTile('Current', cur, _kBlueAccent, dot: _kBlueAccent)),
          const SizedBox(width: 12),
          Expanded(child: _amtTile('Overdue', ov, _kOrange, dot: _kOrange, showArrow: true)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: GestureDetector(
          onTap: _openReports,
          child: const Row(children: [
            Icon(Icons.add_circle_outline, size: 14, color: _kBlueAccent),
            SizedBox(width: 4),
            Text('New Invoice', style: TextStyle(fontSize: 12, color: _kBlueAccent, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]));
  }

  Widget _buildAPCard() {
    final cur = (_payables['current'] as num?)?.toDouble() ?? 0;
    final ov  = (_payables['overdue']  as num?)?.toDouble() ?? 0;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Total Payables'),
      _loadingAP ? _loadingBox() : Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _amtTile('Current', cur, _kBlueAccent, dot: _kBlueAccent)),
          const SizedBox(width: 12),
          Expanded(child: _amtTile('Overdue', ov, _kOrange, dot: _kOrange, showArrow: true)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: GestureDetector(
          onTap: _openReports,
          child: const Row(children: [
            Icon(Icons.add_circle_outline, size: 14, color: _kBlueAccent),
            SizedBox(width: 4),
            Text('New Bill', style: TextStyle(fontSize: 12, color: _kBlueAccent, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]));
  }

  Widget _amtTile(String label, double value, Color color,
      {required Color dot, bool showArrow = false}) {
    return GestureDetector(
      onTap: _openReports,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            if (showArrow) ...[
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey[500]),
            ],
          ]),
          const SizedBox(height: 6),
          Text(_fmt(value), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  // ==========================================================================
  // 2. CASH FLOW
  // ==========================================================================

  Widget _buildCashFlowPanel() {
    final monthly  = (_cashFlow['monthly']  as List?)?.cast<Map>() ?? [];
    final opening  = (_cashFlow['openingBalance'] as num?)?.toDouble() ?? 0;
    final incoming = (_cashFlow['totalIncoming']  as num?)?.toDouble() ?? 0;
    final outgoing = (_cashFlow['totalOutgoing']  as num?)?.toDouble() ?? 0;
    final ending   = (_cashFlow['endingBalance']  as num?)?.toDouble() ?? 0;

    // Build chart spots
    List<FlSpot> spots = [];
    double running = opening;
    for (int i = 0; i < monthly.length; i++) {
      final inc = (monthly[i]['incoming'] as num?)?.toDouble() ?? 0;
      final out = (monthly[i]['outgoing'] as num?)?.toDouble() ?? 0;
      running += inc - out;
      spots.add(FlSpot(i.toDouble(), running));
    }
    if (spots.isEmpty) spots = List.generate(12, (i) => FlSpot(i.toDouble(), 0));

    final allY = spots.map((s) => s.y).toList();
    final maxY = allY.fold(0.0, (a, b) => a > b ? a : b);
    final minY = allY.fold(0.0, (a, b) => a < b ? a : b);

    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle(
        'Cash Flow',
        trailing: _periodDrop(_periodCashFlow, (v) { setState(() => _periodCashFlow = v!); _loadCF(); }),
      ),
      _loadingCF ? _loadingBox() : Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
          child: SizedBox(
            height: 200,
            child: GestureDetector(
              onTap: _openReports,
              child: LineChart(LineChartData(
                minY: minY < 0 ? minY * 1.1 : 0,
                maxY: maxY == 0 ? 10000 : maxY * 1.2,
                gridData: FlGridData(
                  show: true, drawVerticalLine: false,
                  horizontalInterval: maxY == 0 ? 2000 : (maxY / 4).clamp(1, double.infinity),
                  getDrawingHorizontalLine: (_) => const FlLine(color: _kBorder, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 22, interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= monthly.length || i % 2 != 0) return const SizedBox();
                      return Text((monthly[i]['month'] ?? '').toString(),
                          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)));
                    },
                  )),
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 48,
                    getTitlesWidget: (v, _) => Text(_fmtShort(v),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                  )),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.white,
                    tooltipRoundedRadius: 8,
                    tooltipBorder: const BorderSide(color: _kBorder),
                    getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                      final i = s.x.toInt();
                      if (i < 0 || i >= monthly.length) return LineTooltipItem('', const TextStyle());
                      final m   = monthly[i];
                      final inc = (m['incoming'] as num?)?.toDouble() ?? 0;
                      final out = (m['outgoing'] as num?)?.toDouble() ?? 0;
                      return LineTooltipItem(
                        '${m['month']}\nIncoming  ${_fmt(inc)}\nOutgoing  ${_fmt(out)}\nBalance   ${_fmt(s.y)}',
                        const TextStyle(color: _kNavyDark, fontSize: 11, fontWeight: FontWeight.w600, height: 1.7),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [LineChartBarData(
                  spots: spots, isCurved: true,
                  color: _kBlueAccent, barWidth: 2.5,
                  isStrokeCapRound: true,
                  belowBarData: BarAreaData(show: true, color: _kBlueAccent.withOpacity(0.08)),
                  dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) =>
                      FlDotCirclePainter(radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: _kBlueAccent)),
                )],
              )),
            ),
          ),
        ),
        // Legend row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _cfLegItem('Opening',  opening,  Colors.grey),
            _cfLegItem('Incoming', incoming, _kGreen,      suffix: ' (+)'),
            _cfLegItem('Outgoing', outgoing, _kRed,        suffix: ' (-)'),
            _cfLegItem('Closing',  ending,   _kBlueAccent, suffix: ' (=)'),
          ]),
        ),
      ]),
    ]));
  }

  Widget _cfLegItem(String label, double val, Color color, {String suffix = ''}) {
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ]),
      const SizedBox(height: 3),
      Text('${_fmt(val)}$suffix',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  // ==========================================================================
  // 3. INCOME & EXPENSE
  // ==========================================================================

  Widget _buildIncomeExpPanel() {
    final totalInc = (_incomeExpense['totalIncome']  as num?)?.toDouble() ?? 0;
    final totalExp = (_incomeExpense['totalExpense'] as num?)?.toDouble() ?? 0;
    final monthly  = (_incomeExpense['monthly'] as List?)?.cast<Map>() ?? [];

    final barGroups = monthly.asMap().entries.map((e) {
      final inc = (e.value['income']  as num?)?.toDouble() ?? 0;
      final exp = (e.value['expense'] as num?)?.toDouble() ?? 0;
      return BarChartGroupData(x: e.key, barsSpace: 2, barRods: [
        BarChartRodData(toY: inc, color: _kGreen,                   width: 8, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        BarChartRodData(toY: exp, color: _kRed.withOpacity(0.8),    width: 8, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
      ]);
    }).toList();

    final maxVal = monthly.fold(0.0, (prev, m) {
      final inc = (m['income']  as num?)?.toDouble() ?? 0;
      final exp = (m['expense'] as num?)?.toDouble() ?? 0;
      return [prev, inc, exp].reduce((a, b) => a > b ? a : b);
    });

    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Income and Expense', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        // Accrual / Cash toggle
        Container(
          height: 32,
          decoration: BoxDecoration(border: Border.all(color: _kBorder), borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _basisBtn('Accrual'),
            _basisBtn('Cash'),
          ]),
        ),
        const SizedBox(width: 8),
        _periodDrop(_periodIncomeExp, (v) { setState(() => _periodIncomeExp = v!); _loadIE(); }),
      ])),
      _loadingIE ? _loadingBox() : Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            _ieSummary('Total Income',   totalInc, _kGreen),
            const SizedBox(width: 20),
            _ieSummary('Total Expenses', totalExp, _kRed),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
          child: SizedBox(
            height: 200,
            child: GestureDetector(
              onTap: _openReports,
              child: BarChart(BarChartData(
                maxY: maxVal == 0 ? 10000 : maxVal * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipBgColor: Colors.white,
                    tooltipRoundedRadius: 8,
                    tooltipBorder: const BorderSide(color: _kBorder),
                    getTooltipItem: (group, gi, rod, ri) {
                      final m = gi < monthly.length ? monthly[gi] : null;
                      final isInc = ri == 0;
                      return BarTooltipItem(
                        '${m?['month'] ?? ''}\n${isInc ? 'Income' : 'Expense'}: ${_fmt(rod.toY)}',
                        TextStyle(color: isInc ? _kGreen : _kRed, fontSize: 11, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                  touchCallback: (_, resp) { if (resp?.spot != null) _openReports(); },
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 22,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= monthly.length || i % 2 != 0) return const SizedBox();
                      return Text((monthly[i]['month'] ?? '').toString(),
                          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)));
                    },
                  )),
                  leftTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true, reservedSize: 44,
                    getTitlesWidget: (v, _) => Text(_fmtShort(v),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                  )),
                  topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true, drawVerticalLine: false,
                  horizontalInterval: maxVal == 0 ? 2000 : (maxVal / 4).clamp(1, double.infinity),
                  getDrawingHorizontalLine: (_) => const FlLine(color: _kBorder, strokeWidth: 1),
                ),
                barGroups: barGroups,
              )),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Text('* Values are exclusive of taxes.',
              style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic)),
        ),
      ]),
    ]));
  }

  Widget _basisBtn(String label) {
    final sel = _basis == label;
    return GestureDetector(
      onTap: () { setState(() => _basis = label); _loadIE(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _kBlueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : _kNavy)),
      ),
    );
  }

  Widget _ieSummary(String label, double val, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
      const SizedBox(height: 4),
      Text(_fmt(val), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  // ==========================================================================
  // 4. TOP EXPENSES
  // ==========================================================================

  Widget _buildTopExpPanel() {
    final total = (_topExpenses['total'] as num?)?.toDouble() ?? 0;
    final cats  = (_topExpenses['categories'] as List?)?.cast<Map>() ?? [];

    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Top Expenses',
          trailing: _periodDrop(_periodTopExpenses, (v) { setState(() => _periodTopExpenses = v!); _loadTE(); })),
      _loadingTE ? _loadingBox()
      : cats.isEmpty
          ? Padding(padding: const EdgeInsets.all(32),
              child: Center(child: Text('No expense data', style: TextStyle(color: Colors.grey[500]))))
          : GestureDetector(
              onTap: _openReports,
              child: Column(children: [
                // Donut
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SizedBox(
                    height: 180,
                    child: Stack(alignment: Alignment.center, children: [
                      PieChart(PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 55,
                        sections: cats.asMap().entries.map((e) => PieChartSectionData(
                          value: (e.value['amount'] as num).toDouble(),
                          color: _kDonutColors[e.key % _kDonutColors.length],
                          radius: 40,
                          showTitle: false,
                        )).toList(),
                      )),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('All Expenses', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        Text(_fmt(total),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kNavyDark)),
                      ]),
                    ]),
                  ),
                ),
                // Legend
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: cats.take(5).toList().asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Container(width: 10, height: 10,
                            decoration: BoxDecoration(
                                color: _kDonutColors[e.key % _kDonutColors.length],
                                shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.value['name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                        Text(_fmt(e.value['amount']),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    )).toList(),
                  ),
                ),
              ]),
            ),
    ]));
  }

  // ==========================================================================
  // 5. BANK PANEL
  // ==========================================================================

  Widget _buildBankPanel() {
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Bank & Cash Accounts'),
      _loadingBank ? _loadingBox()
      : _banks.isEmpty
          ? Padding(padding: const EdgeInsets.all(24),
              child: Center(child: Text('No bank accounts found', style: TextStyle(color: Colors.grey[500]))))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12, runSpacing: 12,
                children: _banks.take(8).map(_bankTile).toList(),
              ),
            ),
    ]));
  }

  Widget _bankTile(Map<String, dynamic> bank) {
    final name    = bank['accountName']?.toString() ?? 'Account';
    final balance = ((bank['currentBalance'] ?? bank['balance'] ?? 0) as num).toDouble();
    final type    = (bank['accountType'] ?? 'BANK').toString().toUpperCase();

    IconData icon; Color color;
    switch (type) {
      case 'FUEL_CARD':      icon = Icons.local_gas_station; color = const Color(0xFF2980B9); break;
      case 'FASTAG':         icon = Icons.toll;              color = const Color(0xFFE67E22); break;
      case 'PETTY_CASH':     icon = Icons.payments;          color = const Color(0xFF9B59B6); break;
      case 'DRIVER_ADVANCE': icon = Icons.person;            color = const Color(0xFF3F51B5); break;
      default:               icon = Icons.account_balance;   color = _kGreen;
    }

    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 8),
          Expanded(child: Text(name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kNavyDark),
              overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 10),
        Text(_fmt(balance),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}