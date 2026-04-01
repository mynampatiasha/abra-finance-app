// ============================================================================
// NEW BUDGET SCREEN
// ============================================================================
// File: lib/screens/billing/pages/new_budget.dart
// Navy blue gradient theme — same as new_vendor_credit.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/budget_service.dart';
import '../../../../core/services/chart_of_account_service.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

// ── Mutable account line for form ─────────────────────────────────────────────
class _MutableLine {
  String? accountId;
  String accountName;
  String accountType;
  List<TextEditingController> monthControllers;

  _MutableLine({
    this.accountId,
    this.accountName = '',
    this.accountType = 'Expense',
    List<double>? amounts,
  }) : monthControllers = List.generate(
          12,
          (i) => TextEditingController(
              text: amounts != null && amounts[i] > 0 ? amounts[i].toStringAsFixed(2) : ''),
        );

  void dispose() {
    for (final c in monthControllers) c.dispose();
  }

  List<double> get amounts =>
      monthControllers.map((c) => double.tryParse(c.text.replaceAll(',', '')) ?? 0).toList();

  double get total => amounts.reduce((a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'accountName': accountName,
        'accountType': accountType,
        'monthlyAmounts': amounts,
      };
}

// ============================================================================
// SCREEN
// ============================================================================

class NewBudgetScreen extends StatefulWidget {
  final String? budgetId;
  const NewBudgetScreen({Key? key, this.budgetId}) : super(key: key);

  @override
  State<NewBudgetScreen> createState() => _NewBudgetScreenState();
}

class _NewBudgetScreenState extends State<NewBudgetScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Form fields
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _financialYear = _defaultFY();
  String _budgetPeriod  = 'Monthly';
  String _currency      = 'INR';
  bool   _isActive      = true;

  // Account lines
  final List<_MutableLine> _lines = [];

  // COA accounts for dropdown
  List<ChartOfAccount> _coaAccounts = [];
  bool _coaLoading = false;

  static const _periods   = ['Monthly', 'Quarterly', 'Yearly'];
  static const _currencies = ['INR', 'USD', 'EUR', 'GBP', 'AED'];

  // FY month labels (Apr … Mar)
  static const _monthLabels = [
    'Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec','Jan','Feb','Mar'
  ];

  static String _defaultFY() {
    final now = DateTime.now();
    final startY = now.month >= 4 ? now.year : now.year - 1;
    final endY   = startY + 1;
    return '$startY-${endY.toString().substring(2)}';
  }

