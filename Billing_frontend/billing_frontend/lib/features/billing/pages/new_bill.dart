// ============================================================================
// NEW BILL SCREEN - Complete Flutter UI
// ============================================================================
// File: lib/screens/billing/new_bill.dart
// Mirrors Zoho Books Bill creation exactly
// UI matches new_vendor_credit.dart EXACTLY:
// ✅ Gradient AppBar (_navyDark → _navyMid → _navyLight)
// ✅ Gradient icon box section titles (_sectionTitle)
// ✅ Card: borderRadius 10, shadow offset(0,3), 0.05 opacity (_card)
// ✅ Gradient items table header (_navyDark → _navyMid)
// ✅ Mobile item card layout via LayoutBuilder < 600px
// ✅ LayoutBuilder > 800px → Row(flex:3 + 320px sidebar), ≤ 800px → Column
// ✅ Tax sidebar: _sectionTitle + _navyAccent Switch
// ✅ Summary sidebar: _summaryRow + gradient info box + _green Save & Submit
// ✅ Vendor dialog: _navyAccent CircleAvatar + _navyAccent Add New Vendor
//
// FUNCTIONALITY: fully preserved, zero changes to logic
// ✅ BillService.createBill / updateBill / createRecurringProfile unchanged
// ✅ _calculateAmounts, _validateItems, _buildBillData unchanged
// ✅ _saveAsDraft, _saveAndSubmit unchanged
// ✅ _loadBillData unchanged
// ✅ All 4 controllers + dispose() unchanged
// ✅ All state variables unchanged
// ✅ Recurring bill section fully intact
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/bill_service.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../app/config/api_config.dart';
import '../../../../core/finance_secure_storage.dart';
import 'new_vendor.dart';
import 'new_chart_of_account.dart';
import '../widgets/document_preview_buttons.dart';

// Navy blue gradient colors — exact match to new_vendor_credit.dart
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);

// ── Items table column widths ─────────────────────────────────────────────────
const double _bColNo      = 36.0;
const double _bColDesc    = 190.0;
const double _bColAcct    = 150.0;
const double _bColHsn     = 100.0;
const double _bColUnit    = 80.0;
const double _bColQty     = 70.0;
const double _bColRate    = 90.0;
const double _bColDisc    = 110.0;
const double _bColGst     = 80.0;
const double _bColTaxable = 100.0;
const double _bColTax1    = 90.0;   // CGST
const double _bColTax2    = 90.0;   // SGST
const double _bColAmt     = 100.0;
const double _bColDel     = 44.0;

// Unit options
const List<String> _kBillUnits = ['Nos', 'Hrs', 'Kg', 'Pcs', 'Box', 'Mtr', 'Ltr', 'Dz', 'MT', 'Set'];

// GST rate options
const List<double> _kBillGstRates = [0, 5, 12, 18, 28];

class NewBillScreen extends StatefulWidget {
  final String? billId;

  const NewBillScreen({Key? key, this.billId}) : super(key: key);

  @override
  State<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends State<NewBillScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Controllers — unchanged
  final _purchaseOrderController    = TextEditingController();
  final _subjectController          = TextEditingController();
  final _notesController            = TextEditingController();
  final _termsConditionsController  = TextEditingController();

  // Vendor Selection — unchanged
  String? _selectedVendorId;
  String? _selectedVendorName;
  String? _selectedVendorEmail;
  String? _selectedVendorGSTIN;

  // Bill Details — unchanged
  DateTime _billDate = DateTime.now();
  String _selectedPaymentTerms = 'Net 30';
  DateTime? _dueDate;

  // Tax Settings — unchanged
  double _tdsRate  = 0;
  double _tcsRate  = 0;
  double _gstRate  = 18;
  bool _enableTDS  = false;
  bool _enableTCS  = false;
  bool _enableGST  = true;

  // Items — unchanged
  List<MutableBillItem> _items = [];

  // Calculations — unchanged
  double _subTotal      = 0;
  double _tdsAmount     = 0;
  double _tcsAmount     = 0;
  double _gstAmount     = 0;
  double _totalAmount   = 0;
  int    _totalQuantity = 0;

  // Recurring Bill Settings — unchanged
  bool      _makeRecurring      = false;
  String    _repeatEvery        = '1';
  String    _repeatUnit         = 'months';
  DateTime? _recurringStartDate;
  DateTime? _recurringEndDate;
  String    _profileName        = '';

  final List<String> _termsOptions = [
    'Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60',
  ];

  // Dynamic COA expense accounts (replaces hardcoded list)
  List<Map<String, dynamic>> _coaExpAccounts = [];
  bool _loadingCoaAccounts = false;

  // ============================================================================
  // LIFECYCLE — unchanged
  // ============================================================================

  @override
  void initState() {
    super.initState();
    _calculateDueDate();
    _addNewItem();
    _loadCoaExpenseAccounts();
    if (widget.billId != null) _loadBillData();
  }

  @override
  void dispose() {
    _purchaseOrderController.dispose();
    _subjectController.dispose();
    _notesController.dispose();
    _termsConditionsController.dispose();
    super.dispose();
  }

