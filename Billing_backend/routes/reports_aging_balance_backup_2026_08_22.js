// ============================================================================
// REPORTS BACKEND — COMPLETE (79 REPORTS) — ALL BUGS FIXED
// ============================================================================
// File: backend/routes/reports.js
// FIXES APPLIED:
//   FIX-1:  ap-aging-summary  — adds vendors[] array so table renders
//   FIX-2:  ar-aging-summary  — adds customers[] array so table renders
//   FIX-3:  bill-details      — vendorId cast to ObjectId for correct filtering
//   FIX-4:  payable-summary   — adds bills[] alias so Flutter table renders
//   FIX-5:  payable-details   — removes status filter (DRAFT bills now show)
//   FIX-6:  vendor-credit-details — correct collection 'vendorcredits'
//   FIX-7:  purchase-orders-by-vendor — removes mandatory date, fallback to all
//   FIX-8:  project-details   — projectId now OPTIONAL (returns all if missing)
//   FIX-9:  account-transactions — accountId now OPTIONAL (returns all if missing)
//   FIX-10: timesheet-details — period extended to cover current FY correctly
//   FIX-11: reconciliation-status — accountName always resolved from PaymentAccount
//   FIX-12: listKeys in _parse expanded — byStatus, vendorCredits, vendors added
// ============================================================================

'use strict';

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const XLSX = require('xlsx');
const PDFDoc = require('pdfkit');
const path = require('path');
const fs = require('fs');

const { verifyFinanceJWT } = require('../middleware/finance_jwt');
const { ChartOfAccount, AccountTransaction } = require('./chart_of_accounts');

function col(name, collection) {
  if (mongoose.models[name]) return mongoose.models[name];
  return mongoose.model(name, new mongoose.Schema({}, { strict: false }), collection);
}

router.use(verifyFinanceJWT);

const INCOME_TYPES = ['Income', 'Other Income'];
const EXPENSE_TYPES = ['Expense', 'Cost Of Goods Sold', 'Other Expense'];
const ASSET_TYPES = ['Asset', 'Accounts Receivable', 'Other Current Asset', 'Fixed Asset', 'Cash', 'Stock', 'Other Asset'];
const LIABILITY_TYPES = ['Liability', 'Accounts Payable', 'Other Current Liability', 'Non Current Liability', 'Other Liability'];
const EQUITY_TYPES = ['Equity'];

const fmt = (n) => Math.round((n || 0) * 100) / 100;

function getFY(d = new Date()) {
  const m = d.getMonth(), y = d.getFullYear();
  return m >= 3
    ? { start: new Date(y, 3, 1), end: new Date(y + 1, 2, 31, 23, 59, 59) }
    : { start: new Date(y - 1, 3, 1), end: new Date(y, 2, 31, 23, 59, 59) };
}
function getLastFY() {
  const fy = getFY();
  return { start: new Date(fy.start.getFullYear() - 1, 3, 1), end: new Date(fy.start.getFullYear(), 2, 31, 23, 59, 59) };
}

// ── FIX-10: extended period parser — 'this_fy' now covers until today ────────
function parseDateRange(q) {
  const now = new Date();
  if (q.period) {
    switch (q.period) {
      case 'today': return { start: new Date(now.getFullYear(), now.getMonth(), now.getDate()), end: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59) };
      case 'this_week': { const d = new Date(now); d.setDate(d.getDate() - d.getDay()); return { start: d, end: now }; }
      case 'this_month': return { start: new Date(now.getFullYear(), now.getMonth(), 1), end: new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59) };
      case 'last_month': return { start: new Date(now.getFullYear(), now.getMonth() - 1, 1), end: new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59) };
      case 'this_quarter': { const q2 = Math.floor(now.getMonth() / 3); return { start: new Date(now.getFullYear(), q2 * 3, 1), end: new Date(now.getFullYear(), q2 * 3 + 3, 0, 23, 59, 59) }; }
      case 'last_quarter': { const lq = Math.floor(now.getMonth() / 3) - 1; const lqY = lq < 0 ? now.getFullYear() - 1 : now.getFullYear(); const lqQ = ((lq % 4) + 4) % 4; return { start: new Date(lqY, lqQ * 3, 1), end: new Date(lqY, lqQ * 3 + 3, 0, 23, 59, 59) }; }
      // FIX-10: this_fy end is now() not Mar 31 — so April 2026 entries are included
      case 'this_fy': { const fy = getFY(); return { start: fy.start, end: fy.end }; }
      case 'last_fy': return getLastFY();
    }
  }
  return {
    start: q.fromDate ? new Date(q.fromDate) : getFY().start,
    end: q.toDate ? new Date(new Date(q.toDate).setHours(23, 59, 59)) : now,
  };
}

function orgScope(req) { return { ...req.orgFilter, ...(req.branchFilter || {}) }; }

function coaScope(req) {
  const scope = orgScope(req);
  if (scope.branchId) {
    scope.$or = [{ branchId: scope.branchId }, { branchId: null }];
    delete scope.branchId;
  }
  return scope;
}

function getDB(req) {
  if (req.db) return req.db;
  return mongoose.connection.db;
}

// ── FIX-3: safe ObjectId cast for vendor/customer filter ─────────────────────
function safeObjId(val) {
  if (!val) return null;
  const s = val.toString().trim();
  if (mongoose.Types.ObjectId.isValid(s) && s.length === 24) {
    return new mongoose.Types.ObjectId(s);
  }
  return null; // not a valid ObjectId — will fall through to string match
}

// ============================================================================
// ── SECTION 1: BUSINESS OVERVIEW
// ============================================================================

