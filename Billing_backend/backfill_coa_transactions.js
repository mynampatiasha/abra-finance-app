// ============================================================================
// BACKFILL COA TRANSACTIONS
// ============================================================================
// Run once to create missing AccountTransaction entries for all existing
// payments_received, payments_made, and expenses records.
//
// Usage:  node backfill_coa_transactions.js
// ============================================================================

require('dotenv').config();
const mongoose = require('mongoose');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME     = process.env.FINANCE_DB_NAME || 'abra_finance_module';

// ── Schemas (minimal — only what we need) ────────────────────────────────────

const coaSchema = new mongoose.Schema({
  accountName:     String,
  accountCode:     String,
  accountType:     String,
  isSystemAccount: Boolean,
  orgId:           String,
  isActive:        Boolean,
}, { strict: false });
const ChartOfAccount = mongoose.models.ChartOfAccount
  || mongoose.model('ChartOfAccount', coaSchema, 'chartofaccounts');

const txnSchema = new mongoose.Schema({
  accountId:       mongoose.Schema.Types.ObjectId,
  orgId:           String,
  date:            Date,
  description:     String,
  referenceType:   String,
  referenceId:     mongoose.Schema.Types.ObjectId,
  referenceNumber: String,
  debit:           Number,
  credit:          Number,
  balance:         Number,
}, { strict: false, timestamps: true });
const AccountTransaction = mongoose.models.AccountTransaction
  || mongoose.model('AccountTransaction', txnSchema, 'accounttransactions');

// ── Helpers ───────────────────────────────────────────────────────────────────

async function getAccountId(name, orgId) {
  const acc = await ChartOfAccount.findOne({
    accountName: { $regex: new RegExp(`^${name}$`, 'i') },
    ...(orgId ? { orgId } : {}),
  }).select('_id').lean();
  if (acc) return acc._id;
  // fallback without orgId
  const fallback = await ChartOfAccount.findOne({
    accountName: { $regex: new RegExp(`^${name}$`, 'i') },
  }).select('_id').lean();
  return fallback?._id || null;
}

async function alreadyPosted(referenceId, referenceType) {
  const count = await AccountTransaction.countDocuments({ referenceId, referenceType });
  return count > 0;
}

