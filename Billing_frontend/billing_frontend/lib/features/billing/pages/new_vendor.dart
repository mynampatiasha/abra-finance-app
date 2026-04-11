// ============================================================================
// NEW VENDOR PAGE — ZOHO BOOKS STYLE (5 TABS)
// ============================================================================
// UI matches new_customer.dart exactly.
// All service calls / data models are unchanged.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/billing_vendors_service.dart';

// ── Brand palette ─────────────────────────────────────────────────────────────
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);
const Color _red        = Color(0xFFE74C3C);
const Color _bgGrey     = Color(0xFFF0F4F8);

// ── Constants ─────────────────────────────────────────────────────────────────
const List<String> _kSalutations = ['Mr.', 'Mrs.', 'Ms.', 'Dr.', 'Prof.', ''];

const List<String> _kVendorTypes = [
  'External Vendor', 'Internal Employee', 'Contractor', 'Freelancer',
];

const List<String> _kStatuses = [
  'Active', 'Inactive', 'Blocked', 'Pending Approval',
];

const List<String> _kPaymentTerms = [
  'Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60', 'Net 90', 'Custom',
];

const List<String> _kCurrencies = [
  'INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'AUD',
];

const List<String> _kPortalLanguages = [
  'English', 'Hindi', 'Tamil', 'Telugu', 'Kannada', 'Malayalam',
  'Marathi', 'Gujarati', 'Bengali',
];

const List<String> _kTaxPreferences = ['Taxable', 'Tax Exempt'];

const List<String> _kGstRegTypes = [
  'Registered Business - Regular',
  'Registered Business - Composition',
  'Unregistered Business',
  'Consumer',
  'Overseas',
  'Special Economic Zone',
  'Deemed Export',
];

const List<String> _kIndianStates = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh',
  'Assam', 'Bihar', 'Chandigarh', 'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat',
  'Haryana', 'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand',
  'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep', 'Madhya Pradesh',
  'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha',
  'Puducherry', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana',
  'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
];

const List<String> _kCountries = [
  'India', 'USA', 'UK', 'UAE', 'Singapore', 'Australia',
  'Germany', 'France', 'Japan', 'China',
];

// ============================================================================
class NewVendorPage extends StatefulWidget {
  final String? vendorId;
  const NewVendorPage({Key? key, this.vendorId}) : super(key: key);

  @override
  State<NewVendorPage> createState() => _NewVendorPageState();
}

