import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// NEW PURCHASE ORDER SCREEN
// ============================================================================
// File: lib/screens/billing/new_purchase_order.dart
//
// UI matches new_payment_made.dart EXACTLY:
// ✅ Gradient AppBar (_navyDark → _navyMid → _navyLight)
// ✅ Gradient icon box section titles (_sectionTitle) inside _buildCard
// ✅ Desktop (>800px): left main (flex 3) + right 320px white sidebar
// ✅ Mobile (≤800px): stacked column layout
// ✅ Sidebar: Tax Settings + Summary + Save buttons
// ✅ Gradient table header for items
// ✅ Card: borderRadius 10, shadow offset (0,3), 0.05 opacity
// ✅ Gradient info box in summary
// ✅ Vendor selector dialog with navy styling + error/retry state
//
// FUNCTIONALITY: fully preserved, zero changes to logic
// ✅ Save as Draft / Save & Send
// ✅ Vendor selector with search + Add New Vendor
// ✅ PO details (date, payment terms, delivery date, etc.)
// ✅ Items (add/remove, qty, rate, discount, amount)
// ✅ GST / TDS / TCS toggles with live recalculation
// ✅ Notes (vendor notes, terms & conditions)
// ✅ Edit mode via purchaseOrderId
// ✅ All PurchaseOrderService + BillingVendorsService calls unchanged
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../core/services/purchase_order_service.dart';
import '../../../core/services/billing_vendors_service.dart';
import 'new_vendor.dart';
import '../widgets/document_preview_buttons.dart';
import '../../../app/config/api_config.dart';

// Navy gradient colors — exact match to new_payment_made.dart
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green = Color(0xFF27AE60);

// Column widths for items table (same as new_invoice.dart)
const double _colNo = 36.0;
const double _colDesc = 200.0;
const double _colHsn = 110.0;
const double _colUnit = 80.0;
const double _colQty = 70.0;
const double _colRate = 95.0;
const double _colDisc = 110.0;
const double _colGst = 80.0;
const double _colTaxable = 100.0;
const double _colTax1 = 90.0;
const double _colAmt = 95.0;
const double _colDel = 44.0;

const List<double> _kGstRates = [0, 5, 12, 18, 28];
const List<String> _kUnits = [
  'Nos',
  'Hrs',
  'Kg',
  'Pcs',
  'Box',
  'Mtr',
  'Ltr',
  'Dz',
  'MT',
  'Set'
];

const List<String> kPoIndianStates = [
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chhattisgarh',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
  'Andaman and Nicobar Islands',
  'Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Jammu and Kashmir',
  'Ladakh',
  'Lakshadweep',
  'Puducherry',
];

class _PoAddress {
  String attention;
  String street;
  String city;
  String state;
  String zip;
  String country;
  String phone;
  _PoAddress(
      {this.attention = '',
      this.street = '',
      this.city = '',
      this.state = '',
      this.zip = '',
      this.country = 'India',
      this.phone = ''});
  Map<String, dynamic> toJson() => {
        'attention': attention,
        'street': street,
        'city': city,
        'state': state,
        'zip': zip,
        'country': country,
        'phone': phone,
      };
  factory _PoAddress.fromJson(Map<String, dynamic>? j) {
    if (j == null) return _PoAddress();
    return _PoAddress(
      attention: j['attention']?.toString() ?? '',
      street: j['street']?.toString() ?? '',
      city: j['city']?.toString() ?? '',
      state: j['state']?.toString() ?? '',
      zip: j['zip']?.toString() ?? '',
      country: j['country']?.toString() ?? 'India',
      phone: j['phone']?.toString() ?? '',
    );
  }
  factory _PoAddress.fromMap(Map<String, dynamic> j) => _PoAddress.fromJson(j);
}

// ============================================================================
// SCREEN
// ============================================================================

class NewPurchaseOrderScreen extends StatefulWidget {
  final String? purchaseOrderId;

  const NewPurchaseOrderScreen({Key? key, this.purchaseOrderId})
      : super(key: key);

  @override
  State<NewPurchaseOrderScreen> createState() => _NewPurchaseOrderScreenState();
}

