// ============================================================================
// RECONCILIATION — COMPLETE ZOHO BOOKS PIN-TO-PIN
// ============================================================================
// File: lib/screens/banking/reconciliation_billing.dart
//
// SCREENS:
//   Screen 1 → History List     (all past reconciliations)
//   Screen 2 → Initiate Dialog  (start date + end date + closing balance)
//   Screen 3 → Working Screen   (transaction checkboxes, live difference)
//   Screen 4 → Completed View   (read-only after reconciliation done)
//   Report   → Reconciliation Status Report (3 sections + export)
// ============================================================================

import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html show Blob, Url, AnchorElement;
import '../../../core/services/bank_transaction_service.dart';
import '../../../core/finance_secure_storage.dart';
import '../../../app/config/api_config.dart';

// ── colours ──────────────────────────────────────────────────────────────────
const Color _navy       = Color(0xFF0D1B3E);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);
const Color _red        = Color(0xFFE74C3C);
const Color _orange     = Color(0xFFE67E22);
const Color _blue       = Color(0xFF2980B9);
const Color _teal       = Color(0xFF16A085);
const Color _grey       = Color(0xFF7F8C8D);
const Color _bg         = Color(0xFFF4F6F9);
const Color _white      = Colors.white;

final _fmt  = NumberFormat('#,##,##0.00');
final _dfmt = DateFormat('dd MMM yyyy');
final _ifmt = DateFormat('dd/MM/yyyy');

// ── Simple HTTP service for reconciliation ────────────────────────────────────
class _RecService {
  final BankTransactionService _base = BankTransactionService();

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? params}) =>
      _base.publicGet(path, params: params);

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      _base.publicPost(path, body);

  Future<Map<String, dynamic>> _put(String path, Map<String, dynamic> body) =>
      _base.publicPut(path, body);

  Future<Map<String, dynamic>> _delete(String path) =>
      _base.publicDelete(path);

  // History
  Future<Map<String, dynamic>> getHistory(String accountId) =>
      _get('/api/finance/reconciliation/$accountId/history');

  // Initiate
  Future<Map<String, dynamic>> initiate({
    required String accountId,
    required String startDate,
    required String endDate,
    required double closingBalance,
  }) => _post('/api/finance/reconciliation/initiate', {
    'accountId':      accountId,
    'startDate':      startDate,
    'endDate':        endDate,
    'closingBalance': closingBalance,
  });

  // Transactions for working screen
  Future<Map<String, dynamic>> getTransactions(String recId) =>
      _get('/api/finance/reconciliation/$recId/transactions');

  // Save progress
  Future<Map<String, dynamic>> saveProgress({
    required String recId,
    required List<String> clearedTxnIds,
    double? closingBalance,
  }) => _put('/api/finance/reconciliation/$recId/save-progress', {
    'clearedTxnIds': clearedTxnIds,
    if (closingBalance != null) 'closingBalance': closingBalance,
  });

  // +Add Transaction
  Future<Map<String, dynamic>> addTransaction({
    required String recId,
    required String type,
    required String date,
    required double amount,
    required String coaAccountId,
    String? description,
    String? reference,
  }) => _post('/api/finance/reconciliation/$recId/add-transaction', {
    'type':         type,
    'date':         date,
    'amount':       amount,
    'coaAccountId': coaAccountId,
    if (description != null) 'description': description,
    if (reference   != null) 'reference':   reference,
  });

  // Complete
  Future<Map<String, dynamic>> complete(String recId) =>
      _post('/api/finance/reconciliation/$recId/complete', {});

  // Undo
  Future<Map<String, dynamic>> undo(String recId) =>
      _post('/api/finance/reconciliation/$recId/undo', {});

  // Delete
  Future<Map<String, dynamic>> delete(String recId) =>
      _delete('/api/finance/reconciliation/$recId');

  // Report
  Future<Map<String, dynamic>> getReport(String accountId, {String? recId}) =>
      _get('/api/finance/reconciliation/$accountId/report',
          params: recId != null ? {'reconciliationId': recId} : null);

  // COA options for +Add Transaction
  Future<Map<String, dynamic>> getCOAOptions(String context) =>
      _get('/api/finance/banking/coa-options', params: {'context': context});
}

// ============================================================================
// MAIN PAGE — RECONCILIATION BILLING PAGE
// Entry point: pushed from AccountDetailPage Reconcile button
// ============================================================================
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
  State<ReconciliationBillingPage> createState() =>
      _ReconciliationBillingPageState();
}

class _ReconciliationBillingPageState
    extends State<ReconciliationBillingPage> {
  final _svc = _RecService();

  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final r = await _svc.getHistory(widget.accountId);
      if (r['success'] == true) {
        setState(() {
          _history = List<Map<String, dynamic>>.from(r['data'] ?? []);
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // ── INITIATE DIALOG ────────────────────────────────────────────────────────
  void _showInitiateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InitiateDialog(
        svc:       _svc,
        accountId: widget.accountId,
        onCreated: (rec) {
          Navigator.pop(context);
          _loadHistory();
          _openWorkingScreen(rec);
        },
      ),
    ).then((_) {
      // Refresh history when dialog is closed (in case of error or cancellation)
      _loadHistory();
    });
  }

  // ── OPEN WORKING SCREEN ────────────────────────────────────────────────────
  void _openWorkingScreen(Map<String, dynamic> rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _WorkingScreen(
          svc:         _svc,
          rec:         rec,
          accountName: widget.accountName,
          onDone:      _loadHistory,
        ),
      ),
    );
  }

  // ── OPEN COMPLETED VIEW ────────────────────────────────────────────────────
  void _openCompletedView(Map<String, dynamic> rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CompletedView(
          svc:         _svc,
          rec:         rec,
          accountName: widget.accountName,
          accountId:   widget.accountId,
        ),
      ),
    );
  }

  // ── UNDO ──────────────────────────────────────────────────────────────────
  Future<void> _undo(Map<String, dynamic> rec) async {
    final confirmed = await _confirm(
      'Undo Reconciliation',
      'This will revert all transactions to unreconciled state. Continue?',
    );
    if (!confirmed) return;
    try {
      final r = await _svc.undo(rec['_id'].toString());
      if (r['success'] == true) {
        _showSnack('Reconciliation undone', _orange);
        _loadHistory();
      } else {
        _showSnack(r['message'] ?? 'Failed', _red);
      }
    } catch (e) {
      _showSnack('Error: $e', _red);
    }
  }

  // ── DELETE ────────────────────────────────────────────────────────────────
  Future<void> _delete(Map<String, dynamic> rec) async {
    final confirmed = await _confirm(
      'Delete Reconciliation',
      'This will permanently delete this reconciliation record. All transactions will return to unreconciled state. This cannot be undone.',
    );
    if (!confirmed) return;
    try {
      final r = await _svc.delete(rec['_id'].toString());
      if (r['success'] == true) {
        _showSnack('Reconciliation deleted', _green);
        _loadHistory();
      } else {
        _showSnack(r['message'] ?? 'Failed', _red);
      }
    } catch (e) {
      _showSnack('Error: $e', _red);
    }
  }

  Future<bool> _confirm(String title, String msg) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: _navy)),
        content: Text(msg, style: const TextStyle(fontSize: 13, color: Color(0xFF5D6D7E))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              child: const Text('Proceed',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:          Text(msg),
      backgroundColor:  color,
      behavior:         SnackBarBehavior.floating,
      shape:            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration:         const Duration(seconds: 3),
    ));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Is the most-recent reconciliation RECONCILED?
    String? mostRecentReconciledId;
    if (_history.isNotEmpty &&
        _history.first['status'] == 'RECONCILED') {
      mostRecentReconciledId = _history.first['_id']?.toString();
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _white,
        elevation:       0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _navy),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.accountName,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _navy)),
          const Text('Reconciliation',
              style: TextStyle(fontSize: 11, color: _grey)),
        ]),
        actions: [
          // Report button
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ReportScreen(
                    svc:              _svc,
                    accountId:        widget.accountId,
                    accountName:      widget.accountName,
                    reconciliationId: _history.isNotEmpty ? _history.first['_id']?.toString() : null),
              ),
            ),
            icon:  const Icon(Icons.bar_chart_outlined, size: 16, color: _blue),
            label: const Text('Report',
                style: TextStyle(fontSize: 12, color: _blue)),
          ),
          const SizedBox(width: 8),
          // Refresh button
          IconButton(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh_rounded, color: _navyAccent),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showInitiateDialog,
            icon:      const Icon(Icons.add, size: 14, color: Colors.white),
            label:     const Text('Initiate Reconciliation',
                style: TextStyle(fontSize: 12, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navyAccent))
          : _history.isEmpty
              ? _buildEmpty()
              : _buildHistoryList(mostRecentReconciledId),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 16),
      const Text('No reconciliations yet',
          style: TextStyle(fontSize: 15, color: _grey)),
      const SizedBox(height: 8),
      const Text('Click "Initiate Reconciliation" to start',
          style: TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: _showInitiateDialog,
        icon:  const Icon(Icons.add, size: 16),
        label: const Text('Initiate Reconciliation'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _navyAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ]),
  );

  Widget _buildHistoryList(String? mostRecentReconciledId) {
    return Column(children: [
      // Table header
      Container(
        color: const Color(0xFFF8F9FB),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(children: const [
          Expanded(flex: 3, child: _ColHdr('STATEMENT PERIOD')),
          Expanded(flex: 2, child: _ColHdr('CLOSING BALANCE', right: true)),
          Expanded(flex: 2, child: _ColHdr('STATUS', center: true)),
          SizedBox(width: 100),
        ]),
      ),
      const Divider(height: 1, color: Color(0xFFEEF2F7)),
      Expanded(
        child: ListView.separated(
          itemCount:       _history.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFEEF2F7)),
          itemBuilder: (_, i) {
            final rec      = _history[i];
            final recId    = rec['_id']?.toString() ?? '';
            final status   = rec['status']?.toString() ?? 'IN_PROGRESS';
            final isReconciled = status == 'RECONCILED';
            final closing  = (rec['closingBalance'] ?? 0).toDouble();
            final start    = _parseDate(rec['startDate']);
            final end      = _parseDate(rec['endDate']);
            final canUndo  = isReconciled && recId == mostRecentReconciledId;

            return InkWell(
              onTap: () => isReconciled
                  ? _openCompletedView(rec)
                  : _openWorkingScreen(rec),
              child: Container(
                color: _white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(children: [
                  // Period
                  Expanded(
                    flex: 3,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          '${_dfmt.format(start)} – ${_dfmt.format(end)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2C3E50))),
                      const SizedBox(height: 3),
                      Text(
                          isReconciled
                              ? 'Reconciled on ${_dfmt.format(_parseDate(rec['reconciledAt']))}'
                              : 'In progress — tap to continue',
                          style: TextStyle(
                              fontSize: 11,
                              color: isReconciled ? _green : _orange)),
                    ]),
                  ),
                  // Closing balance
                  Expanded(
                    flex: 2,
                    child: Text('₹${_fmt.format(closing)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C3E50))),
                  ),
                  // Status badge
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isReconciled
                              ? _green.withOpacity(0.1)
                              : _orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isReconciled ? _green : _orange,
                              width: 1),
                        ),
                        child: Text(
                            isReconciled ? 'Reconciled' : 'In Progress',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isReconciled ? _green : _orange)),
                      ),
                    ),
                  ),
                  // Actions
                  SizedBox(
                    width: 100,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                      if (canUndo)
                        _actionBtn(
                            'Undo',
                            Icons.undo_outlined,
                            _orange,
                            () => _undo(rec)),
                      const SizedBox(width: 4),
                      _actionBtn(
                          'Delete',
                          Icons.delete_outline,
                          _red,
                          () => _delete(rec)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _actionBtn(
          String tip, IconData icon, Color color, VoidCallback onTap) =>
      Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
        ),
      );
}

