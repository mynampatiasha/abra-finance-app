// ============================================================================
// ITEM BILLING SERVICE — COMPLETE FIXED VERSION
// ============================================================================
// File: lib/core/services/item_billing_service.dart
//
// Fixes applied:
//   1. getItemStatistics() now reads response['statistics'] correctly
//   2. fetchSalesAccounts() calls /api/finance/items/accounts/sales (COA-backed)
//   3. fetchPurchaseAccounts() calls /api/finance/items/accounts/purchase (COA-backed)
//   4. fetchUnits() calls /api/finance/items/units
//   5. searchItems() calls /api/finance/items/search (not a separate /search prefix)
//   6. fetchVendors() calls correct /api/finance/vendors endpoint
//
// All existing functionality preserved — CRUD, export PDF/CSV/Excel, import, etc.
// ============================================================================

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show File, Directory, Platform;
import 'package:universal_html/html.dart' as html
    show Blob, Url, AnchorElement;

import 'api_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ItemBillingService {
  final ApiService _apiService = ApiService();
  static const Duration timeout = Duration(seconds: 30);

  // ==========================================================================
  //  CORE CRUD
  // ==========================================================================

  /// Fetch all items with optional filters
  Future<List<Map<String, dynamic>>> fetchAllItems({
    String? type,
    bool? isSellable,
    bool? isPurchasable,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int? page,
    int? limit,
  }) async {
    try {
      final q = <String, String>{};
      if (type != null)        q['type']         = type;
      if (isSellable != null)  q['isSellable']   = isSellable.toString();
      if (isPurchasable != null) q['isPurchasable'] = isPurchasable.toString();
      if (search != null && search.isNotEmpty) q['search'] = search;
      if (startDate != null)   q['startDate']    = startDate.toIso8601String();
      if (endDate != null)     q['endDate']       = endDate.toIso8601String();
      if (page != null)        q['page']          = page.toString();
      if (limit != null)       q['limit']         = limit.toString();

      final response = await _apiService.get('/api/finance/items', queryParams: q);

      if (response['items'] != null) {
        return List<Map<String, dynamic>>.from(response['items']);
      } else if (response['data'] != null) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
      return [];
    } catch (e) {
      throw Exception('Error fetching items: $e');
    }
  }

  /// Fetch a single item by ID
  Future<Map<String, dynamic>> fetchItemById(String itemId) async {
    try {
      final response = await _apiService.get('/api/finance/items/$itemId');
      if (response['item'] != null)  return Map<String, dynamic>.from(response['item']);
      if (response['data'] != null)  return Map<String, dynamic>.from(response['data']);
      return Map<String, dynamic>.from(response);
    } catch (e) {
      throw Exception('Error fetching item: $e');
    }
  }

  /// Create a new item
  Future<String> createItem(Map<String, dynamic> itemData) async {
    try {
      _validateItemData(itemData);
      final response = await _apiService.post('/api/finance/items', body: itemData);
      return response['message'] ?? 'Item created successfully';
    } catch (e) {
      throw Exception('Error creating item: $e');
    }
  }

  /// Update an existing item
  Future<String> updateItem(String itemId, Map<String, dynamic> itemData) async {
    try {
      _validateItemData(itemData);
      final response = await _apiService.put('/api/finance/items/$itemId', body: itemData);
      return response['message'] ?? 'Item updated successfully';
    } catch (e) {
      throw Exception('Error updating item: $e');
    }
  }

  /// Delete an item (soft delete on backend)
  Future<String> deleteItem(String itemId) async {
    try {
      final response = await _apiService.delete('/api/finance/items/$itemId');
      return response['message'] ?? 'Item deleted successfully';
    } catch (e) {
      throw Exception('Error deleting item: $e');
    }
  }

  /// Search items by name / description
  Future<List<Map<String, dynamic>>> searchItems(String query) async {
    try {
      if (query.trim().isEmpty) return [];
      // FIX 5: correct route — /api/finance/items/search?q=...
      final response = await _apiService.get(
        '/api/finance/items/search',
        queryParams: {'q': query},
      );
      if (response['items'] != null) return List<Map<String, dynamic>>.from(response['items']);
      if (response['data'] != null)  return List<Map<String, dynamic>>.from(response['data']);
      return [];
    } catch (e) {
      throw Exception('Error searching items: $e');
    }
  }

  // ==========================================================================
  //  FIX 1 — getItemStatistics reads response['statistics'] key correctly
  // ==========================================================================

  /// Get item statistics — stat cards on the Items page
  Future<Map<String, dynamic>> getItemStatistics() async {
    try {
      final response = await _apiService.get('/api/finance/items/statistics');

      // FIX 1: backend wraps everything in response['statistics']
      if (response['statistics'] != null) {
        return Map<String, dynamic>.from(response['statistics'] as Map);
      }
      // Fallback: some older builds may return flat structure
      if (response['data'] != null) {
        return Map<String, dynamic>.from(response['data'] as Map);
      }
      return Map<String, dynamic>.from(response);
    } catch (e) {
      throw Exception('Error fetching statistics: $e');
    }
  }

  // ==========================================================================
  //  VALIDATION
  // ==========================================================================

  void _validateItemData(Map<String, dynamic> data) {
    if (data['name'] == null || (data['name'] as String).trim().isEmpty) {
      throw Exception('Item name is required');
    }
    if (data['type'] == null || !['Goods', 'Service'].contains(data['type'])) {
      throw Exception('Invalid item type. Must be "Goods" or "Service"');
    }
    if (data['isSellable'] == true) {
      if (data['sellingPrice'] == null) {
        throw Exception('Selling price is required for sellable items');
      }
      if (data['sellingPrice'] is! num || (data['sellingPrice'] as num) < 0) {
        throw Exception('Selling price must be a positive number');
      }
      if (data['salesAccount'] == null || (data['salesAccount'] as String).trim().isEmpty) {
        throw Exception('Sales account is required for sellable items');
      }
    }
    if (data['isPurchasable'] == true) {
      if (data['costPrice'] == null) {
        throw Exception('Cost price is required for purchasable items');
      }
      if (data['costPrice'] is! num || (data['costPrice'] as num) < 0) {
        throw Exception('Cost price must be a positive number');
      }
      if (data['purchaseAccount'] == null ||
          (data['purchaseAccount'] as String).trim().isEmpty) {
        throw Exception('Purchase account is required for purchasable items');
      }
    }
  }

  // ==========================================================================
  //  VENDOR MANAGEMENT
  // ==========================================================================

  /// Fetch all vendors — FIX 6: correct endpoint
  Future<List<Map<String, dynamic>>> fetchVendors() async {
    try {
      final response = await _apiService.get('/api/finance/vendors');
      if (response['vendors'] != null) {
        return List<Map<String, dynamic>>.from(response['vendors']);
      }
      if (response['data'] != null) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
      if (response is List) {
        return List<Map<String, dynamic>>.from(response as List);
      }
      return [];
    } catch (e) {
      // Non-fatal — vendor dropdown can be empty
      return [];
    }
  }

  /// Create a new vendor
  Future<Map<String, dynamic>> createVendor(Map<String, dynamic> vendorData) async {
    try {
      final response = await _apiService.post('/api/finance/vendors', body: vendorData);
      if (response['vendor'] != null) return Map<String, dynamic>.from(response['vendor']);
      if (response['data'] != null)   return Map<String, dynamic>.from(response['data']);
      return Map<String, dynamic>.from(response);
    } catch (e) {
      throw Exception('Error creating vendor: $e');
    }
  }

  // ==========================================================================
  //  FIX 2 + FIX 3 — DROPDOWN DATA (units, sales accounts, purchase accounts)
  //  All now call correct /api/finance/items/... endpoints backed by COA
  // ==========================================================================

  /// Fetch units list
  Future<List<String>> fetchUnits() async {
    try {
      // FIX 4: correct endpoint
      final response = await _apiService.get('/api/finance/items/units');
      if (response['units'] != null) return List<String>.from(response['units'] as List);
      if (response['data'] != null)  return List<String>.from(response['data'] as List);
      if (response is List)          return List<String>.from(response as List);
      return _defaultUnits();
    } catch (_) {
      return _defaultUnits();
    }
  }

  List<String> _defaultUnits() =>
      ['pcs', 'dz', 'kg', 'g', 'ltr', 'ml', 'box', 'carton', 'unit', 'dozen', 'ton', 'hour'];

  /// Fetch sales accounts — FIX 2: reads from COA (Income accounts)
  Future<List<String>> fetchSalesAccounts() async {
    try {
      final response = await _apiService.get('/api/finance/items/accounts/sales');
      if (response['accounts'] != null) return List<String>.from(response['accounts'] as List);
      if (response['data'] != null)     return List<String>.from(response['data'] as List);
      if (response is List)             return List<String>.from(response as List);
      return _defaultSalesAccounts();
    } catch (_) {
      return _defaultSalesAccounts();
    }
  }

  List<String> _defaultSalesAccounts() =>
      ['Sales', 'Service Revenue', 'Other Income', 'Consulting Revenue'];

  /// Fetch purchase accounts — FIX 3: reads from COA (Expense / COGS accounts)
  Future<List<String>> fetchPurchaseAccounts() async {
    try {
      final response = await _apiService.get('/api/finance/items/accounts/purchase');
      if (response['accounts'] != null) return List<String>.from(response['accounts'] as List);
      if (response['data'] != null)     return List<String>.from(response['data'] as List);
      if (response is List)             return List<String>.from(response as List);
      return _defaultPurchaseAccounts();
    } catch (_) {
      return _defaultPurchaseAccounts();
    }
  }

  List<String> _defaultPurchaseAccounts() =>
      ['Cost of Goods Sold', 'Purchases', 'Direct Expenses', 'Materials'];

  // ==========================================================================
  //  FILE HANDLING — unchanged, all platform paths preserved
  // ==========================================================================

  Future<dynamic> _getDownloadsDirectory() async {
    if (kIsWeb) throw UnsupportedError('Downloads directory not supported on web');
    try {
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) {
            var ms = await Permission.manageExternalStorage.status;
            if (!ms.isGranted) ms = await Permission.manageExternalStorage.request();
            if (!ms.isGranted) throw Exception('Storage permission denied');
          }
        }
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final dp = Directory('/storage/emulated/0/Download');
          if (await dp.exists()) return dp;
        }
        return await getApplicationDocumentsDirectory();
      } else if (Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      } else {
        final d = await getDownloadsDirectory();
        if (d != null) return d;
        return await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      return await getApplicationDocumentsDirectory();
    }
  }

  Future<PlatformFile?> pickCSVFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'Select CSV file to import',
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) return result.files.first;
      return null;
    } catch (e) {
      throw Exception('Error picking file: $e');
    }
  }

  // ==========================================================================
  //  IMPORT — unchanged
  // ==========================================================================

  Future<Map<String, dynamic>> importItemsFromCSV(PlatformFile file) async {
    try {
      final baseUrl = _apiService.baseUrl;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/finance/items/bulk-import'),
      );
      final headers = await _apiService.getHeaders();
      request.headers.addAll(headers);

      if (kIsWeb) {
        if (file.bytes == null) throw Exception('File bytes not available');
        request.files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));
      } else {
        if (file.path == null) throw Exception('File path not available');
        request.files.add(await http.MultipartFile.fromPath('file', file.path!, filename: file.name));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        return {
          'success':      true,
          'successCount': data['successCount'] ?? 0,
          'errorCount':   data['errorCount']   ?? 0,
          'errors':       data['errors']        ?? [],
          'message':      data['message']       ?? 'Import completed',
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to import items');
      }
    } catch (e) {
      throw Exception('Error importing items: $e');
    }
  }

  /// Download CSV template — unchanged
  Future<String> downloadCSVTemplate() async {
    try {
      final csvData = [
        ['Name', 'Type', 'Unit', 'Selling Price', 'Cost Price', 'Sales Account',
         'Purchase Account', 'Sales Description', 'Purchase Description',
         'Is Sellable', 'Is Purchasable'],
        ['Laptop Dell Inspiron', 'Goods', 'pcs', '45000', '40000', 'Sales',
         'Cost of Goods Sold', 'Dell Inspiron 15', 'Bulk purchase', 'true', 'true'],
        ['IT Consulting Service', 'Service', 'hour', '2000', '1500', 'Service Revenue',
         'Direct Expenses', 'Professional IT consulting', 'Outsourced consulting', 'true', 'true'],
        ['Office Chair Premium', 'Goods', 'pcs', '8500', '7000', 'Sales',
         'Purchases', 'Ergonomic office chair', 'Imported from manufacturer', 'true', 'true'],
      ];
      final csvString = const ListToCsvConverter().convert(csvData);

      if (kIsWeb) {
        final bytes = utf8.encode(csvString);
        final blob  = html.Blob([bytes]);
        final url   = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'items_import_template.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
        return 'items_import_template.csv';
      } else {
        final dir  = await _getDownloadsDirectory();
        final ts   = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}/items_import_template_$ts.csv';
        await File(path).writeAsString(csvString);
        return path;
      }
    } catch (e) {
      throw Exception('Error downloading template: $e');
    }
  }

  // ==========================================================================
  //  EXPORT — unchanged
  // ==========================================================================

  Future<String> exportItemsToCSV(List<Map<String, dynamic>> items) async {
    try {
      if (items.isEmpty) throw Exception('No items to export');
      final csvData = [
        ['Name', 'Type', 'Unit', 'Selling Price', 'Cost Price', 'Sales Account',
         'Purchase Account', 'Sales Description', 'Purchase Description',
         'Is Sellable', 'Is Purchasable', 'Created At'],
        ...items.map((i) => [
          i['name'] ?? '', i['type'] ?? '', i['unit'] ?? '',
          i['sellingPrice']?.toString() ?? '', i['costPrice']?.toString() ?? '',
          i['salesAccount'] ?? '', i['purchaseAccount'] ?? '',
          i['salesDescription'] ?? '', i['purchaseDescription'] ?? '',
          i['isSellable']?.toString() ?? 'true',
          i['isPurchasable']?.toString() ?? 'true',
          i['createdAt'] ?? '',
        ]),
      ];
      final csvString = const ListToCsvConverter().convert(csvData);
      final ts = DateTime.now().millisecondsSinceEpoch;

      if (kIsWeb) {
        final blob = html.Blob([utf8.encode(csvString)]);
        final url  = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'items_export_$ts.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
        return 'items_export_$ts.csv';
      } else {
        final dir  = await _getDownloadsDirectory();
        final path = '${dir.path}/items_export_$ts.csv';
        await File(path).writeAsString(csvString);
        return path;
      }
    } catch (e) {
      throw Exception('Error exporting to CSV: $e');
    }
  }

  Future<String> exportItemsToExcel(List<Map<String, dynamic>> items) async {
    // Exports as CSV — Excel opens CSV natively
    return exportItemsToCSV(items);
  }

  Future<String> exportItemsToPDF(List<Map<String, dynamic>> items) async {
    try {
      if (items.isEmpty) throw Exception('No items to export');

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => [
            pw.Header(
              level: 0,
              child: pw.Text('Items Export Report',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Generated on ${DateTime.now().toString().split('.')[0]}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Name', 'Type', 'Unit', 'Selling Price', 'Cost Price', 'Sales Account'],
              data: items.map((i) => [
                i['name'] ?? '',
                i['type'] ?? '',
                i['unit'] ?? '',
                i['sellingPrice'] != null ? '₹${i['sellingPrice']}' : '-',
                i['costPrice']    != null ? '₹${i['costPrice']}'    : '-',
                i['salesAccount'] ?? '',
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              cellHeight: 25,
            ),
            pw.SizedBox(height: 20),
            pw.Text('Total Items: ${items.length}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

      final ts       = DateTime.now().millisecondsSinceEpoch;
      final pdfBytes = await pdf.save();

      if (kIsWeb) {
        final blob = html.Blob([pdfBytes], 'application/pdf');
        final url  = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'items_export_$ts.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);
        return 'items_export_$ts.pdf';
      } else {
        final dir  = await _getDownloadsDirectory();
        final path = '${dir.path}/items_export_$ts.pdf';
        await File(path).writeAsBytes(pdfBytes);
        return path;
      }
    } catch (e) {
      throw Exception('Error exporting to PDF: $e');
    }
  }
}