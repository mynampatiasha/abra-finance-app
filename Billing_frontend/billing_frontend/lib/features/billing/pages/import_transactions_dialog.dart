// ============================================================================
// IMPORT TRANSACTIONS DIALOG
// ============================================================================
// File: lib/screens/banking/import_transactions_dialog.dart
// Features:
// - Upload CSV/Excel files
// - Select account to import to
// - Preview transactions before import
// - Map columns to fields
// - Validation and error handling
// ============================================================================

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;

class ImportTransactionsDialog extends StatefulWidget {
  const ImportTransactionsDialog({Key? key}) : super(key: key);

  @override
  State<ImportTransactionsDialog> createState() =>
      _ImportTransactionsDialogState();
}

class _ImportTransactionsDialogState extends State<ImportTransactionsDialog> {
  int _currentStep = 0;
  bool _isLoading = false;

  // Step 1: File Selection
  String? _selectedFileName;
  List<int>? _fileBytes;

  // Step 2: Account Selection
  String? _selectedAccountId;
  final List<Map<String, dynamic>> _accounts = [
    {
      'id': '1',
      'name': 'HP Fuel Card - Card ending 5678',
      'type': 'FUEL_CARD',
    },
    {
      'id': '2',
      'name': 'Shell Fleet Card - Card ending 9012',
      'type': 'FUEL_CARD',
    },
    {
      'id': '3',
      'name': 'ICICI Corporate Account - A/c xxxx3456',
      'type': 'BANK',
    },
    {
      'id': '4',
      'name': 'FASTag Account - 9876543210',
      'type': 'FASTAG',
    },
  ];

  // Step 3: Column Mapping
  Map<String, String?> _columnMapping = {
    'date': null,
    'amount': null,
    'description': null,
    'vehicle': null,
    'location': null,
  };

  List<String> _csvHeaders = [];
  List<List<String>> _previewData = [];

