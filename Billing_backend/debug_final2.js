require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  
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
  
  console.log('ProviderTransaction Categorized Count:', pts.length);
  console.log('Total Running Balance (Sum of PTs):', sumPTs);
  
  process.exit(0);
}

debug().catch(console.error);