class _NewVendorPageState extends State<NewVendorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isSaving  = false;
  String? _loadError;
  bool get _isEdit => widget.vendorId != null;

  // ── TAB 1: Other Details ──────────────────────────────────────────────────
  String _vendorType     = 'External Vendor';
  String _status         = 'Active';
  String _salutation     = '';
  final _firstNameCtrl   = TextEditingController();
  final _lastNameCtrl    = TextEditingController();
  final _vendorNameCtrl  = TextEditingController(); // display name (required)
  final _companyNameCtrl = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _workPhoneCtrl   = TextEditingController();
  final _mobileCtrl      = TextEditingController();
  final _websiteCtrl     = TextEditingController();
  final _departmentCtrl  = TextEditingController();
  final _designationCtrl = TextEditingController();
  final _twitterCtrl     = TextEditingController();
  final _facebookCtrl    = TextEditingController();
  String _defaultCurrency = 'INR';
  String _paymentTerms    = 'Net 30';
  String _portalLanguage  = 'English';
  final _openingBalanceCtrl  = TextEditingController();
  final _openingBalAsOfCtrl  = TextEditingController();
  DateTime? _openingBalAsOf;
  bool _portalEnabled = false;

  // ── TAB 2: Tax Info ───────────────────────────────────────────────────────
  final _gstNumberCtrl = TextEditingController();
  String _gstRegType   = '';
  String _placeOfSupply = '';
  final _panNumberCtrl = TextEditingController();
  String _taxPreference = 'Taxable';
  final _exemptionCtrl  = TextEditingController();
  bool   _tdsApplicable = false;
  final _tdsSectionCtrl = TextEditingController();
  final _tdsRateCtrl    = TextEditingController(text: '0');

  // ── TAB 3: Address ────────────────────────────────────────────────────────
  final _bAttentionCtrl = TextEditingController();
  final _bStreet1Ctrl   = TextEditingController();
  final _bStreet2Ctrl   = TextEditingController();
  final _bCityCtrl      = TextEditingController();
  String _bState        = '';
  final _bZipCtrl       = TextEditingController();
  String _bCountry      = 'India';
  final _bPhoneCtrl     = TextEditingController();
  final _bFaxCtrl       = TextEditingController();

  final _sAttentionCtrl = TextEditingController();
  final _sStreet1Ctrl   = TextEditingController();
  final _sStreet2Ctrl   = TextEditingController();
  final _sCityCtrl      = TextEditingController();
  String _sState        = '';
  final _sZipCtrl       = TextEditingController();
  String _sCountry      = 'India';
  final _sPhoneCtrl     = TextEditingController();
  final _sFaxCtrl       = TextEditingController();

  // ── Bank Details ──────────────────────────────────────────────────────────
  bool   _bankProvided        = false;
  final _accHolderCtrl        = TextEditingController();
  final _bankNameCtrl         = TextEditingController();
  final _accNumberCtrl        = TextEditingController();
  final _accNumberConfirmCtrl = TextEditingController();
  final _ifscCtrl             = TextEditingController();

  // ── TAB 4: Contact Persons ────────────────────────────────────────────────
  List<_VendorContactForm> _contactPersons = [];

  // ── TAB 5: Remarks ────────────────────────────────────────────────────────
  final _remarksCtrl    = TextEditingController();
  final _serviceCatCtrl = TextEditingController();
  final _notesCtrl      = TextEditingController();

  // ── Display name suggestions ──────────────────────────────────────────────
  List<String> _displayNameSuggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _firstNameCtrl.addListener(_rebuildSuggestions);
    _lastNameCtrl.addListener(_rebuildSuggestions);
    _companyNameCtrl.addListener(_rebuildSuggestions);
    _vendorNameCtrl.addListener(() => setState(() {}));
    if (_isEdit) {
      _loadVendorData();
    } else {
      _contactPersons.add(_VendorContactForm());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in [
      _firstNameCtrl, _lastNameCtrl, _vendorNameCtrl, _companyNameCtrl,
      _emailCtrl, _workPhoneCtrl, _mobileCtrl, _websiteCtrl,
      _departmentCtrl, _designationCtrl, _twitterCtrl, _facebookCtrl,
      _openingBalanceCtrl, _openingBalAsOfCtrl,
      _gstNumberCtrl, _panNumberCtrl, _exemptionCtrl, _tdsSectionCtrl, _tdsRateCtrl,
      _bAttentionCtrl, _bStreet1Ctrl, _bStreet2Ctrl, _bCityCtrl, _bZipCtrl, _bPhoneCtrl, _bFaxCtrl,
      _sAttentionCtrl, _sStreet1Ctrl, _sStreet2Ctrl, _sCityCtrl, _sZipCtrl, _sPhoneCtrl, _sFaxCtrl,
      _accHolderCtrl, _bankNameCtrl, _accNumberCtrl, _accNumberConfirmCtrl, _ifscCtrl,
      _remarksCtrl, _serviceCatCtrl, _notesCtrl,
    ]) { c.dispose(); }
    for (final cp in _contactPersons) { cp.dispose(); }
    super.dispose();
  }

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
    setState(() { _displayNameSuggestions = suggestions.toList(); });
  }

  // ── Load vendor for edit ──────────────────────────────────────────────────
  Future<void> _loadVendorData() async {
    setState(() { _isLoading = true; _loadError = null; });
    try {
      final result = await BillingVendorsService.getVendorById(widget.vendorId!);
      if (result['success'] == true) {
        final v = BillingVendor.fromJson(result['data'] as Map<String, dynamic>);
        setState(() {
          _vendorType            = v.vendorType;
          _status                = v.status;
          _vendorNameCtrl.text   = v.vendorName;
          _companyNameCtrl.text  = v.companyName;
          _emailCtrl.text        = v.email;
          _workPhoneCtrl.text    = v.phoneNumber;
          _mobileCtrl.text       = v.alternatePhone;
          _defaultCurrency       = _kCurrencies.contains(v.defaultCurrency) ? v.defaultCurrency : 'INR';
          _paymentTerms          = _kPaymentTerms.contains(v.paymentTerms) ? v.paymentTerms : 'Net 30';
          _portalLanguage        = v.portalLanguage;
          _portalEnabled         = v.portalEnabled;
          _facebookCtrl.text     = v.facebook;
          _twitterCtrl.text      = v.twitter;
          _openingBalanceCtrl.text = v.openingBalance > 0 ? v.openingBalance.toStringAsFixed(2) : '';
          _openingBalAsOf        = v.openingBalanceAsOf;
          if (_openingBalAsOf != null) {
            _openingBalAsOfCtrl.text =
              '${_openingBalAsOf!.day.toString().padLeft(2,'0')}/'
              '${_openingBalAsOf!.month.toString().padLeft(2,'0')}/'
              '${_openingBalAsOf!.year}';
          }
          _gstNumberCtrl.text  = v.gstNumber;
          _gstRegType          = v.gstRegistrationType;
          _placeOfSupply       = _kIndianStates.contains(v.placeOfSupply) ? v.placeOfSupply : '';
          _panNumberCtrl.text  = v.panNumber;
          _taxPreference       = v.taxPreference.isNotEmpty ? v.taxPreference : 'Taxable';
          _exemptionCtrl.text  = v.exemptionReason;
          _tdsApplicable       = v.tdsApplicable;
          _tdsSectionCtrl.text = v.tdsSection;
          _tdsRateCtrl.text    = v.tdsRate.toString();
          // Billing address
          _bAttentionCtrl.text = v.billingAddress.attention;
          _bStreet1Ctrl.text   = v.billingAddress.street;
          _bCityCtrl.text      = v.billingAddress.city;
          _bState              = _kIndianStates.contains(v.billingAddress.state) ? v.billingAddress.state : '';
          _bZipCtrl.text       = v.billingAddress.zip;
          _bCountry            = _kCountries.contains(v.billingAddress.country) ? v.billingAddress.country : 'India';
          _bPhoneCtrl.text     = v.billingAddress.phone;
          _bFaxCtrl.text       = v.billingAddress.fax;
          // Shipping address
          _sAttentionCtrl.text = v.shippingAddress.attention;
          _sStreet1Ctrl.text   = v.shippingAddress.street;
          _sCityCtrl.text      = v.shippingAddress.city;
          _sState              = _kIndianStates.contains(v.shippingAddress.state) ? v.shippingAddress.state : '';
          _sZipCtrl.text       = v.shippingAddress.zip;
          _sCountry            = _kCountries.contains(v.shippingAddress.country) ? v.shippingAddress.country : 'India';
          _sPhoneCtrl.text     = v.shippingAddress.phone;
          _sFaxCtrl.text       = v.shippingAddress.fax;
          // Bank
          _bankProvided              = v.bankDetailsProvided;
          _accHolderCtrl.text        = v.accountHolderName;
          _bankNameCtrl.text         = v.bankName;
          _accNumberCtrl.text        = v.accountNumber;
          _accNumberConfirmCtrl.text = v.accountNumber;
          _ifscCtrl.text             = v.ifscCode;
          // Contact persons
          _contactPersons = v.contactPersons.map((cp) {
            final f = _VendorContactForm();
            f.salutation          = cp.salutation;
            f.firstNameCtrl.text  = cp.firstName;
            f.lastNameCtrl.text   = cp.lastName;
            f.emailCtrl.text      = cp.email;
            f.workPhoneCtrl.text  = cp.workPhone;
            f.mobileCtrl.text     = cp.mobile;
            f.designationCtrl.text= cp.designation;
            f.departmentCtrl.text = cp.department;
            f.portalAccess        = cp.portalAccess;
            return f;
          }).toList();
          if (_contactPersons.isEmpty) _contactPersons.add(_VendorContactForm());
          _remarksCtrl.text    = v.remarks;
          _serviceCatCtrl.text = v.serviceCategory;
          _notesCtrl.text      = v.notes;
          _isLoading = false;
        });
        _rebuildSuggestions();
      }
    } catch (e) {
      setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

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
  Future<void> _saveVendor() async {
    if (_vendorNameCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      _snack('Vendor Display Name is required', error: true);
      return;
    }
    if (_emailCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      _snack('Email is required', error: true);
      return;
    }
    if (_workPhoneCtrl.text.trim().isEmpty) {
      _tabController.animateTo(0);
      _snack('Phone number is required', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final billingAddr = {
        'attention': _bAttentionCtrl.text.trim(),
        'street'   : _bStreet1Ctrl.text.trim(),
        'street2'  : _bStreet2Ctrl.text.trim(),
        'city'     : _bCityCtrl.text.trim(),
        'state'    : _bState,
        'zip'      : _bZipCtrl.text.trim(),
        'country'  : _bCountry,
        'phone'    : _bPhoneCtrl.text.trim(),
        'fax'      : _bFaxCtrl.text.trim(),
      };
      final shippingAddr = {
        'attention': _sAttentionCtrl.text.trim(),
        'street'   : _sStreet1Ctrl.text.trim(),
        'street2'  : _sStreet2Ctrl.text.trim(),
        'city'     : _sCityCtrl.text.trim(),
        'state'    : _sState,
        'zip'      : _sZipCtrl.text.trim(),
        'country'  : _sCountry,
        'phone'    : _sPhoneCtrl.text.trim(),
        'fax'      : _sFaxCtrl.text.trim(),
      };
      final contactPersonsList = _contactPersons.map((cp) => {
        'salutation'  : cp.salutation,
        'firstName'   : cp.firstNameCtrl.text.trim(),
        'lastName'    : cp.lastNameCtrl.text.trim(),
        'email'       : cp.emailCtrl.text.trim(),
        'workPhone'   : cp.workPhoneCtrl.text.trim(),
        'mobile'      : cp.mobileCtrl.text.trim(),
        'designation' : cp.designationCtrl.text.trim(),
        'department'  : cp.departmentCtrl.text.trim(),
        'portalAccess': cp.portalAccess,
      }).toList();

      Map<String, dynamic> result;
      if (_isEdit) {
        result = await BillingVendorsService.updateVendor(
          vendorId            : widget.vendorId!,
          vendorType          : _vendorType,
          vendorName          : _vendorNameCtrl.text.trim(),
          companyName         : _companyNameCtrl.text.trim(),
          email               : _emailCtrl.text.trim(),
          phoneNumber         : _workPhoneCtrl.text.trim(),
          alternatePhone      : _mobileCtrl.text.trim(),
          status              : _status,
          defaultCurrency     : _defaultCurrency,
          paymentTerms        : _paymentTerms,
          portalLanguage      : _portalLanguage,
          portalEnabled       : _portalEnabled,
          facebook            : _facebookCtrl.text.trim(),
          twitter             : _twitterCtrl.text.trim(),
          openingBalance      : double.tryParse(_openingBalanceCtrl.text) ?? 0,
          openingBalanceAsOf  : _openingBalAsOf?.toIso8601String(),
          gstNumber           : _gstNumberCtrl.text.trim().toUpperCase(),
          gstRegistrationType : _gstRegType,
          placeOfSupply       : _placeOfSupply,
          panNumber           : _panNumberCtrl.text.trim().toUpperCase(),
          taxPreference       : _taxPreference,
          exemptionReason     : _exemptionCtrl.text.trim(),
          tdsApplicable       : _tdsApplicable,
          tdsSection          : _tdsSectionCtrl.text.trim(),
          tdsRate             : double.tryParse(_tdsRateCtrl.text) ?? 0,
          billingAddress      : billingAddr,
          shippingAddress     : shippingAddr,
          bankDetailsProvided : _bankProvided,
          accountHolderName   : _accHolderCtrl.text.trim(),
          bankName            : _bankNameCtrl.text.trim(),
          accountNumber       : _accNumberCtrl.text.trim(),
          accountNumberConfirm: _accNumberConfirmCtrl.text.trim(),
          ifscCode            : _ifscCtrl.text.trim(),
          contactPersons      : contactPersonsList,
          remarks             : _remarksCtrl.text.trim(),
          serviceCategory     : _serviceCatCtrl.text.trim(),
          notes               : _notesCtrl.text.trim(),
        );
      } else {
        result = await BillingVendorsService.createVendor(
          vendorType          : _vendorType,
          vendorName          : _vendorNameCtrl.text.trim(),
          companyName         : _companyNameCtrl.text.trim(),
          email               : _emailCtrl.text.trim(),
          phoneNumber         : _workPhoneCtrl.text.trim(),
          alternatePhone      : _mobileCtrl.text.trim(),
          status              : _status,
          defaultCurrency     : _defaultCurrency,
          paymentTerms        : _paymentTerms,
          portalLanguage      : _portalLanguage,
          portalEnabled       : _portalEnabled,
          facebook            : _facebookCtrl.text.trim(),
          twitter             : _twitterCtrl.text.trim(),
          openingBalance      : double.tryParse(_openingBalanceCtrl.text) ?? 0,
          openingBalanceAsOf  : _openingBalAsOf?.toIso8601String(),
          gstNumber           : _gstNumberCtrl.text.trim().toUpperCase(),
          gstRegistrationType : _gstRegType,
          placeOfSupply       : _placeOfSupply,
          panNumber           : _panNumberCtrl.text.trim().toUpperCase(),
          taxPreference       : _taxPreference,
          exemptionReason     : _exemptionCtrl.text.trim(),
          tdsApplicable       : _tdsApplicable,
          tdsSection          : _tdsSectionCtrl.text.trim(),
          tdsRate             : double.tryParse(_tdsRateCtrl.text) ?? 0,
          billingAddress      : billingAddr,
          shippingAddress     : shippingAddr,
          bankDetailsProvided : _bankProvided,
          accountHolderName   : _accHolderCtrl.text.trim(),
          bankName            : _bankNameCtrl.text.trim(),
          accountNumber       : _accNumberCtrl.text.trim(),
          accountNumberConfirm: _accNumberConfirmCtrl.text.trim(),
          ifscCode            : _ifscCtrl.text.trim(),
          contactPersons      : contactPersonsList,
          remarks             : _remarksCtrl.text.trim(),
          serviceCategory     : _serviceCatCtrl.text.trim(),
          notes               : _notesCtrl.text.trim(),
        );
      }

      if (result['success'] == true) {
        _snack(_isEdit ? 'Vendor updated successfully' : 'Vendor created successfully');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context, true);
      } else {
        throw Exception(result['message'] ?? 'Failed to save vendor');
      }
    } on BillingVendorsException catch (e) {
      _snack(e.toUserMessage(), error: true);
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
    return Scaffold(
      backgroundColor: _bgGrey,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navyLight))
          : _loadError != null
              ? _buildLoadError()
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _navyDark,
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text(_isEdit ? 'Edit Vendor' : 'New Vendor',
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
            onPressed: _isSaving ? null : _saveVendor,
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_isEdit ? 'Update' : 'Save', style: const TextStyle(fontWeight: FontWeight.bold)),
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
      const Text('Failed to load vendor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(_loadError ?? '', style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _loadVendorData,
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

          // ── Vendor Type & Status ───────────────────────────────────────────
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('Vendor Type'),
            const SizedBox(height: 12),
            wide
                ? Row(children: [
                    Expanded(child: _labelDropdown('Vendor Type', _vendorType, _kVendorTypes, (v) => setState(() => _vendorType = v!))),
                    const SizedBox(width: 12),
                    Expanded(child: _labelDropdown('Status', _status, _kStatuses, (v) => setState(() => _status = v!))),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _labelDropdown('Vendor Type', _vendorType, _kVendorTypes, (v) => setState(() => _vendorType = v!)),
                    const SizedBox(height: 12),
                    _labelDropdown('Status', _status, _kStatuses, (v) => setState(() => _status = v!)),
                  ]),
          ])),
          const SizedBox(height: 16),

          // ── Primary Contact ────────────────────────────────────────────────
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('Primary Contact'),
            const SizedBox(height: 16),

            // Salutation + First + Last
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

            // Company Name
            _field('Company Name', _companyNameCtrl, hint: 'Enter company name'),
            const SizedBox(height: 16),

            // Vendor Display Name (required) — with suggestions
            _fieldLabel('Vendor Display Name', required: true),
            const SizedBox(height: 6),
            _displayNameField(),
            const SizedBox(height: 16),

            // Email (required)
            _field('Email', _emailCtrl,
                hint: 'email@example.com', required: true,
                keyboard: TextInputType.emailAddress),
            const SizedBox(height: 16),

            // Work Phone + Mobile
            wide
                ? Row(children: [
                    Expanded(child: _field('Phone Number', _workPhoneCtrl, hint: 'Work phone', required: true, keyboard: TextInputType.phone)),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Alternate Phone', _mobileCtrl, hint: 'Mobile / alternate', keyboard: TextInputType.phone)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field('Phone Number', _workPhoneCtrl, hint: 'Work phone', required: true, keyboard: TextInputType.phone),
                    const SizedBox(height: 12),
                    _field('Alternate Phone', _mobileCtrl, hint: 'Mobile / alternate', keyboard: TextInputType.phone),
                  ]),
            const SizedBox(height: 16),

            // Website
            _field('Website', _websiteCtrl, hint: 'https://example.com', keyboard: TextInputType.url),
            const SizedBox(height: 16),

            // Designation + Department
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

          // ── Preferences ────────────────────────────────────────────────────
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('Preferences'),
            const SizedBox(height: 16),

            wide
                ? Row(children: [
                    Expanded(child: _labelDropdown('Default Currency', _defaultCurrency, _kCurrencies, (v) => setState(() => _defaultCurrency = v!))),
                    const SizedBox(width: 12),
                    Expanded(child: _labelDropdown('Payment Terms', _paymentTerms, _kPaymentTerms, (v) => setState(() => _paymentTerms = v!))),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _labelDropdown('Default Currency', _defaultCurrency, _kCurrencies, (v) => setState(() => _defaultCurrency = v!)),
                    const SizedBox(height: 12),
                    _labelDropdown('Payment Terms', _paymentTerms, _kPaymentTerms, (v) => setState(() => _paymentTerms = v!)),
                  ]),
            const SizedBox(height: 16),

            wide
                ? Row(children: [
                    Expanded(child: _labelDropdown('Portal Language', _portalLanguage, _kPortalLanguages, (v) => setState(() => _portalLanguage = v!))),
                    const SizedBox(width: 12),
                    Expanded(child: _field('Opening Balance', _openingBalanceCtrl, hint: '0.00', keyboard: TextInputType.number, prefix: Icons.currency_rupee)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _labelDropdown('Portal Language', _portalLanguage, _kPortalLanguages, (v) => setState(() => _portalLanguage = v!)),
                    const SizedBox(height: 12),
                    _field('Opening Balance', _openingBalanceCtrl, hint: '0.00', keyboard: TextInputType.number, prefix: Icons.currency_rupee),
                  ]),
            const SizedBox(height: 16),

            // Opening Balance As Of
            _field('Opening Balance As Of', _openingBalAsOfCtrl,
                hint: 'DD/MM/YYYY', prefix: Icons.calendar_today_outlined),
            const SizedBox(height: 16),

            _portalToggle(),
          ])),
          const SizedBox(height: 16),

          // ── Bank Details ───────────────────────────────────────────────────
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _sectionHeader('Bank Details'),
              const Spacer(),
              Switch(value: _bankProvided, activeColor: _navyAccent, onChanged: (v) => setState(() => _bankProvided = v)),
              Text(_bankProvided ? 'Enabled' : 'Disabled',
                  style: TextStyle(fontSize: 12, color: _bankProvided ? _navyAccent : Colors.grey[500])),
            ]),
            if (_bankProvided) ...[
              const SizedBox(height: 16),
              _field('Account Holder Name', _accHolderCtrl, hint: 'Enter account holder name', required: _bankProvided),
              const SizedBox(height: 12),
              _field('Bank Name', _bankNameCtrl, hint: 'Enter bank name', required: _bankProvided),
              const SizedBox(height: 12),
              wide
                  ? Row(children: [
                      Expanded(child: _field('Account Number', _accNumberCtrl, hint: 'Account number', keyboard: TextInputType.number, required: _bankProvided)),
                      const SizedBox(width: 12),
                      Expanded(child: _field('Re-enter Account Number', _accNumberConfirmCtrl, hint: 'Confirm account number', keyboard: TextInputType.number)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _field('Account Number', _accNumberCtrl, hint: 'Account number', keyboard: TextInputType.number, required: _bankProvided),
                      const SizedBox(height: 12),
                      _field('Re-enter Account Number', _accNumberConfirmCtrl, hint: 'Confirm account number', keyboard: TextInputType.number),
                    ]),
              const SizedBox(height: 12),
              _field('IFSC Code', _ifscCtrl, hint: 'e.g. HDFC0001234', caps: TextCapitalization.characters),
            ],
          ])),
        ]);
      }),
    );
  }

  Widget _displayNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        controller: _vendorNameCtrl,
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
              onTap: () => setState(() { _vendorNameCtrl.text = s; _showSuggestions = false; }),
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
        items: _kSalutations.map((s) => DropdownMenuItem(value: s, child: Text(s.isEmpty ? '—' : s, style: const TextStyle(fontSize: 13)))).toList(),
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
        Container(width: 36, height: 36,
            decoration: BoxDecoration(color: (_portalEnabled ? _green : Colors.grey[400]!).withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(Icons.person_pin_outlined, size: 20, color: _portalEnabled ? _green : Colors.grey[500])),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Vendor Portal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _portalEnabled ? _green : _navyDark)),
          Text(_portalEnabled ? 'Portal access is enabled' : 'Portal access is not enabled',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ])),
        Switch(value: _portalEnabled, activeColor: _green, onChanged: (v) => setState(() => _portalEnabled = v)),
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
        return Column(children: [
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('Tax Information'),
            const SizedBox(height: 16),

            // GSTIN + PAN
            wide
                ? Row(children: [
                    Expanded(child: _field('GSTIN / UIN', _gstNumberCtrl,
                        hint: '22AAAAA0000A1Z5', caps: TextCapitalization.characters,
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(v)) return 'Invalid GSTIN format';
                          return null;
                        })),
                    const SizedBox(width: 12),
                    Expanded(child: _field('PAN Number', _panNumberCtrl,
                        hint: 'ABCDE1234F', caps: TextCapitalization.characters,
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v)) return 'Invalid PAN format';
                          return null;
                        })),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _field('GSTIN / UIN', _gstNumberCtrl,
                        hint: '22AAAAA0000A1Z5', caps: TextCapitalization.characters,
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(v)) return 'Invalid GSTIN format';
                          return null;
                        }),
                    const SizedBox(height: 12),
                    _field('PAN Number', _panNumberCtrl,
                        hint: 'ABCDE1234F', caps: TextCapitalization.characters,
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v)) return 'Invalid PAN format';
                          return null;
                        }),
                  ]),
            const SizedBox(height: 16),

            // GST Registration Type
            _labelDropdown('GST Registration Type',
                _gstRegType.isEmpty ? null : _gstRegType,
                _kGstRegTypes, (v) => setState(() => _gstRegType = v ?? ''),
                nullable: true, nullLabel: 'Select GST Registration Type'),
            const SizedBox(height: 16),

            // Place of Supply
            _labelDropdown('Place of Supply',
                _placeOfSupply.isEmpty ? null : _placeOfSupply,
                _kIndianStates, (v) => setState(() => _placeOfSupply = v ?? ''),
                nullable: true, nullLabel: 'Select Place of Supply'),
            const SizedBox(height: 16),

            // Tax Preference
            _labelDropdown('Tax Preference', _taxPreference, _kTaxPreferences,
                (v) => setState(() => _taxPreference = v ?? 'Taxable')),
            const SizedBox(height: 16),

            if (_taxPreference == 'Tax Exempt') ...[
              _field('Exemption Reason', _exemptionCtrl, hint: 'Provide reason for tax exemption'),
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
                  'GST details are used to calculate taxes on bills. Make sure the GSTIN and PAN are accurate.',
                  style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                )),
              ]),
            ),
          ])),
          const SizedBox(height: 16),

          // TDS Settings
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionHeader('TDS Settings'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _tdsApplicable ? _navyAccent.withOpacity(0.06) : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _tdsApplicable ? _navyAccent.withOpacity(0.3) : Colors.grey[200]!),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TDS Applicable', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _tdsApplicable ? _navyAccent : _navyDark)),
                  Text(_tdsApplicable ? 'TDS will be deducted' : 'TDS not applicable',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ])),
                Switch(value: _tdsApplicable, activeColor: _navyAccent, onChanged: (v) => setState(() => _tdsApplicable = v)),
              ]),
            ),
            if (_tdsApplicable) ...[
              const SizedBox(height: 16),
              wide
                  ? Row(children: [
                      Expanded(child: _field('TDS Section', _tdsSectionCtrl, hint: 'e.g. 194C, 194J')),
                      const SizedBox(width: 12),
                      Expanded(child: _field('TDS Rate (%)', _tdsRateCtrl, hint: 'e.g. 10', keyboard: TextInputType.number)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _field('TDS Section', _tdsSectionCtrl, hint: 'e.g. 194C, 194J'),
                      const SizedBox(height: 12),
                      _field('TDS Rate (%)', _tdsRateCtrl, hint: 'e.g. 10', keyboard: TextInputType.number),
                    ]),
            ],
          ])),
        ]);
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
      _labelDropdown('State', _bState.isEmpty ? null : _bState, _kIndianStates,
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
      _labelDropdown('State', _sState.isEmpty ? null : _sState, _kIndianStates,
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel(label),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _kCountries.contains(value) ? value : 'India',
        decoration: _inputDeco(),
        isExpanded: true,
        items: _kCountries.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
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
              'Add multiple contact persons for this vendor. Each contact can optionally have portal access.',
              style: TextStyle(fontSize: 12, color: Colors.blue[900]),
            )),
          ]),
        ),

        ..._contactPersons.asMap().entries.map((e) => _buildContactPersonCard(e.key, e.value)),

        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _contactPersons.add(_VendorContactForm())),
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

  Widget _buildContactPersonCard(int index, _VendorContactForm cp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _navyLight, borderRadius: BorderRadius.circular(20)),
              child: Text('CONTACT ${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
            const Spacer(),
            if (_contactPersons.length > 1)
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
              _field('Email', cp.emailCtrl, hint: 'email@example.com', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 12),
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
                  Expanded(child: Text('Enable vendor portal access',
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

  Widget _cpSalutation(_VendorContactForm cp) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _fieldLabel('Salutation'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: cp.salutation,
        decoration: _inputDeco(),
        isExpanded: true,
        items: _kSalutations.map((s) => DropdownMenuItem(value: s, child: Text(s.isEmpty ? '—' : s, style: const TextStyle(fontSize: 13)))).toList(),
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
      child: Column(children: [
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader('Remarks'),
          const SizedBox(height: 8),
          Text('Add internal notes or remarks about this vendor. This is for internal use only.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const SizedBox(height: 16),
          TextFormField(
            controller: _remarksCtrl,
            maxLines: 8,
            minLines: 5,
            decoration: _inputDeco(hint: 'Enter any internal notes or remarks about this vendor...'),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ValueListenableBuilder(
              valueListenable: _remarksCtrl,
              builder: (_, v, __) => Text('${_remarksCtrl.text.length} characters',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ),
          ]),
        ])),
        const SizedBox(height: 16),
        _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader('Additional Information'),
          const SizedBox(height: 16),
          _field('Service Category', _serviceCatCtrl, hint: 'e.g. Logistics, IT, Consulting'),
          const SizedBox(height: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _fieldLabel('Notes'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 4,
              minLines: 3,
              decoration: _inputDeco(hint: 'Additional notes (optional)'),
              style: const TextStyle(fontSize: 13),
            ),
          ]),
        ])),
      ]),
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
// VENDOR CONTACT PERSON FORM MODEL
// ============================================================================
class _VendorContactForm {
  String salutation      = '';
  final firstNameCtrl    = TextEditingController();
  final lastNameCtrl     = TextEditingController();
  final emailCtrl        = TextEditingController();
  final workPhoneCtrl    = TextEditingController();
  final mobileCtrl       = TextEditingController();
  final designationCtrl  = TextEditingController();
  final departmentCtrl   = TextEditingController();
  bool portalAccess      = false;

  void dispose() {
    for (final c in [firstNameCtrl, lastNameCtrl, emailCtrl, workPhoneCtrl,
                     mobileCtrl, designationCtrl, departmentCtrl]) {
      c.dispose();
    }
  }
}
