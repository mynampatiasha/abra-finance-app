import os
import re

files_info = {
    'quote_detail_page.dart': { 'id': 'widget.quoteId', 'endpoint': '/api/finance/quotes', 'number': "_quote?.quoteNumber ?? 'Quote'" },
    'sales_order_detail_page.dart': { 'id': 'widget.salesOrderId', 'endpoint': '/api/finance/sales-orders', 'number': "_salesOrder?.salesOrderNumber ?? 'Sales Order'" },
    'delivery_challan_detail_page.dart': { 'id': 'widget.deliveryChallanId', 'endpoint': '/api/finance/delivery-challans', 'number': "_deliveryChallan?.challanNumber ?? 'Delivery Challan'" },
    'credit_note_detail_page.dart': { 'id': 'widget.creditNoteId', 'endpoint': '/api/finance/credit-notes', 'number': "_creditNote?.creditNoteNumber ?? 'Credit Note'" },
    'bill_detail_page.dart': { 'id': 'widget.billId', 'endpoint': '/api/finance/bills', 'number': "_bill?.billNumber ?? 'Bill'" },
    'payment_made_detail_page.dart': { 'id': 'widget.paymentId', 'endpoint': '/api/finance/payments-made', 'number': "_payment?.paymentNumber ?? 'Payment Made'" },
    'purchase_order_detail_page.dart': { 'id': 'widget.purchaseOrderId', 'endpoint': '/api/finance/purchase-orders', 'number': "_po?.purchaseOrderNumber ?? 'Purchase Order'" },
    'expense_detail_page.dart': { 'id': 'widget.expenseId', 'endpoint': '/api/finance/expenses', 'number': "_expense?.expenseNumber ?? 'Expense'" },
    'vendor_credit_detail.dart': { 'id': 'widget.vendorCreditId', 'endpoint': '/api/finance/vendor-credits', 'number': "_vc?.vendorCreditNumber ?? 'Vendor Credit'" },
    'payment_received_detail_page.dart': { 'id': 'widget.paymentId', 'endpoint': '/api/finance/payments-received', 'number': "_payment?['paymentNumber']?.toString() ?? widget.payment?['paymentNumber']?.toString() ?? 'Payment Received'" },
}

base_dir = r"D:\Fleet_Management\Fleet_Management\Abra_finance_system\Billing_frontend\billing_frontend\lib\features\billing\pages"

for file_name, info in files_info.items():
    file_path = os.path.join(base_dir, file_name)
    if not os.path.exists(file_path):
        print(f"Skipping {file_name}, not found.")
        continue

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if "import '../widgets/document_preview_buttons.dart';" not in content:
        # insert after first import
        content = re.sub(r"(import .*?;)", r"\1\nimport '../widgets/document_preview_buttons.dart';", content, count=1)

    icon_btn_code = f'''
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
              tooltip: 'View PDF',
              onPressed: () async {{
                await openDocumentPdf(
                  context: context,
                  docId: {info['id']},
                  pdfEndpoint: '{info['endpoint']}',
                  docNumber: {info['number']},
                );
              }},
            ),'''
    
    if "openDocumentPdf(" not in content:
        # find ctions: [ block that belongs to the appbar
        content = re.sub(r"(actions:\s*\[)", r"\1" + icon_btn_code, content, count=1)
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Patched {file_name}")
    else:
        print(f"{file_name} already has openDocumentPdf")
