// ============================================================================
// NEW RECURRING EXPENSE SCREEN
// ============================================================================
// File: lib/screens/billing/new_recurring_expense.dart
//
// UI matches new_payment_made.dart EXACTLY:
// ✅ Gradient AppBar (_navyDark → _navyMid → _navyLight)
// ✅ Gradient icon box section titles (_sectionTitle) inside _card
// ✅ Desktop (>800px): left main (flex 3) + right 320px white sidebar
// ✅ Mobile (≤800px): stacked column layout
// ✅ Sidebar: Automation + Tax Settings + Summary + Save/Cancel buttons
// ✅ Card: borderRadius 10, shadow offset (0,3), 0.05 opacity
// ✅ Gradient info box in summary
// ✅ Vendor selector dialog with navy styling
// ✅ Next Expense Date box with navy gradient style
//
// FUNCTIONALITY: fully preserved, zero changes to logic
// ✅ Save / Update recurring expense profile
// ✅ Vendor selector with search, add vendor, retry
// ✅ Profile info (name)
// ✅ Recurrence settings (repeat, start/end date, end condition)
// ✅ Expense details (account, paid through, billable, amount)
// ✅ Tax settings (tax rate, GST rate toggles)
// ✅ Notes section
// ✅ Edit mode via recurringExpenseId
// ✅ All RecurringExpenseService + BillingVendorsService + AddAccountService calls unchanged
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/recurring_expense_service.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../core/services/add_account_service.dart';
import '../../../../core/services/invoice_service.dart';
import '../../../../core/services/api_service.dart';
import 'new_vendor.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/config/api_config.dart';

// Navy gradient colors — exact match to new_payment_made.dart
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);

// ============================================================================
// SCREEN
// ============================================================================

class NewRecurringExpenseScreen extends StatefulWidget {
  final String? recurringExpenseId;

  const NewRecurringExpenseScreen({Key? key, this.recurringExpenseId})
      : super(key: key);

  @override
  State<NewRecurringExpenseScreen> createState() =>
      _NewRecurringExpenseScreenState();
}

class _NewRecurringExpenseScreenState
    extends State<NewRecurringExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Controllers — unchanged
  final _profileNameController  = TextEditingController();
  final _amountController       = TextEditingController();
  final _repeatEveryController  = TextEditingController(text: '1');
  final _notesController        = TextEditingController();

  // Vendor — unchanged
  String? _selectedVendorId;
  String? _selectedVendorName;
  String? _selectedVendorEmail;

  // Expense Details — unchanged
  String _expenseAccount = 'Office Supplies';
  String _paidThrough    = 'Cash';
  bool   _isBillable     = false;
  // ✅ ADD THESE:
String? _selectedCustomerId;
String? _selectedCustomerName;
String? _selectedCustomerEmail;

  // Accounts from API — unchanged
  List<Map<String, dynamic>> _accounts        = [];
  bool                       _loadingAccounts = false;

  // Tax Settings — unchanged
  double _taxRate   = 0;
  double _gstRate   = 18;
  bool   _enableTax = false;
  bool   _enableGST = false;

  // Recurrence Settings — unchanged
  String    _repeatUnit         = 'month';
  DateTime  _startDate          = DateTime.now();
  DateTime? _endDate;
  String    _endCondition       = 'never';
  int       _maxOccurrences     = 12;
  DateTime? _nextExpenseDate;

  // Automation Settings — unchanged
  String _expenseCreationMode = 'auto_create';

  // Calculations — unchanged
  double _subTotal    = 0;
  double _taxAmount   = 0;
  double _gstAmount   = 0;
  double _totalAmount = 0;

  // Dropdown options — unchanged