  @override
  void initState() {
    super.initState();
    _loadCOA();
    if (widget.budgetId != null) _loadBudget();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  Future<void> _loadCOA() async {
    setState(() => _coaLoading = true);
    try {
      final res = await ChartOfAccountService.getAccounts(isActive: true, limit: 500);
      setState(() => _coaAccounts = res.accounts);
    } catch (_) {}
    setState(() => _coaLoading = false);
  }

  Future<void> _loadBudget() async {
    setState(() => _isLoading = true);
    try {
      final b = await BudgetService.getBudget(widget.budgetId!);
      _nameCtrl.text  = b.budgetName;
      _notesCtrl.text = b.notes ?? '';
      setState(() {
        _financialYear = b.financialYear;
        _budgetPeriod  = b.budgetPeriod;
        _currency      = b.currency;
        _isActive      = b.isActive;
        for (final line in _lines) line.dispose();
        _lines.clear();
        for (final l in b.accountLines) {
          _lines.add(_MutableLine(
            accountId:   l.accountId,
            accountName: l.accountName,
            accountType: l.accountType,
            amounts:     l.monthlyAmounts,
          ));
        }
      });
    } catch (e) {
      _snack('Failed to load: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addLine() {
    setState(() => _lines.add(_MutableLine()));
  }

  void _removeLine(int i) {
    setState(() {
      _lines[i].dispose();
      _lines.removeAt(i);
    });
  }

  // Fill all months with same value
  void _fillAll(_MutableLine line, double value) {
    for (final c in line.monthControllers) {
      c.text = value > 0 ? value.toStringAsFixed(2) : '';
    }
    setState(() {});
  }

  // Distribute annual value equally
  void _distributeAnnual(_MutableLine line) {
    final total = line.amounts.reduce((a, b) => a + b);
    if (total <= 0) return;
    final per = total / 12;
    for (final c in line.monthControllers) c.text = per.toStringAsFixed(2);
    setState(() {});
  }

  // Grand total
  double get _grandTotal =>
      _lines.fold(0.0, (s, l) => s + l.total);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Budget name is required', Colors.red);
      return;
    }
    if (_lines.isEmpty) {
      _snack('Add at least one account line', Colors.red);
      return;
    }
    final invalid = _lines.where((l) => l.accountName.trim().isEmpty).toList();
    if (invalid.isNotEmpty) {
      _snack('All lines must have an account selected', Colors.red);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final body = {
        'budgetName':    _nameCtrl.text.trim(),
        'financialYear': _financialYear,
        'budgetPeriod':  _budgetPeriod,
        'currency':      _currency,
        'isActive':      _isActive,
        'notes':         _notesCtrl.text.trim(),
        'accountLines':  _lines.map((l) => l.toJson()).toList(),
      };

      Budget budget;
      if (widget.budgetId != null) {
        budget = await BudgetService.updateBudget(widget.budgetId!, body);
      } else {
        budget = await BudgetService.createBudget(body);
      }

      _snack('Budget "${budget.budgetName}" saved ✓', Colors.green);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Failed to save: $e', Colors.red);
    } finally {
      setState(() => _isSaving = false);
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
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: LayoutBuilder(builder: (_, cs) {
                final isWide = cs.maxWidth > 800;
                if (isWide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: _buildMain()),
                    Container(
                      width: 300,
                      color: Colors.white,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: _buildSidebar(),
                      ),
                    ),
                  ]);
                }
                return SingleChildScrollView(child: Column(children: [
                  _buildMain(),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: _buildSidebar(),
                  ),
                ]));
              }),
            ),
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
          widget.budgetId != null ? 'Edit Budget' : 'New Budget',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save, size: 18),
            label: Text(_isSaving ? 'Saving...' : 'Save Budget'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );

  // ── Main Content ──────────────────────────────────────────────────────────

  Widget _buildMain() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildBasicInfo(),
      const SizedBox(height: 20),
      _buildAccountLines(),
      const SizedBox(height: 20),
      _buildNotes(),
      const SizedBox(height: 20),
    ]),
  );

  // ── Basic Info Card ───────────────────────────────────────────────────────

  Widget _buildBasicInfo() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sectionTitle('Budget Information', Icons.account_balance),
    const SizedBox(height: 16),
    LayoutBuilder(builder: (_, cs) {
      final wide = cs.maxWidth > 600;
      final nameF = TextFormField(
        controller: _nameCtrl,
        decoration: InputDecoration(
          labelText: 'Budget Name *',
          hintText: 'e.g. FY 2025-26 Annual Budget',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.label_outline),
        ),
        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
      );
      final fyF = _dropField<String>(
        label: 'Financial Year *',
        value: _financialYear,
        items: _generateFYOptions(),
        onChanged: (v) => setState(() => _financialYear = v!),
        icon: Icons.calendar_month,
      );
      if (wide) return Row(children: [Expanded(flex: 2, child: nameF), const SizedBox(width: 16), Expanded(child: fyF)]);
      return Column(children: [nameF, const SizedBox(height: 16), fyF]);
    }),
    const SizedBox(height: 16),
    LayoutBuilder(builder: (_, cs) {
      final wide = cs.maxWidth > 600;
      final periodF = _dropField<String>(
        label: 'Budget Period',
        value: _budgetPeriod,
        items: _periods,
        onChanged: (v) => setState(() => _budgetPeriod = v!),
        icon: Icons.date_range,
      );
      final currF = _dropField<String>(
        label: 'Currency',
        value: _currency,
        items: _currencies,
        onChanged: (v) => setState(() => _currency = v!),
        icon: Icons.currency_rupee,
      );
      final statusF = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.toggle_on_outlined, color: Colors.grey),
          const SizedBox(width: 8),
          const Text('Active', style: TextStyle(fontSize: 14)),
          const Spacer(),
          Switch(
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            activeColor: _navyAccent,
          ),
        ]),
      );
      if (wide) return Row(children: [Expanded(child: periodF), const SizedBox(width: 16), Expanded(child: currF), const SizedBox(width: 16), Expanded(child: statusF)]);
      return Column(children: [periodF, const SizedBox(height: 16), currF, const SizedBox(height: 16), statusF]);
    }),
  ]));

  // ── Account Lines ─────────────────────────────────────────────────────────

  Widget _buildAccountLines() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _sectionTitle('Account Budget Lines', Icons.table_chart_outlined),
      ElevatedButton.icon(
        onPressed: _addLine,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Add Account'),
        style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
      ),
    ]),
    const SizedBox(height: 4),
    Text(
      'Select accounts from Chart of Accounts and set monthly budget amounts',
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
    ),
    const SizedBox(height: 16),

    // Header row
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_navyDark, _navyMid]),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
      ),
      child: LayoutBuilder(builder: (_, cs) {
        if (cs.maxWidth < 600) return const Text('ACCOUNT LINES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13));
        return Row(children: [
          const SizedBox(width: 220, child: Text('ACCOUNT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          const SizedBox(width: 16),
          ..._monthLabels.map((m) => SizedBox(width: 80, child: Text(m, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.center))),
          const SizedBox(width: 16),
          const SizedBox(width: 110, child: Text('ANNUAL TOTAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.right)),
          const SizedBox(width: 48),
        ]);
      }),
    ),

    if (_lines.isEmpty)
      Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
        ),
        child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_chart, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text('No account lines yet — click "Add Account"', style: TextStyle(color: Colors.grey.shade500)),
        ])),
      )
    else
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
        ),
        child: LayoutBuilder(builder: (_, cs) {
          final narrow = cs.maxWidth < 600;
          if (narrow) {
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lines.length,
              separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200, height: 1),
              itemBuilder: (_, i) => _buildLineMobile(i),
            );
          }
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(_lines.length, (i) => Column(children: [
                  _buildLineDesktop(i),
                  if (i < _lines.length - 1) Divider(color: Colors.grey.shade100, height: 1),
                ])),
              ),
            ),
          );
        }),
      ),

    // Grand total
    if (_lines.isNotEmpty) ...[
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_navyDark.withOpacity(0.08), _navyLight.withOpacity(0.08)]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _navyAccent.withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('TOTAL ANNUAL BUDGET', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navyDark)),
          Text(
            '${_currency == 'INR' ? '₹' : _currency} ${NumberFormat('#,##0.00').format(_grandTotal)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _navyAccent),
          ),
        ]),
      ),
    ],
  ]));

  Widget _buildLineDesktop(int idx) {
    final line = _lines[idx];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      color: idx.isEven ? Colors.white : Colors.grey.shade50,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Account selector
        SizedBox(
          width: 220,
          child: _coaLoading
              ? const LinearProgressIndicator()
              : _AccountDropdown(
                  accounts: _coaAccounts,
                  selectedId: line.accountId,
                  selectedName: line.accountName,
                  onSelected: (acc) {
                    setState(() {
                      line.accountId   = acc.id;
                      line.accountName = acc.accountName;
                      line.accountType = acc.accountType;
                    });
                  },
                ),
        ),
        const SizedBox(width: 16),
        // 12 month inputs
        ...List.generate(12, (m) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: SizedBox(
            width: 76,
            child: TextField(
              controller: line.monthControllers[m],
              decoration: InputDecoration(
                hintText: '0',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: _navyAccent, width: 2),
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => setState(() {}),
            ),
          ),
        )),
        const SizedBox(width: 12),
        // Annual total
        SizedBox(
          width: 110,
          child: Text(
            NumberFormat('#,##0.00').format(line.total),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _navyDark),
            textAlign: TextAlign.right,
          ),
        ),
        // Actions
        SizedBox(
          width: 48,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onSelected: (v) {
              if (v == 'fill') _showFillDialog(line);
              if (v == 'distribute') _distributeAnnual(line);
              if (v == 'remove') _removeLine(idx);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'fill', child: Row(children: [Icon(Icons.auto_fix_high, size: 16, color: Colors.blue), SizedBox(width: 8), Text('Fill All Months')])),
              const PopupMenuItem(value: 'distribute', child: Row(children: [Icon(Icons.balance, size: 16, color: Colors.teal), SizedBox(width: 8), Text('Distribute Equally')])),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'remove', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('Remove', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildLineMobile(int idx) {
    final line = _lines[idx];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: _coaLoading
                ? const LinearProgressIndicator()
                : _AccountDropdown(
                    accounts: _coaAccounts,
                    selectedId: line.accountId,
                    selectedName: line.accountName,
                    onSelected: (acc) => setState(() {
                      line.accountId   = acc.id;
                      line.accountName = acc.accountName;
                      line.accountType = acc.accountType;
                    }),
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _removeLine(idx),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(12, (m) => SizedBox(
            width: 80,
            child: TextField(
              controller: line.monthControllers[m],
              decoration: InputDecoration(
                labelText: _monthLabels[m],
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => setState(() {}),
            ),
          )),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Annual Total:', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          Text(NumberFormat('#,##0.00').format(line.total),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navyAccent)),
        ]),
      ]),
    );
  }

  void _showFillDialog(_MutableLine line) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Fill All Months'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Amount per month', prefixText: '₹'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text) ?? 0;
              _fillAll(line, v);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  Widget _buildNotes() => _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sectionTitle('Notes', Icons.note_alt_outlined),
    const SizedBox(height: 12),
    TextFormField(
      controller: _notesCtrl,
      decoration: InputDecoration(
        hintText: 'Add notes about this budget…',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        alignLabelWithHint: true,
      ),
      maxLines: 3,
    ),
  ]));

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sectionTitle('Budget Summary', Icons.summarize),
    const SizedBox(height: 16),
    _summRow('Financial Year', _financialYear),
    const SizedBox(height: 8),
    _summRow('Period', _budgetPeriod),
    const SizedBox(height: 8),
    _summRow('Accounts', '${_lines.length}'),
    const SizedBox(height: 8),
    _summRow('Status', _isActive ? 'Active' : 'Inactive'),
    const Divider(height: 24),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      const Text('Total Budget', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _navyDark)),
      Text(
        '${_currency == 'INR' ? '₹' : _currency} ${NumberFormat('#,##0.00').format(_grandTotal)}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _navyAccent),
      ),
    ]),
    const SizedBox(height: 24),
    SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: _isSaving ? null : _save,
      icon: _isSaving
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.save),
      label: Text(_isSaving ? 'Saving...' : 'Save Budget'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _navyAccent, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    )),
    const SizedBox(height: 10),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: _isSaving ? null : () => Navigator.pop(context),
      icon: const Icon(Icons.close),
      label: const Text('Cancel'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _navyMid, side: const BorderSide(color: _navyMid),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    )),
  ]);

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<String> _generateFYOptions() {
    final now = DateTime.now();
    final base = now.month >= 4 ? now.year : now.year - 1;
    return List.generate(5, (i) {
      final y = base - 2 + i;
      return '$y-${(y + 1).toString().substring(2)}';
    });
  }

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    ),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  Widget _dropField<T>({
    required String label,
    required T value,
    required List<T> items,
    required void Function(T?) onChanged,
    required IconData icon,
  }) => DropdownButtonFormField<T>(
    value: value,
    decoration: InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      prefixIcon: Icon(icon),
    ),
    items: items.map((i) => DropdownMenuItem<T>(value: i, child: Text(i.toString()))).toList(),
    onChanged: onChanged,
  );

  Widget _summRow(String label, String value) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
    Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navyDark)),
  ]);
}

