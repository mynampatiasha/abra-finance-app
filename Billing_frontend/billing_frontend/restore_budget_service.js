const fs = require('fs');
let content = fs.readFileSync('lib/core/services/budget_service.dart', 'utf8');

content = content.replace("import 'dart:convert';", 
  "import 'dart:convert';\nimport 'dart:io';\nimport 'package:path_provider/path_provider.dart';\nimport 'package:flutter/foundation.dart' show kIsWeb;\nimport 'package:universal_html/html.dart' as html show Blob, Url, AnchorElement;");

const appendCode = `
  // ── Exports ───────────────────────────────────────────────────────────────

  static Future<String> downloadBudgetPDF(String id, {String? startDate, String? endDate}) async {
    final headers = await _getHeaders();
    final params = <String, String>{};
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;
    
    final uri = Uri.parse('\\$_base/\\$id/export-pdf').replace(queryParameters: params.isNotEmpty ? params : null);
    final res = await http.get(uri, headers: headers);
    
    if (res.statusCode != 200) {
      throw Exception('Failed to download PDF');
    }
    
    final filename = 'Budget_\\${id}_\\${DateTime.now().millisecondsSinceEpoch}.pdf';
    
    if (kIsWeb) {
      final blob = html.Blob([res.bodyBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
      return 'web_downloaded';
    } else {
      final tempDir = await getTemporaryDirectory();
      final file = File('\\${tempDir.path}/\\$filename');
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    }
  }

  static Future<String> downloadBudgetExcel(String id, {String? startDate, String? endDate}) async {
    final headers = await _getHeaders();
    final params = <String, String>{};
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;
    
    final uri = Uri.parse('\\$_base/\\$id/export-excel').replace(queryParameters: params.isNotEmpty ? params : null);
    final res = await http.get(uri, headers: headers);
    
    if (res.statusCode != 200) {
      throw Exception('Failed to download Excel');
    }
    
    final filename = 'Budget_\\${id}_\\${DateTime.now().millisecondsSinceEpoch}.xlsx';
    
    if (kIsWeb) {
      final blob = html.Blob([res.bodyBytes], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
      return 'web_downloaded';
    } else {
      final tempDir = await getTemporaryDirectory();
      final file = File('\\${tempDir.path}/\\$filename');
      await file.writeAsBytes(res.bodyBytes);
      return file.path;
    }
  }
}
`.replace(/\\\$/g, '$');

let content2 = content.replace(/\s*\}\s*$/, '\n' + appendCode);
fs.writeFileSync('lib/core/services/budget_service.dart', content2);
console.log('Restored budget_service.dart with Web support');
