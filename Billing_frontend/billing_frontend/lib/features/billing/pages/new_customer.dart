// ============================================================================
// NEW CUSTOMER PAGE — ZOHO BOOKS STYLE (5 TABS)
// ============================================================================
// File: lib/features/admin/Billing/pages/new_customer.dart
//
// Tabs: Other Details | Tax Info | Address | Contact Persons | Remarks
// Matches Zoho Books exactly — no transport-specific fields
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/billing_customers_service.dart';

// ── Brand palette (matches rest of billing system) ────────────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);
const Color _red        = Color(0xFFE74C3C);
const Color _bgGrey     = Color(0xFFF0F4F8);

// ── Zoho Books constants ──────────────────────────────────────────────────────
const List<String> kSalutations = ['Mr.', 'Mrs.', 'Ms.', 'Miss.', 'Dr.', ''];

const List<String> kPaymentTermsOptions = [
  'Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60', 'NET 90',
];

const List<String> kCurrencies = [
  'INR - Indian Rupee', 'USD - US Dollar', 'EUR - Euro',
  'GBP - British Pound', 'AED - UAE Dirham', 'SGD - Singapore Dollar',
  'AUD - Australian Dollar',
];

const List<String> kPortalLanguages = [
  'English', 'Hindi', 'Tamil', 'Telugu', 'Kannada', 'Malayalam',
  'Marathi', 'Gujarati', 'Bengali',
];

const List<String> kTaxPreferences = ['Taxable', 'Tax Exempt'];

// ============================================================================
class NewCustomerPage extends StatefulWidget {
  final String? customerId;
  const NewCustomerPage({Key? key, this.customerId}) : super(key: key);

  @override
  State<NewCustomerPage> createState() => _NewCustomerPageState();
}

