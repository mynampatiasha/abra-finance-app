require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  // Find all uncategorized transactions
  const pts = await db.collection('providertransactions').find({
      accountId: pa._id,
      reconciliationStatus: 'UNCATEGORIZED'
  }).toArray();
  
  let restored = 0;
  let stillGhosts = 0;
  
  for (const pt of pts) {
    // 1. Check Expenses
    const exp = await db.collection('expenses').findOne({ providerTransactionId: pt._id });
    if (exp) {
      await db.collection('providertransactions').updateOne(
        { _id: pt._id },
        { $set: { 
           reconciliationStatus: 'CATEGORIZED',
           linkedRecordId: exp._id.toString(),
           linkedRecordType: 'Expense',
           categoryLabel: 'Expense'
        }}
      );
      restored++;
      continue;
    }
    
    // 2. Check PaymentsReceived
    const payRec = await db.collection('payments_received').findOne({ providerTransactionId: pt._id });
    if (payRec) {
      await db.collection('providertransactions').updateOne(
        { _id: pt._id },
        { $set: { 
           reconciliationStatus: 'CATEGORIZED',
           linkedRecordId: payRec._id.toString(),
           linkedRecordType: 'PaymentReceived',
           categoryLabel: 'Customer Payment'
        }}
      );
      restored++;
      continue;
    }
    
    // 3. Check PaymentMade
    const payMade = await db.collection('payments_made').findOne({ providerTransactionId: pt._id });
    if (payMade) {
      await db.collection('providertransactions').updateOne(
        { _id: pt._id },
        { $set: { 
           reconciliationStatus: 'CATEGORIZED',
           linkedRecordId: payMade._id.toString(),
           linkedRecordType: 'PaymentMade',
           categoryLabel: 'Vendor Payment'
        }}
      );
      restored++;
      continue;
    }
    
    // If it reaches here, it has no linked record. It's a true ghost!
    stillGhosts++;
  }
  
  console.log('Restored links for', restored, 'legitimate transactions.');
  console.log('Left', stillGhosts, 'transactions as UNCATEGORIZED (the true ghosts or unassigned).');
  
  process.exit(0);
}

debug().catch(console.error);
