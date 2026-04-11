// ============================================================================
// NEW VENDOR CREDIT SCREEN
// ============================================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../../core/services/vendor_credit_service.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../app/config/api_config.dart';
import '../widgets/document_preview_buttons.dart';
import 'new_vendor.dart';
import '../../../../core/services/bill_service.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

const List<double> _kGstRates = [0, 5, 12, 18, 28];
const List<String> _kUnits    = ['Nos', 'Hrs', 'Kg', 'Pcs', 'Box', 'Mtr', 'Ltr', 'Dz', 'MT', 'Set'];

// Column widths for items table
const double _colNo      = 36.0;
const double _colDesc    = 200.0;
const double _colHsn     = 110.0;
const double _colUnit    = 80.0;
const double _colQty     = 70.0;
const double _colRate    = 95.0;
const double _colDisc    = 110.0;
const double _colGst     = 80.0;
const double _colTaxable = 100.0;
const double _colTax1    = 90.0;
const double _colTax2    = 90.0;
const double _colAmt     = 95.0;
const double _colDel     = 44.0;

// Indian states list (same as invoice)
const List<String> kIndianStates = [
  'Andhra Pradesh','Arunachal Pradesh','Assam','Bihar','Chhattisgarh','Goa','Gujarat',
  'Haryana','Himachal Pradesh','Jharkhand','Karnataka','Kerala','Madhya Pradesh',
  'Maharashtra','Manipur','Meghalaya','Mizoram','Nagaland','Odisha','Punjab',
  'Rajasthan','Sikkim','Tamil Nadu','Telangana','Tripura','Uttar Pradesh',
  'Uttarakhand','West Bengal','Andaman and Nicobar Islands','Chandigarh',
  'Dadra and Nagar Haveli and Daman and Diu','Delhi','Jammu and Kashmir',
  'Ladakh','Lakshadweep','Puducherry',
];

class NewVendorCreditScreen extends StatefulWidget {
  final String? creditId;
  const NewVendorCreditScreen({Key? key, this.creditId}) : super(key: key);

  @override
  State<NewVendorCreditScreen> createState() => _NewVendorCreditScreenState();
}

