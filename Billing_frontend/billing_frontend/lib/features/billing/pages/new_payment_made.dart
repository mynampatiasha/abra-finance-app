// ============================================================================
// NEW PAYMENT MADE — ALL FIXES APPLIED
// ============================================================================
// File: lib/screens/billing/new_payment_made.dart
//
// FIXES:
// ✅ FIX 1: getAllAccounts() instead of getAccountsByType('BANK')
//           → shows ALL paymentaccounts (PETTY_CASH, FUEL_CARD, BANK, etc.)
// ✅ FIX 2: TextEditingController per bill row (not initialValue)
//           → auto-allocate visually updates bill fields correctly
// ✅ FIX 3: Balance shown below account dropdown immediately on selection
//           → fetched via getAccountBalance(id)
// ✅ FIX 4: Insufficient balance → warning dialog before saving
//           → user can confirm to proceed or cancel
// ✅ FIX 5: Balance check on account selection (not just on save)
//
// UI: matches new_vendor_credit.dart exactly
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/payment_made_service.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../core/services/add_account_service.dart';
import '../widgets/document_preview_buttons.dart';
import 'new_vendor.dart';

// Navy colors — exact match to new_vendor_credit.dart
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);
const Color _billPurple = Color(0xFF8E44AD);

// ============================================================================
// MODELS
// ============================================================================

class _BillRow {
  final String billId;
  final String billNumber;
  final DateTime billDate;
  final DateTime dueDate;
  final double totalAmount;
  final double amountDue;
  final String status;
  double paymentAmount;
  // ✅ FIX 2: controller per row so auto-allocate updates visually
  late final TextEditingController ctrl;

  _BillRow({
    required this.billId,
    required this.billNumber,
    required this.billDate,
    required this.dueDate,
    required this.totalAmount,
    required this.amountDue,
    required this.status,
    this.paymentAmount = 0,
  }) {
    ctrl = TextEditingController(
        text: paymentAmount > 0 ? paymentAmount.toStringAsFixed(2) : '');
  }

  void dispose() => ctrl.dispose();
}

class _Item {
  String itemDetails;
  String itemType;
  String? itemId;
  String? account;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  _Item({
    this.itemDetails = '',
    this.itemType = 'MANUAL',
    this.itemId,
    this.account,
    this.quantity = 1,
    this.rate = 0,
    this.discount = 0,
    this.discountType = 'percentage',
    this.amount = 0,
  });

  Map<String, dynamic> toJson() => {
        'itemDetails': itemDetails,
        'itemType': itemType,
        if (itemId != null) 'itemId': itemId,
        if (account != null) 'account': account,
        'quantity': quantity,
        'rate': rate,
        'discount': discount,
        'discountType': discountType,
        'amount': amount,
      };
}

// ============================================================================
// SCREEN
// ============================================================================

class NewPaymentMadeScreen extends StatefulWidget {
  final String? paymentId;
  const NewPaymentMadeScreen({Key? key, this.paymentId}) : super(key: key);

  @override
  State<NewPaymentMadeScreen> createState() => _NewPaymentMadeScreenState();
}

class _NewPaymentMadeScreenState extends State<NewPaymentMadeScreen> {
  final _formKey = GlobalKey<FormState>();

  // loading
  bool _pageLoading         = false;
  bool _saving              = false;
  bool _loadingVendors      = false;
  bool _loadingBills        = false;
  bool _loadingAccounts     = false;
  bool _loadingBalance      = false;

  // vendor
  String? _vendorId;
  String? _vendorName;
  String? _vendorEmail;
  List<Map<String, dynamic>> _vendors = [];

  // bills — ✅ FIX 2: each row has its own TextEditingController
  List<_BillRow> _bills = [];
  bool _noBillsFound = false;

  // total amount
  final _totalAmountCtrl = TextEditingController();
  double _totalAmountEntered = 0;

  // payment details
  DateTime _paymentDate = DateTime.now();
  String _paymentMode   = 'Bank Transfer';
  String _paymentType   = 'PAYMENT';
  final _refCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();

  // ✅ FIX 1 + FIX 3: all accounts + selected account balance
  String? _selectedAccountId;
  String? _selectedAccountName;
  double? _selectedAccountBalance;   // shown below dropdown
  List<Map<String, dynamic>> _allAccounts = [];

  static const _allModes = [
    'Cash','Cheque','Bank Transfer','UPI','Card','Online','NEFT','RTGS','IMPS'
  ];
  static const _types = ['PAYMENT','ADVANCE','EXCESS'];

  // items
  final List<_Item> _items = [];
  static const _expenseAccounts = [
    'Accounts Payable','Cash','Bank Account','Petty Cash',
    'Advance to Vendor','Prepaid Expenses','Other Current Assets',
  ];

  // tax
  bool _enableGST = false;  double _gstRate = 18;
  bool _enableTDS = false;  double _tdsRate = 0;
  bool _enableTCS = false;  double _tcsRate = 0;

