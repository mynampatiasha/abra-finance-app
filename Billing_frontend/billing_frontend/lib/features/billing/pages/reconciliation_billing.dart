// ============================================================================
// RECONCILIATION BILLING PAGE — FULL UI OVERHAUL
// ============================================================================
// File: lib/screens/banking/reconciliation_billing.dart
//
// UI Pattern: Matches recurring_bills_list_page.dart exactly
//   - 3-breakpoint top bar (Desktop ≥1100 / Tablet 700–1100 / Mobile <700)
//   - 4 gradient stat cards (h-scroll on mobile)
//   - Dark navy #0D1B3E header styling
//   - Same color system: Navy / Purple / Green / Blue / Orange / Red
//
// Import: 2-step dialog — Step 1 download template, Step 2 upload
//   - Template columns match backend extractTransactionData() exactly
//   - Uses importProviderStatementBytes() for web, importProviderStatement() for mobile
//   - No manual column mapping required — pre-configured to match backend
//
// All existing functionality preserved:
//   - Opening/closing balance verification
//   - Provider transactions + System expenses side-by-side
//   - Auto-match, manual match, Accept/Reject/Unmatch
//   - Carry Forward, Adjustment, Bulk resolve
//   - Mark as Reconciled → finalize session
//   - Submit for Approval → Approve/Reject flow
//   - Petty cash inline page
//   - Report dialog
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:convert';
import '../../../core/services/reconciliation_billing_service.dart';
import '../../../core/services/add_account_service.dart';
import '../../../core/utils/export_helper.dart';
import '../../../core/finance_secure_storage.dart';
import '../../../app/config/finance_api_config.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── colour palette ──────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);

class _StatCardData {
  final String label, value, subtitle;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label, required this.value, required this.subtitle,
    required this.icon, required this.color, required this.gradientColors,
  });
}

// =============================================================================
//  MAIN PAGE
// =============================================================================

class ReconciliationBillingPage extends StatefulWidget {
  final String accountId;
  final String accountName;
  final String accountType;

  const ReconciliationBillingPage({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.accountType,
  }) : super(key: key);

  @override
  State<ReconciliationBillingPage> createState() => _ReconciliationBillingPageState();
}

class _ReconciliationBillingPageState extends State<ReconciliationBillingPage> {

  final ReconciliationBillingService _service = ReconciliationBillingService();
  final AddAccountService _accountService = AddAccountService();

  // ── state ─────────────────────────────────────────────────────────────────
  bool _isLoading      = true;
  bool _isAutoMatching = false;

  ReconciliationSessionModel? _session;

  DateTime _periodStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _periodEnd   = DateTime.now();

  List<ProviderTransactionModel> _providerTransactions = [];
  List<Map<String, dynamic>>     _systemExpenses       = [];

  // balances & stats
  double _openingBalance      = 0.0;
  double _providerBalance     = 0.0;
  double _systemBalance       = 0.0;
  int    _totalMatched        = 0;
  int    _totalUnmatched      = 0;
  int    _totalPending        = 0;

  // opening balance verification
  bool    _openingBalanceVerified   = false;
  double? _statementOpeningBalance;
  double? _openingBalanceDifference;
  String  _openingBalanceSeverity   = 'none';
  String  _openingBalanceMessage    = '';

  // closing balance
  double?                  _statementClosingBalance;
  Map<String, dynamic>?    _closingBalanceCheckResult;

  // filter
  String _selectedFilter = 'All';
  final List<String> _filterOptions = ['All', 'Matched', 'Unmatched', 'Pending'];

  // manual matching selection
  String? _selectedProviderTxnId;
  String? _selectedSystemExpenseId;

  // bulk resolve
  final Set<String> _selectedUnmatchedIds = {};
  bool _isResolvingUnmatched = false;

