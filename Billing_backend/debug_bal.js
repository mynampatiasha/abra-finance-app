require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  console.log('PaymentAccount:', pa);
  
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  console.log('ChartOfAccount ID:', coa ? coa._id : 'Not Found');
  
  const balAgg = await db.collection('account_transactions').aggregate([
    { $match: { accountId: coa._id } },
    { $group: { _id: null, totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } }
  ]).toArray();
  
  console.log('AccountTransaction Aggregation:', balAgg);
  
  const deposits = await db.collection('providertransactions').aggregate([
    { $match: { accountId: pa._id, transactionType: 'CREDIT' } },
    { $group: { _id: null, total: { $sum: '$amount' } } }
  ]).toArray();
  const withdrawals = await db.collection('providertransactions').aggregate([
    { $match: { accountId: pa._id, transactionType: 'DEBIT' } },
    { $group: { _id: null, total: { $sum: '$amount' } } }
  ]).toArray();
  console.log('Bank Statement Deposits:', deposits);
  console.log('Bank Statement Withdrawals:', withdrawals);
  
  process.exit(0);
}

debug().catch(console.error);