  // totals
  double _billsTotal     = 0;
  double _itemsSubTotal  = 0;
  double _tdsAmt   = 0;
  double _tcsAmt   = 0;
  double _gstAmt   = 0;
  double _grandTotal = 0;
  int    _totalItemCount = 0;

  // ============================================================================
  @override
  void initState() {
    super.initState();
    _fetchVendors();
    _loadAllAccounts(); // ✅ FIX 1
    if (widget.paymentId != null) _loadExistingPayment();
  }

  @override
  void dispose() {
    _totalAmountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    // ✅ FIX 2: dispose all bill controllers
    for (final b in _bills) b.dispose();
    super.dispose();
  }

  // ── loaders ──────────────────────────────────────────────────────────────────

  Future<void> _fetchVendors() async {
    setState(() => _loadingVendors = true);
    try {
      final res = await BillingVendorsService.getAllVendors(limit: 1000);
      if (res['success'] == true) {
        final raw  = res['data'];
        final list = raw is List ? raw : (raw['vendors'] as List? ?? []);
        setState(() {
          _vendors = list.map<Map<String, dynamic>>((v) => {
            '_id':        v['_id'] ?? '',
            'vendorName': v['vendorName'] ?? '',
            'email':      v['email'] ?? v['vendorEmail'] ?? '',
          }).toList();
        });
      }
    } catch (e) { debugPrint('Vendor load: $e'); }
    finally { setState(() => _loadingVendors = false); }
  }

  // ✅ FIX 1: fetch ALL accounts from paymentaccounts collection
Future<void> _loadAllAccounts() async {
  setState(() => _loadingAccounts = true);
  try {
    final accounts = await AddAccountService().getAllAccounts();
    setState(() {
      _allAccounts = accounts;
      // ✅ Auto-select first account if none selected
      if (_allAccounts.isNotEmpty && _selectedAccountId == null) {
        _selectedAccountId = _allAccounts.first['_id'] as String?;
        _selectedAccountName = _allAccounts.first['accountName'] as String?;
      }
    });
    // ✅ Fetch balance for auto-selected account
    if (_selectedAccountId != null) {
      _fetchAccountBalance(_selectedAccountId!);
    }
  } catch (e) {
    debugPrint('Accounts load: $e');
  } finally {
    setState(() => _loadingAccounts = false);
  }
}

  // ✅ FIX 3: fetch balance when account is selected
  Future<void> _fetchAccountBalance(String accountId) async {
    setState(() { _loadingBalance = true; _selectedAccountBalance = null; });
    try {
      final balance = await AddAccountService().getAccountBalance(accountId);
      setState(() => _selectedAccountBalance = balance);
    } catch (e) {
      // fallback: find from already loaded list
      final acc = _allAccounts.firstWhere(
          (a) => a['_id'] == accountId, orElse: () => {});
      if (acc.isNotEmpty) {
        setState(() =>
            _selectedAccountBalance = (acc['currentBalance'] ?? 0).toDouble());
      }
    } finally {
      setState(() => _loadingBalance = false);
    }
  }

  Future<void> _fetchVendorBills(String vendorId) async {
    // dispose old controllers first
    for (final b in _bills) b.dispose();
    setState(() { _loadingBills = true; _bills = []; _noBillsFound = false; });
    try {
      final bills = await PaymentMadeService.getVendorOutstandingBills(vendorId);
      if (bills.isEmpty) {
        setState(() => _noBillsFound = true);
      } else {
        setState(() {
          _bills = bills.map((b) => _BillRow(
            billId:      b['_id'] ?? '',
            billNumber:  b['billNumber'] ?? '',
            billDate:    DateTime.tryParse(b['billDate'] ?? '') ?? DateTime.now(),
            dueDate:     DateTime.tryParse(b['dueDate']  ?? '') ?? DateTime.now(),
            totalAmount: (b['totalAmount'] ?? 0).toDouble(),
            amountDue:   (b['amountDue']   ?? 0).toDouble(),
            status:      b['status'] ?? '',
          )).toList()
            ..sort((a, b) => a.billDate.compareTo(b.billDate));
        });
      }
    } catch (e) { _showError('Failed to load bills: $e'); }
    finally { setState(() => _loadingBills = false); }
  }

  Future<void> _loadExistingPayment() async {
    setState(() => _pageLoading = true);
    try {
      final p = await PaymentMadeService.getPayment(widget.paymentId!);
      setState(() {
        _vendorId    = p.vendorId;
        _vendorName  = p.vendorName;
        _vendorEmail = p.vendorEmail;
        _paymentDate = p.paymentDate;
        _paymentMode = p.paymentMode;
        _paymentType = p.paymentType;
        _refCtrl.text   = p.referenceNumber ?? '';
        _notesCtrl.text = p.notes ?? '';
        _totalAmountCtrl.text = p.amount.toStringAsFixed(2);
        _totalAmountEntered   = p.amount;
        _selectedAccountId   = p.paidFromAccountId;
        _selectedAccountName = p.paidFromAccountName;
        _gstRate = p.gstRate; _tdsRate = p.tdsRate; _tcsRate = p.tcsRate;
        _enableGST = p.gstRate > 0;
        _enableTDS = p.tdsRate > 0;
        _enableTCS = p.tcsRate > 0;
        _items.clear();
        _items.addAll(p.items.map((i) => _Item(
          itemDetails: i.itemDetails, itemType: i.itemType,
          itemId: i.itemId, account: i.account,
          quantity: i.quantity, rate: i.rate,
          discount: i.discount, discountType: i.discountType,
          amount: i.amount,
        )));
        _recalculate();
      });
      if (_selectedAccountId != null) _fetchAccountBalance(_selectedAccountId!);
      if (_vendorId != null) _fetchVendorBills(_vendorId!);
    } catch (e) { _showError('Failed to load payment: $e'); }
    finally { setState(() => _pageLoading = false); }
  }

