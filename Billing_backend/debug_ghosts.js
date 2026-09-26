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
  
  let ptAmounts = pts.map(pt => ({ id: pt._id, amt: (pt.transactionType === 'DEBIT' ? -Number(pt.amount) : Number(pt.amount)) }));
  let atAmounts = ats.map(at => ({ id: at._id, amt: (Number(at.debit) || 0) - (Number(at.credit) || 0) }));
  
  let unmatchedPTs = [];
  
  for (const p of ptAmounts) {
    const idx = atAmounts.findIndex(a => Math.abs(a.amt - p.amt) < 0.01);
    if (idx !== -1) {
      atAmounts.splice(idx, 1);
    } else {
      unmatchedPTs.push(p.id);
    }
  }
  
  console.log('Unmatched PT IDs:', unmatchedPTs.length);
  
  const ghostPTs = await db.collection('providertransactions').find({ _id: { $in: unmatchedPTs } }).toArray();
  for (const pt of ghostPTs) {
      console.log(`Ghost PT: Date=${pt.transactionDate}, Amount=${pt.amount}, Desc=${pt.description}, LinkedRec=${pt.linkedRecordId}`);
  }
  
  if (unmatchedPTs.length > 0) {
      const res = await db.collection('providertransactions').updateMany(
        { _id: { $in: unmatchedPTs } },
        { 
          $set: { 
             reconciliationStatus: 'UNCATEGORIZED',
             linkedRecordId: null,
             linkedRecordType: null,
             categoryLabel: null
          }
        }
      );
      console.log('Reverted remaining', res.modifiedCount, 'ghost transactions!');
  }
  
  process.exit(0);
}

debug().catch(console.error);
