// ============================================================================
// BANK TRANSACTIONS — CATEGORIZATION ENGINE
// ============================================================================
// File: backend/routes/bank_transactions.js
//
// This is the CORE of the banking module.
// Every imported bank transaction passes through here for categorization.
//
// Flow:
//   ProviderTransaction (UNCATEGORIZED)
//     → Rules Engine (auto-categorize)
//     → Manual Categorization (this file)
//     → postTransactionToCOA() → AccountTransaction
//     → ProviderTransaction status = CATEGORIZED
//
// Actions supported (pin-to-pin Zoho Books):
//   1. Expense          → Dr Expense COA   / Cr Bank COA
//   2. Deposit/Income   → Dr Bank COA      / Cr Income COA
//   3. Transfer         → Dr ToBank COA    / Cr FromBank COA
//   4. Match Invoice    → Dr Bank COA      / Cr Accounts Receivable
//   5. Match Bill       → Dr AP COA        / Cr Bank COA
//   6. Split            → Dr Multi-COA     / Cr Bank COA
//   7. Exclude/Ignore   → mark excluded, no COA posting
//
// Smart Multi-Match (both directions):
//   ₹1000 + ₹2000 bank txns  ↔  ₹3000 expense  (many→one)
//   ₹3000 bank txn           ↔  ₹1000 + ₹2000   (one→many)
// ============================================================================

'use strict';

const express  = require('express');
const router   = express.Router();
const mongoose = require('mongoose');

const { verifyFinanceJWT }    = require('../middleware/finance_jwt');
const { postTransactionToCOA, ChartOfAccount, AccountTransaction } = require('./chart_of_accounts');

const multer = require('multer');
const csv    = require('csv-parse/sync');
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

router.use(verifyFinanceJWT);

// ============================================================================
// RE-USE ProviderTransaction model (defined in reconciliation_billing.js)
// ============================================================================

const ProviderTransaction = mongoose.models.ProviderTransaction
  || mongoose.model('ProviderTransaction', new mongoose.Schema({}, { strict: false }), 'providertransactions');

const Expense = mongoose.models.Expense
  || mongoose.model('Expense', new mongoose.Schema({}, { strict: false }), 'expenses');

const PaymentAccount = mongoose.models.PaymentAccount
  || mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');

// ============================================================================
// HELPERS
// ============================================================================

function orgFilter(req) {
  return {
    ...req.orgFilter,
    ...(req.branchFilter || {}),
  };
}

// Find the COA account linked to a PaymentAccount by name or ID
// branchId is required for branch-level isolation — each branch has its own COA set
async function resolveBankCOA(accountId, orgId = null, branchId = null) {
  const pa = await PaymentAccount.findById(accountId).lean();
  if (!pa) throw new Error(`PaymentAccount ${accountId} not found`);

  // Build filter: prefer exact branch match, fall back to org-only if not found
  const exactFilter = {
    accountName: pa.accountName,
    ...(orgId    ? { orgId }    : {}),
    ...(branchId ? { branchId } : {}),
  };

  let coa = await ChartOfAccount.findOne(exactFilter).lean();

  // Fallback: if branch-specific COA not found, try org-level (null branchId)
  if (!coa && branchId) {
    coa = await ChartOfAccount.findOne({
      accountName: pa.accountName,
      ...(orgId ? { orgId } : {}),
    }).lean();
  }

  if (!coa) throw new Error(`COA account not found for bank: ${pa.accountName}`);
  return coa;
}

// Build a unique journal reference number — scoped to branch for clean per-branch sequences
async function nextJournalRef(orgId = null, branchId = null) {
  const filter = {
    ...(orgId    ? { orgId }    : {}),
    ...(branchId ? { branchId } : {}),
  };
  const count = await AccountTransaction.countDocuments(filter);
  const pad   = String(count + 1).padStart(5, '0');
  return `BNK-${new Date().getFullYear()}-${pad}`;
}

// Mark ProviderTransaction(s) as categorized and link journal entries
// branchId is stamped so the record stays correctly scoped after categorization
async function markCategorized(providerTxnIds, journalRef, categoryLabel, orgId = null, linkedRecordId = null, linkedRecordType = null, branchId = null) {
  // ✅ FIX: Determine cash flow section based on account type
  let cashFlowSection = 'OPERATING'; // default
  
  console.log('🔍 [markCategorized] DEBUG - categoryLabel:', categoryLabel);
  
  // Get the account type from COA using categoryLabel
  if (categoryLabel) {
    const expAcc = await ChartOfAccount.findOne({
      accountName: categoryLabel,
      ...(orgId ? { orgId } : {}),
    }).select('accountType').lean();
    
    console.log('🔍 [markCategorized] DEBUG - Found COA account:', expAcc);
    
    if (expAcc) {
      const accType = expAcc.accountType;
      console.log('🔍 [markCategorized] DEBUG - Account type:', accType);
      
      // Asset purchases → Investing Activities
      if (['Asset', 'Fixed Asset', 'Other Current Asset', 'Other Asset'].includes(accType)) {
        cashFlowSection = 'INVESTING';
        console.log('✅ [markCategorized] Cash Flow Section: INVESTING (Asset account)');
      }
      // Liability/Equity payments → Financing Activities
      else if (['Liability', 'Equity', 'Other Current Liability', 'Non Current Liability', 'Other Liability'].includes(accType)) {
        cashFlowSection = 'FINANCING';
        console.log('✅ [markCategorized] Cash Flow Section: FINANCING (Liability/Equity account)');
      }
      // Expense/Income/COGS → Operating Activities (default)
      else {
        cashFlowSection = 'OPERATING';
        console.log('✅ [markCategorized] Cash Flow Section: OPERATING (Expense/Income/COGS account)');
      }
    } else {
      console.log('⚠️ [markCategorized] COA account not found for categoryLabel:', categoryLabel);
    }
  }
  
  console.log('🔍 [markCategorized] Final cashFlowSection:', cashFlowSection);
  
  await ProviderTransaction.updateMany(
    { _id: { $in: providerTxnIds } },
    {
      $set: {
        reconciliationStatus: 'CATEGORIZED',
        categorizedAt:        new Date(),
        categorizedBy:        'user',
        journalRef,
        categoryLabel,
        orgId,
        branchId,
        linkedRecordId,
        linkedRecordType,
        cashFlowSection,      // ✅ FIX: Add cash flow section
      },
    },
  );
  
  console.log(`✅ [markCategorized] Updated ${providerTxnIds.length} ProviderTransaction(s) with cashFlowSection: ${cashFlowSection}`);
}

