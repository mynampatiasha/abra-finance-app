// === CHUNK 1 START ===
// ============================================================================
// NEW INVOICE SCREEN - Complete Flutter UI
// ============================================================================
// File: lib/screens/billing/new_invoice.dart
// Matches new_vendor_credit.dart UI exactly
// All functionality preserved
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
import '../../../../app/config/api_config.dart';
import 'new_customer.dart';
import '../widgets/document_preview_buttons.dart';

// Navy blue gradient colors
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewInvoiceScreen extends StatefulWidget {
  final String? invoiceId;

  const NewInvoiceScreen({Key? key, this.invoiceId}) : super(key: key);

  @override
  State<NewInvoiceScreen> createState() => _NewInvoiceScreenState();
}

class _NewInvoiceScreenState extends State<NewInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Controllers
  final _orderNumberController = TextEditingController();
  final _subjectController = TextEditingController();
  final _customerNotesController = TextEditingController();
  final _termsConditionsController = TextEditingController();

  // Form Data
  String? _selectedCustomerId;
  String? _selectedCustomerName;
  String? _selectedCustomerEmail;
  String? _selectedCustomerPhone;
  DateTime _invoiceDate = DateTime.now();
  String _selectedTerms = 'Net 30';
  DateTime? _dueDate;
  String? _salesperson;

  // Payment account selection
  List<PaymentAccount> _paymentAccounts = [];
  PaymentAccount? _selectedPaymentAccount;
  bool _isLoadingAccounts = false;

  // QR Code Upload
  File? _qrCodeFile;
  Uint8List? _qrCodeBytes;
  String? _qrCodeFileName;
  final ImagePicker _imagePicker = ImagePicker();

  // Tax Settings
  double _tdsRate = 0;
  double _tcsRate = 0;
  double _gstRate = 18;
  bool _enableTDS = false;
  bool _enableTCS = false;
  bool _enableGST = true;

  // Items List
  List<InvoiceItem> _items = [];

  // Billable Expenses