  // scroll
  final ScrollController _statsHScrollCtrl = ScrollController();
  final ScrollController _tableHScrollCtrl = ScrollController();

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initializeReconciliation();
  }

  @override
  void dispose() {
    _statsHScrollCtrl.dispose();
    _tableHScrollCtrl.dispose();
    super.dispose();
  }

  // ── init flow ──────────────────────────────────────────────────────────────

  Future<void> _initializeReconciliation() async {
    await _startOrGetSession();
    await _loadOpeningBalance();
    if (widget.accountType != 'PETTY_CASH') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOpeningBalanceEntryDialog());
    } else {
      await _loadReconciliationData();
    }
  }

  Future<void> _loadOpeningBalance() async {
    try {
      final accountData = await _accountService.getAccountById(widget.accountId);
      setState(() => _openingBalance = (accountData['currentBalance'] ?? 0.0).toDouble());
    } catch (_) {
      setState(() => _openingBalance = 0.0);
    }
  }

  Future<void> _startOrGetSession() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await _service.getAllSessions(accountId: widget.accountId);
      final existing = sessions.where((s) =>
        s.periodStart.isAtSameMomentAs(_periodStart) &&
        s.periodEnd.isAtSameMomentAs(_periodEnd) &&
        s.status != 'LOCKED'
      ).firstOrNull;

      if (existing != null) {
        setState(() { _session = existing; _isLoading = false; });
      } else {
        final newSession = await _service.startReconciliationSession(
          accountId: widget.accountId,
          accountName: widget.accountName,
          accountType: widget.accountType,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
        );
        setState(() { _session = newSession; _isLoading = false; });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to initialize: $e');
    }
  }

  Future<void> _loadReconciliationData() async {
    setState(() => _isLoading = true);
    try {
      final providerTxns = await _service.getProviderTransactions(
        accountId: widget.accountId,
        startDate: _periodStart,
        endDate: _periodEnd,
      );
      final systemExps = await _service.getSystemExpenses(
        accountId: widget.accountId,
        startDate: _periodStart,
        endDate: _periodEnd,
      );

      setState(() {
        _providerTransactions = providerTxns;
        _systemExpenses       = systemExps;
        _providerBalance      = providerTxns.fold(0.0, (s, t) => s + t.amount);
        _systemBalance        = systemExps.fold(0.0, (s, e) => s + (e['total'] ?? 0).toDouble());
        _totalMatched         = providerTxns.where((t) => t.reconciliationStatus == 'MATCHED').length;
        _totalUnmatched       = providerTxns.where((t) => t.reconciliationStatus == 'UNMATCHED').length;
        _totalPending         = providerTxns.where((t) => t.reconciliationStatus == 'PENDING').length;
        _isLoading            = false;
      });
      if (_session != null) _refreshSessionStats();
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load data: $e');
    }
  }

  Future<void> _refreshSessionStats() async {
    if (_session == null) return;
    try {
      final updated = await _service.getSessionDetails(_session!.id);
      if (updated != null) setState(() => _session = updated);
    } catch (_) {}
  }

  // ── filtered lists ─────────────────────────────────────────────────────────

  List<ProviderTransactionModel> get _filteredProviderTransactions {
    switch (_selectedFilter) {
      case 'Matched':   return _providerTransactions.where((t) => t.reconciliationStatus == 'MATCHED').toList();
      case 'Unmatched': return _providerTransactions.where((t) => t.reconciliationStatus == 'UNMATCHED').toList();
      case 'Pending':   return _providerTransactions.where((t) => t.reconciliationStatus == 'PENDING').toList();
      default:          return _providerTransactions;
    }
  }

  List<Map<String, dynamic>> get _filteredSystemExpenses {
    switch (_selectedFilter) {
      case 'Matched':   return _systemExpenses.where((e) => e['providerTransactionId'] != null).toList();
      case 'Unmatched': return _systemExpenses.where((e) => e['providerTransactionId'] == null).toList();
      default:          return _systemExpenses;
    }
  }

  // ── opening balance dialog ─────────────────────────────────────────────────

  void _showOpeningBalanceEntryDialog() {
    final ctrl = TextEditingController(
      text: _openingBalance > 0 ? _openingBalance.toStringAsFixed(2) : '',
    );
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.account_balance_wallet, color: _purple)),
          const SizedBox(width: 12),
          const Expanded(child: Text('Enter Statement Opening Balance', style: TextStyle(fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue[200]!)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Enter the opening balance from your statement. System balance: ₹${_openingBalance.toStringAsFixed(2)}.',
                style: TextStyle(fontSize: 12, color: Colors.blue[900]),
              )),
            ]),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: ctrl, autofocus: true,
            decoration: InputDecoration(
              labelText: 'Statement Opening Balance *',
              prefixIcon: const Icon(Icons.currency_rupee),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              hintText: 'e.g. ${_openingBalance.toStringAsFixed(2)}',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _loadReconciliationData(); },
            child: Text('Skip', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              final v = double.tryParse(ctrl.text);
              if (v == null) return;
              Navigator.pop(context);
              await _verifyOpeningBalance(v);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white),
            child: const Text('Verify & Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyOpeningBalance(double statementBalance) async {
    try {
      final result = await _service.verifyOpeningBalance(
        accountId: widget.accountId,
        statementOpeningBalance: statementBalance,
      );
      if (result['success'] == true) {
        final data = result['data'];
        setState(() {
          _statementOpeningBalance  = statementBalance;
          _openingBalanceDifference = (data['difference'] as num).toDouble();
          _openingBalanceSeverity   = data['severity'] ?? 'none';
          _openingBalanceMessage    = data['message'] ?? '';
          _openingBalanceVerified   = true;
        });
      }
    } catch (_) {
      setState(() => _openingBalanceVerified = false);
    } finally {
      await _loadReconciliationData();
    }
  }

  // ── actions ────────────────────────────────────────────────────────────────

  Future<void> _performAutoMatch() async {
    setState(() => _isAutoMatching = true);
    try {
      final result = await _service.runAutoMatch(
        accountId: widget.accountId,
        startDate: _periodStart,
        endDate: _periodEnd,
      );
      if (result['success'] == true) {
        final data = result['data'];
        _showSuccess('Auto-match: ${data['matchedCount']} matched, ${data['pendingCount']} pending');
        await _loadReconciliationData();
      }
    } catch (e) {
      _showError('Auto-match failed: $e');
    } finally {
      setState(() => _isAutoMatching = false);
    }
  }

  Future<void> _performManualMatch() async {
    if (_selectedProviderTxnId == null || _selectedSystemExpenseId == null) return;
    try {
      final result = await _service.manualMatch(
        providerTxnId: _selectedProviderTxnId!,
        expenseId: _selectedSystemExpenseId!,
      );
      if (result['requiresConfirmation'] == true) {
        final confirmed = await _showMatchConfirmationDialog(result);
        if (confirmed == true) {
          final forceResult = await _service.manualMatch(
            providerTxnId: _selectedProviderTxnId!,
            expenseId: _selectedSystemExpenseId!,
            forceMatch: true,
          );
          if (forceResult['success'] == true) {
            _showSuccess('Matched (forced)');
            setState(() { _selectedProviderTxnId = null; _selectedSystemExpenseId = null; });
            await _loadReconciliationData();
          }
        }
      } else if (result['success'] == true) {
        final warnings = result['warnings'] as List?;
        _showSuccess(warnings != null && warnings.isNotEmpty ? 'Matched with ${warnings.length} warning(s)' : 'Matched successfully');
        setState(() { _selectedProviderTxnId = null; _selectedSystemExpenseId = null; });
        await _loadReconciliationData();
      }
    } catch (e) {
      _showError('Match failed: $e');
    }
  }

  Future<void> _acceptMatch(ProviderTransactionModel txn) async {
    try {
      final ok = await _service.acceptMatch(txn.id);
      if (ok) { _showSuccess('Match accepted'); await _loadReconciliationData(); }
    } catch (e) { _showError('Failed: $e'); }
  }

  Future<void> _rejectMatch(ProviderTransactionModel txn) async {
    try {
      final ok = await _service.rejectMatch(txn.id);
      if (ok) { _showSuccess('Match rejected'); await _loadReconciliationData(); }
    } catch (e) { _showError('Failed: $e'); }
  }

  Future<void> _unmatchTransaction(ProviderTransactionModel txn) async {
    final ok = await _confirmDialog(title: 'Unmatch Transaction', message: 'Unmatch this transaction?', confirmLabel: 'Unmatch', confirmColor: _red);
    if (ok != true) return;
    try {
      final success = await _service.unmatchTransaction(txn.id);
      if (success) { _showSuccess('Transaction unmatched'); await _loadReconciliationData(); }
    } catch (e) { _showError('Failed: $e'); }
  }

  Future<void> _carryForwardTransaction(ProviderTransactionModel txn) async {
    final ok = await _confirmDialog(
      title: 'Carry Forward',
      message: '₹${txn.amount.toStringAsFixed(2)} on ${DateFormat('dd MMM yyyy').format(txn.transactionDate)}\n\nThis transaction will be moved to the next reconciliation period.',
      confirmLabel: 'Carry Forward', confirmColor: _purple,
    );
    if (ok != true) return;
    try {
      setState(() => _isResolvingUnmatched = true);
      final result = await _service.carryForwardTransaction(txn.id);
      setState(() => _isResolvingUnmatched = false);
      if (result['success'] == true) { _showSuccess(result['message'] ?? 'Carried forward'); await _loadReconciliationData(); }
      else _showError(result['message'] ?? 'Failed');
    } catch (e) { setState(() => _isResolvingUnmatched = false); _showError('Failed: $e'); }
  }

  Future<void> _showAdjustmentDialog(ProviderTransactionModel txn) async {
    final reasonCtrl = TextEditingController();
    final notesCtrl  = TextEditingController();
    String selectedType = 'WRITE_OFF';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(Icons.tune, color: _orange), const SizedBox(width: 12), const Text('Create Adjustment')]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _orange.withOpacity(0.3))),
            child: Text('₹${txn.amount.toStringAsFixed(2)} · ${DateFormat('dd MMM yyyy').format(txn.transactionDate)}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _orange)),
          ),
          const SizedBox(height: 16),
          const Text('Adjustment Type *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedType,
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: const [
              DropdownMenuItem(value: 'WRITE_OFF', child: Text('Write Off')),
              DropdownMenuItem(value: 'TIMING_DIFFERENCE', child: Text('Timing Difference')),
              DropdownMenuItem(value: 'BANK_CHARGE', child: Text('Bank Charge')),
              DropdownMenuItem(value: 'OTHER', child: Text('Other')),
            ],
            onChanged: (v) => setS(() => selectedType = v ?? 'WRITE_OFF'),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: reasonCtrl, maxLines: 2,
            decoration: InputDecoration(labelText: 'Reason *', hintText: 'e.g. Bank charge not in system', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          TextFormField(controller: notesCtrl,
            decoration: InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(child: Text('An expense of ₹${txn.amount.toStringAsFixed(2)} will be created.', style: TextStyle(fontSize: 11, color: Colors.blue[900]))),
            ])),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) { _showError('Please enter a reason'); return; }
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Create Adjustment'),
            style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white),
          ),
        ],
      )),
    );

    if (confirmed != true) return;
    try {
      setState(() => _isResolvingUnmatched = true);
      final result = await _service.createAdjustment(
        txn.id,
        reason: reasonCtrl.text.trim(),
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        adjustmentType: selectedType,
      );
      setState(() => _isResolvingUnmatched = false);
      if (result['success'] == true) { _showSuccess(result['message'] ?? 'Adjustment created'); await _loadReconciliationData(); }
      else _showError(result['message'] ?? 'Failed');
    } catch (e) { setState(() => _isResolvingUnmatched = false); _showError('Failed: $e'); }
  }

  Future<void> _bulkResolveUnmatched(String action) async {
    if (_selectedUnmatchedIds.isEmpty) { _showError('Select at least one transaction'); return; }
    String? reason;
    if (action == 'adjustment') {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Bulk Adjustment Reason'),
          content: TextFormField(controller: ctrl, autofocus: true,
            decoration: InputDecoration(labelText: 'Reason *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () { if (ctrl.text.trim().isEmpty) return; Navigator.pop(context, ctrl.text.trim()); },
              style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (reason == null) return;
    }
    try {
      setState(() => _isResolvingUnmatched = true);
      final result = await _service.bulkResolve(
        transactionIds: _selectedUnmatchedIds.toList(),
        action: action,
        reason: reason,
      );
      setState(() { _isResolvingUnmatched = false; _selectedUnmatchedIds.clear(); });
      if (result['success'] == true) { _showSuccess(result['message'] ?? 'Bulk resolved'); await _loadReconciliationData(); }
      else _showError(result['message'] ?? 'Failed');
    } catch (e) { setState(() => _isResolvingUnmatched = false); _showError('Failed: $e'); }
  }

  Future<void> _markAsReconciled() async {
    final closing = await _showClosingBalanceEntryDialog();
    if (closing == null || _session == null) return;
    try {
      setState(() => _isLoading = true);
      final result = await _service.finalizeSession(_session!.id, statementClosingBalance: closing);
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        _showSuccess(result['message'] ?? 'Reconciliation locked');
        Navigator.pop(context, true);
      } else if (result['requiresConfirmation'] == true) {
        setState(() { _statementClosingBalance = closing; _closingBalanceCheckResult = result['closingBalanceCheck']; });
        final confirmed = await _showClosingBalanceMismatchDialog(result['message'] ?? 'Mismatch', result['closingBalanceCheck']);
        if (confirmed == true) {
          setState(() => _isLoading = true);
          final forceResult = await _service.finalizeSession(_session!.id, statementClosingBalance: closing, forceFinalize: true);
          setState(() => _isLoading = false);
          if (forceResult['success'] == true) { _showSuccess(forceResult['message'] ?? 'Locked'); Navigator.pop(context, true); }
          else _showError(forceResult['message'] ?? 'Failed');
        }
      } else {
        _showError(result['message'] ?? 'Finalization failed');
      }
    } catch (e) { setState(() => _isLoading = false); _showError('Failed: $e'); }
  }

  Future<void> _submitForApproval() async {
    if (_session == null) { _showError('No active session'); return; }
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.send, color: _blue), SizedBox(width: 12), Text('Submit for Approval')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Submit this reconciliation for review.', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 16),
          TextFormField(controller: notesCtrl,
            decoration: InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), maxLines: 2),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white),
            child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      setState(() => _isLoading = true);
      final result = await _service.submitForApproval(_session!.id, notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
      setState(() => _isLoading = false);
      if (result['success'] == true) { _showSuccess(result['message'] ?? 'Submitted'); await _refreshSessionStats(); setState(() {}); }
      else _showError(result['message'] ?? 'Failed');
    } catch (e) { setState(() => _isLoading = false); _showError('Failed: $e'); }
  }

  Future<void> _showApprovalDialog() async {
    if (_session == null) return;
    final notesCtrl      = TextEditingController();
    final rejectionCtrl  = TextEditingController();
    String selectedAction = 'approve';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.verified_user, color: _navy), SizedBox(width: 12), Text('Review Reconciliation')]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _reviewInfoRow('Account', widget.accountName),
          _reviewInfoRow('Period', '${DateFormat('dd MMM').format(_session!.periodStart)} – ${DateFormat('dd MMM yyyy').format(_session!.periodEnd)}'),
          _reviewInfoRow('Submitted by', _session!.submittedBy ?? 'N/A'),
          _reviewInfoRow('Matched', '${_session!.totalMatched} transactions'),
          _reviewInfoRow('Variance', '₹${_session!.balanceDifference.toStringAsFixed(2)}'),
          const SizedBox(height: 20),
          const Text('Decision *', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => setS(() => selectedAction = 'approve'),
              child: _decisionCard('Approve', Icons.check_circle, Colors.green, selectedAction == 'approve'))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(onTap: () => setS(() => selectedAction = 'reject'),
              child: _decisionCard('Reject', Icons.cancel, _red, selectedAction == 'reject'))),
          ]),
          const SizedBox(height: 16),
          if (selectedAction == 'approve')
            TextFormField(controller: notesCtrl, decoration: InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), maxLines: 2)
          else
            TextFormField(controller: rejectionCtrl, autofocus: true, decoration: InputDecoration(labelText: 'Rejection Reason *', hintText: 'Explain why', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), maxLines: 2),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (selectedAction == 'reject' && rejectionCtrl.text.trim().isEmpty) { _showError('Enter rejection reason'); return; }
              Navigator.pop(ctx, {'action': selectedAction, 'notes': notesCtrl.text.trim(), 'rejectionReason': rejectionCtrl.text.trim()});
            },
            style: ElevatedButton.styleFrom(backgroundColor: selectedAction == 'approve' ? Colors.green[700] : _red, foregroundColor: Colors.white),
            child: Text(selectedAction == 'approve' ? 'Approve & Lock' : 'Reject'),
          ),
        ],
      )),
    );

    if (result == null) return;
    try {
      setState(() => _isLoading = true);
      final apiResult = await _service.processApproval(
        _session!.id,
        action: result['action'],
        approvalNotes: result['notes'].isEmpty ? null : result['notes'],
        rejectionReason: result['rejectionReason'].isEmpty ? null : result['rejectionReason'],
      );
      setState(() => _isLoading = false);
      if (apiResult['success'] == true) {
        _showSuccess(apiResult['message'] ?? 'Done');
        if (result['action'] == 'approve') Navigator.pop(context, true);
        else { await _refreshSessionStats(); setState(() {}); }
      } else _showError(apiResult['message'] ?? 'Failed');
    } catch (e) { setState(() => _isLoading = false); _showError('Failed: $e'); }
  }

  Future<void> _generateReport() async {
    if (_session == null) { _showError('No active session'); return; }
    try {
      setState(() => _isLoading = true);
      final result = await _service.getReconciliationReport(_session!.id);
      setState(() => _isLoading = false);
      if (result['success'] != true) { _showError(result['message'] ?? 'Failed'); return; }
      await _showReportDialog(result['data']);
    } catch (e) { setState(() => _isLoading = false); _showError('Failed: $e'); }
  }

