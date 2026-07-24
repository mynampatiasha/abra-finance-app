const fs = require('fs');

const dartFile = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_frontend/billing_frontend/lib/features/billing/pages/customer_detail_page.dart';
let dart = fs.readFileSync(dartFile, 'utf8');

// Use regex to replace to avoid whitespace/CRLF issues
dart = dart.replace(/String url = '\$baseUrl\/billing-customers\/\$\{widget\.customerId\}\/statement\/pdf';/, "String url = '$baseUrl/finance/customers/${widget.customerId}/statement/pdf?token=$token&branchIds=$branchHdr';");
dart = dart.replace(/final String baseUrl = ApiConfig\.baseUrl \+ '\/api';/, "final prefs = await SharedPreferences.getInstance();\n        final token = prefs.getString('jwt_token') ?? '';\n        final branchHdr = await FinanceSecureStorage.getBranchHeader();\n        final String baseUrl = ApiConfig.baseUrl + '/api';");
dart = dart.replace(/\?fromDate=/, "&fromDate=");
dart = dart.replace(/\$\{\_statementFrom \!\= null \? '\&' : '\?'\}toDate=/, "&toDate=");
fs.writeFileSync(dartFile, dart);

const jsFile = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_backend/routes/billing-customers.js';
let js = fs.readFileSync(jsFile, 'utf8');
const oldJsRegex = /doc\.fontSize\(10\)\.fillColor\('#000000'\)\.font\('Helvetica-Bold'\)\s*\.text\(customer\.customerDisplayName \|\| 'N\/A', billX \+ 8, metaY \+ 18, \{ width: colW \- 26 \}\);/;
const newJs = `doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold')
         .text(customer.customerDisplayName || 'N/A', billX + 8, metaY + 18, { width: colW - 26 });

      let custAddr = '';
      if (customer.billingAddress && customer.billingAddress.street) {
        custAddr = [
          customer.billingAddress.street,
          customer.billingAddress.city ? customer.billingAddress.city + ' - ' + (customer.billingAddress.zip || '') : '',
          customer.billingAddress.state,
          customer.billingAddress.country
        ].filter(Boolean).join('\\n');
      } else {
        custAddr = [
          customer.addressLine1,
          customer.city ? customer.city + ' - ' + (customer.postalCode || '') : '',
          customer.state,
          customer.country
        ].filter(Boolean).join('\\n');
      }
      if (custAddr) {
        doc.fontSize(8).font('Helvetica').fillColor('#555555')
           .text(custAddr, billX + 8, metaY + 32, { width: colW - 26 });
      }`;
js = js.replace(oldJsRegex, newJs);
fs.writeFileSync(jsFile, js);
console.log('Fixed successfully!');