// ── Column header helper ──────────────────────────────────────────────────────
class _ColHdr extends StatelessWidget {
  final String label;
  final bool right;
  final bool center;
  const _ColHdr(this.label, {this.right = false, this.center = false});

  @override
  Widget build(BuildContext context) => Text(label,
      textAlign: right
          ? TextAlign.right
          : center
              ? TextAlign.center
              : TextAlign.left,
      style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF7F8C8D),
          letterSpacing: 0.5));
}

// ============================================================================
// SCREEN 2 — INITIATE DIALOG
// ============================================================================
class _InitiateDialog extends StatefulWidget {
  final _RecService svc;
  final String accountId;
  final void Function(Map<String, dynamic> rec) onCreated;

  const _InitiateDialog({
    required this.svc,
    required this.accountId,
    required this.onCreated,
  });

  @override
  State<_InitiateDialog> createState() => _InitiateDialogState();
}

class _InitiateDialogState extends State<_InitiateDialog> {
  final _closingCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default: first and last day of current month
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate   = DateTime(now.year, now.month + 1, 0);
  }

  @override
  void dispose() {
    _closingCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate:   DateTime(2020),
      lastDate:    DateTime(2030),
      builder:     (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _navyAccent),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_startDate == null || _endDate == null) {
      setState(() => _error = 'Please select both start and end date');
      return;
    }
    if (_closingCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Closing balance is required');
      return;
    }
    final closing = double.tryParse(_closingCtrl.text.trim().replaceAll(',', ''));
    if (closing == null) {
      setState(() => _error = 'Enter a valid closing balance');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'End date must be after start date');
      return;
    }

    setState(() { _saving = true; _error = null; });
    try {
      final r = await widget.svc.initiate(
        accountId:      widget.accountId,
        startDate:      _startDate!.toIso8601String(),
        endDate:        _endDate!.toIso8601String(),
        closingBalance: closing,
      );
      if (r['success'] == true) {
        widget.onCreated(Map<String, dynamic>.from(r['data']));
      } else {
        // Check if there's already a reconciliation in progress
        if (r['message']?.toString().contains('already in progress') == true) {
          setState(() => _saving = false);
          // Close the dialog and trigger a refresh to show the in-progress reconciliation
          Navigator.pop(context);
          // Show a snackbar to inform the user
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('A reconciliation is already in progress. Please complete or delete it first.'),
              backgroundColor: _orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Refresh',
                textColor: Colors.white,
                onPressed: () {
                  // The parent page will be refreshed when we return
                },
              ),
            ));
          }
          return;
        }
        setState(() => _error = r['message'] ?? 'Failed to initiate');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: _navyAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.account_balance_outlined,
                  color: _navyAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Initiate Reconciliation',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _navy)),
            ),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18, color: _grey)),
          ]),
          const SizedBox(height: 16),

          // Warning
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _orange.withOpacity(0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: _orange, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Opening balance cannot be edited once transactions are reconciled. '
                  'Ensure it is correct before proceeding.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5D6D7E)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Start Date
          const Text('Start Date *',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          _DateField(
              value:    _startDate,
              hint:     'Select start date',
              onTap:    () => _pickDate(true)),
          const SizedBox(height: 14),

          // End Date
          const Text('End Date *',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          _DateField(
              value:    _endDate,
              hint:     'Select end date',
              onTap:    () => _pickDate(false)),
          const SizedBox(height: 14),

          // Closing Balance
          const Text('Closing Balance (from bank statement) *',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
          const SizedBox(height: 6),
          TextField(
            controller:   _closingCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
            ],
            decoration: InputDecoration(
              hintText:      'Enter closing balance as shown on bank statement',
              hintStyle:     const TextStyle(fontSize: 12, color: Color(0xFFADB5BD)),
              prefixIcon:    const Icon(Icons.currency_rupee, size: 16, color: _grey),
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:   const BorderSide(color: Color(0xFFCBD5E1))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:   const BorderSide(color: _navyAccent)),
              isDense:       true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.error_outline, size: 14, color: _red),
              const SizedBox(width: 6),
              Expanded(child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: _red))),
            ]),
          ],

          const SizedBox(height: 24),

          // Buttons
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Cancel',
                  style: TextStyle(color: _grey)),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Start Reconciliation',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  const _DateField({required this.value, required this.hint, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.calendar_today_outlined, size: 15, color: _grey),
        const SizedBox(width: 10),
        Text(
          value != null ? _dfmt.format(value!) : hint,
          style: TextStyle(
              fontSize: 13,
              color: value != null
                  ? const Color(0xFF2C3E50)
                  : const Color(0xFFADB5BD)),
        ),
        const Spacer(),
        const Icon(Icons.arrow_drop_down, color: _grey),
      ]),
    ),
  );
}

// ============================================================================
// SCREEN 3 — MAIN WORKING SCREEN
// ============================================================================
class _WorkingScreen extends StatefulWidget {
  final _RecService svc;
  final Map<String, dynamic> rec;
  final String accountName;
  final VoidCallback onDone;

  const _WorkingScreen({
    required this.svc,
    required this.rec,
    required this.accountName,
    required this.onDone,
  });

  @override
  State<_WorkingScreen> createState() => _WorkingScreenState();
}

