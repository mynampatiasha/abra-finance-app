require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const uncatTxns = await db.collection('providertransactions').find({
    accountId: pa._id,
    reconciliationStatus: { $in: ['UNMATCHED', 'UNCATEGORIZED'] }
  }).toArray();
  
  let dCount = 0, wCount = 0;
  let dSum = 0, wSum = 0;
  
  for (const txn of uncatTxns) {
    const amt = Number(txn.amount) || 0;
    if (txn.transactionType === 'CREDIT') {
      dCount++;
      dSum += amt;
    } else {
      wCount++;
      wSum += amt;
    }
  }
  
  console.log('Uncategorized Deposits: Count =', dCount, ', Sum =', dSum);
  console.log('Uncategorized Withdrawals: Count =', wCount, ', Sum =', wSum);
  
  process.exit(0);
}

debug().catch(console.error);
