require('dotenv').config();
const mongoose = require('mongoose');

async function debug() {
  await mongoose.connect(process.env.MONGODB_URI);
  const db = mongoose.connection.db;
  const pa = await db.collection('paymentaccounts').findOne({ accountName: 'IDFC First Bank' });
  
  const pts = await db.collection('providertransactions').find({
      accountId: pa._id,
      reconciliationStatus: 'UNCATEGORIZED'
  }).toArray();
  
  // Load ALL mappings into memory (fast)
  console.log('Loading mappings into memory...');
  const exps = await db.collection('expenses').find({ providerTransactionId: { $ne: null } }).project({ providerTransactionId: 1 }).toArray();
  const expMap = new Map();
  exps.forEach(e => expMap.set(e.providerTransactionId.toString(), e._id.toString()));
  
  const prs = await db.collection('payments_received').find({ providerTransactionId: { $ne: null } }).project({ providerTransactionId: 1 }).toArray();
  const prMap = new Map();
  prs.forEach(p => prMap.set(p.providerTransactionId.toString(), p._id.toString()));
  
  const pms = await db.collection('payments_made').find({ providerTransactionId: { $ne: null } }).project({ providerTransactionId: 1 }).toArray();
  const pmMap = new Map();
  pms.forEach(p => pmMap.set(p.providerTransactionId.toString(), p._id.toString()));
  
  console.log('Loaded mappings. Exps:', exps.length, 'PRs:', prs.length, 'PMs:', pms.length);
  
  let updates = [];
  let stillGhosts = 0;
  
  for (const pt of pts) {
    const ptId = pt._id.toString();
    
    if (expMap.has(ptId)) {
      updates.push({
        updateOne: {
          filter: { _id: pt._id },
          update: { $set: { reconciliationStatus: 'CATEGORIZED', linkedRecordId: expMap.get(ptId), linkedRecordType: 'Expense', categoryLabel: 'Expense' } }
        }
      });
    } else if (prMap.has(ptId)) {
      updates.push({
        updateOne: {
          filter: { _id: pt._id },
          update: { $set: { reconciliationStatus: 'CATEGORIZED', linkedRecordId: prMap.get(ptId), linkedRecordType: 'PaymentReceived', categoryLabel: 'Customer Payment' } }
        }
      });
    } else if (pmMap.has(ptId)) {
      updates.push({
        updateOne: {
          filter: { _id: pt._id },
          update: { $set: { reconciliationStatus: 'CATEGORIZED', linkedRecordId: pmMap.get(ptId), linkedRecordType: 'PaymentMade', categoryLabel: 'Vendor Payment' } }
        }
      });
    } else {
      stillGhosts++;
    }
  }
  
  console.log('Found', updates.length, 'legitimate transactions to restore.');
  console.log('Left', stillGhosts, 'transactions as UNCATEGORIZED (the true ghosts or unassigned).');
  
  if (updates.length > 0) {
    const res = await db.collection('providertransactions').bulkWrite(updates);
    console.log('Restored', res.modifiedCount, 'transactions successfully!');
  }
  
  process.exit(0);
}

debug().catch(console.error);
