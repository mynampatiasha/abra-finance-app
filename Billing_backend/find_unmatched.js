require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const pts = await db.collection('providertransactions').find({
      accountId: pa._id,
      isExcluded: { $ne: true },
      reconciliationStatus: { $in: ['CATEGORIZED', 'RECONCILED', 'MATCHED'] }
  }).toArray();
  
  const ats = await db.collection('accounttransactions').find({
      accountId: coa._id
  }).toArray();
  
  // Find the AT that is not in the PTs
  let matchedAts = new Set();
  
  for (const pt of pts) {
      if (pt.linkedRecordType === 'Expense' || pt.linkedRecordType === 'Restored Expense' || pt.categoryLabel === 'Restored Auto-Link') {
          // referenceId in AT might be pt._id
          const at = ats.find(a => a.referenceId && a.referenceId.toString() === pt._id.toString());
          if (at) matchedAts.add(at._id.toString());
      } 
      
      if (pt.linkedRecordId) {
          // referenceId in AT might be pt.linkedRecordId
          const at = ats.find(a => a.referenceId && a.referenceId.toString() === pt.linkedRecordId.toString());
          if (at) matchedAts.add(at._id.toString());
      }
  }
  
  const unmatchedAts = ats.filter(a => !matchedAts.has(a._id.toString()));
  console.log(`\nFound ${unmatchedAts.length} Unmatched Ledger Entries (Manual Entries):`);
  
  for (const at of unmatchedAts) {
      const type = at.transactionType;
      const amount = type === 'DEBIT' ? at.debit : at.credit;
      console.log(`- Date: ${at.date}, Amount: ?${amount}, Type: ${type}, Description: ${at.description}, RefID: ${at.referenceId}`);
      
      if (at.referenceId) {
          const expense = await db.collection('expenses').findOne({ _id: at.referenceId });
          if (expense) console.log(`  -> This was created as an Expense to vendor: ${expense.vendor}`);
          
          const pr = await db.collection('payments_received').findOne({ _id: at.referenceId });
          if (pr) console.log(`  -> This was created as a Payment Received.`);
      }
  }
  
  process.exit(0);
}

debug().catch(console.error);
