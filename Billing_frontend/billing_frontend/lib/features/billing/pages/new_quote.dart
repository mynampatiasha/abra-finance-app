// ============================================================================
// NEW QUOTE SCREEN - Complete Flutter UI
// ============================================================================
// File: lib/screens/billing/new_quote.dart
// Matches Zoho Books Quote functionality exactly
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/quote_service.dart';
import '../../../../core/services/invoice_service.dart';
import 'new_customer.dart';
import '../widgets/document_preview_buttons.dart';

// Navy blue gradient colors
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewQuoteScreen extends StatefulWidget {
  final String? quoteId;

  const NewQuoteScreen({Key? key, this.quoteId}) : super(key: key);

  @override
  State<NewQuoteScreen> createState() => _NewQuoteScreenState();
}

class _NewQuoteScreenState extends State<NewQuoteScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Controllers
  final _referenceNumberController = TextEditingController();
  final _salespersonController = TextEditingController();
  final _projectNameController = TextEditingController();
  final _subjectController = TextEditingController();
  final _customerNotesController = TextEditingController();
  final _termsConditionsController = TextEditingController();

  // Form Data
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;
  DateTime _quoteDate = DateTime.now();
  DateTime _expiryDate = DateTime.now().add(const Duration(days: 30));
  
  // Tax Settings
  double _tdsRate = 0;
  double _tcsRate = 0;
  double _gstRate = 18;
  bool _enableTDS = false;
  bool _enableTCS = false;
  bool _enableGST = true;

  // Items List
  List<QuoteItemData> _items = [];

  // Calculations
  double _subTotal = 0;
  double _tdsAmount = 0;
  double _tcsAmount = 0;
  double _gstAmount = 0;
  double _totalAmount = 0;
  int _totalQuantity = 0;

  @override
  void initState() {
    super.initState();
    _addNewItem();
    
    if (widget.quoteId != null) {
      _loadQuoteData();
    }
  }

  @override
  void dispose() {
    _referenceNumberController.dispose();
    _salespersonController.dispose();
    _projectNameController.dispose();
    _subjectController.dispose();
    _customerNotesController.dispose();
    _termsConditionsController.dispose();
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
      _items.add(QuoteItemData());
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateAmounts();
    });
  }

  Future<void> _loadQuoteData() async {
    setState(() => _isLoading = true);
    
    try {
      final quote = await QuoteService.getQuote(widget.quoteId!);
      
      setState(() {
        _selectedCustomerId = quote.customerId;
        _selectedCustomerName = quote.customerName;
        _selectedCustomerEmail = quote.customerEmail;
        _selectedCustomerPhone = quote.customerPhone; // ✅ ADD THIS
        _referenceNumberController.text = quote.referenceNumber ?? '';
        _quoteDate = quote.quoteDate;
        _expiryDate = quote.expiryDate;
        _salespersonController.text = quote.salesperson ?? '';
        _projectNameController.text = quote.projectName ?? '';
        _subjectController.text = quote.subject ?? '';
        _customerNotesController.text = quote.customerNotes ?? '';
        _termsConditionsController.text = quote.termsAndConditions ?? '';
        
        _tdsRate = quote.tdsRate;
        _tcsRate = quote.tcsRate;
        _gstRate = quote.gstRate;
        _enableTDS = quote.tdsRate > 0;
        _enableTCS = quote.tcsRate > 0;
        _enableGST = quote.gstRate > 0;
        
        _items = quote.items.map((item) => QuoteItemData(
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
      _showErrorSnackbar('Failed to load quote: $e');
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

  Map<String, dynamic> _buildQuoteData(String status) {
    final validItems = _items.where((item) => item.itemDetails.trim().isNotEmpty).toList();
    
    // Note: organizationId is automatically extracted from JWT token on backend
    // The backend middleware (verifyJWT) adds req.user.organizationId from the token
    // So we don't need to send it from frontend - backend will add it automatically
    return {
      'customerId': _selectedCustomerId,
      'customerName': _selectedCustomerName,
      'customerEmail': _selectedCustomerEmail,
      'customerPhone': _selectedCustomerPhone, // ✅ ADD THIS
      'referenceNumber': _referenceNumberController.text.trim(),
      'quoteDate': _quoteDate.toIso8601String(),
      'expiryDate': _expiryDate.toIso8601String(),
      'salesperson': _salespersonController.text.trim(),
      'projectName': _projectNameController.text.trim(),
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
      final quoteData = _buildQuoteData('DRAFT');
      
      if (widget.quoteId != null) {
        await QuoteService.updateQuote(widget.quoteId!, quoteData);
      } else {
        await QuoteService.createQuote(quoteData);
      }
      
      _showSuccessSnackbar('Quote saved as draft');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar('Failed to save quote: $e');
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
      _showErrorSnackbar('Customer email is required to send quote');
      return;
    }
    if (!_validateItems()) return;
    
    setState(() => _isSaving = true);
    
    try {
      final quoteData = _buildQuoteData('SENT');
      
      Quote quote;
      if (widget.quoteId != null) {
        quote = await QuoteService.updateQuote(widget.quoteId!, quoteData);
      } else {
        quote = await QuoteService.createQuote(quoteData);
      }
      
      await QuoteService.sendQuote(quote.id);
      
      _showSuccessSnackbar('Quote sent to $_selectedCustomerEmail');
      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackbar('Failed to send quote: $e');
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
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 900;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.quoteId != null ? 'Edit Quote' : 'New Quote'),
        backgroundColor: const Color(0xFF1e3a8a),
        foregroundColor: Colors.white,
        actions: isNarrow
            ? [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (value) {
                    if (value == 'draft') _saveAsDraft();
                    if (value == 'send') _saveAndSend();
                    if (value == 'pdf') {
                      if (widget.quoteId == null || widget.quoteId!.isEmpty) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                          content: Text('Save the quote first to preview PDF'),
                          behavior: SnackBarBehavior.floating,
                        ));
                        return;
                      }
                      openDocumentPdf(context: context, docId: widget.quoteId, pdfEndpoint: '/api/finance/quotes', docNumber: 'Quote');
                    }
                    if (value == 'email') {
                      if (widget.quoteId == null || widget.quoteId!.isEmpty) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                          content: Text('Save the quote first to preview email'),
                          behavior: SnackBarBehavior.floating,
                        ));
                        return;
                      }
                      openEmailPreview(context: context, docId: widget.quoteId, emailEndpoint: '/api/finance/quotes');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'pdf',
                      child: ListTile(
                        leading: Icon(Icons.picture_as_pdf_outlined),
                        title: Text('View PDF'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'email',
                      child: ListTile(
                        leading: Icon(Icons.email_outlined),
                        title: Text('Preview Email'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'draft',
                      child: ListTile(
                        leading: Icon(Icons.save_outlined),
                        title: Text('Save as Draft'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'send',
                      child: ListTile(
                        leading: Icon(Icons.send),
                        title: Text('Save & Send'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ]
            : [
                IconButton(
                  tooltip: 'View PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
                  onPressed: () {
                    if (widget.quoteId == null || widget.quoteId!.isEmpty) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                        content: Text('Save the quote first to preview PDF'),
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    openDocumentPdf(context: context, docId: widget.quoteId, pdfEndpoint: '/api/finance/quotes', docNumber: 'Quote');
                  },
                ),
                IconButton(
                  tooltip: 'Preview Email',
                  icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
                  onPressed: () {
                    if (widget.quoteId == null || widget.quoteId!.isEmpty) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                        content: Text('Save the quote first to preview email'),
                        behavior: SnackBarBehavior.floating,
                      ));
                      return;
                    }
                    openEmailPreview(context: context, docId: widget.quoteId, emailEndpoint: '/api/finance/quotes');
                  },
                ),
                TextButton.icon(
                  onPressed: _isSaving ? null : _saveAsDraft,
                  icon: const Icon(Icons.save_outlined, color: Colors.white70),
                  label: const Text('Save as Draft', style: TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveAndSend,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Save & Send'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCustomerSection(),
                          const SizedBox(height: 16),
                          _buildQuoteDetailsSection(),
                          const SizedBox(height: 16),
                          _buildItemsSection(),
                          const SizedBox(height: 16),
                          _buildNotesSection(),
                          const SizedBox(height: 16),
                          _buildTaxSettingsSection(),
                          const Divider(height: 32),
                          _buildSummarySection(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildCustomerSection(),
                                const SizedBox(height: 24),
                                _buildQuoteDetailsSection(),
                                const SizedBox(height: 24),
                                _buildItemsSection(),
                                const SizedBox(height: 24),
                                _buildNotesSection(),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: 350,
                          color: Colors.white,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
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
                    ),
            ),
    );
  }

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
              color: Color(0xFF1e3a8a),
            ),
          ),
          const SizedBox(height: 16),
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
                  const Icon(Icons.person_outline, color: Color(0xFF3498DB)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCustomerName ?? 'Select Customer *',
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedCustomerName != null
                            ? const Color(0xFF1e3a8a)
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
        ],
      ),
    );
  }

  Widget _buildQuoteDetailsSection() {
    final isNarrow = MediaQuery.of(context).size.width < 900;

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
          const Text(
            'Quote Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1e3a8a),
            ),
          ),
          const SizedBox(height: 16),

          // Reference + Quote Date
          isNarrow
              ? Column(
                  children: [
                    TextFormField(
                      controller: _referenceNumberController,
                      decoration: InputDecoration(
                        labelText: 'Reference Number',
                        hintText: 'Optional',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.numbers),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _quoteDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) setState(() => _quoteDate = date);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Quote Date *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.calendar_today),
                        ),
                        child: Text(DateFormat('dd MMM yyyy').format(_quoteDate)),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _referenceNumberController,
                        decoration: InputDecoration(
                          labelText: 'Reference Number',
                          hintText: 'Optional',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.numbers),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _quoteDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (date != null) setState(() => _quoteDate = date);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Quote Date *',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.calendar_today),
                          ),
                          child: Text(DateFormat('dd MMM yyyy').format(_quoteDate)),
                        ),
                      ),
                    ),
                  ],
                ),

          const SizedBox(height: 16),

          // Expiry + Salesperson
          isNarrow
              ? Column(
                  children: [
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _expiryDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) setState(() => _expiryDate = date);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Expiry Date *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.event),
                        ),
                        child: Text(DateFormat('dd MMM yyyy').format(_expiryDate)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _salespersonController,
                      decoration: InputDecoration(
                        labelText: 'Salesperson',
                        hintText: 'Optional',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _expiryDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2030),
                          );
                          if (date != null) setState(() => _expiryDate = date);
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Expiry Date *',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            prefixIcon: const Icon(Icons.event),
                          ),
                          child: Text(DateFormat('dd MMM yyyy').format(_expiryDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _salespersonController,
                        decoration: InputDecoration(
                          labelText: 'Salesperson',
                          hintText: 'Optional',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.person),
                        ),
                      ),
                    ),
                  ],
                ),

          const SizedBox(height: 16),

          TextFormField(
            controller: _projectNameController,
            decoration: InputDecoration(
              labelText: 'Project Name',
              hintText: _selectedCustomerId == null
                  ? 'Select a customer to associate a project'
                  : 'Optional',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.folder),
              enabled: _selectedCustomerId != null,
            ),
          ),

          const SizedBox(height: 16),

          TextFormField(
            controller: _subjectController,
            decoration: InputDecoration(
              labelText: 'Subject',
              hintText: 'Optional',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.subject),
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
                'Item Table',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1e3a8a),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addNewItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Item'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1e3a8a),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Horizontally scrollable table
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e3a8a),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      SizedBox(width: 220, child: Text('ITEM DETAILS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                      SizedBox(width: 12),
                      SizedBox(width: 70, child: Text('QTY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                      SizedBox(width: 12),
                      SizedBox(width: 100, child: Text('RATE (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                      SizedBox(width: 12),
                      SizedBox(width: 110, child: Text('DISCOUNT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                      SizedBox(width: 12),
                      SizedBox(width: 110, child: Text('AMOUNT (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.right)),
                      SizedBox(width: 44),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('No items added yet', style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  )
                else
                  ...List.generate(_items.length, (index) {
                    return Column(
                      children: [
                        _buildItemRow(index),
                        if (index < _items.length - 1)
                          const Divider(height: 16),
                      ],
                    );
                  }),
              ],
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
          width: 220,
          child: TextFormField(
            initialValue: item.itemDetails,
            decoration: InputDecoration(
              hintText: 'Enter item description',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            maxLines: 2,
            onChanged: (value) {
              item.itemDetails = value;
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 70,
          child: TextFormField(
            initialValue: item.quantity > 0 ? item.quantity.toString() : '',
            decoration: InputDecoration(
              hintText: '0',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: TextFormField(
            initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
            decoration: InputDecoration(
              hintText: '0.00',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onChanged: (value) {
              item.rate = double.tryParse(value) ?? 0;
              _calculateAmounts();
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.discount > 0 ? item.discount.toString() : '',
                  decoration: InputDecoration(
                    hintText: '0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                  const PopupMenuItem(value: 'percentage', child: Text('%')),
                  const PopupMenuItem(value: 'amount', child: Text('₹')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 110,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            item.amount.toStringAsFixed(2),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
          onPressed: () => _removeItem(index),
          tooltip: 'Remove item',
        ),
      ],
    );
  }

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
              color: Color(0xFF1e3a8a),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _customerNotesController,
            decoration: InputDecoration(
              labelText: 'Customer Notes',
              hintText: 'Notes visible on quote',
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
              hintText: 'Payment terms, policies, etc.',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildTaxSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tax Settings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a)),
        ),
        const SizedBox(height: 16),
        
        SwitchListTile(
          title: const Text('Enable GST'),
          value: _enableGST,
          activeColor: const Color(0xFF3498DB),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              setState(() {
                _gstRate = double.tryParse(value) ?? 18;
                _calculateAmounts();
              });
            },
          ),
        ],
        
        const SizedBox(height: 16),
        
        SwitchListTile(
          title: const Text('Enable TDS'),
          subtitle: const Text('Tax Deducted at Source', style: TextStyle(fontSize: 12)),
          value: _enableTDS,
          activeColor: const Color(0xFF3498DB),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              setState(() {
                _tdsRate = double.tryParse(value) ?? 0;
                _calculateAmounts();
              });
            },
          ),
        ],
        
        const SizedBox(height: 16),
        
        SwitchListTile(
          title: const Text('Enable TCS'),
          subtitle: const Text('Tax Collected at Source', style: TextStyle(fontSize: 12)),
          value: _enableTCS,
          activeColor: const Color(0xFF3498DB),
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixText: '%',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quote Summary',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1e3a8a)),
        ),
        const SizedBox(height: 16),
        
        _buildSummaryRow('Sub Total:', _subTotal, isBold: false),
        const SizedBox(height: 8),
        
        if (_enableTDS && _tdsAmount > 0) ...[
          _buildSummaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%):', -_tdsAmount, color: Colors.red[700], isBold: false),
          const SizedBox(height: 8),
        ],
        
        if (_enableTCS && _tcsAmount > 0) ...[
          _buildSummaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%):', _tcsAmount, isBold: false),
          const SizedBox(height: 8),
        ],
        
        if (_enableGST && _gstAmount > 0) ...[
          _buildSummaryRow('CGST (${(_gstRate / 2).toStringAsFixed(1)}%):', _gstAmount / 2, isBold: false),
          const SizedBox(height: 8),
          _buildSummaryRow('SGST (${(_gstRate / 2).toStringAsFixed(1)}%):', _gstAmount / 2, isBold: false),
          const SizedBox(height: 8),
        ],
        
        const Divider(thickness: 2),
        const SizedBox(height: 8),
        
        _buildSummaryRow('Total Amount:', _totalAmount, isBold: true, isTotal: true),
        
        const SizedBox(height: 16),
        
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Quantity:', style: TextStyle(fontSize: 13, color: Color(0xFF34495E))),
                  Text(_totalQuantity.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF34495E))),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total Items:', style: TextStyle(fontSize: 13, color: Color(0xFF34495E))),
                  Text(_items.where((item) => item.itemDetails.isNotEmpty).length.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF34495E))),
                ],
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndSend,
            icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send),
            label: Text(_isSaving ? 'Sending...' : 'Save & Send Quote'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _saveAsDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save as Draft'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3498DB),
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Color(0xFF3498DB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
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
            fontSize: isTotal ? 16 : 14,
            fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
            color: color ?? (isTotal ? const Color(0xFF1e3a8a) : const Color(0xFF7F8C8D)),
          ),
        ),
        Text(
          '${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.w500,
            color: color ?? (isTotal ? const Color(0xFF27AE60) : const Color(0xFF1e3a8a)),
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
                                          backgroundColor: const Color(0xFF3498DB),
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
                        foregroundColor: const Color(0xFF3498DB),
                        side: const BorderSide(color: Color(0xFF3498DB)),
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

class QuoteItemData {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  QuoteItemData({
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