// ============================================================================
// RESET BRANCH DATA - Complete Branch Data Deletion Script
// ============================================================================
// This script deletes ALL data for a specific branch including:
//   - Chart of Accounts (COA) and Account Transactions
//   - Invoices, Bills, Credit Notes, Vendor Credits
//   - Payments Received, Payments Made, Expenses
//   - Quotes, Sales Orders, Purchase Orders, Delivery Challans
//   - Customers, Vendors, Items, Payment Accounts
//   - Manual Journals, Fixed Assets, Payment Links
//   - Recurring profiles (invoices, bills, expenses)
//   - Branch profile and uploaded files (logos, signatures)
//
// Usage:
//   node reset_branch_data.js "Branch Name"
//   node reset_branch_data.js "Testing - branch 1 - Asha"
//
// WARNING: This operation is IRREVERSIBLE. All data will be permanently deleted.
// ============================================================================

const mongoose = require('mongoose');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

// ============================================================================
// COLLECTIONS TO CLEAN (all branch-scoped data)
// ============================================================================
const COLLECTIONS_TO_CLEAN = [
  // Financial/Accounting
  'accounttransactions',
  'chartofaccounts',
  'manualjournal',
  'budgets',
  
  // Sales
  'invoices',
  'recurringinvoices',
  'quotes',
  'salesorders',
  'creditnotes',
  'deliverychallans',
  
  // Purchases
  'bills',
  'recurringbills',
  'purchaseorders',
  'expenses',
  'recurringexpenses',
  'vendorcredits',
  
  // Vendors & Customers
  'billingvendors',
  'billingcustomers',
  
  // Banking & Payments
  'paymentaccounts',
  'paymentsmade',
  'paymentsreceived',
  'paymentlinks',
  
  // Items & Assets
  'items',
  'fixedassets',
];

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function deleteFile(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
      return true;
    }
  } catch (err) {
    console.error(`   ⚠️  Failed to delete file: ${filePath}`, err.message);
  }
  return false;
}

function formatNumber(num) {
  return num.toLocaleString();
}

// ============================================================================
// MAIN RESET FUNCTION
// ============================================================================

