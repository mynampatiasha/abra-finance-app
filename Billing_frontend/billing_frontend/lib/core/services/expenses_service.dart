import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../../core/services/api_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class ExpenseService {
  // Use ApiService singleton for all authenticated API calls
  static final ApiService _api = ApiService();
  
  // Base endpoint for expenses
  static const String _baseEndpoint = '/api/finance/expenses';
  
  // ============================================================================
  // GET ALL EXPENSES
  // ============================================================================
  
  Future<Map<String, dynamic>> getAllExpenses() async {
    try {
      print('📤 GET: $_baseEndpoint');
      
      final data = await _api.get(_baseEndpoint);
      
      print('✅ Expenses fetched: ${data['data']?.length ?? 0}');
      
      return data;
    } catch (e) {
      print('❌ Error fetching expenses: $e');
      rethrow;
    }
  }

  // ============================================================================
  // GET SINGLE EXPENSE BY ID
  // ============================================================================
  
  Future<Map<String, dynamic>> getExpenseById(String id) async {
    try {
      print('📤 GET: $_baseEndpoint/$id');
      
      final data = await _api.get('$_baseEndpoint/$id');
      
      print('✅ Expense fetched: ID $id');
      
      return data;
    } catch (e) {
      print('❌ Error fetching expense: $e');
      rethrow;
    }
  }

  // ============================================================================
  // CREATE NEW EXPENSE WITH PROPER WEB/MOBILE FILE HANDLING
  // ============================================================================
  
  // FIXED: expenses_service.dart - Critical fixes in createExpense method

// Around line 70-120 in createExpense method:

// ISSUE: The service was adding amount even for itemized expenses
// This confused the backend which then calculated totals incorrectly

// BEFORE (WRONG):
/*
if (amount != null && amount.isNotEmpty) {
  request.fields['amount'] = amount.toString();  // ❌ Added even when amount='0'
}
*/

// AFTER (CORRECT):
/*
// Only add amount if NOT itemized and amount is valid
if (!isItemized && amount != null && amount.isNotEmpty && amount != '0') {
  request.fields['amount'] = amount;  // ✅ Don't use toString() - already a string
}
*/

// FULL FIXED createExpense METHOD:

Future<Map<String, dynamic>> createExpense({
  required String date,
  required String expenseAccount,
  required String paidThrough,
  String? amount,
  String? tax,
  String? vendor,
  String? invoiceNumber,
  String? customerName,
  bool isBillable = false,
  String? project,
  double markupPercentage = 0.0,
  List<String>? reportingTags,
  String? notes,
  bool isItemized = false,
  List<Map<String, dynamic>>? itemizedExpenses,
  File? receiptFile,
}) async {
  try {
    print('📤 POST: $_baseEndpoint (multipart)');
    print('📊 Creating expense:');
    print('  - Date: $date');
    print('  - Account: $expenseAccount');
    print('  - Amount: $amount');
    print('  - Tax: $tax');
    print('  - Paid Through: $paidThrough');
    print('  - Is Itemized: $isItemized');
    
    // Get auth headers from ApiService
    final headers = await _api.getHeaders();
    
    // Create multipart request with auth headers
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${_api.baseUrl}$_baseEndpoint'),
    );
    
    // Add auth headers (remove Content-Type as it's set automatically for multipart)
    headers.forEach((key, value) {
      if (key.toLowerCase() != 'content-type') {
        request.headers[key] = value;
      }
    });

    // Add REQUIRED form fields
    request.fields['date'] = date;
    request.fields['expenseAccount'] = expenseAccount;
    request.fields['paidThrough'] = paidThrough;
    
    // FIXED: Only send amount for NON-itemized expenses
    if (!isItemized && amount != null && amount.isNotEmpty && amount != '0') {
      request.fields['amount'] = amount;
      print('  ✅ Amount field set to: $amount');
    } else if (isItemized) {
      print('  ℹ️  Skipping amount field (itemized expense)');
    }
    
    // FIXED: Always send tax, but as '0' if empty
    if (tax != null && tax.isNotEmpty) {
      request.fields['tax'] = tax;
      print('  ✅ Tax field set to: $tax');
    } else {
      request.fields['tax'] = '0';
      print('  ✅ Tax field set to: 0 (default)');
    }
    
    // Add optional fields
    if (vendor != null && vendor.isNotEmpty) {
      request.fields['vendor'] = vendor;
    }
    if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
      request.fields['invoiceNumber'] = invoiceNumber;
    }
    if (customerName != null && customerName.isNotEmpty) {
      request.fields['customerName'] = customerName;
    }
    
    request.fields['isBillable'] = isBillable.toString();
    
    if (project != null && project.isNotEmpty) {
      request.fields['project'] = project;
    }
    request.fields['markupPercentage'] = markupPercentage.toString();
    
    if (reportingTags != null && reportingTags.isNotEmpty) {
      request.fields['reportingTags'] = json.encode(reportingTags);
    }
    
    if (notes != null && notes.isNotEmpty) {
      request.fields['notes'] = notes;
    }
    
    request.fields['isItemized'] = isItemized.toString();
    
    if (itemizedExpenses != null && itemizedExpenses.isNotEmpty) {
      request.fields['itemizedExpenses'] = json.encode(itemizedExpenses);
      print('  ✅ Itemized expenses: ${itemizedExpenses.length} items');
      
      // Calculate and log total for itemized expenses
      double itemizedTotal = 0;
      for (var item in itemizedExpenses) {
        itemizedTotal += (item['amount'] as num).toDouble();
      }
      print('  ℹ️  Itemized total: ₹$itemizedTotal');
    }

    // Add receipt file with web support
    if (receiptFile != null) {
      try {
        String? mimeType = lookupMimeType(receiptFile.path);
        List<String> mimeTypeParts = mimeType?.split('/') ?? ['application', 'octet-stream'];
        
        if (kIsWeb) {
          final bytes = await receiptFile.readAsBytes();
          request.files.add(
            http.MultipartFile.fromBytes(
              'receipt',
              bytes,
              filename: receiptFile.path.split('/').last,
              contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
            ),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath(
              'receipt',
              receiptFile.path,
              contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
            ),
          );
        }
        print('  ✅ Receipt attached: ${receiptFile.path.split('/').last}');
      } catch (e) {
        print('⚠️ Warning: Could not attach receipt: $e');
      }
    }

    // Send request
    print('📡 Sending request...');
    print('📋 Request fields: ${request.fields}');
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    print('📥 Response status: ${response.statusCode}');
    print('📥 Response body: ${response.body}');
    
    if (response.statusCode == 201) {
      print('✅ Expense created successfully');
      final responseData = json.decode(response.body);
      
      // Log the created expense details
      if (responseData['data'] != null) {
        final expense = responseData['data'];
        print('✅ Created expense ID: ${expense['_id']}');
        print('✅ Amount: ₹${expense['amount']}');
        print('✅ Tax: ₹${expense['tax']}');
        print('✅ Total: ₹${expense['total']}');
      }
      
      return responseData;
    } else {
      final errorBody = json.decode(response.body);
      print('❌ Error creating expense: ${errorBody['message']}');
      if (errorBody['errors'] != null) {
        print('❌ Validation errors: ${errorBody['errors']}');
      }
      throw Exception(errorBody['message'] ?? 'Failed to create expense');
    }
  } catch (e) {
    print('❌ Error creating expense: $e');
    rethrow;
  }
}

  // ============================================================================
  // UPDATE EXPENSE WITH PROPER WEB/MOBILE FILE HANDLING
  // ============================================================================
  
  Future<Map<String, dynamic>> updateExpense({
    required String id,
    String? date,
    String? expenseAccount,
    String? paidThrough,
    String? amount,
    String? tax,
    String? vendor,
    String? invoiceNumber,
    String? customerName,
    bool? isBillable,
    String? project,
    double? markupPercentage,
    List<String>? reportingTags,
    String? notes,
    bool? isItemized,
    List<Map<String, dynamic>>? itemizedExpenses,
    File? receiptFile,
    bool deleteReceipt = false,
  }) async {
    try {
      print('📤 PUT: $_baseEndpoint/$id (multipart)');
      
      // Get auth headers from ApiService
      final headers = await _api.getHeaders();
      
      // Create multipart request with auth headers
      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('${_api.baseUrl}$_baseEndpoint/$id'),
      );
      
      // Add auth headers (remove Content-Type as it's set automatically for multipart)
      headers.forEach((key, value) {
        if (key.toLowerCase() != 'content-type') {
          request.headers[key] = value;
        }
      });

      // Add form fields (only if provided)
      if (date != null) request.fields['date'] = date;
      if (expenseAccount != null) request.fields['expenseAccount'] = expenseAccount;
      if (paidThrough != null) request.fields['paidThrough'] = paidThrough;
      if (amount != null) request.fields['amount'] = amount;
      if (tax != null) request.fields['tax'] = tax;
      if (vendor != null) request.fields['vendor'] = vendor;
      if (invoiceNumber != null) request.fields['invoiceNumber'] = invoiceNumber;
      if (customerName != null) request.fields['customerName'] = customerName;
      if (isBillable != null) request.fields['isBillable'] = isBillable.toString();
      if (project != null) request.fields['project'] = project;
      if (markupPercentage != null) request.fields['markupPercentage'] = markupPercentage.toString();
      
      if (reportingTags != null) {
        request.fields['reportingTags'] = json.encode(reportingTags);
      }
      
      if (notes != null) request.fields['notes'] = notes;
      if (isItemized != null) request.fields['isItemized'] = isItemized.toString();
      
      if (itemizedExpenses != null) {
        request.fields['itemizedExpenses'] = json.encode(itemizedExpenses);
      }

      if (deleteReceipt) {
        request.fields['deleteReceipt'] = 'true';
      }

      // Add receipt file with web support
      if (receiptFile != null) {
        try {
          String? mimeType = lookupMimeType(receiptFile.path);
          List<String> mimeTypeParts = mimeType?.split('/') ?? ['application', 'octet-stream'];
          
          if (kIsWeb) {
            // For web: Read file as bytes
            final bytes = await receiptFile.readAsBytes();
            request.files.add(
              http.MultipartFile.fromBytes(
                'receipt',
                bytes,
                filename: receiptFile.path.split('/').last,
                contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
              ),
            );
          } else {
            // For mobile: Use fromPath
            request.files.add(
              await http.MultipartFile.fromPath(
                'receipt',
                receiptFile.path,
                contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
              ),
            );
          }
        } catch (e) {
          print('⚠️ Warning: Could not attach receipt: $e');
        }
      }

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        print('✅ Expense updated successfully');
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        print('❌ Expense not found');
        throw Exception('Expense not found');
      } else {
        final errorBody = json.decode(response.body);
        print('❌ Error updating expense: ${errorBody['message']}');
        throw Exception(errorBody['message'] ?? 'Failed to update expense');
      }
    } catch (e) {
      print('❌ Error updating expense: $e');
      rethrow;
    }
  }

  // ============================================================================
  // DELETE EXPENSE
  // ============================================================================
  
  Future<Map<String, dynamic>> deleteExpense(String id) async {
    try {
      print('📤 DELETE: $_baseEndpoint/$id');
      
      final data = await _api.delete('$_baseEndpoint/$id');
      
      print('✅ Expense deleted successfully');
      
      return data;
    } catch (e) {
      print('❌ Error deleting expense: $e');
      rethrow;
    }
  }

  // ============================================================================
  // DOWNLOAD RECEIPT
  // ============================================================================
  
  Future<String> downloadReceipt(String id) async {
    try {
      print('📤 GET: $_baseEndpoint/$id/receipt (Receipt download)');
      
      // Return the URL for download
      final url = '${_api.baseUrl}$_baseEndpoint/$id/receipt';
      
      print('✅ Receipt URL: $url');
      
      return url;
    } catch (e) {
      print('❌ Error getting receipt URL: $e');
      rethrow;
    }
  }

  // ============================================================================
  // GET EXPENSE STATISTICS
  // ============================================================================
  
  Future<Map<String, dynamic>> getExpenseStatistics() async {
    try {
      print('📤 GET: $_baseEndpoint/stats/summary');
      
      final data = await _api.get('$_baseEndpoint/stats/summary');
      
      print('✅ Expense statistics fetched');
      
      return data;
    } catch (e) {
      print('❌ Error fetching statistics: $e');
      rethrow;
    }
  }

  // ============================================================================
  // BULK IMPORT EXPENSES FROM EXCEL/CSV
  // ============================================================================
  
  Future<Map<String, dynamic>> bulkImportExpenses(File file) async {
    try {
      print('📤 POST: $_baseEndpoint/import/bulk (Bulk import)');
      print('📊 File: ${file.path}');
      
      // Get auth headers from ApiService
      final headers = await _api.getHeaders();
      
      // Create multipart request with auth headers
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${_api.baseUrl}$_baseEndpoint/import/bulk'),
      );
      
      // Add auth headers (remove Content-Type as it's set automatically for multipart)
      headers.forEach((key, value) {
        if (key.toLowerCase() != 'content-type') {
          request.headers[key] = value;
        }
      });

      // Add file with web support
      try {
        String? mimeType = lookupMimeType(file.path);
        
        // Default to Excel MIME type if not detected
        if (mimeType == null) {
          final extension = file.path.split('.').last.toLowerCase();
          if (extension == 'xlsx') {
            mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          } else if (extension == 'xls') {
            mimeType = 'application/vnd.ms-excel';
          } else if (extension == 'csv') {
            mimeType = 'text/csv';
          } else {
            mimeType = 'application/octet-stream';
          }
        }
        
        List<String> mimeTypeParts = mimeType.split('/');
        
        if (kIsWeb) {
          // For web: Read file as bytes
          final bytes = await file.readAsBytes();
          request.files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: file.path.split('/').last,
              contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
            ),
          );
          print('  - Added file from bytes (web): ${bytes.length} bytes');
        } else {
          // For mobile: Use fromPath
          request.files.add(
            await http.MultipartFile.fromPath(
              'file',
              file.path,
              contentType: MediaType(mimeTypeParts[0], mimeTypeParts[1]),
            ),
          );
          print('  - Added file from path (mobile): ${file.path}');
        }
      } catch (e) {
        print('❌ Error adding file to request: $e');
        throw Exception('Failed to read import file: $e');
      }

      // Send request
      print('📡 Sending bulk import request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Expenses imported successfully');
        final responseData = json.decode(response.body);
        print('Import result: ${responseData['data']}');
        return responseData;
      } else {
        final errorBody = json.decode(response.body);
        print('❌ Error importing expenses: ${errorBody['message']}');
        throw Exception(errorBody['message'] ?? 'Failed to import expenses');
      }
    } catch (e) {
      print('❌ Error importing expenses: $e');
      rethrow;
    }
  }

  // ============================================================================
  // DOWNLOAD IMPORT TEMPLATE
  // ============================================================================
  
  Future<String> getImportTemplateUrl() async {
    try {
      final url = '${_api.baseUrl}$_baseEndpoint/import/template';
      print('✅ Import template URL: $url');
      return url;
    } catch (e) {
      print('❌ Error getting template URL: $e');
      rethrow;
    }
  }
}

