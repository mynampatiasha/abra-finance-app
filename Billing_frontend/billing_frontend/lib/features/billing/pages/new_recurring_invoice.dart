// ============================================================================
// NEW RECURRING INVOICE SCREEN - Restyled to match new_vendor_credit.dart
// ============================================================================
// File: lib/screens/billing/new_recurring_invoice.dart
// CHUNK 1 OF 3  (paste first)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/recurring_invoice_service.dart';
import '../../../../core/services/invoice_service.dart';

// Navy blue color scheme
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewRecurringInvoiceScreen extends StatefulWidget {
  final String? recurringInvoiceId;
  const NewRecurringInvoiceScreen({Key? key, this.recurringInvoiceId}) : super(key: key);

  @override
  State<NewRecurringInvoiceScreen> createState() => _NewRecurringInvoiceScreenState();
}

class _NewRecurringInvoiceScreenState extends State<NewRecurringInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Controllers
  final _profileNameController     = TextEditingController();
  final _orderNumberController     = TextEditingController();
  final _subjectController         = TextEditingController();
  final _customerNotesController   = TextEditingController();
  final _termsConditionsController = TextEditingController();
  final _repeatEveryController     = TextEditingController(text: '1');

  // Customer
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;   

  // Recurrence
  String   _repeatUnit     = 'month';
  DateTime _startDate      = DateTime.now();
  DateTime? _endDate;
  bool     _hasEndDate     = false;
  String   _endCondition   = 'never';
  int      _maxOccurrences = 12;
  DateTime? _nextInvoiceDate;

  // Invoice settings
  String  _selectedTerms      = 'Net 30';
  String? _salesperson;
  String  _invoiceCreationMode = 'draft';

  // Tax
  double _tdsRate   = 0;
  double _tcsRate   = 0;
  double _gstRate   = 18;
  bool   _enableTDS = false;
  bool   _enableTCS = false;
  bool   _enableGST = true;

  // Items & calculations
  List<RecurringInvoiceItem> _items = [];
  double _subTotal      = 0;
  double _tdsAmount     = 0;
  double _tcsAmount     = 0;
  double _gstAmount     = 0;
  double _totalAmount   = 0;
  int    _totalQuantity = 0;

  // Options
  final List<String> _termsOptions      = ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'];
  final List<String> _repeatUnitOptions = ['day', 'week', 'month', 'year'];
  final Map<String, String> _repeatUnitLabels = {
    'day': 'Day(s)', 'week': 'Week(s)', 'month': 'Month(s)', 'year': 'Year(s)',
  };

  // ── lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _calculateNextInvoiceDate();
    _addNewItem();
    if (widget.recurringInvoiceId != null) _loadRecurringInvoiceData();
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _orderNumberController.dispose();
    _subjectController.dispose();
    _customerNotesController.dispose();
    _termsConditionsController.dispose();
    _repeatEveryController.dispose();
    super.dispose();
  }

  // ── business logic (UNCHANGED) ─────────────────────────────────────────────

  void _calculateNextInvoiceDate() {
    final repeatEvery = int.tryParse(_repeatEveryController.text) ?? 1;
    DateTime next = _startDate;
    switch (_repeatUnit) {
      case 'day':   next = _startDate.add(Duration(days: repeatEvery)); break;
      case 'week':  next = _startDate.add(Duration(days: repeatEvery * 7)); break;
      case 'month': next = DateTime(_startDate.year, _startDate.month + repeatEvery, _startDate.day); break;
      case 'year':  next = DateTime(_startDate.year + repeatEvery, _startDate.month, _startDate.day); break;
    }
    setState(() => _nextInvoiceDate = next);
  }

  void _calculateAmounts() {
    setState(() {
      _subTotal = 0; _totalQuantity = 0;
      for (var item in _items) {
        if (item.quantity > 0 && item.rate > 0) {
          double amt = item.quantity * item.rate;
          if (item.discount > 0) {
            amt = item.discountType == 'percentage'
                ? amt - (amt * item.discount / 100)
                : amt - item.discount;
          }
          item.amount     = amt;
          _subTotal      += amt;
          _totalQuantity += item.quantity.toInt();
        }
      }
      _tdsAmount  = _enableTDS ? (_subTotal * _tdsRate / 100) : 0;
      _tcsAmount  = _enableTCS ? (_subTotal * _tcsRate / 100) : 0;
      final base  = _subTotal - _tdsAmount + _tcsAmount;
      _gstAmount  = _enableGST ? (base * _gstRate / 100) : 0;
      _totalAmount = _subTotal - _tdsAmount + _tcsAmount + _gstAmount;
    });
  }

  void _addNewItem() => setState(() => _items.add(RecurringInvoiceItem()));

  void _removeItem(int index) {
    setState(() { _items.removeAt(index); _calculateAmounts(); });
  }

  Future<void> _loadRecurringInvoiceData() async {
    setState(() => _isLoading = true);
    try {
      final ri = await RecurringInvoiceService.getRecurringInvoice(widget.recurringInvoiceId!);
      setState(() {
        _profileNameController.text     = ri.profileName;
        _selectedCustomerId             = ri.customerId;
        _selectedCustomerName           = ri.customerName;
        _selectedCustomerEmail          = ri.customerEmail;
        _selectedCustomerPhone          = ri.customerPhone; 
        _repeatEveryController.text     = ri.repeatEvery.toString();
        _repeatUnit                     = ri.repeatUnit;
        _startDate                      = ri.startDate;
        _endDate                        = ri.endDate;
        _maxOccurrences                 = ri.maxOccurrences ?? 12;
        if (_endDate != null) {
          _endCondition = 'on_date'; _hasEndDate = true;
        } else if (ri.maxOccurrences != null) {
          _endCondition = 'after';
        } else {
          _endCondition = 'never';
        }
        _orderNumberController.text     = ri.orderNumber ?? '';
        _selectedTerms                  = ri.terms;
        _salesperson                    = ri.salesperson;
        _subjectController.text         = ri.subject ?? '';
        _customerNotesController.text   = ri.customerNotes ?? '';
        _termsConditionsController.text = ri.termsAndConditions ?? '';
        _tdsRate = ri.tdsRate; _tcsRate = ri.tcsRate; _gstRate = ri.gstRate;
        _enableTDS = ri.tdsRate > 0; _enableTCS = ri.tcsRate > 0; _enableGST = ri.gstRate > 0;
        _invoiceCreationMode = ri.invoiceCreationMode;
        _items = ri.items.map((i) => RecurringInvoiceItem(
          itemDetails: i.itemDetails, quantity: i.quantity, rate: i.rate,
          discount: i.discount, discountType: i.discountType, amount: i.amount,
        )).toList();
        _calculateAmounts();
        _calculateNextInvoiceDate();
      });
    } catch (e) {
      _showError('Failed to load recurring invoice: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveRecurringInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) { _showError('Please select a customer'); return; }
    if (_profileNameController.text.trim().isEmpty) { _showError('Please enter a profile name'); return; }
    if (!_validateItems()) return;

    setState(() => _isSaving = true);
    try {
      final data = _buildRecurringInvoiceData();
      if (widget.recurringInvoiceId != null) {
        await RecurringInvoiceService.updateRecurringInvoice(widget.recurringInvoiceId!, data);
        _showSuccess('Recurring invoice profile updated successfully');
      } else {
        await RecurringInvoiceService.createRecurringInvoice(data);
        _showSuccess('Recurring invoice profile created successfully');
      }
      Navigator.pop(context, true);
    } catch (e) {
      String msg = 'Failed to save recurring invoice';
      if (e.toString().contains('validation failed')) {
        final m = RegExp(r'Path `(\w+)` is required').firstMatch(e.toString());
        msg = m != null ? 'Please fill in required field: ${m.group(1)}' : 'Please check all required fields';
      } else { msg = e.toString(); }
      _showError(msg);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Map<String, dynamic> _buildRecurringInvoiceData() {
    final valid = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (valid.isEmpty) throw Exception('Please add at least one item with details');
    DateTime? finalEndDate; int? maxOcc;
    if (_endCondition == 'on_date' && _endDate != null) finalEndDate = _endDate;
    else if (_endCondition == 'after') maxOcc = _maxOccurrences;
    return {
      'profileName': _profileNameController.text.trim(),
      'customerId': _selectedCustomerId, 'customerName': _selectedCustomerName,
      'customerEmail': _selectedCustomerEmail,
      'customerPhone': _selectedCustomerPhone ?? '',  
      'repeatEvery': int.tryParse(_repeatEveryController.text) ?? 1,
      'repeatUnit': _repeatUnit,
      'startDate': _startDate.toIso8601String(),
      'endDate': finalEndDate?.toIso8601String(),
      'maxOccurrences': maxOcc,
      'nextInvoiceDate': _nextInvoiceDate?.toIso8601String(),
      'orderNumber': _orderNumberController.text.trim(),
      'terms': _selectedTerms, 'salesperson': _salesperson,
      'subject': _subjectController.text.trim(),
      'items': valid.map((i) => i.toJson()).toList(),
      'customerNotes': _customerNotesController.text.trim(),
      'termsAndConditions': _termsConditionsController.text.trim(),
      'tdsRate': _enableTDS ? _tdsRate : 0,
      'tcsRate': _enableTCS ? _tcsRate : 0,
      'gstRate': _enableGST ? _gstRate : 0,
      'invoiceCreationMode': _invoiceCreationMode,
      'status': 'ACTIVE',
    };
  }

  bool _validateItems() {
    final ne = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (ne.isEmpty) { _showError('Please add at least one item with details'); return false; }
    for (var i in ne) {
      if (i.quantity <= 0) { _showError('All items must have quantity greater than 0'); return false; }
      if (i.rate <= 0)     { _showError('All items must have rate greater than 0'); return false; }
    }
    return true;
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  // ── UI helpers (vendor-credit style) ──────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(children: [
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
  }

  Widget _summaryRow(String label, double amount,
      {Color? color, bool isBold = false, bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontSize: isTotal ? 15 : 13,
          fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isTotal ? _navyDark : Colors.grey[700]),
        )),
        Text(
          '${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isTotal ? 17 : 13,
            fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.w500,
            color: color ?? (isTotal ? _navyAccent : _navyDark),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      Text(value,  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navyDark)),
    ]);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
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
                              _buildAutomationSection(),
                              const Divider(height: 28),
                              _buildTaxSection(),
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
                            _buildAutomationSection(),
                            const Divider(height: 28),
                            _buildTaxSection(),
                            const Divider(height: 28),
                            _buildSummarySection(),
                          ]),
                        ),
                      ]),
                    );
                  }
                },
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
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
            widget.recurringInvoiceId != null ? 'Edit Recurring Invoice' : 'New Recurring Invoice',
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
              onPressed: _isSaving ? null : _saveRecurringInvoice,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
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
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileInfoSection(),
          const SizedBox(height: 20),
          _buildCustomerSection(),
          const SizedBox(height: 20),
          _buildRecurrenceSettingsSection(),
          const SizedBox(height: 20),
          _buildInvoiceDetailsSection(),
          const SizedBox(height: 20),
          _buildItemsSection(),
          const SizedBox(height: 20),
          _buildNotesSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

