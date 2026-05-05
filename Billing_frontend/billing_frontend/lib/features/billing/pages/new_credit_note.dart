import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/credit_note_service.dart';
import '../widgets/document_preview_buttons.dart';
import '../../../../core/services/invoice_service.dart' as invoice_svc;
import '../../../../core/services/invoice_service.dart'
    show Address, BillingCustomer;
import '../../../../core/services/item_billing_service.dart';
import 'new_customer.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

const List<double> _kGstRates = [0, 5, 12, 18, 28];
const List<String> _kUnits    = ['Nos','Hrs','Kg','Pcs','Box','Mtr','Ltr','Dz','MT','Set'];

const List<String> kIndianStates = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh',
  'Assam', 'Bihar', 'Chandigarh', 'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat',
  'Haryana', 'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand',
  'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep', 'Madhya Pradesh',
  'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha',
  'Puducherry', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana',
  'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
];

// Column widths — same as new_invoice.dart
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

class NewCreditNoteScreen extends StatefulWidget {
  final String? creditNoteId;
  final String? invoiceId;
  const NewCreditNoteScreen({Key? key, this.creditNoteId, this.invoiceId})
      : super(key: key);

  @override
  State<NewCreditNoteScreen> createState() => _NewCreditNoteScreenState();
}

class _NewCreditNoteScreenState extends State<NewCreditNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Controllers
  final _referenceNumberController   = TextEditingController();
  final _reasonDescriptionController = TextEditingController();
  final _customerNotesController     = TextEditingController();
  final _internalNotesController     = TextEditingController();
  final List<TextEditingController> _descControllers = [];

  // Customer
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;
  String  _customerGSTIN           = '';
  String  _customerPAN             = '';
  String  _gstRegistrationType     = '';
  Address? _billingAddress;

  // Invoice ref
  String? _selectedInvoiceId;
  String? _selectedInvoiceNumber;

  // Credit note details
  DateTime _creditNoteDate  = DateTime.now();
  String   _selectedReason  = 'Product Returned';
  String   _placeOfSupply   = '';
  String   _orgState        = '';
  bool     _isInterState    = false;

  final List<String> _reasonOptions = [
    'Product Returned','Order Cancelled','Pricing Error',
    'Damaged Goods','Quality Issue','Other',
  ];

  // Tax
  double _tdsRate   = 0;
  double _tcsRate   = 0;
  bool   _enableTDS = false;
  bool   _enableTCS = false;
  bool   _enableGST = true;

  // Items
  List<CreditNoteItemRow> _items = [];

  // Totals
  double _subTotal     = 0;
  double _taxableTotal = 0;
  double _totalCGST    = 0;
  double _totalSGST    = 0;
  double _totalIGST    = 0;
  double _totalTax     = 0;
  double _tdsAmount    = 0;
  double _tcsAmount    = 0;
  double _totalAmount  = 0;
  int    _totalQuantity = 0;

  // Available items
  List<Map<String, dynamic>> _availableItems  = [];
  bool _isLoadingItems = false;

  @override
  void initState() {
    super.initState();
    _addNewItem();
    _loadAvailableItems();
    _loadOrgState();
    if (widget.creditNoteId != null) {
      _loadCreditNoteData();
    } else if (widget.invoiceId != null) {
      _loadInvoiceData();
    }
  }

  @override
  void dispose() {
    _referenceNumberController.dispose();
    _reasonDescriptionController.dispose();
    _customerNotesController.dispose();
    _internalNotesController.dispose();
    for (final c in _descControllers) { c.dispose(); }
    super.dispose();
  }

  // ── Org state ──────────────────────────────────────────────────────────────
  Future<void> _loadOrgState() async {
    try {
      final response = await invoice_svc.InvoiceService.getOrgState();
      setState(() => _orgState = response.state);
      _updateInterState();
    } catch (e) { print('Error loading org state: $e'); }
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

  // ── Items ──────────────────────────────────────────────────────────────────
  void _addNewItem() {
    setState(() {
      _items.add(CreditNoteItemRow(itemGstRate: 18));
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
      _subTotal      = 0;
      _totalQuantity = 0;
      _totalCGST     = 0;
      _totalSGST     = 0;
      _totalIGST     = 0;

      for (final item in _items) {
        if (item.quantity <= 0 || item.rate <= 0) continue;

        double taxable = item.quantity * item.rate;
        if (item.discount > 0) {
          taxable = item.discountType == 'percentage'
              ? taxable - (taxable * item.discount / 100)
              : taxable - item.discount;
        }
        taxable       = double.parse(taxable.toStringAsFixed(2));
        item.taxableAmount = taxable;
        _subTotal     += taxable;
        _totalQuantity += item.quantity.toInt();

        final gst = item.itemGstRate;
        if (_isInterState) {
          item.igstAmount = double.parse((taxable * gst / 100).toStringAsFixed(2));
          item.cgstAmount = 0;
          item.sgstAmount = 0;
          _totalIGST += item.igstAmount;
        } else {
          item.cgstAmount = double.parse((taxable * (gst / 2) / 100).toStringAsFixed(2));
          item.sgstAmount = item.cgstAmount;
          item.igstAmount = 0;
          _totalCGST += item.cgstAmount;
          _totalSGST += item.sgstAmount;
        }
        item.amount = taxable + item.cgstAmount + item.sgstAmount + item.igstAmount;
      }

      _taxableTotal = _subTotal;
      _totalTax     = double.parse((_totalCGST + _totalSGST + _totalIGST).toStringAsFixed(2));
      _tdsAmount    = _enableTDS ? double.parse((_taxableTotal * _tdsRate / 100).toStringAsFixed(2)) : 0;
      _tcsAmount    = _enableTCS ? double.parse((_taxableTotal * _tcsRate / 100).toStringAsFixed(2)) : 0;
      _totalAmount  = double.parse((_taxableTotal + _totalTax - _tdsAmount + _tcsAmount).toStringAsFixed(2));
    });
  }

  // ── Data loading ───────────────────────────────────────────────────────────
  Future<void> _loadAvailableItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final items = await ItemBillingService().fetchAllItems(isSellable: true);
      setState(() { _availableItems = items; });
    } catch (e) { print('Error loading items: $e'); }
    finally { setState(() => _isLoadingItems = false); }
  }

  Future<void> _loadCreditNoteData() async {
    setState(() => _isLoading = true);
    try {
      final cn = await CreditNoteService.getCreditNote(widget.creditNoteId!);
      for (final c in _descControllers) { c.dispose(); }
      _descControllers.clear();
      setState(() {
        _selectedCustomerId    = cn.customerId;
        _selectedCustomerName  = cn.customerName;
        _selectedCustomerEmail = cn.customerEmail;
        _selectedCustomerPhone = cn.customerPhone;
        _customerGSTIN         = cn.customerGSTIN;
        _placeOfSupply         = cn.placeOfSupply;
        _billingAddress        = cn.billingAddress;
        _selectedInvoiceId     = cn.invoiceId;
        _selectedInvoiceNumber = cn.invoiceNumber;
        _referenceNumberController.text   = cn.referenceNumber ?? '';
        _creditNoteDate        = cn.creditNoteDate;
        _selectedReason        = cn.reason;
        _reasonDescriptionController.text = cn.reasonDescription ?? '';
        _customerNotesController.text     = cn.customerNotes ?? '';
        _internalNotesController.text     = cn.internalNotes ?? '';
        _enableTDS = cn.tdsRate > 0; _tdsRate = cn.tdsRate;
        _enableTCS = cn.tcsRate > 0; _tcsRate = cn.tcsRate;
        _enableGST = cn.gstRate > 0;
        _items = cn.items.map((i) => CreditNoteItemRow(
          itemDetails:  i.itemDetails,
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
    } catch (e) { _showError('Failed to load credit note: $e'); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _loadInvoiceData() async {
    setState(() => _isLoading = true);
    try {
      final invoice = await invoice_svc.InvoiceService.getInvoice(widget.invoiceId!);
      for (final c in _descControllers) { c.dispose(); }
      _descControllers.clear();
      setState(() {
        _selectedCustomerId    = invoice.customerId;
        _selectedCustomerName  = invoice.customerName;
        _selectedCustomerEmail = invoice.customerEmail;
        _selectedCustomerPhone = invoice.customerPhone;
        _billingAddress        = Address(
          street: invoice.billingAddress.street,
          city:   invoice.billingAddress.city,
          state:  invoice.billingAddress.state,
          pincode:invoice.billingAddress.zip,
          country:invoice.billingAddress.country,
        );
        _enableTDS = invoice.tdsRate > 0; _tdsRate = invoice.tdsRate;
        _enableTCS = invoice.tcsRate > 0; _tcsRate = invoice.tcsRate;
        _placeOfSupply = invoice.placeOfSupply;
        _items = invoice.items.map((i) => CreditNoteItemRow(
          itemDetails:  i.itemDetails,
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
    } catch (e) { _showError('Failed to load invoice: $e'); }
    finally { setState(() => _isLoading = false); }
  }

  // ── Invoice selector ───────────────────────────────────────────────────────
  Future<void> _showInvoiceSelector() async {
    try {
      final response = await invoice_svc.InvoiceService.getInvoices(
          customerId: _selectedCustomerId);
      final unpaid = response.invoices.where((inv) =>
        ['SENT','UNPAID','OVERDUE','PARTIALLY_PAID'].contains(inv.status)).toList();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Select Invoice'),
          content: SizedBox(
            width: 500, height: 400,
            child: unpaid.isEmpty
                ? const Center(child: Text('No unpaid invoices found'))
                : ListView.builder(
                    itemCount: unpaid.length,
                    itemBuilder: (_, i) {
                      final inv = unpaid[i];
                      return ListTile(
                        leading: const Icon(Icons.receipt, color: Color(0xFFE74C3C)),
                        title: Text(inv.invoiceNumber,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            'Due: ₹${inv.amountDue.toStringAsFixed(2)} • ${inv.status}'),
                        onTap: () {
                          for (final c in _descControllers) { c.dispose(); }
                          _descControllers.clear();
                          setState(() {
                            _selectedInvoiceId     = inv.id;
                            _selectedInvoiceNumber = inv.invoiceNumber;
                            _items = inv.items.map((it) => CreditNoteItemRow(
                              itemDetails:  it.itemDetails,
                              quantity:     it.quantity,
                              rate:         it.rate,
                              discount:     it.discount,
                              discountType: it.discountType,
                              itemGstRate:  it.itemGstRate,
                              amount:       it.amount,
                            )).toList();
                            for (final item in _items) {
                              _descControllers.add(
                                  TextEditingController(text: item.itemDetails));
                            }
                            _placeOfSupply = inv.placeOfSupply;
                            _enableTDS = inv.tdsRate > 0; _tdsRate = inv.tdsRate;
                            _enableTCS = inv.tcsRate > 0; _tcsRate = inv.tcsRate;
                            _updateInterState();
                            _calculateAmounts();
                          });
                          Navigator.pop(context);
                        },
                      );
                    }),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'))
          ],
        ),
      );
    } catch (e) { _showError('Failed to load invoices: $e'); }
  }

  // ── Validation ─────────────────────────────────────────────────────────────
  bool _validate() {
    if (!_formKey.currentState!.validate()) return false;
    if (_selectedCustomerId == null) {
      _showError('Please select a customer'); return false;
    }
    final nonEmpty =
        _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      _showError('Please add at least one item'); return false;
    }
    for (final i in nonEmpty) {
      if (i.quantity <= 0) { _showError('All items must have quantity > 0'); return false; }
      if (i.rate     <= 0) { _showError('All items must have rate > 0');     return false; }
    }
    return true;
  }

  // ── Build data ─────────────────────────────────────────────────────────────
  Map<String, dynamic> _buildCreditNoteData(String status) {
    final valid = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    return {
      'customerId':       _selectedCustomerId,
      'customerName':     _selectedCustomerName,
      'customerEmail':    _selectedCustomerEmail,
      'customerPhone':    _selectedCustomerPhone,
      'customerGSTIN':    _customerGSTIN,
      if (_billingAddress != null) 'billingAddress': _billingAddress!.toJson(),
      if (_selectedInvoiceId     != null) 'invoiceId':     _selectedInvoiceId,
      if (_selectedInvoiceNumber != null) 'invoiceNumber': _selectedInvoiceNumber,
      'referenceNumber':  _referenceNumberController.text.trim(),
      'creditNoteDate':   _creditNoteDate.toIso8601String(),
      'reason':           _selectedReason,
      'reasonDescription':_reasonDescriptionController.text.trim(),
      'items': valid.map((i) => i.toJson()).toList(),
      'customerNotes':    _customerNotesController.text.trim(),
      'internalNotes':    _internalNotesController.text.trim(),
      'tdsRate':  _enableTDS ? _tdsRate : 0,
      'tcsRate':  _enableTCS ? _tcsRate : 0,
      'gstRate':  18,
      'placeOfSupply': _placeOfSupply,
      'status':   status,
    };
  }

  // ── Save actions ───────────────────────────────────────────────────────────
  Future<void> _saveAsDraft() async {
    if (!_validate()) return;
    setState(() => _isSaving = true);
    try {
      final data = _buildCreditNoteData('DRAFT');
      if (widget.creditNoteId != null) {
        await CreditNoteService.updateCreditNote(widget.creditNoteId!, data);
      } else {
        await CreditNoteService.createCreditNote(data);
      }
      _showSuccess('Credit note saved as draft');
      Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally { setState(() => _isSaving = false); }
  }

  Future<void> _saveAndSend() async {
    if (!_validate()) return;
    if (_selectedCustomerEmail == null || _selectedCustomerEmail!.isEmpty) {
      _showError('Customer email is required to send credit note'); return;
    }
    setState(() => _isSaving = true);
    try {
      final data = _buildCreditNoteData('OPEN');
      CreditNote cn;
      if (widget.creditNoteId != null) {
        cn = await CreditNoteService.updateCreditNote(widget.creditNoteId!, data);
      } else {
        cn = await CreditNoteService.createCreditNote(data);
      }
      await CreditNoteService.sendCreditNote(cn.id);
      _showSuccess('Credit note sent to $_selectedCustomerEmail');
      Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally { setState(() => _isSaving = false); }
  }

  Future<void> _markAsSent() async {
    if (!_validate()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Sent?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'The email will NOT be sent to the customer.\n\nDo you want to mark this credit note as Sent anyway?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
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
      final data = _buildCreditNoteData('OPEN');
      CreditNote cn;
      if (widget.creditNoteId != null) {
        cn = await CreditNoteService.updateCreditNote(widget.creditNoteId!, data);
      } else {
        cn = await CreditNoteService.createCreditNote(data);
      }
      await CreditNoteService.markCreditNoteAsSent(cn.id);
      _showSuccess('Credit note marked as sent');
      Navigator.pop(context, true);
    } catch (e) { _showError(e.toString()); }
    finally { setState(() => _isSaving = false); }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating));

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
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
                  return Row(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Expanded(flex: 3, child: _buildMainContent()),
                    Container(
                      width: 340, color: Colors.white,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          _buildTaxSettingsSection(),
                          const Divider(height: 28),
                          _buildSummarySection(),
                        ]),
                      ),
                    ),
                  ]);
                }
                return SingleChildScrollView(child: Column(children: [
                  _buildMainContent(),
                  Container(color: Colors.white, padding: const EdgeInsets.all(20),
                      child: Column(children: [
                    _buildTaxSettingsSection(),
                    const Divider(height: 28),
                    _buildSummarySection(),
                  ])),
                ]));
              }),
            ),
    );
  }

  // ── App Bar (gradient like new_invoice.dart) ───────────────────────────────
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
          backgroundColor: Colors.transparent, elevation: 0,
          foregroundColor: Colors.white,
          title: Text(
            widget.creditNoteId != null ? 'Edit Credit Note' : 'New Credit Note',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            if (widget.creditNoteId != null) ...[
              IconButton(
                tooltip: 'View PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined,
                    color: Colors.white70, size: 20),
                onPressed: () => openDocumentPdf(
                    context: context, docId: widget.creditNoteId,
                    pdfEndpoint: '/api/finance/credit-notes', docNumber: 'CN'),
              ),
              IconButton(
                tooltip: 'Preview Email',
                icon: const Icon(Icons.email_outlined,
                    color: Colors.white70, size: 20),
                onPressed: () => openEmailPreview(
                    context: context, docId: widget.creditNoteId,
                    emailEndpoint: '/api/finance/credit-notes'),
              ),
            ],
            TextButton.icon(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              label: const Text('Cancel',
                  style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
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
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAndSend,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save & Send'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _navyAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12)),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  // ── Main content ───────────────────────────────────────────────────────────
  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildCustomerSection(),
        const SizedBox(height: 20),
        _buildCreditNoteDetailsSection(),
        const SizedBox(height: 20),
        _buildPlaceOfSupplySection(),
        const SizedBox(height: 20),
        _buildItemsSection(),
        const SizedBox(height: 20),
        _buildNotesSection(),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
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

  // ── Customer Section ───────────────────────────────────────────────────────
  Widget _buildCustomerSection() {
    return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Customer Information', Icons.person_outline),
      const SizedBox(height: 16),

      // Customer selector button
      InkWell(
        onTap: _showCustomerSelector,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.person_outline, color: _navyAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _selectedCustomerName ?? 'Select Customer *',
              style: TextStyle(
                fontSize: 15,
                color: _selectedCustomerName != null
                    ? _navyDark : Colors.grey[600],
                fontWeight: _selectedCustomerName != null
                    ? FontWeight.w600 : FontWeight.normal,
              ),
            )),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ]),
        ),
      ),

      // Customer details (same as new_invoice.dart)
      if (_selectedCustomerEmail != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(_selectedCustomerEmail!,
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ]),
      ],
      if (_customerGSTIN.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.business, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text('GSTIN: $_customerGSTIN',
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          if (_customerPAN.isNotEmpty) ...[
            const SizedBox(width: 16),
            Text('PAN: $_customerPAN',
                style: TextStyle(color: Colors.grey[700], fontSize: 13)),
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
          child: Text(_gstRegistrationType,
              style: TextStyle(
                  fontSize: 12,
                  color: _navyMid,
                  fontWeight: FontWeight.w500)),
        ),
      ],

      // Invoice selector
      if (_selectedCustomerId != null) ...[
        const SizedBox(height: 12),
        InkWell(
          onTap: _showInvoiceSelector,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.receipt_long, color: _navyAccent),
              const SizedBox(width: 12),
              Expanded(child: Text(
                _selectedInvoiceNumber ?? 'Select Invoice (Optional)',
                style: TextStyle(
                  fontSize: 15,
                  color: _selectedInvoiceNumber != null
                      ? _navyDark : Colors.grey[600],
                ),
              )),
              const Icon(Icons.arrow_drop_down, color: Colors.grey),
            ]),
          ),
        ),
      ],
    ]));
  }

  // ── Credit Note Details ────────────────────────────────────────────────────
  Widget _buildCreditNoteDetailsSection() {
    return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Credit Note Details', Icons.receipt_long),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (ctx, cs) {
        final isWide = cs.maxWidth > 600;
        final refField = TextFormField(
          controller: _referenceNumberController,
          decoration: InputDecoration(
            labelText: 'Reference Number', hintText: 'Optional',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.numbers),
          ),
        );
        final dateField = InkWell(
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: _creditNoteDate,
                firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (d != null) setState(() => _creditNoteDate = d);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Credit Note Date *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.calendar_today),
            ),
            child:
                Text(DateFormat('dd MMM yyyy').format(_creditNoteDate)),
          ),
        );
        return isWide
            ? Row(children: [
                Expanded(child: refField),
                const SizedBox(width: 16),
                Expanded(child: dateField)
              ])
            : Column(children: [
                refField, const SizedBox(height: 16), dateField
              ]);
      }),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        value: _selectedReason,
        decoration: InputDecoration(
          labelText: 'Reason *',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.report_problem_outlined),
        ),
        items: _reasonOptions
            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
            .toList(),
        onChanged: (v) => setState(() => _selectedReason = v!),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _reasonDescriptionController,
        decoration: InputDecoration(
          labelText: 'Reason Description',
          hintText: 'Explain the reason for this credit note',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.description),
        ),
        maxLines: 3,
      ),
    ]));
  }

  // ── Place of Supply ────────────────────────────────────────────────────────
  Widget _buildPlaceOfSupplySection() {
    return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Place of Supply', Icons.location_on_outlined),
      const SizedBox(height: 8),
      Text('Determines CGST+SGST (same state) or IGST (different state)',
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
        items: kIndianStates
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (v) {
          setState(() => _placeOfSupply = v ?? '');
          _updateInterState();
        },
      ),
      if (_placeOfSupply.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isInterState ? Colors.orange[50] : Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: _isInterState
                    ? Colors.orange[300]! : Colors.green[300]!),
          ),
          child: Row(children: [
            Icon(
              _isInterState
                  ? Icons.swap_horiz : Icons.check_circle_outline,
              color: _isInterState
                  ? Colors.orange[700] : Colors.green[700],
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _isInterState
                  ? 'Inter-State: IGST will be applied'
                  : 'Intra-State: CGST + SGST will be applied',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: _isInterState
                    ? Colors.orange[900] : Colors.green[900],
              ),
            )),
          ]),
        ),
      ],
    ]));
  }

  // ── Items Section ──────────────────────────────────────────────────────────
  Widget _buildItemsSection() {
    final bool isInterState = _isInterState;

    final double tableWidth = _colNo + _colDesc + _colHsn + _colUnit +
        _colQty + _colRate + _colDisc + _colGst + _colTaxable +
        _colTax1 + (isInterState ? 0 : _colTax2) + _colAmt + _colDel;

    return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _sectionTitle('Items', Icons.list_alt),
        if (_placeOfSupply.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isInterState
                  ? Colors.orange[50] : Colors.blue[50],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isInterState
                      ? Colors.orange[300]! : Colors.blue[300]!),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                isInterState
                    ? Icons.swap_horiz : Icons.check_circle_outline,
                size: 14,
                color: isInterState
                    ? Colors.orange[700] : Colors.blue[700],
              ),
              const SizedBox(width: 5),
              Text(
                isInterState ? 'IGST' : 'CGST + SGST',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold,
                    color: isInterState
                        ? Colors.orange[800] : Colors.blue[800]),
              ),
            ]),
          ),
      ]),
      const SizedBox(height: 14),

      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Table header
            Container(
              decoration: BoxDecoration(
                color: _navyDark,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8)),
              ),
              child: Row(children: [
                _thCell('#',          _colNo),
                _thCell('DESCRIPTION',_colDesc),
                _thCell('HSN / SAC',  _colHsn),
                _thCell('UNIT',       _colUnit),
                _thCell('QTY',        _colQty,     align: TextAlign.center),
                _thCell('RATE (₹)',   _colRate,    align: TextAlign.right),
                _thCell('DISCOUNT',   _colDisc,    align: TextAlign.right),
                _thCell('GST %',      _colGst,     align: TextAlign.center),
                _thCell('TAXABLE',    _colTaxable, align: TextAlign.right),
                if (isInterState)
                  _thCell('IGST', _colTax1, align: TextAlign.right)
                else ...[
                  _thCell('CGST', _colTax1, align: TextAlign.right),
                  _thCell('SGST', _colTax2, align: TextAlign.right),
                ],
                _thCell('AMOUNT',     _colAmt,     align: TextAlign.right),
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
                    left:   BorderSide(color: Colors.grey[200]!),
                    right:  BorderSide(color: Colors.grey[200]!),
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
              ...List.generate(
                  _items.length, (i) => _buildItemRow(i, isInterState)),

            // Add item row
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
                    left:   BorderSide(color: _navyAccent.withOpacity(0.25)),
                    right:  BorderSide(color: _navyAccent.withOpacity(0.25)),
                    bottom: BorderSide(color: _navyAccent.withOpacity(0.25)),
                  ),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_circle_outline, size: 18, color: _navyAccent),
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
    ]));
  }

  Widget _thCell(String text, double width,
      {TextAlign align = TextAlign.left}) {
    return SizedBox(
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
  }

  // ── Single item row ────────────────────────────────────────────────────────
  Widget _buildItemRow(int index, bool isInterState) {
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
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, children: [
          // #
          SizedBox(
            width: _colNo,
            child: Center(
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54)))),

          // Description — multiline, Enter = new line
          SizedBox(
            width: _colDesc,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: _isLoadingItems
                  ? const SizedBox(
                      height: 48,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Autocomplete<Map<String, dynamic>>(
                      optionsBuilder: (tv) {
                        if (tv.text.isEmpty) return const [];
                        return _availableItems.where((it) => it['name']
                            .toString()
                            .toLowerCase()
                            .contains(tv.text.toLowerCase()));
                      },
                      displayStringForOption: (o) =>
                          o['name'].toString(),
                      onSelected: (sel) {
                        setState(() {
                          item.itemDetails = sel['name'].toString();
                          item.rate =
                              (sel['sellingPrice'] ?? 0).toDouble();
                          descCtrl.text = item.itemDetails;
                          _calculateAmounts();
                        });
                      },
                      fieldViewBuilder:
                          (ctx, ctrl, focus, onSubmit) {
                        if (item.itemDetails.isNotEmpty &&
                            ctrl.text.isEmpty) {
                          ctrl.text = item.itemDetails;
                        }
                        return TextFormField(
                          controller: ctrl,
                          focusNode: focus,
                          maxLines: null,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: _cellDec('Item / Service'),
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
                          onChanged: (v) => item.itemDetails = v,
                        );
                      },
                    ),
            ),
          ),

          // HSN / SAC
          SizedBox(
            width: _colHsn,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.hsnCode,
                decoration: _cellDec('HSN/SAC'),
                style: const TextStyle(
                    fontSize: 13, color: Colors.black87),
                onChanged: (v) => setState(() => item.hsnCode = v),
              ),
            ),
          ),

          // Unit
          SizedBox(
            width: _colUnit,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: DropdownButtonFormField<String>(
                value: _kUnits.contains(item.unit) ? item.unit : 'Nos',
                decoration: _cellDec(null),
                style: const TextStyle(
                    fontSize: 13, color: Colors.black87),
                isDense: true,
                items: _kUnits
                    .toSet()
                    .toList()
                    .map((u) => DropdownMenuItem(
                        value: u,
                        child: Text(u,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87))))
                    .toList(),
                onChanged: (v) =>
                    setState(() => item.unit = v ?? 'Nos'),
              ),
            ),
          ),

          // Qty
          SizedBox(
            width: _colQty,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue:
                    item.quantity > 0 ? item.quantity.toString() : '',
                decoration: _cellDec('0'),
                style: const TextStyle(
                    fontSize: 13, color: Colors.black87),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                onChanged: (v) {
                  setState(() {
                    item.quantity = double.tryParse(v) ?? 0;
                    _calculateAmounts();
                  });
                },
              ),
            ),
          ),

          // Rate
          SizedBox(
            width: _colRate,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: TextFormField(
                initialValue: item.rate > 0
                    ? item.rate.toStringAsFixed(2) : '',
                decoration: _cellDec('0.00'),
                style: const TextStyle(
                    fontSize: 13, color: Colors.black87),
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                onChanged: (v) {
                  setState(() {
                    item.rate = double.tryParse(v) ?? 0;
                    _calculateAmounts();
                  });
                },
              ),
            ),
          ),

          // Discount
          SizedBox(
            width: _colDisc,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: Row(children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.discount > 0
                        ? item.discount.toString() : '',
                    decoration: _cellDec('0'),
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black87),
                    textAlign: TextAlign.right,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    onChanged: (v) {
                      setState(() {
                        item.discount = double.tryParse(v) ?? 0;
                        _calculateAmounts();
                      });
                    },
                  ),
                ),
                PopupMenuButton<String>(
                  initialValue: item.discountType,
                  padding: EdgeInsets.zero,
                  icon: Text(
                    item.discountType == 'percentage' ? '%' : '₹',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _navyAccent),
                  ),
                  onSelected: (v) => setState(() {
                    item.discountType = v;
                    _calculateAmounts();
                  }),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'percentage', child: Text('% Percentage')),
                    const PopupMenuItem(
                        value: 'amount', child: Text('₹ Flat Amount')),
                  ],
                ),
              ]),
            ),
          ),

          // GST %
          SizedBox(
            width: _colGst,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 6),
              child: DropdownButtonFormField<double>(
                value: _kGstRates.contains(item.itemGstRate)
                    ? item.itemGstRate : 18.0,
                decoration: _cellDec(null),
                style: const TextStyle(
                    fontSize: 13, color: Colors.black87),
                isDense: true,
                items: _kGstRates
                    .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text('${r.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87))))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    item.itemGstRate = v ?? 0.0;  // Default to 0% instead of 18%
                    _calculateAmounts();
                  });
                },
              ),
            ),
          ),

          // Taxable (read-only)
          SizedBox(
            width: _colTaxable,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.taxableAmount > 0
                    ? '₹${item.taxableAmount.toStringAsFixed(2)}' : '—',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87),
              ),
            ),
          ),

          // CGST or IGST
          SizedBox(
            width: _colTax1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(
                  isInterState
                      ? (item.igstAmount > 0
                          ? '₹${item.igstAmount.toStringAsFixed(2)}'
                          : '—')
                      : (item.cgstAmount > 0
                          ? '₹${item.cgstAmount.toStringAsFixed(2)}'
                          : '—'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isInterState
                          ? Colors.orange[700] : Colors.blue[700]),
                ),
                if (item.itemGstRate > 0)
                  Text(
                    isInterState
                        ? '${item.itemGstRate.toStringAsFixed(0)}%'
                        : '${(item.itemGstRate / 2).toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey[600]),
                  ),
              ]),
            ),
          ),

          // SGST (intra-state only)
          if (!isInterState)
            SizedBox(
              width: _colTax2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text(
                    item.sgstAmount > 0
                        ? '₹${item.sgstAmount.toStringAsFixed(2)}' : '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue[700]),
                  ),
                  if (item.itemGstRate > 0)
                    Text(
                        '${(item.itemGstRate / 2).toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[600])),
                ]),
              ),
            ),

          // Amount (read-only)
          SizedBox(
            width: _colAmt,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.amount > 0
                    ? '₹${item.amount.toStringAsFixed(2)}' : '—',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
            ),
          ),

          // Delete
          SizedBox(
            width: _colDel,
            child: Center(
                child: IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.red, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _removeItem(index),
            )),
          ),
        ]),
      ),
    );
  }

  InputDecoration _cellDec(String? hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 11, color: Colors.grey[400]),
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey[300]!)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: Colors.grey[300]!)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide:
            const BorderSide(color: _navyAccent, width: 1.5)),
    filled: true,
    fillColor: Colors.white,
  );

  // ── Notes ──────────────────────────────────────────────────────────────────
  Widget _buildNotesSection() {
    return _card(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Additional Information', Icons.note_alt),
      const SizedBox(height: 16),
      TextFormField(
        controller: _customerNotesController,
        decoration: InputDecoration(
          labelText: 'Customer Notes',
          hintText: 'Visible to customer',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          alignLabelWithHint: true,
        ),
        maxLines: 3,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _internalNotesController,
        decoration: InputDecoration(
          labelText: 'Internal Notes',
          hintText: 'Private — not visible to customer',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          alignLabelWithHint: true,
        ),
        maxLines: 3,
      ),
    ]));
  }

  // ── Tax Settings (sidebar) ─────────────────────────────────────────────────
  Widget _buildTaxSettingsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('TDS / TCS', Icons.percent),
      const SizedBox(height: 12),
      SwitchListTile(
        title: const Text('Enable TDS'),
        subtitle: const Text('Tax Deducted at Source',
            style: TextStyle(fontSize: 11)),
        value: _enableTDS, activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) =>
            setState(() { _enableTDS = v; _calculateAmounts(); }),
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
      const SizedBox(height: 8),
      SwitchListTile(
        title: const Text('Enable TCS'),
        subtitle: const Text('Tax Collected at Source',
            style: TextStyle(fontSize: 11)),
        value: _enableTCS, activeColor: _navyAccent,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) =>
            setState(() { _enableTCS = v; _calculateAmounts(); }),
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
    ]);
  }

  // ── Summary (sidebar) ──────────────────────────────────────────────────────
  Widget _buildSummarySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Credit Note Summary', Icons.summarize),
      const SizedBox(height: 16),
      _summaryRow('Sub Total', _subTotal),
      const SizedBox(height: 6),
      if (_isInterState) ...[
        if (_totalIGST > 0) ...[
          _summaryRow('IGST', _totalIGST), const SizedBox(height: 6),
        ],
      ] else ...[
        if (_totalCGST > 0) ...[
          _summaryRow('CGST', _totalCGST), const SizedBox(height: 6),
        ],
        if (_totalSGST > 0) ...[
          _summaryRow('SGST', _totalSGST), const SizedBox(height: 6),
        ],
      ],
      if (_totalTax > 0) ...[
        _summaryRow('Total Tax', _totalTax), const SizedBox(height: 6),
      ],
      if (_enableTDS && _tdsAmount > 0) ...[
        _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)',
            -_tdsAmount, color: Colors.red[700]),
        const SizedBox(height: 6),
      ],
      if (_enableTCS && _tcsAmount > 0) ...[
        _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmount),
        const SizedBox(height: 6),
      ],
      const Divider(thickness: 2),
      const SizedBox(height: 6),
      _summaryRow('Credit Amount', _totalAmount,
          isBold: true, isTotal: true),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _navyAccent.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _navyAccent.withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            const Text('Total Qty:',
                style: TextStyle(fontSize: 13, color: Color(0xFF34495E))),
            Text(_totalQuantity.toString(),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF34495E))),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            const Text('Total Items:',
                style: TextStyle(fontSize: 13, color: Color(0xFF34495E))),
            Text(
                _items
                    .where((i) => i.itemDetails.isNotEmpty)
                    .length
                    .toString(),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF34495E))),
          ]),
        ]),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveAndSend,
          icon: _isSaving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send, size: 16),
          label: Text(_isSaving ? 'Sending...' : 'Save & Send'),
          style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isSaving ? null : _saveAsDraft,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('Save as Draft'),
          style: OutlinedButton.styleFrom(
              foregroundColor: _navyMid,
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: _navyMid),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
        ),
      ),
    ]);
  }

  Widget _summaryRow(String label, double amount,
      {Color? color, bool isBold = false, bool isTotal = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
      Text(label,
          style: TextStyle(
              fontSize: isTotal ? 15 : 13,
              fontWeight:
                  isBold || isTotal ? FontWeight.bold : FontWeight.normal,
              color: color ??
                  (isTotal ? _navyDark : Colors.grey[700]))),
      Text(
          '${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
          style: TextStyle(
              fontSize: isTotal ? 17 : 13,
              fontWeight:
                  isBold || isTotal ? FontWeight.bold : FontWeight.w500,
              color: color ??
                  (isTotal ? _navyAccent : _navyDark))),
    ]);
  }

  // ── Customer Selector Dialog ───────────────────────────────────────────────
  Future<void> _showCustomerSelector() async {
    final searchCtrl = TextEditingController();
    List<BillingCustomer> customers = [];
    List<BillingCustomer> filtered  = [];
    bool isLoading = true;
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) {
        if (isLoading && customers.isEmpty) {
          invoice_svc.InvoiceService.getBillingCustomers()
              .then((r) => setDialog(() {
                    customers = r.customers;
                    filtered  = customers;
                    isLoading = false;
                  }))
              .catchError((e) => setDialog(() {
                    errorMsg  = e.toString();
                    isLoading = false;
                  }));
        }
        return AlertDialog(
          title: const Text('Select Customer'),
          content: SizedBox(
            width: 520, height: 440,
            child: Column(children: [
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setDialog(() {
                  filtered = v.isEmpty
                      ? customers
                      : customers
                          .where((c) =>
                              c.customerName
                                  .toLowerCase()
                                  .contains(v.toLowerCase()) ||
                              c.customerEmail
                                  .toLowerCase()
                                  .contains(v.toLowerCase()))
                          .toList();
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : errorMsg != null
                        ? Center(child: Text('Error: $errorMsg'))
                        : filtered.isEmpty
                            ? const Center(
                                child: Text('No customers found'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final c = filtered[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _navyAccent,
                                      child: Text(
                                        c.customerName.isNotEmpty
                                            ? c.customerName[0]
                                                .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                    title: Text(c.customerName,
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w600)),
                                    subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(c.customerEmail),
                                      Text(c.customerPhone),
                                    ]),
                                    onTap: () {
                                      setState(() {
                                        _selectedCustomerId    = c.id;
                                        _selectedCustomerName  = c.customerName;
                                        _selectedCustomerEmail = c.customerEmail;
                                        _selectedCustomerPhone = c.customerPhone;
                                        _customerGSTIN         = c.gstNumber;
                                        _customerPAN           = c.panNumber;
                                        _gstRegistrationType   = c.gstRegistrationType;
                                        if (c.billingAddress.street
                                                .isNotEmpty ||
                                            c.billingAddress.city
                                                .isNotEmpty) {
                                          _billingAddress = Address(
                                            street:  c.billingAddress.street,
                                            city:    c.billingAddress.city,
                                            state:   c.billingAddress.state,
                                            pincode: c.billingAddress.zip,
                                            country: c.billingAddress.country,
                                          );
                                        }
                                        if (c.billingAddress.state
                                            .isNotEmpty) {
                                          _placeOfSupply =
                                              c.billingAddress.state;
                                        }
                                      });
                                      _updateInterState();
                                      Navigator.pop(ctx);
                                    },
                                  );
                                }),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const NewCustomerPage()));
                    if (result == true) _showCustomerSelector();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add New Customer'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _navyAccent,
                      side:
                          const BorderSide(color: _navyAccent)),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'))
          ],
        );
      }),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// CREDIT NOTE ITEM ROW MODEL
