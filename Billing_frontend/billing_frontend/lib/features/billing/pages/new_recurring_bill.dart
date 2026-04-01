// ============================================================================
// NEW RECURRING BILL SCREEN
// ============================================================================
// File: lib/screens/billing/new_recurring_bill.dart
//
// UI matches new_payment_made.dart EXACTLY:
// ✅ Gradient AppBar (_navyDark → _navyMid → _navyLight)
// ✅ Gradient icon box section titles (_sectionTitle) inside _buildCard
// ✅ Desktop (>900px): left main (flex 3) + right 320px white sidebar
// ✅ Mobile (<900px): stacked column + bottom nav bar
// ✅ Sidebar: Tax Settings + Summary + Save/Cancel buttons
// ✅ Gradient table header for items
// ✅ Card: borderRadius 10, shadow offset (0,3), 0.05 opacity
// ✅ Gradient info box in summary
// ✅ Vendor + Item selector dialogs with navy styling
//
// FUNCTIONALITY: fully preserved, zero changes to logic
// ✅ Save / Update recurring bill profile
// ✅ Vendor selector with search
// ✅ Item selector from master list
// ✅ Schedule (repeat every, start/end date, never expires)
// ✅ Profile details (name, payment terms, bill creation mode)
// ✅ Items (add/remove, qty, rate, discount, amount)
// ✅ GST / TDS / TCS toggles with live recalculation
// ✅ Notes section
// ✅ Edit mode via recurringBillId
// ✅ All RecurringBillService + BillingVendorsService calls unchanged
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/recurring_bill_service.dart';
import '../../../../core/services/billing_vendors_service.dart';

// Navy gradient colors — exact match to new_payment_made.dart
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);

// ============================================================================
// VENDOR DATA MODEL — unchanged
// ============================================================================

class VendorData {
  final String id;
  final String name;
  final String email;
  final String companyName;

  VendorData({
    required this.id,
    required this.name,
    required this.email,
    required this.companyName,
  });

  factory VendorData.fromJson(Map<String, dynamic> json) {
    return VendorData(
      id:          json['_id'] ?? '',
      name:        json['vendorName'] ?? '',
      email:       json['email'] ?? '',
      companyName: json['companyName'] ?? '',
    );
  }
}

// ============================================================================
// SCREEN
// ============================================================================

class NewRecurringBillScreen extends StatefulWidget {
  final String? recurringBillId;

  const NewRecurringBillScreen({Key? key, this.recurringBillId})
      : super(key: key);

  @override
  State<NewRecurringBillScreen> createState() =>
      _NewRecurringBillScreenState();
}