class _WorkingScreenState extends State<_WorkingScreen> {
  late Map<String, dynamic> _rec;
  List<Map<String, dynamic>> _txns = [];
  bool _loading  = true;
  bool _saving   = false;
  bool _completing = false;

  double _openingBalance = 0;
  double _closingBalance = 0;
  double _clearedAmount  = 0;
  double _difference     = 0;

  Set<String> _clearedIds = {};

  // Edit closing balance
  bool _editingClosing = false;
  final _closingEditCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rec = Map<String, dynamic>.from(widget.rec);
    _loadTransactions();
  }

  @override
  void dispose() {
    _closingEditCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    try {
      final r = await widget.svc.getTransactions(_rec['_id'].toString());
      if (r['success'] == true) {
        final txns = List<Map<String, dynamic>>.from(r['data'] ?? []);
        setState(() {
          _txns           = txns;
          _openingBalance = (r['openingBalance'] ?? 0).toDouble();
          _closingBalance = (r['closingBalance'] ?? 0).toDouble();
          _clearedAmount  = (r['clearedAmount']  ?? 0).toDouble();
          _difference     = (r['difference']     ?? _closingBalance).toDouble();

          // Pre-select already cleared ones
          _clearedIds = txns
              .where((t) => t['isCleared'] == true)
              .map((t) => t['_id'].toString())
              .toSet();

          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // ── Toggle checkbox ────────────────────────────────────────────────────────
  void _toggleCleared(Map<String, dynamic> txn) {
    final id = txn['_id'].toString();
    setState(() {
      if (_clearedIds.contains(id)) {
        _clearedIds.remove(id);
      } else {
        _clearedIds.add(id);
      }
      _recalcLive();
    });
    _autoSave(); // auto-save progress
  }

  void _recalcLive() {
    double cleared = 0;
    for (final t in _txns) {
      if (_clearedIds.contains(t['_id'].toString())) {
        if (t['transactionType'] == 'CREDIT') {
          cleared += (t['amount'] ?? 0).toDouble();
        } else {
          cleared -= (t['amount'] ?? 0).toDouble();
        }
      }
    }
    _clearedAmount = cleared;
    _difference    = _closingBalance - _clearedAmount;
  }

  // ── Auto-save ──────────────────────────────────────────────────────────────
  Future<void> _autoSave() async {
    try {
      await widget.svc.saveProgress(
        recId:        _rec['_id'].toString(),
        clearedTxnIds: _clearedIds.toList(),
      );
    } catch (_) {}
  }

  // ── Save and Reconcile Later ───────────────────────────────────────────────
  Future<void> _saveAndLater() async {
    setState(() => _saving = true);
    try {
      final r = await widget.svc.saveProgress(
        recId:         _rec['_id'].toString(),
        clearedTxnIds: _clearedIds.toList(),
      );
      if (r['success'] == true) {
        _showSnack('Progress saved. You can continue later.', _green);
        Navigator.pop(context);
        widget.onDone();
      } else {
        _showSnack(r['message'] ?? 'Failed', _red);
      }
    } catch (e) {
      _showSnack('Error: $e', _red);
    }
    setState(() => _saving = false);
  }

  // ── Edit Closing Balance ───────────────────────────────────────────────────
  void _startEditClosing() {
    _closingEditCtrl.text = _closingBalance.toStringAsFixed(2);
    setState(() => _editingClosing = true);
  }

  Future<void> _updateClosing() async {
    final val = double.tryParse(_closingEditCtrl.text.replaceAll(',', ''));
    if (val == null) return;
    setState(() {
      _closingBalance = val;
      _editingClosing = false;
      _recalcLive();
    });
    await widget.svc.saveProgress(
      recId:         _rec['_id'].toString(),
      clearedTxnIds: _clearedIds.toList(),
      closingBalance: val,
    );
  }

  // ── Complete Reconciliation ────────────────────────────────────────────────
  Future<void> _complete() async {
    if (_difference.abs() > 0.01) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Complete Reconciliation',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: _navy)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'You are about to finalize this reconciliation. '
              'This will lock the period and mark all cleared transactions as reconciled.',
              style: TextStyle(fontSize: 13, color: Color(0xFF5D6D7E))),
          const SizedBox(height: 16),
          _summaryRow('Opening Balance',  '₹${_fmt.format(_openingBalance)}'),
          _summaryRow('Closing Balance',  '₹${_fmt.format(_closingBalance)}'),
          _summaryRow('Cleared Amount',   '₹${_fmt.format(_clearedAmount)}'),
          _summaryRow('Difference',       '₹${_fmt.format(_difference)}',
              color: _difference.abs() < 0.01 ? _green : _red),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child: const Text('Reconcile',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _completing = true);
    try {
      // Save latest progress first
      await widget.svc.saveProgress(
        recId:         _rec['_id'].toString(),
        clearedTxnIds: _clearedIds.toList(),
      );
      final r = await widget.svc.complete(_rec['_id'].toString());
      if (r['success'] == true) {
        _showSnack('Reconciliation completed!', _green);
        Navigator.pop(context);
        widget.onDone();
      } else {
        _showSnack(r['message'] ?? 'Failed', _red);
      }
    } catch (e) {
      _showSnack('Error: $e', _red);
    }
    setState(() => _completing = false);
  }

  Widget _summaryRow(String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF5D6D7E))),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color ?? const Color(0xFF2C3E50))),
        ]),
      );

  // ── +Add Transaction ───────────────────────────────────────────────────────
  void _showAddTransaction() {
    showModalBottomSheet(
      context:     context,
      isScrollControlled: true,
      shape:       const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder:     (_) => _AddTransactionSheet(
        svc:      widget.svc,
        recId:    _rec['_id'].toString(),
        onAdded:  () {
          Navigator.pop(context);
          _loadTransactions();
        },
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: color,
      behavior:        SnackBarBehavior.floating,
      shape:           RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isZero = _difference.abs() < 0.01;
    final start  = _parseDate(_rec['startDate']);
    final end    = _parseDate(_rec['endDate']);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // ── HEADER ────────────────────────────────────────────────────────────
        Container(
          color: _white,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
          ),
          child: Row(children: [
            IconButton(
              icon:      const Icon(Icons.arrow_back, size: 18, color: _navy),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 6),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(widget.accountName,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _navy)),
              Text(
                  '${_dfmt.format(start)} – ${_dfmt.format(end)}',
                  style: const TextStyle(fontSize: 11, color: _grey)),
            ])),
            // Save Later
            OutlinedButton(
              onPressed: _saving ? null : _saveAndLater,
              style: OutlinedButton.styleFrom(
                side:    const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: _saving
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _grey))
                  : const Text('Save and Reconcile Later',
                      style: TextStyle(fontSize: 12, color: _grey)),
            ),
            const SizedBox(width: 10),
            // RECONCILE BUTTON
            ElevatedButton(
              onPressed: isZero && !_completing ? _complete : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isZero ? _green : const Color(0xFFCBD5E1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: _completing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Reconcile',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ]),
        ),

        // ── SUMMARY STRIP ─────────────────────────────────────────────────────
        Container(
          color: _white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
          ),
          child: Row(children: [
            _balanceCard('Opening Balance',
                '₹${_fmt.format(_openingBalance)}', _blue),
            const SizedBox(width: 1),
            _closingBalanceCard(),
            const SizedBox(width: 1),
            _balanceCard('Cleared Amount',
                '₹${_fmt.format(_clearedAmount)}', _teal),
            const SizedBox(width: 1),
            _differenceCard(isZero),
          ]),
        ),

        // ── TABLE HEADER ─────────────────────────────────────────────────────
        Container(
          color: const Color(0xFFF8F9FB),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(children: const [
            SizedBox(width: 36),
            SizedBox(width: 100, child: _ColHdr('DATE')),
            SizedBox(width: 120, child: _ColHdr('TYPE')),
            Expanded(child: _ColHdr('DESCRIPTION / REF')),
            SizedBox(width: 120, child: _ColHdr('DEPOSITS', right: true)),
            SizedBox(width: 120, child: _ColHdr('WITHDRAWALS', right: true)),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFEEF2F7)),

        // ── TRANSACTION LIST ──────────────────────────────────────────────────
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _navyAccent))
          : _txns.isEmpty
              ? _buildEmptyTxns()
              : ListView.separated(
                  itemCount:        _txns.length + 1, // +1 for +Add Transaction row
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFEEF2F7)),
                  itemBuilder: (_, i) {
                    if (i == _txns.length) return _buildAddTxnRow();
                    return _buildTxnRow(_txns[i]);
                  },
                ),
        ),
      ]),
    );
  }

  Widget _buildEmptyTxns() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[300]),
      const SizedBox(height: 14),
      const Text('No categorized transactions for this period',
          style: TextStyle(fontSize: 13, color: _grey)),
      const SizedBox(height: 8),
      const Text(
          'Categorize transactions first, or use +Add Transaction\nfor bank charges/interest not yet in your books',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFADB5BD))),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: _showAddTransaction,
        icon:      const Icon(Icons.add, size: 14, color: _navyAccent),
        label:     const Text('+Add Transaction',
            style: TextStyle(fontSize: 12, color: _navyAccent)),
        style: OutlinedButton.styleFrom(
            side:  const BorderSide(color: _navyAccent),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6))),
      ),
    ]),
  );

  Widget _buildAddTxnRow() => InkWell(
    onTap: _showAddTransaction,
    child: Container(
      color: _white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
        const SizedBox(width: 36),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _navyAccent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: _navyAccent.withOpacity(0.3), style: BorderStyle.solid),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.add, size: 14, color: _navyAccent),
            SizedBox(width: 6),
            Text('+Add Transaction',
                style: TextStyle(
                    fontSize: 12,
                    color: _navyAccent,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        const Text(
            'Add bank charges, interest or any transaction not in your books',
            style: TextStyle(fontSize: 11, color: Color(0xFFADB5BD))),
      ]),
    ),
  );

  Widget _buildTxnRow(Map<String, dynamic> txn) {
    final id        = txn['_id'].toString();
    final isCleared = _clearedIds.contains(id);
    final isCredit  = txn['transactionType'] == 'CREDIT';
    final amount    = (txn['amount'] ?? 0).toDouble();
    final date      = _parseDate(txn['transactionDate']);
    final desc      = txn['description']?.toString()   ?? '';
    final ref       = txn['referenceNumber']?.toString() ?? '';
    final type      = txn['categoryLabel']?.toString()  ??
                      txn['reconciliationStatus']?.toString() ?? '';
    final isAdded   = txn['isManuallyAdded'] == true;

    return InkWell(
      onTap: () => _toggleCleared(txn),
      child: Container(
        color: isCleared
            ? _green.withOpacity(0.04)
            : _white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          SizedBox(width: 36,
              child: Checkbox(
                value:                 isCleared,
                onChanged:             (_) => _toggleCleared(txn),
                activeColor:           _green,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )),
          SizedBox(width: 100,
              child: Text(_dfmt.format(date),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF5D6D7E)))),
          SizedBox(width: 120,
              child: Row(children: [
                if (isAdded)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Added',
                        style: TextStyle(
                            fontSize: 9,
                            color: _blue,
                            fontWeight: FontWeight.bold)),
                  ),
                Flexible(child: Text(type,
                    overflow:  TextOverflow.ellipsis,
                    style:     const TextStyle(
                        fontSize: 12, color: Color(0xFF2C3E50)))),
              ])),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            if (desc.isNotEmpty)
              Text(desc,
                  maxLines:  1,
                  overflow:  TextOverflow.ellipsis,
                  style:     const TextStyle(
                      fontSize: 12, color: Color(0xFF2C3E50))),
            if (ref.isNotEmpty)
              Text('Ref: $ref',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF7F8C8D))),
          ])),
          SizedBox(width: 120,
              child: Text(
                  isCredit ? '₹${_fmt.format(amount)}' : '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _green))),
          SizedBox(width: 120,
              child: Text(
                  !isCredit ? '₹${_fmt.format(amount)}' : '',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _red))),
        ]),
      ),
    );
  }

  Widget _balanceCard(String label, String value, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.15)),
          borderRadius: BorderRadius.circular(8),
          color: color.withOpacity(0.04),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: _grey)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ]),
      ));

  Widget _closingBalanceCard() => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      border: Border.all(color: _navyAccent.withOpacity(0.2)),
      borderRadius: BorderRadius.circular(8),
      color: _navyAccent.withOpacity(0.04),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Closing Balance',
          style: TextStyle(fontSize: 10, color: _grey)),
      const SizedBox(height: 4),
      _editingClosing
          ? Row(children: [
              Expanded(child: TextField(
                controller:   _closingEditCtrl,
                autofocus:    true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style:        const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: _navy),
                decoration: const InputDecoration(
                  isDense:       true,
                  contentPadding: EdgeInsets.zero,
                  border:        InputBorder.none,
                ),
                onSubmitted: (_) => _updateClosing(),
              )),
              GestureDetector(
                onTap: _updateClosing,
                child: const Icon(Icons.check_circle,
                    size: 18, color: _green),
              ),
            ])
          : Row(children: [
              Text('₹${_fmt.format(_closingBalance)}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _navyAccent)),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _startEditClosing,
                child: const Icon(Icons.edit_outlined,
                    size: 13, color: _grey),
              ),
            ]),
    ]),
  ));

  Widget _differenceCard(bool isZero) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      border: Border.all(
          color: (isZero ? _green : _red).withOpacity(0.3)),
      borderRadius: BorderRadius.circular(8),
      color: (isZero ? _green : _red).withOpacity(0.05),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Difference',
          style: TextStyle(fontSize: 10, color: _grey)),
      const SizedBox(height: 4),
      Row(children: [
        Text('₹${_fmt.format(_difference)}',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isZero ? _green : _red)),
        if (isZero) ...[
          const SizedBox(width: 6),
          const Icon(Icons.check_circle,
              size: 16, color: _green),
        ],
      ]),
      if (!isZero)
        const Text('Must be ₹0.00 to reconcile',
            style: TextStyle(fontSize: 9, color: _red)),
    ]),
  ));
}

