// ============================================================================
// CHART OF ACCOUNTS — BACKEND
// ============================================================================
// File: backend/routes/chart_of_accounts.js
// Express routes + MongoDB model + Controller logic
// Register in app.js: app.use('/api/chart-of-accounts', require('./routes/chart_of_accounts'));
// ============================================================================

const express   = require('express');
const router    = express.Router();
const mongoose  = require('mongoose');
const multer    = require('multer');
const path      = require('path');

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const chartOfAccountSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  accountCode: {
    type: String,
    trim: true,
    default: '',
  },
  accountName: {
    type: String,
    required: [true, 'Account name is required'],
    trim: true,
    index: true,
  },
  accountType: {
    type: String,
    required: [true, 'Account type is required'],
    enum: [
      'Asset', 'Liability', 'Equity', 'Income', 'Expense',
      // Detailed types (Zoho Books style)
      'Accounts Receivable', 'Accounts Payable',
      'Other Current Asset', 'Fixed Asset', 'Other Asset',
      'Cash', 'Stock',
      'Other Current Liability', 'Non Current Liability', 'Other Liability',
      'Cost Of Goods Sold', 'Other Expense', 'Other Income',
    ],
    index: true,
  },
  accountSubType: {
    type: String,
    trim: true,
    default: '',
  },
  parentAccountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'ChartOfAccount',
    default: null,
  },
  parentAccountName: {
    type: String,
    default: null,
  },
  description: {
    type: String,
    trim: true,
    default: '',
  },
  currency: {
    type: String,
    default: 'INR',
  },
  isActive: {
    type: Boolean,
    default: true,
    index: true,
  },
  isSystemAccount: {
    type: Boolean,
    default: false,
  },
  // Computed balance (updated on journal posting)
  closingBalance: {
    type: Number,
    default: 0,
  },
  balanceType: {
    type: String,
    enum: ['Dr', 'Cr'],
    default: 'Dr',
  },
  // Linked org/company
  companyId: {
    type: String,
    default: 'default',
  },
  createdBy: {
    type: String,
    default: 'system',
  },
  updatedBy: {
    type: String,
    default: 'system',
  },
}, {
  timestamps: true,
});

// Indexes
chartOfAccountSchema.index({ accountName: 1, companyId: 1 });
chartOfAccountSchema.index({ accountType: 1, isActive: 1 });
chartOfAccountSchema.index({ isSystemAccount: 1 });

const ChartOfAccount = mongoose.models.ChartOfAccount
  || mongoose.model('ChartOfAccount', chartOfAccountSchema);

// ============================================================================
// ACCOUNT TRANSACTIONS SCHEMA (virtual ledger entries)
// ============================================================================

const accountTransactionSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  accountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'ChartOfAccount',
    required: true,
    index: true,
  },
  date: {
    type: Date,
    required: true,
    default: Date.now,
    index: true,
  },
  description: {
    type: String,
    required: true,
    trim: true,
  },
  referenceType: {
    type: String,
    enum: ['Invoice', 'Bill', 'Payment', 'Journal', 'Expense', 'Credit Note', 'Vendor Credit', 'Opening Balance'],
    required: true,
  },
  referenceId: {
    type: mongoose.Schema.Types.ObjectId,
    default: null,
  },
  referenceNumber: {
    type: String,
    default: '',
  },
  debit: {
    type: Number,
    default: 0,
    min: 0,
  },
  credit: {
    type: Number,
    default: 0,
    min: 0,
  },
  balance: {
    type: Number,
    default: 0,
  },
  companyId: {
    type: String,
    default: 'default',
  },
}, {
  timestamps: true,
});

accountTransactionSchema.index({ accountId: 1, date: -1 });

const AccountTransaction = mongoose.models.AccountTransaction
  || mongoose.model('AccountTransaction', accountTransactionSchema);

// ============================================================================
// HELPER — Auto generate account code
// ============================================================================

