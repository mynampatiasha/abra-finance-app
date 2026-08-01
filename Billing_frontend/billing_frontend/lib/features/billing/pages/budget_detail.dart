import 'package:abra_finance/core/utils/app_snackbar.dart';
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

const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
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
  DateTime? _startDate;
  DateTime? _endDate;

  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  static const _monthLabels = [
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
    'Jan',
    'Feb',
    'Mar'
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final b = await BudgetService.getBudgetWithActuals(
        widget.budgetId,
        startDate: _startDate?.toIso8601String(),
        endDate: _endDate?.toIso8601String(),
      );
      setState(() {
        _budget = b;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _goEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => NewBudgetScreen(budgetId: widget.budgetId)),
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
    AppSnackbar.show(context, message: msg);
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

  Widget _buildError() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
        const SizedBox(height: 16),
        Text('Failed to load',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Text(_error ?? '', style: TextStyle(color: Colors.grey.shade500)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent, foregroundColor: Colors.white)),
      ]));

  Widget _buildBody() {
    final b = _budget!;
    return SingleChildScrollView(
      controller: _vScroll,
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(b),
        const Divider(height: 1, color: Color(0xFFE0E0E0)),
        _buildFilterBar(),
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
          final info =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(colors: [_navyDark, _navyLight]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(b.budgetName,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _navyDark)),
                    const SizedBox(height: 4),
                    Text(
                        '${b.financialYear}  •  ${b.budgetPeriod}  •  ${b.currency}',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ])),
              _badge(
                  b.isActive ? 'Active' : 'Inactive',
                  b.isActive ? Colors.green.shade100 : Colors.grey.shade200,
                  b.isActive ? Colors.green.shade700 : Colors.grey.shade600),
            ]),
            if (b.notes != null && b.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(b.notes!,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ]);
          return info;
        }),
      );

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.filter_list, color: Colors.grey, size: 20),
          const SizedBox(width: 12),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _startDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 14, color: _navyDark),
                const SizedBox(width: 8),
                Text(
                    _startDate != null
                        ? DateFormat('dd MMM yyyy').format(_startDate!)
                        : 'Start Date',
                    style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          const Text('-', style: TextStyle(color: Colors.grey)),
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _endDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _endDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 14, color: _navyDark),
                const SizedBox(width: 8),
                Text(
                    _endDate != null
                        ? DateFormat('dd MMM yyyy').format(_endDate!)
                        : 'End Date',
                    style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              if (_startDate != null && _endDate != null) {
                _load();
              } else if (_startDate == null && _endDate == null) {
                _load();
              } else {
                _snack('Please select both Start and End dates', Colors.orange);
              }
            },
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Apply', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0)),
          ),
          if (_startDate != null || _endDate != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
                _load();
              },
              icon: const Icon(Icons.clear, size: 14),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  // ── Summary Cards ─────────────────────────────────────────────────────────

  Widget _buildSummaryCards(Budget b) {
    // Fix floating point precision errors
    final varianceRaw = b.totalBudgeted - b.totalActual;
    final variance = double.parse(varianceRaw.toStringAsFixed(2));
    final pctUsedRaw =
        b.totalBudgeted > 0 ? (b.totalActual / b.totalBudgeted * 100) : 0.0;
    final pctUsed = double.parse(pctUsedRaw.toStringAsFixed(2));
    final overBudget = variance < 0;

    final cards = [
      _CardData('Total Budgeted', '₹${_fmt(b.totalBudgeted)}',
          Icons.account_balance_wallet_outlined, Colors.blue),
      _CardData('Total Actual', '₹${_fmt(b.totalActual)}',
          Icons.receipt_long_outlined, Colors.teal),
      _CardData(
          'Variance',
          '${overBudget ? '-' : ''}₹${_fmt(variance.abs())}',
          Icons.swap_vert_circle_outlined,
          overBudget ? Colors.red : Colors.green),
      _CardData(
          '% Utilised',
          '${pctUsed.toStringAsFixed(1)}%',
          Icons.pie_chart_outline,
          pctUsed > 100
              ? Colors.red
              : pctUsed > 80
                  ? Colors.orange
                  : Colors.green),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 1),
      child: LayoutBuilder(builder: (_, cs) {
        if (cs.maxWidth < 600) {
          return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map((c) => SizedBox(
                      width: (cs.maxWidth - 12) / 2, child: _summCard(c)))
                  .toList());
        }
        return Row(
            children: cards
                .map((c) => Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _summCard(c))))
                .toList());
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
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(c.label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(c.value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: c.color),
                    overflow: TextOverflow.ellipsis),
              ])),
        ]),
      );

  // ── Comparison Table ──────────────────────────────────────────────────────

  Widget _buildComparisonTable(Budget b) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_navyDark, _navyMid]),
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8), topRight: Radius.circular(8)),
            ),
            child: Row(children: [
              const Icon(Icons.compare_arrows, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Budget vs Actual Comparison',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15))),
              Text('${b.accountLines.length} accounts',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          LayoutBuilder(builder: (context, constraints) {
            return Scrollbar(
              controller: _hScroll,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 6,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad
                  },
                ),
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor:
                          WidgetStateProperty.all(const Color(0xFFF0F4FF)),
                      headingTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _navyDark,
                          letterSpacing: 0.4),
                      headingRowHeight: 44,
                      dataRowMinHeight: 56,
                      dataTextStyle:
                          const TextStyle(fontSize: 14, color: _navyDark),
                      dividerThickness: 0.8,
                      columnSpacing: 24,
                      horizontalMargin: 16,
                      columns: const [
                        DataColumn(
                            label:
                                SizedBox(width: 200, child: Text('ACCOUNT'))),
                        DataColumn(
                            label: SizedBox(width: 100, child: Text('TYPE'))),
                        DataColumn(
                            label: SizedBox(
                                width: 120,
                                child: Text('BUDGETED',
                                    textAlign: TextAlign.right)),
                            numeric: true),
                        DataColumn(
                            label: SizedBox(
                                width: 120,
                                child:
                                    Text('ACTUAL', textAlign: TextAlign.right)),
                            numeric: true),
                        DataColumn(
                            label: SizedBox(
                                width: 120,
                                child: Text('VARIANCE',
                                    textAlign: TextAlign.right)),
                            numeric: true),
                        DataColumn(
                            label: SizedBox(
                                width: 100,
                                child:
                                    Text('% USED', textAlign: TextAlign.right)),
                            numeric: true),
                        DataColumn(
                            label:
                                SizedBox(width: 150, child: Text('PROGRESS'))),
                      ],
                      rows: b.accountLines.map((line) {
                        final varianceRaw =
                            line.totalBudgeted - line.totalActual;
                        final variance =
                            double.parse(varianceRaw.toStringAsFixed(2));
                        final over = variance < 0;
                        final pct =
                            double.parse(line.percentUsed.toStringAsFixed(2));
                        return DataRow(cells: [
                          DataCell(Text(line.accountName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13))),
                          DataCell(Text(line.accountType,
                              style: const TextStyle(fontSize: 11))),
                          DataCell(Text('₹${_fmt(line.totalBudgeted)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                          DataCell(Text('₹${_fmt(line.totalActual)}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal.shade700))),
                          DataCell(Text(
                            '${over ? '-' : ''}₹${_fmt(variance.abs())}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    over ? Colors.red : Colors.green.shade700),
                          )),
                          DataCell(_pctBadge(pct)),
                          DataCell(
                              SizedBox(width: 150, child: _progressBar(pct))),
                        ]);
                      }).toList()
                        ..add(_totalRow(b)),
                    ),
                  ),
                ),
              ),
            );
          }),
        ]),
      );

  DataRow _totalRow(Budget b) {
    final varianceRaw = b.totalBudgeted - b.totalActual;
    final variance = double.parse(varianceRaw.toStringAsFixed(2));
    final pctRaw =
        b.totalBudgeted > 0 ? b.totalActual / b.totalBudgeted * 100 : 0.0;
    final pct = double.parse(pctRaw.toStringAsFixed(2));
    final over = variance < 0;
    return DataRow(
      color: WidgetStateProperty.all(const Color(0xFFF0F4FF)),
      cells: [
        const DataCell(Text('TOTAL',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: _navyDark))),
        const DataCell(Text('')),
        DataCell(Text('₹${_fmt(b.totalBudgeted)}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: _navyDark))),
        DataCell(Text('₹${_fmt(b.totalActual)}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.teal))),
        DataCell(Text(
          '${over ? '-' : ''}₹${_fmt(variance.abs())}',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: over ? Colors.red : Colors.green),
        )),
        DataCell(_pctBadge(pct)),
        DataCell(SizedBox(width: 150, child: _progressBar(pct))),
      ],
    );
  }

  // ── Monthly Breakdown ─────────────────────────────────────────────────────

  // Column widths
  static const double _acctColW = 220.0;
  static const double _monthColW = 130.0;
  static const double _annualColW = 150.0;

  Widget _buildMonthlyBreakdown(Budget b) {
    if (b.accountLines.isEmpty) return const SizedBox.shrink();

    final border = TableBorder.all(
      color: const Color(0xFFDDE3ED),
      width: 1,
    );
    const headerBg = Color(0xFF1A3A6B);
    const rowEven = Colors.white;
    const rowOdd = Color(0xFFF7F9FC);
    const totalBg = Color(0xFFEEF2FF);

    // Build header row
    TableRow _headerRow() => TableRow(
          decoration: const BoxDecoration(color: headerBg),
          children: [
            _thCell('ACCOUNT', align: TextAlign.left),
            ..._monthLabels.map((m) => _thCell(m)),
            _thCell('ANNUAL', align: TextAlign.right),
          ],
        );

    // Build data rows
    List<TableRow> _dataRows() => b.accountLines.asMap().entries.map((e) {
          final idx = e.key;
          final line = e.value;
          final bg = idx.isEven ? rowEven : rowOdd;
          return TableRow(
            decoration: BoxDecoration(color: bg),
            children: [
              // Account name cell
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: Container(
                  width: _acctColW,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Text(
                    line.accountName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _navyDark),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ),
              // 12 month cells
              ...List.generate(12, (m) {
                final budgRaw = m < line.monthlyAmounts.length
                    ? line.monthlyAmounts[m]
                    : 0.0;
                final actRaw = m < line.actualMonthly.length
                    ? line.actualMonthly[m]
                    : 0.0;
                final budg = double.parse(budgRaw.toStringAsFixed(2));
                final act = double.parse(actRaw.toStringAsFixed(2));
                final over = act > budg && budg > 0;
                return TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Container(
                    width: _monthColW,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _fmt(budg),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _navyDark),
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _fmt(act),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: over
                                  ? Colors.red.shade600
                                  : const Color(0xFF00796B)),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                );
              }),
              // Annual total cell
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.fill,
                child: Container(
                  width: _annualColW,
                  decoration: BoxDecoration(
                    color: idx.isEven ? const Color(0xFFEBF1F8) : const Color(0xFFE1E8F2),
                    border: const Border(
                      left: BorderSide(color: Color(0xFFC5D3E8), width: 1.5),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(line.totalBudgeted),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _navyDark),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fmt(line.totalActual),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00796B)),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList();

    // Build TOTAL row
    TableRow _totalRow() {
      final totalBudg = b.accountLines.fold(0.0, (s, l) => s + l.totalBudgeted);
      final totalAct = b.accountLines.fold(0.0, (s, l) => s + l.totalActual);
      final monthTotals = List.generate(12, (m) {
        final budg = b.accountLines.fold(
            0.0,
            (s, l) =>
                s +
                (m < l.monthlyAmounts.length ? l.monthlyAmounts[m] : 0.0));
        final act = b.accountLines.fold(
            0.0,
            (s, l) =>
                s + (m < l.actualMonthly.length ? l.actualMonthly[m] : 0.0));
        return (budg, act);
      });
      return TableRow(
        decoration: const BoxDecoration(color: totalBg),
        children: [
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: const Text('TOTAL',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _navyDark)),
            ),
          ),
          ...monthTotals.map((t) {
            final budg = double.parse(t.$1.toStringAsFixed(2));
            final act = double.parse(t.$2.toStringAsFixed(2));
            final over = act > budg && budg > 0;
            return TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt(budg),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _navyDark),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fmt(act),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: over
                              ? Colors.red.shade600
                              : const Color(0xFF00796B)),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
            );
          }),
          TableCell(
            verticalAlignment: TableCellVerticalAlignment.fill,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFD6E4F5),
                border: Border(
                  left: BorderSide(color: Color(0xFFB0C4DE), width: 1.5),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmt(totalBudg),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _navyDark),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fmt(totalAct),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00796B)),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final tableWidget = Table(
      border: border,
      defaultColumnWidth:
          const IntrinsicColumnWidth(),
      children: [
        _headerRow(),
        ..._dataRows(),
        _totalRow(),
      ],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [_navyMid, _navyLight]),
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8), topRight: Radius.circular(8)),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_month, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('Monthly Breakdown (Budgeted vs Actual)',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ]),
        ),
        Listener(
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              final offset = pointerSignal.scrollDelta.dy;
              if (offset != 0) {
                _hScroll.jumpTo(
                  (_hScroll.offset + offset).clamp(
                      0.0, _hScroll.position.maxScrollExtent),
                );
              }
            }
          },
          child: Scrollbar(
            controller: _hScroll,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 8,
            child: ScrollConfiguration(
              behavior: _MouseDragScrollBehavior(),
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: tableWidget,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: Color(0xFF00796B), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Actual', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 12),
            Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                    color: _navyDark, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Budgeted', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 12),
            Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: Colors.red.shade600, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Over budget', style: TextStyle(fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _pctBadge(double pct) {
    Color bg, fg;
    String icon;
    if (pct > 100) {
      bg = Colors.red.shade50;
      fg = Colors.red;
      icon = '🔴';
    } else if (pct > 80) {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade700;
      icon = '🟡';
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
      icon = '🟢';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('$icon ${pct.toStringAsFixed(1)}%',
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  Widget _progressBar(double pct) {
    final clamped = pct.clamp(0.0, 150.0);
    final fraction = (clamped / 150).clamp(0.0, 1.0);
    final color = pct > 100
        ? Colors.red
        : pct > 80
            ? Colors.orange
            : Colors.green;
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
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
      );

  Widget _legendDot(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);
  String _fmtShort(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Table header cell helper ─────────────────────────────────────────────────
Widget _thCell(String text, {TextAlign align = TextAlign.right}) => TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.4),
          textAlign: align,
        ),
      ),
    );

// ── Proper mouse-drag scroll behavior for Flutter web ────────────────────────
class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class _CardData {
  final String label, value;
  final IconData icon;
  final Color color;
  const _CardData(this.label, this.value, this.icon, this.color);
}
