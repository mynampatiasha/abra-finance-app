// ============================================================================
// EXPORT HELPER - Reusable export functionality for all services
// ============================================================================
// Provides CSV, Excel, and PDF export capabilities
// ============================================================================

import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/html.dart' as html show Blob, Url, AnchorElement;

class ExportHelper {
  /// Export data to CSV format
  static Future<String> exportToCSV({
    required List<List<dynamic>> data,
    required String filename,
  }) async {
    try {
      print('📤 Starting CSV export: $filename');

      if (data.isEmpty) {
        throw Exception('No data to export');
      }

      String csv = const ListToCsvConverter().convert(data);

      if (kIsWeb) {
        // Web: Use browser download
        // Excel opens CSV files using the system's ANSI codepage unless a
        // UTF-8 BOM is present at the start of the file — without it, every
        // multi-byte UTF-8 character (₹, etc.) gets split into 2-3 mojibake
        // characters (e.g. "â‚¹"). Prepending the BOM tells Excel to read the
        // file as UTF-8.
        const bom = '﻿';
        final bytes = utf8.encode('$bom$csv');
        final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', '${filename}_$timestamp.csv')
          ..click();
        html.Url.revokeObjectUrl(url);

        print('✅ CSV downloaded via browser');
        return '${filename}_$timestamp.csv';
      } else {
        // Mobile/Desktop: Use file system
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${directory.path}/${filename}_$timestamp.csv';

        print('📁 Saving to: $filePath');

        final file = File(filePath);
        await file.writeAsString(csv);

        print('✅ CSV export completed');
        return filePath;
      }
    } catch (e) {
      print('❌ Error exporting to CSV: $e');
      throw Exception('Error exporting to CSV: $e');
    }
  }

  /// Export data to Excel (as CSV format - Excel can open CSV)
  static Future<String> exportToExcel({
    required List<List<dynamic>> data,
    required String filename,
  }) async {
    try {
      print('📤 Starting Excel export...');
      // For now, export as CSV (Excel can open CSV files)
      // To implement proper .xlsx export, add the 'excel' package
      final filePath = await exportToCSV(data: data, filename: filename);
      print('✅ Excel export completed (as CSV format)');
      return filePath;
    } catch (e) {
      throw Exception('Error exporting to Excel: $e');
    }
  }

