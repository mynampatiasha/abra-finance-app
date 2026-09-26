require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const ptCount = await db.collection('providertransactions').countDocuments({
      accountId: pa._id,
      isExcluded: { $ne: true },
      reconciliationStatus: { $in: ['CATEGORIZED', 'RECONCILED', 'MATCHED'] }
  });
  
  const atCount = await db.collection('accounttransactions').countDocuments({
      accountId: coa._id
  });
  
  console.log('ProviderTransaction Categorized Count:', ptCount);
  console.log('AccountTransaction Count for COA:', atCount);
  
  // Let's sum them
  const pts = await db.collection('providertransactions').find({
      accountId: pa._id,
      isExcluded: { $ne: true },
      reconciliationStatus: { $in: ['CATEGORIZED', 'RECONCILED', 'MATCHED'] }
  }).toArray();
  
  let sumPTs = pa.openingBalance || 0;
  for (const pt of pts) {
    const amt = Number(pt.amount) || 0;
    sumPTs += (pt.transactionType === 'DEBIT') ? -amt : amt;
  }
  
  const ats = await db.collection('accounttransactions').find({ accountId: coa._id }).toArray();
  let sumATs = pa.openingBalance || 0;
  for (const at of ats) {
    sumATs += (Number(at.debit) || 0) - (Number(at.credit) || 0);
  }
  
  console.log('Total Running Balance (Sum of PTs):', sumPTs);
  console.log('Total Current Balance (Sum of ATs):', sumATs);
  console.log('Difference:', sumPTs - sumATs);
  
  process.exit(0);
}

debug().catch(console.error);