// ============================================================================
// MODEL CLASSES WITH SAFE PARSING - FIXED _id HANDLING
// ============================================================================

class Expense {
  final String id;  // Changed from int to String for MongoDB _id
  final String? expenseNumber;
  final String date;
  final String expenseAccount;
  final double amount;
  final double tax;
  final double total;
  final String paidThrough;
  final String? vendor;
  final String? invoiceNumber;
  final String? customerName;
  final bool isBillable;
  final String? project;
  final double markupPercentage;
  final double billableAmount;
  final List<String> reportingTags;
  final String? notes;
  final bool isItemized;
  final List<ItemizedExpenseData> itemizedExpenses;
  final ReceiptFile? receiptFile;
  final ProofFile? proofFile;
  final String createdAt;
  final String updatedAt;

  Expense({
    required this.id,
    this.expenseNumber,
    required this.date,
    required this.expenseAccount,
    required this.amount,
    required this.tax,
    required this.total,
    required this.paidThrough,
    this.vendor,
    this.invoiceNumber,
    this.customerName,
    required this.isBillable,
    this.project,
    required this.markupPercentage,
    required this.billableAmount,
    required this.reportingTags,
    this.notes,
    required this.isItemized,
    required this.itemizedExpenses,
    this.receiptFile,
    this.proofFile,
    required this.createdAt,
    required this.updatedAt,
  });

