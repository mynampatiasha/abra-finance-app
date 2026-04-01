// ============================================================================
// NEW VENDOR CREDIT SCREEN
// ============================================================================
// File: lib/screens/billing/pages/new_vendor_credit.dart
// UI matches new_bill.dart structure exactly
// Navy blue gradient theme
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

// Navy blue gradient colors
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewVendorCreditScreen extends StatefulWidget {
  final String? creditId;

  const NewVendorCreditScreen({Key? key, this.creditId}) : super(key: key);

  @override
  State<NewVendorCreditScreen> createState() => _NewVendorCreditScreenState();
}

class _NewVendorCreditScreenState extends State<NewVendorCreditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Controllers
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  final _termsController = TextEditingController();

  // Vendor
  String? _selectedVendorId;
  String? _selectedVendorName;
  String? _selectedVendorEmail;
  String? _selectedVendorPhone;
  String? _selectedVendorGSTIN;

  // Credit Details
  DateTime _creditDate = DateTime.now();
  String? _linkedBillId;
  String? _linkedBillNumber;
  Bill? _linkedBill; // stores full bill object after selection
bool _loadingBills = false;

  // Tax
  double _gstRate = 18;
  double _tdsRate = 0;
  double _tcsRate = 0;
  bool _enableGST = true;
  bool _enableTDS = false;
  bool _enableTCS = false;

  // Items
  List<MutableCreditItem> _items = [];

  // Calculations
  double _subTotal = 0;
  double _tdsAmount = 0;
  double _tcsAmount = 0;
  double _gstAmount = 0;
  double _totalAmount = 0;
  int _totalQty = 0;

  final List<String> _creditReasons = [
    'Goods Returned',
    'Overcharged by Vendor',
    'Quality Issue',
    'Advance Payment Excess',
    'Discount After Billing',
    'Duplicate Invoice',
    'Service Not Delivered',
    'Other',
  ];

  // Dynamic COA expense accounts — loaded from backend
  List<Map<String, dynamic>> _coaExpAccounts = [];
  bool _loadingCoaAccounts = false;

  @override
  void initState() {
    super.initState();
    _addItem();
    _loadCoaExpenseAccounts();
    if (widget.creditId != null) _loadCreditData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() => _items.add(MutableCreditItem()));
  }

  // ── Load COA Expense accounts from backend ──────────────────────────────────
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

  void _removeItem(int index) {
    setState(() { _items.removeAt(index); _calculate(); });
  }

  void _calculate() {
    setState(() {
      _subTotal = 0;
      _totalQty = 0;
      for (var item in _items) {
        if (item.quantity > 0 && item.rate > 0) {
          double amt = item.quantity * item.rate;
          if (item.discount > 0) {
            amt = item.discountType == 'percentage'
                ? amt - (amt * item.discount / 100)
                : amt - item.discount;
          }
          item.amount = amt;
          _subTotal += amt;
          _totalQty += item.quantity.toInt();
        }
      }
      _tdsAmount = _enableTDS ? (_subTotal * _tdsRate / 100) : 0;
      _tcsAmount = _enableTCS ? (_subTotal * _tcsRate / 100) : 0;
      final gstBase = _subTotal - _tdsAmount + _tcsAmount;
      _gstAmount = _enableGST ? (gstBase * _gstRate / 100) : 0;
      _totalAmount = _subTotal - _tdsAmount + _tcsAmount + _gstAmount;
    });
  }

  Future<void> _loadCreditData() async {
    setState(() => _isLoading = true);
    try {
      final credit = await VendorCreditService.getVendorCredit(widget.creditId!);
      setState(() {
        _selectedVendorId = credit.vendorId;
        _selectedVendorName = credit.vendorName;
        _selectedVendorEmail = credit.vendorEmail;
        _selectedVendorPhone = credit.vendorPhone;
        _selectedVendorGSTIN = credit.vendorGSTIN;
        _creditDate = credit.creditDate;
        _linkedBillId = credit.billId;
        _linkedBillNumber = credit.billNumber;
        _reasonController.text = credit.reason;
        _notesController.text = credit.notes ?? '';
        _gstRate = credit.gstRate;
        _tdsAmount = credit.tdsAmount;
        _tcsAmount = credit.tcsAmount;
        _enableGST = credit.gstRate > 0;
        _enableTDS = credit.tdsAmount > 0;
        _enableTCS = credit.tcsAmount > 0;
        _items = credit.items.map((i) => MutableCreditItem(
          itemDetails: i.itemDetails,
          account: i.account,
          quantity: i.quantity,
          rate: i.rate,
          discount: i.discount,
          discountType: i.discountType,
          amount: i.amount,
        )).toList();
        _calculate();
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
      if (item.rate <= 0) { _showError('All items must have rate > 0'); return false; }
    }
    return true;
  }

  Map<String, dynamic> _buildBody() {
    final valid = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    return {
      'vendorId': _selectedVendorId,
      'vendorName': _selectedVendorName,
      'vendorEmail': _selectedVendorEmail,
      'vendorPhone': _selectedVendorPhone ?? '',
      'vendorGSTIN': _selectedVendorGSTIN,
      'creditDate': _creditDate.toIso8601String(),
      'billId': _linkedBillId,
      'billNumber': _linkedBillNumber,
      'reason': _reasonController.text.trim(),
      'notes': _notesController.text.trim(),
      'items': valid.map((i) => i.toJson()).toList(),
      'gstRate': _enableGST ? _gstRate : 0,
      'tdsRate': _enableTDS ? _tdsRate : 0,
      'tcsRate': _enableTCS ? _tcsRate : 0,
      'subTotal': _subTotal,
      'cgst': _gstAmount / 2,
      'sgst': _gstAmount / 2,
      'tdsAmount': _tdsAmount,
      'tcsAmount': _tcsAmount,
      'totalAmount': _totalAmount,
      'status': 'OPEN',
    };
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
              child: Row(
                children: [
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
                ],
              ),
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
          if (_selectedVendorGSTIN != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.receipt_long, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text('GSTIN: $_selectedVendorGSTIN', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ]),
          ],
        ],
      ),
    );
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
                                      itemDetails: item['itemDetails']
                                              ?.toString() ??
                                          '',
                                      account:
                                          item['account']?.toString(),
                                      quantity:
                                          (item['quantity'] ?? 0)
                                              .toDouble(),
                                      rate: (item['rate'] ?? 0)
                                          .toDouble(),
                                      discount:
                                          (item['discount'] ?? 0)
                                              .toDouble(),
                                      discountType: item['discountType']
                                              ?.toString() ??
                                          'percentage',
                                      amount: (item['amount'] ?? 0)
                                          .toDouble(),
                                    ))
                                .toList();
                            // ✅ Auto-fill tax settings from bill
                            _gstRate =
                                (b['gstRate'] ?? 18).toDouble();
                            _tdsRate =
                                (b['tdsRate'] ?? 0).toDouble();
                            _tcsRate =
                                (b['tcsRate'] ?? 0).toDouble();
                            _enableGST = _gstRate > 0;
                            _enableTDS = _tdsRate > 0;
                            _enableTCS = _tcsRate > 0;
                            _calculate();
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

  // -----------------------------------------------------------------------
  // ITEMS SECTION
  // -----------------------------------------------------------------------

  Widget _buildItemsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Line Items', Icons.list_alt),
              ElevatedButton.icon(
                onPressed: _addItem,
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
          // Header
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
                return const Text('ITEMS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
              }
              return const Row(
                children: [
                  Expanded(flex: 3, child: Text('ITEM DETAILS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                  SizedBox(width: 8),
                  Expanded(flex: 2, child: Text('ACCOUNT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                  SizedBox(width: 8),
                  SizedBox(width: 70, child: Text('QTY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                  SizedBox(width: 8),
                  SizedBox(width: 90, child: Text('RATE (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                  SizedBox(width: 8),
                  SizedBox(width: 80, child: Text('DISCOUNT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                  SizedBox(width: 8),
                  SizedBox(width: 100, child: Text('AMOUNT (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                  SizedBox(width: 48),
                ],
              );
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
                  Text('No items added', style: TextStyle(color: Colors.grey[600])),
                ]),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
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
                    decoration: InputDecoration(labelText: 'Qty', border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), isDense: true),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) { item.quantity = double.tryParse(v) ?? 0; _calculate(); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
                    decoration: InputDecoration(labelText: 'Rate (₹)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) { item.rate = double.tryParse(v) ?? 0; _calculate(); },
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
                        style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                  ),
                ),
              ]),
            ],
          ),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: TextFormField(
            initialValue: item.itemDetails,
            decoration: InputDecoration(
              hintText: 'Enter item description',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            maxLines: 2,
            onChanged: (v) => item.itemDetails = v,
          )),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: DropdownButtonFormField<String>(
            value: item.account,
            decoration: InputDecoration(
              hintText: 'Account',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            isExpanded: true,
            items: _coaExpAccounts.map((a) => DropdownMenuItem(value: a['accountName'] as String, child: Text(a['accountName'] as String, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => item.account = v),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: TextFormField(
            initialValue: item.quantity > 0 ? item.quantity.toString() : '',
            decoration: InputDecoration(
              hintText: '0',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) { item.quantity = double.tryParse(v) ?? 0; _calculate(); },
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
            onChanged: (v) { item.rate = double.tryParse(v) ?? 0; _calculate(); },
          )),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Row(children: [
            Expanded(child: TextFormField(
              initialValue: item.discount > 0 ? item.discount.toString() : '',
              decoration: InputDecoration(
                hintText: '0',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              onChanged: (v) { item.discount = double.tryParse(v) ?? 0; _calculate(); },
            )),
            PopupMenuButton<String>(
              initialValue: item.discountType,
              icon: const Icon(Icons.arrow_drop_down, size: 16),
              onSelected: (v) => setState(() { item.discountType = v; _calculate(); }),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'percentage', child: Text('%')),
                const PopupMenuItem(value: 'amount', child: Text('₹')),
              ],
            ),
          ])),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _removeItem(index),
          ),
        ],
      );
    });
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
          title: const Text('Enable GST'),
          value: _enableGST,
          activeColor: _navyAccent,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() { _enableGST = v; _calculate(); }),
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
            onChanged: (v) => setState(() { _gstRate = double.tryParse(v) ?? 18; _calculate(); }),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Enable TDS'),
          subtitle: const Text('Tax Deducted at Source', style: TextStyle(fontSize: 11)),
          value: _enableTDS,
          activeColor: _navyAccent,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() { _enableTDS = v; _calculate(); }),
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
            onChanged: (v) => setState(() { _tdsRate = double.tryParse(v) ?? 0; _calculate(); }),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Enable TCS'),
          subtitle: const Text('Tax Collected at Source', style: TextStyle(fontSize: 11)),
          value: _enableTCS,
          activeColor: _navyAccent,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() { _enableTCS = v; _calculate(); }),
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
            onChanged: (v) => setState(() { _tcsRate = double.tryParse(v) ?? 0; _calculate(); }),
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
        _summaryRow('Total Credit Amount', _totalAmount, isBold: true, isTotal: true),
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
            _infoRow('Total Qty:', _totalQty.toString()),
            const SizedBox(height: 4),
            _infoRow('Items:', _items.where((i) => i.itemDetails.isNotEmpty).length.toString()),
          ]),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Vendor Credit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
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
                                          _selectedVendorId = v.id;
                                          _selectedVendorName = v.vendorName;
                                          _selectedVendorEmail = v.email;
                                          _selectedVendorPhone = v.phoneNumber;
                                          _selectedVendorGSTIN = null;
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
        _selectedVendorId = result['id'];
        _selectedVendorName = result['vendorName'];
        _selectedVendorEmail = result['email'];
        _selectedVendorPhone = result['phoneNumber'] ?? result['phone'] ?? '';
        _selectedVendorGSTIN = result['gstNumber'];
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