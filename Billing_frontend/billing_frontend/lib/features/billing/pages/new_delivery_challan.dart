// ============================================================================
// NEW DELIVERY CHALLAN SCREEN
// ============================================================================
// File: lib/features/admin/Billing/pages/new_delivery_challan.dart
//
// UI matches new_payment_made.dart EXACTLY:
// ✅ Gradient AppBar (_navyDark → _navyMid → _navyLight)
// ✅ Gradient icon box section titles (_sectionTitle)
// ✅ Desktop (>800px): left main (flex 3) + right 320px white sidebar
// ✅ Mobile (≤800px): stacked column layout
// ✅ Sidebar: Summary + action buttons (same pattern)
// ✅ Gradient table header for items
// ✅ Card: borderRadius 10, shadow offset (0,3), 0.05 opacity
// ✅ Gradient info box in summary
// ✅ Customer selector dialog with navy styling
//
// FUNCTIONALITY: fully preserved, zero changes to logic
// ✅ Save as Draft / Dispatch / Save & Send
// ✅ Customer selector with search
// ✅ Challan details (date, purpose, reference, order number)
// ✅ Transport details (mode, vehicle, driver, transporter, LR)
// ✅ Items (add/remove, qty, unit, HSN)
// ✅ Notes (customer, internal, terms)
// ✅ Edit mode via challanId
// ✅ All DeliveryChallanService calls unchanged
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/delivery_challan_service.dart' as challan_svc;
import '../../../../core/services/invoice_service.dart';
import '../widgets/document_preview_buttons.dart';

// Navy gradient colors — exact match to new_payment_made.dart
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);

// ============================================================================
// HELPER CLASS FOR FORM DATA — unchanged
// ============================================================================
class ChallanItemFormData {
  String itemDetails;
  double quantity;
  String unit;
  String? hsnCode;
  String? notes;

  ChallanItemFormData({
    this.itemDetails = '',
    this.quantity = 0,
    this.unit = 'Pcs',
    this.hsnCode,
    this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'itemDetails': itemDetails,
      'quantity': quantity,
      'unit': unit,
      if (hsnCode != null && hsnCode!.isNotEmpty) 'hsnCode': hsnCode,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }
}

// ============================================================================
// MAIN WIDGET
// ============================================================================
class NewDeliveryChallanScreen extends StatefulWidget {
  final String? challanId;

  const NewDeliveryChallanScreen({Key? key, this.challanId}) : super(key: key);

  @override
  State<NewDeliveryChallanScreen> createState() =>
      _NewDeliveryChallanScreenState();
}

class _NewDeliveryChallanScreenState
    extends State<NewDeliveryChallanScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Controllers — unchanged
  final _referenceNumberController  = TextEditingController();
  final _orderNumberController      = TextEditingController();
  final _vehicleNumberController    = TextEditingController();
  final _driverNameController       = TextEditingController();
  final _driverPhoneController      = TextEditingController();
  final _transporterNameController  = TextEditingController();
  final _lrNumberController         = TextEditingController();
  final _customerNotesController    = TextEditingController();
  final _internalNotesController    = TextEditingController();
  final _termsConditionsController  = TextEditingController();

  // Form Data — unchanged
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;
  challan_svc.Address? _deliveryAddress;

  DateTime  _challanDate          = DateTime.now();
  DateTime? _expectedDeliveryDate;

  String _selectedPurpose       = 'Sales';
  String _selectedTransportMode = 'Road';

  final List<String> _purposeOptions = [
    'Sales', 'Supply on Approval', 'Job Work', 'Stock Transfer',
    'Exhibition/Display', 'Replacement/Repair', 'Other',
  ];

  final List<String> _transportModeOptions = ['Road', 'Rail', 'Air', 'Ship'];

  // Items — unchanged
  List<ChallanItemFormData> _items = [];

  // Calculations — unchanged
  int    _totalItems    = 0;
  double _totalQuantity = 0;

  // ============================================================================
  @override
  void initState() {
    super.initState();
    _addNewItem();
    if (widget.challanId != null) _loadChallanData();
  }

  @override
  void dispose() {
    _referenceNumberController.dispose();
    _orderNumberController.dispose();
    _vehicleNumberController.dispose();
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _transporterNameController.dispose();
    _lrNumberController.dispose();
    _customerNotesController.dispose();
    _internalNotesController.dispose();
    _termsConditionsController.dispose();
    super.dispose();
  }

