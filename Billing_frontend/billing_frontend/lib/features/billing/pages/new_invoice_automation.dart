// ============================================================================
// NEW INVOICE SCREEN — ZOHO BOOKS STYLE (COMPLETE)
// ============================================================================
// File: lib/screens/billing/new_invoice.dart
// PATCH: Items section → horizontal scrollable table, GST default 18%
//        Description field → multiline (Enter = new line within same cell)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/invoice_service.dart';
import '../../../../core/services/invoice_automation_service.dart';
import '../../../../app/config/api_config.dart';
import 'new_customer.dart';
import '../widgets/document_preview_buttons.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

// GST rate options
const List<double> _kGstRates = [0, 5, 12, 18, 28];

// Unit options
const List<String> _kUnits = ['Nos', 'Hrs', 'Kg', 'Pcs', 'Box', 'Mtr', 'Ltr', 'Dz', 'MT', 'Set'];

// ── Items table column widths ─────────────────────────────────────────────────
const double _colNo      = 36.0;
const double _colDesc    = 200.0;
const double _colHsn     = 110.0;
const double _colUnit    = 80.0;
const double _colQty     = 70.0;
const double _colRate    = 95.0;
const double _colDisc    = 110.0;
const double _colGst     = 80.0;
const double _colTaxable = 100.0;
const double _colTax1    = 90.0;   // CGST or IGST
const double _colTax2    = 90.0;   // SGST (intra-state only)
const double _colAmt     = 95.0;
const double _colDel     = 44.0;

class NewInvoiceAutomationScreen extends StatefulWidget {
  final String? draftId;
  final List<InvoiceItem>? initialItems;
  final String? initialCustomerName;
  final String? pivotGroupName;

  const NewInvoiceAutomationScreen({
    Key? key, 
    this.draftId, 
    this.initialItems, 
    this.initialCustomerName,
    this.pivotGroupName,
  }) : super(key: key);

  @override
  State<NewInvoiceAutomationScreen> createState() => _NewInvoiceAutomationScreenState();
}