// ============================================================================
// +ADD TRANSACTION BOTTOM SHEET
// ============================================================================
class _AddTransactionSheet extends StatefulWidget {
  final _RecService svc;
  final String recId;
  final VoidCallback onAdded;

  const _AddTransactionSheet({
    required this.svc,
    required this.recId,
    required this.onAdded,
  });

  @override
  State<_AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<_AddTransactionSheet> {
  String _type = 'DEBIT';
  DateTime _date  = DateTime.now();
  final _amountCtrl  = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _refCtrl     = TextEditingController();

  List<Map<String, dynamic>> _coaOptions = [];
  Map<String, dynamic>? _selectedCOA;
  bool _loadingCOA = true;
  bool _saving     = false;

  @override
  void initState() {
    super.initState();
    _loadCOA();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCOA() async {
    try {
      // Load both expense and income COA
      final rExp = await widget.svc.getCOAOptions('expense');
      final rInc = await widget.svc.getCOAOptions('income');
      final all  = <Map<String, dynamic>>[];
      if (rExp['success'] == true) {
        all.addAll(List<Map<String, dynamic>>.from(rExp['data'] ?? []));
      }
      if (rInc['success'] == true) {
        all.addAll(List<Map<String, dynamic>>.from(rInc['data'] ?? []));
      }
      setState(() {
        _coaOptions  = all;
        _loadingCOA  = false;
      });
    } catch (_) {
      setState(() => _loadingCOA = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context:     context,
      initialDate: _date,
      firstDate:   DateTime(2020),
      lastDate:    DateTime(2030),
      builder:     (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _navyAccent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_selectedCOA == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: _red));
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a valid amount'),
          backgroundColor: _red));
      return;
    }

    setState(() => _saving = true);
    try {
      final r = await widget.svc.addTransaction(
        recId:       widget.recId,
        type:        _type,
        date:        _date.toIso8601String(),
        amount:      amount,
        coaAccountId: _selectedCOA!['id'].toString(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        reference:   _refCtrl.text.trim().isEmpty
            ? null
            : _refCtrl.text.trim(),
      );
      if (r['success'] == true) {
        widget.onAdded();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:         Text(r['message'] ?? 'Failed'),
            backgroundColor: _red));
        setState(() => _saving = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Error: $e'),
          backgroundColor: _red));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            const Text('+Add Transaction',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _navy)),
            const Spacer(),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, size: 18, color: _grey)),
          ]),
          const Text(
              'Add a transaction that is on your bank statement but not yet in your books '
              '(e.g. bank charges, interest income)',
              style: TextStyle(fontSize: 11, color: _grey)),
          const SizedBox(height: 16),

          // Type selector
          Row(children: [
            _typeBtn('DEBIT',  'Money Out (Debit)',  Icons.arrow_upward),
            const SizedBox(width: 10),
            _typeBtn('CREDIT', 'Money In (Credit)',  Icons.arrow_downward),
          ]),
          const SizedBox(height: 14),

          // Date + Amount row
          Row(children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Date *',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
              const SizedBox(height: 4),
              _DateField(
                  value: _date, hint: 'Select date', onTap: _pickDate),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Amount *',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
              const SizedBox(height: 4),
              TextField(
                controller:   _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixIcon:    const Icon(Icons.currency_rupee, size: 14, color: _grey),
                  hintText:      '0.00',
                  isDense:       true,
                  border:        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:   const BorderSide(color: Color(0xFFCBD5E1))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:   const BorderSide(color: _navyAccent)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 12),
                ),
              ),
            ])),
          ]),
          const SizedBox(height: 14),

          // Category (COA)
          const Text('Category *',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
          const SizedBox(height: 4),
          _loadingCOA
              ? const LinearProgressIndicator(color: _navyAccent)
              : DropdownButtonFormField<Map<String, dynamic>>(
                  value:     _selectedCOA,
                  isExpanded: true,
                  hint: const Text('Select category (e.g. Bank Charges, Interest Income)',
                      style: TextStyle(fontSize: 12, color: Color(0xFFADB5BD))),
                  items: _coaOptions.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text('${c['accountName']} (${c['accountType']})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedCOA = v),
                  decoration: InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                  ),
                ),
          const SizedBox(height: 14),

          // Description + Reference
          Row(children: [
            Expanded(child: TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: const TextStyle(fontSize: 11),
                isDense:    true,
                border:     OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 12),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(child: TextField(
              controller: _refCtrl,
              decoration: InputDecoration(
                labelText: 'Reference (optional)',
                labelStyle: const TextStyle(fontSize: 11),
                isDense:    true,
                border:     OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 12),
              ),
            )),
          ]),
          const SizedBox(height: 20),

          SizedBox(width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navyAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: _saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Add & Mark as Cleared',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
              )),
        ]),
      ),
    );
  }

  Widget _typeBtn(String value, String label, IconData icon) =>
      Expanded(child: InkWell(
        onTap: () => setState(() => _type = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: _type == value
                ? (value == 'DEBIT'
                    ? _red.withOpacity(0.08)
                    : _green.withOpacity(0.08))
                : const Color(0xFFF8F9FA),
            border: Border.all(
                color: _type == value
                    ? (value == 'DEBIT' ? _red : _green)
                    : const Color(0xFFCBD5E1),
                width: _type == value ? 1.5 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon,
                size:  14,
                color: _type == value
                    ? (value == 'DEBIT' ? _red : _green)
                    : _grey),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _type == value
                        ? (value == 'DEBIT' ? _red : _green)
                        : _grey)),
          ]),
        ),
      ));
}