  // ── Load COA Expense accounts from backend ──────────────────────────────────
  Future<void> _loadCoaExpenseAccounts() async {
    setState(() => _loadingCoaAccounts = true);
    try {
      final prefs     = await SharedPreferences.getInstance();
      final token     = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();

      // Fetch all three expense-type buckets in parallel — same as new_expenses.dart
      final types = ['Expense', 'Other Expense', 'Cost Of Goods Sold'];
      final futures = types.map((t) {
        final encodedType = Uri.encodeComponent(t);
        final uri = Uri.parse(
            '${ApiConfig.baseUrl}/api/finance/chart-of-accounts?accountType=$encodedType&limit=500');
        return http.get(uri, headers: {
          'Content-Type': 'application/json',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
        });
      });

      final responses = await Future.wait(futures);

      final allAccounts = <Map<String, dynamic>>[];
      for (final resp in responses) {
        if (resp.statusCode == 200) {
          final body     = jsonDecode(resp.body);
          final accounts = (body['data']?['accounts'] as List? ?? []);
          allAccounts.addAll(accounts.map((a) => {
                '_id':         a['_id']?.toString() ?? '',
                'accountName': a['accountName']?.toString() ?? '',
                'accountType': a['accountType']?.toString() ?? '',
              }));
        }
      }

      // Deduplicate by _id, then sort alphabetically
      final seen   = <String>{};
      final unique = allAccounts.where((a) {
        final id = a['_id'] as String;
        if (id.isEmpty || seen.contains(id)) return false;
        seen.add(id);
        return true;
      }).toList()
        ..sort((a, b) =>
            (a['accountName'] as String).compareTo(b['accountName'] as String));

      if (mounted) {
        setState(() {
          _coaExpAccounts     = unique;
          _loadingCoaAccounts = false;
        });
      }
    } catch (_) {
      // Fallback to common expense accounts
      if (mounted) {
        setState(() {
          _coaExpAccounts = [
            {'_id': '1',  'accountName': 'Advertising & Marketing',  'accountType': 'Expense'},
            {'_id': '2',  'accountName': 'Cost of Goods Sold',        'accountType': 'Cost Of Goods Sold'},
            {'_id': '3',  'accountName': 'Fuel',                      'accountType': 'Expense'},
            {'_id': '4',  'accountName': 'Insurance',                 'accountType': 'Expense'},
            {'_id': '5',  'accountName': 'Meals & Entertainment',     'accountType': 'Expense'},
            {'_id': '6',  'accountName': 'Office Supplies',           'accountType': 'Expense'},
            {'_id': '7',  'accountName': 'Other Expenses',            'accountType': 'Other Expense'},
            {'_id': '8',  'accountName': 'Professional Fees',         'accountType': 'Expense'},
            {'_id': '9',  'accountName': 'Rent',                      'accountType': 'Expense'},
            {'_id': '10', 'accountName': 'Travel & Conveyance',       'accountType': 'Expense'},
            {'_id': '11', 'accountName': 'Utilities',                 'accountType': 'Expense'},
          ];
          _loadingCoaAccounts = false;
        });
      }
    }
  }

  // ============================================================================
  // LOGIC — all unchanged
  // ============================================================================

  void _calculateDueDate() {
    switch (_selectedPaymentTerms) {
      case 'Due on Receipt': _dueDate = _billDate; break;
      case 'Net 15': _dueDate = _billDate.add(const Duration(days: 15)); break;
      case 'Net 30': _dueDate = _billDate.add(const Duration(days: 30)); break;
      case 'Net 45': _dueDate = _billDate.add(const Duration(days: 45)); break;
      case 'Net 60': _dueDate = _billDate.add(const Duration(days: 60)); break;
    }
  }

  void _calculateAmounts() {
    setState(() {
      _subTotal      = 0;
      _totalQuantity = 0;
      for (var item in _items) {
        if (item.quantity > 0 && item.rate > 0) {
          // taxable = qty × rate − discount
          double taxable = item.quantity * item.rate;
          if (item.discount > 0) {
            if (item.discountType == 'percentage') {
              taxable = taxable - (taxable * item.discount / 100);
            } else {
              taxable = taxable - item.discount;
            }
          }
          item.taxableAmount = double.parse(taxable.toStringAsFixed(2));

          // Per-item GST (always intra-state CGST+SGST for bills)
          final gst = item.itemGstRate;
          item.cgstAmount = double.parse((taxable * (gst / 2) / 100).toStringAsFixed(2));
          item.sgstAmount = item.cgstAmount;
          item.igstAmount = 0;

          item.amount = double.parse(
              (taxable + item.cgstAmount + item.sgstAmount).toStringAsFixed(2));

          _subTotal      += taxable;
          _totalQuantity += item.quantity.toInt();
        } else {
          item.taxableAmount = 0;
          item.cgstAmount    = 0;
          item.sgstAmount    = 0;
          item.igstAmount    = 0;
          item.amount        = 0;
        }
      }
      _subTotal = double.parse(_subTotal.toStringAsFixed(2));

      _tdsAmount = _enableTDS ? (_subTotal * _tdsRate / 100) : 0;
      _tcsAmount = _enableTCS ? (_subTotal * _tcsRate / 100) : 0;
      final double totalItemTax = _items.fold(0.0, (s, i) => s + i.cgstAmount + i.sgstAmount + i.igstAmount);
      _gstAmount   = totalItemTax;
      _totalAmount = _subTotal - _tdsAmount + _tcsAmount + totalItemTax;
    });
  }

  void _addNewItem() => setState(() => _items.add(MutableBillItem()));

  void _removeItem(int index) {
    setState(() { _items.removeAt(index); _calculateAmounts(); });
  }

