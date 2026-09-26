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
  
  // To match exactly, we need to sum up PTS and sum up ATS. 
  // Let's check how many PTS lack an AT.
  
  // Since we know Expense uses pt._id, Payment uses pt.linkedRecordId
  // It's safer to just match by Amount and Date if we want to be sure,
  // but let's just do a rough matching by Amount.
  
  let ptAmounts = pts.map(pt => (pt.transactionType === 'DEBIT' ? -Number(pt.amount) : Number(pt.amount)));
  let atAmounts = ats.map(at => (Number(at.debit) || 0) - (Number(at.credit) || 0));
  
  ptAmounts.sort((a,b)=>a-b);
  atAmounts.sort((a,b)=>a-b);
  
  // Match them up
  let unmatchedPTs = [];
  let unmatchedATs = [...atAmounts];
  
  for (const p of ptAmounts) {
    const idx = unmatchedATs.findIndex(a => Math.abs(a - p) < 0.01);
    if (idx !== -1) {
      unmatchedATs.splice(idx, 1);
    } else {
      unmatchedPTs.push(p);
    }
  }
  
  console.log('Unmatched PTs (Categorized Bank Statements missing from Ledger):', unmatchedPTs.length, 'Sum:', unmatchedPTs.reduce((a,b)=>a+b, 0));
  console.log('Unmatched ATs (Ledger entries missing from Bank Statements):', unmatchedATs.length, 'Sum:', unmatchedATs.reduce((a,b)=>a+b, 0));
  
  console.log('Unmatched PTs amounts:', unmatchedPTs);
  
  process.exit(0);
}

debug().catch(console.error);
