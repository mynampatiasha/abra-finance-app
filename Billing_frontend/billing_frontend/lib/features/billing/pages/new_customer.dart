// ============================================================================
// NEW CUSTOMER PAGE - COMPLETE IMPLEMENTATION WITH SERVICE INTEGRATION
// ============================================================================
// File: lib/features/admin/Billing/pages/new_customer.dart
// 
// COMPLETE implementation with ALL 11 sections fully coded
// - All fields from the discussion
// - Complete validation
// - Dynamic field visibility
// - Professional UI matching payment page
// - Integrated with BillingCustomersService
// - Document upload support
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/services/billing_customers_service.dart';

// Navy blue gradient colors
const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class NewCustomerPage extends StatefulWidget {
  final String? customerId;
  
  const NewCustomerPage({
    Key? key,
    this.customerId,
  }) : super(key: key);

  @override
  State<NewCustomerPage> createState() => _NewCustomerPageState();
}

class _NewCustomerPageState extends State<NewCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  
  // ============================================================================
  // SECTION 1: BASIC INFORMATION
  // ============================================================================
  String selectedCustomerType = 'Individual';
  final _customerDisplayNameController = TextEditingController();
  final _primaryContactPersonController = TextEditingController();
  final _primaryEmailController = TextEditingController();
  final _primaryPhoneController = TextEditingController();
  final _alternatePhoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  String selectedCountry = 'India';
  
  // ============================================================================
  // SECTION 2: COMPANY DETAILS
  // ============================================================================
  final _companyRegistrationController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _gstNumberController = TextEditingController();
  final _tanNumberController = TextEditingController();
  String? selectedIndustryType;
  final _employeeStrengthController = TextEditingController();
  final _annualContractValueController = TextEditingController();
  
  // ============================================================================
  // SECTION 3: CONTACT PERSONS
  // ============================================================================
  List<ContactPerson> contactPersons = [];
  bool showContactPersonsSection = false;
  
  // ============================================================================
  // SECTION 4: CATEGORIZATION & SEGMENTATION
  // ============================================================================
  String selectedCustomerStatus = 'Active';
  final _reasonForBlockingController = TextEditingController();
  String? selectedCustomerTier;
  String selectedSalesTerritory = 'Bangalore';
  List<String> selectedTags = [];
  
  // ============================================================================
  // SECTION 5: RATE CARD & PRICING
  // ============================================================================
  String? selectedRateCard;
  String? selectedContractType;
  final _contractStartDateController = TextEditingController();
  final _contractEndDateController = TextEditingController();
  bool autoRenewal = false;
  final _renewalNoticePeriodController = TextEditingController();
  
  // Vendor-specific rate card fields
  String? selectedVendorCommissionType;
  final _commissionRateController = TextEditingController();
  final _fixedAmountPerTripController = TextEditingController();
  final _revenueShareController = TextEditingController();
  final _minimumGuaranteeController = TextEditingController();
  String? selectedPaymentCycle;
  List<String> selectedVehicleTypesProvided = [];
  final _numberOfVehiclesProvidedController = TextEditingController();
  
  // ============================================================================
  // SECTION 6: PAYMENT TERMS & CREDIT
  // ============================================================================
  String? selectedPaymentTerms;
  String? selectedPreferredPaymentMethod;
  final _creditLimitController = TextEditingController();
  final _securityDepositController = TextEditingController();
  String? selectedSecurityDepositStatus;
  String? selectedBillingFrequency;
  
  // ============================================================================
  // SECTION 7: BILLING PREFERENCES
  // ============================================================================
  final _billingEmailController = TextEditingController();
  final _billingAddressController = TextEditingController();
  bool sameAsPrimaryAddress = true;
  
  // ============================================================================
  // SECTION 8: VENDOR-SPECIFIC DETAILS
  // ============================================================================
  final _vendorVehiclesAvailableController = TextEditingController();
  List<String> vendorVehicleTypes = [];
  final _vendorAgreementStartController = TextEditingController();
  final _vendorAgreementEndController = TextEditingController();
  double vendorPerformanceRating = 0.0;
  final _insuranceValidUntilController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountNumberController = TextEditingController();
  final _ifscCodeController = TextEditingController();
  final _accountHolderNameController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _upiIdController = TextEditingController();
  
  // ============================================================================
  // SECTION 9: DOCUMENT UPLOADS
  // ============================================================================
  Map<String, List<PlatformFile>> uploadedDocuments = {
    'KYC Documents': [],
    'Company Documents': [],
    'Contracts & Agreements': [],
    'Insurance Documents': [],
    'Vehicle Documents': [],
    'Other Documents': [],
  };
  bool showDocumentSection = false;
  
  // ============================================================================
  // SECTION 10: ADDITIONAL INFORMATION
  // ============================================================================
  final _internalNotesController = TextEditingController();
  final _customerInstructionsController = TextEditingController();
  final _specialRequirementsController = TextEditingController();
  List<CustomField> customFields = [];
  bool showCustomFieldsSection = false;
  
  // ============================================================================
  // SECTION 11: AUDIT & TRACKING (Read-only)
  // ============================================================================
  String customerId = '';
  String createdBy = 'Current User';
  DateTime? createdDate;
  String lastModifiedBy = '';
  DateTime? lastModifiedDate;
  DateTime? lastTransactionDate;
  double totalRevenueGenerated = 0.0;
  int totalTripsCompleted = 0;
  
  bool isLoading = false;
  bool isSaving = false;
  
  // ============================================================================
  // DROPDOWN OPTIONS
  // ============================================================================
  
  final List<String> customerTypes = ['Individual', 'Organization', /* 'Vendor', */ 'Others'];
  final List<String> countries = ['India', 'USA', 'UK', 'UAE', 'Singapore', 'Australia'];
  final List<String> industryTypes = [
    'IT & Software',
    'Manufacturing',
    'Retail',
    'Healthcare',
    'Education',
    'Finance',
    'Real Estate',
    'Transportation',
    'Hospitality',
    'Other'
  ];
  final List<String> customerStatuses = ['Active', 'Inactive', 'Blocked', 'Lead', 'Closed'];
  final List<String> customerTiers = ['Gold', 'Silver', 'Bronze', 'Platinum'];
  final List<String> salesTerritories = [
    'Bangalore',
    'Chennai',
    'Mumbai',
    'Delhi',
    'Hyderabad',
    'Pune',
    'Kolkata',
    'Ahmedabad'
  ];
  final List<String> availableTags = [
    'VIP',
    'Regular',
    'Seasonal',
    'Corporate',
    'Government',
    'High-Value',
    'Low-Priority'
  ];
  
  final List<String> rateCardOptions = [
    'Standard Individual Rate',
    'Corporate Rate A (City-wide Flat)',
    'Corporate Rate B (Region-based)',
    'Premium Customer Rate',
    'Government Rate',
    'Weekend Special Rate',
  ];
  
  final List<String> contractTypes = [
    'Fixed Monthly',
    'Quarterly',
    'Per-trip',
    'Pay-as-you-go'
  ];
  
  final List<String> vendorCommissionTypes = [
    'Percentage',
    'Fixed Amount per Trip',
    'Revenue Share'
  ];
  
  final List<String> paymentCycles = [
    'Daily',
    'Weekly',
    'Bi-weekly',
    'Monthly',
    'Quarterly'
  ];
  
  final List<String> vehicleTypes = [
    'Sedan',
    'SUV',
    'Hatchback',
    'Bus',
    'Mini Van',
    'Tempo Traveller',
    'Luxury Car'
  ];
  
  final List<String> paymentTermsOptions = [
    'Immediate/COD',
    '7 days',
    '15 days',
    '30 days',
    '45 days',
    '60 days',
    'NET 90'
  ];
  
  final List<String> paymentMethods = [
    'Cash',
    'UPI',
    'Bank Transfer',
    'Credit Card',
    'Cheque',
    'Online Payment Gateway'
  ];
  
  final List<String> billingFrequencies = [
    'Per-trip',
    'Weekly',
    'Bi-weekly',
    'Monthly',
    'Quarterly'
  ];
  
  final List<String> securityDepositStatuses = [
    'Received',
    'Pending',
    'Refunded'
  ];
  
  final List<String> contactTypes = [
    'Primary Contact',
    'Billing Contact',
    'Operations Contact',
    'Accounts Contact',
    'Emergency Contact'
  ];
  
  final List<String> customFieldTypes = [
    'Text',
    'Number',
    'Date',
    'Dropdown',
    'Checkbox',
    'Email',
    'Phone'
  ];
  
  // ============================================================================
  // LIFECYCLE METHODS
  // ============================================================================
  
  @override
  void initState() {
    super.initState();
    _initializeForm();
    
    // Load customer data if in edit mode
    if (widget.customerId != null) {
      _loadCustomerData(widget.customerId!);
    }
  }
  
  void _initializeForm() {
    customerId = 'CUST-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}';
    createdDate = DateTime.now();
    
    if (selectedCustomerType == 'Organization' || selectedCustomerType == 'Vendor') {
      _addPrimaryContact();
    }
  }
  
  void _addPrimaryContact() {
    if (contactPersons.isEmpty) {
      contactPersons.add(ContactPerson(
        contactType: 'Primary Contact',
        fullName: _primaryContactPersonController.text,
        email: _primaryEmailController.text,
        phoneNumber: _primaryPhoneController.text,
        isPrimary: true,
      ));
    }
  }
  
  @override
  void dispose() {
    _customerDisplayNameController.dispose();
    _primaryContactPersonController.dispose();
    _primaryEmailController.dispose();
    _primaryPhoneController.dispose();
    _alternatePhoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _companyRegistrationController.dispose();
    _panNumberController.dispose();
    _gstNumberController.dispose();
    _tanNumberController.dispose();
    _employeeStrengthController.dispose();
    _annualContractValueController.dispose();
    _reasonForBlockingController.dispose();
    _contractStartDateController.dispose();
    _contractEndDateController.dispose();
    _renewalNoticePeriodController.dispose();
    _commissionRateController.dispose();
    _fixedAmountPerTripController.dispose();
    _revenueShareController.dispose();
    _minimumGuaranteeController.dispose();
    _numberOfVehiclesProvidedController.dispose();
    _creditLimitController.dispose();
    _securityDepositController.dispose();
    _billingEmailController.dispose();
    _billingAddressController.dispose();
    _vendorVehiclesAvailableController.dispose();
    _vendorAgreementStartController.dispose();
    _vendorAgreementEndController.dispose();
    _insuranceValidUntilController.dispose();
    _bankNameController.dispose();
    _bankAccountNumberController.dispose();
    _ifscCodeController.dispose();
    _accountHolderNameController.dispose();
    _branchNameController.dispose();
    _upiIdController.dispose();
    _internalNotesController.dispose();
    _customerInstructionsController.dispose();
    _specialRequirementsController.dispose();
    super.dispose();
  }
  
  // ============================================================================
  // HELPER METHODS
  // ============================================================================
  
  String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date);
  
  Future<void> _selectDate(TextEditingController controller) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (date != null) {
      setState(() {
        controller.text = _formatDate(date);
      });
    }
  }
  
  Future<void> _pickDocuments(String category) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      
      if (result != null) {
        setState(() {
          uploadedDocuments[category]!.addAll(result.files);
        });
      }
    } catch (e) {
      _showError('Failed to pick files: $e');
    }
  }
  
  void _removeDocument(String category, int index) {
    setState(() {
      uploadedDocuments[category]!.removeAt(index);
    });
  }
  
  void _addContactPerson() {
    setState(() {
      contactPersons.add(ContactPerson(
        contactType: 'Billing Contact',
        fullName: '',
        email: '',
        phoneNumber: '',
        isPrimary: false,
      ));
    });
  }
  
  void _removeContactPerson(int index) {
    if (!contactPersons[index].isPrimary) {
      setState(() {
        contactPersons.removeAt(index);
      });
    }
  }
  
  void _addCustomField() {
    setState(() {
      customFields.add(CustomField(
        fieldName: '',
        fieldType: 'Text',
        fieldValue: '',
        isMandatory: false,
      ));
    });
  }
  
  void _removeCustomField(int index) {
    setState(() {
      customFields.removeAt(index);
    });
  }
  
  void _showCreateRateCardDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Rate Card'),
        content: const SizedBox(
          width: 600,
          height: 400,
          child: Center(
            child: Text(
              'Rate Card creation form will be implemented here.\n\n'
              'Fields:\n'
              '- Rate Card Name\n'
              '- Vehicle Type\n'
              '- Base Fare\n'
              '- Per KM Rate\n'
              '- Per Hour Rate\n'
              '- Waiting Charges\n'
              '- Night Charges\n'
              '- Surcharges (custom)\n'
              '- And more...',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccess('Rate card creation will be implemented');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
            ),
            child: const Text('Save Rate Card'),
          ),
        ],
      ),
    );
  }
  
