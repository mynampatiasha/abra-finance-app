// ============================================================================
// ACCOUNT DETAIL PAGE — COMPLETE FINAL VERSION
// ============================================================================
// File: lib/screens/banking/account_detail_page.dart
//
// FLOW:
//   1. User clicks transaction → right panel opens from TOP (full height)
//   2. CATEGORIZE MANUALLY → category dropdown
//   3. Select category → pre-filled preview → Continue button
//   4. NewExpensePage / NewPaymentPage / NewPaymentMadeScreen opens INSIDE
//      the 40% panel with showAppBar: false
//   5. User fills form → saves → transaction disappears from list
//
// EMBEDDED CATEGORIES:
//   expense / card_payment / owner_drawings  → NewExpensePage(showAppBar:false)
//   customer_payment / customer_advance      → NewPaymentPage(showAppBar:false)
//   vendor_payment / vendor_advance          → NewPaymentMadeScreen(showAppBar:false)
//   transfer + simple categories             → inline form → direct API
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import '../../../core/services/bank_transaction_service.dart';
import '../../../core/services/add_account_service.dart';
import '../../../core/utils/detail_page_actions.dart';
import 'reconciliation_billing.dart';
import 'transaction_rules_screen.dart';
import 'bulk_import_bank_statement_dialog.dart';
import 'new_chart_of_account.dart';
import 'record_deposit_dialog.dart';
import 'manual_entry_dialog.dart';
import 'new_expenses.dart';
import 'new_payment_page.dart';
import 'new_payment_made.dart';
import '../../../core/services/payment_made_service.dart';
import '../../../core/services/billing_vendors_service.dart';
import '../../../core/services/vendor_credit_service.dart';
import '../../../core/services/billing_customers_service.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/services/credit_note_service.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navy       = Color(0xFF1e3a8a);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);
const Color _blue       = Color(0xFF2980B9);
const Color _orange     = Color(0xFFE67E22);
const Color _red        = Color(0xFFE74C3C);
const Color _purple     = Color(0xFF9B59B6);
const Color _teal       = Color(0xFF16A085);

class _Cat {
  final String id, label, group;
  final IconData icon;
  final Color color;
  const _Cat(this.id, this.label, this.group, this.icon, this.color);
}

const _moneyIn = [
  _Cat('customer_payment',      'Customer Payment',              'money_in', Icons.payments_outlined,        _green),
  _Cat('customer_advance',      'Customer Advance',              'money_in', Icons.person_add_outlined,      _green),
  _Cat('transfer_in',           'Transfer From Another Account', 'money_in', Icons.compare_arrows,           _blue),
  _Cat('interest_income',       'Interest Income',               'money_in', Icons.trending_up,              _teal),
  _Cat('other_income',          'Other Income',                  'money_in', Icons.add_circle_outline,       _teal),
  _Cat('expense_refund',        'Expense Refund',                'money_in', Icons.reply_outlined,           _green),
  _Cat('owner_contribution',    "Owner's Contribution",          'money_in', Icons.business_center_outlined, _navy),
  _Cat('vendor_credit_refund',  'Vendor Credit Refund',          'money_in', Icons.undo_outlined,            _green),
  _Cat('vendor_payment_refund', 'Vendor Payment Refund',         'money_in', Icons.reply_all_outlined,       _orange),
];

const _moneyOut = [
  _Cat('expense',            'Expense',                      'money_out', Icons.receipt_outlined,      _red),
  _Cat('vendor_advance',     'Vendor Advance',               'money_out', Icons.person_outlined,       _orange),
  _Cat('vendor_payment',     'Vendor Payment',               'money_out', Icons.payments_outlined,     _orange),
  _Cat('transfer_out',       'Transfer To Another Account',  'money_out', Icons.compare_arrows,        _blue),
  _Cat('card_payment',       'Card Payment',                 'money_out', Icons.credit_card_outlined,  _purple),
  _Cat('owner_drawings',     'Owner Drawings',               'money_out', Icons.person_pin_outlined,   _teal),
  _Cat('credit_note_refund', 'Credit Note Refund',           'money_out', Icons.undo_outlined,         _red),
  _Cat('payment_refund',     'Payment Refund',               'money_out', Icons.reply_outlined,        _orange),
];

class AccountDetailPage extends StatefulWidget {
  final String  accountId;
  final String  accountName;
  final String  accountType;
  final String? accountNumber;
  final int     initialTab;

