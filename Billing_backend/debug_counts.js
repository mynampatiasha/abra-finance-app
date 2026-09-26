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
  
  process.exit(0);
}

debug().catch(console.error);
