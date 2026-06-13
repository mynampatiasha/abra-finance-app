const fs = require('fs');

const updatedGetSystemAccountId = `async function getSystemAccountId(name, orgId = null, branchId = null) {
  try {
    let query = { accountName: name, isSystemAccount: true };
    if (orgId) query.orgId = orgId;
    
    if (branchId) {
      let branchAcc = await ChartOfAccount.findOne({ ...query, branchId }).select('_id').lean();
      if (branchAcc) return branchAcc._id;
    }
    
    let globalAcc = await ChartOfAccount.findOne({ ...query, branchId: null }).select('_id').lean();
    if (globalAcc) return globalAcc._id;
    
    let legacyAcc = await ChartOfAccount.findOne(query).select('_id').lean();
    return legacyAcc ? legacyAcc._id : null;
  } catch (e) {
    console.error(\`COA lookup error for "\${name}":\`, e.message);
    return null;
  }
}`;

function processFile(filePath) {
  if (!fs.existsSync(filePath)) {
    console.log(`File not found: ${filePath}`);
    return;
  }
  let content = fs.readFileSync(filePath, 'utf8');

  // If purchase_order.js doesn't have it defined, maybe it requires it from somewhere?
  if (content.includes('async function getSystemAccountId')) {
    content = content.replace(/async function getSystemAccountId[\s\S]*?return null;\s*}\s*}/g, updatedGetSystemAccountId);
  } else {
    console.log(`getSystemAccountId not defined in ${filePath}`);
  }

  // Replace getSystemAccountId('Accounts Payable', currentOrgId)
  // or getSystemAccountId('Accounts Payable', req.user?.orgId)
  // with getSystemAccountId('Accounts Payable', currentOrgId, branchId)
  // We need to carefully identify what the branchId variable is in the scope.
  // In `POST /` it's `req.body.branchId` or `branchId` if extracted.
  // In `PUT /:id` it's `req.body.branchId` or `bill.branchId`.
  // Let's do a smart regex or just replace all instances.
  // Usually, the route handles it by defining `const branchId = ...`.
  // If we just append `branchId`, we need to make sure `branchId` is defined in scope.

  // Let's replace the ChartOfAccount.findOne fallback as well in bills.js
  content = content.replace(/ChartOfAccount\.findOne\(\{\s*accountName:\s*'Accounts Payable',\s*isSystemAccount:\s*true,\s*orgId:\s*currentOrgId\s*\}\)/g, "ChartOfAccount.findOne({ accountName: 'Accounts Payable', isSystemAccount: true, orgId: currentOrgId, branchId: branchId || null })");
  content = content.replace(/ChartOfAccount\.findOne\(\{\s*accountName:\s*'Accounts Payable',\s*isSystemAccount:\s*true,\s*orgId:\s*req\.user\?\.orgId\s*\}\)/g, "ChartOfAccount.findOne({ accountName: 'Accounts Payable', isSystemAccount: true, orgId: req.user?.orgId, branchId: branchId || null })");

  // Replace getSystemAccountId calls
  content = content.replace(/getSystemAccountId\('Accounts Payable',\s*currentOrgId\)/g, "getSystemAccountId('Accounts Payable', currentOrgId, branchId)");
  content = content.replace(/getSystemAccountId\('Accounts Payable',\s*req\.user\?\.orgId\)/g, "getSystemAccountId('Accounts Payable', req.user?.orgId, branchId)");

  fs.writeFileSync(filePath, content);
  console.log(`Processed ${filePath}`);
}

processFile('routes/bill.js');
processFile('routes/purchase_order.js');