void _showDateRangePicker() async {
  DateTime tempStart = _periodStart;
  DateTime tempEnd = _periodEnd;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.date_range, color: _navy, size: 20),
          SizedBox(width: 8),
          Text('Select Period', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          // Start Date
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: tempStart,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(
                    colorScheme: const ColorScheme.light(primary: _navy),
                  ),
                  child: child!,
                ),
              );
              if (d != null) setS(() => tempStart = d);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 16, color: _navy),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('From', style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                  Text(DateFormat('dd MMM yyyy').format(tempStart),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy)),
                ]),
                const Spacer(),
                Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // End Date
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: tempEnd,
                firstDate: tempStart,
                lastDate: DateTime.now(),
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(
                    colorScheme: const ColorScheme.light(primary: _navy),
                  ),
                  child: child!,
                ),
              );
              if (d != null) setS(() => tempEnd = d);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 16, color: _navy),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('To', style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600)),
                  Text(DateFormat('dd MMM yyyy').format(tempEnd),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navy)),
                ]),
                const Spacer(),
                Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          // Quick select chips
          Wrap(spacing: 6, children: [
            _quickRangeChip('This Month', () {
              final now = DateTime.now();
              setS(() {
                tempStart = DateTime(now.year, now.month, 1);
                tempEnd = now;
              });
            }),
            _quickRangeChip('Last Month', () {
              final now = DateTime.now();
              final first = DateTime(now.year, now.month - 1, 1);
              final last = DateTime(now.year, now.month, 0);
              setS(() { tempStart = first; tempEnd = last; });
            }),
            _quickRangeChip('Last 30 Days', () {
              setS(() {
                tempEnd = DateTime.now();
                tempStart = tempEnd.subtract(const Duration(days: 30));
              });
            }),
            _quickRangeChip('This Year', () {
              final now = DateTime.now();
              setS(() {
                tempStart = DateTime(now.year, 1, 1);
                tempEnd = now;
              });
            }),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() { _periodStart = tempStart; _periodEnd = tempEnd; });
              _initializeReconciliation();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Apply'),
          ),
        ],
      ),
    ),
  );
}