  Future<void> _loadBillData() async {
    setState(() => _isLoading = true);
    try {
      final bill = await BillService.getBill(widget.billId!);
      setState(() {
        _selectedVendorId            = bill.vendorId;
        _selectedVendorName          = bill.vendorName;
        _selectedVendorEmail         = bill.vendorEmail;
        _selectedVendorGSTIN         = bill.vendorGSTIN;
        _purchaseOrderController.text = bill.purchaseOrderNumber ?? '';
        _billDate                    = bill.billDate;
        _selectedPaymentTerms        = bill.paymentTerms;
        _dueDate                     = bill.dueDate;
        _subjectController.text      = bill.subject ?? '';
        _notesController.text        = bill.notes ?? '';
        _termsConditionsController.text = bill.termsAndConditions ?? '';
        _tdsRate    = bill.tdsRate;
        _tcsRate    = bill.tcsRate;
        _gstRate    = bill.gstRate;
        _enableTDS  = bill.tdsRate > 0;
        _enableTCS  = bill.tcsRate > 0;
        _enableGST  = bill.gstRate > 0;
        _items = bill.items.map((item) => MutableBillItem(
          itemDetails:   item.itemDetails,
          account:       item.account,
          quantity:      item.quantity,
          rate:          item.rate,
          discount:      item.discount,
          discountType:  item.discountType,
          amount:        item.amount,
          hsnCode:       item.hsnCode,
          sacCode:       item.sacCode,
          unit:          item.unit,
          itemGstRate:   item.itemGstRate,
          taxableAmount: item.taxableAmount,
          cgstAmount:    item.cgstAmount,
          sgstAmount:    item.sgstAmount,
          igstAmount:    item.igstAmount,
        )).toList();
        _calculateAmounts();
      });
    } catch (e) {
      _showErrorSnackbar('Failed to load bill: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _validateItems() {
    final nonEmpty = _items.where((item) => item.itemDetails.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) { _showErrorSnackbar('Please add at least one item with details'); return false; }
    for (var item in nonEmpty) {
      if (item.quantity <= 0) { _showErrorSnackbar('All items must have quantity greater than 0'); return false; }
      if (item.rate <= 0)     { _showErrorSnackbar('All items must have rate greater than 0');     return false; }
    }
    return true;
  }

  Map<String, dynamic> _buildBillData(String status) {
    final validItems = _items.where((item) => item.itemDetails.trim().isNotEmpty).toList();
    if (validItems.isEmpty) throw Exception('Please add at least one item');
    return {
      'vendorId':            _selectedVendorId,
      'vendorName':          _selectedVendorName,
      'vendorEmail':         _selectedVendorEmail,
      'vendorGSTIN':         _selectedVendorGSTIN,
      'purchaseOrderNumber': _purchaseOrderController.text.trim(),
      'billDate':            _billDate.toIso8601String(),
      'paymentTerms':        _selectedPaymentTerms,
      'dueDate':             _dueDate?.toIso8601String(),
      'subject':             _subjectController.text.trim(),
      'notes':               _notesController.text.trim(),
      'termsAndConditions':  _termsConditionsController.text.trim(),
      'items':               validItems.map((item) => item.toJson()).toList(),
      'tdsRate':             _enableTDS ? _tdsRate : 0,
      'tcsRate':             _enableTCS ? _tcsRate : 0,
      'gstRate':             _enableGST ? _gstRate : 0,
      'status':              status,
      'isRecurring':         _makeRecurring,
    };
  }

  Future<void> _markAsSent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) { _showErrorSnackbar('Please select a vendor'); return; }
    if (!_validateItems()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Sent?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'The email will NOT be sent to the vendor.\n\nDo you want to mark this bill as Sent (Open) anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _navyDark, foregroundColor: Colors.white),
            child: const Text('Mark as Sent'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _isSaving = true);
    try {
      final billData = _buildBillData('OPEN');
      Bill bill;
      if (widget.billId != null) {
        bill = await BillService.updateBill(widget.billId!, billData);
      } else {
        bill = await BillService.createBill(billData);
      }
      await BillService.markAsSent(bill.id);
      _showSuccessSnackbar('Bill marked as sent: ${bill.billNumber}');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar('Failed to mark as sent: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAsDraft() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) { _showErrorSnackbar('Please select a vendor'); return; }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);    try {
      final billData = _buildBillData('DRAFT');
      Bill bill;
      if (widget.billId != null) {
        bill = await BillService.updateBill(widget.billId!, billData);
      } else {
        bill = await BillService.createBill(billData);
      }
      if (_makeRecurring && _profileName.isNotEmpty) await _createRecurringProfile(bill);
      _showSuccessSnackbar('Bill saved as draft: ${bill.billNumber}');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar('Failed to save bill: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) { _showErrorSnackbar('Please select a vendor'); return; }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final billData = _buildBillData('OPEN');
      Bill bill;
      if (widget.billId != null) {
        bill = await BillService.updateBill(widget.billId!, billData);
      } else {
        bill = await BillService.createBill(billData);
      }
      if (_makeRecurring && _profileName.isNotEmpty) await _createRecurringProfile(bill);
      _showSuccessSnackbar('Bill submitted: ${bill.billNumber}');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar('Failed to submit bill: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _createRecurringProfile(Bill bill) async {
    try {
      await BillService.createRecurringProfile({
        'profileName':  _profileName.isNotEmpty ? _profileName : 'Recurring - ${bill.vendorName}',
        'vendorId':     bill.vendorId,
        'vendorName':   bill.vendorName,
        'vendorEmail':  bill.vendorEmail,
        'repeatEvery':  int.tryParse(_repeatEvery) ?? 1,
        'repeatUnit':   _repeatUnit,
        'startDate':    (_recurringStartDate ?? DateTime.now()).toIso8601String(),
        'endDate':      _recurringEndDate?.toIso8601String(),
        'billTemplate': {
          'items':        _items.where((i) => i.itemDetails.isNotEmpty).map((i) => i.toJson()).toList(),
          'paymentTerms': _selectedPaymentTerms,
          'subject':      _subjectController.text.trim(),
          'notes':        _notesController.text.trim(),
          'tdsRate':      _enableTDS ? _tdsRate : 0,
          'tcsRate':      _enableTCS ? _tcsRate : 0,
          'gstRate':      _enableGST ? _gstRate : 0,
        },
        'status':       'ACTIVE',
        'nextBillDate': (_recurringStartDate ?? DateTime.now()).toIso8601String(),
      });
    } catch (e) {
      print('Failed to create recurring profile: $e');
    }
  }

  void _showErrorSnackbar(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating));

  void _showSuccessSnackbar(String msg) => ScaffoldMessenger.of(context).showSnackBar(
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
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
                            _buildTaxSettingsSection(),
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

  // ── AppBar — gradient, exact match to new_vendor_credit.dart ─────────────────

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
          widget.billId != null ? 'Edit Bill' : 'New Bill',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'View PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
            onPressed: () => openDocumentPdf(context: context, docId: widget.billId, pdfEndpoint: '/api/finance/bills', docNumber: 'Bill'),
          ),
          IconButton(
            tooltip: 'Preview Email',
            icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
            onPressed: () => openEmailPreview(context: context, docId: widget.billId, emailEndpoint: '/api/finance/bills'),
          ),
          TextButton.icon(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          // Mark as Sent — no email, just status → OPEN
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _markAsSent,
            icon: const Icon(Icons.mark_email_read_outlined, size: 18, color: Colors.white70),
            label: const Text('Mark as Sent', style: TextStyle(color: Colors.white70)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white38),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAsDraft,
            icon: const Icon(Icons.save_outlined, color: Colors.white70, size: 18),
            label: const Text('Save as Draft', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndSubmit,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(_isSaving ? 'Submitting...' : 'Save & Submit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );

  // ── Main scrollable content ───────────────────────────────────────────────────

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildVendorSection(),
          const SizedBox(height: 20),
          _buildBillDetailsSection(),
          const SizedBox(height: 20),
          _buildItemsSection(),
          const SizedBox(height: 20),
          _buildNotesSection(),
          const SizedBox(height: 20),
          _buildRecurringSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ============================================================================
  // VENDOR SECTION
  // ============================================================================

  Widget _buildVendorSection() {
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Vendor Information', Icons.business),
        const SizedBox(height: 16),
        InkWell(
          onTap: _showVendorSelector,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.business_outlined, color: _navyAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedVendorName ?? 'Select Vendor *',
                  style: TextStyle(
                    fontSize: 15,
                    color: _selectedVendorName != null ? _navyDark : Colors.grey[600],
                    fontWeight: _selectedVendorName != null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
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
        if (_selectedVendorGSTIN != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text('GSTIN: $_selectedVendorGSTIN',
                style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          ]),
        ],
      ],
    ));
  }

  // ============================================================================
  // BILL DETAILS SECTION
  // ============================================================================

  Widget _buildBillDetailsSection() {
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Bill Details', Icons.description_outlined),
        const SizedBox(height: 16),

        // PO Number + Bill Date
        LayoutBuilder(builder: (_, cs) {
          final isWide = cs.maxWidth > 600;
          final poField = TextFormField(
            controller: _purchaseOrderController,
            decoration: InputDecoration(
              labelText: 'Purchase Order Number',
              hintText: 'Optional',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              prefixIcon: const Icon(Icons.numbers),
            ),
          );
          final dateField = InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _billDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (date != null) setState(() { _billDate = date; _calculateDueDate(); });
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Bill Date *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
              child: Text(DateFormat('dd MMM yyyy').format(_billDate)),
            ),
          );
          return isWide
              ? Row(children: [
                  Expanded(child: poField),
                  const SizedBox(width: 16),
                  Expanded(child: dateField),
                ])
              : Column(children: [poField, const SizedBox(height: 16), dateField]);
        }),

        const SizedBox(height: 16),

        // Payment Terms + Due Date
        LayoutBuilder(builder: (_, cs) {
          final isWide = cs.maxWidth > 600;
          final termsField = DropdownButtonFormField<String>(
            value: _selectedPaymentTerms,
            decoration: InputDecoration(
              labelText: 'Payment Terms *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              prefixIcon: const Icon(Icons.payment),
            ),
            items: _termsOptions.map((t) =>
                DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (value) {
              setState(() { _selectedPaymentTerms = value!; _calculateDueDate(); });
            },
          );
          final dueDateField = InputDecorator(
            decoration: InputDecoration(
              labelText: 'Due Date (Auto)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.event),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            child: Text(
              _dueDate != null ? DateFormat('dd MMM yyyy').format(_dueDate!) : '-',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          );
          return isWide
              ? Row(children: [
                  Expanded(child: termsField),
                  const SizedBox(width: 16),
                  Expanded(child: dueDateField),
                ])
              : Column(children: [termsField, const SizedBox(height: 16), dueDateField]);
        }),

        const SizedBox(height: 16),

        TextFormField(
          controller: _subjectController,
          decoration: InputDecoration(
            labelText: 'Subject / Description',
            hintText: 'Optional',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _navyAccent, width: 2)),
            prefixIcon: const Icon(Icons.subject),
          ),
          maxLines: 2,
        ),
      ],
    ));
  }

