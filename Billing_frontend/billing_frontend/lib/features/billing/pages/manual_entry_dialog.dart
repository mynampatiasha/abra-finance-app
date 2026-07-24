import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// MANUAL ENTRY DIALOG — Add Expense / Deposit / Transfer
// ============================================================================
// File: lib/screens/banking/manual_entry_dialog.dart
//
// COA Filtering (exactly like Zoho Books):
//   Expense  → Paid From = Bank/Cash/CC | Category = Expense COA accounts only
//   Deposit  → Deposited To = Bank/Cash | Category = Income COA accounts only
//   Transfer → From = pre-filled (locked) | To = other Bank/Cash accounts only
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/services/bank_transaction_service.dart';
import '../../../core/services/add_account_service.dart';

const Color _navy = Color(0xFF1e3a8a);
const Color _green = Color(0xFF27AE60);
const Color _blue = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red = Color(0xFFE74C3C);

class ManualEntryDialog extends StatefulWidget {
  final String accountId;
  final String accountName;
  final String initialType; // 'expense' | 'deposit' | 'transfer'
  final VoidCallback? onSaved;

  const ManualEntryDialog({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.initialType,
    this.onSaved,
  }) : super(key: key);

  @override
  State<ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<ManualEntryDialog> {
  final BankTransactionService _service = BankTransactionService();
  final _formKey = GlobalKey<FormState>();

  late String _type;
  bool _saving = false;
  bool _loading = true;

  // Form controllers
  final _amountCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _taxRateCtrl = TextEditingController(text: '0');
  DateTime _date = DateTime.now();

  // COA data
  List<COAOption> _expenseCOAs = [];
  List<COAOption> _incomeCOAs = [];
  List<Map<String, dynamic>> _otherAccounts = [];

  // Selected values
  COAOption? _selectedCOA;
  Map<String, dynamic>? _selectedToAccount;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _loadData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    _notesCtrl.dispose();
    _taxRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _service.getCOAOptions('expense'),
        _service.getCOAOptions('income'),
        AddAccountService().getAllAccounts(),
      ]);
      setState(() {
        _expenseCOAs = results[0] as List<COAOption>;
        _incomeCOAs = results[1] as List<COAOption>;
        final all = results[2] as List<dynamic>;
        _otherAccounts = all
            .where(
                (a) => a['_id'] != widget.accountId && (a['isActive'] ?? true))
            .map((a) => Map<String, dynamic>.from(a))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Color get _accentColor {
    switch (_type) {
      case 'expense':
        return _red;
      case 'deposit':
        return _green;
      case 'transfer':
        return _blue;
      default:
        return _navy;
    }
  }

  IconData get _accentIcon {
    switch (_type) {
      case 'expense':
        return Icons.arrow_upward;
      case 'deposit':
        return Icons.arrow_downward;
      case 'transfer':
        return Icons.compare_arrows;
      default:
        return Icons.add;
    }
  }

  String get _title {
    switch (_type) {
      case 'expense':
        return 'Add Expense';
      case 'deposit':
        return 'Add Deposit';
      case 'transfer':
        return 'Add Transfer';
      default:
        return 'Add Transaction';
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (c, child) => Theme(
        data: Theme.of(c)
            .copyWith(colorScheme: const ColorScheme.light(primary: _navy)),
        child: child!,
      ),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_type != 'transfer' && _selectedCOA == null) {
      _showError('Please select a category');
      return;
    }
    if (_type == 'transfer' && _selectedToAccount == null) {
      _showError('Please select destination account');
      return;
    }

    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountCtrl.text.replaceAll(',', ''));
      final taxRate = double.tryParse(_taxRateCtrl.text) ?? 0;
      final taxAmt = taxRate > 0 ? (amount * taxRate / 100) : null;

      final res = await _service.addManualEntry(
        accountId: widget.accountId,
        type: _type,
        date: DateFormat('yyyy-MM-dd').format(_date),
        amount: amount,
        coaAccountId: _type != 'transfer' ? _selectedCOA?.id : null,
        toAccountId: _type == 'transfer'
            ? (_selectedToAccount == null
                ? null
                : _selectedToAccount!['_id']?.toString())
            : null,
        vendorName:
            _vendorCtrl.text.trim().isEmpty ? null : _vendorCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        taxRate: taxRate > 0 ? taxRate : null,
        taxAmount: taxAmt,
      );

      if (!mounted) return;
      setState(() => _saving = false);

      if (res['success'] == true) {
        Navigator.pop(context);
        widget.onSaved?.call();
      } else {
        _showError(res['message'] ?? 'Failed to save');
      }
    } catch (e) {
      setState(() => _saving = false);
      _showError('Failed: $e');
    }
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 520,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildHeader(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: _navy),
            )
          else
            Flexible(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type switcher
                      _buildTypeSwitcher(),
                      const SizedBox(height: 20),

                      // Date
                      _buildDateField(),
                      const SizedBox(height: 14),

                      // Amount
                      _buildAmountField(),
                      const SizedBox(height: 14),

                      // Paid From (locked — always current account)
                      _buildLockedAccountField(
                        label: _type == 'expense'
                            ? 'Paid From'
                            : _type == 'deposit'
                                ? 'Deposited To'
                                : 'From Account',
                        value: widget.accountName,
                      ),
                      const SizedBox(height: 14),

                      // Category or To Account
                      if (_type == 'transfer') ...[
                        _buildToAccountDropdown(),
                      ] else ...[
                        _buildCategoryDropdown(),
                        const SizedBox(height: 14),
                        _buildVendorField(),
                        const SizedBox(height: 14),
                        _buildTaxField(),
                      ],
                      const SizedBox(height: 14),

                      // Notes
                      _buildNotesField(),
                      const SizedBox(height: 16),

                      // Journal entry preview
                      _buildJournalPreview(),
                    ],
                  )),
            )),
          _buildFooter(),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.06),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        border:
            Border(bottom: BorderSide(color: _accentColor.withOpacity(0.15))),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: _accentColor, borderRadius: BorderRadius.circular(12)),
          child: Icon(_accentIcon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Text(_title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50))),
        const Spacer(),
        IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
      ]),
    );
  }

  Widget _buildTypeSwitcher() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        _typeBtn('Expense', 'expense', _red),
        _typeBtn('Deposit', 'deposit', _green),
        _typeBtn('Transfer', 'transfer', _blue),
      ]),
    );
  }

  Widget _typeBtn(String label, String type, Color color) {
    final sel = _type == type;
    return Expanded(
        child: GestureDetector(
      onTap: () => setState(() {
        _type = type;
        _selectedCOA = null;
        _selectedToAccount = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: sel ? Colors.white : Colors.grey[600])),
      ),
    ));
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.calendar_today, size: 18, color: _navy),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Date',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500)),
            Text(DateFormat('dd MMM yyyy').format(_date),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: _navy)),
          ]),
          const Spacer(),
          Icon(Icons.arrow_drop_down, color: Colors.grey[400]),
        ]),
      ),
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
      ],
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: 'Amount *',
        prefixText: '₹ ',
        prefixStyle: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: _accentColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accentColor, width: 2),
        ),
        filled: true,
        fillColor: _accentColor.withOpacity(0.03),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Amount is required';
        if (double.tryParse(v) == null || double.parse(v) <= 0)
          return 'Enter a valid amount';
        return null;
      },
    );
  }

  Widget _buildLockedAccountField(
      {required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.account_balance, size: 18, color: _navy),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50))),
        ]),
        const Spacer(),
        Icon(Icons.lock_outline, size: 14, color: Colors.grey[400]),
      ]),
    );
  }

  Widget _buildCategoryDropdown() {
    final options = _type == 'expense' ? _expenseCOAs : _incomeCOAs;
    return DropdownButtonFormField<COAOption>(
      decoration: InputDecoration(
        labelText: _type == 'expense'
            ? 'Category (Expense Account) *'
            : 'Category (Income Account) *',
        prefixIcon: const Icon(Icons.account_tree_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accentColor, width: 2),
        ),
        helperText: _type == 'expense'
            ? 'Shows only expense accounts'
            : 'Shows only income accounts',
      ),
      isExpanded: true,
      value: _selectedCOA,
      items: options
          .map((c) => DropdownMenuItem(
                value: c,
                child: Text('${c.accountCode}  ${c.accountName}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      onChanged: (v) => setState(() => _selectedCOA = v),
      validator: (v) => v == null ? 'Please select a category' : null,
    );
  }

  Widget _buildToAccountDropdown() {
    return DropdownButtonFormField<Map<String, dynamic>>(
      decoration: InputDecoration(
        labelText: 'Transfer To Account *',
        prefixIcon: const Icon(Icons.account_balance_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _blue, width: 2),
        ),
        helperText: 'Shows only other bank/cash accounts',
      ),
      isExpanded: true,
      value: _selectedToAccount,
      items: _otherAccounts
          .map((a) => DropdownMenuItem(
                value: a,
                child: Text(a['accountName']?.toString() ?? '',
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) => setState(() => _selectedToAccount = v),
      validator: (v) => v == null ? 'Please select destination account' : null,
    );
  }

  Widget _buildVendorField() {
    return TextFormField(
      controller: _vendorCtrl,
      decoration: InputDecoration(
        labelText:
            _type == 'expense' ? 'Vendor (optional)' : 'Customer (optional)',
        prefixIcon: const Icon(Icons.person_outline),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildTaxField() {
    return TextFormField(
      controller: _taxRateCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Tax Rate % (optional)',
        prefixIcon: const Icon(Icons.percent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        helperText: 'e.g. 18 for 18% GST',
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesCtrl,
      maxLines: 2,
      decoration: InputDecoration(
        labelText: 'Notes (optional)',
        prefixIcon: const Icon(Icons.note_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildJournalPreview() {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) return const SizedBox.shrink();

    String dr = '', cr = '';
    if (_type == 'expense') {
      dr = _selectedCOA?.accountName ?? 'Expense Account';
      cr = widget.accountName;
    } else if (_type == 'deposit') {
      dr = widget.accountName;
      cr = _selectedCOA?.accountName ?? 'Income Account';
    } else {
      dr = _selectedToAccount?['accountName']?.toString() ?? 'To Account';
      cr = widget.accountName;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.receipt_long, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 6),
          Text('Journal Entry Preview',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600])),
        ]),
        const Divider(height: 12),
        _jeRow('Dr', dr, amount),
        const SizedBox(height: 4),
        _jeRow('Cr', cr, amount, indent: true),
      ]),
    );
  }

  Widget _jeRow(String side, String account, double amount,
      {bool indent = false}) {
    return Row(children: [
      SizedBox(width: indent ? 24 : 0),
      Container(
        width: 28,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color:
              side == 'Dr' ? _red.withOpacity(0.08) : _green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(side,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: side == 'Dr' ? _red : _green)),
      ),
      const SizedBox(width: 8),
      Expanded(
          child: Text(account,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      Text('₹${NumberFormat('#,##0.00').format(amount)}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: const Border(top: BorderSide(color: Color(0xFFEEF2F7))),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
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
              : Icon(_accentIcon, size: 18),
          label: Text(_saving ? 'Saving…' : _title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      ]),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }
}
