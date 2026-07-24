const fs = require('fs');

const dartFile = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_frontend/billing_frontend/lib/features/billing/pages/customer_detail_page.dart';
let dart = fs.readFileSync(dartFile, 'utf8');

// Fix the PDF URL
const oldUrl =         final String baseUrl = ApiConfig.baseUrl + '/api';\n        String url = '\\/billing-customers/\\/statement/pdf';;
const newUrl =         final prefs = await SharedPreferences.getInstance();\n        final token = prefs.getString('jwt_token') ?? '';\n        final branchHdr = await FinanceSecureStorage.getBranchHeader();\n        final String baseUrl = ApiConfig.baseUrl + '/api';\n        String url = '\\/finance/customers/\\/statement/pdf?token=\\&branchIds=\\';;
dart = dart.replace(oldUrl, newUrl);

// Fix the fromDate toDate bug
dart = dart.replace("url += '?fromDate'", "url += '&fromDate'");
dart = dart.replace("url += '\\toDate='", "url += '&toDate='");
fs.writeFileSync(dartFile, dart);

const jsFile = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_backend/routes/billing-customers.js';
let js = fs.readFileSync(jsFile, 'utf8');
const oldJs =       doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold')\n         .text(customer.customerDisplayName || 'N/A', billX + 8, metaY + 18, { width: colW - 26 });\n      \n      const summX = 40 + colW + 10;;
const newJs =       doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold')\n         .text(customer.customerDisplayName || 'N/A', billX + 8, metaY + 18, { width: colW - 26 });\n\n      let custAddr = '';\n      if (customer.billingAddress && customer.billingAddress.street) {\n        custAddr = [\n          customer.billingAddress.street,\n          customer.billingAddress.city ? customer.billingAddress.city + ' - ' + (customer.billingAddress.zip || '') : '',\n          customer.billingAddress.state,\n          customer.billingAddress.country\n        ].filter(Boolean).join('\\n');\n      } else {\n        custAddr = [\n          customer.addressLine1,\n          customer.city ? customer.city + ' - ' + (customer.postalCode || '') : '',\n          customer.state,\n          customer.country\n        ].filter(Boolean).join('\\n');\n      }\n      if (custAddr) {\n        doc.fontSize(8).font('Helvetica').fillColor('#555555')\n           .text(custAddr, billX + 8, metaY + 32, { width: colW - 26 });\n      }\n      \n      const summX = 40 + colW + 10;;
js = js.replace(oldJs, newJs);
fs.writeFileSync(jsFile, js);

console.log('Fixed successfully!');
