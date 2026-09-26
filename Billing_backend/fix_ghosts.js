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
  
  // Build a set of referenceIds from the Ledger
  const atRefIds = new Set(ats.map(a => a.referenceId ? a.referenceId.toString() : ''));
  
  let toRevert = [];
  
  for (const pt of pts) {
    // If it's categorized, it should have a linkedRecordId
    if (!pt.linkedRecordId) {
      // Very broken
      toRevert.push(pt._id);
    } else {
      if (!atRefIds.has(pt.linkedRecordId.toString())) {
        toRevert.push(pt._id);
      }
    }
  }
  
  console.log('Identified', toRevert.length, 'ghost transactions.');
  
  if (toRevert.length > 0) {
    const res = await db.collection('providertransactions').updateMany(
      { _id: { $in: toRevert } },
      { 
        $set: { 
           reconciliationStatus: 'UNCATEGORIZED',
           linkedRecordId: null,
           linkedRecordType: null,
           categoryLabel: null
        }
      }
    );
    console.log('Reverted', res.modifiedCount, 'transactions to UNCATEGORIZED.');
  }
  
  process.exit(0);
}

debug().catch(console.error);