Widget _quickRangeChip(String label, VoidCallback onTap) {
  return ActionChip(
    label: Text(label, style: const TextStyle(fontSize: 11)),
    onPressed: onTap,
    backgroundColor: _navy.withOpacity(0.08),
    side: BorderSide(color: _navy.withOpacity(0.2)),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    visualDensity: VisualDensity.compact,
  );
}

  void _handleImport() {
    showDialog(
      context: context,
      builder: (_) => _ImportStatementDialog(
        accountId: widget.accountId,
        onImportComplete: _loadReconciliationData,
      ),
    );
  }

  // ── snackbars ──────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _confirmDialog({required String title, required String message, required String confirmLabel, Color confirmColor = _navy}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (widget.accountType == 'PETTY_CASH') {
      return Scaffold(
        appBar: _buildAppBar(),
        backgroundColor: const Color(0xFFF0F4F8),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _navy))
            : _PettyCashInlinePage(
                accountId: widget.accountId,
                accountName: widget.accountName,
                periodStart: _periodStart,
                periodEnd: _periodEnd,
              ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      backgroundColor: const Color(0xFFF0F4F8),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : SingleChildScrollView(
              child: Column(children: [
                _buildTopBar(),
                _buildStatsCards(),
                if (_openingBalanceVerified && (_openingBalanceDifference?.abs() ?? 0) > 0.01)
                  _buildOpeningBalanceAlert(),
                _buildFiltersBar(),
                _buildTransactionsLayout(),
                _buildActionBar(),
              ]),
            ),
    );
  }

  // ── app bar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D1B3E),
      foregroundColor: Colors.white,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reconciliation', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(
          '${widget.accountName} · ${DateFormat('dd MMM').format(_periodStart)} – ${DateFormat('dd MMM yyyy').format(_periodEnd)}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ]),
      actions: [
        IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () async { await _loadOpeningBalance(); await _loadReconciliationData(); }, tooltip: 'Refresh'),
        IconButton(icon: const Icon(Icons.date_range), onPressed: _showDateRangePicker, tooltip: 'Change Period'),
        IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _generateReport, tooltip: 'Report'),
        if (widget.accountType != 'PETTY_CASH')
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _handleImport, tooltip: 'Import Statement'),
        const SizedBox(width: 8),
      ],
      elevation: 0,
    );
  }

  // ── top bar (3-breakpoint) ─────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _filterChips(),
    const Spacer(),
    _iconBtn(Icons.auto_fix_high, _isAutoMatching ? null : _performAutoMatch, tooltip: 'Auto-Match', color: _blue, bg: _blue.withOpacity(0.08)),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Report', Icons.picture_as_pdf_rounded, _navy, _generateReport),
    const SizedBox(width: 8),
    ElevatedButton.icon(
      onPressed: _isAutoMatching ? null : _performAutoMatch,
      icon: _isAutoMatching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_fix_high, size: 16),
      label: Text(_isAutoMatching ? 'Matching…' : 'Auto-Match', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    ),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _filterChips(),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Report', Icons.picture_as_pdf_rounded, _navy, _generateReport),
      const Spacer(),
      ElevatedButton.icon(
        onPressed: _isAutoMatching ? null : _performAutoMatch,
        icon: _isAutoMatching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_fix_high, size: 16),
        label: Text(_isAutoMatching ? 'Matching…' : 'Auto-Match', style: const TextStyle(fontSize: 14)),
        style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: _filterChips()),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _compactBtn('Import', _purple, _handleImport),
      const SizedBox(width: 8),
      _compactBtn('Report', _navy, _generateReport),
      const SizedBox(width: 8),
      _compactBtn(_isAutoMatching ? 'Matching…' : 'Auto-Match', _blue, _isAutoMatching ? null : _performAutoMatch),
    ])),
  ]);

  Widget _filterChips() => Row(mainAxisSize: MainAxisSize.min, children: [
    const Text('Filter:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy)),
    const SizedBox(width: 8),
    ..._filterOptions.map((f) {
      final isSel = _selectedFilter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(f, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isSel ? _navy : Colors.grey[600])),
          selected: isSel,
          onSelected: (_) => setState(() => _selectedFilter = f),
          selectedColor: _navy.withOpacity(0.12),
          backgroundColor: Colors.grey[100],
          side: BorderSide(color: isSel ? _navy : Colors.grey[300]!),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          visualDensity: VisualDensity.compact,
        ),
      );
    }),
  ]);

  // ── reusable widgets ───────────────────────────────────────────────────────

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(width: 42, height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color)),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, elevation: 0, minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  // ── stat cards ─────────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final diff = (_providerBalance - _systemBalance).abs();
    final cards = [
      _StatCardData(
        label: 'Provider Balance', value: '₹${_formatAmount(_providerBalance)}',
        subtitle: '${_providerTransactions.length} transactions',
        icon: Icons.account_balance, color: _blue,
        gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
      ),
      _StatCardData(
        label: 'System Balance', value: '₹${_formatAmount(_systemBalance)}',
        subtitle: '${_systemExpenses.length} expenses',
        icon: Icons.receipt_long, color: _green,
        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'Matched', value: _totalMatched.toString(),
        subtitle: 'reconciled',
        icon: Icons.check_circle_outline, color: _green,
        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'Unmatched', value: _totalUnmatched.toString(),
        subtitle: '${_totalPending} pending',
        icon: Icons.pending_outlined, color: _totalUnmatched > 0 ? _orange : _green,
        gradientColors: _totalUnmatched > 0
            ? const [Color(0xFFF39C12), Color(0xFFE67E22)]
            : const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'Variance', value: '₹${_formatAmount(diff)}',
        subtitle: diff < 0.01 ? 'balanced ✓' : 'needs attention',
        icon: diff < 0.01 ? Icons.check_circle : Icons.warning_amber_rounded,
        color: diff < 0.01 ? _green : _red,
        gradientColors: diff < 0.01
            ? const [Color(0xFF2ECC71), Color(0xFF27AE60)]
            : const [Color(0xFFFF6B6B), Color(0xFFE74C3C)],
      ),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl, scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(
              width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _buildStatCard(e.value, compact: true),
            )).toList()),
          );
        }
        return Row(children: cards.asMap().entries.map((e) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
            child: _buildStatCard(e.value, compact: false),
          ),
        )).toList());
      }),
    );
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                child: Icon(d.icon, color: Colors.white, size: 20)),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
              Text(d.subtitle, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ])
          : Row(children: [
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))]),
                child: Icon(d.icon, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(d.value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: d.color)),
                Text(d.subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ])),
            ]),
    );
  }

  String _formatAmount(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)   return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(2);
  }

  // ── opening balance alert ──────────────────────────────────────────────────

  Widget _buildOpeningBalanceAlert() {
    final diff = _openingBalanceDifference ?? 0;
    Color cardColor; Color borderColor; Color iconColor; IconData alertIcon;
    switch (_openingBalanceSeverity) {
      case 'high':   cardColor = Colors.red[50]!;    borderColor = Colors.red[300]!;    iconColor = Colors.red[700]!;    alertIcon = Icons.error; break;
      case 'medium': cardColor = Colors.orange[50]!; borderColor = Colors.orange[300]!; iconColor = Colors.orange[700]!; alertIcon = Icons.warning_amber; break;
      default:       cardColor = Colors.yellow[50]!; borderColor = Colors.yellow[600]!; iconColor = Colors.yellow[800]!; alertIcon = Icons.info_outline;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor, width: 1.5)),
      child: Row(children: [
        Icon(alertIcon, color: iconColor, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(_openingBalanceMessage, style: TextStyle(fontSize: 12, color: iconColor))),
        TextButton(onPressed: _showOpeningBalanceEntryDialog, child: Text('Re-enter', style: TextStyle(fontSize: 12, color: iconColor))),
      ]),
    );
  }

  // ── filters bar ────────────────────────────────────────────────────────────

  Widget _buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: _filterChips()),
    );
  }

  // ── transactions layout ────────────────────────────────────────────────────

  Widget _buildTransactionsLayout() {
    return LayoutBuilder(builder: (_, c) {
      final isMobile = c.maxWidth < 700;
      if (isMobile) {
        return Column(children: [
          _buildProviderTransactionsList(),
          const SizedBox(height: 8),
          _buildManualMatchMobileButton(),
          const SizedBox(height: 8),
          _buildSystemExpensesList(),
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _buildProviderTransactionsList()),
          Container(
            width: 80, color: Colors.grey[100],
            child: _buildMatchingCenter(),
          ),
          Expanded(child: _buildSystemExpensesList()),
        ]),
      );
    });
  }

  Widget _buildManualMatchMobileButton() {
    final canMatch = _selectedProviderTxnId != null && _selectedSystemExpenseId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: canMatch ? _performManualMatch : null,
          icon: const Icon(Icons.compare_arrows),
          label: Text(canMatch ? 'Match Selected Transactions' : 'Select one from each side to match'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _blue, foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }

  // ── provider transactions ──────────────────────────────────────────────────

  Widget _buildProviderTransactionsList() {
    return Container(
      color: Colors.white,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF0D1B3E), border: Border(bottom: BorderSide(color: Colors.blue[900]!))),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.account_balance, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text('Provider Transactions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Text('${_filteredProviderTransactions.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ]),
            if (_selectedUnmatchedIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                Text('${_selectedUnmatchedIds.length} selected', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const Spacer(),
                _bulkBtn('Carry All', _purple, () => _bulkResolveUnmatched('carry-forward')),
                const SizedBox(width: 8),
                _bulkBtn('Adjust All', _orange, () => _bulkResolveUnmatched('adjustment')),
              ]),
            ],
          ]),
        ),
        if (_filteredProviderTransactions.isEmpty)
          _emptyState('No provider transactions')
        else
          Column(children: _filteredProviderTransactions.map((t) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: _buildProviderCard(t),
          )).toList()),
      ]),
    );
  }

  Widget _bulkBtn(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: _isResolvingUnmatched ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildProviderCard(ProviderTransactionModel txn) {
    final isSel       = _selectedProviderTxnId == txn.id;
    final isMatched   = txn.reconciliationStatus == 'MATCHED';
    final isPending   = txn.reconciliationStatus == 'PENDING';
    final isCF        = txn.reconciliationStatus == 'CARRIED_FORWARD';
    final isUnmatched = txn.reconciliationStatus == 'UNMATCHED';
    final isBulkSel   = _selectedUnmatchedIds.contains(txn.id);

    Color statusColor = isMatched ? _green : isPending ? _orange : isCF ? _purple : Colors.grey;
    Color cardBg = isCF ? _purple.withOpacity(0.06) : isSel ? _blue.withOpacity(0.06) : isMatched ? _green.withOpacity(0.04) : isBulkSel ? _orange.withOpacity(0.06) : Colors.white;
    Color borderC = isCF ? _purple.withOpacity(0.4) : isSel ? _blue : isMatched ? _green.withOpacity(0.3) : isBulkSel ? _orange.withOpacity(0.5) : Colors.grey[200]!;

    return InkWell(
      onTap: () {
        if (!isMatched && !isCF) setState(() => _selectedProviderTxnId = isSel ? null : txn.id);
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderC, width: isSel || isBulkSel ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (isUnmatched) ...[
              Checkbox(
                value: isBulkSel,
                onChanged: (v) => setState(() { if (v == true) _selectedUnmatchedIds.add(txn.id); else _selectedUnmatchedIds.remove(txn.id); }),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.calendar_today, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 5),
                Text(DateFormat('dd MMM yyyy').format(txn.transactionDate), style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                const Spacer(),
                _txnStatusBadge(txn.reconciliationStatus, statusColor, isCF),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text('₹${txn.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: txn.transactionType == 'CREDIT' ? _green.withOpacity(0.1) : _red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(txn.transactionType, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: txn.transactionType == 'CREDIT' ? _green : _red)),
                ),
              ]),
              if (txn.description != null) ...[
                const SizedBox(height: 3),
                Text(txn.description!, style: TextStyle(fontSize: 11, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              if (txn.location != null) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.location_on, size: 11, color: Colors.grey[400]),
                  const SizedBox(width: 3),
                  Expanded(child: Text(txn.location!, style: TextStyle(fontSize: 11, color: Colors.grey[400]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ],
            ])),
          ]),

          // UNMATCHED — carry forward & adjustment
          if (isUnmatched) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEF2F7)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _miniBtn('Carry Forward', Icons.arrow_forward, _purple, () => _carryForwardTransaction(txn))),
              const SizedBox(width: 8),
              Expanded(child: _miniBtn('Adjustment', Icons.tune, _orange, () => _showAdjustmentDialog(txn))),
            ]),
          ],

          // PENDING — accept/reject
          if (isPending && txn.matchConfidence != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEF2F7)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.psychology, size: 13, color: _orange),
              const SizedBox(width: 5),
              Text('${txn.matchConfidence}% confidence', style: TextStyle(fontSize: 11, color: _orange, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: () => _acceptMatch(txn), style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _green), child: const Text('Accept', style: TextStyle(fontSize: 11))),
              TextButton(onPressed: () => _rejectMatch(txn), style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _red), child: const Text('Reject', style: TextStyle(fontSize: 11))),
            ]),
          ],

          // MATCHED
          if (isMatched) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEF2F7)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.link, size: 13, color: _green),
              const SizedBox(width: 5),
              Expanded(child: Text(txn.isAdjustment == true ? 'Resolved as adjustment' : 'Matched with system expense', style: TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w600))),
              if (txn.isAdjustment != true)
                TextButton(onPressed: () => _unmatchTransaction(txn), style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _red), child: const Text('Unmatch', style: TextStyle(fontSize: 11))),
            ]),
          ],

          // CARRIED FORWARD
          if (isCF) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEF2F7)),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.arrow_forward_ios, size: 13, color: _purple),
              const SizedBox(width: 5),
              Expanded(child: Text(txn.carriedForwardNotes ?? 'Carried forward', style: TextStyle(fontSize: 11, color: _purple, fontWeight: FontWeight.w600))),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _txnStatusBadge(String status, Color color, bool isCF) {
    final label = isCF ? 'CARRIED FWD' : status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _miniBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 13),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color, side: BorderSide(color: color.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(vertical: 6), visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── system expenses ────────────────────────────────────────────────────────

  Widget _buildSystemExpensesList() {
    return Container(
      color: Colors.white,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.green[800], border: Border(bottom: BorderSide(color: Colors.green[900]!))),
          child: Row(children: [
            const Icon(Icons.receipt_long, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text('System Expenses', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Text('${_filteredSystemExpenses.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
        ),
        if (_filteredSystemExpenses.isEmpty)
          _emptyState('No system expenses')
        else
          Column(children: _filteredSystemExpenses.map((e) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: _buildExpenseCard(e),
          )).toList()),
      ]),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> expense) {
    final expId   = expense['_id'] ?? expense['id'] ?? '';
    final isSel   = _selectedSystemExpenseId == expId;
    final isMat   = expense['providerTransactionId'] != null;

    return InkWell(
      onTap: () { if (!isMat) setState(() => _selectedSystemExpenseId = isSel ? null : expId); },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSel ? _green.withOpacity(0.06) : isMat ? _green.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSel ? _green : isMat ? _green.withOpacity(0.3) : Colors.grey[200]!, width: isSel ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.calendar_today, size: 13, color: Colors.grey[500]),
            const SizedBox(width: 5),
            Text(_fmtDate(expense['date']), style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
            const Spacer(),
            if (isMat) Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: _green.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: _green.withOpacity(0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 5, height: 5, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                const Text('MATCHED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _green)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          Text('₹${(expense['total'] ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 3),
          Text(expense['expenseAccount'] ?? 'No account', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50))),
          if (expense['vendor'] != null)
            Text('Vendor: ${expense['vendor']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (isMat) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFEEF2F7)),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.link, size: 13, color: _green),
              const SizedBox(width: 5),
              Text('Matched with provider transaction', style: TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
            ]),
          ],
        ]),
      ),
    );
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '-';
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  // ── matching center ────────────────────────────────────────────────────────

  Widget _buildMatchingCenter() {
    final canMatch = _selectedProviderTxnId != null && _selectedSystemExpenseId != null;
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: canMatch
            ? ElevatedButton(
                onPressed: _performManualMatch,
                style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, padding: const EdgeInsets.all(16), shape: const CircleBorder()),
                child: const Icon(Icons.compare_arrows, size: 28),
              )
            : Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[200], shape: BoxShape.circle),
                child: Icon(Icons.compare_arrows, size: 28, color: Colors.grey[400]),
              ),
      ),
      const SizedBox(height: 10),
      Text(
        canMatch ? 'Match' : 'Select\nboth',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: canMatch ? _blue : Colors.grey[400]),
      ),
    ]));
  }

  // ── action bar ─────────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    final isFullyReconciled   = _totalUnmatched == 0 && _totalPending == 0;
    final isSubmitted         = _session?.approvalStatus == 'PENDING_APPROVAL';
    final isRejected          = _session?.approvalStatus == 'REJECTED';
    final requiresApproval    = _session?.requiresApproval == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -3))]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isRejected)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red[300]!)),
            child: Row(children: [
              Icon(Icons.cancel, color: Colors.red[700], size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reconciliation Rejected', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700], fontSize: 13)),
                if (_session?.rejectionReason != null)
                  Text('Reason: ${_session!.rejectionReason}', style: TextStyle(fontSize: 12, color: Colors.red[700])),
              ])),
            ]),
          ),
        if (isSubmitted)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue[300]!)),
            child: Row(children: [
              Icon(Icons.hourglass_top, color: Colors.blue[700], size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('Submitted for approval — waiting for reviewer.', style: TextStyle(fontSize: 12, color: Colors.blue[700]))),
              ElevatedButton(
                onPressed: _showApprovalDialog,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), visualDensity: VisualDensity.compact),
                child: const Text('Review', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),

        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              isFullyReconciled ? '✓ All transactions reconciled' : 'Reconciliation in progress',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isFullyReconciled ? _green : _orange),
            ),
            const SizedBox(height: 3),
            Text(
              isFullyReconciled ? 'Ready to finalize' : '$_totalUnmatched unmatched · $_totalPending pending',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ])),
          if (!requiresApproval && !isSubmitted)
            ElevatedButton.icon(
              onPressed: isFullyReconciled ? _markAsReconciled : null,
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Mark as Reconciled', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          if (requiresApproval && !isSubmitted) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: isFullyReconciled ? _submitForApproval : null,
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Submit for Approval', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue, foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  // ── empty state ────────────────────────────────────────────────────────────

  Widget _emptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(child: Column(children: [
        Icon(Icons.inbox, size: 48, color: Colors.grey[300]),
        const SizedBox(height: 12),
        Text(msg, style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      ])),
    );
  }

  // ── closing balance dialogs ────────────────────────────────────────────────

  Future<double?> _showClosingBalanceEntryDialog() {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _teal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.lock_outline, color: _teal)),
          const SizedBox(width: 12),
          const Expanded(child: Text('Enter Statement Closing Balance', style: TextStyle(fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.teal[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal[200]!)),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.teal[700], size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Enter the closing balance from your statement. This will be verified before locking.', style: TextStyle(fontSize: 12, color: Colors.teal[900]))),
            ])),
          const SizedBox(height: 16),
          TextFormField(controller: ctrl, autofocus: true,
            decoration: InputDecoration(labelText: 'Statement Closing Balance *', prefixIcon: const Icon(Icons.currency_rupee), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: Text('Cancel', style: TextStyle(color: Colors.grey[600]))),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v == null) { _showError('Enter a valid amount'); return; }
              Navigator.pop(context, v);
            },
            style: ElevatedButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
            child: const Text('Verify & Finalize'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showClosingBalanceMismatchDialog(String message, Map<String, dynamic> check) {
    final diff = (check['difference'] as num).toDouble();
    final sys  = (check['systemClosingBalance'] as num).toDouble();
    final stmt = (check['statementClosingBalance'] as num).toDouble();
    final sev  = check['severity'] ?? 'medium';
    Color c = sev == 'high' ? _red : sev == 'medium' ? _orange : Colors.yellow[800]!;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(Icons.warning_amber, color: c, size: 28), const SizedBox(width: 12), const Text('Closing Balance Mismatch')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _balanceRow('System Closing', '₹${sys.toStringAsFixed(2)}', _blue),
          const SizedBox(height: 8),
          _balanceRow('Statement Closing', '₹${stmt.toStringAsFixed(2)}', _green),
          const Divider(height: 20),
          _balanceRow('Difference', '₹${diff.abs().toStringAsFixed(2)}', c, bold: true),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
            child: Text('• Check for missing transactions\n• Verify closing balance is correct\n• Acknowledge and proceed if timing difference', style: TextStyle(fontSize: 12, color: Colors.blue[900]))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go Back')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white),
            child: const Text('Acknowledge & Lock')),
        ],
      ),
    );
  }

  Widget _balanceRow(String label, String value, Color color, {bool bold = false}) {
    return Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: Colors.grey[700]))),
      Text(value, style: TextStyle(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
    ]);
  }

  // ── match confirmation dialog ──────────────────────────────────────────────

  Future<bool?> _showMatchConfirmationDialog(Map<String, dynamic> result) {
    final details  = result['details'] ?? {};
    final warnings = result['warnings'] as List? ?? [];
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(Icons.warning_amber, color: _orange, size: 26), const SizedBox(width: 12), const Text('Confirm Match')]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Text(result['message'] ?? 'Mismatch detected', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange[900]))),
          const SizedBox(height: 14),
          _balanceRow('Bank Amount',   '₹${details['bankAmount'] ?? 0}', _blue),
          const SizedBox(height: 6),
          _balanceRow('System Amount', '₹${details['systemAmount'] ?? 0}', _green),
          const Divider(height: 20),
          _balanceRow('Difference',    '₹${details['difference'] ?? 0}', _red, bold: true),
          const SizedBox(height: 10),
          _balanceRow('Bank Date',   details['bankDate']?.toString() ?? '', _blue),
          const SizedBox(height: 6),
          _balanceRow('System Date', details['systemDate']?.toString() ?? '', _green),
          if (result['suggestion'] != null) ...[
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(6)),
              child: Text(result['suggestion'], style: TextStyle(fontSize: 11, color: Colors.blue[900]))),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white),
            child: const Text('Force Match')),
        ],
      ),
    );
  }

  // ── report dialog ──────────────────────────────────────────────────────────