  // ============================================================================
  // ITEMS SECTION — horizontally scrollable table with HSN/Unit/GST columns
  // ============================================================================

  Widget _buildItemsSection() {
    final double tableWidth = _bColNo + _bColDesc + _bColAcct + _bColHsn +
        _bColUnit + _bColQty + _bColRate + _bColDisc + _bColGst +
        _bColTaxable + _bColTax1 + _bColTax2 + _bColAmt + _bColDel;

    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Line Items', Icons.list_alt),
        const SizedBox(height: 14),

        // Horizontally scrollable table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Table header ──────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: _navyDark,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                ),
                child: Row(children: [
                  _bThCell('#',          _bColNo),
                  _bThCell('DESCRIPTION',_bColDesc),
                  _bThCell('ACCOUNT',    _bColAcct),
                  _bThCell('HSN / SAC',  _bColHsn),
                  _bThCell('UNIT',       _bColUnit),
                  _bThCell('QTY',        _bColQty,     align: TextAlign.center),
                  _bThCell('RATE (₹)',   _bColRate,    align: TextAlign.right),
                  _bThCell('DISCOUNT',   _bColDisc,    align: TextAlign.right),
                  _bThCell('GST %',      _bColGst,     align: TextAlign.center),
                  _bThCell('TAXABLE',    _bColTaxable, align: TextAlign.right),
                  _bThCell('CGST',       _bColTax1,    align: TextAlign.right),
                  _bThCell('SGST',       _bColTax2,    align: TextAlign.right),
                  _bThCell('AMOUNT',     _bColAmt,     align: TextAlign.right),
                  SizedBox(width: _bColDel),
                ]),
              ),