class _NewVendorCreditScreenState extends State<NewVendorCreditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Controllers
  final _reasonController = TextEditingController();
  final _notesController  = TextEditingController();
  final List<TextEditingController> _descControllers = [];

  // Vendor
  String? _selectedVendorId;
  String? _selectedVendorName;
  String? _selectedVendorEmail;
  String? _selectedVendorPhone;
  String? _selectedVendorGSTIN;
  String? _selectedVendorPAN;
  String  _gstRegistrationType = '';

  // Addresses
  VendorAddress _billingAddress  = const VendorAddress();
  VendorAddress _shippingAddress = const VendorAddress();
  bool _sameAsBilling = true;

  // Place of supply
  String _placeOfSupply = '';
  String _orgState      = '';
  bool   _isInterState  = false;

  // Credit Details
  DateTime _creditDate    = DateTime.now();
  String?  _linkedBillId;
  String?  _linkedBillNumber;
  Bill?    _linkedBill;
  bool     _loadingBills = false;

  // Tax toggles
  double _tdsRate  = 0;
  double _tcsRate  = 0;
  bool   _enableTDS = false;
  bool   _enableTCS = false;

  // Items
  List<MutableCreditItem> _items = [];

  // Totals
  double _subTotal   = 0;
  double _totalCGST  = 0;
  double _totalSGST  = 0;
  double _totalIGST  = 0;
  double _totalTax   = 0;
  double _tdsAmount  = 0;
  double _tcsAmount  = 0;
  double _totalAmount = 0;

  final List<String> _creditReasons = [
    'Goods Returned', 'Overcharged by Vendor', 'Quality Issue',
    'Advance Payment Excess', 'Discount After Billing',
    'Duplicate Invoice', 'Service Not Delivered', 'Other',
  ];

  List<Map<String, dynamic>> _coaExpAccounts = [];
  bool _loadingCoaAccounts = false;

  @override
  void initState() {
    super.initState();
    _addItem();
    _loadCoaExpenseAccounts();
    _loadOrgState();
    if (widget.creditId != null) _loadCreditData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    for (final c in _descControllers) { c.dispose(); }
    super.dispose();
  }

  // ── Org state ──────────────────────────────────────────────────────────────
  Future<void> _loadOrgState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final resp  = await http.get(
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
    final newVal = _placeOfSupply.isNotEmpty && _orgState.isNotEmpty &&
        _placeOfSupply.toLowerCase() != _orgState.toLowerCase();
    if (newVal != _isInterState) {
      setState(() => _isInterState = newVal);
      _calculateAmounts();
    }
  }

  // ── Item management ────────────────────────────────────────────────────────
  void _addItem() {
    setState(() {
      _items.add(MutableCreditItem(itemGstRate: 18));
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

  // ── Calculations ───────────────────────────────────────────────────────────
  void _calculateAmounts() {
    setState(() {
      _subTotal  = 0;
      _totalCGST = 0;
      _totalSGST = 0;
      _totalIGST = 0;
      for (final item in _items) {
        item.recalculate(isInterState: _isInterState);
        _subTotal  += item.taxableAmount;
        _totalCGST += item.cgstAmount;
        _totalSGST += item.sgstAmount;
        _totalIGST += item.igstAmount;
      }
      _subTotal  = double.parse(_subTotal.toStringAsFixed(2));
      _totalCGST = double.parse(_totalCGST.toStringAsFixed(2));
      _totalSGST = double.parse(_totalSGST.toStringAsFixed(2));
      _totalIGST = double.parse(_totalIGST.toStringAsFixed(2));
      _totalTax  = double.parse((_totalCGST + _totalSGST + _totalIGST).toStringAsFixed(2));
      _tdsAmount = _enableTDS ? double.parse((_subTotal * _tdsRate / 100).toStringAsFixed(2)) : 0;
      _tcsAmount = _enableTCS ? double.parse((_subTotal * _tcsRate / 100).toStringAsFixed(2)) : 0;
      _totalAmount = double.parse((_subTotal + _totalTax - _tdsAmount + _tcsAmount).toStringAsFixed(2));
    });
  }

  // ── COA accounts ───────────────────────────────────────────────────────────
  Future<void> _loadCoaExpenseAccounts() async {
    setState(() => _loadingCoaAccounts = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final uri   = Uri.parse(
          '${ApiConfig.baseUrl}/api/finance/chart-of-accounts?accountType=Expense&limit=200');
      final resp  = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      });
      if (resp.statusCode == 200) {
        final body     = jsonDecode(resp.body);
        final accounts = (body['data']?['accounts'] as List? ?? []);
        if (mounted) {
          setState(() {
            _coaExpAccounts = accounts
                .map((a) => {
                      '_id':         a['_id']?.toString() ?? '',
                      'accountName': a['accountName']?.toString() ?? '',
                    })
                .toList();
            _loadingCoaAccounts = false;
          });
        }
      } else {
        throw Exception('COA fetch failed: ${resp.statusCode}');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _coaExpAccounts = [
            {'_id': '1',  'accountName': 'Purchase Returns'},
            {'_id': '2',  'accountName': 'Office Supplies'},
            {'_id': '3',  'accountName': 'Rent Expense'},
            {'_id': '4',  'accountName': 'Utilities'},
            {'_id': '5',  'accountName': 'Software Subscriptions'},
            {'_id': '6',  'accountName': 'Travel & Entertainment'},
            {'_id': '7',  'accountName': 'Professional Services'},
            {'_id': '8',  'accountName': 'Marketing & Advertising'},
            {'_id': '9',  'accountName': 'Maintenance & Repairs'},
            {'_id': '10', 'accountName': 'Insurance'},
            {'_id': '11', 'accountName': 'Cost of Goods Sold'},
            {'_id': '12', 'accountName': 'Other Expenses'},
          ];
          _loadingCoaAccounts = false;
        });
      }
    }
  }

  Future<void> _loadCreditData() async {
    setState(() => _isLoading = true);
    try {
      final credit = await VendorCreditService.getVendorCredit(widget.creditId!);
      for (final c in _descControllers) { c.dispose(); }
      _descControllers.clear();
      setState(() {
        _selectedVendorId    = credit.vendorId;
        _selectedVendorName  = credit.vendorName;
        _selectedVendorEmail = credit.vendorEmail;
        _selectedVendorPhone = credit.vendorPhone;
        _selectedVendorGSTIN = credit.vendorGSTIN;
        _selectedVendorPAN   = credit.vendorPAN;
        _gstRegistrationType = credit.gstRegistrationType;
        _billingAddress      = VendorAddress.fromJson(credit.billingAddress);
        _shippingAddress     = VendorAddress.fromJson(credit.shippingAddress);
        _sameAsBilling       = credit.billingAddress.toString() == credit.shippingAddress.toString();
        _placeOfSupply       = credit.placeOfSupply;
        _creditDate          = credit.creditDate;
        _linkedBillId        = credit.billId;
        _linkedBillNumber    = credit.billNumber;
        _reasonController.text = credit.reason;
        _notesController.text  = credit.notes ?? '';
        _tdsRate   = credit.tdsRate;
        _tcsRate   = credit.tcsRate;
        _enableTDS = credit.tdsRate > 0;
        _enableTCS = credit.tcsRate > 0;
        _items = credit.items.map((i) => MutableCreditItem(
          itemDetails:  i.itemDetails,
          account:      i.account,
          hsnCode:      i.hsnCode,
          sacCode:      i.sacCode,
          unit:         i.unit,
          quantity:     i.quantity,
          rate:         i.rate,
          discount:     i.discount,
          discountType: i.discountType,
          itemGstRate:  i.itemGstRate,
          amount:       i.amount,
        )).toList();
        for (final item in _items) {
          _descControllers.add(TextEditingController(text: item.itemDetails));
        }
        _updateInterState();
        _calculateAmounts();
      });
    } catch (e) {
      _showError('Failed to load credit: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _validateForm() {
    if (_selectedVendorId == null) { _showError('Please select a vendor'); return false; }
    if (_reasonController.text.trim().isEmpty) { _showError('Please enter a reason'); return false; }
    final nonEmpty = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) { _showError('Please add at least one item'); return false; }
    for (var item in nonEmpty) {
      if (item.quantity <= 0) { _showError('All items must have quantity > 0'); return false; }
      if (item.rate <= 0)     { _showError('All items must have rate > 0');     return false; }
    }
    return true;
  }

  Map<String, dynamic> _buildBody() {
    final valid = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    return {
      'vendorId':            _selectedVendorId,
      'vendorName':          _selectedVendorName,
      'vendorEmail':         _selectedVendorEmail,
      'vendorPhone':         _selectedVendorPhone ?? '',
      'vendorGSTIN':         _selectedVendorGSTIN,
      'vendorPAN':           _selectedVendorPAN ?? '',
      'gstRegistrationType': _gstRegistrationType,
      'billingAddress':      _billingAddress.toJson(),
      'shippingAddress':     _sameAsBilling ? _billingAddress.toJson() : _shippingAddress.toJson(),
      'placeOfSupply':       _placeOfSupply,
      'isInterState':        _isInterState,
      'creditDate':          _creditDate.toIso8601String(),
      'billId':              _linkedBillId,
      'billNumber':          _linkedBillNumber,
      'reason':              _reasonController.text.trim(),
      'notes':               _notesController.text.trim(),
      'items':               valid.map((i) => i.toJson()).toList(),
      'tdsRate':             _enableTDS ? _tdsRate : 0,
      'tcsRate':             _enableTCS ? _tcsRate : 0,
      'subTotal':            _subTotal,
      'totalCGST':           _totalCGST,
      'totalSGST':           _totalSGST,
      'totalIGST':           _totalIGST,
      'totalTax':            _totalTax,
      'cgst':                _totalCGST,
      'sgst':                _totalSGST,
      'tdsAmount':           _tdsAmount,
      'tcsAmount':           _tcsAmount,
      'totalAmount':         _totalAmount,
      'status':              'OPEN',
    };
  }

  Future<void> _markAsSent() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateForm()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Sent?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'The email will NOT be sent to the vendor.\n\nDo you want to mark this vendor credit as Sent anyway?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
      final data = _buildBody();
      VendorCredit credit;
      if (widget.creditId != null) {
        credit = await VendorCreditService.updateVendorCredit(widget.creditId!, data);
      } else {
        credit = await VendorCreditService.createVendorCredit(data);
      }
      await VendorCreditService.markAsSent(credit.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vendor credit marked as sent'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateForm()) return;
    setState(() => _isSaving = true);
    try {
      final body = _buildBody();
      VendorCredit credit;
      if (widget.creditId != null) {
        credit = await VendorCreditService.updateVendorCredit(widget.creditId!, body);
      } else {
        credit = await VendorCreditService.createVendorCredit(body);
      }
      _showSuccess('Vendor Credit ${credit.creditNumber} saved successfully');
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
                        Expanded(
                          flex: 3,
                          child: _buildMainContent(),
                        ),
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
            widget.creditId != null ? 'Edit Vendor Credit' : 'New Vendor Credit',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              tooltip: 'View PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
              onPressed: () => openDocumentPdf(context: context, docId: widget.creditId, pdfEndpoint: '/api/finance/vendor-credits', docNumber: 'VC'),
            ),
            IconButton(
              tooltip: 'Preview Email',
              icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
              onPressed: () => openEmailPreview(context: context, docId: widget.creditId, emailEndpoint: '/api/finance/vendor-credits'),
            ),
            TextButton.icon(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
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
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save Credit'),
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
          _buildVendorSection(),
          const SizedBox(height: 20),
          _buildCreditDetailsSection(),
          const SizedBox(height: 20),
          _buildPlaceOfSupplySection(),
          const SizedBox(height: 20),
          _buildAddressSection(),
          const SizedBox(height: 20),
          _buildItemsSection(),
          const SizedBox(height: 20),
          _buildNotesSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // VENDOR SECTION
  // -----------------------------------------------------------------------

  Widget _buildVendorSection() {
    return _card(
      child: Column(
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
                Expanded(child: Text(
                  _selectedVendorName ?? 'Select Vendor *',
                  style: TextStyle(
                    fontSize: 15,
                    color: _selectedVendorName != null ? _navyDark : Colors.grey[600],
                    fontWeight: _selectedVendorName != null ? FontWeight.w600 : FontWeight.normal,
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
              Text(_selectedVendorEmail!, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ]),
          ],
          if (_selectedVendorGSTIN != null && _selectedVendorGSTIN!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text('GSTIN: $_selectedVendorGSTIN', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              if (_selectedVendorPAN != null && _selectedVendorPAN!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text('PAN: $_selectedVendorPAN', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              ],
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
              child: Text(_gstRegistrationType, style: TextStyle(fontSize: 12, color: _navyMid, fontWeight: FontWeight.w500)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Place of Supply ────────────────────────────────────────────────────────
  Widget _buildPlaceOfSupplySection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Place of Supply', Icons.location_on_outlined),
        const SizedBox(height: 8),
        Text('Determines CGST+SGST (intra-state) or IGST (inter-state)',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _placeOfSupply.isNotEmpty ? _placeOfSupply : null,
          decoration: InputDecoration(
            labelText: 'Place of Supply',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.place),
          ),
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
                    ? 'Inter-State: IGST will be applied'
                    : 'Intra-State: CGST + SGST will be applied',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                    color: _isInterState ? Colors.orange[900] : Colors.green[900]),
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Address Section ────────────────────────────────────────────────────────
  Widget _buildAddressSection() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Billing & Shipping Address', Icons.location_city),
        const SizedBox(height: 16),
        if (!_billingAddress.isEmpty) ...[
          Text('Billing Address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
            child: Text(_billingAddress.formatted, style: TextStyle(fontSize: 13, color: Colors.grey[800])),
          ),
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
          _buildAddressFields(
            label: 'Shipping Address',
            address: _shippingAddress,
            onChanged: (addr) => setState(() => _shippingAddress = addr),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
            child: Text(
              _billingAddress.isEmpty ? 'No billing address — select a vendor to auto-fill' : _billingAddress.formatted,
              style: TextStyle(fontSize: 13, color: _billingAddress.isEmpty ? Colors.grey[500] : Colors.grey[800],
                  fontStyle: _billingAddress.isEmpty ? FontStyle.italic : FontStyle.normal),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildAddressFields({required String label, required VendorAddress address, required ValueChanged<VendorAddress> onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[700])),
      const SizedBox(height: 8),
      TextFormField(initialValue: address.street,
        decoration: InputDecoration(labelText: 'Street', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
        onChanged: (v) => onChanged(VendorAddress(street: v, city: address.city, state: address.state, zip: address.zip, country: address.country))),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(initialValue: address.city,
          decoration: InputDecoration(labelText: 'City', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(VendorAddress(street: address.street, city: v, state: address.state, zip: address.zip, country: address.country)))),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(initialValue: address.state,
          decoration: InputDecoration(labelText: 'State', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(VendorAddress(street: address.street, city: address.city, state: v, zip: address.zip, country: address.country)))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextFormField(initialValue: address.zip,
          decoration: InputDecoration(labelText: 'PIN/ZIP', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(VendorAddress(street: address.street, city: address.city, state: address.state, zip: v, country: address.country)))),
        const SizedBox(width: 8),
        Expanded(child: TextFormField(initialValue: address.country,
          decoration: InputDecoration(labelText: 'Country', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
          onChanged: (v) => onChanged(VendorAddress(street: address.street, city: address.city, state: address.state, zip: address.zip, country: v)))),
      ]),
    ]);
  }

  // -----------------------------------------------------------------------
  // CREDIT DETAILS SECTION
  // -----------------------------------------------------------------------

Widget _buildCreditDetailsSection() {
  return _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Credit Details', Icons.credit_card),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          final dateField = InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _creditDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (d != null) setState(() => _creditDate = d);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Credit Date *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.calendar_today),
              ),
              child: Text(DateFormat('dd MMM yyyy').format(_creditDate)),
            ),
          );

          // ✅ Bill selector — only shows after vendor is selected
          final billField = _selectedVendorId == null
              ? InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Against Bill (Optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.receipt),
                  ),
                  child: Text('Select a vendor first',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                )
              : InkWell(
                  onTap: _showBillSelector,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Against Bill (Optional)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: _linkedBillId != null
                                  ? _navyAccent
                                  : Colors.grey)),
                      prefixIcon: const Icon(Icons.receipt),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_linkedBillId != null)
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 18, color: Colors.red),
                              onPressed: () => setState(() {
                                _linkedBillId = null;
                                _linkedBillNumber = null;
                                _linkedBill = null;
                              }),
                              tooltip: 'Clear bill',
                            ),
                          _loadingBills
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              : const Icon(Icons.arrow_drop_down,
                                  color: Colors.grey),
                        ],
                      ),
                    ),
                    child: Text(
                      _linkedBillNumber ?? 'Select Bill',
                      style: TextStyle(
                        color: _linkedBillNumber != null
                            ? _navyDark
                            : Colors.grey[500],
                        fontWeight: _linkedBillNumber != null
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );

          if (isWide) {
            return Row(children: [
              Expanded(child: dateField),
              const SizedBox(width: 16),
              Expanded(child: billField),
            ]);
          } else {
            return Column(children: [
              dateField,
              const SizedBox(height: 16),
              billField,
            ]);
          }
        }),

        // ✅ Show linked bill summary if selected
        if (_linkedBill != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _navyAccent.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _navyAccent.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.link, color: _navyAccent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_linkedBill!.billNumber,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _navyDark,
                          fontSize: 13)),
                  Text(
                      'Amount Due: ₹${_linkedBill!.amountDue.toStringAsFixed(2)} · ${_linkedBill!.status}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                ]),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Linked',
                    style: TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _creditReasons.contains(_reasonController.text)
              ? _reasonController.text
              : null,
          decoration: InputDecoration(
            labelText: 'Reason for Credit *',
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.info_outline),
          ),
          items: _creditReasons
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _reasonController.text = v);
          },
        ),
      ],
    ),
  );
}

