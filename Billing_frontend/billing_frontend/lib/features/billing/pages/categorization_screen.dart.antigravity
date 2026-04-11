// ============================================================================
// CATEGORIZATION SCREEN — ZOHO BOOKS PIN-TO-PIN
// ============================================================================
// File: lib/screens/banking/categorization_screen.dart
//
// Layout:
//   Desktop (>900px): Left list (60%) + Right panel (40%) — side by side
//   Tablet  (600-900px): Full list + bottom sheet panel (60% height)
//   Mobile  (<600px): Full list + full screen overlay panel
//
// Sub-tabs inside Uncategorized tab (like Zoho Books):
//   [Dashboard] [Uncategorized Transactions] [All Transactions]
//
// Right panel tabs:
//   [MATCH TRANSACTIONS] [CATEGORIZE MANUALLY]
//
// Category types:
//   Money Out: Expense | Vendor Advance | Vendor Payment | Transfer To Another
//              Account | Card Payment | Owner Drawings | Credit Note Refund |
//              Payment Refund
//   Money In:  Customer Advance | Customer Payment | Transfer From Another
//              Account | Interest Income | Other Income | Expense Refund |
//              Owner's Contribution | Vendor Credit Refund | Vendor Payment
//              Refund
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/services/bank_transaction_service.dart';
import '../../../core/services/add_account_service.dart';

// ─── colour palette ───────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _purple = Color(0xFF9B59B6);
const Color _teal   = Color(0xFF16A085);

// ─── Category model ───────────────────────────────────────────────────────────
class _Category {
  final String id;
  final String label;
  final String group; // 'money_in' | 'money_out'
  final IconData icon;
  final Color color;
  const _Category({
    required this.id, required this.label,
    required this.group, required this.icon, required this.color,
  });
}

const _moneyOutCategories = [
  _Category(id: 'expense',           label: 'Expense',                    group: 'money_out', icon: Icons.receipt_outlined,         color: _red),
  _Category(id: 'vendor_advance',    label: 'Vendor Advance',             group: 'money_out', icon: Icons.person_outlined,          color: _orange),
  _Category(id: 'vendor_payment',    label: 'Vendor Payment',             group: 'money_out', icon: Icons.payments_outlined,        color: _orange),
  _Category(id: 'transfer_out',      label: 'Transfer To Another Account',group: 'money_out', icon: Icons.compare_arrows,           color: _blue),
  _Category(id: 'card_payment',      label: 'Card Payment',               group: 'money_out', icon: Icons.credit_card_outlined,     color: _purple),
  _Category(id: 'owner_drawings',    label: 'Owner Drawings',             group: 'money_out', icon: Icons.person_pin_outlined,      color: _teal),
  _Category(id: 'credit_note_refund',label: 'Credit Note Refund',         group: 'money_out', icon: Icons.undo_outlined,            color: _red),
  _Category(id: 'payment_refund',    label: 'Payment Refund',             group: 'money_out', icon: Icons.reply_outlined,           color: _orange),
];

const _moneyInCategories = [
  _Category(id: 'customer_advance',      label: 'Customer Advance',           group: 'money_in', icon: Icons.person_add_outlined,      color: _green),
  _Category(id: 'customer_payment',      label: 'Customer Payment',           group: 'money_in', icon: Icons.payments_outlined,        color: _green),
  _Category(id: 'transfer_in',           label: 'Transfer From Another Account',group: 'money_in',icon: Icons.compare_arrows,          color: _blue),
  _Category(id: 'interest_income',       label: 'Interest Income',            group: 'money_in', icon: Icons.trending_up_outlined,     color: _teal),
  _Category(id: 'other_income',          label: 'Other Income',               group: 'money_in', icon: Icons.add_circle_outline,       color: _teal),
  _Category(id: 'expense_refund',        label: 'Expense Refund',             group: 'money_in', icon: Icons.reply_outlined,           color: _green),
  _Category(id: 'owner_contribution',    label: "Owner's Contribution",       group: 'money_in', icon: Icons.business_center_outlined, color: _navy),
  _Category(id: 'vendor_credit_refund',  label: 'Vendor Credit Refund',       group: 'money_in', icon: Icons.undo_outlined,            color: _green),
  _Category(id: 'vendor_payment_refund', label: 'Vendor Payment Refund',      group: 'money_in', icon: Icons.reply_all_outlined,       color: _orange),
];

// =============================================================================
//  MAIN WIDGET
// =============================================================================

class CategorizationScreen extends StatefulWidget {
  final String accountId;
  final String accountName;
  final String accountType;
  final VoidCallback? onCategorized;

  const CategorizationScreen({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.accountType,
    this.onCategorized,
  }) : super(key: key);

  @override
  State<CategorizationScreen> createState() => _CategorizationScreenState();
}

