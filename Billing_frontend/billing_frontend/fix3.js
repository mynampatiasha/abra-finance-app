const fs = require('fs');
const dartFile = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_frontend/billing_frontend/lib/features/billing/pages/customer_detail_page.dart';
let dart = fs.readFileSync(dartFile, 'utf8');

// Fix duplicate prefs
dart = dart.replace(/final prefs = await SharedPreferences\.getInstance\(\);\s*final token = prefs\.getString\('jwt_token'\) \?\? '';\s*final branchHdr = await FinanceSecureStorage\.getBranchHeader\(\);\s*final prefs = await SharedPreferences\.getInstance\(\);\s*final token = prefs\.getString\('jwt_token'\) \?\? '';\s*final branchHdr = await FinanceSecureStorage\.getBranchHeader\(\);/g, 
  "final prefs = await SharedPreferences.getInstance();\n        final token = prefs.getString('jwt_token') ?? '';\n        final branchHdr = await FinanceSecureStorage.getBranchHeader();");

fs.writeFileSync(dartFile, dart);
console.log('Dart fixed.');
