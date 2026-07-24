const fs = require('fs');
const dartFile = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_frontend/billing_frontend/lib/features/billing/pages/customer_detail_page.dart';
let dart = fs.readFileSync(dartFile, 'utf8');

if (!dart.includes('int _incomeMonths = 6;')) {
  dart = dart.replace(/String _mailFilter = 'All';/, "String _mailFilter = 'All';\n  int _incomeMonths = 6;");
}

if (!dart.includes('months: _incomeMonths')) {
  dart = dart.replace(/await BillingCustomersService\.getCustomerOverview\(widget\.customerId\);/, "await BillingCustomersService.getCustomerOverview(widget.customerId, months: _incomeMonths);");
}

fs.writeFileSync(dartFile, dart);
console.log('Fixed _incomeMonths issue!');
