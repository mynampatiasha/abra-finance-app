const fs = require('fs');
const file = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_frontend/billing_frontend/lib/core/services/billing_customers_service.dart';
let code = fs.readFileSync(file, 'utf8');

// Update getCustomerOverview to accept {int months = 6}
code = code.replace(/static Future<CustomerOverviewData> getCustomerOverview\(\s*String customerId\) async \{/g, "static Future<CustomerOverviewData> getCustomerOverview(\n      String customerId, {int months = 6}) async {");

// Update URL to include ?months=...
code = code.replace(/Uri\.parse\('\$_endpoint\/\$customerId\/overview'\)/g, "Uri.parse('$_endpoint/$customerId/overview?months=$months')");

fs.writeFileSync(file, code);
console.log('Fixed billing_customers_service.dart!');
