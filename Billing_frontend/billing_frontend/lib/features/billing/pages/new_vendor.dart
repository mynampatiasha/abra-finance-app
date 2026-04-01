// ============================================================================
// NEW VENDOR PAGE (CREATE/EDIT)
// ============================================================================
// File: lib/screens/billing/pages/new_vendor.dart
//
// UI matches new_payment_made.dart EXACTLY:
// ✅ Gradient AppBar (_navyDark → _navyMid → _navyLight)
// ✅ Gradient icon box section titles (_sectionTitle)
// ✅ Card: borderRadius 10, shadow offset (0,3), 0.05 opacity
// ✅ _navyAccent focused borders on all fields
// ✅ Optional section toggle with _navyAccent Switch
// ✅ Responsive field pairs via LayoutBuilder
//
// FUNCTIONALITY: fully preserved, zero changes to logic
// ✅ Create / Edit mode via vendorId
// ✅ All BillingVendorsService calls unchanged
// ✅ All validators unchanged
// ✅ Bank details + Address toggles unchanged
// ✅ All 20 controllers + dispose() unchanged
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/billing_vendors_service.dart';

// Navy gradient colors — exact match to new_payment_made.dart
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);

// ============================================================================
// SCREEN
// ============================================================================

class NewVendorPage extends StatefulWidget {
  final String? vendorId;

  const NewVendorPage({Key? key, this.vendorId}) : super(key: key);

  @override
  State<NewVendorPage> createState() => _NewVendorPageState();
}

class _NewVendorPageState extends State<NewVendorPage> {
  final _formKey = GlobalKey<FormState>();

  // Loading state — unchanged
  bool isLoading = false;
  bool isSaving  = false;

  bool get isEditMode => widget.vendorId != null;

  // Controllers — all unchanged
  final _vendorNameController            = TextEditingController();
  final _companyNameController           = TextEditingController();
  final _emailController                 = TextEditingController();
  final _phoneNumberController           = TextEditingController();
  final _alternatePhoneController        = TextEditingController();
  final _accountHolderNameController     = TextEditingController();
  final _bankNameController              = TextEditingController();
  final _accountNumberController         = TextEditingController();
  final _accountNumberConfirmController  = TextEditingController();
  final _ifscCodeController              = TextEditingController();
  final _addressLine1Controller          = TextEditingController();
  final _addressLine2Controller          = TextEditingController();
  final _cityController                  = TextEditingController();
  final _stateController                 = TextEditingController();
  final _postalCodeController            = TextEditingController();
  final _countryController               = TextEditingController(text: 'India');
  final _gstNumberController             = TextEditingController();
  final _panNumberController             = TextEditingController();
  final _serviceCategoryController       = TextEditingController();
  final _notesController                 = TextEditingController();

  // Dropdown values — unchanged
  String _vendorType = 'External Vendor';
  String _status     = 'Active';

  // Toggle states — unchanged
  bool _bankDetailsProvided = false;
  bool _addressProvided     = false;

  // Options — unchanged
  final List<String> _vendorTypes = [
    'Internal Employee',
    'External Vendor',
    'Contractor',
    'Freelancer',
  ];

  final List<String> _statusOptions = [
    'Active',
    'Inactive',
    'Blocked',
    'Pending Approval',
  ];

  // ============================================================================
  @override
  void initState() {
    super.initState();
    if (isEditMode) _loadVendorData();
  }

