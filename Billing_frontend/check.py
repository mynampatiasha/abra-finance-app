import os
import glob

base_dir = r"D:\Fleet_Management\Fleet_Management\Abra_finance_system\Billing_frontend\billing_frontend\lib\features\billing\pages"
files = glob.glob(os.path.join(base_dir, '*_detail_page.dart')) + [os.path.join(base_dir, 'vendor_credit_detail.dart')]

for fpath in files:
    if not os.path.exists(fpath): continue
    with open(fpath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    for i, line in enumerate(lines):
        if 'Icons.picture_as_pdf_outlined' in line:
            print(f"\n--- {os.path.basename(fpath)} ---")
            start = max(0, i-5)
            end = min(len(lines), i+5)
            for j in range(start, end):
                print(lines[j].rstrip())
            break
