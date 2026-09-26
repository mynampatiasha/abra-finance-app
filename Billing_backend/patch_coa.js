const fs = require('fs');

function updateInvoices() {
  let code = fs.readFileSync('routes/invoices.js', 'utf8');

  // 1. Replace Promise.all destructurings
  code = code.replace(/const \[(arId, salesId, taxId, tdsReceivableId, tcsPayableId)\] = await Promise.all\(\[/g, 
    'const [arId, salesId, taxId, tdsReceivableId, tcsPayableId, otherChargesId] = await Promise.all([');

  // 2. Replace Promise.all calls
  code = code.replace(/getSystemAccountId\('TDS Payable',([^\)]+)\),/g, 
    'getSystemAccountId(\'TDS Payable\',$1),\n          getSystemAccountId(\'Other Charges\',$1),');

  // 3. Add posting logic after TCS
  const tcsPostingPattern = /(if \(tcsPayableId\s+&&\s+invoice\.tcsAmount\s*>\s*0\)\s+await postTransactionToCOA\(\{.*?\}\);)/g;

  const adjustmentLogic = `
        if (otherChargesId && invoice.adjustment) {
          const adjBranch = req.branchIds?.length > 0 ? req.branchIds[0] : (invoice.branchId || null);
          if (invoice.adjustment < 0) {
            await postTransactionToCOA({ accountId: otherChargesId, orgId: currentOrgId, branchId: adjBranch, date: txnDate, description: \`Adjustment on Invoice \${invoice.invoiceNumber}\`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: Math.abs(invoice.adjustment), credit: 0 });
          } else {
            await postTransactionToCOA({ accountId: otherChargesId, orgId: currentOrgId, branchId: adjBranch, date: txnDate, description: \`Adjustment on Invoice \${invoice.invoiceNumber}\`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: 0, credit: invoice.adjustment });
          }
        }`;

  code = code.replace(tcsPostingPattern, '$1' + adjustmentLogic);
  fs.writeFileSync('routes/invoices.js', code);
  console.log('invoices.js updated');
}

function updateCreditNotes() {
  if (!fs.existsSync('routes/credit-notes.js')) {
    console.log('No credit-notes.js');
    return;
  }
  let code = fs.readFileSync('routes/credit-notes.js', 'utf8');

  // 1. Replace Promise.all destructurings
  code = code.replace(/const \[(arId, salesId, taxId)\] = await Promise.all\(\[/g, 
    'const [arId, salesId, taxId, otherChargesId] = await Promise.all([');

  // 2. Replace Promise.all calls (find 'Tax Payable')
  code = code.replace(/getSystemAccountId\('Tax Payable',([^\)]+)\),/g, 
    'getSystemAccountId(\'Tax Payable\',$1),\n          getSystemAccountId(\'Other Charges\',$1),');

  // 3. Add posting logic after Tax
  const taxPostingPattern = /(if \(taxId\s+&&\s+cn\.totalTax\s*>\s*0\)\s+await postTransactionToCOA\(\{.*?\}\);)/g;

  const adjustmentLogic = `
        if (otherChargesId && cn.adjustment) {
          const adjBranch = req.branchIds?.length > 0 ? req.branchIds[0] : (cn.branchId || null);
          if (cn.adjustment > 0) { // Positive adjustment increases credit given, so it's a loss/Debit
            await postTransactionToCOA({ accountId: otherChargesId, orgId: currentOrgId, branchId: adjBranch, date: txnDate, description: \`Adjustment on Credit Note \${cn.creditNoteNumber}\`, referenceType: 'Credit Note', referenceId: cn._id, referenceNumber: cn.creditNoteNumber, debit: Math.abs(cn.adjustment), credit: 0 });
          } else {
            await postTransactionToCOA({ accountId: otherChargesId, orgId: currentOrgId, branchId: adjBranch, date: txnDate, description: \`Adjustment on Credit Note \${cn.creditNoteNumber}\`, referenceType: 'Credit Note', referenceId: cn._id, referenceNumber: cn.creditNoteNumber, debit: 0, credit: Math.abs(cn.adjustment) });
          }
        }`;

  code = code.replace(taxPostingPattern, '$1' + adjustmentLogic);
  fs.writeFileSync('routes/credit-notes.js', code);
  console.log('credit-notes.js updated');
}

updateInvoices();
updateCreditNotes();