// ============================================================================
// ACCOUNT DROPDOWN WIDGET
// ============================================================================

class _AccountDropdown extends StatelessWidget {
  final List<ChartOfAccount> accounts;
  final String? selectedId;
  final String selectedName;
  final void Function(ChartOfAccount) onSelected;

  const _AccountDropdown({
    required this.accounts,
    this.selectedId,
    required this.selectedName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
              selectedName.isEmpty ? 'Select Account' : selectedName,
              style: TextStyle(
                fontSize: 13,
                color: selectedName.isEmpty ? Colors.grey.shade500 : const Color(0xFF0D1B3E),
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
        ]),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final searchCtrl = TextEditingController();
    List<ChartOfAccount> filtered = List.from(accounts);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Select Account'),
        content: SizedBox(
          width: 480,
          height: 400,
          child: Column(children: [
            TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name or code…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onChanged: (v) => setS(() {
                filtered = v.isEmpty
                    ? accounts
                    : accounts.where((a) =>
                        a.accountName.toLowerCase().contains(v.toLowerCase()) ||
                        a.accountCode.toLowerCase().contains(v.toLowerCase()) ||
                        a.accountType.toLowerCase().contains(v.toLowerCase())).toList();
              }),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: accounts.isEmpty
                  ? const Center(child: Text('No accounts found'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final a = filtered[i];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: const Color(0xFF2463AE).withOpacity(0.15),
                            child: Text(a.accountCode.isEmpty ? a.accountType[0] : a.accountCode[0],
                                style: const TextStyle(fontSize: 11, color: Color(0xFF2463AE), fontWeight: FontWeight.bold)),
                          ),
                          title: Text(a.accountName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('${a.accountCode}  •  ${a.accountType}', style: const TextStyle(fontSize: 11)),
                          selected: a.id == (selectedId ?? ''),
                          onTap: () {
                            onSelected(a);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      )),
    );
  }
}