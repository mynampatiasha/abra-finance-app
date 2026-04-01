// ============================================================================
// NEW / EDIT CHART OF ACCOUNT SCREEN
// ============================================================================
// File: lib/screens/billing/pages/new_chart_of_account.dart
// Navy blue gradient theme | Fully responsive
// ============================================================================

import 'package:flutter/material.dart';
import '../../../../core/services/chart_of_account_service.dart';

const Color _navyDark  = Color(0xFF0F172A);
const Color _navyMid   = Color(0xFF1E3A5F);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent= Color(0xFF2563EB);

// ── Account Type / SubType Map ────────────────────────────────────────────────
const Map<String, List<String>> _kSubTypes = {
  'Asset': ['Cash', 'Bank', 'Stock', 'Other Current Asset', 'Fixed Asset', 'Other Asset', 'Accounts Receivable'],
  'Liability': ['Accounts Payable', 'Other Current Liability', 'Non Current Liability', 'Other Liability', 'Credit Card'],
  'Equity': ['Equity', 'Retained Earnings'],
  'Income': ['Income', 'Other Income'],
  'Expense': ['Expense', 'Cost Of Goods Sold', 'Other Expense'],
};

const List<String> _kAccountTypes = ['Asset', 'Liability', 'Equity', 'Income', 'Expense'];
const List<String> _kCurrencies   = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'AUD'];

// ============================================================================
class NewChartOfAccountScreen extends StatefulWidget {
  final String? accountId;
  const NewChartOfAccountScreen({Key? key, this.accountId}) : super(key: key);

  @override
  State<NewChartOfAccountScreen> createState() => _NewChartOfAccountScreenState();
}