async function generateAccountCode(accountType, orgId = null) {
  const prefixMap = {
    'Asset': '1', 'Accounts Receivable': '1', 'Other Current Asset': '1',
    'Fixed Asset': '1', 'Cash': '1', 'Stock': '1', 'Other Asset': '1',
    'Liability': '2', 'Accounts Payable': '2', 'Other Current Liability': '2',
    'Non Current Liability': '2', 'Other Liability': '2',
    'Equity': '3',
    'Income': '4', 'Other Income': '4',
    'Expense': '5', 'Cost Of Goods Sold': '5', 'Other Expense': '5',
  };
  const prefix = prefixMap[accountType] || '9';
  const last = await ChartOfAccount.findOne(
    { accountCode: new RegExp(`^${prefix}`), ...(orgId ? { orgId } : {}) },
    { accountCode: 1 }
  ).sort({ accountCode: -1 });

  let seq = parseInt(prefix) * 1000 + 1;
  if (last && last.accountCode) {
    const n = parseInt(last.accountCode.replace(/\D/g, ''));
    if (!isNaN(n)) seq = n + 1;
  }
  return seq.toString();
}

// ============================================================================
// SEED DEFAULT SYSTEM ACCOUNTS (call once on startup if needed)
// ============================================================================

async function seedSystemAccounts(orgId = null) {
  const systemAccounts = [
    { accountCode: '1100', accountName: 'Accounts Receivable',        accountType: 'Accounts Receivable',     accountSubType: 'Accounts Receivable',    isSystemAccount: true, description: 'Money owed to you by customers' },
    { accountCode: '2100', accountName: 'Accounts Payable',           accountType: 'Accounts Payable',        accountSubType: 'Accounts Payable',       isSystemAccount: true, description: 'Money you owe to vendors' },
    { accountCode: '1010', accountName: 'Petty Cash',                 accountType: 'Cash',                    accountSubType: 'Cash',                   isSystemAccount: true, description: 'Cash on hand' },
    { accountCode: '1020', accountName: 'Undeposited Funds',          accountType: 'Cash',                    accountSubType: 'Cash',                   isSystemAccount: true, description: 'Payments not yet deposited' },
    { accountCode: '1301', accountName: 'Inventory Asset',            accountType: 'Stock',                   accountSubType: 'Stock',                  isSystemAccount: true, description: 'Value of goods in stock' },
    { accountCode: '2200', accountName: 'Opening Balance Adjustments',accountType: 'Other Current Liability', accountSubType: 'Other Current Liability',isSystemAccount: true },
    { accountCode: '3010', accountName: 'Opening Balance Offset',     accountType: 'Equity',                  accountSubType: 'Equity',                 isSystemAccount: true },
    { accountCode: '3020', accountName: 'Retained Earnings',          accountType: 'Equity',                  accountSubType: 'Equity',                 isSystemAccount: true, description: 'Accumulated profits' },
    { accountCode: '4010', accountName: 'Sales',                      accountType: 'Income',                  accountSubType: 'Income',                 isSystemAccount: true, description: 'Revenue from sales' },
    { accountCode: '5010', accountName: 'Cost of Goods Sold',         accountType: 'Cost Of Goods Sold',      accountSubType: 'Cost Of Goods Sold',     isSystemAccount: true, description: 'Direct cost of goods sold' },
    { accountCode: '2300', accountName: 'Tax Payable',                accountType: 'Other Current Liability', accountSubType: 'Other Current Liability',isSystemAccount: true, description: 'GST/Tax collected but not yet remitted' },
    { accountCode: '1400', accountName: 'TDS Receivable',             accountType: 'Other Current Asset',     accountSubType: 'Other Current Asset',    isSystemAccount: true },
    { accountCode: '2310', accountName: 'TDS Payable',                accountType: 'Other Current Liability', accountSubType: 'Other Current Liability',isSystemAccount: true },
  ];

  let created = 0;
  for (const acc of systemAccounts) {
    const exists = await ChartOfAccount.findOne({ accountName: acc.accountName, isSystemAccount: true, orgId: orgId });
    if (!exists) {
      await ChartOfAccount.create({ ...acc, isActive: true, createdBy: 'system', orgId: orgId });
      created++;
    }
  }
  if (created > 0) console.log(`✅ System accounts seeded: ${created} created`);
  else console.log('✅ System accounts already present');
}

