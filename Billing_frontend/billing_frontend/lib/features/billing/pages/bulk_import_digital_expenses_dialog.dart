import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../app/config/api_config.dart';
import '../../../../../core/finance_secure_storage.dart';
import 'package:csv/csv.dart';

class BulkImportDigitalExpensesDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  const BulkImportDigitalExpensesDialog({Key? key, required this.onImportComplete}) : super(key: key);

  @override
  State<BulkImportDigitalExpensesDialog> createState() => _BulkImportDigitalExpensesDialogState();
}

class _BulkImportDigitalExpensesDialogState extends State<BulkImportDigitalExpensesDialog> {
  bool _isUploading = false;
  String? _selectedFileName;
  List<Map<String, dynamic>> _parsedExpenses = [];

  Future<void> _downloadTemplate() async {
    final header = 'Date,Amount,Payment Method,Amount Paid To,Amount In Words,On Account Of,Expense Category,Received By\n';
    final sample = '2026-05-29,150.00,Cash,John Doe,One Hundred Fifty,Office supplies,Office Supplies,Jane Doe\n';
    final csvContent = header + sample;

    if (kIsWeb) {
      final blob = html.Blob([csvContent], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'digital_expenses_template.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      // For desktop/mobile, you'd save it via path_provider, but web is assumed as per similar files
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Template downloaded!'), backgroundColor: Colors.green));
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() { _selectedFileName = file.name; });

        if (file.bytes != null) {
          final csvString = utf8.decode(file.bytes!);
          final List<List<dynamic>> rows = const CsvToListConverter().convert(csvString);
          
          if (rows.length > 1) {
            _parsedExpenses.clear();
            for (int i = 1; i < rows.length; i++) {
              final row = rows[i];
              if (row.length >= 7) {
                _parsedExpenses.add({
                  'date': row[0].toString(),
                  'amount': double.tryParse(row[1].toString()) ?? 0,
                  'paymentMethod': row[2].toString(),
                  'amountPaidTo': row[3].toString(),
                  'amountInWords': row[4].toString(),
                  'onAccountOf': row[5].toString(),
                  'expenseCategory': row[6].toString(),
                  'receivedBy': row.length > 7 ? row[7].toString() : '',
                });
              }
            }
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
    }
  }

  Future<void> _uploadData() async {
    if (_parsedExpenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No valid data found in CSV')));
      return;
    }

    setState(() => _isUploading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final branchHdr = await FinanceSecureStorage.getBranchHeader();
      final orgHdr = await FinanceSecureStorage.getOrgHeader();

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/finance/digital-expenses/bulk-import');
      final response = await http.post(uri,
        headers: {
          'Authorization': 'Bearer $token',
          'x-branch-ids': branchHdr,
          'x-org-ids': orgHdr,
          'Content-Type': 'application/json'
        },
        body: json.encode({ 'expenses': _parsedExpenses }),
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success']) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: Colors.green));
        widget.onImportComplete();
        if (mounted) Navigator.pop(context);
      } else {
        throw Exception(data['message'] ?? 'Import failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Digital Expenses'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Upload a CSV file containing your digital expenses. You can add proof images/documents later by editing individual expenses.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _downloadTemplate,
              icon: const Icon(Icons.download),
              label: const Text('Download CSV Template'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue[700]),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: Colors.grey[50]),
              child: Column(
                children: [
                  Icon(Icons.upload_file, size: 40, color: Colors.grey[400]),
                  const SizedBox(height: 10),
                  Text(_selectedFileName ?? 'No file selected', style: TextStyle(fontWeight: FontWeight.w500, color: _selectedFileName != null ? Colors.black87 : Colors.grey[600])),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _pickFile, child: const Text('Select CSV File')),
                ],
              ),
            ),
            if (_parsedExpenses.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Ready to import ${_parsedExpenses.length} expenses.', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _isUploading || _parsedExpenses.isEmpty ? null : _uploadData,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1e3a8a), foregroundColor: Colors.white),
          child: _isUploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Import Data'),
        ),
      ],
    );
  }
}