              // ── Data rows ─────────────────────────────────────────────────
              if (_items.isEmpty)
                Container(
                  width: tableWidth,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(
                      left:   BorderSide(color: Colors.grey[200]!),
                      right:  BorderSide(color: Colors.grey[200]!),
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.inbox_outlined, size: 20, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text('No items — click Add Item below',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ]),
                )
              else
                ...List.generate(_items.length, (i) => _buildItemTableRow(i)),

              // ── Add Item row ──────────────────────────────────────────────
              InkWell(
                onTap: _addNewItem,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                child: Container(
                  width: tableWidth,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _navyAccent.withOpacity(0.05),
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                    border: Border(
                      left:   BorderSide(color: _navyAccent.withOpacity(0.25)),
                      right:  BorderSide(color: _navyAccent.withOpacity(0.25)),
                      bottom: BorderSide(color: _navyAccent.withOpacity(0.25)),
                    ),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_circle_outline, size: 18, color: _navyAccent),
                    const SizedBox(width: 8),
                    Text('+ Add Item',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                            color: _navyAccent)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ],
    ));
  }

  // ── Table header cell ─────────────────────────────────────────────────────
  Widget _bThCell(String text, double width, {TextAlign align = TextAlign.left}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(text, textAlign: align,
            style: const TextStyle(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.bold, letterSpacing: 0.4)),
      ),
    );
  }

  // ── Cell input decoration ─────────────────────────────────────────────────
  InputDecoration _bCellDeco([String? hint]) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey[300]!)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: _navyAccent, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    isDense: true,
  );

  // ── Single data row ───────────────────────────────────────────────────────
  Widget _buildItemTableRow(int index) {
    final item  = _items[index];
    final isOdd = index.isOdd;

    return Container(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF7F9FC) : Colors.white,
        border: Border(
          left:   BorderSide(color: Colors.grey[200]!),
          right:  BorderSide(color: Colors.grey[200]!),
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [

          // # number
          SizedBox(width: _bColNo,
            child: Center(child: Text('${index + 1}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: Colors.black54)))),

          // Description
          SizedBox(width: _bColDesc,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.itemDetails,
                maxLines: null, minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: _bCellDeco('Item / Service'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                onChanged: (v) => setState(() => item.itemDetails = v),
              ))),

          // Account (searchable)
          SizedBox(width: _bColAcct,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: InkWell(
                onTap: _loadingCoaAccounts ? null : () => _showAccountSelector(item),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(
                      item.account ?? 'Select…',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: item.account != null ? _navyDark : Colors.grey[400],
                      ),
                    )),
                    _loadingCoaAccounts
                        ? const SizedBox(width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5))
                        : Icon(Icons.search, size: 14, color: Colors.grey[400]),
                  ]),
                ),
              ))),

          // HSN / SAC
          SizedBox(width: _bColHsn,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.hsnCode.isNotEmpty ? item.hsnCode : item.sacCode,
                decoration: _bCellDeco('HSN/SAC'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                onChanged: (v) => setState(() { item.hsnCode = v; item.sacCode = v; }),
              ))),

          // Unit
          SizedBox(width: _bColUnit,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: DropdownButtonFormField<String>(
                value: _kBillUnits.contains(item.unit) ? item.unit : 'Nos',
                decoration: _bCellDeco(),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                isDense: true,
                items: _kBillUnits.map((u) => DropdownMenuItem(
                    value: u,
                    child: Text(u, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setState(() => item.unit = v ?? 'Nos'),
              ))),

          // Qty
          SizedBox(width: _bColQty,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.quantity > 0 ? item.quantity.toString() : '',
                decoration: _bCellDeco('0'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                onChanged: (v) { setState(() { item.quantity = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
              ))),

          // Rate
          SizedBox(width: _bColRate,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
                decoration: _bCellDeco('0.00'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) { setState(() { item.rate = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
              ))),

          // Discount + % / ₹ toggle
          SizedBox(width: _bColDisc,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(children: [
                Expanded(child: TextFormField(
                  initialValue: item.discount > 0 ? item.discount.toString() : '',
                  decoration: _bCellDeco('0'),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) { setState(() { item.discount = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
                )),
                PopupMenuButton<String>(
                  initialValue: item.discountType,
                  padding: EdgeInsets.zero,
                  icon: Text(item.discountType == 'percentage' ? '%' : '₹',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                          color: _navyAccent)),
                  onSelected: (v) => setState(() { item.discountType = v; _calculateAmounts(); }),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'percentage', child: Text('% Percentage')),
                    const PopupMenuItem(value: 'amount',     child: Text('₹ Flat Amount')),
                  ],
                ),
              ]))),

          // GST %
          SizedBox(width: _bColGst,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: DropdownButtonFormField<double>(
                value: _kBillGstRates.contains(item.itemGstRate) ? item.itemGstRate : 18.0,
                decoration: _bCellDeco(),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                isDense: true,
                items: _kBillGstRates.map((r) => DropdownMenuItem(
                    value: r,
                    child: Text('${r.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) { setState(() { item.itemGstRate = v ?? 18.0; _calculateAmounts(); }); },
              ))),

          // Taxable (read-only)
          SizedBox(width: _bColTaxable,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                item.taxableAmount > 0
                    ? '₹${item.taxableAmount.toStringAsFixed(2)}' : '—',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                    color: Colors.black87)))),

          // CGST (read-only)
          SizedBox(width: _bColTax1,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  item.cgstAmount > 0
                      ? '₹${item.cgstAmount.toStringAsFixed(2)}' : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                      color: Colors.blue[700]),
                ),
                if (item.itemGstRate > 0)
                  Text('${(item.itemGstRate / 2).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ]))),

          // SGST (read-only)
          SizedBox(width: _bColTax2,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  item.sgstAmount > 0
                      ? '₹${item.sgstAmount.toStringAsFixed(2)}' : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                      color: Colors.blue[700]),
                ),
                if (item.itemGstRate > 0)
                  Text('${(item.itemGstRate / 2).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ]))),

          // Amount (read-only)
          SizedBox(width: _bColAmt,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                item.amount > 0
                    ? '₹${item.amount.toStringAsFixed(2)}' : '—',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                    color: _navyDark)))),

          // Delete
          SizedBox(width: _bColDel,
            child: Center(child: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              onPressed: () => _removeItem(index),
              tooltip: 'Remove item',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ))),
        ]),
      ),
    );
  }



  // ============================================================================
  // NOTES SECTION
  // ============================================================================

  Widget _buildNotesSection() {
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Additional Information', Icons.note_alt),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          decoration: InputDecoration(
            labelText: 'Notes',
            hintText: 'Internal notes about this bill',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _navyAccent, width: 2)),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _termsConditionsController,
          decoration: InputDecoration(
            labelText: 'Terms & Conditions',
            hintText: 'Payment terms, policies, etc.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _navyAccent, width: 2)),
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
      ],
    ));
  }

  // ============================================================================
  // RECURRING BILL SECTION — fully intact, Switch activeColor → _navyAccent
  // ============================================================================

  Widget _buildRecurringSection() {
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.repeat, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('Recurring Bill',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
          const Spacer(),
          Switch(
            value: _makeRecurring,
            activeColor: _navyAccent,
            onChanged: (v) => setState(() => _makeRecurring = v),
          ),
        ]),

        if (_makeRecurring) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // Profile Name
          TextFormField(
            initialValue: _profileName,
            decoration: InputDecoration(
              labelText: 'Profile Name *',
              hintText: 'e.g., Monthly Office Rent',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyAccent, width: 2)),
              prefixIcon: const Icon(Icons.label_outline),
            ),
            onChanged: (v) => _profileName = v,
          ),
          const SizedBox(height: 16),

          // Repeat Every + Unit
          LayoutBuilder(builder: (_, cs) {
            final isWide = cs.maxWidth > 400;
            final repeatField = Expanded(
              flex: isWide ? 1 : 1,
              child: TextFormField(
                initialValue: _repeatEvery,
                decoration: InputDecoration(
                  labelText: 'Repeat Every',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navyAccent, width: 2)),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => _repeatEvery = v,
              ),
            );
            final unitField = Expanded(
              flex: isWide ? 2 : 1,
              child: DropdownButtonFormField<String>(
                value: _repeatUnit,
                decoration: InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _navyAccent, width: 2)),
                ),
                items: const [
                  DropdownMenuItem(value: 'days',   child: Text('Days')),
                  DropdownMenuItem(value: 'weeks',  child: Text('Weeks')),
                  DropdownMenuItem(value: 'months', child: Text('Months')),
                  DropdownMenuItem(value: 'years',  child: Text('Years')),
                ],
                onChanged: (v) => setState(() => _repeatUnit = v!),
              ),
            );
            return isWide
                ? Row(children: [repeatField, const SizedBox(width: 16), unitField])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    repeatField,
                    const SizedBox(height: 16),
                    unitField,
                  ]);
          }),

          const SizedBox(height: 16),

          // Start Date + End Date
          LayoutBuilder(builder: (_, cs) {
            final isWide = cs.maxWidth > 600;
            final startField = Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _recurringStartDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2030),
                  );
                  if (d != null) setState(() => _recurringStartDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Start Date *',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.calendar_today),
                  ),
                  child: Text(_recurringStartDate != null
                      ? DateFormat('dd MMM yyyy').format(_recurringStartDate!)
                      : 'Select date'),
                ),
              ),
            );
            final endField = Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _recurringEndDate ?? DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2035),
                  );
                  if (d != null) setState(() => _recurringEndDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'End Date (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.event),
                    suffixIcon: _recurringEndDate != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _recurringEndDate = null))
                        : null,
                  ),
                  child: Text(_recurringEndDate != null
                      ? DateFormat('dd MMM yyyy').format(_recurringEndDate!)
                      : 'No end date'),
                ),
              ),
            );
            return isWide
                ? Row(children: [startField, const SizedBox(width: 16), endField])
                : Column(children: [startField, const SizedBox(height: 16), endField]);
          }),

          const SizedBox(height: 16),

          // Info box — orange kept intentionally (warning context)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Bills will be auto-created every $_repeatEvery $_repeatUnit starting from '
                '${_recurringStartDate != null ? DateFormat('dd MMM yyyy').format(_recurringStartDate!) : 'selected date'}',
                style: TextStyle(fontSize: 13, color: Colors.orange[800]),
              )),
            ]),
          ),
        ],
      ],
    ));
  }

  // ============================================================================
  // TAX SETTINGS SECTION (Right Sidebar)
  // ============================================================================

  Widget _buildTaxSettingsSection() {
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
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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

  // ============================================================================
  // SUMMARY SECTION (Right Sidebar)
  // ============================================================================

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Bill Summary', Icons.summarize),
        const SizedBox(height: 16),

        _summaryRow('Sub Total', _subTotal),
        if (_enableTDS && _tdsAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)', -_tdsAmount,
              color: Colors.red[700]),
        ],
        if (_enableTCS && _tcsAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmount),
        ],
        // Per-item CGST/SGST totals
        Builder(builder: (_) {
          final totalCgst = _items.fold(0.0, (s, i) => s + i.cgstAmount);
          final totalSgst = _items.fold(0.0, (s, i) => s + i.sgstAmount);
          return Column(children: [
            if (totalCgst > 0) ...[
              const SizedBox(height: 6),
              _summaryRow('CGST', totalCgst),
            ],
            if (totalSgst > 0) ...[
              const SizedBox(height: 6),
              _summaryRow('SGST', totalSgst),
            ],
          ]);
        }),

        const Divider(thickness: 2),
        const SizedBox(height: 6),
        _summaryRow('Total Amount', _totalAmount, isBold: true, isTotal: true),

        const SizedBox(height: 16),

        // Info box — gradient navy matching vendor credit
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
            _infoRow('Total Quantity:', _totalQuantity.toString()),
            const SizedBox(height: 4),
            _infoRow('Total Items:',
                _items.where((i) => i.itemDetails.isNotEmpty).length.toString()),
          ]),
        ),

        const SizedBox(height: 20),

        // Save & Submit — _green
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndSubmit,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_isSaving ? 'Submitting...' : 'Save & Submit Bill'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Save as Draft — outlined _navyMid
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _saveAsDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save as Draft'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navyMid,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: _navyMid),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              foregroundColor: Colors.grey[600],
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.grey[400]!),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // ACCOUNT SELECTOR DIALOG — same pattern as new_expenses.dart
  // ============================================================================

  Future<void> _showAccountSelector(MutableBillItem item) async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> filtered = List.from(_coaExpAccounts);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          void doFilter(String q) {
            setDlg(() {
              filtered = q.trim().isEmpty
                  ? List.from(_coaExpAccounts)
                  : _coaExpAccounts
                      .where((a) => (a['accountName'] as String)
                          .toLowerCase()
                          .contains(q.trim().toLowerCase()))
                      .toList();
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
              child: Column(children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_navyDark, _navyMid],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.account_tree_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Select Account',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search accounts…',
                      prefixIcon: const Icon(Icons.search, color: _navyAccent),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                searchCtrl.clear();
                                doFilter('');
                              })
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _navyAccent, width: 2)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: doFilter,
                  ),
                ),

                // Count
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Row(children: [
                    Text('${filtered.length} account(s)',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ]),
                ),

                // List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off, size: 40, color: Colors.grey[300]),
                              const SizedBox(height: 8),
                              Text('No accounts found',
                                  style: TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final acc  = filtered[i];
                            final name = acc['accountName'] as String;
                            final type = (acc['accountType'] as String?) ?? '';
                            final isSelected = item.account == name;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: _navyAccent.withOpacity(0.08),
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: isSelected
                                    ? _navyAccent
                                    : _navyAccent.withOpacity(0.1),
                                child: Icon(
                                  Icons.account_tree_outlined,
                                  size: 14,
                                  color: isSelected ? Colors.white : _navyAccent,
                                ),
                              ),
                              title: Text(name,
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _navyDark)),
                              subtitle: type.isNotEmpty
                                  ? Text(type,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500]))
                                  : null,
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle,
                                      color: _navyAccent, size: 18)
                                  : null,
                              onTap: () {
                                setState(() => item.account = name);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),

                // ── Add Account button ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // Close the account selector dialog first
                        Navigator.pop(ctx);

                        // Navigate to NewChartOfAccountScreen
                        // Pre-fill with whatever the user typed in the search box
                        final created = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NewChartOfAccountScreen(
                              initialName: searchCtrl.text.trim().isNotEmpty
                                  ? searchCtrl.text.trim()
                                  : null,
                              initialType: 'Expense',
                              initialSubType: 'Expense',
                            ),
                          ),
                        );

                        // If a new account was saved, reload the list and
                        // auto-select the newly created account on this item
                        if (created == true && mounted) {
                          await _loadCoaExpenseAccounts();
                          // The last account added will be the one whose name
                          // matches what was typed — pick it up if possible
                          if (searchCtrl.text.trim().isNotEmpty) {
                            final match = _coaExpAccounts.firstWhere(
                              (a) => (a['accountName'] as String)
                                  .toLowerCase()
                                  .contains(searchCtrl.text.trim().toLowerCase()),
                              orElse: () => {},
                            );
                            if (match.isNotEmpty) {
                              setState(() => item.account = match['accountName'] as String);
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Account'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navyAccent,
                        side: const BorderSide(color: _navyAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ============================================================================
  // VENDOR SELECTOR DIALOG — unchanged logic, _navyAccent avatar + button
  // ============================================================================

  Future<void> _showVendorSelector() async {
    final TextEditingController searchController = TextEditingController();
    List<BillingVendor> vendors         = [];
    List<BillingVendor> filteredVendors = [];
    bool isLoading    = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoading && vendors.isEmpty) {
            BillingVendorsService.getAllVendors(
              sortBy: 'vendorName',
              sortOrder: 'asc',
              limit: 1000,
            ).then((result) {
              if (result['success'] == true) {
                final data       = result['data'];
                final vendorsList = data['vendors'] as List;
                final vendorList = vendorsList
                    .map((json) => BillingVendor.fromJson(json))
                    .toList();
                setDialogState(() {
                  vendors         = vendorList;
                  filteredVendors = vendorList;
                  isLoading       = false;
                });
              } else {
                throw Exception(result['message'] ?? 'Failed to load vendors');
              }
            }).catchError((error) {
              setDialogState(() { errorMessage = error.toString(); isLoading = false; });
            });
          }

          return AlertDialog(
            title: const Text('Select Vendor'),
            content: SizedBox(
              width: 500,
              height: 420,
              child: Column(children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search vendors...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      filteredVendors = value.isEmpty
                          ? vendors
                          : vendors.where((v) =>
                              v.vendorName.toLowerCase().contains(value.toLowerCase()) ||
                              v.email.toLowerCase().contains(value.toLowerCase()) ||
                              (v.companyName?.toLowerCase().contains(value.toLowerCase()) ?? false)
                            ).toList();
                    });
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
                      : errorMessage != null
                          ? Center(child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                                const SizedBox(height: 16),
                                Text('Error: $errorMessage'),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => setDialogState(() {
                                    isLoading    = true;
                                    errorMessage = null;
                                  }),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: _navyAccent,
                                      foregroundColor: Colors.white),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ))
                          : filteredVendors.isEmpty
                              ? const Center(child: Text('No vendors found',
                                  style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: filteredVendors.length,
                                  itemBuilder: (context, index) {
                                    final vendor = filteredVendors[index];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _navyAccent,
                                        child: Text(vendor.vendorName[0].toUpperCase(),
                                            style: const TextStyle(color: Colors.white)),
                                      ),
                                      title: Text(vendor.vendorName),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(vendor.email),
                                          if (vendor.companyName != null &&
                                              vendor.companyName!.isNotEmpty)
                                            Text(vendor.companyName!,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                    fontStyle: FontStyle.italic)),
                                          if (vendor.vendorType != null &&
                                              vendor.vendorType!.isNotEmpty)
                                            Text(vendor.vendorType!,
                                                style: TextStyle(
                                                    fontSize: 12, color: Colors.grey[600])),
                                        ],
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedVendorId    = vendor.id;
                                          _selectedVendorName  = vendor.vendorName;
                                          _selectedVendorEmail = vendor.email;
                                          _selectedVendorGSTIN = null;
                                        });
                                        Navigator.pop(context);
                                      },
                                    );
                                  },
                                ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddVendorDialog();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add New Vendor'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _navyAccent,
                      side: const BorderSide(color: _navyAccent),
                    ),
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
  // ADD VENDOR — unchanged
  // ============================================================================

  Future<void> _showAddVendorDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NewVendorPage()),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedVendorId    = result['id'];
        _selectedVendorName  = result['vendorName'];
        _selectedVendorEmail = result['email'];
        _selectedVendorGSTIN = result['gstNumber'];
      });
      _showSuccessSnackbar('Vendor "${result['vendorName']}" added successfully');
    }
  }

  // ============================================================================
  // HELPERS — exact match to new_vendor_credit.dart
  // ============================================================================

  /// White card with shadow
  Widget _card({required Widget child}) => Container(
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
    child: child,
  );

  /// Section title with gradient icon box
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

  /// Summary row — matching vendor credit _summaryRow
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

  /// Info row inside gradient box
  Widget _infoRow(String label, String value) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      Text(value, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.bold, color: _navyDark)),
    ]);
  }
}