// ══════════════════════════════════════════════════════════════════════════════

class CreditNoteItemRow {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double itemGstRate;
  String hsnCode;
  String unit;
  double taxableAmount;
  double cgstAmount;
  double sgstAmount;
  double igstAmount;
  double amount;

  CreditNoteItemRow({
    this.itemDetails  = '',
    this.quantity     = 0,
    this.rate         = 0,
    this.discount     = 0,
    this.discountType = 'percentage',
    this.itemGstRate  = 0,  // Default to 0% GST instead of 18%
    this.hsnCode      = '',
    this.unit         = 'Nos',
    this.taxableAmount= 0,
    this.cgstAmount   = 0,
    this.sgstAmount   = 0,
    this.igstAmount   = 0,
    this.amount       = 0,
  });

  Map<String, dynamic> toJson() => {
    'itemDetails':  itemDetails,
    'quantity':     quantity,
    'rate':         rate,
    'discount':     discount,
    'discountType': discountType,
    'itemGstRate':  itemGstRate,
    'hsnCode':      hsnCode,
    'unit':         unit,
    'taxableAmount':taxableAmount,
    'cgstAmount':   cgstAmount,
    'sgstAmount':   sgstAmount,
    'igstAmount':   igstAmount,
    'amount':       amount,
  };
}