class _CategorizationScreenState extends State<CategorizationScreen>
    with SingleTickerProviderStateMixin {

  final BankTransactionService _service = BankTransactionService();
  late TabController _subTabCtrl;

  // Data
  bool _loading                              = true;
  List<Map<String, dynamic>> _uncategorized  = [];
  List<Map<String, dynamic>> _allTxns        = [];
  List<COAOption>             _expenseCOAs   = [];
  List<COAOption>             _incomeCOAs    = [];
  List<Map<String, dynamic>>  _bankAccounts  = [];
  List<Map<String, dynamic>>  _possibleMatches = [];

  // Stats for Dashboard sub-tab
  int _uncatCount   = 0;
  int _matchedCount = 0;
  int _totalCount   = 0;

  // Filter
  String _filter = 'All'; // All | DEBIT | CREDIT

  // Selected transaction (for right panel)
  Map<String, dynamic>? _selectedTxn;
  bool _panelOpen                = false;
  int  _panelTab                 = 0; // 0=Match, 1=Categorize
  bool _matchesLoading           = false;

  // Multi-select for multi-match
  final Set<String> _selectedBankTxnIds = {};

  // Categorize form state
  _Category?            _selectedCategory;
  COAOption?            _selectedCOA;
  Map<String, dynamic>? _selectedToAccount;
  Map<String, dynamic>? _selectedVendor;
  Map<String, dynamic>? _selectedCustomer;
  final _amountCtrl   = TextEditingController();
  final _refCtrl      = TextEditingController();
  final _descCtrl     = TextEditingController();
  final _dateCtrl     = TextEditingController();
  bool  _categorizing = false;

  @override
  void initState() {
    super.initState();
    _subTabCtrl = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _subTabCtrl.dispose();
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _descCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadUncategorized(),
      _loadAllTransactions(),
      _loadCOAs(),
      _loadBankAccounts(),
      _loadStats(),
    ]);
    setState(() => _loading = false);
  }

  Future<void> _loadUncategorized() async {
    try {
      final res = await _service.getUncategorized(accountId: widget.accountId, page: 1, limit: 100);
      if (res['success'] == true) {
        setState(() => _uncategorized = List<Map<String, dynamic>>.from(res['data'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _loadAllTransactions() async {
    try {
      final res = await _service.getAllTransactions(accountId: widget.accountId);
      if (res['success'] == true) {
        setState(() => _allTxns = List<Map<String, dynamic>>.from(res['data'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _loadCOAs() async {
    _expenseCOAs = await _service.getCOAOptions('expense');
    _incomeCOAs  = await _service.getCOAOptions('income');
  }

  Future<void> _loadBankAccounts() async {
    try {
      final all = await AddAccountService().getAllAccounts();
      setState(() {
        _bankAccounts = all
            .where((a) => a['_id'] != widget.accountId && (a['isActive'] ?? true))
            .map((a) => Map<String, dynamic>.from(a))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    try {
      final res = await _service.getStats(widget.accountId);
      if (res['success'] == true) {
        final d = res['data'];
        setState(() {
          _uncatCount   = d['uncategorized'] ?? 0;
          _matchedCount = d['categorized']   ?? 0;
          _totalCount   = d['total']         ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPossibleMatches(Map<String, dynamic> txn) async {
    setState(() { _matchesLoading = true; _possibleMatches = []; });
    try {
      final res = await _service.getPossibleMatches(
        accountId: widget.accountId,
        amount:    (txn['amount'] ?? 0).toDouble(),
        txnType:   txn['transactionType'] ?? 'DEBIT',
        txnDate:   txn['transactionDate']?.toString() ?? '',
      );
      setState(() {
        _possibleMatches = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _matchesLoading  = false;
      });
    } catch (_) {
      setState(() => _matchesLoading = false);
    }
  }

  void _openPanel(Map<String, dynamic> txn, {int tab = 0}) {
    setState(() {
      _selectedTxn      = txn;
      _panelOpen        = true;
      _panelTab         = tab;
      _selectedCategory = null;
      _selectedCOA      = null;
      _selectedToAccount = null;
      _categorizing     = false;

      // Pre-fill form fields from transaction
      _amountCtrl.text = (txn['amount'] ?? 0).toStringAsFixed(2);
      _refCtrl.text    = txn['referenceNumber']?.toString() ?? '';
      _descCtrl.text   = txn['description']?.toString() ?? '';
      _dateCtrl.text   = _fmtDateStr(txn['transactionDate']?.toString() ?? '');
    });
    if (tab == 0) _loadPossibleMatches(txn);
  }

  void _closePanel() {
    setState(() {
      _selectedTxn           = null;
      _panelOpen             = false;
      _selectedBankTxnIds.clear();
      _possibleMatches.clear();
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'All') return _uncategorized;
    return _uncategorized.where((t) => t['transactionType'] == _filter).toList();
  }

  // ==========================================================================
  //  BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _navy));

    return Column(children: [
      _buildSubTabBar(),
      Expanded(child: TabBarView(
        controller: _subTabCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildDashboardTab(),
          _buildUncategorizedTab(),
          _buildAllTransactionsTab(),
        ],
      )),
    ]);
  }

  // ── Sub tab bar ──────────────────────────────────────────────────────────

  Widget _buildSubTabBar() => Container(
    color: Colors.white,
    child: TabBar(
      controller: _subTabCtrl,
      labelColor: _navy,
      unselectedLabelColor: Colors.grey[500],
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      indicatorColor: _navy,
      indicatorWeight: 2,
      tabs: [
        const Tab(text: 'Dashboard'),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Uncategorized Transactions'),
          if (_uncatCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(10)),
              child: Text('$_uncatCount',
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ],
        ])),
        const Tab(text: 'All Transactions'),
      ],
    ),
  );

  // ── Dashboard sub-tab ────────────────────────────────────────────────────

  Widget _buildDashboardTab() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Account Summary',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (_, c) {
        final isWide = c.maxWidth > 500;
        final cards  = [
          _dashCard('Uncategorized', '$_uncatCount', Icons.pending_actions, _orange),
          _dashCard('Categorized',   '$_matchedCount', Icons.check_circle_outline, _green),
          _dashCard('Total',         '$_totalCount', Icons.list_alt, _blue),
        ];
        if (isWide) {
          return Row(children: cards.asMap().entries.map((e) =>
              Expanded(child: Padding(
                  padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 12 : 0),
                  child: e.value))).toList());
        }
        return Column(children: cards.map((c) =>
            Padding(padding: const EdgeInsets.only(bottom: 12), child: c)).toList());
      }),
      const SizedBox(height: 24),
      if (_uncatCount > 0) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _orange.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _orange.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_uncatCount Uncategorized Transactions',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('Tap "Uncategorized Transactions" tab to categorize them.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ])),
            TextButton(
              onPressed: () => _subTabCtrl.animateTo(1),
              style: TextButton.styleFrom(foregroundColor: _orange),
              child: const Text('Categorize now ›'),
            ),
          ]),
        ),
      ],
    ]),
  );

  Widget _dashCard(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 28),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ]),
    ]),
  );

  // ── Uncategorized sub-tab ────────────────────────────────────────────────

  Widget _buildUncategorizedTab() {
    return LayoutBuilder(builder: (_, c) {
      final isDesktop = c.maxWidth > 900;
      final isTablet  = c.maxWidth > 600;

      if (_filtered.isEmpty) return _buildEmptyState();

      if (isDesktop && _panelOpen) {
        // Side-by-side layout
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Left list
          SizedBox(
            width: c.maxWidth * 0.58,
            child: _buildTxnList(),
          ),
          // Right panel
          Expanded(child: _buildRightPanel()),
        ]);
      }

      // Full width list
      return Stack(children: [
        _buildTxnList(),
        // Panel overlay for tablet/mobile
        if (_panelOpen)
          Positioned.fill(child: _buildPanelOverlay(isTablet)),
      ]);
    });
  }

  Widget _buildTxnList() => Column(children: [
    _buildFilterBar(),
    Expanded(child: RefreshIndicator(
      color: _navy,
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _buildTxnRow(_filtered[i]),
      ),
    )),
  ]);

  Widget _buildFilterBar() => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      // Multi-select & Match toggle
      if (_selectedBankTxnIds.isNotEmpty) ...[
        Text('${_selectedBankTxnIds.length} selected',
            style: const TextStyle(fontWeight: FontWeight.bold, color: _navy, fontSize: 13)),
        const SizedBox(width: 10),
        TextButton.icon(
          onPressed: () => setState(() => _selectedBankTxnIds.clear()),
          icon: const Icon(Icons.clear, size: 14),
          label: const Text('Clear', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: Colors.grey, visualDensity: VisualDensity.compact),
        ),
        const Spacer(),
      ] else ...[
        Text('${_filtered.length} transactions',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const Spacer(),
      ],
      // Filter chips
      ...['All', 'DEBIT', 'CREDIT'].map((f) {
        final sel = _filter == f;
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ChoiceChip(
            label: Text(f == 'DEBIT' ? 'Money Out' : f == 'CREDIT' ? 'Money In' : 'All',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.grey[600])),
            selected: sel,
            onSelected: (_) => setState(() => _filter = f),
            selectedColor: _navy,
            backgroundColor: Colors.grey[100],
            side: BorderSide(color: sel ? _navy : Colors.grey[300]!),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          ),
        );
      }),
    ]),
  );

  Widget _buildTxnRow(Map<String, dynamic> txn) {
    final id      = txn['_id']?.toString() ?? '';
    final isDebit = txn['transactionType'] == 'DEBIT';
    final amount  = (txn['amount'] ?? 0).toDouble();
    final date    = _parseDate(txn['transactionDate']);
    final desc    = txn['description']?.toString() ?? '';
    final refNum  = txn['referenceNumber']?.toString() ?? '';
    final isSelected = _selectedTxn?['_id']?.toString() == id;
    final isChecked  = _selectedBankTxnIds.contains(id);

    return InkWell(
      onTap: () => _openPanel(txn),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? _navy.withOpacity(0.05)
              : Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey[100]!),
            left: isSelected ? const BorderSide(color: _navy, width: 3) : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          // Checkbox for multi-match
          SizedBox(
            width: 28,
            child: Checkbox(
              value: isChecked,
              onChanged: (_) => setState(() {
                if (isChecked) _selectedBankTxnIds.remove(id);
                else           _selectedBankTxnIds.add(id);
              }),
              activeColor: _navy,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          const SizedBox(width: 8),
          // Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: (isDebit ? _red : _green).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                color: isDebit ? _red : _green, size: 18),
          ),
          const SizedBox(width: 12),
          // Date
          SizedBox(
            width: 60,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('dd MMM').format(date),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Text(DateFormat('yyyy').format(date),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ]),
          ),
          const SizedBox(width: 10),
          // Description
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desc.isNotEmpty ? desc : (isDebit ? 'Debit' : 'Credit'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (refNum.isNotEmpty)
              Text(refNum, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ])),
          const SizedBox(width: 10),
          // Amount
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${isDebit ? '−' : '+'}₹${_fmt(amount)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                    color: isDebit ? _red : _green)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isDebit ? _red : _green).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(isDebit ? 'Money Out' : 'Money In',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                      color: isDebit ? _red : _green)),
            ),
          ]),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ]),
      ),
    );
  }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: _green.withOpacity(0.08), shape: BoxShape.circle),
      child: Icon(Icons.check_circle_outline, size: 64, color: _green.withOpacity(0.5)),
    ),
    const SizedBox(height: 20),
    const Text('All Caught Up!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    Text('No uncategorized transactions.', style: TextStyle(color: Colors.grey[500])),
    const SizedBox(height: 24),
    ElevatedButton.icon(
      onPressed: _loadAll,
      icon: const Icon(Icons.refresh),
      label: const Text('Refresh'),
      style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    ),
  ]));

  // ── Right panel (desktop — inline) ───────────────────────────────────────

  Widget _buildRightPanel() => Container(
    height: double.infinity,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(left: BorderSide(color: Color(0xFFEEF2F7), width: 1.5)),
    ),
    child: _selectedTxn == null
        ? const Center(child: Text('Select a transaction', style: TextStyle(color: Colors.grey)))
        : _buildPanelContent(),
  );

  // ── Panel overlay (tablet/mobile) ────────────────────────────────────────

  Widget _buildPanelOverlay(bool isTablet) {
    return GestureDetector(
      onTap: _closePanel,
      child: Container(
        color: Colors.black26,
        child: Align(
          alignment: isTablet ? Alignment.bottomCenter : Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // prevent close on panel tap
            child: Container(
              height: isTablet
                  ? MediaQuery.of(context).size.height * 0.65
                  : MediaQuery.of(context).size.height,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: _selectedTxn == null
                  ? const SizedBox()
                  : _buildPanelContent(showHandle: true),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanelContent({bool showHandle = false}) {
    final txn     = _selectedTxn!;
    final isDebit = txn['transactionType'] == 'DEBIT';
    final amount  = (txn['amount'] ?? 0).toDouble();
    final date    = _parseDate(txn['transactionDate']);
    final desc    = txn['description']?.toString() ?? '';
    final refNum  = txn['referenceNumber']?.toString() ?? '';

    return Column(children: [
      if (showHandle) ...[
        const SizedBox(height: 10),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
      ],
      // Panel header
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (isDebit ? _red : _green).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${isDebit ? '−' : '+'}₹${_fmt(amount)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                    color: isDebit ? _red : _green)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(desc.isNotEmpty ? desc : (isDebit ? 'Debit' : 'Credit'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(DateFormat('dd MMM yyyy').format(date),
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ])),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _closePanel),
        ]),
      ),

      // Panel tab bar
      Container(
        color: const Color(0xFFF8F9FA),
        child: Row(children: [
          Expanded(child: InkWell(
            onTap: () { setState(() => _panelTab = 0); _loadPossibleMatches(txn); },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(
                    color: _panelTab == 0 ? _navy : Colors.transparent, width: 2)),
              ),
              child: Text('MATCH TRANSACTIONS', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: _panelTab == 0 ? _navy : Colors.grey[500])),
            ),
          )),
          Expanded(child: InkWell(
            onTap: () => setState(() => _panelTab = 1),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(
                    color: _panelTab == 1 ? _navy : Colors.transparent, width: 2)),
              ),
              child: Text('CATEGORIZE MANUALLY', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: _panelTab == 1 ? _navy : Colors.grey[500])),
            ),
          )),
        ]),
      ),

      // Panel body
      Expanded(child: _panelTab == 0
          ? _buildMatchPanel(txn)
          : _buildCategorizePanel(txn)),
    ]);
  }

  // ── MATCH TRANSACTIONS PANEL ─────────────────────────────────────────────

  Widget _buildMatchPanel(Map<String, dynamic> txn) => Column(children: [
    Expanded(child: _matchesLoading
        ? const Center(child: CircularProgressIndicator(color: _navy, strokeWidth: 2))
        : _possibleMatches.isEmpty
            ? _buildNoMatches()
            : _buildMatchList()),

    // Match button
    if (_possibleMatches.isNotEmpty)
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
        child: Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: _closePanel,
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey[300]!),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Cancel'),
          )),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton(
            onPressed: _doMatch,
            style: ElevatedButton.styleFrom(
                backgroundColor: _navy, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Match', style: TextStyle(fontWeight: FontWeight.bold)),
          )),
        ]),
      ),
  ]);

  Widget _buildNoMatches() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('Possible Matches',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('Transactions upto ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      const SizedBox(height: 32),
      Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
      const SizedBox(height: 12),
      Text('There are no transactions matching the selected criteria.',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          textAlign: TextAlign.center),
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: () => setState(() => _panelTab = 1),
        icon: const Icon(Icons.edit_note, size: 16),
        label: const Text('Categorize Manually instead'),
        style: TextButton.styleFrom(foregroundColor: _blue),
      ),
    ]),
  );

  Widget _buildMatchList() {
    final txn = _selectedTxn!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Possible Matches',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton(
            onPressed: () {/* select all */},
            style: TextButton.styleFrom(foregroundColor: _blue, visualDensity: VisualDensity.compact),
            child: const Text('SELECT ALL', style: TextStyle(fontSize: 11)),
          ),
          Icon(Icons.filter_list, size: 16, color: Colors.grey[500]),
        ]),
        Text('Transactions upto ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        const SizedBox(height: 12),

        // Multi-match info banner if multiple bank txns selected
        if (_selectedBankTxnIds.length > 1) ...[
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _blue.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: _blue, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${_selectedBankTxnIds.length} bank transactions selected. '
                'Select a system record below to match them all.',
                style: const TextStyle(fontSize: 11, color: _blue),
              )),
            ]),
          ),
        ],

        ..._possibleMatches.map((match) => _buildMatchCard(match, txn)),
      ]),
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match, Map<String, dynamic> txn) {
    final type    = match['type']?.toString() ?? 'Record';
    final amount  = (match['amount'] ?? match['total'] ?? match['balanceDue'] ?? 0).toDouble();
    final refNum  = match['invoiceNumber'] ?? match['billNumber'] ?? match['referenceNumber'] ?? '';
    final name    = match['customerName']  ?? match['vendorName'] ?? '';
    final dateStr = match['invoiceDate']   ?? match['billDate']   ?? match['date'] ?? '';
    final isSelected = match['_selected'] == true;

    Color typeColor;
    switch (type.toLowerCase()) {
      case 'invoice':      typeColor = _green;  break;
      case 'bill':         typeColor = _orange; break;
      case 'credit note':  typeColor = _purple; break;
      default:             typeColor = _blue;
    }

    return InkWell(
      onTap: () => setState(() => match['_selected'] = !(match['_selected'] ?? false)),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? typeColor.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? typeColor : Colors.grey[200]!, width: isSelected ? 1.5 : 1),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                child: Text(type, style: TextStyle(fontSize: 10,
                    fontWeight: FontWeight.bold, color: typeColor)),
              ),
              const SizedBox(width: 8),
              Text('for ₹${_fmt(amount)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            if (dateStr.isNotEmpty)
              Text('Dated ${_fmtDateStr(dateStr)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            if (name.isNotEmpty || refNum.isNotEmpty)
              Text(
                [if (name.isNotEmpty) name, if (refNum.isNotEmpty) refNum].join(' | '),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
          ])),
          if (isSelected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: typeColor, borderRadius: BorderRadius.circular(6)),
              child: const Text('✓ Selected',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else
            OutlinedButton(
              onPressed: () => setState(() => match['_selected'] = true),
              style: OutlinedButton.styleFrom(
                  foregroundColor: typeColor,
                  side: BorderSide(color: typeColor),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
              child: const Text('Select', style: TextStyle(fontSize: 11)),
            ),
        ]),
      ),
    );
  }

  Future<void> _doMatch() async {
    final selected = _possibleMatches.where((m) => m['_selected'] == true).toList();
    if (selected.isEmpty) {
      _showError('Select at least one match');
      return;
    }

    final txn   = _selectedTxn!;
    final txnId = txn['_id']?.toString() ?? '';

    try {
      Map<String, dynamic> res;

      if (selected.length == 1) {
        final match = selected.first;
        final type  = match['type']?.toString().toLowerCase() ?? '';
        if (type == 'invoice') {
          res = await _service.matchToInvoice(
              providerTransactionId: txnId,
              invoiceId: match['_id'].toString());
        } else if (type == 'bill') {
          res = await _service.matchToBill(
              providerTransactionId: txnId,
              billId: match['_id'].toString());
        } else {
          // Generic match
          res = await _service.matchToRecord(
              providerTransactionId: txnId,
              recordId: match['_id'].toString(),
              recordType: type);
        }
      } else {
        // Multi-match: one bank txn → many system records
        res = await _service.multiMatchOneToMany(
            providerTransactionId: txnId,
            expenseIds: selected.map((m) => m['_id'].toString()).toList());
      }

      if (res['success'] == true) {
        _showSuccess('Transaction matched successfully');
        _closePanel();
        _loadAll();
        widget.onCategorized?.call();
      } else {
        _showError(res['message'] ?? 'Match failed');
      }
    } catch (e) {
      _showError('Failed: $e');
    }
  }

  // ── CATEGORIZE MANUALLY PANEL ────────────────────────────────────────────

  Widget _buildCategorizePanel(Map<String, dynamic> txn) {
    final isDebit = txn['transactionType'] == 'DEBIT';
    final suggestedCategories = isDebit ? _moneyOutCategories : _moneyInCategories;

    return Column(children: [
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Category dropdown
          _buildCategoryDropdown(suggestedCategories, isDebit),
          const SizedBox(height: 14),

          // Dynamic fields based on selected category
          if (_selectedCategory != null) ...[
            _buildDynamicFields(txn),
          ],
        ]),
      )),

      // Save button
      if (_selectedCategory != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: _categorizing ? null : _closePanel,
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: const Text('Cancel'),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: _categorizing ? null : () => _saveCategory(txn),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _categorizing
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ),
    ]);
  }

  Widget _buildCategoryDropdown(List<_Category> categories, bool isDebit) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(isDebit ? 'Category (Money Out) *' : 'Category (Money In) *',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<_Category>(
            value: _selectedCategory,
            isExpanded: true,
            hint: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('Select category', style: TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            icon: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.arrow_drop_down),
            ),
            items: [
              DropdownMenuItem<_Category>(
                enabled: false,
                value: null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(isDebit ? 'MONEY OUT' : 'MONEY IN',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                          color: Colors.grey[400], letterSpacing: 0.8)),
                ),
              ),
              ...categories.map((c) => DropdownMenuItem(
                value: c,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(children: [
                    Icon(c.icon, color: c.color, size: 16),
                    const SizedBox(width: 10),
                    Text(c.label, style: const TextStyle(fontSize: 13)),
                  ]),
                ),
              )),
            ],
            onChanged: (v) => setState(() {
              _selectedCategory  = v;
              _selectedCOA       = null;
              _selectedToAccount = null;
            }),
          ),
        ),
      ),
    ]);
  }

  Widget _buildDynamicFields(Map<String, dynamic> txn) {
    final cat = _selectedCategory!;
    final id  = cat.id;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Customer fields ──────────────────────────────────────────────────
      if (id == 'customer_payment' || id == 'customer_advance') ...[
        _fieldLabel('Customer'),
        const SizedBox(height: 6),
        TextFormField(
          onChanged: (v) => _selectedCustomer = {'name': v},
          decoration: _inputDeco('Customer Name', Icons.person_outline),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Amount Received'),
        const SizedBox(height: 6),
        TextFormField(controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: _inputDeco('Amount', Icons.currency_rupee)),
        const SizedBox(height: 12),
        _fieldLabel('Bank Charges (if any)'),
        const SizedBox(height: 6),
        TextFormField(decoration: _inputDeco('Bank Charges', Icons.currency_rupee)),
        const SizedBox(height: 12),
        _fieldLabel('Date *'),
        const SizedBox(height: 6),
        TextFormField(controller: _dateCtrl,
            decoration: _inputDeco('Date', Icons.calendar_today)),
        const SizedBox(height: 12),
        _fieldLabel('Payment #'),
        const SizedBox(height: 6),
        TextFormField(decoration: _inputDeco('Payment #', Icons.tag)),
        const SizedBox(height: 12),
        _fieldLabel('Reference #'),
        const SizedBox(height: 6),
        TextFormField(controller: _refCtrl,
            decoration: _inputDeco('Reference #', Icons.tag_outlined)),
        const SizedBox(height: 12),
        _fieldLabel('Received Via'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          decoration: _inputDeco('Payment Mode', Icons.payment),
          items: ['Cash', 'Bank Transfer', 'UPI', 'Cheque', 'Card', 'Online']
              .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (_) {},
        ),
        const SizedBox(height: 12),
        _fieldLabel('Description'),
        const SizedBox(height: 6),
        TextFormField(controller: _descCtrl, maxLines: 2,
            decoration: _inputDeco('Description', Icons.note_outlined)),
      ],

      // ── Vendor / Expense fields ──────────────────────────────────────────
      if (id == 'expense' || id == 'vendor_advance' || id == 'vendor_payment') ...[
        _fieldLabel(id == 'expense' ? 'Category (Expense Account) *' : 'Expense Account'),
        const SizedBox(height: 6),
        DropdownButtonFormField<COAOption>(
          decoration: _inputDeco('Select account', Icons.account_tree_outlined),
          isExpanded: true,
          value: _selectedCOA,
          items: _expenseCOAs.map((c) => DropdownMenuItem(
              value: c,
              child: Text('${c.accountCode} - ${c.accountName}',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setState(() => _selectedCOA = v),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Vendor (optional)'),
        const SizedBox(height: 6),
        TextFormField(decoration: _inputDeco('Vendor Name', Icons.store_outlined)),
        const SizedBox(height: 12),
        _fieldLabel('Amount'),
        const SizedBox(height: 6),
        TextFormField(controller: _amountCtrl, keyboardType: TextInputType.number,
            decoration: _inputDeco('Amount', Icons.currency_rupee)),
        const SizedBox(height: 12),
        _fieldLabel('Date *'),
        const SizedBox(height: 6),
        TextFormField(controller: _dateCtrl,
            decoration: _inputDeco('Date', Icons.calendar_today)),
        const SizedBox(height: 12),
        _fieldLabel('Reference #'),
        const SizedBox(height: 6),
        TextFormField(controller: _refCtrl,
            decoration: _inputDeco('Reference #', Icons.tag_outlined)),
        const SizedBox(height: 12),
        _fieldLabel('Notes (optional)'),
        const SizedBox(height: 6),
        TextFormField(controller: _descCtrl, maxLines: 2,
            decoration: _inputDeco('Notes', Icons.note_outlined)),
      ],

      // ── Transfer fields ──────────────────────────────────────────────────
      if (id == 'transfer_out' || id == 'transfer_in') ...[
        _fieldLabel(id == 'transfer_out'
            ? 'Transfer To Account *' : 'Transfer From Account *'),
        const SizedBox(height: 6),
        DropdownButtonFormField<Map<String, dynamic>>(
          decoration: _inputDeco('Select account', Icons.account_balance_outlined),
          isExpanded: true,
          value: _selectedToAccount,
          items: _bankAccounts.map((a) => DropdownMenuItem(
              value: a,
              child: Text(a['accountName']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _selectedToAccount = v),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Amount'),
        const SizedBox(height: 6),
        TextFormField(controller: _amountCtrl, keyboardType: TextInputType.number,
            decoration: _inputDeco('Amount', Icons.currency_rupee)),
        const SizedBox(height: 12),
        _fieldLabel('Date *'),
        const SizedBox(height: 6),
        TextFormField(controller: _dateCtrl,
            decoration: _inputDeco('Date', Icons.calendar_today)),
        const SizedBox(height: 12),
        _fieldLabel('Notes (optional)'),
        const SizedBox(height: 6),
        TextFormField(controller: _descCtrl, maxLines: 2,
            decoration: _inputDeco('Notes', Icons.note_outlined)),
      ],

      // ── Income / Other fields ────────────────────────────────────────────
      if (id == 'interest_income' || id == 'other_income' ||
          id == 'expense_refund' || id == 'owner_contribution' ||
          id == 'vendor_credit_refund' || id == 'vendor_payment_refund' ||
          id == 'credit_note_refund' || id == 'payment_refund' ||
          id == 'card_payment' || id == 'owner_drawings') ...[
        _fieldLabel('Category Account *'),
        const SizedBox(height: 6),
        DropdownButtonFormField<COAOption>(
          decoration: _inputDeco('Select account', Icons.account_tree_outlined),
          isExpanded: true,
          value: _selectedCOA,
          items: (cat.group == 'money_in' ? _incomeCOAs : _expenseCOAs)
              .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text('${c.accountCode} - ${c.accountName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setState(() => _selectedCOA = v),
        ),
        const SizedBox(height: 12),
        _fieldLabel('Amount'),
        const SizedBox(height: 6),
        TextFormField(controller: _amountCtrl, keyboardType: TextInputType.number,
            decoration: _inputDeco('Amount', Icons.currency_rupee)),
        const SizedBox(height: 12),
        _fieldLabel('Date *'),
        const SizedBox(height: 6),
        TextFormField(controller: _dateCtrl,
            decoration: _inputDeco('Date', Icons.calendar_today)),
        const SizedBox(height: 12),
        _fieldLabel('Reference # (optional)'),
        const SizedBox(height: 6),
        TextFormField(controller: _refCtrl,
            decoration: _inputDeco('Reference #', Icons.tag_outlined)),
        const SizedBox(height: 12),
        _fieldLabel('Description (optional)'),
        const SizedBox(height: 6),
        TextFormField(controller: _descCtrl, maxLines: 2,
            decoration: _inputDeco('Description', Icons.note_outlined)),
      ],

      // Journal entry preview
      const SizedBox(height: 12),
      _buildJournalPreview(txn),
    ]);
  }

  Widget _buildJournalPreview(Map<String, dynamic> txn) {
    final cat    = _selectedCategory;
    if (cat == null) return const SizedBox.shrink();
    final amount = double.tryParse(_amountCtrl.text) ?? (txn['amount'] ?? 0).toDouble();
    if (amount <= 0) return const SizedBox.shrink();

    String dr = '', cr = '';
    if (cat.group == 'money_out') {
      dr = _selectedCOA?.accountName ?? cat.label;
      cr = widget.accountName;
    } else {
      dr = widget.accountName;
      cr = _selectedCOA?.accountName ?? cat.label;
    }
    if (cat.id == 'transfer_out') { dr = _selectedToAccount?['accountName'] ?? 'To Account'; cr = widget.accountName; }
    if (cat.id == 'transfer_in')  { dr = widget.accountName; cr = _selectedToAccount?['accountName'] ?? 'From Account'; }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.receipt_long, size: 13, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text('Journal Entry Preview',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[600])),
        ]),
        const Divider(height: 10),
        _jeRow('Dr', dr, amount),
        const SizedBox(height: 3),
        _jeRow('Cr', cr, amount, indent: true),
      ]),
    );
  }

  Widget _jeRow(String side, String account, double amount, {bool indent = false}) => Row(children: [
    SizedBox(width: indent ? 16 : 0),
    Container(
      width: 24, padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
          color: side == 'Dr' ? _red.withOpacity(0.08) : _green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(3)),
      child: Text(side, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
              color: side == 'Dr' ? _red : _green)),
    ),
    const SizedBox(width: 6),
    Expanded(child: Text(account, style: const TextStyle(fontSize: 11))),
    Text('₹${_fmt(amount)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
  ]);

  Future<void> _saveCategory(Map<String, dynamic> txn) async {
    final cat   = _selectedCategory!;
    final txnId = txn['_id']?.toString() ?? '';
    final amount = double.tryParse(_amountCtrl.text) ?? (txn['amount'] ?? 0).toDouble();

    setState(() => _categorizing = true);
    try {
      Map<String, dynamic> res;

      switch (cat.id) {
        case 'expense':
        case 'vendor_advance':
        case 'vendor_payment':
        case 'card_payment':
        case 'owner_drawings':
        case 'credit_note_refund':
        case 'payment_refund':
          if (_selectedCOA == null) { _showError('Select a category account'); setState(() => _categorizing = false); return; }
          res = await _service.categorizeAsExpense(
            providerTransactionId: txnId,
            coaAccountId: _selectedCOA!.id,
            vendorName:   null,
            notes:        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          );
          break;

        case 'customer_payment':
        case 'customer_advance':
        case 'interest_income':
        case 'other_income':
        case 'expense_refund':
        case 'owner_contribution':
        case 'vendor_credit_refund':
        case 'vendor_payment_refund':
          if (_selectedCOA == null) { _showError('Select a category account'); setState(() => _categorizing = false); return; }
          res = await _service.categorizeAsDeposit(
            providerTransactionId: txnId,
            coaAccountId:  _selectedCOA!.id,
            customerName:  null,
            notes:         _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          );
          break;

        case 'transfer_out':
        case 'transfer_in':
          if (_selectedToAccount == null) { _showError('Select destination account'); setState(() => _categorizing = false); return; }
          res = await _service.categorizeAsTransfer(
            providerTransactionId: txnId,
            toAccountId:           _selectedToAccount!['_id']?.toString() ?? '',
            notes:                 _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          );
          break;

        default:
          _showError('Unsupported category');
          setState(() => _categorizing = false);
          return;
      }

      setState(() => _categorizing = false);

      if (res['success'] == true) {
        _showSuccess('Categorized as ${cat.label}');
        _closePanel();
        _loadAll();
        widget.onCategorized?.call();
      } else {
        _showError(res['message'] ?? 'Failed');
      }
    } catch (e) {
      setState(() => _categorizing = false);
      _showError('Failed: $e');
    }
  }

  // ── All Transactions sub-tab ─────────────────────────────────────────────

  Widget _buildAllTransactionsTab() {
    if (_allTxns.isEmpty) return const Center(child: Text('No transactions yet'));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _allTxns.length,
      itemBuilder: (_, i) {
        final txn    = _allTxns[i];
        final isDebit= txn['transactionType'] == 'DEBIT';
        final amount = (txn['amount'] ?? 0).toDouble();
        final date   = _parseDate(txn['transactionDate'] ?? txn['date']);
        final status = txn['reconciliationStatus']?.toString() ?? '';
        final desc   = txn['description']?.toString() ?? '';

        Color statusColor;
        switch (status) {
          case 'CATEGORIZED': statusColor = _green;  break;
          case 'EXCLUDED':    statusColor = Colors.grey; break;
          default:            statusColor = _orange;
        }

        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: (isDebit ? _red : _green).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                  color: isDebit ? _red : _green, size: 18),
            ),
            title: Text(desc.isNotEmpty ? desc : (isDebit ? 'Debit' : 'Credit'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Row(children: [
              Text(DateFormat('dd MMM yyyy').format(date),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(status, style: TextStyle(fontSize: 9,
                    fontWeight: FontWeight.bold, color: statusColor)),
              ),
            ]),
            trailing: Text('${isDebit ? '−' : '+'}₹${_fmt(amount)}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                    color: isDebit ? _red : _green)),
          ),
        );
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _fieldLabel(String label) => Text(label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)));

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _navy, width: 1.5)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  String _fmt(double v)       => NumberFormat('#,##0.00').format(v);
  DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    try { return DateTime.parse(d.toString()); } catch (_) { return DateTime.now(); }
  }
  String _fmtDateStr(String d) {
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(d)); } catch (_) { return d; }
  }
}