const fs = require('fs');
let code = fs.readFileSync('routes/invoices.js', 'utf8');

// 1. Remove duplicate getSystemAccountId('Other Charges', currentOrgId, branchId),
code = code.replace(/getSystemAccountId\('Other Charges',\s*currentOrgId,\s*branchId\),\n\s*getSystemAccountId\('Other Charges',\s*currentOrgId,\s*branchId\),/g, 'getSystemAccountId(\'Other Charges\',          currentOrgId, branchId),');

// 2. Remove duplicate adjustment block using a precise regex
// We look for two consecutive identical "if (otherChargesId && invoice.adjustment) {" blocks.
// They are identical in characters. We can match the entire block.
const regex = /(if \(otherChargesId && invoice\.adjustment\) \{[\s\S]*?credit: invoice\.adjustment \}\);\n\s*\}\n\s*\})\n\s*if \(otherChargesId && invoice\.adjustment\) \{[\s\S]*?credit: invoice\.adjustment \}\);\n\s*\}\n\s*\}/g;

code = code.replace(regex, '$1');

fs.writeFileSync('routes/invoices.js', code);
console.log('Fixed duplications in invoices.js');