// ============================================================================
// SCREEN 4 — COMPLETED VIEW (read-only)
// ============================================================================
class _CompletedView extends StatefulWidget {
  final _RecService svc;
  final Map<String, dynamic> rec;
  final String accountName;
  final String accountId;

  const _CompletedView({
    required this.svc,
    required this.rec,
    required this.accountName,
    required this.accountId,
  });

  @override
  State<_CompletedView> createState() => _CompletedViewState();
}

class _CompletedViewState extends State<_CompletedView> {
  List<Map<String, dynamic>> _txns = [];
  bool _loading = true;
  double _openingBalance = 0;
  double _closingBalance = 0;
  double _clearedAmount  = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.svc.getTransactions(
          widget.rec['_id'].toString());
      if (r['success'] == true) {
        setState(() {
          _txns           = List<Map<String, dynamic>>.from(r['data'] ?? [])
              .where((t) => t['isCleared'] == true)
              .toList();
          _openingBalance = (r['openingBalance'] ?? 0).toDouble();
          _closingBalance = (r['closingBalance'] ?? 0).toDouble();
          _clearedAmount  = (r['clearedAmount']  ?? 0).toDouble();
          _loading        = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final start       = _parseDate(widget.rec['startDate']);
    final end         = _parseDate(widget.rec['endDate']);
    final reconciledAt = _parseDate(widget.rec['reconciledAt']);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _navy),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.accountName,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _navy)),
          Text('${_dfmt.format(start)} – ${_dfmt.format(end)}',
              style: const TextStyle(fontSize: 11, color: _grey)),
        ]),
        actions: [
          // View Report
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _ReportScreen(
                  svc:            widget.svc,
                  accountId:      widget.accountId,
                  accountName:    widget.accountName,
                  reconciliationId: widget.rec['_id']?.toString(),
                ),
              ),
            ),
            icon:  const Icon(Icons.bar_chart_outlined, size: 14, color: _blue),
            label: const Text('View Report',
                style: TextStyle(fontSize: 12, color: _blue)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(children: [
        // Reconciled banner
        Container(
          color: _green.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            const Icon(Icons.check_circle, color: _green, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Reconciled on ${_dfmt.format(reconciledAt)}',
              style: const TextStyle(
                  fontSize: 13, color: _green, fontWeight: FontWeight.w600),
            )),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:        _green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Reconciled',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
        ),

        // Summary strip
        Container(
          color: _white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE8ECF0))),
          ),
          child: Row(children: [
            _sCard('Opening Balance',
                '₹${_fmt.format(_openingBalance)}', _blue),
            const SizedBox(width: 8),
            _sCard('Closing Balance',
                '₹${_fmt.format(_closingBalance)}', _navyAccent),
            const SizedBox(width: 8),
            _sCard('Cleared Amount',
                '₹${_fmt.format(_clearedAmount)}', _teal),
            const SizedBox(width: 8),
            _sCard('Difference',  '₹0.00', _green),
          ]),
        ),

        // Cleared transactions list
        Container(
          color: const Color(0xFFF8F9FB),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(children: const [
            SizedBox(width: 100, child: _ColHdr('DATE')),
            SizedBox(width: 140, child: _ColHdr('TYPE')),
            Expanded(child: _ColHdr('DESCRIPTION / REF')),
            SizedBox(width: 110, child: _ColHdr('DEPOSITS', right: true)),
            SizedBox(width: 110, child: _ColHdr('WITHDRAWALS', right: true)),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFEEF2F7)),

        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: _navyAccent))
          : ListView.separated(
              itemCount:        _txns.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFEEF2F7)),
              itemBuilder: (_, i) {
                final txn     = _txns[i];
                final isCredit = txn['transactionType'] == 'CREDIT';
                final amount   = (txn['amount'] ?? 0).toDouble();
                final date     = _parseDate(txn['transactionDate']);
                final desc     = txn['description']?.toString()    ?? '';
                final ref      = txn['referenceNumber']?.toString() ?? '';
                final type     = txn['categoryLabel']?.toString()   ?? '';

                return Container(
                  color: _white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  child: Row(children: [
                    SizedBox(width: 100,
                        child: Text(_dfmt.format(date),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF5D6D7E)))),
                    SizedBox(width: 140,
                        child: Text(type,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF2C3E50)))),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      if (desc.isNotEmpty)
                        Text(desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF2C3E50))),
                      if (ref.isNotEmpty)
                        Text('Ref: $ref',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7F8C8D))),
                    ])),
                    SizedBox(width: 110,
                        child: Text(
                            isCredit ? '₹${_fmt.format(amount)}' : '',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _green))),
                    SizedBox(width: 110,
                        child: Text(
                            !isCredit ? '₹${_fmt.format(amount)}' : '',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _red))),
                  ]),
                );
              },
            )),
      ]),
    );
  }

  Widget _sCard(String label, String value, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(8),
          color: color.withOpacity(0.04),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _grey)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ]),
      ));
}

// ============================================================================
// REPORT SCREEN — Reconciliation Status Report
// 3 sections + Export PDF + Export CSV
// ============================================================================
class _ReportScreen extends StatefulWidget {
  final _RecService svc;
  final String accountId;
  final String accountName;
  final String? reconciliationId;

  const _ReportScreen({
    required this.svc,
    required this.accountId,
    required this.accountName,
    this.reconciliationId,
  });