// Seed on module load
// seedSystemAccounts().catch(console.error);

// ============================================================================
// MIDDLEWARE — authenticate (reuse from your project)
// ============================================================================
// Replace with your actual authenticate middleware
const { verifyFinanceJWT } = require('../middleware/finance_jwt');
const authenticate = verifyFinanceJWT;

// ============================================================================
// ROUTES
// ============================================================================

// ── POST /seed (trigger system account seeding) ───────────────────────────────
router.post('/seed', authenticate, async (req, res) => {
  try {
    await seedSystemAccounts(req.user?.orgId || null);
    const accounts = await ChartOfAccount.find({ isSystemAccount: true, orgId: req.user?.orgId || null }).lean();
    res.json({ success: true, message: 'System accounts seeded', count: accounts.length, accounts: accounts.map(a => a.accountName) });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /stats ────────────────────────────────────────────────────────────────
router.get('/stats', authenticate, async (req, res) => {
  try {
const orgFilter = { orgId: req.user?.orgId };
const [total, active, inactive, byType] = await Promise.all([
  ChartOfAccount.countDocuments(orgFilter),
  ChartOfAccount.countDocuments({ ...orgFilter, isActive: true }),
  ChartOfAccount.countDocuments({ ...orgFilter, isActive: false }),
  ChartOfAccount.aggregate([
    { $match: orgFilter },
    { $group: { _id: '$accountType', count: { $sum: 1 } } }
  ]),
]);

    const byTypeMap = {};
    byType.forEach(b => { byTypeMap[b._id] = b.count; });

    res.json({
      success: true,
      data: { totalAccounts: total, activeAccounts: active, inactiveAccounts: inactive, byType: byTypeMap },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET / (list) ──────────────────────────────────────────────────────────────
router.get('/', authenticate, async (req, res) => {
  try {
    const { accountType, isActive, search, page = 1, limit = 200 } = req.query;

    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (accountType && accountType !== 'All') {
      // Support broad category matching
      const broadMap = {
        'Asset':     ['Asset','Accounts Receivable','Other Current Asset','Fixed Asset','Cash','Stock','Other Asset'],
        'Liability': ['Liability','Accounts Payable','Other Current Liability','Non Current Liability','Other Liability'],
        'Equity':    ['Equity'],
        'Income':    ['Income','Other Income'],
        'Expense':   ['Expense','Cost Of Goods Sold','Other Expense'],
      };
      if (broadMap[accountType]) {
        query.accountType = { $in: broadMap[accountType] };
      } else {
        query.accountType = accountType;
      }
    }
    if (isActive !== undefined && isActive !== 'null') {
      query.isActive = isActive === 'true';
    }
    if (search && search.trim()) {
      query.$or = [
        { accountName: { $regex: search.trim(), $options: 'i' } },
        { accountCode: { $regex: search.trim(), $options: 'i' } },
        { accountType: { $regex: search.trim(), $options: 'i' } },
      ];
    }

    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const total = await ChartOfAccount.countDocuments(query);

    const accounts = await ChartOfAccount.find(query)
      .sort({ accountType: 1, accountName: 1 })
      .skip(skip)
      .limit(parseInt(limit))
      .lean();

    // Attach transaction count per account
    const ids = accounts.map(a => a._id);
    const txnCounts = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', count: { $sum: 1 } } },
    ]);
    const txnMap = {};
    txnCounts.forEach(t => { txnMap[t._id.toString()] = t.count; });

    const enriched = accounts.map(a => ({
      ...a,
      id: a._id,
      transactionCount: txnMap[a._id.toString()] || 0,
    }));

    res.json({
      success: true,
      data: {
        accounts: enriched,
        pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});



// ── GET /:id/transactions ─────────────────────────────────────────────────────
router.get('/:id/transactions', authenticate, async (req, res) => {
  try {
    const { fromDate, toDate } = req.query;

    // Verify account belongs to this org before returning its transactions
    const account = await ChartOfAccount.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });

    const query = { accountId: req.params.id };
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (fromDate || toDate) {
      query.date = {};
      if (fromDate) query.date.$gte = new Date(fromDate);
      if (toDate)   query.date.$lte = new Date(toDate);
    }

    const txns = await AccountTransaction.find(query)
      .sort({ date: -1 })
      .limit(500)
      .lean();

    res.json({ success: true, data: txns.map(t => ({ ...t, id: t._id })) });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});
// ── GET /:id ──────────────────────────────────────────────────────────────────
router.get('/:id', authenticate, async (req, res) => {
  try {
    const account = await ChartOfAccount.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });

    const txnCount = await AccountTransaction.countDocuments({
      accountId: account._id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    res.json({ success: true, data: { ...account, id: account._id, transactionCount: txnCount } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST / (create) ───────────────────────────────────────────────────────────
router.post('/', authenticate, async (req, res) => {
  try {
    const data = req.body;

    // Check duplicate name
    const existing = await ChartOfAccount.findOne({
      accountName: { $regex: `^${data.accountName}$`, $options: 'i' },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (existing) {
      return res.status(400).json({ success: false, message: `Account "${data.accountName}" already exists` });
    }

    // Auto code if not provided
    if (!data.accountCode || data.accountCode.trim() === '') {
      data.accountCode = await generateAccountCode(data.accountType, req.user?.orgId);
    }

    // Resolve parent name
    if (data.parentAccountId) {
      const parent = await ChartOfAccount.findOne({
        _id: data.parentAccountId,
        ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
      }).lean();
      if (parent) data.parentAccountName = parent.accountName;
    }

    const account = await ChartOfAccount.create({
      ...data,
      orgId: req.user?.orgId || null,
      createdBy: req.user?.email || 'system',
    });

    console.log(`✅ Account created: ${account.accountName} (${account.accountCode})`);
    res.status(201).json({ success: true, message: 'Account created successfully', data: { ...account.toObject(), id: account._id } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── PUT /:id (update) ─────────────────────────────────────────────────────────
router.put('/:id', authenticate, async (req, res) => {
  try {
    const account = await ChartOfAccount.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });

    if (account.isSystemAccount) {
      // System accounts: only allow description + currency update
      const { description, currency } = req.body;
      if (description !== undefined) account.description = description;
      if (currency !== undefined) account.currency = currency;
    } else {
      const allowed = ['accountCode','accountName','accountType','accountSubType',
        'parentAccountId','parentAccountName','description','currency','isActive'];
      allowed.forEach(k => { if (req.body[k] !== undefined) account[k] = req.body[k]; });

      // Resolve parent
      if (req.body.parentAccountId) {
        const parent = await ChartOfAccount.findOne({
          _id: req.body.parentAccountId,
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        }).lean();
        if (parent) account.parentAccountName = parent.accountName;
      } else if (req.body.parentAccountId === null) {
        account.parentAccountName = null;
      }
    }

    account.updatedBy = req.user?.email || 'system';
    await account.save();

    res.json({ success: true, message: 'Account updated successfully', data: { ...account.toObject(), id: account._id } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── PATCH /:id/toggle-active ──────────────────────────────────────────────────
router.patch('/:id/toggle-active', authenticate, async (req, res) => {
  try {
    const account = await ChartOfAccount.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });
    if (account.isSystemAccount) return res.status(400).json({ success: false, message: 'Cannot deactivate system accounts' });

    account.isActive  = req.body.isActive ?? !account.isActive;
    account.updatedBy = req.user?.email || 'system';
    await account.save();

    res.json({ success: true, message: `Account ${account.isActive ? 'activated' : 'deactivated'}`, data: { ...account.toObject(), id: account._id } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── DELETE /:id ───────────────────────────────────────────────────────────────
router.delete('/:id', authenticate, async (req, res) => {
  try {
    const account = await ChartOfAccount.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });
    if (account.isSystemAccount) return res.status(400).json({ success: false, message: 'System accounts cannot be deleted' });

    const txnCount = await AccountTransaction.countDocuments({
      accountId: account._id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (txnCount > 0) return res.status(400).json({ success: false, message: `Cannot delete account with ${txnCount} transactions` });

    await account.deleteOne();
    res.json({ success: true, message: 'Account deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST /import (bulk import) ────────────────────────────────────────────────
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

router.post('/import', authenticate, upload.single('file'), async (req, res) => {
  try {
    const accountsData = JSON.parse(req.body.accounts || '[]');

    let successCount = 0;
    let failedCount  = 0;
    const errors     = [];

    for (let i = 0; i < accountsData.length; i++) {
      const item = accountsData[i];
      try {
        // Check duplicate
        const existing = await ChartOfAccount.findOne({
          accountName: { $regex: `^${item.accountName}$`, $options: 'i' },
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        });
        if (existing) {
          errors.push(`Row ${i + 2}: Account "${item.accountName}" already exists`);
          failedCount++;
          continue;
        }

        // Auto code
        if (!item.accountCode || item.accountCode.trim() === '') {
          item.accountCode = await generateAccountCode(item.accountType, req.user?.orgId);
        }

        // Resolve parent by name
        if (item.parentAccountName && item.parentAccountName.trim()) {
          const parent = await ChartOfAccount.findOne({
            accountName: { $regex: `^${item.parentAccountName}$`, $options: 'i' },
            ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
          }).lean();
          if (parent) {
            item.parentAccountId   = parent._id;
            item.parentAccountName = parent.accountName;
          }
        }

        await ChartOfAccount.create({ ...item, createdBy: req.user?.email || 'system', orgId: req.user?.orgId || null });
        successCount++;
      } catch (err) {
        errors.push(`Row ${i + 2}: ${err.message}`);
        failedCount++;
      }
    }

    res.json({
      success: true,
      message: `Imported ${successCount} accounts`,
      data: { totalProcessed: accountsData.length, successCount, failedCount, errors },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// EXPORT helper — post a journal entry to COA (used by other modules)
// ============================================================================
// Call this from manual_journal.js, bills.js, invoices.js etc.

async function postTransactionToCOA({ accountId, orgId = null, date, description, referenceType, referenceId, referenceNumber, debit = 0, credit = 0 }) {
  try {
    // Get current balance
    const lastTxn = await AccountTransaction.findOne({
      accountId,
      ...(orgId ? { orgId } : {}),
    }).sort({ date: -1, createdAt: -1 }).lean();
    const prevBalance = lastTxn ? lastTxn.balance : 0;
    const newBalance  = prevBalance + debit - credit;

    await AccountTransaction.create({
      accountId, orgId, date, description, referenceType, referenceId, referenceNumber,
      debit, credit, balance: newBalance,
    });

    // Update account closing balance
    await ChartOfAccount.findByIdAndUpdate(accountId, {
      closingBalance: Math.abs(newBalance),
      balanceType: newBalance >= 0 ? 'Dr' : 'Cr',
    });
  } catch (err) {
    console.error('COA posting error:', err.message);
  }
}

module.exports = router;
module.exports.ChartOfAccount       = ChartOfAccount;
module.exports.AccountTransaction   = AccountTransaction;
module.exports.postTransactionToCOA = postTransactionToCOA;
module.exports.seedSystemAccounts   = seedSystemAccounts;