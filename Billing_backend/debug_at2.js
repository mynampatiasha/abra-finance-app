require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const cnt = await db.collection('accounttransactions').countDocuments({
      accountId: coa._id,
      referenceType: 'Payment'
  });
  console.log('Payment in COA:', cnt);
  
  process.exit(0);
}

debug().catch(console.error);