Future<void> _showReportDialog(Map<String, dynamic> data) async {
  final summary = data['summary'] as Map<String, dynamic>;
  final fmt     = NumberFormat('#,##0.00');
  await showDialog(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 680),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Color(0xFF0D1B3E),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
            child: Row(children: [
              const Icon(Icons.picture_as_pdf, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reconciliation Report', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${widget.accountName} · ${DateFormat('dd MMM').format(_session!.periodStart)} – ${DateFormat('dd MMM yyyy').format(_session!.periodEnd)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ])),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _reportCard('Matched',     summary['matched'],       _green,  '₹${fmt.format(summary['matchedAmount'])}'),
              const SizedBox(width: 10),
              _reportCard('Adjustments', summary['adjustments'],   _orange, '₹${fmt.format(summary['adjustmentAmount'])}'),
              const SizedBox(width: 10),
              _reportCard('Carried Fwd', summary['carriedForward'], _purple, '₹${fmt.format(summary['carriedForwardAmount'])}'),
              const SizedBox(width: 10),
              _reportCard('Unmatched',   summary['unmatched'],     _red,    ''),
            ]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Balance Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _balanceRow('Provider Balance', '₹${fmt.format(_session!.providerBalance)}', _blue),
                const SizedBox(height: 6),
                _balanceRow('System Balance',   '₹${fmt.format(_session!.systemBalance)}',   _green),
                const Divider(height: 20),
                _balanceRow('Difference', '₹${fmt.format(_session!.balanceDifference)}',
                    _session!.balanceDifference < 0.01 ? _green : _orange, bold: true),
                if (_session!.isLocked) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.lock, size: 13, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Text(
                      'Locked ${_session!.lockedAt != null ? DateFormat('dd MMM yyyy').format(_session!.lockedAt!) : ''} by ${_session!.lockedBy ?? 'system'}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _session!.isLocked ? _green.withOpacity(0.08) : _orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _session!.isLocked ? _green.withOpacity(0.3) : _orange.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(_session!.isLocked ? Icons.lock : Icons.lock_open, size: 16,
                    color: _session!.isLocked ? _green : _orange),
                const SizedBox(width: 8),
                Text(_session!.isLocked ? 'Locked & Finalized' : 'In Progress',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                        color: _session!.isLocked ? _green : _orange)),
              ]),
            ),
          ]))),
          // ── Footer with Download button ───────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
            ),
            child: Row(children: [
              // Download PDF button
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  if (_session == null) return;
                  try {
                    setState(() => _isLoading = true);
                    final token = await FinanceSecureStorage.getToken() ?? '';
                    final url = '${FinanceApiConfig.baseUrl}/api/finance/reconciliation/sessions/${_session!.id}/report/pdf?token=$token';
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      _showError('Could not open PDF');
                    }
                    setState(() => _isLoading = false);
                  } catch (e) {
                    setState(() => _isLoading = false);
                    _showError('Download failed: $e');
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

  Widget _reportCard(String label, dynamic count, Color color, String amount) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(count.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        if (amount.isNotEmpty) Text(amount, style: TextStyle(fontSize: 11, color: color)),
      ]),
    ));
  }

  Widget _reviewInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _decisionCard(String label, IconData icon, Color color, bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? color : Colors.grey[300]!, width: selected ? 2 : 1),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

