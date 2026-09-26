const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

mongoose.connect(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/abra_finance');

// Require the routes to register the models
require('./routes/invoices');
const Invoice = mongoose.model('Invoice');

const { postTransactionToCOA, ChartOfAccount, AccountTransaction } = require('./routes/chart_of_accounts');

async function getSystemAccountId(accountName, orgId, branchId) {
  const q = { accountName };
  if (orgId) q.orgId = orgId;
  if (branchId) q.branchId = branchId;
  const acc = await ChartOfAccount.findOne(q);
  return acc ? acc._id : null;
}

async function revertInvoice() {
  try {
    const invoice = await Invoice.findById('6a127b6eaef99160d927ef43');
    if (!invoice) {
      console.log('Invoice not found');
      process.exit(1);
    }

    console.log(`Found invoice: ${invoice.invoiceNumber}, Current Total: ${invoice.totalAmount}, Adjustment: ${invoice.adjustment}`);

    // Revert the adjustment
    invoice.adjustment = 0;
    invoice.autoRoundOff = false;
    
    // The pre('save') hook will recalculate totalAmount and amountDue
    await invoice.save();

    console.log(`After save: Total: ${invoice.totalAmount}, Due: ${invoice.amountDue}, Status: ${invoice.status}`);
    
    // Manually force status back to PARTIALLY_PAID if it got caught in the OVERDUE trap
    await Invoice.updateOne({ _id: invoice._id }, { $set: { status: 'PARTIALLY_PAID' } });

    // Fix the ledger (COA)
    const currentOrgId = invoice.orgId;
    const branchId = invoice.branchId;
    
    await AccountTransaction.deleteMany({ referenceType: 'Invoice', referenceId: invoice._id });
    
    const arId = await getSystemAccountId('Accounts Receivable', currentOrgId, branchId);
    const salesId = await getSystemAccountId('Sales', currentOrgId, branchId);
    const taxId = await getSystemAccountId('Tax Payable', currentOrgId, branchId);
    const tdsReceivableId = await getSystemAccountId('TDS Receivable', currentOrgId, branchId);
    const tcsPayableId = await getSystemAccountId('TDS Payable', currentOrgId, branchId);

    const txnDate = new Date(invoice.invoiceDate);
    const desc = `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`;
    
    if (arId) await postTransactionToCOA({ accountId: arId, orgId: currentOrgId, branchId, date: txnDate, description: desc, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: invoice.totalAmount, credit: 0 });
    if (salesId) await postTransactionToCOA({ accountId: salesId, orgId: currentOrgId, branchId, date: txnDate, description: desc, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: 0, credit: invoice.subTotal });
    if (taxId && invoice.totalTax > 0) await postTransactionToCOA({ accountId: taxId, orgId: currentOrgId, branchId, date: txnDate, description: `GST on Invoice ${invoice.invoiceNumber}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: 0, credit: invoice.totalTax });
    if (tdsReceivableId && invoice.tdsAmount > 0) await postTransactionToCOA({ accountId: tdsReceivableId, orgId: currentOrgId, branchId, date: txnDate, description: `TDS on Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: invoice.tdsAmount, credit: 0 });
    if (tcsPayableId && invoice.tcsAmount > 0) await postTransactionToCOA({ accountId: tcsPayableId, orgId: currentOrgId, branchId, date: txnDate, description: `TCS on Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: 0, credit: invoice.tcsAmount });

    console.log('Ledger updated perfectly!');
    process.exit(0);
  } catch (e) {
    console.error(e);
    process.exit(1);
  }
}

revertInvoice();
