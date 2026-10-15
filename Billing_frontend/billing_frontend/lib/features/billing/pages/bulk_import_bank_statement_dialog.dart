import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// BULK IMPORT BANK STATEMENT DIALOG
// ============================================================================
// File: lib/screens/banking/bulk_import_bank_statement_dialog.dart
//
// 2-step pattern identical to BulkImportInvoicesDialog:
//   Step 1 → Download CSV template
//   Step 2 → Upload filled CSV → backend saves as ProviderTransactions
//
// CSV columns (from sample_bankstatement.csv):
//   Date | Description | Reference Number | Deposit | Withdrawal | Balance
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;
import '../../../core/services/api_service.dart';

const Color _kNavy = Color(0xFF1e3a8a);
const Color _kGreen = Color(0xFF27AE60);
const Color _kBlue = Color(0xFF2980B9);
const Color _kRed = Color(0xFFE74C3C);
const Color _kOrange = Color(0xFFE67E22);
const Color _kPurple = Color(0xFF9B59B6);

class BulkImportBankStatementDialog extends StatefulWidget {
  final String accountId;
  final String accountName;
  final VoidCallback onImportComplete;

  const BulkImportBankStatementDialog({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.onImportComplete,
  }) : super(key: key);

  @override
  State<BulkImportBankStatementDialog> createState() =>
      _BulkImportBankStatementDialogState();
}

