// ============================================================================
// BULK IMPORT INVOICES DIALOG — FINAL FIXED VERSION
// ============================================================================
// Backend response shape (confirmed from invoices.js):
//   {
//     success: true,
//     message: "Import complete. X invoices imported, Y failed.",
//     data: {
//       imported:     <number>,   ← success count
//       errors:       <number>,   ← fail count  (NUMBER, not array)
//       errorDetails: [           ← array of { row, error }
//         { row: 3, error: "Missing required fields: Customer Name" }
//       ]
//     }
//   }
// ============================================================================
// Fixes:
//   ✅ Reads exact keys: data.imported / data.errors / data.errorDetails
//   ✅ ConstrainedBox(maxHeight 88vh) + Flexible → SingleChildScrollView
//      Results section ALWAYS scrolls into view, never overflows screen
//   ✅ Confirmation dialog before upload starts
//   ✅ Summary cards: Total / Imported / Failed with correct counts
//   ✅ Scrollable error list capped at 160px
//   ✅ Close button shows "Done — X Invoice(s) Imported" on full success
//   ✅ debugPrint of raw response for console verification
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/api_service.dart';

// Brand palette — matches invoices_list_page.dart
const Color _kNavy   = Color(0xFF1e3a8a);
const Color _kPurple = Color(0xFF9B59B6);
const Color _kGreen  = Color(0xFF27AE60);
const Color _kBlue   = Color(0xFF2980B9);
const Color _kRed    = Color(0xFFE74C3C);

class BulkImportInvoicesDialog extends StatefulWidget {
  final VoidCallback onImportComplete;
  const BulkImportInvoicesDialog({Key? key, required this.onImportComplete})
      : super(key: key);

  @override
  State<BulkImportInvoicesDialog> createState() =>
      _BulkImportInvoicesDialogState();
}

