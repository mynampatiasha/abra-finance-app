// ============================================================================
// EXPORT HELPER - Reusable export functionality for all services
// ============================================================================
// Provides CSV, Excel, and PDF export capabilities
// ============================================================================

import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
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
        final bytes = utf8.encode(csv);
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
  static Future<String> exportToPDF({
    required String title,
    required List<String> headers,
    required List<List<dynamic>> data,
    required String filename,
  }) async {
    try {
      print('📤 Starting PDF export: $filename');
      
      if (data.isEmpty) {
        throw Exception('No data to export');
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Title
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
            
            // Data table
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
}
