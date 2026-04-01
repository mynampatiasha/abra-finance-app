// ============================================================================
// NEW CREDIT NOTE SCREEN - Complete Flutter UI
// ============================================================================
// File: lib/screens/billing/new_credit_note.dart
// Features:
// ✅ Same UI as new_invoice.dart
// ✅ Fetch items from existing items OR manual entry
// ✅ Create from invoice OR create manually
// ✅ All validations
// ✅ PDF generation
// ✅ Email sending
// ✅ Refund tracking
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/credit_note_service.dart';
import '../widgets/document_preview_buttons.dart';

import '../../../../core/services/invoice_service.dart' as invoice_svc;
import '../../../../core/services/invoice_service.dart' show Address, BillingCustomer;

import '../../../../core/services/item_billing_service.dart';

// Navy blue gradient colors
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewCreditNoteScreen extends StatefulWidget {
  final String? creditNoteId; // For edit mode
  final String? invoiceId; // To create from invoice

  const NewCreditNoteScreen({
    Key? key,
    this.creditNoteId,
    this.invoiceId,
  }) : super(key: key);

  @override
  State<NewCreditNoteScreen> createState() => _NewCreditNoteScreenState();
}

class _NewCreditNoteScreenState extends State<NewCreditNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Controllers
  final _referenceNumberController = TextEditingController();
  final _reasonDescriptionController = TextEditingController();
  final _customerNotesController = TextEditingController();
  final _internalNotesController = TextEditingController();

  // Form Data
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;
  Address? _billingAddress;
  
  String? _selectedInvoiceId;
  String? _selectedInvoiceNumber;
  
  DateTime _creditNoteDate = DateTime.now();
  String _selectedReason = 'Product Returned';
  
  // Reason options
  final List<String> _reasonOptions = [
    'Product Returned',
    'Order Cancelled',
    'Pricing Error',
    'Damaged Goods',
    'Quality Issue',
    'Other',
  ];

  // Tax Settings
  double _tdsRate = 0;
  double _tcsRate = 0;
  double _gstRate = 18;
  bool _enableTDS = false;
  bool _enableTCS = false;
  bool _enableGST = true;

  // Items List
  List<CreditNoteItemRow> _items = [];

  // Calculations
  double _subTotal = 0;
  double _tdsAmount = 0;
  double _tcsAmount = 0;
  double _gstAmount = 0;
  double _totalAmount = 0;
  int _totalQuantity = 0;

  // Available items from backend
  List<Map<String, dynamic>> _availableItems = [];
  bool _isLoadingItems = false;

  @override
  void initState() {
    super.initState();
    _addNewItem(); // Add first empty item
    _loadAvailableItems(); // Load items from backend

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
    super.dispose();
  }

  Future<void> _showInvoiceSelector() async {
  try {
    // Fetch unpaid invoices for this customer
    final response = await invoice_svc.InvoiceService.getInvoices(
      customerId: _selectedCustomerId,
    );

    final unpaidInvoices = response.invoices.where((inv) =>
      inv.status == 'SENT' ||
      inv.status == 'UNPAID' ||
      inv.status == 'OVERDUE' ||
      inv.status == 'PARTIALLY_PAID'
    ).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Invoice'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: unpaidInvoices.isEmpty
              ? const Center(child: Text('No unpaid invoices found'))
              : ListView.builder(
                  itemCount: unpaidInvoices.length,
                  itemBuilder: (context, index) {
                    final invoice = unpaidInvoices[index];
                    return ListTile(
                      leading: const Icon(
                        Icons.receipt,
                        color: Color(0xFFE74C3C),
                      ),
                      title: Text(
                        invoice.invoiceNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Amount Due: ₹${invoice.amountDue.toStringAsFixed(2)} • ${invoice.status}',
                      ),
                      onTap: () {
                        setState(() {
                          _selectedInvoiceId   = invoice.id;
                          _selectedInvoiceNumber = invoice.invoiceNumber;

                          // Auto-fill items from invoice
                          _items = invoice.items.map((item) =>
                            CreditNoteItemRow(
                              itemDetails:  item.itemDetails,
                              quantity:     item.quantity,
                              rate:         item.rate,
                              discount:     item.discount,
                              discountType: item.discountType,
                              amount:       item.amount,
                            )
                          ).toList();

                          // Auto-fill tax settings
                          _gstRate   = invoice.gstRate;
                          _tdsRate   = invoice.tdsRate;
                          _tcsRate   = invoice.tcsRate;
                          _enableGST = invoice.gstRate > 0;
                          _enableTDS = invoice.tdsRate > 0;
                          _enableTCS = invoice.tcsRate > 0;

                          _calculateAmounts();
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  } catch (e) {
    _showErrorSnackbar('Failed to load invoices: $e');
  }
}

  // Load available items from backend
  Future<void> _loadAvailableItems() async {
    setState(() => _isLoadingItems = true);

    try {
      final items = await ItemBillingService().fetchAllItems(
        isSellable: true,
      );

      setState(() {
        _availableItems = items;
        _isLoadingItems = false;
      });
    } catch (e) {
      print('Error loading items: $e');
      setState(() => _isLoadingItems = false);
    }
  }

  // Calculate all amounts
  void _calculateAmounts() {
    setState(() {
      // Calculate subtotal and quantity
      _subTotal = 0;
      _totalQuantity = 0;

      for (var item in _items) {
        if (item.quantity > 0 && item.rate > 0) {
          double itemAmount = item.quantity * item.rate;

          // Apply discount
          if (item.discount > 0) {
            if (item.discountType == 'percentage') {
              itemAmount = itemAmount - (itemAmount * item.discount / 100);
            } else {
              itemAmount = itemAmount - item.discount;
            }
          }

          item.amount = itemAmount;
          _subTotal += itemAmount;
          _totalQuantity += item.quantity.toInt();
        }
      }

      // Calculate TDS (reduces total)
      _tdsAmount = _enableTDS ? (_subTotal * _tdsRate / 100) : 0;

      // Calculate TCS (increases total)
      _tcsAmount = _enableTCS ? (_subTotal * _tcsRate / 100) : 0;

      // Calculate GST on adjusted base
      double gstBase = _subTotal - _tdsAmount + _tcsAmount;
      _gstAmount = _enableGST ? (gstBase * _gstRate / 100) : 0;

      // Calculate total
      _totalAmount = _subTotal - _tdsAmount + _tcsAmount + _gstAmount;
    });
  }

  // Add new item row
  void _addNewItem() {
    setState(() {
      _items.add(CreditNoteItemRow());
    });
  }

  // Remove item
  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateAmounts();
    });
  }

  // Load credit note data for editing
  Future<void> _loadCreditNoteData() async {
    setState(() => _isLoading = true);

    try {
      final creditNote = await CreditNoteService.getCreditNote(widget.creditNoteId!);

      setState(() {
        _selectedCustomerId = creditNote.customerId;
        _selectedCustomerName = creditNote.customerName;
        _selectedCustomerEmail = creditNote.customerEmail;
        _selectedCustomerPhone = creditNote.customerPhone;
        _billingAddress = creditNote.billingAddress;
        
        _selectedInvoiceId = creditNote.invoiceId;
        _selectedInvoiceNumber = creditNote.invoiceNumber;
        
        _referenceNumberController.text = creditNote.referenceNumber ?? '';
        _creditNoteDate = creditNote.creditNoteDate;
        _selectedReason = creditNote.reason;
        _reasonDescriptionController.text = creditNote.reasonDescription ?? '';
        _customerNotesController.text = creditNote.customerNotes ?? '';
        _internalNotesController.text = creditNote.internalNotes ?? '';

        // Load tax settings
        _tdsRate = creditNote.tdsRate;
        _tcsRate = creditNote.tcsRate;
        _gstRate = creditNote.gstRate;
        _enableTDS = creditNote.tdsRate > 0;
        _enableTCS = creditNote.tcsRate > 0;
        _enableGST = creditNote.gstRate > 0;

        // Load items
        _items = creditNote.items
            .map((item) => CreditNoteItemRow(
                  itemDetails: item.itemDetails,
                  quantity: item.quantity,
                  rate: item.rate,
                  discount: item.discount,
                  discountType: item.discountType,
                  amount: item.amount,
                ))
            .toList();

        _calculateAmounts();
      });
    } catch (e) {
      _showErrorSnackbar('Failed to load credit note: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Load invoice data (create from invoice)
  Future<void> _loadInvoiceData() async {
    setState(() => _isLoading = true);

    try {
      final invoice = await invoice_svc.InvoiceService.getInvoice(widget.invoiceId!);

      setState(() {
        _selectedCustomerId = invoice.customerId;
        _selectedCustomerName = invoice.customerName;
        _selectedCustomerEmail = invoice.customerEmail;
        _selectedCustomerPhone = invoice.customerPhone;
        _billingAddress = invoice.billingAddress;
        
        _selectedInvoiceId = invoice.id;
        _selectedInvoiceNumber = invoice.invoiceNumber;

        // Load tax settings from invoice
        _tdsRate = invoice.tdsRate;
        _tcsRate = invoice.tcsRate;
        _gstRate = invoice.gstRate;
        _enableTDS = invoice.tdsRate > 0;
        _enableTCS = invoice.tcsRate > 0;
        _enableGST = invoice.gstRate > 0;

        // Load items from invoice
        _items = invoice.items
            .map((item) => CreditNoteItemRow(
                  itemDetails: item.itemDetails,
                  quantity: item.quantity,
                  rate: item.rate,
                  discount: item.discount,
                  discountType: item.discountType,
                  amount: item.amount,
                ))
            .toList();

        _calculateAmounts();
      });
    } catch (e) {
      _showErrorSnackbar('Failed to load invoice: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Save as draft
  Future<void> _saveAsDraft() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomerId == null) {
      _showErrorSnackbar('Please select a customer');
      return;
    }

    if (!_validateItems()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final creditNoteData = _buildCreditNoteData('DRAFT');

      CreditNote creditNote;
      if (widget.creditNoteId != null) {
        creditNote = await CreditNoteService.updateCreditNote(
            widget.creditNoteId!, creditNoteData);
      } else {
        creditNote = await CreditNoteService.createCreditNote(creditNoteData);
      }

      _showSuccessSnackbar('Credit note saved as draft');
      Navigator.pop(context, true);
    } catch (e) {
      String errorMessage = 'Failed to save credit note';

      if (e.toString().contains('validation failed')) {
        final match = RegExp(r'Path `(\w+)` is required').firstMatch(e.toString());
        if (match != null) {
          errorMessage = 'Please fill in required field: ${match.group(1)}';
        } else {
          errorMessage = 'Please check all required fields';
        }
      } else {
        errorMessage = e.toString();
      }

      _showErrorSnackbar(errorMessage);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // Save and send
  Future<void> _saveAndSend() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomerId == null) {
      _showErrorSnackbar('Please select a customer');
      return;
    }

    if (_selectedCustomerEmail == null || _selectedCustomerEmail!.isEmpty) {
      _showErrorSnackbar('Customer email is required to send credit note');
      return;
    }

    if (!_validateItems()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final creditNoteData = _buildCreditNoteData('OPEN');

      CreditNote creditNote;
      if (widget.creditNoteId != null) {
        creditNote = await CreditNoteService.updateCreditNote(
            widget.creditNoteId!, creditNoteData);
      } else {
        creditNote = await CreditNoteService.createCreditNote(creditNoteData);
      }

      // Send the credit note
      await CreditNoteService.sendCreditNote(creditNote.id);

      _showSuccessSnackbar('Credit note sent to $_selectedCustomerEmail');
      Navigator.pop(context, true);
    } catch (e) {
      String errorMessage = 'Failed to send credit note';

      if (e.toString().contains('validation failed')) {
        final match = RegExp(r'Path `(\w+)` is required').firstMatch(e.toString());
        if (match != null) {
          errorMessage = 'Please fill in required field: ${match.group(1)}';
        } else {
          errorMessage = 'Please check all required fields';
        }
      } else {
        errorMessage = e.toString();
      }

      _showErrorSnackbar(errorMessage);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // Validate items
  bool _validateItems() {
    final nonEmptyItems =
        _items.where((item) => item.itemDetails.trim().isNotEmpty).toList();

    if (nonEmptyItems.isEmpty) {
      _showErrorSnackbar('Please add at least one item with details');
      return false;
    }

    for (var item in nonEmptyItems) {
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

  // Build credit note data object
  Map<String, dynamic> _buildCreditNoteData(String status) {
    // Filter out empty items
    final validItems =
        _items.where((item) => item.itemDetails.trim().isNotEmpty).toList();

    if (validItems.isEmpty) {
      throw Exception('Please add at least one item with details');
    }

    // Validate items have quantity and rate
    for (var item in validItems) {
      if (item.quantity <= 0) {
        throw Exception('All items must have quantity greater than 0');
      }
      if (item.rate <= 0) {
        throw Exception('All items must have rate greater than 0');
      }
    }

    return {
      'customerId': _selectedCustomerId,
      'customerName': _selectedCustomerName,
      'customerEmail': _selectedCustomerEmail,
      'customerPhone': _selectedCustomerPhone,
      if (_billingAddress != null) 'billingAddress': _billingAddress!.toJson(),
      if (_selectedInvoiceId != null) 'invoiceId': _selectedInvoiceId,
      if (_selectedInvoiceNumber != null) 'invoiceNumber': _selectedInvoiceNumber,
      'referenceNumber': _referenceNumberController.text.trim(),
      'creditNoteDate': _creditNoteDate.toIso8601String(),
      'reason': _selectedReason,
      'reasonDescription': _reasonDescriptionController.text.trim(),
      'items': validItems.map((item) => item.toJson()).toList(),
      'customerNotes': _customerNotesController.text.trim(),
      'internalNotes': _internalNotesController.text.trim(),
      'tdsRate': _enableTDS ? _tdsRate : 0,
      'tcsRate': _enableTCS ? _tcsRate : 0,
      'gstRate': _enableGST ? _gstRate : 0,
      'status': status,
    };
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          widget.creditNoteId != null ? 'Edit Credit Note' : 'New Credit Note',
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF1e3a8a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'View PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
            onPressed: () => openDocumentPdf(context: context, docId: widget.creditNoteId, pdfEndpoint: '/api/finance/credit-notes', docNumber: 'CN'),
          ),
          IconButton(
            tooltip: 'Preview Email',
            icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
            onPressed: () => openEmailPreview(context: context, docId: widget.creditNoteId, emailEndpoint: '/api/finance/credit-notes'),
          ),
          TextButton.icon(
            onPressed: _isSaving ? null : _saveAsDraft,
            icon: const Icon(Icons.save_outlined, color: Colors.white70, size: 18),
            label: const Text('Save as Draft', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAndSend,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Save & Send', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return Form(
                  key: _formKey,
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildCustomerSection(),
                                    const SizedBox(height: 20),
                                    _buildCreditNoteDetailsSection(),
                                    const SizedBox(height: 20),
                                    _buildItemsSection(),
                                    const SizedBox(height: 20),
                                    _buildNotesSection(),
                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: 320,
                              color: Colors.white,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTaxSettingsSection(),
                                    const Divider(height: 32),
                                    _buildSummarySection(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCustomerSection(),
                              const SizedBox(height: 16),
                              _buildCreditNoteDetailsSection(),
                              const SizedBox(height: 16),
                              _buildItemsSection(),
                              const SizedBox(height: 16),
                              _buildNotesSection(),
                              const SizedBox(height: 16),
                              Container(
                                color: Colors.white,
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildTaxSettingsSection(),
                                    const Divider(height: 32),
                                    _buildSummarySection(),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                );
              },
            ),
    );
  }

  // Customer Section
  Widget _buildCustomerSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customer Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 16),

          // Customer Selector
          InkWell(
            onTap: () => _showCustomerSelector(),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: Color(0xFFE74C3C)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCustomerName ?? 'Select Customer *',
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedCustomerName != null
                            ? const Color(0xFF2C3E50)
                            : Colors.grey[600],
                        fontWeight: _selectedCustomerName != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),

          if (_selectedCustomerEmail != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.email_outlined, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  _selectedCustomerEmail!,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ],

// Invoice Selector
if (_selectedCustomerId != null) ...[
  const SizedBox(height: 12),
  InkWell(
    onTap: () => _showInvoiceSelector(),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: Color(0xFFE74C3C)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _selectedInvoiceNumber ?? 'Select Invoice (Optional)',
              style: TextStyle(
                fontSize: 16,
                color: _selectedInvoiceNumber != null
                    ? const Color(0xFF2C3E50)
                    : Colors.grey[600],
              ),
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: Colors.grey),
        ],
      ),
    ),
  ),
],
        ],
      ),
    );
  }

  // Credit Note Details Section
  Widget _buildCreditNoteDetailsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Credit Note Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              // Reference Number
              Expanded(
                child: TextFormField(
                  controller: _referenceNumberController,
                  decoration: InputDecoration(
                    labelText: 'Reference Number',
                    hintText: 'Optional',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.numbers),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Credit Note Date
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _creditNoteDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null) {
                      setState(() {
                        _creditNoteDate = date;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Credit Note Date *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      DateFormat('dd MMM yyyy').format(_creditNoteDate),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Reason
          DropdownButtonFormField<String>(
            value: _selectedReason,
            decoration: InputDecoration(
              labelText: 'Reason *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.report_problem_outlined),
            ),
            items: _reasonOptions.map((reason) {
              return DropdownMenuItem(value: reason, child: Text(reason));
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedReason = value!;
              });
            },
          ),

          const SizedBox(height: 16),

          // Reason Description
          TextFormField(
            controller: _reasonDescriptionController,
            decoration: InputDecoration(
              labelText: 'Reason Description',
              hintText: 'Explain the reason for this credit note',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.description),
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // Items Section
  Widget _buildItemsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addNewItem,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Item'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1e3a8a),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Scrollable table header + rows
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e3a8a),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      SizedBox(
                        width: 220,
                        child: Text(
                          'ITEM DETAILS',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: Text(
                          'QTY',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: Text(
                          'RATE (₹)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: Text(
                          'DISCOUNT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        child: Text(
                          'AMOUNT (₹)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      SizedBox(width: 48),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.inbox,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No items added yet',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Column(
                    children: List.generate(_items.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildItemRow(index),
                      );
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Single Item Row
  Widget _buildItemRow(int index) {
    final item = _items[index];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Item Details - with autocomplete
        SizedBox(
          width: 220,
          child: _isLoadingItems
              ? const SizedBox(
                  height: 48,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : Autocomplete<Map<String, dynamic>>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    return _availableItems.where((availItem) {
                      return availItem['name']
                          .toString()
                          .toLowerCase()
                          .contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  displayStringForOption: (Map<String, dynamic> option) =>
                      option['name'].toString(),
                  onSelected: (Map<String, dynamic> selection) {
                    setState(() {
                      item.itemDetails = selection['name'].toString();
                      item.rate =
                          (selection['sellingPrice'] ?? 0).toDouble();
                      _calculateAmounts();
                    });
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmit) {
                    if (item.itemDetails.isNotEmpty &&
                        controller.text.isEmpty) {
                      controller.text = item.itemDetails;
                    }
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: 'Search or enter item',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        suffixIcon:
                            const Icon(Icons.search, size: 18),
                      ),
                      maxLines: 2,
                      onChanged: (value) {
                        item.itemDetails = value;
                      },
                    );
                  },
                ),
        ),

        const SizedBox(width: 8),

        // Quantity
        SizedBox(
          width: 80,
          child: TextFormField(
            initialValue:
                item.quantity > 0 ? item.quantity.toString() : '',
            decoration: InputDecoration(
              hintText: '0',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) {
              item.quantity = double.tryParse(value) ?? 0;
              _calculateAmounts();
            },
          ),
        ),

        const SizedBox(width: 8),

        // Rate
        SizedBox(
          width: 100,
          child: TextFormField(
            initialValue:
                item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
            decoration: InputDecoration(
              hintText: '0.00',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onChanged: (value) {
              item.rate = double.tryParse(value) ?? 0;
              _calculateAmounts();
            },
          ),
        ),

        const SizedBox(width: 8),

        // Discount
        SizedBox(
          width: 100,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue:
                      item.discount > 0 ? item.discount.toString() : '',
                  decoration: InputDecoration(
                    hintText: '0',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 10),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  textAlign: TextAlign.right,
                  onChanged: (value) {
                    item.discount = double.tryParse(value) ?? 0;
                    _calculateAmounts();
                  },
                ),
              ),
              PopupMenuButton<String>(
                initialValue: item.discountType,
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                onSelected: (value) {
                  setState(() {
                    item.discountType = value;
                    _calculateAmounts();
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                      value: 'percentage', child: Text('%')),
                  const PopupMenuItem(value: 'amount', child: Text('₹')),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Amount (calculated)
        Container(
          width: 110,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            item.amount.toStringAsFixed(2),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            textAlign: TextAlign.right,
          ),
        ),

        const SizedBox(width: 8),

        // Delete button
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
          onPressed: () => _removeItem(index),
          tooltip: 'Remove item',
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  // Notes Section
  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Additional Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(height: 16),

          // Customer Notes
          TextFormField(
            controller: _customerNotesController,
            decoration: InputDecoration(
              labelText: 'Customer Notes',
              hintText: 'Notes visible to customer',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 16),

          // Internal Notes
          TextFormField(
            controller: _internalNotesController,
            decoration: InputDecoration(
              labelText: 'Internal Notes',
              hintText: 'Private notes (not visible to customer)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // Tax Settings Section (Right Sidebar)
 Widget _buildTaxSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tax Settings',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 12),

        // GST Toggle
        SwitchListTile(
          title: const Text('Enable GST'),
          value: _enableGST,
          activeColor: const Color(0xFF1e3a8a),
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            setState(() {
              _enableGST = value;
              _calculateAmounts();
            });
          },
        ),

        if (_enableGST) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _gstRate.toString(),
            decoration: InputDecoration(
              labelText: 'GST Rate (%)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              setState(() {
                _gstRate = double.tryParse(value) ?? 18;
                _calculateAmounts();
              });
            },
          ),
        ],

        const SizedBox(height: 12),

        // TDS Toggle
        SwitchListTile(
          title: const Text('Enable TDS'),
          subtitle: const Text('Tax Deducted at Source',
              style: TextStyle(fontSize: 12)),
          value: _enableTDS,
          activeColor: const Color(0xFF1e3a8a),
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            setState(() {
              _enableTDS = value;
              _calculateAmounts();
            });
          },
        ),

        if (_enableTDS) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _tdsRate.toString(),
            decoration: InputDecoration(
              labelText: 'TDS Rate (%)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              setState(() {
                _tdsRate = double.tryParse(value) ?? 0;
                _calculateAmounts();
              });
            },
          ),
        ],

        const SizedBox(height: 12),

        // TCS Toggle
        SwitchListTile(
          title: const Text('Enable TCS'),
          subtitle: const Text('Tax Collected at Source',
              style: TextStyle(fontSize: 12)),
          value: _enableTCS,
          activeColor: const Color(0xFF1e3a8a),
          contentPadding: EdgeInsets.zero,
          onChanged: (value) {
            setState(() {
              _enableTCS = value;
              _calculateAmounts();
            });
          },
        ),

        if (_enableTCS) ...[
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _tcsRate.toString(),
            decoration: InputDecoration(
              labelText: 'TCS Rate (%)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              setState(() {
                _tcsRate = double.tryParse(value) ?? 0;
                _calculateAmounts();
              });
            },
          ),
        ],
      ],
    );
  }

  // Summary Section (Right Sidebar)
  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Credit Note Summary',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(height: 16),

        _buildSummaryRow('Sub Total:', _subTotal, isBold: false),
        const SizedBox(height: 8),

        if (_enableTDS && _tdsAmount > 0) ...[
          _buildSummaryRow(
            'TDS (${_tdsRate.toStringAsFixed(1)}%):',
            -_tdsAmount,
            color: Colors.red[700],
            isBold: false,
          ),
          const SizedBox(height: 8),
        ],

        if (_enableTCS && _tcsAmount > 0) ...[
          _buildSummaryRow(
            'TCS (${_tcsRate.toStringAsFixed(1)}%):',
            _tcsAmount,
            isBold: false,
          ),
          const SizedBox(height: 8),
        ],

        if (_enableGST && _gstAmount > 0) ...[
          _buildSummaryRow(
            'CGST (${(_gstRate / 2).toStringAsFixed(1)}%):',
            _gstAmount / 2,
            isBold: false,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'SGST (${(_gstRate / 2).toStringAsFixed(1)}%):',
            _gstAmount / 2,
            isBold: false,
          ),
          const SizedBox(height: 8),
        ],

        const Divider(thickness: 2),
        const SizedBox(height: 8),

        _buildSummaryRow('Credit Amount:', _totalAmount,
            isBold: true, isTotal: true),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1e3a8a).withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF1e3a8a).withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Quantity:',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF34495E))),
                  Text(
                    _totalQuantity.toString(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF34495E)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Items:',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF34495E))),
                  Text(
                    _items
                        .where((item) => item.itemDetails.isNotEmpty)
                        .length
                        .toString(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF34495E)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndSend,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 16),
            label: Text(_isSaving ? 'Sending...' : 'Save & Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
              foregroundColor: const Color(0xFF1e3a8a),
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Color(0xFF1e3a8a)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
    String label,
    double amount, {
    Color? color,
    bool isBold = false,
    bool isTotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
            color: color ??
                (isTotal ? const Color(0xFF2C3E50) : const Color(0xFF7F8C8D)),
          ),
        ),
        Text(
          '${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.w500,
            color: color ??
                (isTotal ? const Color(0xFFE74C3C) : const Color(0xFF2C3E50)),
          ),
        ),
      ],
    );
  }

  // Show customer selector dialog
  Future<void> _showCustomerSelector() async {
    final TextEditingController searchController = TextEditingController();
    List<BillingCustomer> customers = [];
    List<BillingCustomer> filteredCustomers = [];
    bool isLoading = true;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Load customers when dialog opens
          if (isLoading && customers.isEmpty) {
            invoice_svc.InvoiceService.getBillingCustomers().then((response) {
              setDialogState(() {
                customers = response.customers;
                filteredCustomers = customers;
                isLoading = false;
              });
            }).catchError((error) {
              setDialogState(() {
                errorMessage = error.toString();
                isLoading = false;
              });
            });
          }

          return AlertDialog(
            title: const Text('Select Customer'),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search customers...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value.isEmpty) {
                          filteredCustomers = customers;
                        } else {
                          filteredCustomers = customers.where((customer) {
                            return customer.customerName
                                    .toLowerCase()
                                    .contains(value.toLowerCase()) ||
                                customer.customerEmail
                                    .toLowerCase()
                                    .contains(value.toLowerCase());
                          }).toList();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Customer list
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                            ? Center(child: Text('Error: $errorMessage'))
                            : filteredCustomers.isEmpty
                                ? const Center(
                                    child: Text('No customers found'))
                                : ListView.builder(
                                    itemCount: filteredCustomers.length,
                                    itemBuilder: (context, index) {
                                      final customer = filteredCustomers[index];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor:
                                              const Color(0xFFE74C3C),
                                          child: Text(
                                            customer.customerName[0]
                                                .toUpperCase(),
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        ),
                                        title: Text(customer.customerName),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(customer.customerEmail),
                                            Text(customer.customerPhone),
                                          ],
                                        ),
                                        onTap: () {
                                          setState(() {
                                            _selectedCustomerId = customer.id;
                                            _selectedCustomerName =
                                                customer.customerName;
                                            _selectedCustomerEmail =
                                                customer.customerEmail;
                                            _selectedCustomerPhone =
                                                customer.customerPhone;
                                            
                                            // Set billing address if available
                                            if (customer.addressLine1 != null ||
                                                customer.city != null) {
                                              _billingAddress = Address(
                                                street: customer.addressLine1,
                                                city: customer.city,
                                                state: customer.state,
                                                pincode: customer.postalCode,
                                                country: customer.country,
                                              );
                                            }
                                          });
                                          Navigator.pop(context);
                                        },
                                      );
                                    },
                                  ),
                  ),
                ],
              ),
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
}

// ============================================================================
// CREDIT NOTE ITEM ROW MODEL
// ============================================================================

class CreditNoteItemRow {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  CreditNoteItemRow({
    this.itemDetails = '',
    this.quantity = 0,
    this.rate = 0,
    this.discount = 0,
    this.discountType = 'percentage',
    this.amount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'itemDetails': itemDetails,
      'quantity': quantity,
      'rate': rate,
      'discount': discount,
      'discountType': discountType,
      'amount': amount,
    };
  }
}