// ── END OF CHUNK 1 ──────────────────────────────────────────────────────────
// ── CHUNK 2 OF 3 — paste immediately after Chunk 1 ──────────────────────────

  // ── Profile Info ────────────────────────────────────────────────────────────

  Widget _buildProfileInfoSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Recurring Invoice Profile', Icons.repeat),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Profile Name *', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _profileNameController,
                decoration: InputDecoration(
                  hintText: 'e.g., Monthly Subscription - Customer Name',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  helperText: 'A unique name to identify this recurring invoice profile',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _navyAccent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Profile name is required' : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Customer ────────────────────────────────────────────────────────────────

  Widget _buildCustomerSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Customer Information', Icons.person),
          const SizedBox(height: 16),
          InkWell(
            onTap: _showCustomerSelector,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: _navyAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCustomerName ?? 'Select Customer *',
                      style: TextStyle(
                        fontSize: 15,
                        color: _selectedCustomerName != null ? _navyDark : Colors.grey[600],
                        fontWeight: _selectedCustomerName != null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),
          if (_selectedCustomerEmail != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(_selectedCustomerEmail!,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ]),
          ],
        ],
      ),
    );
  }

  // ── Recurrence Settings ─────────────────────────────────────────────────────

  Widget _buildRecurrenceSettingsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Recurrence Settings', Icons.autorenew),
          const SizedBox(height: 20),

          // Repeat Every + Period
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            final repeatEveryField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Repeat Every *', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _repeatEveryController,
                  decoration: InputDecoration(
                    hintText: '1',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navyAccent, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final n = int.tryParse(v);
                    if (n == null || n <= 0) return 'Must be > 0';
                    return null;
                  },
                  onChanged: (_) => _calculateNextInvoiceDate(),
                ),
              ],
            );

            final periodField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Time Period *', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _repeatUnit,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navyAccent, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: _repeatUnitOptions.map((u) => DropdownMenuItem(
                    value: u, child: Text(_repeatUnitLabels[u]!),
                  )).toList(),
                  onChanged: (v) => setState(() { _repeatUnit = v!; _calculateNextInvoiceDate(); }),
                ),
              ],
            );

            if (isWide) {
              return Row(children: [
                Expanded(flex: 2, child: repeatEveryField),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: periodField),
              ]);
            } else {
              return Column(children: [
                repeatEveryField,
                const SizedBox(height: 16),
                periodField,
              ]);
            }
          }),

          const SizedBox(height: 16),

          // Start Date
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Start Date *', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _startDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2030),
                  );
                  if (d != null) setState(() { _startDate = d; _calculateNextInvoiceDate(); });
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    prefixIcon: const Icon(Icons.event, color: _navyAccent),
                  ),
                  child: Text(DateFormat('dd MMM yyyy').format(_startDate),
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // End Condition label
          const Text('End Condition', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
          const SizedBox(height: 8),

          // Radio: Never
          RadioListTile<String>(
            title: const Text('Never — Continues indefinitely'),
            value: 'never',
            groupValue: _endCondition,
            activeColor: _navyAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() { _endCondition = v!; _hasEndDate = false; }),
          ),

          // Radio: After X occurrences
          RadioListTile<String>(
            title: Row(children: [
              const Text('After '),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextFormField(
                  initialValue: _maxOccurrences.toString(),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _navyAccent, width: 2),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: _endCondition == 'after',
                  onChanged: (v) => _maxOccurrences = int.tryParse(v) ?? 12,
                ),
              ),
              const SizedBox(width: 8),
              const Text('occurrences'),
            ]),
            value: 'after',
            groupValue: _endCondition,
            activeColor: _navyAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() { _endCondition = v!; _hasEndDate = false; }),
          ),

          // Radio: On specific date
          RadioListTile<String>(
            title: const Text('On a specific date'),
            value: 'on_date',
            groupValue: _endCondition,
            activeColor: _navyAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() { _endCondition = v!; _hasEndDate = true; }),
          ),

          if (_endCondition == 'on_date') ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? _startDate.add(const Duration(days: 365)),
                    firstDate: _startDate,
                    lastDate: DateTime(2030),
                  );
                  if (d != null) setState(() => _endDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'End Date',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.event_busy, color: _navyAccent),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: Text(
                    _endDate != null ? DateFormat('dd MMM yyyy').format(_endDate!) : 'Select end date',
                    style: TextStyle(
                      color: _endDate != null ? _navyDark : Colors.grey,
                      fontWeight: _endDate != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Next Invoice Date display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_navyDark.withOpacity(0.08), _navyLight.withOpacity(0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _navyAccent.withOpacity(0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.event_available, color: _navyAccent),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Next Invoice Date', style: TextStyle(
                    fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    _nextInvoiceDate != null
                        ? DateFormat('EEEE, dd MMMM yyyy').format(_nextInvoiceDate!)
                        : 'Not calculated',
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark),
                  ),
                ],
              )),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Invoice Details ─────────────────────────────────────────────────────────

  Widget _buildInvoiceDetailsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Invoice Template Details', Icons.description),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            final orderField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Order Number', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _orderNumberController,
                  decoration: InputDecoration(
                    hintText: 'Optional',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _navyAccent, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            );
            final termsField = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Payment Terms *', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedTerms,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _navyAccent, width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: _termsOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _selectedTerms = v!),
                ),
              ],
            );
            if (isWide) {
              return Row(children: [
                Expanded(child: orderField),
                const SizedBox(width: 16),
                Expanded(child: termsField),
              ]);
            } else {
              return Column(children: [orderField, const SizedBox(height: 16), termsField]);
            }
          }),
          const SizedBox(height: 16),
          // Subject
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Subject', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _subjectController,
                decoration: InputDecoration(
                  hintText: 'Optional — appears on each invoice',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navyAccent, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Items ───────────────────────────────────────────────────────────────────

  Widget _buildItemsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Items', Icons.list_alt),
              ElevatedButton.icon(
                onPressed: _addNewItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navyAccent,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Table header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_navyDark, _navyMid],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: LayoutBuilder(builder: (ctx, cs) {
              final isMobile = cs.maxWidth < 600;
              if (isMobile) {
                return const Text('ITEMS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
              }
              return const Row(children: [
                Expanded(flex: 3, child: Text('ITEM DETAILS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                SizedBox(width: 8),
                SizedBox(width: 80, child: Text('QTY',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.center)),
                SizedBox(width: 8),
                SizedBox(width: 100, child: Text('RATE (₹)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.right)),
                SizedBox(width: 8),
                SizedBox(width: 100, child: Text('DISCOUNT',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.right)),
                SizedBox(width: 8),
                SizedBox(width: 120, child: Text('AMOUNT (₹)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.right)),
                SizedBox(width: 48),
              ]);
            }),
          ),

          const SizedBox(height: 8),

          if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No items added yet', style: TextStyle(color: Colors.grey[600])),
                ]),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (_, i) => _buildItemRow(i),
            ),
        ],
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      if (isMobile) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: item.itemDetails,
                      decoration: InputDecoration(
                        labelText: 'Item Description',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        isDense: true,
                      ),
                      onChanged: (v) => item.itemDetails = v,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => _removeItem(index),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.quantity > 0 ? item.quantity.toString() : '',
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      item.quantity = double.tryParse(v) ?? 0;
                      _calculateAmounts();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
                    decoration: InputDecoration(
                      labelText: 'Rate (₹)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      item.rate = double.tryParse(v) ?? 0;
                      _calculateAmounts();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text('₹${item.amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right),
                  ),
                ),
              ]),
            ],
          ),
        );
      }

      // Desktop row
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: TextFormField(
            initialValue: item.itemDetails,
            decoration: InputDecoration(
              hintText: 'Enter item description',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            maxLines: 2,
            onChanged: (v) => item.itemDetails = v,
          )),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextFormField(
            initialValue: item.quantity > 0 ? item.quantity.toString() : '',
            decoration: InputDecoration(
              hintText: '0',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) { item.quantity = double.tryParse(v) ?? 0; _calculateAmounts(); },
          )),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: TextFormField(
            initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
            decoration: InputDecoration(
              hintText: '0.00',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onChanged: (v) { item.rate = double.tryParse(v) ?? 0; _calculateAmounts(); },
          )),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: Row(children: [
            Expanded(child: TextFormField(
              initialValue: item.discount > 0 ? item.discount.toString() : '',
              decoration: InputDecoration(
                hintText: '0',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _navyAccent, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              onChanged: (v) { item.discount = double.tryParse(v) ?? 0; _calculateAmounts(); },
            )),
            PopupMenuButton<String>(
              initialValue: item.discountType,
              icon: const Icon(Icons.arrow_drop_down, size: 16),
              onSelected: (v) => setState(() { item.discountType = v; _calculateAmounts(); }),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'percentage', child: Text('%')),
                const PopupMenuItem(value: 'amount',     child: Text('₹')),
              ],
            ),
          ])),
          const SizedBox(width: 8),
          Container(
            width: 120,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(item.amount.toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _removeItem(index),
            tooltip: 'Remove item',
          ),
        ],
      );
    });
  }

  // ── Notes ───────────────────────────────────────────────────────────────────

  Widget _buildNotesSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Additional Information', Icons.note_alt),
          const SizedBox(height: 16),
          // Customer Notes
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Customer Notes', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _customerNotesController,
                decoration: InputDecoration(
                  hintText: 'Notes visible on every invoice',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navyAccent, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: 3,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Terms & Conditions
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Terms & Conditions', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _termsConditionsController,
                decoration: InputDecoration(
                  hintText: 'Payment terms, policies, etc.',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navyAccent, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ],
      ),
    );
  }

