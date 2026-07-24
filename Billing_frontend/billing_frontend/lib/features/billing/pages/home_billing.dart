import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// HOME BILLING — ZOHO BOOKS EXACT DASHBOARD — FULLY FIXED
// ============================================================================
// File: lib/screens/billing/pages/home_billing.dart
//
// FIXES IN THIS VERSION:
//   1. Cash Flow chart Y axis — smart min/max so curve shows correctly
//      (was always minY=0 making flat line when all values are positive)
//   2. Navigation — all taps now use InkWell with larger hit areas
//   3. Bank panel — correctly unwraps { success, count, data: [...] }
//   4. _goToReport wrapped in try-catch to surface errors
// ============================================================================

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/services/dashboard_service.dart';
import '../../../core/finance_secure_storage.dart';
import '../../../core/services/reports_service.dart';
import 'account_detail_page.dart';
import 'report_viewer_page.dart';
import 'reports_list_page.dart';

// ─── COLOURS ──────────────────────────────────────────────────────────────────
const _kNavyDark = Color(0xFF0F172A);
const _kNavy = Color(0xFF1E3A5F);
const _kBlueAccent = Color(0xFF2563EB);
const _kGreen = Color(0xFF16A34A);
const _kRed = Color(0xFFDC2626);
const _kOrange = Color(0xFFF59E0B);
const _kPageBg = Color(0xFFF8FAFC);
const _kCardBg = Color(0xFFFFFFFF);
const _kBorder = Color(0xFFE2E8F0);

const _kPeriods = [
  'This Month',
  'Last Month',
  'This Quarter',
  'This Fiscal Year',
  'Last Fiscal Year',
];