class _NewRecurringBillScreenState
    extends State<NewRecurringBillScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving  = false;

  // Form Controllers — unchanged
  final _profileNameController = TextEditingController();
  final _notesController       = TextEditingController();

  // Vendor — unchanged
  String? _selectedVendorId;
  String? _selectedVendorName;
  String? _selectedVendorEmail;

  // Schedule — unchanged
  int       _repeatEvery       = 1;
  String    _repeatUnit        = 'months';
  DateTime  _startDate         = DateTime.now();
  DateTime? _endDate;
  bool      _neverExpires      = true;
  String    _billCreationMode  = 'save_as_draft';
  String    _paymentTerms      = 'Net 30';

  // Tax — unchanged
  bool   _enableGST = true;
  bool   _enableTDS = false;
  bool   _enableTCS = false;
  double _gstRate   = 18;
  double _tdsRate   = 0;
  double _tcsRate   = 0;

  // Amounts — unchanged
  double _subTotal    = 0;
  double _gstAmount   = 0;
  double _tdsAmount   = 0;
  double _tcsAmount   = 0;
  double _totalAmount = 0;

  // Items — unchanged
  List<RecurringBillItem> _items       = [];
  List<BillItem>          _masterItems = [];
  bool                    _isLoadingItems = false;

  // Dropdown options — unchanged
  final List<String> _repeatUnits = ['days', 'weeks', 'months', 'years'];
  final List<String> _paymentTermsList = [
    'Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60',
  ];

  // ============================================================================
  @override
  void initState() {
    super.initState();
    _addNewItem();
    _loadMasterItems();
    if (widget.recurringBillId != null) _loadExistingBill();
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ============================================================================
  // LOAD MASTER ITEMS — unchanged
  // ============================================================================

  Future<void> _loadMasterItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final items = await RecurringBillService.getItems();
      setState(() { _masterItems = items; _isLoadingItems = false; });
    } catch (e) {
      setState(() => _isLoadingItems = false);
    }
  }

  // ============================================================================
  // LOAD EXISTING BILL — unchanged
  // ============================================================================

  Future<void> _loadExistingBill() async {
    setState(() => _isLoading = true);
    try {
      final bill = await RecurringBillService.getRecurringBillById(
          widget.recurringBillId!);
      setState(() {
        _profileNameController.text = bill.profileName;
        _selectedVendorId           = bill.vendorId;
        _selectedVendorName         = bill.vendorName;
        _selectedVendorEmail        = bill.vendorEmail;
        _repeatEvery                = bill.repeatEvery;
        _repeatUnit                 = bill.repeatUnit;
        _startDate                  = bill.startDate;
        _endDate                    = bill.endDate;
        _neverExpires               = bill.endDate == null;
        _billCreationMode           = bill.billCreationMode;
        _paymentTerms               = bill.paymentTerms ?? 'Net 30';
        _notesController.text       = bill.notes ?? '';
        _gstRate                    = bill.gstRate;
        _tdsRate                    = bill.tdsRate;
        _tcsRate                    = bill.tcsRate;
        _enableGST                  = bill.gstRate > 0;
        _enableTDS                  = bill.tdsRate > 0;
        _enableTCS                  = bill.tcsRate > 0;
        _items = bill.items.isNotEmpty ? bill.items : [RecurringBillItem()];
        _isLoading = false;
      });
      _calculateAmounts();
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load bill: $e');
    }
  }

  // ============================================================================
  // ITEM MANAGEMENT — unchanged
  // ============================================================================

  void _addNewItem() => setState(() => _items.add(RecurringBillItem()));

  void _removeItem(int index) {
    if (_items.length <= 1) {
      _showError('At least one item is required');
      return;
    }
    setState(() {
      _items.removeAt(index);
      _calculateAmounts();
    });
  }

  // ============================================================================
  // CALCULATE AMOUNTS — unchanged
  // ============================================================================

  void _calculateAmounts() {
    setState(() {
      _subTotal = 0;
      for (var item in _items) {
        if (item.quantity > 0 && item.rate > 0) {
          double amt = item.quantity * item.rate;
          if (item.discount > 0) {
            if (item.discountType == 'percentage') {
              amt -= amt * item.discount / 100;
            } else {
              amt -= item.discount;
            }
          }
          item.amount = amt < 0 ? 0 : amt;
          _subTotal  += item.amount;
        } else {
          item.amount = 0;
        }
      }
      _tdsAmount  = _enableTDS ? _subTotal * _tdsRate / 100 : 0;
      _tcsAmount  = _enableTCS ? _subTotal * _tcsRate / 100 : 0;
      double gstBase = _subTotal - _tdsAmount + _tcsAmount;
      _gstAmount  = _enableGST ? gstBase * _gstRate / 100 : 0;
      _totalAmount = _subTotal - _tdsAmount + _tcsAmount + _gstAmount;
    });
  }

  // ============================================================================
  // VALIDATE — unchanged
  // ============================================================================

  bool _validate() {
    if (_selectedVendorId == null) {
      _showError('Please select a vendor'); return false;
    }
    if (_profileNameController.text.trim().isEmpty) {
      _showError('Please enter a profile name'); return false;
    }
    final validItems = _items
        .where((i) => i.itemDetails.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      _showError('Please add at least one item'); return false;
    }
    for (final item in validItems) {
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

  // ============================================================================
  // BUILD REQUEST BODY — unchanged
  // ============================================================================

  Map<String, dynamic> _buildRequestBody() {
    final validItems = _items
        .where((i) => i.itemDetails.trim().isNotEmpty)
        .map((i) => i.toJson())
        .toList();
    return {
      'profileName':      _profileNameController.text.trim(),
      'vendorId':         _selectedVendorId,
      'vendorName':       _selectedVendorName,
      'vendorEmail':      _selectedVendorEmail ?? '',
      'repeatEvery':      _repeatEvery,
      'repeatUnit':       _repeatUnit,
      'startDate':        _startDate.toIso8601String(),
      'endDate':          _neverExpires ? null : _endDate?.toIso8601String(),
      'billCreationMode': _billCreationMode,
      'paymentTerms':     _paymentTerms,
      'items':            validItems,
      'tdsRate':          _enableTDS ? _tdsRate : 0,
      'tcsRate':          _enableTCS ? _tcsRate : 0,
      'gstRate':          _enableGST ? _gstRate : 0,
      'notes':            _notesController.text.trim(),
    };
  }

  // ============================================================================
  // SAVE — unchanged
  // ============================================================================

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validate()) return;
    setState(() => _isSaving = true);
    try {
      if (widget.recurringBillId != null) {
        await RecurringBillService.updateRecurringBill(
            widget.recurringBillId!, _buildRequestBody());
        _showSuccess('Recurring bill profile updated successfully');
      } else {
        await RecurringBillService.createRecurringBill(_buildRequestBody());
        _showSuccess('Recurring bill profile created successfully');
      }
      Navigator.pop(context, true);
    } catch (e) {
      _showError(
          e is RecurringBillException ? e.toUserMessage() : e.toString());
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ============================================================================
  // VENDOR SELECTOR — functionality unchanged, styling updated
  // ============================================================================

  Future<void> _showVendorSelector() async {
    final searchCtrl = TextEditingController();
    List<VendorData> vendors  = [];
    List<VendorData> filtered = [];
    bool    loading = true;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          if (loading && vendors.isEmpty) {
            BillingVendorsService.getAllVendors(limit: 1000)
                .then((result) {
              final list = (result['data']['vendors'] as List)
                  .map((v) => VendorData.fromJson(v))
                  .toList();
              setS(() { vendors = list; filtered = list; loading = false; });
            }).catchError((e) {
              setS(() { error = e.toString(); loading = false; });
            });
          }

          return AlertDialog(
            title: const Text('Select Vendor'),
            content: SizedBox(width: 500, height: 400, child: Column(children: [
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search vendors...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setS(() {
                  filtered = vendors.where((vd) =>
                      vd.name.toLowerCase().contains(v.toLowerCase()) ||
                      vd.companyName.toLowerCase().contains(v.toLowerCase()) ||
                      vd.email.toLowerCase().contains(v.toLowerCase())).toList();
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
                    : error != null
                        ? Center(child: Text('Error: $error'))
                        : filtered.isEmpty
                            ? const Center(child: Text('No vendors found'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final v = filtered[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _navyAccent,
                                      child: Text(
                                        v.name.isNotEmpty
                                            ? v.name[0].toUpperCase() : 'V',
                                        style: const TextStyle(
                                            color: Colors.white),
                                      ),
                                    ),
                                    title: Text(v.name),
                                    subtitle: Text(v.email),
                                    onTap: () {
                                      setState(() {
                                        _selectedVendorId    = v.id;
                                        _selectedVendorName  = v.name;
                                        _selectedVendorEmail = v.email;
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
  // ITEM SELECTOR — functionality unchanged, styling updated
  // ============================================================================

  Future<void> _showItemSelector(int index) async {
    final searchCtrl = TextEditingController();
    List<BillItem> filtered = List.from(_masterItems);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Select Item'),
          content: SizedBox(width: 500, height: 400, child: Column(children: [
            TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search items...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) => setS(() {
                filtered = _masterItems.where((item) =>
                    item.name.toLowerCase().contains(v.toLowerCase()) ||
                    item.description.toLowerCase()
                        .contains(v.toLowerCase())).toList();
              }),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoadingItems
                  ? const Center(child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
                  : filtered.isEmpty
                      ? const Center(child: Text('No items found'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final item = filtered[i];
                            return ListTile(
                              title: Text(item.name),
                              subtitle: Text(item.description.isNotEmpty
                                  ? item.description
                                  : '₹${item.rate.toStringAsFixed(2)}'),
                              trailing: Text(
                                '₹${item.rate.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _navyAccent,
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  _items[index].itemDetails = item.name;
                                  _items[index].rate        = item.rate;
                                  _items[index].itemId      = item.id;
                                  if (_items[index].quantity == 0) {
                                    _items[index].quantity = 1;
                                  }
                                  _calculateAmounts();
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
        ),
      ),
    );
  }

  // ============================================================================
  // SNACKBARS — unchanged
  // ============================================================================

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: _green,
          behavior: SnackBarBehavior.floating));

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
          : Form(
              key: _formKey,
              child: isNarrow
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        _buildVendorSection(),
                        const SizedBox(height: 16),
                        _buildProfileSection(),
                        const SizedBox(height: 16),
                        _buildScheduleSection(),
                        const SizedBox(height: 16),
                        _buildItemsSection(),
                        const SizedBox(height: 16),
                        _buildNotesSection(),
                        const SizedBox(height: 16),
                        _buildTaxSection(),
                        const SizedBox(height: 16),
                        _buildSummarySection(),
                        const SizedBox(height: 80),
                      ]),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(children: [
                              _buildVendorSection(),
                              const SizedBox(height: 20),
                              _buildProfileSection(),
                              const SizedBox(height: 20),
                              _buildScheduleSection(),
                              const SizedBox(height: 20),
                              _buildItemsSection(),
                              const SizedBox(height: 20),
                              _buildNotesSection(),
                              const SizedBox(height: 20),
                            ]),
                          ),
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
                    ),
            ),
      // Bottom action bar for narrow screens — unchanged logic, restyled
      bottomNavigationBar: isNarrow
          ? Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving
                        ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _navyMid,
                      side: BorderSide(color: _navyMid),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Save Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navyAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ]),
            )
          : null,
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
          widget.recurringBillId != null
              ? 'Edit Recurring Bill' : 'New Recurring Bill',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            label: const Text('Cancel',
                style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(_isSaving
                ? 'Saving...'
                : widget.recurringBillId != null
                    ? 'Update Profile' : 'Save Profile'),
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
            border: Border.all(color: _selectedVendorId == null
                ? Colors.red.shade300 : Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.business_outlined, color: _navyAccent),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _selectedVendorName ?? 'Select Vendor *',
              style: TextStyle(
                fontSize: 15,
                color: _selectedVendorName != null
                    ? _navyDark : Colors.grey[600],
                fontWeight: _selectedVendorName != null
                    ? FontWeight.w600 : FontWeight.normal,
              ),
            )),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ]),
        ),
      ),
      if (_selectedVendorEmail != null &&
          _selectedVendorEmail!.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(_selectedVendorEmail!,
              style: TextStyle(color: Colors.grey[700], fontSize: 13)),
        ]),
      ],
    ]),
  );

  // ============================================================================
  // PROFILE SECTION
  // ============================================================================

  Widget _buildProfileSection() => _card(
    title: 'Profile Details',
    icon: Icons.label_outline,
    child: Column(children: [
      TextFormField(
        controller: _profileNameController,
        decoration: InputDecoration(
          labelText: 'Profile Name *',
          hintText: 'e.g. Monthly Office Rent',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.label_outline),
        ),
        validator: (v) => (v == null || v.trim().isEmpty)
            ? 'Profile name is required' : null,
      ),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 500;
        final termsField = Expanded(child: DropdownButtonFormField<String>(
          value: _paymentTerms,
          decoration: InputDecoration(
            labelText: 'Payment Terms',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.payment_outlined),
          ),
          items: _paymentTermsList.map((t) =>
              DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _paymentTerms = v!),
        ));
        final modeField = Expanded(child: DropdownButtonFormField<String>(
          value: _billCreationMode,
          decoration: InputDecoration(
            labelText: 'Bill Creation Mode',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.auto_mode),
          ),
          items: const [
            DropdownMenuItem(
                value: 'save_as_draft', child: Text('📝 Save as Draft')),
            DropdownMenuItem(
                value: 'auto_save', child: Text('🚀 Auto Save')),
          ],
          onChanged: (v) => setState(() => _billCreationMode = v!),
        ));
        return isWide
            ? Row(children: [termsField, const SizedBox(width: 16), modeField])
            : Column(children: [
                termsField,
                const SizedBox(height: 16),
                modeField,
              ]);
      }),
    ]),
  );

  // ============================================================================
  // SCHEDULE SECTION
  // ============================================================================

  Widget _buildScheduleSection() => _card(
    title: 'Recurring Schedule',
    icon: Icons.repeat,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Repeat Every
      Row(children: [
        const Text('Repeat Every',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(width: 16),
        SizedBox(width: 80, child: TextFormField(
          initialValue: _repeatEvery.toString(),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) =>
              setState(() => _repeatEvery = int.tryParse(v) ?? 1),
          validator: (v) =>
              (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Required' : null,
        )),
        const SizedBox(width: 12),
        Expanded(child: DropdownButtonFormField<String>(
          value: _repeatUnit,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
          ),
          items: _repeatUnits.map((u) =>
              DropdownMenuItem(value: u, child: Text(u))).toList(),
          onChanged: (v) => setState(() => _repeatUnit = v!),
        )),
      ]),

      const SizedBox(height: 16),

      // Start Date + End Date / Never Expires
      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 500;
        final startField = Expanded(child: InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _startDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (d != null) setState(() => _startDate = d);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Start Date *',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.calendar_today),
            ),
            child: Text(DateFormat('dd MMM yyyy').format(_startDate)),
          ),
        ));
        final endField = Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Checkbox(
                value: _neverExpires,
                onChanged: (v) => setState(() {
                  _neverExpires = v!;
                  if (_neverExpires) _endDate = null;
                }),
                activeColor: _navyAccent,
              ),
              const Text('Never Expires',
                  style: TextStyle(fontSize: 14)),
            ]),
            if (!_neverExpires)
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _endDate ??
                        DateTime.now().add(
                            const Duration(days: 365)),
                    firstDate: _startDate,
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _endDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'End Date',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.event_busy),
                  ),
                  child: Text(
                    _endDate != null
                        ? DateFormat('dd MMM yyyy').format(_endDate!)
                        : 'Select end date',
                    style: TextStyle(
                      color: _endDate != null
                          ? _navyDark : Colors.grey[600],
                    ),
                  ),
                ),
              ),
          ],
        ));
        return isWide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [startField, const SizedBox(width: 16), endField])
            : Column(children: [startField, const SizedBox(height: 16), endField]);
      }),
    ]),
  );

  // ============================================================================
  // ITEMS SECTION
  // ============================================================================

  Widget _buildItemsSection() => _card(
    title: 'Items',
    icon: Icons.list_alt,
    trailing: ElevatedButton.icon(
      onPressed: _addNewItem,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add Item'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _navyAccent,
        foregroundColor: Colors.white,
      ),
    ),
    child: Column(children: [
      // Gradient table header — exact match to new_payment_made.dart
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
        child: LayoutBuilder(builder: (_, cs) {
          if (cs.maxWidth < 600) {
            return const _HeaderText('ITEM DETAILS / QTY / RATE / AMOUNT');
          }
          return const Row(children: [
            Expanded(flex: 3, child: _HeaderText('ITEM DETAILS')),
            SizedBox(width: 8),
            SizedBox(width: 70,
                child: _HeaderText('QTY', center: true)),
            SizedBox(width: 8),
            SizedBox(width: 100,
                child: _HeaderText('RATE (₹)', right: true)),
            SizedBox(width: 8),
            SizedBox(width: 100,
                child: _HeaderText('DISCOUNT', right: true)),
            SizedBox(width: 8),
            SizedBox(width: 110,
                child: _HeaderText('AMOUNT (₹)', right: true)),
            SizedBox(width: 40),
          ]);
        }),
      ),
      const SizedBox(height: 8),

      if (_items.isEmpty)
        Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Icon(Icons.inbox, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No items added',
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
    ]),
  );

  Widget _buildItemRow(int index) {
    final item = _items[index];
    return LayoutBuilder(builder: (_, cs) {
      // Mobile layout
      if (cs.maxWidth < 600) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Text('Item ${index + 1}',
                  style: TextStyle(fontWeight: FontWeight.w600,
                      fontSize: 12, color: _navyMid)),
              const Spacer(),
              if (_masterItems.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.search,
                      color: _navyAccent, size: 18),
                  onPressed: () => _showItemSelector(index),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 8),
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
                    borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
              onChanged: (v) => item.itemDetails = v,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: item.quantity > 0
                    ? item.quantity.toString() : '',
                decoration: InputDecoration(
                  labelText: 'Qty',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  item.quantity = double.tryParse(v) ?? 0;
                  _calculateAmounts();
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(
                initialValue: item.rate > 0
                    ? item.rate.toStringAsFixed(2) : '',
                decoration: InputDecoration(
                  labelText: 'Rate (₹)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                onChanged: (v) {
                  item.rate = double.tryParse(v) ?? 0;
                  _calculateAmounts();
                },
              )),
              const SizedBox(width: 8),
              Expanded(child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text('₹${item.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right),
              )),
            ]),
          ]),
        );
      }

      // Desktop layout — same column widths as header
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Item details + search icon
        Expanded(flex: 3, child: Row(children: [
          Expanded(child: TextFormField(
            initialValue: item.itemDetails,
            decoration: InputDecoration(
              hintText: 'Enter item description',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
            ),
            maxLines: 2,
            onChanged: (v) => item.itemDetails = v,
          )),
          if (_masterItems.isNotEmpty) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.search, color: _navyAccent),
              tooltip: 'Pick from items list',
              onPressed: () => _showItemSelector(index),
            ),
          ],
        ])),
        const SizedBox(width: 8),
        // Qty
        SizedBox(width: 70, child: TextFormField(
          initialValue: item.quantity > 0
              ? item.quantity.toString() : '',
          decoration: InputDecoration(
            hintText: '0',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 10),
          ),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            item.quantity = double.tryParse(v) ?? 0;
            _calculateAmounts();
          },
        )),
        const SizedBox(width: 8),
        // Rate
        SizedBox(width: 100, child: TextFormField(
          initialValue: item.rate > 0
              ? item.rate.toStringAsFixed(2) : '',
          decoration: InputDecoration(
            hintText: '0.00',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true),
          textAlign: TextAlign.right,
          onChanged: (v) {
            item.rate = double.tryParse(v) ?? 0;
            _calculateAmounts();
          },
        )),
        const SizedBox(width: 8),
        // Discount
        SizedBox(width: 100, child: Row(children: [
          Expanded(child: TextFormField(
            initialValue: item.discount > 0
                ? item.discount.toString() : '',
            decoration: InputDecoration(
              hintText: '0',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 10),
            ),
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true),
            textAlign: TextAlign.right,
            onChanged: (v) {
              item.discount = double.tryParse(v) ?? 0;
              _calculateAmounts();
            },
          )),
          PopupMenuButton<String>(
            initialValue: item.discountType,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            onSelected: (v) => setState(() {
              item.discountType = v;
              _calculateAmounts();
            }),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'percentage', child: Text('%')),
              const PopupMenuItem(value: 'amount',     child: Text('₹')),
            ],
          ),
        ])),
        const SizedBox(width: 8),
        // Amount
        Container(
          width: 110,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text('₹${item.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.right),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _removeItem(index),
        ),
      ]);
    });
  }

  // ============================================================================
  // NOTES SECTION
  // ============================================================================

  Widget _buildNotesSection() => _card(
    title: 'Additional Notes',
    icon: Icons.note_alt,
    child: TextFormField(
      controller: _notesController,
      decoration: InputDecoration(
        hintText: 'Enter any notes for this recurring bill...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        alignLabelWithHint: true,
      ),
      maxLines: 3,
    ),
  );

  // ============================================================================
  // TAX SECTION (sidebar) — exact match to new_payment_made.dart
  // ============================================================================

  Widget _buildTaxSection() => Column(
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
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() {
            _gstRate = double.tryParse(v) ?? 18;
            _calculateAmounts();
          }),
        ),
      ],
      const SizedBox(height: 8),

      // TDS
      SwitchListTile(
        title: const Text('Enable TDS'),
        subtitle: const Text('Tax Deducted at Source',
            style: TextStyle(fontSize: 12)),
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
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => setState(() {
            _tdsRate = double.tryParse(v) ?? 0;
            _calculateAmounts();
          }),
        ),
      ],
      const SizedBox(height: 8),

      // TCS
      SwitchListTile(
        title: const Text('Enable TCS'),
        subtitle: const Text('Tax Collected at Source',
            style: TextStyle(fontSize: 12)),
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
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      _sectionTitle('Bill Summary', Icons.summarize),
      const SizedBox(height: 16),

      _summaryRow('Sub Total', _subTotal),
      if (_enableTDS && _tdsAmount > 0) ...[
        const SizedBox(height: 6),
        _summaryRow('TDS (${_tdsRate.toStringAsFixed(1)}%)',
            -_tdsAmount, color: Colors.red[700]),
      ],
      if (_enableTCS && _tcsAmount > 0) ...[
        const SizedBox(height: 6),
        _summaryRow('TCS (${_tcsRate.toStringAsFixed(1)}%)', _tcsAmount),
      ],
      if (_enableGST && _gstAmount > 0) ...[
        const SizedBox(height: 6),
        _summaryRow('CGST (${(_gstRate / 2).toStringAsFixed(1)}%)',
            _gstAmount / 2),
        const SizedBox(height: 6),
        _summaryRow('SGST (${(_gstRate / 2).toStringAsFixed(1)}%)',
            _gstAmount / 2),
      ],
      const Divider(thickness: 2, height: 24),
      _summaryRow('Total Amount', _totalAmount,
          bold: true, isTotal: true),

      const SizedBox(height: 16),

      // Gradient info box — exact match to new_payment_made.dart
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark.withOpacity(0.1),
                _navyLight.withOpacity(0.1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _navyAccent.withOpacity(0.3)),
        ),
        child: Column(children: [
          _infoRow('Repeat:', 'Every $_repeatEvery $_repeatUnit'),
          const SizedBox(height: 4),
          _infoRow('Start Date:',
              DateFormat('dd MMM yyyy').format(_startDate)),
          const SizedBox(height: 4),
          _infoRow('Expires:',
              _neverExpires ? 'Never' :
              (_endDate != null
                  ? DateFormat('dd MMM yyyy').format(_endDate!)
                  : 'Not set')),
          const SizedBox(height: 4),
          _infoRow('Mode:',
              _billCreationMode == 'save_as_draft'
                  ? 'Save as Draft' : 'Auto Save'),
        ]),
      ),

      const SizedBox(height: 20),

      // Save Profile button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(_isSaving
              ? 'Saving...'
              : widget.recurringBillId != null
                  ? 'Update Profile' : 'Save Profile'),
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

      // Cancel button
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid,
            side: BorderSide(color: _navyMid),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ],
  );

  Widget _summaryRow(String label, double amount,
      {Color? color, bool bold = false, bool isTotal = false}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(
          fontSize: isTotal ? 15 : 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isTotal ? _navyDark : Colors.grey[700]),
        )),
        Text(
          '${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isTotal ? 17 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: color ?? (isTotal ? _navyAccent : _navyDark),
          ),
        ),
      ]);

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
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              _sectionTitle(title, icon),
              if (trailing != null) trailing,
            ]),
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
    Text(title, style: const TextStyle(
        fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  /// Info row inside gradient box
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

// ============================================================================
// HEADER TEXT WIDGET — unchanged
// ============================================================================

class _HeaderText extends StatelessWidget {
  final String text;
  final bool center;
  final bool right;

  const _HeaderText(this.text, {this.center = false, this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 0.3),
      textAlign: right
          ? TextAlign.right
          : center ? TextAlign.center : TextAlign.left,
    );
  }
}