  @override
  State<_ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<_ReportScreen> {
  Map<String, dynamic>? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final r = await widget.svc.getReport(
          widget.accountId,
          recId: widget.reconciliationId);
      if (r['success'] == true) {
        setState(() {
          _report  = Map<String, dynamic>.from(r['data']);
          _loading = false;
        });
      } else {
        setState(() {
          _error   = r['message'];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  /// Summary card widget for PDF export
  pw.Widget _summaryCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: color, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 7,
                color: const PdfColor.fromInt(0xFF7F8C8D),
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the flat list of rows used by both PDF and Excel exports.
  /// Returns: { openingBalance, closingBalance, reconciledOn, rows, period }
  Map<String, dynamic> _buildExportData() {
    final summary  = _report!['summary']  as Map<String, dynamic>;
    final sections = _report!['sections'] as Map<String, dynamic>;
    final period   = _report!['period']   as Map<String, dynamic>;

    final openingBalance = (summary['openingBalance'] ?? 0).toDouble();
    final closingBalance = (summary['closingBalance'] ?? 0).toDouble();
    final reconciledOn   = _report!['reconciledAt'] ?? _report!['updatedAt'];

    final List<Map<String, dynamic>> rows = [];

    for (final sectionKey in ['cleared', 'unmatched', 'outstanding']) {
      final sec  = sections[sectionKey] as Map<String, dynamic>;
      final txns = List<Map<String, dynamic>>.from(sec['transactions'] ?? []);
      for (final t in txns) {
        final isCredit = t['transactionType'] == 'CREDIT';
        final amount   = (t['amount'] ?? 0).toDouble();
        final date     = _parseDate(t['transactionDate']);

        // Build "Transaction Details" — description + optional ref
        final desc = t['description']?.toString() ?? '';
        final ref  = t['referenceNumber']?.toString() ?? '';

        // Build "Type" — category + optional vendor/customer sub-line
        final typeMain = t['categoryLabel']?.toString() ?? '';
        final typeSub  = t['vendorName']?.toString() ??
                         t['customerName']?.toString() ?? '';

        rows.add({
          'date':      date,
          'desc':      desc,
          'ref':       ref,
          'typeMain':  typeMain,
          'typeSub':   typeSub,
          'deposit':   isCredit ? amount : 0.0,
          'withdrawal': !isCredit ? amount : 0.0,
        });
      }
    }

    // Sort by date ascending
    rows.sort((a, b) =>
        (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    return {
      'openingBalance': openingBalance,
      'closingBalance': closingBalance,
      'reconciledOn':   reconciledOn,
      'rows':           rows,
      'period':         period,
    };
  }

  // ── PDF Export ────────────────────────────────────────────────────────────
  Future<void> _exportPDF() async {
    if (_report == null) return;
    try {
      final data           = _buildExportData();
      final rows           = data['rows'] as List<Map<String, dynamic>>;
      final openingBalance = data['openingBalance'] as double;
      final closingBalance = data['closingBalance'] as double;
      final reconciledOn   = data['reconciledOn'];
      final period         = data['period'] as Map<String, dynamic>;

      final startDate = _parseDate(period['startDate']);
      final endDate   = _parseDate(period['endDate']);

      // ── Fetch org/branch info for header ──
      final orgName    = await FinanceSecureStorage.getOrgName()    ?? widget.accountName;
      final orgLogoUrl = await FinanceSecureStorage.getOrgLogoUrl();

      // ── Try to load logo bytes ──
      pw.MemoryImage? logoImage;
      if (orgLogoUrl != null && orgLogoUrl.isNotEmpty) {
        try {
          final fullUrl = orgLogoUrl.startsWith('http')
              ? orgLogoUrl
              : '${ApiConfig.baseUrl}$orgLogoUrl';
          final response = await http.get(Uri.parse(fullUrl));
          if (response.statusCode == 200) {
            logoImage = pw.MemoryImage(response.bodyBytes);
          }
        } catch (_) {}
      }

      final pdf = pw.Document();

      // ── colour palette ──
      const headerBg    = PdfColor.fromInt(0xFF0D1B3E); // navy
      const headerFg    = PdfColors.white;
      const accentBlue  = PdfColor.fromInt(0xFF1E3A8A);
      const rowAlt      = PdfColor.fromInt(0xFFF4F6F9);
      const borderCol   = PdfColor.fromInt(0xFFDDE4EF);
      const greenCol    = PdfColor.fromInt(0xFF27AE60);
      const redCol      = PdfColor.fromInt(0xFFE74C3C);
      const greyCol     = PdfColor.fromInt(0xFF7F8C8D);
      const lightBg     = PdfColor.fromInt(0xFFF7F9FC);
      const summaryBg   = PdfColor.fromInt(0xFFF0F4FF);

      final summary = _report!['summary'] as Map<String, dynamic>;
      final totalClearedCredits = (summary['totalClearedCredits'] ?? 0).toDouble();
      final totalClearedDebits  = (summary['totalClearedDebits']  ?? 0).toDouble();
      final difference          = (summary['difference']          ?? 0).toDouble();
      final recStatus           = summary['reconciliationStatus']?.toString() ?? 'IN_PROGRESS';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          header: (ctx) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: borderCol, width: 0.5)),
            ),
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  orgName.toUpperCase(),
                  style: pw.TextStyle(fontSize: 7, color: greyCol, letterSpacing: 0.5),
                ),
                pw.Text(
                  'Reconciliation Report - ${_ifmt.format(startDate)} to ${_ifmt.format(endDate)}',
                  style: pw.TextStyle(fontSize: 7, color: greyCol),
                ),
              ],
            ),
          ),
          footer: (ctx) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: borderCol, width: 0.5)),
            ),
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated on ${_ifmt.format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 7, color: greyCol),
                ),
                pw.Text(
                  'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: pw.TextStyle(fontSize: 7, color: greyCol),
                ),
              ],
            ),
          ),
          build: (ctx) {
            final tableRows = <List<String>>[];

            // Opening balance row
            tableRows.add([
              _ifmt.format(startDate),
              'Opening Balance',
              '',
              '',
              'Rs. ${_fmt.format(openingBalance)}',
            ]);

            // Transaction rows
            for (final r in rows) {
              final date       = r['date']       as DateTime;
              final desc       = r['desc']       as String;
              final ref        = r['ref']        as String;
              final typeMain   = r['typeMain']   as String;
              final deposit    = (r['deposit']   as double);
              final withdrawal = (r['withdrawal'] as double);

              final detailCell = ref.isNotEmpty ? '$desc\nRef: $ref' : desc;

              tableRows.add([
                _ifmt.format(date),
                detailCell,
                typeMain,
                deposit    > 0 ? 'Rs. ${_fmt.format(deposit)}'    : '',
                withdrawal > 0 ? 'Rs. ${_fmt.format(withdrawal)}' : '',
              ]);
            }

            // Closing balance row
            tableRows.add([
              _ifmt.format(endDate),
              'Closing Balance',
              '',
              '',
              'Rs. ${_fmt.format(closingBalance)}',
            ]);

            return [
              // ══════════════════════════════════════════════════════════════
              // HEADER — Logo + Company + Report Title
              // ══════════════════════════════════════════════════════════════
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Logo
                  if (logoImage != null) ...[
                    pw.Container(
                      width: 70,
                      height: 70,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: borderCol, width: 0.5),
                      ),
                      child: pw.ClipRRect(
                        horizontalRadius: 6,
                        verticalRadius: 6,
                        child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                      ),
                    ),
                    pw.SizedBox(width: 16),
                  ],
                  // Company info
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          orgName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: headerBg,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'BANKING & RECONCILIATION',
                          style: pw.TextStyle(
                            fontSize: 7,
                            color: greyCol,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Report title block (right side)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: pw.BoxDecoration(
                      color: headerBg,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'RECONCILIATION REPORT',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: headerFg,
                            letterSpacing: 0.8,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          widget.accountName,
                          style: pw.TextStyle(fontSize: 9, color: headerFg),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${_ifmt.format(startDate)} to ${_ifmt.format(endDate)}',
                          style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFFADD8E6)),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            color: recStatus == 'RECONCILED' ? greenCol : PdfColor.fromInt(0xFFE67E22),
                            borderRadius: pw.BorderRadius.circular(10),
                          ),
                          child: pw.Text(
                            recStatus == 'RECONCILED' ? 'RECONCILED' : 'IN PROGRESS',
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: headerFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 20),

              // ══════════════════════════════════════════════════════════════
              // SUMMARY CARDS
              // ══════════════════════════════════════════════════════════════
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderCol, width: 0.5),
                ),
                padding: const pw.EdgeInsets.all(12),
                child: pw.Row(
                  children: [
                    _summaryCard('Opening Balance', 'Rs. ${_fmt.format(openingBalance)}', accentBlue),
                    pw.SizedBox(width: 8),
                    _summaryCard('Closing Balance', 'Rs. ${_fmt.format(closingBalance)}', accentBlue),
                    pw.SizedBox(width: 8),
                    _summaryCard('Total Credits', 'Rs. ${_fmt.format(totalClearedCredits)}', greenCol),
                    pw.SizedBox(width: 8),
                    _summaryCard('Total Debits', 'Rs. ${_fmt.format(totalClearedDebits)}', redCol),
                    pw.SizedBox(width: 8),
                    _summaryCard(
                      'Difference',
                      'Rs. ${_fmt.format(difference)}',
                      difference == 0 ? greenCol : redCol,
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // ══════════════════════════════════════════════════════════════
              // TRANSACTIONS TABLE
              // ══════════════════════════════════════════════════════════════
              pw.Text(
                'TRANSACTION DETAILS',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: greyCol,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 6),

              pw.Table(
                border: pw.TableBorder.all(color: borderCol, width: 0.5),
                columnWidths: {
                  0: const pw.FixedColumnWidth(68),   // DATE
                  1: const pw.FlexColumnWidth(3.5),   // TRANSACTION DETAILS
                  2: const pw.FlexColumnWidth(2),     // TYPE
                  3: const pw.FixedColumnWidth(75),   // DEPOSITS
                  4: const pw.FixedColumnWidth(75),   // WITHDRAWALS
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: headerBg),
                    children: [
                      'DATE',
                      'TRANSACTION DETAILS',
                      'TYPE',
                      'DEPOSITS',
                      'WITHDRAWALS',
                    ].asMap().entries.map((e) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: pw.Text(
                        e.value,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: headerFg,
                        ),
                        textAlign: e.key >= 3 ? pw.TextAlign.right : pw.TextAlign.left,
                      ),
                    )).toList(),
                  ),

                  // Data rows
                  ...tableRows.asMap().entries.map((entry) {
                    final idx      = entry.key;
                    final row      = entry.value;
                    final isOpen   = row[1] == 'Opening Balance';
                    final isClose  = row[1] == 'Closing Balance';
                    final isSpecial = isOpen || isClose;
                    final bg = isSpecial
                        ? summaryBg
                        : (idx % 2 == 0 ? PdfColors.white : rowAlt);

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: bg),
                      children: row.asMap().entries.map((cell) {
                        final colIdx = cell.key;
                        final val    = cell.value;
                        final isAmt  = colIdx >= 3;
                        final isDeposit    = colIdx == 3;
                        final isWithdrawal = colIdx == 4;

                        final textColor = isDeposit && val.isNotEmpty
                            ? greenCol
                            : isWithdrawal && val.isNotEmpty
                                ? redCol
                                : isSpecial
                                    ? headerBg
                                    : PdfColors.black;

                        return pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                          child: pw.Text(
                            val,
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: isSpecial ? pw.FontWeight.bold : pw.FontWeight.normal,
                              color: textColor,
                            ),
                            textAlign: isAmt ? pw.TextAlign.right : pw.TextAlign.left,
                          ),
                        );
                      }).toList(),
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 16),

              // ══════════════════════════════════════════════════════════════
              // FOOTER NOTE
              // ══════════════════════════════════════════════════════════════
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (reconciledOn != null)
                    pw.Text(
                      'Reconciled on: ${_ifmt.format(_parseDate(reconciledOn))}',
                      style: pw.TextStyle(fontSize: 8, color: greenCol, fontWeight: pw.FontWeight.bold),
                    )
                  else
                    pw.Text(
                      'Status: In Progress',
                      style: pw.TextStyle(fontSize: 8, color: PdfColor.fromInt(0xFFE67E22)),
                    ),
                  pw.Text(
                    'Difference: Rs. ${_fmt.format(difference)}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: difference == 0 ? greenCol : redCol,
                    ),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final bytes    = await pdf.save();
      final filename =
          'reconciliation_${widget.accountName.replaceAll(' ', '_')}_'
          '${DateFormat('yyyyMMdd').format(startDate)}.pdf';

      if (kIsWeb) {
        final blob   = html.Blob([bytes], 'application/pdf');
        final url    = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final dir  = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         const Text('PDF exported successfully'),
          backgroundColor: _green,
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('PDF export failed: $e'),
          backgroundColor: _red,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Excel Export ──────────────────────────────────────────────────────────
  Future<void> _exportExcel() async {
    if (_report == null) return;
    try {
      final data           = _buildExportData();
      final rows           = data['rows'] as List<Map<String, dynamic>>;
      final openingBalance = data['openingBalance'] as double;
      final closingBalance = data['closingBalance'] as double;
      final reconciledOn   = data['reconciledOn'];
      final period         = data['period'] as Map<String, dynamic>;

      final startDate = _parseDate(period['startDate']);
      final endDate   = _parseDate(period['endDate']);

      final book  = xl.Excel.createExcel();
      final sheet = book['Reconciliation Details'];
      book.delete('Sheet1');

      // ── styles ──
      final titleStyle = xl.CellStyle(
        bold:      true,
        fontSize:  16,
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      final subStyle = xl.CellStyle(
        bold:      true,
        fontSize:  12,
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      final periodStyle = xl.CellStyle(
        fontSize:  10,
        horizontalAlign: xl.HorizontalAlign.Center,
        fontColorHex: xl.ExcelColor.fromHexString('#7F8C8D'),
      );
      final headerStyle = xl.CellStyle(
        bold:             true,
        fontSize:         10,
        backgroundColorHex: xl.ExcelColor.fromHexString('#0D1B3E'),
        fontColorHex:     xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign:  xl.HorizontalAlign.Left,
      );
      final specialRowStyle = xl.CellStyle(
        bold:             true,
        fontSize:         9,
        backgroundColorHex: xl.ExcelColor.fromHexString('#EEF2FF'),
      );
      final amtGreenStyle = xl.CellStyle(
        fontSize:         9,
        fontColorHex:     xl.ExcelColor.fromHexString('#27AE60'),
        horizontalAlign:  xl.HorizontalAlign.Right,
      );
      final amtRedStyle = xl.CellStyle(
        fontSize:         9,
        fontColorHex:     xl.ExcelColor.fromHexString('#E74C3C'),
        horizontalAlign:  xl.HorizontalAlign.Right,
      );
      final normalStyle = xl.CellStyle(fontSize: 9);

      int r = 0;

      // ── Title rows ──
      void _setCell(int row, int col, dynamic value, xl.CellStyle? style) {
        final cell = sheet.cell(
            xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        cell.value = xl.TextCellValue(value.toString());
        if (style != null) cell.cellStyle = style;
      }

      _setCell(r, 0, widget.accountName, titleStyle);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
                  xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r));
      r++;

      _setCell(r, 0, 'Reconciliation Details', subStyle);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
                  xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r));
      r++;

      _setCell(r, 0, widget.accountName, subStyle);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
                  xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r));
      r++;

      _setCell(r, 0, 'Reconciliation Period', periodStyle);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
                  xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r));
      r++;

      _setCell(r, 0,
          '${_ifmt.format(startDate)} To ${_ifmt.format(endDate)}',
          periodStyle);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r),
                  xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r));
      r++;
      r++; // blank row

      // ── Column headers ──
      final headers = ['DATE', 'TRANSACTION DETAILS', 'TYPE', 'DEPOSITS', 'WITHDRAWALS'];
      for (int c = 0; c < headers.length; c++) {
        _setCell(r, c, headers[c], headerStyle);
      }
      r++;

      // ── Opening balance ──
      _setCell(r, 0, _ifmt.format(startDate), specialRowStyle);
      _setCell(r, 1, '***Opening Balance***', specialRowStyle);
      _setCell(r, 2, '', specialRowStyle);
      _setCell(r, 3, '', specialRowStyle);
      _setCell(r, 4, '₹${_fmt.format(openingBalance)}',
          xl.CellStyle(
            bold: true, fontSize: 9,
            backgroundColorHex: xl.ExcelColor.fromHexString('#EEF2FF'),
            fontColorHex: xl.ExcelColor.fromHexString('#E74C3C'),
            horizontalAlign: xl.HorizontalAlign.Right,
          ));
      r++;

      // ── Transaction rows ──
      for (final row in rows) {
        final date       = row['date'] as DateTime;
        final desc       = row['desc'] as String;
        final ref        = row['ref']  as String;
        final typeMain   = row['typeMain'] as String;
        final typeSub    = row['typeSub']  as String;
        final deposit    = (row['deposit']    as double);
        final withdrawal = (row['withdrawal'] as double);

        final detailCell = ref.isNotEmpty ? '$desc\nRef#: $ref' : desc;
        final typeCell   = typeSub.isNotEmpty ? '$typeMain\n$typeSub' : typeMain;

        _setCell(r, 0, _ifmt.format(date), normalStyle);
        _setCell(r, 1, detailCell, normalStyle);
        _setCell(r, 2, typeCell, normalStyle);
        _setCell(r, 3,
            deposit > 0 ? '₹${_fmt.format(deposit)}' : '',
            deposit > 0 ? amtGreenStyle : normalStyle);
        _setCell(r, 4,
            withdrawal > 0 ? '₹${_fmt.format(withdrawal)}' : '',
            withdrawal > 0 ? amtRedStyle : normalStyle);
        r++;
      }

      // ── Closing balance ──
      _setCell(r, 0, _ifmt.format(endDate), specialRowStyle);
      _setCell(r, 1, '***Closing Balance***', specialRowStyle);
      _setCell(r, 2, '', specialRowStyle);
      _setCell(r, 3, '', specialRowStyle);
      _setCell(r, 4, '₹${_fmt.format(closingBalance)}',
          xl.CellStyle(
            bold: true, fontSize: 9,
            backgroundColorHex: xl.ExcelColor.fromHexString('#EEF2FF'),
            fontColorHex: xl.ExcelColor.fromHexString('#E74C3C'),
            horizontalAlign: xl.HorizontalAlign.Right,
          ));
      r++;
      r++; // blank row

      // ── Reconciled On ──
      if (reconciledOn != null) {
        _setCell(r, 3, 'Reconciled On:', periodStyle);
        _setCell(r, 4,
            _ifmt.format(_parseDate(reconciledOn)),
            xl.CellStyle(
              fontSize: 9,
              fontColorHex: xl.ExcelColor.fromHexString('#7F8C8D'),
              horizontalAlign: xl.HorizontalAlign.Right,
            ));
      }

      // ── Column widths ──
      sheet.setColumnWidth(0, 14);
      sheet.setColumnWidth(1, 36);
      sheet.setColumnWidth(2, 28);
      sheet.setColumnWidth(3, 16);
      sheet.setColumnWidth(4, 16);

      final bytes    = Uint8List.fromList(book.encode()!);
      final filename =
          'reconciliation_${widget.accountName.replaceAll(' ', '_')}_'
          '${DateFormat('yyyyMMdd').format(startDate)}.xlsx';

      if (kIsWeb) {
        final blob   = html.Blob(
            [bytes],
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        final url    = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final dir  = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         const Text('Excel exported successfully'),
          backgroundColor: _green,
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('Excel export failed: $e'),
          backgroundColor: _red,
          behavior:        SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _navy),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.accountName,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _navy)),
          const Text('Reconciliation Status Report',
              style: TextStyle(fontSize: 11, color: _grey)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: _exportPDF,
            icon:  const Icon(Icons.picture_as_pdf_outlined,
                size: 14, color: _red),
            label: const Text('Export PDF',
                style: TextStyle(fontSize: 12, color: _red)),
          ),
          TextButton.icon(
            onPressed: _exportExcel,
            icon:  const Icon(Icons.table_chart_outlined,
                size: 14, color: _green),
            label: const Text('Export Excel',
                style: TextStyle(fontSize: 12, color: _green)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _navyAccent))
          : _error != null
              ? Center(child: Text('Error: $_error',
                  style: const TextStyle(color: _red)))
              : _buildReport(),
    );
  }

  Widget _buildReport() {
    final summary  = _report!['summary']  as Map<String, dynamic>;
    final sections = _report!['sections'] as Map<String, dynamic>;
    final period   = _report!['period']   as Map<String, dynamic>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Summary card ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Summary',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _navy)),
            const SizedBox(height: 4),
            Text(
                'Period: ${_dfmt.format(_parseDate(period['startDate']))} '
                '– ${_dfmt.format(_parseDate(period['endDate']))}',
                style: const TextStyle(fontSize: 12, color: _grey)),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFEEF2F7)),
            const SizedBox(height: 12),
            _rRow('Opening Balance',
                '₹${_fmt.format((summary['openingBalance'] ?? 0).toDouble())}',
                _blue),
            _rRow('Closing Balance',
                '₹${_fmt.format((summary['closingBalance'] ?? 0).toDouble())}',
                _navyAccent),
            _rRow('Total Cleared Credits',
                '₹${_fmt.format((summary['totalClearedCredits'] ?? 0).toDouble())}',
                _green),
            _rRow('Total Cleared Debits',
                '₹${_fmt.format((summary['totalClearedDebits'] ?? 0).toDouble())}',
                _red),
            _rRow('Uncategorized Transactions',
                '${summary['totalUncategorized'] ?? 0}', _orange),
            _rRow('Outstanding Transactions',
                '${summary['totalOutstanding'] ?? 0}', _orange),
            const Divider(color: Color(0xFFEEF2F7)),
            _rRow('Difference',
                '₹${_fmt.format((summary['difference'] ?? 0).toDouble())}',
                (summary['difference'] ?? 0).toDouble().abs() < 0.01
                    ? _green
                    : _red,
                bold: true),
          ]),
        ),
        const SizedBox(height: 20),

        // ── Section 1: Cleared ────────────────────────────────────────────────
        _buildSection(
          sections['cleared']   as Map<String, dynamic>,
          _green, Icons.check_circle_outline,
        ),
        const SizedBox(height: 16),

        // ── Section 2: Unmatched ──────────────────────────────────────────────
        _buildSection(
          sections['unmatched'] as Map<String, dynamic>,
          _orange, Icons.warning_amber_outlined,
        ),
        const SizedBox(height: 16),

        // ── Section 3: Outstanding ────────────────────────────────────────────
        _buildSection(
          sections['outstanding'] as Map<String, dynamic>,
          _blue, Icons.pending_outlined,
        ),
      ]),
    );
  }

  Widget _buildSection(
      Map<String, dynamic> sec, Color color, IconData icon) {
    final txns = List<Map<String, dynamic>>.from(sec['transactions'] ?? []);
    final totalCredits = (sec['totalCredits'] ?? 0).toDouble();
    final totalDebits  = (sec['totalDebits']  ?? 0).toDouble();

    return Container(
      decoration: BoxDecoration(
        color:        _white,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10)),
            border: Border(
                bottom: BorderSide(color: color.withOpacity(0.15))),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(sec['label']?.toString() ?? '',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color))),
            Text('${txns.length} transactions',
                style: TextStyle(fontSize: 11, color: color)),
          ]),
        ),

        if (txns.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('No transactions',
                style: TextStyle(
                    fontSize: 12, color: _grey,
                    fontStyle: FontStyle.italic)),
          )
        else ...[
          // Column headers
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: const Color(0xFFF8F9FB),
            child: Row(children: const [
              SizedBox(width: 90,  child: _ColHdr('DATE')),
              SizedBox(width: 130, child: _ColHdr('TYPE')),
              Expanded(child:      _ColHdr('DESCRIPTION')),
              SizedBox(width: 100, child: _ColHdr('DEPOSITS',    right: true)),
              SizedBox(width: 100, child: _ColHdr('WITHDRAWALS', right: true)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFEEF2F7)),

          // Rows
          ...txns.map((t) {
            final isCredit = t['transactionType'] == 'CREDIT';
            final amount   = (t['amount'] ?? 0).toDouble();
            final date     = _parseDate(t['transactionDate']);
            final desc     = t['description']?.toString()    ?? '';
            final type     = t['categoryLabel']?.toString()   ??
                             t['reconciliationStatus']?.toString() ?? '';
            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: Color(0xFFF0F0F0)))),
              child: Row(children: [
                SizedBox(width: 90,
                    child: Text(_dfmt.format(date),
                        style: const TextStyle(
                            fontSize: 11, color: _grey))),
                SizedBox(width: 130,
                    child: Text(type,
                        overflow:  TextOverflow.ellipsis,
                        style:     const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2C3E50)))),
                Expanded(child: Text(desc,
                    maxLines:  1,
                    overflow:  TextOverflow.ellipsis,
                    style:     const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5D6D7E)))),
                SizedBox(width: 100,
                    child: Text(
                        isCredit
                            ? '₹${_fmt.format(amount)}'
                            : '',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 11,
                            color: _green,
                            fontWeight: FontWeight.w600))),
                SizedBox(width: 100,
                    child: Text(
                        !isCredit
                            ? '₹${_fmt.format(amount)}'
                            : '',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 11,
                            color: _red,
                            fontWeight: FontWeight.w600))),
              ]),
            );
          }),

          // Section totals
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.04),
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10)),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
              Text('Total Deposits:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _grey)),
              const SizedBox(width: 8),
              Text('₹${_fmt.format(totalCredits)}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _green)),
              const SizedBox(width: 20),
              Text('Total Withdrawals:',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _grey)),
              const SizedBox(width: 8),
              Text('₹${_fmt.format(totalDebits)}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _red)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _rRow(String label, String value, Color color,
      {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF5D6D7E))),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.w600,
                  color: color)),
        ]),
      );
}

// ── Date parse helper ─────────────────────────────────────────────────────────
DateTime _parseDate(dynamic d) {
  if (d == null) return DateTime.now();
  try {
    return DateTime.parse(d.toString()).toLocal();
  } catch (_) {
    return DateTime.now();
  }
}