  @override
  void dispose() {
    _vendorNameController.dispose();
    _companyNameController.dispose();
    _emailController.dispose();
    _phoneNumberController.dispose();
    _alternatePhoneController.dispose();
    _accountHolderNameController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountNumberConfirmController.dispose();
    _ifscCodeController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _gstNumberController.dispose();
    _panNumberController.dispose();
    _serviceCategoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ============================================================================
  // LOAD VENDOR DATA (FOR EDIT MODE) — unchanged
  // ============================================================================

  Future<void> _loadVendorData() async {
    if (widget.vendorId == null) return;
    setState(() => isLoading = true);
    try {
      final result = await BillingVendorsService.getVendorById(widget.vendorId!);
      if (result['success'] == true) {
        final data = result['data'];
        setState(() {
          _vendorNameController.text           = data['vendorName'] ?? '';
          _companyNameController.text          = data['companyName'] ?? '';
          _emailController.text                = data['email'] ?? '';
          _phoneNumberController.text          = data['phoneNumber'] ?? '';
          _alternatePhoneController.text       = data['alternatePhone'] ?? '';
          _vendorType                          = data['vendorType'] ?? 'External Vendor';
          _status                              = data['status'] ?? 'Active';
          _bankDetailsProvided                 = data['bankDetailsProvided'] ?? false;
          _accountHolderNameController.text    = data['accountHolderName'] ?? '';
          _bankNameController.text             = data['bankName'] ?? '';
          _accountNumberController.text        = data['accountNumber'] ?? '';
          _accountNumberConfirmController.text = data['accountNumber'] ?? '';
          _ifscCodeController.text             = data['ifscCode'] ?? '';
          _addressProvided                     = data['addressProvided'] ?? false;
          _addressLine1Controller.text         = data['addressLine1'] ?? '';
          _addressLine2Controller.text         = data['addressLine2'] ?? '';
          _cityController.text                 = data['city'] ?? '';
          _stateController.text                = data['state'] ?? '';
          _postalCodeController.text           = data['postalCode'] ?? '';
          _countryController.text              = data['country'] ?? 'India';
          _gstNumberController.text            = data['gstNumber'] ?? '';
          _panNumberController.text            = data['panNumber'] ?? '';
          _serviceCategoryController.text      = data['serviceCategory'] ?? '';
          _notesController.text                = data['notes'] ?? '';
          isLoading                            = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Failed to load vendor data: ${e.toString()}');
    }
  }

  // ============================================================================
  // SAVE VENDOR — unchanged
  // ============================================================================

  Future<void> _saveVendor() async {
    if (!_formKey.currentState!.validate()) {
      _showError('Please fix the errors in the form');
      return;
    }
    setState(() => isSaving = true);
    try {
      Map<String, dynamic> result;
      if (isEditMode) {
        result = await BillingVendorsService.updateVendor(
          vendorId:               widget.vendorId!,
          vendorType:             _vendorType,
          vendorName:             _vendorNameController.text,
          companyName:            _companyNameController.text,
          email:                  _emailController.text,
          phoneNumber:            _phoneNumberController.text,
          alternatePhone:         _alternatePhoneController.text,
          status:                 _status,
          bankDetailsProvided:    _bankDetailsProvided,
          accountHolderName:      _accountHolderNameController.text,
          bankName:               _bankNameController.text,
          accountNumber:          _accountNumberController.text,
          accountNumberConfirm:   _accountNumberConfirmController.text,
          ifscCode:               _ifscCodeController.text,
          addressProvided:        _addressProvided,
          addressLine1:           _addressLine1Controller.text,
          addressLine2:           _addressLine2Controller.text,
          city:                   _cityController.text,
          state:                  _stateController.text,
          postalCode:             _postalCodeController.text,
          country:                _countryController.text,
          gstNumber:              _gstNumberController.text,
          panNumber:              _panNumberController.text,
          serviceCategory:        _serviceCategoryController.text,
          notes:                  _notesController.text,
        );
      } else {
        result = await BillingVendorsService.createVendor(
          vendorType:             _vendorType,
          vendorName:             _vendorNameController.text,
          companyName:            _companyNameController.text,
          email:                  _emailController.text,
          phoneNumber:            _phoneNumberController.text,
          alternatePhone:         _alternatePhoneController.text,
          status:                 _status,
          bankDetailsProvided:    _bankDetailsProvided,
          accountHolderName:      _accountHolderNameController.text,
          bankName:               _bankNameController.text,
          accountNumber:          _accountNumberController.text,
          accountNumberConfirm:   _accountNumberConfirmController.text,
          ifscCode:               _ifscCodeController.text,
          addressProvided:        _addressProvided,
          addressLine1:           _addressLine1Controller.text,
          addressLine2:           _addressLine2Controller.text,
          city:                   _cityController.text,
          state:                  _stateController.text,
          postalCode:             _postalCodeController.text,
          country:                _countryController.text,
          gstNumber:              _gstNumberController.text,
          panNumber:              _panNumberController.text,
          serviceCategory:        _serviceCategoryController.text,
          notes:                  _notesController.text,
        );
      }
      setState(() => isSaving = false);
      if (result['success'] == true) {
        _showSuccess(
            isEditMode ? 'Vendor updated successfully' : 'Vendor created successfully');
        Navigator.pop(context, true);
      } else {
        throw Exception(result['message'] ?? 'Failed to save vendor');
      }
    } on BillingVendorsException catch (e) {
      setState(() => isSaving = false);
      _showError(e.toUserMessage());
    } catch (e) {
      setState(() => isSaving = false);
      _showError('Failed to save vendor: ${e.toString()}');
    }
  }

  // ============================================================================
  // SNACKBAR HELPERS — unchanged
  // ============================================================================

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));

  void _showSuccess(String message) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic Information
                    _sectionTitle('Basic Information', Icons.person_outline),
                    const SizedBox(height: 16),
                    _buildBasicInfoSection(),

                    const SizedBox(height: 28),

                    // Bank Details (Optional toggle)
                    _buildOptionalSection(
                      title: 'Bank Details',
                      icon: Icons.account_balance,
                      isEnabled: _bankDetailsProvided,
                      onToggle: (v) => setState(() => _bankDetailsProvided = v),
                      child: _buildBankDetailsSection(),
                    ),

                    const SizedBox(height: 28),

                    // Address (Optional toggle)
                    _buildOptionalSection(
                      title: 'Address Information',
                      icon: Icons.location_on_outlined,
                      isEnabled: _addressProvided,
                      onToggle: (v) => setState(() => _addressProvided = v),
                      child: _buildAddressSection(),
                    ),

                    const SizedBox(height: 28),

                    // Additional Information
                    _sectionTitle('Additional Information', Icons.info_outline),
                    const SizedBox(height: 16),
                    _buildAdditionalInfoSection(),

                    const SizedBox(height: 28),

                    // Bottom action buttons
                    _buildActionButtons(),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
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
          isEditMode ? 'Edit Vendor' : 'New Vendor',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton.icon(
            onPressed: isSaving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            label: const Text('Cancel',
                style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: isSaving ? null : _saveVendor,
            icon: isSaving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(isSaving
                ? 'Saving...'
                : isEditMode ? 'Update Vendor' : 'Create Vendor'),
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
  // SECTION BUILDERS
  // ============================================================================

  /// Optional section with toggle switch — same header style as _sectionTitle
  Widget _buildOptionalSection({
    required String title,
    required IconData icon,
    required bool isEnabled,
    required Function(bool) onToggle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          // Gradient icon box — matches _sectionTitle
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_navyDark, _navyLight]),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, color: _navyDark)),
          const SizedBox(width: 16),
          Switch(
            value: isEnabled,
            onChanged: onToggle,
            activeColor: _navyAccent,
          ),
          const SizedBox(width: 6),
          Text(
            isEnabled ? 'Enabled' : 'Disabled',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isEnabled ? _navyAccent : Colors.grey,
            ),
          ),
        ]),
        if (isEnabled) ...[
          const SizedBox(height: 16),
          child,
        ],
      ],
    );
  }

  // ============================================================================
  // BASIC INFO SECTION
  // ============================================================================

  Widget _buildBasicInfoSection() => _card(child: Column(children: [
    // Vendor Type + Status
    LayoutBuilder(builder: (_, cs) {
      final isWide = cs.maxWidth > 600;
      final typeField = _buildDropdownField(
        label: 'Vendor Type *',
        value: _vendorType,
        items: _vendorTypes,
        onChanged: (v) => setState(() => _vendorType = v!),
      );
      final statusField = _buildDropdownField(
        label: 'Status *',
        value: _status,
        items: _statusOptions,
        onChanged: (v) => setState(() => _status = v!),
      );
      return isWide
          ? Row(children: [
              Expanded(child: typeField),
              const SizedBox(width: 16),
              Expanded(child: statusField),
            ])
          : Column(children: [
              typeField,
              const SizedBox(height: 16),
              statusField,
            ]);
    }),

    const SizedBox(height: 16),

    // Vendor Name + Company Name
    LayoutBuilder(builder: (_, cs) {
      final isWide = cs.maxWidth > 600;
      final nameField = _buildTextField(
        controller: _vendorNameController,
        label: 'Vendor Name *',
        hint: 'Enter vendor name',
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Vendor name is required';
          }
          return null;
        },
      );
      final companyField = _buildTextField(
        controller: _companyNameController,
        label: 'Company Name',
        hint: 'Enter company name (optional)',
      );
      return isWide
          ? Row(children: [
              Expanded(child: nameField),
              const SizedBox(width: 16),
              Expanded(child: companyField),
            ])
          : Column(children: [
              nameField,
              const SizedBox(height: 16),
              companyField,
            ]);
    }),

    const SizedBox(height: 16),

    // Email + Phone
    LayoutBuilder(builder: (_, cs) {
      final isWide = cs.maxWidth > 600;
      final emailField = _buildTextField(
        controller: _emailController,
        label: 'Email *',
        hint: 'Enter email address',
        keyboardType: TextInputType.emailAddress,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Email is required';
          }
          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
              .hasMatch(value)) {
            return 'Invalid email format';
          }
          return null;
        },
      );
      final phoneField = _buildTextField(
        controller: _phoneNumberController,
        label: 'Phone Number *',
        hint: 'Enter 10-digit phone number',
        keyboardType: TextInputType.phone,
        maxLength: 10,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Phone number is required';
          }
          if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value)) {
            return 'Invalid phone number';
          }
          return null;
        },
      );
      return isWide
          ? Row(children: [
              Expanded(child: emailField),
              const SizedBox(width: 16),
              Expanded(child: phoneField),
            ])
          : Column(children: [
              emailField,
              const SizedBox(height: 16),
              phoneField,
            ]);
    }),

    const SizedBox(height: 16),

    // Alternate Phone — full width
    _buildTextField(
      controller: _alternatePhoneController,
      label: 'Alternate Phone',
      hint: 'Enter alternate phone number (optional)',
      keyboardType: TextInputType.phone,
      maxLength: 10,
    ),
  ]));

  // ============================================================================
  // BANK DETAILS SECTION
  // ============================================================================

  Widget _buildBankDetailsSection() => _card(child: Column(children: [
    // Account Holder Name — full width
    _buildTextField(
      controller: _accountHolderNameController,
      label: 'Account Holder Name *',
      hint: 'Enter account holder name',
      validator: (value) {
        if (_bankDetailsProvided &&
            (value == null || value.trim().isEmpty)) {
          return 'Account holder name is required';
        }
        return null;
      },
    ),

    const SizedBox(height: 16),

    // Bank Name — full width
    _buildTextField(
      controller: _bankNameController,
      label: 'Bank Name *',
      hint: 'Enter bank name',
      validator: (value) {
        if (_bankDetailsProvided &&
            (value == null || value.trim().isEmpty)) {
          return 'Bank name is required';
        }
        return null;
      },
    ),

    const SizedBox(height: 16),

    // Account Number + Confirm Account Number
    LayoutBuilder(builder: (_, cs) {
      final isWide = cs.maxWidth > 600;
      final accField = _buildTextField(
        controller: _accountNumberController,
        label: 'Account Number *',
        hint: 'Enter account number',
        keyboardType: TextInputType.number,
        validator: (value) {
          if (_bankDetailsProvided &&
              (value == null || value.trim().isEmpty)) {
            return 'Account number is required';
          }
          return null;
        },
      );
      final accConfirmField = _buildTextField(
        controller: _accountNumberConfirmController,
        label: 'Re-enter Account Number *',
        hint: 'Re-enter account number',
        keyboardType: TextInputType.number,
        validator: (value) {
          if (_bankDetailsProvided &&
              (value == null || value.trim().isEmpty)) {
            return 'Please confirm account number';
          }
          if (_bankDetailsProvided &&
              value != _accountNumberController.text) {
            return 'Account numbers do not match';
          }
          return null;
        },
      );
      return isWide
          ? Row(children: [
              Expanded(child: accField),
              const SizedBox(width: 16),
              Expanded(child: accConfirmField),
            ])
          : Column(children: [
              accField,
              const SizedBox(height: 16),
              accConfirmField,
            ]);
    }),

    const SizedBox(height: 16),

    // IFSC Code — full width
    _buildTextField(
      controller: _ifscCodeController,
      label: 'IFSC Code *',
      hint: 'Enter IFSC code',
      textCapitalization: TextCapitalization.characters,
      maxLength: 11,
      validator: (value) {
        if (_bankDetailsProvided &&
            (value == null || value.trim().isEmpty)) {
          return 'IFSC code is required';
        }
        if (_bankDetailsProvided &&
            !RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(value!)) {
          return 'Invalid IFSC code format';
        }
        return null;
      },
    ),
  ]));

  // ============================================================================
  // ADDRESS SECTION
  // ============================================================================

  Widget _buildAddressSection() => _card(child: Column(children: [
    // Address Line 1 — full width
    _buildTextField(
      controller: _addressLine1Controller,
      label: 'Address Line 1',
      hint: 'Enter address line 1',
    ),

    const SizedBox(height: 16),

    // Address Line 2 — full width
    _buildTextField(
      controller: _addressLine2Controller,
      label: 'Address Line 2',
      hint: 'Enter address line 2',
    ),

    const SizedBox(height: 16),

    // City + State
    LayoutBuilder(builder: (_, cs) {
      final isWide = cs.maxWidth > 600;
      final cityField = _buildTextField(
        controller: _cityController,
        label: 'City',
        hint: 'Enter city',
      );
      final stateField = _buildTextField(
        controller: _stateController,
        label: 'State',
        hint: 'Enter state',
      );
      return isWide
          ? Row(children: [
              Expanded(child: cityField),
              const SizedBox(width: 16),
              Expanded(child: stateField),
            ])
          : Column(children: [
              cityField,
              const SizedBox(height: 16),
              stateField,
            ]);
    }),

    const SizedBox(height: 16),

    // Postal Code + Country
    LayoutBuilder(builder: (_, cs) {
      final isWide = cs.maxWidth > 600;
      final postalField = _buildTextField(
        controller: _postalCodeController,
        label: 'Postal Code',
        hint: 'Enter postal code',
        keyboardType: TextInputType.number,
        maxLength: 6,
      );
      final countryField = _buildTextField(
        controller: _countryController,
        label: 'Country',
        hint: 'Enter country',
      );
      return isWide
          ? Row(children: [
              Expanded(child: postalField),
              const SizedBox(width: 16),
              Expanded(child: countryField),
            ])
          : Column(children: [
              postalField,
              const SizedBox(height: 16),
              countryField,
            ]);
    }),
  ]));

  // ============================================================================
  // ADDITIONAL INFO SECTION
  // ============================================================================

  Widget _buildAdditionalInfoSection() => _card(child: Column(children: [
    // GST + PAN
    LayoutBuilder(builder: (_, cs) {
      final isWide = cs.maxWidth > 600;
      final gstField = _buildTextField(
        controller: _gstNumberController,
        label: 'GST Number',
        hint: 'Enter GST number (optional)',
        textCapitalization: TextCapitalization.characters,
        maxLength: 15,
      );
      final panField = _buildTextField(
        controller: _panNumberController,
        label: 'PAN Number',
        hint: 'Enter PAN number (optional)',
        textCapitalization: TextCapitalization.characters,
        maxLength: 10,
        validator: (value) {
          if (value != null && value.trim().isNotEmpty) {
            if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(value)) {
              return 'Invalid PAN format';
            }
          }
          return null;
        },
      );
      return isWide
          ? Row(children: [
              Expanded(child: gstField),
              const SizedBox(width: 16),
              Expanded(child: panField),
            ])
          : Column(children: [
              gstField,
              const SizedBox(height: 16),
              panField,
            ]);
    }),

    const SizedBox(height: 16),

    // Service Category — full width
    _buildTextField(
      controller: _serviceCategoryController,
      label: 'Service Category',
      hint: 'Enter service category (optional)',
    ),

    const SizedBox(height: 16),

    // Notes — full width, multiline
    _buildTextField(
      controller: _notesController,
      label: 'Notes',
      hint: 'Enter any additional notes (optional)',
      maxLines: 4,
    ),
  ]));

  // ============================================================================
  // BOTTOM ACTION BUTTONS — styled with navy, same layout as original
  // ============================================================================

  Widget _buildActionButtons() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      OutlinedButton.icon(
        onPressed: isSaving ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close),
        label: const Text('Cancel', style: TextStyle(fontSize: 15)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _navyMid,
          side: BorderSide(color: _navyMid),
          padding: const EdgeInsets.symmetric(
              horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const SizedBox(width: 16),
      ElevatedButton.icon(
        onPressed: isSaving ? null : _saveVendor,
        icon: isSaving
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white)))
            : const Icon(Icons.check_circle_outline),
        label: Text(
          isSaving
              ? 'Saving...'
              : isEditMode ? 'Update Vendor' : 'Create Vendor',
          style: const TextStyle(fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _navyAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
              horizontal: 28, vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ],
  );

  // ============================================================================
  // HELPERS — exact match to new_payment_made.dart
  // ============================================================================

  /// White card with shadow
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

  /// Section title with gradient icon box
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

  // ============================================================================
  // FORM FIELD BUILDERS — validators all unchanged, only border colors updated
  // ============================================================================

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _navyAccent, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            counterText: '',
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _navyAccent, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
          ),
          items: items.map((item) =>
              DropdownMenuItem<String>(
                  value: item, child: Text(item))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}