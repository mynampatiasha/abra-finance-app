require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  // Get all ATs
  const ats = await db.collection('accounttransactions').find({ accountId: coa._id }).project({ referenceId: 1 }).toArray();
  const refIds = ats.map(a => a.referenceId).filter(id => id);
  
  // We need to convert them to ObjectIds carefully
  const validIds = [];
  for (const id of refIds) {
      try { validIds.push(new mongoose.Types.ObjectId(id.toString())); } catch(e) {}
  }
  
  const res = await db.collection('providertransactions').updateMany(
      { accountId: pa._id, _id: { $in: validIds }, reconciliationStatus: 'UNCATEGORIZED' },
      { $set: { reconciliationStatus: 'CATEGORIZED', categoryLabel: 'Restored Auto-Link' } }
  );
  
  console.log('Restored', res.modifiedCount, 'transactions from AccountTransactions references!');
  
  process.exit(0);
}

debug().catch(console.error);