List<BillableExpense> _billableExpenses = [];
bool _isLoadingBillableExpenses = false;

  // Calculations
  double _subTotal = 0;
  double _tdsAmount = 0;
  double _tcsAmount = 0;
  double _gstAmount = 0;
  double _totalAmount = 0;
  int _totalQuantity = 0;

  // Dropdown options
  final List<String> _termsOptions = [
    'Due on Receipt',
    'Net 15',
    'Net 30',
    'Net 45',
    'Net 60',
  ];

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _calculateDueDate();
    _addNewItem();
    _loadPaymentAccounts();
    if (widget.invoiceId != null) {
      _loadInvoiceData();
    }
  }

  @override
  void dispose() {
    _orderNumberController.dispose();
    _subjectController.dispose();
    _customerNotesController.dispose();
    _termsConditionsController.dispose();
    super.dispose();
  }

  // ============================================================
  // CALCULATION LOGIC
  // ============================================================

  void _calculateDueDate() {
    switch (_selectedTerms) {
      case 'Due on Receipt':
        _dueDate = _invoiceDate;
        break;
      case 'Net 15':
        _dueDate = _invoiceDate.add(const Duration(days: 15));
        break;
      case 'Net 30':
        _dueDate = _invoiceDate.add(const Duration(days: 30));
        break;
      case 'Net 45':
        _dueDate = _invoiceDate.add(const Duration(days: 45));
        break;
      case 'Net 60':
        _dueDate = _invoiceDate.add(const Duration(days: 60));
        break;
    }
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

  // ============================================================
  // PAYMENT ACCOUNTS
  // ============================================================

Future<void> _loadBillableExpenses(String customerName) async {
  setState(() {
    _billableExpenses = [];
    _isLoadingBillableExpenses = true;
  });
  try {
    final expenses = await InvoiceService.getBillableExpenses(customerName);
    setState(() {
      _billableExpenses = expenses;
      _isLoadingBillableExpenses = false;
    });
    print('✅ Loaded ${expenses.length} billable expenses for $customerName');
  } catch (e) {
    print('❌ Error loading billable expenses: $e');
    setState(() => _isLoadingBillableExpenses = false);
  }
}


  Future<void> _loadPaymentAccounts() async {
    setState(() => _isLoadingAccounts = true);
    try {
      final accounts = await InvoiceService.getPaymentAccounts();
      setState(() {
        _paymentAccounts = accounts;
        if (_paymentAccounts.isNotEmpty) {
          _selectedPaymentAccount = _paymentAccounts.firstWhere(
            (account) => account.accountType == 'BANK_ACCOUNT',
            orElse: () => _paymentAccounts.first,
          );
        }
      });
    } catch (e) {
      print('Error loading payment accounts: $e');
      _showError('Failed to load payment accounts: $e');
    } finally {
      setState(() => _isLoadingAccounts = false);
    }
  }

  // ============================================================
  // QR CODE
  // ============================================================

  Future<void> _pickQRCode() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() => _qrCodeFileName = pickedFile.name);
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() => _qrCodeBytes = bytes);
        } else {
          setState(() => _qrCodeFile = File(pickedFile.path));
        }
        _showSuccess('QR code uploaded successfully');
      }
    } catch (e) {
      _showError('Failed to upload QR code: $e');
    }
  }

  void _removeQRCode() {
    setState(() {
      _qrCodeFile = null;
      _qrCodeBytes = null;
      _qrCodeFileName = null;
    });
    _showSuccess('QR code removed');
  }

  Future<String> _uploadQRCode() async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/finance/invoices/upload/qr-code');
      final request = http.MultipartRequest('POST', uri);
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      if (kIsWeb && _qrCodeBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'qrCode',
          _qrCodeBytes!,
          filename: _qrCodeFileName ?? 'qr_code.png',
        ));
      } else if (_qrCodeFile != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'qrCode',
          _qrCodeFile!.path,
          filename: _qrCodeFileName,
        ));
      }
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final jsonData = json.decode(responseData);
        return jsonData['data']['url'];
      } else {
        throw Exception('Upload failed: ${response.statusCode}');
      }
    } catch (e) {
      print('QR code upload error: $e');
      rethrow;
    }
  }

  // ============================================================
  // ITEM MANAGEMENT
  // ============================================================

  void _addNewItem() {
    setState(() => _items.add(InvoiceItem()));
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateAmounts();
    });
  }

  // ============================================================
  // LOAD INVOICE (EDIT MODE)
  // ============================================================

  Future<void> _loadInvoiceData() async {
    setState(() => _isLoading = true);
    try {
      final invoice = await InvoiceService.getInvoice(widget.invoiceId!);
      setState(() {
        _selectedCustomerId = invoice.customerId;
        _selectedCustomerName = invoice.customerName;
        _selectedCustomerEmail = invoice.customerEmail;
        _selectedCustomerPhone = invoice.customerPhone;
        _orderNumberController.text = invoice.orderNumber ?? '';
        _invoiceDate = invoice.invoiceDate;
        _selectedTerms = invoice.terms;
        _dueDate = invoice.dueDate;
        _salesperson = invoice.salesperson;
        _subjectController.text = invoice.subject ?? '';
        _customerNotesController.text = invoice.customerNotes ?? '';
        _termsConditionsController.text = invoice.termsAndConditions ?? '';
        _tdsRate = invoice.tdsRate;
        _tcsRate = invoice.tcsRate;
        _gstRate = invoice.gstRate;
        _enableTDS = invoice.tdsRate > 0;
        _enableTCS = invoice.tcsRate > 0;
        _enableGST = invoice.gstRate > 0;
        _items = invoice.items.map((item) => InvoiceItem(
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
      _showError('Failed to load invoice: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  bool _validateItems() {
    final nonEmptyItems = _items
        .where((item) => item.itemDetails.trim().isNotEmpty)
        .toList();
    if (nonEmptyItems.isEmpty) {
      _showError('Please add at least one item with details');
      return false;
    }
    for (var item in nonEmptyItems) {
      if (item.quantity <= 0) {
        _showError('All items must have quantity greater than 0');
        return false;
      }
      if (item.rate <= 0) {
        _showError('All items must have rate greater than 0');
        return false;
      }
    }
    return true;
  }

  // ============================================================
  // SAVE ACTIONS
  // ============================================================

  Future<void> _saveAsDraft() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showError('Please select a customer');
      return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final invoiceData = await _buildInvoiceData('DRAFT');
      Invoice invoice;
      if (widget.invoiceId != null) {
        invoice = await InvoiceService.updateInvoice(widget.invoiceId!, invoiceData);
      } else {
        invoice = await InvoiceService.createInvoice(invoiceData);
      }
      _showSuccess('Invoice saved as draft');
      Navigator.pop(context, true);
    } catch (e) {
      _showError(_extractErrorMessage(e, 'Failed to save invoice'));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAndSend() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showError('Please select a customer');
      return;
    }
    if (_selectedCustomerEmail == null || _selectedCustomerEmail!.isEmpty) {
      _showError('Customer email is required to send invoice');
      return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final invoiceData = await _buildInvoiceData('SENT');
      Invoice invoice;
      if (widget.invoiceId != null) {
        invoice = await InvoiceService.updateInvoice(widget.invoiceId!, invoiceData);
      } else {
        invoice = await InvoiceService.createInvoice(invoiceData);
      }
      await InvoiceService.sendInvoice(invoice.id);
      _showSuccess('Invoice sent to $_selectedCustomerEmail');
      Navigator.pop(context, true);
    } catch (e) {
      _showError(_extractErrorMessage(e, 'Failed to send invoice'));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _markAsPaid() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      _showError('Please select a customer');
      return;
    }
    if (!_validateItems()) return;
    setState(() => _isSaving = true);
    try {
      final invoiceData = await _buildInvoiceData('PAID');
      Invoice invoice;
      if (widget.invoiceId != null) {
        invoice = await InvoiceService.updateInvoice(widget.invoiceId!, invoiceData);
      } else {
        invoice = await InvoiceService.createInvoice(invoiceData);
      }
      final paymentData = {
        'amount': _totalAmount,
        'paymentDate': DateTime.now().toIso8601String(),
        'paymentMethod': 'Cash',
        'notes': 'Payment received at time of invoice creation',
      };
      await InvoiceService.recordPayment(invoice.id, paymentData);
      _showSuccess('Invoice created and marked as paid');
      Navigator.pop(context, true);
    } catch (e) {
      _showError(_extractErrorMessage(e, 'Failed to create paid invoice'));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  String _extractErrorMessage(Object e, String fallback) {
    final str = e.toString();
    if (str.contains('validation failed')) {
      final match = RegExp(r'Path `(\w+)` is required').firstMatch(str);
      if (match != null) return 'Please fill in required field: ${match.group(1)}';
      return 'Please check all required fields';
    }
    if (str.contains('Invoice validation failed')) {
      return str.split('error":"')[1].split('"')[0];
    }
    return str;
  }

  Future<Map<String, dynamic>> _buildInvoiceData(String status) async {
    final validItems = _items
        .where((item) => item.itemDetails.trim().isNotEmpty)
        .toList();
    if (validItems.isEmpty) {
      throw Exception('Please add at least one item with details');
    }
    for (var item in validItems) {
      if (item.quantity <= 0) throw Exception('All items must have quantity greater than 0');
      if (item.rate <= 0) throw Exception('All items must have rate greater than 0');
    }

    Map<String, dynamic>? selectedAccountData;
    if (_selectedPaymentAccount != null) {
      selectedAccountData = _selectedPaymentAccount!.toJson();
    }

    String? qrCodeUrl;
    if (_qrCodeFile != null || _qrCodeBytes != null) {
      try {
        qrCodeUrl = await _uploadQRCode();
      } catch (e) {
        print('Failed to upload QR code: $e');
      }
    }

    return {
      'customerId': _selectedCustomerId,
      'customerName': _selectedCustomerName,
      'customerEmail': _selectedCustomerEmail,
      'customerPhone': _selectedCustomerPhone ?? '',
      'orderNumber': _orderNumberController.text.trim(),
      'invoiceDate': _invoiceDate.toIso8601String(),
      'terms': _selectedTerms,
      'dueDate': _dueDate?.toIso8601String(),
      'salesperson': _salesperson,
      'subject': _subjectController.text.trim(),
'items': validItems.map((item) {
  final json = item.toJson();
  // Attach expenseId if this item came from a billable expense
  final matchedExpense = _billableExpenses.firstWhere(
    (exp) => exp.isSelected &&
        item.itemDetails.startsWith('Expense: ${exp.expenseAccount}'),
    orElse: () => BillableExpense(
      id: '', date: '', expenseAccount: '',
      amount: 0, tax: 0, total: 0,
      billableAmount: 0, markupPercentage: 0, paidThrough: '',
    ),
  );
  if (matchedExpense.id.isNotEmpty) {
    json['expenseId'] = matchedExpense.id;
  }
  return json;
}).toList(),
      'customerNotes': _customerNotesController.text.trim(),
      'termsAndConditions': _termsConditionsController.text.trim(),
      'tdsRate': _enableTDS ? _tdsRate : 0,
      'tcsRate': _enableTCS ? _tcsRate : 0,
      'gstRate': _enableGST ? _gstRate : 0,
      'status': status,
      if (selectedAccountData != null) 'selectedPaymentAccount': selectedAccountData,
      if (qrCodeUrl != null) 'qrCodeUrl': qrCodeUrl,
    };
  }

  // ============================================================
  // SNACKBARS
  // ============================================================

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

// === CHUNK 1 END ===
// === CHUNK 2 START ===
// Continues inside _NewInvoiceScreenState
// build() → AppBar → _buildMainContent → all section widgets

  // ============================================================
  // BUILD
  // ============================================================

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

  // ============================================================
  // APP BAR  — navy gradient matching vendor credit
  // ============================================================

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
            widget.invoiceId != null ? 'Edit Invoice' : 'New Invoice',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            // View PDF button
            IconButton(
              tooltip: 'View PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70, size: 20),
              onPressed: () {
                if (widget.invoiceId == null || widget.invoiceId!.isEmpty) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                    content: Text('Save the invoice first to preview PDF'),
                    behavior: SnackBarBehavior.floating,
                  ));
                  return;
                }
                openDocumentPdf(
                  context: context,
                  docId: widget.invoiceId,
                  pdfEndpoint: '/api/finance/invoices',
                  docNumber: 'Invoice',
                );
              },
            ),
            // View Email button
            IconButton(
              tooltip: 'Preview Email',
              icon: const Icon(Icons.email_outlined, color: Colors.white70, size: 20),
              onPressed: () {
                if (widget.invoiceId == null || widget.invoiceId!.isEmpty) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                    content: Text('Save the invoice first to preview email'),
                    behavior: SnackBarBehavior.floating,
                  ));
                  return;
                }
                openEmailPreview(
                  context: context,
                  docId: widget.invoiceId,
                  emailEndpoint: '/api/finance/invoices',
                );
              },
            ),
            TextButton.icon(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAndSend,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save & Send'),
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

  // ============================================================
  // MAIN CONTENT
  // ============================================================

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCustomerSection(),
          const SizedBox(height: 20),
          _buildInvoiceDetailsSection(),
          const SizedBox(height: 20),
          _buildItemsSection(),
          const SizedBox(height: 20),
         _buildUnbilledExpensesSection(),
const SizedBox(height: 20),
// _buildPaymentAccountSection(),
// const SizedBox(height: 20),
_buildNotesSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS — matching vendor credit exactly
  // ============================================================

  Widget _card({required Widget child}) {
    return Container(
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
      Text(title,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
    ]);
  }

  // ============================================================
  // CUSTOMER SECTION
  // ============================================================

  Widget _buildCustomerSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Customer Information', Icons.person_outline),
          const SizedBox(height: 16),
          InkWell(
            onTap: _showCustomerSelector,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, color: _navyAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCustomerName ?? 'Select Customer *',
                      style: TextStyle(
                        fontSize: 15,
                        color: _selectedCustomerName != null
                            ? _navyDark
                            : Colors.grey[600],
                        fontWeight: _selectedCustomerName != null
                            ? FontWeight.w600
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
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(_selectedCustomerEmail!,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            ]),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // INVOICE DETAILS SECTION
  // ============================================================

  Widget _buildInvoiceDetailsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Invoice Details', Icons.receipt_long),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final orderField = TextFormField(
              controller: _orderNumberController,
              decoration: InputDecoration(
                labelText: 'Order Number',
                hintText: 'Optional',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.numbers),
              ),
            );
            final dateField = InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _invoiceDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  setState(() {
                    _invoiceDate = date;
                    _calculateDueDate();
                  });
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Invoice Date *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(DateFormat('dd MMM yyyy').format(_invoiceDate)),
              ),
            );
            if (isWide) {
              return Row(children: [
                Expanded(child: orderField),
                const SizedBox(width: 16),
                Expanded(child: dateField),
              ]);
            } else {
              return Column(children: [
                orderField,
                const SizedBox(height: 16),
                dateField,
              ]);
            }
          }),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            final termsField = DropdownButtonFormField<String>(
              value: _selectedTerms,
              decoration: InputDecoration(
                labelText: 'Payment Terms *',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.payment),
              ),
              items: _termsOptions
                  .map((term) => DropdownMenuItem(value: term, child: Text(term)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTerms = value!;
                  _calculateDueDate();
                });
              },
            );
            final dueDateField = InputDecorator(
              decoration: InputDecoration(
                labelText: 'Due Date',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.event),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              child: Text(
                _dueDate != null
                    ? DateFormat('dd MMM yyyy').format(_dueDate!)
                    : '-',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            );
            if (isWide) {
              return Row(children: [
                Expanded(child: termsField),
                const SizedBox(width: 16),
                Expanded(child: dueDateField),
              ]);
            } else {
              return Column(children: [
                termsField,
                const SizedBox(height: 16),
                dueDateField,
              ]);
            }
          }),
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

  // ============================================================
  // ITEMS SECTION
  // ============================================================

  Widget _buildItemsSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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
            ],
          ),
          const SizedBox(height: 16),
          // Gradient table header — matching vendor credit
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
                return const Text('ITEMS',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
              }
              return const Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('ITEM DETAILS',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: Text('QTY',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center),
                  ),
                  SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Text('RATE (₹)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right),
                  ),
                  SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Text('DISCOUNT',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right),
                  ),
                  SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: Text('AMOUNT (₹)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right),
                  ),
                  SizedBox(width: 50),
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
                  Text('No items added yet', style: TextStyle(color: Colors.grey[600])),
                ]),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (_, index) => _buildItemRow(index),
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
                    decoration: InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      item.quantity = double.tryParse(v) ?? 0;
                      _calculateAmounts();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: item.rate > 0 ? item.rate.toStringAsFixed(2) : '',
                    decoration: InputDecoration(
                      labelText: 'Rate (₹)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) {
                      item.rate = double.tryParse(v) ?? 0;
                      _calculateAmounts();
                    },
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
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right),
                  ),
                ),
              ]),
            ],
          ),
        );
      }

      // Desktop item row
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: item.itemDetails,
              decoration: InputDecoration(
                hintText: 'Enter item description',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              maxLines: 2,
              onChanged: (v) => item.itemDetails = v,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
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
              onChanged: (v) {
                item.quantity = double.tryParse(v) ?? 0;
                _calculateAmounts();
              },
            ),
          ),
          const SizedBox(width: 8),
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
              onChanged: (v) {
                item.rate = double.tryParse(v) ?? 0;
                _calculateAmounts();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: item.discount > 0 ? item.discount.toString() : '',
                  decoration: InputDecoration(
                    hintText: '0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  onChanged: (v) {
                    item.discount = double.tryParse(v) ?? 0;
                    _calculateAmounts();
                  },
                ),
              ),
              PopupMenuButton<String>(
                initialValue: item.discountType,
                icon: const Icon(Icons.arrow_drop_down, size: 16),
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
          const SizedBox(width: 8),
          Container(
            width: 120,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              item.amount.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _removeItem(index),
            tooltip: 'Remove item',
          ),
        ],
      );
    });
  }

  // ============================================================
  // NOTES SECTION
  // ============================================================

  Widget _buildNotesSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Additional Information', Icons.note_alt),
          const SizedBox(height: 16),
          TextFormField(
            controller: _customerNotesController,
            decoration: InputDecoration(
              labelText: 'Customer Notes',
              hintText: 'Notes visible on invoice',
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

// === CHUNK 2 END ===
// === CHUNK 3 START ===
// Continues inside _NewInvoiceScreenState
// Payment Account Section → Tax Settings → Summary → Customer Selector Dialog
// + InvoiceItem model at bottom

  // ============================================================
  // PAYMENT ACCOUNT SECTION
  // ============================================================

Widget _buildUnbilledExpensesSection() {
  if (_selectedCustomerName == null) return const SizedBox.shrink();
  return _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Unbilled Expenses', Icons.receipt_outlined),
        const SizedBox(height: 4),
        Text(
          'Billable expenses for $_selectedCustomerName not yet invoiced',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        if (_isLoadingBillableExpenses)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_billableExpenses.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(children: [
              Icon(Icons.check_circle_outline, color: Colors.grey[400]),
              const SizedBox(width: 12),
              Text(
                'No unbilled expenses for this customer',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ]),
          )
        else
          Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_navyDark, _navyMid],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  SizedBox(width: 40),
                  Expanded(
                    flex: 3,
                    child: Text('EXPENSE ACCOUNT',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Text('DATE',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Text('AMOUNT (₹)',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 11),
                        textAlign: TextAlign.right),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _billableExpenses.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final exp = _billableExpenses[index];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        exp.isSelected = !exp.isSelected;
                        if (exp.isSelected) {
                          // Add as invoice line item
                          final item = InvoiceItem(
                            itemDetails: exp.markupPercentage > 0
                                ? 'Expense: ${exp.expenseAccount}'
                                    '${exp.vendor != null ? ' (${exp.vendor})' : ''}'
                                    ' + ${exp.markupPercentage.toStringAsFixed(0)}% markup'
                                : 'Expense: ${exp.expenseAccount}'
                                    '${exp.vendor != null ? ' (${exp.vendor})' : ''}',
                            quantity: 1,
                            rate: exp.billableAmount,
                            discount: 0,
                            discountType: 'percentage',
                            amount: exp.billableAmount,
                          );
                          _items.add(item);
                          _calculateAmounts();
                        } else {
                          // Remove from items — match by description prefix
                          final descPrefix = 'Expense: ${exp.expenseAccount}';
                          _items.removeWhere(
                              (i) => i.itemDetails.startsWith(descPrefix));
                          _calculateAmounts();
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 10),
                      child: Row(children: [
                        SizedBox(
                          width: 40,
                          child: Checkbox(
                            value: exp.isSelected,
                            activeColor: _navyAccent,
                            onChanged: (val) {
                              setState(() {
                                exp.isSelected = val ?? false;
                                if (exp.isSelected) {
                                  final item = InvoiceItem(
                                    itemDetails: exp.markupPercentage > 0
                                        ? 'Expense: ${exp.expenseAccount}'
                                            '${exp.vendor != null ? ' (${exp.vendor})' : ''}'
                                            ' + ${exp.markupPercentage.toStringAsFixed(0)}% markup'
                                        : 'Expense: ${exp.expenseAccount}'
                                            '${exp.vendor != null ? ' (${exp.vendor})' : ''}',
                                    quantity: 1,
                                    rate: exp.billableAmount,
                                    discount: 0,
                                    discountType: 'percentage',
                                    amount: exp.billableAmount,
                                  );
                                  _items.add(item);
                                  _calculateAmounts();
                                } else {
                                  final descPrefix =
                                      'Expense: ${exp.expenseAccount}';
                                  _items.removeWhere(
                                      (i) => i.itemDetails.startsWith(descPrefix));
                                  _calculateAmounts();
                                }
                              });
                            },
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(exp.expenseAccount,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: _navyDark,
                                      fontSize: 13)),
                              if (exp.vendor != null)
                                Text(exp.vendor!,
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[600])),
                              if (exp.markupPercentage > 0)
                                Text(
                                    '+${exp.markupPercentage.toStringAsFixed(0)}% markup',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Text(exp.date,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[700])),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: Text(
                            '₹${exp.billableAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _navyDark,
                                fontSize: 13),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ]),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _navyAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _navyAccent.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 16, color: _navyAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Check expenses to add them as line items to this invoice',
                      style: TextStyle(fontSize: 12, color: _navyMid),
                    ),
                  ),
                ]),
              ),
            ],
          ),
      ],
    ),
  );
}


  // Widget _buildPaymentAccountSection() {
  //   return _card(
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         _sectionTitle('Payment Account', Icons.account_balance_wallet),
  //         const SizedBox(height: 4),
  //         Text(
  //           'Selected account details will appear on invoice and in email',
  //           style: TextStyle(fontSize: 12, color: Colors.grey[600]),
  //         ),
  //         const SizedBox(height: 16),
  //         if (_isLoadingAccounts)
  //           const Center(
  //             child: Padding(
  //               padding: EdgeInsets.all(20),
  //               child: CircularProgressIndicator(),
  //             ),
  //           )
  //         else if (_paymentAccounts.isEmpty)
  //           Container(
  //             padding: const EdgeInsets.all(16),
  //             decoration: BoxDecoration(
  //               color: Colors.orange[50],
  //               borderRadius: BorderRadius.circular(8),
  //               border: Border.all(color: Colors.orange[200]!),
  //             ),
  //             child: Row(
  //               children: [
  //                 Icon(Icons.warning_amber, color: Colors.orange[700]),
  //                 const SizedBox(width: 12),
  //                 Expanded(
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Text(
  //                         'No payment accounts available',
  //                         style: TextStyle(
  //                             fontWeight: FontWeight.bold, color: Colors.orange[900]),
  //                       ),
  //                       const SizedBox(height: 4),
  //                       Text(
  //                         'Add a bank account in Banking section',
  //                         style: TextStyle(fontSize: 13, color: Colors.orange[800]),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           )
  //         else
  //           DropdownButtonFormField<PaymentAccount>(
  //             value: _selectedPaymentAccount,
  //             decoration: InputDecoration(
  //               labelText: 'Select Payment Account *',
  //               border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  //               prefixIcon: Icon(
  //                 _selectedPaymentAccount != null
  //                     ? _getIconData(_selectedPaymentAccount!.getIconName())
  //                     : Icons.account_balance,
  //                 color: _navyAccent,
  //               ),
  //               filled: true,
  //               fillColor: Colors.grey[50],
  //             ),
  //             items: _paymentAccounts.map((account) {
  //               return DropdownMenuItem(
  //                 value: account,
  //                 child: Row(
  //                   children: [
  //                     Icon(_getIconData(account.getIconName()), size: 20, color: _navyAccent),
  //                     const SizedBox(width: 12),
  //                     Expanded(
  //                       child: Text(account.getDisplayText(), overflow: TextOverflow.ellipsis),
  //                     ),
  //                   ],
  //                 ),
  //               );
  //             }).toList(),
  //             onChanged: (account) => setState(() => _selectedPaymentAccount = account),
  //             validator: (value) {
  //               if (value == null) return 'Please select a payment account';
  //               return null;
  //             },
  //           ),
  //         if (_selectedPaymentAccount != null) ...[
  //           const SizedBox(height: 16),
  //           Container(
  //             padding: const EdgeInsets.all(16),
  //             decoration: BoxDecoration(
  //               color: Colors.blue[50],
  //               borderRadius: BorderRadius.circular(8),
  //               border: Border.all(color: Colors.blue[200]!),
  //             ),
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 Row(children: [
  //                   Icon(Icons.check_circle, color: Colors.blue[700], size: 20),
  //                   const SizedBox(width: 8),
  //                   Text('Selected Account Details',
  //                       style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
  //                 ]),
  //                 const SizedBox(height: 12),
  //                 _buildAccountDetailRow('Account Name', _selectedPaymentAccount!.accountName),
  //                 if (_selectedPaymentAccount!.accountType == 'BANK_ACCOUNT') ...[
  //                   _buildAccountDetailRow('Bank Name', _selectedPaymentAccount!.bankName),
  //                   _buildAccountDetailRow('Account Number',
  //                       _maskAccountNumber(_selectedPaymentAccount!.accountNumber)),
  //                   _buildAccountDetailRow('IFSC Code', _selectedPaymentAccount!.ifscCode),
  //                   _buildAccountDetailRow('Account Holder', _selectedPaymentAccount!.holderName),
  //                 ],
  //                 if (_selectedPaymentAccount!.upiId != null)
  //                   _buildAccountDetailRow('UPI ID', _selectedPaymentAccount!.upiId),
  //                 if (_selectedPaymentAccount!.accountType == 'FUEL_CARD') ...[
  //                   _buildAccountDetailRow('Provider', _selectedPaymentAccount!.providerName),
  //                   _buildAccountDetailRow('Card Number',
  //                       _maskAccountNumber(_selectedPaymentAccount!.cardNumber)),
  //                 ],
  //                 if (_selectedPaymentAccount!.accountType == 'FASTAG') ...[
  //                   _buildAccountDetailRow('FASTag Number', _selectedPaymentAccount!.fastagNumber),
  //                   _buildAccountDetailRow('Vehicle Number', _selectedPaymentAccount!.vehicleNumber),
  //                 ],
  //               ],
  //             ),
  //           ),

  //           // QR CODE UPLOAD
  //           const SizedBox(height: 20),
  //           const Divider(),
  //           const SizedBox(height: 16),
  //           _sectionTitle('Payment QR Code (Optional)', Icons.qr_code_2),
  //           const SizedBox(height: 4),
  //           Text(
  //             'Upload a QR code for easy payment (will be shown on invoice and email)',
  //             style: TextStyle(fontSize: 12, color: Colors.grey[600]),
  //           ),
  //           const SizedBox(height: 16),
  //           if (_qrCodeFile == null && _qrCodeBytes == null)
  //             OutlinedButton.icon(
  //               onPressed: _pickQRCode,
  //               icon: const Icon(Icons.upload_file),
  //               label: const Text('Upload QR Code'),
  //               style: OutlinedButton.styleFrom(
  //                 foregroundColor: _navyAccent,
  //                 side: const BorderSide(color: _navyAccent),
  //                 padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  //               ),
  //             )
  //           else
  //             Container(
  //               padding: const EdgeInsets.all(16),
  //               decoration: BoxDecoration(
  //                 color: Colors.green[50],
  //                 borderRadius: BorderRadius.circular(8),
  //                 border: Border.all(color: Colors.green[200]!),
  //               ),
  //               child: Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   Row(children: [
  //                     Icon(Icons.check_circle, color: Colors.green[700], size: 20),
  //                     const SizedBox(width: 8),
  //                     Text('QR Code Uploaded',
  //                         style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900])),
  //                     const Spacer(),
  //                     IconButton(
  //                       icon: const Icon(Icons.delete_outline, color: Colors.red),
  //                       onPressed: _removeQRCode,
  //                       tooltip: 'Remove QR code',
  //                     ),
  //                   ]),
  //                   const SizedBox(height: 12),
  //                   Center(
  //                     child: Container(
  //                       width: 200,
  //                       height: 200,
  //                       decoration: BoxDecoration(
  //                         color: Colors.white,
  //                         borderRadius: BorderRadius.circular(8),
  //                         border: Border.all(color: Colors.grey[300]!),
  //                       ),
  //                       child: ClipRRect(
  //                         borderRadius: BorderRadius.circular(8),
  //                         child: kIsWeb
  //                             ? Image.memory(_qrCodeBytes!, fit: BoxFit.contain)
  //                             : Image.file(_qrCodeFile!, fit: BoxFit.contain),
  //                       ),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 12),
  //                   Center(
  //                     child: Text(_qrCodeFileName ?? 'QR Code',
  //                         style: TextStyle(fontSize: 13, color: Colors.grey[700])),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //         ],
  //       ],
  //     ),
  //   );
  // }

  Widget _buildAccountDetailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: _navyDark, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _maskAccountNumber(String? accountNumber) {
    if (accountNumber == null || accountNumber.isEmpty) return '';
    if (accountNumber.length <= 4) return accountNumber;
    return '**** **** ${accountNumber.substring(accountNumber.length - 4)}';
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'account_balance':
        return Icons.account_balance;
      case 'smartphone':
        return Icons.smartphone;
      case 'local_gas_station':
        return Icons.local_gas_station;
      case 'toll':
        return Icons.toll;
      case 'account_balance_wallet':
        return Icons.account_balance_wallet;
      case 'payment':
        return Icons.payment;
      default:
        return Icons.account_balance;
    }
  }

  // ============================================================
  // TAX SETTINGS SECTION (Sidebar)
  // ============================================================

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

  // ============================================================
  // SUMMARY SECTION (Sidebar)
  // ============================================================

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Invoice Summary', Icons.summarize),
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
        if (_enableGST && _gstAmount > 0) ...[
          const SizedBox(height: 6),
          _summaryRow('CGST (${(_gstRate / 2).toStringAsFixed(1)}%)', _gstAmount / 2),
          const SizedBox(height: 6),
          _summaryRow('SGST (${(_gstRate / 2).toStringAsFixed(1)}%)', _gstAmount / 2),
        ],

        const Divider(thickness: 2),
        const SizedBox(height: 6),
        _summaryRow('Total Amount', _totalAmount, isBold: true, isTotal: true),

        const SizedBox(height: 16),

        // Gradient info box — matching vendor credit
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
                _items.where((item) => item.itemDetails.isNotEmpty).length.toString()),
          ]),
        ),

        const SizedBox(height: 20),

        // Save & Send
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndSend,
            icon: _isSaving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_isSaving ? 'Sending...' : 'Save & Send Invoice'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: _navyMid),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Mark as Paid
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _markAsPaid,
            icon: const Icon(Icons.payment),
            label: const Text('Mark as Paid'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
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

  // ============================================================
  // SUMMARY ROW HELPERS
  // ============================================================

  Widget _summaryRow(String label, double amount,
      {Color? color, bool isBold = false, bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
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
      Text(value,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: _navyDark)),
    ]);
  }

  // ============================================================
  // CUSTOMER SELECTOR DIALOG
  // ============================================================

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
                            return customer.customerName
                                    .toLowerCase()
                                    .contains(value.toLowerCase()) ||
                                customer.customerEmail
                                    .toLowerCase()
                                    .contains(value.toLowerCase()) ||
                                (customer.companyName
                                        ?.toLowerCase()
                                        .contains(value.toLowerCase()) ??
                                    false);
                          }).toList();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                                    const SizedBox(height: 12),
                                    Text('Error loading customers',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red[700])),
                                    const SizedBox(height: 8),
                                    Text(errorMessage!,
                                        style: TextStyle(color: Colors.grey[600]),
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () {
                                        setDialogState(() {
                                          isLoading = true;
                                          errorMessage = null;
                                        });
                                      },
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              )
                            : filteredCustomers.isEmpty
                                ? const Center(
                                    child: Text('No customers found',
                                        style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    itemCount: filteredCustomers.length,
                                    itemBuilder: (context, index) {
                                      final customer = filteredCustomers[index];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: _navyAccent,
                                          child: Text(
                                            customer.customerName[0].toUpperCase(),
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                        ),
                                        title: Text(customer.customerName),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(customer.customerEmail),
                                            if (customer.companyName != null)
                                              Text(customer.companyName!,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                      fontStyle: FontStyle.italic)),
                                            Text(customer.customerPhone,
                                                style: TextStyle(
                                                    fontSize: 12, color: Colors.grey[600])),
                                          ],
                                        ),
                                        onTap: () {
                                         setState(() {
  _selectedCustomerId = customer.id;
  _selectedCustomerName = customer.customerName;
  _selectedCustomerEmail = customer.customerEmail;
  _selectedCustomerPhone = customer.customerPhone;
});
Navigator.pop(context);
_loadBillableExpenses(customer.customerName);
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
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const NewCustomerPage()),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add New Customer'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navyAccent,
                        side: const BorderSide(color: _navyAccent),
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

// ============================================================================
// INVOICE ITEM MODEL
// ============================================================================

class InvoiceItem {
  String itemDetails;
  double quantity;
  double rate;
  double discount;
  String discountType;
  double amount;

  InvoiceItem({
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

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      itemDetails: json['itemDetails'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      rate: (json['rate'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      discountType: json['discountType'] ?? 'percentage',
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }
}

// === CHUNK 3 END ===