class _BulkImportBankStatementDialogState
    extends State<BulkImportBankStatementDialog> {
  bool _isDownloading = false;
  bool _isUploading = false;
  String? _uploadedFileName;
  int _importedCount = 0;
  int _skippedCount = 0;
  int _errorsCount = 0;
  List<dynamic> _errorDetails = [];
  bool _showResults = false;
  bool _importSuccess = false;

  // The format the dates in the user's file are written in. Sent to the server
  // so a date is never guessed (03/10/2026 = 3 Oct or 10 Mar?). 2026-10-03
  // (year-month-day) is unambiguous and always accepted, whatever is chosen.
  static const List<String> _dateFormats = [
    'DD/MM/YYYY',
    'MM/DD/YYYY',
    'YYYY-MM-DD',
    'DD-MM-YYYY',
    'MM-DD-YYYY',
    'DD-MMM-YYYY',
  ];
  static const Map<String, String> _dateFormatExamples = {
    'DD/MM/YYYY': '03/10/2026 = 3 October 2026',
    'MM/DD/YYYY': '10/03/2026 = 3 October 2026',
    'YYYY-MM-DD': '2026-10-03 = 3 October 2026',
    'DD-MM-YYYY': '03-10-2026 = 3 October 2026',
    'MM-DD-YYYY': '10-03-2026 = 3 October 2026',
    'DD-MMM-YYYY': '03-Oct-2026 = 3 October 2026',
  };
  String _dateFormat = 'DD/MM/YYYY';

  // ── Download CSV template ─────────────────────────────────────────────────
  Future<void> _downloadTemplate() async {
    setState(() => _isDownloading = true);
    try {
      const csvContent =
          '''Date,Withdrawals,Deposits,Payee,Description,Reference Number
2026-03-01,0,0,,Opening Balance,
2026-03-05,0,50000.00,,Salary Credit,SAL-001
2026-03-10,2500.00,0,Power Corp,Electricity Bill,REF-101
2026-03-15,0,15000.00,Acme Corp,Customer Payment - Acme Corp,PAY-001
2026-03-20,800.00,0,,Office Supplies,REF-202
2026-03-25,12000.00,0,ABC Traders,Vendor Payment - ABC Traders,VND-001
''';

      final bytes = utf8.encode(csvContent);

      if (kIsWeb) {
        final blob = html.Blob([bytes], 'text/csv');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'bank_statement_template.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final apiService = ApiService();
        await apiService.downloadBytes(
          bytes: bytes,
          filename: 'bank_statement_template.csv',
        );
      }

      setState(() => _isDownloading = false);
      _toast('✅ Template downloaded! Fill it and upload.', success: true);
    } catch (e) {
      setState(() => _isDownloading = false);
      _toast('Download failed: $e', success: false);
    }
  }

  // ── Pick CSV → confirm → upload ───────────────────────────────────────────
  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child:
                const Icon(Icons.upload_file_rounded, color: _kBlue, size: 22),
          ),
          const SizedBox(width: 12),
          const Text('Confirm Import',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kGreen.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.insert_drive_file_rounded,
                      color: _kGreen, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(file.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 14),
              Text(
                'Import bank statement for:\n${widget.accountName}\n\n'
                'Transactions will appear as UNCATEGORIZED.\nThis action cannot be undone.',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey[600], height: 1.5),
              ),
            ]),
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

    setState(() {
      _uploadedFileName = file.name;
      _isUploading = true;
      _showResults = false;
    });

    try {
      final apiService = ApiService();
      final headers = await apiService.getHeaders();

      // validateOnly = true asks the server to check every row WITHOUT saving
      // anything. validateOnly = false is the normal import.
      Future<Map<String, dynamic>> sendImport(
          {required bool validateOnly}) async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse(
              '${apiService.baseUrl}/api/finance/banking/transactions/import'),
        );

        // Add accountId as form field
        request.fields['accountId'] = widget.accountId;
        request.fields['dateFormat'] = _dateFormat;
        if (validateOnly) request.fields['validateOnly'] = 'true';

        headers.forEach((k, v) {
          if (k.toLowerCase() != 'content-type') request.headers[k] = v;
        });

        if (kIsWeb) {
          request.files.add(http.MultipartFile.fromBytes('file', file.bytes!,
              filename: file.name));
        } else {
          request.files.add(await http.MultipartFile.fromPath(
              'file', file.path!,
              filename: file.name));
        }

        final streamed = await request.send();
        final response = await http.Response.fromStream(streamed);

        debugPrint(
            '📥 Bank Import (validateOnly=$validateOnly) status: ${response.statusCode}');
        debugPrint('📥 Bank Import body  : ${response.body}');

        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      // Step 1 — check the file first (nothing is saved yet).
      var decoded = await sendImport(validateOnly: true);
      final checkData = decoded['data'] as Map<String, dynamic>? ?? {};

      // Only when the server confirms it ran in check-only mode do we offer
      // the choice. If it did not (older server, or an error response such as
      // a CSV parse error), `decoded` is treated exactly as the final import
      // result below — the same behaviour as before this change.
      if (checkData['validateOnly'] == true) {
        final failedCount = (checkData['errors'] as num?)?.toInt() ?? 0;
        final validCount = (checkData['valid'] as num?)?.toInt() ?? 0;

        // The choice is shown every time — whether or not any row failed.
        if (mounted) setState(() => _isUploading = false);
        final importValid = await _askImportValidOnly(
          validCount: validCount,
          failedCount: failedCount,
          skippedCount: (checkData['skipped'] as num?)?.toInt() ?? 0,
          errorDetails: (checkData['errorDetails'] as List?) ?? [],
          dateFormat: (checkData['dateFormat'] as String?) ?? 'AUTO',
          preview: (checkData['preview'] as List?) ?? [],
          warnings: ((checkData['warnings'] as List?) ?? [])
              .map((w) => w.toString())
              .toList(),
          dateRange: checkData['dateRange'] is Map
              ? Map<String, dynamic>.from(checkData['dateRange'] as Map)
              : null,
        );
        if (importValid != true) {
          // Cancelled (or nothing to import) — nothing was saved.
          if (mounted) {
            setState(() {
              _uploadedFileName = null;
              _showResults = false;
            });
          }
          _toast(
              validCount == 0
                  ? 'No new transactions to import.'
                  : 'Import cancelled — no transactions were imported.',
              success: false);
          return;
        }
        if (mounted) setState(() => _isUploading = true);

        // Step 2 — the real import (the user chose to import; any failed rows
        // are skipped again).
        decoded = await sendImport(validateOnly: false);
      }

      final data = decoded['data'] as Map<String, dynamic>? ?? {};
      final imported = (data['imported'] as num?)?.toInt() ?? 0;
      final skipped = (data['skipped'] as num?)?.toInt() ?? 0;
      final errorsCount = (data['errors'] as num?)?.toInt() ?? 0;
      final errorDetails = (data['errorDetails'] as List?) ?? [];

      setState(() {
        _isUploading = false;
        _importedCount = imported;
        _skippedCount = skipped;
        _errorsCount = errorsCount;
        _errorDetails = errorDetails;
        _showResults = true;
        _importSuccess = decoded['success'] == true;
      });

      if (_importedCount > 0) {
        _toast(
          '✅ $imported transaction(s) imported'
          '${skipped > 0 ? ', $skipped duplicate(s) skipped' : ''}'
          '${errorsCount > 0 ? ', $errorsCount failed' : ''}.',
          success: true,
        );
        widget.onImportComplete();
      } else if (skipped > 0 && errorsCount == 0) {
        _toast('All $skipped transaction(s) already imported — no new data.',
            success: false);
      } else {
        _toast(decoded['message']?.toString() ?? 'Import failed',
            success: false);
      }
    } catch (e) {
      debugPrint('❌ Bank Import error: $e');
      setState(() {
        _isUploading = false;
        _showResults = false;
      });
      _toast('Failed to import: $e', success: false);
    }
  }

  // The date format used, how the first dates will be SAVED, and any warning
  // (format looks wrong, dates far from today ...).
  // "2026-05-03" → "03 May 2026" (the month as a word, so it cannot be misread)
  String _niceDay(dynamic iso) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse('$iso'));
    } catch (_) {
      return '$iso';
    }
  }

  // 50000 → "₹50,000.00"
  String _money(dynamic v) {
    final n = v is num ? v : num.tryParse('$v');
    if (n == null) return '$v';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
        .format(n);
  }

  List<Widget> _checkInfoWidgets({
    required String dateFormat,
    required List<dynamic> preview,
    required List<String> warnings,
    Map<String, dynamic>? dateRange,
  }) {
    final widgets = <Widget>[];
    widgets.add(const SizedBox(height: 10));
    widgets.add(Text(
        dateFormat == 'AUTO'
            ? 'Date format: detected automatically'
            : 'Date format used: $dateFormat',
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800])));
    if (dateRange != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
            'Dates run from ${_niceDay(dateRange['from'])} to ${_niceDay(dateRange['to'])}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ));
    }
    if (preview.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: _kBlue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBlue.withOpacity(0.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Preview — how the first rows will be saved',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _kBlue)),
          const SizedBox(height: 6),
          // column headings
          Row(children: [
            SizedBox(
                width: 84,
                child: Text('In your file',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600]))),
            const SizedBox(width: 18),
            SizedBox(
                width: 92,
                child: Text('Will be saved as',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600]))),
            Expanded(
                child: Text('Description',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600]))),
            Text('Amount',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600])),
          ]),
          const Divider(height: 8),
          ...preview.map<Widget>((p) {
            final m = p is Map ? p : const {};
            final isCredit = m['type'] == 'CREDIT';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                    width: 84,
                    child: Text('${m['rawDate']}',
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[700]))),
                const Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
                const SizedBox(width: 6),
                SizedBox(
                    width: 92,
                    child: Text(_niceDay(m['date']),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700))),
                Expanded(
                    child: Text('${m['description'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))),
                Text('${isCredit ? '+' : '-'}${_money(m['amount'])}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCredit ? _kGreen : _kRed)),
              ]),
            );
          }),
        ]),
      ));
    }
    for (final w in warnings) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kOrange.withOpacity(0.4))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: _kOrange, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(w, style: const TextStyle(fontSize: 12, height: 1.4))),
        ]),
      ));
    }
    return widgets;
  }

  // ── Some rows failed the check: import the good ones, or cancel everything ──
  // Returns true  → import only the successful rows (failed rows are skipped)
  //         false → cancel, nothing is imported
  Future<bool?> _askImportValidOnly({
    required int validCount,
    required int failedCount,
    required int skippedCount,
    required List<dynamic> errorDetails,
    String dateFormat = 'AUTO',
    List<dynamic> preview = const [],
    List<String> warnings = const [],
    Map<String, dynamic>? dateRange,
  }) {
    final canImport = validCount > 0;
    final hasFailures = failedCount > 0;
    final accent = hasFailures ? _kRed : (canImport ? _kGreen : _kOrange);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(
                hasFailures
                    ? Icons.warning_amber_rounded
                    : (canImport
                        ? Icons.check_circle_outline
                        : Icons.info_outline),
                color: accent,
                size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                hasFailures
                    ? '$failedCount row(s) failed'
                    : (canImport ? 'Ready to import' : 'Nothing new to import'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  canImport
                      ? '$validCount transaction(s) ${hasFailures ? 'are valid' : 'will be imported'}'
                          '${skippedCount > 0 ? ' ($skippedCount duplicate/empty row(s) will be skipped)' : ''}.\n'
                          'Nothing has been imported yet. Choose what to do:'
                      : (hasFailures
                          ? 'None of the rows in this file can be imported.\n'
                              'Nothing has been imported.'
                          : 'All $skippedCount row(s) in this file are duplicates or empty, '
                              'so there is nothing new to import.'),
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[700], height: 1.5),
                ),
                ..._checkInfoWidgets(
                    dateFormat: dateFormat,
                    preview: preview,
                    warnings: warnings,
                    dateRange: dateRange),
                if (hasFailures) const SizedBox(height: 12),
                if (hasFailures)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: _kRed.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kRed.withOpacity(0.2))),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: errorDetails.map<Widget>((e) {
                            final msg = e is Map
                                ? 'Row ${e['row']}: ${e['error'] ?? e['message'] ?? e}'
                                : e.toString();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(msg,
                                  style: const TextStyle(
                                      fontSize: 12, color: _kRed)),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
              ])),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(canImport
                ? (hasFailures ? 'Cancel — import nothing' : 'Cancel')
                : 'Close'),
          ),
          if (canImport)
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: Text(hasFailures
                  ? 'Import $validCount successful'
                  : 'Import $validCount transaction(s)'),
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
  }

  void _toast(String msg, {required bool success}) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg, isError: true);
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildHeader(),
          Flexible(
              child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildInfoBox(),
              const SizedBox(height: 20),
              _buildStep(
                step: '1',
                color: _kBlue,
                icon: Icons.download_rounded,
                title: 'Download Template',
                subtitle: 'Get the CSV template with required columns.',
                buttonLabel: 'Download Template',
                isLoading: _isDownloading,
                onPressed:
                    (_isDownloading || _isUploading) ? null : _downloadTemplate,
              ),
              const SizedBox(height: 14),
              _buildDateFormatPicker(),
              const SizedBox(height: 14),
              _buildStep(
                step: '2',
                color: _kGreen,
                icon: Icons.upload_rounded,
                title: 'Upload Bank Statement',
                subtitle: 'Fill the template and upload (CSV / Excel).',
                buttonLabel: 'Select CSV / Excel File',
                isLoading: _isUploading,
                onPressed:
                    (_isDownloading || _isUploading) ? null : _pickAndUpload,
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
            ]),
          )),
        ]),
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
                color: _kOrange.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.file_upload_outlined,
                color: _kOrange, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Import Bank Statement',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(widget.accountName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ])),
          IconButton(
            onPressed: _isUploading ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
        ]),
      );

  // "Which format are the dates in your file?" — never guessed by the server.
  Widget _buildDateFormatPicker() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kOrange.withOpacity(0.35))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.event_outlined, color: _kOrange, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Date format in your file',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _dateFormat,
            isDense: true,
            decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: _dateFormats
                .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text('$f   (${_dateFormatExamples[f]})',
                        style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: _isUploading
                ? null
                : (v) => setState(() => _dateFormat = v ?? _dateFormat),
          ),
          const SizedBox(height: 6),
          Text(
              'You will see how your dates will be saved before anything is imported.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[700])),
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
            Text('CSV Format Required',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: _kBlue, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          const Text(
            'Required columns:\n'
            '• Date — choose its format below (2026-10-03 always works)\n'
            '• Withdrawals (debit/money out — 0 or blank if deposit)\n'
            '• Deposits (credit/money in — 0 or blank if withdrawal)\n'
            '• Payee (optional — vendor/customer name)\n'
            '• Description\n'
            '• Reference Number',
            style: TextStyle(fontSize: 13, height: 1.65),
          ),
        ]),
      );

  Widget _buildStep({
    required String step,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final circle = Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
              child: Text(step,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15))),
        );
        final textBlock =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]);
        final button = ElevatedButton.icon(
          onPressed: onPressed,
          icon: isLoading
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
              : Icon(icon, size: 15),
          label: Text(isLoading ? 'Please wait…' : buttonLabel,
              style: const TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withOpacity(0.5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );

        if (constraints.maxWidth < 340) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  circle,
                  const SizedBox(width: 10),
                  Expanded(child: textBlock)
                ]),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: button),
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          circle,
          const SizedBox(width: 14),
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
          Expanded(
              child: Text(_uploadedFileName!,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _kGreen,
                      fontSize: 13))),
          if (_isUploading) ...[
            const SizedBox(width: 8),
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_kGreen))),
            const SizedBox(width: 8),
            Text('Uploading…',
                style:
                    TextStyle(fontSize: 12, color: _kGreen.withOpacity(0.7))),
          ],
        ]),
      );

  Widget _buildResults() {
    final total = _importedCount + _errorsCount + _skippedCount;
    final allSuccess =
        _errorsCount == 0 && _skippedCount == 0 && _importedCount > 0;
    final allFailed = _importedCount == 0 && _errorsCount > 0;
    final allSkipped =
        _importedCount == 0 && _errorsCount == 0 && _skippedCount > 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(
          allFailed
              ? Icons.cancel_rounded
              : allSkipped
                  ? Icons.info_rounded
                  : Icons.check_circle_rounded,
          color: allFailed
              ? _kRed
              : allSkipped
                  ? _kOrange
                  : _kGreen,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
          allSuccess
              ? 'Import Successful!'
              : allFailed
                  ? 'Import Failed'
                  : allSkipped
                      ? 'Already Imported — No New Transactions'
                      : 'Import Completed with Issues',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: allFailed
                  ? _kRed
                  : allSkipped
                      ? _kOrange
                      : const Color(0xFF2C3E50)),
        )),
      ]),
      if (allSkipped) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kOrange.withOpacity(0.3)),
          ),
          child: Text(
            'All $_skippedCount transaction(s) in this file were already imported previously. '
            'Try uploading a file with new/different transactions.',
            style:
                TextStyle(fontSize: 13, color: Colors.orange[800], height: 1.5),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: _summaryCard(
                label: 'Total',
                value: '$total',
                icon: Icons.summarize_outlined,
                color: _kBlue)),
        const SizedBox(width: 10),
        Expanded(
            child: _summaryCard(
                label: 'Imported',
                value: '$_importedCount',
                icon: Icons.check_circle_outline_rounded,
                color: _kGreen)),
        const SizedBox(width: 10),
        Expanded(
            child: _summaryCard(
                label: 'Skipped',
                value: '$_skippedCount',
                icon: Icons.skip_next_rounded,
                color: _skippedCount > 0 ? _kOrange : Colors.grey)),
        const SizedBox(width: 10),
        Expanded(
            child: _summaryCard(
                label: 'Failed',
                value: '$_errorsCount',
                icon: Icons.cancel_outlined,
                color: _errorsCount > 0 ? _kRed : Colors.grey)),
      ]),
      if (_errorDetails.isNotEmpty) ...[
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _kRed.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kRed.withOpacity(0.25))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: _kRed, size: 18),
              const SizedBox(width: 8),
              Text('${_errorDetails.length} row(s) failed:',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: _kRed, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _errorDetails.map<Widget>((e) {
                    final rowNum =
                        e is Map ? (e['row'] ?? '?').toString() : '?';
                    final errMsg = e is Map
                        ? (e['error'] ?? e['message'] ?? e.toString())
                            .toString()
                        : e.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Icon(Icons.circle,
                                    size: 6, color: _kRed.withOpacity(0.6))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: RichText(
                                    text: TextSpan(
                              style: TextStyle(
                                  fontSize: 12, color: Colors.red[800]),
                              children: [
                                TextSpan(
                                    text: 'Row $rowNum: ',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                TextSpan(text: errMsg),
                              ],
                            ))),
                          ]),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: Icon(allSuccess ? Icons.done_all_rounded : Icons.close_rounded,
              size: 16),
          label: Text(
            allSuccess
                ? 'Done — $_importedCount Transaction(s) Imported'
                : allSkipped
                    ? 'Close — No New Transactions'
                    : 'Close',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: allSuccess
                ? _kGreen
                : allSkipped
                    ? _kOrange
                    : _kNavy,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(double.infinity, 46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
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
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            textAlign: TextAlign.center),
      ]),
    );
  }
}