class _NewPurchaseOrderScreenState extends State<NewPurchaseOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Controllers — all unchanged
  final _referenceNumberController = TextEditingController();
  final _subjectController = TextEditingController();
  final _deliveryAddressController = TextEditingController();
  final _shipmentPreferenceController = TextEditingController();
  final _vendorNotesController = TextEditingController();
  final _termsConditionsController = TextEditingController();

  // Form Data
  String? _selectedVendorId;
  String? _selectedVendorName;
  String? _selectedVendorEmail;
  String? _selectedVendorPhone;
  String _selectedVendorGSTIN = '';
  String _selectedVendorPAN = '';
  String _gstRegistrationType = '';
  String? _selectedVendorCompany;
  DateTime _poDate = DateTime.now();
  String _selectedPaymentTerms = 'Net 30';
  DateTime? _expectedDeliveryDate;
  String? _salesperson;

  // Addresses
  _PoAddress _billingAddress = _PoAddress();
  _PoAddress _shippingAddress = _PoAddress();
  bool _sameAsBilling = true;

  // Place of supply
  String _placeOfSupply = '';
  String _orgState = '';
  bool _isInterState = false;

  // Tax Settings
  double _tdsRate = 0;
  double _tcsRate = 0;
  bool _enableTDS = false;
  bool _enableTCS = false;

  // Items
  List<PurchaseOrderItem> _items = [];
  final List<TextEditingController> _descControllers = [];

  // Calculations
  double _subTotal = 0;
  double _totalCGST = 0;
  double _totalSGST = 0;
  double _totalIGST = 0;
  double _totalTax = 0;
  double _tdsAmount = 0;
  double _tcsAmount = 0;
  double _totalAmount = 0;
  int _totalQuantity = 0;

  // Dropdown options — unchanged
  final List<String> _paymentTermsOptions = [
    'Due on Receipt',
    'Net 15',
    'Net 30',
    'Net 45',
    'Net 60',
  ];

  // ============================================================================
  @override
  void initState() {
    super.initState();
    _addNewItem();
    _loadOrgState();
    if (widget.purchaseOrderId != null) _loadPurchaseOrderData();
  }

  @override
  void dispose() {
    _referenceNumberController.dispose();
    _subjectController.dispose();
    _deliveryAddressController.dispose();
    _shipmentPreferenceController.dispose();
    _vendorNotesController.dispose();
    _termsConditionsController.dispose();
    for (final c in _descControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ============================================================================
  // CALCULATIONS — unchanged
  // ============================================================================
  // ORG STATE
  // ============================================================================

  Future<void> _loadOrgState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final resp = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/finance/invoices/org-state'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        setState(() => _orgState = body['data']?['state'] ?? '');
        _updateInterState();
      }
    } catch (_) {}
  }

  void _updateInterState() {
    final newVal = _placeOfSupply.isNotEmpty &&
        _orgState.isNotEmpty &&
        _placeOfSupply.toLowerCase() != _orgState.toLowerCase();
    if (newVal != _isInterState) {
      setState(() => _isInterState = newVal);
      _calculateAmounts();
    }
  }

  // ============================================================================
  // CALCULATIONS
  // ============================================================================

  void _calculateAmounts() {
    setState(() {
      _subTotal = 0;
      _totalCGST = 0;
      _totalSGST = 0;
      _totalIGST = 0;
      _totalQuantity = 0;
      for (var item in _items) {
        if (item.quantity > 0 && item.rate > 0) {
          double taxable = item.quantity * item.rate;
          if (item.discount > 0) {
            taxable = item.discountType == 'percentage'
                ? taxable - (taxable * item.discount / 100)
                : taxable - item.discount;
          }
          taxable = double.parse(taxable.toStringAsFixed(2));
          item.taxableAmount = taxable;
          final gst = item.itemGstRate;
          if (_isInterState) {
            item.igstAmount =
                double.parse((taxable * gst / 100).toStringAsFixed(2));
            item.cgstAmount = 0;
            item.sgstAmount = 0;
          } else {
            item.cgstAmount =
                double.parse((taxable * (gst / 2) / 100).toStringAsFixed(2));
            item.sgstAmount = item.cgstAmount;
            item.igstAmount = 0;
          }
          item.amount = double.parse(
              (taxable + item.cgstAmount + item.sgstAmount + item.igstAmount)
                  .toStringAsFixed(2));
          _subTotal += taxable;
          _totalCGST += item.cgstAmount;
          _totalSGST += item.sgstAmount;
          _totalIGST += item.igstAmount;
          _totalQuantity += item.quantity.toInt();
        } else {
          item.taxableAmount = 0;
          item.cgstAmount = 0;
          item.sgstAmount = 0;
          item.igstAmount = 0;
          item.amount = 0;
        }
      }
      _subTotal = double.parse(_subTotal.toStringAsFixed(2));
      _totalCGST = double.parse(_totalCGST.toStringAsFixed(2));
      _totalSGST = double.parse(_totalSGST.toStringAsFixed(2));
      _totalIGST = double.parse(_totalIGST.toStringAsFixed(2));
      _totalTax = double.parse(
          (_totalCGST + _totalSGST + _totalIGST).toStringAsFixed(2));
      _tdsAmount = _enableTDS
          ? double.parse((_subTotal * _tdsRate / 100).toStringAsFixed(2))
          : 0;
      _tcsAmount = _enableTCS
          ? double.parse((_subTotal * _tcsRate / 100).toStringAsFixed(2))
          : 0;
      _totalAmount = double.parse(
          (_subTotal + _totalTax - _tdsAmount + _tcsAmount).toStringAsFixed(2));
    });
  }

  void _addNewItem() {
    setState(() {
      _items.add(PurchaseOrderItem(itemGstRate: 18));
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

  // ============================================================================
  // LOAD / VALIDATE / BUILD — all unchanged
  // ============================================================================

  Future<void> _loadPurchaseOrderData() async {
    setState(() => _isLoading = true);
    try {
      final po =
          await PurchaseOrderService.getPurchaseOrder(widget.purchaseOrderId!);
      setState(() {
        _selectedVendorId = po.vendorId;
        _selectedVendorName = po.vendorName;
        _selectedVendorEmail = po.vendorEmail;
        _selectedVendorGSTIN = po.vendorGSTIN ?? '';
        _selectedVendorPAN = po.vendorPAN ?? '';
        _gstRegistrationType = po.gstRegistrationType ?? '';
        _billingAddress = _PoAddress.fromJson(po.billingAddress.toJson());
        _shippingAddress = _PoAddress.fromJson(po.shippingAddress.toJson());
        _placeOfSupply = po.placeOfSupply ?? '';
        _referenceNumberController.text = po.referenceNumber ?? '';
        _poDate = po.purchaseOrderDate;
        _expectedDeliveryDate = po.expectedDeliveryDate;
        _selectedPaymentTerms = po.paymentTerms;
        _salesperson = po.salesperson;
        _subjectController.text = po.subject ?? '';
        _deliveryAddressController.text = po.deliveryAddress ?? '';
        _shipmentPreferenceController.text = po.shipmentPreference ?? '';
        _vendorNotesController.text = po.vendorNotes ?? '';
        _termsConditionsController.text = po.termsAndConditions ?? '';
        _tdsRate = po.tdsRate;
        _tcsRate = po.tcsRate;
        _enableTDS = po.tdsRate > 0;
        _enableTCS = po.tcsRate > 0;
        _items = po.items
            .map((item) => PurchaseOrderItem(
                  itemDetails: item.itemDetails,
                  quantity: item.quantity,
                  rate: item.rate,
                  discount: item.discount,
                  discountType: item.discountType,
                  amount: item.amount,
                  hsnCode: item.hsnCode,
                  unit: item.unit,
                  itemGstRate: item.itemGstRate,
                ))
            .toList();
        for (final c in _descControllers) {
          c.dispose();
        }
        _descControllers.clear();
        for (final item in _items) {
          _descControllers.add(TextEditingController(text: item.itemDetails));
        }
        _updateInterState();
        _calculateAmounts();
      });
    } catch (e) {
      _showErrorSnackbar('Failed to load purchase order: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _validateItems() {
    final nonEmpty =
        _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      _showErrorSnackbar('Please add at least one item with details');
      return false;
    }
    for (var item in nonEmpty) {
      if (item.quantity <= 0) {
        _showErrorSnackbar('All items must have quantity greater than 0');
        return false;
      }
      if (item.rate <= 0) {
        _showErrorSnackbar('All items must have rate greater than 0');
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _buildPOData(String status) {
    final validItems =
        _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      throw Exception('Please add at least one item with details');
    }
    for (var item in validItems) {
      if (item.quantity <= 0) {
        throw Exception('All items must have quantity greater than 0');
      }
      if (item.rate <= 0) {
        throw Exception('All items must have rate greater than 0');
      }
    }
    return {
      'vendorId': _selectedVendorId,
      'vendorName': _selectedVendorName,
      'vendorEmail': _selectedVendorEmail,
      'vendorPhone': _selectedVendorPhone ?? '',
      'vendorGSTIN': _selectedVendorGSTIN,
      'vendorPAN': _selectedVendorPAN,
      'gstRegistrationType': _gstRegistrationType,
      'billingAddress': _billingAddress.toJson(),
      'shippingAddress':
          _sameAsBilling ? _billingAddress.toJson() : _shippingAddress.toJson(),
      'placeOfSupply': _placeOfSupply,
      'isInterState': _isInterState,
      'referenceNumber': _referenceNumberController.text.trim(),
      'purchaseOrderDate': DateFormat('yyyy-MM-dd').format(_poDate),
      'expectedDeliveryDate': _expectedDeliveryDate != null ? DateFormat('yyyy-MM-dd').format(_expectedDeliveryDate!) : null,
      'paymentTerms': _selectedPaymentTerms,
      'salesperson': _salesperson,
      'subject': _subjectController.text.trim(),
      'deliveryAddress': _deliveryAddressController.text.trim(),
      'shipmentPreference': _shipmentPreferenceController.text.trim(),
      'items': validItems.map((i) => i.toJson()).toList(),
      'vendorNotes': _vendorNotesController.text.trim(),
      'termsAndConditions': _termsConditionsController.text.trim(),
      'tdsRate': _enableTDS ? _tdsRate : 0,
      'tcsRate': _enableTCS ? _tcsRate : 0,
      'subTotal': _subTotal,
      'totalCGST': _totalCGST,
      'totalSGST': _totalSGST,
      'totalIGST': _totalIGST,
      'totalTax': _totalTax,
      'totalAmount': _totalAmount,
      'status': status,
    };
  }

  // ============================================================================
  // SAVE METHODS — all unchanged
  // ============================================================================

  Future<void> _markAsSent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) {
      _showErrorSnackbar('Please select a vendor');
      return;
    }
    if (!_validateItems()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Sent?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'The email will NOT be sent to the vendor.\n\nDo you want to mark this purchase order as Sent (Issued) anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navyDark, foregroundColor: Colors.white),
            child: const Text('Mark as Sent'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _isSaving = true);
    try {
      final poData = _buildPOData('ISSUED');
      PurchaseOrder po;
      if (widget.purchaseOrderId != null) {
        po = await PurchaseOrderService.updatePurchaseOrder(
            widget.purchaseOrderId!, poData);
      } else {
        po = await PurchaseOrderService.createPurchaseOrder(poData);
      }
      await PurchaseOrderService.markAsSent(po.id);
      _showSuccessSnackbar('Purchase order marked as sent');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar(_extractError(e, 'Failed to mark as sent'));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAsDraft() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) {
      _showErrorSnackbar('Please select a vendor');
      return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final poData = _buildPOData('DRAFT');
      if (widget.purchaseOrderId != null) {
        await PurchaseOrderService.updatePurchaseOrder(
            widget.purchaseOrderId!, poData);
      } else {
        await PurchaseOrderService.createPurchaseOrder(poData);
      }
      _showSuccessSnackbar('Purchase order saved as draft');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar(_extractError(e, 'Failed to save purchase order'));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendorId == null) {
      _showErrorSnackbar('Please select a vendor');
      return;
    }
    if (_selectedVendorEmail == null || _selectedVendorEmail!.isEmpty) {
      _showErrorSnackbar('Vendor email is required to send purchase order');
      return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final poData = _buildPOData('ISSUED');
      PurchaseOrder po;
      if (widget.purchaseOrderId != null) {
        po = await PurchaseOrderService.updatePurchaseOrder(
            widget.purchaseOrderId!, poData);
      } else {
        po = await PurchaseOrderService.createPurchaseOrder(poData);
      }
      await PurchaseOrderService.sendPurchaseOrder(po.id);
      _showSuccessSnackbar('Purchase order sent to $_selectedVendorEmail');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar(_extractError(e, 'Failed to send purchase order'));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  String _extractError(dynamic e, String defaultMessage) {
    final errStr = e.toString();
    if (errStr.contains('validation failed')) {
      final match = RegExp(r'Path `(\w+)` is required').firstMatch(errStr);
      if (match != null) {
        return 'Please fill in required field: ${match.group(1)}';
      }
      return 'Please check all required fields';
    }
    return errStr.isNotEmpty ? errStr : defaultMessage;
  }

  // ============================================================================
  // SNACKBARS — unchanged
  // ============================================================================

  void _showErrorSnackbar(String message) =>
      AppSnackbar.show(context, message: message, isError: true);

  void _showSuccessSnackbar(String message) =>
      AppSnackbar.show(context, message: message);

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
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
              widget.purchaseOrderId != null
                  ? 'Edit Purchase Order'
                  : 'New Purchase Order',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            actions: [
              // View PDF
              IconButton(
                tooltip: 'View PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.white70, size: 20),
                onPressed: () {
                  if (widget.purchaseOrderId == null ||
                      widget.purchaseOrderId!.isEmpty) {
                    ScaffoldMessenger.maybeOf(context)
                        ?.showSnackBar(const SnackBar(
                      content:
                          Text('Save the purchase order first to preview PDF'),
                      behavior: SnackBarBehavior.floating,
                    ));
                    return;
                  }
                  openDocumentPdf(
                    context: context,
                    docId: widget.purchaseOrderId,
                    pdfEndpoint: '/api/finance/purchase-orders',
                    docNumber: 'Purchase Order',
                  );
                },
              ),
              // Preview Email
              IconButton(
                tooltip: 'Preview Email',
                icon: const Icon(Icons.email_outlined,
                    color: Colors.white70, size: 20),
                onPressed: () {
                  if (widget.purchaseOrderId == null ||
                      widget.purchaseOrderId!.isEmpty) {
                    ScaffoldMessenger.maybeOf(context)
                        ?.showSnackBar(const SnackBar(
                      content: Text(
                          'Save the purchase order first to preview email'),
                      behavior: SnackBarBehavior.floating,
                    ));
                    return;
                  }
                  openEmailPreview(
                    context: context,
                    docId: widget.purchaseOrderId,
                    emailEndpoint: '/api/finance/purchase-orders',
                  );
                },
              ),
              TextButton.icon(
                onPressed: _isSaving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                label: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 4),
              // Mark as Sent — no email, just status → ISSUED
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _markAsSent,
                icon: const Icon(Icons.mark_email_read_outlined,
                    size: 18, color: Colors.white70),
                label: const Text('Mark as Sent',
                    style: TextStyle(color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _isSaving ? null : _saveAsDraft,
                icon: const Icon(Icons.save_outlined,
                    color: Colors.white70, size: 18),
                label: const Text('Save as Draft',
                    style: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveAndSend,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save & Send'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navyAccent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          _buildVendorSection(),
          const SizedBox(height: 20),
          _buildAddressSection(),
          const SizedBox(height: 20),
          _buildPODetailsSection(),
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

  Widget _buildVendorSection() => _card(
        title: 'Vendor Information',
        icon: Icons.business_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: _showVendorSelector,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                    color: _selectedVendorId == null
                        ? Colors.red.shade300
                        : Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.store_outlined, color: _navyAccent),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                  _selectedVendorName ?? 'Select Vendor *',
                  style: TextStyle(
                    fontSize: 15,
                    color: _selectedVendorName != null
                        ? _navyDark
                        : Colors.grey[600],
                    fontWeight: _selectedVendorName != null
                        ? FontWeight.w600
                        : FontWeight.normal,
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
          if (_selectedVendorPhone != null &&
              _selectedVendorPhone!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.phone_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(_selectedVendorPhone!,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ]),
          ],
          if (_selectedVendorGSTIN.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.business, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text('GSTIN: $_selectedVendorGSTIN',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ]),
          ],
          if (_selectedVendorPAN.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.credit_card_outlined,
                  size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text('PAN: $_selectedVendorPAN',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ]),
          ],
          if (_gstRegistrationType.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _navyAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_gstRegistrationType,
                  style: TextStyle(
                      fontSize: 12,
                      color: _navyMid,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ]),
      );

  // ============================================================================
  // ADDRESS + PLACE OF SUPPLY SECTION
  // ============================================================================

  Widget _buildAddressSection() => _card(
        title: 'Address & Place of Supply',
        icon: Icons.location_on_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Place of Supply
          DropdownButtonFormField<String>(
            value: kPoIndianStates.contains(_placeOfSupply)
                ? _placeOfSupply
                : null,
            decoration: InputDecoration(
              labelText: 'Place of Supply',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.map_outlined),
            ),
            items: kPoIndianStates
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) {
              setState(() => _placeOfSupply = v ?? '');
              _updateInterState();
            },
          ),
          if (_placeOfSupply.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isInterState
                    ? Colors.orange.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _isInterState
                        ? Colors.orange.shade200
                        : Colors.green.shade200),
              ),
              child: Row(children: [
                Icon(
                    _isInterState
                        ? Icons.swap_horiz
                        : Icons.check_circle_outline,
                    size: 14,
                    color: _isInterState
                        ? Colors.orange.shade700
                        : Colors.green.shade700),
                const SizedBox(width: 6),
                Text(
                    _isInterState
                        ? 'Inter-State Supply — IGST applies'
                        : 'Intra-State Supply — CGST + SGST applies',
                    style: TextStyle(
                        fontSize: 12,
                        color: _isInterState
                            ? Colors.orange.shade700
                            : Colors.green.shade700)),
              ]),
            ),
          ],
          const SizedBox(height: 16),

          // Billing Address
          Text('Billing Address',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: _navyDark)),
          const SizedBox(height: 8),
          _buildAddressFields(_billingAddress,
              onChanged: (addr) => setState(() {
                    _billingAddress = addr;
                    if (_sameAsBilling) _shippingAddress = addr;
                  })),
          const SizedBox(height: 12),

          // Same as billing toggle
          Row(children: [
            Checkbox(
              value: _sameAsBilling,
              activeColor: _navyAccent,
              onChanged: (v) => setState(() {
                _sameAsBilling = v ?? true;
                if (_sameAsBilling) _shippingAddress = _billingAddress;
              }),
            ),
            const Text('Shipping address same as billing',
                style: TextStyle(fontSize: 13)),
          ]),

          if (!_sameAsBilling) ...[
            const SizedBox(height: 8),
            Text('Shipping Address',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _navyDark)),
            const SizedBox(height: 8),
            _buildAddressFields(_shippingAddress,
                onChanged: (addr) => setState(() => _shippingAddress = addr)),
          ],
        ]),
      );

  Widget _buildAddressFields(_PoAddress addr,
      {required void Function(_PoAddress) onChanged}) {
    return Column(children: [
      Row(children: [
        Expanded(
            child: TextFormField(
          initialValue: addr.street,
          decoration: InputDecoration(
              labelText: 'Street',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true),
          onChanged: (v) => onChanged(_PoAddress(
              street: v,
              city: addr.city,
              state: addr.state,
              zip: addr.zip,
              country: addr.country)),
        )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: TextFormField(
          initialValue: addr.city,
          decoration: InputDecoration(
              labelText: 'City',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true),
          onChanged: (v) => onChanged(_PoAddress(
              street: addr.street,
              city: v,
              state: addr.state,
              zip: addr.zip,
              country: addr.country)),
        )),
        const SizedBox(width: 8),
        Expanded(
            child: TextFormField(
          initialValue: addr.state,
          decoration: InputDecoration(
              labelText: 'State',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true),
          onChanged: (v) => onChanged(_PoAddress(
              street: addr.street,
              city: addr.city,
              state: v,
              zip: addr.zip,
              country: addr.country)),
        )),
        const SizedBox(width: 8),
        SizedBox(
            width: 100,
            child: TextFormField(
              initialValue: addr.zip,
              decoration: InputDecoration(
                  labelText: 'PIN',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true),
              onChanged: (v) => onChanged(_PoAddress(
                  street: addr.street,
                  city: addr.city,
                  state: addr.state,
                  zip: v,
                  country: addr.country)),
            )),
      ]),
    ]);
  }

  // ============================================================================
  // PO DETAILS SECTION
  // ============================================================================

  Widget _buildPODetailsSection() => _card(
        title: 'Purchase Order Details',
        icon: Icons.description_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Reference Number + PO Date
          LayoutBuilder(builder: (_, cs) {
            final isWide = cs.maxWidth > 600;
            final refField = TextFormField(
              controller: _referenceNumberController,
              decoration: InputDecoration(
                labelText: 'Reference Number',
                hintText: 'Vendor\'s reference / PO Ref',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.numbers),
              ),
            );
            final dateField = InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _poDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) setState(() => _poDate = date);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'PO Date *',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('dd MMM yyyy').format(_poDate)),
              ),
            );
            return isWide
                ? Row(children: [
                    Expanded(child: refField),
                    const SizedBox(width: 16),
                    Expanded(child: dateField),
                  ])
                : Column(children: [
                    refField,
                    const SizedBox(height: 16),
                    dateField,
                  ]);
          }),

          const SizedBox(height: 16),

          // Payment Terms + Expected Delivery Date
          LayoutBuilder(builder: (_, cs) {
            final isWide = cs.maxWidth > 600;
            final termsField = DropdownButtonFormField<String>(
              value: _selectedPaymentTerms,
              decoration: InputDecoration(
                labelText: 'Payment Terms *',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.payment),
              ),
              items: _paymentTermsOptions
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPaymentTerms = v!),
            );
            final deliveryField = InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _expectedDeliveryDate ??
                      DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2030),
                );
                if (date != null) setState(() => _expectedDeliveryDate = date);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Expected Delivery Date',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.local_shipping),
                ),
                child: Text(
                  _expectedDeliveryDate != null
                      ? DateFormat('dd MMM yyyy').format(_expectedDeliveryDate!)
                      : 'Select date',
                  style: TextStyle(
                    color: _expectedDeliveryDate != null
                        ? _navyDark
                        : Colors.grey[600],
                  ),
                ),
              ),
            );
            return isWide
                ? Row(children: [
                    Expanded(child: termsField),
                    const SizedBox(width: 16),
                    Expanded(child: deliveryField),
                  ])
                : Column(children: [
                    termsField,
                    const SizedBox(height: 16),
                    deliveryField,
                  ]);
          }),

          const SizedBox(height: 16),

          // Shipment Preference + Salesperson
          LayoutBuilder(builder: (_, cs) {
            final isWide = cs.maxWidth > 600;
            final shipField = TextFormField(
              controller: _shipmentPreferenceController,
              decoration: InputDecoration(
                labelText: 'Shipment Preference',
                hintText: 'e.g. Standard, Express',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.local_shipping_outlined),
              ),
            );
            final salesField = TextFormField(
              initialValue: _salesperson,
              decoration: InputDecoration(
                labelText: 'Salesperson',
                hintText: 'Optional',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.person_outline),
              ),
              onChanged: (v) => _salesperson = v,
            );
            return isWide
                ? Row(children: [
                    Expanded(child: shipField),
                    const SizedBox(width: 16),
                    Expanded(child: salesField),
                  ])
                : Column(children: [
                    shipField,
                    const SizedBox(height: 16),
                    salesField,
                  ]);
          }),

          const SizedBox(height: 16),

          // Delivery Address — full width
          TextFormField(
            controller: _deliveryAddressController,
            decoration: InputDecoration(
              labelText: 'Delivery Address',
              hintText: 'Address where goods should be delivered',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.location_on_outlined),
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 16),

          // Subject — full width
          TextFormField(
            controller: _subjectController,
            decoration: InputDecoration(
              labelText: 'Subject',
              hintText: 'Optional',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.subject),
            ),
          ),
        ]),
      );

  // ============================================================================
  // ITEMS SECTION
  // ============================================================================

  Widget _buildItemsSection() {
    final double tableWidth = _colNo +
        _colDesc +
        _colHsn +
        _colUnit +
        _colQty +
        _colRate +
        _colDisc +
        _colGst +
        _colTaxable +
        _colTax1 +
        _colTax1 +
        _colAmt +
        _colDel;

    return _card(
      title: 'Items',
      icon: Icons.list_alt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Container(
                decoration: const BoxDecoration(
                  color: _navyDark,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8)),
                ),
                child: Row(children: [
                  _thCell('#', _colNo),
                  _thCell('DESCRIPTION', _colDesc),
                  _thCell('HSN / SAC', _colHsn),
                  _thCell('UNIT', _colUnit),
                  _thCell('QTY', _colQty, align: TextAlign.center),
                  _thCell('RATE (₹)', _colRate, align: TextAlign.right),
                  _thCell('DISCOUNT', _colDisc, align: TextAlign.right),
                  _thCell('GST %', _colGst, align: TextAlign.center),
                  _thCell('TAXABLE', _colTaxable, align: TextAlign.right),
                  _thCell('CGST', _colTax1, align: TextAlign.right),
                  _thCell('SGST', _colTax1, align: TextAlign.right),
                  _thCell('AMOUNT', _colAmt, align: TextAlign.right),
                  SizedBox(width: _colDel),
                ]),
              ),

              // Rows
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
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 20, color: Colors.grey[400]),
                        const SizedBox(width: 8),
                        Text('No items — click Add Item below',
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 13)),
                      ]),
                )
              else
                ...List.generate(_items.length, (i) => _buildItemTableRow(i)),

              // Add Item row
              InkWell(
                onTap: _addNewItem,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8)),
                child: Container(
                  width: tableWidth,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: _navyAccent.withOpacity(0.05),
                    borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8)),
                    border: Border(
                      left: BorderSide(color: _navyAccent.withOpacity(0.25)),
                      right: BorderSide(color: _navyAccent.withOpacity(0.25)),
                      bottom: BorderSide(color: _navyAccent.withOpacity(0.25)),
                    ),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 18, color: _navyAccent),
                        const SizedBox(width: 8),
                        Text('+ Add Item',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _navyAccent)),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _thCell(String text, double width,
          {TextAlign align = TextAlign.left}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(text,
              textAlign: align,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4)),
        ),
      );

  Widget _buildItemTableRow(int index) {
    final item = _items[index];
    final isOdd = index.isOdd;
    final descCtrl = _descControllers[index];

    return Container(
      decoration: BoxDecoration(
        color: isOdd ? const Color(0xFFF7F9FC) : Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey[200]!),
          right: BorderSide(color: Colors.grey[200]!),
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // #
        SizedBox(
            width: _colNo,
            child: Center(
                child: Text('${index + 1}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])))),

        // Description (multiline)
        SizedBox(
          width: _colDesc,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: TextFormField(
              controller: descCtrl,
              decoration: InputDecoration(
                hintText: 'Item description',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              maxLines: null,
              keyboardType: TextInputType.multiline,
              onChanged: (v) {
                item.itemDetails = v;
              },
            ),
          ),
        ),

        // HSN/SAC
        SizedBox(
          width: _colHsn,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: TextFormField(
              initialValue: item.hsnCode,
              decoration: InputDecoration(
                hintText: 'HSN/SAC',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              onChanged: (v) => item.hsnCode = v,
            ),
          ),
        ),

        // Unit
        SizedBox(
          width: _colUnit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: DropdownButtonFormField<String>(
              value: _kUnits.contains(item.unit) ? item.unit : 'Nos',
              isExpanded: true,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                isDense: true,
              ),
              items: _kUnits
                  .map((u) => DropdownMenuItem(
                      value: u,
                      child: Text(u, style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (v) => setState(() => item.unit = v ?? 'Nos'),
            ),
          ),
        ),

        // Qty
        SizedBox(
          width: _colQty,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: TextFormField(
              initialValue: item.quantity > 0 ? item.quantity.toString() : '',
              decoration: InputDecoration(
                hintText: '0',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              onChanged: (v) {
                item.quantity = double.tryParse(v) ?? 0;
                _calculateAmounts();
              },
            ),
          ),
        ),

        // Rate
        SizedBox(
          width: _colRate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: TextFormField(
              initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
              decoration: InputDecoration(
                hintText: '0.00',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              onChanged: (v) {
                item.rate = double.tryParse(v) ?? 0;
                _calculateAmounts();
              },
            ),
          ),
        ),

        // Discount
        SizedBox(
          width: _colDisc,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(children: [
              Expanded(
                  child: TextFormField(
                initialValue: item.discount > 0 ? item.discount.toString() : '',
                decoration: InputDecoration(
                  hintText: '0',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  isDense: true,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                onChanged: (v) {
                  item.discount = double.tryParse(v) ?? 0;
                  _calculateAmounts();
                },
              )),
              PopupMenuButton<String>(
                initialValue: item.discountType,
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                padding: EdgeInsets.zero,
                onSelected: (v) => setState(() {
                  item.discountType = v;
                  _calculateAmounts();
                }),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'percentage', child: Text('%')),
                  const PopupMenuItem(value: 'amount', child: Text('₹')),
                ],
              ),
            ]),
          ),
        ),

        // GST %
        SizedBox(
          width: _colGst,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: DropdownButtonFormField<double>(
              value: _kGstRates.contains(item.itemGstRate)
                  ? item.itemGstRate
                  : 18.0,
              isExpanded: true,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                isDense: true,
              ),
              items: _kGstRates
                  .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r.toInt()}%',
                          style: const TextStyle(fontSize: 12))))
                  .toList(),
              onChanged: (v) => setState(() {
                item.itemGstRate = v ?? 18;
                _calculateAmounts();
              }),
            ),
          ),
        ),

        // Taxable (read-only)
        SizedBox(
          width: _colTaxable,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(item.taxableAmount.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12)),
          ),
        ),

        // CGST (read-only)
        SizedBox(
          width: _colTax1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(item.cgstAmount.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12)),
          ),
        ),

        // SGST (read-only)
        SizedBox(
          width: _colTax1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(item.sgstAmount.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12)),
          ),
        ),

        // Amount (read-only)
        SizedBox(
          width: _colAmt,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(item.amount.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _navyDark)),
          ),
        ),

        // Delete
        SizedBox(
          width: _colDel,
          child: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
            onPressed: () => _removeItem(index),
            tooltip: 'Remove',
          ),
        ),
      ]),
    );
  }

  // ============================================================================
  // NOTES SECTION
  // ============================================================================

  Widget _buildNotesSection() => _card(
        title: 'Additional Information',
        icon: Icons.note_alt,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            controller: _vendorNotesController,
            decoration: InputDecoration(
              labelText: 'Vendor Notes',
              hintText: 'Notes visible on purchase order',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),
        ]),
      );

  // ============================================================================
  // TAX SETTINGS SECTION (sidebar)
  // ============================================================================

  Widget _buildTaxSettingsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Tax Settings', Icons.calculate),
          const SizedBox(height: 16),

          // TDS
          SwitchListTile(
            title: const Text('Enable TDS'),
            subtitle: const Text('Tax Deducted at Source',
                style: TextStyle(fontSize: 11)),
            value: _enableTDS,
            activeColor: _navyAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() {
              _enableTDS = v;
              _calculateAmounts();
            }),
          ),
          if (_enableTDS) ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _tdsRate.toString(),
              decoration: InputDecoration(
                labelText: 'TDS Rate (%)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixText: '%',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => setState(() {
                _tdsRate = double.tryParse(v) ?? 0;
                _calculateAmounts();
              }),
            ),
          ],
          const SizedBox(height: 12),

          // TCS
          SwitchListTile(
            title: const Text('Enable TCS'),
            subtitle: const Text('Tax Collected at Source',
                style: TextStyle(fontSize: 11)),
            value: _enableTCS,
            activeColor: _navyAccent,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() {
              _enableTCS = v;
              _calculateAmounts();
            }),
          ),
          if (_enableTCS) ...[
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _tcsRate.toString(),
              decoration: InputDecoration(
                labelText: 'TCS Rate (%)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixText: '%',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => setState(() {
                _tcsRate = double.tryParse(v) ?? 0;
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
          _sectionTitle('PO Summary', Icons.summarize),
          const SizedBox(height: 16),

          _summaryRow('Sub Total', _subTotal),
          const SizedBox(height: 6),
          if (_enableTDS && _tdsAmount > 0) ...[
            _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)', -_tdsAmount,
                color: Colors.red[700]),
            const SizedBox(height: 6),
          ],
          if (_enableTCS && _tcsAmount > 0) ...[
            _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmount),
            const SizedBox(height: 6),
          ],
          if (_totalCGST > 0) ...[
            _summaryRow('CGST', _totalCGST),
            const SizedBox(height: 6),
          ],
          if (_totalSGST > 0) ...[
            _summaryRow('SGST', _totalSGST),
            const SizedBox(height: 6),
          ],
          if (_totalIGST > 0) ...[
            _summaryRow('IGST', _totalIGST),
            const SizedBox(height: 6),
          ],
          const Divider(thickness: 2),
          const SizedBox(height: 6),
          _summaryRow('Total Amount', _totalAmount,
              isBold: true, isTotal: true),

          const SizedBox(height: 16),

          // Gradient info box — exact match to new_payment_made.dart
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _navyDark.withOpacity(0.1),
                  _navyLight.withOpacity(0.1)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _navyAccent.withOpacity(0.3)),
            ),
            child: Column(children: [
              _infoRow('Total Qty:', _totalQuantity.toString()),
              const SizedBox(height: 4),
              _infoRow(
                  'Total Items:',
                  _items
                      .where((i) => i.itemDetails.isNotEmpty)
                      .length
                      .toString()),
              const SizedBox(height: 4),
              _infoRow('Payment Terms:', _selectedPaymentTerms),
              if (_selectedVendorName != null) ...[
                const SizedBox(height: 4),
                _infoRow('Vendor:', _selectedVendorName!),
              ],
            ]),
          ),

          const SizedBox(height: 20),

          // Save & Send to Vendor
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAndSend,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_isSaving ? 'Sending...' : 'Save & Send to Vendor'),
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

          // Save as Draft
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _saveAsDraft,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save as Draft'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navyMid,
                side: BorderSide(color: _navyMid),
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
                foregroundColor: Colors.grey[600],
                side: BorderSide(color: Colors.grey[400]!),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      );

  // ============================================================================
  // VENDOR SELECTOR DIALOG — functionality unchanged, styling updated
  // ============================================================================

  Future<void> _showVendorSelector() async {
    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> vendors = [];
    List<Map<String, dynamic>> filteredVendors = [];
    bool isLoading = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (isLoading && vendors.isEmpty) {
            BillingVendorsService.getAllVendors(limit: 1000).then((response) {
              setS(() {
                if (response['success'] == true) {
                  final raw = response['data'];
                  final list =
                      raw is List ? raw : (raw['vendors'] as List? ?? []);
                  vendors = list
                      .map<Map<String, dynamic>>((v) => {
                            '_id': v['_id'] ?? '',
                            'vendorName': v['vendorName'] ?? '',
                            'email': v['email'] ?? '',
                            'vendorPhone': v['vendorPhone'] ?? v['phone'] ?? '',
                            'gstNumber': v['gstNumber'] ?? '',
                            'panNumber': v['panNumber'] ?? '',
                            'gstType':
                                v['gstType'] ?? v['gstRegistrationType'] ?? '',
                            'companyName': v['companyName'],
                            'billingAddress': v['billingAddress'] ?? {},
                            'shippingAddress': v['shippingAddress'] ?? {},
                            'state': v['state'] ??
                                (v['billingAddress'] is Map
                                    ? v['billingAddress']['state']
                                    : '') ??
                                '',
                          })
                      .toList();
                  filteredVendors = vendors;
                }
                isLoading = false;
              });
            }).catchError((error) {
              setS(() {
                errorMessage = error.toString();
                isLoading = false;
              });
            });
          }

          return AlertDialog(
            title: const Text('Select Vendor'),
            content: SizedBox(
                width: 500,
                height: 450,
                child: Column(children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search vendors...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) => setS(() {
                      filteredVendors = v.isEmpty
                          ? vendors
                          : vendors
                              .where((vd) =>
                                  vd['vendorName']
                                      .toString()
                                      .toLowerCase()
                                      .contains(v.toLowerCase()) ||
                                  vd['email']
                                      .toString()
                                      .toLowerCase()
                                      .contains(v.toLowerCase()) ||
                                  (vd['companyName']
                                          ?.toString()
                                          .toLowerCase()
                                          .contains(v.toLowerCase()) ??
                                      false))
                              .toList();
                    }),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(_navyAccent)))
                        : errorMessage != null
                            ? Center(
                                child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 48, color: Colors.red[400]),
                                  const SizedBox(height: 12),
                                  Text('Error loading vendors',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red[700])),
                                  const SizedBox(height: 8),
                                  Text(errorMessage!,
                                      style: TextStyle(color: Colors.grey[600]),
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () => setS(() {
                                      isLoading = true;
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
                                ? const Center(
                                    child: Text('No vendors found',
                                        style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    itemCount: filteredVendors.length,
                                    itemBuilder: (_, i) {
                                      final v = filteredVendors[i];
                                      final name = v['vendorName'].toString();
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: _navyAccent,
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        ),
                                        title: Text(name),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(v['email'].toString()),
                                            if (v['companyName'] != null)
                                              Text(
                                                v['companyName'].toString(),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                          ],
                                        ),
                                        onTap: () {
                                          final ba = v['billingAddress'];
                                          final sa = v['shippingAddress'];
                                          setState(() {
                                            _selectedVendorId =
                                                v['_id'].toString();
                                            _selectedVendorName =
                                                v['vendorName'].toString();
                                            _selectedVendorEmail =
                                                v['email'].toString();
                                            _selectedVendorPhone =
                                                v['vendorPhone']?.toString() ??
                                                    '';
                                            _selectedVendorGSTIN =
                                                v['gstNumber']?.toString() ??
                                                    '';
                                            _selectedVendorPAN =
                                                v['panNumber']?.toString() ??
                                                    '';
                                            _gstRegistrationType =
                                                v['gstType']?.toString() ?? '';
                                            _selectedVendorCompany =
                                                v['companyName']?.toString();
                                            _billingAddress =
                                                _PoAddress.fromMap(ba is Map
                                                    ? Map<String, dynamic>.from(
                                                        ba)
                                                    : {});
                                            _shippingAddress =
                                                _PoAddress.fromMap(sa is Map
                                                    ? Map<String, dynamic>.from(
                                                        sa)
                                                    : {});
                                            _sameAsBilling = true;
                                            // Auto-set place of supply from vendor state
                                            final vendorState =
                                                v['state']?.toString() ?? '';
                                            if (vendorState.isNotEmpty &&
                                                _placeOfSupply.isEmpty) {
                                              _placeOfSupply = vendorState;
                                            }
                                          });
                                          _updateInterState();
                                          Navigator.pop(ctx);
                                        },
                                      );
                                    },
                                  ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
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
                ])),
            actions: [
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
  // ADD VENDOR — unchanged
  // ============================================================================

  Future<void> _showAddVendorDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewVendorPage()),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedVendorId = result['id'];
        _selectedVendorName = result['vendorName'];
        _selectedVendorEmail = result['email'];
        _selectedVendorPhone = result['vendorPhone']?.toString() ??
            result['phone']?.toString() ??
            '';
        _selectedVendorGSTIN = result['gstNumber']?.toString() ?? '';
        _selectedVendorPAN = result['panNumber']?.toString() ?? '';
        _gstRegistrationType = result['gstType']?.toString() ?? '';
        _selectedVendorCompany = result['companyName']?.toString();
        final ba = result['billingAddress'];
        _billingAddress =
            _PoAddress.fromMap(ba is Map ? Map<String, dynamic>.from(ba) : {});
        _shippingAddress = _billingAddress;
        _sameAsBilling = true;
      });
      _showSuccessSnackbar(
          'Vendor "${result['vendorName']}" added successfully');
    }
  }

  // ============================================================================
  // HELPERS — exact match to new_payment_made.dart
  // ============================================================================

  /// White card with gradient section title + optional trailing widget
  Widget _card({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionTitle(title, icon),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );

  /// Section title with gradient icon box — exact match to new_payment_made.dart
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
        Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
      ]);

  /// Summary row — exact match to new_payment_made.dart
  Widget _summaryRow(String label, double amount,
          {Color? color, bool isBold = false, bool isTotal = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight:
                  isBold || isTotal ? FontWeight.bold : FontWeight.normal,
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

  /// Info row inside gradient box — exact match to new_payment_made.dart
  Widget _infoRow(String label, String value) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        Flexible(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _navyDark),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis)),
      ]);
}
