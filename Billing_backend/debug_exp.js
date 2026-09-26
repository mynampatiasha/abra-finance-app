require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  
  // Get one Expense
  const exp = await db.collection('expenses').findOne({ providerTransactionId: { $ne: null } });
  console.log('Expense providerTransactionId:', exp.providerTransactionId, 'Type:', typeof exp.providerTransactionId, 'Is ObjectId?', exp.providerTransactionId instanceof mongoose.Types.ObjectId);
  
  process.exit(0);
}

debug().catch(console.error);
