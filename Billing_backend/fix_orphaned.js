require('dotenv').config();
const mongoose = require('mongoose');
const { ObjectId } = mongoose.Types;

async function fixOrphaned() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  
  const orphaned = await db.collection('providertransactions').find({
    reconciliationStatus: 'CATEGORIZED',
    categoryLabel: 'Customer Payment',
    $or: [{ linkedRecordId: null }, { linkedRecordId: '' }]
  }).toArray();
  
  console.log('Found ' + orphaned.length + ' orphaned Customer Payments');
  
  let fixedCount = 0;
  let uncatCount = 0;
  
  for (const txn of orphaned) {
    const payment = await db.collection('paymentreceived').findOne({
      providerTransactionId: txn._id.toString()
    });
    
    if (payment) {
      await db.collection('providertransactions').updateOne(
        { _id: txn._id },
        { $set: { linkedRecordId: payment._id.toString(), linkedRecordType: 'PaymentReceived' } }
      );
      fixedCount++;
      console.log('Fixed ' + txn._id + ' -> linked to ' + payment._id);
    } else {
      const payment2 = await db.collection('payments_received').findOne({
        providerTransactionId: txn._id.toString()
      });
      if (payment2) {
        await db.collection('providertransactions').updateOne(
          { _id: txn._id },
          { $set: { linkedRecordId: payment2._id.toString(), linkedRecordType: 'PaymentReceived' } }
        );
        fixedCount++;
        console.log('Fixed ' + txn._id + ' -> linked to ' + payment2._id);
      } else {
        await db.collection('providertransactions').updateOne(
          { _id: txn._id },
          { $set: { reconciliationStatus: 'UNCATEGORIZED', categoryLabel: null, linkedRecordId: null, linkedRecordType: null } }
        );
        uncatCount++;
        console.log('Uncategorized ' + txn._id + ' (No payment found)');
      }
    }
  }
  
  console.log('Done. Fixed: ' + fixedCount + ', Uncategorized: ' + uncatCount);
  process.exit(0);
}

fixOrphaned().catch(console.error);