class _NewInvoiceAutomationScreenState extends State<NewInvoiceAutomationScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // ── Controllers ────────────────────────────────────────────────────────────
  final _orderNumberController    = TextEditingController();
  final _referenceNumberController= TextEditingController();
  final _subjectController        = TextEditingController();
  final _customerNotesController  = TextEditingController();
  final _termsConditionsController= TextEditingController();
  final _shippingChargesController= TextEditingController();
  final _adjustmentController     = TextEditingController();

  // ── Per-item description controllers (to support multiline) ───────────────
  final List<TextEditingController> _descControllers = [];

  // ── Customer ───────────────────────────────────────────────────────────────
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;
  String  _customerGSTIN           = '';
  String  _customerPAN             = '';
  String  _gstRegistrationType     = '';

  // ── Billing address ────────────────────────────────────────────────────────
  CustomerAddress _billingAddress  = const CustomerAddress();
  CustomerAddress _shippingAddress = const CustomerAddress();
  bool _sameAsBilling = true;

  // ── Invoice header ─────────────────────────────────────────────────────────
  DateTime _invoiceDate    = DateTime.now();
  DateTime? _dueDate;
  String?  _salesperson;
  String   _currency = 'INR';

  // ── Place of Supply ─────────────────────────────────────────────────────────
  String _placeOfSupply = '';
  String _orgState      = '';
  bool   _isInterState  = false;

  // ── Tax settings ───────────────────────────────────────────────────────────
  double _tdsRate  = 0;
  double _tcsRate  = 0;
  bool   _enableTDS = false;
  bool   _enableTCS = false;

  // ── Invoice-level discount ─────────────────────────────────────────────────
  double _invoiceLevelDiscount     = 0;
  String _invoiceLevelDiscountType = 'percentage';

  // ── Items ──────────────────────────────────────────────────────────────────
  List<InvoiceItem> _items = [];

  // ── Billable expenses ──────────────────────────────────────────────────────
  List<BillableExpense> _billableExpenses = [];
  bool _isLoadingExpenses = false;

  // ── Payment accounts ───────────────────────────────────────────────────────
  List<PaymentAccount> _paymentAccounts     = [];
  PaymentAccount?      _selectedPaymentAccount;
  bool _isLoadingAccounts = false;

  // ── QR Code ────────────────────────────────────────────────────────────────
  File?     _qrCodeFile;
  Uint8List? _qrCodeBytes;
  String?   _qrCodeFileName;
  final     _imagePicker = ImagePicker();

  // ── Calculated totals ──────────────────────────────────────────────────────
  double _subTotal              = 0;
  double _invoiceDiscountAmount = 0;
  double _taxableTotal          = 0;
  double _totalCGST             = 0;
  double _totalSGST             = 0;
  double _totalIGST             = 0;
  double _totalTax              = 0;
  double _tdsAmount             = 0;
  double _tcsAmount             = 0;
  double _shippingCharges       = 0;
  double _adjustment            = 0;
  double _totalAmount           = 0;
  List<TaxSlab> _taxSlabs       = [];

  final List<String> _currencies   = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD'];

  // ==========================================================================
  // LIFECYCLE
  // ==========================================================================

  @override
  void initState() {
    super.initState();
    _dueDate = _invoiceDate;
    
    if (widget.draftId != null) {
      _loadDraftData();
    } else if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      _items = List.from(widget.initialItems!);
      for (final item in _items) {
        _descControllers.add(TextEditingController(text: item.itemDetails));
      }
      _selectedCustomerName = widget.initialCustomerName;
      // Pre-fill notes with the Pivot Group Name
      if (widget.pivotGroupName != null) {
        _customerNotesController.text = 'Billing for: ${widget.pivotGroupName}';
      }
    } else {
      _addNewItem();
    }
    
    _loadOrgState();
    _loadPaymentAccounts();
  }

  @override
  void dispose() {
    _orderNumberController.dispose();
    _referenceNumberController.dispose();
    _subjectController.dispose();
    _customerNotesController.dispose();
    _termsConditionsController.dispose();
    _shippingChargesController.dispose();
    _adjustmentController.dispose();
    for (final c in _descControllers) { c.dispose(); }
    super.dispose();
  }

  // ==========================================================================
  // ORG STATE
  // ==========================================================================

  Future<void> _loadOrgState() async {
    try {
      final response = await InvoiceService.getOrgState();
      setState(() => _orgState = response.state);
      _updateInterState();
    } catch (e) { print('❌ Error loading org state: $e'); }
  }

  void _updateInterState() {
    final newIsInterState = _placeOfSupply.isNotEmpty &&
        _orgState.isNotEmpty &&
        _placeOfSupply.toLowerCase() != _orgState.toLowerCase();
    if (newIsInterState != _isInterState) {
      setState(() => _isInterState = newIsInterState);
      _recalculateAllItemTax();
    }
  }

  // ==========================================================================
  // CALCULATIONS
  // ==========================================================================

  void _recalculateAllItemTax() {
    for (final item in _items) { item.recalculateTax(isInterState: _isInterState); }
    _calculateAmounts();
  }

  void _calculateAmounts() {
    setState(() {
      _subTotal = 0;
      for (final item in _items) {
        item.recalculateTax(isInterState: _isInterState);
        _subTotal += item.taxableAmount;
      }
      _subTotal = double.parse(_subTotal.toStringAsFixed(2));

      if (_invoiceLevelDiscount > 0) {
        _invoiceDiscountAmount = _invoiceLevelDiscountType == 'percentage'
            ? double.parse((_subTotal * _invoiceLevelDiscount / 100).toStringAsFixed(2))
            : _invoiceLevelDiscount.clamp(0, _subTotal);
      } else { _invoiceDiscountAmount = 0; }
      _taxableTotal = double.parse((_subTotal - _invoiceDiscountAmount).toStringAsFixed(2));

      final discountRatio = _subTotal > 0 ? (_taxableTotal / _subTotal) : 1.0;
      final Map<double, Map<String, double>> slabs = {};
      for (final item in _items) {
        final rate = item.itemGstRate;
        slabs.putIfAbsent(rate, () => {'taxable': 0, 'cgst': 0, 'sgst': 0, 'igst': 0});
        final adjTaxable = item.taxableAmount * discountRatio;
        slabs[rate]!['taxable'] = slabs[rate]!['taxable']! + adjTaxable;
        if (_isInterState) {
          slabs[rate]!['igst'] = slabs[rate]!['igst']! + adjTaxable * rate / 100;
        } else {
          slabs[rate]!['cgst'] = slabs[rate]!['cgst']! + adjTaxable * (rate / 2) / 100;
          slabs[rate]!['sgst'] = slabs[rate]!['sgst']! + adjTaxable * (rate / 2) / 100;
        }
      }

      _taxSlabs = slabs.entries.map((e) {
        final m = e.value;
        return TaxSlab(
          gstRate: e.key, taxableAmount: double.parse((m['taxable']!).toStringAsFixed(2)),
          cgst: double.parse((m['cgst']!).toStringAsFixed(2)), sgst: double.parse((m['sgst']!).toStringAsFixed(2)),
          igst: double.parse((m['igst']!).toStringAsFixed(2)),
          totalTax: double.parse(((m['cgst']! + m['sgst']! + m['igst']!)).toStringAsFixed(2)),
        );
      }).toList()..sort((a, b) => a.gstRate.compareTo(b.gstRate));

      _totalCGST = double.parse(_taxSlabs.fold(0.0, (s, t) => s + t.cgst).toStringAsFixed(2));
      _totalSGST = double.parse(_taxSlabs.fold(0.0, (s, t) => s + t.sgst).toStringAsFixed(2));
      _totalIGST = double.parse(_taxSlabs.fold(0.0, (s, t) => s + t.igst).toStringAsFixed(2));
      _totalTax  = double.parse((_totalCGST + _totalSGST + _totalIGST).toStringAsFixed(2));

      _tdsAmount = _enableTDS ? double.parse((_taxableTotal * _tdsRate / 100).toStringAsFixed(2)) : 0;
      _tcsAmount = _enableTCS ? double.parse((_taxableTotal * _tcsRate / 100).toStringAsFixed(2)) : 0;

      _shippingCharges = double.tryParse(_shippingChargesController.text) ?? 0;
      _adjustment      = double.tryParse(_adjustmentController.text) ?? 0;
      _totalAmount     = double.parse((_taxableTotal + _totalTax - _tdsAmount + _tcsAmount + _shippingCharges + _adjustment).toStringAsFixed(2));
    });
  }

  // ==========================================================================
  // DATA LOADING
  // ==========================================================================

  Future<void> _loadPaymentAccounts() async {
    setState(() => _isLoadingAccounts = true);
    try {
      final accounts = await InvoiceService.getPaymentAccounts();
      setState(() {
        _paymentAccounts = accounts;
        if (_paymentAccounts.isNotEmpty) {
          _selectedPaymentAccount = _paymentAccounts.firstWhere(
            (a) => a.accountType == 'BANK_ACCOUNT', orElse: () => _paymentAccounts.first);
        }
      });
    } catch (e) { print('Error loading payment accounts: $e'); }
    finally { setState(() => _isLoadingAccounts = false); }
  }

  Future<void> _loadBillableExpenses(String customerName) async {
    setState(() { _billableExpenses = []; _isLoadingExpenses = true; });
    try {
      final expenses = await InvoiceService.getBillableExpenses(customerName);
      setState(() { _billableExpenses = expenses; });
    } catch (e) { print('❌ Error loading billable expenses: $e'); }
    finally { setState(() => _isLoadingExpenses = false); }
  }

  Future<void> _loadDraftData() async {
    setState(() => _isLoading = true);
    try {
      final drafts = await InvoiceAutomationService.getAutomationDrafts();
      final draft = drafts.firstWhere((d) => d.id == widget.draftId);
      
      for (final c in _descControllers) { c.dispose(); }
      _descControllers.clear();
      
      setState(() {
        _selectedCustomerId       = draft.customerId;
        _selectedCustomerName     = draft.customerName;
        _selectedCustomerEmail    = draft.customerEmail;
        _selectedCustomerPhone    = draft.customerPhone;
        _customerGSTIN            = draft.customerGSTIN;
        _customerPAN              = draft.customerPAN;
        _gstRegistrationType      = draft.gstRegistrationType;
        _billingAddress           = draft.billingAddress;
        _shippingAddress          = draft.shippingAddress;
        _sameAsBilling            = draft.billingAddress.formatted == draft.shippingAddress.formatted;
        _placeOfSupply            = draft.placeOfSupply;
        _orderNumberController.text    = draft.orderNumber ?? '';
        _referenceNumberController.text= draft.referenceNumber;
        _invoiceDate              = draft.invoiceDate;
        _dueDate                  = draft.dueDate;
        _salesperson              = draft.salesperson;
        _currency                 = draft.currency;
        _subjectController.text   = draft.subject ?? '';
        _customerNotesController.text  = draft.customerNotes ?? '';
        _termsConditionsController.text= draft.termsAndConditions ?? '';
        _invoiceLevelDiscount     = draft.invoiceLevelDiscount;
        _invoiceLevelDiscountType = draft.invoiceLevelDiscountType;
        _shippingChargesController.text= draft.shippingCharges > 0 ? draft.shippingCharges.toString() : '';
        _adjustmentController.text     = draft.adjustment != 0 ? draft.adjustment.toString() : '';
        _tdsRate                  = draft.tdsRate;
        _tcsRate                  = draft.tcsRate;
        _enableTDS                = draft.tdsRate > 0;
        _enableTCS                = draft.tcsRate > 0;
        _items = draft.items.map((item) => InvoiceItem(
          itemDetails: item.itemDetails, hsnCode: item.hsnCode, sacCode: item.sacCode,
          unit: item.unit, quantity: item.quantity, rate: item.rate,
          discount: item.discount, discountType: item.discountType,
          taxableAmount: item.taxableAmount, itemGstRate: item.itemGstRate,
          cgstAmount: item.cgstAmount, sgstAmount: item.sgstAmount,
          igstAmount: item.igstAmount, amount: item.amount, expenseId: item.expenseId,
        )).toList();
        
        for (final item in _items) {
          _descControllers.add(TextEditingController(text: item.itemDetails));
        }
        _updateInterState();
        _calculateAmounts();
      });
    } catch (e) { _showError('Failed to load draft: $e'); }
    finally { setState(() => _isLoading = false); }
  }

  // ==========================================================================
  // ITEM MANAGEMENT  — default GST = 18%
  // ==========================================================================

  void _addNewItem() {
    setState(() {
      _items.add(InvoiceItem(itemGstRate: 18));
      _descControllers.add(TextEditingController());
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _descControllers[index].dispose();
      _descControllers.removeAt(index);
      _calculateAmounts();
    });
  }

  // ==========================================================================
  // SAVE ACTIONS
  // ==========================================================================

  bool _validate() {
    if (!_formKey.currentState!.validate()) return false;
    if (_selectedCustomerId == null) { _showError('Please select a customer'); return false; }
    final nonEmpty = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) { _showError('Please add at least one item'); return false; }
    for (final i in nonEmpty) {
      if (i.quantity <= 0) { _showError('All items must have quantity > 0'); return false; }
    }
    return true;
  }

  Future<void> _saveAsStagingDraft() async {
    if (!_validate()) return;
    _calculateAmounts();
    setState(() => _isSaving = true);
    try {
      final data = await _buildInvoiceData('DRAFT');
      
      if (widget.draftId != null) {
        await InvoiceAutomationService.updateAutomationDraft(widget.draftId!, data);
      } else {
        await InvoiceAutomationService.saveAutomationDraft(data);
      }
      _showSuccess('Successfully saved to Staging Drafts');
      Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally { setState(() => _isSaving = false); }
  }

  Future<void> _approveToFinance() async {
    if (widget.draftId == null) {
      _showError('Please Save to Staging first before Approving to Finance.');
      return;
    }
    
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve to Finance?'),
        content: const Text('This will push the staging draft into the official Finance database.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    
    setState(() => _isSaving = true);
    try {
      await InvoiceAutomationService.approveAutomationDraft(widget.draftId!);
      _showSuccess('Successfully Approved to Finance');
      Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally { setState(() => _isSaving = false); }
  }

  Future<Map<String, dynamic>> _buildInvoiceData(String status) async {
    final validItems = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    String? qrCodeUrl;
    if (_qrCodeFile != null || _qrCodeBytes != null) {
      try { qrCodeUrl = await _uploadQRCode(); } catch (e) { print('QR upload failed: $e'); }
    }
    return {
      'customerId': _selectedCustomerId, 'customerName': _selectedCustomerName,
      'customerEmail': _selectedCustomerEmail, 'customerPhone': _selectedCustomerPhone ?? '',
      'customerGSTIN': _customerGSTIN, 'customerPAN': _customerPAN,
      'gstRegistrationType': _gstRegistrationType,
      'billingAddress': _billingAddress.toJson(),
      'shippingAddress': _sameAsBilling ? _billingAddress.toJson() : _shippingAddress.toJson(),
      'placeOfSupply': _placeOfSupply, 'sourceState': _orgState,
      'orderNumber': _orderNumberController.text.trim(),
      'referenceNumber': _referenceNumberController.text.trim(),
      'currency': _currency, 'invoiceDate': _invoiceDate.toIso8601String(),
      'terms': 'Custom', 'dueDate': _dueDate?.toIso8601String(),
      'salesperson': _salesperson, 'subject': _subjectController.text.trim(),
      'items': validItems.map((item) {
        final json = item.toJson();
        // shipmentTrackingNumber is already preserved directly by item.toJson()
        if (json['shipmentTrackingNumber'] == null) {
            final matched = _billableExpenses.firstWhere(
              (e) => e.isSelected && item.itemDetails.startsWith('Expense: ${e.expenseAccount}'),
              orElse: () => BillableExpense(id: '', date: '', expenseAccount: '', amount: 0, tax: 0, total: 0, billableAmount: 0, markupPercentage: 0, paidThrough: ''),
            );
            if (matched.id.isNotEmpty) json['expenseId'] = matched.id;
        }
        return json;
      }).toList(),
      'customerNotes': _customerNotesController.text.trim(),
      'termsAndConditions': _termsConditionsController.text.trim(),
      'invoiceLevelDiscount': _invoiceLevelDiscount,
      'invoiceLevelDiscountType': _invoiceLevelDiscountType,
      'shippingCharges': _shippingCharges, 'adjustment': _adjustment,
      'tdsRate': _enableTDS ? _tdsRate : 0, 'tcsRate': _enableTCS ? _tcsRate : 0,
      'subTotal': _subTotal,
      'taxableTotal': _taxableTotal,
      'totalCGST': _totalCGST,
      'totalSGST': _totalSGST,
      'totalIGST': _totalIGST,
      'totalTax': _totalTax,
      'totalAmount': _totalAmount,
      'invoiceDiscountAmount': _invoiceDiscountAmount,
      'shippingCharges': _shippingCharges,
      'adjustment': _adjustment,
      'status': status,
      if (_selectedPaymentAccount != null) 'selectedPaymentAccount': _selectedPaymentAccount!.toJson(),
      if (qrCodeUrl != null) 'qrCodeUrl': qrCodeUrl,
    };
  }

  // ==========================================================================
  // QR CODE
  // ==========================================================================

  Future<void> _pickQRCode() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (pickedFile != null) {
        setState(() => _qrCodeFileName = pickedFile.name);
        if (kIsWeb) { setState(() => _qrCodeBytes = null); pickedFile.readAsBytes().then((b) => setState(() => _qrCodeBytes = b)); }
        else { setState(() => _qrCodeFile = File(pickedFile.path)); }
        _showSuccess('QR code uploaded');
      }
    } catch (e) { _showError('Failed to upload QR code: $e'); }
  }

  Future<String> _uploadQRCode() async {
    final uri     = Uri.parse('${ApiConfig.baseUrl}/api/finance/invoices/upload/qr-code');
    final request = http.MultipartRequest('POST', uri);
    final prefs   = await SharedPreferences.getInstance();
    final token   = prefs.getString('jwt_token');
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (kIsWeb && _qrCodeBytes != null) {
      request.files.add(http.MultipartFile.fromBytes('qrCode', _qrCodeBytes!, filename: _qrCodeFileName ?? 'qr.png'));
    } else if (_qrCodeFile != null) {
      request.files.add(await http.MultipartFile.fromPath('qrCode', _qrCodeFile!.path, filename: _qrCodeFileName));
    }
    final response = await request.send();
    final data     = json.decode(await response.stream.bytesToString());
    if (response.statusCode == 200) return data['data']['url'];
    throw Exception('Upload failed: ${response.statusCode}');
  }

  // ==========================================================================
  // SNACKBARS
  // ==========================================================================

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: LayoutBuilder(builder: (context, constraints) {
                final isWide = constraints.maxWidth > 900;
                if (isWide) {
                  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: _buildMainContent()),
                    Container(
                      width: 340, color: Colors.white,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          _buildTaxSummarySection(), const Divider(height: 28),
                          _buildAdjustmentsSection(), const Divider(height: 28),
                          _buildTaxTogglesSection(), const Divider(height: 28),
                          _buildSummarySection(),
                        ]),
                      ),
                    ),
                  ]);
                } else {
                  return SingleChildScrollView(child: Column(children: [
                    _buildMainContent(),
                    Container(color: Colors.white, padding: const EdgeInsets.all(20), child: Column(children: [
                      _buildTaxSummarySection(), const Divider(height: 28),
                      _buildAdjustmentsSection(), const Divider(height: 28),
                      _buildTaxTogglesSection(), const Divider(height: 28),
                      _buildSummarySection(),
                    ])),
                  ]));
                }
              }),
            ),
    );
  }

  // ==========================================================================
  // APP BAR
  // ==========================================================================

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_navyDark, _navyMid, _navyLight], begin: Alignment.centerLeft, end: Alignment.centerRight),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent, elevation: 0, foregroundColor: Colors.white,
          title: Text(widget.draftId != null ? 'Edit Staging Draft' : 'New Automation Invoice',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [
            if (widget.draftId != null) ...[
              OutlinedButton.icon(
                onPressed: () => openDocumentPdf(context: context, docId: widget.draftId, pdfEndpoint: '/api/finance/invoices', docNumber: 'Draft'),
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 16), label: const Text('Preview PDF', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => openEmailPreview(context: context, docId: widget.draftId, emailEndpoint: '/api/finance/invoices'),
                icon: const Icon(Icons.email, color: Colors.white, size: 16), label: const Text('Email', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
              ),
              const SizedBox(width: 16),
            ],
            TextButton.icon(onPressed: _isSaving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70, size: 18), label: const Text('Cancel', style: TextStyle(color: Colors.white70))),
            const SizedBox(width: 8),
            if (widget.draftId != null)
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _approveToFinance,
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('Approve to Finance'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _saveAsStagingDraft,
              icon: const Icon(Icons.drafts, size: 18, color: Colors.white70),
              label: const Text('Save as Draft', style: TextStyle(color: Colors.white70)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAsStagingDraft,
              icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save to Staging'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // MAIN CONTENT
  // ==========================================================================

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildCustomerSection(), const SizedBox(height: 20),
        _buildInvoiceDetailsSection(), const SizedBox(height: 20),
        _buildPlaceOfSupplySection(), const SizedBox(height: 20),
        _buildAddressSection(), const SizedBox(height: 20),
        _buildItemsSection(), const SizedBox(height: 20),
        _buildUnbilledExpensesSection(), const SizedBox(height: 20),
        _buildNotesSection(), const SizedBox(height: 20),
      ]),
    );
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))]),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Container(padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [_navyDark, _navyLight]), borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, color: Colors.white, size: 18)),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  // ==========================================================================
  // CUSTOMER SECTION
  // ==========================================================================

  Widget _buildCustomerSection() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Customer Information', Icons.person_outline),
      const SizedBox(height: 16),
      InkWell(
        onTap: _showCustomerSelector,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.person_outline, color: _navyAccent), const SizedBox(width: 12),
            Expanded(child: Text(_selectedCustomerName ?? 'Select Customer *',
                style: TextStyle(fontSize: 15, color: _selectedCustomerName != null ? _navyDark : Colors.grey[600],
                    fontWeight: _selectedCustomerName != null ? FontWeight.w600 : FontWeight.normal))),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ]),
        ),
      ),
      if (_selectedCustomerEmail != null) ...[
        const SizedBox(height: 10),
        Row(children: [const Icon(Icons.email_outlined, size: 16, color: Colors.grey), const SizedBox(width: 6), Text(_selectedCustomerEmail!, style: TextStyle(color: Colors.grey[700], fontSize: 13))]),
      ],
      if (_customerGSTIN.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.business, size: 16, color: Colors.grey), const SizedBox(width: 6),
          Text('GSTIN: $_customerGSTIN', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          if (_customerPAN.isNotEmpty) ...[const SizedBox(width: 16), Text('PAN: $_customerPAN', style: TextStyle(color: Colors.grey[700], fontSize: 13))],
        ]),
      ],
      if (_gstRegistrationType.isNotEmpty) ...[
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _navyAccent.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
          child: Text(_gstRegistrationType, style: TextStyle(fontSize: 12, color: _navyMid, fontWeight: FontWeight.w500))),
      ],
    ]));
  }

  // ==========================================================================
  // INVOICE DETAILS SECTION
  // ==========================================================================

  Widget _buildInvoiceDetailsSection() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Invoice Details', Icons.receipt_long),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (ctx, cs) {
        final isWide = cs.maxWidth > 600;
        final orderField = TextFormField(controller: _orderNumberController,
          decoration: InputDecoration(labelText: 'Order Number', hintText: 'Optional',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.numbers)));
        final refField = TextFormField(controller: _referenceNumberController,
          decoration: InputDecoration(labelText: 'Reference # / PO Number', hintText: 'Optional',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.tag)));
        return isWide ? Row(children: [Expanded(child: orderField), const SizedBox(width: 16), Expanded(child: refField)])
            : Column(children: [orderField, const SizedBox(height: 16), refField]);
      }),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (ctx, cs) {
        final isWide = cs.maxWidth > 600;
        final dateField = InkWell(
          onTap: () async {
            final date = await showDatePicker(context: context, initialDate: _invoiceDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (date != null) setState(() {
              _invoiceDate = date;
              _dueDate = date;
            });
          },
          child: InputDecorator(decoration: InputDecoration(labelText: 'Invoice Date *', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.calendar_today)),
            child: Text(DateFormat('dd MMM yyyy').format(_invoiceDate))),
        );
        return isWide
            ? Row(children: [Expanded(child: dateField)])
            : dateField;
      }),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (ctx, cs) {
        final isWide = cs.maxWidth > 600;
        final dueDateField = InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _dueDate ?? _invoiceDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (date != null) setState(() => _dueDate = date);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Due Date *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.event),
            ),
            child: Text(
              _dueDate != null ? DateFormat('dd MMM yyyy').format(_dueDate!) : 'Select due date',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: _dueDate != null ? null : Colors.grey[600],
              ),
            ),
          ),
        );
        final currencyField2 = DropdownButtonFormField<String>(value: _currency,
          decoration: InputDecoration(labelText: 'Currency', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.currency_rupee)),
          items: _currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _currency = v!));
        return isWide
            ? Row(children: [Expanded(child: dueDateField), const SizedBox(width: 16), Expanded(child: currencyField2)])
            : Column(children: [dueDateField, const SizedBox(height: 16), currencyField2]);
      }),
      const SizedBox(height: 16),
      TextFormField(controller: _subjectController,
        decoration: InputDecoration(labelText: 'Subject', hintText: 'Optional',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.subject)),
        maxLines: 2),
    ]));
  }

  // ==========================================================================
  // PLACE OF SUPPLY SECTION
  // ==========================================================================

  Widget _buildPlaceOfSupplySection() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Place of Supply', Icons.location_on_outlined),
      const SizedBox(height: 8),
      Text('Determines CGST+SGST (same state as org) or IGST (different state)',
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        value: _placeOfSupply.isNotEmpty ? _placeOfSupply : null,
        decoration: InputDecoration(labelText: 'Place of Supply',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), prefixIcon: const Icon(Icons.place)),
        hint: const Text('Select State'),
        items: kIndianStates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (v) { setState(() => _placeOfSupply = v ?? ''); _updateInterState(); },
      ),
      if (_placeOfSupply.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isInterState ? Colors.orange[50] : Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _isInterState ? Colors.orange[300]! : Colors.green[300]!),
          ),
          child: Row(children: [
            Icon(_isInterState ? Icons.swap_horiz : Icons.check_circle_outline,
                color: _isInterState ? Colors.orange[700] : Colors.green[700]),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _isInterState
                  ? 'Inter-State: IGST will be applied ($_placeOfSupply ≠ ${_orgState.isNotEmpty ? _orgState : 'Org State'})'
                  : 'Intra-State: CGST + SGST will be applied',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                  color: _isInterState ? Colors.orange[900] : Colors.green[900]),
            )),
          ]),
        ),
      ],
    ]));
  }

  // ==========================================================================
  // ADDRESS SECTION
  // ==========================================================================

  Widget _buildAddressSection() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Billing & Shipping Address', Icons.location_city),
      const SizedBox(height: 16),
      if (!_billingAddress.isEmpty) ...[
        Text('Billing Address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
        const SizedBox(height: 6),
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
          child: Text(_billingAddress.formatted, style: TextStyle(fontSize: 13, color: Colors.grey[800]))),
        const SizedBox(height: 16),
      ],
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Ship To', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
        Row(children: [
          Text('Same as Billing', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Switch(value: _sameAsBilling, activeColor: _navyAccent,
            onChanged: (v) => setState(() { _sameAsBilling = v; if (v) _shippingAddress = _billingAddress; })),
        ]),
      ]),
      if (!_sameAsBilling) ...[
        const SizedBox(height: 12),
        _buildAddressFields(label: 'Shipping Address', address: _shippingAddress, onChanged: (addr) => setState(() => _shippingAddress = addr)),
      ] else ...[
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
          child: Text(
            _billingAddress.isEmpty ? 'No billing address — select a customer to auto-fill' : _billingAddress.formatted,
            style: TextStyle(fontSize: 13, color: _billingAddress.isEmpty ? Colors.grey[500] : Colors.grey[800], fontStyle: _billingAddress.isEmpty ? FontStyle.italic : FontStyle.normal))),
      ],
    ]));
  }

  Widget _buildAddressFields({required String label, required CustomerAddress address, required ValueChanged<CustomerAddress> onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
      const SizedBox(height: 8),
      TextFormField(initialValue: address.street,
        decoration: InputDecoration(labelText: 'Street', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
        onChanged: (v) => onChanged(address.copyWith(street: v))),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(initialValue: address.city,
          decoration: InputDecoration(labelText: 'City', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(address.copyWith(city: v)))),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(initialValue: address.state,
          decoration: InputDecoration(labelText: 'State', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(address.copyWith(state: v)))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(initialValue: address.zip,
          decoration: InputDecoration(labelText: 'PIN/ZIP', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(address.copyWith(zip: v)))),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(initialValue: address.country,
          decoration: InputDecoration(labelText: 'Country', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(address.copyWith(country: v)))),
      ]),
    ]);
  }

  // ==========================================================================
  // ██ ITEMS SECTION — HORIZONTAL SCROLLABLE TABLE ██
  // ==========================================================================

  Widget _buildItemsSection() {
    final bool isInterState = _isInterState;

    final double tableWidth = _colNo + _colDesc + _colHsn + _colUnit + _colQty +
        _colRate + _colDisc + _colGst + _colTaxable + _colTax1 +
        (isInterState ? 0 : _colTax2) + _colAmt + _colDel;

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section header row
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _sectionTitle('Items', Icons.list_alt),
          if (_placeOfSupply.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isInterState ? Colors.orange[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isInterState ? Colors.orange[300]! : Colors.blue[300]!),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isInterState ? Icons.swap_horiz : Icons.check_circle_outline,
                    size: 14, color: isInterState ? Colors.orange[700] : Colors.blue[700]),
                const SizedBox(width: 5),
                Text(isInterState ? 'IGST' : 'CGST + SGST',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                        color: isInterState ? Colors.orange[800] : Colors.blue[800])),
              ]),
            ),
        ]),
        const SizedBox(height: 14),

        // Scrollable table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Table header ──────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: _navyDark,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                ),
                child: Row(children: [
                  _thCell('#',           _colNo),
                  _thCell('DESCRIPTION', _colDesc),
                  _thCell('HSN / SAC',   _colHsn),
                  _thCell('UNIT',        _colUnit),
                  _thCell('QTY',         _colQty,     align: TextAlign.center),
                  _thCell('RATE (₹)',    _colRate,    align: TextAlign.right),
                  _thCell('DISCOUNT',    _colDisc,    align: TextAlign.right),
                  _thCell('GST %',       _colGst,     align: TextAlign.center),
                  _thCell('TAXABLE',     _colTaxable, align: TextAlign.right),
                  if (isInterState)
                    _thCell('IGST',      _colTax1,    align: TextAlign.right)
                  else ...[
                    _thCell('CGST',      _colTax1,    align: TextAlign.right),
                    _thCell('SGST',      _colTax2,    align: TextAlign.right),
                  ],
                  _thCell('AMOUNT',      _colAmt,     align: TextAlign.right),
                  SizedBox(width: _colDel),
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
                      left: BorderSide(color: Colors.grey[200]!),
                      right: BorderSide(color: Colors.grey[200]!),
                      bottom: BorderSide(color: Colors.grey[200]!),
                    ),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.inbox_outlined, size: 20, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text('No items — click Add Item below', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ]),
                )
              else
                ...List.generate(_items.length, (i) => _buildItemTableRow(i, isInterState)),

              // ── Add Item row ──────────────────────────────────────────────
              InkWell(
                onTap: _addNewItem,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                child: Container(
                  width: tableWidth,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _navyAccent.withOpacity(0.05),
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                    border: Border(
                      left: BorderSide(color: _navyAccent.withOpacity(0.25)),
                      right: BorderSide(color: _navyAccent.withOpacity(0.25)),
                      bottom: BorderSide(color: _navyAccent.withOpacity(0.25)),
                    ),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_circle_outline, size: 18, color: _navyAccent),
                    const SizedBox(width: 8),
                    Text('+ Add Item', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navyAccent)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Table header cell ─────────────────────────────────────────────────────
  Widget _thCell(String text, double width, {TextAlign align = TextAlign.left}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(text, textAlign: align,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
      ),
    );
  }

  // ── Single data row ───────────────────────────────────────────────────────
  // KEY CHANGE: Description TextFormField now uses controller from _descControllers[index]
  // with maxLines: null so Enter key creates a new line within the same cell.
  Widget _buildItemTableRow(int index, bool isInterState) {
    final item    = _items[index];
    final isOdd   = index.isOdd;
    final descCtrl = _descControllers[index];

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
          SizedBox(width: _colNo,
            child: Center(child: Text('${index + 1}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)))),

          // ── DESCRIPTION — multiline, Enter = new line ──────────────────
          SizedBox(width: _colDesc,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                controller: descCtrl,
                // maxLines: null → unlimited lines; Enter key inserts newline
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: _cellDecoration('Item / Service'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                onChanged: (v) => setState(() => item.itemDetails = v),
              ))),

          // HSN / SAC
          SizedBox(width: _colHsn,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.hsnCode.isNotEmpty ? item.hsnCode : item.sacCode,
                decoration: _cellDecoration('HSN/SAC'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                onChanged: (v) => setState(() { item.hsnCode = v; item.sacCode = v; }),
              ))),

          // Unit
          SizedBox(width: _colUnit,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: DropdownButtonFormField<String>(
                value: item.unit.isNotEmpty ? item.unit : 'Nos',
                decoration: _cellDecoration(null),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                isDense: true,
                items: {..._kUnits, if (item.unit.isNotEmpty) item.unit}.toList()
                    .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13, color: Colors.black87)))).toList(),
                onChanged: (v) => setState(() => item.unit = v ?? 'Nos'),
              ))),

          // Qty
          SizedBox(width: _colQty,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.quantity > 0 ? item.quantity.toString() : '',
                decoration: _cellDecoration('0'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                onChanged: (v) { setState(() { item.quantity = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
              ))),

          // Rate
          SizedBox(width: _colRate,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
                decoration: _cellDecoration('0.00'),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) { setState(() { item.rate = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
              ))),

          // Discount + % / ₹ toggle
          SizedBox(width: _colDisc,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(children: [
                Expanded(child: TextFormField(
                  initialValue: item.discount > 0 ? item.discount.toString() : '',
                  decoration: _cellDecoration('0'),
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) { setState(() { item.discount = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
                )),
                PopupMenuButton<String>(
                  initialValue: item.discountType,
                  padding: EdgeInsets.zero,
                  icon: Text(item.discountType == 'percentage' ? '%' : '₹',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyAccent)),
                  onSelected: (v) => setState(() { item.discountType = v; _calculateAmounts(); }),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'percentage', child: Text('% Percentage')),
                    const PopupMenuItem(value: 'amount',     child: Text('₹ Flat Amount')),
                  ],
                ),
              ]))),

          // GST % — default 18
          SizedBox(width: _colGst,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: DropdownButtonFormField<double>(
                value: _kGstRates.contains(item.itemGstRate) ? item.itemGstRate : 18.0,
                decoration: _cellDecoration(null),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                isDense: true,
                items: _kGstRates.map((r) => DropdownMenuItem(
                    value: r, child: Text('${r.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, color: Colors.black87)))).toList(),
                onChanged: (v) { setState(() { item.itemGstRate = v ?? 18.0; _calculateAmounts(); }); },
              ))),

          // Taxable (read-only)
          SizedBox(width: _colTaxable,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(item.taxableAmount > 0 ? '₹${item.taxableAmount.toStringAsFixed(2)}' : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87)))),

          // CGST or IGST
          SizedBox(width: _colTax1,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  isInterState
                      ? (item.igstAmount > 0 ? '₹${item.igstAmount.toStringAsFixed(2)}' : '—')
                      : (item.cgstAmount > 0 ? '₹${item.cgstAmount.toStringAsFixed(2)}' : '—'),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                      color: isInterState ? Colors.orange[700] : Colors.blue[700]),
                ),
                if (item.itemGstRate > 0)
                  Text(isInterState ? '${item.itemGstRate.toStringAsFixed(0)}%' : '${(item.itemGstRate / 2).toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ]))),

          // SGST (intra-state only)
          if (!isInterState)
            SizedBox(width: _colTax2,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(item.sgstAmount > 0 ? '₹${item.sgstAmount.toStringAsFixed(2)}' : '—',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.blue[700])),
                  if (item.itemGstRate > 0)
                    Text('${(item.itemGstRate / 2).toStringAsFixed(1)}%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                ]))),

          // Amount (read-only)
          SizedBox(width: _colAmt,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(item.amount > 0 ? '₹${item.amount.toStringAsFixed(2)}' : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)))),

          // Delete
          SizedBox(width: _colDel,
            child: Center(child: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _removeItem(index),
            ))),
        ]),
      ),
    );
  }

  // ── Compact cell input decoration ─────────────────────────────────────────
  InputDecoration _cellDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _navyAccent, width: 1.5)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  // ==========================================================================
  // UNBILLED EXPENSES
  // ==========================================================================

  Widget _buildUnbilledExpensesSection() {
    if (_selectedCustomerName == null) return const SizedBox.shrink();
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Unbilled Expenses', Icons.receipt_outlined),
      const SizedBox(height: 4),
      Text('Billable expenses for $_selectedCustomerName not yet invoiced', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      const SizedBox(height: 16),
      if (_isLoadingExpenses) const Center(child: CircularProgressIndicator())
      else if (_billableExpenses.isEmpty)
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
          child: Row(children: [Icon(Icons.check_circle_outline, color: Colors.grey[400]), const SizedBox(width: 12), Text('No unbilled expenses', style: TextStyle(color: Colors.grey[600]))]))
      else
        ListView.separated(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: _billableExpenses.length, separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final exp = _billableExpenses[index];
            return InkWell(
              onTap: () { setState(() {
                exp.isSelected = !exp.isSelected;
                if (exp.isSelected) {
                  _items.add(InvoiceItem(
                    itemDetails: 'Expense: ${exp.expenseAccount}${exp.vendor != null ? ' (${exp.vendor})' : ''}',
                    quantity: 1, rate: exp.billableAmount, amount: exp.billableAmount, itemGstRate: 18,
                  ));
                  _descControllers.add(TextEditingController(
                    text: 'Expense: ${exp.expenseAccount}${exp.vendor != null ? ' (${exp.vendor})' : ''}'));
                  _calculateAmounts();
                } else {
                  final idx = _items.indexWhere((i) => i.itemDetails.startsWith('Expense: ${exp.expenseAccount}'));
                  if (idx != -1) {
                    _descControllers[idx].dispose();
                    _descControllers.removeAt(idx);
                    _items.removeAt(idx);
                    _calculateAmounts();
                  }
                }
              }); },
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Row(children: [
                  Checkbox(value: exp.isSelected, activeColor: _navyAccent, onChanged: (val) => setState(() => exp.isSelected = val ?? false)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(exp.expenseAccount, style: const TextStyle(fontWeight: FontWeight.w600, color: _navyDark, fontSize: 13)),
                    if (exp.vendor != null) Text(exp.vendor!, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ])),
                  Text('₹${exp.billableAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: _navyDark)),
                ])),
            );
          },
        ),
    ]));
  }

  // ==========================================================================
  // NOTES SECTION
  // ==========================================================================

  Widget _buildNotesSection() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Additional Information', Icons.note_alt),
      const SizedBox(height: 16),
      TextFormField(controller: _customerNotesController,
        decoration: InputDecoration(labelText: 'Customer Notes', hintText: 'Visible on invoice',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), alignLabelWithHint: true), maxLines: 3),
      const SizedBox(height: 16),
      TextFormField(controller: _termsConditionsController,
        decoration: InputDecoration(labelText: 'Terms & Conditions',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), alignLabelWithHint: true), maxLines: 3),
    ]));
  }

  // ==========================================================================
  // TAX SUMMARY SECTION (Sidebar)
  // ==========================================================================

  Widget _buildTaxSummarySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Tax Summary', Icons.calculate),
      const SizedBox(height: 12),
      if (_taxSlabs.isEmpty)
        Text('Tax will appear here when items with GST are added', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic))
      else ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFF0D1B3E), borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            Expanded(child: const Text('Taxable Amt', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
            if (_isInterState)
              SizedBox(width: 80, child: const Text('IGST', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right))
            else ...[
              SizedBox(width: 60, child: const Text('CGST', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
              SizedBox(width: 60, child: const Text('SGST', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
            ],
            SizedBox(width: 70, child: const Text('Total Tax', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          ]),
        ),
        for (final slab in _taxSlabs)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('@${slab.gstRate.toStringAsFixed(0)}% GST', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text('₹${slab.taxableAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87))),
                if (_isInterState)
                  SizedBox(width: 80, child: Text('₹${slab.igst.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.black87), textAlign: TextAlign.right))
                else ...[
                  SizedBox(width: 60, child: Text('₹${slab.cgst.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.black87), textAlign: TextAlign.right)),
                  SizedBox(width: 60, child: Text('₹${slab.sgst.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.black87), textAlign: TextAlign.right)),
                ],
                SizedBox(width: 70, child: Text('₹${slab.totalTax.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87), textAlign: TextAlign.right)),
              ]),
            ]),
          ),
      ],
    ]);
  }

  // ==========================================================================
  // ADJUSTMENTS SECTION (Sidebar)
  // ==========================================================================

  Widget _buildAdjustmentsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Adjustments', Icons.tune),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: TextFormField(
          initialValue: _invoiceLevelDiscount > 0 ? _invoiceLevelDiscount.toString() : '',
          decoration: InputDecoration(labelText: 'Invoice Discount',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) { setState(() { _invoiceLevelDiscount = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
        )),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          initialValue: _invoiceLevelDiscountType,
          icon: Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
            child: Text(_invoiceLevelDiscountType == 'percentage' ? '%' : '₹', style: const TextStyle(fontWeight: FontWeight.bold, color: _navyAccent))),
          onSelected: (v) => setState(() { _invoiceLevelDiscountType = v; _calculateAmounts(); }),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'percentage', child: Text('% Percentage')),
            const PopupMenuItem(value: 'amount',     child: Text('₹ Flat Amount')),
          ],
        ),
      ]),
      const SizedBox(height: 12),
      TextFormField(controller: _shippingChargesController,
        decoration: InputDecoration(labelText: 'Shipping Charges',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixText: '₹ ', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => _calculateAmounts()),
      const SizedBox(height: 12),
      TextFormField(controller: _adjustmentController,
        decoration: InputDecoration(labelText: 'Adjustment (+ or -)', hintText: 'e.g. -50 or +100',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        onChanged: (_) => _calculateAmounts()),
    ]);
  }

  // ==========================================================================
  // TAX TOGGLES (TDS / TCS)
  // ==========================================================================

  Widget _buildTaxTogglesSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('TDS / TCS', Icons.percent),
      const SizedBox(height: 12),
      SwitchListTile(title: const Text('Enable TDS'), subtitle: const Text('Tax Deducted at Source', style: TextStyle(fontSize: 11)),
        value: _enableTDS, activeColor: _navyAccent, contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() { _enableTDS = v; _calculateAmounts(); })),
      if (_enableTDS) ...[
        const SizedBox(height: 8),
        TextFormField(initialValue: _tdsRate.toString(),
          decoration: InputDecoration(labelText: 'TDS Rate (%)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixText: '%', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() { _tdsRate = double.tryParse(v) ?? 0; _calculateAmounts(); })),
      ],
      const SizedBox(height: 8),
      SwitchListTile(title: const Text('Enable TCS'), subtitle: const Text('Tax Collected at Source', style: TextStyle(fontSize: 11)),
        value: _enableTCS, activeColor: _navyAccent, contentPadding: EdgeInsets.zero,
        onChanged: (v) => setState(() { _enableTCS = v; _calculateAmounts(); })),
      if (_enableTCS) ...[
        const SizedBox(height: 8),
        TextFormField(initialValue: _tcsRate.toString(),
          decoration: InputDecoration(labelText: 'TCS Rate (%)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixText: '%', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() { _tcsRate = double.tryParse(v) ?? 0; _calculateAmounts(); })),
      ],
    ]);
  }

  // ==========================================================================
  // SUMMARY SECTION (Sidebar)
  // ==========================================================================

  Widget _buildSummarySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Invoice Summary', Icons.summarize),
      const SizedBox(height: 16),
      _summaryRow('Sub Total', _subTotal),
      if (_invoiceDiscountAmount > 0) ...[
        const SizedBox(height: 6),
        _summaryRow('Discount (${_invoiceLevelDiscountType == 'percentage' ? '${_invoiceLevelDiscount}%' : '₹$_invoiceLevelDiscount'})', -_invoiceDiscountAmount, color: Colors.red[700]),
        const SizedBox(height: 6),
        _summaryRow('Taxable Total', _taxableTotal),
      ],
      const SizedBox(height: 6),
      if (_isInterState) ...[
        if (_totalIGST > 0) _summaryRow('IGST', _totalIGST),
      ] else ...[
        if (_totalCGST > 0) _summaryRow('CGST', _totalCGST),
        const SizedBox(height: 6),
        if (_totalSGST > 0) _summaryRow('SGST', _totalSGST),
      ],
      if (_totalTax > 0) ...[const SizedBox(height: 6), _summaryRow('Total Tax', _totalTax)],
      if (_enableTDS && _tdsAmount > 0) ...[const SizedBox(height: 6), _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)', -_tdsAmount, color: Colors.red[700])],
      if (_enableTCS && _tcsAmount > 0) ...[const SizedBox(height: 6), _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmount)],
      if (_shippingCharges > 0) ...[const SizedBox(height: 6), _summaryRow('Shipping', _shippingCharges)],
      if (_adjustment != 0) ...[const SizedBox(height: 6), _summaryRow('Adjustment', _adjustment, color: _adjustment < 0 ? Colors.red[700] : null)],
      const Divider(thickness: 2),
      const SizedBox(height: 6),
      _summaryRow('Total Amount', _totalAmount, isBold: true, isTotal: true),
      const SizedBox(height: 24),
      if (widget.draftId != null) ...[
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _approveToFinance,
          icon: const Icon(Icons.check_circle), label: const Text('Approve to Finance'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
        const SizedBox(height: 10),
      ],
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveAsStagingDraft,
        icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
        label: Text(_isSaving ? 'Saving...' : 'Save to Staging'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: _isSaving ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close), label: const Text('Cancel'),
        style: OutlinedButton.styleFrom(foregroundColor: _navyMid, padding: const EdgeInsets.symmetric(vertical: 16), side: BorderSide(color: _navyMid), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))),
    ]);
  }

  Widget _summaryRow(String label, double amount, {Color? color, bool isBold = false, bool isTotal = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: isTotal ? 15 : 13, fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal, color: color ?? (isTotal ? _navyDark : Colors.grey[700]))),
      Text('${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}', style: TextStyle(fontSize: isTotal ? 17 : 13, fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.w500, color: color ?? (isTotal ? _navyAccent : _navyDark))),
    ]);
  }

  // ==========================================================================
  // CUSTOMER SELECTOR DIALOG
  // ==========================================================================

  Future<void> _showCustomerSelector() async {
    final searchController = TextEditingController();
    List<BillingCustomer> customers = [];
    List<BillingCustomer> filtered  = [];
    bool isLoading = true;
    String? errorMessage;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialog) {
        if (isLoading && customers.isEmpty) {
          InvoiceService.getBillingCustomers().then((response) {
            setDialog(() { customers = response.customers; filtered = customers; isLoading = false; });
          }).catchError((e) { setDialog(() { errorMessage = e.toString(); isLoading = false; }); });
        }
        return AlertDialog(
          title: const Text('Select Customer'),
          content: SizedBox(width: 520, height: 440, child: Column(children: [
            TextField(
              controller: searchController,
              decoration: InputDecoration(hintText: 'Search customers...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onChanged: (v) { setDialog(() { filtered = v.isEmpty ? customers : customers.where((c) =>
                c.customerName.toLowerCase().contains(v.toLowerCase()) ||
                c.customerEmail.toLowerCase().contains(v.toLowerCase()) ||
                c.companyName.toLowerCase().contains(v.toLowerCase())).toList(); }); },
            ),
            const SizedBox(height: 12),
            Expanded(child: isLoading ? const Center(child: CircularProgressIndicator())
              : errorMessage != null ? Center(child: Text('Error: $errorMessage'))
              : filtered.isEmpty ? const Center(child: Text('No customers found'))
              : ListView.builder(itemCount: filtered.length, itemBuilder: (context, index) {
                  final customer = filtered[index];
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: _navyAccent,
                      child: Text(customer.customerName.isNotEmpty ? customer.customerName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                    title: Text(customer.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(customer.customerEmail),
                      if (customer.companyName.isNotEmpty) Text(customer.companyName, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (customer.gstNumber.isNotEmpty) Text('GSTIN: ${customer.gstNumber}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ]),
                    onTap: () {
                      setState(() {
                        _selectedCustomerId    = customer.id;
                        _selectedCustomerName  = customer.customerName;
                        _selectedCustomerEmail = customer.customerEmail;
                        _selectedCustomerPhone = customer.customerPhone;
                        _customerGSTIN         = customer.gstNumber;
                        _customerPAN           = customer.panNumber;
                        _gstRegistrationType   = customer.gstRegistrationType;
                        _billingAddress        = customer.billingAddress;
                        if (customer.shippingAddress.isEmpty) {
                          _shippingAddress = customer.billingAddress; _sameAsBilling = true;
                        } else {
                          _shippingAddress = customer.shippingAddress;
                          _sameAsBilling = customer.billingAddress.formatted == customer.shippingAddress.formatted;
                        }
                        if (customer.placeOfSupply.isNotEmpty) { _placeOfSupply = customer.placeOfSupply; }
                        else if (customer.billingAddress.state.isNotEmpty) { _placeOfSupply = customer.billingAddress.state; }
                        if (customer.defaultCurrency.isNotEmpty && _currencies.contains(customer.defaultCurrency)) { _currency = customer.defaultCurrency; }
                      });
                      _updateInterState();
                      _calculateAmounts();
                      Navigator.pop(context);
                      _loadBillableExpenses(customer.customerName);
                    },
                  );
                })),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const NewCustomerPage())); },
              icon: const Icon(Icons.add), label: const Text('Add New Customer'),
              style: OutlinedButton.styleFrom(foregroundColor: _navyAccent, side: const BorderSide(color: _navyAccent)))),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
        );
      }),
    );
  }
}