require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const sample = await db.collection('accounttransactions').findOne({ accountId: coa._id });
  console.log('Sample accountId type:', typeof sample.accountId, sample.accountId);
  
  const balAgg = await db.collection('accounttransactions').aggregate([
    { $match: { accountId: coa._id } },
    { $group: { _id: null, totalDebit: { $sum: '' }, totalCredit: { $sum: '' } } }
  ]).toArray();
  console.log('Agg:', balAgg);
  process.exit(0);
}

debug().catch(console.error);