  // FIXED: Safe parsing with MongoDB _id support
  factory Expense.fromJson(Map<String, dynamic> json) {
    // Helper function to safely parse numbers
    double _parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) {
        try {
          return double.parse(value);
        } catch (e) {
          print('⚠️ Warning: Could not parse "$value" as double, using 0.0');
          return 0.0;
        }
      }
      print('⚠️ Warning: Unexpected type for number: ${value.runtimeType}');
      return 0.0;
    }
    
    // FIXED: Parse MongoDB _id as String
    String _parseId(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      if (value is Map && value.containsKey('\$oid')) {
        return value['\$oid'].toString();
      }
      return value.toString();
    }
    
    // Helper function to safely parse strings
    String _parseString(dynamic value, String defaultValue) {
      if (value == null) return defaultValue;
      return value.toString();
    }
    
    // Helper function to safely parse booleans
    bool _parseBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is String) {
        return value.toLowerCase() == 'true' || value == '1';
      }
      if (value is num) return value != 0;
      return false;
    }
    
    try {
      return Expense(
        id: _parseId(json['_id'] ?? json['id']),  // FIXED: Handle both _id and id
        expenseNumber: json['expenseNumber'],
        date: _parseString(json['date'], ''),
        expenseAccount: _parseString(json['expenseAccount'], ''),
        amount: _parseDouble(json['amount']),
        tax: _parseDouble(json['tax']),
        total: _parseDouble(json['total']),
        paidThrough: _parseString(json['paidThrough'], ''),
        vendor: json['vendor'],
        invoiceNumber: json['invoiceNumber'],
        customerName: json['customerName'],
        isBillable: _parseBool(json['isBillable']),
        project: json['project'],
        markupPercentage: _parseDouble(json['markupPercentage']),
        billableAmount: _parseDouble(json['billableAmount']),
        reportingTags: (json['reportingTags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        notes: json['notes'],
        isItemized: _parseBool(json['isItemized']),
        itemizedExpenses: (json['itemizedExpenses'] as List?)
                ?.map((e) => ItemizedExpenseData.fromJson(e))
                .toList() ??
            [],
        receiptFile: json['receiptFile'] != null
            ? ReceiptFile.fromJson(json['receiptFile'])
            : null,
        proofFile: json['proofFile'] != null
            ? ProofFile.fromJson(json['proofFile'] as Map<String, dynamic>)
            : null,
        createdAt: _parseString(json['createdAt'], ''),
        updatedAt: _parseString(json['updatedAt'], ''),
      );
    } catch (e) {
      print('❌ Error parsing Expense from JSON: $e');
      print('JSON data: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'expenseNumber': expenseNumber,
      'date': date,
      'expenseAccount': expenseAccount,
      'amount': amount,
      'tax': tax,
      'total': total,
      'paidThrough': paidThrough,
      'vendor': vendor,
      'invoiceNumber': invoiceNumber,
      'customerName': customerName,
      'isBillable': isBillable,
      'project': project,
      'markupPercentage': markupPercentage,
      'billableAmount': billableAmount,
      'reportingTags': reportingTags,
      'notes': notes,
      'isItemized': isItemized,
      'itemizedExpenses': itemizedExpenses.map((e) => e.toJson()).toList(),
      'receiptFile': receiptFile?.toJson(),
      'proofFile': proofFile?.toJson(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class ItemizedExpenseData {
  final String? expenseAccount;
  final double amount;
  final String? description;

  ItemizedExpenseData({
    this.expenseAccount,
    required this.amount,
    this.description,
  });

  factory ItemizedExpenseData.fromJson(Map<String, dynamic> json) {
    // Helper function to safely parse numbers
    double _parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }
    
    return ItemizedExpenseData(
      expenseAccount: json['expenseAccount'],
      amount: _parseDouble(json['amount']),
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'expenseAccount': expenseAccount,
      'amount': amount,
      'description': description,
    };
  }
}

class ReceiptFile {
  final String filename;
  final String originalName;
  final String path;
  final int size;
  final String mimetype;

  ReceiptFile({
    required this.filename,
    required this.originalName,
    required this.path,
    required this.size,
    required this.mimetype,
  });

  factory ReceiptFile.fromJson(Map<String, dynamic> json) {
    return ReceiptFile(
      filename: json['filename'] ?? '',
      originalName: json['originalName'] ?? '',
      path: json['path'] ?? '',
      size: json['size'] ?? 0,
      mimetype: json['mimetype'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'originalName': originalName,
      'path': path,
      'size': size,
      'mimetype': mimetype,
    };
  }
}

class ProofFile {
  final String filename;
  final String originalName;
  final int size;
  final String mimetype;
  final String? uploadedAt;

  const ProofFile({
    required this.filename,
    required this.originalName,
    required this.size,
    required this.mimetype,
    this.uploadedAt,
  });

  factory ProofFile.fromJson(Map<String, dynamic> j) => ProofFile(
    filename:     j['filename']     as String,
    originalName: j['originalName'] as String,
    size:         (j['size'] as num).toInt(),
    mimetype:     j['mimetype']     as String,
    uploadedAt:   j['uploadedAt']   as String?,
  );

  Map<String, dynamic> toJson() => {
    'filename':     filename,
    'originalName': originalName,
    'size':         size,
    'mimetype':     mimetype,
    'uploadedAt':   uploadedAt,
  };

  bool get isImage => mimetype.startsWith('image/');
  bool get isPdf   => mimetype == 'application/pdf';
}
