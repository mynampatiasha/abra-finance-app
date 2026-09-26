require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const all = await db.collection('accounttransactions').find({ accountId: coa._id }).toArray();
  let totalDebit = 0;
  let totalCredit = 0;
  let hasStrings = false;
  
  for (const t of all) {
    if (typeof t.debit === 'string' || typeof t.credit === 'string') hasStrings = true;
    totalDebit += (Number(t.debit) || 0);
    totalCredit += (Number(t.credit) || 0);
  }
  
  console.log('Manual Sum -> Debit:', totalDebit, 'Credit:', totalCredit, 'HasStrings:', hasStrings);
  process.exit(0);
}

debug().catch(console.error);