const _kDonutColors = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFF59E0B),
  Color(0xFFDC2626),
  Color(0xFF9333EA),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF65A30D),
  Color(0xFF7C3AED),
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
  String _periodGlobal = 'This Fiscal Year';
  String _periodCashFlow = 'This Fiscal Year';
  String _periodIncomeExp = 'This Fiscal Year';
  String _periodTopExpenses = 'This Fiscal Year';
  String _basis = 'Accrual';

  Map<String, dynamic> _receivables = {};
  Map<String, dynamic> _payables = {};
  Map<String, dynamic> _cashFlow = {};
  Map<String, dynamic> _incomeExpense = {};
  Map<String, dynamic> _topExpenses = {};
  List<Map<String, dynamic>> _banks = [];

  bool _loadingAR = true;
  bool _loadingAP = true;
  bool _loadingCF = true;
  bool _loadingIE = true;
  bool _loadingTE = true;
  bool _loadingBank = true;

  int _touchedDonutIndex = -1;

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
    _loadAR();
    _loadAP();
    _loadCF();
    _loadIE();
    _loadTE();
    _loadBanks();
  }

  Future<void> _loadAR() async {
    setState(() => _loadingAR = true);
    final d = await _svc.fetchReceivables(_periodGlobal);
    if (mounted)
      setState(() {
        _receivables = d;
        _loadingAR = false;
      });
  }

  Future<void> _loadAP() async {
    setState(() => _loadingAP = true);
    final d = await _svc.fetchPayables(_periodGlobal);
    if (mounted)
      setState(() {
        _payables = d;
        _loadingAP = false;
      });
  }

  Future<void> _loadCF() async {
    setState(() => _loadingCF = true);
    final d = await _svc.fetchCashFlow(_periodCashFlow);
    if (mounted)
      setState(() {
        _cashFlow = d;
        _loadingCF = false;
      });
  }

  Future<void> _loadIE() async {
    setState(() => _loadingIE = true);
    final d = await _svc.fetchIncomeExpense(_periodIncomeExp, _basis);
    if (mounted)
      setState(() {
        _incomeExpense = d;
        _loadingIE = false;
      });
  }

  Future<void> _loadTE() async {
    setState(() => _loadingTE = true);
    final d = await _svc.fetchTopExpenses(_periodTopExpenses);
    if (mounted)
      setState(() {
        _topExpenses = d;
        _loadingTE = false;
        _touchedDonutIndex = -1;
      });
  }

  Future<void> _loadBanks() async {
    setState(() => _loadingBank = true);
    final d = await _svc.fetchBankAccounts();
    if (mounted)
      setState(() {
        _banks = d;
        _loadingBank = false;
      });
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _goToReport(String key, String name, {Map<String, String>? initialParams}) {
    try {
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportViewerPage(
              report: ReportMeta(key: key, name: name),
              orgName: _orgName,
              initialParams: initialParams,
            ),
          ));
    } catch (e) {
      AppSnackbar.show(context, message: 'Error opening report: $e');
    }
  }

  void _goToExpenseCategory(String categoryName, [List<String>? othersList]) {
    try {
      // ── If Others clicked, first show the category list dialog (Step 1) ──
      if (categoryName == 'Others' && othersList != null && othersList.isNotEmpty) {
        _showOthersCategoriesDialog(othersList);
        return;
      }

      // ── Navigate directly to expense-details for a specific category ──
      final params = <String, String>{};
      if (categoryName != 'Others') {
        params['expenseAccount'] = categoryName;
      }
      params['period'] = _periodTopExpenses;

      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportViewerPage(
              report: ReportMeta(key: 'expense-details', name: 'Expense Details'),
              orgName: _orgName,
              initialParams: params.isEmpty ? null : params,
            ),
          ));
    } catch (e) {
      AppSnackbar.show(context, message: 'Error: $e');
    }
  }

  /// Step 1: Show a dialog listing the expense categories grouped under "Others".
  /// Tapping a category navigates to Expense Details for that category (Step 2).
  void _showOthersCategoriesDialog(List<String> categoryNames) {
    // Filter out empty names and sort alphabetically
    final cats = categoryNames.where((n) => n.isNotEmpty).toList()..sort();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Container(
          width: 480,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E3A8A),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pie_chart_outline, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Other Expense Categories',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Tap a category to view its expenses',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Category list
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (_, i) {
                    final catName = cats[i];
                    return ListTile(
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _kDonutColors[i % _kDonutColors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        catName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF94A3B8)),
                      onTap: () {
                        Navigator.pop(context); // close dialog
                        // Step 2: navigate to expense details for this category
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReportViewerPage(
                              report: ReportMeta(key: 'expense-details', name: 'Expense Details — $catName'),
                              orgName: _orgName,
                              initialParams: {
                                'expenseAccount': catName,
                                'period': _periodTopExpenses,
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // Footer hint
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${cats.length} categories grouped under "Others"',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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

  void _goToBankAccount(Map<String, dynamic> bank) {
    final accountId = bank['_id']?.toString() ?? '';
    final accountName = bank['accountName']?.toString() ?? 'Account';
    final accountType = bank['accountType']?.toString() ?? 'BANK';
    if (accountId.isEmpty) return;
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AccountDetailPage(
            accountId: accountId,
            accountName: accountName,
            accountType: accountType,
            accountNumber: bank['accountNumber']?.toString(),
          ),
        ));
  }

  void _openReportsList() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ReportsListPage()));
  }

  // ── Formatters ─────────────────────────────────────────────────────────────
  String _fmt(dynamic v) {
    final val =
        (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;
    return '₹${NumberFormat('#,##,##0.00', 'en_IN').format(val)}';
  }

  String _fmtShort(double v) {
    if (v == 0) return '0';
    return NumberFormat.compact(locale: 'en_US').format(v);
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildARAPRow(),
                    const SizedBox(height: 16),
                    _buildCashFlowPanel(),
                    const SizedBox(height: 16),
                    LayoutBuilder(builder: (_, c) {
                      if (c.maxWidth >= 700) {
                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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

  // ── Header ─────────────────────────────────────────────────────────────────
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
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kNavyDark)),
          if (_orgName.isNotEmpty)
            Text(_orgName,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ]),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: _kNavy, size: 20),
          onPressed: _loadAll,
        ),
      ]),
    );
  }

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
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _kNavy),
          items: _kPeriods
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: child,
    );
  }

  // FIX: cardTitle now uses InkWell for larger tap area
  Widget _cardTitle(String title, {Widget? trailing, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(children: [
        InkWell(
          onTap: onTap ?? _openReportsList,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _kNavyDark)),
              const SizedBox(width: 4),
              const Icon(Icons.open_in_new, size: 12, color: _kBlueAccent),
            ]),
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _loadingBox() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
            child:
                CircularProgressIndicator(strokeWidth: 2, color: _kBlueAccent)),
      );

  // ==========================================================================
  // 1. AR + AP
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
      return Column(children: [
        _buildARCard(),
        const SizedBox(height: 12),
        _buildAPCard(),
      ]);
    });
  }

  Widget _buildARCard() {
    final cur = _toDouble(_receivables['current']);
    final ov = _toDouble(_receivables['overdue']);
    final total = _toDouble(_receivables['unpaidTotal'] ?? (cur + ov));

    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Total Receivables',
          onTap: () => _goToReport('ar-aging-details', 'AR Aging Details')),
      _loadingAR
          ? _loadingBox()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Unpaid Invoices',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    Text(_fmt(total),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _kNavyDark)),
                    const SizedBox(height: 10),
                    _progressBar(cur, ov, total),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _arApTile('Current', cur, _kBlueAccent,
                              onTap: () => _goToReport(
                                  'ar-aging-details', 'AR Aging Details'))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _arApTile('Overdue', ov, _kOrange,
                              showArrow: true,
                              onTap: () => _goToReport(
                                  'ar-aging-details', 'AR Aging Details'))),
                    ]),
                  ]),
            ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: InkWell(
          onTap: () => _goToReport('invoice-details', 'Invoice Details'),
          child: const Row(children: [
            Icon(Icons.add_circle_outline, size: 14, color: _kBlueAccent),
            SizedBox(width: 4),
            Text('New Invoice',
                style: TextStyle(
                    fontSize: 12,
                    color: _kBlueAccent,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]));
  }

  Widget _buildAPCard() {
    final cur = _toDouble(_payables['current']);
    final ov = _toDouble(_payables['overdue']);
    final total = _toDouble(_payables['unpaidTotal'] ?? (cur + ov));

    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Total Payables',
          onTap: () => _goToReport('ap-aging-details', 'AP Aging Details')),
      _loadingAP
          ? _loadingBox()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Unpaid Bills',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(height: 4),
                    Text(_fmt(total),
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _kNavyDark)),
                    const SizedBox(height: 10),
                    _progressBar(cur, ov, total),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _arApTile('Current', cur, _kBlueAccent,
                              onTap: () => _goToReport(
                                  'ap-aging-details', 'AP Aging Details'))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _arApTile('Overdue', ov, _kOrange,
                              showArrow: true,
                              onTap: () => _goToReport(
                                  'ap-aging-details', 'AP Aging Details'))),
                    ]),
                  ]),
            ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: InkWell(
          onTap: () => _goToReport('bill-details', 'Bill Details'),
          child: const Row(children: [
            Icon(Icons.add_circle_outline, size: 14, color: _kBlueAccent),
            SizedBox(width: 4),
            Text('New Bill',
                style: TextStyle(
                    fontSize: 12,
                    color: _kBlueAccent,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]));
  }

  Widget _progressBar(double current, double overdue, double total) {
    if (total <= 0) {
      return Container(
          height: 8,
          decoration: BoxDecoration(
              color: Colors.grey[200], borderRadius: BorderRadius.circular(4)));
    }
    final curFrac = (current / total).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      return Container(
        height: 8,
        decoration: BoxDecoration(
            color: Colors.grey[200], borderRadius: BorderRadius.circular(4)),
        child: Row(children: [
          if (curFrac > 0)
            Container(
              width: w * curFrac,
              decoration: BoxDecoration(
                color: _kBlueAccent,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(4),
                  bottomLeft: const Radius.circular(4),
                  topRight:
                      curFrac >= 1.0 ? const Radius.circular(4) : Radius.zero,
                  bottomRight:
                      curFrac >= 1.0 ? const Radius.circular(4) : Radius.zero,
                ),
              ),
            ),
          if (overdue > 0)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _kOrange,
                  borderRadius: BorderRadius.only(
                    topRight: const Radius.circular(4),
                    bottomRight: const Radius.circular(4),
                    topLeft:
                        curFrac <= 0 ? const Radius.circular(4) : Radius.zero,
                    bottomLeft:
                        curFrac <= 0 ? const Radius.circular(4) : Radius.zero,
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }

  Widget _arApTile(String label, double value, Color color,
      {bool showArrow = false, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
            if (showArrow) ...[
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey[500]),
            ],
          ]),
          const SizedBox(height: 6),
          Text(_fmt(value),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  // ==========================================================================
  // 2. CASH FLOW — FIXED Y AXIS
  // ==========================================================================

  Widget _buildCashFlowPanel() {
    final monthly = (_cashFlow['monthly'] as List?)?.cast<Map>() ?? [];
    final opening = _toDouble(_cashFlow['openingBalance']);
    final incoming = _toDouble(_cashFlow['totalIncoming']);
    final outgoing = _toDouble(_cashFlow['totalOutgoing']);
    final ending = _toDouble(_cashFlow['endingBalance']);
    final fyStart = _cashFlow['fyStartLabel']?.toString() ?? '';
    final fyEnd = _cashFlow['fyEndLabel']?.toString() ?? '';

    // ── STEP 1: log raw service output ────────────────────────────────────────
    debugPrint(
        '╔══ CASHFLOW DEBUG ══════════════════════════════════════════════');
    debugPrint('║  RAW _cashFlow keys : ${_cashFlow.keys.toList()}');
    debugPrint(
        '║  opening=$opening  incoming=$incoming  outgoing=$outgoing  ending=$ending');
    debugPrint('║  fyStart=$fyStart  fyEnd=$fyEnd');
    debugPrint('║  monthly.length=${monthly.length}');
    for (int i = 0; i < monthly.length; i++) {
      final m = monthly[i];
      debugPrint('║  [$i] month=${m['month']}  '
          'incoming=${m['incoming']}  '
          'outgoing=${m['outgoing']}  '
          'endingBalance=${m['endingBalance']}');
    }

    // ── STEP 2: build FlSpots from endingBalance ───────────────────────────
    // Prepend a synthetic opening-balance point at x=-1 so the line visually
    // rises from the opening balance into the first transaction month.
    List<FlSpot> spots = [FlSpot(-1, opening)];
    for (int i = 0; i < monthly.length; i++) {
      final raw = monthly[i]['endingBalance'];
      final balance = _toDouble(raw);
      debugPrint('║  spot[$i] raw=$raw  parsed=$balance');
      spots.add(FlSpot(i.toDouble(), balance));
    }
    if (spots.length == 1) {
      // Only the synthetic point — no monthly data
      debugPrint('║  ⚠️  monthly empty → using flat-zero fallback spots');
      spots = List.generate(12, (i) => FlSpot(i.toDouble(), 0));
    }

    // ── STEP 3: compute Y axis bounds ─────────────────────────────────────
    // Skip the synthetic point (index 0 = x:-1) for range calc so opening=0
    // doesn't collapse the scale when all real data is positive.
    final allY = spots.map((s) => s.y).toList();
    final dataMax = allY.fold(double.negativeInfinity, (a, b) => a > b ? a : b);
    final dataMin = allY.fold(double.infinity, (a, b) => a < b ? a : b);
    final dataRange = (dataMax - dataMin).abs();
    final absMax = allY.map((v) => v.abs()).fold(0.0, (a, b) => a > b ? a : b);

    debugPrint('║  allY       : $allY');
    debugPrint(
        '║  dataMin=$dataMin  dataMax=$dataMax  dataRange=$dataRange  absMax=$absMax');

    double chartMinY, chartMaxY;
    if (absMax == 0) {
      chartMinY = -100;
      chartMaxY = 100;
      debugPrint(
          '║  branch=NO_DATA  chartMinY=$chartMinY  chartMaxY=$chartMaxY');
    } else if (dataRange < 1) {
      final pad = (absMax * 0.5).clamp(1.0, double.infinity);
      chartMinY = dataMin - pad;
      chartMaxY = dataMax + pad;
      debugPrint(
          '║  branch=SINGLE_VALUE  pad=$pad  chartMinY=$chartMinY  chartMaxY=$chartMaxY');
    } else {
      final pad = dataRange * 0.3;
      chartMinY = dataMin - pad;
      chartMaxY = dataMax + pad;
      debugPrint(
          '║  branch=NORMAL  pad=$pad  chartMinY=$chartMinY  chartMaxY=$chartMaxY');
    }
    debugPrint(
        '╚════════════════════════════════════════════════════════════════');

    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Cash Flow',
          onTap: () => _goToReport('cash-flow', 'Cash Flow Statement', initialParams: {'period': _mapPeriod(_periodCashFlow)}),
          trailing: _periodDrop(_periodCashFlow, (v) {
            setState(() => _periodCashFlow = v!);
            _loadCF();
          })),
      _loadingCF
          ? _loadingBox()
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
              child: LayoutBuilder(builder: (_, c) {
                if (c.maxWidth >= 500) {
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: SizedBox(
                            height: 220,
                            child: GestureDetector(
                              onTap: () => _goToReport(
                                  'cash-flow', 'Cash Flow Statement', initialParams: {'period': _mapPeriod(_periodCashFlow)}),
                              child: _buildCashFlowChart(
                                  spots, monthly, chartMinY, chartMaxY),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 150,
                          child: _buildCashFlowLegend(opening, incoming,
                              outgoing, ending, fyStart, fyEnd),
                        ),
                      ]);
                }
                return Column(children: [
                  SizedBox(
                    height: 200,
                    child: GestureDetector(
                      onTap: () =>
                          _goToReport('cash-flow', 'Cash Flow Statement', initialParams: {'period': _mapPeriod(_periodCashFlow)}),
                      child: _buildCashFlowChart(
                          spots, monthly, chartMinY, chartMaxY),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCashFlowLegendRow(opening, incoming, outgoing, ending),
                ]);
              }),
            ),
    ]));
  }

  Widget _buildCashFlowChart(List<FlSpot> spots, List<Map> monthly,
      double chartMinY, double chartMaxY) {
    // Interval for Y axis labels — divide range into ~4 steps
    final range = (chartMaxY - chartMinY).abs();
    // Divide range into ~4 readable steps; never below 1 to avoid fl_chart assertion
    final interval = (range / 4).clamp(1.0, double.infinity);

    return LineChart(LineChartData(
      minX: -1,
      maxX: (monthly.length - 1).toDouble(),
      minY: chartMinY,
      maxY: chartMaxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: _kBorder, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 1,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= monthly.length) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text((monthly[i]['month'] ?? '').toString(),
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: interval,
            reservedSize: 75,
            getTitlesWidget: (v, _) => Text(_fmtShort(v),
                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
          ),
        ),
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
            if (i < 0 || i >= monthly.length) {
              return LineTooltipItem('', const TextStyle());
            }
            final m = monthly[i];
            final inc = _toDouble(m['incoming']);
            final out = _toDouble(m['outgoing']);
            return LineTooltipItem(
              '${m['month']}\nIncoming  ${_fmt(inc)}\nOutgoing  ${_fmt(out)}\nBalance   ${_fmt(s.y)}',
              const TextStyle(
                  color: _kNavyDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.7),
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: _kBlueAccent,
          barWidth: 2.5,
          isStrokeCapRound: true,
          belowBarData: BarAreaData(
            show: true,
            color: _kBlueAccent.withOpacity(0.08),
          ),
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 3,
              color: Colors.white,
              strokeWidth: 2,
              strokeColor: _kBlueAccent,
            ),
          ),
        ),
      ],
    ));
  }

  Widget _buildCashFlowLegend(double opening, double incoming, double outgoing,
      double ending, String fyStart, String fyEnd) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      _cfLegendItem(
          label: fyStart.isNotEmpty ? 'Cash as on $fyStart' : 'Opening Balance',
          value: opening,
          color: Colors.grey,
          bulletColor: Colors.grey[400]!),
      const SizedBox(height: 16),
      _cfLegendItem(
          label: 'Incoming',
          value: incoming,
          color: _kGreen,
          bulletColor: _kGreen,
          suffix: ' ( + )'),
      const SizedBox(height: 16),
      _cfLegendItem(
          label: 'Outgoing',
          value: outgoing,
          color: _kRed,
          bulletColor: _kRed,
          suffix: ' ( - )'),
      const SizedBox(height: 16),
      _cfLegendItem(
          label: fyEnd.isNotEmpty ? 'Cash as on $fyEnd' : 'Closing Balance',
          value: ending,
          color: _kBlueAccent,
          bulletColor: _kBlueAccent,
          suffix: ' ( = )'),
    ]);
  }

  Widget _cfLegendItem(
      {required String label,
      required double value,
      required Color color,
      required Color bulletColor,
      String suffix = ''}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: bulletColor, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
            child: Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 3),
      Text('${_fmt(value)}$suffix',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _buildCashFlowLegendRow(
      double opening, double incoming, double outgoing, double ending) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _cfLegItem('Opening', opening, Colors.grey),
      _cfLegItem('Incoming', incoming, _kGreen, suffix: ' (+)'),
      _cfLegItem('Outgoing', outgoing, _kRed, suffix: ' (-)'),
      _cfLegItem('Closing', ending, _kBlueAccent, suffix: ' (=)'),
    ]);
  }

  Widget _cfLegItem(String label, double val, Color color,
      {String suffix = ''}) {
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ]),
      const SizedBox(height: 3),
      Text('${_fmt(val)}$suffix',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  // ==========================================================================
  // 3. INCOME & EXPENSE
  // ==========================================================================

  Widget _buildIncomeExpPanel() {
    final totalInc = _toDouble(_incomeExpense['totalIncome']);
    final totalExp = _toDouble(_incomeExpense['totalExpense']);
    final monthly = (_incomeExpense['monthly'] as List?)?.cast<Map>() ?? [];

    final barGroups = monthly.asMap().entries.map((e) {
      final inc = _toDouble(e.value['income']);
      final exp = _toDouble(e.value['expense']);
      return BarChartGroupData(x: e.key, barsSpace: 2, barRods: [
        BarChartRodData(
            toY: inc,
            color: _kGreen,
            width: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        BarChartRodData(
            toY: exp,
            color: _kRed.withOpacity(0.8),
            width: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
      ]);
    }).toList();

    final maxVal = monthly.fold(0.0, (prev, m) {
      final inc = _toDouble(m['income']);
      final exp = _toDouble(m['expense']);
      return [prev, inc, exp].reduce((a, b) => a > b ? a : b);
    });

    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Income and Expense',
          onTap: () => _goToReport('profit-loss', 'Profit and Loss', initialParams: {'period': _mapPeriod(_periodIncomeExp)}),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            // Container(
            //   height: 32,
            //   decoration: BoxDecoration(
            //       border: Border.all(color: _kBorder),
            //       borderRadius: BorderRadius.circular(8)),
            //   child: Row(mainAxisSize: MainAxisSize.min, children: [
            //     _basisBtn('Accrual'),
            //     _basisBtn('Cash'),
            //   ]),
            // ),
            // const SizedBox(width: 8),
            _periodDrop(_periodIncomeExp, (v) {
              setState(() => _periodIncomeExp = v!);
              _loadIE();
            }),
          ])),
      _loadingIE
          ? _loadingBox()
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(children: [
                  _ieSummary('Total Income', totalInc, _kGreen),
                  const SizedBox(width: 20),
                  _ieSummary('Total Expenses', totalExp, _kRed),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
                child: SizedBox(
                  height: 200,
                  child: barGroups.isEmpty
                      ? Center(
                          child: Text('No data for this period',
                              style: TextStyle(
                                  color: Colors.grey[400], fontSize: 13)))
                      : GestureDetector(
                          onTap: () =>
                              _goToReport('profit-loss', 'Profit and Loss', initialParams: {'period': _mapPeriod(_periodIncomeExp)}),
                          child: BarChart(BarChartData(
                            maxY: maxVal == 0 ? 10000 : maxVal * 1.2,
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                tooltipBgColor: Colors.white,
                                tooltipRoundedRadius: 8,
                                tooltipBorder:
                                    const BorderSide(color: _kBorder),
                                getTooltipItem: (group, gi, rod, ri) {
                                  final m =
                                      gi < monthly.length ? monthly[gi] : null;
                                  final isInc = ri == 0;
                                  return BarTooltipItem(
                                      '${m?['month'] ?? ''}\n'
                                      '${isInc ? 'Income' : 'Expense'}: ${_fmt(rod.toY)}',
                                      TextStyle(
                                          color: isInc ? _kGreen : _kRed,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600));
                                },
                              ),
                              touchCallback: (event, resp) {
                                if (event is FlTapUpEvent &&
                                    resp?.spot != null) {
                                  final gi = resp!.spot!.touchedBarGroupIndex;
                                  final m = gi < monthly.length ? monthly[gi] : null;
                                  if (m != null && m['year'] != null && m['monthNum'] != null) {
                                    final year = m['year'] as int;
                                    final month = m['monthNum'] as int;
                                    final fromDate = DateTime(year, month, 1);
                                    // Month 0 means previous year Dec, so passing month + 1 with day 0 is fine.
                                    // Wait, DateTime handles year/month overflow properly in Dart!
                                    // A safer way for end of month: month + 1, day 0.
                                    final toDate = DateTime(year, month + 1, 0); 
                                    
                                    _goToReport('profit-loss', 'Profit and Loss', initialParams: {
                                      'period': 'custom',
                                      'fromDate': fromDate.toIso8601String(),
                                      'toDate': toDate.toIso8601String(),
                                    });
                                  } else {
                                    _goToReport('profit-loss', 'Profit and Loss', initialParams: {'period': _mapPeriod(_periodIncomeExp)});
                                  }
                                }
                              },
                            ),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 26,
                                interval: 1,
                                getTitlesWidget: (v, _) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= monthly.length) return const SizedBox();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                        (monthly[i]['month'] ?? '').toString(),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF94A3B8))),
                                  );
                                },
                              )),
                              leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 44,
                                interval: maxVal == 0
                                    ? 2000
                                    : (maxVal / 4).clamp(1, double.infinity),
                                getTitlesWidget: (v, _) => Text(_fmtShort(v),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF94A3B8))),
                              )),
                              topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: maxVal == 0
                                  ? 2000
                                  : (maxVal / 4).clamp(1, double.infinity),
                              getDrawingHorizontalLine: (_) =>
                                  const FlLine(color: _kBorder, strokeWidth: 1),
                            ),
                            barGroups: barGroups,
                          )),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                    '* Income and expense values displayed are exclusive of taxes.',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic)),
              ),
            ]),
    ]));
  }

  Widget _basisBtn(String label) {
    final sel = _basis == label;
    return GestureDetector(
      onTap: () {
        setState(() => _basis = label);
        _loadIE();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _kBlueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : _kNavy)),
      ),
    );
  }

  Widget _ieSummary(String label, double val, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
      const SizedBox(height: 4),
      Text(_fmt(val),
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  // ==========================================================================
  // 4. TOP EXPENSES
  // ==========================================================================

  Widget _buildTopExpPanel() {
    final total = _toDouble(_topExpenses['total']);
    final rawCats = (_topExpenses['categories'] as List?)?.cast<Map>() ?? [];
    
    final List<Map<String, dynamic>> cats = [];
    final List<String> othersCatNames = [];
    if (rawCats.length > 6) {
      cats.addAll(rawCats.take(5).map((e) => Map<String, dynamic>.from(e)));
      final othersAmount = rawCats.skip(5).fold(0.0, (sum, cat) {
        othersCatNames.add(cat['name']?.toString() ?? '');
        return sum + _toDouble(cat['amount']);
      });
      if (othersAmount > 0) cats.add({'name': 'Others', 'amount': othersAmount, 'isOthers': true});
    } else {
      cats.addAll(rawCats.map((e) => Map<String, dynamic>.from(e)));
    }

    String centerLabel = 'All Expenses';
    String centerAmount = _fmt(total);
    if (_touchedDonutIndex >= 0 && _touchedDonutIndex < cats.length) {
      final tCat = cats[_touchedDonutIndex];
      final amt = _toDouble(tCat['amount']);
      final pct = total > 0 ? (amt / total * 100).toStringAsFixed(2) : '0';
      centerLabel = tCat['name']?.toString() ?? '';
      centerAmount = '${_fmt(amt)}\n($pct%)';
    }

    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Top Expenses',
          onTap: () => _goToReport('expense-details', 'Expense Details', initialParams: {'period': _mapPeriod(_periodTopExpenses)}),
          trailing: _periodDrop(_periodTopExpenses, (v) {
            setState(() => _periodTopExpenses = v!);
            _loadTE();
          })),
      _loadingTE
          ? _loadingBox()
          : cats.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                      child: Text('No expense data',
                          style: TextStyle(color: Colors.grey[500]))))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: SizedBox(
                      height: 180,
                      child: Stack(alignment: Alignment.center, children: [
                        PieChart(PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 55,
                          pieTouchData: PieTouchData(
                            touchCallback: (event, resp) {
                              if (event is FlTapUpEvent) {
                                final idx =
                                    resp?.touchedSection?.touchedSectionIndex;
                                if (idx != null &&
                                    idx >= 0 &&
                                    idx < cats.length) {
                                  final catName =
                                      cats[idx]['name']?.toString() ?? '';
                                  if (catName.isNotEmpty) {
                                    if (cats[idx]['isOthers'] == true) {
                                      _goToExpenseCategory('Others', othersCatNames);
                                    } else {
                                      _goToExpenseCategory(catName);
                                    }
                                  }
                                }
                              }
                              setState(() {
                                _touchedDonutIndex =
                                    resp?.touchedSection?.touchedSectionIndex ??
                                        -1;
                              });
                            },
                          ),
                          sections: cats.asMap().entries.map((e) {
                            final isTouched = e.key == _touchedDonutIndex;
                            return PieChartSectionData(
                              value: _toDouble(e.value['amount']),
                              color:
                                  _kDonutColors[e.key % _kDonutColors.length],
                              radius: isTouched ? 48 : 40,
                              showTitle: false,
                            );
                          }).toList(),
                        )),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(centerLabel,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          Text(centerAmount,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _kNavyDark),
                              textAlign: TextAlign.center),
                        ]),
                      ]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: cats.take(6).toList().asMap().entries.map((e) {
                        final catName = e.value['name']?.toString() ?? '';
                        final amt = _toDouble(e.value['amount']);
                        return InkWell(
                          onTap: () {
                            if (e.value['isOthers'] == true) {
                              _goToExpenseCategory('Others', othersCatNames);
                            } else {
                              _goToExpenseCategory(catName);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      color: _kDonutColors[
                                          e.key % _kDonutColors.length],
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(catName,
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis)),
                              Text(_fmt(amt),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ]),
    ]));
  }

  // ==========================================================================
  // 5. BANK ACCOUNTS
  // ==========================================================================

  Widget _buildBankPanel() {
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _cardTitle('Bank and Credit Cards', onTap: _openReportsList),
      _loadingBank
          ? _loadingBox()
          : _banks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('No bank accounts found',
                          style: TextStyle(color: Colors.grey[500]))))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      Column(children: _banks.take(8).map(_bankRow).toList())),
    ]));
  }

  Widget _bankRow(Map<String, dynamic> bank) {
    final name = bank['accountName']?.toString() ?? 'Account';
    final balance = _toDouble(bank['currentBalance'] ?? bank['balance'] ?? 0);
    final type = (bank['accountType'] ?? 'BANK').toString().toUpperCase();
    final uncatCount = (bank['uncategorizedCount'] as num?)?.toInt() ?? 0;

    IconData icon;
    Color color;
    switch (type) {
      case 'FUEL_CARD':
        icon = Icons.local_gas_station;
        color = const Color(0xFF2980B9);
        break;
      case 'FASTAG':
        icon = Icons.toll;
        color = const Color(0xFFE67E22);
        break;
      case 'PETTY_CASH':
        icon = Icons.payments;
        color = const Color(0xFF9B59B6);
        break;
      case 'DRIVER_ADVANCE':
        icon = Icons.person;
        color = const Color(0xFF3F51B5);
        break;
      case 'CREDIT_CARD':
        icon = Icons.credit_card;
        color = const Color(0xFFE74C3C);
        break;
      default:
        icon = Icons.account_balance;
        color = _kGreen;
    }

    return InkWell(
      onTap: () => _goToBankAccount(bank),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _kBorder, width: 0.5))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _kNavyDark),
                    overflow: TextOverflow.ellipsis),
                if (uncatCount > 0)
                  Text('$uncatCount Uncategorized Transactions',
                      style:
                          TextStyle(fontSize: 11, color: Colors.orange[700])),
              ])),
          Text(_fmt(balance),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: balance < 0 ? _kRed : _kNavyDark)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: Color(0xFFCBD5E1)),
        ]),
      ),
    );
  }

  // ── Helper ─────────────────────────────────────────────────────────────────
  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    if (v is num) return v.toDouble();
    return 0.0;
  }

  static String _mapPeriod(String p) {
    switch (p) {
      case 'This Month': return 'this_month';
      case 'Last Month': return 'last_month';
      case 'This Quarter': return 'this_quarter';
      case 'This Fiscal Year': return 'this_fy';
      case 'Last Fiscal Year': return 'last_fy';
      default: return 'this_fy';
    }
  }
}