// ============================================================================
// ROUTE 1 — GET /uncategorized
// Returns all uncategorized transactions for an account
// ============================================================================
router.get('/uncategorized', async (req, res) => {
  try {
    const { accountId, startDate, endDate, page = 1, limit = 50 } = req.query;

    if (!accountId) {
      return res.status(400).json({ success: false, message: 'accountId is required' });
    }

    const filter = {
      accountId: mongoose.Types.ObjectId.isValid(accountId)
        ? { $in: [new mongoose.Types.ObjectId(accountId), accountId] }
        : accountId,
      reconciliationStatus: { $in: ['UNMATCHED', 'UNCATEGORIZED'] },
      isExcluded: { $ne: true },
      ...orgFilter(req),
    };

    if (startDate) filter.transactionDate = { ...filter.transactionDate, $gte: new Date(startDate) };
    if (endDate)   filter.transactionDate = { ...filter.transactionDate, $lte: new Date(endDate) };

    const total = await ProviderTransaction.countDocuments(filter);
    const txns  = await ProviderTransaction.find(filter)
      .sort({ transactionDate: -1 })
      .skip((parseInt(page) - 1) * parseInt(limit))
      .limit(parseInt(limit))
      .lean();

    res.json({
      success: true,
      total,
      page:       parseInt(page),
      totalPages: Math.ceil(total / parseInt(limit)),
      data:       txns,
    });
  } catch (err) {
    console.error('❌ uncategorized fetch error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 1b — GET /stats/:accountId
// Returns counts + currentBalance for the account detail page header
// ============================================================================
router.get('/stats/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const orgF = orgFilter(req);
    const accountObjId = mongoose.Types.ObjectId.isValid(accountId)
      ? new mongoose.Types.ObjectId(accountId) : accountId;

    const [uncategorized, categorized, account] = await Promise.all([
      ProviderTransaction.countDocuments({
        accountId: accountObjId,
        reconciliationStatus: { $in: ['UNMATCHED', 'UNCATEGORIZED'] },
        isExcluded: { $ne: true }, ...orgF,
      }),
      ProviderTransaction.countDocuments({
        accountId: accountObjId,
        reconciliationStatus: 'CATEGORIZED', ...orgF,
      }),
      PaymentAccount.findById(accountId).lean(),
    ]);

    let bankCOABalance = 0;
    try {
      const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
      const bankCOA  = await resolveBankCOA(accountId, req.user?.orgId, branchId);
      // Compute branch-scoped closing balance from AccountTransaction aggregation
      const balAgg = await AccountTransaction.aggregate([
        { $match: {
          accountId: bankCOA._id,
          ...req.orgFilter,
          ...(branchId ? { branchId } : {}),
        }},
        { $group: { _id: null, totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
      ]);
      bankCOABalance = (balAgg[0]?.totalDebit || 0) - (balAgg[0]?.totalCredit || 0);
    } catch (_) {}

    res.json({
      success: true,
      data: {
        uncategorized,
        categorized,
        total: uncategorized + categorized,
        currentBalance: account?.currentBalance ?? 0,
        bankCOABalance,
        openingBalance: account?.openingBalance ?? 0,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 1c — GET /all-transactions
// Returns all ProviderTransactions for the All Transactions tab
// ============================================================================
router.get('/all-transactions', async (req, res) => {
  try {
    const { accountId, page = 1, limit = 50 } = req.query;
    if (!accountId) return res.status(400).json({ success: false, message: 'accountId is required' });

    const accountObjId = mongoose.Types.ObjectId.isValid(accountId)
      ? new mongoose.Types.ObjectId(accountId) : accountId;

    const PaymentAccount = mongoose.models.PaymentAccount || mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const account = await PaymentAccount.findById(accountObjId).lean();
    let openingBalance = account?.openingBalance || 0;

    const filter = { 
      accountId: accountObjId, 
      isExcluded: { $ne: true }, 
      reconciliationStatus: { $in: ['CATEGORIZED', 'RECONCILED', 'MATCHED'] },
      ...orgFilter(req) 
    };

    // Fetch all matched transactions sorted from oldest to newest to compute running balance
    const allTxns = await ProviderTransaction.find(filter)
      .sort({ transactionDate: 1, categorizedAt: 1, _id: 1 })
      .lean();

    const total = allTxns.length;
    
    // Calculate accurate running balance across all pages
    let currentRun = openingBalance;
    allTxns.forEach(t => {
      const amt = parseFloat(t.amount) || 0;
      currentRun += (t.transactionType === 'DEBIT') ? -amt : amt;
      t.computedRunningBalance = currentRun;
    });

    // Sort them descending (newest first) for UI
    allTxns.reverse();

    // Apply pagination slice
    const startIndex = (parseInt(page) - 1) * parseInt(limit);
    const endIndex = startIndex + parseInt(limit);
    const paginatedTxns = allTxns.slice(startIndex, endIndex);

    res.json({ success: true, total, data: paginatedTxns });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 1d — GET /by-category-label
// Returns ProviderTransactions for a specific categoryLabel (P&L drill-down)
// ============================================================================
router.get('/by-category-label', async (req, res) => {
  try {
    const { categoryLabel, startDate, endDate } = req.query;
    if (!categoryLabel) return res.status(400).json({ success: false, message: 'categoryLabel is required' });

    const coa = await ChartOfAccount.findOne({ accountName: categoryLabel, ...orgFilter(req) }).lean();
    if (!coa) {
      return res.json({ success: true, total: 0, totalAmount: 0, data: [] });
    }

    const filter = {
      accountId: coa._id,
      ...orgFilter(req),
    };

    if (startDate || endDate) {
      filter.date = {};
      if (startDate) {
        filter.date.$gte = new Date(startDate.split('T')[0] + 'T00:00:00.000Z');
      }
      if (endDate) {
        filter.date.$lte = new Date(endDate.split('T')[0] + 'T23:59:59.999Z');
      }
    }

    const txns = await AccountTransaction.find(filter).sort({ date: -1 }).lean();

    // Deep lookups for Payee and Bank Account
    const Expense = mongoose.models.Expense || mongoose.model('Expense', new mongoose.Schema({}, { strict: false }), 'expenses');
    const Bill = mongoose.models.Bill || mongoose.model('Bill', new mongoose.Schema({}, { strict: false }), 'bills');

    const expIds = txns.filter(t => t.referenceType === 'Expense').map(t => t.referenceId);
    const billIds = txns.filter(t => t.referenceType === 'Bill').map(t => t.referenceId);
    const provTxnIds = txns.filter(t => t.referenceType === 'ProviderTransaction').map(t => t.referenceId);

    const [expenses, bills, provTxns] = await Promise.all([
      expIds.length ? Expense.find({ _id: { $in: expIds } }).lean() : [],
      billIds.length ? Bill.find({ _id: { $in: billIds } }).lean() : [],
      provTxnIds.length ? ProviderTransaction.find({ _id: { $in: provTxnIds } }).lean() : [],
    ]);

    const expMap = {}; expenses.forEach(e => { expMap[e._id.toString()] = e; });
    const billMap = {}; bills.forEach(b => { billMap[b._id.toString()] = b; });
    const provTxnMap = {}; provTxns.forEach(p => { provTxnMap[p._id.toString()] = p; });

    // Fetch bank account names if we only have IDs
    const bankIdsToFetch = new Set();
    provTxns.forEach(p => { if (p.accountId) bankIdsToFetch.add(p.accountId.toString()); });
    
    let accMap = {};
    if (bankIdsToFetch.size > 0) {
      const accounts = await PaymentAccount.find({ _id: { $in: Array.from(bankIdsToFetch) } }).lean();
      accounts.forEach(a => { accMap[a._id.toString()] = a.accountName; });
    }

    const enriched = txns.map(t => {
      let payee = '—';
      let bankAccount = '—';
      let desc = t.description || '';
      
      // Attempt to extract from description first
      if (desc.includes('|')) {
        const parts = desc.split('|');
        payee = parts[1].trim();
        desc = parts[0].trim();
      }

      if (t.referenceType === 'Expense') {
        const exp = expMap[t.referenceId?.toString()];
        if (exp) {
          if (exp.vendor) payee = exp.vendor;
          if (exp.paidThrough) bankAccount = exp.paidThrough;
        }
      } else if (t.referenceType === 'Bill') {
        const bill = billMap[t.referenceId?.toString()];
        if (bill) {
          if (bill.vendorName) payee = bill.vendorName;
          // Bills are usually Accrued, so bank account is Accounts Payable initially
        }
      } else if (t.referenceType === 'ProviderTransaction') {
        const prov = provTxnMap[t.referenceId?.toString()];
        if (prov) {
          if (prov.payee || prov.vendorName || prov.customerName) payee = prov.payee || prov.vendorName || prov.customerName;
          if (prov.accountId) bankAccount = accMap[prov.accountId.toString()] || prov.accountId.toString();
        }
      }

      const amount = (t.debit || 0) + (t.credit || 0);

      return {
        date:             t.date,
        bankAccount:      bankAccount,
        description:      desc,
        payee:            payee,
        referenceNumber:  t.referenceNumber || '',
        type:             t.debit > 0 ? 'Withdrawal' : 'Deposit',
        amount:           amount,
      };
    });

    const total = enriched.reduce((s, t) => s + (t.amount || 0), 0);

    res.json({ success: true, total: txns.length, totalAmount: total, data: enriched });
  } catch (err) {
    console.error('by-category-label error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});


// ============================================================================
// ROUTE 2 — GET /ledger
// Returns all transactions (ledger/passbook view) for an account
// ============================================================================
router.get('/ledger', async (req, res) => {
  try {
    const { accountId, startDate, endDate, page = 1, limit = 100 } = req.query;
    if (!accountId) return res.status(400).json({ success: false, message: 'accountId is required' });

    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const bankCOA  = await resolveBankCOA(accountId, req.user?.orgId, branchId);
    const filter   = { accountId: bankCOA._id, ...orgFilter(req) };
    if (startDate) filter.date = { ...filter.date, $gte: new Date(startDate) };
    if (endDate)   filter.date = { ...filter.date, $lte: new Date(endDate) };

    const total = await AccountTransaction.countDocuments(filter);
    const txns  = await AccountTransaction.find(filter)
      .sort({ date: -1, createdAt: -1 })
      .skip((parseInt(page) - 1) * parseInt(limit))
      .limit(parseInt(limit))
      .lean();

    // Compute branch-scoped closing balance
    const balAgg = await AccountTransaction.aggregate([
      { $match: {
        accountId: bankCOA._id,
        ...req.orgFilter,
        ...(branchId ? { branchId } : {}),
      }},
      { $group: { _id: null, totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
    ]);
    const branchClosingBalance = (balAgg[0]?.totalDebit || 0) - (balAgg[0]?.totalCredit || 0);

    res.json({
      success:         true,
      total,
      page:            parseInt(page),
      totalPages:      Math.ceil(total / parseInt(limit)),
      currentBalance:  branchClosingBalance,
      data:            txns,
    });
  } catch (err) {
    console.error('❌ ledger fetch error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 3 — GET /coa-options
// Returns COA accounts filtered by context (expense / income / bank / all)
// This powers the dropdown in categorization dialogs
// ============================================================================
router.get('/coa-options', async (req, res) => {
  try {
    const { context } = req.query;
    // context: 'expense' | 'income' | 'bank' | 'all'

    const contextMap = {
      expense: ['Expense', 'Cost Of Goods Sold', 'Other Expense'],
      income:  ['Income', 'Other Income'],
      bank:    ['Other Current Asset', 'Cash', 'Fixed Asset', 'Other Asset'],
      all:     null, // no filter
    };

    const types = contextMap[context] ?? null;
    const filter = {
      isActive: true,
      ...orgFilter(req),
      ...(types ? { accountType: { $in: types } } : {}),
    };

    const accounts = await ChartOfAccount.find(filter)
      .sort({ accountType: 1, accountName: 1 })
      .lean();

    res.json({
      success: true,
      data:    accounts.map(a => ({
        id:          a._id,
        accountCode: a.accountCode,
        accountName: a.accountName,
        accountType: a.accountType,
      })),
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 3b — GET /resolve-category-coa
// Resolves the COA account for a simple category type.
// Returns the account if found, or a 404 with suggested name+type to create.
// Used by the frontend to check before categorizing — if missing, prompt user
// to create the account via NewChartOfAccountScreen.
// ============================================================================
const CATEGORY_COA_MAP = {
  // Money IN
  interest_income:       { name: 'Interest Income',      type: 'Income',   subType: 'Other Income' },
  other_income:          { name: 'Other Income',          type: 'Income',   subType: 'Other Income' },
  expense_refund:        { name: 'Other Income',          type: 'Income',   subType: 'Other Income' },
  owner_contribution:    { name: "Owner's Contribution",  type: 'Equity',   subType: 'Equity' },
  vendor_credit_refund:  { name: 'Accounts Payable',      type: 'Liability',subType: 'Accounts Payable' },
  vendor_payment_refund: { name: 'Accounts Payable',      type: 'Liability',subType: 'Accounts Payable' },
  // Money OUT
  owner_drawings:        { name: "Owner's Drawings",      type: 'Equity',   subType: 'Equity' },
  credit_note_refund:    { name: 'Accounts Receivable',   type: 'Asset',    subType: 'Accounts Receivable' },
  payment_refund:        { name: 'Accounts Receivable',   type: 'Asset',    subType: 'Accounts Receivable' },
};

router.get('/resolve-category-coa', async (req, res) => {
  try {
    const { categoryType } = req.query;
    const mapping = CATEGORY_COA_MAP[categoryType];
    if (!mapping) {
      return res.json({ success: true, found: true, account: null }); // not a mapped category
    }

    const account = await ChartOfAccount.findOne({
      accountName: { $regex: new RegExp(`^${mapping.name}$`, 'i') },
      isActive: true,
      ...req.orgFilter,
      ...(req.branchIds?.length > 0 ? { branchId: req.branchIds[0] } : {}),
    }).lean();

    if (account) {
      return res.json({
        success: true,
        found:   true,
        account: { id: account._id, accountName: account.accountName, accountType: account.accountType },
      });
    }

    // Not found — return suggested details so frontend can pre-fill the create form
    return res.json({
      success:         true,
      found:           false,
      suggestedName:   mapping.name,
      suggestedType:   mapping.type,
      suggestedSubType: mapping.subType,
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 4 — GET /smart-match-suggestions
// Finds potential multi-transaction matches (both directions)
// ₹1000+₹2000  ↔  ₹3000
// ============================================================================
router.get('/smart-match-suggestions', async (req, res) => {
  try {
    const { accountId, startDate, endDate } = req.query;

    const AMOUNT_TOLERANCE = 50;   // ₹50
    const DATE_TOLERANCE   = 3;    // days

    // Get all uncategorized provider transactions
    const providerTxns = await ProviderTransaction.find({
      accountId,
      reconciliationStatus: { $in: ['UNMATCHED', 'UNCATEGORIZED'] },
      ...orgFilter(req),
      ...(startDate ? { transactionDate: { $gte: new Date(startDate) } } : {}),
      ...(endDate   ? { transactionDate: { $lte: new Date(endDate) }   } : {}),
    }).lean();

    // Get all uncategorized system expenses for this account
    const pa       = await PaymentAccount.findById(accountId).lean();
    const expenses = await Expense.find({
      $or: [
        { paidThrough: accountId },
        { paidThrough: pa?.accountName },
      ],
      providerTransactionId: { $exists: false },
      ...orgFilter(req),
    }).lean();

    const suggestions = [];

    // ── Direction 1: Many bank txns → One expense ────────────────────────────
    // Group bank transactions by date window and check if sum ≈ expense amount
    for (const expense of expenses) {
      const expDate   = new Date(expense.date);
      const expAmount = expense.total || 0;

      // Find bank txns within date window
      const nearby = providerTxns.filter(t => {
        const diff = Math.abs((new Date(t.transactionDate) - expDate) / 86400000);
        return diff <= DATE_TOLERANCE && t.transactionType === 'DEBIT';
      });

      // Try all subset combos (up to 4 transactions to avoid explosion)
      const subsets = getSubsets(nearby.slice(0, 8));
      for (const subset of subsets) {
        if (subset.length < 2) continue;
        const subsetSum = subset.reduce((s, t) => s + t.amount, 0);
        if (Math.abs(subsetSum - expAmount) <= AMOUNT_TOLERANCE) {
          suggestions.push({
            type:              'many_to_one',
            bankTransactions:  subset.map(t => t._id),
            bankTotal:         subsetSum,
            systemRecord:      expense._id,
            systemAmount:      expAmount,
            difference:        Math.abs(subsetSum - expAmount),
            confidence:        difference_to_confidence(Math.abs(subsetSum - expAmount), expAmount),
          });
          break;
        }
      }
    }

    // ── Direction 2: One bank txn → Many expenses ────────────────────────────
    for (const txn of providerTxns) {
      if (txn.transactionType !== 'DEBIT') continue;
      const txnDate   = new Date(txn.transactionDate);
      const txnAmount = txn.amount;

      const nearby = expenses.filter(e => {
        const diff = Math.abs((new Date(e.date) - txnDate) / 86400000);
        return diff <= DATE_TOLERANCE;
      });

      const subsets = getSubsets(nearby.slice(0, 8));
      for (const subset of subsets) {
        if (subset.length < 2) continue;
        const subsetSum = subset.reduce((s, e) => s + (e.total || 0), 0);
        if (Math.abs(subsetSum - txnAmount) <= AMOUNT_TOLERANCE) {
          suggestions.push({
            type:             'one_to_many',
            bankTransactions: [txn._id],
            bankTotal:        txnAmount,
            systemRecords:    subset.map(e => e._id),
            systemAmount:     subsetSum,
            difference:       Math.abs(subsetSum - txnAmount),
            confidence:       difference_to_confidence(Math.abs(subsetSum - txnAmount), txnAmount),
          });
          break;
        }
      }
    }

    res.json({ success: true, count: suggestions.length, data: suggestions });
  } catch (err) {
    console.error('❌ smart-match error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

function getSubsets(arr) {
  const result = [[]];
  for (const item of arr) {
    const len = result.length;
    for (let i = 0; i < len; i++) {
      result.push([...result[i], item]);
    }
  }
  return result.filter(s => s.length > 0);
}

function difference_to_confidence(diff, total) {
  if (total === 0) return 0;
  const pct = diff / total;
  if (pct === 0)    return 100;
  if (pct < 0.01)   return 95;
  if (pct < 0.05)   return 85;
  if (pct < 0.10)   return 70;
  return 50;
}

// ============================================================================
// ROUTE 5 — POST /categorize/expense
// Categorize a bank debit as an expense
// Dr Expense COA / Cr Bank COA
// ============================================================================
router.post('/categorize/expense', async (req, res) => {
  try {
    const {
      providerTransactionId,
      coaAccountId,     // Expense COA account
      vendorId,
      vendorName,
      date,
      amount,
      notes,
      taxRate,
      taxAmount,
    } = req.body;

    if (!providerTransactionId || !coaAccountId) {
      return res.status(400).json({ success: false, message: 'providerTransactionId and coaAccountId are required' });
    }

    const txn = await ProviderTransaction.findOne({
      _id: providerTransactionId,
      ...orgFilter(req),
    });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    const txnAmount  = amount || txn.amount;
    const txnDate    = new Date(date || txn.transactionDate);
    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);

    // Resolve bank COA — branch-scoped
    const bankCOA    = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);
    const expenseCOA = await ChartOfAccount.findById(coaAccountId).lean();
    if (!expenseCOA) return res.status(404).json({ success: false, message: 'Expense COA account not found' });

    const description = `${expenseCOA.accountName}${vendorName ? ' - ' + vendorName : ''} | ${journalRef}`;

    // ── DOUBLE ENTRY ──────────────────────────────────────────────────────────
    // Dr Expense Account
    await postTransactionToCOA({
      accountId:       expenseCOA._id,
      orgId:           req.user?.orgId || null,
      branchId,
      date:            txnDate,
      description,
      referenceType:   'Expense',
      referenceId:     txn._id,
      referenceNumber: journalRef,
      debit:           txnAmount,
      credit:          0,
    });

    // Cr Bank Account
    await postTransactionToCOA({
      accountId:       bankCOA._id,
      orgId:           req.user?.orgId || null,
      branchId,
      date:            txnDate,
      description,
      referenceType:   'Expense',
      referenceId:     txn._id,
      referenceNumber: journalRef,
      debit:           0,
      credit:          txnAmount,
    });

    // ── Update bank account current balance ───────────────────────────────────
    await PaymentAccount.findByIdAndUpdate(txn.accountId, {
      $inc: { currentBalance: -txnAmount },
    });

    // ── Save expense record ───────────────────────────────────────────────────
    const expense = await Expense.create({
      orgId:                   req.user?.orgId || null,
      branchId,
      expenseNumber:           journalRef,
      date:                    txnDate.toISOString().split('T')[0],
      expenseAccount:          expenseCOA.accountName,
      expenseAccountId:        expenseCOA._id,
      paidThrough:             bankCOA.accountName,
      paidThroughAccountId:    bankCOA._id,
      vendor:                  vendorName || null,
      vendorId:                vendorId   || null,
      amount:                  txnAmount,
      total:                   txnAmount,
      tax:                     taxAmount  || 0,
      taxRate:                 taxRate    || 0,
      notes:                   notes      || txn.description || '',
      providerTransactionId:   txn._id,
      journalRef,
      createdBy:               req.user?.email || 'system',
    });

    // ── Mark provider transaction as categorized ──────────────────────────────
    await markCategorized([txn._id], journalRef, expenseCOA.accountName, req.user?.orgId, expense._id, 'Expense', branchId);

    console.log(`✅ Expense categorized: ${journalRef} ₹${txnAmount} → ${expenseCOA.accountName}`);

    res.json({
      success: true,
      message: 'Transaction categorized as expense',
      data: { journalRef, expense, bankBalance: bankCOA.closingBalance - txnAmount },
    });
  } catch (err) {
    console.error('❌ categorize/expense error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 6 — POST /categorize/deposit
// Categorize a bank credit as income/deposit
// Dr Bank COA / Cr Income COA
// ============================================================================
router.post('/categorize/deposit', async (req, res) => {
  try {
    const {
      providerTransactionId,
      coaAccountId,     // Income COA account (optional if categoryType is provided)
      categoryType,     // e.g. 'interest_income', 'owner_contribution' etc.
      customerId,
      customerName,
      date,
      amount,
      notes,
    } = req.body;

    if (!providerTransactionId) {
      return res.status(400).json({ success: false, message: 'providerTransactionId is required' });
    }

    const txn = await ProviderTransaction.findOne({
      _id: providerTransactionId,
      ...orgFilter(req),
    });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    // Resolve COA account — prefer explicit coaAccountId, else map from categoryType
    let incomeCOA = null;
    if (coaAccountId) {
      incomeCOA = await ChartOfAccount.findById(coaAccountId).lean();
    } else if (categoryType && CATEGORY_COA_MAP[categoryType]) {
      const mapping = CATEGORY_COA_MAP[categoryType];
      incomeCOA = await ChartOfAccount.findOne({
        accountName: { $regex: new RegExp(`^${mapping.name}$`, 'i') },
        isActive: true,
        ...req.orgFilter,
        ...(req.branchIds?.length > 0 ? { branchId: req.branchIds[0] } : {}),
      }).lean();
      // If still not found, return a specific error so frontend can prompt creation
      if (!incomeCOA) {
        return res.status(422).json({
          success:          false,
          code:             'COA_ACCOUNT_MISSING',
          message:          `Account "${mapping.name}" not found. Please create it first.`,
          suggestedName:    mapping.name,
          suggestedType:    mapping.type,
          suggestedSubType: mapping.subType,
        });
      }
    }

    if (!incomeCOA) {
      return res.status(400).json({ success: false, message: 'coaAccountId or categoryType is required' });
    }

    const txnAmount  = amount || txn.amount;
    const txnDate    = new Date(date || txn.transactionDate);
    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);

    const bankCOA = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);

    const description = `${incomeCOA.accountName}${customerName ? ' - ' + customerName : ''} | ${journalRef}`;

    // ── DOUBLE ENTRY ──────────────────────────────────────────────────────────
    // Dr Bank Account
    await postTransactionToCOA({
      accountId:       bankCOA._id,
      orgId:           req.user?.orgId || null,
      branchId,
      date:            txnDate,
      description,
      referenceType:   'Payment',
      referenceId:     txn._id,
      referenceNumber: journalRef,
      debit:           txnAmount,
      credit:          0,
    });

    // Cr Income/Equity/Liability Account
    await postTransactionToCOA({
      accountId:       incomeCOA._id,
      orgId:           req.user?.orgId || null,
      branchId,
      date:            txnDate,
      description,
      referenceType:   'Payment',
      referenceId:     txn._id,
      referenceNumber: journalRef,
      debit:           0,
      credit:          txnAmount,
    });

    await PaymentAccount.findByIdAndUpdate(txn.accountId, {
      $inc: { currentBalance: txnAmount },
    });

    await markCategorized([txn._id], journalRef, incomeCOA.accountName, req.user?.orgId, null, null, branchId);

    console.log(`✅ Deposit categorized: ${journalRef} ₹${txnAmount} → ${incomeCOA.accountName}`);

    res.json({
      success: true,
      message: 'Transaction categorized as deposit/income',
      data:    { journalRef },
    });
  } catch (err) {
    console.error('❌ categorize/deposit error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 7 — POST /categorize/transfer
// Transfer between two bank accounts
// Dr ToBank COA / Cr FromBank COA
// ============================================================================
router.post('/categorize/transfer', async (req, res) => {
  try {
    const {
      providerTransactionId,
      toAccountId,   // destination PaymentAccount ID
      date,
      amount,
      notes,
    } = req.body;

    if (!providerTransactionId || !toAccountId) {
      return res.status(400).json({ success: false, message: 'providerTransactionId and toAccountId are required' });
    }

    const txn = await ProviderTransaction.findOne({
      _id: providerTransactionId,
      ...orgFilter(req),
    });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    const txnAmount  = amount || txn.amount;
    const txnDate    = new Date(date || txn.transactionDate);
    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);

    const fromCOA = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);
    const toCOA   = await resolveBankCOA(toAccountId, req.user?.orgId, branchId);

    const description = `Transfer: ${fromCOA.accountName} → ${toCOA.accountName} | ${journalRef}`;

    // ── DOUBLE ENTRY ──────────────────────────────────────────────────────────
    // Dr To Account (money arrives)
    await postTransactionToCOA({
      accountId:       toCOA._id,
      orgId:           req.user?.orgId || null,
      branchId,
      date:            txnDate,
      description,
      referenceType:   'Journal',
      referenceId:     txn._id,
      referenceNumber: journalRef,
      debit:           txnAmount,
      credit:          0,
    });

    // Cr From Account (money leaves)
    await postTransactionToCOA({
      accountId:       fromCOA._id,
      orgId:           req.user?.orgId || null,
      branchId,
      date:            txnDate,
      description,
      referenceType:   'Journal',
      referenceId:     txn._id,
      referenceNumber: journalRef,
      debit:           0,
      credit:          txnAmount,
    });

    // ── Update both PaymentAccount balances ───────────────────────────────────
    await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: -txnAmount } });
    await PaymentAccount.findByIdAndUpdate(toAccountId,   { $inc: { currentBalance:  txnAmount } });

    await markCategorized([txn._id], journalRef, `Transfer → ${toCOA.accountName}`, req.user?.orgId, null, null, branchId);

    console.log(`✅ Transfer: ${journalRef} ₹${txnAmount} ${fromCOA.accountName} → ${toCOA.accountName}`);

    res.json({
      success: true,
      message: 'Transfer recorded successfully',
      data:    { journalRef, from: fromCOA.accountName, to: toCOA.accountName, amount: txnAmount },
    });
  } catch (err) {
    console.error('❌ categorize/transfer error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 8 — POST /categorize/split
// Split one bank transaction across multiple COA accounts
// Dr COA-1 ₹X / Dr COA-2 ₹Y / Cr Bank COA ₹(X+Y)
// ============================================================================
router.post('/categorize/split', async (req, res) => {
  try {
    const {
      providerTransactionId,
      splits, // [{ coaAccountId, amount, vendorName, notes }]
      date,
    } = req.body;

    if (!providerTransactionId || !splits || splits.length < 2) {
      return res.status(400).json({ success: false, message: 'providerTransactionId and at least 2 splits are required' });
    }

    const txn = await ProviderTransaction.findOne({
      _id: providerTransactionId,
      ...orgFilter(req),
    });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    const txnDate    = new Date(date || txn.transactionDate);
    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);
    const bankCOA    = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);

    // Validate split amounts sum to transaction amount
    const splitsTotal = splits.reduce((s, sp) => s + parseFloat(sp.amount), 0);
    if (Math.abs(splitsTotal - txn.amount) > 0.01) {
      return res.status(400).json({
        success: false,
        message: `Split amounts (₹${splitsTotal}) must equal transaction amount (₹${txn.amount})`,
      });
    }

    const splitDetails = [];

    for (const split of splits) {
      const splitCOA = await ChartOfAccount.findById(split.coaAccountId).lean();
      if (!splitCOA) continue;

      const description = `${splitCOA.accountName}${split.vendorName ? ' - ' + split.vendorName : ''} [Split] | ${journalRef}`;

      // Dr each split COA account
      await postTransactionToCOA({
        accountId:       splitCOA._id,
        orgId:           req.user?.orgId || null,
        branchId,
        date:            txnDate,
        description,
        referenceType:   'Expense',
        referenceId:     txn._id,
        referenceNumber: journalRef,
        debit:           parseFloat(split.amount),
        credit:          0,
      });

      // Save individual expense record for each split
      await Expense.create({
        orgId:                 req.user?.orgId || null,
        branchId,
        expenseNumber:         `${journalRef}-${splitDetails.length + 1}`,
        date:                  txnDate.toISOString().split('T')[0],
        expenseAccount:        splitCOA.accountName,
        expenseAccountId:      splitCOA._id,
        paidThrough:           bankCOA.accountName,
        paidThroughAccountId:  bankCOA._id,
        vendor:                split.vendorName || null,
        amount:                parseFloat(split.amount),
        total:                 parseFloat(split.amount),
        notes:                 split.notes || '',
        providerTransactionId: txn._id,
        journalRef,
        isSplit:               true,
        createdBy:             req.user?.email || 'system',
      });

      splitDetails.push({ account: splitCOA.accountName, amount: split.amount });
    }

    // Cr Bank Account (once for total)
    await postTransactionToCOA({
      accountId:       bankCOA._id,
      orgId:           req.user?.orgId || null,
      branchId,
      date:            txnDate,
      description:     `Split transaction | ${journalRef}`,
      referenceType:   'Expense',
      referenceId:     txn._id,
      referenceNumber: journalRef,
      debit:           0,
      credit:          txn.amount,
    });

    await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: -txn.amount } });

    await markCategorized([txn._id], journalRef, 'Split', req.user?.orgId, null, null, branchId);

    console.log(`✅ Split transaction: ${journalRef} ₹${txn.amount} → ${splits.length} splits`);

    res.json({
      success: true,
      message: `Transaction split into ${splits.length} categories`,
      data:    { journalRef, splits: splitDetails },
    });
  } catch (err) {
    console.error('❌ categorize/split error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 9 — POST /categorize/match-invoice
// Match bank credit to an existing invoice payment
// Dr Bank COA / Cr Accounts Receivable
// ============================================================================
router.post('/categorize/match-invoice', async (req, res) => {
  try {
    const { providerTransactionId, invoiceId, date, amount } = req.body;

    if (!providerTransactionId || !invoiceId) {
      return res.status(400).json({ success: false, message: 'providerTransactionId and invoiceId are required' });
    }

    const txn = await ProviderTransaction.findOne({ _id: providerTransactionId, ...orgFilter(req) });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    const Invoice = mongoose.models.Invoice
      || mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');
    const invoice = await Invoice.findById(invoiceId);
    if (!invoice) return res.status(404).json({ success: false, message: 'Invoice not found' });

    const txnAmount  = amount || txn.amount;
    const txnDate    = new Date(date || txn.transactionDate);
    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);

    const bankCOA = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);
    const arCOA   = await ChartOfAccount.findOne({
      accountName:     'Accounts Receivable',
      isSystemAccount: true,
      ...orgFilter(req),
    }).lean();
    if (!arCOA) return res.status(400).json({ success: false, message: 'Accounts Receivable COA account not found. Please seed system accounts.' });

    const description = `Payment for Invoice ${invoice.invoiceNumber} - ${invoice.customerName} | ${journalRef}`;

    // Dr Bank (money arrives)
    await postTransactionToCOA({
      accountId: bankCOA._id, orgId: req.user?.orgId || null,
      branchId,
      date: txnDate, description,
      referenceType: 'Payment', referenceId: txn._id, referenceNumber: journalRef,
      debit: txnAmount, credit: 0,
    });

    // Cr Accounts Receivable (clears the AR)
    await postTransactionToCOA({
      accountId: arCOA._id, orgId: req.user?.orgId || null,
      branchId,
      date: txnDate, description,
      referenceType: 'Payment', referenceId: txn._id, referenceNumber: journalRef,
      debit: 0, credit: txnAmount,
    });

    // Mark invoice as paid (partial or full)
    const newBalance = (invoice.balanceDue || invoice.totalAmount) - txnAmount;
    await Invoice.findByIdAndUpdate(invoiceId, {
      balanceDue: Math.max(0, newBalance),
      paymentStatus: newBalance <= 0 ? 'paid' : 'partial',
      lastPaymentDate: txnDate,
    });

    await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: txnAmount } });
    await markCategorized([txn._id], journalRef, `Invoice: ${invoice.invoiceNumber}`, req.user?.orgId, invoice._id, 'Invoice', branchId);

    console.log(`✅ Invoice payment matched: ${journalRef} Invoice ${invoice.invoiceNumber} ₹${txnAmount}`);

    res.json({
      success: true,
      message: `Matched to Invoice ${invoice.invoiceNumber}`,
      data:    { journalRef, invoice: invoice.invoiceNumber, amount: txnAmount },
    });
  } catch (err) {
    console.error('❌ match-invoice error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 10 — POST /categorize/match-bill
// Match bank debit to an existing bill payment
// Dr Accounts Payable / Cr Bank COA
// ============================================================================
router.post('/categorize/match-bill', async (req, res) => {
  try {
    const { providerTransactionId, billId, date, amount } = req.body;

    if (!providerTransactionId || !billId) {
      return res.status(400).json({ success: false, message: 'providerTransactionId and billId are required' });
    }

    const txn = await ProviderTransaction.findOne({ _id: providerTransactionId, ...orgFilter(req) });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    const Bill = mongoose.models.Bill
      || mongoose.model('Bill', new mongoose.Schema({}, { strict: false }), 'bills');
    const bill = await Bill.findById(billId);
    if (!bill) return res.status(404).json({ success: false, message: 'Bill not found' });

    const txnAmount  = amount || txn.amount;
    const txnDate    = new Date(date || txn.transactionDate);
    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);

    const bankCOA = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);
    const apCOA   = await ChartOfAccount.findOne({
      accountName: 'Accounts Payable', isSystemAccount: true, ...orgFilter(req),
    }).lean();
    if (!apCOA) return res.status(400).json({ success: false, message: 'Accounts Payable COA not found. Please seed system accounts.' });

    const description = `Payment for Bill ${bill.billNumber} - ${bill.vendorName || bill.vendor} | ${journalRef}`;

    // Dr Accounts Payable (clears the AP)
    await postTransactionToCOA({
      accountId: apCOA._id, orgId: req.user?.orgId || null,
      branchId,
      date: txnDate, description,
      referenceType: 'Bill', referenceId: txn._id, referenceNumber: journalRef,
      debit: txnAmount, credit: 0,
    });

    // Cr Bank (money leaves)
    await postTransactionToCOA({
      accountId: bankCOA._id, orgId: req.user?.orgId || null,
      branchId,
      date: txnDate, description,
      referenceType: 'Bill', referenceId: txn._id, referenceNumber: journalRef,
      debit: 0, credit: txnAmount,
    });

    // Mark bill as paid
    const newBalance = (bill.balanceDue || bill.totalAmount) - txnAmount;
    await Bill.findByIdAndUpdate(billId, {
      balanceDue:     Math.max(0, newBalance),
      paymentStatus:  newBalance <= 0 ? 'paid' : 'partial',
      lastPaymentDate: txnDate,
    });

    await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: -txnAmount } });
    await markCategorized([txn._id], journalRef, `Bill: ${bill.billNumber}`, req.user?.orgId, bill._id, 'Bill', branchId);

    res.json({
      success: true,
      message: `Matched to Bill ${bill.billNumber}`,
      data:    { journalRef, bill: bill.billNumber, amount: txnAmount },
    });
  } catch (err) {
    console.error('❌ match-bill error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 11 — POST /categorize/exclude
// Exclude a transaction (non-business, personal, etc.)
// No COA posting
// ============================================================================
router.post('/categorize/exclude', async (req, res) => {
  try {
    const { providerTransactionId, reason } = req.body;

    await ProviderTransaction.findOneAndUpdate(
      { _id: providerTransactionId, ...orgFilter(req) },
      {
        $set: {
          isExcluded:           true,
          excludedAt:           new Date(),
          excludedReason:       reason || 'Excluded by user',
          reconciliationStatus: 'EXCLUDED',
        },
      },
    );

    res.json({ success: true, message: 'Transaction excluded' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 12 — POST /categorize/undo
// Undo a categorization — reverses COA entries and resets status
// ============================================================================
router.post('/categorize/undo', async (req, res) => {
  try {
    const { providerTransactionId } = req.body;

    const txn = await ProviderTransaction.findOne({ _id: providerTransactionId, ...orgFilter(req) });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    if (!txn.journalRef) {
      return res.status(400).json({ success: false, message: 'Transaction has no journal reference to reverse' });
    }

    // Delete the COA entries created by this categorization
    // Match by journalRef + orgId + branchId (from the transaction itself, as a plain string).
    // Do NOT use req.branchFilter here — it uses $in which won't match the stored plain string.
    const orgId = req.user?.orgId || null;
    const txnBranchId = txn.branchId || null;
    const coaDeleteFilter = {
      referenceNumber: txn.journalRef,
      ...(orgId ? { orgId } : {}),
      ...(txnBranchId ? { branchId: txnBranchId } : {}),
    };
    const coaEntries = await AccountTransaction.find(coaDeleteFilter);
    const affectedCOAIds = new Set(coaEntries.map(e => e.accountId.toString()));

    await AccountTransaction.deleteMany(coaDeleteFilter);

    // Delete the linked record if it was created
    await deleteLinkedRecord(txn, req);

    // Recompute closingBalance for all affected COA accounts from scratch — branch-scoped
    for (const coaId of affectedCOAIds) {
      await recomputeClosingBalance(coaId, req.user?.orgId, txnBranchId);
    }

    // Reverse PaymentAccount balance
    if (txn.transactionType === 'DEBIT') {
      await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: txn.amount } });
    } else {
      await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: -txn.amount } });
    }

    // Reset the provider transaction
    await ProviderTransaction.findByIdAndUpdate(txn._id, {
      $set: {
        reconciliationStatus: 'UNMATCHED',
        categorizedAt:        null,
        categorizedBy:        null,
        journalRef:           null,
        categoryLabel:        null,
        isExcluded:           false,
        excludedAt:           null,
      },
    });

    res.json({ success: true, message: 'Categorization reversed successfully' });
  } catch (err) {
    console.error('❌ undo error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 13 — POST /manual-entry
// Create a manual transaction (not from import)
// Same double-entry logic but user provides all details
// ============================================================================
router.post('/manual-entry', async (req, res) => {
  try {
    const {
      accountId,        // PaymentAccount ID
      type,             // 'expense' | 'deposit' | 'transfer'
      coaAccountId,     // For expense/deposit
      toAccountId,      // For transfer
      date,
      amount,
      vendorName,
      customerName,
      notes,
      taxRate,
      taxAmount,
    } = req.body;

    if (!accountId || !type || !amount || !date) {
      return res.status(400).json({ success: false, message: 'accountId, type, amount, date are required' });
    }

    // Generate a fake ProviderTransaction for manual entries
    // so it flows through the same categorization pipeline
    const manualTxn = await ProviderTransaction.create({
      accountId,
      transactionDate:      new Date(date),
      amount:               parseFloat(amount),
      description:          notes || `Manual ${type}`,
      transactionType:      type === 'deposit' ? 'CREDIT' : 'DEBIT',
      reconciliationStatus: 'UNMATCHED',
      importBatchId:        `MANUAL-${Date.now()}`,
      importedAt:           new Date(),
      importedBy:           req.user?.email || 'system',
      orgId:                req.user?.orgId || null,
      branchId:             req.branchIds?.length > 0 ? req.branchIds[0] : null,
      isManualEntry:        true,
    });

    // Now call the appropriate categorization route internally
    req.body.providerTransactionId = manualTxn._id.toString();

    let result;
    if (type === 'expense') {
      result = await categorizeExpenseInternal(req, manualTxn);
    } else if (type === 'deposit') {
      result = await categorizeDepositInternal(req, manualTxn);
    } else if (type === 'transfer') {
      result = await categorizeTransferInternal(req, manualTxn);
    } else {
      return res.status(400).json({ success: false, message: 'Invalid type. Use expense | deposit | transfer' });
    }

    res.json({ success: true, message: `Manual ${type} recorded`, data: result });
  } catch (err) {
    console.error('❌ manual-entry error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// Internal helpers reused by manual-entry
async function categorizeExpenseInternal(req, txn) {
  const { coaAccountId, vendorName, date, amount, notes, taxRate, taxAmount } = req.body;
  const txnAmount  = amount || txn.amount;
  const txnDate    = new Date(date || txn.transactionDate);
  const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
  const journalRef = await nextJournalRef(req.user?.orgId, branchId);
  const bankCOA    = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);
  const expCOA     = await ChartOfAccount.findById(coaAccountId).lean();

  const desc = `${expCOA.accountName}${vendorName ? ' - ' + vendorName : ''} | ${journalRef}`;

  await postTransactionToCOA({ accountId: expCOA._id, orgId: req.user?.orgId || null, branchId, date: txnDate, description: desc, referenceType: 'Expense', referenceId: txn._id, referenceNumber: journalRef, debit: txnAmount, credit: 0 });
  await postTransactionToCOA({ accountId: bankCOA._id, orgId: req.user?.orgId || null, branchId, date: txnDate, description: desc, referenceType: 'Expense', referenceId: txn._id, referenceNumber: journalRef, debit: 0, credit: txnAmount });
  await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: -txnAmount } });

  await Expense.create({ orgId: req.user?.orgId || null, branchId, expenseNumber: journalRef, date: txnDate.toISOString().split('T')[0], expenseAccount: expCOA.accountName, expenseAccountId: expCOA._id, paidThrough: bankCOA.accountName, paidThroughAccountId: bankCOA._id, vendor: vendorName || null, amount: txnAmount, total: txnAmount, tax: taxAmount || 0, taxRate: taxRate || 0, notes: notes || '', providerTransactionId: txn._id, journalRef, createdBy: req.user?.email || 'system' });
  await markCategorized([txn._id], journalRef, expCOA.accountName, req.user?.orgId, null, null, branchId);
  return { journalRef };
}

async function categorizeDepositInternal(req, txn) {
  const { coaAccountId, customerName, date, amount, notes } = req.body;
  const txnAmount  = amount || txn.amount;
  const txnDate    = new Date(date || txn.transactionDate);
  const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
  const journalRef = await nextJournalRef(req.user?.orgId, branchId);
  const bankCOA    = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);
  const incCOA     = await ChartOfAccount.findById(coaAccountId).lean();

  const desc = `${incCOA.accountName}${customerName ? ' - ' + customerName : ''} | ${journalRef}`;

  await postTransactionToCOA({ accountId: bankCOA._id, orgId: req.user?.orgId || null, branchId, date: txnDate, description: desc, referenceType: 'Payment', referenceId: txn._id, referenceNumber: journalRef, debit: txnAmount, credit: 0 });
  await postTransactionToCOA({ accountId: incCOA._id, orgId: req.user?.orgId || null, branchId, date: txnDate, description: desc, referenceType: 'Payment', referenceId: txn._id, referenceNumber: journalRef, debit: 0, credit: txnAmount });
  await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: txnAmount } });
  await markCategorized([txn._id], journalRef, incCOA.accountName, req.user?.orgId, null, null, branchId);
  return { journalRef };
}

async function categorizeTransferInternal(req, txn) {
  const { toAccountId, date, amount } = req.body;
  const txnAmount  = amount || txn.amount;
  const txnDate    = new Date(date || txn.transactionDate);
  const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
  const journalRef = await nextJournalRef(req.user?.orgId, branchId);
  const fromCOA    = await resolveBankCOA(txn.accountId.toString(), req.user?.orgId, branchId);
  const toCOA      = await resolveBankCOA(toAccountId, req.user?.orgId, branchId);

  const desc = `Transfer: ${fromCOA.accountName} → ${toCOA.accountName} | ${journalRef}`;

  await postTransactionToCOA({ accountId: toCOA._id, orgId: req.user?.orgId || null, branchId, date: txnDate, description: desc, referenceType: 'Journal', referenceId: txn._id, referenceNumber: journalRef, debit: txnAmount, credit: 0 });
  await postTransactionToCOA({ accountId: fromCOA._id, orgId: req.user?.orgId || null, branchId, date: txnDate, description: desc, referenceType: 'Journal', referenceId: txn._id, referenceNumber: journalRef, debit: 0, credit: txnAmount });
  await PaymentAccount.findByIdAndUpdate(txn.accountId, { $inc: { currentBalance: -txnAmount } });
  await PaymentAccount.findByIdAndUpdate(toAccountId, { $inc: { currentBalance: txnAmount } });
  await markCategorized([txn._id], journalRef, `Transfer → ${toCOA.accountName}`, req.user?.orgId, null, null, branchId);
  return { journalRef };
}

// ============================================================================
// ROUTE 14 — GET /open-invoices
// Returns open invoices for matching (amount/customer filter)
// ============================================================================
router.get('/open-invoices', async (req, res) => {
  try {
    const { amount, customerId, tolerance = 50 } = req.query;

    const Invoice = mongoose.models.Invoice
      || mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');

    const filter = {
      paymentStatus: { $in: ['unpaid', 'partial', 'overdue'] },
      ...orgFilter(req),
    };

    if (customerId) filter.customerId = customerId;
    if (amount) {
      const amt = parseFloat(amount);
      filter.balanceDue = { $gte: amt - parseFloat(tolerance), $lte: amt + parseFloat(tolerance) };
    }

    const invoices = await Invoice.find(filter)
      .sort({ invoiceDate: -1 })
      .limit(20)
      .lean();

    res.json({ success: true, data: invoices });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 15 — GET /open-bills
// Returns open bills for matching
// ============================================================================
router.get('/open-bills', async (req, res) => {
  try {
    const { amount, vendorId, tolerance = 50 } = req.query;

    const Bill = mongoose.models.Bill
      || mongoose.model('Bill', new mongoose.Schema({}, { strict: false }), 'bills');

    const filter = {
      paymentStatus: { $in: ['unpaid', 'partial', 'overdue'] },
      ...orgFilter(req),
    };

    if (vendorId) filter.vendorId = vendorId;
    if (amount) {
      const amt = parseFloat(amount);
      filter.balanceDue = { $gte: amt - parseFloat(tolerance), $lte: amt + parseFloat(tolerance) };
    }

    const bills = await Bill.find(filter)
      .sort({ billDate: -1 })
      .limit(20)
      .lean();

    res.json({ success: true, data: bills });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 16 — GET /stats/:accountId
// Returns categorization stats for the account detail page header
// ============================================================================
router.get('/stats/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const filter = {
      accountId: mongoose.Types.ObjectId.isValid(accountId)
        ? { $in: [new mongoose.Types.ObjectId(accountId), accountId] }
        : accountId,
      ...orgFilter(req),
    };

    const [total, uncategorized, categorized, excluded] = await Promise.all([
      ProviderTransaction.countDocuments(filter),
      ProviderTransaction.countDocuments({ ...filter, reconciliationStatus: { $in: ['UNMATCHED', 'UNCATEGORIZED'] }, isExcluded: { $ne: true } }),
      ProviderTransaction.countDocuments({ ...filter, reconciliationStatus: 'CATEGORIZED' }),
      ProviderTransaction.countDocuments({ ...filter, isExcluded: true }),
    ]);

    const bankCOA  = await resolveBankCOA(accountId, req.user?.orgId, req.branchIds?.length > 0 ? req.branchIds[0] : null).catch(() => null);

    // Compute branch-scoped closing balance
    let branchBalance = 0;
    if (bankCOA) {
      const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
      const balAgg = await AccountTransaction.aggregate([
        { $match: {
          accountId: bankCOA._id,
          ...req.orgFilter,
          ...(branchId ? { branchId } : {}),
        }},
        { $group: { _id: null, totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
      ]);
      branchBalance = (balAgg[0]?.totalDebit || 0) - (balAgg[0]?.totalCredit || 0);
    }

    res.json({
      success: true,
      data: {
        total,
        uncategorized,
        categorized,
        excluded,
        currentBalance: branchBalance,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 17 — POST /import
// Import bank statement CSV → saves as ProviderTransactions (UNCATEGORIZED)
// ============================================================================
router.post('/import', upload.single('file'), async (req, res) => {
  try {
    const { accountId } = req.body;
    if (!accountId) {
      return res.status(400).json({ success: false, message: 'accountId is required' });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No file uploaded' });
    }

    const account = await PaymentAccount.findOne({
      _id: accountId,
      ...orgFilter(req),
    }).lean();
    if (!account) {
      return res.status(404).json({ success: false, message: 'Account not found' });
    }

    let records;
    try {
      records = csv.parse(req.file.buffer.toString('utf8'), {
        columns:          true,
        skip_empty_lines: true,
        trim:             true,
      });
    } catch (parseErr) {
      return res.status(400).json({ success: false, message: `CSV parse error: ${parseErr.message}` });
    }

    const importBatchId = `IMPORT-${Date.now()}-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;
    const results = { imported: 0, errors: 0, skipped: 0, errorDetails: [] };

    for (let i = 0; i < records.length; i++) {
      const row    = records[i];
      const rowNum = i + 2;
      try {
        const rawDate       = row['Date']             || row['date']             || '';
        const description   = row['Description']      || row['description']      || '';
        const payee         = row['Payee']            || row['payee']            || row['Payee Name'] || row['Vendor'] || row['Customer'] || '';
        const referenceNum  = row['Reference Number'] || row['reference_number'] || row['Reference'] || '';
        const depositStr    = row['Deposit']          || row['deposit']          || row['Credit']    || '';
        const withdrawalStr = row['Withdrawal']       || row['withdrawal']       || row['Debit']     || '';
        const balanceStr    = row['Balance']          || row['balance']          || '';

        if (!rawDate) {
          results.errors++;
          results.errorDetails.push({ row: rowNum, error: 'Missing Date' });
          continue;
        }

        let parsedDate;
        if (rawDate.includes('/')) {
          const [day, month, year] = rawDate.split('/');
          parsedDate = new Date(`${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`);
        } else {
          parsedDate = new Date(rawDate);
        }
        if (isNaN(parsedDate.getTime())) {
          results.errors++;
          results.errorDetails.push({ row: rowNum, error: `Invalid date: ${rawDate}` });
          continue;
        }

        const deposit    = parseFloat(depositStr.replace(/,/g, ''))    || 0;
        const withdrawal = parseFloat(withdrawalStr.replace(/,/g, '')) || 0;
        const balance    = parseFloat(balanceStr.replace(/,/g, ''))    || 0;

        if (deposit === 0 && withdrawal === 0) {
          results.errors++;
          results.errorDetails.push({ row: rowNum, error: 'Both Deposit and Withdrawal are empty or zero' });
          continue;
        }

        const isCredit = deposit > 0;
        const amount   = isCredit ? deposit : withdrawal;
        const txnType  = isCredit ? 'CREDIT' : 'DEBIT';

        // Build duplicate check — only include referenceNumber if it's non-empty
        const accountObjId = mongoose.Types.ObjectId.isValid(accountId)
          ? new mongoose.Types.ObjectId(accountId)
          : accountId;

        const dupFilter = {
          accountId: accountObjId,
          transactionDate: parsedDate,
          amount,
          transactionType: txnType,
          ...orgFilter(req),
        };
        if (referenceNum) dupFilter.referenceNumber = referenceNum;

        const existing = await ProviderTransaction.findOne(dupFilter).lean();

        if (existing) {
          console.log(`⏭️  Row ${rowNum}: Duplicate skipped (${parsedDate.toISOString().split('T')[0]} ₹${amount})`);
          results.skipped++;
          continue;
        }

        await ProviderTransaction.create({
          accountId: accountObjId,
          orgId:                req.user?.orgId || null,
          branchId:             req.branchIds?.length > 0 ? req.branchIds[0] : null,
          transactionDate:      parsedDate,
          description:          description || (isCredit ? 'Credit' : 'Debit'),
          payee:                payee || null,
          referenceNumber:      referenceNum || null,
          amount,
          transactionType:      txnType,
          balance:              balance || null,
          reconciliationStatus: 'UNCATEGORIZED',
          importBatchId,
          importedAt:           new Date(),
          importedBy:           req.user?.email || 'system',
          source:               'CSV_IMPORT',
        });
        results.imported++;
      } catch (rowErr) {
        console.error(`❌ Row ${rowNum} error:`, rowErr);
        results.errors++;
        results.errorDetails.push({ row: rowNum, error: rowErr.message });
      }
    }

    try {
      const TransactionRulesRouter = require('./transaction_rules');
      if (typeof TransactionRulesRouter.applyRulesToAccount === 'function') {
        await TransactionRulesRouter.applyRulesToAccount(accountId, req.user?.orgId);
        console.log(`✅ Rules applied after import for account ${accountId}`);
      }
    } catch (rulesErr) {
      console.warn('⚠️ Rules engine skipped:', rulesErr.message);
    }

    console.log(`✅ Import complete: ${results.imported} imported, ${results.skipped} skipped (duplicates), ${results.errors} failed (batch: ${importBatchId})`);
    res.json({
      success: results.imported > 0 || (results.errors === 0 && results.skipped === 0),
      message: results.skipped > 0 && results.imported === 0
        ? `All ${results.skipped} transaction(s) already exist — no new transactions imported.`
        : `Import complete. ${results.imported} transactions imported, ${results.skipped} skipped (duplicates), ${results.errors} failed.`,
      data: {
        imported:     results.imported,
        skipped:      results.skipped,
        errors:       results.errors,
        errorDetails: results.errorDetails,
        importBatchId,
      },
    });
  } catch (err) {
    console.error('❌ Import error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 18 — GET /possible-matches
// Returns possible system records matching a bank transaction amount
// ============================================================================
router.get('/possible-matches', async (req, res) => {
  try {
    const { accountId, amount, txnType, txnDate, tolerance = 100 } = req.query;
    if (!amount) {
      return res.status(400).json({ success: false, message: 'amount is required' });
    }

    const amt        = parseFloat(amount);
    const toleranceN = parseFloat(tolerance);
    const txnDateObj = txnDate ? new Date(txnDate) : new Date();
    const dateDelta  = 30;
    const startDate  = new Date(txnDateObj); startDate.setDate(startDate.getDate() - dateDelta);
    const endDate    = new Date(txnDateObj); endDate.setDate(endDate.getDate() + dateDelta);

    const amountFilter = { $gte: amt - toleranceN, $lte: amt + toleranceN };
    const matches = [];

    if (!txnType || txnType === 'CREDIT') {
      const Invoice = mongoose.models.Invoice
        || mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');
      const invoices = await Invoice.find({
        paymentStatus: { $in: ['unpaid', 'partial', 'overdue'] },
        $or: [{ balanceDue: amountFilter }, { totalAmount: amountFilter }, { total: amountFilter }],
        invoiceDate: { $gte: startDate, $lte: endDate },
        ...orgFilter(req),
      }).limit(10).lean();
      matches.push(...invoices.map(inv => ({
        ...inv,
        type:   'Invoice',
        amount: inv.balanceDue || inv.total || inv.totalAmount || 0,
      })));
    }

    if (!txnType || txnType === 'DEBIT') {
      const Bill = mongoose.models.Bill
        || mongoose.model('Bill', new mongoose.Schema({}, { strict: false }), 'bills');
      const bills = await Bill.find({
        paymentStatus: { $in: ['unpaid', 'partial', 'overdue'] },
        $or: [{ balanceDue: amountFilter }, { totalAmount: amountFilter }, { total: amountFilter }],
        billDate: { $gte: startDate, $lte: endDate },
        ...orgFilter(req),
      }).limit(10).lean();
      matches.push(...bills.map(bill => ({
        ...bill,
        type:   'Bill',
        amount: bill.balanceDue || bill.total || bill.totalAmount || 0,
      })));
    }

    const expenses = await Expense.find({
      providerTransactionId: { $exists: false },
      $or: [{ total: amountFilter }, { amount: amountFilter }],
      date: { $gte: startDate.toISOString().split('T')[0], $lte: endDate.toISOString().split('T')[0] },
      ...orgFilter(req),
    }).limit(10).lean();
    matches.push(...expenses.map(exp => ({
      ...exp,
      type:   'Expense',
      amount: exp.total || exp.amount || 0,
    })));

    matches.sort((a, b) => Math.abs(a.amount - amt) - Math.abs(b.amount - amt));
    res.json({ success: true, count: matches.length, data: matches });
  } catch (err) {
    console.error('❌ possible-matches error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 19 — GET /all-transactions
// Returns ALL transactions (categorized + uncategorized) for an account
// ============================================================================
router.get('/all-transactions', async (req, res) => {
  try {
    const { accountId, page = 1, limit = 100 } = req.query;
    if (!accountId) {
      return res.status(400).json({ success: false, message: 'accountId is required' });
    }

    const filter = {
      accountId: mongoose.Types.ObjectId.isValid(accountId)
        ? { $in: [new mongoose.Types.ObjectId(accountId), accountId] }
        : accountId,
      ...orgFilter(req),
    };
    const total  = await ProviderTransaction.countDocuments(filter);
    const txns   = await ProviderTransaction.find(filter)
      .sort({ transactionDate: -1 })
      .skip((parseInt(page) - 1) * parseInt(limit))
      .limit(parseInt(limit))
      .lean();

    res.json({
      success:    true,
      total,
      page:       parseInt(page),
      totalPages: Math.ceil(total / parseInt(limit)),
      data:       txns,
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 20 — GET /depositable-transactions
// Returns system transactions available for Record Deposit
// ============================================================================
router.get('/depositable-transactions', async (req, res) => {
  try {
    const { receivedFrom } = req.query;
    const PaymentReceived = mongoose.models.PaymentReceived
      || mongoose.model('PaymentReceived',
          new mongoose.Schema({}, { strict: false }),
          'payments_received');

    const filter = {
      isUndeposited: true,
      $or: [
        { depositedToAccountId: { $exists: false } },
        { depositedToAccountId: null }
      ],
      ...orgFilter(req),
    };

    if (receivedFrom && receivedFrom !== 'All') {
      filter.customerName = { $regex: receivedFrom, $options: 'i' };
    }

    const payments = await PaymentReceived.find(filter)
      .sort({ paymentDate: -1 })
      .limit(50)
      .lean();

    res.json({
      success: true,
      data: payments.map(p => ({
        _id:          p._id,
        type:         'Payment',
        description:  `Payment ${p.paymentNumber}`,
        date:         p.paymentDate,
        customerName: p.customerName,
        amount:       p.amountReceived || 0,
      })),
    });
  } catch (err) {
    console.error('❌ depositable-transactions error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 21 — POST /record-deposit
// Records a deposit from system transactions into a bank account
// ============================================================================
router.post('/record-deposit', async (req, res) => {
  try {
    const { accountId, depositDate, paidVia, reference, description, transactionIds, otherDeposits } = req.body;
    if (!accountId) {
      return res.status(400).json({ success: false, message: 'accountId is required' });
    }

    const txnDate    = new Date(depositDate || Date.now());
    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);
    const bankCOA    = await resolveBankCOA(accountId, req.user?.orgId, branchId);
    let totalDeposit = 0;

    if (transactionIds && transactionIds.length > 0) {
      const PaymentReceived = mongoose.models.PaymentReceived
        || mongoose.model('PaymentReceived',
            new mongoose.Schema({}, { strict: false }),
            'payments_received');
      for (const pmtId of transactionIds) {
        const pmt = await PaymentReceived.findById(pmtId).lean();
        if (!pmt) continue;
        const amt  = pmt.amountReceived || 0;
        const desc = `Deposit: Payment ${pmt.paymentNumber} - ${pmt.customerName} | ${journalRef}`;
        await postTransactionToCOA({
          accountId:       bankCOA._id,
          orgId: req.user?.orgId || null,
          branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
          date:            txnDate,
          description:     desc,
          referenceType:   'Deposit',
          referenceId:     pmt._id,
          referenceNumber: journalRef,
          debit:           amt,
          credit:          0,
        });

        // ✅ FIX — Cr Undeposited Funds (clears it to zero)
        const undepositedCOA = await ChartOfAccount.findOne({
          accountName: 'Undeposited Funds',
          ...req.orgFilter,
        }).lean();

        if (undepositedCOA) {
          await postTransactionToCOA({
            accountId:       undepositedCOA._id,
            orgId: req.user?.orgId || null,
            branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
            date:            txnDate,
            description:     desc,
            referenceType:   'Deposit',
            referenceId:     pmt._id,
            referenceNumber: journalRef,
            debit:           0,
            credit:          amt,  // ← clears Undeposited Funds
          });
        }

        await PaymentReceived.findByIdAndUpdate(pmtId, {
          depositedToAccountId: accountId,
          depositedAt:          txnDate,
        });
        totalDeposit += amt;

        // ── Create ProviderTransaction so it appears in All Transactions tab ──
        try {
          await ProviderTransaction.create({
            accountId:            mongoose.Types.ObjectId.isValid(accountId)
                                    ? new mongoose.Types.ObjectId(accountId)
                                    : accountId,
            orgId:                req.user?.orgId || null,
            branchId:             req.branchIds?.length > 0 ? req.branchIds[0] : null,
            transactionDate:      txnDate,
            description:          `Deposit: Payment ${pmt.paymentNumber} - ${pmt.customerName}`,
            amount:               amt,
            transactionType:      'CREDIT',
            reconciliationStatus: 'CATEGORIZED',
            categoryLabel:        'Deposit',
            source:               'RECORD_DEPOSIT',
            linkedRecordId:       pmt._id,
            linkedRecordType:     'PaymentReceived',
            journalRef:           journalRef,
            categorizedAt:        new Date(),
            categorizedBy:        req.user?.email || 'system',
            importedAt:           new Date(),
            importedBy:           req.user?.email || 'system',
          });
          console.log(`✅ ProviderTransaction created for deposit: Payment ${pmt.paymentNumber}`);
        } catch (ptErr) {
          console.error('⚠️ ProviderTransaction create error (deposit):', ptErr.message);
        }
      }
    }

    if (otherDeposits && otherDeposits.length > 0) {
      for (const dep of otherDeposits) {
        const amt  = parseFloat(dep.amount) || 0;
        const desc = dep.description || 'Other Deposit';
        await postTransactionToCOA({
          accountId:       bankCOA._id,
          orgId: req.user?.orgId || null,
          branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
          date:            txnDate,
          description:     `${desc} | ${journalRef}`,
          referenceType:   'Deposit',
          referenceNumber: journalRef,
          debit:           amt,
          credit:          0,
        });
        totalDeposit += amt;

        // ── Create ProviderTransaction for other deposit ──────────────────────
        try {
          await ProviderTransaction.create({
            accountId:            mongoose.Types.ObjectId.isValid(accountId)
                                    ? new mongoose.Types.ObjectId(accountId)
                                    : accountId,
            orgId:                req.user?.orgId || null,
            branchId:             req.branchIds?.length > 0 ? req.branchIds[0] : null,
            transactionDate:      txnDate,
            description:          dep.description || 'Other Deposit',
            amount:               amt,
            transactionType:      'CREDIT',
            reconciliationStatus: 'CATEGORIZED',
            categoryLabel:        'Deposit',
            source:               'RECORD_DEPOSIT',
            journalRef:           journalRef,
            categorizedAt:        new Date(),
            categorizedBy:        req.user?.email || 'system',
            importedAt:           new Date(),
            importedBy:           req.user?.email || 'system',
          });
          console.log(`✅ ProviderTransaction created for other deposit: ${dep.description}`);
        } catch (ptErr) {
          console.error('⚠️ ProviderTransaction create error (other deposit):', ptErr.message);
        }
      }
    }

    if (totalDeposit === 0) {
      return res.status(400).json({ success: false, message: 'No deposit amount' });
    }

    await PaymentAccount.findByIdAndUpdate(accountId, { $inc: { currentBalance: totalDeposit } });
    res.json({
      success: true,
      message: `Deposit of ₹${totalDeposit} recorded`,
      data:    { journalRef, amount: totalDeposit },
    });
  } catch (err) {
    console.error('❌ record-deposit error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// ROUTE 22 — POST /match-record
// Generic match — for records that aren't invoice or bill
// ============================================================================
router.post('/match-record', async (req, res) => {
  try {
    const { providerTransactionId, recordId, recordType } = req.body;
    const txn = await ProviderTransaction.findOne({
      _id: providerTransactionId,
      ...orgFilter(req),
    });
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    const branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const journalRef = await nextJournalRef(req.user?.orgId, branchId);
    await markCategorized([txn._id], journalRef, recordType, req.user?.orgId, recordId, recordType, branchId);
    res.json({ success: true, message: `Matched to ${recordType}`, data: { journalRef } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

router.post('/mark-categorized', async (req, res) => {
  try {
    const { providerTransactionId, categoryLabel, linkedRecordId, linkedRecordType, journalRef } = req.body;
    if (!providerTransactionId) {
      return res.status(400).json({ success: false, message: 'providerTransactionId required' });
    }
    // Cast linkedRecordId to ObjectId so deleteLinkedRecord can find it later
    const linkedRecordObjId = linkedRecordId && mongoose.Types.ObjectId.isValid(linkedRecordId)
      ? new mongoose.Types.ObjectId(linkedRecordId)
      : null;
    await ProviderTransaction.findOneAndUpdate(
      { _id: providerTransactionId, ...orgFilter(req) },
      {
        $set: {
          reconciliationStatus: 'CATEGORIZED',
          categorizedAt:        new Date(),
          categorizedBy:        'user',
          categoryLabel:        categoryLabel || 'Manual',
          linkedRecordId:       linkedRecordObjId,
          linkedRecordType:     linkedRecordType || null,
          journalRef:           journalRef || null,
        },
      }
    );
    res.json({ success: true, message: 'Transaction marked as categorized' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ROUTE 24 — DELETE /delete-transaction/:id
router.delete('/delete-transaction/:id', async (req, res) => {
  try {
    const txn = await ProviderTransaction.findOne({
      _id: req.params.id, ...orgFilter(req)
    });
    if (!txn) return res.status(404).json({ success: false, message: 'Not found' });

    if (txn.reconciliationStatus === 'CATEGORIZED' && txn.journalRef) {
      const entries = await AccountTransaction.find({
        referenceNumber: txn.journalRef, ...orgFilter(req)
      });
      for (const entry of entries) {
        await ChartOfAccount.findByIdAndUpdate(entry.accountId, {
          $inc: { closingBalance: -(entry.debit - entry.credit) }
        });
      }
      await AccountTransaction.deleteMany({
        referenceNumber: txn.journalRef, ...orgFilter(req)
      });
      await deleteLinkedRecord(txn, req);
      if (txn.transactionType === 'DEBIT') {
        await PaymentAccount.findByIdAndUpdate(txn.accountId,
          { $inc: { currentBalance: txn.amount } });
      } else {
        await PaymentAccount.findByIdAndUpdate(txn.accountId,
          { $inc: { currentBalance: -txn.amount } });
      }
    }

    await ProviderTransaction.findByIdAndDelete(txn._id);
    res.json({ success: true, message: 'Transaction deleted and all entries reversed' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ROUTE 25 — PUT /edit-transaction/:id
router.put('/edit-transaction/:id', async (req, res) => {
  try {
    const { date, description, amount, referenceNumber } = req.body;
    const txn = await ProviderTransaction.findOne({
      _id: req.params.id, ...orgFilter(req)
    });
    if (!txn) return res.status(404).json({ success: false, message: 'Not found' });

    if (txn.reconciliationStatus === 'CATEGORIZED' && txn.journalRef) {
      const oldEntries = await AccountTransaction.find({
        referenceNumber: txn.journalRef, ...orgFilter(req)
      });
      for (const entry of oldEntries) {
        await ChartOfAccount.findByIdAndUpdate(entry.accountId, {
          $inc: { closingBalance: -(entry.debit - entry.credit) }
        });
      }
      await AccountTransaction.deleteMany({
        referenceNumber: txn.journalRef, ...orgFilter(req)
      });

      const newAmount = parseFloat(amount) || txn.amount;
      const newDate   = date ? new Date(date) : txn.transactionDate;
      const orgId     = req.user?.orgId || null;
      const branchId  = txn.branchId || (req.branchIds?.length > 0 ? req.branchIds[0] : null);

      // ── Handle Expense type ───────────────────────────────────────────────
      if (!txn.linkedRecordType || txn.linkedRecordType === 'Expense') {
        const expRecord = await Expense.findOne({ providerTransactionId: txn._id }).lean();
        if (expRecord) {
          await Expense.findByIdAndUpdate(expRecord._id, {
            $set: { amount: newAmount, total: newAmount, date: newDate.toISOString().split('T')[0] }
          });
          const bankCOA = await resolveBankCOA(txn.accountId.toString(), orgId, branchId);
          const expCOA  = expRecord.expenseAccountId
            ? await ChartOfAccount.findById(expRecord.expenseAccountId).lean()
            : await ChartOfAccount.findOne({ accountName: expRecord.expenseAccount, ...(orgId ? { orgId } : {}), ...(branchId ? { branchId } : {}) }).lean();

          if (expCOA) {
            await postTransactionToCOA({
              accountId: expCOA._id, orgId, branchId,
              date: newDate, description: description || txn.description,
              referenceType: 'Expense', referenceId: txn._id,
              referenceNumber: txn.journalRef, debit: newAmount, credit: 0,
            });
          }
          await postTransactionToCOA({
            accountId: bankCOA._id, orgId, branchId,
            date: newDate, description: description || txn.description,
            referenceType: 'Expense', referenceId: txn._id,
            referenceNumber: txn.journalRef, debit: 0, credit: newAmount,
          });
        }
      }

      // ── Handle PaymentMade type ───────────────────────────────────────────
      else if (txn.linkedRecordType === 'PaymentMade') {
        const PaymentMade = mongoose.models.PaymentMade
          || mongoose.model('PaymentMade', new mongoose.Schema({}, { strict: false }), 'payments_made');
        const pmRecord = await PaymentMade.findOne({ providerTransactionId: txn._id }).lean();
        if (pmRecord) {
          const oldAmt = pmRecord.amount || pmRecord.amountPaid || 0;
          const diff   = newAmount - oldAmt;

          await PaymentMade.findByIdAndUpdate(pmRecord._id, {
            $set: { amount: newAmount, amountPaid: newAmount, paymentDate: newDate }
          });

          const apCOA = await ChartOfAccount.findOne({
            accountName: 'Accounts Payable',
            ...(orgId    ? { orgId }    : {}),
            ...(branchId ? { branchId } : {}),
          }).lean();
          const bankCOA = await resolveBankCOA(txn.accountId.toString(), orgId, branchId);

          if (apCOA) {
            await postTransactionToCOA({
              accountId: apCOA._id, orgId, branchId,
              date: newDate, description: description || txn.description,
              referenceType: 'Bill', referenceId: txn._id,
              referenceNumber: txn.journalRef, debit: newAmount, credit: 0,
            });
          }
          await postTransactionToCOA({
            accountId: bankCOA._id, orgId, branchId,
            date: newDate, description: description || txn.description,
            referenceType: 'Bill', referenceId: txn._id,
            referenceNumber: txn.journalRef, debit: 0, credit: newAmount,
          });

          if (diff !== 0) {
            const paidFrom = pmRecord.paidFromAccount || pmRecord.paidThroughAccount || pmRecord.paidThrough;
            if (paidFrom) {
              if (mongoose.Types.ObjectId.isValid(paidFrom)) {
                await PaymentAccount.findByIdAndUpdate(paidFrom, { $inc: { currentBalance: -diff } });
              } else {
                await PaymentAccount.findOneAndUpdate({ accountName: paidFrom }, { $inc: { currentBalance: -diff } });
              }
            }
          }
        }
      }

      // ── Handle PaymentReceived type ───────────────────────────────────────
      else if (txn.linkedRecordType === 'PaymentReceived') {
        const PaymentReceived = mongoose.models.PaymentReceived
          || mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'payments_received');
        const prRecord = await PaymentReceived.findOne({ providerTransactionId: txn._id }).lean();
        if (prRecord) {
          const oldAmt = prRecord.amountReceived || prRecord.amount || 0;
          const diff   = newAmount - oldAmt;

          await PaymentReceived.findByIdAndUpdate(prRecord._id, {
            $set: { amountReceived: newAmount, amount: newAmount, paymentDate: newDate }
          });

          const arCOA   = await ChartOfAccount.findOne({
            accountName: 'Accounts Receivable',
            ...(orgId    ? { orgId }    : {}),
            ...(branchId ? { branchId } : {}),
          }).lean();
          const bankCOA = await resolveBankCOA(txn.accountId.toString(), orgId, branchId);

          await postTransactionToCOA({
            accountId: bankCOA._id, orgId, branchId,
            date: newDate, description: description || txn.description,
            referenceType: 'Payment', referenceId: txn._id,
            referenceNumber: txn.journalRef, debit: newAmount, credit: 0,
          });
          if (arCOA) {
            await postTransactionToCOA({
              accountId: arCOA._id, orgId, branchId,
              date: newDate, description: description || txn.description,
              referenceType: 'Payment', referenceId: txn._id,
              referenceNumber: txn.journalRef, debit: 0, credit: newAmount,
            });
          }

          if (diff !== 0) {
            try {
              const Invoice = mongoose.models.Invoice
                || mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');
              const invoicePayments = prRecord.invoicePayments || {};
              const invoiceCount    = Object.keys(invoicePayments).length;

              for (const [invoiceId, allocatedAmt] of Object.entries(invoicePayments)) {
                if (!mongoose.Types.ObjectId.isValid(invoiceId)) continue;
                const invoice = await Invoice.findById(invoiceId).lean();
                if (!invoice) continue;

                const adjustAmt = invoiceCount === 1
                  ? diff
                  : (parseFloat(allocatedAmt) / oldAmt) * diff;

                const newAmountPaid = Math.max(0, (invoice.amountPaid || 0) + adjustAmt);
                const newAmountDue  = Math.max(0, (invoice.totalAmount || 0) - newAmountPaid);

                let newStatus;
                if (newAmountPaid <= 0)                          newStatus = 'UNPAID';
                else if (newAmountPaid > 0 && newAmountDue > 0)  newStatus = 'PARTIALLY_PAID';
                else                                             newStatus = 'PAID';

                await Invoice.findByIdAndUpdate(invoiceId, {
                  amountPaid: newAmountPaid,
                  amountDue:  newAmountDue,
                  status:     newStatus,
                });
                console.log(`✅ Invoice ${invoiceId} adjusted by ₹${adjustAmt} — status: ${newStatus}`);
              }
            } catch (e) {
              console.error('⚠️ Invoice adjust error (PaymentReceived edit):', e.message);
            }

            // Adjust paymentaccounts balance
            try {
              const depositTo = prRecord.depositTo;
              if (depositTo) {
                if (mongoose.Types.ObjectId.isValid(depositTo)) {
                  await PaymentAccount.findByIdAndUpdate(depositTo,
                    { $inc: { currentBalance: diff } });
                } else {
                  await PaymentAccount.findOneAndUpdate(
                    { accountName: depositTo },
                    { $inc: { currentBalance: diff } }
                  );
                }
                console.log(`✅ PaymentAccount balance adjusted by ₹${diff}`);
              }
            } catch (e) {
              console.error('⚠️ PaymentAccount adjust error (PaymentReceived edit):', e.message);
            }
          }
        }
      }

      // Adjust bank PaymentAccount balance
      const diff = newAmount - txn.amount;
      if (diff !== 0) {
        await PaymentAccount.findByIdAndUpdate(txn.accountId, {
          $inc: { currentBalance: txn.transactionType === 'DEBIT' ? -diff : diff }
        });
      }
    }

    await ProviderTransaction.findByIdAndUpdate(txn._id, {
      $set: {
        ...(date            && { transactionDate: new Date(date) }),
        ...(description     && { description }),
        ...(amount          && { amount: parseFloat(amount) }),
        ...(referenceNumber && { referenceNumber }),
      }
    });

    res.json({ success: true, message: 'Transaction updated' });
  } catch (err) {
    console.error('❌ edit-transaction error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// Helper: recompute ChartOfAccount.closingBalance from AccountTransaction sum
// branchId scopes the recompute to a specific branch's transactions
async function recomputeClosingBalance(accountId, orgId = null, branchId = null) {
  try {
    const matchFilter = {
      accountId: mongoose.Types.ObjectId.isValid(accountId)
        ? new mongoose.Types.ObjectId(accountId.toString()) : accountId,
      ...(orgId    ? { orgId }    : {}),
      ...(branchId ? { branchId } : {}),
    };
    const agg = await AccountTransaction.aggregate([
      { $match: matchFilter },
      { $group: { _id: null, totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
    ]);
    const totalDebit  = agg[0]?.totalDebit  || 0;
    const totalCredit = agg[0]?.totalCredit || 0;
    // For asset/bank accounts: balance = debit - credit
    const newBalance = Math.round((totalDebit - totalCredit) * 100) / 100;
    // NOTE: closingBalance on ChartOfAccount is org-wide; branch balance is always
    // computed on-the-fly via aggregation. We still update it for backward compat.
    await ChartOfAccount.findByIdAndUpdate(accountId, { $set: { closingBalance: newBalance } });
    return newBalance;
  } catch (e) {
    console.error('⚠️ recomputeClosingBalance error:', e.message);
    return null;
  }
}

// ── POST /recompute-balances/:accountId ──────────────────────────────────────
// Recomputes COA closingBalance from AccountTransaction for a bank account.
// Call this once to fix any stale balance data.
router.post('/recompute-balances/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const bankCOA  = await resolveBankCOA(accountId, req.user?.orgId, branchId).catch(() => null);
    if (!bankCOA) return res.status(404).json({ success: false, message: 'Bank COA not found' });

    const newBalance = await recomputeClosingBalance(bankCOA._id, req.user?.orgId, branchId);
    res.json({ success: true, message: 'Balance recomputed', closingBalance: newBalance });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ROUTE 25b — POST /cleanup-duplicates (ADMIN ONLY - for fixing duplicate ProviderTransactions)
router.post('/cleanup-duplicates', async (req, res) => {
  try {
    const { linkedRecordId, linkedRecordType } = req.body;
    
    if (!linkedRecordId || !linkedRecordType) {
      return res.status(400).json({ 
        success: false, 
        message: 'linkedRecordId and linkedRecordType are required' 
      });
    }

    console.log('🧹 [Cleanup] Starting duplicate cleanup:', { linkedRecordId, linkedRecordType });

    // Find all SYSTEM_ENTRY transactions for this record
    const duplicates = await ProviderTransaction.find({
      linkedRecordId: mongoose.Types.ObjectId.isValid(linkedRecordId) 
        ? new mongoose.Types.ObjectId(linkedRecordId) 
        : linkedRecordId,
      linkedRecordType,
      source: 'SYSTEM_ENTRY',
      ...orgFilter(req),
    }).lean();

    console.log(`🧹 [Cleanup] Found ${duplicates.length} SYSTEM_ENTRY transactions`);
    
    if (duplicates.length === 0) {
      return res.json({ 
        success: true, 
        message: 'No duplicates found',
        deleted: 0 
      });
    }

    // Show all found transactions
    duplicates.forEach((d, idx) => {
      console.log(`  [${idx + 1}] _id: ${d._id} | amount: ₹${d.amount} | journalRef: ${d.journalRef} | date: ${d.transactionDate}`);
    });

    // Delete all of them
    const result = await ProviderTransaction.deleteMany({
      _id: { $in: duplicates.map(d => d._id) },
    });

    console.log(`✅ [Cleanup] Deleted ${result.deletedCount} duplicate transactions`);

    res.json({
      success: true,
      message: `Deleted ${result.deletedCount} duplicate transactions`,
      deleted: result.deletedCount,
      transactions: duplicates.map(d => ({
        _id: d._id,
        amount: d.amount,
        description: d.description,
        journalRef: d.journalRef,
      })),
    });
  } catch (err) {
    console.error('❌ cleanup-duplicates error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ROUTE 25c — POST /fix-corrupted-transaction (ADMIN ONLY - for fixing CSV_IMPORT transactions that got corrupted)
router.post('/fix-corrupted-transaction', async (req, res) => {
  try {
    const { transactionId } = req.body;
    
    if (!transactionId) {
      return res.status(400).json({ 
        success: false, 
        message: 'transactionId is required' 
      });
    }

    console.log('🔧 [Fix] Finding corrupted transaction:', transactionId);

    const txn = await ProviderTransaction.findOne({
      _id: mongoose.Types.ObjectId.isValid(transactionId) 
        ? new mongoose.Types.ObjectId(transactionId) 
        : transactionId,
      ...orgFilter(req),
    });

    if (!txn) {
      return res.status(404).json({ 
        success: false, 
        message: 'Transaction not found' 
      });
    }

    console.log('🔧 [Fix] Transaction BEFORE:', {
      _id: txn._id,
      description: txn.description,
      source: txn.source,
      linkedRecordType: txn.linkedRecordType,
      linkedRecordId: txn.linkedRecordId,
      journalRef: txn.journalRef,
      reconciliationStatus: txn.reconciliationStatus,
      categoryLabel: txn.categoryLabel,
    });

    // Reset to UNCATEGORIZED state
    txn.reconciliationStatus = 'UNCATEGORIZED';
    txn.linkedRecordType = null;
    txn.linkedRecordId = null;
    txn.journalRef = null;
    txn.categoryLabel = null;
    txn.cashFlowSection = null;
    txn.categorizedAt = null;
    txn.categorizedBy = null;

    await txn.save();

    console.log('✅ [Fix] Transaction reset to UNCATEGORIZED');

    res.json({
      success: true,
      message: 'Transaction reset to UNCATEGORIZED state',
      transaction: {
        _id: txn._id,
        description: txn.description,
        amount: txn.amount,
        reconciliationStatus: txn.reconciliationStatus,
      },
    });
  } catch (err) {
    console.error('❌ fix-corrupted-transaction error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// ROUTE 26 — POST /uncategorize/:id
router.post('/uncategorize/:id', async (req, res) => {
  try {
    console.log('═══════════════════════════════════════════════════════════════');
    console.log(`🔍 [uncategorize] START — id=${req.params.id} orgId=${req.user?.orgId}`);
    console.log('═══════════════════════════════════════════════════════════════');
    
    const txn = await ProviderTransaction.findOne({
      _id: req.params.id, ...orgFilter(req)
    });
    
    console.log(`🔍 [uncategorize] Transaction details:`, {
      found: !!txn,
      journalRef: txn?.journalRef,
      linkedRecordId: txn?.linkedRecordId,
      linkedRecordType: txn?.linkedRecordType,
      accountId: txn?.accountId,
      amount: txn?.amount,
      transactionType: txn?.transactionType,
      source: txn?.source,
      reconciliationStatus: txn?.reconciliationStatus,
    });
    
    if (!txn) return res.status(404).json({ success: false, message: 'Transaction not found' });

    // Collect affected COA account IDs so we can recompute their balances after deletion
    const affectedCOAIds = new Set();

    if (txn.journalRef) {
      // ── Case A: categorized via bank_transactions.js (has journalRef) ──────
      console.log('📍 [uncategorize] Entering Case A (has journalRef)');
      
      const orgId = req.user?.orgId || null;
      // NOTE: do NOT filter by branchId — AccountTransaction entries may store
      // branchId differently (array element vs string) causing misses.
      // referenceNumber + orgId is sufficient to uniquely identify the entries.
      const coaDeleteFilter = {
        referenceNumber: txn.journalRef,
        ...(orgId ? { orgId } : {}),
      };
      let entries = await AccountTransaction.find(coaDeleteFilter);
      console.log(`🔍 [uncategorize] Case A — journalRef=${txn.journalRef} orgId=${orgId} → found ${entries.length} COA entries`);
      
      if (entries.length > 0) {
        console.log('🔍 [uncategorize] COA entries to delete:', entries.map(e => ({
          accountId: e.accountId,
          debit: e.debit,
          credit: e.credit,
          description: e.description,
        })));
      }

      // Fallback: if journalRef-based delete finds nothing, try by linkedRecordId.
      // This covers embedded-page saves (NewExpensePage etc.) where the COA entries
      // were posted with referenceId = expense._id, not referenceNumber = journalRef.
      if (entries.length === 0 && txn.linkedRecordId) {
        const linkedObjId = mongoose.Types.ObjectId.isValid(txn.linkedRecordId.toString())
          ? new mongoose.Types.ObjectId(txn.linkedRecordId.toString())
          : txn.linkedRecordId;

        // Try referenceId first
        let fallbackFilter = {
          referenceId: linkedObjId,
          ...(orgId ? { orgId } : {}),
        };
        entries = await AccountTransaction.find(fallbackFilter);

        // If still nothing, look up the payment/expense record and try by referenceNumber
        if (entries.length === 0) {
          let refNumber = null;
          try {
            const PaymentReceived = mongoose.models.PaymentReceived
              || mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'payments_received');
            const PaymentMade = mongoose.models.PaymentMade
              || mongoose.model('PaymentMade', new mongoose.Schema({}, { strict: false }), 'payments_made');
            const pr = await PaymentReceived.findById(linkedObjId).lean();
            if (pr) refNumber = pr.paymentNumber;
            if (!refNumber) {
              const pm = await PaymentMade.findById(linkedObjId).lean();
              if (pm) refNumber = pm.paymentNumber;
            }
            if (!refNumber) {
              const exp = await Expense.findById(linkedObjId).lean();
              if (exp) refNumber = exp.expenseNumber || exp._id.toString();
            }
          } catch (_) {}

          if (refNumber) {
            fallbackFilter = { referenceNumber: refNumber, ...(orgId ? { orgId } : {}) };
            entries = await AccountTransaction.find(fallbackFilter);
            console.log(`[uncategorize] Case A fallback-2 — referenceNumber=${refNumber} → found ${entries.length} COA entries`);
          }
        }

        entries.forEach(e => affectedCOAIds.add(e.accountId.toString()));
        await AccountTransaction.deleteMany(fallbackFilter);
      } else {
        entries.forEach(e => affectedCOAIds.add(e.accountId.toString()));
        await AccountTransaction.deleteMany(coaDeleteFilter);
      }

      // Delete the linked Expense/record created during categorization
      let linkedAmount = txn.amount;
      console.log(`🔍 [uncategorize] Initial linkedAmount: ₹${linkedAmount}`);
      
      if (txn.linkedRecordType === 'Expense' && txn.linkedRecordId) {
        try {
          const linked = await Expense.findById(txn.linkedRecordId).lean();
          console.log(`🔍 [uncategorize] Found linked Expense:`, {
            _id: linked?._id,
            total: linked?.total,
            expenseAccount: linked?.expenseAccount,
            paidThrough: linked?.paidThrough,
          });
          if (linked?.total) {
            linkedAmount = linked.total;
            console.log(`✅ [uncategorize] Updated linkedAmount from Expense.total: ₹${linkedAmount}`);
          }
        } catch (e) {
          console.error('⚠️ [uncategorize] Error fetching linked Expense:', e.message);
        }
      }
      
      console.log(`🔍 [uncategorize] About to delete linked record with skipCOAReversal=true`);
      await deleteLinkedRecord(txn, req, { skipCOAReversal: true });
      console.log(`✅ [uncategorize] Linked record deleted`);

      // Restore PaymentAccount.currentBalance
      // ✅ FIX: Always restore balance when uncategorizing, regardless of source.
      // When a CSV_IMPORT transaction is categorized as an expense, the PaymentAccount
      // balance IS reduced. So when uncategorizing, we must restore it.
      if (txn.accountId) {
        console.log(`🔍 [uncategorize] Restoring PaymentAccount balance:`, {
          accountId: txn.accountId,
          linkedAmount: linkedAmount,
          transactionType: txn.transactionType,
          source: txn.source,
        });
        
        // Get current balance before update
        const accountBefore = await PaymentAccount.findById(txn.accountId).lean();
        console.log(`🔍 [uncategorize] PaymentAccount BEFORE: currentBalance = ₹${accountBefore?.currentBalance}`);
        
        if (txn.transactionType === 'DEBIT') {
          await PaymentAccount.findByIdAndUpdate(txn.accountId,
            { $inc: { currentBalance: linkedAmount } });
          console.log(`✅ [uncategorize] PaymentAccount balance restored: +₹${linkedAmount}`);
        } else {
          await PaymentAccount.findByIdAndUpdate(txn.accountId,
            { $inc: { currentBalance: -linkedAmount } });
          console.log(`✅ [uncategorize] PaymentAccount balance restored: -₹${linkedAmount}`);
        }
        
        // Get balance after update
        const accountAfter = await PaymentAccount.findById(txn.accountId).lean();
        console.log(`🔍 [uncategorize] PaymentAccount AFTER: currentBalance = ₹${accountAfter?.currentBalance}`);
      } else {
        console.log(`⚠️ [uncategorize] No accountId found, skipping PaymentAccount balance restoration`);
      }
    } else {
      // ── Case B: no journalRef ────────────────────────────────────────────────
      console.log('📍 [uncategorize] Entering Case B (no journalRef)');
      
      const orgId = req.user?.orgId || null;

      let linkedObjId = null;
      let paymentNumber = null;

      if (txn.linkedRecordId) {
        linkedObjId = mongoose.Types.ObjectId.isValid(txn.linkedRecordId.toString())
          ? new mongoose.Types.ObjectId(txn.linkedRecordId.toString())
          : txn.linkedRecordId;
      }

      // ── If linkedRecordId is missing, find the payment by providerTransactionId ──
      // Old ProviderTransactions created before linkedRecordId was stored fall here.
      if (!linkedObjId && txn.linkedRecordType) {
        try {
          const collectionMap = {
            PaymentReceived: 'payments_received',
            PaymentMade:     'payments_made',
            Expense:         'expenses',
          };
          const collName = collectionMap[txn.linkedRecordType];
          if (collName) {
            const db = mongoose.connection.db;
            // Try to find by providerTransactionId field
            let rec = await db.collection(collName).findOne({
              providerTransactionId: txn._id,
              ...(orgId ? { orgId } : {}),
            });
            // Fallback: find by matching amount + date window
            if (!rec) {
              const txnDate = new Date(txn.transactionDate || txn.createdAt);
              const dayBefore = new Date(txnDate); dayBefore.setDate(dayBefore.getDate() - 1);
              const dayAfter  = new Date(txnDate); dayAfter.setDate(dayAfter.getDate() + 1);
              rec = await db.collection(collName).findOne({
                ...(orgId ? { orgId } : {}),
                $or: [
                  { amountReceived: txn.amount },
                  { amount: txn.amount },
                ],
                createdAt: { $gte: dayBefore, $lte: dayAfter },
              });
            }
            if (rec) {
              linkedObjId   = rec._id;
              paymentNumber = rec.paymentNumber || rec.expenseNumber;
              console.log(`[uncategorize] Case B resolved linkedRecord via collection lookup: ${collName} → ${linkedObjId} paymentNumber=${paymentNumber}`);
            }
          }
        } catch (e) {
          console.error('[uncategorize] Case B linkedRecord lookup error:', e.message);
        }
      }

      // Now delete COA entries — try all available keys
      let entries = [];

      // 1. Try by referenceId
      if (linkedObjId) {
        const f = { referenceId: linkedObjId, ...(orgId ? { orgId } : {}) };
        entries = await AccountTransaction.find(f);
        console.log(`[uncategorize] Case B referenceId lookup → found ${entries.length}`);
        if (entries.length > 0) {
          entries.forEach(e => affectedCOAIds.add(e.accountId.toString()));
          await AccountTransaction.deleteMany(f);
        }
      }

      // 2. Try by referenceNumber = paymentNumber
      if (entries.length === 0 && paymentNumber) {
        const f = { referenceNumber: paymentNumber, ...(orgId ? { orgId } : {}) };
        entries = await AccountTransaction.find(f);
        console.log(`[uncategorize] Case B referenceNumber=${paymentNumber} → found ${entries.length}`);
        if (entries.length > 0) {
          entries.forEach(e => affectedCOAIds.add(e.accountId.toString()));
          await AccountTransaction.deleteMany(f);
        }
      }

      // 3. Last resort: look up paymentNumber from the record if not yet resolved
      if (entries.length === 0 && linkedObjId && !paymentNumber) {
        try {
          const PaymentReceived = mongoose.models.PaymentReceived
            || mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'payments_received');
          const PaymentMade = mongoose.models.PaymentMade
            || mongoose.model('PaymentMade', new mongoose.Schema({}, { strict: false }), 'payments_made');
          const pr = await PaymentReceived.findById(linkedObjId).lean();
          if (pr?.paymentNumber) paymentNumber = pr.paymentNumber;
          if (!paymentNumber) {
            const pm = await PaymentMade.findById(linkedObjId).lean();
            if (pm?.paymentNumber) paymentNumber = pm.paymentNumber;
          }
          if (!paymentNumber) {
            const exp = await Expense.findById(linkedObjId).lean();
            if (exp) paymentNumber = exp.expenseNumber || exp._id.toString();
          }
          if (paymentNumber) {
            const f = { referenceNumber: paymentNumber, ...(orgId ? { orgId } : {}) };
            entries = await AccountTransaction.find(f);
            console.log(`[uncategorize] Case B fallback referenceNumber=${paymentNumber} → found ${entries.length}`);
            if (entries.length > 0) {
              entries.forEach(e => affectedCOAIds.add(e.accountId.toString()));
              await AccountTransaction.deleteMany(f);
            }
          }
        } catch (_) {}
      }

      await deleteLinkedRecord(txn, req, { skipCOAReversal: true });

      // Restore PaymentAccount.currentBalance
      // ✅ FIX: Always restore balance when uncategorizing, regardless of source.
      if (txn.accountId) {
        console.log(`🔍 [uncategorize] Restoring PaymentAccount balance (Case B): accountId=${txn.accountId}, amount=${txn.amount}, type=${txn.transactionType}`);
        if (txn.transactionType === 'DEBIT') {
          await PaymentAccount.findByIdAndUpdate(txn.accountId,
            { $inc: { currentBalance: txn.amount } });
          console.log(`✅ [uncategorize] PaymentAccount balance restored (Case B): +₹${txn.amount}`);
        } else {
          await PaymentAccount.findByIdAndUpdate(txn.accountId,
            { $inc: { currentBalance: -txn.amount } });
          console.log(`✅ [uncategorize] PaymentAccount balance restored (Case B): -₹${txn.amount}`);
        }
      }
    }

    // Recompute closingBalance for all affected COA accounts from scratch — branch-scoped
    const txnBranchIdForRecompute = txn.branchId || null;
    console.log(`🔍 [uncategorize] Recomputing closingBalance for ${affectedCOAIds.size} COA accounts`);
    for (const coaId of affectedCOAIds) {
      await recomputeClosingBalance(coaId, req.user?.orgId, txnBranchIdForRecompute);
    }
    console.log(`✅ [uncategorize] COA balances recomputed`);

    console.log(`🔍 [uncategorize] Updating ProviderTransaction status to UNCATEGORIZED`);
    await ProviderTransaction.findByIdAndUpdate(txn._id, {
      $set: {
        reconciliationStatus: 'UNCATEGORIZED',
        categorizedAt:    null,
        categorizedBy:    null,
        journalRef:       null,
        categoryLabel:    null,
        linkedRecordId:   null,
        linkedRecordType: null,
      }
    });
    console.log(`✅ [uncategorize] ProviderTransaction updated to UNCATEGORIZED`);

    console.log('═══════════════════════════════════════════════════════════════');
    console.log('✅ [uncategorize] COMPLETE — Transaction uncategorized successfully');
    console.log('═══════════════════════════════════════════════════════════════');

    res.json({ success: true, message: 'Transaction uncategorized successfully' });
  } catch (err) {
    console.error('❌ uncategorize error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// Helper to delete linked records and reverse COA + balances
async function deleteLinkedRecord(txn, req, { skipCOAReversal = false } = {}) {
  if (!txn.linkedRecordType) {
    await Expense.deleteMany({ providerTransactionId: txn._id, ...orgFilter(req) });
    return;
  }

  // Build query — prefer _id lookup when linkedRecordId is available (most reliable)
  let modelQuery;
  if (txn.linkedRecordId) {
    const linkedObjId = mongoose.Types.ObjectId.isValid(txn.linkedRecordId.toString())
      ? new mongoose.Types.ObjectId(txn.linkedRecordId.toString())
      : txn.linkedRecordId;
    modelQuery = { _id: linkedObjId, ...orgFilter(req) };
  } else {
    modelQuery = { providerTransactionId: txn._id, ...orgFilter(req) };
  }

  switch (txn.linkedRecordType) {

    case 'Expense': {
      const expense = await Expense.findOne(modelQuery).lean();
      if (!expense) break;
      const orgId = req.user?.orgId || null;

      // Reverse COA — only when not already handled by direct AccountTransaction deletion
      if (!skipCOAReversal) {
        try {
          const branchId = txn.branchId || (req.branchIds?.length > 0 ? req.branchIds[0] : null);
          let expAccId = null;
          let paidAccId = null;

          expAccId = await ChartOfAccount.findOne({
            accountName: expense.expenseAccount,
            ...(orgId    ? { orgId }    : {}),
            ...(branchId ? { branchId } : {}),
          }).then(a => a?._id).catch(() => null);

          if (mongoose.Types.ObjectId.isValid(expense.paidThrough)) {
            paidAccId = await ChartOfAccount.findById(expense.paidThrough)
              .then(a => a?._id).catch(() => null);
          }
          if (!paidAccId) {
            paidAccId = await ChartOfAccount.findOne({
              accountName: expense.paidThrough,
              ...(orgId    ? { orgId }    : {}),
              ...(branchId ? { branchId } : {}),
            }).then(a => a?._id).catch(() => null);
          }

          const txnDate = new Date();
          const desc = `REVERSAL (Uncategorize) - Expense ${expense._id}`;

          // Cr Expense account (reverses the original Dr)
          if (expAccId) {
            await postTransactionToCOA({
              accountId: expAccId, orgId, branchId,
              date: txnDate, description: desc,
              referenceType: 'Expense', referenceId: expense._id,
              referenceNumber: expense._id.toString(),
              debit: 0, credit: expense.total,
            });
          }
          // Dr Bank/Cash account (reverses the original Cr)
          if (paidAccId) {
            await postTransactionToCOA({
              accountId: paidAccId, orgId, branchId,
              date: txnDate, description: desc,
              referenceType: 'Expense', referenceId: expense._id,
              referenceNumber: expense._id.toString(),
              debit: expense.total, credit: 0,
            });
          }
        } catch (e) {
          console.error('⚠️ Expense COA reversal error:', e.message);
        }
      }

      // Restore PaymentAccount balance — only when COA reversal is also being done
      // (Case A with journalRef already restores balance via txn.accountId above)
      if (!skipCOAReversal) {
        try {
          const pt = expense.paidThrough;
          if (mongoose.Types.ObjectId.isValid(pt)) {
            await PaymentAccount.findByIdAndUpdate(pt,
              { $inc: { currentBalance: expense.total } });
          } else {
            await PaymentAccount.findOneAndUpdate(
              { accountName: pt },
              { $inc: { currentBalance: expense.total } }
            );
          }
        } catch (e) {
          console.error('⚠️ Expense balance restore error:', e.message);
        }
      }

      await Expense.deleteOne({ _id: expense._id });
      break;
    }

    case 'PaymentMade': {
      const PaymentMade = mongoose.models.PaymentMade
        || mongoose.model('PaymentMade', new mongoose.Schema({}, { strict: false }), 'payments_made');

      const payment = await PaymentMade.findOne(modelQuery).lean();
      if (!payment) break;
      const orgId = req.user?.orgId || null;

      // Reverse bill balances if linked
      try {
        const Bill = mongoose.models.Bill
          || mongoose.model('Bill', new mongoose.Schema({}, { strict: false }), 'bills');

        // Handle billsApplied array (standard payment_made.js format)
        const billsApplied = payment.billsApplied || [];
        for (const ba of billsApplied) {
          if (!ba.billId) continue;
          const bill = await Bill.findById(ba.billId).lean();
          if (!bill) continue;
          const appliedAmt   = parseFloat(ba.amountApplied || 0);
          const newAmountPaid = Math.max(0, (bill.amountPaid || 0) - appliedAmt);
          const newAmountDue  = Math.max(0, (bill.totalAmount || bill.total || 0) - newAmountPaid);

          let newStatus;
          if (newAmountPaid <= 0)                                    newStatus = 'OPEN';
          else if (newAmountPaid > 0 && newAmountDue > 0)           newStatus = 'PARTIALLY_PAID';
          else                                                        newStatus = 'PAID';

          // Also remove the payment entry from bill.payments array
          await Bill.findByIdAndUpdate(ba.billId, {
            amountPaid: newAmountPaid,
            amountDue:  newAmountDue,
            status:     newStatus,
            $pull: { payments: { referenceNumber: payment.paymentNumber } },
          });
        }

        // Fallback: handle legacy single billId field
        if (billsApplied.length === 0 && (payment.billId || payment.vendorBillId)) {
          const billId = payment.billId || payment.vendorBillId;
          const bill = await Bill.findById(billId).lean();
          if (bill) {
            const appliedAmt   = parseFloat(payment.amount || payment.amountPaid || 0);
            const newAmountPaid = Math.max(0, (bill.amountPaid || 0) - appliedAmt);
            const newAmountDue  = Math.max(0, (bill.totalAmount || bill.total || 0) - newAmountPaid);

            let newStatus;
            if (newAmountPaid <= 0)                                  newStatus = 'OPEN';
            else if (newAmountPaid > 0 && newAmountDue > 0)         newStatus = 'PARTIALLY_PAID';
            else                                                      newStatus = 'PAID';

            await Bill.findByIdAndUpdate(billId, {
              amountPaid: newAmountPaid,
              amountDue:  newAmountDue,
              status:     newStatus,
              $pull: { payments: { referenceNumber: payment.paymentNumber } },
            });
          }
        }
      } catch (e) {
        console.error('⚠️ Bill balance restore error:', e.message);
      }

      // Reverse PaymentAccount (paidFromAccount) balance — only when not already handled by Case A
      if (!skipCOAReversal) {
        try {
          const paidFrom = payment.paidFromAccountId || payment.paidFromAccount || payment.paidThroughAccount || payment.paidThrough;
          if (paidFrom) {
            if (mongoose.Types.ObjectId.isValid(paidFrom)) {
              await PaymentAccount.findByIdAndUpdate(paidFrom,
                { $inc: { currentBalance: payment.amount || payment.amountPaid || 0 } });
            } else {
              await PaymentAccount.findOneAndUpdate(
                { accountName: paidFrom },
                { $inc: { currentBalance: payment.amount || payment.amountPaid || 0 } }
              );
            }
          }
        } catch (e) {
          console.error('⚠️ PaymentMade balance restore error:', e.message);
        }
      }

      // Reverse COA entries — Dr AP / Cr Bank
      if (!skipCOAReversal) {
        try {
          const branchId = txn.branchId || (req.branchIds?.length > 0 ? req.branchIds[0] : null);
          const apCOA = await ChartOfAccount.findOne({
            accountName: 'Accounts Payable',
            ...(orgId    ? { orgId }    : {}),
            ...(branchId ? { branchId } : {}),
          }).lean();

          let bankCOAId = null;
          const paidFrom = payment.paidFromAccountId || payment.paidFromAccount || payment.paidThroughAccount || payment.paidThrough;
          if (paidFrom) {
            if (mongoose.Types.ObjectId.isValid(paidFrom)) {
              bankCOAId = await ChartOfAccount.findById(paidFrom).then(a => a?._id).catch(() => null);
            }
            if (!bankCOAId) {
              const nameToSearch = payment.paidFromAccountName || paidFrom;
              bankCOAId = await ChartOfAccount.findOne({
                accountName: nameToSearch,
                ...(orgId    ? { orgId }    : {}),
                ...(branchId ? { branchId } : {}),
              }).then(a => a?._id).catch(() => null);
            }
          }

          const txnDate = new Date();
          const desc = `REVERSAL (Uncategorize) - PaymentMade ${payment._id}`;
          const amt = payment.amount || payment.amountPaid || 0;

          // Cr AP (reverses original Dr AP)
          if (apCOA) {
            await postTransactionToCOA({
              accountId: apCOA._id, orgId, branchId,
              date: txnDate, description: desc,
              referenceType: 'Bill', referenceId: payment._id,
              referenceNumber: payment._id.toString(),
              debit: 0, credit: amt,
            });
          }
          // Dr Bank (reverses original Cr Bank)
          if (bankCOAId) {
            await postTransactionToCOA({
              accountId: bankCOAId, orgId, branchId,
              date: txnDate, description: desc,
              referenceType: 'Bill', referenceId: payment._id,
              referenceNumber: payment._id.toString(),
              debit: amt, credit: 0,
            });
          }
        } catch (e) {
          console.error('⚠️ PaymentMade COA reversal error:', e.message);
        }
      }

      await PaymentMade.deleteOne({ _id: payment._id });

      // Clean up any system-created ProviderTransaction linked to this payment
      try {
        await ProviderTransaction.deleteMany({
          linkedRecordId:   payment._id,
          linkedRecordType: 'PaymentMade',
          source:           'SYSTEM_ENTRY',
          ...(orgId ? { orgId } : {}),
        });
      } catch (e) {
        console.error('⚠️ PaymentMade system ProviderTransaction cleanup error:', e.message);
      }

      break;
    }

    case 'PaymentReceived': {
      const PaymentReceived = mongoose.models.PaymentReceived
        || mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'payments_received');

      const payment = await PaymentReceived.findOne(modelQuery).lean();
      if (!payment) break;
      const orgId = req.user?.orgId || null;

      // Reverse invoice balances if linked
      try {
        const invoicePayments = payment.invoicePayments || {};
        const Invoice = mongoose.models.Invoice
          || mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');

        for (const [invoiceId, amount] of Object.entries(invoicePayments)) {
          if (!mongoose.Types.ObjectId.isValid(invoiceId)) continue;
          const invoice = await Invoice.findById(invoiceId).lean();
          if (!invoice) continue;

          const amt = parseFloat(amount) || 0;
          const restoredAmountPaid = Math.max(0, (invoice.amountPaid || 0) - amt);
          const restoredAmountDue  = Math.max(0, (invoice.totalAmount || 0) - restoredAmountPaid);

          let newStatus;
          if (restoredAmountPaid <= 0)                               newStatus = 'UNPAID';
          else if (restoredAmountPaid > 0 && restoredAmountDue > 0) newStatus = 'PARTIALLY_PAID';
          else                                                       newStatus = 'PAID';

          await Invoice.findByIdAndUpdate(invoiceId, {
            amountPaid: restoredAmountPaid,
            amountDue:  restoredAmountDue,
            status:     newStatus,
            $pull:      { payments: { paymentId: payment._id.toString() } },
          });
          console.log(`✅ Invoice ${invoiceId} restored — status: ${newStatus}`);
        }
      } catch (e) {
        console.error('⚠️ Invoice balance restore error:', e.message);
      }

      // Reverse paymentaccounts balance — only when not already handled by Case A
      if (!skipCOAReversal) {
        try {
          const depositTo = payment.depositTo;
          const amt       = parseFloat(payment.amountReceived || 0);
          if (depositTo && amt > 0) {
            if (mongoose.Types.ObjectId.isValid(depositTo)) {
              await PaymentAccount.findByIdAndUpdate(depositTo,
                { $inc: { currentBalance: -amt } });
            } else {
              await PaymentAccount.findOneAndUpdate(
                { accountName: depositTo },
                { $inc: { currentBalance: -amt } }
              );
            }
            console.log(`✅ PaymentAccount balance reversed: -₹${amt}`);
          }
        } catch (e) {
          console.error('⚠️ PaymentAccount reverse error (PaymentReceived uncategorize):', e.message);
        }
      }

      // Reverse COA entries — Cr deposit account / Dr AR
      if (!skipCOAReversal) {
        try {
          const branchId = txn.branchId || (req.branchIds?.length > 0 ? req.branchIds[0] : null);
          const arCOA = await ChartOfAccount.findOne({
            accountName: 'Accounts Receivable',
            ...(orgId    ? { orgId }    : {}),
            ...(branchId ? { branchId } : {}),
          }).lean();

          let depositCOAId = null;
          const depositAcct = payment.depositTo || payment.depositToAccount || payment.depositToAccountId;
          if (depositAcct) {
            if (mongoose.Types.ObjectId.isValid(depositAcct)) {
              depositCOAId = await ChartOfAccount.findById(depositAcct).then(a => a?._id).catch(() => null);
            }
            if (!depositCOAId) {
              depositCOAId = await ChartOfAccount.findOne({
                accountName: depositAcct,
                ...(orgId    ? { orgId }    : {}),
                ...(branchId ? { branchId } : {}),
              }).then(a => a?._id).catch(() => null);
            }
          }

          const txnDate = new Date();
          const desc = `REVERSAL (Uncategorize) - PaymentReceived ${payment._id}`;
          const amt = payment.amountReceived || payment.amount || 0;

          // Cr Bank/deposit (reverses original Dr Bank)
          if (depositCOAId) {
            await postTransactionToCOA({
              accountId: depositCOAId, orgId, branchId,
              date: txnDate, description: desc,
              referenceType: 'Payment', referenceId: payment._id,
              referenceNumber: payment._id.toString(),
              debit: 0, credit: amt,
            });
          }
          // Dr AR (reverses original Cr AR)
          if (arCOA) {
            await postTransactionToCOA({
              accountId: arCOA._id, orgId, branchId,
              date: txnDate, description: desc,
              referenceType: 'Payment', referenceId: payment._id,
              referenceNumber: payment._id.toString(),
              debit: amt, credit: 0,
            });
          }
        } catch (e) {
          console.error('⚠️ PaymentReceived COA reversal error:', e.message);
        }
      }

      // ── REVERSE CUSTOMER UNUSED CREDITS ─────────────────────────────────
      // DON'T delete payment here - check if it's a refund first!
      try {
        console.log('\n💰💰💰 [PAYMENT REFUND UNCATEGORIZE] START 💰💰💰');
        console.log('🔍 [uncategorize] Checking if this is a Payment Refund...');
        console.log('   categoryLabel:', txn.categoryLabel);
        console.log('   linkedRecordType:', txn.linkedRecordType);
        console.log('   payment._id:', payment._id);
        console.log('   payment.paymentNumber:', payment.paymentNumber);
        console.log('   payment.customerId:', payment.customerId);
        
        // Check if this is a Payment Refund (not a full payment deletion)
        const isPaymentRefund = txn.categoryLabel === 'Payment Refund' || 
                                txn.linkedRecordType === 'PaymentRefund';
        
        console.log('   isPaymentRefund:', isPaymentRefund);
        
        if (isPaymentRefund) {
          console.log('\n✅ [uncategorize] This IS a Payment Refund - reversing refund (NOT deleting payment)');
          
          // For Payment Refund: DON'T delete the payment, just reverse the refund
          // Restore amountInExcess and remove the refund entry
          const refundAmount = parseFloat(txn.amount || 0);
          
          console.log('   refundAmount:', refundAmount);
          
          if (refundAmount > 0) {
            // Restore amountInExcess on the payment
            const newAmountRefunded = Math.max(0, (payment.amountRefunded || 0) - refundAmount);
            const newAmountInExcess = (payment.amountInExcess || 0) + refundAmount;
            
            console.log('\n📊 [uncategorize] Payment amounts BEFORE reversal:');
            console.log('   amountRefunded:', payment.amountRefunded || 0);
            console.log('   amountInExcess:', payment.amountInExcess || 0);
            console.log('\n📊 [uncategorize] Payment amounts AFTER reversal:');
            console.log('   newAmountRefunded:', newAmountRefunded);
            console.log('   newAmountInExcess:', newAmountInExcess);
            
            console.log('\n🔄 [uncategorize] Updating payment document...');
            const updateResult = await PaymentReceived.findByIdAndUpdate(
              payment._id,
              {
                $set: {
                  amountRefunded: newAmountRefunded,
                  amountInExcess: newAmountInExcess,
                  updatedAt: new Date(),
                },
                // Remove the refund entry from the refunds array if it exists
                $pull: { refunds: { amount: refundAmount } },
              },
              { new: true }
            );
            
            if (updateResult) {
              console.log('✅ [uncategorize] Payment document updated successfully');
              console.log('   Updated payment._id:', updateResult._id);
              console.log('   Updated amountInExcess:', updateResult.amountInExcess);
              console.log('   Updated amountRefunded:', updateResult.amountRefunded);
            } else {
              console.error('❌ [uncategorize] Payment update FAILED - payment not found!');
            }
            
            console.log(`\n✅ [uncategorize] Payment ${payment.paymentNumber} refund reversed - amountInExcess restored to ${newAmountInExcess}`);
            
            // Restore unusedCredits to customer
            if (payment.customerId) {
              const BillingCustomer = mongoose.models.BillingCustomer
                || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
              
              const custId = mongoose.Types.ObjectId.isValid(payment.customerId)
                ? new mongoose.Types.ObjectId(payment.customerId)
                : payment.customerId;
              
              console.log(`\n🔄 [uncategorize] Restoring unusedCredits to customer ${custId}`);
              console.log('   Amount to restore:', refundAmount);
              
              const customerBefore = await BillingCustomer.findById(custId);
              console.log('   Customer unusedCredits BEFORE:', customerBefore?.unusedCredits || 0);
              
              const customerResult = await BillingCustomer.findOneAndUpdate(
                { _id: custId },
                { $inc: { unusedCredits: refundAmount } },
                { new: true }
              );
              
              if (customerResult) {
                console.log('   Customer unusedCredits AFTER:', customerResult.unusedCredits || 0);
                console.log(`✅ [uncategorize] Customer unusedCredits restored by +₹${refundAmount}`);
              } else {
                console.error('❌ [uncategorize] Customer update FAILED - customer not found!');
              }
            } else {
              console.warn('⚠️ [uncategorize] No customerId on payment - skipping unusedCredits restore');
            }
            
            console.log('\n💰💰💰 [PAYMENT REFUND UNCATEGORIZE] COMPLETE - Payment kept in database 💰💰💰\n');
          } else {
            console.warn('⚠️ [uncategorize] refundAmount is 0 or invalid - skipping reversal');
          }
        } else {
          console.log('\n⚠️ [uncategorize] This is NOT a Payment Refund - deleting entire payment');
          
          // Standard payment deletion: delete the entire payment
          console.log('🗑️ [uncategorize] Deleting payment document:', payment._id);
          await PaymentReceived.deleteOne({ _id: payment._id });
          console.log('✅ [uncategorize] Payment deleted');
          
          // Standard payment deletion logic
          const BillingCustomer = mongoose.models.BillingCustomer
            || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');

          let creditDelta;
          if (payment.paymentType === 'advance') {
            // Advance: full netAmount was added to unusedCredits → reverse it
            creditDelta = -(parseFloat(payment.netAmount || payment.amountReceived || 0));
          } else {
            // Normal payment: amountInExcess was the net credit contribution → reverse it
            creditDelta = -(parseFloat(payment.amountInExcess || 0));
          }

          console.log('   creditDelta:', creditDelta);

          if (creditDelta !== 0 && payment.customerId) {
            const custId = mongoose.Types.ObjectId.isValid(payment.customerId)
              ? new mongoose.Types.ObjectId(payment.customerId)
              : payment.customerId;
            await BillingCustomer.findOneAndUpdate(
              { _id: custId },
              { $inc: { unusedCredits: creditDelta } }
            );
            // Clamp to 0 — never go negative
            await BillingCustomer.findOneAndUpdate(
              { _id: custId, unusedCredits: { $lt: 0 } },
              { $set: { unusedCredits: 0 } }
            );
            console.log(`✅ [uncategorize] Customer unusedCredits reversed by ${creditDelta} (type: ${payment.paymentType || 'payment'})`);
          }
        }
      } catch (e) {
        console.error('❌ [uncategorize] unusedCredits reversal error:', e.message);
        console.error('   Stack:', e.stack);
      }
      // ── END UNUSED CREDITS REVERSAL ──────────────────────────────────────

      // Clean up any system-created ProviderTransaction linked to this payment
      try {
        await ProviderTransaction.deleteMany({
          linkedRecordId:   payment._id,
          linkedRecordType: 'PaymentReceived',
          source:           'SYSTEM_ENTRY',
          ...(orgId ? { orgId } : {}),
        });
      } catch (e) {
        console.error('⚠️ PaymentReceived system ProviderTransaction cleanup error:', e.message);
      }

      break;
    }

    case 'Invoice':
    case 'Bill':
      // Do NOT delete the invoice/bill itself — only reverse the bank match
      break;

    case 'VendorCredit': {
      // Reverse the specific refund sub-doc from the vendor credit.
      // txn.journalRef = refund sub-doc _id (set during vendor_credit_refund categorization)
      // txn.linkedRecordId = vendor credit _id
      try {
        const VendorCredit = mongoose.models.VendorCredit
          || mongoose.model('VendorCredit', new mongoose.Schema({}, { strict: false }), 'vendorcredits');

        const credit = await VendorCredit.findOne({
          _id: txn.linkedRecordId,
          ...req.orgFilter,
        });

        if (credit) {
          const refundId = txn.journalRef?.toString();

          if (refundId && mongoose.Types.ObjectId.isValid(refundId)) {
            // Remove the exact refund sub-doc by its _id
            const before = credit.refunds.length;
            credit.refunds = credit.refunds.filter(
              r => r._id.toString() !== refundId
            );
            console.log(`[uncategorize] VendorCredit: removed ${before - credit.refunds.length} refund(s) by _id=${refundId}`);
          } else {
            // Fallback: remove the most recent refund matching the transaction amount
            const txnAmt = txn.amount || 0;
            const idx = credit.refunds.map(r => r.amount).lastIndexOf(txnAmt);
            if (idx !== -1) {
              credit.refunds.splice(idx, 1);
              console.log(`[uncategorize] VendorCredit: removed refund by amount fallback idx=${idx}`);
            }
          }

          // Recalculate balance
          const totalUsed =
            credit.applications.reduce((s, a) => s + (a.amount || 0), 0) +
            credit.refunds.reduce((s, r) => s + (r.amount || 0), 0);
          credit.appliedAmount = totalUsed;
          credit.balanceAmount = credit.totalAmount - totalUsed;

          // Restore status
          if (credit.balanceAmount <= 0.01) {
            credit.status        = 'CLOSED';
            credit.balanceAmount = 0;
          } else if (credit.appliedAmount > 0) {
            credit.status = 'PARTIALLY_APPLIED';
          } else {
            credit.status = 'OPEN';
          }

          await credit.save();
          console.log(`[uncategorize] VendorCredit ${credit.creditNumber} restored → status=${credit.status} balance=${credit.balanceAmount}`);
        }
      } catch (e) {
        console.error('⚠️ VendorCredit refund reversal error:', e.message);
      }
      break;
    }

    case 'CreditNote': {
      // Reverse the specific refund sub-doc from the credit note.
      // txn.journalRef    = refund sub-doc _id (set during credit_note_refund categorization)
      // txn.linkedRecordId = credit note _id
      try {
        const CreditNote = mongoose.models.CreditNote
          || mongoose.model('CreditNote', new mongoose.Schema({}, { strict: false }), 'creditnotes');

        const creditNote = await CreditNote.findOne({
          _id: txn.linkedRecordId,
          ...req.orgFilter,
        });

        if (creditNote) {
          const refundId = txn.journalRef?.toString();

          if (refundId && mongoose.Types.ObjectId.isValid(refundId)) {
            // Remove the exact refund sub-doc by its _id
            const before = creditNote.refunds.length;
            creditNote.refunds = creditNote.refunds.filter(
              r => r._id.toString() !== refundId
            );
            console.log(`[uncategorize] CreditNote: removed ${before - creditNote.refunds.length} refund(s) by _id=${refundId}`);
          } else {
            // Fallback: remove the most recent refund matching the transaction amount
            const txnAmt = txn.amount || 0;
            const idx = creditNote.refunds.map(r => r.amount).lastIndexOf(txnAmt);
            if (idx !== -1) {
              creditNote.refunds.splice(idx, 1);
              console.log(`[uncategorize] CreditNote: removed refund by amount fallback idx=${idx}`);
            }
          }

          // Recalculate creditUsed and creditBalance
          const totalRefunded = creditNote.refunds.reduce((s, r) => s + (r.amount || 0), 0);
          const totalApplied  = (creditNote.creditApplications || []).reduce((s, a) => s + (a.amount || 0), 0);
          creditNote.creditUsed    = totalRefunded + totalApplied;
          creditNote.creditBalance = creditNote.totalAmount - creditNote.creditUsed;

          // Restore status
          if (creditNote.creditBalance <= 0.01) {
            creditNote.status        = 'CLOSED';
            creditNote.creditBalance = 0;
          } else if (creditNote.creditUsed > 0) {
            creditNote.status = 'PARTIALLY_APPLIED';
          } else {
            creditNote.status = 'OPEN';
          }

          await creditNote.save();
          console.log(`[uncategorize] CreditNote ${creditNote.creditNoteNumber} restored → status=${creditNote.status} balance=${creditNote.creditBalance}`);

          // ── Restore Customer unusedCredits ────────────────────────────────────
          // When refund is uncategorized, restore the credit to customer profile
          try {
            const Customer = mongoose.models.Customer
              || mongoose.model('Customer', new mongoose.Schema({}, { strict: false }), 'customers');
            
            const refundAmount = txn.amount || 0;
            console.log(`🔍 [uncategorize] Restoring customer unusedCredits: customerId=${creditNote.customerId}, amount=+₹${refundAmount}`);
            
            await Customer.findByIdAndUpdate(creditNote.customerId, {
              $inc: { unusedCredits: refundAmount }
            });
            
            console.log(`✅ [uncategorize] Customer unusedCredits restored: +₹${refundAmount}`);
          } catch (custErr) {
            console.error('⚠️ [uncategorize] Customer unusedCredits restore error:', custErr.message);
          }

          // ── Delete System-Created ProviderTransaction ─────────────────────────
          // Clean up any duplicate system-created ProviderTransaction that was
          // created during the refund (to prevent duplicate cash flow entries)
          try {
            const orgId = req.user?.orgId || null;
            const deleted = await ProviderTransaction.deleteMany({
              linkedRecordId:   creditNote._id,
              linkedRecordType: 'CreditNote',
              source:           'SYSTEM_ENTRY',
              journalRef:       refundId,
              ...(orgId ? { orgId } : {}),
            });
            console.log(`✅ [uncategorize] Deleted ${deleted.deletedCount} system-created ProviderTransaction(s) for CreditNote refund`);
          } catch (ptErr) {
            console.error('⚠️ [uncategorize] CreditNote system ProviderTransaction cleanup error:', ptErr.message);
          }
        }
      } catch (e) {
        console.error('⚠️ CreditNote refund reversal error:', e.message);
      }
      break;
    }

    default:
      await Expense.deleteMany({ providerTransactionId: txn._id, ...orgFilter(req) });
      break;
  }
}

module.exports = router;

// Export recomputeClosingBalance so it can be used by other routes if needed
module.exports.recomputeClosingBalance = recomputeClosingBalance;