// =============================================================================
//  IMPORT STATEMENT DIALOG — 2-STEP PATTERN
//  Step 1: Download template (pre-built columns matching backend exactly)
//  Step 2: Upload file → importProviderStatementBytes / importProviderStatement
// =============================================================================

class _ImportStatementDialog extends StatefulWidget {
  final String accountId;
  final Future<void> Function() onImportComplete;

  const _ImportStatementDialog({required this.accountId, required this.onImportComplete});

  @override
  State<_ImportStatementDialog> createState() => _ImportStatementDialogState();
}

class _ImportStatementDialogState extends State<_ImportStatementDialog> {
  final ReconciliationBillingService _service = ReconciliationBillingService();

  bool _downloading = false;
  bool _uploading   = false;
  String?    _fileName;
  Uint8List? _fileBytes;
  File?      _file;
  Map<String, dynamic>? _results;

  // Pre-configured column mappings — match backend extractTransactionData() exactly
  // Backend looks for these column names via findColumnName() fuzzy matching
  static const Map<String, String> _columnMappings = {
    'dateColumn':        'Transaction Date',
    'debitColumn':       'Debit',
    'creditColumn':      'Credit',
    'descriptionColumn': 'Description',
    'referenceColumn':   'Reference Number',
    'locationColumn':    'Location',
    'cardNumberColumn':  'Card Number',
  };

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      // Template columns match backend column names exactly
      final data = <List<dynamic>>[
        [
          'Transaction Date', // dateColumn → parseDate() handles DD/MM/YYYY & YYYY-MM-DD
          'Debit',            // debitColumn → used for DEBIT type transactions
          'Credit',           // creditColumn → used for CREDIT type transactions
          'Description',      // descriptionColumn
          'Reference Number', // referenceColumn
          'Location',         // locationColumn
          'Card Number',      // cardNumberColumn
        ],
        // Example row 1 — Debit transaction
        ['22/01/2026', '800.00', '', 'Fuel Purchase', 'REF001', 'Shell Marathahalli', 'xxxx-5678'],
        // Example row 2 — Credit transaction
        ['23/01/2026', '', '500.00', 'Refund', 'REF002', '', ''],
        // Example row 3
        ['24/01/2026', '1200.00', '', 'Maintenance', 'REF003', 'HP Whitefield', 'xxxx-5678'],
        // Instructions row
        ['--- INSTRUCTIONS ---',
         'Enter debit amounts (expenses)',
         'Enter credit amounts (refunds/receipts)',
         'Transaction description',
         'Bank reference/transaction ID',
         'Merchant location (optional)',
         'Card number used (optional) — DELETE THIS ROW BEFORE UPLOADING'],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'bank_statement_template');
      setState(() => _downloading = false);
      _showSnack('Template downloaded! Fill in your transactions and upload.', _green);
    } catch (e) {
      setState(() => _downloading = false);
      _showSnack('Download failed: $e', _red);
    }
  }

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false, withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      if (picked.bytes == null) { _showSnack('Could not read file', _red); return; }

      setState(() {
        _fileName  = picked.name;
        _fileBytes = picked.bytes;
        _file      = kIsWeb ? null : (picked.path != null ? File(picked.path!) : null);
        _results   = null;
        _uploading = true;
      });

      Map<String, dynamic> importResult;

      if (kIsWeb && _fileBytes != null) {
        importResult = await _service.importProviderStatementBytes(
          accountId: widget.accountId,
          fileBytes: _fileBytes!,
          fileName: _fileName!,
          columnMappings: _columnMappings,
          dateFormat: 'DD/MM/YYYY',
        );
      } else if (_file != null) {
        importResult = await _service.importProviderStatement(
          accountId: widget.accountId,
          file: _file!,
          columnMappings: _columnMappings,
          dateFormat: 'DD/MM/YYYY',
        );
      } else {
        // Fallback: use bytes even on mobile if file path not available
        importResult = await _service.importProviderStatementBytes(
          accountId: widget.accountId,
          fileBytes: _fileBytes!,
          fileName: _fileName!,
          columnMappings: _columnMappings,
          dateFormat: 'DD/MM/YYYY',
        );
      }

      final data = importResult['data'] ?? {};
      setState(() {
        _uploading = false;
        _results = {
          'imported':   data['imported']  ?? 0,
          'duplicates': data['duplicates'] ?? 0,
          'errors':     data['errors']    ?? 0,
          'errorDetails': data['errorDetails'] ?? [],
          'message':    importResult['message'] ?? 'Import complete',
        };
      });

      if ((_results!['imported'] as int) > 0) {
        _showSnack('✅ ${_results!['imported']} transaction(s) imported!', _green);
        await widget.onImportComplete();
      }
      if ((_results!['duplicates'] as int) > 0) {
        _showSnack('⚠ ${_results!['duplicates']} duplicate(s) skipped', _orange);
      }
      if ((_results!['errors'] as int) > 0) {
        _showSnack('❌ ${_results!['errors']} row(s) failed', _red);
      }

    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _showSnack('Import failed: $e', _red);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width > 600
            ? 560
            : MediaQuery.of(context).size.width * 0.92,
        // ✅ FIX: constrain height so dialog doesn't overflow screen,
        // and wrap content in SingleChildScrollView so results are reachable
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Fixed header (never scrolls) ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.upload_file_rounded, color: _blue, size: 24)),
                const SizedBox(width: 14),
                const Expanded(child: Text('Import Bank Statement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 8),
              Text('Upload your bank/provider statement. Supported formats: XLSX, XLS, CSV.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 24),
            ]),
          ),
          // ── Scrollable body ────────────────────────────────────────────
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Step 1 — Download template
          _importStep(
            step: '1', color: _blue, icon: Icons.download_rounded,
            title: 'Download Template',
            subtitle: 'Get the Excel template with correct column headers and 2 example rows.',
            buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
            onPressed: _downloading || _uploading ? null : _downloadTemplate,
          ),
          const SizedBox(height: 16),

          // Step 2 — Upload
          _importStep(
            step: '2', color: _green, icon: Icons.upload_rounded,
            title: 'Upload Your Statement',
            subtitle: 'Fill in the template and upload, or upload your bank\'s statement directly.',
            buttonLabel: _uploading ? 'Importing…' : (_fileName != null ? 'Change File' : 'Select File'),
            onPressed: _downloading || _uploading ? null : _pickAndUpload,
          ),

          // File selected indicator
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
              child: Row(children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8),
                Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600, fontSize: 13))),
                if (_uploading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _green)),
              ]),
            ),
          ],

          // Column mapping info
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDDE3EE))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text('Expected column names in your file:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: ['Transaction Date', 'Debit', 'Credit', 'Description', 'Reference Number', 'Location', 'Card Number'].map((col) =>
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                    child: Text(col, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _navy)),
                  )
                ).toList(),
              ),
              const SizedBox(height: 6),
              Text('Date format: DD/MM/YYYY or YYYY-MM-DD. Only Debit column is required (Credit is optional).', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ),

          // Results
          if (_results != null) ...[
            const Divider(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                _resultRow('Successfully Imported', '${_results!['imported']}', _green),
                const SizedBox(height: 6),
                _resultRow('Duplicates Skipped',    '${_results!['duplicates']}', _orange),
                const SizedBox(height: 6),
                _resultRow('Rows Failed',            '${_results!['errors']}', _red),
                if ((_results!['errorDetails'] as List).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: _red, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: SingleChildScrollView(
                      child: Text(
                        (_results!['errorDetails'] as List).map((e) => 'Row ${e['row']}: ${e['error']}').join('\n'),
                        style: const TextStyle(fontSize: 11, color: _red),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Close & Refresh'),
            )),
          ],  // end results if-block
        ]),   // end scrollable Column children
      )),     // end Flexible + SingleChildScrollView
        ]),   // end outer Column children
      ),      // end Container
    );        // end Dialog
  }

  Widget _importStep({
    required String step, required Color color, required IconData icon,
    required String title, required String subtitle,
    required String buttonLabel, required VoidCallback? onPressed,
  }) {
    final circle = Container(width: 34, height: 34, decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color, foregroundColor: Colors.white,
        disabledBackgroundColor: color.withOpacity(0.4), elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 12), button]);
      }),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ]);
  }
}