async function postTxn({ accountId, orgId, date, description, referenceType, referenceId, referenceNumber, debit, credit }) {
  if (!accountId) return;
  const lastTxn = await AccountTransaction.findOne({ accountId })
    .sort({ date: -1, createdAt: -1 }).lean();
  const prevBalance = lastTxn?.balance || 0;
  const newBalance  = prevBalance + (debit || 0) - (credit || 0);
  await AccountTransaction.create({
    accountId, orgId, date, description,
    referenceType, referenceId, referenceNumber,
    debit: debit || 0, credit: credit || 0, balance: newBalance,
  });
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function run() {
  await mongoose.connect(MONGODB_URI, { dbName: DB_NAME });
  console.log('✅ Connected to MongoDB:', DB_NAME);

  const db = mongoose.connection.db;

  let created = 0;
  let skipped = 0;

  // ── 1. payments_received ─────────────────────────────────────────────────
  console.log('\n📥 Processing payments_received...');
  const paymentsReceived = await db.collection('payments_received').find({}).toArray();
  console.log(`   Found ${paymentsReceived.length} records`);

  for (const p of paymentsReceived) {
    if (await alreadyPosted(p._id, 'Payment')) { skipped++; continue; }

    const orgId  = p.orgId || null;
    const amount = p.amountReceived || p.amount || p.netAmount || 0;
    if (!amount) { skipped++; continue; }

    const txnDate = new Date(p.paymentDate || p.createdAt);
    const depositName = p.depositTo || 'Undeposited Funds';

    // Resolve deposit account (bank/cash)
    let depositId = await getAccountId(depositName, orgId);
    if (!depositId) depositId = await getAccountId('Undeposited Funds', orgId);

    const arId = await getAccountId('Accounts Receivable', orgId);

    const desc = `[BACKFILL] Payment received - ${p.paymentNumber} - ${p.customerName}`;

    // Dr Bank/Cash (money came in)
    if (depositId) {
      await postTxn({ accountId: depositId, orgId, date: txnDate, description: desc,
        referenceType: 'Payment', referenceId: p._id, referenceNumber: p.paymentNumber,
        debit: amount, credit: 0 });
      created++;
    }
    // Cr Accounts Receivable
    if (arId) {
      await postTxn({ accountId: arId, orgId, date: txnDate, description: desc,
        referenceType: 'Payment', referenceId: p._id, referenceNumber: p.paymentNumber,
        debit: 0, credit: amount });
      created++;
    }

    process.stdout.write('.');
  }

  // ── 2. payments_made ─────────────────────────────────────────────────────
  console.log('\n\n📤 Processing payments_made...');
  const paymentsMade = await db.collection('payments_made').find({
    status: { $nin: ['VOIDED', 'void'] },
  }).toArray();
  console.log(`   Found ${paymentsMade.length} records`);

  for (const p of paymentsMade) {
    if (await alreadyPosted(p._id, 'PaymentMade')) { skipped++; continue; }

    const orgId  = p.orgId || null;
    const amount = p.totalAmount || p.amount || 0;
    if (!amount) { skipped++; continue; }

    const txnDate = new Date(p.paymentDate || p.createdAt);

    // Resolve bank account used
    let bankId = p.paidFromAccountId
      ? await ChartOfAccount.findById(p.paidFromAccountId).select('_id').lean().then(a => a?._id)
      : null;
    if (!bankId) bankId = await getAccountId('Undeposited Funds', orgId);

    const apId = await getAccountId('Accounts Payable', orgId);

    const desc = `[BACKFILL] Payment made - ${p.paymentNumber} - ${p.vendorName}`;

    // Dr Accounts Payable (liability reduced)
    if (apId) {
      await postTxn({ accountId: apId, orgId, date: txnDate, description: desc,
        referenceType: 'PaymentMade', referenceId: p._id, referenceNumber: p.paymentNumber,
        debit: amount, credit: 0 });
      created++;
    }
    // Cr Bank/Cash (money went out)
    if (bankId) {
      await postTxn({ accountId: bankId, orgId, date: txnDate, description: desc,
        referenceType: 'PaymentMade', referenceId: p._id, referenceNumber: p.paymentNumber,
        debit: 0, credit: amount });
      created++;
    }

    process.stdout.write('.');
  }

  // ── 3. expenses ──────────────────────────────────────────────────────────
  console.log('\n\n🧾 Processing expenses...');
  const expenses = await db.collection('expenses').find({}).toArray();
  console.log(`   Found ${expenses.length} records`);

  for (const e of expenses) {
    if (await alreadyPosted(e._id, 'Expense')) { skipped++; continue; }

    const orgId  = e.orgId || null;
    const amount = e.total || e.amount || 0;
    if (!amount) { skipped++; continue; }

    const txnDate = new Date(e.date || e.expenseDate || e.createdAt);

    // Resolve expense account
    const expenseAccountName = e.expenseAccount || e.account || 'Other Expense';
    let expenseId = await getAccountId(expenseAccountName, orgId);
    if (!expenseId) expenseId = await getAccountId('Other Expense', orgId);

    // Resolve paid-from account
    let bankId = null;
    if (e.paidThroughAccount || e.paidThrough) {
      bankId = await getAccountId(e.paidThroughAccount || e.paidThrough, orgId);
    }
    if (!bankId) bankId = await getAccountId('Undeposited Funds', orgId);

    const desc = `[BACKFILL] Expense - ${e.expenseNumber || e._id}`;

    // Dr Expense account
    if (expenseId) {
      await postTxn({ accountId: expenseId, orgId, date: txnDate, description: desc,
        referenceType: 'Expense', referenceId: e._id, referenceNumber: e.expenseNumber,
        debit: amount, credit: 0 });
      created++;
    }
    // Cr Bank/Cash (money went out)
    if (bankId) {
      await postTxn({ accountId: bankId, orgId, date: txnDate, description: desc,
        referenceType: 'Expense', referenceId: e._id, referenceNumber: e.expenseNumber,
        debit: 0, credit: amount });
      created++;
    }

    process.stdout.write('.');
  }

  console.log(`\n\n✅ Done!`);
  console.log(`   AccountTransaction entries created : ${created}`);
  console.log(`   Records skipped (already posted)   : ${skipped}`);

  await mongoose.disconnect();
}

run().catch(err => {
  console.error('❌ Backfill failed:', err);
  process.exit(1);
});
