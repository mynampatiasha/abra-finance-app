import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// RECORD DEPOSIT DIALOG
// ============================================================================
// File: lib/screens/banking/record_deposit_dialog.dart
//
// Matches Zoho Books Record Deposit modal exactly:
//   - To Account (pre-filled, locked)
//   - Deposit Date
//   - Paid Via
//   - Reference#
//   - Description
//   - Currency (INR locked)
//   - Select Transactions (filters + table of system transactions to deposit)
//   - Other Deposits section → Add Other Deposits
// ============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/config/api_config.dart';
import '../../../core/services/bank_transaction_service.dart';
import '../../../core/services/add_account_service.dart';
import '../../../core/finance_secure_storage.dart';

const Color _navy = Color(0xFF1e3a8a);
const Color _green = Color(0xFF27AE60);
const Color _blue = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red = Color(0xFFE74C3C);

class RecordDepositDialog extends StatefulWidget {
  final String accountId;
  final String accountName;
  final VoidCallback? onSaved;

  const RecordDepositDialog({
    Key? key,
    required this.accountId,
    required this.accountName,
    this.onSaved,
  }) : super(key: key);

  @override
  State<RecordDepositDialog> createState() => _RecordDepositDialogState();
}

class _RecordDepositDialogState extends State<RecordDepositDialog> {
  final BankTransactionService _service = BankTransactionService();

  DateTime _depositDate = DateTime.now();
  String? _paidVia;
  final _refCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _otherAmountCtrl = TextEditingController();
  final _otherDescCtrl = TextEditingController();

  bool _loading = false;
  bool _saving = false;

  // Filter state
  String _filterReceivedFrom = 'All';
  String _filterEntityType = 'All';
  DateTime _filterDate = DateTime.now();

  // Transactions from system (invoices/payments)
  List<Map<String, dynamic>> _availableTxns = [];
  Set<String> _selectedTxnIds = {};
  bool _txnsLoading = false;

  // Other deposits (manual)
  List<Map<String, dynamic>> _otherDeposits = [];
  bool _showOtherDepositForm = false;

  // Bank account selector
  List<Map<String, dynamic>> _bankAccounts = [];
  String? _selectedBankId;
  String? _selectedBankName;
  bool _bankAccountsLoading = false;

