// fix_paymentmades_index.js
// Drops the old orgId+paymentNumber unique index on paymentmades
// and recreates it as orgId+branchId+paymentNumber (branch-scoped)
//
// Run once: node fix_paymentmades_index.js

'use strict';

const mongoose = require('mongoose');
const path     = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function run() {
  await mongoose.connect(process.env.MONGODB_URI, {
    dbName: 'abra_finance_module',
    serverSelectionTimeoutMS: 15000,
  });

  const db         = mongoose.connection.db;
  const collection = db.collection('paymentmades');

  // List current indexes
  const indexes = await collection.indexes();
  console.log('\nCurrent indexes on paymentmades:');
  indexes.forEach(idx => console.log(' -', idx.name, JSON.stringify(idx.key)));

  // Drop the old org-only unique index if it exists
  const oldIndex = indexes.find(
    idx => idx.unique &&
           idx.key.orgId === 1 &&
           idx.key.paymentNumber === 1 &&
           !idx.key.branchId
  );

  if (oldIndex) {
    console.log(`\n🗑  Dropping old index: ${oldIndex.name}`);
    await collection.dropIndex(oldIndex.name);
    console.log('✅ Old index dropped');
  } else {
    console.log('\n✅ Old index not found — nothing to drop');
  }

  // Create the correct branch-scoped unique index
  console.log('\n📐 Creating new index: { orgId, branchId, paymentNumber } unique');
  await collection.createIndex(
    { orgId: 1, branchId: 1, paymentNumber: 1 },
    { unique: true, name: 'orgId_1_branchId_1_paymentNumber_1' }
  );
  console.log('✅ New index created');

  // Verify
  const updated = await collection.indexes();
  console.log('\nUpdated indexes on paymentmades:');
  updated.forEach(idx => console.log(' -', idx.name, JSON.stringify(idx.key)));

  await mongoose.disconnect();
  console.log('\n✅ Done. Restart your backend server.\n');
}

run().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