  // ── allocation ───────────────────────────────────────────────────────────────

  // ✅ FIX 2: update both model AND controller text
  void _autoAllocate() {
    double remaining = _totalAmountEntered;
    for (final bill in _bills) {
      if (remaining <= 0) {
        bill.paymentAmount = 0;
        bill.ctrl.text = '';
      } else {
        final apply = remaining >= bill.amountDue ? bill.amountDue : remaining;
        bill.paymentAmount = apply;
        bill.ctrl.text = apply.toStringAsFixed(2); // ✅ visually updates field
        remaining -= apply;
      }
    }
    _recalculate();
  }

  // ── calculation ──────────────────────────────────────────────────────────────

  void _recalculate() {
    double billsTotal = _bills.fold(0, (s, b) => s + b.paymentAmount);
    double sub = 0;
    for (final item in _items) {
      if (item.rate > 0) {
        double a = item.quantity * item.rate;
        if (item.discount > 0) {
          a -= item.discountType == 'percentage'
              ? a * item.discount / 100 : item.discount;
        }
        item.amount = a.clamp(0, double.infinity);
      } else { item.amount = 0; }
      sub += item.amount;
    }
    final tdsAmt  = _enableTDS ? sub * _tdsRate / 100 : 0.0;
    final tcsAmt  = _enableTCS ? sub * _tcsRate / 100 : 0.0;
    final gstBase = sub - tdsAmt + tcsAmt;
    final gstAmt  = _enableGST ? gstBase * _gstRate / 100 : 0.0;
    setState(() {
      _billsTotal    = billsTotal;
      _itemsSubTotal = sub;
      _tdsAmt = tdsAmt; _tcsAmt = tcsAmt; _gstAmt = gstAmt;
      _grandTotal = billsTotal + (sub - tdsAmt + tcsAmt + gstAmt);
      _totalItemCount = _items.where((i) => i.itemDetails.trim().isNotEmpty).length;
    });
  }

  // ── save ─────────────────────────────────────────────────────────────────────

