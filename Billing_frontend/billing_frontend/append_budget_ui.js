const fs = require('fs');

let content = fs.readFileSync('lib/features/billing/pages/budget_detail.dart', 'utf8');

const newImports = `
import 'package:open_file/open_file.dart';
`;
content = content.replace("import 'new_budget.dart';", "import 'new_budget.dart';\n" + newImports);

const newMethods = `
  Future<void> _exportPdf() async {
    if (_budget == null) return;
    try {
      AppSnackBar.showInfo(context, 'Generating PDF...');
      final path = await BudgetService.downloadBudgetPDF(
        _budget!.id,
        startDate: _filterStart,
        endDate: _filterEnd,
      );
      OpenFile.open(path);
    } catch (e) {
      AppSnackBar.showError(context, e.toString());
    }
  }

  Future<void> _exportExcel() async {
    if (_budget == null) return;
    try {
      AppSnackBar.showInfo(context, 'Generating Excel...');
      final path = await BudgetService.downloadBudgetExcel(
        _budget!.id,
        startDate: _filterStart,
        endDate: _filterEnd,
      );
      OpenFile.open(path);
    } catch (e) {
      AppSnackBar.showError(context, e.toString());
    }
  }
`;

content = content.replace("  Future<void> _goEdit() async {", newMethods + "\n  Future<void> _goEdit() async {");

const newButtons = `
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Export PDF',
                  onPressed: _exportPdf,
                ),
                IconButton(
                  icon: const Icon(Icons.table_view_outlined),
                  tooltip: 'Export Excel',
                  onPressed: _exportExcel,
                ),
`;

content = content.replace(
  "                  icon: const Icon(Icons.refresh),",
  newButtons + "                  icon: const Icon(Icons.refresh),"
);

fs.writeFileSync('lib/features/billing/pages/budget_detail.dart', content);
console.log('Appended UI export buttons to budget_detail.dart');
