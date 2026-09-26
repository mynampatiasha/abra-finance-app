require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  console.log('COA ID:', coa._id);
  
  // Find ALL account transactions just to see the collection name
  const allTxns = await db.collection('accounttransactions').find({}).limit(1).toArray();
  console.log('Sample account transaction:', allTxns.length ? 'FOUND' : 'EMPTY');
  
  // Check if they are stored in a different collection?
  const allTxns2 = await db.collection('account_transactions').find({}).limit(1).toArray();
  console.log('Sample account_transactions:', allTxns2.length ? 'FOUND' : 'EMPTY');

  // Let's count them for this COA
  const cnt = await db.collection('accounttransactions').countDocuments({ accountId: coa._id });
  console.log('Transactions for this COA:', cnt);
  
  process.exit(0);
}

debug().catch(console.error);