Future<void> _showBillSelector() async {
  if (_selectedVendorId == null) return;
  setState(() => _loadingBills = true);

  List<Map<String, dynamic>> bills = [];
  try {
    // Fetch OPEN + PARTIALLY_PAID bills for this vendor
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';

    // Fetch OPEN bills
    final uriOpen = Uri.parse('${ApiConfig.baseUrl}/api/finance/bills').replace(
        queryParameters: {
          'vendorId': _selectedVendorId!,
          'status': 'OPEN',
          'limit': '100'
        });
    final uriPartial = Uri.parse('${ApiConfig.baseUrl}/api/finance/bills')
        .replace(queryParameters: {
      'vendorId': _selectedVendorId!,
      'status': 'PARTIALLY_PAID',
      'limit': '100'
    });

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final responses = await Future.wait([
      http.get(uriOpen, headers: headers),
      http.get(uriPartial, headers: headers),
    ]);

    for (final resp in responses) {
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
final rawData = body['data'];
final list = List<Map<String, dynamic>>.from(
  rawData is List ? rawData : (rawData?['bills'] ?? [])
);
        bills.addAll(list);
      }
    }
  } catch (e) {
    _showError('Failed to load bills: $e');
  } finally {
    setState(() => _loadingBills = false);
  }

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _navyDark.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              const Icon(Icons.receipt_long, color: _navyDark, size: 20),
        ),
        const SizedBox(width: 12),
        const Text('Select Bill',
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
      content: SizedBox(
        width: 520,
        height: 400,
        child: bills.isEmpty
            ? Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.receipt_outlined,
                      size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text(
                    'No open bills found for ${_selectedVendorName ?? 'this vendor'}',
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text('Only OPEN and PARTIALLY PAID bills are shown',
                      style: TextStyle(
                          color: Colors.grey[400], fontSize: 12),
                      textAlign: TextAlign.center),
                ]),
              )
            : Column(children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _navyDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Expanded(
                        flex: 3,
                        child: Text('BILL #',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('DATE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                    Expanded(
                        flex: 2,
                        child: Text('AMOUNT DUE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                    SizedBox(
                        width: 90,
                        child: Text('STATUS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold))),
                  ]),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: bills.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = bills[i];
                      final status = b['status'] ?? 'OPEN';
                      final statusColor = status == 'OPEN'
                          ? Colors.orange
                          : Colors.blue;
                      final amountDue =
                          (b['amountDue'] ?? b['totalAmount'] ?? 0)
                              .toDouble();

                      String dateStr = 'N/A';
                      try {
                        dateStr = DateFormat('dd MMM yyyy').format(
                            DateTime.parse(
                                b['billDate'].toString()));
                      } catch (_) {}

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _linkedBillId =
                                b['_id']?.toString() ?? '';
                            _linkedBillNumber =
                                b['billNumber']?.toString() ?? '';
                            // Store full bill for summary display
                            _linkedBill = Bill.fromJson(b);
                            // ✅ Auto-fill items from bill
                            _items = (b['items'] as List? ?? [])
                                .map((item) => MutableCreditItem(
                                      itemDetails: item['itemDetails']?.toString() ?? '',
                                      account:     item['account']?.toString(),
                                      hsnCode:     item['hsnCode']?.toString() ?? '',
                                      sacCode:     item['sacCode']?.toString() ?? '',
                                      unit:        item['unit']?.toString() ?? 'Nos',
                                      quantity:    (item['quantity'] ?? 0).toDouble(),
                                      rate:        (item['rate'] ?? 0).toDouble(),
                                      discount:    (item['discount'] ?? 0).toDouble(),
                                      discountType: item['discountType']?.toString() ?? 'percentage',
                                      itemGstRate: (item['itemGstRate'] ?? item['gstRate'] ?? 18).toDouble(),
                                      amount:      (item['amount'] ?? 0).toDouble(),
                                    ))
                                .toList();
                            // Rebuild desc controllers
                            for (final c in _descControllers) { c.dispose(); }
                            _descControllers.clear();
                            for (final item in _items) {
                              _descControllers.add(TextEditingController(text: item.itemDetails));
                            }
                            // ✅ Auto-fill tax settings from bill
                            _tdsRate   = (b['tdsRate'] ?? 0).toDouble();
                            _tcsRate   = (b['tcsRate'] ?? 0).toDouble();
                            _enableTDS = _tdsRate > 0;
                            _enableTCS = _tcsRate > 0;
                            _calculateAmounts();
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          color: i.isOdd
                              ? Colors.grey[50]
                              : Colors.white,
                          child: Row(children: [
                            Expanded(
                                flex: 3,
                                child: Text(
                                    b['billNumber']?.toString() ??
                                        'N/A',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: _navyDark))),
                            Expanded(
                                flex: 2,
                                child: Text(dateStr,
                                    style: const TextStyle(
                                        fontSize: 13))),
                            Expanded(
                                flex: 2,
                                child: Text(
                                    '₹${amountDue.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight:
                                            FontWeight.w600))),
                            SizedBox(
                                width: 90,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: statusColor
                                        .withOpacity(0.12),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                  child: Text(status,
                                      style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 10),
                                      textAlign: TextAlign.center),
                                )),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    ),
  );
}

  // ── Items Section — horizontal scrollable table ────────────────────────────
  Widget _buildItemsSection() {
    final double tableWidth = _colNo + _colDesc + _colHsn + _colUnit + _colQty +
        _colRate + _colDisc + _colGst + _colTaxable + _colTax1 +
        (_isInterState ? 0 : _colTax2) + _colAmt + _colDel;

    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _sectionTitle('Line Items', Icons.list_alt),
          if (_placeOfSupply.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _isInterState ? Colors.orange[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _isInterState ? Colors.orange[300]! : Colors.blue[300]!),
              ),
              child: Text(_isInterState ? 'IGST' : 'CGST + SGST',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: _isInterState ? Colors.orange[800] : Colors.blue[800])),
            ),
        ]),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
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
                  if (_isInterState)
                    _thCell('IGST',      _colTax1,    align: TextAlign.right)
                  else ...[
                    _thCell('CGST',      _colTax1,    align: TextAlign.right),
                    _thCell('SGST',      _colTax2,    align: TextAlign.right),
                  ],
                  _thCell('AMOUNT',      _colAmt,     align: TextAlign.right),
                  SizedBox(width: _colDel),
                ]),
              ),
              if (_items.isEmpty)
                Container(
                  width: tableWidth,
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(left: BorderSide(color: Colors.grey[200]!), right: BorderSide(color: Colors.grey[200]!), bottom: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.inbox_outlined, size: 20, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text('No items — click Add Item below', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                  ]),
                )
              else
                ...List.generate(_items.length, (i) => _buildItemTableRow(i)),
              // Add item row
              InkWell(
                onTap: _addItem,
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

  InputDecoration _cellDecoration(String? hint) => InputDecoration(
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey[300]!)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey[300]!)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _navyAccent)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    isDense: true,
  );

  Widget _buildItemTableRow(int index) {
    final item     = _items[index];
    final isOdd    = index.isOdd;
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
          // #
          SizedBox(width: _colNo, child: Center(child: Text('${index + 1}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)))),
          // Description
          SizedBox(width: _colDesc, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: TextFormField(
              controller: descCtrl,
              maxLines: null, minLines: 1,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: _cellDecoration('Item / Service'),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              onChanged: (v) => setState(() => item.itemDetails = v),
            ))),
          // HSN/SAC
          SizedBox(width: _colHsn, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: TextFormField(
              initialValue: item.hsnCode.isNotEmpty ? item.hsnCode : item.sacCode,
              decoration: _cellDecoration('HSN/SAC'),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              onChanged: (v) => setState(() { item.hsnCode = v; item.sacCode = v; }),
            ))),
          // Unit
          SizedBox(width: _colUnit, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: DropdownButtonFormField<String>(
              value: _kUnits.contains(item.unit) ? item.unit : 'Nos',
              decoration: _cellDecoration(null),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              isDense: true,
              items: _kUnits.map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setState(() => item.unit = v ?? 'Nos'),
            ))),
          // Qty
          SizedBox(width: _colQty, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
          SizedBox(width: _colRate, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: TextFormField(
              initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
              decoration: _cellDecoration('0.00'),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) { setState(() { item.rate = double.tryParse(v) ?? 0; _calculateAmounts(); }); },
            ))),
          // Discount
          SizedBox(width: _colDisc, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
          // GST %
          SizedBox(width: _colGst, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: DropdownButtonFormField<double>(
              value: _kGstRates.contains(item.itemGstRate) ? item.itemGstRate : 18.0,
              decoration: _cellDecoration(null),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              isDense: true,
              items: _kGstRates.map((r) => DropdownMenuItem(value: r, child: Text('${r.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) { setState(() { item.itemGstRate = v ?? 18.0; _calculateAmounts(); }); },
            ))),
          // Taxable
          SizedBox(width: _colTaxable, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(item.taxableAmount > 0 ? '₹${item.taxableAmount.toStringAsFixed(2)}' : '—',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87)))),
          // CGST or IGST
          SizedBox(width: _colTax1, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                _isInterState
                    ? (item.igstAmount > 0 ? '₹${item.igstAmount.toStringAsFixed(2)}' : '—')
                    : (item.cgstAmount > 0 ? '₹${item.cgstAmount.toStringAsFixed(2)}' : '—'),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                    color: _isInterState ? Colors.orange[700] : Colors.blue[700]),
              ),
              if (item.itemGstRate > 0)
                Text(_isInterState ? '${item.itemGstRate.toStringAsFixed(0)}%' : '${(item.itemGstRate / 2).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            ]))),
          // SGST (intra-state only)
          if (!_isInterState)
            SizedBox(width: _colTax2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(item.sgstAmount > 0 ? '₹${item.sgstAmount.toStringAsFixed(2)}' : '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.blue[700])),
                if (item.itemGstRate > 0)
                  Text('${(item.itemGstRate / 2).toStringAsFixed(1)}%', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ]))),
          // Amount
          SizedBox(width: _colAmt, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('₹${item.amount.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)))),
          // Delete
          SizedBox(width: _colDel, child: IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
            onPressed: () => _removeItem(index),
          )),
        ]),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // NOTES SECTION
  // -----------------------------------------------------------------------

  Widget _buildNotesSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Additional Information', Icons.note_alt),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            decoration: InputDecoration(
              labelText: 'Notes',
              hintText: 'Internal notes about this credit',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // TAX SECTION (Sidebar)
  // -----------------------------------------------------------------------

  Widget _buildTaxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Tax Settings', Icons.calculate),
        const SizedBox(height: 16),
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
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => setState(() { _tdsRate = double.tryParse(v) ?? 0; _calculateAmounts(); }),
          ),
        ],
        const SizedBox(height: 12),
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

  // -----------------------------------------------------------------------
  // SUMMARY SECTION (Sidebar)
  // -----------------------------------------------------------------------

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Credit Summary', Icons.summarize),
        const SizedBox(height: 16),
        _summaryRow('Sub Total', _subTotal),
        if (_isInterState) ...[
          if (_totalIGST > 0) ...[const SizedBox(height: 6), _summaryRow('IGST', _totalIGST)],
        ] else ...[
          if (_totalCGST > 0) ...[const SizedBox(height: 6), _summaryRow('CGST', _totalCGST)],
          if (_totalSGST > 0) ...[const SizedBox(height: 6), _summaryRow('SGST', _totalSGST)],
        ],
        if (_enableTDS && _tdsAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)', -_tdsAmount, color: Colors.red[700]),
        ],
        if (_enableTCS && _tcsAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmount),
        ],
        const Divider(thickness: 2),
        const SizedBox(height: 6),
        _summaryRow('Total Credit Amount', _totalAmount, isBold: true, isTotal: true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_navyDark.withOpacity(0.1), _navyLight.withOpacity(0.1)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _navyAccent.withOpacity(0.3)),
          ),
          child: Column(children: [
            _infoRow('Items:', _items.where((i) => i.itemDetails.isNotEmpty).length.toString()),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Vendor Credit'),
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
              foregroundColor: _navyMid,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: _navyMid),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // VENDOR SELECTOR
  // -----------------------------------------------------------------------

  Future<void> _showVendorSelector() async {
    final searchCtrl = TextEditingController();
    List<BillingVendor> vendors = [];
    List<BillingVendor> filtered = [];
    bool loading = true;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (loading && vendors.isEmpty) {
            BillingVendorsService.getAllVendors(
              sortBy: 'vendorName',
              sortOrder: 'asc',
              limit: 1000,
            ).then((result) {
              if (result['success'] == true) {
                final list = (result['data']['vendors'] as List)
                    .map((j) => BillingVendor.fromJson(j))
                    .toList();
                setS(() { vendors = list; filtered = list; loading = false; });
              } else {
                setS(() { error = result['message']; loading = false; });
              }
            }).catchError((e) => setS(() { error = e.toString(); loading = false; }));
          }

          return AlertDialog(
            title: const Text('Select Vendor'),
            content: SizedBox(
              width: 480,
              height: 400,
              child: Column(children: [
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search vendors...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) {
                    setS(() {
                      filtered = v.isEmpty
                          ? vendors
                          : vendors.where((vd) =>
                              vd.vendorName.toLowerCase().contains(v.toLowerCase()) ||
                              vd.email.toLowerCase().contains(v.toLowerCase())).toList();
                    });
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                          ? Center(child: Text('Error: $error', style: const TextStyle(color: Colors.red)))
                          : filtered.isEmpty
                              ? const Center(child: Text('No vendors found'))
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final v = filtered[i];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _navyAccent,
                                        child: Text(v.vendorName[0].toUpperCase(),
                                            style: const TextStyle(color: Colors.white)),
                                      ),
                                      title: Text(v.vendorName),
                                      subtitle: Text(v.email),
                                      onTap: () {
                                        setState(() {
                                          _selectedVendorId    = v.id;
                                          _selectedVendorName  = v.vendorName;
                                          _selectedVendorEmail = v.email;
                                          _selectedVendorPhone = v.phoneNumber;
                                          _selectedVendorGSTIN = v.gstNumber.isNotEmpty ? v.gstNumber : null;
                                          _selectedVendorPAN   = v.panNumber.isNotEmpty ? v.panNumber : null;
                                          _gstRegistrationType = v.gstRegistrationType;
                                          _billingAddress      = v.billingAddress;
                                          _shippingAddress     = v.shippingAddress.isEmpty ? v.billingAddress : v.shippingAddress;
                                          _sameAsBilling       = v.shippingAddress.isEmpty;
                                          if (v.placeOfSupply.isNotEmpty) {
                                            _placeOfSupply = v.placeOfSupply;
                                            _updateInterState();
                                          }
                                        });
                                        Navigator.pop(ctx);
                                      },
                                    );
                                  },
                                ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _addNewVendor();
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addNewVendor() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewVendorPage()),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedVendorId    = result['id'];
        _selectedVendorName  = result['vendorName'];
        _selectedVendorEmail = result['email'];
        _selectedVendorPhone = result['phoneNumber'] ?? result['phone'] ?? '';
        _selectedVendorGSTIN = result['gstNumber'];
        _selectedVendorPAN   = result['panNumber'];
        _gstRegistrationType = result['gstRegistrationType'] ?? '';
      });
    }
  }

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
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

  Widget _summaryRow(String label, double amount, {Color? color, bool isBold = false, bool isTotal = false}) {
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
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _navyDark)),
    ]);
  }
}