// =============================================================================
//  PETTY CASH INLINE PAGE (preserved exactly)
// =============================================================================

class _PettyCashInlinePage extends StatefulWidget {
  final String accountId;
  final String accountName;
  final DateTime periodStart;
  final DateTime periodEnd;

  const _PettyCashInlinePage({
    required this.accountId, required this.accountName,
    required this.periodStart, required this.periodEnd,
  });

  @override
  State<_PettyCashInlinePage> createState() => _PettyCashInlinePageState();
}

class _PettyCashInlinePageState extends State<_PettyCashInlinePage> {
  final ReconciliationBillingService _service = ReconciliationBillingService();
  final TextEditingController _cashCtrl  = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _isLoading    = true;
  bool _isSubmitting = false;
  bool _submitted    = false;

  double _openingBalance  = 0;
  double _totalExpenses   = 0;
  double _expectedBalance = 0;
  int    _expenseCount    = 0;
  List<Map<String, dynamic>> _expenses = [];

  double? _physicalCount;
  double? _variance;

  @override
  void initState() { super.initState(); _loadData(); }

  @override
  void dispose() { _cashCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final summary = await _service.getPettyCashSummary(
        accountId: widget.accountId,
        startDate: widget.periodStart,
        endDate: widget.periodEnd,
      );
      if (summary['success'] == true) {
        final d = summary['data'];
        setState(() {
          _openingBalance  = (d['openingBalance'] ?? 0).toDouble();
          _totalExpenses   = (d['totalExpenses']  ?? 0).toDouble();
          _expectedBalance = (d['expectedBalance'] ?? 0).toDouble();
          _expenseCount    = d['expenseCount'] ?? 0;
          _expenses        = List<Map<String, dynamic>>.from(d['expenses'] ?? []);
        });
      }
    } catch (e) { print('Petty cash load error: $e'); }
    setState(() => _isLoading = false);
  }

  Future<void> _submit() async {
    final count = double.tryParse(_cashCtrl.text.trim());
    if (count == null) { _showSnack('Enter a valid cash count amount', _red); return; }
    setState(() => _isSubmitting = true);
    try {
      await _service.submitPettyCashCount(
        accountId: widget.accountId, accountName: widget.accountName,
        periodStart: widget.periodStart, periodEnd: widget.periodEnd,
        physicalCashCount: count,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      setState(() { _physicalCount = count; _variance = count - _expectedBalance; _submitted = true; _isSubmitting = false; });
    } catch (e) { setState(() => _isSubmitting = false); _showSnack('Failed: $e', _red); }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: _navy));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Balance cards
        Row(children: [
          _pcCard('Opening Balance', _openingBalance, Icons.account_balance_wallet, _purple),
          const SizedBox(width: 12),
          _pcCard('Total Expenses', _totalExpenses, Icons.receipt_long, _red, subtitle: '$_expenseCount expenses'),
          const SizedBox(width: 12),
          _pcCard('Expected Closing', _expectedBalance, Icons.calculate, _blue, subtitle: 'Opening − Expenses'),
        ]),
        const SizedBox(height: 20),

        // Expenses list
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(color: Color(0xFF0D1B3E), borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
              child: Row(children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text('Petty Cash Expenses', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Text('$_expenseCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
              ]),
            ),
            if (_expenses.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No expenses for this period', style: TextStyle(color: Colors.grey))))
            else ...[
              Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.grey[100],
                child: Row(children: [
                  Expanded(flex: 2, child: Text('DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 0.5))),
                  Expanded(flex: 4, child: Text('DESCRIPTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 0.5))),
                  Expanded(flex: 3, child: Text('VENDOR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 0.5))),
                  Expanded(flex: 2, child: Text('AMOUNT', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600], letterSpacing: 0.5))),
                ]),
              ),
              ..._expenses.asMap().entries.map((entry) {
                final e = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: entry.key.isEven ? Colors.white : Colors.grey[50],
                  child: Row(children: [
                    Expanded(flex: 2, child: Text(_fmtDate(e['date']), style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                    Expanded(flex: 4, child: Text(e['expenseAccount'] ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 3, child: Text(e['vendor'] ?? '-', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Expanded(flex: 2, child: Text('₹${(e['total'] ?? 0).toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _red))),
                  ]),
                );
              }),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                child: Row(children: [
                  const Expanded(flex: 9, child: Text('Total Expenses', style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text('₹${_totalExpenses.toStringAsFixed(2)}', textAlign: TextAlign.right, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red[700]))),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 20),

        // Cash count input
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.calculate, color: _purple, size: 24)),
              const SizedBox(width: 12),
              const Text('Physical Cash Count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(flex: 2, child: TextFormField(
                controller: _cashCtrl, enabled: !_submitted,
                decoration: InputDecoration(
                  labelText: 'Actual Cash Counted *',
                  prefixIcon: const Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: _submitted ? Colors.grey[100] : Colors.white,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: TextFormField(
                controller: _notesCtrl, enabled: !_submitted,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: _submitted ? Colors.grey[100] : Colors.white,
                ),
              )),
            ]),
            const SizedBox(height: 16),
            if (!_submitted)
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle),
                label: Text(_isSubmitting ? 'Submitting…' : 'Submit Cash Count', style: const TextStyle(fontSize: 15)),
                style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: _green.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: _green.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: _green),
                  const SizedBox(width: 10),
                  Text('Submitted successfully', style: const TextStyle(fontWeight: FontWeight.w600, color: _green)),
                  const Spacer(),
                  TextButton(onPressed: () => setState(() { _submitted = false; _cashCtrl.clear(); _notesCtrl.clear(); }), child: const Text('Re-submit')),
                ]),
              ),
          ]),
        ),

        // Result
        if (_submitted && _variance != null) ...[
          const SizedBox(height: 20),
          _buildPCResult(),
        ],
      ]),
    );
  }

  Widget _pcCard(String label, double amount, IconData icon, Color color, {String? subtitle}) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 20)),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text('₹${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ]),
    ));
  }

  Widget _buildPCResult() {
    final v      = _variance!;
    final hasVar = v.abs() > 0.01;
    final isOver = v > 0;
    final c      = hasVar ? _orange : _green;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withOpacity(0.4), width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasVar ? Icons.warning_amber : Icons.check_circle, color: c, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hasVar ? 'Variance Detected' : 'Perfectly Balanced ✓', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c)),
            Text(hasVar ? (isOver ? 'You have ₹${v.toStringAsFixed(2)} MORE than expected' : 'You are SHORT by ₹${v.abs().toStringAsFixed(2)}') : 'Physical count matches expected balance', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.3))),
            child: Text('${isOver ? '+' : ''}₹${v.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))),
        ]),
        const SizedBox(height: 16), const Divider(), const SizedBox(height: 12),
        _pcResultRow('Opening Balance',     '₹${_openingBalance.toStringAsFixed(2)}',  _purple),
        const SizedBox(height: 6),
        _pcResultRow('Less: Expenses',      '− ₹${_totalExpenses.toStringAsFixed(2)}', _red),
        const Divider(height: 20),
        _pcResultRow('Expected Closing',    '₹${_expectedBalance.toStringAsFixed(2)}', _blue,   bold: true),
        const SizedBox(height: 6),
        _pcResultRow('Physical Count',      '₹${_physicalCount!.toStringAsFixed(2)}',  _purple, bold: true),
        const Divider(height: 20),
        _pcResultRow('Variance',            '${isOver ? '+' : ''}₹${v.toStringAsFixed(2)}', c,  bold: true),
      ]),
    );
  }

  Widget _pcResultRow(String label, String value, Color color, {bool bold = false}) {
    return Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: bold ? 14 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: Colors.grey[700]))),
      Text(value, style: TextStyle(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.bold : FontWeight.w600, color: color)),
    ]);
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '-';
    try { return DateFormat('dd MMM yyyy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }
}

// Extension
extension _ListExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}