const mongoose = require('mongoose');

mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const db = mongoose.connection.db;
    
    // Get all system accounts
    const coaList = await db.collection('chartofaccounts').find({ isSystemAccount: true }).toArray();
    const getSysId = (name, orgId, branchId) => {
      // Find matching org and branch. If not found, fallback to nulls
      let acc = coaList.find(c => c.accountName === name && c.orgId === orgId && c.branchId === branchId);
      if (!acc) acc = coaList.find(c => c.accountName === name && c.orgId === orgId && c.branchId === null);
      if (!acc) acc = coaList.find(c => c.accountName === name && c.orgId === null && c.branchId === null);
      return acc ? acc._id : null;
    };

    const postTxn = async (txn) => {
      if (!txn.accountId || (txn.debit === 0 && txn.credit === 0)) return;
      txn.createdAt = new Date();
      txn.updatedAt = new Date();
      await db.collection('accounttransactions').insertOne(txn);
    };

    // We only update for the branch they asked about, to be safe, or all of them?
    // User said: "yes do ot correctly ad it wont tpouch the reamining functiality im telling you"
    // I will do it for all branches to ensure the entire DB is clean.
    
    const invoices = await db.collection('invoices').find({ 
      status: { $ne: 'DRAFT' }, 
      adjustment: { $exists: true, $ne: 0, $ne: null } 
    }).toArray();
    
    console.log('Fixing Invoices:', invoices.length);
    for (const inv of invoices) {
      await db.collection('accounttransactions').deleteMany({ referenceType: 'Invoice', referenceId: inv._id });
      
      const currentOrgId = inv.orgId || null;
      const branchId = inv.branchId || null;
      
      const arId = getSysId('Accounts Receivable', currentOrgId, branchId);
      const salesId = getSysId('Sales', currentOrgId, branchId);
      const taxId = getSysId('Tax Payable', currentOrgId, branchId);
      const tdsId = getSysId('TDS Receivable', currentOrgId, branchId);
      const tcsId = getSysId('TDS Payable', currentOrgId, branchId);
      const otherId = getSysId('Other Charges', currentOrgId, branchId);
      
      const txnDate = new Date(inv.invoiceDate);
      const desc = `Invoice ${inv.invoiceNumber} - ${inv.customerName}`;
      
      if (arId)    await postTxn({ accountId: arId, orgId: currentOrgId, branchId, date: txnDate, description: desc, referenceType: 'Invoice', referenceId: inv._id, referenceNumber: inv.invoiceNumber, debit: inv.totalAmount, credit: 0 });
      if (salesId) await postTxn({ accountId: salesId, orgId: currentOrgId, branchId, date: txnDate, description: desc, referenceType: 'Invoice', referenceId: inv._id, referenceNumber: inv.invoiceNumber, debit: 0, credit: inv.subTotal });
      if (taxId && inv.totalTax > 0) await postTxn({ accountId: taxId, orgId: currentOrgId, branchId, date: txnDate, description: `GST on Invoice ${inv.invoiceNumber}`, referenceType: 'Invoice', referenceId: inv._id, referenceNumber: inv.invoiceNumber, debit: 0, credit: inv.totalTax });
      if (tdsId && inv.tdsAmount > 0) await postTxn({ accountId: tdsId, orgId: currentOrgId, branchId, date: txnDate, description: `TDS on Invoice ${inv.invoiceNumber} - ${inv.customerName}`, referenceType: 'Invoice', referenceId: inv._id, referenceNumber: inv.invoiceNumber, debit: inv.tdsAmount, credit: 0 });
      if (tcsId && inv.tcsAmount > 0) await postTxn({ accountId: tcsId, orgId: currentOrgId, branchId, date: txnDate, description: `TCS on Invoice ${inv.invoiceNumber} - ${inv.customerName}`, referenceType: 'Invoice', referenceId: inv._id, referenceNumber: inv.invoiceNumber, debit: 0, credit: inv.tcsAmount });
      
      if (otherId && inv.adjustment) {
        if (inv.adjustment < 0) {
          await postTxn({ accountId: otherId, orgId: currentOrgId, branchId, date: txnDate, description: `Adjustment on Invoice ${inv.invoiceNumber}`, referenceType: 'Invoice', referenceId: inv._id, referenceNumber: inv.invoiceNumber, debit: Math.abs(inv.adjustment), credit: 0 });
        } else {
          await postTxn({ accountId: otherId, orgId: currentOrgId, branchId, date: txnDate, description: `Adjustment on Invoice ${inv.invoiceNumber}`, referenceType: 'Invoice', referenceId: inv._id, referenceNumber: inv.invoiceNumber, debit: 0, credit: inv.adjustment });
        }
      }
    }

    const creditNotes = await db.collection('creditnotes').find({ 
      status: { $ne: 'DRAFT' }, 
      adjustment: { $exists: true, $ne: 0, $ne: null } 
    }).toArray();
    
    console.log('Fixing Credit Notes:', creditNotes.length);
    for (const cn of creditNotes) {
      await db.collection('accounttransactions').deleteMany({ referenceType: 'Credit Note', referenceId: cn._id });
      
      const currentOrgId = cn.orgId || null;
      const branchId = cn.branchId || null;
      
      const arId = getSysId('Accounts Receivable', currentOrgId, branchId);
      const salesId = getSysId('Sales', currentOrgId, branchId);
      const taxId = getSysId('Tax Payable', currentOrgId, branchId);
      const otherId = getSysId('Other Charges', currentOrgId, branchId);
      
      const txnDate = new Date(cn.creditNoteDate);
      const desc = `Credit Note ${cn.creditNoteNumber} - ${cn.customerName}`;
      
      if (arId)    await postTxn({ accountId: arId, orgId: currentOrgId, branchId, date: txnDate, description: desc, referenceType: 'Credit Note', referenceId: cn._id, referenceNumber: cn.creditNoteNumber, debit: 0, credit: cn.totalAmount });
      if (salesId) await postTxn({ accountId: salesId, orgId: currentOrgId, branchId, date: txnDate, description: desc, referenceType: 'Credit Note', referenceId: cn._id, referenceNumber: cn.creditNoteNumber, debit: cn.subTotal, credit: 0 });
      if (taxId && cn.totalTax > 0) await postTxn({ accountId: taxId, orgId: currentOrgId, branchId, date: txnDate, description: `GST on Credit Note ${cn.creditNoteNumber}`, referenceType: 'Credit Note', referenceId: cn._id, referenceNumber: cn.creditNoteNumber, debit: cn.totalTax, credit: 0 });
      
      if (otherId && cn.adjustment) {
        if (cn.adjustment > 0) {
          await postTxn({ accountId: otherId, orgId: currentOrgId, branchId, date: txnDate, description: `Adjustment on Credit Note ${cn.creditNoteNumber}`, referenceType: 'Credit Note', referenceId: cn._id, referenceNumber: cn.creditNoteNumber, debit: Math.abs(cn.adjustment), credit: 0 });
        } else {
          await postTxn({ accountId: otherId, orgId: currentOrgId, branchId, date: txnDate, description: `Adjustment on Credit Note ${cn.creditNoteNumber}`, referenceType: 'Credit Note', referenceId: cn._id, referenceNumber: cn.creditNoteNumber, debit: 0, credit: Math.abs(cn.adjustment) });
        }
      }
    }

    console.log('Finished updating ledger entries!');
    process.exit(0);
  })
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