  /// Export data to PDF format
  ///
  /// [rowTypes], when provided (one entry per row in [data], values
  /// 'header' | 'subtotal' | 'detail'), switches the table from the flat
  /// grey-header grid to a hierarchy-aware layout: 'header' rows render as
  /// a full-width section title bar, 'subtotal' rows render bold with a
  /// divider line above, and 'detail' rows render indented under their
  /// section — matching how financial statements (P&L, Balance Sheet, Cash
  /// Flow, Movement of Equity) are structured. Leave null for plain list
  /// reports to keep the existing flat-table rendering unchanged.
  static Future<String> exportToPDF({
    required String title,
    required List<String> headers,
    required List<List<dynamic>> data,
    required String filename,
    String? orgName,
    Uint8List? orgLogoBytes,
    String? orgAddress,
    String? orgPhone,
    String? orgGst,
    String? customerName,
    String? customerAddress,
    List<String>? rowTypes,
    bool portrait = false,
  }) async {
    try {
      print('📤 Starting PDF export: $filename');

      if (data.isEmpty) {
        throw Exception('No data to export');
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: portrait ? PdfPageFormat.a4 : PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Company Header
            if (orgName != null || orgLogoBytes != null) ...[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if (orgLogoBytes != null)
                        pw.Container(
                          height: 50,
                          margin: const pw.EdgeInsets.only(bottom: 8),
                          child: pw.Image(pw.MemoryImage(orgLogoBytes)),
                        ),
                      if (orgName != null)
                        pw.Text(
                          orgName,
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                      if (orgAddress != null && orgAddress.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4),
                          child: pw.Text(
                            orgAddress,
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        ),
                      if (orgPhone != null && orgPhone.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            'Ph: $orgPhone',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        ),
                      if (orgGst != null && orgGst.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 2),
                          child: pw.Text(
                            'GSTIN: $orgGst',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        title.split('\n').last, // Usually the report name/date
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Generated on ${DateTime.now().toString().split('.')[0]}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 16),
              
              if (customerName != null && customerName.isNotEmpty) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'TO',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        customerName,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (customerAddress != null && customerAddress.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          customerAddress,
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
              ],
            ] else ...[
              // Fallback basic header
              pw.Header(
                level: 0,
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Generated on ${DateTime.now().toString().split('.')[0]}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 20),
            ],

            // Data table
            if (rowTypes != null)
              _buildStructuredTable(headers, data, rowTypes)
            else
              pw.Table.fromTextArray(
                headers: headers,
                data: data,
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellHeight: 30,
                cellAlignments: {
                  for (var i = 0; i < headers.length; i++)
                    i: pw.Alignment.centerLeft,
                },
              ),
          ],
        ),
      );

      if (kIsWeb) {
        // Web: Download PDF
        final bytes = await pdf.save();
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', '${filename}_$timestamp.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);

        print('✅ PDF downloaded via browser');
        return '${filename}_$timestamp.pdf';
      } else {
        // Mobile/Desktop: Save to file system
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${directory.path}/${filename}_$timestamp.pdf';

        final file = File(filePath);
        await file.writeAsBytes(await pdf.save());

        print('✅ PDF export completed');
        return filePath;
      }
    } catch (e) {
      print('❌ Error exporting to PDF: $e');
      throw Exception('Error exporting to PDF: $e');
    }
  }

  static bool _looksNumericCell(String s) {
    final stripped = s
        .replaceAll('₹', '')
        .replaceAll('Rs.', '')
        .replaceAll(',', '')
        .replaceAll('%', '')
        .trim();
    if (stripped.isEmpty) return false;
    return RegExp(r'^-?\(?\d+(\.\d+)?\)?$').hasMatch(stripped);
  }

  /// Renders `data` as a hierarchy-aware table: 'header' rows become a
  /// full-width section title bar, 'subtotal' rows render bold with a top
  /// divider, 'detail' rows render indented under their section with
  /// numeric-looking cells right-aligned.
  // Header/subtotal rows put their label text in whichever column holds the
  // long descriptive name — for the Section/Account/Amount financial-
  // statement shape that's always the first column, but Trial Balance and
  // General Ledger put "Account Code" first and the actual long text in
  // "Account Name" instead. Detect the real label column by header name
  // rather than assuming it's always index 0.
  static bool _isWideColumn(String header) {
    final h = header.toLowerCase();
    if (h.contains('code') || h.contains('type')) return false;
    return h.contains('account') || h.contains('item') || h.contains('description');
  }

  static pw.Widget _buildStructuredTable(
    List<String> headers,
    List<List<dynamic>> data,
    List<String> rowTypes,
  ) {
    int labelCol = headers.indexWhere(_isWideColumn);
    if (labelCol == -1) labelCol = 0;

    final columnWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < headers.length; i++)
        i: _isWideColumn(headers[i])
            ? const pw.FlexColumnWidth(2.4)
            : const pw.FlexColumnWidth(1),
    };

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
        children: headers
            .map((h) => pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: pw.Text(
                    h,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ))
            .toList(),
      ),
    ];

    for (var i = 0; i < data.length; i++) {
      final cells = data[i];
      final type = i < rowTypes.length ? rowTypes[i] : 'detail';

      if (type == 'header') {
        tableRows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.blue50),
            children: List.generate(headers.length, (ci) {
              if (ci != labelCol) return pw.Container();
              return pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: pw.Text(
                  ci < cells.length ? cells[ci].toString() : '',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              );
            }),
          ),
        );
        continue;
      }

      final isSubtotal = type == 'subtotal';
      tableRows.add(
        pw.TableRow(
          decoration: isSubtotal
              ? const pw.BoxDecoration(
                  color: PdfColors.grey200,
                  border: pw.Border(
                      top: pw.BorderSide(color: PdfColors.grey500, width: 0.75)),
                )
              : (i % 2 == 1
                  ? const pw.BoxDecoration(color: PdfColors.grey50)
                  : null),
          children: List.generate(headers.length, (ci) {
            final val = ci < cells.length ? cells[ci].toString() : '';
            final numeric = _looksNumericCell(val);
            return pw.Padding(
              padding: pw.EdgeInsets.only(
                left: (ci == labelCol && !isSubtotal) ? 14 : 6,
                right: 6,
                top: 5,
                bottom: 5,
              ),
              child: pw.Text(
                val,
                textAlign: numeric ? pw.TextAlign.right : pw.TextAlign.left,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: isSubtotal ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: isSubtotal ? PdfColors.blue900 : PdfColors.grey900,
                ),
              ),
            );
          }),
        ),
      );
    }

    return pw.Table(columnWidths: columnWidths, children: tableRows);
  }
}
