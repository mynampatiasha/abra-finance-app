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
  
  // Calculate running balance logic exactly as UI does
  let currentRun = pa.openingBalance || 0;
  pts.sort((a,b) => new Date(a.transactionDate) - new Date(b.transactionDate));
  
  let missingImpact = 0;
  
  // Now find the missing ones
  const ats = await db.collection('accounttransactions').find({
      accountId: coa._id
  }).toArray();
  const atRefIds = new Set();
  
  // AccountTransaction referenceId could be Expense, PaymentReceived, etc.
  // We need to look up ProviderTransactions by matching amounts and dates?
  // Actually, we can just sum ALL ATS and sum ALL PTS.
  
  let sumPTs = pa.openingBalance || 0;
  for (const pt of pts) {
    const amt = Number(pt.amount) || 0;
    sumPTs += (pt.transactionType === 'DEBIT') ? -amt : amt;
  }
  
  let sumATs = pa.openingBalance || 0;
  for (const at of ats) {
    sumATs += (Number(at.debit) || 0) - (Number(at.credit) || 0);
  }
  
  console.log('Total Running Balance (Sum of 557 PTS):', sumPTs);
  console.log('Total Current Balance (Sum of 500 ATS):', sumATs);
  console.log('Difference:', sumPTs - sumATs);
  
  process.exit(0);
}

debug().catch(console.error);
