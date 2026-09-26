const fs = require('fs');

const appendCode = `
  // ── Exports ───────────────────────────────────────────────────────────────

  static Future<String> downloadBudgetPDF(String id, {String? startDate, String? endDate}) async {
    final headers = await _getHeaders();
    final params = <String, String>{};
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;
    
    final uri = Uri.parse('\$_base/\$id/export-pdf').replace(queryParameters: params.isNotEmpty ? params : null);
    final res = await http.get(uri, headers: headers);
    
    if (res.statusCode != 200) {
      throw Exception('Failed to download PDF');
    }
    
    final tempDir = await getTemporaryDirectory();
    final file = File('\${tempDir.path}/budget_\${id}_\${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }

  static Future<String> downloadBudgetExcel(String id, {String? startDate, String? endDate}) async {
    final headers = await _getHeaders();
    final params = <String, String>{};
    if (startDate != null) params['startDate'] = startDate;
    if (endDate != null) params['endDate'] = endDate;
    
    final uri = Uri.parse('\$_base/\$id/export-excel').replace(queryParameters: params.isNotEmpty ? params : null);
    final res = await http.get(uri, headers: headers);
    
    if (res.statusCode != 200) {
      throw Exception('Failed to download Excel');
    }
    
    final tempDir = await getTemporaryDirectory();
    final file = File('\${tempDir.path}/budget_\${id}_\${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(res.bodyBytes);
    return file.path;
  }
}
`;

let content = fs.readFileSync('lib/core/services/budget_service.dart', 'utf8');
content = content.replace(/\s*\}\s*$/, '\n' + appendCode);
fs.writeFileSync('lib/core/services/budget_service.dart', content);
console.log('Appended methods to budget_service.dart');