List<String> _expenseAccountOptions = [];
bool _loadingExpenseAccounts = false;

  final List<String> _repeatUnitOptions = ['day', 'week', 'month', 'year'];

  final Map<String, String> _repeatUnitLabels = {
    'day':   'Day(s)',
    'week':  'Week(s)',
    'month': 'Month(s)',
    'year':  'Year(s)',
  };

  // ============================================================================
  @override
  void initState() {
    super.initState();
    _calculateNextExpenseDate();
    _loadAccounts();
     _loadExpenseAccounts(); // ✅ ADD THIS
    if (widget.recurringExpenseId != null) _loadRecurringExpenseData();
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _amountController.dispose();
    _repeatEveryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ============================================================================
  // LOAD ACCOUNTS — unchanged
  // ============================================================================

  Future<void> _loadAccounts() async {
    setState(() => _loadingAccounts = true);
    try {
      final accountService = AddAccountService();
      final accounts = await accountService.getAllAccounts();
      setState(() {
        _accounts        = accounts;
        _loadingAccounts = false;
      });
      if (_accounts.isNotEmpty && _paidThrough == 'Cash') {
        setState(() =>
            _paidThrough = _accounts[0]['accountName'] ?? 'Cash');
      }
    } catch (e) {
      setState(() => _loadingAccounts = false);
    }
  }

Future<void> _loadExpenseAccounts() async {
  setState(() => _loadingExpenseAccounts = true);
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/finance/chart-of-accounts?accountType=Expense&limit=200');
    final resp = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    });

    if (resp.statusCode == 200) {
      final body     = json.decode(resp.body);
      final List accounts = (body['data']?['accounts'] as List? ?? []);

      final expenseNames = accounts
          .map<String>((acc) => acc['accountName'].toString())
          .toList();

      final defaults = [
        'Office Supplies', 'Fuel', 'Travel & Conveyance',
        'Advertising & Marketing', 'Meals & Entertainment',
        'Utilities', 'Rent', 'Professional Fees',
        'Insurance', 'Other Expenses',
      ];

      final combined = {...defaults, ...expenseNames}.toList()..sort();

      setState(() {
        _expenseAccountOptions  = combined;
        _loadingExpenseAccounts = false;
        if (!_expenseAccountOptions.contains(_expenseAccount)) {
          _expenseAccount = _expenseAccountOptions.isNotEmpty
              ? _expenseAccountOptions.first
              : 'Office Supplies';
        }
      });
    } else {
      throw Exception('Failed: ${resp.statusCode}');
    }
  } catch (e) {
    setState(() {
      _expenseAccountOptions = [
        'Office Supplies', 'Fuel', 'Travel & Conveyance',
        'Advertising & Marketing', 'Meals & Entertainment',
        'Utilities', 'Rent', 'Professional Fees',
        'Insurance', 'Other Expenses',
      ];
      _loadingExpenseAccounts = false;
    });
  }
}

  // ============================================================================
  // CALCULATE NEXT EXPENSE DATE — unchanged
  // ============================================================================

  void _calculateNextExpenseDate() {
    final repeatEvery = int.tryParse(_repeatEveryController.text) ?? 1;
    DateTime nextDate = _startDate;
    switch (_repeatUnit) {
      case 'day':
        nextDate = _startDate.add(Duration(days: repeatEvery));
        break;
      case 'week':
        nextDate = _startDate.add(Duration(days: repeatEvery * 7));
        break;
      case 'month':
        nextDate = DateTime(_startDate.year,
            _startDate.month + repeatEvery, _startDate.day);
        break;
      case 'year':
        nextDate = DateTime(_startDate.year + repeatEvery,
            _startDate.month, _startDate.day);
        break;
    }
    setState(() => _nextExpenseDate = nextDate);
  }

  // ============================================================================
  // CALCULATE AMOUNTS — unchanged
  // ============================================================================

  void _calculateAmounts() {
    setState(() {
      _subTotal   = double.tryParse(_amountController.text) ?? 0;
      _taxAmount  = _enableTax ? (_subTotal * _taxRate / 100) : 0;
      double gstBase = _subTotal + _taxAmount;
      _gstAmount  = _enableGST ? (gstBase * _gstRate / 100) : 0;
      _totalAmount = _subTotal + _taxAmount + _gstAmount;
    });
  }

  // ============================================================================
  // LOAD EXISTING — unchanged
  // ============================================================================

  Future<void> _loadRecurringExpenseData() async {
    setState(() => _isLoading = true);
    try {
      final expense = await RecurringExpenseService.getRecurringExpense(
          widget.recurringExpenseId!);
      if (expense != null) {
        setState(() {
          _profileNameController.text    = expense.profileName;
          _selectedVendorId              = expense.vendorId;
          _selectedVendorName            = expense.vendorName;
          _expenseAccount                = expense.expenseAccount;
          _paidThrough                   = expense.paidThrough;
          _amountController.text         = expense.amount.toString();
          _isBillable                    = expense.isBillable ?? false;
          _taxRate                       = expense.tax;
          _enableTax                     = expense.tax > 0;
          _gstRate                       = expense.gstRate ?? 18;
          _enableGST                     = (expense.gstRate ?? 0) > 0;
          _repeatEveryController.text    = expense.repeatEvery.toString();
          _repeatUnit                    = expense.repeatUnit;
          _startDate                     = expense.startDate;
          _endDate                       = expense.endDate;
          _maxOccurrences                = expense.maxOccurrences ?? 12;
          if (_endDate != null) {
            _endCondition = 'on_date';
          } else if (expense.maxOccurrences != null) {
            _endCondition = 'after';
          } else {
            _endCondition = 'never';
          }
          _expenseCreationMode           = expense.expenseCreationMode;
          _notesController.text          = expense.notes ?? '';
          _calculateAmounts();
          _calculateNextExpenseDate();
        });
      }
    } catch (e) {
      _showErrorSnackbar('Failed to load recurring expense: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================================
  // SAVE — unchanged
  // ============================================================================

  Future<void> _saveRecurringExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) {
      _showErrorSnackbar('Please select a vendor'); return;
    }
    if (_profileNameController.text.trim().isEmpty) {
      _showErrorSnackbar('Please enter a profile name'); return;
    }
    if (_amountController.text.trim().isEmpty ||
        (double.tryParse(_amountController.text) ?? 0) <= 0) {
      _showErrorSnackbar('Please enter a valid amount'); return;
    }
    setState(() => _isSaving = true);
    try {
      final expenseData = _buildRecurringExpenseData();
      bool success;
      if (widget.recurringExpenseId != null) {
        success = await RecurringExpenseService.updateRecurringExpense(
            widget.recurringExpenseId!, expenseData);
        _showSuccessSnackbar(
            'Recurring expense profile updated successfully');
      } else {
        success = await RecurringExpenseService.createRecurringExpense(
            expenseData);
        _showSuccessSnackbar(
            'Recurring expense profile created successfully');
      }
      if (success) Navigator.pop(context, true);
      else _showErrorSnackbar('Failed to save recurring expense');
    } catch (e) {
      _showErrorSnackbar('Error: ${e.toString()}');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ============================================================================
  // BUILD REQUEST BODY — unchanged
  // ============================================================================

  Map<String, dynamic> _buildRecurringExpenseData() {
    DateTime? finalEndDate;
    int? maxOccurrences;
    if (_endCondition == 'on_date' && _endDate != null) {
      finalEndDate = _endDate;
    } else if (_endCondition == 'after') {
      maxOccurrences = _maxOccurrences;
    }
    return {
      'profileName':          _profileNameController.text.trim(),
      'vendorId':             _selectedVendorId,
      'vendorName':           _selectedVendorName,
      'expenseAccount':       _expenseAccount,
      'paidThrough':          _paidThrough,
      'amount':               double.tryParse(_amountController.text) ?? 0,
      'isBillable':           _isBillable,
      'customerName':         _selectedCustomerName,
'customerId':           _selectedCustomerId,
      'tax':                  _enableTax ? _taxRate : 0,
      'gstRate':              _enableGST ? _gstRate : 0,
      'repeatEvery':          int.tryParse(_repeatEveryController.text) ?? 1,
      'repeatUnit':           _repeatUnit,
      'startDate':            _startDate.toIso8601String(),
      'endDate':              finalEndDate?.toIso8601String(),
      'maxOccurrences':       maxOccurrences,
      'nextExpenseDate':      _nextExpenseDate?.toIso8601String(),
      'expenseCreationMode':  _expenseCreationMode,
      'notes':                _notesController.text.trim(),
      'status':               'ACTIVE',
    };
  }

  // ============================================================================
  // SNACKBARS — unchanged
  // ============================================================================

  void _showErrorSnackbar(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));

  void _showSuccessSnackbar(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
      ));

  // ============================================================================
  // ACCOUNT ICON HELPER — unchanged
  // ============================================================================

  IconData _getAccountIcon(String accountType) {
    switch (accountType.toLowerCase()) {
      case 'bank':        return Icons.account_balance;
      case 'cash':        return Icons.money;
      case 'credit card': return Icons.credit_card;
      case 'upi':         return Icons.phone_android;
      case 'petty cash':  return Icons.account_balance_wallet;
      default:            return Icons.account_balance_wallet;
    }
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
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
          : Form(
              key: _formKey,
              child: LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildMainContent()),
                      Container(
                        width: 320,
                        color: Colors.white,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            _buildAutomationSettingsSection(),
                            const Divider(height: 28),
                            _buildTaxSettingsSection(),
                            const Divider(height: 28),
                            _buildSummarySection(),
                          ]),
                        ),
                      ),
                    ],
                  );
                } else {
                  return SingleChildScrollView(
                    child: Column(children: [
                      _buildMainContent(),
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          _buildAutomationSettingsSection(),
                          const Divider(height: 28),
                          _buildTaxSettingsSection(),
                          const Divider(height: 28),
                          _buildSummarySection(),
                        ]),
                      ),
                    ]),
                  );
                }
              }),
            ),
    );
  }

  // ── AppBar — gradient, exact match to new_payment_made.dart ──────────────────

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
          widget.recurringExpenseId != null
              ? 'Edit Recurring Expense' : 'New Recurring Expense',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            label: const Text('Cancel',
                style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveRecurringExpense,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );

  // ── Main scrollable content ───────────────────────────────────────────────────

  Widget _buildMainContent() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildProfileInfoSection(),
      const SizedBox(height: 20),
      _buildVendorSection(),
      const SizedBox(height: 20),
      _buildRecurrenceSettingsSection(),
      const SizedBox(height: 20),
      _buildExpenseDetailsSection(),
      const SizedBox(height: 20),
      _buildNotesSection(),
      const SizedBox(height: 20),
    ]),
  );

  // ============================================================================
  // PROFILE INFO SECTION
  // ============================================================================

  Widget _buildProfileInfoSection() => _card(
    title: 'Recurring Expense Profile',
    icon: Icons.repeat,
    child: TextFormField(
      controller: _profileNameController,
      decoration: InputDecoration(
        labelText: 'Profile Name *',
        hintText: 'e.g., Monthly Office Rent - Vendor Name',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        prefixIcon: const Icon(Icons.label),
        helperText:
            'A unique name to identify this recurring expense profile',
      ),
      validator: (v) => (v == null || v.trim().isEmpty)
          ? 'Profile name is required' : null,
    ),
  );

  // ============================================================================
  // VENDOR SECTION
  // ============================================================================

  Widget _buildVendorSection() => _card(
    title: 'Vendor Information',
    icon: Icons.business_outlined,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: _showVendorSelector,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: _selectedVendorId == null
                ? Colors.red.shade300 : Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.business_outlined, color: _navyAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _selectedVendorName ?? 'Select Vendor *',
              style: TextStyle(
                fontSize: 15,
                color: _selectedVendorName != null
                    ? _navyDark : Colors.grey[600],
                fontWeight: _selectedVendorName != null
                    ? FontWeight.w600 : FontWeight.normal,
              ),
            )),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ]),
        ),
      ),
      if (_selectedVendorEmail != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(_selectedVendorEmail!,
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ]),
      ],
    ]),
  );

  // ============================================================================
  // RECURRENCE SETTINGS SECTION
  // ============================================================================

  Widget _buildRecurrenceSettingsSection() => _card(
    title: 'Recurrence Settings',
    icon: Icons.autorenew,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Repeat Every
      Row(children: [
        Expanded(flex: 2, child: TextFormField(
          controller: _repeatEveryController,
          decoration: InputDecoration(
            labelText: 'Repeat Every *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.repeat_one),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            final n = int.tryParse(v);
            if (n == null || n <= 0) return 'Must be > 0';
            return null;
          },
          onChanged: (_) => _calculateNextExpenseDate(),
        )),
        const SizedBox(width: 16),
        Expanded(flex: 3, child: DropdownButtonFormField<String>(
          value: _repeatUnit,
          decoration: InputDecoration(
            labelText: 'Time Period *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.calendar_today),
          ),
          items: _repeatUnitOptions.map((u) => DropdownMenuItem(
            value: u,
            child: Text(_repeatUnitLabels[u]!),
          )).toList(),
          onChanged: (v) => setState(() {
            _repeatUnit = v!;
            _calculateNextExpenseDate();
          }),
        )),
      ]),

      const SizedBox(height: 16),

      // Start Date
      InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _startDate,
            firstDate: DateTime.now(),
            lastDate: DateTime(2030),
          );
          if (date != null) setState(() {
            _startDate = date;
            _calculateNextExpenseDate();
          });
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Start Date *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.event),
          ),
          child: Text(DateFormat('dd MMM yyyy').format(_startDate),
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ),

      const SizedBox(height: 20),

      // End Condition
      Text('End Condition',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
              color: Colors.grey[600])),
      const SizedBox(height: 12),

      RadioListTile<String>(
        title: const Text('Never - Continues indefinitely'),
        value: 'never',
        groupValue: _endCondition,
        activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() => _endCondition = v!),
      ),

      RadioListTile<String>(
        title: Row(children: [
          const Text('After '),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextFormField(
            initialValue: _maxOccurrences.toString(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            enabled: _endCondition == 'after',
            onChanged: (v) => _maxOccurrences = int.tryParse(v) ?? 12,
          )),
          const SizedBox(width: 8),
          const Text('occurrences'),
        ]),
        value: 'after',
        groupValue: _endCondition,
        activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() => _endCondition = v!),
      ),

      RadioListTile<String>(
        title: const Text('On a specific date'),
        value: 'on_date',
        groupValue: _endCondition,
        activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() => _endCondition = v!),
      ),

      if (_endCondition == 'on_date') ...[
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _endDate ??
                    _startDate.add(const Duration(days: 365)),
                firstDate: _startDate,
                lastDate: DateTime(2030),
              );
              if (date != null) setState(() => _endDate = date);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'End Date',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.event_busy),
              ),
              child: Text(
                _endDate != null
                    ? DateFormat('dd MMM yyyy').format(_endDate!)
                    : 'Select end date',
                style: TextStyle(
                  color: _endDate != null ? _navyDark : Colors.grey[600],
                  fontWeight: _endDate != null
                      ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ],

      const SizedBox(height: 20),

      // Next Expense Date — gradient info box, matches pattern
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark.withOpacity(0.08),
                _navyLight.withOpacity(0.06)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _navyAccent.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_navyDark, _navyLight]),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.event_available,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Next Expense Date',
                  style: TextStyle(fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                _nextExpenseDate != null
                    ? DateFormat('EEEE, dd MMMM yyyy')
                        .format(_nextExpenseDate!)
                    : 'Not calculated',
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.bold, color: _navyDark),
              ),
            ],
          )),
        ]),
      ),
    ]),
  );

  // ============================================================================
  // EXPENSE DETAILS SECTION
  // ============================================================================

  Widget _buildExpenseDetailsSection() => _card(
    title: 'Expense Template Details',
    icon: Icons.receipt_outlined,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Expense Account + Paid Through
      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
final accountField = Expanded(
  child: _loadingExpenseAccounts
      ? Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(children: [
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_navyAccent))),
            SizedBox(width: 12),
            Text('Loading accounts...'),
          ]),
        )
      : DropdownButtonFormField<String>(
          value: _expenseAccountOptions.contains(_expenseAccount)
              ? _expenseAccount
              : (_expenseAccountOptions.isNotEmpty
                  ? _expenseAccountOptions.first : null),
          decoration: InputDecoration(
            labelText: 'Expense Account *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.category),
          ),
          items: _expenseAccountOptions.map((a) =>
              DropdownMenuItem(value: a, child: Text(a))).toList(),
          onChanged: (v) => setState(() => _expenseAccount = v!),
        ),
);

        final paidField = Expanded(
          child: _loadingAccounts
              ? Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                _navyAccent))),
                    SizedBox(width: 12),
                    Text('Loading accounts...'),
                  ]),
                )
              : DropdownButtonFormField<String>(
                  value: _accounts.any(
                          (acc) => acc['accountName'] == _paidThrough)
                      ? _paidThrough
                      : (_accounts.isNotEmpty
                          ? _accounts[0]['accountName'] : 'Cash'),
                  decoration: InputDecoration(
                    labelText: 'Paid Through *',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.account_balance_wallet),
                  ),
                  items: _accounts.isNotEmpty
                      ? _accounts.map((account) {
                          final name = account['accountName'] ?? 'Unknown';
                          final type = account['accountType'] ?? '';
                          return DropdownMenuItem<String>(
                            value: name,
                            child: Row(children: [
                              Icon(_getAccountIcon(type),
                                  size: 18, color: Colors.grey[600]),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name)),
                            ]),
                          );
                        }).toList()
                      : [
                          const DropdownMenuItem(
                              value: 'Cash', child: Text('Cash')),
                          const DropdownMenuItem(
                              value: 'Bank', child: Text('Bank')),
                        ],
                  onChanged: (v) => setState(() => _paidThrough = v!),
                ),
        );

        return isWide
            ? Row(children: [
                accountField,
                const SizedBox(width: 16),
                paidField,
              ])
            : Column(children: [
                accountField,
                const SizedBox(height: 16),
                paidField,
              ]);
      }),

      const SizedBox(height: 16),

      // Billable Toggle
