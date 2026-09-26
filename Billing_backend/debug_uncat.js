require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const uncatDeposits = await db.collection('providertransactions').aggregate([
    { $match: { accountId: pa._id, transactionType: 'CREDIT', reconciliationStatus: { $in: ['UNMATCHED', 'UNCATEGORIZED'] } } },
    { $group: { _id: null, total: { $sum: '' }, count: { $sum: 1 } } }
  ]).toArray();
  
  const uncatWithdrawals = await db.collection('providertransactions').aggregate([
    { $match: { accountId: pa._id, transactionType: 'DEBIT', reconciliationStatus: { $in: ['UNMATCHED', 'UNCATEGORIZED'] } } },
    { $group: { _id: null, total: { $sum: '' }, count: { $sum: 1 } } }
  ]).toArray();
  
  console.log('Uncategorized Deposits:', uncatDeposits);
  console.log('Uncategorized Withdrawals:', uncatWithdrawals);
  
  process.exit(0);
}

debug().catch(console.error);