  Future<void> _recordPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_vendorId == null) { _showError('Please select a vendor'); return; }
    if (_grandTotal <= 0 && _bills.every((b) => b.paymentAmount == 0)) {
      _showError('Enter a payment amount or allocate to bills'); return;
    }

    // ✅ FIX 4: insufficient balance warning dialog
    if (_selectedAccountId != null && _selectedAccountBalance != null) {
      if (_grandTotal > _selectedAccountBalance!) {
        final shortage = _grandTotal - _selectedAccountBalance!;
        final proceed = await _showInsufficientBalanceDialog(
          accountName: _selectedAccountName ?? 'Selected Account',
          available: _selectedAccountBalance!,
          required: _grandTotal,
          shortage: shortage,
        );
        if (!proceed) return;
      }
    }

    setState(() => _saving = true);
    try {
      final billsApplied = _bills
          .where((b) => b.paymentAmount > 0)
          .map((b) => {
                'billId':        b.billId,
                'billNumber':    b.billNumber,
                'amountApplied': b.paymentAmount,
              })
          .toList();

      final validItems = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();

      final payload = {
        'vendorId':        _vendorId,
        'vendorName':      _vendorName,
        'vendorEmail':     _vendorEmail,
        'paymentDate':     _paymentDate.toIso8601String(),
        'paymentMode':     _paymentMode,
        'paymentType':     _paymentType,
        'referenceNumber': _refCtrl.text.trim(),
        'notes':           _notesCtrl.text.trim(),
        'amount':          _grandTotal,
        'billsApplied':    billsApplied,
        'items':           validItems.map((i) => i.toJson()).toList(),
        'tdsRate':         _enableTDS ? _tdsRate : 0,
        'tcsRate':         _enableTCS ? _tcsRate : 0,
        'gstRate':         _enableGST ? _gstRate : 0,
        'status':          'RECORDED',
        if (_selectedAccountId   != null) 'paidFromAccountId':   _selectedAccountId,
        if (_selectedAccountName != null) 'paidFromAccountName': _selectedAccountName,
      };

      if (widget.paymentId != null) {
        await PaymentMadeService.updatePayment(widget.paymentId!, payload);
      } else {
        await PaymentMadeService.createPayment(payload);
      }

      _showSuccess(widget.paymentId != null
          ? 'Payment updated successfully' : 'Payment Recorded ✓');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) { _showError('Save failed: $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  // ✅ FIX 4: insufficient balance dialog
  Future<bool> _showInsufficientBalanceDialog({
    required String accountName,
    required double available,
    required double required,
    required double shortage,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Insufficient Balance',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(children: [
              _dialogRow('Account:', accountName),
              const SizedBox(height: 8),
              _dialogRow('Available Balance:',
                  '₹${available.toStringAsFixed(2)}',
                  valueColor: _green),
              const SizedBox(height: 8),
              _dialogRow('Payment Amount:',
                  '₹${required.toStringAsFixed(2)}',
                  valueColor: _navyDark),
              const Divider(height: 16),
              _dialogRow('Shortage:',
                  '₹${shortage.toStringAsFixed(2)}',
                  valueColor: Colors.red.shade700,
                  bold: true),
            ]),
          ),
          const SizedBox(height: 16),
          Text(
            'The payment amount exceeds the available balance in "$accountName". Do you want to proceed anyway?',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            textAlign: TextAlign.center,
          ),
        ]),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navyMid,
              side: BorderSide(color: _navyMid),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Proceed Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _dialogRow(String label, String value,
      {Color? valueColor, bool bold = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        Text(value, style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: valueColor ?? _navyDark,
        )),
      ]);

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _green,
          behavior: SnackBarBehavior.floating));

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _pageLoading
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
                          _buildTaxSection(),
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
          widget.paymentId != null ? 'Edit Payment Made' : 'New Payment Made',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'View PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
            onPressed: () => openDocumentPdf(context: context, docId: widget.paymentId, pdfEndpoint: '/api/finance/payments-made', docNumber: 'PM'),
          ),
          IconButton(
            tooltip: 'Preview Email',
            icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
            onPressed: () => openEmailPreview(context: context, docId: widget.paymentId, emailEndpoint: '/api/finance/payments-made'),
          ),
          TextButton.icon(
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saving ? null : _recordPayment,
            icon: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(_saving ? 'Saving...' : 'Record Payment'),
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

  Widget _buildMainContent() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildVendorSection(),
      const SizedBox(height: 20),
      _buildPaymentDetailsSection(),
      const SizedBox(height: 20),
      _buildBillsSection(),
      const SizedBox(height: 20),
      _buildItemsSection(),
      const SizedBox(height: 20),
      _buildNotesSection(),
      const SizedBox(height: 20),
    ]),
  );

  // ============================================================================
  // VENDOR SECTION
  // ============================================================================

  Widget _buildVendorSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Vendor Information', Icons.business),
      const SizedBox(height: 16),
      InkWell(
        onTap: _showVendorSelector,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: _vendorId == null
                ? Colors.red.shade300 : Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.business_outlined, color: _navyAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _vendorName ?? 'Select Vendor *',
              style: TextStyle(
                fontSize: 15,
                color: _vendorName != null ? _navyDark : Colors.grey[600],
                fontWeight: _vendorName != null ? FontWeight.w600 : FontWeight.normal,
              ),
            )),
            if (_loadingVendors)
              const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ]),
        ),
      ),
      if (_vendorEmail != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(_vendorEmail!, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ]),
      ],
    ],
  ));

  // ============================================================================
  // PAYMENT DETAILS SECTION
  // ============================================================================

  Widget _buildPaymentDetailsSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Payment Details', Icons.payment),
      const SizedBox(height: 16),

      // Row 1: Date + Mode
      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final dateField = InkWell(
          onTap: () async {
            final d = await showDatePicker(
                context: context, initialDate: _paymentDate,
                firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (d != null) setState(() => _paymentDate = d);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Payment Date *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.calendar_today),
            ),
            child: Text(DateFormat('dd MMM yyyy').format(_paymentDate)),
          ),
        );
        final modeField = DropdownButtonFormField<String>(
          value: _paymentMode,
          decoration: InputDecoration(
            labelText: 'Payment Mode *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.payment),
          ),
          items: _allModes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (v) => setState(() => _paymentMode = v!),
        );
        return isWide
            ? Row(children: [
                Expanded(child: dateField),
                const SizedBox(width: 16),
                Expanded(child: modeField),
              ])
            : Column(children: [dateField, const SizedBox(height: 16), modeField]);
      }),

      const SizedBox(height: 16),

      // ✅ FIX 1: ALL accounts dropdown
      // ✅ FIX 3: balance shown below
      _loadingAccounts
          ? const Center(child: CircularProgressIndicator())
          : DropdownButtonFormField<String>(
              value: _selectedAccountId,
              decoration: InputDecoration(
                labelText: 'Paid From Account *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.account_balance_wallet),
                hintText: 'Select account',
              ),
              items: _allAccounts.map((a) {
                final type = a['accountType'] as String? ?? '';
                final name = a['accountName'] as String? ?? '';
                return DropdownMenuItem<String>(
                  value: a['_id'] as String,
                  child: Row(children: [
                    Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _navyAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(type,
                          style: const TextStyle(fontSize: 10, color: _navyAccent)),
                    ),
                  ]),
                );
              }).toList(),
              onChanged: (v) {
                final sel = _allAccounts.firstWhere(
                    (a) => a['_id'] == v, orElse: () => {});
                setState(() {
                  _selectedAccountId   = v;
                  _selectedAccountName = sel['accountName'] as String?;
                  _selectedAccountBalance = null;
                });
                // ✅ FIX 3 + FIX 5: fetch balance immediately on selection
                if (v != null) _fetchAccountBalance(v);
              },
              validator: (v) => v == null ? 'Please select an account' : null,
            ),

      // ✅ FIX 3: Balance display below dropdown
      if (_selectedAccountId != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _selectedAccountBalance != null && _grandTotal > 0 &&
                    _grandTotal > _selectedAccountBalance!
                ? Colors.red.shade50
                : Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _selectedAccountBalance != null && _grandTotal > 0 &&
                      _grandTotal > _selectedAccountBalance!
                  ? Colors.red.shade200
                  : Colors.green.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              _selectedAccountBalance != null && _grandTotal > 0 &&
                      _grandTotal > _selectedAccountBalance!
                  ? Icons.warning_amber_rounded
                  : Icons.account_balance_wallet_outlined,
              size: 16,
              color: _selectedAccountBalance != null && _grandTotal > 0 &&
                      _grandTotal > _selectedAccountBalance!
                  ? Colors.red.shade700
                  : Colors.green.shade700,
            ),
            const SizedBox(width: 8),
            Text('Available Balance: ',
                style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            if (_loadingBalance)
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Text(
                _selectedAccountBalance != null
                    ? '₹${_selectedAccountBalance!.toStringAsFixed(2)}'
                    : '---',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _selectedAccountBalance != null && _grandTotal > 0 &&
                          _grandTotal > _selectedAccountBalance!
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                ),
              ),
            if (_selectedAccountBalance != null && _grandTotal > 0 &&
                _grandTotal > _selectedAccountBalance!) ...[
              const SizedBox(width: 8),
              Text('(Insufficient)',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ],

      const SizedBox(height: 16),

      // Row 2: Type + Reference
      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final typeField = DropdownButtonFormField<String>(
          value: _paymentType,
          decoration: InputDecoration(
            labelText: 'Payment Type *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.category_outlined),
          ),
          items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _paymentType = v!),
        );
        final refField = TextFormField(
          controller: _refCtrl,
          decoration: InputDecoration(
            labelText: 'Reference / Transaction #',
            hintText: 'Enter reference number',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.tag_outlined),
          ),
        );
        return isWide
            ? Row(children: [
                Expanded(child: typeField),
                const SizedBox(width: 16),
                Expanded(child: refField),
              ])
            : Column(children: [typeField, const SizedBox(height: 16), refField]);
      }),
    ],
  ));

  // ============================================================================
  // BILLS SECTION
  // ============================================================================

  Widget _buildBillsSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _sectionTitle('Outstanding Bills', Icons.receipt_long),
        if (_bills.isNotEmpty)
          ElevatedButton.icon(
            onPressed: _autoAllocate,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Auto-Allocate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _billPurple, foregroundColor: Colors.white,
            ),
          ),
      ]),
      const SizedBox(height: 16),

      // Total payment amount
      TextFormField(
        controller: _totalAmountCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(
          labelText: 'Total Payment Amount *',
          hintText: '0.00',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.currency_rupee),
          helperText: _bills.isNotEmpty
              ? 'Amount auto-distributed to bills (oldest first)' : null,
        ),
        onChanged: (v) {
          _totalAmountEntered = double.tryParse(v) ?? 0;
          if (_bills.isNotEmpty) _autoAllocate();
          // refresh balance indicator color
          setState(() {});
        },
      ),
      const SizedBox(height: 16),

      if (_vendorId == null)
        _infoBox(Icons.info_outline, Colors.blue.shade700, Colors.blue.shade50,
            'Select a vendor above to see their outstanding bills.')
      else if (_loadingBills)
        const Center(child: Padding(padding: EdgeInsets.all(24),
            child: CircularProgressIndicator()))
      else if (_noBillsFound)
        _infoBox(Icons.warning_amber_outlined, Colors.orange.shade700,
            Colors.orange.shade50,
            'No outstanding bills found. You can still proceed using the items section below for advance or manual payments.')
      else ...[
        // Gradient table header
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
          child: LayoutBuilder(builder: (_, cs) {
            if (cs.maxWidth < 600) {
              return const Text('OUTSTANDING BILLS',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
            }
            return const Row(children: [
              Expanded(flex: 2, child: Text('BILL #',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              SizedBox(width: 8),
              Expanded(flex: 2, child: Text('BILL DATE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              SizedBox(width: 8),
              Expanded(flex: 2, child: Text('DUE DATE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
              SizedBox(width: 8),
              Expanded(flex: 2, child: Text('AMOUNT DUE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.right)),
              SizedBox(width: 8),
              Expanded(flex: 2, child: Text('STATUS',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.center)),
              SizedBox(width: 8),
              SizedBox(width: 110, child: Text('PAY AMOUNT',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  textAlign: TextAlign.right)),
            ]);
          }),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _bills.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (_, i) => _buildBillRow(i),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_billPurple.withOpacity(0.1), _billPurple.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _billPurple.withOpacity(0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total Allocated to Bills',
                style: TextStyle(fontWeight: FontWeight.w600,
                    fontSize: 13, color: _billPurple)),
            Text('₹${_billsTotal.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold,
                    fontSize: 15, color: _billPurple)),
          ]),
        ),
      ],
    ],
  ));

  // ✅ FIX 2: bill row uses controller — auto-allocate updates text field visually
  Widget _buildBillRow(int index) {
    final bill = _bills[index];
    final isOverdue = bill.status == 'OVERDUE';
    final Color sc = bill.status == 'OPEN'
        ? Colors.blue
        : bill.status == 'OVERDUE'
            ? Colors.red
            : Colors.orange;

    return LayoutBuilder(builder: (_, cs) {
      // Mobile
      if (cs.maxWidth < 600) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isOverdue ? Colors.red.shade50 : Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isOverdue ? Colors.red.shade200 : Colors.grey[200]!),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(bill.billNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sc.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: sc.withOpacity(0.4)),
                ),
                child: Text(bill.status,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, color: sc)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Due: ₹${bill.amountDue.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: bill.ctrl, // ✅ uses controller
              decoration: InputDecoration(
                labelText: 'Pay Amount',
                prefixText: '₹',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (v) {
                final val = double.tryParse(v) ?? 0;
                _bills[index].paymentAmount =
                    val > bill.amountDue ? bill.amountDue : val;
                _recalculate();
              },
            ),
          ]),
        );
      }

      // Desktop
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isOverdue ? Colors.red.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(flex: 2,
              child: Text(bill.billNumber,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13))),
          const SizedBox(width: 8),
          Expanded(flex: 2,
              child: Text(DateFormat('dd MMM yy').format(bill.billDate),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          const SizedBox(width: 8),
          Expanded(flex: 2,
              child: Text(DateFormat('dd MMM yy').format(bill.dueDate),
                  style: TextStyle(
                      fontSize: 12,
                      color: isOverdue
                          ? Colors.red.shade700
                          : Colors.grey[600]))),
          const SizedBox(width: 8),
          Expanded(flex: 2,
              child: Text('₹${bill.amountDue.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13))),
          const SizedBox(width: 8),
          Expanded(flex: 2,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: sc.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sc.withOpacity(0.4)),
                  ),
                  child: Text(bill.status,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: sc)),
                ),
              )),
          const SizedBox(width: 8),
          // ✅ FIX 2: uses controller — visually updates when auto-allocate runs
          SizedBox(
            width: 110,
            child: TextField(
              controller: bill.ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '₹',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      const BorderSide(color: _billPurple, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              onChanged: (v) {
                final val = double.tryParse(v) ?? 0;
                _bills[index].paymentAmount =
                    val > bill.amountDue ? bill.amountDue : val;
                _recalculate();
              },
            ),
          ),
        ]),
      );
    });
  }

  // ============================================================================
  // ITEMS SECTION
  // ============================================================================

  Widget _buildItemsSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _sectionTitle('Additional Line Items', Icons.list_alt),
        Row(children: [
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _items.add(_Item(itemType: 'FETCHED')); _recalculate();
            }),
            icon: const Icon(Icons.cloud_download_outlined, size: 16),
            label: const Text('Fetched'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyLight, foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _items.add(_Item(itemType: 'MANUAL')); _recalculate();
            }),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Manual'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent, foregroundColor: Colors.white,
            ),
          ),
        ]),
      ]),
      const SizedBox(height: 16),
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
        child: LayoutBuilder(builder: (_, cs) {
          if (cs.maxWidth < 600) {
            return const Text('ITEMS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
          }
          return const Row(children: [
            Expanded(flex: 3, child: Text('ITEM DETAILS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
            SizedBox(width: 8),
            Expanded(flex: 2, child: Text('ACCOUNT',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
            SizedBox(width: 8),
            SizedBox(width: 70, child: Text('QTY',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center)),
            SizedBox(width: 8),
            SizedBox(width: 90, child: Text('RATE (₹)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.right)),
            SizedBox(width: 8),
            SizedBox(width: 100, child: Text('AMOUNT (₹)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.right)),
            SizedBox(width: 48),
          ]);
        }),
      ),
      const SizedBox(height: 8),
      if (_items.isEmpty)
        Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No items added yet', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 6),
            Text('Use Fetched or Manual buttons above',
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ]),
        ))
      else
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 12),
          itemBuilder: (_, i) => _buildItemRow(i),
        ),
    ],
  ));

  Widget _buildItemRow(int index) {
    final item = _items[index];
    final isFetched = item.itemType == 'FETCHED';
    final accent = isFetched ? _navyLight : _navyAccent;

    return LayoutBuilder(builder: (_, cs) {
      if (cs.maxWidth < 600) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(isFetched ? Icons.cloud_download_outlined : Icons.edit_outlined,
                  size: 14, color: accent),
              const SizedBox(width: 6),
              Text(isFetched ? 'Fetched Item' : 'Manual Item',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                onPressed: () => setState(() { _items.removeAt(index); _recalculate(); }),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: item.itemDetails,
              decoration: InputDecoration(
                labelText: 'Item Description',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                isDense: true,
              ),
              onChanged: (v) => item.itemDetails = v,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: item.quantity.toStringAsFixed(0),
                decoration: InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (v) { item.quantity = double.tryParse(v) ?? 1; _recalculate(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(
                initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
                decoration: InputDecoration(
                  labelText: 'Rate (₹)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) { item.rate = double.tryParse(v) ?? 0; _recalculate(); },
              )),
              const SizedBox(width: 8),
              Expanded(child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text('₹${item.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right),
              )),
            ]),
          ]),
        );
      }

      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: TextFormField(
          initialValue: item.itemDetails,
          decoration: InputDecoration(
            hintText: isFetched ? 'Fetched item description' : 'Enter item description',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            prefixIcon: Icon(
                isFetched ? Icons.cloud_download_outlined : Icons.edit_outlined,
                size: 16, color: accent),
          ),
          maxLines: 2,
          onChanged: (v) => item.itemDetails = v,
        )),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: DropdownButtonFormField<String>(
          value: _expenseAccounts.contains(item.account) ? item.account : null,
          decoration: InputDecoration(
            hintText: 'Account',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
          isExpanded: true,
          items: _expenseAccounts.map((a) => DropdownMenuItem(
              value: a, child: Text(a, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => item.account = v),
        )),
        const SizedBox(width: 8),
        SizedBox(width: 70, child: TextFormField(
          initialValue: item.quantity.toStringAsFixed(0),
          decoration: InputDecoration(
            hintText: '1',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onChanged: (v) { item.quantity = double.tryParse(v) ?? 1; _recalculate(); },
        )),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: TextFormField(
          initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
          decoration: InputDecoration(
            hintText: '0.00',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          onChanged: (v) { item.rate = double.tryParse(v) ?? 0; _recalculate(); },
        )),
        const SizedBox(width: 8),
        Container(
          width: 100,
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
          onPressed: () => setState(() { _items.removeAt(index); _recalculate(); }),
        ),
      ]);
    });
  }

  // ============================================================================
  // NOTES SECTION
  // ============================================================================

  Widget _buildNotesSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Additional Notes', Icons.note_alt),
      const SizedBox(height: 16),
      TextFormField(
        controller: _notesCtrl,
        decoration: InputDecoration(
          labelText: 'Notes',
          hintText: 'Internal notes about this payment',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          alignLabelWithHint: true,
        ),
        maxLines: 3,
      ),
    ],
  ));

  // ============================================================================
  // TAX SECTION (sidebar)
  // ============================================================================

  Widget _buildTaxSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Tax Settings', Icons.calculate),
      const SizedBox(height: 16),
      SwitchListTile(
        title: const Text('Enable GST'),
        value: _enableGST, activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() { _enableGST = v; _recalculate(); }),
      ),
      if (_enableGST) ...[
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _gstRate.toString(),
          decoration: InputDecoration(
            labelText: 'GST Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() { _gstRate = double.tryParse(v) ?? 18; _recalculate(); }),
        ),
      ],
      const SizedBox(height: 12),
      SwitchListTile(
        title: const Text('Enable TDS'),
        subtitle: const Text('Tax Deducted at Source', style: TextStyle(fontSize: 11)),
        value: _enableTDS, activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() { _enableTDS = v; _recalculate(); }),
      ),
      if (_enableTDS) ...[
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _tdsRate.toString(),
          decoration: InputDecoration(
            labelText: 'TDS Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() { _tdsRate = double.tryParse(v) ?? 0; _recalculate(); }),
        ),
      ],
      const SizedBox(height: 12),
      SwitchListTile(
        title: const Text('Enable TCS'),
        subtitle: const Text('Tax Collected at Source', style: TextStyle(fontSize: 11)),
        value: _enableTCS, activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() { _enableTCS = v; _recalculate(); }),
      ),
      if (_enableTCS) ...[
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _tcsRate.toString(),
          decoration: InputDecoration(
            labelText: 'TCS Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() { _tcsRate = double.tryParse(v) ?? 0; _recalculate(); }),
        ),
      ],
    ],
  );

  // ============================================================================
  // SUMMARY SECTION (sidebar)
  // ============================================================================

  Widget _buildSummarySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Payment Summary', Icons.summarize),
      const SizedBox(height: 16),
      if (_billsTotal > 0) ...[
        _summaryRow('Bills Allocated', _billsTotal, color: _billPurple),
        const SizedBox(height: 6),
      ],
      if (_itemsSubTotal > 0) ...[
        _summaryRow('Items Sub Total', _itemsSubTotal),
        const SizedBox(height: 6),
      ],
      if (_enableTDS && _tdsAmt > 0) ...[
        _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)', -_tdsAmt,
            color: Colors.red[700]),
        const SizedBox(height: 6),
      ],
      if (_enableTCS && _tcsAmt > 0) ...[
        _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmt),
        const SizedBox(height: 6),
      ],
      if (_enableGST && _gstAmt > 0) ...[
        _summaryRow('CGST (${(_gstRate/2).toStringAsFixed(1)}%)', _gstAmt / 2),
        const SizedBox(height: 6),
        _summaryRow('SGST (${(_gstRate/2).toStringAsFixed(1)}%)', _gstAmt / 2),
        const SizedBox(height: 6),
      ],
      const Divider(thickness: 2),
      const SizedBox(height: 6),
      _summaryRow('Total Payment Amount', _grandTotal, isBold: true, isTotal: true),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark.withOpacity(0.1), _navyLight.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _navyAccent.withOpacity(0.3)),
        ),
        child: Column(children: [
          _infoRow('Bills Paid:',
              '${_bills.where((b) => b.paymentAmount > 0).length}'),
          const SizedBox(height: 4),
          _infoRow('Line Items:', '$_totalItemCount'),
          const SizedBox(height: 4),
          _infoRow('Mode:', _paymentMode),
          if (_selectedAccountName != null) ...[
            const SizedBox(height: 4),
            _infoRow('Account:', _selectedAccountName!),
          ],
          if (_selectedAccountBalance != null) ...[
            const SizedBox(height: 4),
            _infoRow('Avail. Balance:',
                '₹${_selectedAccountBalance!.toStringAsFixed(2)}'),
          ],
        ]),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _recordPayment,
          icon: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(_saving ? 'Saving...'
              : widget.paymentId != null ? 'Update Payment' : 'Record Payment'),
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid,
            side: BorderSide(color: _navyMid),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ],
  );

  // ============================================================================
  // VENDOR SELECTOR DIALOG
  // ============================================================================

  Future<void> _showVendorSelector() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> allVendors = List.from(_vendors);
    List<Map<String, dynamic>> filtered   = List.from(_vendors);
    bool loading = _vendors.isEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        if (loading && allVendors.isEmpty) {
          BillingVendorsService.getAllVendors(
            sortBy: 'vendorName', sortOrder: 'asc', limit: 1000,
          ).then((res) {
            if (res['success'] == true) {
              final raw  = res['data'];
              final list = raw is List ? raw : (raw['vendors'] as List? ?? []);
              final mapped = list.map<Map<String, dynamic>>((v) => {
                '_id': v['_id'] ?? '',
                'vendorName': v['vendorName'] ?? '',
                'email': v['email'] ?? v['vendorEmail'] ?? '',
              }).toList();
              setS(() { allVendors = mapped; filtered = mapped; loading = false; });
            } else {
              setS(() => loading = false);
            }
          }).catchError((_) => setS(() => loading = false));
        }

        return AlertDialog(
          title: const Text('Select Vendor'),
          content: SizedBox(width: 480, height: 420, child: Column(children: [
            TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search vendors...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setS(() {
                filtered = v.isEmpty ? allVendors
                    : allVendors.where((vd) =>
                        vd['vendorName'].toString().toLowerCase().contains(v.toLowerCase()) ||
                        vd['email'].toString().toLowerCase().contains(v.toLowerCase())).toList();
              }),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('No vendors found'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final v = filtered[i];
                            final name = v['vendorName'].toString();
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _navyAccent,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white)),
                              ),
                              title: Text(name),
                              subtitle: Text(v['email'].toString()),
                              onTap: () {
                                setState(() {
                                  _vendorId    = v['_id'];
                                  _vendorName  = v['vendorName'];
                                  _vendorEmail = v['email'];
                                  for (final b in _bills) b.dispose();
                                  _bills = []; _noBillsFound = false;
                                });
                                Navigator.pop(ctx);
                                _fetchVendorBills(v['_id']);
                              },
                            );
                          }),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final result = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewVendorPage()));
                  if (result != null && result is Map<String, dynamic>) {
                    setState(() {
                      _vendorId    = result['id'];
                      _vendorName  = result['vendorName'];
                      _vendorEmail = result['email'];
                    });
                    _fetchVendorBills(result['id']);
                    _showSuccess('Vendor "${result['vendorName']}" added');
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add New Vendor'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navyAccent,
                  side: const BorderSide(color: _navyAccent),
                ),
              )),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'))],
        );
      }),
    );
  }

  // ============================================================================
  // HELPERS — exact match to new_vendor_credit.dart
  // ============================================================================

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10, offset: const Offset(0, 3))],
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
    Text(title, style: const TextStyle(
      fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  Widget _summaryRow(String label, double amount,
      {Color? color, bool isBold = false, bool isTotal = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
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
      ]);

  Widget _infoRow(String label, String value) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        Text(value, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: _navyDark)),
      ]);

  Widget _infoBox(IconData icon, Color textColor, Color bgColor, String msg) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: textColor.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: textColor, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(msg,
              style: TextStyle(fontSize: 13, color: textColor))),
        ]),
      );
}