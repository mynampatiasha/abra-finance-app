require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  console.log('PaymentAccount currentBalance:', pa.currentBalance);
  
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const balAgg = await db.collection('accounttransactions').aggregate([
    { $match: { accountId: coa._id } },
    { $group: { _id: null, totalDebit: { $sum: '' }, totalCredit: { $sum: '' } } }
  ]).toArray();
  
  console.log('AccountTransaction Aggregation:', balAgg);
  
  process.exit(0);
}

debug().catch(console.error);
