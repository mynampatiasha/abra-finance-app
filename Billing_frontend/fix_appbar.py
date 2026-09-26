import os
import re

file_path = r"D:\Fleet_Management\Fleet_Management\Abra_finance_system\Billing_frontend\billing_frontend\lib\features\billing\pages\payment_received_detail_page.dart"

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# The incorrect injection starts at line 115:             IconButton(\n... inside the AlertDialog
# We will use regex to remove that block.
icon_button_pattern = r'''\s*IconButton\(\s*icon: const Icon\(Icons\.picture_as_pdf_outlined, color: Colors\.white\),\s*tooltip: 'View PDF',\s*onPressed: \(\) async \{\s*await openDocumentPdf\(\s*context: context,\s*docId: _paymentId,\s*pdfEndpoint: '/api/finance/payments-received',\s*docNumber: _payment\['paymentNumber'\]\?\.toString\(\) \?\? widget\.payment\['paymentNumber'\]\?\.toString\(\) \?\? 'Payment Received',\s*\);\s*\},\s*\),'''

# First remove the incorrect block
content = re.sub(icon_button_pattern, '', content)

# Now find the AppBar actions block inside _buildAppBar
appbar_pattern = r'''(child: AppBar\(\s*backgroundColor: Colors\.transparent,\s*elevation: 0,\s*foregroundColor: Colors\.white,\s*title:\s*Text\(title, style: const TextStyle\(fontWeight: FontWeight\.bold\)\),\s*actions: \[)'''

correct_injection = r'''\1
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
              tooltip: 'View PDF',
              onPressed: () async {
                await openDocumentPdf(
                  context: context,
                  docId: _paymentId,
                  pdfEndpoint: '/api/finance/payments-received',
                  docNumber: _payment['paymentNumber']?.toString() ?? widget.payment['paymentNumber']?.toString() ?? 'Payment Received',
                );
              },
            ),'''

content = re.sub(appbar_pattern, correct_injection, content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Fixed payment_received_detail_page.dart")
