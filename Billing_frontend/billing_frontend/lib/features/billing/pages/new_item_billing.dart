// ============================================================================
// NEW ITEM BILLING — Vendor Credit UI Style Applied
// ============================================================================
// UI: Navy gradient AppBar, card sections, _sectionTitle helper
// Functionality: 100% identical to original — no logic changes whatsoever
// ============================================================================

import 'package:flutter/material.dart';
import '../../../../core/services/item_billing_service.dart';

// ── Navy palette (matches new_vendor_credit.dart exactly) ─────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewItemBilling extends StatefulWidget {
  final Map<String, dynamic>? itemToEdit;

  const NewItemBilling({super.key, this.itemToEdit});

  @override
  State<NewItemBilling> createState() => _NewItemBillingState();
}

class _NewItemBillingState extends State<NewItemBilling> {
  final _formKey = GlobalKey<FormState>();
  final ItemBillingService _service = ItemBillingService();

  // ── Form Controllers (unchanged) ─────────────────────────────────────────
  final TextEditingController _nameController               = TextEditingController();
  final TextEditingController _unitController               = TextEditingController();
  final TextEditingController _sellingPriceController       = TextEditingController();
  final TextEditingController _costPriceController          = TextEditingController();
  final TextEditingController _salesDescriptionController   = TextEditingController();
  final TextEditingController _purchaseDescriptionController = TextEditingController();

  // ── Form State (unchanged) ───────────────────────────────────────────────
  String  _itemType        = 'Goods';
  bool    _isSellable      = true;
  bool    _isPurchasable   = true;
  String  _salesAccount    = 'Sales';
  String  _purchaseAccount = 'Cost of Goods Sold';
  String? _selectedVendor;

  // ── Loading states (unchanged) ───────────────────────────────────────────
  bool _isLoading = false;
  bool _isSaving  = false;

  // ── Dropdown options (unchanged) ─────────────────────────────────────────
  final List<String> _units            = ['pcs','dz','kg','ltr','box','carton','unit','hour'];
  final List<String> _salesAccounts    = ['Sales','Service Revenue','Other Income'];
  final List<String> _purchaseAccounts = ['Cost of Goods Sold','Purchases','Direct Expenses'];
  List<Map<String, dynamic>> _vendors  = [];

