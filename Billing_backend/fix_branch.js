const fs = require('fs');
const path = require('path');
const dir = 'routes';

// Find all variants of the broken pattern
const BAD = 'branchId: (req.branchFilter || {}).branchId || null';
const GOOD_SPREAD = '...(req.branchFilter || {})';

let total = 0;
fs.readdirSync(dir).filter(f => f.endsWith('.js')).forEach(f => {
  const fp = path.join(dir, f);
  let c = fs.readFileSync(fp, 'utf8');
  if (!c.includes(BAD)) return;

  // Replace: "branchId: (req.branchFilter || {}).branchId || null, ...(req.branchFilter || {})"
  // with just: "...(req.branchFilter || {})"
  // Handle all whitespace/newline variants between the comma and the spread
  const regex = /branchId:\s*\(req\.branchFilter\s*\|\|\s*\{\}\)\.branchId\s*\|\|\s*null,\s*\.\.\.\(req\.branchFilter\s*\|\|\s*\{\}\)/g;
  const c2 = c.replace(regex, '...(req.branchFilter || {})');

  // Also fix standalone: "branchId: (req.branchFilter || {}).branchId || null,"
  // (used in object literals where spread is on next line separately)
  const regex2 = /branchId:\s*\(req\.branchFilter\s*\|\|\s*\{\}\)\.branchId\s*\|\|\s*null,?\s*\n/g;
  const c3 = c2.replace(regex2, '');

  if (c3 !== c) {
    fs.writeFileSync(fp, c3);
    total++;
    console.log('Fixed:', f);
  }
});
console.log('Total fixed:', total);