  // ============================================================================
  // DATA LOADING & CALCULATIONS — all unchanged
  // ============================================================================

  Future<void> _loadChallanData() async {
    setState(() => _isLoading = true);
    try {
      final challan = await challan_svc.DeliveryChallanService
          .getDeliveryChallan(widget.challanId!);
      setState(() {
        _selectedCustomerId    = challan.customerId;
        _selectedCustomerName  = challan.customerName;
        _selectedCustomerEmail = challan.customerEmail;
        _selectedCustomerPhone = challan.customerPhone;
        _deliveryAddress       = challan.deliveryAddress;

        _referenceNumberController.text = challan.referenceNumber ?? '';
        _orderNumberController.text     = challan.orderNumber ?? '';
        _challanDate          = challan.challanDate;
        _expectedDeliveryDate = challan.expectedDeliveryDate;

        _selectedPurpose       = challan.purpose;
        _selectedTransportMode = challan.transportMode;

        _vehicleNumberController.text   = challan.vehicleNumber ?? '';
        _driverNameController.text      = challan.driverName ?? '';
        _driverPhoneController.text     = challan.driverPhone ?? '';
        _transporterNameController.text = challan.transporterName ?? '';
        _lrNumberController.text        = challan.lrNumber ?? '';

        _customerNotesController.text   = challan.customerNotes ?? '';
        _internalNotesController.text   = challan.internalNotes ?? '';
        _termsConditionsController.text = challan.termsAndConditions ?? '';

        _items = challan.items.map((item) => ChallanItemFormData(
          itemDetails: item.itemDetails,
          quantity:    item.quantity,
          unit:        item.unit,
          hsnCode:     item.hsnCode,
          notes:       item.notes,
        )).toList();

        _calculateTotals();
      });
    } catch (e) {
      _showErrorSnackbar('Failed to load challan: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _calculateTotals() {
    setState(() {
      _totalItems    = _items.where((i) => i.itemDetails.trim().isNotEmpty).length;
      _totalQuantity = _items.fold(0.0, (s, i) => s + i.quantity);
    });
  }

  void _addNewItem() => setState(() => _items.add(ChallanItemFormData()));

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateTotals();
    });
  }

  // ============================================================================
  // VALIDATION & SAVE — all unchanged
  // ============================================================================

  bool _validateItems() {
    final nonEmpty = _items.where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      _showErrorSnackbar('Please add at least one item with details');
      return false;
    }
    for (var item in nonEmpty) {
      if (item.quantity <= 0) {
        _showErrorSnackbar('All items must have quantity greater than 0');
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _buildChallanData(String status) {
    final validItems = _items
        .where((i) => i.itemDetails.trim().isNotEmpty)
        .toList();
    return {
      'customerId':    _selectedCustomerId,
      'customerName':  _selectedCustomerName,
      'customerEmail': _selectedCustomerEmail,
      'customerPhone': _selectedCustomerPhone,
      if (_deliveryAddress != null) 'deliveryAddress': _deliveryAddress!.toJson(),
      'challanDate': _challanDate.toIso8601String(),
      if (_expectedDeliveryDate != null)
        'expectedDeliveryDate': _expectedDeliveryDate!.toIso8601String(),
      'referenceNumber': _referenceNumberController.text.trim(),
      'orderNumber':     _orderNumberController.text.trim(),
      'purpose':         _selectedPurpose,
      'transportMode':   _selectedTransportMode,
      'vehicleNumber':   _vehicleNumberController.text.trim(),
      'driverName':      _driverNameController.text.trim(),
      'driverPhone':     _driverPhoneController.text.trim(),
      'transporterName': _transporterNameController.text.trim(),
      'lrNumber':        _lrNumberController.text.trim(),
      'items': validItems.map((i) => i.toJson()).toList(),
      'customerNotes':     _customerNotesController.text.trim(),
      'internalNotes':     _internalNotesController.text.trim(),
      'termsAndConditions': _termsConditionsController.text.trim(),
      'status': status,
    };
  }

  Future<void> _saveAsDraft() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showErrorSnackbar('Please select a customer'); return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final data = _buildChallanData('DRAFT');
      if (widget.challanId != null) {
        await challan_svc.DeliveryChallanService
            .updateDeliveryChallan(widget.challanId!, data);
      } else {
        await challan_svc.DeliveryChallanService.createDeliveryChallan(data);
      }
      _showSuccessSnackbar('Delivery challan saved as draft');
      Navigator.pop(context, true);
    } catch (e) {
      String msg = 'Failed to save challan';
      if (e.toString().contains('validation failed')) {
        final match = RegExp(r'Path `(\w+)` is required').firstMatch(e.toString());
        msg = match != null
            ? 'Please fill in required field: ${match.group(1)}'
            : 'Please check all required fields';
      } else { msg = e.toString(); }
      _showErrorSnackbar(msg);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showErrorSnackbar('Please select a customer'); return;
    }
    if (_selectedCustomerEmail == null || _selectedCustomerEmail!.isEmpty) {
      _showErrorSnackbar('Customer email is required to send challan'); return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final data = _buildChallanData('OPEN');
      challan_svc.DeliveryChallan challan;
      if (widget.challanId != null) {
        challan = await challan_svc.DeliveryChallanService
            .updateDeliveryChallan(widget.challanId!, data);
      } else {
        challan = await challan_svc.DeliveryChallanService
            .createDeliveryChallan(data);
      }
      await challan_svc.DeliveryChallanService.sendChallan(challan.id);
      _showSuccessSnackbar('Challan sent to $_selectedCustomerEmail');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar(e.toString().contains('validation failed')
          ? 'Please check all required fields' : e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndDispatch() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showErrorSnackbar('Please select a customer'); return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final data = _buildChallanData('OPEN');
      if (widget.challanId != null) {
        await challan_svc.DeliveryChallanService
            .updateDeliveryChallan(widget.challanId!, data);
      } else {
        await challan_svc.DeliveryChallanService.createDeliveryChallan(data);
      }
      _showSuccessSnackbar('Challan marked as dispatched');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar(e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ============================================================================
  // CUSTOMER SELECTION — functionality unchanged, styling updated
  // ============================================================================

  Future<void> _showCustomerSelector() async {
    final searchCtrl = TextEditingController();
    List<BillingCustomer> customers         = [];
    List<BillingCustomer> filteredCustomers = [];
    bool   isLoading    = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (isLoading && customers.isEmpty) {
            InvoiceService.getBillingCustomers().then((response) {
              setS(() {
                customers         = response.customers;
                filteredCustomers = customers;
                isLoading         = false;
              });
            }).catchError((error) {
              setS(() { errorMessage = error.toString(); isLoading = false; });
            });
          }

          return AlertDialog(
            title: const Text('Select Customer'),
            content: SizedBox(width: 500, height: 420, child: Column(children: [
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setS(() {
                  filteredCustomers = v.isEmpty
                      ? customers
                      : customers.where((c) =>
                          c.customerName.toLowerCase().contains(v.toLowerCase()) ||
                          c.customerEmail.toLowerCase().contains(v.toLowerCase()))
                          .toList();
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
                    : errorMessage != null
                        ? Center(child: Text(errorMessage!))
                        : filteredCustomers.isEmpty
                            ? const Center(child: Text('No customers found'))
                            : ListView.builder(
                                itemCount: filteredCustomers.length,
                                itemBuilder: (_, i) {
                                  final c = filteredCustomers[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _navyAccent,
                                      child: Text(
                                        c.customerName[0].toUpperCase(),
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                    title: Text(c.customerName),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(c.customerEmail),
                                        Text(c.customerPhone,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600])),
                                      ],
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedCustomerId    = c.id;
                                        _selectedCustomerName  = c.customerName;
                                        _selectedCustomerEmail = c.customerEmail;
                                        _selectedCustomerPhone = c.customerPhone;
                                        _deliveryAddress = challan_svc.Address(
                                          street:  c.addressLine1,
                                          city:    c.city,
                                          state:   c.state,
                                          pincode: c.postalCode,
                                          country: c.country ?? 'India',
                                        );
                                      });
                                      Navigator.pop(ctx);
                                    },
                                  );
                                },
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
  // SNACKBAR HELPERS — unchanged
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
                          child: _buildSummarySection(),
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
                        child: _buildSummarySection(),
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
          widget.challanId != null
              ? 'Edit Delivery Challan' : 'New Delivery Challan',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          // View PDF
          IconButton(
            tooltip: 'View PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
            onPressed: () {
              if (widget.challanId == null || widget.challanId!.isEmpty) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                  content: Text('Save the challan first to preview PDF'),
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              openDocumentPdf(
                context: context,
                docId: widget.challanId,
                pdfEndpoint: '/api/finance/delivery-challans',
                docNumber: 'Delivery Challan',
              );
            },
          ),
          // Preview Email
          IconButton(
            tooltip: 'Preview Email',
            icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
            onPressed: () {
              if (widget.challanId == null || widget.challanId!.isEmpty) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                  content: Text('Save the challan first to preview email'),
                  behavior: SnackBarBehavior.floating,
                ));
                return;
              }
              openEmailPreview(
                context: context,
                docId: widget.challanId,
                emailEndpoint: '/api/finance/delivery-challans',
              );
            },
          ),
          // Save as Draft
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAsDraft,
            icon: const Icon(Icons.save_outlined,
                color: Colors.white70, size: 18),
            label: const Text('Save as Draft',
                style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 4),

          // Dispatch
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAndDispatch,
            icon: const Icon(Icons.local_shipping,
                color: Colors.white70, size: 18),
            label: const Text('Dispatch',
                style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),

          // Save & Send
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndSend,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send, size: 18),
            label: Text(_isSaving ? 'Sending...' : 'Save & Send'),
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
      _buildCustomerSection(),
      const SizedBox(height: 20),
      _buildChallanDetailsSection(),
      const SizedBox(height: 20),
      _buildTransportSection(),
      const SizedBox(height: 20),
      _buildItemsSection(),
      const SizedBox(height: 20),
      _buildNotesSection(),
      const SizedBox(height: 20),
    ]),
  );

  // ============================================================================
  // CUSTOMER SECTION
  // ============================================================================

  Widget _buildCustomerSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Customer Information', Icons.business),
      const SizedBox(height: 16),

      InkWell(
        onTap: _showCustomerSelector,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: _selectedCustomerId == null
                ? Colors.red.shade300 : Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.business_outlined, color: _navyAccent),
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

      if (_selectedCustomerEmail != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(_selectedCustomerEmail!,
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ]),
      ],

      if (_selectedCustomerPhone != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.phone_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(_selectedCustomerPhone!,
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ]),
      ],
    ],
  ));

  // ============================================================================
  // CHALLAN DETAILS SECTION
  // ============================================================================

  Widget _buildChallanDetailsSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Challan Details', Icons.description_outlined),
      const SizedBox(height: 16),

      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final refField = TextFormField(
          controller: _referenceNumberController,
          decoration: InputDecoration(
            labelText: 'Reference Number',
            hintText: 'Optional',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.tag),
          ),
        );
        final orderField = TextFormField(
          controller: _orderNumberController,
          decoration: InputDecoration(
            labelText: 'Order Number',
            hintText: 'Optional',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.numbers),
          ),
        );
        return isWide
            ? Row(children: [
                Expanded(child: refField),
                const SizedBox(width: 16),
                Expanded(child: orderField),
              ])
            : Column(children: [
                refField,
                const SizedBox(height: 16),
                orderField,
              ]);
      }),

      const SizedBox(height: 16),

      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final challanDateField = InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _challanDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (date != null) setState(() => _challanDate = date);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Challan Date *',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.calendar_today),
            ),
            child: Text(DateFormat('dd MMM yyyy').format(_challanDate)),
          ),
        );
        final deliveryDateField = InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _expectedDeliveryDate ??
                  DateTime.now().add(const Duration(days: 1)),
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
              prefixIcon: const Icon(Icons.event),
            ),
            child: Text(_expectedDeliveryDate != null
                ? DateFormat('dd MMM yyyy').format(_expectedDeliveryDate!)
                : 'Select Date'),
          ),
        );
        return isWide
            ? Row(children: [
                Expanded(child: challanDateField),
                const SizedBox(width: 16),
                Expanded(child: deliveryDateField),
              ])
            : Column(children: [
                challanDateField,
                const SizedBox(height: 16),
                deliveryDateField,
              ]);
      }),

      const SizedBox(height: 16),

      DropdownButtonFormField<String>(
        value: _selectedPurpose,
        decoration: InputDecoration(
          labelText: 'Purpose *',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.info_outline),
        ),
        items: _purposeOptions.map((p) =>
            DropdownMenuItem(value: p, child: Text(p))).toList(),
        onChanged: (v) => setState(() => _selectedPurpose = v!),
      ),
    ],
  ));

  // ============================================================================
  // TRANSPORT SECTION
  // ============================================================================

  Widget _buildTransportSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Transport Details', Icons.local_shipping_outlined),
      const SizedBox(height: 16),

      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final modeField = DropdownButtonFormField<String>(
          value: _selectedTransportMode,
          decoration: InputDecoration(
            labelText: 'Transport Mode *',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.directions_bus),
          ),
          items: _transportModeOptions.map((m) =>
              DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (v) => setState(() => _selectedTransportMode = v!),
        );
        final vehicleField = TextFormField(
          controller: _vehicleNumberController,
          decoration: InputDecoration(
            labelText: 'Vehicle Number',
            hintText: 'e.g., KA-01-AB-1234',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.local_shipping),
          ),
        );
        return isWide
            ? Row(children: [
                Expanded(child: modeField),
                const SizedBox(width: 16),
                Expanded(child: vehicleField),
              ])
            : Column(children: [
                modeField,
                const SizedBox(height: 16),
                vehicleField,
              ]);
      }),

      const SizedBox(height: 16),

      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final driverNameField = TextFormField(
          controller: _driverNameController,
          decoration: InputDecoration(
            labelText: 'Driver Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.person),
          ),
        );
        final driverPhoneField = TextFormField(
          controller: _driverPhoneController,
          decoration: InputDecoration(
            labelText: 'Driver Phone',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.phone),
          ),
          keyboardType: TextInputType.phone,
        );
        return isWide
            ? Row(children: [
                Expanded(child: driverNameField),
                const SizedBox(width: 16),
                Expanded(child: driverPhoneField),
              ])
            : Column(children: [
                driverNameField,
                const SizedBox(height: 16),
                driverPhoneField,
              ]);
      }),

      const SizedBox(height: 16),

      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 600;
        final transporterField = TextFormField(
          controller: _transporterNameController,
          decoration: InputDecoration(
            labelText: 'Transporter Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.business),
          ),
        );
        final lrField = TextFormField(
          controller: _lrNumberController,
          decoration: InputDecoration(
            labelText: 'LR Number',
            hintText: 'Lorry Receipt Number',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.receipt_long),
          ),
        );
        return isWide
            ? Row(children: [
                Expanded(child: transporterField),
                const SizedBox(width: 16),
                Expanded(child: lrField),
              ])
            : Column(children: [
                transporterField,
                const SizedBox(height: 16),
                lrField,
              ]);
      }),
    ],
  ));

  // ============================================================================
  // ITEMS SECTION
  // ============================================================================

  Widget _buildItemsSection() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
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
      ]),
      const SizedBox(height: 16),

      // Gradient table header — matches new_payment_made.dart
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
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold));
          }
          return const Row(children: [
            Expanded(flex: 3, child: Text('ITEM DETAILS',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 12))),
            SizedBox(width: 8),
            SizedBox(width: 80, child: Text('QTY',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center)),
            SizedBox(width: 8),
            SizedBox(width: 100, child: Text('UNIT',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center)),
            SizedBox(width: 8),
            SizedBox(width: 100, child: Text('HSN CODE',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center)),
            SizedBox(width: 50),
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
            Text('No items added yet',
                style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 6),
            Text('Use Add Item button above',
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ]),
        ))
      else
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 16),
          itemBuilder: (_, i) => _buildItemRow(i),
        ),
    ],
  ));

  Widget _buildItemRow(int index) {
    final item = _items[index];

    return LayoutBuilder(builder: (_, cs) {
      // Mobile layout
      if (cs.maxWidth < 600) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              Text('Item ${index + 1}',
                  style: TextStyle(fontWeight: FontWeight.w600,
                      fontSize: 12, color: _navyMid)),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 18),
                onPressed: () => _removeItem(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: item.itemDetails,
              decoration: InputDecoration(
                labelText: 'Item Description',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6)),
                isDense: true,
              ),
              maxLines: 2,
              onChanged: (v) { item.itemDetails = v; _calculateTotals(); },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: item.quantity > 0
                    ? item.quantity.toString() : '',
                decoration: InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9.]'))],
                onChanged: (v) {
                  item.quantity = double.tryParse(v) ?? 0;
                  _calculateTotals();
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(
                initialValue: item.unit,
                decoration: InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                textAlign: TextAlign.center,
                onChanged: (v) => item.unit = v,
              )),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(
                initialValue: item.hsnCode,
                decoration: InputDecoration(
                  labelText: 'HSN',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                  isDense: true,
                ),
                textAlign: TextAlign.center,
                onChanged: (v) => item.hsnCode = v,
              )),
            ]),
          ]),
        );
      }

      // Desktop layout — same column widths as header
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: TextFormField(
          initialValue: item.itemDetails,
          decoration: InputDecoration(
            hintText: 'Enter item description',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          maxLines: 2,
          onChanged: (v) { item.itemDetails = v; _calculateTotals(); },
        )),
        const SizedBox(width: 8),
        SizedBox(width: 80, child: TextFormField(
          initialValue: item.quantity > 0 ? item.quantity.toString() : '',
          decoration: InputDecoration(
            hintText: '0',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 12),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.allow(
              RegExp(r'[0-9.]'))],
          onChanged: (v) {
            item.quantity = double.tryParse(v) ?? 0;
            _calculateTotals();
          },
        )),
        const SizedBox(width: 8),
        SizedBox(width: 100, child: TextFormField(
          initialValue: item.unit,
          decoration: InputDecoration(
            hintText: 'Pcs',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 12),
          ),
          textAlign: TextAlign.center,
          onChanged: (v) => item.unit = v,
        )),
        const SizedBox(width: 8),
        SizedBox(width: 100, child: TextFormField(
          initialValue: item.hsnCode,
          decoration: InputDecoration(
            hintText: 'HSN',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 12),
          ),
          textAlign: TextAlign.center,
          onChanged: (v) => item.hsnCode = v,
        )),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _removeItem(index),
          tooltip: 'Remove item',
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
      _sectionTitle('Additional Information', Icons.note_alt),
      const SizedBox(height: 16),

      TextFormField(
        controller: _customerNotesController,
        decoration: InputDecoration(
          labelText: 'Customer Notes',
          hintText: 'Notes visible on challan',
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
          hintText: 'For internal use only',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          alignLabelWithHint: true,
        ),
        maxLines: 3,
      ),

      const SizedBox(height: 16),

      TextFormField(
        controller: _termsConditionsController,
        decoration: InputDecoration(
          labelText: 'Terms & Conditions',
          hintText: 'Delivery terms, conditions, etc.',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          alignLabelWithHint: true,
        ),
        maxLines: 3,
      ),
    ],
  ));

  // ============================================================================
  // SUMMARY SECTION (sidebar) — exact match to new_payment_made.dart
  // ============================================================================

  Widget _buildSummarySection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionTitle('Challan Summary', Icons.summarize),
      const SizedBox(height: 16),

      // Summary rows
      _summaryRow('Total Items', _totalItems.toDouble(), isCount: true),
      const SizedBox(height: 6),
      _summaryRow('Total Quantity', _totalQuantity, isCount: true),

      const Divider(thickness: 2, height: 28),

      // Gradient info box — exact match to new_payment_made.dart
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
          _infoRow('Purpose:', _selectedPurpose),
          const SizedBox(height: 4),
          _infoRow('Transport:', _selectedTransportMode),
          const SizedBox(height: 4),
          _infoRow('Customer:',
              _selectedCustomerName ?? '—'),
          if (_selectedCustomerEmail != null) ...[
            const SizedBox(height: 4),
            _infoRow('Email:', _selectedCustomerEmail!),
          ],
        ]),
      ),

      const SizedBox(height: 20),

      // Save & Send
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveAndSend,
          icon: _isSaving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(_isSaving ? 'Sending...' : 'Save & Send Challan'),
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

      // Dispatch
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveAndDispatch,
          icon: const Icon(Icons.local_shipping),
          label: const Text('Save & Dispatch'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navyAccent,
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
  // HELPERS — exact match to new_payment_made.dart
  // ============================================================================

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

  /// Summary row — for count values (items, qty) shown without currency
  Widget _summaryRow(String label, double value, {bool isCount = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
        Text(
          isCount ? value.toStringAsFixed(0) : value.toStringAsFixed(2),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: _navyDark),
        ),
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