  final List<String> _paymentModes = [
    'Cash',
    'Bank Transfer',
    'Cheque',
    'UPI',
    'Card',
    'Online',
    'NEFT',
    'RTGS',
  ];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _loadBankAccounts();
  }

  Future<void> _loadBankAccounts() async {
    setState(() => _bankAccountsLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/banking'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
        },
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        List<dynamic> list = [];
        if (body['data'] is List) {
          list = body['data'];
        } else if (body['data'] is Map) {
          list = body['data']['accounts'] ?? [];
        }
        setState(() {
          // Include ALL accounts — the current account is the deposit destination
          // and is shown locked in the header; the dropdown lets user pick source
          _bankAccounts =
              list.map((a) => Map<String, dynamic>.from(a)).toList();
          // Pre-select the current account as the deposit-to account
          if (_selectedBankId == null && _bankAccounts.isNotEmpty) {
            final match = _bankAccounts.firstWhere(
              (a) => a['_id']?.toString() == widget.accountId,
              orElse: () => _bankAccounts.first,
            );
            _selectedBankId = match['_id']?.toString();
            _selectedBankName = match['accountName']?.toString();
          }
          _bankAccountsLoading = false;
        });
      } else {
        setState(() => _bankAccountsLoading = false);
      }
    } catch (_) {
      setState(() => _bankAccountsLoading = false);
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _descCtrl.dispose();
    _otherAmountCtrl.dispose();
    _otherDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() => _txnsLoading = true);
    try {
      final res = await _service.getDepositableTransactions(
        accountId: widget.accountId,
        date: DateFormat('yyyy-MM-dd').format(_filterDate),
        receivedFrom: _filterReceivedFrom == 'All' ? null : _filterReceivedFrom,
        entityType: _filterEntityType == 'All' ? null : _filterEntityType,
      );
      setState(() {
        _availableTxns = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _txnsLoading = false;
      });
    } catch (e) {
      setState(() => _txnsLoading = false);
    }
  }

  double get _selectedTotal {
    double total = 0;
    for (final t in _availableTxns) {
      if (_selectedTxnIds.contains(t['_id']?.toString())) {
        total += (t['amount'] ?? 0).toDouble();
      }
    }
    for (final d in _otherDeposits) {
      total += (d['amount'] ?? 0).toDouble();
    }
    return total;
  }

  void _addOtherDeposit() {
    final amt = double.tryParse(_otherAmountCtrl.text.trim());
    final desc = _otherDescCtrl.text.trim();
    if (amt == null || amt <= 0) {
      _showError('Enter a valid amount');
      return;
    }
    setState(() {
      _otherDeposits.add({'amount': amt, 'description': desc});
      _otherAmountCtrl.clear();
      _otherDescCtrl.clear();
      _showOtherDepositForm = false;
    });
  }

  Future<void> _save() async {
    if (_selectedBankId == null) {
      _showError('Please select a bank account');
      return;
    }
    if (_selectedTxnIds.isEmpty && _otherDeposits.isEmpty) {
      _showError('Select at least one transaction or add an Other Deposit');
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await _service.recordDeposit(
        accountId: _selectedBankId!,
        depositDate: DateFormat('yyyy-MM-dd').format(_depositDate),
        paidVia: _paidVia,
        reference: _refCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        transactionIds: _selectedTxnIds.toList(),
        otherDeposits: _otherDeposits,
      );
      setState(() => _saving = false);
      if (res['success'] == true) {
        Navigator.pop(context);
        widget.onSaved?.call();
        _showSuccess('Deposit recorded successfully');
      } else {
        _showError(res['message'] ?? 'Failed to record deposit');
      }
    } catch (e) {
      setState(() => _saving = false);
      _showError('Failed: $e');
    }
  }

  // ==========================================================================
  //  BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isWide = screenW > 700;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 700 : screenW * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildHeader(),
          Flexible(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Top fields row
              isWide ? _buildTopFieldsWide() : _buildTopFieldsMobile(),
              const SizedBox(height: 16),
              isWide ? _buildMidFieldsWide() : _buildMidFieldsMobile(),
              const SizedBox(height: 24),
              _buildSelectTransactionsSection(),
              const SizedBox(height: 20),
              _buildOtherDepositsSection(),
              const SizedBox(height: 16),
              if (_selectedTotal > 0) _buildTotalRow(),
            ]),
          )),
          _buildFooter(),
        ]),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
        decoration: const BoxDecoration(
            color: Color(0xFF0D1B3E),
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16))),
        child: Row(children: [
          const Icon(Icons.savings_outlined, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Record Deposit',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text('To: ${widget.accountName}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white60)),
              ])),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ]),
      );

  Widget _buildTopFieldsWide() => Row(children: [
        Expanded(child: _bankAccountDropdown()),
        const SizedBox(width: 16),
        Expanded(child: _datePicker()),
      ]);

  Widget _buildTopFieldsMobile() => Column(children: [
        _bankAccountDropdown(),
        const SizedBox(height: 14),
        _datePicker(),
      ]);

  Widget _bankAccountDropdown() {
    if (_bankAccountsLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Loading accounts...', style: TextStyle(fontSize: 13)),
        ]),
      );
    }
    if (_bankAccounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.account_balance, color: Colors.grey[500]),
          const SizedBox(width: 12),
          Expanded(
              child: Text('No accounts found',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
          GestureDetector(
            onTap: _loadBankAccounts,
            child: Icon(Icons.refresh, color: Colors.red.shade400, size: 18),
          ),
        ]),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedBankId,
      decoration: InputDecoration(
        labelText: 'To Account *',
        prefixIcon: const Icon(Icons.account_balance),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      items: _bankAccounts
          .map((a) => DropdownMenuItem<String>(
                value: a['_id']?.toString(),
                child: Text(
                  '${a['accountName'] ?? ''} (${a['accountType'] ?? ''})',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: (v) => setState(() {
        _selectedBankId = v;
        _selectedBankName = _bankAccounts
            .firstWhere((a) => a['_id']?.toString() == v)['accountName']
            ?.toString();
      }),
    );
  }

  Widget _buildMidFieldsWide() => Row(children: [
        Expanded(child: _paidViaDropdown()),
        const SizedBox(width: 16),
        Expanded(
            child: TextFormField(
          controller: _refCtrl,
          decoration: _inputDeco('Reference#', Icons.tag_outlined),
        )),
      ]);

  Widget _buildMidFieldsMobile() => Column(children: [
        _paidViaDropdown(),
        const SizedBox(height: 14),
        TextFormField(
            controller: _refCtrl,
            decoration: _inputDeco('Reference#', Icons.tag_outlined)),
        const SizedBox(height: 14),
        TextFormField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: _inputDeco('Description', Icons.note_outlined)),
      ]);

  Widget _lockedField(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: _navy),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Text(value,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
          const Spacer(),
          Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
        ]),
      );

  Widget _datePicker() => InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _depositDate,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            builder: (c, child) => Theme(
              data: Theme.of(c).copyWith(
                  colorScheme: const ColorScheme.light(primary: _navy)),
              child: child!,
            ),
          );
          if (d != null) setState(() => _depositDate = d);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today, size: 18, color: _navy),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Deposit Date *',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              Text(DateFormat('dd/MM/yyyy').format(_depositDate),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: _navy)),
            ]),
            const Spacer(),
            Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
          ]),
        ),
      );

  Widget _paidViaDropdown() => DropdownButtonFormField<String>(
        value: _paidVia,
        decoration: _inputDeco('Paid Via', Icons.payment),
        hint: const Text('Choose payment mode'),
        items: _paymentModes
            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
            .toList(),
        onChanged: (v) => setState(() => _paidVia = v),
      );

  // ── Select Transactions section ──────────────────────────────────────────

  Widget _buildSelectTransactionsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Transactions',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50))),
          const SizedBox(height: 12),

          // Filters row
          Wrap(spacing: 8, runSpacing: 8, children: [
            // Currency — locked INR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50]),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('INR - Indian Rupee', style: TextStyle(fontSize: 12)),
              ]),
            ),

            // Date filter
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _filterDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  builder: (c, child) => Theme(
                    data: Theme.of(c).copyWith(
                        colorScheme: const ColorScheme.light(primary: _navy)),
                    child: child!,
                  ),
                );
                if (d != null) {
                  setState(() => _filterDate = d);
                  _loadTransactions();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_today, size: 14),
                  const SizedBox(width: 6),
                  Text(DateFormat('dd/MM/yyyy').format(_filterDate),
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),

            // Received From filter
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filterReceivedFrom,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  items: ['All', 'Customer', 'Vendor', 'Other']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _filterReceivedFrom = v!);
                    _loadTransactions();
                  },
                ),
              ),
            ),

            // Apply Filter button
            ElevatedButton(
              onPressed: _loadTransactions,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Apply Filter', style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 14),

          // Table
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(children: [
              // Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D1B3E),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10)),
                ),
                child: const Row(children: [
                  SizedBox(width: 32),
                  Expanded(
                      flex: 2,
                      child: Text('DATE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 2,
                      child: Text('TYPE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 3,
                      child: Text('DESCRIPTION',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 2,
                      child: Text('CUSTOMER',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold))),
                  Expanded(
                      flex: 2,
                      child: Text('AMOUNT',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.right)),
                ]),
              ),

              // Body
              if (_txnsLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: _navy, strokeWidth: 2)),
                )
              else if (_availableTxns.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text(
                    'No transactions available for the selected filters. Adjust the filters to view available transactions.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  )),
                )
              else
                ...(_availableTxns.asMap().entries.map((e) {
                  final txn = e.value;
                  final id = txn['_id']?.toString() ?? '';
                  final sel = _selectedTxnIds.contains(id);
                  final date = _parseDate(txn['date'] ??
                      txn['invoiceDate'] ??
                      txn['transactionDate']);
                  final amt =
                      (txn['amount'] ?? txn['balanceDue'] ?? txn['total'] ?? 0)
                          .toDouble();
                  return InkWell(
                    onTap: () => setState(() {
                      if (sel)
                        _selectedTxnIds.remove(id);
                      else
                        _selectedTxnIds.add(id);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel
                            ? _navy.withOpacity(0.05)
                            : (e.key.isEven
                                ? Colors.white
                                : const Color(0xFFFAFBFD)),
                        border: Border(
                            bottom: BorderSide(color: Colors.grey[100]!)),
                      ),
                      child: Row(children: [
                        Checkbox(
                          value: sel,
                          onChanged: (_) => setState(() {
                            if (sel)
                              _selectedTxnIds.remove(id);
                            else
                              _selectedTxnIds.add(id);
                          }),
                          activeColor: _navy,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                            flex: 2,
                            child: Text(DateFormat('dd/MM/yyyy').format(date),
                                style: const TextStyle(fontSize: 12))),
                        Expanded(
                            flex: 2,
                            child: Text(txn['type']?.toString() ?? 'Invoice',
                                style: const TextStyle(fontSize: 12))),
                        Expanded(
                            flex: 3,
                            child: Text(
                                txn['description']?.toString() ??
                                    txn['invoiceNumber']?.toString() ??
                                    '',
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        Expanded(
                            flex: 2,
                            child: Text(txn['customerName']?.toString() ?? '',
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        Expanded(
                            flex: 2,
                            child: Text('₹${_fmt(amt)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: sel ? _navy : Colors.black87),
                                textAlign: TextAlign.right)),
                      ]),
                    ),
                  );
                })),
            ]),
          ),
        ],
      );

  // ── Other Deposits section ───────────────────────────────────────────────

  Widget _buildOtherDepositsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Other Deposits',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50))),
            const SizedBox(width: 8),
            Text('Add deposits received from other sources manually.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const Spacer(),
            if (!_showOtherDepositForm)
              TextButton.icon(
                onPressed: () => setState(() => _showOtherDepositForm = true),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Other Deposits'),
                style: TextButton.styleFrom(foregroundColor: _navy),
              ),
          ]),
          if (_otherDeposits.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._otherDeposits.asMap().entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _green.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.add_circle_outline,
                        color: _green, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            e.value['description']?.toString().isNotEmpty ==
                                    true
                                ? e.value['description']
                                : 'Other Deposit',
                            style: const TextStyle(fontSize: 13))),
                    Text('₹${_fmt((e.value['amount'] ?? 0).toDouble())}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _green)),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () =>
                          setState(() => _otherDeposits.removeAt(e.key)),
                      child: const Icon(Icons.remove_circle_outline,
                          color: _red, size: 18),
                    ),
                  ]),
                )),
          ],
          if (_showOtherDepositForm) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _green.withOpacity(0.2)),
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: TextFormField(
                    controller: _otherAmountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'))
                    ],
                    decoration: _inputDeco('Amount *', Icons.currency_rupee),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: TextFormField(
                    controller: _otherDescCtrl,
                    decoration: _inputDeco('Description', Icons.note_outlined),
                  )),
                ]),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _showOtherDepositForm = false;
                      _otherAmountCtrl.clear();
                      _otherDescCtrl.clear();
                    }),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addOtherDeposit,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: const Text('Add'),
                  ),
                ]),
              ]),
            ),
          ],
        ],
      );

  Widget _buildTotalRow() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _navy.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _navy.withOpacity(0.15)),
        ),
        child: Row(children: [
          const Text('Total Deposit Amount',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(),
          Text('₹${_fmt(_selectedTotal)}',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _navy)),
        ]),
      );

  Widget _buildFooter() => Container(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FA),
          border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16)),
        ),
        child: Row(children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'Saving…' : 'Record Deposit',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ]),
      );

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
        isDense: true,
      );

  void _showError(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  String _fmt(double v) => NumberFormat('#,##0.00').format(v);
  DateTime _parseDate(dynamic d) {
    if (d == null) return DateTime.now();
    try {
      return DateTime.parse(d.toString());
    } catch (_) {
      return DateTime.now();
    }
  }
}
