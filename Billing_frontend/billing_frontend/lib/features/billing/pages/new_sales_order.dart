// ============================================================================
// NEW SALES ORDER SCREEN - Complete Flutter UI
// ============================================================================
// File: lib/screens/billing/new_sales_order.dart
// Complete form for creating/editing sales orders with all features
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/sales_order_service.dart';
import '../../../../core/services/invoice_service.dart';
import 'new_customer.dart';
import '../widgets/document_preview_buttons.dart';

// Navy blue gradient colors
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewSalesOrderScreen extends StatefulWidget {
  final String? salesOrderId;

  const NewSalesOrderScreen({Key? key, this.salesOrderId}) : super(key: key);

  @override
  State<NewSalesOrderScreen> createState() => _NewSalesOrderScreenState();
}

class _NewSalesOrderScreenState extends State<NewSalesOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Controllers
  final _referenceNumberController = TextEditingController();
  final _salespersonController = TextEditingController();
  final _subjectController = TextEditingController();
  final _deliveryMethodController = TextEditingController();
  final _customerNotesController = TextEditingController();
  final _termsConditionsController = TextEditingController();

  // Form Data
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;
  DateTime _salesOrderDate = DateTime.now();
  DateTime? _expectedShipmentDate;
  String _paymentTerms = 'Net 30';
  
  // Tax Settings
  double _tdsRate = 0;
  double _tcsRate = 0;
  double _gstRate = 18;
  bool _enableTDS = false;
  bool _enableTCS = false;
  bool _enableGST = true;

  // Items List
  List<SalesOrderItemData> _items = [];

  // Calculations
  double _subTotal = 0;
  double _tdsAmount = 0;
  double _tcsAmount = 0;
  double _gstAmount = 0;
  double _totalAmount = 0;
  int _totalQuantity = 0;

  // Payment Terms Options
  final List<String> _paymentTermsOptions = [
    'Due on Receipt',
    'Net 15',
    'Net 30',
    'Net 45',
    'Net 60',
  ];

  @override
  void initState() {
    super.initState();
    _addNewItem();
    
    if (widget.salesOrderId != null) {
      _loadSalesOrderData();
    }
  }

  @override
  void dispose() {
    _referenceNumberController.dispose();
    _salespersonController.dispose();
    _subjectController.dispose();
    _deliveryMethodController.dispose();
    _customerNotesController.dispose();
    _termsConditionsController.dispose();
    for (final item in _items) { item.dispose(); }
    super.dispose();
  }

  void _calculateAmounts() {
    setState(() {
      _subTotal = 0;
      _totalQuantity = 0;
      
      for (var item in _items) {
        if (item.quantity > 0 && item.rate > 0) {
          double itemAmount = item.quantity * item.rate;
          
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
      
      _tdsAmount = _enableTDS ? (_subTotal * _tdsRate / 100) : 0;
      _tcsAmount = _enableTCS ? (_subTotal * _tcsRate / 100) : 0;
      double gstBase = _subTotal - _tdsAmount + _tcsAmount;
      _gstAmount = _enableGST ? (gstBase * _gstRate / 100) : 0;
      _totalAmount = _subTotal - _tdsAmount + _tcsAmount + _gstAmount;
    });
  }

  void _addNewItem() {
    setState(() {
      _items.add(SalesOrderItemData());
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
      _calculateAmounts();
    });
  }

  Future<void> _loadSalesOrderData() async {
    setState(() => _isLoading = true);
    
    try {
      final salesOrder = await SalesOrderService.getSalesOrder(widget.salesOrderId!);
      
      setState(() {
        _selectedCustomerId = salesOrder.customerId;
        _selectedCustomerName = salesOrder.customerName;
        _selectedCustomerEmail = salesOrder.customerEmail;
        _selectedCustomerPhone = salesOrder.customerPhone;
        _referenceNumberController.text = salesOrder.referenceNumber ?? '';
        _salesOrderDate = salesOrder.salesOrderDate;
        _expectedShipmentDate = salesOrder.expectedShipmentDate;
        _paymentTerms = salesOrder.paymentTerms;
        _deliveryMethodController.text = salesOrder.deliveryMethod ?? '';
        _salespersonController.text = salesOrder.salesperson ?? '';
        _subjectController.text = salesOrder.subject ?? '';
        _customerNotesController.text = salesOrder.customerNotes ?? '';
        _termsConditionsController.text = salesOrder.termsAndConditions ?? '';
        
        _tdsRate = salesOrder.tdsRate;
        _tcsRate = salesOrder.tcsRate;
        _gstRate = salesOrder.gstRate;
        _enableTDS = salesOrder.tdsRate > 0;
        _enableTCS = salesOrder.tcsRate > 0;
        _enableGST = salesOrder.gstRate > 0;
        
        _items = salesOrder.items.map((item) => SalesOrderItemData(
          itemDetails: item.itemDetails,
          quantity: item.quantity,
          rate: item.rate,
          discount: item.discount,
          discountType: item.discountType,
          amount: item.amount,
        )).toList();
        
        _calculateAmounts();
      });
      
    } catch (e) {
      _showErrorSnackbar('Failed to load sales order: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _validateItems() {
    final nonEmptyItems = _items.where((item) => item.itemDetails.trim().isNotEmpty).toList();
    
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

  Map<String, dynamic> _buildSalesOrderData(String status) {
    final validItems = _items.where((item) => item.itemDetails.trim().isNotEmpty).toList();
    
    return {
      'customerId': _selectedCustomerId,
      'customerName': _selectedCustomerName,
      'customerEmail': _selectedCustomerEmail,
      'customerPhone': _selectedCustomerPhone ?? '',
      'referenceNumber': _referenceNumberController.text.trim(),
      'salesOrderDate': _salesOrderDate.toIso8601String(),
      'expectedShipmentDate': _expectedShipmentDate?.toIso8601String(),
      'paymentTerms': _paymentTerms,
      'deliveryMethod': _deliveryMethodController.text.trim(),
      'salesperson': _salespersonController.text.trim(),
      'subject': _subjectController.text.trim(),
      'items': validItems.map((item) => item.toJson()).toList(),
      'customerNotes': _customerNotesController.text.trim(),
      'termsAndConditions': _termsConditionsController.text.trim(),
      'tdsRate': _enableTDS ? _tdsRate : 0,
      'tcsRate': _enableTCS ? _tcsRate : 0,
      'gstRate': _enableGST ? _gstRate : 0,
      'status': status,
    };
  }

  Future<void> _saveAsDraft() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showErrorSnackbar('Please select a customer');
      return;
    }
    if (!_validateItems()) return;
    
    setState(() => _isSaving = true);
    
    try {
      final salesOrderData = _buildSalesOrderData('DRAFT');
      
      if (widget.salesOrderId != null) {
        await SalesOrderService.updateSalesOrder(widget.salesOrderId!, salesOrderData);
      } else {
        await SalesOrderService.createSalesOrder(salesOrderData);
      }
      
      _showSuccessSnackbar('Sales order saved as draft');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar('Failed to save sales order: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showErrorSnackbar('Please select a customer');
      return;
    }
    if (_selectedCustomerEmail == null || _selectedCustomerEmail!.isEmpty) {
      _showErrorSnackbar('Customer email is required to send sales order');
      return;
    }
    if (!_validateItems()) return;
    
    setState(() => _isSaving = true);
    
    try {
      final salesOrderData = _buildSalesOrderData('OPEN');
      
      SalesOrder salesOrder;
      if (widget.salesOrderId != null) {
        salesOrder = await SalesOrderService.updateSalesOrder(widget.salesOrderId!, salesOrderData);
      } else {
        salesOrder = await SalesOrderService.createSalesOrder(salesOrderData);
      }
      
      await SalesOrderService.sendSalesOrder(salesOrder.id);
      
      _showSuccessSnackbar('Sales order sent to $_selectedCustomerEmail');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar('Failed to send sales order: $e');
    } finally {
      setState(() => _isSaving = false);
    }
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
  @override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final isNarrow = screenWidth < 800;

  return Scaffold(
    backgroundColor: Colors.grey[100],
    appBar: AppBar(
      title: Text(
        widget.salesOrderId != null ? 'Edit Sales Order' : 'New Sales Order',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      backgroundColor: const Color(0xFF1e3a8a),
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'View PDF',
          icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
          onPressed: () => openDocumentPdf(context: context, docId: widget.salesOrderId, pdfEndpoint: '/api/finance/sales-orders', docNumber: 'SO'),
        ),
        IconButton(
          tooltip: 'Preview Email',
          icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
          onPressed: () => openEmailPreview(context: context, docId: widget.salesOrderId, emailEndpoint: '/api/finance/sales-orders'),
        ),
        TextButton.icon(
          onPressed: _isSaving ? null : _saveAsDraft,
          icon: const Icon(Icons.save_outlined, color: Colors.white70, size: 16),
          label: const Text('Save as Draft', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndSend,
            icon: const Icon(Icons.send, size: 15),
            label: const Text('Save & Send', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1e3a8a),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: isNarrow
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildCustomerSection(),
                        const SizedBox(height: 16),
                        _buildSalesOrderDetailsSection(),
                        const SizedBox(height: 16),
                        _buildItemsSection(),
                        const SizedBox(height: 16),
                        _buildTaxSettingsSection(),
                        const SizedBox(height: 16),
                        _buildSummarySection(),
                        const SizedBox(height: 16),
                        _buildNotesSection(),
                      ],
                    ),
                  )
                : Row(
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
                              _buildSalesOrderDetailsSection(),
                              const SizedBox(height: 20),
                              _buildItemsSection(),
                              const SizedBox(height: 20),
                              _buildNotesSection(),
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
                              const Divider(height: 28),
                              _buildSummarySection(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
  );
}

  Widget _buildCustomerSection() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Information',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a)),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _showCustomerSelector(),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: Color(0xFF1e3a8a), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _selectedCustomerName ?? 'Select Customer *',
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedCustomerName != null ? const Color(0xFF2C3E50) : Colors.grey[600],
                      fontWeight: _selectedCustomerName != null ? FontWeight.w500 : FontWeight.normal,
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
          Row(
            children: [
              const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(_selectedCustomerEmail!, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ],
          ),
        ],
      ],
    ),
  );
}

  Widget _buildSalesOrderDetailsSection() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sales Order Details',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a)),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            if (isWide) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _referenceNumberController,
                          decoration: InputDecoration(
                            labelText: 'Reference / PO Number',
                            hintText: 'Customer PO Number',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.numbers, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _salesOrderDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) setState(() => _salesOrderDate = date);
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Sales Order Date *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              prefixIcon: const Icon(Icons.calendar_today, size: 18),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            child: Text(DateFormat('dd MMM yyyy').format(_salesOrderDate), style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _expectedShipmentDate ?? DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) setState(() => _expectedShipmentDate = date);
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Expected Shipment Date',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              prefixIcon: const Icon(Icons.local_shipping, size: 18),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              suffixIcon: _expectedShipmentDate != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () => setState(() => _expectedShipmentDate = null),
                                    )
                                  : null,
                            ),
                            child: Text(
                              _expectedShipmentDate != null ? DateFormat('dd MMM yyyy').format(_expectedShipmentDate!) : 'Select Date',
                              style: TextStyle(fontSize: 14, color: _expectedShipmentDate != null ? Colors.black : Colors.grey[600]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _paymentTerms,
                          decoration: InputDecoration(
                            labelText: 'Payment Terms *',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.payment, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          items: _paymentTermsOptions.map((term) => DropdownMenuItem(value: term, child: Text(term, style: const TextStyle(fontSize: 14)))).toList(),
                          onChanged: (value) { if (value != null) setState(() => _paymentTerms = value); },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _deliveryMethodController,
                          decoration: InputDecoration(
                            labelText: 'Delivery Method',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.delivery_dining, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _salespersonController,
                          decoration: InputDecoration(
                            labelText: 'Salesperson',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.person, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  TextFormField(
                    controller: _referenceNumberController,
                    decoration: InputDecoration(
                      labelText: 'Reference / PO Number',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.numbers, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(context: context, initialDate: _salesOrderDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (date != null) setState(() => _salesOrderDate = date);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Sales Order Date *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.calendar_today, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      child: Text(DateFormat('dd MMM yyyy').format(_salesOrderDate), style: const TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(context: context, initialDate: _expectedShipmentDate ?? DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime(2030));
                      if (date != null) setState(() => _expectedShipmentDate = date);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Expected Shipment Date',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.local_shipping, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      child: Text(
                        _expectedShipmentDate != null ? DateFormat('dd MMM yyyy').format(_expectedShipmentDate!) : 'Select Date',
                        style: TextStyle(fontSize: 14, color: _expectedShipmentDate != null ? Colors.black : Colors.grey[600]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _paymentTerms,
                    decoration: InputDecoration(
                      labelText: 'Payment Terms *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.payment, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: _paymentTermsOptions.map((term) => DropdownMenuItem(value: term, child: Text(term, style: const TextStyle(fontSize: 14)))).toList(),
                    onChanged: (value) { if (value != null) setState(() => _paymentTerms = value); },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _deliveryMethodController,
                    decoration: InputDecoration(
                      labelText: 'Delivery Method',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.delivery_dining, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _salespersonController,
                    decoration: InputDecoration(
                      labelText: 'Salesperson',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.person, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              );
            }
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _subjectController,
          decoration: InputDecoration(
            labelText: 'Subject / Description',
            hintText: 'Brief description of the order',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.subject, size: 18),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          maxLines: 2,
        ),
      ],
    ),
  );
}

  Widget _buildItemsSection() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Item Table', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a))),
            ElevatedButton.icon(
              onPressed: _addNewItem,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Item', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1e3a8a),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 600),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e3a8a),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: const [
                      SizedBox(width: 240, child: Text('ITEM DETAILS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                      SizedBox(width: 8),
                      SizedBox(width: 70, child: Text('QTY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center)),
                      SizedBox(width: 8),
                      SizedBox(width: 90, child: Text('RATE (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
                      SizedBox(width: 8),
                      SizedBox(width: 110, child: Text('DISCOUNT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
                      SizedBox(width: 8),
                      SizedBox(width: 100, child: Text('AMOUNT (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.right)),
                      SizedBox(width: 40),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text('No items added yet', style: TextStyle(color: Colors.grey[600], fontSize: 13))),
                  )
                else
                  Column(
                    children: [
                      for (int i = 0; i < _items.length; i++) ...[
                        _buildItemRow(i),
                        if (i < _items.length - 1) const Divider(height: 12),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildItemRow(int index) {
  final item = _items[index];
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 240,
        child: TextFormField(
          controller: item.detailsCtrl,
          decoration: InputDecoration(
            hintText: 'Item description',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          maxLines: 2,
          style: const TextStyle(fontSize: 13),
          onChanged: (value) { item.itemDetails = value; },
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 70,
        child: TextFormField(
          controller: item.qtyCtrl,
          decoration: InputDecoration(
            hintText: '0',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) { item.quantity = double.tryParse(value) ?? 0; _calculateAmounts(); },
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 90,
        child: TextFormField(
          controller: item.rateCtrl,
          decoration: InputDecoration(
            hintText: '0.00',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 13),
          onChanged: (value) { item.rate = double.tryParse(value) ?? 0; _calculateAmounts(); },
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 110,
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: item.discountCtrl,
                decoration: InputDecoration(
                  hintText: '0',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13),
                onChanged: (value) { item.discount = double.tryParse(value) ?? 0; _calculateAmounts(); },
              ),
            ),
            PopupMenuButton<String>(
              initialValue: item.discountType,
              icon: Text(item.discountType == 'percentage' ? '%' : '₹', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a))),
              onSelected: (value) { setState(() { item.discountType = value; _calculateAmounts(); }); },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'percentage', child: Text('%')),
                const PopupMenuItem(value: 'amount', child: Text('₹')),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Text(item.amount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 32,
        child: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
          onPressed: () => _removeItem(index),
          padding: EdgeInsets.zero,
          tooltip: 'Remove',
        ),
      ),
    ],
  );
}

  Widget _buildNotesSection() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Additional Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a))),
        const SizedBox(height: 12),
        TextFormField(
          controller: _customerNotesController,
          decoration: InputDecoration(
            labelText: 'Customer Notes',
            hintText: 'Notes visible on sales order',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            alignLabelWithHint: true,
            contentPadding: const EdgeInsets.all(12),
          ),
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _termsConditionsController,
          decoration: InputDecoration(
            labelText: 'Terms & Conditions',
            hintText: 'Payment terms, policies, etc.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            alignLabelWithHint: true,
            contentPadding: const EdgeInsets.all(12),
          ),
          maxLines: 3,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    ),
  );
}

Widget _buildTaxSettingsSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Tax Settings', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a))),
      const SizedBox(height: 12),
      SwitchListTile(
        title: const Text('Enable GST', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        value: _enableGST,
        activeColor: const Color(0xFF1e3a8a),
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (value) { setState(() { _enableGST = value; _calculateAmounts(); }); },
      ),
      if (_enableGST) ...[
        const SizedBox(height: 6),
        TextFormField(
          initialValue: _gstRate.toString(),
          decoration: InputDecoration(
            labelText: 'GST Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13),
          onChanged: (value) { setState(() { _gstRate = double.tryParse(value) ?? 18; _calculateAmounts(); }); },
        ),
      ],
      const SizedBox(height: 8),
      SwitchListTile(
        title: const Text('Enable TDS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: const Text('Tax Deducted at Source', style: TextStyle(fontSize: 11)),
        value: _enableTDS,
        activeColor: const Color(0xFF1e3a8a),
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (value) { setState(() { _enableTDS = value; _calculateAmounts(); }); },
      ),
      if (_enableTDS) ...[
        const SizedBox(height: 6),
        TextFormField(
          initialValue: _tdsRate.toString(),
          decoration: InputDecoration(
            labelText: 'TDS Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13),
          onChanged: (value) { setState(() { _tdsRate = double.tryParse(value) ?? 0; _calculateAmounts(); }); },
        ),
      ],
      const SizedBox(height: 8),
      SwitchListTile(
        title: const Text('Enable TCS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: const Text('Tax Collected at Source', style: TextStyle(fontSize: 11)),
        value: _enableTCS,
        activeColor: const Color(0xFF1e3a8a),
        contentPadding: EdgeInsets.zero,
        dense: true,
        onChanged: (value) { setState(() { _enableTCS = value; _calculateAmounts(); }); },
      ),
      if (_enableTCS) ...[
        const SizedBox(height: 6),
        TextFormField(
          initialValue: _tcsRate.toString(),
          decoration: InputDecoration(
            labelText: 'TCS Rate (%)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixText: '%',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13),
          onChanged: (value) { setState(() { _tcsRate = double.tryParse(value) ?? 0; _calculateAmounts(); }); },
        ),
      ],
    ],
  );
}

Widget _buildSummarySection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Sales Order Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a))),
      const SizedBox(height: 12),
      _buildSummaryRow('Sub Total:', _subTotal),
      if (_enableTDS && _tdsAmount > 0) ...[
        const SizedBox(height: 6),
        _buildSummaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%):', -_tdsAmount, color: Colors.red[700]),
      ],
      if (_enableTCS && _tcsAmount > 0) ...[
        const SizedBox(height: 6),
        _buildSummaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%):', _tcsAmount),
      ],
      if (_enableGST && _gstAmount > 0) ...[
        const SizedBox(height: 6),
        _buildSummaryRow('CGST (${(_gstRate / 2).toStringAsFixed(1)}%):', _gstAmount / 2),
        const SizedBox(height: 6),
        _buildSummaryRow('SGST (${(_gstRate / 2).toStringAsFixed(1)}%):', _gstAmount / 2),
      ],
      const Divider(thickness: 1.5),
      _buildSummaryRow('Total Amount:', _totalAmount, isBold: true, isTotal: true),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1e3a8a).withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1e3a8a).withOpacity(0.2)),
        ),
        child: Column(
          children: [
            _buildInfoPair('Total Qty', _totalQuantity.toString()),
            const SizedBox(height: 4),
            _buildInfoPair('Total Items', _items.where((i) => i.itemDetails.isNotEmpty).length.toString()),
            const SizedBox(height: 4),
            _buildInfoPair('Payment Terms', _paymentTerms),
          ],
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveAndSend,
          icon: _isSaving ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send, size: 15),
          label: Text(_isSaving ? 'Sending...' : 'Save & Send Order', style: const TextStyle(fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF27AE60),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isSaving ? null : _saveAsDraft,
          icon: const Icon(Icons.save_outlined, size: 15),
          label: const Text('Save as Draft', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1e3a8a),
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: Color(0xFF1e3a8a)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ],
  );
}

Widget _buildInfoPair(String label, String value) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF34495E))),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a))),
    ],
  );
}

 Widget _buildSummaryRow(String label, double amount, {Color? color, bool isBold = false, bool isTotal = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: isTotal ? 14 : 13,
          fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isTotal ? const Color(0xFF1e3a8a) : const Color(0xFF7F8C8D)),
        ),
      ),
      Text(
        '${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: isTotal ? 16 : 13,
          fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.w500,
          color: color ?? (isTotal ? const Color(0xFF27AE60) : const Color(0xFF2C3E50)),
        ),
      ),
    ],
  );
}

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
          if (isLoading && customers.isEmpty) {
            InvoiceService.getBillingCustomers().then((response) {
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
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search customers...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value.isEmpty) {
                          filteredCustomers = customers;
                        } else {
                          filteredCustomers = customers.where((customer) {
                            return customer.customerName.toLowerCase().contains(value.toLowerCase()) ||
                                   customer.customerEmail.toLowerCase().contains(value.toLowerCase());
                          }).toList();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                            ? Center(child: Text('Error: $errorMessage'))
                            : filteredCustomers.isEmpty
                                ? const Center(child: Text('No customers found'))
                                : ListView.builder(
                                    itemCount: filteredCustomers.length,
                                    itemBuilder: (context, index) {
                                      final customer = filteredCustomers[index];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: const Color(0xFF1e3a8a),
                                          child: Text(customer.customerName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                                        ),
                                        title: Text(customer.customerName),
                                        subtitle: Text(customer.customerEmail),
                                        onTap: () {
                                          setState(() {
                                            _selectedCustomerId = customer.id;
                                            _selectedCustomerName = customer.customerName;
                                            _selectedCustomerEmail = customer.customerEmail;
                                            _selectedCustomerPhone = customer.customerPhone;
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
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const NewCustomerPage()));
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add New Customer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1e3a8a),
                        side: const BorderSide(color: Color(0xFF1e3a8a)),
                      ),
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

class SalesOrderItemData {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  // Controllers keep field values stable across rebuilds
  late final TextEditingController detailsCtrl;
  late final TextEditingController qtyCtrl;
  late final TextEditingController rateCtrl;
  late final TextEditingController discountCtrl;

  SalesOrderItemData({
    this.itemDetails = '',
    this.quantity = 0,
    this.rate = 0,
    this.discount = 0,
    this.discountType = 'percentage',
    this.amount = 0,
  }) {
    detailsCtrl  = TextEditingController(text: itemDetails);
    qtyCtrl      = TextEditingController(text: quantity > 0 ? quantity.toString() : '');
    rateCtrl     = TextEditingController(text: rate > 0 ? rate.toStringAsFixed(2) : '');
    discountCtrl = TextEditingController(text: discount > 0 ? discount.toString() : '');
  }

  void dispose() {
    detailsCtrl.dispose();
    qtyCtrl.dispose();
    rateCtrl.dispose();
    discountCtrl.dispose();
  }

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