class _BulkImportInvoicesDialogState
    extends State<BulkImportInvoicesDialog> {
  bool           _isDownloading = false;
  bool           _isUploading   = false;
  String?        _uploadedFileName;
  int            _importedCount = 0;
  int            _errorsCount   = 0;
  List<dynamic>  _errorDetails  = [];
  bool           _showResults   = false;
  bool           _importSuccess = false;

  // ── Download template ──────────────────────────────────────────────────────
  Future<void> _downloadTemplate() async {
    setState(() => _isDownloading = true);
    try {
      await ExportHelper.exportToExcel(
        filename: 'invoices_import_template',
        data: [
          [
            'Customer Name*', 'Customer Email*',
            'Invoice Date* (DD/MM/YYYY)', 'Due Date (DD/MM/YYYY)',
            'Payment Terms', 'Order Number', 'Item Details*',
            'Quantity*', 'Rate*', 'Discount',
            'Discount Type (percentage/amount)', 'GST Rate (%)',
            'Notes', 'Status (DRAFT/SENT/UNPAID/PAID)',
          ],
          [
            'Acme Corp', 'billing@acme.com', '15/01/2026', '14/02/2026',
            'Net 30', 'ORD-001', 'Fleet Management Services - January',
            '1', '25000.00', '5', 'percentage', '18',
            'Payment due within 30 days', 'DRAFT',
          ],
          [
            'TechCorp Solutions', 'accounts@techcorp.com',
            '20/01/2026', '04/02/2026', 'Net 15', 'ORD-002',
            'Driver Hire - 10 Days', '10', '1500.00', '0',
            'percentage', '18', '', 'SENT',
          ],
          [
            'INSTRUCTIONS: DELETE THIS ROW BEFORE UPLOADING',
            'Fields marked * are required', 'Date format: DD/MM/YYYY',
            'Terms: Due on Receipt / Net 15 / Net 30 / Net 45 / Net 60',
            'Status: DRAFT/SENT/UNPAID/PAID', 'GST Rate: number e.g. 18',
            '', '', '', '', '', '', '', '',
          ],
        ],
      );
      setState(() => _isDownloading = false);
      _toast('✅ Template downloaded!', success: true);
    } catch (e) {
      setState(() => _isDownloading = false);
      _toast('Download failed: $e', success: false);
    }
  }

  // ── Pick file → confirm → upload ──────────────────────────────────────────
  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
      allowMultiple: false,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.upload_file_rounded,
                color: _kBlue, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Confirm Import',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: _kGreen.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.insert_drive_file_rounded,
                    color: _kGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(file.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 14),
            Text(
              'Upload this file for processing?\n'
              'Imported invoices cannot be undone.',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: const Text('Yes, Import'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Start upload
    setState(() {
      _uploadedFileName = file.name;
      _isUploading      = true;
      _showResults      = false;
    });

    try {
      final apiService = ApiService();
      final headers    = await apiService.getHeaders();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${apiService.baseUrl}/api/finance/invoices/import/bulk'),
      );
      headers.forEach((k, v) {
        if (k.toLowerCase() != 'content-type') request.headers[k] = v;
      });

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
            'file', file.bytes!, filename: file.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
            'file', file.path!, filename: file.name));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      // Log raw response — verify in console
      debugPrint('📥 Import status : ${response.statusCode}');
      debugPrint('📥 Import body   : ${response.body}');

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      // ── Extract exact backend keys ─────────────────────────────────────────
      // Backend: { success, message, data: { imported, errors, errorDetails } }
      final data         = decoded['data'] as Map<String, dynamic>? ?? {};
      final imported     = (data['imported']     as num?)?.toInt() ?? 0;
      final errorsCount  = (data['errors']        as num?)?.toInt() ?? 0;
      final errorDetails = (data['errorDetails']  as List?)         ?? [];

      setState(() {
        _isUploading   = false;
        _importedCount = imported;
        _errorsCount   = errorsCount;
        _errorDetails  = errorDetails;
        _showResults   = true;
        _importSuccess = decoded['success'] == true;
      });

      if (_importSuccess) {
        _toast(
          '✅ $imported invoice(s) imported'
          '${errorsCount > 0 ? ', $errorsCount failed' : ''}.',
          success: true,
        );
        widget.onImportComplete();
      } else {
        _toast(
          decoded['message']?.toString() ??
              'Import failed (status ${response.statusCode})',
          success: false,
        );
      }
    } catch (e) {
      debugPrint('❌ Import error: $e');
      setState(() { _isUploading = false; _showResults = false; });
      _toast('Failed to import: $e', success: false);
    }
  }

  void _toast(String msg, {required bool success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(success ? Icons.check_circle_outline : Icons.error_outline,
            color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: success ? _kGreen : Colors.red[700],
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: success ? 3 : 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ==========================================================================
  //  BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width > 620
              ? 580
              : MediaQuery.of(context).size.width * 0.92,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoBox(),
                    const SizedBox(height: 20),
                    _buildStep(
                      step: '1', color: _kBlue,
                      icon: Icons.download_rounded,
                      title: 'Download Template',
                      subtitle: 'Get the Excel template with required columns and sample data.',
                      buttonLabel: 'Download Template',
                      isLoading: _isDownloading,
                      onPressed: (_isDownloading || _isUploading)
                          ? null : _downloadTemplate,
                    ),
                    const SizedBox(height: 14),
                    _buildStep(
                      step: '2', color: _kGreen,
                      icon: Icons.upload_rounded,
                      title: 'Upload Filled File',
                      subtitle: 'Fill the template and upload to import your invoices.',
                      buttonLabel: 'Select Excel / CSV File',
                      isLoading: _isUploading,
                      onPressed: (_isDownloading || _isUploading)
                          ? null : _pickAndUpload,
                    ),
                    if (_uploadedFileName != null) ...[
                      const SizedBox(height: 14),
                      _buildFileChip(),
                    ],
                    if (_showResults) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 20),
                      _buildResults(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(28, 22, 18, 18),
    decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: _kPurple.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.upload_file_rounded,
            color: _kPurple, size: 24),
      ),
      const SizedBox(width: 14),
      const Expanded(
          child: Text('Bulk Import Invoices',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold))),
      IconButton(
        onPressed: _isUploading ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close),
        tooltip: 'Close',
      ),
    ]),
  );

  Widget _buildInfoBox() => Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: _kBlue.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBlue.withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.info_outline, color: _kBlue, size: 18),
        const SizedBox(width: 8),
        Text('How to Import',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _kBlue, fontSize: 14)),
      ]),
      const SizedBox(height: 10),
      const Text(
        '1. Download the sample Excel template\n'
        '2. Fill in invoice data (fields marked * are required)\n'
        '3. Save as .xlsx or .csv\n'
        '4. Upload — the server processes each row\n'
        '5. Review import results below',
        style: TextStyle(fontSize: 13, height: 1.65),
      ),
    ]),
  );

  Widget _buildStep({
    required String step, required Color color, required IconData icon,
    required String title, required String subtitle,
    required String buttonLabel, required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    final circle = Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(child: Text(step,
          style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.bold, fontSize: 15))),
    );
    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: isLoading
          ? const SizedBox(width: 15, height: 15,
              child: CircularProgressIndicator(strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
          : Icon(icon, size: 15),
      label: Text(isLoading ? 'Please wait…' : buttonLabel,
          style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          circle, const SizedBox(width: 14),
          Expanded(child: textBlock),
          const SizedBox(width: 12),
          button,
        ]);
      }),
    );
  }

  Widget _buildFileChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
        color: _kGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGreen.withOpacity(0.3))),
    child: Row(children: [
      const Icon(Icons.check_circle_outline_rounded,
          color: _kGreen, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(_uploadedFileName!,
          style: const TextStyle(fontWeight: FontWeight.w600,
              color: _kGreen, fontSize: 13))),
      if (_isUploading) ...[
        const SizedBox(width: 8),
        const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_kGreen))),
        const SizedBox(width: 8),
        Text('Uploading…', style: TextStyle(
            fontSize: 12, color: _kGreen.withOpacity(0.7))),
      ],
    ]),
  );

  Widget _buildResults() {
    final total      = _importedCount + _errorsCount;
    final allSuccess = _errorsCount == 0 && _importedCount > 0;
    final allFailed  = _importedCount == 0 && _errorsCount > 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Title
      Row(children: [
        Icon(allFailed
            ? Icons.cancel_rounded : Icons.check_circle_rounded,
            color: allFailed ? _kRed : _kGreen, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(
          allSuccess ? 'Import Successful!'
              : allFailed ? 'Import Failed'
                          : 'Import Completed with Issues',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
              color: allFailed ? _kRed : const Color(0xFF2C3E50)),
        )),
      ]),
      const SizedBox(height: 16),

      // Summary cards
      Row(children: [
        Expanded(child: _summaryCard(
            label: 'Total', value: '$total',
            icon: Icons.summarize_outlined, color: _kBlue)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard(
            label: 'Imported', value: '$_importedCount',
            icon: Icons.check_circle_outline_rounded, color: _kGreen)),
        const SizedBox(width: 10),
        Expanded(child: _summaryCard(
            label: 'Failed', value: '$_errorsCount',
            icon: Icons.cancel_outlined,
            color: _errorsCount > 0 ? _kRed : Colors.grey)),
      ]),

      // Error detail list
      if (_errorDetails.isNotEmpty) ...[
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _kRed.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kRed.withOpacity(0.25))),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: _kRed, size: 18),
              const SizedBox(width: 8),
              Text('${_errorDetails.length} row(s) failed:',
                  style: TextStyle(fontWeight: FontWeight.w700,
                      color: _kRed, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _errorDetails.map<Widget>((e) {
                    final rowNum = e is Map
                        ? (e['row'] ?? '?').toString() : '?';
                    final errMsg = e is Map
                        ? (e['error'] ?? e['message'] ?? e.toString()).toString()
                        : e.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Icon(Icons.circle, size: 6,
                                color: _kRed.withOpacity(0.6)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: RichText(text: TextSpan(
                            style: TextStyle(fontSize: 12,
                                color: Colors.red[800]),
                            children: [
                              TextSpan(text: 'Row $rowNum: ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              TextSpan(text: errMsg),
                            ],
                          ))),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 20),

      // Close / Done button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            allSuccess ? Icons.done_all_rounded : Icons.close_rounded,
            size: 16),
          label: Text(
            allSuccess
                ? 'Done — $_importedCount Invoice(s) Imported'
                : 'Close',
            style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: allSuccess ? _kGreen : _kNavy,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  Widget _summaryCard({
    required String label, required String value,
    required IconData icon, required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 22,
            fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            textAlign: TextAlign.center),
      ]),
    );
  }
}