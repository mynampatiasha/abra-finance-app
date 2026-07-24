const fs = require('fs');
const path = require('path');
const file = path.join(__dirname, 'lib', 'features', 'billing', 'pages', 'customer_detail_page.dart');
const lines = fs.readFileSync(file, 'utf8').split('\n');

let newLines = [];
let inPdfBlock = false;
let pdfBlockDone = false;

const newFunc = [
  "  Future<void> _exportStatementPdf() async {",
  "    if (_statement == null) return;",
  "    try {",
  "      final String baseUrl = dotenv.env['API_URL'] ?? 'http://localhost:5000/api';",
  "      String url = '$baseUrl/billing-customers/${widget.customer.id}/statement/pdf';",
  "      if (_statementFrom != null) {",
  "        url += '?fromDate=${_statementFrom!.toIso8601String()}';",
  "      }",
  "      if (_statementTo != null) {",
  "        url += '${_statementFrom != null ? '&' : '?'}toDate=${_statementTo!.toIso8601String()}';",
  "      }",
  "      ",
  "      final Uri uri = Uri.parse(url);",
  "      if (await canLaunchUrl(uri)) {",
  "        await launchUrl(uri, mode: LaunchMode.externalApplication);",
  "      } else {",
  "        if (mounted) {",
  "          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(",
  "              content: Text('Could not launch PDF viewer'),",
  "              backgroundColor: Colors.red));",
  "        }",
  "      }",
  "    } catch (e) {",
  "      if (mounted) {",
  "        ScaffoldMessenger.of(context).showSnackBar(SnackBar(",
  "            content: Text('Error: $e'), backgroundColor: Colors.red));",
  "      }",
  "    }",
  "  }"
].join('\n');

for (let i = 0; i < lines.length; i++) {
  if (lines[i].includes('Future<void> _exportStatementPdf() async {') && !pdfBlockDone) {
    inPdfBlock = true;
    newLines.push(newFunc);
  }
  
  if (inPdfBlock) {
    if (lines[i].includes('Future<void> _postComment() async {')) {
      inPdfBlock = false;
      pdfBlockDone = true;
      newLines.push(lines[i]);
    }
  } else {
    newLines.push(lines[i]);
  }
}

fs.writeFileSync(file, newLines.join('\n'));
console.log('Replaced _exportStatementPdf');
