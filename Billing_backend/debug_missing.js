require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  const coa = await db.collection('chartofaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const pts = await db.collection('providertransactions').find({
      accountId: pa._id,
      isExcluded: { $ne: true },
      reconciliationStatus: { $in: ['CATEGORIZED', 'RECONCILED', 'MATCHED'] }
  }).toArray();
  
  const ats = await db.collection('accounttransactions').find({
      accountId: coa._id
  }).toArray();
  
  const atRefIds = new Set(ats.map(a => a.referenceId ? a.referenceId.toString() : ''));
  
  let missingLedger = [];
  let missingExpenses = 0;
  let missingPayments = 0;
  
  for (const pt of pts) {
    if (!atRefIds.has(pt._id.toString())) {
      missingLedger.push(pt);
      
      // Check if linked record exists
      if (pt.linkedRecordType === 'Expense') {
         const exp = await db.collection('expenses').findOne({ _id: pt.linkedRecordId ? new mongoose.Types.ObjectId(pt.linkedRecordId) : null });
         if (!exp) missingExpenses++;
      }
      else if (pt.linkedRecordType === 'PaymentReceived') {
         const pay = await db.collection('paymentreceived').findOne({ _id: pt.linkedRecordId ? new mongoose.Types.ObjectId(pt.linkedRecordId) : null });
         if (!pay) missingPayments++;
      }
    }
  }
  
  console.log('Total Missing from Ledger:', missingLedger.length);
  console.log('Missing Expenses (deleted?):', missingExpenses);
  console.log('Missing Payments (deleted?):', missingPayments);
  
  // Show a few samples
  console.log('Samples:', missingLedger.slice(0, 2).map(m => ({ id: m._id, type: m.linkedRecordType, label: m.categoryLabel })));
  
  process.exit(0);
}

debug().catch(console.error);