// Billable Toggle
Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.grey[50],
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.grey[200]!),
  ),
  child: Row(children: [
    Icon(Icons.attach_money, color: Colors.grey[700], size: 20),
    const SizedBox(width: 12),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Billable',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text('Mark if this expense can be billed to a client',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    )),
    Switch(
      value: _isBillable,
      onChanged: (v) => setState(() {
        _isBillable = v;
        if (!v) {
          _selectedCustomerId    = null;
          _selectedCustomerName  = null;
          _selectedCustomerEmail = null;
        }
      }),
      activeColor: _navyAccent,
    ),
  ]),
),

// ✅ Customer selector when billable is ON
if (_isBillable) ...[
  const SizedBox(height: 12),
  InkWell(
    onTap: _showCustomerSelector,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: _selectedCustomerName == null
              ? Colors.red.shade300 : Colors.grey[300]!,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.person_outline, color: _navyAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _selectedCustomerName ?? 'Select Customer *',
            style: TextStyle(
              fontSize: 15,
              color: _selectedCustomerName != null
                  ? _navyDark : Colors.grey[600],
              fontWeight: _selectedCustomerName != null
                  ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        const Icon(Icons.arrow_drop_down, color: Colors.grey),
      ]),
    ),
  ),
  if (_selectedCustomerEmail != null) ...[
    const SizedBox(height: 6),
    Row(children: [
      const Icon(Icons.email_outlined, size: 14, color: Colors.grey),
      const SizedBox(width: 6),
      Text(_selectedCustomerEmail!,
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]),
  ],
  if (_selectedCustomerName == null) ...[
    const SizedBox(height: 4),
    Text('Customer required when billable',
        style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
  ],
],

const SizedBox(height: 16),

// Amount


      // Amount
      TextFormField(
        controller: _amountController,
        decoration: InputDecoration(
          labelText: 'Amount (₹) *',
          hintText: '0.00',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.currency_rupee),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Amount is required';
          final a = double.tryParse(v);
          if (a == null || a <= 0) return 'Please enter a valid amount';
          return null;
        },
        onChanged: (_) => _calculateAmounts(),
      ),
    ]),
  );

  // ============================================================================
  // NOTES SECTION
  // ============================================================================

  Widget _buildNotesSection() => _card(
    title: 'Additional Information',
    icon: Icons.note_alt,
    child: TextFormField(
      controller: _notesController,
      decoration: InputDecoration(
        labelText: 'Notes',
        hintText: 'Notes visible on every expense',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        alignLabelWithHint: true,
      ),
      maxLines: 4,
    ),
  );

  // ============================================================================
  // AUTOMATION SETTINGS SECTION (sidebar)
  // ============================================================================

  Widget _buildAutomationSettingsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Automation Settings', Icons.auto_mode),
      const SizedBox(height: 16),

      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('When expense is generated:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                  color: Colors.grey[600])),
          const SizedBox(height: 12),

          RadioListTile<String>(
            title: const Text('Auto-Create & Record'),
            subtitle: const Text('Automatically records expense',
                style: TextStyle(fontSize: 11)),
            value: 'auto_create',
            groupValue: _expenseCreationMode,
            activeColor: _navyAccent,
            contentPadding: EdgeInsets.zero,
            dense: true,
            onChanged: (v) => setState(() => _expenseCreationMode = v!),
          ),

          RadioListTile<String>(
            title: const Text('Save as Draft'),
            subtitle: const Text('Requires manual review before recording',
                style: TextStyle(fontSize: 11)),
            value: 'draft',
            groupValue: _expenseCreationMode,
            activeColor: _navyAccent,
            contentPadding: EdgeInsets.zero,
            dense: true,
            onChanged: (v) => setState(() => _expenseCreationMode = v!),
          ),
        ]),
      ),
    ],
  );

  // ============================================================================
  // TAX SETTINGS SECTION (sidebar) — exact match to new_payment_made.dart
  // ============================================================================

  Widget _buildTaxSettingsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Tax Settings', Icons.calculate),
      const SizedBox(height: 16),

      // General Tax
      SwitchListTile(
        title: const Text('Enable Tax'),
        subtitle: const Text('General tax rate',
            style: TextStyle(fontSize: 11)),
        value: _enableTax,
        activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() { _enableTax = v; _calculateAmounts(); }),
      ),
      if (_enableTax) ...[
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _taxRate.toString(),
          decoration: InputDecoration(
            labelText: 'Tax Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() {
            _taxRate = double.tryParse(v) ?? 0;
            _calculateAmounts();
          }),
        ),
      ],

      const SizedBox(height: 12),

      // GST
      SwitchListTile(
        title: const Text('Enable GST'),
        value: _enableGST,
        activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() { _enableGST = v; _calculateAmounts(); }),
      ),
      if (_enableGST) ...[
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _gstRate.toString(),
          decoration: InputDecoration(
            labelText: 'GST Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() {
            _gstRate = double.tryParse(v) ?? 18;
            _calculateAmounts();
          }),
        ),
      ],
    ],
  );

  // ============================================================================
  // SUMMARY SECTION (sidebar) — exact match to new_payment_made.dart
  // ============================================================================

  Widget _buildSummarySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Expense Preview', Icons.summarize),
      const SizedBox(height: 4),
      Text('This is how each expense will be calculated',
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      const SizedBox(height: 16),

      _summaryRow('Amount', _subTotal),
      if (_enableTax && _taxAmount > 0) ...[
        const SizedBox(height: 6),
        _summaryRow('Tax (${_taxRate.toStringAsFixed(1)}%)', _taxAmount),
      ],
      if (_enableGST && _gstAmount > 0) ...[
        const SizedBox(height: 6),
        _summaryRow('CGST (${(_gstRate / 2).toStringAsFixed(1)}%)',
            _gstAmount / 2),
        const SizedBox(height: 6),
        _summaryRow('SGST (${(_gstRate / 2).toStringAsFixed(1)}%)',
            _gstAmount / 2),
      ],
      const Divider(thickness: 2, height: 24),
      _summaryRow('Total Amount', _totalAmount, isBold: true, isTotal: true),

      const SizedBox(height: 16),

      // Gradient info box — exact match to new_payment_made.dart
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark.withOpacity(0.1),
                _navyLight.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _navyAccent.withOpacity(0.3)),
        ),
        child: Column(children: [
          _infoRow('Expense Account:', _expenseAccount),
          const SizedBox(height: 4),
          _infoRow('Payment Method:', _paidThrough),
          const SizedBox(height: 4),
          _infoRow('Mode:',
              _expenseCreationMode == 'auto_create'
                  ? 'Auto-Create' : 'Save as Draft'),
          if (_selectedVendorName != null) ...[
            const SizedBox(height: 4),
            _infoRow('Vendor:', _selectedVendorName!),
          ],
        ]),
      ),

      const SizedBox(height: 16),

      // Orange info note — kept as-is (informational only)
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: Colors.orange[700], size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'This profile will automatically generate expenses based on your recurrence settings.',
            style: TextStyle(fontSize: 11, color: Colors.orange[900]),
          )),
        ]),
      ),

      const SizedBox(height: 20),

      // Save Profile
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveRecurringExpense,
          icon: _isSaving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(_isSaving ? 'Saving...'
              : widget.recurringExpenseId != null
                  ? 'Update Profile' : 'Save Recurring Profile'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),

      const SizedBox(height: 10),

      // Cancel
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid,
            side: BorderSide(color: _navyMid),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ],
  );

  Widget _summaryRow(String label, double amount,
      {Color? color, bool isBold = false, bool isTotal = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(
          fontSize: isTotal ? 15 : 13,
          fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isTotal ? _navyDark : Colors.grey[700]),
        )),
        Text('₹${amount.toStringAsFixed(2)}', style: TextStyle(
          fontSize: isTotal ? 17 : 13,
          fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.w500,
          color: color ?? (isTotal ? _navyAccent : _navyDark),
        )),
      ]);


