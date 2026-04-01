// ============================================================================
// MIGRATION SCRIPT — One-time run
// Assigns organizationId to all existing records missing it
// Org: Abra Travels → 69bd251dd852a7f1531cb66d
// ============================================================================
// HOW TO RUN:
//   1. Place this file in your backend root folder
//   2. Run: node migrate.js
//   3. Wait for "✅ Migration complete" message
//   4. Delete this file after running
// ============================================================================

require('dotenv').config();
const mongoose = require('mongoose');

// ── Abra Travels orgId ────────────────────────────────────────────────────────
const ABRA_TRAVELS_ORG_ID = '69bd251dd852a7f1531cb66d';

// ── All collections that need migration ───────────────────────────────────────
const COLLECTIONS = [
  'invoices',
  'bills',
  'expenses',
  'payments_received',
  'paymentmades',
  'quotes',
  'salesorders',
  'purchaseorders',
  'vendorcredits',
  'recurringbills',
  'recurringexpenses',
  'recurringinvoices',
  'projects',
  'ratecards',
  'vendors',
  'reconciliationsessions',
  'tripbillings',
  'timesheets',
  'budgets',
  'manualjournals',
  'creditnotes',
  'deliverychallans',
  'recurringexpensesgenerated',
];

async function migrate() {
  // ── Connect to MongoDB ──────────────────────────────────────────────────────
  const mongoUri = process.env.MONGODB_URI || process.env.MONGO_URI;

  if (!mongoUri) {
    console.error('❌ No MONGODB_URI found in .env file');
    process.exit(1);
  }

  console.log('\n🔌 Connecting to MongoDB...');
  await mongoose.connect(mongoUri);
  console.log('✅ Connected to MongoDB\n');

  const db = mongoose.connection.db;

  let grandTotal = 0;

  // ── Loop through each collection ────────────────────────────────────────────
  for (const collectionName of COLLECTIONS) {
    try {
      // Check if collection exists
      const collections = await db
        .listCollections({ name: collectionName })
        .toArray();

      if (collections.length === 0) {
        console.log(`⏭️  Skipping "${collectionName}" — collection does not exist`);
        continue;
      }

      const collection = db.collection(collectionName);

      // Count records missing organizationId
      const missingCount = await collection.countDocuments({
        $and: [
          {
            $or: [
              { organizationId: { $exists: false } },
              { organizationId: null },
              { organizationId: '' },
            ],
          },
          // Also handle invoices that use "orgId" field name
          {
            $or: [
              { orgId: { $exists: false } },
              { orgId: null },
              { orgId: '' },
              { orgId: { $exists: true } }, // has orgId — will set organizationId too
            ],
          },
        ],
      });

      // Simpler count — just find anything without organizationId
      const toUpdateCount = await collection.countDocuments({
        $or: [
          { organizationId: { $exists: false } },
          { organizationId: null },
          { organizationId: '' },
        ],
      });

      if (toUpdateCount === 0) {
        console.log(`✅ "${collectionName}" — already up to date (0 records to migrate)`);
        continue;
      }

      console.log(
        `📋 "${collectionName}" — found ${toUpdateCount} records to migrate...`
      );

      // Update all records missing organizationId
      const result = await collection.updateMany(
        {
          $or: [
            { organizationId: { $exists: false } },
            { organizationId: null },
            { organizationId: '' },
          ],
        },
        {
          $set: { organizationId: ABRA_TRAVELS_ORG_ID },
        }
      );

      console.log(
        `   ✅ Updated ${result.modifiedCount} records in "${collectionName}"`
      );
      grandTotal += result.modifiedCount;

    } catch (err) {
      console.error(`   ❌ Error migrating "${collectionName}":`, err.message);
    }
  }

  // ── Special handling for invoices — also set orgId field ───────────────────
  // invoices.js uses "orgId" field name (not organizationId)
  // We set both so it works before and after the code fix
  try {
    const invoiceCollection = db.collection('invoices');
    const invoicesWithoutOrgId = await invoiceCollection.countDocuments({
      $or: [
        { orgId: { $exists: false } },
        { orgId: null },
        { orgId: '' },
      ],
    });

    if (invoicesWithoutOrgId > 0) {
      const result = await invoiceCollection.updateMany(
        {
          $or: [
            { orgId: { $exists: false } },
            { orgId: null },
            { orgId: '' },
          ],
        },
        {
          $set: { orgId: ABRA_TRAVELS_ORG_ID },
        }
      );
      console.log(
        `   ✅ Also set "orgId" field on ${result.modifiedCount} invoices`
      );
    }
  } catch (err) {
    console.error('   ❌ Error setting orgId on invoices:', err.message);
  }

  // ── Summary ─────────────────────────────────────────────────────────────────
  console.log('\n══════════════════════════════════════════');
  console.log(`✅ Migration complete!`);
  console.log(`   Total records updated: ${grandTotal}`);
  console.log(`   Assigned to org: Abra Travels (${ABRA_TRAVELS_ORG_ID})`);
  console.log('══════════════════════════════════════════\n');

  await mongoose.disconnect();
  console.log('🔌 Disconnected from MongoDB');
  process.exit(0);
}

migrate().catch((err) => {
  console.error('❌ Migration failed:', err.message);
  process.exit(1);
});