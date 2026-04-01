// ============================================================================
// ITEM BILLING SERVICE - COMPLETE UPDATED VERSION
// ============================================================================
// This is the COMPLETE service file with all fixes applied
// Replace your existing item_billing_service.dart with this file
// ============================================================================

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'api_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show File, Directory, Platform;
import 'package:universal_html/html.dart' as html show Blob, Url, AnchorElement;

class ItemBillingService {
  final ApiService _apiService = ApiService();
  static const Duration timeout = Duration(seconds: 30);

  // ==================== CORE CRUD OPERATIONS ====================

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
      final queryParams = <String, String>{};
      if (type != null) queryParams['type'] = type;
      if (isSellable != null) queryParams['isSellable'] = isSellable.toString();
      if (isPurchasable != null) queryParams['isPurchasable'] = isPurchasable.toString();
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (startDate != null) queryParams['startDate'] = startDate.toIso8601String();
      if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();
      if (page != null) queryParams['page'] = page.toString();
      if (limit != null) queryParams['limit'] = limit.toString();

      final response = await _apiService.get('/api/finance/items', queryParams: queryParams);
      
      if (response['items'] != null) {
        return List<Map<String, dynamic>>.from(response['items']);
      } else if (response['data'] != null) {
        return List<Map<String, dynamic>>.from(response['data']);
      } else {
        return [];
      }
    } catch (e) {
      throw Exception('Error fetching items: $e');
    }
  }

  /// Fetch a single item by ID
  Future<Map<String, dynamic>> fetchItemById(String itemId) async {
    try {
      final response = await _apiService.get('/api/finance/items/$itemId');
      
      if (response['item'] != null) {
        return response['item'];
      } else if (response['data'] != null) {
        return response['data'];
      } else {
        return response;
      }
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

  /// Delete an item
  Future<String> deleteItem(String itemId) async {
    try {
      final response = await _apiService.delete('/api/finance/items/$itemId');
      return response['message'] ?? 'Item deleted successfully';
    } catch (e) {
      throw Exception('Error deleting item: $e');
    }
  }

  /// Search items by name
  Future<List<Map<String, dynamic>>> searchItems(String query) async {
    try {
      if (query.trim().isEmpty) {
        return [];
      }

      final response = await _apiService.get('/api/finance/items/search', queryParams: {'q': query});
      
      if (response['items'] != null) {
        return List<Map<String, dynamic>>.from(response['items']);
      } else if (response['data'] != null) {
        return List<Map<String, dynamic>>.from(response['data']);
      } else {
        return [];
      }
    } catch (e) {
      throw Exception('Error searching items: $e');
    }
  }

  /// Get item statistics
  Future<Map<String, dynamic>> getItemStatistics() async {
    try {
      final response = await _apiService.get('/api/finance/items/statistics');
      
      if (response['statistics'] != null) {
        return response['statistics'];
      } else if (response['data'] != null) {
        return response['data'];
      } else {
        return response;
      }
    } catch (e) {
      throw Exception('Error fetching statistics: $e');
    }
  }

  // ==================== VALIDATION ====================

  /// Validate item data before sending to backend
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
      if (data['sellingPrice'] is! num || data['sellingPrice'] < 0) {
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
      if (data['costPrice'] is! num || data['costPrice'] < 0) {
        throw Exception('Cost price must be a positive number');
      }
      if (data['purchaseAccount'] == null || (data['purchaseAccount'] as String).trim().isEmpty) {
        throw Exception('Purchase account is required for purchasable items');
      }
    }
  }

  // ==================== VENDOR MANAGEMENT ====================

  /// Fetch all vendors from the backend
  Future<List<Map<String, dynamic>>> fetchVendors() async {
    try {
      final response = await _apiService.get('/api/finance/vendors');
      
      // Handle different response formats
      if (response is List) {
        return List<Map<String, dynamic>>.from(response['items'] ?? []);
      } else if (response is Map) {
        if (response['vendors'] != null) {
          return List<Map<String, dynamic>>.from(response['vendors']);
        } else if (response['data'] != null) {
          return List<Map<String, dynamic>>.from(response['data']);
        }
      }
      
      return [];
    } catch (e) {
      print('⚠️ Error fetching vendors: $e');
      return [];
    }
  }

  /// Create a new vendor
  Future<Map<String, dynamic>> createVendor(Map<String, dynamic> vendorData) async {
    try {
      final response = await _apiService.post('/api/finance/vendors', body: vendorData);
      
      if (response['vendor'] != null) {
        return response['vendor'];
      } else if (response['data'] != null) {
        return response['data'];
      } else {
        return response;
      }
    } catch (e) {
      throw Exception('Error creating vendor: $e');
    }
  }

  // ==================== DROPDOWN DATA ====================

  /// Fetch units list (for dropdown)
  Future<List<String>> fetchUnits() async {
    try {
      final response = await _apiService.get('/api/units');
      
      if (response is List) {
        return List<String>.from(response as List);
      } else if (response is Map && response['units'] != null) {
        return List<String>.from(response['units'] as List);
      } else if (response is Map && response['data'] != null) {
        return List<String>.from(response['data'] as List);
      } else {
        return ['pcs', 'dz', 'kg', 'ltr', 'box', 'carton'];
      }
    } catch (e) {
      return ['pcs', 'dz', 'kg', 'ltr', 'box', 'carton'];
    }
  }

  /// Fetch sales accounts list
  Future<List<String>> fetchSalesAccounts() async {
    try {
      final response = await _apiService.get('/api/finance/chart-of-accounts/sales');
      
      if (response is List) {
        return List<String>.from(response as List);
      } else if (response is Map && response['accounts'] != null) {
        return List<String>.from(response['accounts'] as List);
      } else if (response is Map && response['data'] != null) {
        return List<String>.from(response['data'] as List);
      } else {
        return ['Sales', 'Service Revenue', 'Other Income'];
      }
    } catch (e) {
      return ['Sales', 'Service Revenue', 'Other Income'];
    }
  }

  /// Fetch purchase accounts list
  Future<List<String>> fetchPurchaseAccounts() async {
    try {
      final response = await _apiService.get('/api/finance/chart-of-accounts/purchase');
      
      if (response is List) {
        return List<String>.from(response as List);
      } else if (response is Map && response['accounts'] != null) {
        return List<String>.from(response['accounts'] as List);
      } else if (response is Map && response['data'] != null) {
        return List<String>.from(response['data'] as List);
      } else {
        return ['Cost of Goods Sold', 'Purchases', 'Direct Expenses'];
      }
    } catch (e) {
      return ['Cost of Goods Sold', 'Purchases', 'Direct Expenses'];
    }
  }

  // ==================== FILE HANDLING - FIXED ====================

  /// Get downloads directory with proper permissions
  Future<dynamic> _getDownloadsDirectory() async {
    // This method should never be called on web
    if (kIsWeb) {
      throw UnsupportedError('Downloads directory not supported on web');
    }
    
    try {
      if (Platform.isAndroid) {
        // Request storage permission
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
          if (!status.isGranted) {
            // Try manageExternalStorage permission for Android 11+
            var manageStatus = await Permission.manageExternalStorage.status;
            if (!manageStatus.isGranted) {
              manageStatus = await Permission.manageExternalStorage.request();
            }
            if (!manageStatus.isGranted) {
              throw Exception('Storage permission denied');
            }
          }
        }

        // Try to get Downloads folder
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final downloadsPath = '/storage/emulated/0/Download';
          final downloadsDir = Directory(downloadsPath);
          
          if (await downloadsDir.exists()) {
            print('📁 Using Downloads directory: $downloadsPath');
            return downloadsDir;
          }
        }
        
        // Fallback to app documents directory
        print('📁 Using app documents directory');
        return await getApplicationDocumentsDirectory();
      } else if (Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final directory = await getDownloadsDirectory();
        if (directory != null) {
          return directory;
        }
        return await getApplicationDocumentsDirectory();
      }
      
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      print('⚠️ Error getting downloads directory: $e');
      return await getApplicationDocumentsDirectory();
    }
  }

  /// Pick a CSV file for import
  Future<PlatformFile?> pickCSVFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'Select CSV file to import',
        withData: kIsWeb, // Load bytes on web
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files.first;
      }
      return null;
    } catch (e) {
      throw Exception('Error picking file: $e');
    }
  }

  // ==================== IMPORT FUNCTIONALITY ====================

  /// Import items from CSV file
  Future<Map<String, dynamic>> importItemsFromCSV(PlatformFile file) async {
    try {
      print('📤 Starting CSV import...');
      
      final baseUrl = _apiService.baseUrl;
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/items/bulk-import'),
      );
      
      // Add authentication headers from ApiService
      final headers = await _apiService.getHeaders();
      request.headers.addAll(headers);
      
      // Add file based on platform
      if (kIsWeb) {
        // Web: Use bytes
        if (file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'file',
              file.bytes!,
              filename: file.name,
            ),
          );
        } else {
          throw Exception('File bytes not available');
        }
      } else {
        // Mobile/Desktop: Use path
        if (file.path != null) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'file',
              file.path!,
              filename: file.name,
            ),
          );
        } else {
          throw Exception('File path not available');
        }
      }
      
      print('📡 Sending file to server...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        print('✅ Import completed: ${data['successCount']} successful, ${data['errorCount']} failed');
        
        return {
          'success': true,
          'successCount': data['successCount'] ?? 0,
          'errorCount': data['errorCount'] ?? 0,
          'errors': data['errors'] ?? [],
          'message': data['message'] ?? 'Import completed',
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to import items');
      }
    } catch (e) {
      print('❌ Import error: $e');
      throw Exception('Error importing items: $e');
    }
  }

  /// Download CSV template with sample data
  Future<String> downloadCSVTemplate() async {
    try {
      print('📥 Starting CSV template download...');
      
      // Create sample CSV template
      List<List<dynamic>> csvData = [
        // Header row
        [
          'Name',
          'Type',
          'Unit',
          'Selling Price',
          'Cost Price',
          'Sales Account',
          'Purchase Account',
          'Sales Description',
          'Purchase Description',
          'Is Sellable',
          'Is Purchasable',
        ],
        // Sample row 1 - Goods example
        [
          'Laptop Dell Inspiron',
          'Goods',
          'pcs',
          '45000',
          '40000',
          'Sales',
          'Cost of Goods Sold',
          'Dell Inspiron 15 3000 Series laptop',
          'Bulk purchase from authorized dealer',
          'true',
          'true',
        ],
        // Sample row 2 - Service example
        [
          'IT Consulting Service',
          'Service',
          'hour',
          '2000',
          '1500',
          'Service Revenue',
          'Direct Expenses',
          'Professional IT consulting and support',
          'Outsourced technical consulting',
          'true',
          'true',
        ],
        // Sample row 3 - Goods with different units
        [
          'Office Chair Premium',
          'Goods',
          'pcs',
          '8500',
          '7000',
          'Sales',
          'Purchases',
          'Ergonomic office chair with lumbar support',
          'Imported from manufacturer',
          'true',
          'true',
        ],
      ];

      String csv = const ListToCsvConverter().convert(csvData);

      // Handle web vs mobile/desktop differently
      if (kIsWeb) {
        // Web: Use browser download
        final bytes = utf8.encode(csv);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'items_import_template.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
        
        print('✅ Template downloaded via browser');
        return 'items_import_template.csv';
      } else {
        // Mobile/Desktop: Use file system
        final directory = await _getDownloadsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${directory.path}/items_import_template_$timestamp.csv';
        
        print('📁 Saving to: $filePath');
        
        final file = File(filePath);
        await file.writeAsString(csv);

        print('✅ Template saved successfully');
        
        return filePath;
      }
    } catch (e) {
      print('❌ Error downloading template: $e');
      throw Exception('Error downloading template: $e');
    }
  }

  // ==================== EXPORT FUNCTIONALITY ====================

  /// Export items to CSV
  Future<String> exportItemsToCSV(List<Map<String, dynamic>> items) async {
    try {
      print('📤 Starting CSV export for ${items.length} items...');
      
      if (items.isEmpty) {
        throw Exception('No items to export');
      }

      // Prepare CSV data
      List<List<dynamic>> csvData = [
        // Header row
        [
          'Name',
          'Type',
          'Unit',
          'Selling Price',
          'Cost Price',
          'Sales Account',
          'Purchase Account',
          'Sales Description',
          'Purchase Description',
          'Is Sellable',
          'Is Purchasable',
          'Created At',
        ],
      ];

      // Data rows
      for (var item in items) {
        csvData.add([
          item['name'] ?? '',
          item['type'] ?? '',
          item['unit'] ?? '',
          item['sellingPrice']?.toString() ?? '',
          item['costPrice']?.toString() ?? '',
          item['salesAccount'] ?? '',
          item['purchaseAccount'] ?? '',
          item['salesDescription'] ?? '',
          item['purchaseDescription'] ?? '',
          item['isSellable']?.toString() ?? 'true',
          item['isPurchasable']?.toString() ?? 'true',
          item['createdAt'] ?? '',
        ]);
      }

      String csv = const ListToCsvConverter().convert(csvData);

      // Handle web vs mobile/desktop differently
      if (kIsWeb) {
        // Web: Use browser download
        final bytes = utf8.encode(csv);
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'items_export_$timestamp.csv')
          ..click();
        html.Url.revokeObjectUrl(url);
        
        print('✅ Export downloaded via browser');
        return 'items_export_$timestamp.csv';
      } else {
        // Mobile/Desktop: Use file system
        final directory = await _getDownloadsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${directory.path}/items_export_$timestamp.csv';
        
        print('📁 Saving to: $filePath');
        
        final file = File(filePath);
        await file.writeAsString(csv);

        print('✅ Export completed successfully');

        return filePath;
      }
    } catch (e) {
      print('❌ Error exporting to CSV: $e');
      throw Exception('Error exporting to CSV: $e');
    }
  }

  /// Export items to Excel (as CSV format)
  Future<String> exportItemsToExcel(List<Map<String, dynamic>> items) async {
    try {
      print('📤 Starting Excel export...');
      // For now, export as CSV (Excel can open CSV files)
      // To implement proper .xlsx export, add the 'excel' package
      final filePath = await exportItemsToCSV(items);
      print('✅ Excel export completed (as CSV format)');
      return filePath;
    } catch (e) {
      throw Exception('Error exporting to Excel: $e');
    }
  }

  /// Export items to PDF
  Future<String> exportItemsToPDF(List<Map<String, dynamic>> items) async {
    try {
      print('📤 Starting PDF export for ${items.length} items...');
      
      if (items.isEmpty) {
        throw Exception('No items to export');
      }

      final pdf = pw.Document();

      // Add page with items table
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            // Title
            pw.Header(
              level: 0,
              child: pw.Text(
                'Items Export Report',
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
            
            // Items table
            pw.Table.fromTextArray(
              headers: [
                'Name',
                'Type',
                'Unit',
                'Selling Price',
                'Cost Price',
                'Sales Account',
              ],
              data: items.map((item) => [
                item['name'] ?? '',
                item['type'] ?? '',
                item['unit'] ?? '',
                item['sellingPrice'] != null ? '₹${item['sellingPrice']}' : '-',
                item['costPrice'] != null ? '₹${item['costPrice']}' : '-',
                item['salesAccount'] ?? '',
              ]).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellHeight: 25,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerLeft,
              },
            ),
            
            pw.SizedBox(height: 20),
            
            // Footer
            pw.Text(
              'Total Items: ${items.length}',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

      // Handle web vs mobile/desktop differently
      if (kIsWeb) {
        // Web: Use browser download
        final pdfBytes = await pdf.save();
        final blob = html.Blob([pdfBytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'items_export_$timestamp.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);
        
        print('✅ PDF export downloaded via browser');
        return 'items_export_$timestamp.pdf';
      } else {
        // Mobile/Desktop: Use file system
        final directory = await _getDownloadsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${directory.path}/items_export_$timestamp.pdf';
        
        print('📁 Saving to: $filePath');
        
        final file = File(filePath);
        await file.writeAsBytes(await pdf.save());

        print('✅ PDF export completed successfully');

        return filePath;
      }
    } catch (e) {
      print('❌ Error exporting to PDF: $e');
      throw Exception('Error exporting to PDF: $e');
    }
  }
}
