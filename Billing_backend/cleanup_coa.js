// File: backend/fix_closing_balance.js
// Run: node fix_closing_balance.js

const mongoose = require('mongoose');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixBalances() {
  await mongoose.connect(MONGODB_URI);
  console.log('✅ Connected to MongoDB');

  const db = mongoose.connection.db;

  // Get ALL accounts
  const accounts = await db.collection('chartofaccounts').find({}).toArray();
  console.log(`📋 Found ${accounts.length} accounts`);

  for (const account of accounts) {
    const accountId = account._id;

    // Sum all debits and credits for this account
    const txns = await db.collection('accounttransactions')
      .find({ accountId: accountId }).toArray();

    const totalDebit  = txns.reduce((sum, t) => sum + (t.debit  || 0), 0);
    const totalCredit = txns.reduce((sum, t) => sum + (t.credit || 0), 0);
    const netBalance  = totalDebit - totalCredit;

    // Update closing balance
    await db.collection('chartofaccounts').updateOne(
      { _id: accountId },
      { $set: {
        closingBalance: Math.abs(netBalance),
        balanceType: netBalance >= 0 ? 'Dr' : 'Cr',
      }}
    );

    if (txns.length > 0) {
      console.log(`✅ ${account.accountName} → Dr:${totalDebit} Cr:${totalCredit} → Net: ${netBalance} (${netBalance >= 0 ? 'Dr' : 'Cr'})`);
    }
  }

  await mongoose.disconnect();
  console.log('\n✅ All closing balances recalculated!');
}

fixBalances().catch(console.error);