class _NewChartOfAccountScreenState extends State<NewChartOfAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Controllers
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Values
  String  _accountType    = 'Asset';
  String  _accountSubType = 'Cash';
  String  _currency       = 'INR';
  bool    _isActive       = true;
  String? _parentAccountId;
  String? _parentAccountName;

  // Parent accounts list
  List<ChartOfAccount> _parentAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadParentAccounts();
    if (widget.accountId != null) _loadAccountData();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadParentAccounts() async {
    try {
      final accounts = await ChartOfAccountService.getParentAccounts();
      if (mounted) setState(() => _parentAccounts = accounts);
    } catch (_) {}
  }

  Future<void> _loadAccountData() async {
    setState(() => _isLoading = true);
    try {
      final acc = await ChartOfAccountService.getAccount(widget.accountId!);
      setState(() {
        _codeCtrl.text      = acc.accountCode;
        _nameCtrl.text      = acc.accountName;
        _descCtrl.text      = acc.description ?? '';
        _accountType        = acc.accountType;
        _accountSubType     = acc.accountSubType;
        _currency           = acc.currency;
        _isActive           = acc.isActive;
        _parentAccountId    = acc.parentAccountId;
        _parentAccountName  = acc.parentAccountName;
        _isLoading          = false;
      });
    } catch (e) {
      _showError('Failed to load account: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameCtrl.text.trim().isEmpty) { _showError('Account name is required'); return; }

    setState(() => _isSaving = true);
    try {
      final data = {
        'accountCode'   : _codeCtrl.text.trim(),
        'accountName'   : _nameCtrl.text.trim(),
        'accountType'   : _accountType,
        'accountSubType': _accountSubType,
        'description'   : _descCtrl.text.trim(),
        'currency'      : _currency,
        'isActive'      : _isActive,
        'parentAccountId': _parentAccountId,
      };

      ChartOfAccount acc;
      if (widget.accountId != null) {
        acc = await ChartOfAccountService.updateAccount(widget.accountId!, data);
      } else {
        acc = await ChartOfAccountService.createAccount(data);
      }

      _showSuccess('Account "${acc.accountName}" saved successfully');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(builder: (_, c) {
                  final isWide = c.maxWidth > 700;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildMainForm()),
                        const SizedBox(width: 20),
                        SizedBox(width: 280, child: _buildSidePanel()),
                      ],
                    );
                  }
                  return Column(children: [
                    _buildMainForm(),
                    const SizedBox(height: 20),
                    _buildSidePanel(),
                  ]);
                }),
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_navyDark, _navyMid, _navyLight],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(widget.accountId != null ? 'Edit Account' : 'New Account',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
            label: Text(_isSaving ? 'Saving…' : 'Save Account'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );

  // ── Main Form ─────────────────────────────────────────────────────────────

  Widget _buildMainForm() => Column(children: [
    _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Account Details', Icons.account_balance_wallet_outlined),
      const SizedBox(height: 20),

      // Account Name
      TextFormField(
        controller: _nameCtrl,
        decoration: _deco('Account Name *', Icons.label_outline, hint: 'e.g. Cash in Hand'),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Account name is required' : null,
      ),
      const SizedBox(height: 16),

      // Account Code
      TextFormField(
        controller: _codeCtrl,
        decoration: _deco('Account Code', Icons.tag, hint: 'e.g. 1001'),
      ),
      const SizedBox(height: 16),

      // Account Type + Sub Type
      LayoutBuilder(builder: (_, c) {
        final isWide = c.maxWidth > 500;
        final typeField = DropdownButtonFormField<String>(
          value: _accountType,
          decoration: _deco('Account Type *', Icons.category_outlined),
          items: _kAccountTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _accountType    = v;
                _accountSubType = _kSubTypes[v]?.first ?? v;
              });
            }
          },
          validator: (v) => (v == null || v.isEmpty) ? 'Account type is required' : null,
        );

        final subTypeField = DropdownButtonFormField<String>(
          value: (_kSubTypes[_accountType] ?? []).contains(_accountSubType)
              ? _accountSubType : (_kSubTypes[_accountType]?.first ?? ''),
          decoration: _deco('Account Sub Type *', Icons.subdirectory_arrow_right),
          items: (_kSubTypes[_accountType] ?? [_accountType])
              .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) { if (v != null) setState(() => _accountSubType = v); },
        );

        if (isWide) {
          return Row(children: [
            Expanded(child: typeField),
            const SizedBox(width: 16),
            Expanded(child: subTypeField),
          ]);
        }
        return Column(children: [typeField, const SizedBox(height: 16), subTypeField]);
      }),
      const SizedBox(height: 16),

      // Description
      TextFormField(
        controller: _descCtrl,
        decoration: _deco('Description', Icons.description_outlined,
            hint: 'Describe what this account is used for'),
        maxLines: 3,
      ),
    ])),

    const SizedBox(height: 16),

    // Parent Account
    _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Parent Account (Optional)', Icons.account_tree_outlined),
      const SizedBox(height: 16),
      Text('Making this a sub-account will place it under the selected parent account.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _parentAccountId,
        decoration: _deco('Parent Account', Icons.account_tree_outlined),
        isExpanded: true,
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('None (Top Level Account)')),
          ..._parentAccounts
              .where((a) => a.id != widget.accountId)
              .map((a) => DropdownMenuItem<String>(
                value: a.id,
                child: Text('${a.accountName} (${a.accountType})', overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: (v) {
          setState(() {
            _parentAccountId   = v;
            _parentAccountName = v == null ? null : _parentAccounts.firstWhere((a) => a.id == v).accountName;
          });
        },
      ),
    ])),
  ]);

  // ── Side Panel ────────────────────────────────────────────────────────────

  Widget _buildSidePanel() => Column(children: [
    _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Settings', Icons.settings_outlined),
      const SizedBox(height: 16),

      // Currency
      DropdownButtonFormField<String>(
        value: _currency,
        decoration: _deco('Currency', Icons.currency_rupee),
        items: _kCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (v) { if (v != null) setState(() => _currency = v); },
      ),
      const SizedBox(height: 16),

      // Active toggle
      SwitchListTile(
        title: const Text('Account Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(_isActive ? 'This account is active and can be used' : 'This account is inactive',
            style: const TextStyle(fontSize: 12)),
        value: _isActive,
        activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() => _isActive = v),
      ),
    ])),

    const SizedBox(height: 16),

    // Account Type Reference
    _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Account Type Guide', Icons.help_outline),
      const SizedBox(height: 12),
      ...[
        ['Asset', 'Things your business owns', Colors.blue],
        ['Liability', 'Things your business owes', Colors.red],
        ['Equity', 'Owner\'s stake in business', Colors.purple],
        ['Income', 'Money coming in', Colors.green],
        ['Expense', 'Money going out', Colors.orange],
      ].map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: item[2] as Color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item[0] as String,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: item[2] as Color)),
            Text(item[1] as String, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ])),
        ]),
      )),
    ])),

    const SizedBox(height: 16),

    // Save button
    SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save),
        label: Text(_isSaving ? 'Saving…' : 'Save Account'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _navyAccent, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isSaving ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close),
        label: const Text('Cancel'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _navyMid, side: const BorderSide(color: _navyMid),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
  ]);

  // ── Helpers ───────────────────────────────────────────────────────────────

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
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  InputDecoration _deco(String label, IconData icon, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, size: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );
}