async function resetBranchData(branchName) {
  console.log('\n' + '═'.repeat(80));
  console.log('🗑️  BRANCH DATA RESET SCRIPT');
  console.log('═'.repeat(80));
  console.log(`Branch Name: "${branchName}"`);
  console.log('⚠️  WARNING: This will DELETE ALL DATA for this branch!');
  console.log('═'.repeat(80) + '\n');

  // Connect to database
  await mongoose.connect(MONGODB_URI);
  console.log('✅ Connected to MongoDB\n');

  const db = mongoose.connection.db;

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 1: Find the branch
  // ──────────────────────────────────────────────────────────────────────────
  console.log('🔍 Step 1: Finding branch...');
  const branch = await db.collection('branches').findOne({
    branchName: { $regex: new RegExp(`^${branchName}$`, 'i') }
  });

  if (!branch) {
    console.error(`❌ Branch "${branchName}" not found!`);
    await mongoose.disconnect();
    process.exit(1);
  }

  const { branchId, orgId } = branch;
  console.log(`   ✅ Found branch:`);
  console.log(`      Branch ID: ${branchId}`);
  console.log(`      Org ID: ${orgId}`);
  console.log(`      Branch Name: ${branch.branchName}`);
  console.log();

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 2: Delete data from all collections
  // ──────────────────────────────────────────────────────────────────────────
  console.log('🗑️  Step 2: Deleting branch data from collections...\n');

  const deletionReport = [];
  let totalDeleted = 0;

  for (const collectionName of COLLECTIONS_TO_CLEAN) {
    try {
      // Check if collection exists
      const collections = await db.listCollections({ name: collectionName }).toArray();
      if (collections.length === 0) {
        console.log(`   ⏭️  ${collectionName.padEnd(30)} - Collection not found, skipping`);
        continue;
      }

      // Count documents before deletion
      const countBefore = await db.collection(collectionName).countDocuments({ branchId });

      if (countBefore === 0) {
        console.log(`   ⏭️  ${collectionName.padEnd(30)} - No documents to delete`);
        continue;
      }

      // Delete documents
      const result = await db.collection(collectionName).deleteMany({ branchId });
      const deleted = result.deletedCount;
      totalDeleted += deleted;

      console.log(`   ✅ ${collectionName.padEnd(30)} - Deleted ${formatNumber(deleted)} documents`);
      deletionReport.push({ collection: collectionName, deleted });

    } catch (err) {
      console.error(`   ❌ ${collectionName.padEnd(30)} - Error: ${err.message}`);
      deletionReport.push({ collection: collectionName, deleted: 0, error: err.message });
    }
  }

  console.log();

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 3: Delete branch files (logos, signatures)
  // ──────────────────────────────────────────────────────────────────────────
  console.log('🗑️  Step 3: Deleting branch files...\n');

  const uploadsDir = path.join(__dirname, 'uploads');
  let filesDeleted = 0;

  // Delete branch logo
  if (branch.logoUrl) {
    const logoPath = path.join(__dirname, branch.logoUrl.replace(/^\//, ''));
    if (deleteFile(logoPath)) {
      console.log(`   ✅ Deleted logo: ${branch.logoUrl}`);
      filesDeleted++;
    }
  }

  // Delete branch signature
  if (branch.digitalSignaturePath) {
    const sigPath = path.join(__dirname, branch.digitalSignaturePath.replace(/^\//, ''));
    if (deleteFile(sigPath)) {
      console.log(`   ✅ Deleted signature: ${branch.digitalSignaturePath}`);
      filesDeleted++;
    }
  }

  // Delete all files in branch-specific folders
  const branchFolders = [
    path.join(uploadsDir, 'branch-logos'),
    path.join(uploadsDir, 'branch-signatures'),
  ];

  for (const folder of branchFolders) {
    if (fs.existsSync(folder)) {
      const files = fs.readdirSync(folder);
      for (const file of files) {
        if (file.includes(branchId)) {
          const filePath = path.join(folder, file);
          if (deleteFile(filePath)) {
            console.log(`   ✅ Deleted file: ${file}`);
            filesDeleted++;
          }
        }
      }
    }
  }

  if (filesDeleted === 0) {
    console.log('   ⏭️  No files to delete');
  }

  console.log();

  // ──────────────────────────────────────────────────────────────────────────
  // STEP 4: Delete the branch record itself
  // ──────────────────────────────────────────────────────────────────────────
  console.log('🗑️  Step 4: Deleting branch record...\n');

  const branchDeleteResult = await db.collection('branches').deleteOne({ branchId });
  if (branchDeleteResult.deletedCount > 0) {
    console.log(`   ✅ Branch record deleted\n`);
  } else {
    console.log(`   ⚠️  Branch record not deleted (may have been removed already)\n`);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FINAL REPORT
  // ──────────────────────────────────────────────────────────────────────────
  console.log('═'.repeat(80));
  console.log('📊 DELETION SUMMARY');
  console.log('═'.repeat(80));
  console.log(`Branch: ${branchName}`);
  console.log(`Branch ID: ${branchId}`);
  console.log(`Org ID: ${orgId}`);
  console.log();
  console.log(`Total Documents Deleted: ${formatNumber(totalDeleted)}`);
  console.log(`Total Files Deleted: ${filesDeleted}`);
  console.log(`Branch Record Deleted: ${branchDeleteResult.deletedCount > 0 ? 'Yes' : 'No'}`);
  console.log();

  if (deletionReport.length > 0) {
    console.log('Breakdown by Collection:');
    console.log('─'.repeat(80));
    for (const item of deletionReport) {
      if (item.deleted > 0) {
        console.log(`   ${item.collection.padEnd(30)} ${formatNumber(item.deleted).padStart(10)} documents`);
      }
    }
  }

  console.log('═'.repeat(80));
  console.log('✅ BRANCH DATA RESET COMPLETE!');
  console.log('═'.repeat(80) + '\n');

  await mongoose.disconnect();
}

// ============================================================================
// RESET BY BRANCH ID (direct, no name lookup needed)
// ============================================================================

async function resetBranchById(branchId) {
  console.log('\n' + '═'.repeat(80));
  console.log('🗑️  BRANCH DATA RESET SCRIPT (by ID)');
  console.log('═'.repeat(80));
  console.log(`Branch ID: "${branchId}"`);
  console.log('⚠️  WARNING: This will DELETE ALL DATA for this branch!');
  console.log('═'.repeat(80) + '\n');

  await mongoose.connect(MONGODB_URI);
  console.log('✅ Connected to MongoDB\n');

  const db = mongoose.connection.db;

  // Find branch record
  console.log('🔍 Step 1: Finding branch...');
  const branch = await db.collection('branches').findOne({ branchId });

  if (!branch) {
    // Branch record may already be gone — still proceed with data cleanup
    console.log(`   ⚠️  Branch record not found in branches collection (may already be deleted)`);
    console.log(`   ℹ️  Proceeding with data cleanup using branchId: ${branchId}\n`);
  } else {
    console.log(`   ✅ Found branch:`);
    console.log(`      Branch ID  : ${branch.branchId}`);
    console.log(`      Org ID     : ${branch.orgId}`);
    console.log(`      Branch Name: ${branch.branchName}`);
    console.log();
  }

  // Delete all collection data
  console.log('🗑️  Step 2: Deleting branch data from collections...\n');

  const deletionReport = [];
  let totalDeleted = 0;

  for (const collectionName of COLLECTIONS_TO_CLEAN) {
    try {
      const collections = await db.listCollections({ name: collectionName }).toArray();
      if (collections.length === 0) {
        console.log(`   ⏭️  ${collectionName.padEnd(30)} - Collection not found, skipping`);
        continue;
      }

      const countBefore = await db.collection(collectionName).countDocuments({ branchId });

      if (countBefore === 0) {
        console.log(`   ⏭️  ${collectionName.padEnd(30)} - No documents to delete`);
        continue;
      }

      const result = await db.collection(collectionName).deleteMany({ branchId });
      const deleted = result.deletedCount;
      totalDeleted += deleted;

      console.log(`   ✅ ${collectionName.padEnd(30)} - Deleted ${formatNumber(deleted)} documents`);
      deletionReport.push({ collection: collectionName, deleted });

    } catch (err) {
      console.error(`   ❌ ${collectionName.padEnd(30)} - Error: ${err.message}`);
      deletionReport.push({ collection: collectionName, deleted: 0, error: err.message });
    }
  }

  console.log();

  // Delete files
  console.log('🗑️  Step 3: Deleting branch files...\n');

  const uploadsDir = path.join(__dirname, 'uploads');
  let filesDeleted = 0;

  if (branch) {
    if (branch.logoUrl) {
      const logoPath = path.join(__dirname, branch.logoUrl.replace(/^\//, ''));
      if (deleteFile(logoPath)) { console.log(`   ✅ Deleted logo: ${branch.logoUrl}`); filesDeleted++; }
    }
    if (branch.digitalSignaturePath) {
      const sigPath = path.join(__dirname, branch.digitalSignaturePath.replace(/^\//, ''));
      if (deleteFile(sigPath)) { console.log(`   ✅ Deleted signature: ${branch.digitalSignaturePath}`); filesDeleted++; }
    }
  }

  // Scan upload folders for files containing this branchId
  const branchFolders = [
    path.join(uploadsDir, 'branch-logos'),
    path.join(uploadsDir, 'branch-signatures'),
  ];

  for (const folder of branchFolders) {
    if (fs.existsSync(folder)) {
      const files = fs.readdirSync(folder);
      for (const file of files) {
        if (file.includes(branchId)) {
          if (deleteFile(path.join(folder, file))) {
            console.log(`   ✅ Deleted file: ${file}`);
            filesDeleted++;
          }
        }
      }
    }
  }

  if (filesDeleted === 0) console.log('   ⏭️  No files to delete');
  console.log();

  // Delete branch record
  console.log('🗑️  Step 4: Deleting branch record...\n');
  const branchDeleteResult = await db.collection('branches').deleteOne({ branchId });
  console.log(branchDeleteResult.deletedCount > 0
    ? '   ✅ Branch record deleted\n'
    : '   ⏭️  Branch record already removed\n');

  // Summary
  console.log('═'.repeat(80));
  console.log('📊 DELETION SUMMARY');
  console.log('═'.repeat(80));
  console.log(`Branch ID : ${branchId}`);
  console.log(`Total Documents Deleted : ${formatNumber(totalDeleted)}`);
  console.log(`Total Files Deleted     : ${filesDeleted}`);
  console.log();

  if (deletionReport.length > 0) {
    console.log('Breakdown by Collection:');
    console.log('─'.repeat(80));
    for (const item of deletionReport) {
      if (item.deleted > 0) {
        console.log(`   ${item.collection.padEnd(30)} ${formatNumber(item.deleted).padStart(10)} documents`);
      }
    }
  }

  console.log('═'.repeat(80));
  console.log('✅ BRANCH DATA RESET COMPLETE!');
  console.log('═'.repeat(80) + '\n');

  await mongoose.disconnect();
}

// ============================================================================
// SCRIPT EXECUTION
// ============================================================================

const arg = process.argv[2];

if (!arg) {
  console.error('\n❌ Error: Branch name or ID is required!');
  console.error('\nUsage:');
  console.error('  node reset_branch_data.js "Branch Name"');
  console.error('  node reset_branch_data.js --id <branchId>');
  console.error('\nExamples:');
  console.error('  node reset_branch_data.js "Testing - branch 1 - Asha"');
  console.error('  node reset_branch_data.js --id 69e86043899a84339ba74a18');
  console.error();
  process.exit(1);
}

// Detect --id flag
const useId   = arg === '--id';
const target  = useId ? process.argv[3] : arg;

if (useId && !target) {
  console.error('\n❌ Error: --id flag requires a branchId value');
  process.exit(1);
}

console.log('\n⚠️  WARNING: You are about to DELETE ALL DATA for:');
console.log(`   ${useId ? 'Branch ID' : 'Branch Name'}: "${target}"`);
console.log('\n   This action is IRREVERSIBLE!');
console.log('\n   Press Ctrl+C to cancel, or wait 5 seconds to continue...\n');

setTimeout(() => {
  const fn = useId ? resetBranchById(target) : resetBranchData(target);
  fn.catch(err => {
    console.error('\n❌ Error:', err);
    process.exit(1);
  });
}, 5000);