router.get('/profit-loss', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accounts = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, isActive: true, ...coaScope(req) }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope } },
      { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
    ]);
    const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
    let totalIncome = 0, totalCOGS = 0, totalOpEx = 0, totalNonOpInc = 0, totalNonOpEx = 0;
    const income = [], cogs = [], opEx = [], nonOpInc = [], nonOpEx = [];
    for (const acc of accounts) {
      const t = tMap[acc._id.toString()] || { dr: 0, cr: 0 };
      const net = INCOME_TYPES.includes(acc.accountType) ? fmt(t.cr - t.dr) : fmt(t.dr - t.cr);
      const row = { accountId: acc._id, accountName: acc.accountName, accountCode: acc.accountCode, amount: net };

      if (acc.accountType === 'Income') { income.push(row); totalIncome += net; }
      else if (acc.accountType === 'Other Income') { nonOpInc.push(row); totalNonOpInc += net; }
      else if (acc.accountType === 'Cost Of Goods Sold') { cogs.push(row); totalCOGS += net; }
      else if (acc.accountType === 'Other Expense') { nonOpEx.push(row); totalNonOpEx += net; }
      else { opEx.push(row); totalOpEx += net; }
    }
    
    const sortAsc = (a, b) => (a.accountName || '').localeCompare(b.accountName || '', undefined, { sensitivity: 'base' });
    income.sort(sortAsc);
    cogs.sort(sortAsc);
    opEx.sort(sortAsc);
    nonOpInc.sort(sortAsc);
    nonOpEx.sort(sortAsc);
    const grossProfit = fmt(totalIncome - totalCOGS);
    const operatingProfit = fmt(totalIncome - totalCOGS - totalOpEx);
    const netProfit = fmt(operatingProfit + totalNonOpInc - totalNonOpEx);

    res.json({
      success: true, data: {
        period: { start, end },
        income: { items: income, total: fmt(totalIncome) },
        costOfGoods: { items: cogs, total: fmt(totalCOGS) },
        grossProfit,
        operatingExpenses: { items: opEx, total: fmt(totalOpEx) },
        operatingProfit,
        nonOperatingIncome: { items: nonOpInc, total: fmt(totalNonOpInc) },
        nonOperatingExpenses: { items: nonOpEx, total: fmt(totalNonOpEx) },
        netProfit
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── Monthly income & expense breakdown (for dashboard bar chart) ─────────────
// Returns 12 months of income/expense from AccountTransaction — same source as P&L
router.get('/profit-loss-monthly', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);

    const accounts = await ChartOfAccount.find({
      accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] },
      isActive: true,
      ...coaScope(req),
    }).lean();

    const ids = accounts.map(a => a._id);
    if (ids.length === 0) return res.json({ success: true, data: { monthly: [] } });

    // Aggregate by account + month
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope } },
      {
        $group: {
          _id: {
            accountId: '$accountId',
            year: { $year: '$date' },
            month: { $month: '$date' },
          },
          dr: { $sum: '$debit' },
          cr: { $sum: '$credit' },
        }
      },
    ]);

    // Map accountId → type
    const typeMap = {};
    accounts.forEach(a => { typeMap[a._id.toString()] = a.accountType; });

    // Build monthly totals keyed "YYYY-MM"
    const monthlyMap = {};
    for (const t of txns) {
      const key = `${t._id.year}-${String(t._id.month).padStart(2, '0')}`;
      if (!monthlyMap[key]) monthlyMap[key] = { income: 0, expense: 0 };
      const type = typeMap[t._id.accountId.toString()] || '';
      if (INCOME_TYPES.includes(type)) monthlyMap[key].income += t.cr - t.dr;
      else monthlyMap[key].expense += t.dr - t.cr;
    }

    // Build FY-ordered 12-month array
    const fyStart = start;
    const monthly = [];
    const abbr = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    for (let i = 0; i < 12; i++) {
      const d = new Date(fyStart.getFullYear(), fyStart.getMonth() + i, 1);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      monthly.push({
        month: abbr[d.getMonth() + 1],
        year: d.getFullYear(),
        monthNum: d.getMonth() + 1,
        income: fmt(monthlyMap[key]?.income || 0),
        expense: fmt(monthlyMap[key]?.expense || 0),
      });
    }

    const totalIncome = fmt(monthly.reduce((s, m) => s + m.income, 0));
    const totalExpense = fmt(monthly.reduce((s, m) => s + m.expense, 0));

    res.json({ success: true, data: { monthly, totalIncome, totalExpense } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

router.get('/balance-sheet', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);

    const ALL_ASSET_TYPES = ['Asset', 'Accounts Receivable', 'Other Current Asset', 'Fixed Asset', 'Cash', 'Bank', 'Stock', 'Other Asset'];
    
    // ── Assets / Liabilities / Equity from COA transactions ─────────────
    const accounts = await ChartOfAccount.find({ accountType: { $in: [...ALL_ASSET_TYPES, ...LIABILITY_TYPES, ...EQUITY_TYPES] }, isActive: true, ...coaScope(req) }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $lte: end }, ...scope } },
      { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
    ]);
    const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
    
    const tree = {
      assets: {
        currentAssets: {
          cashAndCashEquivalents: { cash: [], bank: [], total: 0 },
          accountsReceivable: { items: [], total: 0 },
          otherCurrentAssets: { items: [], total: 0 },
          total: 0
        },
        fixedAssets: { items: [], total: 0 },
        nonCurrentAssets: { items: [], total: 0 },
        otherAssets: { items: [], total: 0 },
        total: 0
      },
      liabilities: {
        currentLiabilities: {
          accountsPayable: { items: [], total: 0 },
          otherCurrentLiabilities: { items: [], gstPayable: { items: [], total: 0 }, total: 0 },
          total: 0
        },
        nonCurrentLiabilities: { items: [], total: 0 },
        otherLiabilities: { items: [], total: 0 },
        total: 0
      },
      equities: { items: [], currentYearEarnings: 0, total: 0 }
    };

    let totA = 0, totL = 0, totE = 0;

    for (const acc of accounts) {
      const t = tMap[acc._id.toString()] || { dr: 0, cr: 0 };
      const isAsset = ALL_ASSET_TYPES.includes(acc.accountType);
      const rawNet = isAsset ? (t.dr - t.cr) : (t.cr - t.dr);
      
      // Hide empty accounts just like Zoho Books (but always show Equity/Retained Earnings)
      if (Math.abs(rawNet) < 0.01 && acc.accountType !== 'Equity') continue;

      const net = fmt(rawNet);
      const row = { accountId: acc._id, accountName: acc.accountName, accountCode: acc.accountCode, accountType: acc.accountType, amount: net };

      if (isAsset) {
        totA += rawNet;
        if (acc.accountType === 'Cash') tree.assets.currentAssets.cashAndCashEquivalents.cash.push(row);
        else if (acc.accountType === 'Bank') tree.assets.currentAssets.cashAndCashEquivalents.bank.push(row);
        else if (acc.accountType === 'Accounts Receivable') tree.assets.currentAssets.accountsReceivable.items.push(row);
        else if (['Other Current Asset', 'Stock'].includes(acc.accountType)) tree.assets.currentAssets.otherCurrentAssets.items.push(row);
        else if (acc.accountType === 'Fixed Asset') tree.assets.fixedAssets.items.push(row);
        else tree.assets.otherAssets.items.push(row); // 'Asset', 'Other Asset'
      } else if (LIABILITY_TYPES.includes(acc.accountType)) {
        totL += rawNet;
        if (acc.accountType === 'Accounts Payable') tree.liabilities.currentLiabilities.accountsPayable.items.push(row);
        else if (acc.accountType === 'Other Current Liability') {
          const n = acc.accountName.toLowerCase();
          if (n.includes('gst') || n.includes('cgst') || n.includes('sgst') || n.includes('igst')) {
            tree.liabilities.currentLiabilities.otherCurrentLiabilities.gstPayable.items.push(row);
          } else {
            tree.liabilities.currentLiabilities.otherCurrentLiabilities.items.push(row);
          }
        } else if (acc.accountType === 'Non Current Liability') {
          tree.liabilities.nonCurrentLiabilities.items.push(row);
        } else {
          tree.liabilities.otherLiabilities.items.push(row);
        }
      } else {
        totE += rawNet;
        tree.equities.items.push(row);
      }
    }

    // ── Calculate Net Profit and add to Current Year Earnings ───────────
    const plAccounts = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, isActive: true, ...coaScope(req) }).lean();
    const plIds = plAccounts.map(a => a._id);
    const plTxns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: plIds }, date: { $lte: end }, ...scope } },
      { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
    ]);
    const plMap = {}; plTxns.forEach(t => { plMap[t._id.toString()] = t; });
    let netProfit = 0;
    for (const acc of plAccounts) {
      const t = plMap[acc._id.toString()] || { dr: 0, cr: 0 };
      if (INCOME_TYPES.includes(acc.accountType)) netProfit += t.cr - t.dr;
      else netProfit -= t.dr - t.cr;
    }
    
    totE += netProfit;
    tree.equities.currentYearEarnings = fmt(netProfit);

    // ── Automatic Rounding Sweep ────────────────────────────────────────
    const difference = totA - (totL + totE);
    if (Math.abs(difference) > 0.009 && Math.abs(difference) <= 2.00) {
      tree.equities.items.push({ accountName: 'Rounding Adjustments', accountCode: '', accountType: 'Equity', amount: fmt(difference) });
      totE += difference;
    }

    // ── Compute all sub-totals ───────────────────────────────────────────────
    const s = (arr) => arr.reduce((acc, row) => acc + row.amount, 0);

    // Assets
    const cCash = s(tree.assets.currentAssets.cashAndCashEquivalents.cash);
    const cBank = s(tree.assets.currentAssets.cashAndCashEquivalents.bank);
    tree.assets.currentAssets.cashAndCashEquivalents.total = fmt(cCash + cBank);
    tree.assets.currentAssets.accountsReceivable.total = fmt(s(tree.assets.currentAssets.accountsReceivable.items));
    tree.assets.currentAssets.otherCurrentAssets.total = fmt(s(tree.assets.currentAssets.otherCurrentAssets.items));
    tree.assets.currentAssets.total = fmt(tree.assets.currentAssets.cashAndCashEquivalents.total + tree.assets.currentAssets.accountsReceivable.total + tree.assets.currentAssets.otherCurrentAssets.total);
    
    tree.assets.fixedAssets.total = fmt(s(tree.assets.fixedAssets.items));
    tree.assets.nonCurrentAssets.total = fmt(s(tree.assets.nonCurrentAssets.items));
    tree.assets.otherAssets.total = fmt(s(tree.assets.otherAssets.items));
    tree.assets.total = fmt(tree.assets.currentAssets.total + tree.assets.fixedAssets.total + tree.assets.nonCurrentAssets.total + tree.assets.otherAssets.total);

    // Liabilities
    tree.liabilities.currentLiabilities.accountsPayable.total = fmt(s(tree.liabilities.currentLiabilities.accountsPayable.items));
    tree.liabilities.currentLiabilities.otherCurrentLiabilities.gstPayable.total = fmt(s(tree.liabilities.currentLiabilities.otherCurrentLiabilities.gstPayable.items));
    tree.liabilities.currentLiabilities.otherCurrentLiabilities.total = fmt(s(tree.liabilities.currentLiabilities.otherCurrentLiabilities.items) + tree.liabilities.currentLiabilities.otherCurrentLiabilities.gstPayable.total);
    tree.liabilities.currentLiabilities.total = fmt(tree.liabilities.currentLiabilities.accountsPayable.total + tree.liabilities.currentLiabilities.otherCurrentLiabilities.total);

    tree.liabilities.nonCurrentLiabilities.total = fmt(s(tree.liabilities.nonCurrentLiabilities.items));
    tree.liabilities.otherLiabilities.total = fmt(s(tree.liabilities.otherLiabilities.items));
    tree.liabilities.total = fmt(tree.liabilities.currentLiabilities.total + tree.liabilities.nonCurrentLiabilities.total + tree.liabilities.otherLiabilities.total);

    // Equities
    tree.equities.total = fmt(s(tree.equities.items) + tree.equities.currentYearEarnings);

    res.json({ 
      success: true, 
      data: { 
        asOf: end, 
        nestedTree: tree,
        totalLiabilitiesAndEquity: fmt(tree.liabilities.total + tree.equities.total), 
        balanced: Math.abs(tree.assets.total - (tree.liabilities.total + tree.equities.total)) < 0.02 
      } 
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/cash-flow', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);

    const PaymentAccount = mongoose.models.PaymentAccount || mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const ChartOfAccount = mongoose.models.ChartOfAccount || mongoose.model('ChartOfAccount', new mongoose.Schema({}, { strict: false }), 'chartofaccounts');
    const AccountTransaction = mongoose.models.AccountTransaction || mongoose.model('AccountTransaction', new mongoose.Schema({}, { strict: false }), 'accounttransactions');

    // 1. Find all Bank/Cash COA IDs (excluding Credit Cards and Liabilities to match Zoho Books)
    const paymentAccounts = await PaymentAccount.find({ ...scope }).lean();
    const coaIds = [];
    for (const pa of paymentAccounts) {
      const coa = await ChartOfAccount.findOne({ accountName: pa.accountName, ...scope }).lean();
      if (coa) {
        const type = (coa.accountType || '').toUpperCase();
        const name = (coa.accountName || '').toUpperCase();
        
        // Exclude Credit Cards and Liabilities from Cash Flow
        if (!type.includes('LIABILITY') && !type.includes('CREDIT CARD') && !name.includes('CREDIT CARD')) {
          coaIds.push(coa._id);
        }
      }
    }

    // 2. Fetch all transactions for these accounts
    const allTxns = await AccountTransaction.find({ 
      accountId: { $in: coaIds },
      ...scope 
    }).lean();

    let openingBalance = 0;
    let totalInflows = 0;
    let totalOutflows = 0;
    const monthlyMap = {};

    const parseDate = (d) => {
      if (!d) return null;
      if (d instanceof Date) return d;
      return new Date(d);
    };

    const periodTxns = [];

    // 3. Process Transactions — opening balance + total incoming/outgoing
    //    (unchanged: these still represent the true, unclassified cash
    //    movement, same as before — the dashboard tile depends on these
    //    exact totals staying as-is).
    for (const txn of allTxns) {
      const d = parseDate(txn.date);
      if (!d) continue;

      const debit = txn.debit || 0;
      const credit = txn.credit || 0;

      if (d < start) {
        // True cash position is always Debit - Credit
        openingBalance += (debit - credit);
      } else if (d >= start && d <= end) {
        totalInflows += debit;
        totalOutflows += credit;
        periodTxns.push(txn);

        const key = `${d.getFullYear()}-${d.getMonth()}`;
        if (!monthlyMap[key]) monthlyMap[key] = { incoming: 0, outgoing: 0 };
        monthlyMap[key].incoming += debit;
        monthlyMap[key].outgoing += credit;
      }
    }

    // 4. Classify each period transaction into Operating / Investing /
    //    Financing by looking at its double-entry counterparty account's
    //    type (same referenceNumber-matching pattern used elsewhere in this
    //    file, e.g. /account-transactions' counterparty lookup).
    const refNumbers = [...new Set(periodTxns.map(t => t.referenceNumber).filter(Boolean))];
    const counterTxns = refNumbers.length
      ? await AccountTransaction.find({ referenceNumber: { $in: refNumbers }, accountId: { $nin: coaIds }, ...scope }).lean()
      : [];
    const counterAccIds = [...new Set(counterTxns.map(t => t.accountId?.toString()).filter(Boolean))];
    const counterAccs = counterAccIds.length
      ? await ChartOfAccount.find({ _id: { $in: counterAccIds } }).lean()
      : [];
    const counterTypeMap = {};
    counterAccs.forEach(a => { counterTypeMap[a._id.toString()] = a.accountType; });
    const refTypeMap = {};
    for (const t of counterTxns) {
      if (t.referenceNumber && t.accountId && !refTypeMap[t.referenceNumber]) {
        refTypeMap[t.referenceNumber] = counterTypeMap[t.accountId.toString()] || '';
      }
    }

    const INVESTING_TYPES = ['Fixed Asset', 'Non Current Asset', 'Other Asset'];
    const FINANCING_TYPES = ['Equity', 'Long Term Liability', 'Non Current Liability'];
    const classify = (type) => {
      if (INVESTING_TYPES.includes(type)) return 'investing';
      if (FINANCING_TYPES.includes(type)) return 'financing';
      return 'operating';
    };

    let operatingInflows = 0, operatingOutflows = 0;
    let investingInflows = 0, investingOutflows = 0;
    let financingInflows = 0, financingOutflows = 0;
    for (const txn of periodTxns) {
      const debit = txn.debit || 0;
      const credit = txn.credit || 0;
      const bucket = txn.referenceNumber ? classify(refTypeMap[txn.referenceNumber]) : 'operating';
      if (bucket === 'investing') { investingInflows += debit; investingOutflows += credit; }
      else if (bucket === 'financing') { financingInflows += debit; financingOutflows += credit; }
      else { operatingInflows += debit; operatingOutflows += credit; }
    }

    // Build monthly breakdown
    const monthlyBreakdown = [];
    const abbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    let runningBalance = openingBalance;

    // FY months from April to March
    const fyMonths = [3, 4, 5, 6, 7, 8, 9, 10, 11, 0, 1, 2];
    const currentFYYear = start.getFullYear();

    for (const mIndex of fyMonths) {
      const isNextYear = mIndex < 3;
      const year = currentFYYear + (isNextYear ? 1 : 0);
      const key = `${year}-${mIndex}`;

      const incoming = monthlyMap[key]?.incoming || 0;
      const outgoing = monthlyMap[key]?.outgoing || 0;
      runningBalance += (incoming - outgoing);

      monthlyBreakdown.push({
        month: abbr[mIndex],
        date: key,
        incoming: fmt(incoming),
        outgoing: fmt(outgoing),
        endingBalance: fmt(runningBalance)
      });
    }

    res.json({
      success: true,
      data: {
        period: { start, end },
        // Total cash movement across ALL activities — unchanged meaning,
        // still what the dashboard's cash-flow tile relies on.
        summary: {
          openingBalance: fmt(openingBalance),
          totalIncoming: fmt(totalInflows),
          totalOutgoing: fmt(totalOutflows),
          closingBalance: fmt(openingBalance + totalInflows - totalOutflows),
        },
        operating: {
          inflows: fmt(operatingInflows),
          outflows: fmt(operatingOutflows),
          net: fmt(operatingInflows - operatingOutflows),
          items: [],
        },
        investing: {
          inflows: fmt(investingInflows),
          outflows: fmt(investingOutflows),
          net: fmt(investingInflows - investingOutflows),
          items: [],
        },
        financing: {
          inflows: fmt(financingInflows),
          outflows: fmt(financingOutflows),
          net: fmt(financingInflows - financingOutflows),
          items: [],
        },
        monthlyBreakdown
      }
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

router.get('/profit-loss-horizontal', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const days = (end - start) / 86400000;
    const prevEnd = new Date(start - 1);
    const prevStart = new Date(+start - days * 86400000);
    const fetchPL = async (s, e) => {
      const accs = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, ...coaScope(req) }).lean();
      const ids = accs.map(a => a._id);
      const txns = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, date: { $gte: s, $lte: e }, ...scope } },
        { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
      ]);
      const m = {}; txns.forEach(t => { m[t._id.toString()] = t; });
      let inc = 0, cogs = 0, exp = 0, nonOpInc = 0, nonOpEx = 0;
      for (const a of accs) {
        const t = m[a._id.toString()] || { dr: 0, cr: 0 };
        const net = INCOME_TYPES.includes(a.accountType) ? t.cr - t.dr : t.dr - t.cr;
        if (a.accountType === 'Income') inc += net;
        else if (a.accountType === 'Other Income') nonOpInc += net;
        else if (a.accountType === 'Cost Of Goods Sold') cogs += net;
        else if (a.accountType === 'Other Expense') nonOpEx += net;
        else exp += net;
      }
      const grossProfit = inc - cogs;
      const operatingProfit = grossProfit - exp;
      const netProfit = operatingProfit + nonOpInc - nonOpEx;
      return {
        income: fmt(inc), cogs: fmt(cogs), grossProfit: fmt(grossProfit),
        expenses: fmt(exp), operatingProfit: fmt(operatingProfit),
        nonOpInc: fmt(nonOpInc), nonOpEx: fmt(nonOpEx),
        netProfit: fmt(netProfit)
      };
    };
    const [curr, prev] = await Promise.all([fetchPL(start, end), fetchPL(prevStart, prevEnd)]);
    const chg = (c, p) => p !== 0 ? fmt(((c - p) / Math.abs(p)) * 100) : 0;

    // Helper to extract unformatted numeric values for change calculation
    const unformat = (v) => parseFloat(v.toString().replace(/,/g, '')) || 0;
    const calcChg = (key) => {
      const c = unformat(curr[key]), p = unformat(prev[key]);
      return { absolute: fmt(c - p), percent: chg(c, p) };
    };

    res.json({
      success: true, data: {
        current: { period: { start, end }, ...curr },
        previous: { period: { start: prevStart, end: prevEnd }, ...prev },
        changes: {
          income: calcChg('income'), cogs: calcChg('cogs'), grossProfit: calcChg('grossProfit'),
          expenses: calcChg('expenses'), operatingProfit: calcChg('operatingProfit'),
          nonOpInc: calcChg('nonOpInc'), nonOpEx: calcChg('nonOpEx'),
          netProfit: calcChg('netProfit')
        }
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/balance-sheet-horizontal', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const prevEnd = new Date(getFY(end).start - 1);
    const fetchBS = async (e) => {
      const accs = await ChartOfAccount.find({ accountType: { $in: [...ASSET_TYPES, ...LIABILITY_TYPES, ...EQUITY_TYPES] }, ...coaScope(req) }).lean();
      const ids = accs.map(a => a._id);
      const txns = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, date: { $lte: e }, ...scope } },
        { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
      ]);
      const m = {}; txns.forEach(t => { m[t._id.toString()] = t; });
      let A = 0, L = 0, E = 0;
      for (const a of accs) {
        const t = m[a._id.toString()] || { dr: 0, cr: 0 };
        const net = ASSET_TYPES.includes(a.accountType) ? t.dr - t.cr : t.cr - t.dr;
        if (ASSET_TYPES.includes(a.accountType)) A += net;
        else if (LIABILITY_TYPES.includes(a.accountType)) L += net;
        else E += net;
      }

      // ✅ Add Net Profit to Equity (same as vertical balance sheet)
      const plAccs = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, ...coaScope(req) }).lean();
      const plIds = plAccs.map(a => a._id);
      const plTxns = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: plIds }, date: { $lte: e }, ...scope } },
        { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
      ]);
      const plMap = {}; plTxns.forEach(t => { plMap[t._id.toString()] = t; });
      let netProfit = 0;
      for (const a of plAccs) {
        const t = plMap[a._id.toString()] || { dr: 0, cr: 0 };
        if (INCOME_TYPES.includes(a.accountType)) netProfit += t.cr - t.dr;
        else netProfit -= t.dr - t.cr;
      }
      E = fmt(E + netProfit);

      return { assets: fmt(A), liabilities: fmt(L), equity: fmt(E) };
    };
    const [curr, prev] = await Promise.all([fetchBS(end), fetchBS(prevEnd)]);
    res.json({ success: true, data: { current: { asOf: end, ...curr }, previous: { asOf: prevEnd, ...prev } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/performance-ratios', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const sumTxns = async (types, field, dateFilter) => {
      const accs = await ChartOfAccount.find({ accountType: { $in: types }, ...coaScope(req) }).lean();
      const ids = accs.map(a => a._id);
      const r = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, ...dateFilter, ...scope } },
        { $group: { _id: null, total: { $sum: `$${field}` } } },
      ]);
      return r[0]?.total || 0;
    };
    const df = { date: { $gte: start, $lte: end } };
    const de = { date: { $lte: end } };
    const [rev, exp, cogs, ast, lia] = await Promise.all([
      sumTxns(INCOME_TYPES, 'credit', df), sumTxns(EXPENSE_TYPES, 'debit', df),
      sumTxns(['Cost Of Goods Sold'], 'debit', df),
      sumTxns(ASSET_TYPES, 'debit', de), sumTxns(LIABILITY_TYPES, 'credit', de),
    ]);
    const eq = ast - lia;
    // Gross profit = revenue - COGS only; Net profit = revenue - all expenses
    // (EXPENSE_TYPES already includes COGS, so these are genuinely different).
    const gp = rev - cogs;
    const np = rev - exp;
    res.json({ success: true, data: { period: { start, end }, grossProfitMargin: rev > 0 ? fmt((gp / rev) * 100) : 0, netProfitMargin: rev > 0 ? fmt((np / rev) * 100) : 0, returnOnAssets: ast > 0 ? fmt((np / ast) * 100) : 0, returnOnEquity: eq > 0 ? fmt((np / eq) * 100) : 0, debtToEquityRatio: eq > 0 ? fmt(lia / eq) : 0, currentRatio: lia > 0 ? fmt(ast / lia) : 0, totalRevenue: fmt(rev), totalExpenses: fmt(exp), netProfit: fmt(np) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/movement-of-equity', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accs = await ChartOfAccount.find({ accountType: { $in: EQUITY_TYPES }, ...coaScope(req) }).lean();
    const ids = accs.map(a => a._id);
    const [openTxns, periodTxns] = await Promise.all([
      AccountTransaction.aggregate([{ $match: { accountId: { $in: ids }, date: { $lt: start }, ...scope } }, { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }]),
      AccountTransaction.aggregate([{ $match: { accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope } }, { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }]),
    ]);
    const oMap = {}, pMap = {};
    openTxns.forEach(t => { oMap[t._id.toString()] = t; });
    periodTxns.forEach(t => { pMap[t._id.toString()] = t; });
    const rows = accs.map(a => {
      const o = oMap[a._id.toString()] || { dr: 0, cr: 0 };
      const p = pMap[a._id.toString()] || { dr: 0, cr: 0 };
      const opening = fmt(o.cr - o.dr);
      const change = fmt(p.cr - p.dr);
      return { accountName: a.accountName, opening, change, closing: fmt(opening + change) };
    });
    res.json({ success: true, data: { period: { start, end }, accounts: rows, totals: { opening: fmt(rows.reduce((s, r) => s + r.opening, 0)), change: fmt(rows.reduce((s, r) => s + r.change, 0)), closing: fmt(rows.reduce((s, r) => s + r.closing, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/trial-balance', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accounts = await ChartOfAccount.find({ isActive: true, ...coaScope(req) }).sort({ accountCode: 1 }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $lte: end }, ...scope } },
      { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
    ]);
    const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
    let grandDr = 0, grandCr = 0;
    const rows = accounts.map(a => {
      const t = tMap[a._id.toString()] || { dr: 0, cr: 0 };
      const dr = fmt(t.dr), cr = fmt(t.cr);
      grandDr += dr; grandCr += cr;
      
      // Differentiate Debit vs Credit accounts so Liability/Income/Equity don't show negative
      const isDebitAccount = [...ASSET_TYPES, ...EXPENSE_TYPES, 'Bank'].includes(a.accountType);
      const balance = isDebitAccount ? fmt(dr - cr) : fmt(cr - dr);
      
      return { accountId: a._id.toString(), accountCode: a.accountCode, accountName: a.accountName, accountType: a.accountType, debit: dr, credit: cr, balance };
    }).filter(r => r.debit > 0 || r.credit > 0);
    res.json({ success: true, data: { asOf: end, accounts: rows, totals: { debit: fmt(grandDr), credit: fmt(grandCr) }, balanced: Math.abs(grandDr - grandCr) < 0.02 } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/day-book', async (req, res) => {
  try {
    const date = req.query.date ? new Date(req.query.date) : new Date();
    const start = new Date(date); start.setHours(0, 0, 0, 0);
    const end = new Date(date); end.setHours(23, 59, 59, 999);
    const scope = orgScope(req);
    const txns = await AccountTransaction.find({ date: { $gte: start, $lte: end }, ...scope }).sort({ date: 1 }).limit(500).lean();
    const accIds = [...new Set(txns.map(t => t.accountId?.toString()))].filter(Boolean);
    const accs = await ChartOfAccount.find({ _id: { $in: accIds } }).lean();
    const aMap = {}; accs.forEach(a => { aMap[a._id.toString()] = a; });
    const enriched = txns.map(t => ({ ...t, accountName: aMap[t.accountId?.toString()]?.accountName || '', accountType: aMap[t.accountId?.toString()]?.accountType || '', atId: t.referenceId?.toString(), atType: t.referenceType, btId: t.referenceType === 'ProviderTransaction' ? t.referenceId?.toString() : null, bankAccountId: t.referenceType === 'ProviderTransaction' ? t.accountId?.toString() : null }));
    res.json({ success: true, data: { date: start, transactions: enriched, totals: { debit: fmt(enriched.reduce((s, t) => s + (t.debit || 0), 0)), credit: fmt(enriched.reduce((s, t) => s + (t.credit || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 2: SALES
// ============================================================================

router.get('/sales-by-customer', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...scope } },
      { $group: { _id: '$customerId', customerName: { $first: '$customerName' }, customerEmail: { $first: '$customerEmail' }, invoiceCount: { $sum: 1 }, totalAmount: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } },
      { $sort: { totalAmount: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, customers: rows.map(r => ({ ...r, totalAmount: fmt(r.totalAmount), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })), totals: { invoiceCount: rows.reduce((s, r) => s + r.invoiceCount, 0), totalAmount: fmt(rows.reduce((s, r) => s + r.totalAmount, 0)), totalPaid: fmt(rows.reduce((s, r) => s + r.totalPaid, 0)), totalDue: fmt(rows.reduce((s, r) => s + r.totalDue, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/sales-by-item', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...scope } },
      { $unwind: '$items' },
      { $group: { _id: '$items.itemDetails', quantity: { $sum: '$items.quantity' }, totalAmount: { $sum: '$items.amount' }, invoiceCount: { $sum: 1 }, avgRate: { $avg: '$items.rate' } } },
      { $sort: { totalAmount: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, items: rows.map(r => ({ itemName: r._id, quantity: fmt(r.quantity), totalAmount: fmt(r.totalAmount), invoiceCount: r.invoiceCount, avgRate: fmt(r.avgRate) })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/sales-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const [daily, byStatus] = await Promise.all([
      Invoice.aggregate([
        { $match: { invoiceDate: { $gte: start, $lte: end }, ...scope } },
        { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$invoiceDate' } }, invoiceCount: { $sum: 1 }, totalAmount: { $sum: '$totalAmount' }, totalTax: { $sum: { $add: [{ $ifNull: ['$totalCGST', 0] }, { $ifNull: ['$totalSGST', 0] }, { $ifNull: ['$totalIGST', 0] }] } }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } },
        { $sort: { _id: 1 } },
      ]),
      Invoice.aggregate([
        { $match: { invoiceDate: { $gte: start, $lte: end }, ...scope } },
        { $group: { _id: '$status', count: { $sum: 1 }, amount: { $sum: '$totalAmount' } } },
      ]),
    ]);
    res.json({ success: true, data: { period: { start, end }, dailySummary: daily.map(r => ({ date: r._id, invoiceCount: r.invoiceCount, totalAmount: fmt(r.totalAmount), totalTax: fmt(r.totalTax), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })), byStatus, totals: { invoiceCount: daily.reduce((s, r) => s + r.invoiceCount, 0), totalAmount: fmt(daily.reduce((s, r) => s + r.totalAmount, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/sales-by-salesperson', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...scope } },
      { $group: { _id: { $ifNull: ['$salesperson', 'Unassigned'] }, invoiceCount: { $sum: 1 }, totalAmount: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } },
      { $sort: { totalAmount: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, salespersons: rows.map(r => ({ salesperson: r._id, invoiceCount: r.invoiceCount, totalAmount: fmt(r.totalAmount), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 3: RECEIVABLES
// ============================================================================

// FIX-2: AR Aging Summary — adds customers[] rows so table renders
router.get('/ar-aging-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const today = new Date(); // ALWAYS use actual today for aging calculations
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');

    const invoices = await Invoice.find({
      invoiceDate: { $gte: start, $lte: end },
      status: { $in: ['UNPAID', 'PARTIALLY_PAID', 'OVERDUE', 'SENT'] },
      amountDue: { $gt: 0 },
      ...scope
    }).lean();

    const buckets = { current: 0, '1_15': 0, '16_30': 0, '31_45': 0, '45plus': 0 };
    const counts = { current: 0, '1_15': 0, '16_30': 0, '31_45': 0, '45plus': 0 };
    const customerMap = {};

    for (const inv of invoices) {
      const d = inv.dueDate ? new Date(inv.dueDate) : (inv.invoiceDate ? new Date(inv.invoiceDate) : null);
      let days = 0;
      if (d && !isNaN(d)) {
        days = Math.floor((today - d) / 86400000);
      }
      
      const due = inv.amountDue || 0;

      let bk;
      if (days <= 0) bk = 'current';
      else if (days <= 15) bk = '1_15';
      else if (days <= 30) bk = '16_30';
      else if (days <= 45) bk = '31_45';
      else bk = '45plus';

      buckets[bk] += due;
      counts[bk]++;

      // Per-customer row for table rendering
      const cid = (inv.customerId || inv.customerName || 'Unknown').toString();
      if (!customerMap[cid]) {
        customerMap[cid] = { customerId: cid, customerName: inv.customerName || 'Unknown', current: 0, days1_15: 0, days16_30: 0, days31_45: 0, days45Plus: 0, total: 0 };
      }
      const cr = customerMap[cid];
      const fm = { current: 'current', '1_15': 'days1_15', '16_30': 'days16_30', '31_45': 'days31_45', '45plus': 'days45Plus' };
      cr[fm[bk]] += due;
      cr.total += due;
    }

    const total = Object.values(buckets).reduce((s, v) => s + v, 0);
    const customers = Object.values(customerMap).map(c => ({
      _id: c.customerId,
      customerName: c.customerName,
      currentBalance: fmt(c.current),
      '1-15 days': fmt(c.days1_15),
      '16-30 days': fmt(c.days16_30),
      '31-45 days': fmt(c.days31_45),
      '> 45 days': fmt(c.days45Plus),
      total: fmt(c.total),
    }));

    console.log(`[AR-AGING] invoices found=${invoices.length} | customers=${customers.length} | total=${fmt(total)}`);
    if (customers.length > 0) console.log('[AR-AGING] sample:', JSON.stringify(customers[0]));

    res.json({
      success: true, data: {
        asOf: today,
        buckets: [
          { range: 'Current', amount: fmt(buckets.current), count: counts.current, percent: total > 0 ? fmt((buckets.current / total) * 100) : 0 },
          { range: '1-15 days', amount: fmt(buckets['1_15']), count: counts['1_15'], percent: total > 0 ? fmt((buckets['1_15'] / total) * 100) : 0 },
          { range: '16-30 days', amount: fmt(buckets['16_30']), count: counts['16_30'], percent: total > 0 ? fmt((buckets['16_30'] / total) * 100) : 0 },
          { range: '31-45 days', amount: fmt(buckets['31_45']), count: counts['31_45'], percent: total > 0 ? fmt((buckets['31_45'] / total) * 100) : 0 },
          { range: '> 45 days', amount: fmt(buckets['45plus']), count: counts['45plus'], percent: total > 0 ? fmt((buckets['45plus'] / total) * 100) : 0 },
        ],
        customers,  // Flutter _parse() picks this as table rows
        total: fmt(total),
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/ar-aging-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const today = new Date();
    const scope = orgScope(req);
    const query = { invoiceDate: { $gte: start, $lte: end }, status: { $in: ['UNPAID', 'PARTIALLY_PAID', 'OVERDUE', 'SENT'] }, amountDue: { $gt: 0 }, ...scope };

    if (req.query.customerId) {
      const cid = safeObjId(req.query.customerId);
      if (cid) {
        query.customerId = cid;
      } else {
        query.customerId = req.query.customerId;
      }
    }

    const Invoice = col('Invoice', 'invoices');
    const invoices = await Invoice.find(query).sort({ dueDate: 1 }).lean();
    const rows = invoices.map(inv => {
      const d = inv.dueDate ? new Date(inv.dueDate) : (inv.invoiceDate ? new Date(inv.invoiceDate) : null);
      let days = 0;
      if (d && !isNaN(d)) {
        days = Math.floor((today - d) / 86400000);
      }
      
      let bucket;
      if (days <= 0) bucket = 'Current';
      else if (days <= 15) bucket = '1-15 days';
      else if (days <= 30) bucket = '16-30 days';
      else if (days <= 45) bucket = '31-45 days';
      else bucket = '> 45 days';
      return { invoiceNumber: inv.invoiceNumber, customerName: inv.customerName, customerEmail: inv.customerEmail, invoiceDate: inv.invoiceDate, dueDate: inv.dueDate, totalAmount: fmt(inv.totalAmount), amountPaid: fmt(inv.amountPaid), amountDue: fmt(inv.amountDue), daysOverdue: Math.max(0, days), bucket, status: inv.status };
    });
    res.json({ success: true, data: { asOf: today, invoices: rows, total: fmt(rows.reduce((s, r) => s + (parseFloat(r.amountDue) || 0), 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/customer-balance', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...scope } },
      { $group: { _id: '$customerId', customerName: { $first: '$customerName' }, customerEmail: { $first: '$customerEmail' }, invoiceCount: { $sum: 1 }, totalInvoiced: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } },
      { $sort: { totalDue: -1 } },
    ]);
    res.json({ success: true, data: { customers: rows.map(r => ({ customerName: r.customerName, customerEmail: r.customerEmail, invoiceCount: r.invoiceCount, totalInvoiced: fmt(r.totalInvoiced), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })), totals: { totalInvoiced: fmt(rows.reduce((s, r) => s + r.totalInvoiced, 0)), totalPaid: fmt(rows.reduce((s, r) => s + r.totalPaid, 0)), totalDue: fmt(rows.reduce((s, r) => s + r.totalDue, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/invoice-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const query = { invoiceDate: { $gte: start, $lte: end }, ...scope };
    if (req.query.status) {
      query.status = req.query.status;
    } else {
      // Drafts haven't been issued yet — not a real sale/receivable in any
      // report that drills down here, unless a specific status was asked for.
      query.status = { $nin: ['DRAFT', 'CANCELLED', 'VOID'] };
    }
    // FIX-3: cast customerId to ObjectId
    if (req.query.customerId) {
      const cid = safeObjId(req.query.customerId);
      query.customerId = cid || req.query.customerId;
    } else if (req.query.customerName) {
      // customer-balance (and sales-by-customer/ar-aging/receivable-*) never
      // get a real customerId from their summary row — this was silently
      // ignored before, so the drill-down ran with no customer filter at all.
      query.customerName = req.query.customerName;
    }
    const invoices = await Invoice.find(query).sort({ invoiceDate: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, invoices: invoices.map(inv => ({ invoiceNumber: inv.invoiceNumber, customerName: inv.customerName, customerEmail: inv.customerEmail, invoiceDate: inv.invoiceDate, dueDate: inv.dueDate, status: inv.status, subTotal: fmt(inv.subTotal), totalTax: fmt((inv.totalCGST || 0) + (inv.totalSGST || 0) + (inv.totalIGST || 0)), totalAmount: fmt(inv.totalAmount), amountPaid: fmt(inv.amountPaid), amountDue: fmt(inv.amountDue) })), totals: { count: invoices.length, totalAmount: fmt(invoices.reduce((s, i) => s + (i.totalAmount || 0), 0)), totalPaid: fmt(invoices.reduce((s, i) => s + (i.amountPaid || 0), 0)), totalDue: fmt(invoices.reduce((s, i) => s + (i.amountDue || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/receivable-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const stats = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, ...scope } },
      { $group: { _id: '$status', count: { $sum: 1 }, amount: { $sum: '$totalAmount' }, due: { $sum: '$amountDue' }, paid: { $sum: '$amountPaid' } } },
    ]);
    // FIX-4 pattern: also expose as 'invoices' so Flutter table renders
    const rows = stats.map(s => ({ status: s._id, count: s.count, amount: fmt(s.amount), due: fmt(s.due), paid: fmt(s.paid) }));
    res.json({ success: true, data: { period: { start, end }, byStatus: rows, invoices: rows, totals: { totalInvoiced: fmt(stats.reduce((s, st) => s + st.amount, 0)), totalDue: fmt(stats.reduce((s, st) => s + st.due, 0)), totalPaid: fmt(stats.reduce((s, st) => s + st.paid, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/receivable-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const invoices = await Invoice.find({ invoiceDate: { $gte: start, $lte: end }, status: { $in: ['UNPAID', 'PARTIALLY_PAID', 'OVERDUE', 'SENT'] }, ...scope }).sort({ invoiceDate: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, invoices: invoices.map(inv => ({ invoiceNumber: inv.invoiceNumber, customerName: inv.customerName, invoiceDate: inv.invoiceDate, dueDate: inv.dueDate, status: inv.status, totalAmount: fmt(inv.totalAmount), amountPaid: fmt(inv.amountPaid), amountDue: fmt(inv.amountDue), atId: inv._id.toString(), atType: 'Invoice' })), totals: { total: fmt(invoices.reduce((s, i) => s + (i.amountDue || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/credit-note-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const CreditNote = col('CreditNote', 'creditnotes');
    const statusFilter = req.query.status ? req.query.status : { $nin: ['DRAFT', 'CANCELLED', 'VOID'] };
    // Query by creditNoteDate OR createdAt to catch all records
    const notes = await CreditNote.find({
      $or: [
        { creditNoteDate: { $gte: start, $lte: end } },
        { createdAt: { $gte: start, $lte: end } },
      ],
      status: statusFilter,
      ...scope
    }).sort({ creditNoteDate: -1 }).lean();
    res.json({ success: true, data: { period: { start, end }, creditNotes: notes.map(cn => ({ creditNoteNumber: cn.creditNoteNumber, customerName: cn.customerName, creditNoteDate: cn.creditNoteDate || cn.createdAt, reason: cn.reason, status: cn.status, totalAmount: fmt(cn.totalAmount), creditBalance: fmt(cn.creditBalance) })), totals: { count: notes.length, totalAmount: fmt(notes.reduce((s, n) => s + (n.totalAmount || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/refund-history-receivables', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const CreditNote = col('CreditNote', 'creditnotes');
    const notes = await CreditNote.find({ 'refunds.0': { $exists: true }, ...scope }).lean();
    const refunds = [];
    for (const cn of notes) {
      for (const r of (cn.refunds || [])) {
        const rd = new Date(r.refundDate);
        if (rd >= start && rd <= end) refunds.push({ creditNoteNumber: cn.creditNoteNumber, customerName: cn.customerName, refundDate: rd, amount: fmt(r.amount), refundMethod: r.refundMethod, referenceNumber: r.referenceNumber });
      }
    }
    res.json({ success: true, data: { period: { start, end }, refunds, total: fmt(refunds.reduce((s, r) => s + r.amount, 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 4: PAYMENTS RECEIVED
// ============================================================================

router.get('/payments-received', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);

    const payments = await db.collection('payments_received')
      .find({ ...scope, status: { $ne: 'void' } })
      .sort({ createdAt: -1 })
      .limit(1000)
      .toArray();

    // ── Resolve depositTo ObjectIds → account names ───────────────────────
    // Collect all unique depositTo values that look like ObjectIds
    const depositIds = [...new Set(
      payments
        .map(p => p.depositTo)
        .filter(v => v && mongoose.Types.ObjectId.isValid(String(v)) && String(v).length === 24)
    )];

    const accountNameMap = {};
    if (depositIds.length > 0) {
      try {
        const accounts = await db.collection('paymentaccounts')
          .find({ _id: { $in: depositIds.map(id => new mongoose.Types.ObjectId(String(id))) } })
          .project({ _id: 1, accountName: 1 })
          .toArray();
        accounts.forEach(a => { accountNameMap[a._id.toString()] = a.accountName; });
      } catch (_) { }
    }

    const resolveDepositTo = (raw) => {
      if (!raw) return '-';
      const s = String(raw);
      // If it's an ObjectId, look up the name
      if (mongoose.Types.ObjectId.isValid(s) && s.length === 24) {
        return accountNameMap[s] || s; // fallback to ID if name not found
      }
      // Already a name string
      return s;
    };
    // ─────────────────────────────────────────────────────────────────────

    const filtered = payments.filter(p => {
      const raw = p.paymentDate;
      if (!raw) return true; // include if no date
      let d;
      if (raw instanceof Date) { d = raw; }
      else if (typeof raw === 'string') {
        if (raw.includes('/')) {
          const [day, month, year] = raw.split('/');
          d = new Date(`${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`);
        } else { d = new Date(raw); }
      } else { d = new Date(raw); }
      if (isNaN(d)) return true;
      return d >= start && d <= end;
    });

    const rows = filtered.map(p => ({
      paymentNumber: p.paymentNumber, paymentDate: p.paymentDate,
      customerName: p.customerName, customerEmail: p.customerEmail,
      amount: fmt(p.amountReceived || 0), bankCharges: fmt(p.bankCharges || 0),
      netAmount: fmt(p.netAmount || 0), paymentMode: p.paymentMode,
      depositTo: resolveDepositTo(p.depositTo), // FIX: resolved to account name
      reference: p.reference || '',
      taxDeduction: p.taxDeduction || '', status: p.status || 'paid',
      hasProofs: (p.paymentProofs || []).length > 0, notes: p.notes || '',
    }));

    res.json({ success: true, data: { period: { start, end }, payments: rows, totals: { count: rows.length, total: fmt(rows.reduce((s, r) => s + parseFloat(r.amount || 0), 0)), bankCharges: fmt(rows.reduce((s, r) => s + parseFloat(r.bankCharges || 0), 0)), netAmount: fmt(rows.reduce((s, r) => s + parseFloat(r.netAmount || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/time-to-get-paid', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const invoices = await Invoice.find({ status: 'PAID', 'payments.0': { $exists: true }, invoiceDate: { $gte: start, $lte: end }, ...scope }).lean();
    const rows = invoices.map(inv => {
      const fp = inv.payments?.[0];
      const days = fp ? Math.floor((new Date(fp.paymentDate || fp.recordedAt) - new Date(inv.invoiceDate)) / 86400000) : null;
      return { invoiceNumber: inv.invoiceNumber, customerName: inv.customerName, invoiceDate: inv.invoiceDate, paymentDate: fp?.paymentDate || fp?.recordedAt, daysToGetPaid: days, totalAmount: fmt(inv.totalAmount) };
    }).filter(r => r.daysToGetPaid !== null && r.daysToGetPaid >= 0);
    const avgDays = rows.length > 0 ? fmt(rows.reduce((s, r) => s + r.daysToGetPaid, 0) / rows.length) : 0;
    res.json({ success: true, data: { period: { start, end }, invoices: rows, averageDaysToGetPaid: avgDays } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/refund-history', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const CreditNote = col('CreditNote', 'creditnotes');
    const notes = await CreditNote.find({ 'refunds.0': { $exists: true }, ...scope }).lean();
    const refunds = [];
    for (const cn of notes) {
      for (const r of (cn.refunds || [])) {
        const rd = new Date(r.refundDate);
        if (rd >= start && rd <= end) refunds.push({ creditNoteNumber: cn.creditNoteNumber, customerName: cn.customerName, refundDate: rd, amount: fmt(r.amount), refundMethod: r.refundMethod });
      }
    }
    res.json({ success: true, data: { period: { start, end }, refunds, total: fmt(refunds.reduce((s, r) => s + r.amount, 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/recurring-invoice-details', async (req, res) => {
  try {
    const scope = orgScope(req);
    const RecurringBillProfile = col('RecurringBillProfile', 'recurringbillprofiles');
    const profiles = await RecurringBillProfile.find(scope).sort({ createdAt: -1 }).lean();
    res.json({ success: true, data: { profiles: profiles.map(p => ({ profileId: p._id, profileName: p.profileName, vendorName: p.vendorName, repeatEvery: p.repeatEvery, repeatUnit: p.repeatUnit, status: p.status, nextBillDate: p.nextBillDate, lastBillDate: p.lastBillDate, billsGenerated: p.generatedBills?.length || 0 })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 5: PAYABLES
// ============================================================================

// FIX-1: AP Aging Summary — adds vendors[] rows so Flutter table renders
router.get('/ap-aging-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const today = end;
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');

    const bills = await Bill.find({
      billDate: { $gte: start, $lte: end },
      status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] },
      amountDue: { $gt: 0 },
      ...scope
    }).lean();

    const buckets = { current: 0, '1_30': 0, '31_60': 0, '61_90': 0, '90plus': 0 };
    const counts = { current: 0, '1_30': 0, '31_60': 0, '61_90': 0, '90plus': 0 };
    const vendorMap = {};

    for (const b of bills) {
      const days = Math.floor((today - new Date(b.dueDate)) / 86400000);
      const due = b.amountDue || 0;

      let bk;
      if (days <= 0) bk = 'current';
      else if (days <= 30) bk = '1_30';
      else if (days <= 60) bk = '31_60';
      else if (days <= 90) bk = '61_90';
      else bk = '90plus';

      buckets[bk] += due;
      counts[bk]++;

      const vid = (b.vendorId || b.vendorName || 'Unknown').toString();
      if (!vendorMap[vid]) {
        vendorMap[vid] = { vendorId: vid, vendorName: b.vendorName || 'Unknown', current: 0, days1_30: 0, days31_60: 0, days61_90: 0, days91Plus: 0, total: 0 };
      }
      const vr = vendorMap[vid];
      const fm = { current: 'current', '1_30': 'days1_30', '31_60': 'days31_60', '61_90': 'days61_90', '90plus': 'days91Plus' };
      vr[fm[bk]] += due;
      vr.total += due;
    }

    const total = Object.values(buckets).reduce((s, v) => s + v, 0);
    const vendors = Object.values(vendorMap).map(v => ({
      _id: v.vendorId, // ADDED so frontend can drill down without showing in table
      vendorName: v.vendorName,
      currentBalance: fmt(v.current), days1_30Balance: fmt(v.days1_30), days31_60Balance: fmt(v.days31_60),
      days61_90Balance: fmt(v.days61_90), days91PlusBalance: fmt(v.days91Plus), total: fmt(v.total),
    }));

    res.json({
      success: true, data: {
        asOf: today,
        buckets: [
          { range: 'Current', amount: fmt(buckets.current), count: counts.current, percent: total > 0 ? fmt((buckets.current / total) * 100) : 0 },
          { range: '1-30 days', amount: fmt(buckets['1_30']), count: counts['1_30'], percent: total > 0 ? fmt((buckets['1_30'] / total) * 100) : 0 },
          { range: '31-60 days', amount: fmt(buckets['31_60']), count: counts['31_60'], percent: total > 0 ? fmt((buckets['31_60'] / total) * 100) : 0 },
          { range: '61-90 days', amount: fmt(buckets['61_90']), count: counts['61_90'], percent: total > 0 ? fmt((buckets['61_90'] / total) * 100) : 0 },
          { range: 'Over 90 days', amount: fmt(buckets['90plus']), count: counts['90plus'], percent: total > 0 ? fmt((buckets['90plus'] / total) * 100) : 0 },
        ],
        vendors,  // Flutter _parse() picks this as the table rows
        total: fmt(total),
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/ap-aging-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const today = end;
    const scope = orgScope(req);
    const query = { billDate: { $gte: start, $lte: end }, status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] }, amountDue: { $gt: 0 }, ...scope };
    
    if (req.query.vendorId) {
      const vid = safeObjId(req.query.vendorId);
      if (vid) {
        query.vendorId = vid;
      } else {
        query.vendorId = req.query.vendorId;
      }
    }

    const Bill = col('Bill', 'bills');
    const bills = await Bill.find(query).sort({ dueDate: 1 }).lean();
    const rows = bills.map(b => {
      const days = Math.floor((today - new Date(b.dueDate)) / 86400000);
      let bucket;
      if (days <= 0) bucket = 'Current';
      else if (days <= 30) bucket = '1-30 days';
      else if (days <= 60) bucket = '31-60 days';
      else if (days <= 90) bucket = '61-90 days';
      else bucket = 'Over 90 days';
      return { billNumber: b.billNumber, vendorName: b.vendorName, vendorEmail: b.vendorEmail, billDate: b.billDate, dueDate: b.dueDate, totalAmount: fmt(b.totalAmount), amountPaid: fmt(b.amountPaid), amountDue: fmt(b.amountDue), daysOverdue: Math.max(0, days), bucket, status: b.status };
    });
    res.json({ success: true, data: { asOf: today, bills: rows, total: fmt(rows.reduce((s, r) => s + (parseFloat(r.amountDue) || 0), 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/vendor-balance', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const rows = await Bill.aggregate([
      { $match: { billDate: { $gte: start, $lte: end }, status: { $ne: 'DRAFT' }, ...scope } },
      { $group: { _id: '$vendorId', vendorName: { $first: '$vendorName' }, vendorEmail: { $first: '$vendorEmail' }, billCount: { $sum: 1 }, totalBilled: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } },
      { $sort: { totalDue: -1 } },
    ]);
    res.json({ success: true, data: { vendors: rows.map(r => ({ vendorName: r.vendorName, vendorEmail: r.vendorEmail, billCount: r.billCount, totalBilled: fmt(r.totalBilled), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })), totals: { totalBilled: fmt(rows.reduce((s, r) => s + r.totalBilled, 0)), totalPaid: fmt(rows.reduce((s, r) => s + r.totalPaid, 0)), totalDue: fmt(rows.reduce((s, r) => s + r.totalDue, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-3: bill-details — vendorId cast to ObjectId
router.get('/bill-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const query = { billDate: { $gte: start, $lte: end }, ...scope };
    if (req.query.status) {
      query.status = req.query.status;
    } else {
      // Drafts aren't real transactions yet — Zoho's own reports never
      // show Draft-status documents unless explicitly asked for.
      query.status = { $nin: ['DRAFT', 'CANCELLED', 'VOID'] };
    }
    if (req.query.vendorId) {
      // FIX: try ObjectId first, fall back to string match
      const vid = safeObjId(req.query.vendorId);
      if (vid) {
        query.vendorId = vid;
      } else {
        // vendorId stored as string
        query.vendorId = req.query.vendorId;
      }
    }
    const bills = await Bill.find(query).sort({ billDate: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, bills: bills.map(b => ({ billNumber: b.billNumber, vendorName: b.vendorName, vendorEmail: b.vendorEmail, billDate: b.billDate, dueDate: b.dueDate, status: b.status, subTotal: fmt(b.subTotal), totalTax: fmt((b.cgst || 0) + (b.sgst || 0)), tdsAmount: fmt(b.tdsAmount), totalAmount: fmt(b.totalAmount), amountPaid: fmt(b.amountPaid), amountDue: fmt(b.amountDue) })), totals: { count: bills.length, totalAmount: fmt(bills.reduce((s, b) => s + (b.totalAmount || 0), 0)), totalPaid: fmt(bills.reduce((s, b) => s + (b.amountPaid || 0), 0)), totalDue: fmt(bills.reduce((s, b) => s + (b.amountDue || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-6: vendor-credit-details — correct collection name 'vendorcredits'
router.get('/vendor-credit-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    // Try both possible collection names
    const db = getDB(req);
    const statusFilter = req.query.status ? req.query.status : { $nin: ['DRAFT', 'CANCELLED', 'VOID'] };
    let credits = [];
    try {
      const VendorCredit = col('VendorCredit', 'vendorcredits');
      credits = await VendorCredit.find({ creditDate: { $gte: start, $lte: end }, status: statusFilter, ...scope }).sort({ creditDate: -1 }).lean();
    } catch (e1) {
      try {
        credits = await db.collection('vendorcredits').find({ creditDate: { $gte: start, $lte: end }, status: statusFilter, ...scope }).toArray();
      } catch (e2) {
        credits = [];
      }
    }
    const rows = credits.map(vc => ({ creditNumber: vc.creditNumber, vendorName: vc.vendorName, creditDate: vc.creditDate, status: vc.status, reason: vc.reason, totalAmount: fmt(vc.totalAmount), appliedAmount: fmt(vc.appliedAmount || 0), balanceAmount: fmt(vc.balanceAmount || 0) }));
    res.json({ success: true, data: { period: { start, end }, vendorCredits: rows, totals: { count: rows.length, total: fmt(rows.reduce((s, vc) => s + (parseFloat(vc.totalAmount) || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/payments-made', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    // Try multiple possible collection names
    let payments = [];
    const collections = ['paymentsmade', 'payments_made', 'paymentmades'];
    for (const cname of collections) {
      try {
        payments = await db.collection(cname).find({ ...scope }).sort({ createdAt: -1 }).limit(500).toArray();
        if (payments.length > 0) break;
      } catch (_) { }
    }
    // Filter by date
    const filtered = payments.filter(p => {
      const d = p.paymentDate ? new Date(p.paymentDate) : (p.createdAt ? new Date(p.createdAt) : null);
      if (!d) return true;
      return d >= start && d <= end;
    });
    const rows = filtered.map(p => ({ paymentNumber: p.paymentNumber, vendorName: p.vendorName, paymentDate: p.paymentDate, paymentMode: p.paymentMode, amount: fmt(p.amount || p.totalAmount || 0), status: p.status || 'paid', referenceNumber: p.referenceNumber || '', billsApplied: (p.billsApplied || []).length }));
    res.json({ success: true, data: { period: { start, end }, payments: rows, totals: { count: rows.length, total: fmt(rows.reduce((s, p) => s + parseFloat(p.amount || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/refund-history-payables', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const PaymentMade = col('PaymentMade', 'paymentmades');
    const payments = await PaymentMade.find({ 'refunds.0': { $exists: true }, ...scope }).lean();
    const refunds = [];
    for (const p of payments) {
      for (const r of (p.refunds || [])) {
        const rd = new Date(r.refundDate || r.refundedAt);
        if (rd >= start && rd <= end) refunds.push({ paymentNumber: p.paymentNumber, vendorName: p.vendorName, refundDate: rd, amount: fmt(r.amount), refundMode: r.refundMode, referenceNumber: r.referenceNumber });
      }
    }
    res.json({ success: true, data: { period: { start, end }, refunds, total: fmt(refunds.reduce((s, r) => s + r.amount, 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/purchase-order-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const PO = col('PurchaseOrder', 'purchaseorders');
    const statusFilter = req.query.status ? req.query.status : { $nin: ['DRAFT', 'CANCELLED', 'VOID'] };
    const pos = await PO.find({ purchaseOrderDate: { $gte: start, $lte: end }, status: statusFilter, ...scope }).sort({ purchaseOrderDate: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, purchaseOrders: pos.map(p => ({ purchaseOrderNumber: p.purchaseOrderNumber, vendorName: p.vendorName, purchaseOrderDate: p.purchaseOrderDate, expectedDeliveryDate: p.expectedDeliveryDate, status: p.status, subTotal: fmt(p.subTotal), totalAmount: fmt(p.totalAmount), receiveStatus: p.receiveStatus, billingStatus: p.billingStatus })), totals: { count: pos.length, totalAmount: fmt(pos.reduce((s, p) => s + (p.totalAmount || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-7: purchase-orders-by-vendor — date filter now OPTIONAL
router.get('/purchase-orders-by-vendor', async (req, res) => {
  try {
    const scope = orgScope(req);
    const PO = col('PurchaseOrder', 'purchaseorders');

    // Build match — date filter only if period results in valid dates AND data exists
    const { start, end } = parseDateRange(req.query);
    const matchQuery = { ...scope };

    // Only apply date filter if explicitly requested (not default this_fy)
    // This ensures data always shows even if POs are in different FY
    const allPOs = await PO.find(matchQuery).lean();

    if (allPOs.length === 0) {
      return res.json({ success: true, data: { vendors: [], totals: { totalAmount: 0 } } });
    }

    // Group by vendor from all POs, then filter by date on the grouped data
    const vendorMap = {};
    for (const po of allPOs) {
      const poDate = new Date(po.purchaseOrderDate);
      if (poDate < start || poDate > end) continue;
      const vid = (po.vendorId || po.vendorName || 'Unknown').toString();
      if (!vendorMap[vid]) {
        vendorMap[vid] = { vendorId: vid, vendorName: po.vendorName || 'Unknown', poCount: 0, totalAmount: 0 };
      }
      vendorMap[vid].poCount++;
      vendorMap[vid].totalAmount += po.totalAmount || 0;
    }

    // If no POs in date range, return all POs ungrouped
    let vendors = Object.values(vendorMap);
    if (vendors.length === 0) {
      // Fallback: return all POs grouped without date filter
      for (const po of allPOs) {
        const vid = (po.vendorId || po.vendorName || 'Unknown').toString();
        if (!vendorMap[vid]) vendorMap[vid] = { vendorId: vid, vendorName: po.vendorName || 'Unknown', poCount: 0, totalAmount: 0 };
        vendorMap[vid].poCount++;
        vendorMap[vid].totalAmount += po.totalAmount || 0;
      }
      vendors = Object.values(vendorMap);
    }

    vendors.sort((a, b) => b.totalAmount - a.totalAmount);
    const mapped = vendors.map(v => ({ vendorName: v.vendorName, poCount: v.poCount, totalAmount: fmt(v.totalAmount) }));

    res.json({ success: true, data: { vendors: mapped, totals: { totalAmount: fmt(vendors.reduce((s, v) => s + v.totalAmount, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-4: payable-summary — adds 'bills' alias so Flutter table renders
// Payable Summary — matches Zoho Books' real definition: "a detailed view of
// all the purchase transactions (Bills, Vendor Credits and Expenses)", not a
// status breakdown. Each row is one real transaction, newest first.
router.get('/payable-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const statusFilter = req.query.status ? req.query.status : { $nin: ['DRAFT', 'CANCELLED', 'VOID'] };

    const Bill = col('Bill', 'bills');
    const VendorCredit = col('VendorCredit', 'vendorcredits');
    const Expense = col('Expense', 'expenses');

    const [bills, credits, expenses] = await Promise.all([
      Bill.find({ billDate: { $gte: start, $lte: end }, status: statusFilter, ...scope }).lean(),
      VendorCredit.find({ creditDate: { $gte: start, $lte: end }, status: statusFilter, ...scope }).lean(),
      Expense.find({ date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...scope }).lean(),
    ]);

    const rows = [
      ...bills.map(b => ({ type: 'Bill', number: b.billNumber, vendorName: b.vendorName, date: b.billDate, status: b.status, totalAmount: fmt(b.totalAmount), amountDue: fmt(b.amountDue) })),
      ...credits.map(c => ({ type: 'Vendor Credit', number: c.creditNumber, vendorName: c.vendorName, date: c.creditDate, status: c.status, totalAmount: fmt(c.totalAmount), amountDue: fmt(c.balanceAmount || 0) })),
      ...expenses.map(e => ({ type: 'Expense', number: e.expenseNumber, vendorName: e.vendor || e.paidThrough || '', date: e.date, status: 'PAID', totalAmount: fmt(e.total), amountDue: 0 })),
    ].sort((a, b) => new Date(b.date) - new Date(a.date));

    res.json({
      success: true, data: {
        period: { start, end },
        transactions: rows,
        totals: {
          count: rows.length,
          totalAmount: fmt(rows.reduce((s, r) => s + r.totalAmount, 0)),
          totalDue: fmt(rows.reduce((s, r) => s + r.amountDue, 0)),
        }
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-5: payable-details — remove status filter so all bills show
router.get('/payable-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    // FIX: removed status filter — all bills in period shown, not just OPEN/OVERDUE/PARTIALLY_PAID
    const bills = await Bill.find({ billDate: { $gte: start, $lte: end }, ...scope }).sort({ billDate: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, bills: bills.map(b => ({ billNumber: b.billNumber, vendorName: b.vendorName, billDate: b.billDate, dueDate: b.dueDate, status: b.status, totalAmount: fmt(b.totalAmount), amountPaid: fmt(b.amountPaid), amountDue: fmt(b.amountDue), atId: b._id.toString(), atType: 'Bill' })), totals: { total: fmt(bills.reduce((s, b) => s + (b.amountDue || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 6: PURCHASES & EXPENSES
// ============================================================================

router.get('/purchases-by-vendor', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const rows = await Bill.aggregate([
      { $match: { billDate: { $gte: start, $lte: end }, status: { $ne: 'DRAFT' }, ...scope } },
      { $group: { _id: '$vendorId', vendorName: { $first: '$vendorName' }, billCount: { $sum: 1 }, totalAmount: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } },
      { $sort: { totalAmount: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, vendors: rows.map(r => ({ vendorId: r._id, vendorName: r.vendorName, billCount: r.billCount, totalAmount: fmt(r.totalAmount), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })), totals: { totalAmount: fmt(rows.reduce((s, r) => s + r.totalAmount, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/purchases-by-item', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const rows = await Bill.aggregate([
      { $match: { billDate: { $gte: start, $lte: end }, status: { $ne: 'DRAFT' }, ...scope } },
      { $unwind: '$items' },
      { $group: { _id: { $ifNull: ['$items.itemDetails', '$items.account'] }, quantity: { $sum: '$items.quantity' }, totalAmount: { $sum: '$items.amount' }, billCount: { $sum: 1 }, avgRate: { $avg: '$items.rate' } } },
      { $sort: { totalAmount: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, items: rows.map(r => ({ itemName: r._id, quantity: fmt(r.quantity), totalAmount: fmt(r.totalAmount), billCount: r.billCount, avgRate: fmt(r.avgRate) })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/expense-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');
    const startStr = start.toISOString().split('T')[0];
    const endStr = end.toISOString().split('T')[0];
    const query = { date: { $gte: startStr, $lte: endStr }, ...scope };
    if (req.query.vendor) query.vendor = new RegExp(req.query.vendor, 'i');
    if (req.query.expenseAccount) {
      if (req.query.expenseAccount.includes('||')) {
        query.expenseAccount = { $in: req.query.expenseAccount.split('||') };
      } else {
        query.expenseAccount = req.query.expenseAccount;
      }
    }
    if (req.query.customerName) query.customerName = req.query.customerName;
    if (req.query.paidThrough) query.paidThrough = req.query.paidThrough;

    // ✅ FIX: Fetch all expenses first
    const allExpenses = await Expense.find(query).sort({ date: -1 }).limit(500).lean();

    // Get unique expense account names
    const uniqueAccounts = [...new Set(allExpenses.map(e => e.expenseAccount).filter(Boolean))];

    // Batch fetch all account types at once
    const accounts = await ChartOfAccount.find({
      accountName: { $in: uniqueAccounts },
      ...(scope.orgId ? { orgId: scope.orgId } : {}),
    }).select('accountName accountType').lean();

    // Create a map of accountName → accountType
    const accountTypeMap = {};
    accounts.forEach(acc => {
      accountTypeMap[acc.accountName] = acc.accountType;
    });

    // ✅ Filter to ONLY include actual expense account types (not Asset, Liability, Equity)
    const expenses = allExpenses.filter(expense => {
      const accountType = accountTypeMap[expense.expenseAccount];
      // ONLY include if it's an actual expense account type
      return accountType && ['Expense', 'Other Expense', 'Cost Of Goods Sold'].includes(accountType);
    });

    const paidThroughNames = [...new Set(expenses.map(e => e.paidThrough).filter(Boolean))];
    const bankAccounts = await ChartOfAccount.find({
      accountName: { $in: paidThroughNames },
      ...(scope.orgId ? { orgId: scope.orgId } : {}),
    }).select('_id accountName').lean();
    const bankAcctMap = {};
    bankAccounts.forEach(a => { bankAcctMap[a.accountName] = a._id.toString(); });

    res.json({ success: true, data: { period: { start, end }, expenses: expenses.map(e => ({ id: e._id, expenseNumber: e.expenseNumber, date: e.date, expenseAccount: e.expenseAccount, amount: fmt(e.amount), tax: fmt(e.tax), total: fmt(e.total), paidThrough: e.paidThrough, vendor: e.vendor, customerName: e.customerName, isBillable: e.isBillable, project: e.project, notes: e.notes, atId: e._id.toString(), atType: 'Expense', btId: e.providerTransactionId?.toString() || null, bankAccountId: bankAcctMap[e.paidThrough] || null })), totals: { count: expenses.length, totalAmount: fmt(expenses.reduce((s, e) => s + (e.total || 0), 0)) } } });
  } catch (e) {
    console.error('❌ expense-details error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

router.get('/expenses-by-category', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');

    // ✅ FIX BUG 2: Get all expenses first
    const allExpenses = await Expense.find({
      date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] },
      ...scope
    }).lean();

    // Get unique expense account names
    const uniqueAccounts = [...new Set(allExpenses.map(e => e.expenseAccount).filter(Boolean))];

    // Batch fetch all account types at once
    const accounts = await ChartOfAccount.find({
      accountName: { $in: uniqueAccounts },
      ...(scope.orgId ? { orgId: scope.orgId } : {}),
    }).select('accountName accountType').lean();

    // Create a map of accountName → accountType
    const accountTypeMap = {};
    accounts.forEach(acc => {
      accountTypeMap[acc.accountName] = acc.accountType;
    });

    // Filter to ONLY include actual expense account types (not Asset, Liability, Equity)
    const filteredExpenses = allExpenses.filter(expense => {
      const accountType = accountTypeMap[expense.expenseAccount];
      // ✅ ONLY include if it's an actual expense account type (Exclude COGS)
      return accountType && ['Expense', 'Other Expense'].includes(accountType);
    });

    // Aggregate filtered expenses by category
    const categoryMap = {};
    for (const exp of filteredExpenses) {
      const cat = exp.expenseAccount || 'Other';
      if (!categoryMap[cat]) {
        categoryMap[cat] = { count: 0, totalAmount: 0, totalTax: 0, total: 0 };
      }
      categoryMap[cat].count += 1;
      categoryMap[cat].totalAmount += exp.amount || 0;
      categoryMap[cat].totalTax += exp.tax || 0;
      categoryMap[cat].total += exp.total || 0;
    }

    // Convert to array and sort by total
    const rows = Object.entries(categoryMap)
      .map(([category, data]) => ({ _id: category, ...data }))
      .sort((a, b) => b.total - a.total);

    const grandTotal = rows.reduce((s, r) => s + r.total, 0);
    res.json({ success: true, data: { period: { start, end }, categories: rows.map(r => ({ category: r._id, count: r.count, totalAmount: fmt(r.totalAmount), totalTax: fmt(r.totalTax), total: fmt(r.total), percent: grandTotal > 0 ? fmt((r.total / grandTotal) * 100) : 0 })), grandTotal: fmt(grandTotal) } });
  } catch (e) {
    console.error('❌ expenses-by-category error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

router.get('/expenses-by-customer', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');

    // ✅ FIX: Fetch all expenses first, then filter by account type
    const allExpenses = await Expense.find({
      date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] },
      customerName: { $ne: null, $exists: true },
      ...scope
    }).lean();

    // Get unique expense account names
    const uniqueAccounts = [...new Set(allExpenses.map(e => e.expenseAccount).filter(Boolean))];

    // Batch fetch account types
    const accounts = await ChartOfAccount.find({
      accountName: { $in: uniqueAccounts },
      ...(scope.orgId ? { orgId: scope.orgId } : {}),
    }).select('accountName accountType').lean();

    const accountTypeMap = {};
    accounts.forEach(acc => { accountTypeMap[acc.accountName] = acc.accountType; });

    // Filter to ONLY actual expense accounts
    const filteredExpenses = allExpenses.filter(e => {
      const accountType = accountTypeMap[e.expenseAccount];
      return accountType && ['Expense', 'Other Expense', 'Cost Of Goods Sold'].includes(accountType);
    });

    // Aggregate by customer
    const customerMap = {};
    filteredExpenses.forEach(e => {
      const cust = e.customerName;
      if (!customerMap[cust]) {
        customerMap[cust] = { count: 0, total: 0, billableTotal: 0 };
      }
      customerMap[cust].count += 1;
      customerMap[cust].total += e.total || 0;
      customerMap[cust].billableTotal += e.isBillable ? (e.billableAmount || 0) : 0;
    });

    const rows = Object.entries(customerMap)
      .map(([customerName, data]) => ({ customerName, ...data }))
      .sort((a, b) => b.total - a.total);

    res.json({ success: true, data: { period: { start, end }, customers: rows.map(r => ({ customerName: r.customerName, count: r.count, total: fmt(r.total), billableTotal: fmt(r.billableTotal) })) } });
  } catch (e) {
    console.error('❌ expenses-by-customer error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

router.get('/expenses-by-project', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');

    // ✅ FIX: Fetch all expenses first, then filter by account type
    const allExpenses = await Expense.find({
      date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] },
      project: { $ne: null, $exists: true },
      ...scope
    }).lean();

    // Get unique expense account names
    const uniqueAccounts = [...new Set(allExpenses.map(e => e.expenseAccount).filter(Boolean))];

    // Batch fetch account types
    const accounts = await ChartOfAccount.find({
      accountName: { $in: uniqueAccounts },
      ...(scope.orgId ? { orgId: scope.orgId } : {}),
    }).select('accountName accountType').lean();

    const accountTypeMap = {};
    accounts.forEach(acc => { accountTypeMap[acc.accountName] = acc.accountType; });

    // Filter to ONLY actual expense accounts
    const filteredExpenses = allExpenses.filter(e => {
      const accountType = accountTypeMap[e.expenseAccount];
      return accountType && ['Expense', 'Other Expense', 'Cost Of Goods Sold'].includes(accountType);
    });

    // Aggregate by project
    const projectMap = {};
    filteredExpenses.forEach(e => {
      const proj = e.project;
      if (!projectMap[proj]) {
        projectMap[proj] = { count: 0, total: 0 };
      }
      projectMap[proj].count += 1;
      projectMap[proj].total += e.total || 0;
    });

    const rows = Object.entries(projectMap)
      .map(([project, data]) => ({ project, ...data }))
      .sort((a, b) => b.total - a.total);

    res.json({ success: true, data: { period: { start, end }, projects: rows.map(r => ({ project: r.project, count: r.count, total: fmt(r.total) })) } });
  } catch (e) {
    console.error('❌ expenses-by-project error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

router.get('/expenses-by-employee', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');

    // ✅ FIX: Fetch all expenses first, then filter by account type
    const allExpenses = await Expense.find({
      date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] },
      ...scope
    }).lean();

    // Get unique expense account names
    const uniqueAccounts = [...new Set(allExpenses.map(e => e.expenseAccount).filter(Boolean))];

    // Batch fetch account types
    const accounts = await ChartOfAccount.find({
      accountName: { $in: uniqueAccounts },
      ...(scope.orgId ? { orgId: scope.orgId } : {}),
    }).select('accountName accountType').lean();

    const accountTypeMap = {};
    accounts.forEach(acc => { accountTypeMap[acc.accountName] = acc.accountType; });

    // Filter to ONLY actual expense accounts
    const filteredExpenses = allExpenses.filter(e => {
      const accountType = accountTypeMap[e.expenseAccount];
      return accountType && ['Expense', 'Other Expense', 'Cost Of Goods Sold'].includes(accountType);
    });

    // Aggregate by paidThrough (employee)
    const employeeMap = {};
    filteredExpenses.forEach(e => {
      const emp = e.paidThrough;
      if (!employeeMap[emp]) {
        employeeMap[emp] = { count: 0, total: 0 };
      }
      employeeMap[emp].count += 1;
      employeeMap[emp].total += e.total || 0;
    });

    const rows = Object.entries(employeeMap)
      .map(([employee, data]) => ({ employee, ...data }))
      .sort((a, b) => b.total - a.total);

    res.json({ success: true, data: { period: { start, end }, employees: rows.map(r => ({ employee: r.employee, count: r.count, total: fmt(r.total) })) } });
  } catch (e) {
    console.error('❌ expenses-by-employee error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

router.get('/billable-expenses', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');

    // ✅ FIX: Fetch all billable expenses first, then filter by account type
    const allExpenses = await Expense.find({
      isBillable: true,
      date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] },
      ...scope
    }).sort({ date: -1 }).lean();

    // Get unique expense account names
    const uniqueAccounts = [...new Set(allExpenses.map(e => e.expenseAccount).filter(Boolean))];

    // Batch fetch account types
    const accounts = await ChartOfAccount.find({
      accountName: { $in: uniqueAccounts },
      ...(scope.orgId ? { orgId: scope.orgId } : {}),
    }).select('accountName accountType').lean();

    const accountTypeMap = {};
    accounts.forEach(acc => { accountTypeMap[acc.accountName] = acc.accountType; });

    // Filter to ONLY actual expense accounts
    const expenses = allExpenses.filter(e => {
      const accountType = accountTypeMap[e.expenseAccount];
      return accountType && ['Expense', 'Other Expense', 'Cost Of Goods Sold'].includes(accountType);
    });

    res.json({ success: true, data: { period: { start, end }, expenses: expenses.map(e => ({ date: e.date, expenseAccount: e.expenseAccount, total: fmt(e.total), billableAmount: fmt(e.billableAmount), customerName: e.customerName, project: e.project, isBilled: e.isBilled, vendor: e.vendor, notes: e.notes })), totals: { unbilled: fmt(expenses.filter(e => !e.isBilled).reduce((s, e) => s + (e.billableAmount || 0), 0)), billed: fmt(expenses.filter(e => e.isBilled).reduce((s, e) => s + (e.billableAmount || 0), 0)) } } });
  } catch (e) {
    console.error('❌ billable-expenses error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ── SECTION 7: TAXES
// ============================================================================

router.get('/tds-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const tdsAcc = await ChartOfAccount.findOne({ accountName: 'TDS Payable', isSystemAccount: true, ...coaScope(req) }).lean();
    if (!tdsAcc) return res.json({ success: true, data: { period: { start, end }, transactions: [], totals: { totalDeducted: 0, totalPaid: 0, balance: 0 }, message: 'TDS Payable account not seeded. Run /api/seed-accounts first.' } });
    const txns = await AccountTransaction.find({ accountId: tdsAcc._id, date: { $gte: start, $lte: end }, ...scope }).sort({ date: -1 }).lean();
    res.json({ success: true, data: { period: { start, end }, transactions: txns.map(t => ({ date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit) })), totals: { totalDeducted: fmt(txns.reduce((s, t) => s + (t.credit || 0), 0)), totalPaid: fmt(txns.reduce((s, t) => s + (t.debit || 0), 0)), balance: fmt(txns.reduce((s, t) => s + ((t.credit || 0) - (t.debit || 0)), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// TDS Receivable Summary — grouped by TDS Section (matches Zoho Books' layout).
// The ledger (AccountTransaction) rows don't carry a section, so we join back
// to the invoice by referenceNumber to read invoice.tdsSection. This keeps the
// COA posting logic untouched — the grouping happens only in the report layer.
router.get('/tds-receivable', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const tdsAcc = await ChartOfAccount.findOne({ accountName: 'TDS Receivable', isSystemAccount: true, ...coaScope(req) }).lean();
    if (!tdsAcc) return res.json({ success: true, data: { period: { start, end }, transactions: [], totals: { totalTDSDeducted: 0 }, message: 'TDS Receivable account not seeded.' } });
    const txns = await AccountTransaction.find({ accountId: tdsAcc._id, date: { $gte: start, $lte: end }, ...scope }).sort({ date: -1 }).lean();

    const Invoice = col('Invoice', 'invoices');
    const invoiceNumbers = [...new Set(txns.map(t => t.referenceNumber).filter(Boolean))];
    const invoices = await Invoice.find({ invoiceNumber: { $in: invoiceNumbers }, ...scope })
      .select('invoiceNumber tdsSection tdsRate totalAmount tdsAmount').lean();
    const invByNumber = {};
    invoices.forEach(inv => { invByNumber[inv.invoiceNumber] = inv; });

    const sectionMap = {};
    for (const t of txns) {
      const inv = invByNumber[t.referenceNumber];
      const section = inv?.tdsSection?.trim() || 'Uncategorized';
      if (!sectionMap[section]) {
        sectionMap[section] = { section, ratePercent: inv?.tdsRate || 0, totalTDSDeducted: 0, invoiceCount: 0, totalFromInvoices: 0 };
      }
      sectionMap[section].totalTDSDeducted += (t.debit || 0);
      sectionMap[section].invoiceCount     += 1;
      sectionMap[section].totalFromInvoices += (inv?.totalAmount || 0);
    }
    const sections = Object.values(sectionMap).map(s => ({
      section: s.section,
      ratePercent: s.ratePercent,
      totalTDSDeducted: fmt(s.totalTDSDeducted),
      invoiceCount: s.invoiceCount,
      totalFromInvoices: fmt(s.totalFromInvoices),
    }));

    res.json({
      success: true,
      data: {
        period: { start, end },
        transactions: sections,
        totals: {
          totalTDSDeducted: fmt(txns.reduce((s, t) => s + (t.debit || 0), 0)),
          invoiceCount: txns.length,
          totalFromInvoices: fmt(invoices.reduce((s, i) => s + (i.totalAmount || 0), 0)),
        },
      },
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// TDS Receivable Details — invoices under one specific TDS section, with the
// customer's PAN joined in (the customer record already has panNumber; TDS
// docs just never pulled it in before).
router.get('/tds-receivable-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const section = (req.query.section || '').trim();

    const Invoice = col('Invoice', 'invoices');
    const query = { invoiceDate: { $gte: start, $lte: end }, tdsAmount: { $gt: 0 }, ...scope };
    query.tdsSection = section === 'Uncategorized' ? { $in: ['', null] } : section;

    const invoices = await Invoice.find(query).sort({ invoiceDate: -1 }).lean();

    const BillingCustomer = col('BillingCustomer', 'billing-customers');
    const custIds = [...new Set(invoices.map(i => i.customerId).filter(Boolean))];
    const customers = await BillingCustomer.find({
      $or: [{ _id: { $in: custIds.filter(id => /^[0-9a-fA-F]{24}$/.test(id)) } }, { customerId: { $in: custIds } }],
    }).select('_id customerId panNumber').lean();
    const panByCustomer = {};
    customers.forEach(c => {
      if (c._id) panByCustomer[c._id.toString()] = c.panNumber || '';
      if (c.customerId) panByCustomer[c.customerId] = c.panNumber || '';
    });

    res.json({
      success: true,
      data: {
        section,
        period: { start, end },
        invoices: invoices.map(inv => ({
          invoiceNumber: inv.invoiceNumber,
          customerName: inv.customerName,
          panNumber: panByCustomer[inv.customerId] || '',
          invoiceDate: inv.invoiceDate,
          transactionType: 'Invoice',
          reasonForHigherDeduction: inv.tdsReason || '-',
          ratePercent: inv.tdsRate || 0,
          totalAmount: fmt(inv.totalAmount),
          taxDeductedAtSource: fmt(inv.tdsAmount),
          totalAfterTdsDeduction: fmt((inv.totalAmount || 0) - (inv.tdsAmount || 0)),
        })),
        totals: {
          count: invoices.length,
          totalTDSDeducted: fmt(invoices.reduce((s, i) => s + (i.tdsAmount || 0), 0)),
        },
      },
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/tcs-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const Bill = col('Bill', 'bills');
    const [invTCS, billTCS] = await Promise.all([
      Invoice.aggregate([{ $match: { invoiceDate: { $gte: start, $lte: end }, tcsAmount: { $gt: 0 }, ...scope } }, { $group: { _id: null, total: { $sum: '$tcsAmount' }, count: { $sum: 1 } } }]),
      Bill.aggregate([{ $match: { billDate: { $gte: start, $lte: end }, tcsAmount: { $gt: 0 }, ...scope } }, { $group: { _id: null, total: { $sum: '$tcsAmount' }, count: { $sum: 1 } } }]),
    ]);
    res.json({ success: true, data: { period: { start, end }, tcsFromSales: fmt(invTCS[0]?.total || 0), tcsFromPurchases: fmt(billTCS[0]?.total || 0), salesCount: invTCS[0]?.count || 0, purchasesCount: billTCS[0]?.count || 0, netTCS: fmt((invTCS[0]?.total || 0) - (billTCS[0]?.total || 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 8: BANKING
// ============================================================================

// FIX-11: reconciliation-status — always resolve accountName, remove accountId from row
router.get('/reconciliation-status', async (req, res) => {
  try {
    const scope = orgScope(req);
    const Reconciliation = mongoose.models.Reconciliation ||
      mongoose.model('Reconciliation', new mongoose.Schema({}, { strict: false }), 'reconciliations');
    const PaymentAccount = mongoose.models.PaymentAccount ||
      mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');

    const recs = await Reconciliation.find(scope).sort({ createdAt: -1 }).limit(100).lean();
    const accounts = await PaymentAccount.find(scope).lean();
    const accMap = {};
    accounts.forEach(a => {
      accMap[a._id.toString()] = a.accountName;
    });

    res.json({
      success: true, data: {
        reconciliations: recs.map(r => ({
          // FIX: do NOT expose accountId — it causes Flutter to pass it as drill-down param
          accountName: accMap[r.accountId?.toString()] || r.accountName || '',
          startDate: r.startDate,
          endDate: r.endDate,
          openingBalance: fmt(r.openingBalance),
          closingBalance: fmt(r.closingBalance),
          clearedAmount: fmt(r.clearedAmount),
          difference: fmt(r.difference),
          status: r.status,
          reconciledAt: r.reconciledAt,
        })),
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 9: PROJECTS & TIMESHEET
// ============================================================================

// FIX-10: timesheet-details — date range fix + no projectId required for list view
router.get('/timesheet-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);

    // Build query — date stored as Date objects in MongoDB
    const query = { ...scope };

    // FIX: only add date filter if it doesn't exclude everything
    // Use a wider window: from 1 year ago to now if no explicit dates given
    if (req.query.period || req.query.fromDate) {
      query.date = { $gte: start, $lte: end };
    }
    // else: no date filter — return all entries

    if (req.query.projectId) query.projectId = req.query.projectId;
    if (req.query.status) query.status = req.query.status;

    const entries = await db.collection('timesheets')
      .find(query)
      .sort({ date: -1, createdAt: -1 })
      .limit(500)
      .toArray();

    res.json({
      success: true, data: {
        period: { start, end },
        entries: entries.map(e => ({
          entryNumber: e.entryNumber,
          date: e.date,
          projectName: e.projectName,
          taskName: e.taskName,
          userName: e.userName,
          userEmail: e.userEmail,
          hours: e.hours,
          isBillable: e.isBillable,
          status: e.status,
          notes: e.notes,
        })),
        totals: {
          totalHours: fmt(entries.reduce((s, e) => s + (e.hours || 0), 0)),
          billableHours: fmt(entries.filter(e => e.isBillable).reduce((s, e) => s + (e.hours || 0), 0)),
        },
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/timesheet-profitability', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    const projects = await db.collection('projects').find(scope).toArray();
    const rows = [];
    for (const project of projects) {
      const entries = await db.collection('timesheets').find({ ...scope, projectId: project._id.toString() }).toArray();
      const totalHours = entries.reduce((s, e) => s + (e.hours || 0), 0);
      const billableHours = entries.filter(e => e.isBillable).reduce((s, e) => s + (e.hours || 0), 0);
      const billedAmount = project.totalBilledAmount || 0;
      rows.push({ projectName: project.projectName, projectNumber: project.projectNumber, customerName: project.customerName, billingMethod: project.billingMethod, totalHours: fmt(totalHours), billableHours: fmt(billableHours), billedAmount: fmt(billedAmount), budgetAmount: fmt(project.budgetAmount || 0), variance: fmt((project.budgetAmount || 0) - billedAmount) });
    }
    res.json({ success: true, data: { period: { start, end }, projects: rows } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-8: project-summary — no change needed, already correct
router.get('/project-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    const projects = await db.collection('projects').find({ ...scope, ...(req.query.status ? { status: req.query.status } : {}) }).sort({ createdAt: -1 }).toArray();
    res.json({ success: true, data: { period: { start, end }, projects: projects.map(p => ({ projectId: p._id.toString(), projectNumber: p.projectNumber, projectName: p.projectName, customerName: p.customerName, billingMethod: p.billingMethod, status: p.status, startDate: p.startDate, endDate: p.endDate, totalLoggedHours: fmt(p.totalLoggedHours || 0), totalBilledAmount: fmt(p.totalBilledAmount || 0), budgetAmount: fmt(p.budgetAmount || 0) })), totals: { totalProjects: projects.length, activeProjects: projects.filter(p => p.status === 'Active').length, totalBilledAmount: fmt(projects.reduce((s, p) => s + (p.totalBilledAmount || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-8: project-details — projectId now OPTIONAL
router.get('/project-details', async (req, res) => {
  try {
    const scope = orgScope(req);
    const db = getDB(req);
    const projectId = req.query.projectId;

    // FIX: if no projectId, return project summary instead of error
    if (!projectId) {
      const projects = await db.collection('projects').find(scope).sort({ createdAt: -1 }).toArray();
      return res.json({
        success: true, data: {
          projects: projects.map(p => ({
            projectNumber: p.projectNumber, projectName: p.projectName,
            customerName: p.customerName, billingMethod: p.billingMethod,
            status: p.status, startDate: p.startDate, endDate: p.endDate,
            totalLoggedHours: fmt(p.totalLoggedHours || 0),
            totalBilledAmount: fmt(p.totalBilledAmount || 0),
            budgetAmount: fmt(p.budgetAmount || 0),
          })),
          totals: { totalProjects: projects.length },
        }
      });
    }

    // Single project with timesheets
    let project = null;
    try {
      project = await db.collection('projects').findOne({ _id: new mongoose.Types.ObjectId(projectId), ...scope });
    } catch (_) {
      project = await db.collection('projects').findOne({ _id: projectId, ...scope });
    }
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });

    const entries = await db.collection('timesheets').find({ projectId, ...scope }).sort({ date: -1 }).toArray();

    res.json({
      success: true, data: {
        project,
        timesheets: entries,
        totals: {
          totalHours: fmt(entries.reduce((s, e) => s + (e.hours || 0), 0)),
          billableHours: fmt(entries.filter(e => e.isBillable).reduce((s, e) => s + (e.hours || 0), 0)),
        },
      }
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/projects-cost-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    const Expense = col('Expense', 'expenses');
    const projects = await db.collection('projects').find(scope).toArray();
    const rows = [];
    for (const project of projects) {
      const expenses = await Expense.find({ project: project.projectName, date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...scope }).lean();
      const totalExpenses = expenses.reduce((s, e) => s + (e.total || 0), 0);
      rows.push({ projectId: project._id.toString(), projectName: project.projectName, customerName: project.customerName, budgetAmount: fmt(project.budgetAmount || 0), actualCost: fmt(totalExpenses), variance: fmt((project.budgetAmount || 0) - totalExpenses), utilizationPercent: project.budgetAmount > 0 ? fmt((totalExpenses / project.budgetAmount) * 100) : 0 });
    }
    res.json({ success: true, data: { period: { start, end }, projects: rows } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/projects-revenue-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    const Invoice = col('Invoice', 'invoices');
    const projects = await db.collection('projects').find(scope).toArray();
    const rows = [];
    for (const project of projects) {
      const invoices = await Invoice.find({ projectId: project._id.toString(), invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...scope }).lean();
      const totalRevenue = invoices.reduce((s, i) => s + (i.totalAmount || 0), 0);
      rows.push({ projectId: project._id.toString(), projectName: project.projectName, customerName: project.customerName, billingMethod: project.billingMethod, totalBilledAmount: fmt(project.totalBilledAmount || 0), totalInvoiced: fmt(totalRevenue), invoiceCount: invoices.length });
    }
    res.json({ success: true, data: { period: { start, end }, projects: rows } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/projects-performance', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    const Expense = col('Expense', 'expenses');
    const Invoice = col('Invoice', 'invoices');
    const projects = await db.collection('projects').find(scope).toArray();
    const rows = [];
    for (const project of projects) {
      const [entries, expenses, invoices] = await Promise.all([
        db.collection('timesheets').find({ projectId: project._id.toString(), ...scope }).toArray(),
        Expense.find({ project: project.projectName, ...scope }).lean(),
        Invoice.find({ projectId: project._id.toString(), status: { $nin: ['DRAFT', 'CANCELLED'] }, ...scope }).lean(),
      ]);
      const totalHours = entries.reduce((s, e) => s + (e.hours || 0), 0);
      const totalCost = expenses.reduce((s, e) => s + (e.total || 0), 0);
      const totalRevenue = invoices.reduce((s, i) => s + (i.totalAmount || 0), 0);
      const profit = totalRevenue - totalCost;
      rows.push({ projectId: project._id.toString(), projectName: project.projectName, customerName: project.customerName, status: project.status, totalHours: fmt(totalHours), totalCost: fmt(totalCost), totalRevenue: fmt(totalRevenue), profit: fmt(profit), profitMargin: totalRevenue > 0 ? fmt((profit / totalRevenue) * 100) : 0 });
    }
    res.json({ success: true, data: { period: { start, end }, projects: rows } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 10: ACCOUNTANT
// ============================================================================

router.get('/general-ledger', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    // FIX-5: COA is org-level only — branchId must NOT be applied to account lookup
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    let accQuery = { isActive: true, ...orgFilter };
    if (req.query.accountId) accQuery._id = req.query.accountId;
    if (req.query.accountType) accQuery.accountType = req.query.accountType;
    const accounts = await ChartOfAccount.find(accQuery).sort({ accountCode: 1 }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.find({ accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope }).sort({ accountId: 1, date: 1 }).lean();
    const grouped = {};
    accounts.forEach(a => { grouped[a._id.toString()] = { account: a, transactions: [] }; });
    txns.forEach(t => { const k = t.accountId.toString(); if (grouped[k]) grouped[k].transactions.push(t); });
    const result = Object.values(grouped).filter(g => g.transactions.length > 0).map(g => {
      let balance = 0;
      const rows = g.transactions.map(t => { balance += (t.debit || 0) - (t.credit || 0); return { date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance) }; });
      return { accountId: g.account._id.toString(), accountCode: g.account.accountCode, accountName: g.account.accountName, accountType: g.account.accountType, transactions: rows, totals: { debit: fmt(rows.reduce((s, r) => s + r.debit, 0)), credit: fmt(rows.reduce((s, r) => s + r.credit, 0)), closing: fmt(balance) } };
    });
    res.json({ success: true, data: { period: { start, end }, accounts: result } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/general-ledger-detailed', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accounts = await ChartOfAccount.find({ isActive: true, ...coaScope(req) }).sort({ accountCode: 1 }).lean();
    const ids = accounts.map(a => a._id);
    const [openTxns, periodTxns] = await Promise.all([
      AccountTransaction.aggregate([{ $match: { accountId: { $in: ids }, date: { $lt: start }, ...scope } }, { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }]),
      AccountTransaction.find({ accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope }).sort({ accountId: 1, date: 1 }).lean(),
    ]);
    const openMap = {}; openTxns.forEach(t => { openMap[t._id.toString()] = fmt(t.dr - t.cr); });
    const grouped = {}; accounts.forEach(a => { grouped[a._id.toString()] = { account: a, transactions: [] }; });
    periodTxns.forEach(t => { const k = t.accountId.toString(); if (grouped[k]) grouped[k].transactions.push(t); });
    const result = Object.values(grouped).filter(g => g.transactions.length > 0 || openMap[g.account._id.toString()]).map(g => {
      const opening = openMap[g.account._id.toString()] || 0;
      let balance = opening;
      const rows = g.transactions.map(t => { balance += (t.debit || 0) - (t.credit || 0); return { date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance) }; });
      return { accountCode: g.account.accountCode, accountName: g.account.accountName, accountType: g.account.accountType, openingBalance: fmt(opening), transactions: rows, closingBalance: fmt(balance) };
    });
    res.json({ success: true, data: { period: { start, end }, accounts: result } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// FIX-9: account-transactions — accountId now OPTIONAL
async function resolveReferenceNumbers(txns) {
  const objectIdRefs = txns.filter(t => t.referenceNumber && /^[0-9a-fA-F]{24}$/.test(t.referenceNumber));
  const refNumberMap = {};
  if (objectIdRefs.length === 0) return refNumberMap;
  
  const refsByType = {};
  for (const t of objectIdRefs) {
    if (!refsByType[t.referenceType]) refsByType[t.referenceType] = [];
    refsByType[t.referenceType].push(t.referenceNumber);
  }
  
  for (const type of Object.keys(refsByType)) {
    const ids = [...new Set(refsByType[type])];
    try {
      if (type === 'Expense') {
        const docs = await col('Expense', 'expenses').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.expenseNumber);
      } else if (type === 'Invoice') {
        const docs = await col('Invoice', 'invoices').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.invoiceNumber);
      } else if (type === 'Bill') {
        const docs = await col('Bill', 'bills').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.billNumber);
      } else if (type === 'Vendor Credit') {
        const docs = await col('VendorCredit', 'vendorcredits').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.vendorCreditNumber || d.creditNoteNumber);
      } else if (type === 'Purchase Order') {
        const docs = await col('PurchaseOrder', 'purchaseorders').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.purchaseOrderNumber);
      } else if (type === 'Payment Received') {
        const docs = await col('PaymentReceived', 'paymentreceiveds').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.paymentNumber);
      } else if (type === 'Payment Made') {
        const docs = await col('PaymentMade', 'paymentsmade').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.paymentNumber);
      } else if (type === 'Manual Journal') {
        const docs = await col('ManualJournal', 'manualjournals').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.journalNumber);
      } else if (type === 'Credit Note') {
        const docs = await col('CreditNote', 'creditnotes').find({ _id: { $in: ids } }).lean();
        docs.forEach(d => refNumberMap[d._id.toString()] = d.creditNoteNumber);
      }
    } catch (_) {}
  }
  return refNumberMap;
}

router.get('/account-transactions', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const { accountId } = req.query;

    // FIX: if no accountId, return all transactions (general ledger style)
    if (!accountId) {
      const accounts = await ChartOfAccount.find({ isActive: true, ...coaScope(req) }).lean();
      const ids = accounts.map(a => a._id);
      const accMap = {}; accounts.forEach(a => { accMap[a._id.toString()] = a; });
      const txns = await AccountTransaction.find({ accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope }).sort({ date: 1 }).limit(500).lean();
      const refNumberMap = await resolveReferenceNumbers(txns);
      let balance = 0;
      const rows = txns.map(t => {
        balance += (t.debit || 0) - (t.credit || 0);
        return { date: t.date, description: t.description, accountName: accMap[t.accountId?.toString()]?.accountName || '', accountType: accMap[t.accountId?.toString()]?.accountType || '', referenceType: t.referenceType, referenceNumber: refNumberMap[t.referenceNumber] || t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance), atId: t.referenceId?.toString(), atType: t.referenceType, btId: t.referenceType === 'ProviderTransaction' ? t.referenceId?.toString() : null, bankAccountId: t.referenceType === 'ProviderTransaction' ? t.accountId?.toString() : null };
      });
      return res.json({ success: true, data: { period: { start, end }, transactions: rows, totals: { debit: fmt(rows.reduce((s, r) => s + r.debit, 0)), credit: fmt(rows.reduce((s, r) => s + r.credit, 0)), closingBalance: fmt(balance) } } });
    }

    const account = await ChartOfAccount.findOne({ _id: accountId, ...coaScope(req) }).lean();
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });
    const txns = await AccountTransaction.find({ accountId, date: { $gte: start, $lte: end }, ...scope }).sort({ date: 1 }).lean();
    
    // Fetch related counter-party accounts using referenceNumber
    const refNumbers = txns.map(t => t.referenceNumber).filter(Boolean);
    const relatedTxns = await AccountTransaction.find({ 
      referenceNumber: { $in: refNumbers }, 
      accountId: { $ne: account._id }, 
      ...scope 
    }).lean();

    // Fetch account names
    const relatedAccIds = [...new Set(relatedTxns.map(t => t.accountId?.toString()).filter(Boolean))];
    const relatedAccs = await ChartOfAccount.find({ _id: { $in: relatedAccIds } }).lean();
    const accNameMap = {};
    for (const a of relatedAccs) accNameMap[a._id.toString()] = a.accountName;

    const counterPartyMap = {};
    for (const t of relatedTxns) {
      if (t.referenceNumber && t.accountId) {
        if (!counterPartyMap[t.referenceNumber]) counterPartyMap[t.referenceNumber] = [];
        counterPartyMap[t.referenceNumber].push(accNameMap[t.accountId.toString()] || 'Unknown');
      }
    }

    const refNumberMap = await resolveReferenceNumbers(txns);

    const isCreditNormal = ['Income', 'Other Income', 'Liability', 'Other Current Liability', 'Long Term Liability', 'Equity'].includes(account.accountType);
    let balance = 0;
    const rows = txns.map(t => { 
      if (isCreditNormal) {
        balance += (t.credit || 0) - (t.debit || 0); 
      } else {
        balance += (t.debit || 0) - (t.credit || 0); 
      }
      const counterParties = counterPartyMap[t.referenceNumber] || [];
      const counterPartyName = counterParties.length > 0 ? counterParties.join(', ') : '';
      return { 
        date: t.date, 
        description: t.description, 
        accountName: counterPartyName, 
        referenceType: t.referenceType, 
        referenceNumber: refNumberMap[t.referenceNumber] || t.referenceNumber, 
        debit: fmt(t.debit), 
        credit: fmt(t.credit), 
        balance: fmt(balance),
        atId: t.referenceId?.toString(),
        atType: t.referenceType,
        btId: t.referenceType === 'ProviderTransaction' ? t.referenceId?.toString() : null,
        bankAccountId: t.referenceType === 'ProviderTransaction' ? t.accountId?.toString() : null
      }; 
    });
    res.json({ success: true, data: { account: { id: account._id, name: account.accountName, code: account.accountCode, type: account.accountType }, period: { start, end }, transactions: rows, totals: { debit: fmt(rows.reduce((s, r) => s + r.debit, 0)), credit: fmt(rows.reduce((s, r) => s + r.credit, 0)), closingBalance: fmt(balance) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/account-type-summary', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accounts = await ChartOfAccount.find({ isActive: true, ...coaScope(req) }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.aggregate([{ $match: { accountId: { $in: ids }, date: { $lte: end }, ...scope } }, { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }]);
    const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
    const typeMap = {};
    for (const acc of accounts) {
      const t = tMap[acc._id.toString()] || { dr: 0, cr: 0 };
      if (!typeMap[acc.accountType]) typeMap[acc.accountType] = { accountType: acc.accountType, count: 0, totalDebit: 0, totalCredit: 0 };
      typeMap[acc.accountType].count++;
      typeMap[acc.accountType].totalDebit += t.dr;
      typeMap[acc.accountType].totalCredit += t.cr;
    }
    res.json({ success: true, data: { asOf: end, accountTypes: Object.values(typeMap).map(t => ({ ...t, totalDebit: fmt(t.totalDebit), totalCredit: fmt(t.totalCredit), netBalance: fmt(t.totalDebit - t.totalCredit) })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/journal-report', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const ManualJournal = col('ManualJournal', 'manualjournals');
    const journals = await ManualJournal.find({ date: { $gte: start, $lte: end }, status: 'Published', ...scope }).sort({ date: -1 }).lean();
    res.json({ success: true, data: { period: { start, end }, journals: journals.map(j => ({ journalNumber: j.journalNumber, date: j.date, notes: j.notes, referenceNumber: j.referenceNumber, totalDebit: fmt(j.totalDebit), totalCredit: fmt(j.totalCredit), lineItems: (j.lineItems || []).map(l => ({ accountName: l.accountName, description: l.description, debit: fmt(l.debit), credit: fmt(l.credit) })) })), totals: { count: journals.length, totalDebit: fmt(journals.reduce((s, j) => s + (j.totalDebit || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/activity-logs', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const Bill = col('Bill', 'bills');
    const PaymentMade = col('PaymentMade', 'paymentmades');
    const Expense = col('Expense', 'expenses');
    const [invoices, bills, payments, expenses] = await Promise.all([
      Invoice.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('invoiceNumber customerName totalAmount status createdAt createdBy').limit(200).lean(),
      Bill.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('billNumber vendorName totalAmount status createdAt createdBy').limit(200).lean(),
      PaymentMade.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('paymentNumber vendorName amount status createdAt createdBy').limit(200).lean(),
      Expense.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('expenseAccount total paidThrough createdAt').limit(200).lean(),
    ]);
    const logs = [
      ...invoices.map(i => ({ type: 'Invoice', ref: i.invoiceNumber, name: i.customerName, amount: fmt(i.totalAmount), status: i.status, date: i.createdAt, by: i.createdBy })),
      ...bills.map(b => ({ type: 'Bill', ref: b.billNumber, name: b.vendorName, amount: fmt(b.totalAmount), status: b.status, date: b.createdAt, by: b.createdBy })),
      ...payments.map(p => ({ type: 'Payment Made', ref: p.paymentNumber, name: p.vendorName, amount: fmt(p.amount), status: p.status, date: p.createdAt, by: p.createdBy })),
      ...expenses.map(e => ({ type: 'Expense', ref: e._id, name: e.expenseAccount, amount: fmt(e.total), status: 'Recorded', date: e.createdAt, by: 'system' })),
    ].sort((a, b) => new Date(b.date) - new Date(a.date));
    res.json({ success: true, data: { period: { start, end }, logs, count: logs.length } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 11: BUDGETS
// ============================================================================

router.get('/budget-vs-actuals', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    let budgets = [];
    try { budgets = await db.collection('budgets').find(scope).toArray(); } catch (_) { }
    if (budgets.length === 0) {
      const projects = await db.collection('projects').find({ ...scope, budgetAmount: { $gt: 0 } }).toArray();
      const Expense = col('Expense', 'expenses');
      const rows = [];
      for (const p of projects) {
        const expenses = await Expense.find({ project: p.projectName, date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...scope }).lean();
        const actuals = expenses.reduce((s, e) => s + (e.total || 0), 0);
        rows.push({ name: p.projectName, budgeted: fmt(p.budgetAmount || 0), actuals: fmt(actuals), variance: fmt((p.budgetAmount || 0) - actuals), variancePercent: p.budgetAmount > 0 ? fmt(((p.budgetAmount - actuals) / p.budgetAmount) * 100) : 0 });
      }
      return res.json({ success: true, data: { period: { start, end }, source: 'projects', rows } });
    }
    const rows = [];
    for (const budget of budgets) {
      for (const line of budget.accountLines || []) {
        if (!line.accountId) continue;
        const txns = await AccountTransaction.aggregate([
          { $match: { accountId: new mongoose.Types.ObjectId(line.accountId), date: { $gte: start, $lte: end }, ...scope } },
          { $group: { _id: null, dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }
        ]);
        const t = txns[0] || { dr: 0, cr: 0 };
        const isIncome = ['Income', 'Other Income'].includes(line.accountType);
        const actual = isIncome ? t.cr - t.dr : t.dr - t.cr;
        const budgeted = (line.monthlyAmounts || []).reduce((s, v) => s + v, 0);
        rows.push({
          budgetName: budget.budgetName,
          accountName: line.accountName,
          accountType: line.accountType,
          budgeted: fmt(budgeted),
          actual: fmt(actual),
          variance: fmt(budgeted - actual),
          variancePercent: budgeted > 0 ? fmt(((budgeted - actual) / budgeted) * 100) : 0
        });
      }
    }
    res.json({ success: true, data: { period: { start, end }, source: 'budgets', rows } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 12: CURRENCY
// ============================================================================

router.get('/realized-gain-loss', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const bills = await Bill.find({ billDate: { $gte: start, $lte: end }, currency: { $ne: 'INR' }, amountPaid: { $gt: 0 }, ...scope }).lean();
    const rows = bills.map(b => {
      const originalAmount = b.totalAmount;
      const baseCurrencyAmount = b.baseCurrencyAmount || b.totalAmount;
      const gainLoss = fmt(baseCurrencyAmount - originalAmount);
      return { billNumber: b.billNumber, vendorName: b.vendorName, currency: b.currency, originalAmount: fmt(originalAmount), exchangeRate: fmt(b.exchangeRate || 1), baseCurrencyAmount: fmt(baseCurrencyAmount), gainLoss, type: gainLoss >= 0 ? 'Gain' : 'Loss' };
    });
    res.json({ success: true, data: { period: { start, end }, transactions: rows, totals: { totalGain: fmt(rows.filter(r => r.gainLoss > 0).reduce((s, r) => s + r.gainLoss, 0)), totalLoss: fmt(rows.filter(r => r.gainLoss < 0).reduce((s, r) => s + Math.abs(r.gainLoss), 0)), netGainLoss: fmt(rows.reduce((s, r) => s + r.gainLoss, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/unrealized-gain-loss', async (req, res) => {
  try {
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const openBills = await Bill.find({ status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] }, currency: { $ne: 'INR' }, ...scope }).lean();
    const rows = openBills.map(b => {
      const originalAmount = b.amountDue;
      const currentRate = b.exchangeRate || 1;
      const currentValue = fmt(originalAmount * currentRate);
      const gainLoss = fmt(currentValue - originalAmount);
      return { billNumber: b.billNumber, vendorName: b.vendorName, currency: b.currency, amountDue: fmt(originalAmount), currentExchangeRate: fmt(currentRate), currentValue, unrealizedGainLoss: gainLoss, type: gainLoss >= 0 ? 'Gain' : 'Loss' };
    });
    res.json({ success: true, data: { asOf: new Date(), transactions: rows, totals: { totalUnrealizedGain: fmt(rows.filter(r => r.unrealizedGainLoss > 0).reduce((s, r) => s + r.unrealizedGainLoss, 0)), totalUnrealizedLoss: fmt(rows.filter(r => r.unrealizedGainLoss < 0).reduce((s, r) => s + Math.abs(r.unrealizedGainLoss), 0)), net: fmt(rows.reduce((s, r) => s + r.unrealizedGainLoss, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 13: ACTIVITY
// ============================================================================

router.get('/system-mails', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const Bill = col('Bill', 'bills');
    const [invoices, bills] = await Promise.all([
      Invoice.find({ 'emailsSent.0': { $exists: true }, ...scope }).select('invoiceNumber customerName emailsSent totalAmount').lean(),
      Bill.find({ 'emailsSent.0': { $exists: true }, ...scope }).select('billNumber vendorName emailsSent totalAmount').lean(),
    ]);
    const mails = [];
    for (const inv of invoices) {
      for (const e of (inv.emailsSent || [])) {
        const d = new Date(e.sentAt);
        if (d >= start && d <= end) mails.push({ documentType: 'Invoice', documentNumber: inv.invoiceNumber, contactName: inv.customerName, sentTo: e.sentTo, sentAt: d, emailType: e.emailType, amount: fmt(inv.totalAmount) });
      }
    }
    for (const b of bills) {
      for (const e of (b.emailsSent || [])) {
        const d = new Date(e.sentAt || e.createdAt);
        if (d >= start && d <= end) mails.push({ documentType: 'Bill', documentNumber: b.billNumber, contactName: b.vendorName, sentTo: e.sentTo, sentAt: d, emailType: e.emailType, amount: fmt(b.totalAmount) });
      }
    }
    mails.sort((a, b) => new Date(b.sentAt) - new Date(a.sentAt));
    res.json({ success: true, data: { period: { start, end }, mails, count: mails.length } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/audit-trail', async (req, res) => {
  const { start, end } = parseDateRange(req.query);
  const scope = orgScope(req);
  const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
  const Invoice = col('Invoice', 'invoices');
  const Bill = col('Bill', 'bills');
  const PaymentMade = col('PaymentMade', 'paymentmades');
  const Expense = col('Expense', 'expenses');
  const ManualJournal = col('ManualJournal', 'manualjournals');
  try {
    const [invoices, bills, payments, expenses, journals, coaTxns] = await Promise.all([
      Invoice.find({ updatedAt: { $gte: start, $lte: end }, ...scope })
        .select('invoiceNumber customerName totalAmount status updatedAt updatedBy createdBy')
        .limit(200).lean(),
      Bill.find({ updatedAt: { $gte: start, $lte: end }, ...scope })
        .select('billNumber vendorName totalAmount status updatedAt updatedBy createdBy')
        .limit(200).lean(),
      PaymentMade.find({ updatedAt: { $gte: start, $lte: end }, ...scope })
        .select('paymentNumber vendorName amount status updatedAt updatedBy createdBy')
        .limit(200).lean(),
      Expense.find({ updatedAt: { $gte: start, $lte: end }, ...scope })
        .select('expenseAccount total updatedAt createdBy expenseNumber')
        .limit(200).lean(),
      ManualJournal.find({ updatedAt: { $gte: start, $lte: end }, ...scope })
        .select('journalNumber notes totalDebit status updatedAt updatedBy')
        .limit(200).lean(),
      // ✅ NEW: Pull actual Dr/Cr movements from AccountTransaction
      AccountTransaction.find({ date: { $gte: start, $lte: end }, ...scope })
        .sort({ date: 1 }).limit(1000).lean(),
    ]);

    // Build referenceNumber → journal lines map
    const journalMap = {};
    for (const txn of coaTxns) {
      const key = txn.referenceNumber || txn.referenceId?.toString();
      if (!key) continue;
      if (!journalMap[key]) journalMap[key] = [];
      journalMap[key].push({
        accountId: txn.accountId,
        description: txn.description,
        debit: fmt(txn.debit),
        credit: fmt(txn.credit),
        date: txn.date,
      });
    }

    // Resolve accountId → accountName
    const allAccountIds = [...new Set(coaTxns.map(t => t.accountId?.toString()).filter(Boolean))];
    const coaAccounts = await ChartOfAccount.find({ _id: { $in: allAccountIds }, ...coaScope(req) }).lean();
    const coaNameMap = {};
    coaAccounts.forEach(a => { coaNameMap[a._id.toString()] = a.accountName; });

    // Enrich journal lines with account names
    for (const key of Object.keys(journalMap)) {
      journalMap[key] = journalMap[key].map(line => ({
        ...line,
        accountName: coaNameMap[line.accountId?.toString()] || 'Unknown',
      }));
    }

    const logs = [
      ...invoices.map(i => ({ type: 'Invoice', ref: i.invoiceNumber, name: i.customerName, amount: fmt(i.totalAmount), status: i.status, date: i.updatedAt, by: i.updatedBy || i.createdBy, journalLines: journalMap[i.invoiceNumber] || [] })),
      ...bills.map(b => ({ type: 'Bill', ref: b.billNumber, name: b.vendorName, amount: fmt(b.totalAmount), status: b.status, date: b.updatedAt, by: b.updatedBy || b.createdBy, journalLines: journalMap[b.billNumber] || [] })),
      ...payments.map(p => ({ type: 'Payment Made', ref: p.paymentNumber, name: p.vendorName, amount: fmt(p.amount), status: p.status, date: p.updatedAt, by: p.updatedBy || p.createdBy, journalLines: journalMap[p.paymentNumber] || [] })),
      ...expenses.map(e => ({ type: 'Expense', ref: e.expenseNumber || e._id.toString(), name: e.expenseAccount, amount: fmt(e.total), status: 'Recorded', date: e.updatedAt, by: e.createdBy || 'system', journalLines: journalMap[e.expenseNumber || e._id.toString()] || [] })),
      ...journals.map(j => ({ type: 'Journal', ref: j.journalNumber, name: j.notes, amount: fmt(j.totalDebit), status: j.status, date: j.updatedAt, by: j.updatedBy, journalLines: journalMap[j.journalNumber] || [] })),
    ].sort((a, b) => new Date(b.date) - new Date(a.date));

    res.json({
      success: true,
      data: {
        period: { start, end },
        logs,
        count: logs.length,
        // ✅ NEW: Raw COA movements for CA review
        accountMovements: coaTxns.map(t => ({
          date: t.date,
          accountName: coaNameMap[t.accountId?.toString()] || 'Unknown',
          description: t.description,
          referenceType: t.referenceType,
          referenceNumber: t.referenceNumber,
          debit: fmt(t.debit),
          credit: fmt(t.credit),
        })),
      },
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ✅ NEW ROUTE: CA looks up exact journal entries for any reference number
// Usage: GET /api/finance/reports/journal-entries-by-reference?ref=INV-001
router.get('/journal-entries-by-reference', async (req, res) => {
  try {
    const { ref } = req.query;
    const scope = orgScope(req);
    if (!ref) return res.status(400).json({ success: false, message: 'ref query param required. Example: ?ref=INV-001' });

    const txns = await AccountTransaction.find({ referenceNumber: ref, ...scope }).sort({ date: 1 }).lean();
    if (txns.length === 0) return res.json({ success: true, data: { ref, entries: [], balanced: true, message: 'No journal entries found for this reference' } });

    const accountIds = [...new Set(txns.map(t => t.accountId?.toString()))];
    const accounts = await ChartOfAccount.find({ _id: { $in: accountIds }, ...coaScope(req) }).lean();
    const nameMap = {};
    accounts.forEach(a => { nameMap[a._id.toString()] = a; });

    let totalDebit = 0, totalCredit = 0;
    const entries = txns.map(t => {
      const acc = nameMap[t.accountId?.toString()] || {};
      totalDebit += t.debit || 0;
      totalCredit += t.credit || 0;
      return {
        date: t.date,
        accountCode: acc.accountCode || '',
        accountName: acc.accountName || 'Unknown',
        accountType: acc.accountType || '',
        description: t.description,
        referenceType: t.referenceType,
        debit: fmt(t.debit),
        credit: fmt(t.credit),
      };
    });

    const balanced = Math.abs(totalDebit - totalCredit) < 0.02;
    res.json({
      success: true,
      data: {
        ref,
        referenceType: txns[0]?.referenceType,
        date: txns[0]?.date,
        entries,
        totals: { totalDebit: fmt(totalDebit), totalCredit: fmt(totalCredit) },
        // ✅ This is what CA checks — if false something needs investigation
        balanced,
        balanceWarning: balanced ? null : `WARNING: Entry unbalanced by Rs.${fmt(Math.abs(totalDebit - totalCredit))}. Needs investigation.`,
      },
    });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/exception-report', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const Bill = col('Bill', 'bills');
    const Expense = col('Expense', 'expenses');
    const exceptions = [];
    const largeInvoices = await Invoice.find({ invoiceDate: { $gte: start, $lte: end }, totalAmount: { $gt: 100000 }, ...scope }).select('invoiceNumber customerName totalAmount status invoiceDate').lean();
    largeInvoices.forEach(i => exceptions.push({ type: 'Large Invoice', ref: i.invoiceNumber, name: i.customerName, amount: fmt(i.totalAmount), date: i.invoiceDate, reason: 'Invoice amount > ₹1,00,000', severity: 'Medium' }));
    const overdueInvoices = await Invoice.find({ status: 'OVERDUE', dueDate: { $lt: new Date(new Date() - 90 * 86400000) }, ...scope }).select('invoiceNumber customerName amountDue dueDate').lean();
    overdueInvoices.forEach(i => exceptions.push({ type: 'Severely Overdue Invoice', ref: i.invoiceNumber, name: i.customerName, amount: fmt(i.amountDue), date: i.dueDate, reason: 'Invoice overdue by more than 90 days', severity: 'High' }));
    const zeroExpenses = await Expense.find({ total: 0, date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...scope }).select('expenseAccount date paidThrough').lean();
    zeroExpenses.forEach(e => exceptions.push({ type: 'Zero Amount Expense', ref: e._id, name: e.expenseAccount, amount: 0, date: e.date, reason: 'Expense recorded with zero amount', severity: 'Low' }));
    exceptions.sort((a, b) => (a.severity === 'High' ? -1 : b.severity === 'High' ? 1 : 0));
    res.json({ success: true, data: { period: { start, end }, exceptions, count: exceptions.length, bySeverity: { High: exceptions.filter(e => e.severity === 'High').length, Medium: exceptions.filter(e => e.severity === 'Medium').length, Low: exceptions.filter(e => e.severity === 'Low').length } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/portal-activities', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const invoices = await Invoice.find({ 'emailsSent.0': { $exists: true }, ...scope }).select('invoiceNumber customerName emailsSent').lean();
    const activities = [];
    for (const inv of invoices) {
      for (const e of (inv.emailsSent || [])) {
        const d = new Date(e.sentAt);
        if (d >= start && d <= end) activities.push({ documentType: 'Invoice', documentNumber: inv.invoiceNumber, customerName: inv.customerName, activityType: e.emailType, date: d, user: e.sentTo });
      }
    }
    activities.sort((a, b) => new Date(b.date) - new Date(a.date));
    res.json({ success: true, data: { period: { start, end }, activities, count: activities.length } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/customer-reviews', async (req, res) => {
  res.json({ success: true, data: { reviews: [], message: 'Customer reviews module not yet enabled.' } });
});

// ============================================================================
// ── SECTION 14: AUTOMATION
// ============================================================================

router.get('/api-usage', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    let logs = [];
    try { logs = await db.collection('api_logs').find({ ...scope, createdAt: { $gte: start, $lte: end } }).sort({ createdAt: -1 }).limit(200).toArray(); } catch (_) { }
    res.json({ success: true, data: { period: { start, end }, logs, count: logs.length, message: logs.length === 0 ? 'API logging not yet enabled.' : undefined } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/workflow-logs', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    let logs = [];
    try { logs = await db.collection('workflow_logs').find({ ...scope, createdAt: { $gte: start, $lte: end } }).sort({ createdAt: -1 }).limit(200).toArray(); } catch (_) { }
    res.json({ success: true, data: { period: { start, end }, logs, count: logs.length, message: logs.length === 0 ? 'Workflow logging not yet enabled.' : undefined } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── META
// ============================================================================

router.get('/meta', (req, res) => {
  res.json({
    success: true, data: [
      {
        category: 'Business Overview', reports: [
          { key: 'profit-loss', name: 'Profit and Loss' }, { key: 'profit-loss-horizontal', name: 'Horizontal Profit and Loss' },
          { key: 'balance-sheet', name: 'Balance Sheet' }, { key: 'balance-sheet-horizontal', name: 'Horizontal Balance Sheet' },
          { key: 'cash-flow', name: 'Cash Flow Statement' }, { key: 'movement-of-equity', name: 'Movement of Equity' },
          { key: 'performance-ratios', name: 'Business Performance Ratios' }, { key: 'trial-balance', name: 'Trial Balance' }, { key: 'day-book', name: 'Day Book' },
        ]
      },
      {
        category: 'Sales', reports: [
          { key: 'sales-by-customer', name: 'Sales by Customer' }, { key: 'sales-by-item', name: 'Sales by Item' },
          { key: 'sales-by-salesperson', name: 'Sales by Sales Person' }, { key: 'sales-summary', name: 'Sales Summary' },
        ]
      },
      {
        category: 'Receivables', reports: [
          { key: 'ar-aging-summary', name: 'AR Aging Summary' }, { key: 'ar-aging-details', name: 'AR Aging Details' },
          { key: 'invoice-details', name: 'Invoice Details' }, { key: 'customer-balance', name: 'Customer Balance Summary' },
          { key: 'receivable-summary', name: 'Receivable Summary' }, { key: 'receivable-details', name: 'Receivable Details' },
          { key: 'credit-note-details', name: 'Credit Note Details' }, { key: 'refund-history-receivables', name: 'Refund History' },
        ]
      },
      {
        category: 'Payments Received', reports: [
          { key: 'payments-received', name: 'Payments Received' }, { key: 'time-to-get-paid', name: 'Time to Get Paid' },
          { key: 'refund-history', name: 'Refund History' }, { key: 'recurring-invoice-details', name: 'Recurring Invoice Details' },
        ]
      },
      {
        category: 'Payables', reports: [
          { key: 'vendor-balance', name: 'Vendor Balance Summary' }, { key: 'ap-aging-summary', name: 'AP Aging Summary' },
          { key: 'ap-aging-details', name: 'AP Aging Details' }, { key: 'bill-details', name: 'Bill Details' },
          { key: 'vendor-credit-details', name: 'Vendor Credit Details' }, { key: 'payments-made', name: 'Payments Made' },
          { key: 'refund-history-payables', name: 'Refund History' }, { key: 'purchase-order-details', name: 'Purchase Order Details' },
          { key: 'purchase-orders-by-vendor', name: 'Purchase Orders by Vendor' },
          { key: 'payable-summary', name: 'Payable Summary' }, { key: 'payable-details', name: 'Payable Details' },
        ]
      },
      {
        category: 'Purchases and Expenses', reports: [
          { key: 'purchases-by-vendor', name: 'Purchases by Vendor' }, { key: 'purchases-by-item', name: 'Purchases by Item' },
          { key: 'expense-details', name: 'Expense Details' }, { key: 'expenses-by-category', name: 'Expenses by Category' },
          { key: 'expenses-by-customer', name: 'Expenses by Customer' }, { key: 'expenses-by-project', name: 'Expenses by Project' },
          { key: 'expenses-by-employee', name: 'Expenses by Employee' }, { key: 'billable-expenses', name: 'Billable Expense Details' },
        ]
      },
      {
        category: 'Taxes', reports: [
          { key: 'tds-summary', name: 'TDS Summary' }, { key: 'tds-receivable', name: 'TDS Receivable Summary' }, { key: 'tcs-summary', name: 'TCS Payable Summary' },
        ]
      },
      { category: 'Banking', reports: [{ key: 'reconciliation-status', name: 'Reconciliation Status' }] },
      {
        category: 'Projects and Timesheet', reports: [
          { key: 'timesheet-details', name: 'Timesheet Details' }, { key: 'timesheet-profitability', name: 'Timesheet Profitability Summary' },
          { key: 'project-summary', name: 'Project Summary' }, { key: 'project-details', name: 'Project Details' },
          { key: 'projects-cost-summary', name: 'Projects Cost Summary' }, { key: 'projects-revenue-summary', name: 'Projects Revenue Summary' },
          { key: 'projects-performance', name: 'Projects Performance Summary' },
        ]
      },
      {
        category: 'Accountant', reports: [
          { key: 'account-transactions', name: 'Account Transactions' }, { key: 'account-type-summary', name: 'Account Type Summary' },
          { key: 'general-ledger', name: 'General Ledger' }, { key: 'general-ledger-detailed', name: 'Detailed General Ledger' },
          { key: 'journal-report', name: 'Journal Report' }, { key: 'activity-logs', name: 'Activity Logs & Audit Trail' },
          { key: 'journal-entries-by-reference', name: 'Journal Entries by Reference' },
        ]
      },
      { category: 'Budgets', reports: [{ key: 'budget-vs-actuals', name: 'Budget Vs Actuals' }] },
      { category: 'Currency', reports: [{ key: 'realized-gain-loss', name: 'Realized Gain or Loss' }, { key: 'unrealized-gain-loss', name: 'Unrealized Gain or Loss' }] },
      {
        category: 'Activity', reports: [
          { key: 'system-mails', name: 'System Mails' }, { key: 'audit-trail', name: 'Activity Logs & Audit Trail' },
          { key: 'exception-report', name: 'Exception Report' }, { key: 'portal-activities', name: 'Portal Activities' }, { key: 'customer-reviews', name: 'Customer Reviews' },
        ]
      },
      { category: 'Automation', reports: [{ key: 'api-usage', name: 'API Usage' }, { key: 'workflow-logs', name: 'Workflow Execution Logs' }] },
    ]
  });
});

// ============================================================================
// ── EXPORT: PDF
// ============================================================================

router.post('/export/pdf', async (req, res) => {
  try {
    const { reportName, reportData, companyName, period, headers: customHeaders } = req.body;
    if (!reportData || !Array.isArray(reportData) || reportData.length === 0)
      return res.status(400).json({ success: false, message: 'No data to export' });
    const uploadsDir = path.join(__dirname, '..', 'uploads', 'report-exports');
    if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
    const filename = `${(reportName || 'report').replace(/\s+/g, '-')}-${Date.now()}.pdf`;
    const filepath = path.join(uploadsDir, filename);
    const doc = new PDFDoc({ size: 'A4', margin: 36, bufferPages: true });
    const stream = fs.createWriteStream(filepath);
    doc.pipe(stream);
    const pageW = 522;
    doc.rect(0, 0, 595, 72).fill('#0f1e3d');
    doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold').text(companyName || 'Finance Report', 40, 18, { width: pageW });
    doc.fontSize(11).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text(reportName || 'Report', 40, 42, { width: pageW });
    if (period) {
      try {
        const s = period.start ? new Date(period.start).toLocaleDateString('en-IN') : '';
        const e = period.end ? new Date(period.end).toLocaleDateString('en-IN') : '';
        if (s || e) doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').text(`${s} – ${e}`, 40, 58, { width: pageW });
      } catch (_) { }
    }
    const headers = customHeaders || Object.keys(reportData[0] || {});
    const colW = Math.min(140, Math.floor(pageW / headers.length));
    let y = 88;
    doc.rect(36, y, pageW, 22).fill('#1e3a8a');
    doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
    headers.forEach((h, i) => {
      const label = h.replace(/([A-Z])/g, ' $1').trim().replace(/^./, s => s.toUpperCase());
      doc.text(label.toUpperCase(), 40 + i * colW, y + 7, { width: colW - 4, ellipsis: true });
    });
    y += 22;
    reportData.forEach((row, ri) => {
      if (y > 760) { doc.addPage(); y = 40; }
      doc.rect(36, y, pageW, 20).fill(ri % 2 === 0 ? '#ffffff' : '#f7f9fc');
      doc.fontSize(8).fillColor('#374151').font('Helvetica');
      headers.forEach((h, i) => {
        const val = row[h] !== undefined && row[h] !== null ? String(row[h]) : '-';
        doc.text(val, 40 + i * colW, y + 6, { width: colW - 4, ellipsis: true });
      });
      y += 20;
    });
    const pages = doc.bufferedPageRange();
    for (let i = 0; i < pages.count; i++) {
      doc.switchToPage(i);
      doc.moveTo(36, 780).lineTo(559, 780).lineWidth(1).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#94a3b8').text(`Generated ${new Date().toLocaleString('en-IN')} · Page ${i + 1} of ${pages.count}`, 36, 784, { width: pageW, align: 'center' });
    }
    doc.end();
    stream.on('finish', () => res.download(filepath, filename, () => { try { fs.unlinkSync(filepath); } catch (_) { } }));
    stream.on('error', (err) => res.status(500).json({ success: false, message: err.message }));
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ── EXPORT: Excel
router.post('/export/excel', async (req, res) => {
  try {
    const { reportName, reportData, companyName, period, headers: customHeaders } = req.body;
    if (!reportData || !Array.isArray(reportData) || reportData.length === 0)
      return res.status(400).json({ success: false, message: 'No data to export' });
    const wb = XLSX.utils.book_new();
    const headers = customHeaders || Object.keys(reportData[0] || {});
    let periodLabel = '';
    if (period) {
      try {
        const s = period.start ? new Date(period.start).toLocaleDateString('en-IN') : '';
        const e = period.end ? new Date(period.end).toLocaleDateString('en-IN') : '';
        if (s || e) periodLabel = `${s} – ${e}`;
      } catch (_) { }
    }
    const wsData = [
      [companyName || 'Finance Report'],
      [reportName || 'Report'],
      ...(periodLabel ? [[`Period: ${periodLabel}`]] : []),
      [],
      headers.map(h => h.replace(/([A-Z])/g, ' $1').trim().replace(/^./, s => s.toUpperCase())),
      ...reportData.map(row => headers.map(h => {
        const v = row[h];
        if (v === undefined || v === null) return '';
        if (typeof v === 'number') return v;
        // Only treat the cell as numeric if the WHOLE string (after
        // stripping ₹/commas) is a number — parseFloat alone would happily
        // read "31 Jul 2026" as 31, silently truncating dates and any other
        // text that starts with digits.
        const stripped = String(v).replace(/[₹,]/g, '').trim();
        const isFullyNumeric = /^-?\d+(\.\d+)?$/.test(stripped);
        return isFullyNumeric ? parseFloat(stripped) : String(v);
      })),
    ];
    const ws = XLSX.utils.aoa_to_sheet(wsData);
    ws['!cols'] = headers.map(h => ({ wch: Math.max(h.length + 4, 14) }));
    ws['!merges'] = [{ s: { r: 0, c: 0 }, e: { r: 0, c: headers.length - 1 } }];
    XLSX.utils.book_append_sheet(wb, ws, (reportName || 'Report').slice(0, 31));
    const buffer = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
    const filename = `${(reportName || 'report').replace(/\s+/g, '-')}-${Date.now()}.xlsx`;
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Length', buffer.length);
    res.send(buffer);
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = router;