// ── END OF CHUNK 2 ──────────────────────────────────────────────────────────
// ── CHUNK 3 OF 3 — paste immediately after Chunk 2 ──────────────────────────

  // ── Automation Settings (sidebar) ──────────────────────────────────────────

  Widget _buildAutomationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Automation', Icons.smart_toy_outlined),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_navyDark.withOpacity(0.06), _navyLight.withOpacity(0.06)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _navyAccent.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('When invoice is generated:', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
              const SizedBox(height: 10),
              RadioListTile<String>(
                title: const Text('Save as Draft',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text('Requires manual review before sending',
                    style: TextStyle(fontSize: 11)),
                value: 'draft',
                groupValue: _invoiceCreationMode,
                activeColor: _navyAccent,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (v) => setState(() => _invoiceCreationMode = v!),
              ),
              RadioListTile<String>(
                title: const Text('Auto-Send to Customer',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: const Text('Automatically emails invoice to customer',
                    style: TextStyle(fontSize: 11)),
                value: 'auto_send',
                groupValue: _invoiceCreationMode,
                activeColor: _navyAccent,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (v) => setState(() => _invoiceCreationMode = v!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tax Settings (sidebar) ──────────────────────────────────────────────────

  Widget _buildTaxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Tax Settings', Icons.calculate),
        const SizedBox(height: 16),

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
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => setState(() { _gstRate = double.tryParse(v) ?? 18; _calculateAmounts(); }),
          ),
        ],

        const SizedBox(height: 12),

        // TDS
        SwitchListTile(
          title: const Text('Enable TDS'),
          subtitle: const Text('Tax Deducted at Source', style: TextStyle(fontSize: 11)),
          value: _enableTDS,
          activeColor: _navyAccent,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() { _enableTDS = v; _calculateAmounts(); }),
        ),
        if (_enableTDS) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _tdsRate.toString(),
            decoration: InputDecoration(
              labelText: 'TDS Rate (%)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => setState(() { _tdsRate = double.tryParse(v) ?? 0; _calculateAmounts(); }),
          ),
        ],

        const SizedBox(height: 12),

        // TCS
        SwitchListTile(
          title: const Text('Enable TCS'),
          subtitle: const Text('Tax Collected at Source', style: TextStyle(fontSize: 11)),
          value: _enableTCS,
          activeColor: _navyAccent,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() { _enableTCS = v; _calculateAmounts(); }),
        ),
        if (_enableTCS) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _tcsRate.toString(),
            decoration: InputDecoration(
              labelText: 'TCS Rate (%)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => setState(() { _tcsRate = double.tryParse(v) ?? 0; _calculateAmounts(); }),
          ),
        ],
      ],
    );
  }

  // ── Summary (sidebar) ───────────────────────────────────────────────────────

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Invoice Preview', Icons.summarize),
        const SizedBox(height: 6),
        Text('How each invoice will be calculated',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 16),

        _summaryRow('Sub Total', _subTotal),

        if (_enableTDS && _tdsAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)', -_tdsAmount, color: Colors.red[700]),
        ],
        if (_enableTCS && _tcsAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmount),
        ],
        if (_enableGST && _gstAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('CGST (${(_gstRate / 2).toStringAsFixed(1)}%)', _gstAmount / 2),
          const SizedBox(height: 6),
          _summaryRow('SGST (${(_gstRate / 2).toStringAsFixed(1)}%)', _gstAmount / 2),
        ],

        const Divider(thickness: 2),
        const SizedBox(height: 6),
        _summaryRow('Total Amount', _totalAmount, isBold: true, isTotal: true),
        const SizedBox(height: 16),

        // Info chips
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_navyDark.withOpacity(0.08), _navyLight.withOpacity(0.08)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _navyAccent.withOpacity(0.3)),
          ),
          child: Column(children: [
            _infoRow('Total Quantity:', _totalQuantity.toString()),
            const SizedBox(height: 4),
            _infoRow('Total Items:',
                _items.where((i) => i.itemDetails.isNotEmpty).length.toString()),
          ]),
        ),

        const SizedBox(height: 20),

        // Save button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveRecurringInvoice,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Recurring Profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Cancel button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navyMid,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: _navyMid),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Info note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber[300]!),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.amber[800], size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'This profile will automatically generate invoices based on your recurrence settings.',
                style: TextStyle(fontSize: 11, color: Colors.amber[900]),
              )),
            ],
          ),
        ),
      ],
    );
  }

  // ── Customer Selector Dialog (UNCHANGED logic) ──────────────────────────────

  Future<void> _showCustomerSelector() async {
    final searchController = TextEditingController();
    List<BillingCustomer> customers = [];
    List<BillingCustomer> filteredCustomers = [];
    bool isLoading = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoading && customers.isEmpty) {
            InvoiceService.getBillingCustomers().then((response) {
              setDialogState(() {
                customers = response.customers;
                filteredCustomers = customers;
                isLoading = false;
              });
            }).catchError((error) {
              setDialogState(() { errorMessage = error.toString(); isLoading = false; });
            });
          }

          return AlertDialog(
            title: const Text('Select Customer'),
            content: SizedBox(
              width: 500, height: 400,
              child: Column(children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search customers...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) {
                    setDialogState(() {
                      filteredCustomers = v.isEmpty
                          ? customers
                          : customers.where((c) =>
                              c.customerName.toLowerCase().contains(v.toLowerCase()) ||
                              c.customerEmail.toLowerCase().contains(v.toLowerCase()) ||
                              (c.companyName?.toLowerCase().contains(v.toLowerCase()) ?? false))
                              .toList();
                    });
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : errorMessage != null
                          ? Center(child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                                const SizedBox(height: 16),
                                Text('Error loading customers',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red[700])),
                                const SizedBox(height: 8),
                                Text(errorMessage!, style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => setDialogState(() { isLoading = true; errorMessage = null; }),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ))
                          : filteredCustomers.isEmpty
                              ? const Center(child: Text('No customers found', style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: filteredCustomers.length,
                                  itemBuilder: (context, index) {
                                    final c = filteredCustomers[index];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _navyAccent,
                                        child: Text(c.customerName[0].toUpperCase(),
                                            style: const TextStyle(color: Colors.white)),
                                      ),
                                      title: Text(c.customerName),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(c.customerEmail),
                                          if (c.companyName != null)
                                            Text(c.companyName!,
                                                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                                          Text(c.customerPhone,
                                              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                        ],
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedCustomerId    = c.id;
                                          _selectedCustomerName  = c.customerName;
                                          _selectedCustomerEmail = c.customerEmail;
                                          _selectedCustomerPhone = c.customerPhone;
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// RECURRING INVOICE ITEM MODEL (UNCHANGED)
// ============================================================================

class RecurringInvoiceItem {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  RecurringInvoiceItem({
    this.itemDetails  = '',
    this.quantity     = 0,
    this.rate         = 0,
    this.discount     = 0,
    this.discountType = 'percentage',
    this.amount       = 0,
  });

  Map<String, dynamic> toJson() => {
    'itemDetails':  itemDetails,
    'quantity':     quantity,
    'rate':         rate,
    'discount':     discount,
    'discountType': discountType,
    'amount':       amount,
  };

  factory RecurringInvoiceItem.fromJson(Map<String, dynamic> json) => RecurringInvoiceItem(
    itemDetails:  json['itemDetails']  ?? '',
    quantity:     (json['quantity']    ?? 0).toDouble(),
    rate:         (json['rate']        ?? 0).toDouble(),
    discount:     (json['discount']    ?? 0).toDouble(),
    discountType: json['discountType'] ?? 'percentage',
    amount:       (json['amount']      ?? 0).toDouble(),
  );
}

