// ============================================================================
// CLEANUP: Remove duplicate system accounts created with branchId=null
// ============================================================================
// Background:
//   - At registration, seedSystemAccounts(orgId) was called → branchId=null
//   - At branch creation, seedSystemAccounts(orgId, branchId) was called → branchId=Y
//   - This created two sets of identical system accounts per org
//
// This script:
//   1. Finds all system accounts with branchId=null
//   2. Checks if a branch-scoped duplicate exists (same accountName + orgId + branchId set)
//   3. If the null-branchId account has NO transactions → deletes it (safe)
//   4. If it HAS transactions → reports it (manual review needed)
//
// Run: node cleanup_duplicate_system_accounts.js
// ============================================================================

const mongoose = require('mongoose');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function cleanup() {
  await mongoose.connect(MONGODB_URI);
  console.log('✅ Connected to MongoDB\n');

  const db = mongoose.connection.db;

  // Find all system accounts with branchId=null
  const nullBranchAccounts = await db.collection('chartofaccounts').find({
    isSystemAccount: true,
    $or: [{ branchId: null }, { branchId: { $exists: false } }],
  }).toArray();

  console.log(`📋 Found ${nullBranchAccounts.length} system accounts with branchId=null\n`);

  if (nullBranchAccounts.length === 0) {
    console.log('✅ Nothing to clean up.');
    await mongoose.disconnect();
    return;
  }

  let deleted   = 0;
  let skipped   = 0;
  let hasTxns   = 0;

  for (const acc of nullBranchAccounts) {
    // Check if a branch-scoped version exists for the same org
    const branchScopedExists = await db.collection('chartofaccounts').findOne({
      accountName:     acc.accountName,
      isSystemAccount: true,
      orgId:           acc.orgId,
      branchId:        { $nin: [null, ''], $exists: true },
    });

    if (!branchScopedExists) {
      // No branch-scoped duplicate — this is the only copy, leave it alone
      console.log(`⏭️  SKIP (no branch duplicate): ${acc.accountName} [orgId=${acc.orgId}]`);
      skipped++;
      continue;
    }

    // Check if the null-branchId account has any transactions
    const txnCount = await db.collection('accounttransactions').countDocuments({
      accountId: acc._id,
    });

    if (txnCount > 0) {
      // Has transactions — do NOT delete, needs manual review
      console.log(`⚠️  HAS TRANSACTIONS (${txnCount}) — SKIPPED: ${acc.accountName} [_id=${acc._id}, orgId=${acc.orgId}]`);
      hasTxns++;
      continue;
    }

    // Safe to delete — no transactions, branch-scoped duplicate exists
    await db.collection('chartofaccounts').deleteOne({ _id: acc._id });
    console.log(`🗑️  DELETED: ${acc.accountName} [_id=${acc._id}, orgId=${acc.orgId}]`);
    deleted++;
  }

  console.log('\n════════════════════════════════════════');
  console.log(`✅ Deleted:          ${deleted}`);
  console.log(`⏭️  Skipped (no dup): ${skipped}`);
  console.log(`⚠️  Has transactions: ${hasTxns} (manual review needed)`);
  console.log('════════════════════════════════════════\n');

  if (hasTxns > 0) {
    console.log('⚠️  Some null-branchId accounts have transactions.');
    console.log('   These were NOT deleted. You should:');
    console.log('   1. Migrate their transactions to the branch-scoped account, OR');
    console.log('   2. Leave them if they represent org-level entries.\n');
  }

  await mongoose.disconnect();
  console.log('✅ Done.');
}

cleanup().catch(console.error);