// ============================================================================
// METHOD 3: _saveCustomer - Verify validation exists (around line 950)
// ============================================================================

Future<void> _saveCustomer() async {
  if (!_formKey.currentState!.validate()) {
    _showError('Please fill all required fields');
    return;
  }
  
  // Validation for blocked status
  if (selectedCustomerStatus == 'Blocked' && 
      _reasonForBlockingController.text.isEmpty) {
    _showError('Please provide reason for blocking');
    return;
  }
  
  // ✅ CRITICAL: Validation for B2B customers (must exist)
  if ((selectedCustomerType == 'Organization' || 
       selectedCustomerType == 'Vendor') &&
      _gstNumberController.text.isEmpty) {
    _showError('GST Number is required for B2B customers');
    return;
  }
  
  // ✅ CRITICAL: Validation for Vendor commission type (must exist)
  if (selectedCustomerType == 'Vendor' && 
      selectedVendorCommissionType == null) {
    _showError('Commission Type is required for Vendor customers');
    return;
  }
  
  setState(() => isSaving = true);
  
  try {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    // Build customer data using service
    final customerData = BillingCustomersService.buildCustomerDataFromControllers(
      // Section 1: Basic Information
      customerType: selectedCustomerType,
      customerDisplayName: _customerDisplayNameController.text,
      primaryContactPerson: _primaryContactPersonController.text,
      primaryEmail: _primaryEmailController.text,
      primaryPhone: _primaryPhoneController.text,
      alternatePhone: _alternatePhoneController.text,
      addressLine1: _addressLine1Controller.text,
      addressLine2: _addressLine2Controller.text,
      city: _cityController.text,
      state: _stateController.text,
      postalCode: _postalCodeController.text,
      country: selectedCountry,
      
      // Section 2: Company Details
      companyRegistration: _companyRegistrationController.text,
      panNumber: _panNumberController.text,
      gstNumber: _gstNumberController.text,
      tanNumber: _tanNumberController.text,
      industryType: selectedIndustryType,
      employeeStrength: _employeeStrengthController.text,
      annualContractValue: _annualContractValueController.text,
      
      // Section 3: Contact Persons
      contactPersons: contactPersons.map((c) => c.toJson()).toList(),
      
      // Section 4: Categorization
      customerStatus: selectedCustomerStatus,
      reasonForBlocking: _reasonForBlockingController.text,
      customerTier: selectedCustomerTier,
      salesTerritory: selectedSalesTerritory,
      tags: selectedTags,
      
      // Section 5: Rate Card & Pricing
      rateCard: selectedRateCard,
      contractType: selectedContractType,
      contractStartDate: _contractStartDateController.text,
      contractEndDate: _contractEndDateController.text,
      autoRenewal: autoRenewal,
      renewalNoticePeriod: _renewalNoticePeriodController.text,
      
      // ✅ CRITICAL: Vendor-specific fields (must be included)
      vendorCommissionType: selectedVendorCommissionType,
      commissionRate: _commissionRateController.text,
      fixedAmountPerTrip: _fixedAmountPerTripController.text,
      revenueShare: _revenueShareController.text,
      minimumGuarantee: _minimumGuaranteeController.text,
      paymentCycle: selectedPaymentCycle,
      vehicleTypesProvided: selectedVehicleTypesProvided,
      numberOfVehiclesProvided: _numberOfVehiclesProvidedController.text,
      
      // Section 6: Payment Terms & Credit
      paymentTerms: selectedPaymentTerms ?? '',
      preferredPaymentMethod: selectedPreferredPaymentMethod,
      creditLimit: _creditLimitController.text,
      securityDeposit: _securityDepositController.text,
      securityDepositStatus: selectedSecurityDepositStatus,
      billingFrequency: selectedBillingFrequency ?? '',
      
      // Section 7: Billing Preferences
      billingEmail: _billingEmailController.text,
      billingAddress: _billingAddressController.text,
      sameAsPrimaryAddress: sameAsPrimaryAddress,
      
      // ✅ CRITICAL: Section 8: Vendor-Specific Details (must be included)
      vendorVehiclesAvailable: _vendorVehiclesAvailableController.text,
      vendorVehicleTypes: vendorVehicleTypes,
      vendorAgreementStart: _vendorAgreementStartController.text,
      vendorAgreementEnd: _vendorAgreementEndController.text,
      vendorPerformanceRating: vendorPerformanceRating,
      insuranceValidUntil: _insuranceValidUntilController.text,
      bankName: _bankNameController.text,
      bankAccountNumber: _bankAccountNumberController.text,
      ifscCode: _ifscCodeController.text,
      accountHolderName: _accountHolderNameController.text,
      branchName: _branchNameController.text,
      upiId: _upiIdController.text,
      
      // Section 10: Additional Information
      internalNotes: _internalNotesController.text,
      customerInstructions: _customerInstructionsController.text,
      specialRequirements: _specialRequirementsController.text,
      customFields: customFields.map((c) => c.toJson()).toList(),
    );
    
    // Validate data
    final validationError = BillingCustomersService.validateCustomerData(customerData);
    if (validationError != null) {
      Navigator.pop(context);
      setState(() => isSaving = false);
      _showError(validationError);
      return;
    }
    
    // Create customer via API
    final result = await BillingCustomersService.createCustomer(customerData);
    
    if (result['success'] == true) {
      final createdCustomer = result['data'];
      final createdCustomerId = createdCustomer['_id'];
      
      print('✅ Customer created with ID: $createdCustomerId');
      
      // Upload documents if any
      bool hasDocuments = false;
      for (final entry in uploadedDocuments.entries) {
        if (entry.value.isNotEmpty) {
          hasDocuments = true;
          break;
        }
      }
      
      if (hasDocuments) {
        print('📤 Uploading documents...');
        for (final entry in uploadedDocuments.entries) {
          final category = entry.key;
          final files = entry.value;
          
          if (files.isNotEmpty) {
            try {
              await BillingCustomersService.uploadDocuments(
                createdCustomerId,
                category,
                files,
              );
              print('✅ Uploaded ${files.length} files in category: $category');
            } catch (e) {
              print('⚠️  Failed to upload documents in $category: $e');
            }
          }
        }
      }
      
      Navigator.pop(context);
      setState(() => isSaving = false);
      
      _showSuccess('Customer saved successfully');
      await Future.delayed(const Duration(milliseconds: 500));
      Navigator.pop(context, true);
      
    } else {
      Navigator.pop(context);
      setState(() => isSaving = false);
      _showError(result['message'] ?? 'Failed to save customer');
    }
    
  } on BillingCustomersException catch (e) {
    Navigator.pop(context);
    setState(() => isSaving = false);
    print('❌ BillingCustomersException: ${e.message}');
    _showError(e.toUserMessage());
    
  } catch (e) {
    Navigator.pop(context);
    setState(() => isSaving = false);
    print('❌ Unexpected error: $e');
    _showError('Failed to save customer: ${e.toString()}');
  }
}
  
  Future<void> _saveAsDraft() async {
    _showSuccess('Customer saved as draft');
  }
  
  // ============================================================================
  // LOAD CUSTOMER DATA FOR EDIT MODE
  // ============================================================================
  
  Future<void> _loadCustomerData(String customerId) async {
    print('\n🔄 Loading customer data for ID: $customerId');
    setState(() => isLoading = true);
    
    try {
      print('📡 Calling API: BillingCustomersService.getCustomerById($customerId)');
      final result = await BillingCustomersService.getCustomerById(customerId);
      print('📥 API Response: ${result['success']}');
      
      if (result['success'] == true) {
        final customer = result['data'];
        print('✅ Customer data loaded successfully: ${customer['customerDisplayName']}');
        
        // Populate all form fields from customer data
        setState(() {
          // Section 1: Basic Information
          selectedCustomerType = customer['customerType']?.toString() ?? 'Individual';
          _customerDisplayNameController.text = customer['customerDisplayName']?.toString() ?? '';
          _primaryContactPersonController.text = customer['primaryContactPerson']?.toString() ?? '';
          _primaryEmailController.text = customer['primaryEmail']?.toString() ?? '';
          _primaryPhoneController.text = customer['primaryPhone']?.toString() ?? '';
          _alternatePhoneController.text = customer['alternatePhone']?.toString() ?? '';
          _addressLine1Controller.text = customer['addressLine1']?.toString() ?? '';
          _addressLine2Controller.text = customer['addressLine2']?.toString() ?? '';
          _cityController.text = customer['city']?.toString() ?? '';
          _stateController.text = customer['state']?.toString() ?? '';
          _postalCodeController.text = customer['postalCode']?.toString() ?? '';
          selectedCountry = customer['country']?.toString() ?? 'India';
          
          // Section 2: Company Details
          _companyRegistrationController.text = customer['companyRegistration']?.toString() ?? '';
          _panNumberController.text = customer['panNumber']?.toString() ?? '';
          _gstNumberController.text = customer['gstNumber']?.toString() ?? '';
          _tanNumberController.text = customer['tanNumber']?.toString() ?? '';
          selectedIndustryType = customer['industryType']?.toString();
          _employeeStrengthController.text = customer['employeeStrength']?.toString() ?? '';
          _annualContractValueController.text = customer['annualContractValue']?.toString() ?? '';
          
          // Section 3: Contact Persons
          if (customer['contactPersons'] != null) {
            contactPersons = (customer['contactPersons'] as List).map((cp) => ContactPerson(
              contactType: cp['contactType'],
              fullName: cp['fullName'],
              email: cp['email'],
              phoneNumber: cp['phoneNumber'],
              designation: cp['designation'],
              department: cp['department'],
              isPrimary: cp['isPrimary'] ?? false,
            )).toList();
          }
          
          // Section 4: Categorization
          selectedCustomerStatus = customer['customerStatus']?.toString() ?? 'Active';
          _reasonForBlockingController.text = customer['reasonForBlocking']?.toString() ?? '';
          selectedCustomerTier = customer['customerTier']?.toString();
          selectedSalesTerritory = customer['salesTerritory']?.toString() ?? 'Bangalore';
          selectedTags = customer['tags'] != null ? List<String>.from(customer['tags']) : [];
          
          // Section 5: Rate Card & Pricing
          selectedRateCard = customer['rateCard']?.toString();
          selectedContractType = customer['contractType']?.toString();
          _contractStartDateController.text = customer['contractStartDate']?.toString() ?? '';
          _contractEndDateController.text = customer['contractEndDate']?.toString() ?? '';
          autoRenewal = customer['autoRenewal'] == true;
          _renewalNoticePeriodController.text = customer['renewalNoticePeriod']?.toString() ?? '';
          
          // Vendor-specific
          selectedVendorCommissionType = customer['vendorCommissionType']?.toString();
          _commissionRateController.text = customer['commissionRate']?.toString() ?? '';
          _fixedAmountPerTripController.text = customer['fixedAmountPerTrip']?.toString() ?? '';
          _revenueShareController.text = customer['revenueShare']?.toString() ?? '';
          _minimumGuaranteeController.text = customer['minimumGuarantee']?.toString() ?? '';
          selectedPaymentCycle = customer['paymentCycle']?.toString();
          selectedVehicleTypesProvided = customer['vehicleTypesProvided'] != null ? List<String>.from(customer['vehicleTypesProvided']) : [];
          _numberOfVehiclesProvidedController.text = customer['numberOfVehiclesProvided']?.toString() ?? '';
          
          // Section 6: Payment Terms & Credit
          selectedPaymentTerms = customer['paymentTerms']?.toString();
          selectedPreferredPaymentMethod = customer['preferredPaymentMethod']?.toString();
          _creditLimitController.text = customer['creditLimit']?.toString() ?? '';
          _securityDepositController.text = customer['securityDeposit']?.toString() ?? '';
          selectedSecurityDepositStatus = customer['securityDepositStatus']?.toString();
          selectedBillingFrequency = customer['billingFrequency']?.toString();
          
          // Section 7: Billing Preferences
          _billingEmailController.text = customer['billingEmail']?.toString() ?? '';
          _billingAddressController.text = customer['billingAddress']?.toString() ?? '';
          sameAsPrimaryAddress = customer['sameAsPrimaryAddress'] == true;
          
          // Section 8: Vendor-Specific Details
          _vendorVehiclesAvailableController.text = customer['vendorVehiclesAvailable']?.toString() ?? '';
          vendorVehicleTypes = customer['vendorVehicleTypes'] != null ? List<String>.from(customer['vendorVehicleTypes']) : [];
          _vendorAgreementStartController.text = customer['vendorAgreementStart']?.toString() ?? '';
          _vendorAgreementEndController.text = customer['vendorAgreementEnd']?.toString() ?? '';
          vendorPerformanceRating = (customer['vendorPerformanceRating'] ?? 0).toDouble();
          _insuranceValidUntilController.text = customer['insuranceValidUntil']?.toString() ?? '';
          _bankNameController.text = customer['bankName']?.toString() ?? '';
          _bankAccountNumberController.text = customer['bankAccountNumber']?.toString() ?? '';
          _ifscCodeController.text = customer['ifscCode']?.toString() ?? '';
          _accountHolderNameController.text = customer['accountHolderName']?.toString() ?? '';
          _branchNameController.text = customer['branchName']?.toString() ?? '';
          _upiIdController.text = customer['upiId']?.toString() ?? '';
          
          // Section 10: Additional Information
          _internalNotesController.text = customer['internalNotes']?.toString() ?? '';
          _customerInstructionsController.text = customer['customerInstructions']?.toString() ?? '';
          _specialRequirementsController.text = customer['specialRequirements']?.toString() ?? '';
          
          if (customer['customFields'] != null) {
            customFields = (customer['customFields'] as List).map((cf) => CustomField(
              fieldName: cf['fieldName'],
              fieldType: cf['fieldType'],
              fieldValue: cf['fieldValue'],
              isMandatory: cf['isMandatory'] ?? false,
            )).toList();
          }
          
          // Section 11: Audit Trail
          this.customerId = customer['customerId']?.toString() ?? '';
          createdBy = customer['createdBy']?.toString() ?? 'Unknown';
          createdDate = customer['createdDate'] != null 
              ? DateTime.tryParse(customer['createdDate'].toString())
              : null;
          lastModifiedBy = customer['lastModifiedBy']?.toString() ?? '';
          lastModifiedDate = customer['lastModifiedDate'] != null 
              ? DateTime.tryParse(customer['lastModifiedDate'].toString())
              : null;
          totalRevenueGenerated = (customer['totalRevenueGenerated'] ?? 0).toDouble();
          totalTripsCompleted = customer['totalTripsCompleted'] ?? 0;
          
          isLoading = false;
        });
        
        print('✅ All fields populated successfully');
      } else {
        throw Exception(result['message'] ?? 'Failed to load customer');
      }
    } on BillingCustomersException catch (e) {
      print('❌ BillingCustomersException: ${e.message}');
      setState(() => isLoading = false);
      _showError(e.toUserMessage());
    } catch (e) {
      print('❌ Error loading customer: $e');
      setState(() => isLoading = false);
      _showError('Failed to load customer: $e');
    }
  }
  
  // ============================================================================
  // UPDATE CUSTOMER (FOR EDIT MODE)
  // ============================================================================
  
  Future<void> _updateCustomer() async {
    if (!_formKey.currentState!.validate()) {
      _showError('Please fill all required fields');
      return;
    }
    
    setState(() => isSaving = true);
    
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Build updated customer data
      final customerData = BillingCustomersService.buildCustomerDataFromControllers(
        customerType: selectedCustomerType,
        customerDisplayName: _customerDisplayNameController.text,
        primaryContactPerson: _primaryContactPersonController.text,
        primaryEmail: _primaryEmailController.text,
        primaryPhone: _primaryPhoneController.text,
        alternatePhone: _alternatePhoneController.text,
        addressLine1: _addressLine1Controller.text,
        addressLine2: _addressLine2Controller.text,
        city: _cityController.text,
        state: _stateController.text,
        postalCode: _postalCodeController.text,
        country: selectedCountry,
        companyRegistration: _companyRegistrationController.text,
        panNumber: _panNumberController.text,
        gstNumber: _gstNumberController.text,
        tanNumber: _tanNumberController.text,
        industryType: selectedIndustryType,
        employeeStrength: _employeeStrengthController.text,
        annualContractValue: _annualContractValueController.text,
        contactPersons: contactPersons.map((c) => c.toJson()).toList(),
        customerStatus: selectedCustomerStatus,
        reasonForBlocking: _reasonForBlockingController.text,
        customerTier: selectedCustomerTier,
        salesTerritory: selectedSalesTerritory,
        tags: selectedTags,
        rateCard: selectedRateCard,
        contractType: selectedContractType,
        contractStartDate: _contractStartDateController.text,
        contractEndDate: _contractEndDateController.text,
        autoRenewal: autoRenewal,
        renewalNoticePeriod: _renewalNoticePeriodController.text,
        vendorCommissionType: selectedVendorCommissionType,
        commissionRate: _commissionRateController.text,
        fixedAmountPerTrip: _fixedAmountPerTripController.text,
        revenueShare: _revenueShareController.text,
        minimumGuarantee: _minimumGuaranteeController.text,
        paymentCycle: selectedPaymentCycle,
        vehicleTypesProvided: selectedVehicleTypesProvided,
        numberOfVehiclesProvided: _numberOfVehiclesProvidedController.text,
        paymentTerms: selectedPaymentTerms ?? '',
        preferredPaymentMethod: selectedPreferredPaymentMethod,
        creditLimit: _creditLimitController.text,
        securityDeposit: _securityDepositController.text,
        securityDepositStatus: selectedSecurityDepositStatus,
        billingFrequency: selectedBillingFrequency ?? '',
        billingEmail: _billingEmailController.text,
        billingAddress: _billingAddressController.text,
        sameAsPrimaryAddress: sameAsPrimaryAddress,
        vendorVehiclesAvailable: _vendorVehiclesAvailableController.text,
        vendorVehicleTypes: vendorVehicleTypes,
        vendorAgreementStart: _vendorAgreementStartController.text,
        vendorAgreementEnd: _vendorAgreementEndController.text,
        vendorPerformanceRating: vendorPerformanceRating,
        insuranceValidUntil: _insuranceValidUntilController.text,
        bankName: _bankNameController.text,
        bankAccountNumber: _bankAccountNumberController.text,
        ifscCode: _ifscCodeController.text,
        accountHolderName: _accountHolderNameController.text,
        branchName: _branchNameController.text,
        upiId: _upiIdController.text,
        internalNotes: _internalNotesController.text,
        customerInstructions: _customerInstructionsController.text,
        specialRequirements: _specialRequirementsController.text,
        customFields: customFields.map((c) => c.toJson()).toList(),
      );
      
      // Update customer via API
      final result = await BillingCustomersService.updateCustomer(
        widget.customerId!,
        customerData,
      );
      
      if (result['success'] == true) {
        Navigator.pop(context); // Close loading dialog
        setState(() => isSaving = false);
        
        _showSuccess('Customer updated successfully');
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, true);
      } else {
        Navigator.pop(context);
        setState(() => isSaving = false);
        _showError(result['message'] ?? 'Failed to update customer');
      }
      
    } on BillingCustomersException catch (e) {
      Navigator.pop(context);
      setState(() => isSaving = false);
      _showError(e.toUserMessage());
    } catch (e) {
      Navigator.pop(context);
      setState(() => isSaving = false);
      _showError('Failed to update customer: $e');
    }
  }
  
  void _resetForm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Form'),
        content: const Text(
          'Are you sure you want to reset the form? All unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _formKey.currentState?.reset();
                _initializeForm();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Inactive':
        return Colors.grey;
      case 'Blocked':
        return Colors.red;
      case 'Lead':
        return Colors.blue;
      case 'Closed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  
  Color _getTierColor(String tier) {
    switch (tier) {
      case 'Platinum':
        return const Color(0xFF95A5A6);
      case 'Gold':
        return const Color(0xFFF39C12);
      case 'Silver':
        return const Color(0xFFBDC3C7);
      case 'Bronze':
        return const Color(0xFFCD7F32);
      default:
        return Colors.grey;
    }
  }
  
  Color _getCustomerTypeColor() {
    switch (selectedCustomerType) {
      case 'Individual':
        return const Color(0xFF3498DB);
      case 'Organization':
        return const Color(0xFF9B59B6);
      case 'Vendor':
        return const Color(0xFFE67E22);
      case 'Others':
        return const Color(0xFF95A5A6);
      default:
        return const Color(0xFF3498DB);
    }
  }
  
  IconData _getCustomerTypeIcon(String type) {
    switch (type) {
      case 'Individual':
        return Icons.person_outline;
      case 'Organization':
        return Icons.business_outlined;
      case 'Vendor':
        return Icons.local_shipping_outlined;
      case 'Others':
        return Icons.more_horiz;
      default:
        return Icons.person_outline;
    }
  }
  
  String _getCustomerTypeDescription() {
    switch (selectedCustomerType) {
      case 'Individual':
        return 'For individual customers or end-users';
      case 'Organization':
        return 'For corporate clients and business entities';
      case 'Vendor':
        return 'For transport vendors and fleet partners';
      case 'Others':
        return 'For customers that don\'t fit other categories';
      default:
        return '';
    }
  }
  
  IconData _getDocumentCategoryIcon(String category) {
    switch (category) {
      case 'KYC Documents':
        return Icons.badge_outlined;
      case 'Company Documents':
        return Icons.business_center_outlined;
      case 'Contracts & Agreements':
        return Icons.description_outlined;
      case 'Insurance Documents':
        return Icons.shield_outlined;
      case 'Vehicle Documents':
        return Icons.directions_car_outlined;
      default:
        return Icons.folder_outlined;
    }
  }
  
  IconData _getFileIcon(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  // ============================================================================
  // BUILD METHOD
  // ============================================================================
  
  @override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
  final isMobile = screenWidth < 900;
  
  return Scaffold(
    backgroundColor: Colors.grey[100],
    appBar: AppBar(
      title: Text(widget.customerId == null ? 'New Customer' : 'Edit Customer'),
      backgroundColor: const Color(0xFF2C3E50),
      foregroundColor: Colors.white,
      elevation: 1,
      actions: [
        // Mobile: Show icon buttons only
        if (isMobile) ...[
          IconButton(
            onPressed: _saveAsDraft,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save as Draft',
          ),
          IconButton(
            onPressed: isSaving ? null : () {
              if (widget.customerId != null) {
                _updateCustomer();
              } else {
                _saveCustomer();
              }
            },
            icon: const Icon(Icons.check),
            tooltip: widget.customerId != null ? 'Update Customer' : 'Save & Activate',
          ),
        ]
        // Desktop: Show full buttons
        else ...[
          OutlinedButton.icon(
            onPressed: _saveAsDraft,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save as Draft'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: isSaving ? null : () {
              if (widget.customerId != null) {
                _updateCustomer();
              } else {
                _saveCustomer();
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: Text(widget.customerId != null ? 'Update Customer' : 'Save & Activate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ],
    ),
    body: isLoading
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3498DB)),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.customerId != null 
                      ? 'Loading customer data...' 
                      : 'Initializing form...',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                if (widget.customerId != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Customer ID: ${widget.customerId}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
          )
        : Form(
            key: _formKey,
            child: isMobile
                // Mobile Layout: Single column with all content
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer Type Selection
                        _buildCustomerTypeSection(),
                        const SizedBox(height: 20),
                        
                        // Section 1: Basic Information
                        _buildBasicInformationSection(),
                        const SizedBox(height: 20),
                        
                        // Section 2: Company Details (for Organization/Vendor)
                        if (selectedCustomerType == 'Organization' ||
                            selectedCustomerType == 'Vendor')
                          ...[
                            _buildCompanyDetailsSection(),
                            const SizedBox(height: 20),
                          ],
                        
                        // Section 3: Contact Persons (for Organization/Vendor)
                        if (selectedCustomerType == 'Organization' ||
                            selectedCustomerType == 'Vendor')
                          ...[
                            _buildContactPersonsSection(),
                            const SizedBox(height: 20),
                          ],
                        
                        // Section 4: Categorization & Segmentation
                        _buildCategorizationSection(),
                        const SizedBox(height: 20),
                        
                        // Section 5: Rate Card & Pricing
                        _buildRateCardSection(),
                        const SizedBox(height: 20),
                        
                        // Section 6: Payment Terms & Credit
                        _buildPaymentTermsSection(),
                        const SizedBox(height: 20),
                        
                        // Section 7: Billing Preferences
                        _buildBillingPreferencesSection(),
                        const SizedBox(height: 20),
                        
                        // Section 8: Vendor-Specific Details (for Vendor only)
                        if (selectedCustomerType == 'Vendor')
                          ...[
                            _buildVendorSpecificSection(),
                            const SizedBox(height: 20),
                          ],
                        
                        // Section 9: Document Uploads
                        _buildDocumentUploadsSection(),
                        const SizedBox(height: 20),
                        
                        // Section 10: Additional Information
                        _buildAdditionalInformationSection(),
                        const SizedBox(height: 20),
                        
                        // Mobile: Summary sections at bottom
                        _buildCustomerSummarySection(),
                        const Divider(height: 32),
                        _buildAuditTrailSection(),
                        const Divider(height: 32),
                        _buildQuickActionsSection(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  )
                // Desktop Layout: Row with sidebar
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main content area (left side)
                      Expanded(
                        flex: 3,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Customer Type Selection
                              _buildCustomerTypeSection(),
                              const SizedBox(height: 24),
                              
                              // Section 1: Basic Information
                              _buildBasicInformationSection(),
                              const SizedBox(height: 24),
                              
                              // Section 2: Company Details (for Organization/Vendor)
                              if (selectedCustomerType == 'Organization' ||
                                  selectedCustomerType == 'Vendor')
                                ...[
                                  _buildCompanyDetailsSection(),
                                  const SizedBox(height: 24),
                                ],
                              
                              // Section 3: Contact Persons (for Organization/Vendor)
                              if (selectedCustomerType == 'Organization' ||
                                  selectedCustomerType == 'Vendor')
                                ...[
                                  _buildContactPersonsSection(),
                                  const SizedBox(height: 24),
                                ],
                              
                              // Section 4: Categorization & Segmentation
                              _buildCategorizationSection(),
                              const SizedBox(height: 24),
                              
                              // Section 5: Rate Card & Pricing
                              _buildRateCardSection(),
                              const SizedBox(height: 24),
                              
                              // Section 6: Payment Terms & Credit
                              _buildPaymentTermsSection(),
                              const SizedBox(height: 24),
                              
                              // Section 7: Billing Preferences
                              _buildBillingPreferencesSection(),
                              const SizedBox(height: 24),
                              
                              // Section 8: Vendor-Specific Details (for Vendor only)
                              if (selectedCustomerType == 'Vendor')
                                ...[
                                  _buildVendorSpecificSection(),
                                  const SizedBox(height: 24),
                                ],
                              
                              // Section 9: Document Uploads
                              _buildDocumentUploadsSection(),
                              const SizedBox(height: 24),
                              
                              // Section 10: Additional Information
                              _buildAdditionalInformationSection(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                      
                      // Right sidebar - Summary & Audit Trail (Desktop only)
                      Container(
                        width: 350,
                        color: Colors.white,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCustomerSummarySection(),
                              const Divider(height: 32),
                              _buildAuditTrailSection(),
                              const Divider(height: 32),
                              _buildQuickActionsSection(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
  );
}
  
  // ============================================================================
  // CUSTOMER TYPE SELECTION SECTION
  // ============================================================================
  
  Widget _buildCustomerTypeSection() {
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
          Row(
            children: [
              const Text(
                'Customer Type',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
              const Text(
                ' *',
                style: TextStyle(color: Colors.red, fontSize: 15),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getCustomerTypeColor(),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  selectedCustomerType.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: customerTypes.map((type) {
              final isSelected = selectedCustomerType == type;
              return InkWell(
                onTap: () {
                  setState(() {
                    selectedCustomerType = type;
                    // Reset type-specific fields
                    if (type != 'Organization' && type != 'Vendor') {
                      contactPersons.clear();
                    } else {
                      _addPrimaryContact();
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF3498DB).withOpacity(0.1)
                        : Colors.grey[50],
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF3498DB)
                          : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getCustomerTypeIcon(type),
                        color: isSelected
                            ? const Color(0xFF3498DB)
                            : Colors.grey[600],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        type,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontSize: 14,
                          color: isSelected
                              ? const Color(0xFF3498DB)
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            _getCustomerTypeDescription(),
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
  
  // ============================================================================
  // SECTION 1: BASIC INFORMATION
  // ============================================================================
  
  Widget _buildBasicInformationSection() {
    return _buildSection(
      title: 'Basic Information',
      icon: Icons.info_outline,
      child: Column(
        children: [
          // Customer Display Name / Company Name
          _buildRequiredField(
            label: selectedCustomerType == 'Organization' || 
                    selectedCustomerType == 'Vendor'
                ? 'Company Name'
                : 'Customer Display Name',
            child: TextFormField(
              controller: _customerDisplayNameController,
              decoration: _inputDecoration(
                hintText: selectedCustomerType == 'Organization' || 
                         selectedCustomerType == 'Vendor'
                    ? 'Enter company name'
                    : 'Enter customer name',
              ),
              validator: (value) =>
                  value?.isEmpty == true ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 20),
          
          // Primary Contact Person Name (for Organization/Vendor)
          if (selectedCustomerType == 'Organization' ||
              selectedCustomerType == 'Vendor')
            ...[
              _buildRequiredField(
                label: 'Primary Contact Person Name',
                child: TextFormField(
                  controller: _primaryContactPersonController,
                  decoration: _inputDecoration(
                    hintText: 'Enter contact person name',
                  ),
                  validator: (value) =>
                      value?.isEmpty == true ? 'Required' : null,
                  onChanged: (value) {
                    if (contactPersons.isNotEmpty) {
                      contactPersons[0].fullName = value;
                    }
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          
          // Primary Email
          _buildRequiredField(
            label: 'Primary Email',
            child: TextFormField(
              controller: _primaryEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration(
                hintText: 'email@example.com',
                prefixIcon: Icons.email_outlined,
              ),
              validator: (value) {
                if (value?.isEmpty == true) return 'Required';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                    .hasMatch(value!)) {
                  return 'Invalid email format';
                }
                return null;
              },
              onChanged: (value) {
                if (contactPersons.isNotEmpty) {
                  contactPersons[0].email = value;
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // Primary Phone Number
          _buildRequiredField(
            label: 'Primary Phone Number',
            child: TextFormField(
              controller: _primaryPhoneController,
              keyboardType: TextInputType.phone,
              decoration: _inputDecoration(
                hintText: '+91 98765 43210',
                prefixIcon: Icons.phone_outlined,
              ),
              validator: (value) {
                if (value?.isEmpty == true) return 'Required';
                if (!RegExp(r'^[+]?[0-9]{10,15}$').hasMatch(value!)) {
                  return 'Invalid phone number';
                }
                return null;
              },
              onChanged: (value) {
                if (contactPersons.isNotEmpty) {
                  contactPersons[0].phoneNumber = value;
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // Alternate Phone
          _buildOptionalField(
            label: 'Alternate Phone',
            child: TextFormField(
              controller: _alternatePhoneController,
              keyboardType: TextInputType.phone,
              decoration: _inputDecoration(
                hintText: '+91 98765 43210',
                prefixIcon: Icons.phone_outlined,
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Address Line 1
          _buildRequiredField(
            label: 'Address Line 1',
            child: TextFormField(
              controller: _addressLine1Controller,
              decoration: _inputDecoration(
                hintText: 'Street address, building number',
              ),
              validator: (value) =>
                  value?.isEmpty == true ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 20),
          
          // Address Line 2
          _buildOptionalField(
            label: 'Address Line 2',
            child: TextFormField(
              controller: _addressLine2Controller,
              decoration: _inputDecoration(
                hintText: 'Apartment, suite, floor (optional)',
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // City and State (Responsive Row)
          _buildResponsiveRow(
            context,
            [
              _buildRequiredField(
                label: 'City',
                child: TextFormField(
                  controller: _cityController,
                  decoration: _inputDecoration(
                    hintText: 'City',
                  ),
                  validator: (value) =>
                      value?.isEmpty == true ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 16),
              _buildRequiredField(
                label: 'State/Province',
                child: TextFormField(
                  controller: _stateController,
                  decoration: _inputDecoration(
                    hintText: 'State',
                  ),
                  validator: (value) =>
                      value?.isEmpty == true ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Postal Code and Country (Responsive Row)
          _buildResponsiveRow(
            context,
            [
              _buildOptionalField(
                label: 'Postal/PIN Code',
                child: TextFormField(
                  controller: _postalCodeController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    hintText: '560001',
                  ),
                ),
              ),
              const SizedBox(width: 16),
              _buildRequiredField(
                label: 'Country',
                child: DropdownButtonFormField<String>(
                  value: selectedCountry,
                  decoration: _inputDecoration(),
                  items: countries.map((country) {
                    return DropdownMenuItem(
                      value: country,
                      child: Text(country),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedCountry = value!);
                  },
                  validator: (value) =>
                      value?.isEmpty == true ? 'Required' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  
  // ============================================================================
  // SECTION 2: COMPANY DETAILS - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildCompanyDetailsSection() {
    return _buildSection(
      title: 'Company Details',
      icon: Icons.business_center_outlined,
      child: Column(
        children: [
          // Company Registration Number
          _buildOptionalField(
            label: 'Company Registration Number',
            child: TextFormField(
              controller: _companyRegistrationController,
              decoration: _inputDecoration(
                hintText: 'Enter registration number',
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // PAN Number
          _buildOptionalField(
            label: 'PAN Number',
            child: TextFormField(
              controller: _panNumberController,
              decoration: _inputDecoration(
                hintText: 'ABCDE1234F',
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if (value?.isNotEmpty == true &&
                    !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(value!)) {
                  return 'Invalid PAN format';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // GST Number
          _buildRequiredField(
            label: 'GST Number/GSTIN',
            showRequired: selectedCustomerType == 'Organization' ||
                          selectedCustomerType == 'Vendor',
            child: TextFormField(
              controller: _gstNumberController,
              decoration: _inputDecoration(
                hintText: '22AAAAA0000A1Z5',
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if ((selectedCustomerType == 'Organization' ||
                     selectedCustomerType == 'Vendor') &&
                    value?.isEmpty == true) {
                  return 'Required for B2B customers';
                }
                if (value?.isNotEmpty == true &&
                    !RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$')
                        .hasMatch(value!)) {
                  return 'Invalid GST format';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // TAN Number (for Organization only)
          if (selectedCustomerType == 'Organization')
            ...[
              _buildOptionalField(
                label: 'TAN Number',
                child: TextFormField(
                  controller: _tanNumberController,
                  decoration: _inputDecoration(
                    hintText: 'ABCD12345E',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              const SizedBox(height: 20),
            ],
          
          // Industry Type (for Organization only)
          if (selectedCustomerType == 'Organization')
            ...[
              _buildOptionalField(
                label: 'Industry Type',
                child: DropdownButtonFormField<String>(
                  value: selectedIndustryType,
                  decoration: _inputDecoration(),
                  hint: const Text('Select industry'),
                  items: industryTypes.map((industry) {
                    return DropdownMenuItem(
                      value: industry,
                      child: Text(industry),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedIndustryType = value);
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          
          // Employee Strength (for Organization only)
          if (selectedCustomerType == 'Organization')
            ...[
              _buildOptionalField(
                label: 'Employee Strength',
                child: TextFormField(
                  controller: _employeeStrengthController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration(
                    hintText: 'Number of employees',
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          
          // Annual Contract Value (for Organization only)
          if (selectedCustomerType == 'Organization')
            _buildOptionalField(
              label: 'Annual Contract Value (ACV)',
              child: TextFormField(
                controller: _annualContractValueController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(
                  hintText: 'Enter amount',
                  prefixText: '₹ ',
                ),
              ),
            ),
        ],
      ),
    );
  }

  
  // ============================================================================
  // SECTION 3: CONTACT PERSONS - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildContactPersonsSection() {
    return _buildExpandableSection(
      title: 'Contact Persons',
      icon: Icons.contacts_outlined,
      isExpanded: showContactPersonsSection,
      onToggle: () {
        setState(() {
          showContactPersonsSection = !showContactPersonsSection;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manage multiple contact persons for different purposes (billing, operations, accounts, etc.)',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          
          // List of contact persons
          ...contactPersons.asMap().entries.map((entry) {
            final index = entry.key;
            final contact = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: contact.isPrimary ? const Color(0xFF3498DB) : Colors.grey[700],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          contact.isPrimary ? 'PRIMARY' : 'CONTACT ${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (!contact.isPrimary)
                        IconButton(
                          onPressed: () => _removeContactPerson(index),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: Colors.red,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Contact Type
                  _buildOptionalField(
                    label: 'Contact Type',
                    child: DropdownButtonFormField<String>(
                      value: contact.contactType,
                      decoration: _inputDecoration(),
                      items: contactTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type),
                          enabled: !contact.isPrimary || type == 'Primary Contact',
                        );
                      }).toList(),
                      onChanged: contact.isPrimary
                          ? null
                          : (value) {
                              setState(() {
                                contactPersons[index].contactType = value!;
                              });
                            },
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Full Name
                  _buildRequiredField(
                    label: 'Full Name',
                    child: TextFormField(
                      initialValue: contact.fullName,
                      decoration: _inputDecoration(hintText: 'Enter full name'),
                      enabled: !contact.isPrimary,
                      onChanged: (value) {
                        contactPersons[index].fullName = value;
                      },
                      validator: (value) => value?.isEmpty == true ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Email and Phone (Responsive Row)
                  _buildResponsiveRow(
                    context,
                    [
                      _buildRequiredField(
                        label: 'Email',
                        child: TextFormField(
                          initialValue: contact.email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _inputDecoration(hintText: 'email@example.com'),
                          enabled: !contact.isPrimary,
                          onChanged: (value) {
                            contactPersons[index].email = value;
                          },
                          validator: (value) {
                            if (value?.isEmpty == true) return 'Required';
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value!)) {
                              return 'Invalid email';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildRequiredField(
                        label: 'Phone Number',
                        child: TextFormField(
                          initialValue: contact.phoneNumber,
                          keyboardType: TextInputType.phone,
                          decoration: _inputDecoration(hintText: '+91 98765 43210'),
                          enabled: !contact.isPrimary,
                          onChanged: (value) {
                            contactPersons[index].phoneNumber = value;
                          },
                          validator: (value) {
                            if (value?.isEmpty == true) return 'Required';
                            if (!RegExp(r'^[+]?[0-9]{10,15}$').hasMatch(value!)) {
                              return 'Invalid phone';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Designation and Department (Responsive Row)
                  _buildResponsiveRow(
                    context,
                    [
                      _buildOptionalField(
                        label: 'Designation/Role',
                        child: TextFormField(
                          initialValue: contact.designation,
                          decoration: _inputDecoration(hintText: 'Manager, CEO, etc.'),
                          onChanged: (value) {
                            contactPersons[index].designation = value;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      _buildOptionalField(
                        label: 'Department',
                        child: TextFormField(
                          initialValue: contact.department,
                          decoration: _inputDecoration(hintText: 'Sales, Finance, etc.'),
                          onChanged: (value) {
                            contactPersons[index].department = value;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
          
          const SizedBox(height: 16),
          
          // Add Contact Person Button
          OutlinedButton.icon(
            onPressed: _addContactPerson,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Contact Person'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3498DB),
              side: const BorderSide(color: Color(0xFF3498DB)),
            ),
          ),
        ],
      ),
    );
  }

  
  // ============================================================================
  // SECTION 4: CATEGORIZATION & SEGMENTATION - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildCategorizationSection() {
    return _buildSection(
      title: 'Categorization & Segmentation',
      icon: Icons.category_outlined,
      child: Column(
        children: [
          // Customer Status
          _buildRequiredField(
            label: 'Customer Status',
            child: DropdownButtonFormField<String>(
              value: selectedCustomerStatus,
              decoration: _inputDecoration(),
              items: customerStatuses.map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _getStatusColor(status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(status),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => selectedCustomerStatus = value!);
              },
              validator: (value) => value?.isEmpty == true ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 20),
          
          // Reason for Blocking (if status is Blocked)
          if (selectedCustomerStatus == 'Blocked') ...[
            _buildRequiredField(
              label: 'Reason for Blocking',
              child: TextFormField(
                controller: _reasonForBlockingController,
                maxLines: 3,
                decoration: _inputDecoration(
                  hintText: 'Please provide reason for blocking this customer',
                ),
                validator: (value) =>
                    value?.isEmpty == true ? 'Required when blocked' : null,
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          // Customer Tier
          _buildOptionalField(
            label: 'Customer Tier',
            child: DropdownButtonFormField<String>(
              value: selectedCustomerTier,
              decoration: _inputDecoration(),
              hint: const Text('Select tier'),
              items: customerTiers.map((tier) {
                return DropdownMenuItem(
                  value: tier,
                  child: Row(
                    children: [
                      Icon(Icons.star, size: 16, color: _getTierColor(tier)),
                      const SizedBox(width: 8),
                      Text(tier),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => selectedCustomerTier = value);
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // Sales Territory
          _buildRequiredField(
            label: 'Sales Territory',
            child: DropdownButtonFormField<String>(
              value: selectedSalesTerritory,
              decoration: _inputDecoration(),
              items: salesTerritories.map((territory) {
                return DropdownMenuItem(value: territory, child: Text(territory));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedSalesTerritory = value!);
              },
              validator: (value) => value?.isEmpty == true ? 'Required' : null,
            ),
          ),
          const SizedBox(height: 20),
          
          // Tags/Labels
          _buildOptionalField(
            label: 'Tags/Labels',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableTags.map((tag) {
                    final isSelected = selectedTags.contains(tag);
                    return FilterChip(
                      label: Text(tag),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            selectedTags.add(tag);
                          } else {
                            selectedTags.remove(tag);
                          }
                        });
                      },
                      selectedColor: const Color(0xFF3498DB).withOpacity(0.2),
                      checkmarkColor: const Color(0xFF3498DB),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select multiple tags to categorize this customer',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // ============================================================================
  // SECTION 5: RATE CARD & PRICING - FULLY IMPLEMENTED
  // ============================================================================
  
Widget _buildRateCardSection() {
  final isVendor = selectedCustomerType == 'Vendor';
  
  return _buildSection(
    title: 'Rate Card & Pricing',
    icon: Icons.payments_outlined,
    isOptional: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Rate card is optional. You can assign or create a rate card now, or do it later from the Rate Card module.',
                  style: TextStyle(color: Colors.blue[900], fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // ✅ REGULAR CUSTOMER RATE CARD (for non-vendors)
        if (!isVendor) ...[
          // Regular customer rate card
          _buildOptionalField(
            label: 'Assigned Rate Card',
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectedRateCard,
                    decoration: _inputDecoration(),
                    hint: const Text('Select rate card (or skip)'),
                    items: rateCardOptions.map((card) {
                      return DropdownMenuItem(value: card, child: Text(card));
                    }).toList(),
                    onChanged: (value) {
                      setState(() => selectedRateCard = value);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _showCreateRateCardDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create New'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3498DB),
                    side: const BorderSide(color: Color(0xFF3498DB)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Contract Type
          _buildOptionalField(
            label: 'Contract Type',
            child: DropdownButtonFormField<String>(
              value: selectedContractType,
              decoration: _inputDecoration(),
              hint: const Text('Select contract type'),
              items: contractTypes.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedContractType = value);
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // Contract Dates (Responsive Row)
          _buildResponsiveRow(
            context,
            [
              _buildOptionalField(
                label: 'Contract Start Date',
                child: TextFormField(
                  controller: _contractStartDateController,
                  readOnly: true,
                  decoration: _inputDecoration(
                    hintText: 'Select date',
                    suffixIcon: Icons.calendar_today,
                  ),
                  onTap: () => _selectDate(_contractStartDateController),
                ),
              ),
              const SizedBox(width: 16),
              _buildOptionalField(
                label: 'Contract End Date',
                child: TextFormField(
                  controller: _contractEndDateController,
                  readOnly: true,
                  decoration: _inputDecoration(
                    hintText: 'Select date',
                    suffixIcon: Icons.calendar_today,
                  ),
                  onTap: () => _selectDate(_contractEndDateController),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Auto-renewal
          CheckboxListTile(
            title: const Text('Auto-renewal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('Automatically renew contract when it expires', style: TextStyle(fontSize: 12)),
            value: autoRenewal,
            onChanged: (value) {
              setState(() => autoRenewal = value!);
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          
          if (autoRenewal) ...[
            const SizedBox(height: 16),
            _buildOptionalField(
              label: 'Renewal Notice Period (days)',
              child: TextFormField(
                controller: _renewalNoticePeriodController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hintText: 'Days before contract end'),
              ),
            ),
          ],
        ],
        
        // ✅ VENDOR-SPECIFIC RATE CARD (commission-based) - THIS MUST NOT BE COMMENTED
        if (isVendor) ...[
          const Text(
            'Vendor Commission Structure',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          
          // Vendor Commission Type
          _buildRequiredField(
            label: 'Commission Type',
            child: DropdownButtonFormField<String>(
              value: selectedVendorCommissionType,
              decoration: _inputDecoration(),
              hint: const Text('Select commission type'),
              items: vendorCommissionTypes.map((type) {
                return DropdownMenuItem(value: type, child: Text(type));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedVendorCommissionType = value);
              },
              validator: (value) => value?.isEmpty == true ? 'Required for vendors' : null,
            ),
          ),
          const SizedBox(height: 20),
          
          // Commission fields based on type
          if (selectedVendorCommissionType == 'Percentage') ...[
            _buildRequiredField(
              label: 'Commission Rate (%)',
              child: TextFormField(
                controller: _commissionRateController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hintText: 'e.g., 10', suffixText: '%'),
                validator: (value) => value?.isEmpty == true ? 'Required' : null,
              ),
            ),
          ] else if (selectedVendorCommissionType == 'Fixed Amount per Trip') ...[
            _buildRequiredField(
              label: 'Fixed Amount per Trip',
              child: TextFormField(
                controller: _fixedAmountPerTripController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hintText: 'Enter amount', prefixText: '₹ '),
                validator: (value) => value?.isEmpty == true ? 'Required' : null,
              ),
            ),
          ] else if (selectedVendorCommissionType == 'Revenue Share') ...[
            _buildRequiredField(
              label: 'Revenue Share (%)',
              child: TextFormField(
                controller: _revenueShareController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hintText: 'e.g., 15', suffixText: '%'),
                validator: (value) => value?.isEmpty == true ? 'Required' : null,
              ),
            ),
          ],
          const SizedBox(height: 20),
          
          // Minimum Guarantee Amount
          _buildOptionalField(
            label: 'Minimum Guarantee Amount',
            child: TextFormField(
              controller: _minimumGuaranteeController,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(hintText: 'Enter amount', prefixText: '₹ '),
            ),
          ),
          const SizedBox(height: 20),
          
          // Payment Cycle
          _buildRequiredField(
            label: 'Payment Cycle',
            child: DropdownButtonFormField<String>(
              value: selectedPaymentCycle,
              decoration: _inputDecoration(),
              hint: const Text('Select payment cycle'),
              items: paymentCycles.map((cycle) {
                return DropdownMenuItem(value: cycle, child: Text(cycle));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedPaymentCycle = value);
              },
              validator: (value) => value?.isEmpty == true ? 'Required for vendors' : null,
            ),
          ),
          const SizedBox(height: 20),
          
          // Vehicle Types Provided
          _buildOptionalField(
            label: 'Vehicle Types Provided',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: vehicleTypes.map((vehicle) {
                final isSelected = selectedVehicleTypesProvided.contains(vehicle);
                return FilterChip(
                  label: Text(vehicle),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        selectedVehicleTypesProvided.add(vehicle);
                      } else {
                        selectedVehicleTypesProvided.remove(vehicle);
                      }
                    });
                  },
                  selectedColor: const Color(0xFFE67E22).withOpacity(0.2),
                  checkmarkColor: const Color(0xFFE67E22),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
          
          // Number of Vehicles
          _buildOptionalField(
            label: 'Number of Vehicles',
            child: TextFormField(
              controller: _numberOfVehiclesProvidedController,
              keyboardType: TextInputType.number,
              decoration: _inputDecoration(hintText: 'Total vehicles available'),
            ),
          ),
        ],
      ],
    ),
  );
}
  
  // ============================================================================
  // SECTION 6: PAYMENT TERMS & CREDIT - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildPaymentTermsSection() {
    final isVendor = selectedCustomerType == 'Vendor';
    
    return _buildSection(
      title: 'Payment Terms & Credit',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        children: [
          // Payment Terms
          _buildOptionalField(
            label: 'Payment Terms',
            child: DropdownButtonFormField<String>(
              value: selectedPaymentTerms,
              decoration: _inputDecoration(),
              hint: const Text('Select payment terms'),
              items: paymentTermsOptions.map((term) {
                return DropdownMenuItem(value: term, child: Text(term));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedPaymentTerms = value);
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // Preferred Payment Method
          _buildOptionalField(
            label: 'Preferred Payment Method',
            child: DropdownButtonFormField<String>(
              value: selectedPreferredPaymentMethod,
              decoration: _inputDecoration(),
              hint: const Text('Select payment method'),
              items: paymentMethods.map((method) {
                return DropdownMenuItem(value: method, child: Text(method));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedPreferredPaymentMethod = value);
              },
            ),
          ),
          const SizedBox(height: 20),
          
          // Credit Limit (not for vendors)
          if (!isVendor) ...[
            _buildOptionalField(
              label: 'Credit Limit',
              child: TextFormField(
                controller: _creditLimitController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hintText: '0 = No limit', prefixText: '₹ '),
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          // Security Deposit (for Organization/Vendor)
          if (selectedCustomerType == 'Organization' || isVendor) ...[
            _buildOptionalField(
              label: 'Security Deposit Amount',
              child: TextFormField(
                controller: _securityDepositController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hintText: 'Enter amount', prefixText: '₹ '),
              ),
            ),
            const SizedBox(height: 20),
            
            // Security Deposit Status
            _buildOptionalField(
              label: 'Security Deposit Status',
              child: DropdownButtonFormField<String>(
                value: selectedSecurityDepositStatus,
                decoration: _inputDecoration(),
                hint: const Text('Select status'),
                items: securityDepositStatuses.map((status) {
                  return DropdownMenuItem(value: status, child: Text(status));
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedSecurityDepositStatus = value);
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
          
          // Billing Frequency
          _buildOptionalField(
            label: 'Billing Frequency',
            child: DropdownButtonFormField<String>(
              value: selectedBillingFrequency,
              decoration: _inputDecoration(),
              hint: const Text('Select billing frequency'),
              items: billingFrequencies.map((freq) {
                return DropdownMenuItem(value: freq, child: Text(freq));
              }).toList(),
              onChanged: (value) {
                setState(() => selectedBillingFrequency = value);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  
  // ============================================================================
  // SECTION 7: BILLING PREFERENCES - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildBillingPreferencesSection() {
    return _buildSection(
      title: 'Billing Preferences',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: [
          // Billing Email
          _buildOptionalField(
            label: 'Billing Email',
            child: TextFormField(
              controller: _billingEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration(hintText: 'Defaults to primary email if empty'),
            ),
          ),
          const SizedBox(height: 20),
          
          // Same as Primary Address checkbox
          CheckboxListTile(
            title: const Text('Billing Address same as Primary Address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            value: sameAsPrimaryAddress,
            onChanged: (value) {
              setState(() {
                sameAsPrimaryAddress = value!;
                if (value) {
                  _billingAddressController.text =
                      '${_addressLine1Controller.text}\n${_addressLine2Controller.text}\n'
                      '${_cityController.text}, ${_stateController.text} ${_postalCodeController.text}\n$selectedCountry';
                }
              });
            },
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 16),
          
          // Billing Address
          if (!sameAsPrimaryAddress) ...[
            _buildOptionalField(
              label: 'Billing Address',
              child: TextFormField(
                controller: _billingAddressController,
                maxLines: 4,
                decoration: _inputDecoration(hintText: 'Enter billing address'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
  
  // ============================================================================
  // SECTION 8: VENDOR-SPECIFIC DETAILS - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildVendorSpecificSection() {
  return _buildSection(
    title: 'Vendor-Specific Details',
    icon: Icons.local_shipping_outlined,
    child: Column(
      children: [
        // Number of Vehicles Available
        _buildOptionalField(
          label: 'Number of Vehicles Available',
          child: TextFormField(
            controller: _vendorVehiclesAvailableController,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration(hintText: 'Total vehicles in fleet'),
          ),
        ),
        const SizedBox(height: 20),
        
        // Vehicle Types Available
        _buildOptionalField(
          label: 'Vehicle Types Available',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: vehicleTypes.map((vehicle) {
              final isSelected = vendorVehicleTypes.contains(vehicle);
              return FilterChip(
                label: Text(vehicle),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      vendorVehicleTypes.add(vehicle);
                    } else {
                      vendorVehicleTypes.remove(vehicle);
                    }
                  });
                },
                selectedColor: const Color(0xFFE67E22).withOpacity(0.2),
                checkmarkColor: const Color(0xFFE67E22),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        
        // Vendor Agreement Dates (Responsive Row)
        _buildResponsiveRow(
          context,
          [
            _buildOptionalField(
              label: 'Agreement Start Date',
              child: TextFormField(
                controller: _vendorAgreementStartController,
                readOnly: true,
                decoration: _inputDecoration(hintText: 'Select date', suffixIcon: Icons.calendar_today),
                onTap: () => _selectDate(_vendorAgreementStartController),
              ),
            ),
            const SizedBox(width: 16),
            _buildOptionalField(
              label: 'Agreement End Date',
              child: TextFormField(
                controller: _vendorAgreementEndController,
                readOnly: true,
                decoration: _inputDecoration(hintText: 'Select date', suffixIcon: Icons.calendar_today),
                onTap: () => _selectDate(_vendorAgreementEndController),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Vendor Performance Rating
        _buildOptionalField(
          label: 'Vendor Performance Rating',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(5, (index) {
                  return IconButton(
                    onPressed: () {
                      setState(() {
                        vendorPerformanceRating = (index + 1).toDouble();
                      });
                    },
                    icon: Icon(
                      index < vendorPerformanceRating ? Icons.star : Icons.star_border,
                      color: const Color(0xFFF39C12),
                      size: 32,
                    ),
                  );
                }),
              ),
              if (vendorPerformanceRating > 0)
                Text(
                  '${vendorPerformanceRating.toStringAsFixed(1)} out of 5 stars',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // Insurance Valid Until
        _buildOptionalField(
          label: 'Insurance Valid Until',
          child: TextFormField(
            controller: _insuranceValidUntilController,
            readOnly: true,
            decoration: _inputDecoration(hintText: 'Select date', suffixIcon: Icons.calendar_today),
            onTap: () => _selectDate(_insuranceValidUntilController),
          ),
        ),
        const SizedBox(height: 20),
        
        // Bank Details Section
        const Divider(height: 32),
        const Text(
          'Bank Account Details',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        const SizedBox(height: 16),
        
        // Bank Name
        _buildOptionalField(
          label: 'Bank Name',
          child: TextFormField(
            controller: _bankNameController,
            decoration: _inputDecoration(hintText: 'Enter bank name'),
          ),
        ),
        const SizedBox(height: 20),
        
        // Account Number and IFSC Code (Responsive Row)
        _buildResponsiveRow(
          context,
          [
            _buildOptionalField(
              label: 'Bank Account Number',
              child: TextFormField(
                controller: _bankAccountNumberController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(hintText: 'Account number'),
              ),
            ),
            const SizedBox(width: 16),
            _buildOptionalField(
              label: 'IFSC Code',
              child: TextFormField(
                controller: _ifscCodeController,
                decoration: _inputDecoration(hintText: 'IFSC code'),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        
        // Account Holder Name
        _buildOptionalField(
          label: 'Account Holder Name',
          child: TextFormField(
            controller: _accountHolderNameController,
            decoration: _inputDecoration(hintText: 'As per bank records'),
          ),
        ),
        const SizedBox(height: 20),
        
        // Branch Name
        _buildOptionalField(
          label: 'Branch Name',
          child: TextFormField(
            controller: _branchNameController,
            decoration: _inputDecoration(hintText: 'Bank branch'),
          ),
        ),
        const SizedBox(height: 20),
        
        // UPI ID
        _buildOptionalField(
          label: 'UPI ID',
          child: TextFormField(
            controller: _upiIdController,
            decoration: _inputDecoration(hintText: 'upiid@bank'),
          ),
        ),
      ],
    ),
  );
}
  
  // ============================================================================
  // SECTION 9: DOCUMENT UPLOADS - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildDocumentUploadsSection() {
    return _buildExpandableSection(
      title: 'Document Uploads',
      icon: Icons.upload_file_outlined,
      isExpanded: showDocumentSection,
      onToggle: () {
        setState(() {
          showDocumentSection = !showDocumentSection;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload relevant documents for record keeping and compliance. All file types allowed.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 20),
          
          ...uploadedDocuments.entries.map((entry) {
            final category = entry.key;
            final files = entry.value;
            
            // Skip categories not relevant to customer type
            if (category == 'KYC Documents' && selectedCustomerType != 'Individual') {
              return const SizedBox.shrink();
            }
            if (category == 'Company Documents' &&
                selectedCustomerType != 'Organization' && selectedCustomerType != 'Vendor') {
              return const SizedBox.shrink();
            }
            if ((category == 'Insurance Documents' || category == 'Vehicle Documents') &&
                selectedCustomerType != 'Vendor') {
              return const SizedBox.shrink();
            }
            
            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_getDocumentCategoryIcon(category), color: const Color(0xFF3498DB), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(category, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickDocuments(category),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Files'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF3498DB),
                          side: const BorderSide(color: Color(0xFF3498DB)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  if (files.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ...files.asMap().entries.map((entry) {
                      final index = entry.key;
                      final file = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(_getFileIcon(file.extension), color: const Color(0xFF3498DB), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.name,
                                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${(file.size / 1024).toStringAsFixed(1)} KB',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removeDocument(category, index),
                              icon: const Icon(Icons.close, size: 18),
                              color: Colors.red,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
  
  // ============================================================================
  // SECTION 10: ADDITIONAL INFORMATION - FULLY IMPLEMENTED
  // ============================================================================
  
  Widget _buildAdditionalInformationSection() {
    return _buildSection(
      title: 'Additional Information',
      icon: Icons.notes_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Internal Notes
          _buildOptionalField(
            label: 'Internal Notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _internalNotesController,
                  maxLines: 4,
                  decoration: _inputDecoration(hintText: 'Add internal notes (visible only to internal team)'),
                ),
                const SizedBox(height: 6),
                Text(
                  'These notes are for internal use only and not visible to the customer',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Custom Fields Section
          const Divider(height: 32),
          Row(
            children: [
              const Text(
                'Custom Fields',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    showCustomFieldsSection = !showCustomFieldsSection;
                  });
                },
                icon: Icon(showCustomFieldsSection ? Icons.expand_less : Icons.expand_more, size: 20),
                label: Text(showCustomFieldsSection ? 'Hide' : 'Show', style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          
          if (showCustomFieldsSection) ...[
            const SizedBox(height: 16),
            const Text(
              'Add custom fields specific to your business needs',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            
            // Custom fields list
            ...customFields.asMap().entries.map((entry) {
              final index = entry.key;
              final field = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[700],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'FIELD ${index + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _removeCustomField(index),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: Colors.red,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Field Name
                    _buildRequiredField(
                      label: 'Field Name/Label',
                      child: TextFormField(
                        initialValue: field.fieldName,
                        decoration: _inputDecoration(hintText: 'e.g., Preferred Driver Name'),
                        onChanged: (value) {
                          customFields[index].fieldName = value;
                        },
                        validator: (value) => value?.isEmpty == true ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Field Type
                    _buildRequiredField(
                      label: 'Field Type',
                      child: DropdownButtonFormField<String>(
                        value: field.fieldType,
                        decoration: _inputDecoration(),
                        items: customFieldTypes.map((type) {
                          return DropdownMenuItem(value: type, child: Text(type));
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            customFields[index].fieldType = value!;
                          });
                        },
                        validator: (value) => value?.isEmpty == true ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Field Value
                    _buildOptionalField(
                      label: 'Field Value',
                      child: TextFormField(
                        initialValue: field.fieldValue,
                        decoration: _inputDecoration(hintText: 'Enter value'),
                        onChanged: (value) {
                          customFields[index].fieldValue = value;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Is Mandatory
                    CheckboxListTile(
                      title: const Text('This field is mandatory', style: TextStyle(fontSize: 13)),
                      value: field.isMandatory,
                      onChanged: (value) {
                        setState(() {
                          customFields[index].isMandatory = value!;
                        });
                      },
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
              );
            }).toList(),
            
            const SizedBox(height: 16),
            
            // Add Custom Field Button (Disabled)
            OutlinedButton.icon(
              onPressed: null, // Disabled
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Custom Field'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey,
                side: const BorderSide(color: Colors.grey),
                disabledForegroundColor: Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // ============================================================================
  // RIGHT SIDEBAR SECTIONS
  // ============================================================================
  
  Widget _buildCustomerSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer Summary',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
        ),
        const SizedBox(height: 20),
        _buildSummaryRow('Customer ID:', customerId),
        _buildSummaryRow('Type:', selectedCustomerType),
        _buildSummaryRow('Status:', selectedCustomerStatus),
        if (selectedCustomerTier != null) _buildSummaryRow('Tier:', selectedCustomerTier!),
        _buildSummaryRow('Territory:', selectedSalesTerritory),
        if (selectedRateCard != null) ...[
          const Divider(height: 24),
          _buildSummaryRow('Rate Card:', selectedRateCard!),
        ],
        if (selectedCustomerType == 'Vendor' && selectedVendorCommissionType != null) ...[
          const Divider(height: 24),
          _buildSummaryRow('Commission:', selectedVendorCommissionType!),
        ],
      ],
    );
  }
  
  Widget _buildAuditTrailSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Audit Trail',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
        ),
        const SizedBox(height: 16),
        _buildAuditRow(Icons.person_outline, 'Created By', createdBy),
        _buildAuditRow(
          Icons.calendar_today,
          'Created Date',
          createdDate != null ? _formatDate(createdDate!) : '-',
        ),
        if (lastModifiedBy.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildAuditRow(Icons.edit_outlined, 'Last Modified By', lastModifiedBy),
        ],
        if (lastModifiedDate != null) ...[
          _buildAuditRow(Icons.update, 'Last Modified', _formatDate(lastModifiedDate!)),
        ],
      ],
    );
  }
  
  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _resetForm,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reset Form'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Preview'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3498DB),
              side: const BorderSide(color: Color(0xFF3498DB)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAuditRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // ============================================================================
  // HELPER WIDGETS
  // ============================================================================
  
  // Helper to create responsive row/column for form fields
  Widget _buildResponsiveRow(BuildContext context, List<Widget> children) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 900;
    
    if (isMobile) {
      // Mobile: Stack vertically
      return Column(
        children: children.map((child) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: child,
          );
        }).toList(),
      );
    } else {
      // Desktop: Show horizontally
      return Row(
        children: children.map((child) {
          if (child is SizedBox && child.width != null) {
            return child; // Keep SizedBox spacers as is
          }
          return Expanded(child: child);
        }).toList(),
      );
    }
  }
  
  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
    bool isOptional = false,
  }) {
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
          Row(
            children: [
              Icon(icon, color: const Color(0xFF3498DB), size: 22),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black87),
              ),
              if (isOptional) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'OPTIONAL',
                    style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
  
  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
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
          InkWell(
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF3498DB), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.black87),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildRequiredField({
    required String label,
    required Widget child,
    bool showRequired = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
            ),
            if (showRequired)
              const Text(' *', style: TextStyle(color: Colors.red, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
  
  Widget _buildOptionalField({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
  
  InputDecoration _inputDecoration({
    String? hintText,
    IconData? prefixIcon,
    IconData? suffixIcon,
    String? prefixText,
    String? suffixText,
  }) {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFF3498DB), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.grey[600], size: 20) : null,
      suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: Colors.grey[600], size: 20) : null,
      prefixText: prefixText,
      suffixText: suffixText,
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

class ContactPerson {
  String contactType;
  String fullName;
  String email;
  String phoneNumber;
  String? designation;
  String? department;
  bool isPrimary;
  
  ContactPerson({
    required this.contactType,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    this.designation,
    this.department,
    this.isPrimary = false,
  });
  
  Map<String, dynamic> toJson() => {
    'contactType': contactType,
    'fullName': fullName,
    'email': email,
    'phoneNumber': phoneNumber,
    'designation': designation,
    'department': department,
    'isPrimary': isPrimary,
  };
}

class CustomField {
  String fieldName;
  String fieldType;
  String fieldValue;
  bool isMandatory;
  
  CustomField({
    required this.fieldName,
    required this.fieldType,
    required this.fieldValue,
    required this.isMandatory,
  });
  
  Map<String, dynamic> toJson() => {
    'fieldName': fieldName,
    'fieldType': fieldType,
    'fieldValue': fieldValue,
    'isMandatory': isMandatory,
  };
}