Future<void> _showCustomerSelector() async {
  final searchCtrl = TextEditingController();
  List<BillingCustomer> customers         = [];
  List<BillingCustomer> filteredCustomers = [];
  bool isLoading      = true;
  String? errorMessage;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        if (isLoading && customers.isEmpty) {
          InvoiceService.getBillingCustomers().then((response) {
            setDialogState(() {
              customers         = response.customers;
              filteredCustomers = customers;
              isLoading         = false;
            });
          }).catchError((error) {
            setDialogState(() {
              errorMessage = error.toString();
              isLoading    = false;
            });
          });
        }

        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.person_outline, color: _navyAccent),
            const SizedBox(width: 12),
            const Text('Select Customer'),
          ]),
          content: SizedBox(
            width: 500, height: 400,
            child: Column(children: [
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setDialogState(() {
                  filteredCustomers = v.isEmpty
                      ? customers
                      : customers.where((c) =>
                          c.customerName.toLowerCase()
                              .contains(v.toLowerCase()) ||
                          c.customerEmail.toLowerCase()
                              .contains(v.toLowerCase()))
                      .toList();
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _navyAccent)))
                    : errorMessage != null
                        ? Center(child: Text('Error: $errorMessage'))
                        : filteredCustomers.isEmpty
                            ? const Center(
                                child: Text('No customers found'))
                            : ListView.builder(
                                itemCount: filteredCustomers.length,
                                itemBuilder: (context, index) {
                                  final customer =
                                      filteredCustomers[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _navyAccent,
                                      child: Text(
                                        customer.customerName[0]
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                    title: Text(customer.customerName),
                                    subtitle:
                                        Text(customer.customerEmail),
                                    onTap: () {
                                      setState(() {
                                        _selectedCustomerId =
                                            customer.id;
                                        _selectedCustomerName =
                                            customer.customerName;
                                        _selectedCustomerEmail =
                                            customer.customerEmail;
                                      });
                                      Navigator.pop(context);
                                    },
                                  );
                                },
                              ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    ),
  );
}

  // ============================================================================
  // VENDOR SELECTOR — functionality unchanged, styling updated
  // ============================================================================

  Future<void> _showVendorSelector() async {
    final searchCtrl = TextEditingController();
    List<BillingVendor> vendors         = [];
    List<BillingVendor> filteredVendors = [];
    bool    isLoading    = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (isLoading && vendors.isEmpty) {
            BillingVendorsService.getVendors().then((response) {
              setS(() {
                vendors         = response;
                filteredVendors = vendors;
                isLoading       = false;
              });
            }).catchError((error) {
              setS(() {
                errorMessage = error.toString();
                isLoading    = false;
              });
            });
          }

          return AlertDialog(
            title: Row(children: [
              const Icon(Icons.business_outlined, color: _navyAccent),
              const SizedBox(width: 12),
              const Text('Select Vendor'),
            ]),
            content: SizedBox(width: 500, height: 500, child: Column(children: [
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search vendors by name, email, or company...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                onChanged: (v) => setS(() {
                  filteredVendors = v.isEmpty
                      ? vendors
                      : vendors.where((vendor) {
                          final s = v.toLowerCase();
                          return vendor.vendorName.toLowerCase().contains(s) ||
                              vendor.email.toLowerCase().contains(s) ||
                              (vendor.companyName?.toLowerCase()
                                      .contains(s) ??
                                  false);
                        }).toList();
                }),
              ),
              const SizedBox(height: 12),

              // Vendor count badge
              if (!isLoading)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_navyDark.withOpacity(0.08),
                          _navyLight.withOpacity(0.06)],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _navyAccent.withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: _navyAccent),
                    const SizedBox(width: 6),
                    Text('${filteredVendors.length} vendor(s) found',
                        style: const TextStyle(
                            color: _navyAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),

              const SizedBox(height: 12),

              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _navyAccent)))
                    : errorMessage != null
                        ? Center(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: Colors.red[400]),
                              const SizedBox(height: 16),
                              Text('Error loading vendors',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red[700])),
                              const SizedBox(height: 8),
                              Text(errorMessage!,
                                  style: TextStyle(color: Colors.grey[600]),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => setS(() {
                                  isLoading    = true;
                                  errorMessage = null;
                                }),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _navyAccent,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ))
                        : filteredVendors.isEmpty
                            ? Center(child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.business_outlined,
                                      size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    searchCtrl.text.isEmpty
                                        ? 'No vendors found'
                                        : 'No vendors match your search',
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16),
                                  ),
                                  if (searchCtrl.text.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('Try a different search term',
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 14)),
                                  ],
                                ],
                              ))
                            : ListView.separated(
                                itemCount: filteredVendors.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final vendor = filteredVendors[i];
                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: _navyAccent,
                                      child: Text(
                                        vendor.vendorName[0].toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(vendor.vendorName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15)),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          const Icon(Icons.email,
                                              size: 14, color: Colors.grey),
                                          const SizedBox(width: 6),
                                          Expanded(child: Text(vendor.email,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[700]))),
                                        ]),
                                        if (vendor.companyName != null &&
                                            vendor.companyName!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Row(children: [
                                            const Icon(Icons.business,
                                                size: 14,
                                                color: Colors.grey),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(
                                                vendor.companyName!,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey[600],
                                                    fontStyle:
                                                        FontStyle.italic))),
                                          ]),
                                        ],
                                        const SizedBox(height: 2),
                                        Row(children: [
                                          const Icon(Icons.phone,
                                              size: 14, color: Colors.grey),
                                          const SizedBox(width: 6),
                                          Text(vendor.phoneNumber,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[700])),
                                        ]),
                                        if (vendor.vendorType != null) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  _navyDark.withOpacity(0.1),
                                                  _navyLight.withOpacity(0.08),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: _navyAccent
                                                      .withOpacity(0.3)),
                                            ),
                                            child: Text(vendor.vendorType!,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: _navyAccent,
                                                    fontWeight:
                                                        FontWeight.w500)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    trailing: Icon(Icons.arrow_forward_ios,
                                        size: 16, color: Colors.grey[400]),
                                    onTap: () {
                                      setState(() {
                                        _selectedVendorId    = vendor.id;
                                        _selectedVendorName  = vendor.vendorName;
                                        _selectedVendorEmail = vendor.email;
                                      });
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
                              ),
              ),
            ])),
            actions: [
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NewVendorPage()),
                  );
                  if (result == true) _showVendorSelector();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Vendor'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navyAccent,
                  side: const BorderSide(color: _navyAccent),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================================
  // HELPERS — exact match to new_payment_made.dart
  // ============================================================================

  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(title, icon),
            const SizedBox(height: 16),
            child,
          ],
        ),
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
    Text(title, style: const TextStyle(
        fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  Widget _infoRow(String label, String value) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        Flexible(child: Text(value,
            style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.bold, color: _navyDark),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis)),
      ]);
}