class _NewCustomerPageState extends State<NewCustomerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isSaving  = false;
  String? _loadError;

  // ── TAB 1: Other Details ──────────────────────────────────────────────────
  String   _customerType        = 'Business';
  String   _salutation          = '';
  final _firstNameCtrl          = TextEditingController();
  final _lastNameCtrl           = TextEditingController();
  final _displayNameCtrl        = TextEditingController();
  final _companyNameCtrl        = TextEditingController();
  final _emailCtrl              = TextEditingController();
  final _workPhoneCtrl          = TextEditingController();
  final _mobileCtrl             = TextEditingController();
  final _websiteCtrl            = TextEditingController();
  final _departmentCtrl         = TextEditingController();
  final _designationCtrl        = TextEditingController();
  final _twitterCtrl            = TextEditingController();
  final _facebookCtrl           = TextEditingController();
  String   _defaultCurrency     = 'INR - Indian Rupee';
  String   _paymentTerms        = 'Due on Receipt';
  String   _portalLanguage      = 'English';
  final _openingBalanceCtrl     = TextEditingController();
  bool     _portalEnabled       = false;

  // ── TAB 2: Tax Info ───────────────────────────────────────────────────────
  final _gstinCtrl              = TextEditingController();
  String   _gstRegistrationType = '';
  String   _placeOfSupply       = '';
  final _panCtrl                = TextEditingController();
  String   _taxPreference       = 'Taxable';
  final _exemptionReasonCtrl    = TextEditingController();

  // ── TAB 3: Address ────────────────────────────────────────────────────────
  // Billing
  final _bAttentionCtrl   = TextEditingController();
  final _bStreet1Ctrl     = TextEditingController();
  final _bStreet2Ctrl     = TextEditingController();
  final _bCityCtrl        = TextEditingController();
  String _bState          = '';
  final _bZipCtrl         = TextEditingController();
  String _bCountry        = 'India';
  final _bPhoneCtrl       = TextEditingController();
  final _bFaxCtrl         = TextEditingController();
  // Shipping
  final _sAttentionCtrl   = TextEditingController();
  final _sStreet1Ctrl     = TextEditingController();
  final _sStreet2Ctrl     = TextEditingController();
  final _sCityCtrl        = TextEditingController();
  String _sState          = '';
  final _sZipCtrl         = TextEditingController();
  String _sCountry        = 'India';
  final _sPhoneCtrl       = TextEditingController();
  final _sFaxCtrl         = TextEditingController();

  // ── TAB 4: Contact Persons ────────────────────────────────────────────────
  List<_ContactPersonForm> _contactPersons = [];

  // ── TAB 5: Remarks ────────────────────────────────────────────────────────
  final _remarksCtrl = TextEditingController();

  // ── Display name suggestions ──────────────────────────────────────────────
  List<String> _displayNameSuggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    // Listen to name fields to rebuild display name suggestions
    _firstNameCtrl.addListener(_rebuildSuggestions);
    _lastNameCtrl.addListener(_rebuildSuggestions);
    _companyNameCtrl.addListener(_rebuildSuggestions);
    _displayNameCtrl.addListener(() => setState(() {}));

    if (widget.customerId != null) {
      _loadCustomer();
    } else {
      // Add one blank contact person by default
      _contactPersons.add(_ContactPersonForm());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in [
      _firstNameCtrl, _lastNameCtrl, _displayNameCtrl, _companyNameCtrl,
      _emailCtrl, _workPhoneCtrl, _mobileCtrl, _websiteCtrl,
      _departmentCtrl, _designationCtrl, _twitterCtrl, _facebookCtrl,
      _openingBalanceCtrl, _gstinCtrl, _panCtrl, _exemptionReasonCtrl,
      _bAttentionCtrl, _bStreet1Ctrl, _bStreet2Ctrl, _bCityCtrl, _bZipCtrl, _bPhoneCtrl, _bFaxCtrl,
      _sAttentionCtrl, _sStreet1Ctrl, _sStreet2Ctrl, _sCityCtrl, _sZipCtrl, _sPhoneCtrl, _sFaxCtrl,
      _remarksCtrl,
    ]) { c.dispose(); }
    for (final cp in _contactPersons) { cp.dispose(); }
    super.dispose();
  }

  // ── Display name suggestions (Zoho behaviour) ─────────────────────────────
  void _rebuildSuggestions() {
    final first   = _firstNameCtrl.text.trim();
    final last    = _lastNameCtrl.text.trim();
    final company = _companyNameCtrl.text.trim();
    final sal     = _salutation;

    final suggestions = <String>{};
    if (first.isNotEmpty || last.isNotEmpty) {
      final full = [first, last].where((s) => s.isNotEmpty).join(' ');
      suggestions.add(full);
      if (sal.isNotEmpty) suggestions.add('$sal $full'.trim());
      if (last.isNotEmpty && first.isNotEmpty) suggestions.add('$last, $first');
    }
    if (company.isNotEmpty) suggestions.add(company);

    setState(() {
      _displayNameSuggestions = suggestions.toList();
    });
  }

  // ── Load customer for edit mode ───────────────────────────────────────────
  Future<void> _loadCustomer() async {
    setState(() { _isLoading = true; _loadError = null; });
    try {
      final c = await BillingCustomersService.getCustomerById(widget.customerId!);
      setState(() {
        _customerType        = c.customerType;
        _salutation          = c.salutation;
        _firstNameCtrl.text  = c.firstName;
        _lastNameCtrl.text   = c.lastName;
        _displayNameCtrl.text= c.customerDisplayName;
        _companyNameCtrl.text= c.companyName;
        _emailCtrl.text      = c.primaryEmail;
        _workPhoneCtrl.text  = c.workPhone;
        _mobileCtrl.text     = c.mobile;
        _websiteCtrl.text    = c.website;
        _twitterCtrl.text    = c.twitter;
        _facebookCtrl.text   = c.facebook;
        _defaultCurrency     = kCurrencies.firstWhere((cu) => cu.startsWith(c.defaultCurrency), orElse: () => 'INR - Indian Rupee');
        _paymentTerms        = kPaymentTermsOptions.contains(c.paymentTerms) ? c.paymentTerms : 'Due on Receipt';
        _portalLanguage      = c.portalLanguage;
        _openingBalanceCtrl.text = c.openingBalance > 0 ? c.openingBalance.toStringAsFixed(2) : '';
        _portalEnabled       = c.portalEnabled;

        _gstinCtrl.text            = c.gstNumber;
        _gstRegistrationType       = c.gstRegistrationType;
        _placeOfSupply             = kIndianStates.contains(c.placeOfSupply) ? c.placeOfSupply : '';
        _panCtrl.text              = c.panNumber;
        _taxPreference             = c.taxPreference.isNotEmpty ? c.taxPreference : 'Taxable';
        _exemptionReasonCtrl.text  = c.exemptionReason;

        _bAttentionCtrl.text = c.billingAddress.attention;
        _bStreet1Ctrl.text   = c.billingAddress.street;
        _bCityCtrl.text      = c.billingAddress.city;
        _bState              = kIndianStates.contains(c.billingAddress.state) ? c.billingAddress.state : '';
        _bZipCtrl.text       = c.billingAddress.zip;
        _bCountry            = c.billingAddress.country.isNotEmpty ? c.billingAddress.country : 'India';
        _bPhoneCtrl.text     = c.billingAddress.phone;
        _bFaxCtrl.text       = c.billingAddress.fax;

        _sAttentionCtrl.text = c.shippingAddress.attention;
        _sStreet1Ctrl.text   = c.shippingAddress.street;
        _sCityCtrl.text      = c.shippingAddress.city;
        _sState              = kIndianStates.contains(c.shippingAddress.state) ? c.shippingAddress.state : '';
        _sZipCtrl.text       = c.shippingAddress.zip;
        _sCountry            = c.shippingAddress.country.isNotEmpty ? c.shippingAddress.country : 'India';
        _sPhoneCtrl.text     = c.shippingAddress.phone;
        _sFaxCtrl.text       = c.shippingAddress.fax;

        _contactPersons = c.contactPersons.map((cp) {
          final f = _ContactPersonForm();
          f.salutation   = cp.salutation;
          f.firstNameCtrl.text  = cp.firstName;
          f.lastNameCtrl.text   = cp.lastName;
          f.emailCtrl.text      = cp.email;
          f.workPhoneCtrl.text  = cp.workPhone;
          f.mobileCtrl.text     = cp.mobile;
          f.designationCtrl.text= cp.designation;
          f.departmentCtrl.text = cp.department;
          f.isPrimary    = cp.isPrimary;
          f.portalAccess = cp.portalAccess;
          return f;
        }).toList();
        if (_contactPersons.isEmpty) _contactPersons.add(_ContactPersonForm());

        _remarksCtrl.text = c.remarks;
        _isLoading = false;
      });
      _rebuildSuggestions();
    } catch (e) {
      setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

  // ── Copy billing address to shipping ──────────────────────────────────────
  void _copyBillingToShipping() {
    setState(() {
      _sAttentionCtrl.text = _bAttentionCtrl.text;
      _sStreet1Ctrl.text   = _bStreet1Ctrl.text;
      _sStreet2Ctrl.text   = _bStreet2Ctrl.text;
      _sCityCtrl.text      = _bCityCtrl.text;
      _sState              = _bState;
      _sZipCtrl.text       = _bZipCtrl.text;
      _sCountry            = _bCountry;
      _sPhoneCtrl.text     = _bPhoneCtrl.text;
      _sFaxCtrl.text       = _bFaxCtrl.text;
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    // Validate required fields
    if (_displayNameCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      _snack('Customer Display Name is required', error: true);
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      _snack('Primary Email is required', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final currencyCode = _defaultCurrency.split(' - ').first;
      final data = {
        'customerType':        _customerType,
        'salutation':          _salutation,
        'firstName':           _firstNameCtrl.text.trim(),
        'lastName':            _lastNameCtrl.text.trim(),
        'customerDisplayName': _displayNameCtrl.text.trim(),
        'companyName':         _companyNameCtrl.text.trim(),
        'primaryEmail':        _emailCtrl.text.trim(),
        'primaryPhone':        _workPhoneCtrl.text.trim().isNotEmpty ? _workPhoneCtrl.text.trim() : _mobileCtrl.text.trim(),
        'workPhone':           _workPhoneCtrl.text.trim(),
        'mobile':              _mobileCtrl.text.trim(),
        'website':             _websiteCtrl.text.trim(),
        'twitter':             _twitterCtrl.text.trim(),
        'facebook':            _facebookCtrl.text.trim(),
        'defaultCurrency':     currencyCode,
        'paymentTerms':        _paymentTerms,
        'portalLanguage':      _portalLanguage,
        'openingBalance':      double.tryParse(_openingBalanceCtrl.text) ?? 0,
        'portalEnabled':       _portalEnabled,
        // Tax
        'gstNumber':           _gstinCtrl.text.trim().toUpperCase(),
        'gstRegistrationType': _gstRegistrationType,
        'placeOfSupply':       _placeOfSupply,
        'panNumber':           _panCtrl.text.trim().toUpperCase(),
        'taxPreference':       _taxPreference,
        'exemptionReason':     _exemptionReasonCtrl.text.trim(),
        // Billing address
        'billingAddress': {
          'attention': _bAttentionCtrl.text.trim(),
          'street':    _bStreet1Ctrl.text.trim(),
          'street2':   _bStreet2Ctrl.text.trim(),
          'city':      _bCityCtrl.text.trim(),
          'state':     _bState,
          'zip':       _bZipCtrl.text.trim(),
          'country':   _bCountry,
          'phone':     _bPhoneCtrl.text.trim(),
          'fax':       _bFaxCtrl.text.trim(),
        },
        // Shipping address
        'shippingAddress': {
          'attention': _sAttentionCtrl.text.trim(),
          'street':    _sStreet1Ctrl.text.trim(),
          'street2':   _sStreet2Ctrl.text.trim(),
          'city':      _sCityCtrl.text.trim(),
          'state':     _sState,
          'zip':       _sZipCtrl.text.trim(),
          'country':   _sCountry,
          'phone':     _sPhoneCtrl.text.trim(),
          'fax':       _sFaxCtrl.text.trim(),
        },
        // Contact persons
        'contactPersons': _contactPersons.map((cp) => {
          'salutation':  cp.salutation,
          'firstName':   cp.firstNameCtrl.text.trim(),
          'lastName':    cp.lastNameCtrl.text.trim(),
          'email':       cp.emailCtrl.text.trim(),
          'workPhone':   cp.workPhoneCtrl.text.trim(),
          'mobile':      cp.mobileCtrl.text.trim(),
          'designation': cp.designationCtrl.text.trim(),
          'department':  cp.departmentCtrl.text.trim(),
          'isPrimary':   cp.isPrimary,
          'portalAccess':cp.portalAccess,
        }).toList(),
        // Remarks
        'remarks':      _remarksCtrl.text.trim(),
        // Kept for backward compat / list page
        'customerStatus':  'Active',
        'salesTerritory':  '',
        'tags':            [],
      };

      if (widget.customerId != null) {
        await BillingCustomersService.updateCustomer(widget.customerId!, data);
        _snack('Customer updated successfully');
      } else {
        await BillingCustomersService.createCustomer(data);
        _snack('Customer created successfully');
      }

      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Failed to save: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _red : _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.customerId != null;
    return Scaffold(
      backgroundColor: _bgGrey,
      appBar: _buildAppBar(isEdit),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navyLight))
          : _loadError != null
              ? _buildLoadError()
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isEdit) {
    return AppBar(
      backgroundColor: _navyDark,
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text(isEdit ? 'Edit Customer' : 'New Customer',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 14)),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(isEdit ? 'Update' : 'Save', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicatorColor: _navyAccent,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
        tabs: const [
          Tab(text: 'Other Details'),
          Tab(text: 'Tax Info'),
          Tab(text: 'Address'),
          Tab(text: 'Contact Persons'),
          Tab(text: 'Remarks'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Form(
      key: _formKey,
      child: TabBarView(
        controller: _tabController,
        children: [
          _buildOtherDetailsTab(),
          _buildTaxInfoTab(),
          _buildAddressTab(),
          _buildContactPersonsTab(),
          _buildRemarksTab(),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, size: 64, color: _red),
      const SizedBox(height: 16),
      const Text('Failed to load customer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(_loadError ?? '', style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _loadCustomer,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _navyLight, foregroundColor: Colors.white),
      ),
    ]));
  }

  // ==========================================================================
  // TAB 1 — OTHER DETAILS
  // ==========================================================================

  Widget _buildOtherDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(builder: (ctx, cs) {
        final wide = cs.maxWidth > 700;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Customer Type ──────────────────────────────────────────────────
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('Customer Type'),
            const SizedBox(height: 12),
            Row(children: ['Business', 'Individual'].map((t) {
              final sel = _customerType == t;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () => setState(() => _customerType = t),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? _navyLight.withOpacity(0.1) : Colors.grey[50],
                      border: Border.all(color: sel ? _navyLight : Colors.grey[300]!, width: sel ? 2 : 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(t == 'Business' ? Icons.business_outlined : Icons.person_outline,
                          size: 18, color: sel ? _navyLight : Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(t, style: TextStyle(
                          fontSize: 14, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          color: sel ? _navyLight : Colors.grey[800])),
                    ]),
                  ),
                ),
              );
            }).toList()),
          ])),
          const SizedBox(height: 16),

          // ── Name fields ────────────────────────────────────────────────────
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('Primary Contact'),
            const SizedBox(height: 16),

            // Salutation + First + Last  (responsive)
            wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 120, child: _salutationDropdown()),
                    const SizedBox(width: 12),
                    Expanded(child: _field('First Name', _firstNameCtrl, hint: 'First name')),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Last Name', _lastNameCtrl, hint: 'Last name')),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _salutationDropdown(),
                    const SizedBox(height: 12),
                    _field('First Name', _firstNameCtrl, hint: 'First name'),
                    const SizedBox(height: 12),
                    _field('Last Name', _lastNameCtrl, hint: 'Last name'),
                  ]),
            const SizedBox(height: 16),

            // Company Name (Business only)
            if (_customerType == 'Business') ...[
              _field('Company Name', _companyNameCtrl, hint: 'Enter company name'),
              const SizedBox(height: 16),
            ],

            // Display Name (required) — with suggestions dropdown
            _fieldLabel('Customer Display Name', required: true),
            const SizedBox(height: 6),
            _displayNameField(),
            const SizedBox(height: 16),

            // Email
            _field('Customer Email', _emailCtrl,
                hint: 'email@example.com', required: true,
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: 16),

            // Work Phone + Mobile
            wide
                ? Row(children: [
                    Expanded(child: _field('Work Phone', _workPhoneCtrl, hint: 'Work phone', keyboard: TextInputType.phone)),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Mobile', _mobileCtrl, hint: 'Mobile number', keyboard: TextInputType.phone)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field('Work Phone', _workPhoneCtrl, hint: 'Work phone', keyboard: TextInputType.phone),
                    const SizedBox(height: 12),
                    _field('Mobile', _mobileCtrl, hint: 'Mobile number', keyboard: TextInputType.phone),
                  ]),
            const SizedBox(height: 16),

            // Website
            _field('Website', _websiteCtrl, hint: 'https://example.com', keyboard: TextInputType.url),
            const SizedBox(height: 16),

            // Department + Designation
            wide
                ? Row(children: [
                    Expanded(child: _field('Designation', _designationCtrl, hint: 'e.g. Manager')),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Department', _departmentCtrl, hint: 'e.g. Finance')),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field('Designation', _designationCtrl, hint: 'e.g. Manager'),
                    const SizedBox(height: 12),
                    _field('Department', _departmentCtrl, hint: 'e.g. Finance'),
                  ]),
            const SizedBox(height: 16),

            // Twitter + Facebook
            wide
                ? Row(children: [
                    Expanded(child: _field('Twitter', _twitterCtrl, hint: '@username', prefix: Icons.alternate_email)),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Facebook', _facebookCtrl, hint: 'Facebook URL', prefix: Icons.facebook)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field('Twitter', _twitterCtrl, hint: '@username', prefix: Icons.alternate_email),
                    const SizedBox(height: 12),
                    _field('Facebook', _facebookCtrl, hint: 'Facebook URL', prefix: Icons.facebook),
                  ]),
          ])),
          const SizedBox(height: 16),

          // ── Financial / Portal ─────────────────────────────────────────────
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('Preferences'),
            const SizedBox(height: 16),

            // Currency + Payment Terms
            wide
                ? Row(children: [
                    Expanded(child: _labelDropdown('Default Currency', _defaultCurrency, kCurrencies, (v) => setState(() => _defaultCurrency = v!))),
                    const SizedBox(width: 12),
                    Expanded(child: _labelDropdown('Payment Terms', _paymentTerms, kPaymentTermsOptions, (v) => setState(() => _paymentTerms = v!))),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _labelDropdown('Default Currency', _defaultCurrency, kCurrencies, (v) => setState(() => _defaultCurrency = v!)),
                    const SizedBox(height: 12),
                    _labelDropdown('Payment Terms', _paymentTerms, kPaymentTermsOptions, (v) => setState(() => _paymentTerms = v!)),
                  ]),
            const SizedBox(height: 16),

            // Portal Language + Opening Balance
            wide
                ? Row(children: [
                    Expanded(child: _labelDropdown('Portal Language', _portalLanguage, kPortalLanguages, (v) => setState(() => _portalLanguage = v!))),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Opening Balance', _openingBalanceCtrl, hint: '0.00', keyboard: TextInputType.number, prefix: Icons.currency_rupee)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _labelDropdown('Portal Language', _portalLanguage, kPortalLanguages, (v) => setState(() => _portalLanguage = v!)),
                    const SizedBox(height: 12),
                    _field('Opening Balance', _openingBalanceCtrl, hint: '0.00', keyboard: TextInputType.number, prefix: Icons.currency_rupee),
                  ]),
            const SizedBox(height: 16),

            // Portal toggle
            _portalToggle(),
          ])),
        ]);
      }),
    );
  }

  Widget _displayNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: _displayNameCtrl,
        onTap: () => setState(() => _showSuggestions = _displayNameSuggestions.isNotEmpty),
        onChanged: (_) => setState(() => _showSuggestions = false),
        validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        decoration: _inputDeco(hint: 'Select or enter display name'),
      ),
      if (_showSuggestions && _displayNameSuggestions.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(
            children: _displayNameSuggestions.map((s) => InkWell(
              onTap: () => setState(() { _displayNameCtrl.text = s; _showSuggestions = false; }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Align(alignment: Alignment.centerLeft, child: Text(s, style: const TextStyle(fontSize: 13, color: _navyDark))),
              ),
            )).toList(),
          ),
        ),
    ]);
  }

  Widget _salutationDropdown() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel('Salutation'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _salutation,
        decoration: _inputDeco(),
        isExpanded: true,
        items: kSalutations.map((s) => DropdownMenuItem(value: s, child: Text(s.isEmpty ? '—' : s, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) { setState(() { _salutation = v ?? ''; _rebuildSuggestions(); }); },
      ),
    ]);
  }

  Widget _portalToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _portalEnabled ? _green.withOpacity(0.06) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _portalEnabled ? _green.withOpacity(0.3) : Colors.grey[200]!),
      ),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(
            color: (_portalEnabled ? _green : Colors.grey[400]!).withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(Icons.person_pin_outlined, size: 20, color: _portalEnabled ? _green : Colors.grey[500])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Customer Portal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _portalEnabled ? _green : _navyDark)),
          Text(_portalEnabled ? 'Portal access is enabled' : 'Portal access is not enabled',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ])),
        Switch(
          value: _portalEnabled,
          activeColor: _green,
          onChanged: (v) => setState(() => _portalEnabled = v),
        ),
      ]),
    );
  }

  // ==========================================================================
  // TAB 2 — TAX INFO
  // ==========================================================================

  Widget _buildTaxInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(builder: (ctx, cs) {
        final wide = cs.maxWidth > 700;
        return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader('Tax Information'),
          const SizedBox(height: 16),

          // GSTIN
          _field('GSTIN / UIN', _gstinCtrl,
              hint: '22AAAAA0000A1Z5',
              caps: TextCapitalization.characters,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(v)) {
                  return 'Invalid GSTIN format';
                }
                return null;
              }),
          const SizedBox(height: 16),

          // GST Registration Type
          _labelDropdown(
            'GST Registration Type',
            _gstRegistrationType.isEmpty ? null : _gstRegistrationType,
            kGstRegistrationTypes,
            (v) => setState(() => _gstRegistrationType = v ?? ''),
            nullable: true,
            nullLabel: 'Select GST Registration Type',
          ),
          const SizedBox(height: 16),

          // Place of Supply
          _labelDropdown(
            'Place of Supply',
            _placeOfSupply.isEmpty ? null : _placeOfSupply,
            kIndianStates,
            (v) => setState(() => _placeOfSupply = v ?? ''),
            nullable: true,
            nullLabel: 'Select Place of Supply',
          ),
          const SizedBox(height: 16),

          // PAN
          _field('PAN Number', _panCtrl,
              hint: 'ABCDE1234F',
              caps: TextCapitalization.characters,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v)) return 'Invalid PAN format';
                return null;
              }),
          const SizedBox(height: 16),

          // Tax Preference
          _labelDropdown(
            'Tax Preference',
            _taxPreference,
            kTaxPreferences,
            (v) => setState(() => _taxPreference = v ?? 'Taxable'),
          ),
          const SizedBox(height: 16),

          // Exemption Reason (if tax exempt)
          if (_taxPreference == 'Tax Exempt') ...[
            _field('Exemption Reason', _exemptionReasonCtrl,
                hint: 'Provide reason for tax exemption'),
            const SizedBox(height: 16),
          ],

          // Info box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF1D4ED8)),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'GST details are used to calculate taxes on invoices. Make sure the GSTIN and PAN are accurate.',
                style: TextStyle(fontSize: 12, color: Colors.blue[900]),
              )),
            ]),
          ),
        ]));
      }),
    );
  }

  // ==========================================================================
  // TAB 3 — ADDRESS
  // ==========================================================================

  Widget _buildAddressTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(builder: (ctx, cs) {
        final wide = cs.maxWidth > 700;
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildBillingAddressCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildShippingAddressCard()),
              ])
            : Column(children: [
                _buildBillingAddressCard(),
                const SizedBox(height: 16),
                _buildShippingAddressCard(),
              ]);
      }),
    );
  }

  Widget _buildBillingAddressCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.location_on_outlined, size: 18, color: _navyAccent),
        const SizedBox(width: 8),
        const Text('Billing Address', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
      const SizedBox(height: 16),
      _field('Attention', _bAttentionCtrl, hint: 'Person/Department name'),
      const SizedBox(height: 12),
      _field('Street 1', _bStreet1Ctrl, hint: 'Street address line 1'),
      const SizedBox(height: 12),
      _field('Street 2', _bStreet2Ctrl, hint: 'Street address line 2'),
      const SizedBox(height: 12),
      _field('City', _bCityCtrl, hint: 'City'),
      const SizedBox(height: 12),
      _labelDropdown('State', _bState.isEmpty ? null : _bState, kIndianStates,
          (v) => setState(() => _bState = v ?? ''), nullable: true, nullLabel: 'Select State'),
      const SizedBox(height: 12),
      _field('Zip Code', _bZipCtrl, hint: 'PIN / ZIP', keyboard: TextInputType.number),
      const SizedBox(height: 12),
      _countryDropdown('Country', _bCountry, (v) => setState(() => _bCountry = v!)),
      const SizedBox(height: 12),
      _field('Phone', _bPhoneCtrl, hint: 'Phone', keyboard: TextInputType.phone),
      const SizedBox(height: 12),
      _field('Fax', _bFaxCtrl, hint: 'Fax number'),
    ]));
  }

  Widget _buildShippingAddressCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.local_shipping_outlined, size: 18, color: _navyAccent),
        const SizedBox(width: 8),
        const Text('Shipping Address', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        const Spacer(),
        TextButton.icon(
          onPressed: _copyBillingToShipping,
          icon: const Icon(Icons.copy_outlined, size: 14),
          label: const Text('Copy Billing', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: _navyAccent, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
        ),
      ]),
      const SizedBox(height: 16),
      _field('Attention', _sAttentionCtrl, hint: 'Person/Department name'),
      const SizedBox(height: 12),
      _field('Street 1', _sStreet1Ctrl, hint: 'Street address line 1'),
      const SizedBox(height: 12),
      _field('Street 2', _sStreet2Ctrl, hint: 'Street address line 2'),
      const SizedBox(height: 12),
      _field('City', _sCityCtrl, hint: 'City'),
      const SizedBox(height: 12),
      _labelDropdown('State', _sState.isEmpty ? null : _sState, kIndianStates,
          (v) => setState(() => _sState = v ?? ''), nullable: true, nullLabel: 'Select State'),
      const SizedBox(height: 12),
      _field('Zip Code', _sZipCtrl, hint: 'PIN / ZIP', keyboard: TextInputType.number),
      const SizedBox(height: 12),
      _countryDropdown('Country', _sCountry, (v) => setState(() => _sCountry = v!)),
      const SizedBox(height: 12),
      _field('Phone', _sPhoneCtrl, hint: 'Phone', keyboard: TextInputType.phone),
      const SizedBox(height: 12),
      _field('Fax', _sFaxCtrl, hint: 'Fax number'),
    ]));
  }

  Widget _countryDropdown(String label, String value, ValueChanged<String?> onChanged) {
    final countries = ['India', 'USA', 'UK', 'UAE', 'Singapore', 'Australia', 'Germany', 'France', 'Japan', 'China'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel(label),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: countries.contains(value) ? value : 'India',
        decoration: _inputDeco(),
        isExpanded: true,
        items: countries.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: onChanged,
      ),
    ]);
  }

  // ==========================================================================
  // TAB 4 — CONTACT PERSONS
  // ==========================================================================

  Widget _buildContactPersonsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFF0369A1)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Add multiple contact persons for this customer. Each contact can optionally have portal access.',
              style: TextStyle(fontSize: 12, color: Colors.blue[900]),
            )),
          ]),
        ),

        // Contact person cards
        ..._contactPersons.asMap().entries.map((e) => _buildContactPersonCard(e.key, e.value)),

        // Add button
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _contactPersons.add(_ContactPersonForm())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Contact Person'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyAccent,
            side: const BorderSide(color: _navyAccent),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }

  Widget _buildContactPersonCard(int index, _ContactPersonForm cp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cp.isPrimary ? _navyAccent.withOpacity(0.4) : Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cp.isPrimary ? _navyLight.withOpacity(0.06) : Colors.grey[50],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cp.isPrimary ? _navyLight : Colors.grey[600],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(cp.isPrimary ? 'PRIMARY' : 'CONTACT ${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
            const Spacer(),
            if (!cp.isPrimary && _contactPersons.length > 1)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: _red),
                onPressed: () => setState(() => _contactPersons.removeAt(index)),
                tooltip: 'Remove',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ]),
        ),

        // Fields
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (ctx, cs) {
            final wide = cs.maxWidth > 500;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Salutation + First + Last
              wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 110, child: _cpSalutation(cp)),
                      const SizedBox(width: 10),
                      Expanded(child: _field('First Name', cp.firstNameCtrl, hint: 'First name')),
                      const SizedBox(width: 10),
                      Expanded(child: _field('Last Name', cp.lastNameCtrl, hint: 'Last name')),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _cpSalutation(cp),
                      const SizedBox(height: 10),
                      _field('First Name', cp.firstNameCtrl, hint: 'First name'),
                      const SizedBox(height: 10),
                      _field('Last Name', cp.lastNameCtrl, hint: 'Last name'),
                    ]),
              const SizedBox(height: 12),

              // Email
              _field('Email', cp.emailCtrl, hint: 'email@example.com', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 12),

              // Work Phone + Mobile
              wide
                  ? Row(children: [
                      Expanded(child: _field('Work Phone', cp.workPhoneCtrl, hint: 'Work phone', keyboard: TextInputType.phone)),
                      const SizedBox(width: 10),
                      Expanded(child: _field('Mobile', cp.mobileCtrl, hint: 'Mobile', keyboard: TextInputType.phone)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _field('Work Phone', cp.workPhoneCtrl, hint: 'Work phone', keyboard: TextInputType.phone),
                      const SizedBox(height: 10),
                      _field('Mobile', cp.mobileCtrl, hint: 'Mobile', keyboard: TextInputType.phone),
                    ]),
              const SizedBox(height: 12),

              // Designation + Department
              wide
                  ? Row(children: [
                      Expanded(child: _field('Designation', cp.designationCtrl, hint: 'Job title')),
                      const SizedBox(width: 10),
                      Expanded(child: _field('Department', cp.departmentCtrl, hint: 'Department')),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _field('Designation', cp.designationCtrl, hint: 'Job title'),
                      const SizedBox(height: 10),
                      _field('Department', cp.departmentCtrl, hint: 'Department'),
                    ]),
              const SizedBox(height: 14),

              // Portal access toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cp.portalAccess ? _green.withOpacity(0.06) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cp.portalAccess ? _green.withOpacity(0.25) : Colors.grey[200]!),
                ),
                child: Row(children: [
                  Icon(Icons.vpn_key_outlined, size: 16, color: cp.portalAccess ? _green : Colors.grey[500]),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Enable customer portal access',
                      style: TextStyle(fontSize: 13, color: cp.portalAccess ? _green : Colors.grey[700], fontWeight: FontWeight.w500))),
                  Switch(
                    value: cp.portalAccess,
                    activeColor: _green,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => cp.portalAccess = v),
                  ),
                ]),
              ),
            ]);
          }),
        ),
      ]),
    );
  }

  Widget _cpSalutation(_ContactPersonForm cp) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel('Salutation'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: cp.salutation,
        decoration: _inputDeco(),
        isExpanded: true,
        items: kSalutations.map((s) => DropdownMenuItem(value: s, child: Text(s.isEmpty ? '—' : s, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: (v) => setState(() => cp.salutation = v ?? ''),
      ),
    ]);
  }

  // ==========================================================================
  // TAB 5 — REMARKS
  // ==========================================================================

  Widget _buildRemarksTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('Remarks'),
        const SizedBox(height: 8),
        Text('Add internal notes or remarks about this customer. This is for internal use only.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 16),
        TextFormField(
          controller: _remarksCtrl,
          maxLines: 10,
          minLines: 6,
          decoration: _inputDeco(hint: 'Enter any internal notes or remarks about this customer...'),
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          ValueListenableBuilder(
            valueListenable: _remarksCtrl,
            builder: (_, v, __) => Text('${_remarksCtrl.text.length} characters',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ),
        ]),
      ])),
    );
  }

  // ==========================================================================
  // SHARED HELPERS
  // ==========================================================================

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark));
  }

  Widget _fieldLabel(String label, {bool required = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navyDark)),
      if (required) const Text(' *', style: TextStyle(color: _red, fontSize: 13)),
    ]);
  }

  InputDecoration _inputDeco({String? hint, IconData? prefix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      prefixIcon: prefix != null ? Icon(prefix, size: 18, color: Colors.grey[500]) : null,
      filled: true,
      fillColor: const Color(0xFFFAFBFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navyLight, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _red)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _red, width: 1.5)),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool required = false,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization caps = TextCapitalization.none,
    IconData? prefix,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel(label, required: required),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        textCapitalization: caps,
        decoration: _inputDeco(hint: hint, prefix: prefix),
        style: const TextStyle(fontSize: 13),
        validator: validator ?? (required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null),
      ),
    ]);
  }

  Widget _labelDropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    bool nullable = false,
    String? nullLabel,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel(label),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: value,
        decoration: _inputDeco(),
        isExpanded: true,
        hint: nullLabel != null ? Text(nullLabel, style: TextStyle(fontSize: 13, color: Colors.grey[400])) : null,
        items: [
          if (nullable) DropdownMenuItem<String>(value: null, child: Text(nullLabel ?? 'None', style: TextStyle(fontSize: 13, color: Colors.grey[400]))),
          ...items.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))),
        ],
        onChanged: onChanged,
      ),
    ]);
  }
}

// ============================================================================
// CONTACT PERSON FORM MODEL
// ============================================================================
class _ContactPersonForm {
  String salutation   = '';
  final firstNameCtrl  = TextEditingController();
  final lastNameCtrl   = TextEditingController();
  final emailCtrl      = TextEditingController();
  final workPhoneCtrl  = TextEditingController();
  final mobileCtrl     = TextEditingController();
  final designationCtrl= TextEditingController();
  final departmentCtrl = TextEditingController();
  bool isPrimary   = false;
  bool portalAccess= false;

  void dispose() {
    for (final c in [firstNameCtrl, lastNameCtrl, emailCtrl, workPhoneCtrl,
                     mobileCtrl, designationCtrl, departmentCtrl]) {
      c.dispose();
    }
  }
}