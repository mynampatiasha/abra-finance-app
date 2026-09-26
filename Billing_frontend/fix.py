import os
import re

base_dir = r"D:\Fleet_Management\Fleet_Management\Abra_finance_system\Billing_frontend\billing_frontend\lib\features\billing\pages"

fixes = [
    {
        'file': 'sales_order_detail_page.dart',
        'replacements': [
            ("docNumber: _salesOrder?.salesOrderNumber", "docNumber: _order?.salesOrderNumber")
        ]
    },
    {
        'file': 'delivery_challan_detail_page.dart',
        'replacements': [
            ("docId: widget.deliveryChallanId", "docId: widget.challanId"),
            ("docNumber: _deliveryChallan?.challanNumber", "docNumber: _challan?.challanNumber")
        ]
    },
    {
        'file': 'payment_made_detail_page.dart',
        'replacements': [
            ("docId: widget.paymentId", "docId: _payment.id"),
            ("docNumber: _payment?.paymentNumber", "docNumber: _payment.paymentNumber")
        ]
    },
    {
        'file': 'vendor_credit_detail.dart',
        'replacements': [
            ("docId: widget.vendorCreditId", "docId: widget.creditId"),
            ("docNumber: _vc?.vendorCreditNumber", "docNumber: _credit?.vendorCreditNumber")
        ]
    }
]

for fix in fixes:
    file_path = os.path.join(base_dir, fix['file'])
    if not os.path.exists(file_path):
        print(f"File {fix['file']} not found")
        continue
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    for old, new in fix['replacements']:
        content = content.replace(old, new)
        
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
        
    print(f"Fixed {fix['file']}")