  // Step 4: Preview
  List<Map<String, dynamic>> _transactionsToImport = [];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            Expanded(
              child: Stepper(
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _onStepCancel,
                controlsBuilder: _buildStepControls,
                steps: [
                  Step(
                    title: const Text('Upload File'),
                    content: _buildStep1UploadFile(),
                    isActive: _currentStep >= 0,
                    state: _getStepState(0),
                  ),
                  Step(
                    title: const Text('Select Account'),
                    content: _buildStep2SelectAccount(),
                    isActive: _currentStep >= 1,
                    state: _getStepState(1),
                  ),
                  Step(
                    title: const Text('Map Columns'),
                    content: _buildStep3MapColumns(),
                    isActive: _currentStep >= 2,
                    state: _getStepState(2),
                  ),
                  Step(
                    title: const Text('Preview & Import'),
                    content: _buildStep4Preview(),
                    isActive: _currentStep >= 3,
                    state: _getStepState(3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF27AE60).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.upload_file,
            color: Color(0xFF27AE60),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import Transactions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Upload CSV or Excel file with your transactions',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  StepState _getStepState(int stepIndex) {
    if (stepIndex < _currentStep) {
      return StepState.complete;
    } else if (stepIndex == _currentStep) {
      return StepState.editing;
    } else {
      return StepState.indexed;
    }
  }

  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_selectedFileName == null) {
        _showErrorSnackbar('Please upload a file first');
        return;
      }
      setState(() {
        _currentStep++;
        _parseCsvFile();
      });
    } else if (_currentStep == 1) {
      if (_selectedAccountId == null) {
        _showErrorSnackbar('Please select an account');
        return;
      }
      setState(() {
        _currentStep++;
      });
    } else if (_currentStep == 2) {
      if (!_validateColumnMapping()) {
        _showErrorSnackbar('Please map all required columns');
        return;
      }
      setState(() {
        _currentStep++;
        _prepareTransactionsPreview();
      });
    } else if (_currentStep == 3) {
      _importTransactions();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Widget _buildStepControls(BuildContext context, ControlsDetails details) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: details.onStepCancel,
              child: const Text('Back'),
            ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: details.onStepContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(_currentStep == 3 ? 'Import' : 'Continue'),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // STEP 1: UPLOAD FILE
  // ============================================================================

  Widget _buildStep1UploadFile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Icon(
                Icons.cloud_upload,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                _selectedFileName ?? 'No file selected',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _selectedFileName != null
                      ? const Color(0xFF2C3E50)
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.file_upload),
                label: const Text('Choose File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Supported formats: CSV, Excel (.xlsx)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoBox(
          'File Format Tips',
          [
            'Date column should be in DD/MM/YYYY or YYYY-MM-DD format',
            'Amount column should contain only numbers (decimals allowed)',
            'First row should contain column headers',
            'Remove any summary rows at the top or bottom',
          ],
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (result != null) {
        setState(() {
          _selectedFileName = result.files.first.name;
          _fileBytes = result.files.first.bytes;
        });
      }
    } catch (e) {
      _showErrorSnackbar('Error picking file: $e');
    }
  }

  // ============================================================================
  // STEP 2: SELECT ACCOUNT
  // ============================================================================

  Widget _buildStep2SelectAccount() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select the account to import transactions into:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ..._accounts.map((account) {
          final isSelected = _selectedAccountId == account['id'];
          return InkWell(
            onTap: () {
              setState(() {
                _selectedAccountId = account['id'];
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[50] : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFF3498DB) : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getAccountIcon(account['type']),
                    color:
                        isSelected ? const Color(0xFF3498DB) : Colors.grey[600],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      account['name'],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFF2C3E50)
                            : Colors.grey[700],
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF3498DB),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  IconData _getAccountIcon(String type) {
    switch (type) {
      case 'FUEL_CARD':
        return Icons.local_gas_station;
      case 'BANK':
        return Icons.account_balance;
      case 'FASTAG':
        return Icons.toll;
      default:
        return Icons.account_balance_wallet;
    }
  }

  // ============================================================================
  // STEP 3: MAP COLUMNS
  // ============================================================================

  Widget _buildStep3MapColumns() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Map your CSV columns to transaction fields:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _buildColumnMappingRow('Date *', 'date'),
        const SizedBox(height: 12),
        _buildColumnMappingRow('Amount *', 'amount'),
        const SizedBox(height: 12),
        _buildColumnMappingRow('Description', 'description'),
        const SizedBox(height: 12),
        _buildColumnMappingRow('Vehicle Number', 'vehicle'),
        const SizedBox(height: 12),
        _buildColumnMappingRow('Location', 'location'),
        const SizedBox(height: 16),
        if (_previewData.isNotEmpty) _buildDataPreview(),
      ],
    );
  }

  Widget _buildColumnMappingRow(String label, String field) {
    return Row(
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _columnMapping[field],
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            hint: const Text('Select column'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('-- Not Mapped --'),
              ),
              ..._csvHeaders.map((header) {
                return DropdownMenuItem<String>(
                  value: header,
                  child: Text(header),
                );
              }).toList(),
            ],
            onChanged: (value) {
              setState(() {
                _columnMapping[field] = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDataPreview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Data Preview (first 5 rows):',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.grey[100]),
              columns: _csvHeaders.map((header) {
                return DataColumn(
                  label: Text(
                    header,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
              rows: _previewData.take(5).map((row) {
                return DataRow(
                  cells: row.map((cell) {
                    return DataCell(Text(cell));
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // STEP 4: PREVIEW & IMPORT
  // ============================================================================

  Widget _buildStep4Preview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ready to import ${_transactionsToImport.length} transactions',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.green[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import Summary',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• ${_transactionsToImport.length} transactions will be imported\n'
                      '• Account: ${_accounts.firstWhere((a) => a['id'] == _selectedAccountId)['name']}\n'
                      '• All transactions will be marked as "Uncategorized"',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Transaction Preview:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 250,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            itemCount: _transactionsToImport.take(10).length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final transaction = _transactionsToImport[index];
              return ListTile(
                dense: true,
                title: Text(
                  transaction['description'] ?? 'No description',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${transaction['date']} ${transaction['vehicle'] ?? ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                trailing: Text(
                  '₹${transaction['amount']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // HELPER FUNCTIONS
  // ============================================================================

  void _parseCsvFile() {
    // TODO: Implement actual CSV parsing
    // For now, mock data
    _csvHeaders = [
      'Transaction Date',
      'Card Number',
      'Amount',
      'Location',
      'Vehicle No',
      'Description'
    ];
    _previewData = [
      ['22/01/2026', '5678', '800.00', 'Shell Marathahalli', 'KA-01-AB-1234', 'Fuel'],
      ['23/01/2026', '5678', '1200.00', 'HP Whitefield', 'KA-05-CD-5678', 'Fuel'],
      ['23/01/2026', '5678', '600.00', 'Reliance HSR', '', 'Fuel'],
      ['24/01/2026', '5678', '950.00', 'Shell Koramangala', 'KA-01-AB-1234', 'Fuel'],
      ['24/01/2026', '5678', '1100.00', 'HP Electronic City', 'KA-05-CD-5678', 'Fuel'],
    ];
  }

  bool _validateColumnMapping() {
    return _columnMapping['date'] != null && _columnMapping['amount'] != null;
  }

  void _prepareTransactionsPreview() {
    // TODO: Map actual data based on column mapping
    _transactionsToImport = _previewData.map((row) {
      final dateIndex = _csvHeaders.indexOf(_columnMapping['date']!);
      final amountIndex = _csvHeaders.indexOf(_columnMapping['amount']!);
      final descIndex = _columnMapping['description'] != null
          ? _csvHeaders.indexOf(_columnMapping['description']!)
          : -1;
      final vehicleIndex = _columnMapping['vehicle'] != null
          ? _csvHeaders.indexOf(_columnMapping['vehicle']!)
          : -1;
      final locationIndex = _columnMapping['location'] != null
          ? _csvHeaders.indexOf(_columnMapping['location']!)
          : -1;

      return {
        'date': row[dateIndex],
        'amount': row[amountIndex],
        'description': descIndex >= 0 ? row[descIndex] : null,
        'vehicle': vehicleIndex >= 0 ? row[vehicleIndex] : null,
        'location': locationIndex >= 0 ? row[locationIndex] : null,
      };
    }).toList();
  }

  Future<void> _importTransactions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // TODO: Replace with actual API call
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_transactionsToImport.length} transactions imported successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackbar('Import failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildInfoBox(String title, List<String> points) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...points.map((point) => Padding(
                padding: const EdgeInsets.only(left: 28, top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• ',
                      style: TextStyle(color: Colors.blue[700]),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}