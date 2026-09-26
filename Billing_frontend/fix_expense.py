import os
import re

file_path = r"D:\Fleet_Management\Fleet_Management\Abra_finance_system\Billing_frontend\billing_frontend\lib\features\billing\pages\expense_detail_page.dart"

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# First remove the incorrect block inside the alert dialog
icon_button_pattern = r'''\s*IconButton\(\s*icon: const Icon\(Icons\.picture_as_pdf_outlined, color: Colors\.white\),\s*tooltip: 'View PDF',\s*onPressed: \(\) async \{\s*await openDocumentPdf\(\s*context: context,\s*docId: widget\.expenseId,\s*pdfEndpoint: '/api/finance/expenses',\s*docNumber: _expense\?\.expenseNumber \?\? 'Expense',\s*\);\s*\},\s*\),'''

content = re.sub(icon_button_pattern, '', content)

# Now find the correct AppBar
appbar_pattern = r'''(child: AppBar\(\s*backgroundColor: Colors\.transparent,\s*elevation: 0,\s*foregroundColor: Colors\.white,\s*title: Text\(_expense\?\.expenseNumber \?\? 'Expense Detail',\s*style: const TextStyle\(fontWeight: FontWeight\.bold\)\),\s*actions: \[)'''

correct_injection = r'''\1
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
              tooltip: 'View PDF',
              onPressed: () async {
                await openDocumentPdf(
                  context: context,
                  docId: widget.expenseId,
                  pdfEndpoint: '/api/finance/expenses',
                  docNumber: _expense?.expenseNumber ?? 'Expense',
                );
              },
            ),'''

content = re.sub(appbar_pattern, correct_injection, content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Fixed expense_detail_page.dart")