  const AccountDetailPage({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.accountType,
    this.accountNumber,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage>
    with SingleTickerProviderStateMixin {

  final BankTransactionService _svc = BankTransactionService();
  late TabController _tabCtrl;

  int    _uncatCount   = 0;
  int    _catCount     = 0;
  int    _total        = 0;
  double _balance      = 0;
  bool   _statsLoading = true;

  List<Map<String,dynamic>> _txns    = [];
  List<Map<String,dynamic>> _allTxns = [];
  bool _txnsLoading = true;

  String _filter = 'All';
  String _allTxnsFilter = 'All';
  bool        _multiSelect = false;
  Set<String> _selectedIds = {};

  Map<String,dynamic>? _selectedTxn;
  bool _panelOpen = false;
  int  _panelTab  = 0;

  List<Map<String,dynamic>> _matches      = [];
  bool                      _matchLoading = false;

  _Cat?   _selectedCat;
  bool    _catDropOpen = false;
  String? _catSearch;

  // KEY: true = embedded page shown, false = category picker / inline form
  bool _showingEmbeddedPage = false;

  final _notesCtrl = TextEditingController();
  Map<String,dynamic>? _selectedToAccount;
  bool _panelSaving = false;

  List<Map<String,dynamic>> _bankAccounts = [];
  List<COAOption>           _expCOAs      = [];
  double _openingBalance = 0;

  // ── Categorized transaction panel (All Transactions tab) ──────────────────
  Map<String,dynamic>? _selectedCatTxn;
  bool  _catPanelOpen    = false;
  bool  _catPanelLoading = false;
  Map<String,dynamic>? _linkedRecord;

  bool _isEmbeddedCategory(_Cat cat) => const [
    'expense', 'card_payment', 'owner_drawings',
    'customer_payment', 'customer_advance',
    'vendor_payment', 'vendor_advance',
    'vendor_payment_refund',
    'vendor_credit_refund',
    'payment_refund',
    'credit_note_refund',
  ].contains(cat.id);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _tabCtrl.addListener(() => setState(() {}));
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadStats(), _loadTxns(), _loadSupport()]);
  }

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final r = await _svc.getStats(widget.accountId);
      if (r['success'] == true) {
        final d = r['data'];
        setState(() {
          _uncatCount   = d['uncategorized'] ?? 0;
          _catCount     = d['categorized']   ?? 0;
          _total        = d['total']          ?? 0;
          _balance      = (d['currentBalance'] ?? 0).toDouble();
          _statsLoading = false;
        });
      }
    } catch (_) { setState(() => _statsLoading = false); }
  }

  Future<void> _loadTxns() async {
    setState(() => _txnsLoading = true);
    try {
      final r  = await _svc.getUncategorized(accountId: widget.accountId, page: 1, limit: 200);
      final r2 = await _svc.getAllTransactions(accountId: widget.accountId);
      setState(() {
        if (r['success']  == true) _txns    = List<Map<String,dynamic>>.from(r['data']  ?? []);
        if (r2['success'] == true) _allTxns = List<Map<String,dynamic>>.from(r2['data'] ?? []);
        _txnsLoading = false;
      });
    } catch (_) { setState(() => _txnsLoading = false); }
  }

  Future<void> _loadSupport() async {
    try {
      _expCOAs = await _svc.getCOAOptions('expense');
      final all = await AddAccountService().getAllAccounts();
      setState(() {
        _bankAccounts = all
            .where((a) => a['_id'] != widget.accountId && (a['isActive'] ?? true))
            .map((a) => Map<String,dynamic>.from(a)).toList();
        // grab opening balance for this account
        final thisAcct = all.firstWhere(
          (a) => a['_id']?.toString() == widget.accountId,
          orElse: () => {},
        );
        _openingBalance = (thisAcct['openingBalance'] ?? 0).toDouble();
      });
    } catch (_) {}
  }

  double get _runningBalance {
    // Only categorized transactions, starting from opening balance
    final catTxns = _allTxns
        .where((t) => t['reconciliationStatus'] == 'CATEGORIZED')
        .toList();
    if (catTxns.isEmpty) return _openingBalance;
    final sorted = [...catTxns];
    sorted.sort((a, b) {
      final da = _parseDate(a['transactionDate'] ?? a['date']);
      final db = _parseDate(b['transactionDate'] ?? b['date']);
      return da.compareTo(db);
    });
    double running = _openingBalance;
    for (final txn in sorted) {
      final isDebit = txn['transactionType'] == 'DEBIT';
      final amount  = (txn['amount'] ?? 0).toDouble();
      running += isDebit ? -amount : amount;
    }
    return running;
  }

  List<Map<String,dynamic>> get _filteredAllTxns {
    // All Transactions tab only shows categorized/matched transactions
    final categorized = _allTxns
        .where((t) => t['reconciliationStatus'] == 'CATEGORIZED')
        .toList();
    return categorized;
  }

  List<Map<String,dynamic>> get _filtered {
    switch (_filter) {
      case 'Recognized': return _txns.where((t) => t['isRecognized'] == true).toList();
      case 'Excluded':   return _txns.where((t) => t['isExcluded']   == true).toList();
      default:           return _txns;
    }
  }

  void _openPanel(Map<String,dynamic> txn, {int tab = 0}) {
    setState(() {
      _selectedTxn         = txn;
      _panelOpen           = true;
      _panelTab            = tab;
      _selectedCat         = null;
      _catDropOpen         = false;
      _catSearch           = null;
      _showingEmbeddedPage = false;
      _selectedToAccount   = null;
      _panelSaving         = false;
      _notesCtrl.clear();
    });
    if (tab == 0) _loadMatches(txn);
  }

  void _closePanel() => setState(() {
    _panelOpen           = false;
    _selectedTxn         = null;
    _showingEmbeddedPage = false;
    _selectedCat         = null;
  });

  void _markAsCategorizedLocally(String txnId, String label) {
    setState(() {
      _txns.removeWhere((t) => t['_id']?.toString() == txnId);
      for (var t in _allTxns) {
        if (t['_id']?.toString() == txnId) {
          t['reconciliationStatus'] = 'CATEGORIZED';
          t['categoryLabel'] = label;
        }
      }
      _uncatCount = _uncatCount > 0 ? _uncatCount - 1 : 0;
      _catCount++;
    });
  }

  void _backToCategoryPicker() => setState(() {
    _showingEmbeddedPage = false;
    _selectedCat         = null;
    _catDropOpen         = false;
  });

  // Called by embedded page after successful save
  void _onEmbeddedPageSaved(String recordId) async {
    final txn = _selectedTxn;
    final cat = _selectedCat;
    if (txn != null && cat != null) {
      String linkedRecordType;
      switch (cat.id) {
        case 'expense':
        case 'card_payment':
        case 'owner_drawings':
          linkedRecordType = 'Expense';
          break;
        case 'customer_payment':
        case 'customer_advance':
          linkedRecordType = 'PaymentReceived';
          break;
        case 'vendor_payment':
        case 'vendor_advance':
          linkedRecordType = 'PaymentMade';
          break;
        case 'vendor_payment_refund':
          linkedRecordType = 'PaymentMade';
          break;
        case 'vendor_credit_refund':
          linkedRecordType = 'VendorCredit';
          break;
        case 'payment_refund':
          linkedRecordType = 'PaymentReceived';
          break;
        case 'credit_note_refund':
          linkedRecordType = 'CreditNote';
          break;
        default:
          linkedRecordType = 'Expense';
      }

      // vendor_credit_refund passes "creditId::refundId" so we can
      // store creditId as linkedRecordId and refundId as journalRef
      // for precise reversal on uncategorize.
      // credit_note_refund follows the exact same pattern.
      String linkedRecordId = recordId;
      String journalRef     = recordId;
      if ((cat.id == 'vendor_credit_refund' || cat.id == 'credit_note_refund') &&
          recordId.contains('::')) {
        final parts    = recordId.split('::');
        linkedRecordId = parts[0]; // creditId / creditNoteId
        journalRef     = parts[1]; // refund sub-doc _id
      }

      await _svc.markAsCategorized(
        providerTransactionId: txn['_id']?.toString() ?? '',
        categoryLabel:    cat.label,
        linkedRecordId:   linkedRecordId,
        linkedRecordType: linkedRecordType,
        journalRef:       journalRef,
      );
    }
    _showSuccess('Transaction categorized successfully');
    _closePanel();
    if (txn != null) _markAsCategorizedLocally(txn['_id']?.toString() ?? '', cat?.label ?? '');
  }

  Future<void> _loadMatches(Map<String,dynamic> txn) async {
    setState(() { _matchLoading = true; _matches = []; });
    try {
      final r = await _svc.getPossibleMatches(
        accountId: widget.accountId,
        amount:    (txn['amount'] ?? 0).toDouble(),
        txnType:   txn['transactionType'] ?? 'DEBIT',
        txnDate:   txn['transactionDate']?.toString() ?? '',
      );
      setState(() {
        _matches      = List<Map<String,dynamic>>.from(r['data'] ?? []);
        _matchLoading = false;
      });
    } catch (_) { setState(() => _matchLoading = false); }
  }

  Future<void> _saveSimpleCategory() async {
    final cat = _selectedCat;
    final txn = _selectedTxn;
    if (cat == null || txn == null) return;
    final txnId = txn['_id']?.toString() ?? '';
    setState(() => _panelSaving = true);
    try {
      Map<String,dynamic> result;
      if (cat.id == 'transfer_in' || cat.id == 'transfer_out') {
        if (_selectedToAccount == null) {
          _showError('Please select an account');
          setState(() => _panelSaving = false);
          return;
        }
        result = await _svc.categorizeAsTransfer(
          providerTransactionId: txnId,
          toAccountId: _selectedToAccount!['_id']?.toString() ?? '',
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        result = await _svc.categorizeAsDeposit(
          providerTransactionId: txnId,
          categoryType: cat.id,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      }
      if (result['success'] == true) {
        _showSuccess('Transaction categorized');
        _closePanel();
        _markAsCategorizedLocally(txnId, cat.label);
      } else if (result['code'] == 'COA_ACCOUNT_MISSING') {
        // The required COA account doesn't exist yet — take the user to create it
        final suggestedName    = result['suggestedName']    as String?;
        final suggestedType    = result['suggestedType']    as String?;
        final suggestedSubType = result['suggestedSubType'] as String?;
        setState(() => _panelSaving = false);
        final created = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Account Not Found'),
            content: Text(
              'The account "${suggestedName ?? 'required account'}" doesn\'t exist yet.\n\n'
              'Create it now to continue categorizing this transaction.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Create Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
        if (created == true && mounted) {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => NewChartOfAccountScreen(
                initialName:    suggestedName,
                initialType:    suggestedType,
                initialSubType: suggestedSubType,
              ),
            ),
          );
          if (ok == true) {
            // Account created — retry the categorization automatically
            _saveSimpleCategory();
          }
        }
        return;
      } else {
        _showError(result['message'] ?? 'Failed');
      }
    } catch (e) { _showError('Failed: $e'); }
    setState(() => _panelSaving = false);
  }

void _openReconcile() {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ReconciliationBillingPage(
      accountId:   widget.accountId,
      accountName: widget.accountName,
      accountType: widget.accountType,
    ),
  )).then((_) { if (mounted) _loadAll(); });
}
  // ==========================================================================
  //  BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Stack(children: [
        Column(children: [
          _buildHeader(),
          _buildAmountStrip(),
          _buildTabsRow(),
          Expanded(child: TabBarView(
            controller: _tabCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildDashboard(),
              _buildUncatContent(),
              _buildAllTxnsTab(),
            ],
          )),
        ]),
        if (_panelOpen && _tabCtrl.index == 1)
          _buildOverlayPanel(),
        if (_catPanelOpen && _selectedCatTxn != null && _tabCtrl.index == 2)
          _buildCatTxnPanel(),
      ]),
    );
  }

  Widget _buildHeader() {
    final isWide = MediaQuery.of(context).size.width > 750;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
        boxShadow: [BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0,2))],
      ),
      child: Row(children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(6),
          child: const Padding(padding: EdgeInsets.all(6),
              child: Icon(Icons.arrow_back, size: 18, color: Color(0xFF2C3E50))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(widget.accountName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A)), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF5D6D7E)),
          ]),
          if (widget.accountNumber != null)
            Text('Account Number: ${widget.accountNumber}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF7F8C8D))),
        ])),
        const SizedBox(width: 8),
        if (isWide) ...[
          // TextButton.icon(
          //   onPressed: () {},
          //   icon: const Icon(Icons.description_outlined, size: 14, color: _blue),
          //   label: const Text('Bank Statements',
          //       style: TextStyle(fontSize: 12, color: _blue, fontWeight: FontWeight.w500)),
          //   style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), minimumSize: Size.zero),
          // ),
          // const SizedBox(width: 4),
          // _addTxnDropdown(),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: _showRecordDeposit,
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2C3E50), side: const BorderSide(color: Color(0xFFCBD5E1)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), minimumSize: Size.zero),
            child: const Text('Record Deposit', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: _showImport,
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2C3E50), side: const BorderSide(color: Color(0xFFCBD5E1)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), minimumSize: Size.zero),
            child: const Text('Import Statement', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: _openReconcile,
            icon: const Icon(Icons.balance, size: 13),
            label: const Text('Reconcile', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(foregroundColor: _teal, side: const BorderSide(color: _teal), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)), minimumSize: Size.zero),
          ),
          const SizedBox(width: 6),
          _headerIcon(Icons.settings_outlined, _showRules),
          const SizedBox(width: 4),
          _headerIcon(Icons.refresh_rounded, _loadAll, color: _navyAccent),
          const SizedBox(width: 4),
          _headerIcon(Icons.close, () => Navigator.pop(context), color: _red),
        ] else ...[
          // _addTxnDropdown(),
          // const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF5D6D7E)),
            onSelected: (v) {
              if (v == 'import')    _showImport();
              if (v == 'deposit')   _showRecordDeposit();
              if (v == 'rules')     _showRules();
              if (v == 'reconcile') _openReconcile();
              if (v == 'refresh')   _loadAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh',   child: Text('Refresh')),
              PopupMenuItem(value: 'import',    child: Text('Import Statement')),
              PopupMenuItem(value: 'deposit',   child: Text('Record Deposit')),
              PopupMenuItem(value: 'reconcile', child: Text('Reconcile')),
              PopupMenuItem(value: 'rules',     child: Text('Transaction Rules')),
            ],
          ),
        ],
      ]),
    );
  }

  // Widget _addTxnDropdown() => PopupMenuButton<String>(
  //   onSelected: (type) => showDialog(context: context,
  //       builder: (_) => ManualEntryDialog(accountId: widget.accountId, accountName: widget.accountName, initialType: type, onSaved: () { _loadAll(); _showSuccess('Transaction added'); })),
  //   itemBuilder: (_) => const [
  //     PopupMenuItem(value: 'expense',  child: Text('Expense')),
  //     PopupMenuItem(value: 'deposit',  child: Text('Deposit')),
  //     PopupMenuItem(value: 'transfer', child: Text('Transfer')),
  //   ],
  //   child: Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  //     decoration: BoxDecoration(color: _navyAccent, borderRadius: BorderRadius.circular(6)),
  //     child: Row(mainAxisSize: MainAxisSize.min, children: const [
  //       Text('Add Transaction', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
  //       SizedBox(width: 4),
  //       Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
  //     ]),
  //   ),
  // );

  Widget _headerIcon(IconData icon, VoidCallback onTap, {Color color = const Color(0xFF64748B)}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 15, color: color),
        ),
      );

  Widget _buildAmountStrip() => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _blue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.account_balance_outlined, color: _blue, size: 20),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _tabCtrl.index == 2
              ? 'Current Balance (Categorized)'
              : 'Amount',
          style: const TextStyle(fontSize: 12, color: Color(0xFF7F8C8D)),
        ),
        Text(
          _txnsLoading
              ? 'Loading...'
              : '₹${NumberFormat('#,##,##0.00').format(
                  _tabCtrl.index == 2 ? _runningBalance : _balance
                )}',
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
      ]),
      const Spacer(),
    ]),
  );

  Widget _buildTabsRow() => Container(
    color: Colors.white,
    child: Column(children: [
      Row(children: [
        Expanded(child: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: _navyAccent,
          unselectedLabelColor: const Color(0xFF64748B),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          indicatorColor: _navyAccent,
          indicatorWeight: 2,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Dashboard'),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_uncatCount > 0) Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: _navyAccent, borderRadius: BorderRadius.circular(10)),
                child: Text('$_uncatCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const Text('Uncategorized Transactions'),
              const SizedBox(width: 4),
              const Text('From Bank Statements', style: TextStyle(fontSize: 10, color: Color(0xFF7F8C8D))),
            ])),
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('All Transactions'),
              SizedBox(width: 4),

              Icon(Icons.keyboard_arrow_down, size: 14),
            ])),
          ],
        )),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(children: [
            Text('Multi-Select & Match', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
            const SizedBox(width: 6),
            Switch(value: _multiSelect, activeColor: _navyAccent, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, onChanged: (v) => setState(() { _multiSelect = v; if (!v) _selectedIds.clear(); })),
          ]),
        ),
      ]),
      const Divider(height: 1, color: Color(0xFFE8ECF0)),
    ]),
  );

  Widget _buildDashboard() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Account Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (_, c) {
        final cards = [_dashCard('Uncategorized', '$_uncatCount', _orange), _dashCard('Categorized', '$_catCount', _green), _dashCard('Total', '$_total', _blue)];
        if (c.maxWidth > 480) return Row(children: cards.asMap().entries.map((e) => Expanded(child: Padding(padding: EdgeInsets.only(right: e.key < 2 ? 10 : 0), child: e.value))).toList());
        return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: c)).toList());
      }),
      if (_uncatCount > 0) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _orange.withOpacity(0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: _orange.withOpacity(0.2))),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: _orange, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text('$_uncatCount transactions need categorization', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            TextButton(onPressed: () => _tabCtrl.animateTo(1), style: TextButton.styleFrom(foregroundColor: _orange, padding: EdgeInsets.zero, minimumSize: Size.zero), child: const Text('Categorize now ›', style: TextStyle(fontSize: 12))),
          ]),
        ),
      ],
    ]),
  );

  Widget _dashCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.15)), boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 6, offset: const Offset(0,2))]),
    child: Row(children: [
      Container(width: 4, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7F8C8D))),
      ]),
    ]),
  );

  Widget _buildUncatContent() => Column(children: [
    _buildFilterRow(),
    Expanded(child: _txnsLoading ? const Center(child: CircularProgressIndicator(color: _navyAccent)) : _filtered.isEmpty ? _buildEmptyState() : _buildTable()),
  ]);

  Widget _buildFilterRow() => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
    child: Row(children: [
      _chip('All', '${_txns.length}'),
      const SizedBox(width: 8),
      _chip('Recognized', '${_txns.where((t) => t['isRecognized'] == true).length}'),
      const Spacer(),
      GestureDetector(
        onTap: () => setState(() => _filter = 'Excluded'),
        child: Text('Excluded', style: TextStyle(fontSize: 13, color: _filter == 'Excluded' ? _navyAccent : const Color(0xFF5D6D7E), fontWeight: _filter == 'Excluded' ? FontWeight.w600 : FontWeight.normal)),
      ),
    ]),
  );

  Widget _chip(String label, String count) {
    final sel = _filter == label;
    return InkWell(
      onTap: () => setState(() => _filter = label),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(color: sel ? _navyAccent : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? _navyAccent : const Color(0xFFCBD5E1))),
        child: Text('$label ($count)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF5D6D7E))),
      ),
    );
  }

  Widget _allTxnsChip(String label) {
    final sel = _allTxnsFilter == label;
    return InkWell(
      onTap: () => setState(() => _allTxnsFilter = label),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? _navyAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? _navyAccent : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: sel ? Colors.white : const Color(0xFF5D6D7E)),
        ),
      ),
    );
  }

  Widget _buildTable() => Column(children: [
    Container(
      color: const Color(0xFFF8F9FB),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(width: 36, child: Checkbox(value: _selectedIds.length == _filtered.length && _filtered.isNotEmpty, tristate: true, onChanged: (v) => setState(() { if (v == true) _selectedIds = _filtered.map((t) => t['_id'].toString()).toSet(); else _selectedIds.clear(); }), activeColor: _navyAccent, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
        _col('DATE ↕', 100),
        const Expanded(child: Text('STATEMENT DETAILS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7F8C8D), letterSpacing: 0.4))),
        _col('DEPOSITS', 110, align: TextAlign.right),
        _col('WITHDRAWALS', 110, align: TextAlign.right),
        const SizedBox(width: 36, child: Icon(Icons.search, size: 14, color: Color(0xFF7F8C8D))),
      ]),
    ),
    const Divider(height: 1, color: Color(0xFFEEF2F7)),
    Expanded(child: RefreshIndicator(color: _navyAccent, onRefresh: _loadAll, child: ListView.separated(physics: const AlwaysScrollableScrollPhysics(), itemCount: _filtered.length, separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)), itemBuilder: (_, i) => _buildRow(_filtered[i])))),
  ]);

  Widget _col(String label, double width, {TextAlign align = TextAlign.left}) =>
      SizedBox(width: width, child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7F8C8D), letterSpacing: 0.4), textAlign: align));

  Widget _buildRow(Map<String,dynamic> txn) {
    final id         = txn['_id']?.toString() ?? '';
    final isDebit    = txn['transactionType'] == 'DEBIT';
    final amount     = (txn['amount'] ?? 0).toDouble();
    final date       = _parseDate(txn['transactionDate']);
    final refNum     = txn['referenceNumber']?.toString() ?? '';
    final desc       = txn['description']?.toString() ?? '';
    final payee      = txn['payee']?.toString() ?? txn['vendorName']?.toString() ?? txn['customerName']?.toString() ?? '';
    final isSelected = _selectedTxn?['_id']?.toString() == id;
    final isChecked  = _selectedIds.contains(id);

    return InkWell(
      onTap: () => _openPanel(txn),
      child: Container(
        color: isSelected ? _navyAccent.withOpacity(0.05) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 36, child: Checkbox(value: isChecked, onChanged: (_) => setState(() { if (isChecked) _selectedIds.remove(id); else _selectedIds.add(id); }), activeColor: _navyAccent, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
          SizedBox(width: 100, child: Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50), fontWeight: FontWeight.w500))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (refNum.isNotEmpty) Text('Reference#: $refNum', style: const TextStyle(fontSize: 12, color: Color(0xFF2C3E50))),
            if (desc.isNotEmpty)   Text('Description: $desc', style: const TextStyle(fontSize: 12, color: Color(0xFF5D6D7E))),
            if (payee.isNotEmpty)  Text('Payee: $payee', style: const TextStyle(fontSize: 12, color: Color(0xFF5D6D7E))),
          ])),
          SizedBox(width: 110, child: Text(!isDebit ? '₹${NumberFormat('#,##,##0.00').format(amount)}' : '', style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50), fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
          SizedBox(width: 110, child: Text(isDebit ? '₹${NumberFormat('#,##,##0.00').format(amount)}' : '', style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50), fontWeight: FontWeight.w500), textAlign: TextAlign.right)),
          SizedBox(width: 80, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            InkWell(
              onTap: () => _editTransaction(txn),
              child: const Padding(padding: EdgeInsets.all(6),
                  child: Icon(Icons.edit_outlined, size: 15, color: Color(0xFF7F8C8D))),
            ),
            InkWell(
              onTap: () => _confirmDeleteTransaction(txn),
              child: const Padding(padding: EdgeInsets.all(6),
                  child: Icon(Icons.delete_outline, size: 15, color: Color(0xFFE74C3C))),
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.check_circle_outline, size: 52, color: Colors.grey[300]),
    const SizedBox(height: 14),
    const Text('No uncategorized transactions', style: TextStyle(fontSize: 14, color: Color(0xFF7F8C8D))),
    const SizedBox(height: 16),
    OutlinedButton.icon(onPressed: _showImport, icon: const Icon(Icons.upload_file_outlined, size: 16), label: const Text('Import Statement'), style: OutlinedButton.styleFrom(foregroundColor: _navyAccent, side: const BorderSide(color: _navyAccent))),
  ]));

  Widget _buildAllTxnsTab() {
    if (_txnsLoading) return const Center(
        child: CircularProgressIndicator(color: _navyAccent));
    final categorizedTxns = _allTxns
        .where((t) => t['reconciliationStatus'] == 'CATEGORIZED')
        .toList();
    if (categorizedTxns.isEmpty) return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.receipt_long_outlined, size: 52, color: Colors.grey[300]),
      const SizedBox(height: 14),
      const Text('No categorized transactions yet',
          style: TextStyle(fontSize: 14, color: Color(0xFF7F8C8D))),
    ]));

    // ── Calculate running balance oldest → newest (categorized only, from opening balance) ──
    final sorted = _allTxns
        .where((t) => t['reconciliationStatus'] == 'CATEGORIZED')
        .toList();
    sorted.sort((a, b) {
      final da = _parseDate(a['transactionDate'] ?? a['date']);
      final db = _parseDate(b['transactionDate'] ?? b['date']);
      return da.compareTo(db);
    });

    double running = _openingBalance;
    final runningBalances = <String, double>{};
    for (final txn in sorted) {
      final id      = txn['_id']?.toString() ?? '';
      final isDebit = txn['transactionType'] == 'DEBIT';
      final amount  = (txn['amount'] ?? 0).toDouble();
      running += isDebit ? -amount : amount;
      runningBalances[id] = running;
    }

    return Stack(children: [
      Column(children: [

        // ── Column header row ──────────────────────────────────────────────
        Container(
          color: const Color(0xFFF8F9FB),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7))),
          ),
          child: Row(children: [
            // DATE
            SizedBox(width: 90,
                child: Text('DATE',
                    style: _hdrStyle)),
            const SizedBox(width: 10),
            // TYPE
            Expanded(
                child: Text('TYPE',
                    style: _hdrStyle)),
            // STATUS
            SizedBox(width: 90,
                child: Text('STATUS',
                    style: _hdrStyle, textAlign: TextAlign.center)),
            // DEPOSITS
            SizedBox(width: 100,
                child: Text('DEPOSITS',
                    style: _hdrStyle, textAlign: TextAlign.right)),
            // WITHDRAWALS
            SizedBox(width: 100,
                child: Text('WITHDRAWALS',
                    style: _hdrStyle, textAlign: TextAlign.right)),
            // RUNNING BALANCE
            SizedBox(width: 110,
                child: Text('RUNNING BALANCE',
                    style: _hdrStyle, textAlign: TextAlign.right)),
            // actions space
            const SizedBox(width: 40),
          ]),
        ),

        // ── Transaction rows ───────────────────────────────────────────────
        Expanded(child: ListView.separated(
          itemCount: _filteredAllTxns.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFEEF2F7)),
          itemBuilder: (_, i) {
            final txn      = _filteredAllTxns[i];
            final id       = txn['_id']?.toString() ?? '';
            final isDebit  = txn['transactionType'] == 'DEBIT';
            final amount   = (txn['amount'] ?? 0).toDouble();
            final date     = _parseDate(txn['transactionDate'] ?? txn['date']);
            final status   = txn['reconciliationStatus']?.toString() ?? 'UNCATEGORIZED';
            final desc     = txn['description']?.toString() ?? '';
            final catLabel = txn['categoryLabel']?.toString() ?? '';
            final refNum   = txn['referenceNumber']?.toString() ?? '';
            final payee    = txn['payee']?.toString() ?? txn['vendorName']?.toString() ?? txn['customerName']?.toString() ?? '';
            final isCat    = status == 'CATEGORIZED';
            final isSelected =
                _selectedCatTxn?['_id']?.toString() == id;
            final runBal   = runningBalances[id] ?? 0.0;

            // Status color
            Color sc;
            switch (status) {
              case 'CATEGORIZED': sc = _green;      break;
              case 'EXCLUDED':    sc = Colors.grey; break;
              default:            sc = _orange;
            }

            // Status label — match Zoho Books style
            String statusLabel;
            switch (status) {
              case 'CATEGORIZED':   statusLabel = 'Categorized';    break;
              case 'EXCLUDED':      statusLabel = 'Excluded';       break;
              case 'UNCATEGORIZED': statusLabel = 'Unmatched';      break;
              default:              statusLabel = status;
            }

            return InkWell(
              onTap: isCat
                  ? () => _openCatPanel(txn)
                  : () => _editTransaction(txn),
              child: Container(
                color: isSelected
                    ? _navyAccent.withOpacity(0.05)
                    : Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // DATE
                    SizedBox(width: 90, child: Text(
                      DateFormat('dd/MM/yyyy').format(date),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF5D6D7E)),
                    )),
                    const SizedBox(width: 10),

                    // TYPE — category label + description
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            desc.isNotEmpty ? desc : (isCat && catLabel.isNotEmpty ? catLabel : (isDebit ? 'Debit' : 'Credit')),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF2C3E50)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (payee.isNotEmpty)
                            Text('Payee: $payee',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7F8C8D)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          if (isCat && catLabel.isNotEmpty)
                            Text('Category: $catLabel',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7F8C8D)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          if (refNum.isNotEmpty)
                            Text('Ref: $refNum',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7F8C8D)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ])),

                    // STATUS badge
                    SizedBox(width: 90, child: Center(child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: sc.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: sc),
                          textAlign: TextAlign.center),
                    ))),

                    // DEPOSITS — only if CREDIT
                    SizedBox(width: 100, child: Text(
                      !isDebit
                          ? '₹${NumberFormat('#,##,##0.00').format(amount)}'
                          : '',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF27AE60)),
                      textAlign: TextAlign.right,
                    )),

                    // WITHDRAWALS — only if DEBIT
                    SizedBox(width: 100, child: Text(
                      isDebit
                          ? '₹${NumberFormat('#,##,##0.00').format(amount)}'
                          : '',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE74C3C)),
                      textAlign: TextAlign.right,
                    )),

                    // RUNNING BALANCE
                    SizedBox(width: 110, child: Text(
                      '₹${NumberFormat('#,##,##0.00').format(runBal)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: runBal >= 0
                              ? const Color(0xFF2C3E50)
                              : _red),
                      textAlign: TextAlign.right,
                    )),

                    // Actions
                    SizedBox(width: 40, child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!isCat) ...[
                          InkWell(
                            onTap: () => _confirmDeleteTransaction(txn),
                            child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.delete_outline,
                                    size: 14, color: Color(0xFFE74C3C))),
                          ),
                        ],
                        if (isCat)
                          const Icon(Icons.chevron_right,
                              size: 16, color: Color(0xFF7F8C8D)),
                      ],
                    )),
                  ],
                ),
              ),
            );
          },
        )),
      ]),

      // Categorized panel overlay
      if (_catPanelOpen && _selectedCatTxn != null)
        _buildCatTxnPanel(),
    ]);
  }

  // Header column style
  static const TextStyle _hdrStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.bold,
    color: Color(0xFF7F8C8D),
    letterSpacing: 0.4,
  );

  void _openCatPanel(Map<String,dynamic> txn) async {
    setState(() {
      _selectedCatTxn  = txn;
      _catPanelOpen    = true;
      _catPanelLoading = true;
      _linkedRecord    = null;
    });

    final linkedId   = txn['linkedRecordId']?.toString() ?? '';
    final linkedType = txn['linkedRecordType']?.toString() ?? '';
    if (linkedId.isNotEmpty && linkedType.isNotEmpty) {
      try {
        final r = await _svc.getLinkedRecord(
          linkedRecordId:   linkedId,
          linkedRecordType: linkedType,
        );
        if (r['success'] == true) {
          setState(() => _linkedRecord = r['data'] as Map<String,dynamic>?);
        }
      } catch (_) {}
    }
    setState(() => _catPanelLoading = false);
  }

  void _closeCatPanel() => setState(() {
    _catPanelOpen   = false;
    _selectedCatTxn = null;
    _linkedRecord   = null;
  });

  // Print a simple transaction receipt using only bank transaction data
  void _printTransactionReceipt(Map<String, dynamic> txn) {
    final isDebit  = txn['transactionType'] == 'DEBIT';
    final amount   = (txn['amount'] ?? 0).toDouble();
    final date     = _parseDate(txn['transactionDate'] ?? txn['date']);
    final desc     = txn['description']?.toString() ?? '';
    final ref      = txn['referenceNumber']?.toString() ?? '';
    final catLabel = txn['categoryLabel']?.toString() ?? '';

    // Build simple HTML receipt
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Transaction Receipt</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; }
    .header { text-align: center; margin-bottom: 30px; border-bottom: 2px solid #333; padding-bottom: 15px; }
    .header h1 { margin: 0; font-size: 24px; color: #0D1B3E; }
    .header p { margin: 5px 0; color: #666; font-size: 12px; }
    .content { margin: 20px 0; }
    .row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #eee; }
    .row .label { font-weight: bold; color: #555; }
    .row .value { color: #000; }
    .amount-box { background: ${isDebit ? '#fee' : '#efe'}; padding: 15px; margin: 20px 0; text-align: center; border-radius: 8px; }
    .amount-box .label { font-size: 12px; color: #666; margin-bottom: 5px; }
    .amount-box .amount { font-size: 28px; font-weight: bold; color: ${isDebit ? '#E74C3C' : '#27AE60'}; }
    .footer { margin-top: 40px; text-align: center; font-size: 11px; color: #999; }
  </style>
</head>
<body>
  <div class="header">
    <h1>TRANSACTION RECEIPT</h1>
    <p>${widget.accountName}</p>
    <p>Account Number: ${widget.accountNumber ?? 'N/A'}</p>
  </div>
  
  <div class="content">
    <div class="amount-box">
      <div class="label">${isDebit ? 'DEBIT' : 'CREDIT'}</div>
      <div class="amount">${isDebit ? '-' : '+'}₹${NumberFormat('#,##,##0.00').format(amount)}</div>
    </div>
    
    <div class="row">
      <span class="label">Date:</span>
      <span class="value">${DateFormat('dd MMM yyyy, hh:mm a').format(date)}</span>
    </div>
    
    <div class="row">
      <span class="label">Category:</span>
      <span class="value">${catLabel.isNotEmpty ? catLabel : 'Uncategorized'}</span>
    </div>
    
    ${desc.isNotEmpty ? '<div class="row"><span class="label">Description:</span><span class="value">$desc</span></div>' : ''}
    
    ${ref.isNotEmpty ? '<div class="row"><span class="label">Reference:</span><span class="value">$ref</span></div>' : ''}
    
    <div class="row">
      <span class="label">Transaction ID:</span>
      <span class="value">${txn['_id']?.toString() ?? 'N/A'}</span>
    </div>
  </div>
  
  <div class="footer">
    <p>Generated on ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}</p>
    <p>This is a computer-generated receipt</p>
  </div>
  
  <script>
    window.onload = function() {
      window.print();
    };
  </script>
</body>
</html>
''';

    // Open in new window and trigger print
    if (kIsWeb) {
      final blob = html.Blob([htmlContent], 'text/html');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
      Future.delayed(const Duration(seconds: 2), () => html.Url.revokeObjectUrl(url));
    } else {
      // For mobile, show a dialog with the receipt data
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Transaction Receipt'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${isDebit ? 'DEBIT' : 'CREDIT'}: ${isDebit ? '-' : '+'}₹${NumberFormat('#,##,##0.00').format(amount)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                        color: isDebit ? _red : _green)),
                const SizedBox(height: 10),
                Text('Date: ${DateFormat('dd MMM yyyy').format(date)}'),
                Text('Category: ${catLabel.isNotEmpty ? catLabel : 'Uncategorized'}'),
                if (desc.isNotEmpty) Text('Description: $desc'),
                if (ref.isNotEmpty) Text('Reference: $ref'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildCatTxnPanel() {
    final txn      = _selectedCatTxn!;
    final isDebit  = txn['transactionType'] == 'DEBIT';
    final amount   = (txn['amount'] ?? 0).toDouble();
    final date     = _parseDate(txn['transactionDate'] ?? txn['date']);
    final desc     = txn['description']?.toString() ?? '';
    final catLabel = txn['categoryLabel']?.toString() ?? '';
    final linkedId   = txn['linkedRecordId']?.toString() ?? '';
    final linkedType = txn['linkedRecordType']?.toString() ?? '';

    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      final panelW    = isDesktop ? constraints.maxWidth * 0.42 : constraints.maxWidth;

      return Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeCatPanel,
            child: Container(color: Colors.black.withOpacity(0.15)),
          ),
        ),
        Positioned(
          top: 0, right: 0, bottom: 0,
          width: panelW,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x20000000), blurRadius: 20, offset: Offset(-4, 0))],
            ),
            child: Column(children: [

              // ── Header ──────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7))),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (isDebit ? _red : _green).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${isDebit ? '-' : '+'}₹${NumberFormat('#,##,##0.00').format(amount)}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                          color: isDebit ? _red : _green),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(desc.isNotEmpty ? desc : (isDebit ? 'Debit' : 'Credit'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                            color: Color(0xFF2C3E50)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(DateFormat('dd MMM yyyy').format(date),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF7F8C8D))),
                    if (catLabel.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(catLabel, style: TextStyle(fontSize: 10,
                            fontWeight: FontWeight.w600, color: _green)),
                      ),
                  ])),
                  InkWell(onTap: _closeCatPanel,
                      child: const Icon(Icons.close, size: 16, color: Color(0xFF7F8C8D))),
                ]),
              ),

              // ── Linked record details ────────────────────────────────────
              if (_catPanelLoading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator(color: _navyAccent, strokeWidth: 2)),
                )
              else if (_linkedRecord != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: _buildLinkedRecordDetails(linkedType, _linkedRecord!),
                ),

              const Spacer(),

              // ── Action buttons ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _closeCatPanel();
                        _openEditLinkedRecord(txn);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navyAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _printTransactionReceipt(txn),
                        icon: const Icon(Icons.print_outlined, size: 15),
                        label: const Text('Print Receipt', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _blue,
                          side: const BorderSide(color: _blue),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _closeCatPanel();
                        _confirmUncategorize(txn);
                      },
                      icon: const Icon(Icons.undo_outlined, size: 15),
                      label: const Text('Uncategorize', style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _orange,
                        side: const BorderSide(color: _orange),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]);
    });
  }

  Widget _buildLinkedRecordDetails(String linkedType, Map<String,dynamic> record) {
    final rows = <Map<String,String>>[];

    switch (linkedType) {
      case 'Expense':
        if (record['expenseNumber'] != null) rows.add({'Expense #': record['expenseNumber'].toString()});
        if (record['expenseAccount'] != null) rows.add({'Account': record['expenseAccount'].toString()});
        if ((record['vendor'] ?? '').toString().isNotEmpty) rows.add({'Vendor': record['vendor'].toString()});
        if (record['paidThrough'] != null) rows.add({'Paid Through': record['paidThrough'].toString()});
        if (record['total'] != null) rows.add({'Total': '₹${(record['total'] as num).toStringAsFixed(2)}'});
        if ((record['notes'] ?? '').toString().isNotEmpty) rows.add({'Notes': record['notes'].toString()});
        break;
      case 'PaymentReceived':
        if (record['paymentNumber'] != null) rows.add({'Payment #': record['paymentNumber'].toString()});
        if (record['customerName'] != null) rows.add({'Customer': record['customerName'].toString()});
        if (record['amountReceived'] != null)
          rows.add({'Amount': '₹${(record['amountReceived'] as num).toStringAsFixed(2)}'});
        if (record['paymentMode'] != null) rows.add({'Mode': record['paymentMode'].toString()});
        if ((record['reference'] ?? '').toString().isNotEmpty) rows.add({'Reference': record['reference'].toString()});
        break;
      case 'PaymentMade':
        if (record['paymentNumber'] != null) rows.add({'Payment #': record['paymentNumber'].toString()});
        if (record['vendorName'] != null) rows.add({'Vendor': record['vendorName'].toString()});
        if (record['amount'] != null)
          rows.add({'Amount': '₹${(record['amount'] as num).toStringAsFixed(2)}'});
        if (record['paymentMode'] != null) rows.add({'Mode': record['paymentMode'].toString()});
        if ((record['reference'] ?? '').toString().isNotEmpty) rows.add({'Reference': record['reference'].toString()});
        break;
      case 'CreditNote':
        if (record['creditNoteNumber'] != null) rows.add({'Credit Note #': record['creditNoteNumber'].toString()});
        if (record['customerName'] != null) rows.add({'Customer': record['customerName'].toString()});
        if (record['totalAmount'] != null)
          rows.add({'Total Amount': '₹${(record['totalAmount'] as num).toStringAsFixed(2)}'});
        if (record['creditBalance'] != null)
          rows.add({'Balance': '₹${(record['creditBalance'] as num).toStringAsFixed(2)}'});
        if (record['status'] != null) rows.add({'Status': record['status'].toString()});
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(linkedType, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
            color: Color(0xFF7F8C8D), letterSpacing: 0.5)),
        const SizedBox(height: 10),
        ...rows.map((r) {
          final label = r.keys.first;
          final value = r.values.first;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7F8C8D))),
                Flexible(child: Text(value,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E50)),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right)),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  void _openEditLinkedRecord(Map<String,dynamic> txn) {
    final linkedType = txn['linkedRecordType']?.toString() ?? '';
    final linkedId   = txn['linkedRecordId']?.toString() ?? '';
    final amount     = (txn['amount'] ?? 0).toDouble();
    final date       = _parseDate(txn['transactionDate'] ?? txn['date']);
    final ref        = txn['referenceNumber']?.toString() ?? '';

    if (linkedId.isEmpty) { _editTransaction(txn); return; }

    Widget page;
    switch (linkedType) {
      case 'Expense':
        page = NewExpensePage(
          expenseId: linkedId,
          showAppBar: true,
          onSavedCallback: (_) { _loadAll(); _showSuccess('Expense updated'); },
        );
        break;
      case 'PaymentReceived':
        page = NewPaymentPage(
          showAppBar: true,
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          onSavedCallback: (_) { _loadAll(); _showSuccess('Payment updated'); },
        );
        break;
      case 'PaymentMade':
        page = NewPaymentMadeScreen(
          paymentId: linkedId,
          showAppBar: true,
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          onSavedCallback: (_) { _loadAll(); _showSuccess('Payment updated'); },
        );
        break;
      default:
        _editTransaction(txn);
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => page))
        .then((_) => _loadAll());
  }

  // ==========================================================================
  //  OVERLAY PANEL — positioned at TOP
  // ==========================================================================

  Widget _buildOverlayPanel() {
    return LayoutBuilder(builder: (context, constraints) {
      final isDesktop = constraints.maxWidth > 900;
      final panelW    = isDesktop ? constraints.maxWidth * 0.42 : constraints.maxWidth;
      return Stack(children: [
        Positioned(top: 0, right: 0, bottom: 0, width: panelW, child: _buildRightPanel()),
      ]);
    });
  }

  Widget _buildRightPanel() {
    // ✅ Embedded page fills the panel when Continue is tapped
    if (_showingEmbeddedPage && _selectedCat != null && _selectedTxn != null) {
      return _buildEmbeddedPagePanel();
    }
    return Container(
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x20000000), blurRadius: 20, offset: Offset(-4,0))]),
      child: Column(children: [
        _buildPanelHeader(),
        _buildPanelTabs(),
        Expanded(child: _panelTab == 0 ? _buildMatchPanel() : _buildCatPanel()),
      ]),
    );
  }

  // ==========================================================================
  //  EMBEDDED PAGE PANEL
  //  The actual existing page widget rendered inside 40% panel
  // ==========================================================================

  Widget _buildEmbeddedPagePanel() {
    final txn    = _selectedTxn!;
    final cat    = _selectedCat!;
    final amount = (txn['amount'] ?? 0).toDouble();
    final date   = _parseDate(txn['transactionDate']);
    final ref    = txn['referenceNumber']?.toString() ?? '';
    final desc   = txn['description']?.toString() ?? '';

    return Container(
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x20000000), blurRadius: 20, offset: Offset(-4,0))]),
      child: Column(children: [
        // Top bar: back + category name + close
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
          child: Row(children: [
            InkWell(
              onTap: _backToCategoryPicker,
              borderRadius: BorderRadius.circular(6),
              child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.arrow_back, size: 14, color: Color(0xFF5D6D7E))),
            ),
            const SizedBox(width: 10),
            Icon(cat.icon, color: cat.color, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(cat.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))),
            InkWell(onTap: _closePanel, child: const Icon(Icons.close, size: 16, color: Color(0xFF7F8C8D))),
          ]),
        ),
        // Pre-filled info chips
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: const Color(0xFFF8F9FA),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            _infoChip(Icons.currency_rupee, '₹${NumberFormat('#,##,##0.00').format(amount)}', _navyAccent),
            _infoChip(Icons.calendar_today_outlined, DateFormat('dd MMM yyyy').format(date), const Color(0xFF5D6D7E)),
            if (ref.isNotEmpty) _infoChip(Icons.tag, ref, const Color(0xFF5D6D7E)),
            _infoChip(Icons.account_balance_outlined, widget.accountName, _blue),
          ]),
        ),
        // ✅ Existing page widget with showAppBar: false
        Expanded(child: _buildEmbeddedWidget(cat, amount, date, ref, desc)),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.2))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Flexible(child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _buildEmbeddedWidget(_Cat cat, double amount, DateTime date, String ref, String desc) {
    final dateStr = DateFormat('dd/MM/yyyy').format(date);

    Widget page;
    switch (cat.id) {
      case 'expense':
      case 'card_payment':
      case 'owner_drawings':
        page = NewExpensePage(
          showAppBar: false,
          prefilledAmount: amount,
          prefilledDate: dateStr,
          prefilledReference: ref,
          prefilledNotes: desc,
          prefilledPaidThroughName: widget.accountName,
          providerTransactionId: _selectedTxn?['_id']?.toString(),
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      case 'customer_payment':
        page = NewPaymentPage(
          showAppBar: false,
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          providerTransactionId: _selectedTxn?['_id']?.toString(),
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      case 'customer_advance':
        page = NewPaymentPage(
          showAppBar: false,
          isAdvance: true,
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          providerTransactionId: _selectedTxn?['_id']?.toString(),
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      case 'vendor_payment':
      case 'vendor_advance':
        page = NewPaymentMadeScreen(
          showAppBar: false,
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          prefilledPaymentType: 'ADVANCE',
          providerTransactionId: _selectedTxn?['_id']?.toString(),
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      case 'vendor_payment_refund':
        page = _VendorPaymentRefundPage(
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      case 'vendor_credit_refund':
        page = _VendorCreditRefundPage(
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      case 'credit_note_refund':
        page = _CreditNoteRefundPage(
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          bankAccountId: widget.accountId,
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      case 'payment_refund':
        page = _CustomerPaymentRefundPage(
          prefilledAmount: amount,
          prefilledDate: date,
          prefilledReference: ref,
          providerTransactionId: _selectedTxn?['_id']?.toString(),
          onSavedCallback: _onEmbeddedPageSaved,
        );
        break;
      default:
        return const Center(child: Text('Unknown category'));
    }

    // Wrap in an isolated Navigator so any Navigator.pop() called inside
    // the embedded page resolves within this inner Navigator only —
    // the main app Navigator (and this route) are never popped.
    return Navigator(
      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => page),
    );
  }

  Widget _buildPanelHeader() {
    final txn = _selectedTxn;
    if (txn == null) return const SizedBox.shrink();
    final isDebit = txn['transactionType'] == 'DEBIT';
    final amount  = (txn['amount'] ?? 0).toDouble();
    final date    = _parseDate(txn['transactionDate']);
    final desc    = txn['description']?.toString() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: (isDebit ? _red : _green).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: Text('${isDebit ? '-' : '+'}₹${NumberFormat('#,##,##0.00').format(amount)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDebit ? _red : _green)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(desc.isNotEmpty ? desc : (isDebit ? 'Debit' : 'Credit'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF2C3E50)), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontSize: 11, color: Color(0xFF7F8C8D))),
        ])),
        InkWell(onTap: _closePanel, child: const Icon(Icons.close, size: 16, color: Color(0xFF7F8C8D))),
      ]),
    );
  }

  Widget _buildPanelTabs() => Row(children: [
    Expanded(child: _panelTabBtn('MATCH TRANSACTIONS', 0)),
    Expanded(child: _panelTabBtn('CATEGORIZE MANUALLY', 1)),
  ]);

  Widget _panelTabBtn(String label, int idx) => InkWell(
    onTap: () { setState(() => _panelTab = idx); if (idx == 0 && _selectedTxn != null) _loadMatches(_selectedTxn!); },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _panelTab == idx ? _navyAccent : const Color(0xFFEEF2F7), width: _panelTab == idx ? 2 : 1))),
      child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _panelTab == idx ? _navyAccent : const Color(0xFF7F8C8D), letterSpacing: 0.2)),
    ),
  );

  Widget _buildMatchPanel() => Column(children: [
    Expanded(child: _matchLoading ? const Center(child: CircularProgressIndicator(color: _navyAccent, strokeWidth: 2)) : _matches.isEmpty ? _buildNoMatches() : _buildMatchList()),
    if (_matches.isNotEmpty) _buildMatchFooter(),
  ]);

  Widget _buildNoMatches() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 16),
      const Align(alignment: Alignment.centerLeft, child: Text('Possible Matches', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))),
      Align(alignment: Alignment.centerLeft, child: Text('Transactions upto ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const TextStyle(fontSize: 11, color: Color(0xFF7F8C8D)))),
      const SizedBox(height: 48),
      Icon(Icons.search_off, size: 40, color: Colors.grey[300]),
      const SizedBox(height: 12),
      const Text('There are no transactions matching the selected criteria.', style: TextStyle(fontSize: 12, color: Color(0xFF7F8C8D)), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => setState(() => _panelTab = 1), style: OutlinedButton.styleFrom(foregroundColor: _navyAccent, side: const BorderSide(color: _navyAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), child: const Text('Categorize Manually'))),
    ]),
  );

  Widget _buildMatchList() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Possible Matches', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const Spacer(),
        TextButton(onPressed: () => setState(() { for (final m in _matches) m['_selected'] = true; }), style: TextButton.styleFrom(foregroundColor: _navyAccent, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero), child: const Text('SELECT ALL', style: TextStyle(fontSize: 11))),
      ]),
      Text('Transactions upto ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const TextStyle(fontSize: 11, color: Color(0xFF7F8C8D))),
      const SizedBox(height: 12),
      ..._matches.map((m) => _buildMatchCard(m)),
    ]),
  );

  Widget _buildMatchCard(Map<String,dynamic> m) {
    final type   = m['type']?.toString() ?? 'Record';
    final amount = (m['amount'] ?? m['total'] ?? 0).toDouble();
    final refNum = m['invoiceNumber'] ?? m['billNumber'] ?? m['referenceNumber'] ?? '';
    final name   = m['customerName'] ?? m['vendorName'] ?? '';
    final sel    = m['_selected'] == true;
    Color tc;
    switch (type.toLowerCase()) {
      case 'invoice':     tc = _green;  break;
      case 'bill':        tc = _orange; break;
      case 'credit note': tc = _purple; break;
      default:            tc = _blue;
    }
    return InkWell(
      onTap: () => setState(() => m['_selected'] = !(m['_selected'] ?? false)),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: sel ? tc.withOpacity(0.06) : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: sel ? tc : const Color(0xFFE2E8F0), width: sel ? 1.5 : 1)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: tc.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(type, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: tc))),
              const SizedBox(width: 8),
              Text('for ₹${NumberFormat('#,##,##0.00').format(amount)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            ]),
            if (name.isNotEmpty || refNum.toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text([if (name.isNotEmpty) name, if (refNum.toString().isNotEmpty) refNum.toString()].join(' | '), style: const TextStyle(fontSize: 11, color: Color(0xFF7F8C8D))),
            ],
          ])),
          const SizedBox(width: 8),
          sel
              ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: tc, borderRadius: BorderRadius.circular(5)), child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.check, color: Colors.white, size: 12), SizedBox(width: 4), Text('Selected', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))]))
              : OutlinedButton(onPressed: () => setState(() => m['_selected'] = true), style: OutlinedButton.styleFrom(foregroundColor: tc, side: BorderSide(color: tc), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))), child: const Text('Select', style: TextStyle(fontSize: 11))),
        ]),
      ),
    );
  }

  Widget _buildMatchFooter() => Container(
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
    child: Row(children: [
      Expanded(child: OutlinedButton(onPressed: _closePanel, style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFCBD5E1)), padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), child: const Text('Cancel', style: TextStyle(color: Color(0xFF5D6D7E))))),
      const SizedBox(width: 10),
      Expanded(child: ElevatedButton(onPressed: _doMatch, style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), child: const Text('Match', style: TextStyle(fontWeight: FontWeight.bold)))),
    ]),
  );

  Future<void> _doMatch() async {
    final selected = _matches.where((m) => m['_selected'] == true).toList();
    if (selected.isEmpty) { _showError('Select at least one match'); return; }
    final txnId = _selectedTxn?['_id']?.toString() ?? '';
    try {
      final m    = selected.first;
      final type = m['type']?.toString().toLowerCase() ?? '';
      Map<String,dynamic> r;
      if (type == 'invoice') {
        r = await _svc.matchToInvoice(providerTransactionId: txnId, invoiceId: m['_id'].toString());
      } else if (type == 'bill') {
        r = await _svc.matchToBill(providerTransactionId: txnId, billId: m['_id'].toString());
      } else {
        r = await _svc.matchToRecord(providerTransactionId: txnId, recordId: m['_id'].toString(), recordType: type);
      }
      if (r['success'] == true) { _showSuccess('Transaction matched'); _closePanel(); _markAsCategorizedLocally(txnId, 'Matched to ${type}'); }
      else { _showError(r['message'] ?? 'Match failed'); }
    } catch (e) { _showError('Failed: $e'); }
  }

  Widget _buildCatPanel() {
    final txn = _selectedTxn;
    if (txn == null) return const SizedBox.shrink();
    final isDebit  = txn['transactionType'] == 'DEBIT';
    final cats     = isDebit ? _moneyOut : _moneyIn;
    final groupLbl = isDebit ? 'Money Out' : 'Money In';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RichText(text: const TextSpan(text: 'Category', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)), children: [TextSpan(text: ' *', style: TextStyle(color: Colors.red))])),
        const SizedBox(height: 8),
        _buildCatDropdown(cats, groupLbl),
        if (_selectedCat != null) ...[
          const SizedBox(height: 16),
          _buildCategoryAction(txn),
        ],
      ]),
    );
  }

  Widget _buildCategoryAction(Map<String,dynamic> txn) {
    final cat    = _selectedCat!;
    final amount = (txn['amount'] ?? 0).toDouble();
    final date   = _parseDate(txn['transactionDate']);
    final ref    = txn['referenceNumber']?.toString() ?? '';

    if (_isEmbeddedCategory(cat)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Pre-filled preview
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cat.color.withOpacity(0.04), borderRadius: BorderRadius.circular(8), border: Border.all(color: cat.color.withOpacity(0.2))),
          child: Column(children: [
            _previewRow('Amount', '₹${NumberFormat('#,##,##0.00').format(amount)}'),
            const SizedBox(height: 6),
            _previewRow('Date', DateFormat('dd MMM yyyy').format(date)),
            if (ref.isNotEmpty) ...[const SizedBox(height: 6), _previewRow('Reference', ref)],
            const SizedBox(height: 6),
            _previewRow('Bank Account', widget.accountName),
          ]),
        ),
        const SizedBox(height: 14),
        // ✅ Continue button — sets _showingEmbeddedPage = true
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () => setState(() => _showingEmbeddedPage = true),
          icon: Icon(cat.icon, size: 16),
          label: Text('Continue to ${cat.label}', style: const TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: cat.color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        )),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton(
          onPressed: _closePanel,
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFCBD5E1)), padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF5D6D7E))),
        )),
      ]);
    }

    // Inline form for transfer + simple categories
    return _buildSimpleInlineForm(cat, amount);
  }

  Widget _previewRow(String label, String value) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7F8C8D))),
    Flexible(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)), overflow: TextOverflow.ellipsis, textAlign: TextAlign.right)),
  ]);

  Widget _buildSimpleInlineForm(_Cat cat, double amount) {
    final isTransfer = cat.id == 'transfer_in' || cat.id == 'transfer_out';

    Widget amtChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FA), border: Border.all(color: const Color(0xFFCBD5E1)), borderRadius: BorderRadius.circular(6)),
      child: Row(children: [
        const Text('₹ ', style: TextStyle(fontSize: 13, color: Color(0xFF7F8C8D))),
        Text(NumberFormat('#,##,##0.00').format(amount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
        const Spacer(),
        const Text('pre-filled', style: TextStyle(fontSize: 10, color: Color(0xFF7F8C8D))),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isTransfer) ...[
        Text(cat.id == 'transfer_out' ? 'Transfer To Account *' : 'Transfer From Account *', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
        const SizedBox(height: 6),
        DropdownButtonFormField<Map<String,dynamic>>(
          value: _selectedToAccount,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.account_balance, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
          isExpanded: true,
          hint: const Text('Select account', style: TextStyle(fontSize: 13)),
          items: _bankAccounts.map((a) => DropdownMenuItem(value: a, child: Text(a['accountName']?.toString() ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => setState(() => _selectedToAccount = v),
        ),
        const SizedBox(height: 12),
      ],
      const Text('Amount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      const SizedBox(height: 6),
      amtChip,
      const SizedBox(height: 12),
      const Text('Notes (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      const SizedBox(height: 6),
      TextField(controller: _notesCtrl, maxLines: 2, decoration: InputDecoration(hintText: 'Notes', hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)), prefixIcon: const Icon(Icons.note_outlined, size: 16, color: Color(0xFF7F8C8D)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12))),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _closePanel, style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFCBD5E1)), padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), child: const Text('Cancel', style: TextStyle(color: Color(0xFF5D6D7E))))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton(onPressed: _panelSaving ? null : _saveSimpleCategory, style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), child: _panelSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)))),
      ]),
    ]);
  }

  Widget _buildCatDropdown(List<_Cat> cats, String groupLbl) => Column(children: [
    InkWell(
      onTap: () => setState(() => _catDropOpen = !_catDropOpen),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _catDropOpen ? _navyAccent : const Color(0xFFCBD5E1)), borderRadius: BorderRadius.only(topLeft: const Radius.circular(6), topRight: const Radius.circular(6), bottomLeft: Radius.circular(_catDropOpen ? 0 : 6), bottomRight: Radius.circular(_catDropOpen ? 0 : 6))),
        child: Row(children: [
          if (_selectedCat != null) ...[
            Icon(_selectedCat!.icon, color: _selectedCat!.color, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_selectedCat!.label, style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50)))),
          ] else
            Expanded(child: Text('Select $groupLbl Category', style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)))),
          Icon(_catDropOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: const Color(0xFF7F8C8D)),
        ]),
      ),
    ),
    if (_catDropOpen) Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _navyAccent), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 12, offset: const Offset(0,4))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(8), child: TextField(autofocus: true, onChanged: (v) => setState(() => _catSearch = v.toLowerCase()), decoration: InputDecoration(hintText: 'Search', prefixIcon: const Icon(Icons.search, size: 15), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)))),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(children: cats.where((c) {
              final s = _catSearch;
              return s == null || s.isEmpty || c.label.toLowerCase().contains(s);
            }).map((c) {
              final sel = _selectedCat?.id == c.id;
              return InkWell(
                onTap: () => setState(() { _selectedCat = c; _catDropOpen = false; _catSearch = null; _showingEmbeddedPage = false; _selectedToAccount = null; _notesCtrl.clear(); }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  color: sel ? _navyAccent.withOpacity(0.07) : Colors.transparent,
                  child: Row(children: [
                    Icon(c.icon, color: sel ? _navyAccent : c.color, size: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.label, style: TextStyle(fontSize: 13, color: sel ? _navyAccent : const Color(0xFF2C3E50), fontWeight: sel ? FontWeight.w600 : FontWeight.normal))),
                    if (sel) Icon(Icons.check, color: _navyAccent, size: 15),
                  ]),
                ),
              );
            }).toList()),
          ),
        ),
      ]),
    ),
  ]);

  void _showImport() {
    bool _imported = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkImportBankStatementDialog(
        accountId: widget.accountId,
        accountName: widget.accountName,
        onImportComplete: () { _imported = true; },
      ),
    ).then((_) {
      if (_imported && mounted) {
        _loadAll();
        _showSuccess('Statement imported');
      }
    });
  }
  void _showRecordDeposit() => showDialog(context: context, builder: (_) => RecordDepositDialog(accountId: widget.accountId, accountName: widget.accountName, onSaved: () { _loadAll(); _showSuccess('Deposit recorded'); }));
  void _showRules() => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionRulesScreen(accountId: widget.accountId, accountName: widget.accountName))).then((_) => _loadAll());

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _green, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), duration: const Duration(seconds: 2)));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: _red, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  void _editTransaction(Map<String, dynamic> txn) {
    final dateCtrl = TextEditingController(
        text: DateFormat('dd/MM/yyyy').format(_parseDate(txn['transactionDate'])));
    final descCtrl = TextEditingController(text: txn['description']?.toString() ?? '');
    final amtCtrl  = TextEditingController(text: (txn['amount'] ?? '').toString());
    final refCtrl  = TextEditingController(text: txn['referenceNumber']?.toString() ?? '');
    final isCat    = txn['reconciliationStatus'] == 'CATEGORIZED';

    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(isCat ? 'Edit Categorized Transaction' : 'Edit Transaction',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isCat) Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: _orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _orange.withOpacity(0.3))),
          child: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: _orange, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text('Editing will reverse and re-post all accounting entries.',
                style: TextStyle(fontSize: 11, color: _orange))),
          ]),
        ),
        TextField(controller: dateCtrl,
            decoration: const InputDecoration(labelText: 'Date (dd/MM/yyyy)',
                border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: descCtrl,
            decoration: const InputDecoration(labelText: 'Description',
                border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: amtCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount',
                border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: refCtrl,
            decoration: const InputDecoration(labelText: 'Reference Number',
                border: OutlineInputBorder(), isDense: true)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _navyAccent),
          onPressed: () async {
            Navigator.pop(context);
            final parts = dateCtrl.text.split('/');
            String? isoDate;
            if (parts.length == 3) {
              isoDate = '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
            }
            final r = await _svc.editTransaction(
              txn['_id'].toString(),
              date:            isoDate,
              description:     descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              amount:          double.tryParse(amtCtrl.text.trim()),
              referenceNumber: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
            );
            if (r['success'] == true) { _showSuccess('Transaction updated'); _loadAll(); }
            else { _showError(r['message'] ?? 'Update failed'); }
          },
          child: const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  void _confirmDeleteTransaction(Map<String, dynamic> txn) {
    final isCat = txn['reconciliationStatus'] == 'CATEGORIZED';
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Transaction',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _red)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isCat) Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: _red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _red.withOpacity(0.2))),
          child: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: _red, size: 16),
            SizedBox(width: 8),
            Expanded(child: Text(
              'This transaction is categorized. Deleting will permanently reverse all COA journal entries, remove the linked expense/payment record, and update the account balance.',
              style: TextStyle(fontSize: 11, color: _red))),
          ]),
        ) else
          const Text('This will permanently delete the transaction. This cannot be undone.',
              style: TextStyle(fontSize: 13)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _red),
          onPressed: () async {
            Navigator.pop(context);
            final r = await _svc.deleteTransaction(txn['_id'].toString());
            if (r['success'] == true) { _showSuccess('Transaction deleted'); _closePanel(); _loadAll(); }
            else { _showError(r['message'] ?? 'Delete failed'); }
          },
          child: const Text('Delete', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  void _confirmUncategorize(Map<String, dynamic> txn) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Uncategorize Transaction',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _orange)),
      content: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _orange.withOpacity(0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _orange.withOpacity(0.2))),
        child: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _orange, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(
            'This will reverse all COA journal entries and accounting records linked to this transaction. The transaction will return to Uncategorized.',
            style: TextStyle(fontSize: 11, color: _orange))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _orange),
          onPressed: () async {
            Navigator.pop(context);
            final r = await _svc.uncategorizeTransaction(txn['_id'].toString());
            if (r['success'] == true) { _showSuccess('Transaction uncategorized'); _closePanel(); _loadAll(); }
            else { _showError(r['message'] ?? 'Failed'); }
          },
          child: const Text('Uncategorize', style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    try { return DateTime.parse(d.toString()); } catch (_) { return DateTime.now(); }
  }
}

// ============================================================================
// VENDOR CREDIT REFUND PAGE — embedded inside account_detail_page panel
// ============================================================================

class _VendorCreditRefundPage extends StatefulWidget {
  final double   prefilledAmount;
  final DateTime prefilledDate;
  final String   prefilledReference;
  // Callback receives "creditId::refundId" so _onEmbeddedPageSaved can split them
  final void Function(String creditIdAndRefundId) onSavedCallback;

  const _VendorCreditRefundPage({
    Key? key,
    required this.prefilledAmount,
    required this.prefilledDate,
    required this.prefilledReference,
    required this.onSavedCallback,
  }) : super(key: key);

  @override
  State<_VendorCreditRefundPage> createState() => _VendorCreditRefundPageState();
}

class _VendorCreditRefundPageState extends State<_VendorCreditRefundPage> {
  // ── vendors ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _vendors        = [];
  bool                       _loadingVendors = true;
  String?                    _selectedVendorId;

  // ── credits for selected vendor ──────────────────────────────────────────
  List<VendorCredit> _credits        = [];
  bool               _loadingCredits = false;

  // per-credit refund amount controllers (creditId → controller)
  final Map<String, TextEditingController> _amtCtrls = {};

  // ── form fields ──────────────────────────────────────────────────────────
  late DateTime _refundDate;
  String        _paymentMode = 'Cash';
  final _refCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  bool  _saving   = false;

  static const _modes = [
    'Cash', 'Cheque', 'Bank Transfer', 'UPI', 'NEFT', 'RTGS', 'IMPS', 'Online',
  ];

  @override
  void initState() {
    super.initState();
    _refundDate   = widget.prefilledDate;
    _refCtrl.text = widget.prefilledReference;
    _fetchVendors();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _amtCtrls.values) c.dispose();
    super.dispose();
  }

  // ── loaders ──────────────────────────────────────────────────────────────

  Future<void> _fetchVendors() async {
    setState(() => _loadingVendors = true);
    try {
      final res = await BillingVendorsService.getAllVendors(limit: 1000);
      if (res['success'] == true) {
        final raw  = res['data'];
        final list = raw is List ? raw : (raw['vendors'] as List? ?? []);
        setState(() {
          _vendors = list.map<Map<String, dynamic>>((v) => {
            '_id':        v['_id']?.toString() ?? '',
            'vendorName': v['vendorName']?.toString() ?? '',
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Vendor load error: $e');
    } finally {
      setState(() => _loadingVendors = false);
    }
  }

  Future<void> _fetchCredits(String vendorId) async {
    setState(() { _loadingCredits = true; _credits = []; _amtCtrls.clear(); });
    try {
      final res = await VendorCreditService.getVendorCredits(
        vendorId: vendorId,
        limit: 100,
      );
      // Only show credits that still have a balance (OPEN or PARTIALLY_APPLIED)
      final open = res.credits
          .where((c) =>
              (c.status == 'OPEN' || c.status == 'PARTIALLY_APPLIED') &&
              c.balanceAmount > 0)
          .toList();
      setState(() {
        _credits = open;
        for (final c in open) {
          _amtCtrls[c.id] = TextEditingController();
        }
      });
    } catch (e) {
      debugPrint('Credits load error: $e');
    } finally {
      setState(() => _loadingCredits = false);
    }
  }

  // ── save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedVendorId == null) {
      _showError('Please select a vendor');
      return;
    }

    // Collect credits with a refund amount entered
    final toRefund = <({VendorCredit credit, double amount})>[];
    for (final credit in _credits) {
      final raw = double.tryParse(_amtCtrls[credit.id]?.text.trim() ?? '') ?? 0;
      if (raw <= 0) continue;
      if (raw > credit.balanceAmount + 0.01) {
        _showError(
          'Refund for ${credit.creditNumber} exceeds balance '
          '₹${credit.balanceAmount.toStringAsFixed(2)}',
        );
        return;
      }
      toRefund.add((credit: credit, amount: raw));
    }

    if (toRefund.isEmpty) {
      _showError('Enter a refund amount for at least one vendor credit');
      return;
    }

    setState(() => _saving = true);
    try {
      String refundId = '';
      String creditId = '';
      for (final item in toRefund) {
        // refundCredit returns the refund sub-doc _id for precise reversal
        refundId = await VendorCreditService.refundCredit(item.credit.id, {
          'amount':          item.amount,
          'refundDate':      _refundDate.toIso8601String(),
          'paymentMode':     _paymentMode,
          'referenceNumber': _refCtrl.text.trim(),
          'notes':           _descCtrl.text.trim(),
        });
        creditId = item.credit.id;
      }
      // Pass "creditId::refundId" — _onEmbeddedPageSaved splits this to store
      // creditId as linkedRecordId and refundId as journalRef
      widget.onSavedCallback('$creditId::$refundId');
    } catch (e) {
      _showError('Failed: $e');
      setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Vendor ──────────────────────────────────────────────────────────
        _label('Vendor', required: true),
        const SizedBox(height: 6),
        _loadingVendors
            ? const LinearProgressIndicator()
            : DropdownButtonFormField<String>(
                value: _selectedVendorId,
                isExpanded: true,
                decoration: _inputDec(hint: 'Select Vendor'),
                items: _vendors.map((v) => DropdownMenuItem(
                  value: v['_id'] as String,
                  child: Text(v['vendorName'] as String,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _selectedVendorId = id);
                  _fetchCredits(id);
                },
              ),

        const SizedBox(height: 14),

        // ── Date ────────────────────────────────────────────────────────────
        _label('Date', required: true),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _refundDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _refundDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF7F8C8D)),
              const SizedBox(width: 8),
              Text(DateFormat('dd/MM/yyyy').format(_refundDate),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50))),
            ]),
          ),
        ),

        const SizedBox(height: 14),

        // ── Received Via ────────────────────────────────────────────────────
        _label('Received Via'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _paymentMode,
          isExpanded: true,
          decoration: _inputDec(),
          items: _modes.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: (v) { if (v != null) setState(() => _paymentMode = v); },
        ),

        const SizedBox(height: 14),

        // ── Reference# ──────────────────────────────────────────────────────
        _label('Reference#'),
        const SizedBox(height: 6),
        TextField(
          controller: _refCtrl,
          decoration: _inputDec(hint: 'e.g. Ref-1900'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 18),

        // ── Select Vendor Credit table ───────────────────────────────────────
        RichText(text: const TextSpan(
          text: 'Select Vendor Credit',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _red),
          children: [TextSpan(text: ' *', style: TextStyle(color: _red))],
        )),
        const SizedBox(height: 8),

        if (_selectedVendorId == null)
          _emptyBox('Select a vendor to load available credits')
        else if (_loadingCredits)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: _navyAccent, strokeWidth: 2)),
          )
        else if (_credits.isEmpty)
          _emptyBox('No open vendor credits found for this vendor')
        else
          _buildCreditsTable(),

        const SizedBox(height: 14),

        // ── Description ─────────────────────────────────────────────────────
        _label('Description'),
        const SizedBox(height: 6),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: _inputDec(hint: 'e.g. Cheque deposit'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 20),

        // ── Save / Cancel ────────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF5D6D7E))),
            ),
          ),
        ]),

        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _emptyBox(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Center(child: Text(msg,
        style: const TextStyle(fontSize: 12, color: Color(0xFF7F8C8D)))),
  );

  Widget _buildCreditsTable() {
    final fmt = NumberFormat('#,##,##0.00');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(5), topRight: Radius.circular(5),
            ),
          ),
          child: Row(children: const [
            SizedBox(width: 28),
            Expanded(child: Text('CN#',     style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 72, child: Text('Amount',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 72, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 82, child: Text('Refund',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        // Rows
        ...List.generate(_credits.length, (i) {
          final c = _credits[i];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // Radio indicator — activates when amount is typed
                SizedBox(
                  width: 28,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _amtCtrls[c.id]!,
                    builder: (_, val, __) {
                      final active = (double.tryParse(val.text.trim()) ?? 0) > 0;
                      return Icon(
                        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18,
                        color: active ? _navyAccent : const Color(0xFFCBD5E1),
                      );
                    },
                  ),
                ),
                // CN# — blue underlined
                Expanded(
                  child: Text(c.creditNumber,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _navyAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                // Total amount
                SizedBox(width: 72,
                  child: Text('₹${fmt.format(c.totalAmount)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF2C3E50))),
                ),
                // Balance
                SizedBox(width: 72,
                  child: Text('₹${fmt.format(c.balanceAmount)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E50))),
                ),
                // Refund amount input
                SizedBox(
                  width: 82,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextField(
                      controller: _amtCtrls[c.id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        hintText: '0.00',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            if (i < _credits.length - 1)
              const Divider(height: 1, color: Color(0xFFEEF2F7)),
          ]);
        }),
      ]),
    );
  }

  Widget _label(String text, {bool required = false}) => RichText(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
      children: required
          ? const [TextSpan(text: ' *', style: TextStyle(color: _red))]
          : [],
    ),
  );

  InputDecoration _inputDec({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

// ============================================================================
// CREDIT NOTE REFUND PAGE — embedded inside account_detail_page panel
// ============================================================================
// Shown when user selects "Credit Note Refund" (money_out) in the categorize panel.
// Flow:
//   1. Select customer → loads all their credit notes with creditBalance > 0
//   2. Table shows: CN# | Total Amount | Balance | Refund amount input
//   3. Fill Date, Paid Via, Reference#, Description
//   4. Save → POST /api/finance/credit-notes/:id/refund
//   5. onSavedCallback("creditNoteId::refundId") → bank transaction categorized
// ============================================================================

class _CreditNoteRefundPage extends StatefulWidget {
  final double   prefilledAmount;
  final DateTime prefilledDate;
  final String   prefilledReference;
  final String   bankAccountId;
  // Callback receives "creditNoteId::refundId" so _onEmbeddedPageSaved can split them
  final void Function(String creditNoteIdAndRefundId) onSavedCallback;

  const _CreditNoteRefundPage({
    Key? key,
    required this.prefilledAmount,
    required this.prefilledDate,
    required this.prefilledReference,
    required this.bankAccountId,
    required this.onSavedCallback,
  }) : super(key: key);

  @override
  State<_CreditNoteRefundPage> createState() => _CreditNoteRefundPageState();
}

class _CreditNoteRefundPageState extends State<_CreditNoteRefundPage> {
  // ── customers ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _customers        = [];
  bool                       _loadingCustomers = true;
  String?                    _selectedCustomerId;

  // ── credit notes for selected customer ────────────────────────────────────
  List<CreditNote> _creditNotes        = [];
  bool             _loadingCreditNotes = false;

  // per-credit-note refund amount controllers (creditNoteId → controller)
  final Map<String, TextEditingController> _amtCtrls = {};

  // ── form fields ───────────────────────────────────────────────────────────
  late DateTime _refundDate;
  String        _paymentMode = 'Cash';
  final _refCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  bool  _saving   = false;

  static const _modes = [
    'Cash', 'Cheque', 'Bank Transfer', 'UPI', 'NEFT', 'RTGS', 'IMPS', 'Online',
  ];

  @override
  void initState() {
    super.initState();
    _refundDate   = widget.prefilledDate;
    _refCtrl.text = widget.prefilledReference;
    _fetchCustomers();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _amtCtrls.values) c.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _fetchCustomers() async {
    setState(() => _loadingCustomers = true);
    try {
      final res = await BillingCustomersService.getAllCustomers(limit: 1000);
      setState(() {
        _customers = res.customers.map<Map<String, dynamic>>((c) => {
          '_id':          c.id,
          'customerName': c.customerDisplayName,
        }).toList();
      });
    } catch (e) {
      debugPrint('Customer load error: $e');
    } finally {
      setState(() => _loadingCustomers = false);
    }
  }

  Future<void> _fetchCreditNotes(String customerId) async {
    setState(() { _loadingCreditNotes = true; _creditNotes = []; _amtCtrls.clear(); });
    try {
      final res = await CreditNoteService.getCreditNotes(
        customerId: customerId,
        limit: 100,
      );
      // Only show credit notes that still have a balance (OPEN or PARTIALLY_APPLIED)
      final open = res.creditNotes
          .where((cn) =>
              (cn.status == 'OPEN' || cn.status == 'PARTIALLY_APPLIED') &&
              cn.creditBalance > 0)
          .toList();
      setState(() {
        _creditNotes = open;
        for (final cn in open) {
          _amtCtrls[cn.id] = TextEditingController();
        }
      });
    } catch (e) {
      debugPrint('Credit notes load error: $e');
    } finally {
      setState(() => _loadingCreditNotes = false);
    }
  }

  // ── save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedCustomerId == null) {
      _showError('Please select a customer');
      return;
    }

    // Collect credit notes with a refund amount entered
    final toRefund = <({CreditNote creditNote, double amount})>[];
    for (final cn in _creditNotes) {
      final raw = double.tryParse(_amtCtrls[cn.id]?.text.trim() ?? '') ?? 0;
      if (raw <= 0) continue;
      if (raw > cn.creditBalance + 0.01) {
        _showError(
          'Refund for ${cn.creditNoteNumber} exceeds balance '
          '₹${cn.creditBalance.toStringAsFixed(2)}',
        );
        return;
      }
      toRefund.add((creditNote: cn, amount: raw));
    }

    if (toRefund.isEmpty) {
      _showError('Enter a refund amount for at least one credit note');
      return;
    }

    setState(() => _saving = true);
    try {
      String refundId     = '';
      String creditNoteId = '';
      for (final item in toRefund) {
        // refundCreditNote returns the refund sub-doc _id for precise reversal
        refundId = await CreditNoteService.refundCreditNote(item.creditNote.id, {
          'amount':          item.amount,
          'refundDate':      _refundDate.toIso8601String(),
          'refundMethod':    _paymentMode,
          'referenceNumber': _refCtrl.text.trim(),
          'notes':           _descCtrl.text.trim(),
          'bankAccountId':   widget.bankAccountId,
        });
        creditNoteId = item.creditNote.id;
      }
      // Pass "creditNoteId::refundId" — _onEmbeddedPageSaved splits this to store
      // creditNoteId as linkedRecordId and refundId as journalRef
      widget.onSavedCallback('$creditNoteId::$refundId');
    } catch (e) {
      _showError('Failed: $e');
      setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Customer ──────────────────────────────────────────────────────
        _label('Customer', required: true),
        const SizedBox(height: 6),
        _loadingCustomers
            ? const LinearProgressIndicator()
            : DropdownButtonFormField<String>(
                value: _selectedCustomerId,
                isExpanded: true,
                decoration: _inputDec(hint: 'Select Customer'),
                items: _customers.map((c) => DropdownMenuItem(
                  value: c['_id'] as String,
                  child: Text(c['customerName'] as String,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _selectedCustomerId = id);
                  _fetchCreditNotes(id);
                },
              ),

        const SizedBox(height: 14),

        // ── Date ──────────────────────────────────────────────────────────
        _label('Date', required: true),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _refundDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _refundDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF7F8C8D)),
              const SizedBox(width: 8),
              Text(DateFormat('dd/MM/yyyy').format(_refundDate),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50))),
            ]),
          ),
        ),

        const SizedBox(height: 14),

        // ── Paid Via ──────────────────────────────────────────────────────
        _label('Paid Via'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _paymentMode,
          isExpanded: true,
          decoration: _inputDec(),
          items: _modes.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: (v) { if (v != null) setState(() => _paymentMode = v); },
        ),

        const SizedBox(height: 14),

        // ── Reference# ────────────────────────────────────────────────────
        _label('Reference#'),
        const SizedBox(height: 6),
        TextField(
          controller: _refCtrl,
          decoration: _inputDec(hint: 'e.g. Ref-1900'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 18),

        // ── Select Credit Note table ───────────────────────────────────────
        RichText(text: const TextSpan(
          text: 'Select Credit Note',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _red),
          children: [TextSpan(text: ' *', style: TextStyle(color: _red))],
        )),
        const SizedBox(height: 8),

        if (_selectedCustomerId == null)
          _emptyBox('Select a customer to load available credit notes')
        else if (_loadingCreditNotes)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: _navyAccent, strokeWidth: 2)),
          )
        else if (_creditNotes.isEmpty)
          _emptyBox('There are no credit notes with balance for this customer')
        else
          _buildCreditNotesTable(),

        const SizedBox(height: 14),

        // ── Description ───────────────────────────────────────────────────
        _label('Description'),
        const SizedBox(height: 6),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: _inputDec(hint: 'Optional notes'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 20),

        // ── Save / Cancel ─────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF5D6D7E))),
            ),
          ),
        ]),

        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _emptyBox(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Center(child: Text(msg,
        style: const TextStyle(fontSize: 12, color: Color(0xFF7F8C8D)))),
  );

  Widget _buildCreditNotesTable() {
    final fmt = NumberFormat('#,##,##0.00');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(5), topRight: Radius.circular(5),
            ),
          ),
          child: Row(children: const [
            SizedBox(width: 28),
            Expanded(child: Text('CN#',     style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 72, child: Text('Amount',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 72, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 82, child: Text('Refund',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        // Rows
        ...List.generate(_creditNotes.length, (i) {
          final cn = _creditNotes[i];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // Radio indicator — activates when amount is typed
                SizedBox(
                  width: 28,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _amtCtrls[cn.id]!,
                    builder: (_, val, __) {
                      final active = (double.tryParse(val.text.trim()) ?? 0) > 0;
                      return Icon(
                        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18,
                        color: active ? _navyAccent : const Color(0xFFCBD5E1),
                      );
                    },
                  ),
                ),
                // CN# — blue underlined
                Expanded(
                  child: Text(cn.creditNoteNumber,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _navyAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                // Total amount
                SizedBox(width: 72,
                  child: Text('₹${fmt.format(cn.totalAmount)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF2C3E50))),
                ),
                // Balance
                SizedBox(width: 72,
                  child: Text('₹${fmt.format(cn.creditBalance)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E50))),
                ),
                // Refund amount input
                SizedBox(
                  width: 82,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextField(
                      controller: _amtCtrls[cn.id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        hintText: '0.00',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            if (i < _creditNotes.length - 1)
              const Divider(height: 1, color: Color(0xFFEEF2F7)),
          ]);
        }),
      ]),
    );
  }

  Widget _label(String text, {bool required = false}) => RichText(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
      children: required
          ? const [TextSpan(text: ' *', style: TextStyle(color: _red))]
          : [],
    ),
  );

  InputDecoration _inputDec({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

// ============================================================================
// VENDOR PAYMENT REFUND — Embedded page
// ============================================================================
// Shown when user selects "Vendor Payment Refund" in the categorize panel.
// Flow:
//   1. Select vendor → loads all their payments with amountUnused > 0
//   2. Table shows: Payment# | Amount | Balance | Refund amount input
//   3. Fill Date, Received Via, Reference#, Description
//   4. Save → POST /api/payments-made/:id/refund for each row with amount
//   5. onSavedCallback(paymentId) → bank transaction gets categorized
// ============================================================================

class _VendorPaymentRefundPage extends StatefulWidget {
  final double   prefilledAmount;
  final DateTime prefilledDate;
  final String   prefilledReference;
  final void Function(String paymentId) onSavedCallback;

  const _VendorPaymentRefundPage({
    Key? key,
    required this.prefilledAmount,
    required this.prefilledDate,
    required this.prefilledReference,
    required this.onSavedCallback,
  }) : super(key: key);

  @override
  State<_VendorPaymentRefundPage> createState() => _VendorPaymentRefundPageState();
}

class _VendorPaymentRefundPageState extends State<_VendorPaymentRefundPage> {
  // ── vendors ──────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _vendors      = [];
  bool                       _loadingVendors = true;
  String?                    _selectedVendorId;

  // ── payments with balance ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _payments        = [];
  bool                       _loadingPayments = false;

  // per-payment refund amount controllers  (paymentId → controller)
  final Map<String, TextEditingController> _amtCtrls = {};

  // ── form fields ──────────────────────────────────────────────────────────
  late DateTime _refundDate;
  String        _paymentMode = 'Cash';
  final _refCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  bool  _saving   = false;

  static const _modes = [
    'Cash', 'Cheque', 'Bank Transfer', 'UPI', 'NEFT', 'RTGS', 'IMPS', 'Online',
  ];

  @override
  void initState() {
    super.initState();
    _refundDate   = widget.prefilledDate;
    _refCtrl.text = widget.prefilledReference;
    _fetchVendors();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _amtCtrls.values) c.dispose();
    super.dispose();
  }

  // ── loaders ──────────────────────────────────────────────────────────────

  Future<void> _fetchVendors() async {
    setState(() => _loadingVendors = true);
    try {
      final res = await BillingVendorsService.getAllVendors(limit: 1000);
      if (res['success'] == true) {
        final raw  = res['data'];
        final list = raw is List ? raw : (raw['vendors'] as List? ?? []);
        setState(() {
          _vendors = list.map<Map<String, dynamic>>((v) => {
            '_id':        v['_id']?.toString() ?? '',
            'vendorName': v['vendorName']?.toString() ?? '',
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Vendor load error: $e');
    } finally {
      setState(() => _loadingVendors = false);
    }
  }

  Future<void> _fetchPayments(String vendorId) async {
    setState(() {
      _loadingPayments = true;
      _payments = [];
      // dispose old controllers
      for (final c in _amtCtrls.values) c.dispose();
      _amtCtrls.clear();
    });
    try {
      final list = await PaymentMadeService.getVendorPaymentsWithBalance(vendorId);
      setState(() {
        _payments = list;
        for (final p in list) {
          final id = p['_id']?.toString() ?? '';
          if (id.isNotEmpty) _amtCtrls[id] = TextEditingController();
        }
      });
    } catch (e) {
      debugPrint('Payments load error: $e');
    } finally {
      setState(() => _loadingPayments = false);
    }
  }

  // ── save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedVendorId == null) {
      _showErr('Please select a vendor');
      return;
    }

    // Collect rows where user entered a refund amount
    final toRefund = <({Map<String, dynamic> payment, double amount})>[];
    for (final p in _payments) {
      final id  = p['_id']?.toString() ?? '';
      final raw = double.tryParse(_amtCtrls[id]?.text.trim() ?? '') ?? 0;
      if (raw <= 0) continue;
      final balance = (p['amountUnused'] as num?)?.toDouble() ?? 0;
      if (raw > balance + 0.01) {
        _showErr('Refund for ${p['paymentNumber']} exceeds balance ₹${balance.toStringAsFixed(2)}');
        return;
      }
      toRefund.add((payment: p, amount: raw));
    }

    if (toRefund.isEmpty) {
      _showErr('Enter a refund amount for at least one payment');
      return;
    }

    setState(() => _saving = true);
    try {
      String lastPaymentId = '';
      for (final item in toRefund) {
        final id = item.payment['_id']?.toString() ?? '';
        await PaymentMadeService.recordRefund(id, {
          'amount':          item.amount,
          'refundMode':      _paymentMode,
          'referenceNumber': _refCtrl.text.trim(),
          'notes':           _descCtrl.text.trim(),
        });
        lastPaymentId = id;
      }
      widget.onSavedCallback(lastPaymentId);
    } catch (e) {
      _showErr('Failed: $e');
      setState(() => _saving = false);
    }
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Vendor ──────────────────────────────────────────────────────────
        _lbl('Vendor', required: true),
        const SizedBox(height: 6),
        _loadingVendors
            ? const LinearProgressIndicator()
            : DropdownButtonFormField<String>(
                value: _selectedVendorId,
                isExpanded: true,
                decoration: _dec(hint: 'Select Vendor'),
                items: _vendors.map((v) => DropdownMenuItem(
                  value: v['_id'] as String,
                  child: Text(v['vendorName'] as String,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _selectedVendorId = id);
                  _fetchPayments(id);
                },
              ),

        const SizedBox(height: 14),

        // ── Date ────────────────────────────────────────────────────────────
        _lbl('Date', required: true),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _refundDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _refundDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF7F8C8D)),
              const SizedBox(width: 8),
              Text(DateFormat('dd/MM/yyyy').format(_refundDate),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50))),
            ]),
          ),
        ),

        const SizedBox(height: 14),

        // ── Received Via ────────────────────────────────────────────────────
        _lbl('Received Via'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _paymentMode,
          isExpanded: true,
          decoration: _dec(),
          items: _modes.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: (v) { if (v != null) setState(() => _paymentMode = v); },
        ),

        const SizedBox(height: 14),

        // ── Reference# ──────────────────────────────────────────────────────
        _lbl('Reference#'),
        const SizedBox(height: 6),
        TextField(
          controller: _refCtrl,
          decoration: _dec(hint: 'e.g. Ref-1900'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 18),

        // ── Select a Payment table ───────────────────────────────────────────
        RichText(text: const TextSpan(
          text: 'Select a Payment',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
          children: [TextSpan(text: ' *', style: TextStyle(color: _red))],
        )),
        const SizedBox(height: 8),

        if (_selectedVendorId == null)
          _emptyBox('Select a vendor to load available payments')
        else if (_loadingPayments)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: _navyAccent, strokeWidth: 2)),
          )
        else if (_payments.isEmpty)
          _emptyBox('There are no payments with credits for this vendor')
        else
          _buildPaymentsTable(),

        const SizedBox(height: 14),

        // ── Description ─────────────────────────────────────────────────────
        _lbl('Description'),
        const SizedBox(height: 6),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: _dec(hint: 'e.g. Refund received via cheque'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 20),

        // ── Save / Cancel ────────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF5D6D7E))),
            ),
          ),
        ]),

        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _emptyBox(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Center(
      child: Text(msg, style: const TextStyle(fontSize: 12, color: Color(0xFF7F8C8D))),
    ),
  );

  Widget _buildPaymentsTable() {
    final fmt = NumberFormat('#,##,##0.00');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(5), topRight: Radius.circular(5),
            ),
          ),
          child: Row(children: const [
            SizedBox(width: 28),
            Expanded(child: Text('Payment#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 70, child: Text('Amount',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 70, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 80, child: Text('Refund',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        // Rows
        ...List.generate(_payments.length, (i) {
          final p       = _payments[i];
          final id      = p['_id']?.toString() ?? '';
          final pNum    = p['paymentNumber']?.toString() ?? '-';
          final total   = (p['amount'] as num?)?.toDouble() ?? 0;
          final balance = (p['amountUnused'] as num?)?.toDouble() ?? 0;
          final ctrl    = _amtCtrls[id];
          if (ctrl == null) return const SizedBox.shrink();

          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // Radio indicator — lights up when amount is typed
                SizedBox(
                  width: 28,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: ctrl,
                    builder: (_, val, __) {
                      final active = (double.tryParse(val.text.trim()) ?? 0) > 0;
                      return Icon(
                        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18,
                        color: active ? _navyAccent : const Color(0xFFCBD5E1),
                      );
                    },
                  ),
                ),
                // Payment number — blue underlined
                Expanded(
                  child: Text(pNum,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _navyAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                // Total amount
                SizedBox(
                  width: 70,
                  child: Text('₹${fmt.format(total)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF2C3E50))),
                ),
                // Balance (refundable)
                SizedBox(
                  width: 70,
                  child: Text('₹${fmt.format(balance)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: Color(0xFF2C3E50))),
                ),
                // Refund amount input
                SizedBox(
                  width: 80,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        hintText: '0.00',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            if (i < _payments.length - 1)
              const Divider(height: 1, color: Color(0xFFEEF2F7)),
          ]);
        }),
      ]),
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  Widget _lbl(String text, {bool required = false}) => RichText(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
      children: required
          ? const [TextSpan(text: ' *', style: TextStyle(color: _red))]
          : [],
    ),
  );

  InputDecoration _dec({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

// ============================================================================
// CUSTOMER PAYMENT REFUND — Embedded page
// ============================================================================
// Shown when user selects "Payment Refund" (money_out) in the categorize panel.
// Flow:
//   1. Select customer → loads all their payments with amountInExcess > 0
//   2. Table shows: Payment# | Amount | Balance | Refund amount input
//   3. Fill Date, Paid Via, Reference#, Description
//   4. Save → POST /api/finance/payments-received/:id/refund for each row
//   5. onSavedCallback(paymentId) → bank transaction gets categorized
// ============================================================================

class _CustomerPaymentRefundPage extends StatefulWidget {
  final double   prefilledAmount;
  final DateTime prefilledDate;
  final String   prefilledReference;
  final String?  providerTransactionId;
  final void Function(String paymentId) onSavedCallback;

  const _CustomerPaymentRefundPage({
    Key? key,
    required this.prefilledAmount,
    required this.prefilledDate,
    required this.prefilledReference,
    this.providerTransactionId,
    required this.onSavedCallback,
  }) : super(key: key);

  @override
  State<_CustomerPaymentRefundPage> createState() => _CustomerPaymentRefundPageState();
}

class _CustomerPaymentRefundPageState extends State<_CustomerPaymentRefundPage> {
  // ── customers ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _customers       = [];
  bool                       _loadingCustomers = true;
  String?                    _selectedCustomerId;

  // ── payments with balance ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _payments        = [];
  bool                       _loadingPayments = false;

  // per-payment refund amount controllers (paymentId → controller)
  final Map<String, TextEditingController> _amtCtrls = {};

  // ── form fields ──────────────────────────────────────────────────────────
  late DateTime _refundDate;
  String        _paymentMode = 'Cash';
  final _refCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  bool  _saving   = false;

  static const _modes = [
    'Cash', 'Cheque', 'Bank Transfer', 'UPI', 'NEFT', 'RTGS', 'IMPS', 'Online',
  ];

  @override
  void initState() {
    super.initState();
    _refundDate   = widget.prefilledDate;
    _refCtrl.text = widget.prefilledReference;
    _fetchCustomers();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _amtCtrls.values) c.dispose();
    super.dispose();
  }

  // ── loaders ──────────────────────────────────────────────────────────────

  Future<void> _fetchCustomers() async {
    setState(() => _loadingCustomers = true);
    try {
      final res = await BillingCustomersService.getAllCustomers(limit: 1000, skipStats: true);
      setState(() {
        _customers = res.customers.map<Map<String, dynamic>>((c) => {
          '_id':          c.id,
          'customerName': c.customerDisplayName.isNotEmpty
              ? c.customerDisplayName
              : c.companyName,
        }).toList();
      });
    } catch (e) {
      debugPrint('Customer load error: $e');
    } finally {
      setState(() => _loadingCustomers = false);
    }
  }

  Future<void> _fetchPayments(String customerId) async {
    setState(() {
      _loadingPayments = true;
      _payments = [];
      for (final c in _amtCtrls.values) c.dispose();
      _amtCtrls.clear();
    });
    try {
      final list = await PaymentService.getCustomerPaymentsWithBalance(customerId);
      setState(() {
        _payments = list;
        for (final p in list) {
          final id = p['_id']?.toString() ?? '';
          if (id.isNotEmpty) _amtCtrls[id] = TextEditingController();
        }
      });
    } catch (e) {
      debugPrint('Payments load error: $e');
    } finally {
      setState(() => _loadingPayments = false);
    }
  }

  // ── save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_selectedCustomerId == null) {
      _showErr('Please select a customer');
      return;
    }

    final toRefund = <({Map<String, dynamic> payment, double amount})>[];
    for (final p in _payments) {
      final id      = p['_id']?.toString() ?? '';
      final raw     = double.tryParse(_amtCtrls[id]?.text.trim() ?? '') ?? 0;
      if (raw <= 0) continue;
      final balance = (p['amountInExcess'] as num?)?.toDouble() ?? 0;
      if (raw > balance + 0.01) {
        _showErr('Refund for ${p['paymentNumber']} exceeds balance ₹${balance.toStringAsFixed(2)}');
        return;
      }
      toRefund.add((payment: p, amount: raw));
    }

    if (toRefund.isEmpty) {
      _showErr('Enter a refund amount for at least one payment');
      return;
    }

    setState(() => _saving = true);
    try {
      String lastPaymentId = '';
      for (final item in toRefund) {
        final id = item.payment['_id']?.toString() ?? '';
        await PaymentService.recordRefund(id, {
          'amount':          item.amount,
          'refundMode':      _paymentMode,
          'referenceNumber': _refCtrl.text.trim(),
          'refundDate':      _refundDate.toIso8601String(),
          'notes':           _descCtrl.text.trim(),
          if (widget.providerTransactionId != null)
            'providerTransactionId': widget.providerTransactionId,
        });
        lastPaymentId = id;
      }
      widget.onSavedCallback(lastPaymentId);
    } catch (e) {
      _showErr('Failed: $e');
      setState(() => _saving = false);
    }
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Customer ────────────────────────────────────────────────────────
        _lbl('Customer', required: true),
        const SizedBox(height: 6),
        _loadingCustomers
            ? const LinearProgressIndicator()
            : DropdownButtonFormField<String>(
                value: _selectedCustomerId,
                isExpanded: true,
                decoration: _dec(hint: 'Select Customer'),
                items: _customers.map((c) => DropdownMenuItem(
                  value: c['_id'] as String,
                  child: Text(c['customerName'] as String,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                )).toList(),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _selectedCustomerId = id);
                  _fetchPayments(id);
                },
              ),

        const SizedBox(height: 14),

        // ── Date ────────────────────────────────────────────────────────────
        _lbl('Date', required: true),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _refundDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _refundDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined, size: 15, color: Color(0xFF7F8C8D)),
              const SizedBox(width: 8),
              Text(DateFormat('dd/MM/yyyy').format(_refundDate),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF2C3E50))),
            ]),
          ),
        ),

        const SizedBox(height: 14),

        // ── Paid Via ────────────────────────────────────────────────────────
        _lbl('Paid Via'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _paymentMode,
          isExpanded: true,
          decoration: _dec(),
          items: _modes.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m, style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: (v) { if (v != null) setState(() => _paymentMode = v); },
        ),

        const SizedBox(height: 14),

        // ── Reference# ──────────────────────────────────────────────────────
        _lbl('Reference#'),
        const SizedBox(height: 6),
        TextField(
          controller: _refCtrl,
          decoration: _dec(hint: 'e.g. Ref-1900'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 18),

        // ── Select a Payment table ───────────────────────────────────────────
        RichText(text: const TextSpan(
          text: 'Select a Payment',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
          children: [TextSpan(text: ' *', style: TextStyle(color: _red))],
        )),
        const SizedBox(height: 8),

        if (_selectedCustomerId == null)
          _emptyBox('Select a customer to load available payments')
        else if (_loadingPayments)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: _navyAccent, strokeWidth: 2)),
          )
        else if (_payments.isEmpty)
          _emptyBox('There are no payments with credits for this customer')
        else
          _buildPaymentsTable(),

        const SizedBox(height: 14),

        // ── Description ─────────────────────────────────────────────────────
        _lbl('Description'),
        const SizedBox(height: 6),
        TextField(
          controller: _descCtrl,
          maxLines: 3,
          decoration: _dec(hint: 'e.g. Refund via bank transfer'),
          style: const TextStyle(fontSize: 13),
        ),

        const SizedBox(height: 20),

        // ── Save / Cancel ────────────────────────────────────────────────────
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF5D6D7E))),
            ),
          ),
        ]),

        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _emptyBox(String msg) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FB),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Center(
      child: Text(msg, style: const TextStyle(fontSize: 12, color: Color(0xFF7F8C8D))),
    ),
  );

  Widget _buildPaymentsTable() {
    final fmt = NumberFormat('#,##,##0.00');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(5), topRight: Radius.circular(5),
            ),
          ),
          child: Row(children: const [
            SizedBox(width: 28),
            Expanded(child: Text('Payment#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 70, child: Text('Amount',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 70, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
            SizedBox(width: 80, child: Text('Refund',  textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        // Rows
        ...List.generate(_payments.length, (i) {
          final p       = _payments[i];
          final id      = p['_id']?.toString() ?? '';
          final amount  = (p['amountReceived'] as num?)?.toDouble() ?? 0;
          final balance = (p['amountInExcess'] as num?)?.toDouble() ?? 0;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // Radio indicator — activates when amount is typed
                SizedBox(
                  width: 28,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _amtCtrls[id]!,
                    builder: (_, val, __) {
                      final active = (double.tryParse(val.text.trim()) ?? 0) > 0;
                      return Icon(
                        active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 18,
                        color: active ? _navyAccent : const Color(0xFFCBD5E1),
                      );
                    },
                  ),
                ),
                // Payment#
                Expanded(
                  child: Text(p['paymentNumber']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _navyAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                // Amount
                SizedBox(width: 70,
                  child: Text('₹${fmt.format(amount)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF2C3E50))),
                ),
                // Balance (amountInExcess)
                SizedBox(width: 70,
                  child: Text('₹${fmt.format(balance)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E50))),
                ),
                // Refund input
                SizedBox(
                  width: 80,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextField(
                      controller: _amtCtrls[id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        hintText: '0.00',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            if (i < _payments.length - 1)
              const Divider(height: 1, color: Color(0xFFEEF2F7)),
          ]);
        }),
      ]),
    );
  }

  Widget _lbl(String text, {bool required = false}) => RichText(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
      children: required
          ? const [TextSpan(text: ' *', style: TextStyle(color: _red))]
          : [],
    ),
  );

  InputDecoration _dec({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}