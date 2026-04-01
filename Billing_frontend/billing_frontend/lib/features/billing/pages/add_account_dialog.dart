// ============================================================================
// ADD ACCOUNT DIALOG - WITH CUSTOM ACCOUNT TYPE SUPPORT
// ============================================================================
// File: lib/screens/banking/add_account_dialog.dart
// Features:
// - Predefined account types (Fuel Card, Bank, FASTag, Petty Cash, Driver Advance)
// - Custom "Other" account type that auto-creates new types
// - Custom types are saved and reusable across the app
// - Dynamic custom fields for OTHER type
// - All fields optional except account name and type
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/add_account_service.dart';

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({Key? key}) : super(key: key);

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final AddAccountService _accountService = AddAccountService();
  
  // Form Fields
  String _selectedAccountType = 'FUEL_CARD';
  final TextEditingController _accountNameController = TextEditingController();
  final TextEditingController _holderNameController = TextEditingController();
  final TextEditingController _openingBalanceController = TextEditingController();
  final TextEditingController _providerNameController = TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _ifscCodeController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _fastagNumberController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  
  // Custom type fields
  final TextEditingController _customTypeNameController = TextEditingController();
  
  // Bank details for other account types
  final TextEditingController _linkedBankNameController = TextEditingController();
  final TextEditingController _linkedAccountNumberController = TextEditingController();
  final TextEditingController _linkedIfscCodeController = TextEditingController();
  
  bool _isLoading = false;
  bool _showLinkedBankDetails = false;
  
  // Custom fields for OTHER type
  List<Map<String, TextEditingController>> _customFields = [];

  // Predefined account types
  final List<Map<String, dynamic>> _predefinedAccountTypes = [
    {
      'value': 'FUEL_CARD',
      'label': 'Fuel Card',
      'icon': Icons.local_gas_station,
      'color': Colors.blue,
    },
    {
      'value': 'BANK',
      'label': 'Bank Account',
      'icon': Icons.account_balance,
      'color': Colors.green,
    },
    {
      'value': 'FASTAG',
      'label': 'FASTag Account',
      'icon': Icons.toll,
      'color': Colors.orange,
    },
    {
      'value': 'PETTY_CASH',
      'label': 'Petty Cash',
      'icon': Icons.payments,
      'color': Colors.purple,
    },
    {
      'value': 'DRIVER_ADVANCE',
      'label': 'Driver Advance',
      'icon': Icons.person,
      'color': Colors.indigo,
    },
    {
      'value': 'OTHER',
      'label': 'Other / Custom',
      'icon': Icons.add_circle_outline,
      'color': Colors.grey,
    },
  ];

  // Loaded custom account types
  List<Map<String, dynamic>> _customAccountTypes = [];
  
  // Combined account types
  List<Map<String, dynamic>> _accountTypes = [];

  @override
  void initState() {
    super.initState();
    _loadCustomAccountTypes();
  }

  @override
  void dispose() {
    _accountNameController.dispose();
    _holderNameController.dispose();
    _openingBalanceController.dispose();
    _providerNameController.dispose();
    _cardNumberController.dispose();
    _accountNumberController.dispose();
    _ifscCodeController.dispose();
    _bankNameController.dispose();
    _fastagNumberController.dispose();
    _vehicleNumberController.dispose();
    _customTypeNameController.dispose();
    _linkedBankNameController.dispose();
    _linkedAccountNumberController.dispose();
    _linkedIfscCodeController.dispose();
    
    // Dispose custom field controllers
    for (var field in _customFields) {
      field['name']?.dispose();
      field['value']?.dispose();
    }
    
    super.dispose();
  }

  Future<void> _loadCustomAccountTypes() async {
    try {
      final customTypes = await _accountService.getCustomAccountTypes();
      
      setState(() {
        _customAccountTypes = customTypes.map((type) {
          return {
            'value': type['typeName'],
            'label': type['displayName'],
            'icon': _getIconFromString(type['icon'] ?? 'add_circle_outline'),
            'color': _getColorFromHex(type['color'] ?? '#808080'),
            'isCustom': true,
          };
        }).toList();
        
        // Combine predefined and custom types
        _accountTypes = [..._predefinedAccountTypes, ..._customAccountTypes];
      });
    } catch (e) {
      // If loading fails, just use predefined types
      setState(() {
        _accountTypes = _predefinedAccountTypes;
      });
    }
  }

  IconData _getIconFromString(String iconName) {
    final iconMap = {
      'local_gas_station': Icons.local_gas_station,
      'account_balance': Icons.account_balance,
      'toll': Icons.toll,
      'payments': Icons.payments,
      'person': Icons.person,
      'add_circle_outline': Icons.add_circle_outline,
      'wallet': Icons.account_balance_wallet,
      'credit_card': Icons.credit_card,
      'phone_android': Icons.phone_android,
      'qr_code': Icons.qr_code,
    };
    return iconMap[iconName] ?? Icons.add_circle_outline;
  }

  Color _getColorFromHex(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceAll('#', '0xFF')));
    } catch (e) {
      return Colors.grey;
    }
  }

  void _addCustomField() {
    setState(() {
      _customFields.add({
        'name': TextEditingController(),
        'value': TextEditingController(),
      });
    });
  }

  void _removeCustomField(int index) {
    setState(() {
      _customFields[index]['name']?.dispose();
      _customFields[index]['value']?.dispose();
      _customFields.removeAt(index);
    });
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Additional validation for OTHER type
    if (_selectedAccountType == 'OTHER' && _customTypeNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a custom account type name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Prepare account data
      final accountData = {
        'accountType': _selectedAccountType,
        'accountName': _accountNameController.text.trim(),
        'holderName': _holderNameController.text.trim().isNotEmpty 
            ? _holderNameController.text.trim() 
            : null,
        'openingBalance': _openingBalanceController.text.trim().isNotEmpty
            ? double.parse(_openingBalanceController.text.trim())
            : 0.0,
      };

      // Add custom type name if OTHER is selected
      if (_selectedAccountType == 'OTHER') {
        accountData['customTypeName'] = _customTypeNameController.text.trim();
        
        // Add custom fields
        if (_customFields.isNotEmpty) {
          accountData['customFields'] = _customFields.map((field) {
            return {
              'fieldName': field['name']!.text.trim(),
              'fieldValue': field['value']!.text.trim(),
            };
          }).toList();
        }
      }

      // Add type-specific fields
      switch (_selectedAccountType) {
        case 'FUEL_CARD':
          accountData['providerName'] = _providerNameController.text.trim().isNotEmpty
              ? _providerNameController.text.trim()
              : null;
          accountData['cardNumber'] = _cardNumberController.text.trim().isNotEmpty
              ? _cardNumberController.text.trim()
              : null;
          break;
        case 'BANK':
          accountData['bankName'] = _bankNameController.text.trim().isNotEmpty
              ? _bankNameController.text.trim()
              : null;
          accountData['accountNumber'] = _accountNumberController.text.trim().isNotEmpty
              ? _accountNumberController.text.trim()
              : null;
          accountData['ifscCode'] = _ifscCodeController.text.trim().isNotEmpty
              ? _ifscCodeController.text.trim()
              : null;
          break;
        case 'FASTAG':
          accountData['fastagNumber'] = _fastagNumberController.text.trim().isNotEmpty
              ? _fastagNumberController.text.trim()
              : null;
          accountData['vehicleNumber'] = _vehicleNumberController.text.trim().isNotEmpty
              ? _vehicleNumberController.text.trim()
              : null;
          break;
      }

      // Add linked bank details if provided (for non-bank accounts)
      if (_showLinkedBankDetails && _selectedAccountType != 'BANK') {
        accountData['linkedBankDetails'] = {
          'bankName': _linkedBankNameController.text.trim().isNotEmpty
              ? _linkedBankNameController.text.trim()
              : null,
          'accountNumber': _linkedAccountNumberController.text.trim().isNotEmpty
              ? _linkedAccountNumberController.text.trim()
              : null,
          'ifscCode': _linkedIfscCodeController.text.trim().isNotEmpty
              ? _linkedIfscCodeController.text.trim()
              : null,
        };
      }

      // Call service to save account
      final result = await _accountService.addAccount(accountData);

      if (mounted) {
        Navigator.pop(context, result);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 750,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3498DB).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: Color(0xFF3498DB),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Add Payment Account',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Account Type Selection
              Row(
                children: const [
                  Text(
                    'Account Type',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.info_outline, size: 16, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _accountTypes.map((type) {
                  final isSelected = _selectedAccountType == type['value'];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedAccountType = type['value'];
                        _showLinkedBankDetails = false;
                        
                        // Clear custom fields when switching away from OTHER
                        if (_selectedAccountType != 'OTHER') {
                          for (var field in _customFields) {
                            field['name']?.dispose();
                            field['value']?.dispose();
                          }
                          _customFields.clear();
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (type['color'] as Color).withOpacity(0.1)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? (type['color'] as Color)
                              : Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            type['icon'],
                            color: isSelected
                                ? (type['color'] as Color)
                                : Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            type['label'],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? (type['color'] as Color)
                                  : Colors.grey[700],
                            ),
                          ),
                          if (type['isCustom'] == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Custom',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue[900],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Dynamic Form Fields based on Account Type
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Custom Type Name Field (only for OTHER)
                      if (_selectedAccountType == 'OTHER') ...[
                        TextFormField(
                          controller: _customTypeNameController,
                          decoration: InputDecoration(
                            labelText: 'Custom Account Type Name *',
                            hintText: 'e.g., Digital Wallet, Corporate Card, UPI',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.edit),
                            helperText: 'This will be saved for future use',
                          ),
                          validator: (value) {
                            if (_selectedAccountType == 'OTHER' &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Please enter a custom account type name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      _buildAccountNameField(),
                      const SizedBox(height: 16),
                      _buildHolderNameField(),
                      const SizedBox(height: 16),
                      _buildOpeningBalanceField(),
                      const SizedBox(height: 16),
                      ..._buildTypeSpecificFields(),
                      
                      // Custom Fields Section (only for OTHER)
                      if (_selectedAccountType == 'OTHER') ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Text(
                              'Custom Fields (Optional)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _addCustomField,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Field'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF3498DB),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._buildCustomFieldsWidgets(),
                      ],
                      
                      // Optional Bank Account Details for non-bank accounts
                      if (_selectedAccountType != 'BANK') ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Checkbox(
                              value: _showLinkedBankDetails,
                              onChanged: (value) {
                                setState(() {
                                  _showLinkedBankDetails = value ?? false;
                                });
                              },
                            ),
                            const Expanded(
                              child: Text(
                                'Link to Bank Account (Optional)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_showLinkedBankDetails) ...[
                          const SizedBox(height: 16),
                          ..._buildLinkedBankFields(),
                        ],
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3498DB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Add Account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountNameField() {
    return TextFormField(
      controller: _accountNameController,
      decoration: InputDecoration(
        labelText: 'Account Name *',
        hintText: 'e.g., HP Fuel Card - Primary',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        prefixIcon: const Icon(Icons.label),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter account name';
        }
        return null;
      },
    );
  }

  Widget _buildHolderNameField() {
    return TextFormField(
      controller: _holderNameController,
      decoration: InputDecoration(
        labelText: 'Account Holder Name',
        hintText: 'Name of the account holder',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        prefixIcon: const Icon(Icons.person_outline),
      ),
    );
  }

  Widget _buildOpeningBalanceField() {
    return TextFormField(
      controller: _openingBalanceController,
      decoration: InputDecoration(
        labelText: 'Opening Balance',
        hintText: '0.00',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        prefixIcon: const Icon(Icons.currency_rupee),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
    );
  }

  List<Widget> _buildCustomFieldsWidgets() {
    if (_customFields.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add custom fields to store additional information specific to this account type',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return _customFields.asMap().entries.map((entry) {
      final index = entry.key;
      final field = entry.value;
      
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: field['name'],
                    decoration: InputDecoration(
                      labelText: 'Field Name',
                      hintText: 'e.g., Card Number, Provider',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      fillColor: Colors.white,
                      filled: true,
                      prefixIcon: const Icon(Icons.label_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => _removeCustomField(index),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red[700],
                  tooltip: 'Remove field',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: field['value'],
              decoration: InputDecoration(
                labelText: 'Field Value',
                hintText: 'Enter value',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                fillColor: Colors.white,
                filled: true,
                prefixIcon: const Icon(Icons.edit_outlined),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
  List<Widget> _buildTypeSpecificFields() {
    switch (_selectedAccountType) {
      case 'FUEL_CARD':
        return [
          TextFormField(
            controller: _providerNameController,
            decoration: InputDecoration(
              labelText: 'Provider Name',
              hintText: 'e.g., HP, Shell, Indian Oil',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.business),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _cardNumberController,
            decoration: InputDecoration(
              labelText: 'Card Number',
              hintText: 'Last 4 digits or full number',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.credit_card),
            ),
          ),
        ];

      case 'BANK':
        return [
          TextFormField(
            controller: _bankNameController,
            decoration: InputDecoration(
              labelText: 'Bank Name',
              hintText: 'e.g., ICICI Bank, HDFC Bank',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.account_balance),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _accountNumberController,
            decoration: InputDecoration(
              labelText: 'Account Number',
              hintText: 'Bank account number',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.pin),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _ifscCodeController,
            decoration: InputDecoration(
              labelText: 'IFSC Code',
              hintText: 'e.g., ICIC0001234',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.qr_code),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
        ];

      case 'FASTAG':
        return [
          TextFormField(
            controller: _fastagNumberController,
            decoration: InputDecoration(
              labelText: 'FASTag Number',
              hintText: 'FASTag ID',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _vehicleNumberController,
            decoration: InputDecoration(
              labelText: 'Vehicle Number',
              hintText: 'e.g., KA-01-AB-1234',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: const Icon(Icons.directions_car),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
        ];

      case 'PETTY_CASH':
      case 'DRIVER_ADVANCE':
        return [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Basic account details are sufficient. You can optionally link this to a bank account below.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];

      case 'OTHER':
        return [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tips_and_updates, color: Colors.purple[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create Your Custom Account Type',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.purple[900],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'This account type will be saved and available for future use. You can add custom fields below to store specific information.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.purple[800],
                  ),
                ),
              ],
            ),
          ),
        ];

      default:
        // For custom account types loaded from backend
        return [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'This is a previously created custom account type. Add the basic details and any additional information needed.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green[900],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ];
    }
  }

  List<Widget> _buildLinkedBankFields() {
    return [
      const Text(
        'Linked Bank Account Details',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2C3E50),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _linkedBankNameController,
        decoration: InputDecoration(
          labelText: 'Bank Name',
          hintText: 'e.g., ICICI Bank, HDFC Bank',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          prefixIcon: const Icon(Icons.account_balance),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _linkedAccountNumberController,
        decoration: InputDecoration(
          labelText: 'Account Number',
          hintText: 'Bank account number',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          prefixIcon: const Icon(Icons.pin),
        ),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _linkedIfscCodeController,
        decoration: InputDecoration(
          labelText: 'IFSC Code',
          hintText: 'e.g., ICIC0001234',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          prefixIcon: const Icon(Icons.qr_code),
        ),
        textCapitalization: TextCapitalization.characters,
      ),
    ];
  }
}