  // ── initState / dispose (unchanged) ──────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _sellingPriceController.dispose();
    _costPriceController.dispose();
    _salesDescriptionController.dispose();
    _purchaseDescriptionController.dispose();
    super.dispose();
  }

  // ── All business logic unchanged ──────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      try {
        final vendors = await _service.fetchVendors();
        setState(() => _vendors = vendors);
      } catch (e) {
        print('⚠️ Error loading vendors: $e');
        setState(() => _vendors = []);
      }
      if (widget.itemToEdit != null) {
        _populateFormWithData(widget.itemToEdit!);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _populateFormWithData(Map<String, dynamic> data) {
    _nameController.text               = data['name'] ?? '';
    _unitController.text               = data['unit'] ?? '';
    _sellingPriceController.text       = data['sellingPrice']?.toString() ?? '';
    _costPriceController.text          = data['costPrice']?.toString() ?? '';
    _salesDescriptionController.text   = data['salesDescription'] ?? '';
    _purchaseDescriptionController.text = data['purchaseDescription'] ?? '';

    String? vendorId;
    if (data['preferredVendor'] != null) {
      if (data['preferredVendor'] is String) {
        vendorId = data['preferredVendor'] as String;
      } else if (data['preferredVendor'] is Map) {
        vendorId = (data['preferredVendor'] as Map)['_id']?.toString();
      }
    }

    setState(() {
      _itemType        = data['type'] ?? 'Goods';
      _isSellable      = data['isSellable'] ?? true;
      _isPurchasable   = data['isPurchasable'] ?? true;
      _salesAccount    = data['salesAccount'] ?? 'Sales';
      _purchaseAccount = data['purchaseAccount'] ?? 'Cost of Goods Sold';
      _selectedVendor  = vendorId;
    });
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final itemData = {
        'name':                _nameController.text.trim(),
        'type':                _itemType,
        'unit':                _unitController.text.trim(),
        'isSellable':          _isSellable,
        'isPurchasable':       _isPurchasable,
        'sellingPrice':        _isSellable    ? double.tryParse(_sellingPriceController.text) : null,
        'salesAccount':        _isSellable    ? _salesAccount    : null,
        'salesDescription':    _isSellable    ? _salesDescriptionController.text.trim() : null,
        'costPrice':           _isPurchasable ? double.tryParse(_costPriceController.text) : null,
        'purchaseAccount':     _isPurchasable ? _purchaseAccount : null,
        'purchaseDescription': _isPurchasable ? _purchaseDescriptionController.text.trim() : null,
        'preferredVendor':     _selectedVendor,
      };
      String result;
      if (widget.itemToEdit != null) {
        result = await _service.updateItem(widget.itemToEdit!['_id'], itemData);
      } else {
        result = await _service.createItem(itemData);
      }
      if (mounted) {
        _showSuccessSnackBar(result);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save item: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)));
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4)));
  }

  // ── Vendor selector & add vendor dialogs (unchanged logic) ────────────────

  Future<void> _showVendorSelector() async {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> filteredVendors = _vendors;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(children: [
              const Text('Select Vendor', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _showAddVendorDialog();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Vendor'),
                style: TextButton.styleFrom(foregroundColor: _navyAccent),
              ),
            ]),
            content: SizedBox(
              width: 400,
              height: 300,
              child: Column(children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search vendors...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      filteredVendors = value.isEmpty
                          ? _vendors
                          : _vendors.where((vendor) =>
                              (vendor['name'] ?? '').toLowerCase().contains(value.toLowerCase())).toList();
                    });
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filteredVendors.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.business, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(_vendors.isEmpty ? 'No vendors yet' : 'No vendors found',
                              style: TextStyle(color: Colors.grey[600])),
                          const SizedBox(height: 16),
                          if (_vendors.isEmpty)
                            ElevatedButton.icon(
                              onPressed: () async { Navigator.pop(context); await _showAddVendorDialog(); },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Your First Vendor'),
                              style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
                            ),
                        ]))
                      : ListView.builder(
                          itemCount: filteredVendors.length,
                          itemBuilder: (context, index) {
                            final vendor = filteredVendors[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _navyAccent,
                                child: Text((vendor['name'] ?? 'V')[0].toUpperCase(),
                                    style: const TextStyle(color: Colors.white)),
                              ),
                              title: Text(vendor['name'] ?? ''),
                              subtitle: vendor['email'] != null ? Text(vendor['email']) : null,
                              onTap: () {
                                setState(() => _selectedVendor = vendor['_id']);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () { setState(() => _selectedVendor = null); Navigator.pop(context); },
                child: const Text('Clear Selection'),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddVendorDialog() async {
    final formKey        = GlobalKey<FormState>();
    final nameController    = TextEditingController();
    final emailController   = TextEditingController();
    final phoneController   = TextEditingController();
    final addressController = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Add New Vendor', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 400,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(labelText: 'Vendor Name *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          prefixIcon: const Icon(Icons.business)),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'Vendor name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      decoration: InputDecoration(labelText: 'Email',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          prefixIcon: const Icon(Icons.email)),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneController,
                      decoration: InputDecoration(labelText: 'Phone',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          prefixIcon: const Icon(Icons.phone)),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: addressController,
                      decoration: InputDecoration(labelText: 'Address',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          prefixIcon: const Icon(Icons.location_on)),
                      maxLines: 2,
                    ),
                  ]),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isCreating ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isCreating ? null : () async {
                  if (!formKey.currentState!.validate()) return;
                  setDialogState(() => isCreating = true);
                  try {
                    final vendorData = {
                      'name': nameController.text.trim(),
                      if (emailController.text.trim().isNotEmpty) 'email': emailController.text.trim(),
                      if (phoneController.text.trim().isNotEmpty) 'phone': phoneController.text.trim(),
                      if (addressController.text.trim().isNotEmpty) 'address': addressController.text.trim(),
                    };
                    final vendor = await _service.createVendor(vendorData);
                    await _loadData();
                    setState(() => _selectedVendor = vendor['_id']);
                    Navigator.pop(context);
                    _showSuccessSnackBar('Vendor "${vendor['name']}" added successfully');
                  } catch (e) {
                    setDialogState(() => isCreating = false);
                    _showErrorSnackBar('Failed to create vendor: $e');
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
                child: isCreating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Add Vendor'),
              ),
            ],
          );
        },
      ),
    );
  }

  // =========================================================================
  //  BUILD — navy gradient AppBar + card sections
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildTypeCard(),
                  const SizedBox(height: 16),
                  _buildNameUnitCard(),
                  const SizedBox(height: 16),
                  _buildSalesPurchaseCards(),
                  const SizedBox(height: 24),
                  _buildBottomActions(),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
    );
  }

  // ── AppBar (navy gradient — matches vendor credit) ────────────────────────

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
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.itemToEdit != null ? 'Edit Item' : 'New Item',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            TextButton.icon(
              onPressed: _isSaving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveItem,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save Item'),
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

  // ── Card: Item Type ───────────────────────────────────────────────────────

  Widget _buildTypeCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Item Type', Icons.category_outlined),
        const SizedBox(height: 16),
        Row(children: [
          _buildRadioOption('Goods'),
          const SizedBox(width: 24),
          _buildRadioOption('Service'),
        ]),
      ]),
    );
  }

  Widget _buildRadioOption(String value) {
    return InkWell(
      onTap: () => setState(() => _itemType = value),
      borderRadius: BorderRadius.circular(8),
      child: Row(children: [
        Radio<String>(
          value: value,
          groupValue: _itemType,
          onChanged: (val) => setState(() => _itemType = val!),
          activeColor: _navyAccent,
        ),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ── Card: Name + Unit ─────────────────────────────────────────────────────

  Widget _buildNameUnitCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Basic Details', Icons.info_outline),
        const SizedBox(height: 16),
        // Name
        _fieldLabel('Name', required: true),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          validator: (value) => (value == null || value.trim().isEmpty) ? 'Name is required' : null,
          decoration: _inputDecoration(hintText: 'Enter item name'),
        ),
        const SizedBox(height: 16),
        // Unit
        _fieldLabel('Unit'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _unitController.text.isEmpty ? null : _unitController.text,
          decoration: _inputDecoration(hintText: 'Select or type to add'),
          items: _units.map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
          onChanged: (value) => setState(() => _unitController.text = value ?? ''),
        ),
      ]),
    );
  }

  // ── Cards: Sales + Purchase (responsive) ─────────────────────────────────

  Widget _buildSalesPurchaseCards() {
    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth > 700) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _buildSalesCard()),
          const SizedBox(width: 16),
          Expanded(child: _buildPurchaseCard()),
        ]);
      }
      return Column(children: [
        _buildSalesCard(),
        const SizedBox(height: 16),
        _buildPurchaseCard(),
      ]);
    });
  }

  Widget _buildSalesCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionTitle('Sales Information', Icons.trending_up),
          const Spacer(),
          Checkbox(
            value: _isSellable,
            onChanged: (value) => setState(() => _isSellable = value ?? true),
            activeColor: _navyAccent,
          ),
          const Text('Sellable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
        if (_isSellable) ...[
          const SizedBox(height: 16),
          _buildPriceField(label: 'Selling Price', controller: _sellingPriceController, isRequired: true),
          const SizedBox(height: 16),
          _buildAccountDropdown(
            label: 'Account',
            value: _salesAccount,
            items: _salesAccounts,
            isRequired: true,
            onChanged: (v) => setState(() => _salesAccount = v!),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Description'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _salesDescriptionController,
            maxLines: 3,
            decoration: _inputDecoration(hintText: 'Sales description'),
          ),
        ],
      ]),
    );
  }

  Widget _buildPurchaseCard() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _sectionTitle('Purchase Information', Icons.shopping_cart_outlined),
          const Spacer(),
          Checkbox(
            value: _isPurchasable,
            onChanged: (value) => setState(() => _isPurchasable = value ?? true),
            activeColor: _navyAccent,
          ),
          const Text('Purchasable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
        if (_isPurchasable) ...[
          const SizedBox(height: 16),
          _buildPriceField(label: 'Cost Price', controller: _costPriceController, isRequired: true),
          const SizedBox(height: 16),
          _buildAccountDropdown(
            label: 'Account',
            value: _purchaseAccount,
            items: _purchaseAccounts,
            isRequired: true,
            onChanged: (v) => setState(() => _purchaseAccount = v!),
          ),
          const SizedBox(height: 16),
          _fieldLabel('Description'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _purchaseDescriptionController,
            maxLines: 3,
            decoration: _inputDecoration(hintText: 'Purchase description'),
          ),
          const SizedBox(height: 16),
          _buildVendorDropdown(),
        ],
      ]),
    );
  }

  // ── Price field (unchanged logic) ─────────────────────────────────────────

  Widget _buildPriceField({
    required String label,
    required TextEditingController controller,
    bool isRequired = false,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel(label, required: isRequired),
      const SizedBox(height: 8),
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
          ),
          child: const Text('INR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        Expanded(child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: isRequired
              ? (value) {
                  if (value == null || value.trim().isEmpty) return 'Price is required';
                  if (double.tryParse(value) == null) return 'Enter valid number';
                  return null;
                }
              : null,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
              borderSide: BorderSide(color: _navyAccent, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
        )),
      ]),
    ]);
  }

  // ── Account dropdown (unchanged logic) ────────────────────────────────────

  Widget _buildAccountDropdown({
    required String label,
    required String value,
    required List<String> items,
    required bool isRequired,
    required void Function(String?) onChanged,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel(label, required: isRequired),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: value,
        decoration: _inputDecoration(),
        items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
        onChanged: onChanged,
      ),
    ]);
  }

  // ── Vendor dropdown (unchanged logic) ─────────────────────────────────────

  Widget _buildVendorDropdown() {
    final vendorName = _selectedVendor != null
        ? (_vendors.firstWhere(
            (v) => v['_id'] == _selectedVendor,
            orElse: () => {'name': 'Unknown'},
          )['name'] ?? 'Unknown')
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel('Preferred Vendor'),
      const SizedBox(height: 8),
      InkWell(
        onTap: _showVendorSelector,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.business_outlined, size: 18, color: vendorName != null ? _navyAccent : Colors.grey[500]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                vendorName ?? 'Select vendor (optional)',
                style: TextStyle(
                  color: vendorName != null ? _navyDark : Colors.grey[600],
                  fontWeight: vendorName != null ? FontWeight.w500 : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
          ]),
        ),
      ),
    ]);
  }

  // ── Bottom action buttons ─────────────────────────────────────────────────

  Widget _buildBottomActions() {
    return Row(children: [
      ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveItem,
        icon: _isSaving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save),
        label: Text(_isSaving ? 'Saving...' : 'Save Item',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _navyAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const SizedBox(width: 16),
      OutlinedButton.icon(
        onPressed: _isSaving ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close),
        label: const Text('Cancel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _navyMid,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          side: const BorderSide(color: _navyMid),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ]);
  }

  // ── UI helpers (matching vendor credit style) ─────────────────────────────

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
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
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
  ]);

  Widget _fieldLabel(String label, {bool required = false}) => Row(children: [
    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
    if (required) const Text(' *', style: TextStyle(color: Colors.red, fontSize: 14)),
  ]);

  InputDecoration _inputDecoration({String? hintText}) => InputDecoration(
    hintText: hintText,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: _navyAccent, width: 2)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );
}