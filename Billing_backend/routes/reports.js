// ============================================================================
// REPORTS - COMPLETE BACKEND (43 REPORTS)
// ============================================================================
// File: backend/routes/reports.js
// Register: app.use('/api/reports', require('./routes/reports'));
//
// Categories:
//  1. Business Overview  (9 reports)
//  2. Sales              (4 reports)
//  3. Receivables        (8 reports)
//  4. Payables           (8 reports)
//  5. Purchases/Expenses (5 reports)
//  6. Taxes              (3 reports)
//  7. Accountant         (6 reports)
// ============================================================================

const express   = require('express');
const router    = express.Router();
const mongoose  = require('mongoose');
const PDFDocument = require('pdfkit');
const XLSX      = require('xlsx');
const path      = require('path');
const fs        = require('fs');

// ── Models (lazy-load to avoid circular deps) ────────────────────────────────
const getModel = (name, collectionName) => {
  if (mongoose.models[name]) return mongoose.models[name];
  return mongoose.model(name, new mongoose.Schema({}, { strict: false }), collectionName);
};

// ── Auth middleware ──────────────────────────────────────────────────────────
const { verifyFinanceJWT } = require('../middleware/finance_jwt');
const authenticate = verifyFinanceJWT;

// ── COA models ───────────────────────────────────────────────────────────────
const { ChartOfAccount, AccountTransaction } = require('./chart_of_accounts');

// ── Financial year helpers ───────────────────────────────────────────────────
// India: April 1 → March 31
function getFinancialYear(date = new Date()) {
  const m = date.getMonth(); // 0-indexed
  const y = date.getFullYear();
  return m >= 3 ? { start: new Date(y, 3, 1), end: new Date(y + 1, 2, 31, 23, 59, 59) }
                : { start: new Date(y - 1, 3, 1), end: new Date(y, 2, 31, 23, 59, 59) };
}

function getLastFinancialYear() {
  const fy = getFinancialYear();
  return { start: new Date(fy.start.getFullYear() - 1, 3, 1), end: new Date(fy.start.getFullYear(), 2, 31, 23, 59, 59) };
}

// ── Date range parser ────────────────────────────────────────────────────────
function parseDateRange(query) {
  const { fromDate, toDate, period } = query;
  const now = new Date();

  if (period) {
    switch (period) {
      case 'this_month': {
        const s = new Date(now.getFullYear(), now.getMonth(), 1);
        const e = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);
        return { start: s, end: e };
      }
      case 'last_month': {
        const s = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const e = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
        return { start: s, end: e };
      }
      case 'this_quarter': {
        const q = Math.floor(now.getMonth() / 3);
        const s = new Date(now.getFullYear(), q * 3, 1);
        const e = new Date(now.getFullYear(), q * 3 + 3, 0, 23, 59, 59);
        return { start: s, end: e };
      }
      case 'this_fy':    return getFinancialYear();
      case 'last_fy':    return getLastFinancialYear();
      default: break;
    }
  }

  const start = fromDate ? new Date(fromDate) : getFinancialYear().start;
  const end   = toDate   ? new Date(new Date(toDate).setHours(23, 59, 59)) : new Date();
  return { start, end };
}

// ── COA account type groupings ───────────────────────────────────────────────
const INCOME_TYPES   = ['Income', 'Other Income'];
const EXPENSE_TYPES  = ['Expense', 'Cost Of Goods Sold', 'Other Expense'];
const ASSET_TYPES    = ['Asset', 'Accounts Receivable', 'Other Current Asset', 'Fixed Asset', 'Cash', 'Stock', 'Other Asset'];
const LIABILITY_TYPES= ['Liability', 'Accounts Payable', 'Other Current Liability', 'Non Current Liability', 'Other Liability'];
const EQUITY_TYPES   = ['Equity'];

// ── Formatters ───────────────────────────────────────────────────────────────
const fmt = (n) => Math.round((n || 0) * 100) / 100;

// ── Company filter helper ────────────────────────────────────────────────────
function companyFilter(req) {
  const orgId = req.user?.orgId || req.user?.companyId || req.query.orgId || 'default';
  return orgId;
}

// ============================================================================
// SECTION 1 — BUSINESS OVERVIEW (9 reports)
// ============================================================================

// ── 1.1 Profit & Loss ────────────────────────────────────────────────────────
router.get('/profit-loss', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    // Get all COA accounts for income/expense
    const accounts = await ChartOfAccount.find({
      accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] },
      isActive: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const accountIds = accounts.map(a => a._id);

    // Aggregate transactions
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: accountIds }, date: { $gte: start, $lte: end }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
    ]);

    const txnMap = {};
    txns.forEach(t => { txnMap[t._id.toString()] = t; });

    const income   = [];
    const cogs     = [];
    const expenses = [];

    let totalIncome   = 0;
    let totalCOGS     = 0;
    let totalExpenses = 0;

    for (const acc of accounts) {
      const t = txnMap[acc._id.toString()] || { totalDebit: 0, totalCredit: 0 };
      // For income accounts: credit increases, debit decreases
      const net = INCOME_TYPES.includes(acc.accountType)
        ? fmt(t.totalCredit - t.totalDebit)
        : fmt(t.totalDebit - t.totalCredit);

      const row = { accountName: acc.accountName, accountCode: acc.accountCode, amount: net };

      if (INCOME_TYPES.includes(acc.accountType)) {
        income.push(row);
        totalIncome += net;
      } else if (acc.accountType === 'Cost Of Goods Sold') {
        cogs.push(row);
        totalCOGS += net;
      } else {
        expenses.push(row);
        totalExpenses += net;
      }
    }

    const grossProfit = fmt(totalIncome - totalCOGS);
    const netProfit   = fmt(grossProfit - totalExpenses);

    res.json({
      success: true,
      data: {
        period: { start, end },
        income:        { items: income,   total: fmt(totalIncome) },
        costOfGoods:   { items: cogs,     total: fmt(totalCOGS) },
        grossProfit,
        operatingExpenses: { items: expenses, total: fmt(totalExpenses) },
        netProfit,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.2 Balance Sheet ─────────────────────────────────────────────────────────
router.get('/balance-sheet', authenticate, async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);

    const accounts = await ChartOfAccount.find({
      accountType: { $in: [...ASSET_TYPES, ...LIABILITY_TYPES, ...EQUITY_TYPES] },
      isActive: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const accountIds = accounts.map(a => a._id);

    // All transactions up to end date
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: accountIds }, date: { $lte: end }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
    ]);

    const txnMap = {};
    txns.forEach(t => { txnMap[t._id.toString()] = t; });

    const assets      = [];
    const liabilities = [];
    const equity      = [];

    let totalAssets      = 0;
    let totalLiabilities = 0;
    let totalEquity      = 0;

    for (const acc of accounts) {
      const t = txnMap[acc._id.toString()] || { totalDebit: 0, totalCredit: 0 };
      // Assets: debit increases; Liabilities & Equity: credit increases
      const net = ASSET_TYPES.includes(acc.accountType)
        ? fmt(t.totalDebit - t.totalCredit)
        : fmt(t.totalCredit - t.totalDebit);

      const row = { accountName: acc.accountName, accountCode: acc.accountCode, accountType: acc.accountType, amount: net };

      if (ASSET_TYPES.includes(acc.accountType)) {
        assets.push(row);
        totalAssets += net;
      } else if (LIABILITY_TYPES.includes(acc.accountType)) {
        liabilities.push(row);
        totalLiabilities += net;
      } else {
        equity.push(row);
        totalEquity += net;
      }
    }

    res.json({
      success: true,
      data: {
        asOf: end,
        assets:      { items: assets,      total: fmt(totalAssets) },
        liabilities: { items: liabilities, total: fmt(totalLiabilities) },
        equity:      { items: equity,      total: fmt(totalEquity) },
        totalLiabilitiesAndEquity: fmt(totalLiabilities + totalEquity),
        balanced: Math.abs(totalAssets - (totalLiabilities + totalEquity)) < 0.01,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.3 Cash Flow Statement ───────────────────────────────────────────────────
router.get('/cash-flow', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    // Get cash/bank accounts
    const cashAccounts = await ChartOfAccount.find({
      accountType: { $in: ['Cash', 'Asset'] },
      isActive: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const ids = cashAccounts.map(a => a._id);

    const txns = await AccountTransaction.find({
      accountId: { $in: ids },
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: 1 }).lean();

    // Group by referenceType
    const operating = txns.filter(t => ['Invoice', 'Bill', 'Payment', 'Expense'].includes(t.referenceType));
    const investing  = txns.filter(t => ['Journal'].includes(t.referenceType));

    const operatingIn  = fmt(operating.reduce((s, t) => s + (t.debit  || 0), 0));
    const operatingOut = fmt(operating.reduce((s, t) => s + (t.credit || 0), 0));
    const investingIn  = fmt(investing.reduce((s,  t) => s + (t.debit  || 0), 0));
    const investingOut = fmt(investing.reduce((s,  t) => s + (t.credit || 0), 0));

    res.json({
      success: true,
      data: {
        period: { start, end },
        operating: {
          inflows:  operatingIn,
          outflows: operatingOut,
          net:      fmt(operatingIn - operatingOut),
          items:    operating.slice(0, 100).map(t => ({
            date: t.date, description: t.description,
            referenceType: t.referenceType, referenceNumber: t.referenceNumber,
            debit: t.debit, credit: t.credit,
          })),
        },
        investing: {
          inflows:  investingIn,
          outflows: investingOut,
          net:      fmt(investingIn - investingOut),
        },
        netCashChange: fmt((operatingIn - operatingOut) + (investingIn - investingOut)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.4 Trial Balance ─────────────────────────────────────────────────────────
router.get('/trial-balance', authenticate, async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);

    const accounts = await ChartOfAccount.find({
      isActive: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ accountCode: 1 }).lean();    const accountIds = accounts.map(a => a._id);

    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: accountIds }, date: { $lte: end }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
    ]);

    const txnMap = {};
    txns.forEach(t => { txnMap[t._id.toString()] = t; });

    let grandDebit  = 0;
    let grandCredit = 0;

    const rows = accounts.map(acc => {
      const t = txnMap[acc._id.toString()] || { totalDebit: 0, totalCredit: 0 };
      const debit  = fmt(t.totalDebit);
      const credit = fmt(t.totalCredit);
      grandDebit  += debit;
      grandCredit += credit;
      return {
        accountCode: acc.accountCode,
        accountName: acc.accountName,
        accountType: acc.accountType,
        debit,
        credit,
        balance:     fmt(debit - credit),
      };
    }).filter(r => r.debit > 0 || r.credit > 0);

    res.json({
      success: true,
      data: {
        asOf: end,
        accounts: rows,
        totals: { debit: fmt(grandDebit), credit: fmt(grandCredit) },
        balanced: Math.abs(grandDebit - grandCredit) < 0.01,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.5 Business Performance Ratios ──────────────────────────────────────────
router.get('/performance-ratios', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const fyEnd = end;

    const incomeAccounts  = await ChartOfAccount.find({ accountType: { $in: INCOME_TYPES },   ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) }).lean();
    const expenseAccounts = await ChartOfAccount.find({ accountType: { $in: EXPENSE_TYPES },  ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) }).lean();
    const assetAccounts   = await ChartOfAccount.find({ accountType: { $in: ASSET_TYPES },    ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) }).lean();
    const liabAccounts    = await ChartOfAccount.find({ accountType: { $in: LIABILITY_TYPES }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) }).lean();

    const sumTxns = async (ids, field, dateFilter, orgId = null) => {
      const result = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, ...dateFilter, ...(orgId ? { orgId } : {}) } },
        { $group: { _id: null, total: { $sum: `$${field}` } } },
      ]);
      return result[0]?.total || 0;
    };

    const dateFilter = { date: { $gte: start, $lte: end } };
    const endFilter  = { date: { $lte: fyEnd } };

    const incomeIds  = incomeAccounts.map(a => a._id);
    const expenseIds = expenseAccounts.map(a => a._id);
    const assetIds   = assetAccounts.map(a => a._id);
    const liabIds    = liabAccounts.map(a => a._id);

    const [totalRevenue, totalExpenses, totalAssets, totalLiabilities] = await Promise.all([
      sumTxns(incomeIds,  'credit', dateFilter, req.user?.orgId),
      sumTxns(expenseIds, 'debit',  dateFilter, req.user?.orgId),
      sumTxns(assetIds,   'debit',  endFilter,  req.user?.orgId),
      sumTxns(liabIds,    'credit', endFilter,  req.user?.orgId),
    ]);

    const grossProfit = totalRevenue - totalExpenses;
    const netProfit   = grossProfit;
    const equity      = totalAssets - totalLiabilities;

    res.json({
      success: true,
      data: {
        period: { start, end },
        grossProfitMargin:   totalRevenue  > 0 ? fmt((grossProfit / totalRevenue) * 100) : 0,
        netProfitMargin:     totalRevenue  > 0 ? fmt((netProfit   / totalRevenue) * 100) : 0,
        returnOnAssets:      totalAssets   > 0 ? fmt((netProfit   / totalAssets)  * 100) : 0,
        returnOnEquity:      equity        > 0 ? fmt((netProfit   / equity)       * 100) : 0,
        debtToEquityRatio:   equity        > 0 ? fmt(totalLiabilities / equity)          : 0,
        currentRatio:        totalLiabilities > 0 ? fmt(totalAssets / totalLiabilities)  : 0,
        totalRevenue:        fmt(totalRevenue),
        totalExpenses:       fmt(totalExpenses),
        netProfit:           fmt(netProfit),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.6 Horizontal P&L ───────────────────────────────────────────────────────
router.get('/profit-loss-horizontal', authenticate, async (req, res) => {
  try {
    // Same data as P&L but structured as current vs previous period comparison
    const { start, end } = parseDateRange(req.query);
    const periodDays = (end - start) / (1000 * 60 * 60 * 24);
    const prevEnd    = new Date(start - 1);
    const prevStart  = new Date(start - periodDays * 24 * 60 * 60 * 1000);

    const fetchPL = async (s, e, orgId) => {
      const accounts = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, ...(orgId ? { orgId } : {}) }).lean();
      const ids = accounts.map(a => a._id);
      const txns = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, date: { $gte: s, $lte: e }, ...(orgId ? { orgId } : {}) } },
        { $group: { _id: '$accountId', totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
      ]);
      const map = {};
      txns.forEach(t => { map[t._id.toString()] = t; });
      let income = 0, expenses = 0;
      for (const acc of accounts) {
        const t = map[acc._id.toString()] || { totalDebit: 0, totalCredit: 0 };
        if (INCOME_TYPES.includes(acc.accountType)) income += t.totalCredit - t.totalDebit;
        else expenses += t.totalDebit - t.totalCredit;
      }
      return { income: fmt(income), expenses: fmt(expenses), netProfit: fmt(income - expenses) };
    };

    const [current, previous] = await Promise.all([fetchPL(start, end, req.user?.orgId), fetchPL(prevStart, prevEnd, req.user?.orgId)]);
    const change = (curr, prev) => prev !== 0 ? fmt(((curr - prev) / Math.abs(prev)) * 100) : 0;

    res.json({
      success: true,
      data: {
        current:  { period: { start, end }, ...current },
        previous: { period: { start: prevStart, end: prevEnd }, ...previous },
        changes: {
          income:    { absolute: fmt(current.income - previous.income),    percent: change(current.income, previous.income) },
          expenses:  { absolute: fmt(current.expenses - previous.expenses), percent: change(current.expenses, previous.expenses) },
          netProfit: { absolute: fmt(current.netProfit - previous.netProfit), percent: change(current.netProfit, previous.netProfit) },
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.7 Horizontal Balance Sheet ──────────────────────────────────────────────
router.get('/balance-sheet-horizontal', authenticate, async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const fy = getFinancialYear(end);
    const prevEnd = new Date(fy.start - 1);

    const fetchBS = async (e, orgId) => {
      const accounts = await ChartOfAccount.find({ accountType: { $in: [...ASSET_TYPES, ...LIABILITY_TYPES, ...EQUITY_TYPES] }, ...(orgId ? { orgId } : {}) }).lean();
      const ids = accounts.map(a => a._id);
      const txns = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, date: { $lte: e }, ...(orgId ? { orgId } : {}) } },
        { $group: { _id: '$accountId', totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
      ]);
      const map = {};
      txns.forEach(t => { map[t._id.toString()] = t; });
      let assets = 0, liabilities = 0, equity = 0;
      for (const acc of accounts) {
        const t = map[acc._id.toString()] || { totalDebit: 0, totalCredit: 0 };
        const net = ASSET_TYPES.includes(acc.accountType) ? t.totalDebit - t.totalCredit : t.totalCredit - t.totalDebit;
        if (ASSET_TYPES.includes(acc.accountType)) assets += net;
        else if (LIABILITY_TYPES.includes(acc.accountType)) liabilities += net;
        else equity += net;
      }
      return { assets: fmt(assets), liabilities: fmt(liabilities), equity: fmt(equity) };
    };

    const [current, previous] = await Promise.all([fetchBS(end, req.user?.orgId), fetchBS(prevEnd, req.user?.orgId)]);

    res.json({
      success: true,
      data: {
        current:  { asOf: end, ...current },
        previous: { asOf: prevEnd, ...previous },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.8 Movement of Equity ────────────────────────────────────────────────────
router.get('/movement-of-equity', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    const equityAccounts = await ChartOfAccount.find({
      accountType: { $in: EQUITY_TYPES },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    const ids = equityAccounts.map(a => a._id);

    const openingTxns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $lt: start }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
    ]);

    const periodTxns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
    ]);

    const openingMap = {};
    openingTxns.forEach(t => { openingMap[t._id.toString()] = t; });
    const periodMap = {};
    periodTxns.forEach(t => { periodMap[t._id.toString()] = t; });

    const rows = equityAccounts.map(acc => {
      const o = openingMap[acc._id.toString()] || { totalDebit: 0, totalCredit: 0 };
      const p = periodMap[acc._id.toString()]  || { totalDebit: 0, totalCredit: 0 };
      const opening = fmt(o.totalCredit - o.totalDebit);
      const change  = fmt(p.totalCredit - p.totalDebit);
      return { accountName: acc.accountName, opening, change, closing: fmt(opening + change) };
    });

    res.json({
      success: true,
      data: {
        period: { start, end },
        accounts: rows,
        totals: {
          opening: fmt(rows.reduce((s, r) => s + r.opening, 0)),
          change:  fmt(rows.reduce((s, r) => s + r.change,  0)),
          closing: fmt(rows.reduce((s, r) => s + r.closing, 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 1.9 Day Book ─────────────────────────────────────────────────────────────
router.get('/day-book', authenticate, async (req, res) => {
  try {
    const date = req.query.date ? new Date(req.query.date) : new Date();
    const start = new Date(date.setHours(0,  0,  0,  0));
    const end   = new Date(date.setHours(23, 59, 59, 999));

    const txns = await AccountTransaction.find({
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: 1 }).limit(500).lean();

    const accountIds = [...new Set(txns.map(t => t.accountId.toString()))];
    const accounts = await ChartOfAccount.find({
      _id: { $in: accountIds },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    const accMap = {};
    accounts.forEach(a => { accMap[a._id.toString()] = a; });

    const enriched = txns.map(t => ({
      ...t,
      accountName: accMap[t.accountId.toString()]?.accountName || '',
      accountType: accMap[t.accountId.toString()]?.accountType || '',
    }));

    res.json({
      success: true,
      data: {
        date: start,
        transactions: enriched,
        totals: {
          debit:  fmt(enriched.reduce((s, t) => s + (t.debit  || 0), 0)),
          credit: fmt(enriched.reduce((s, t) => s + (t.credit || 0), 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// SECTION 2 — SALES (4 reports)
// ============================================================================

// ── 2.1 Sales by Customer ─────────────────────────────────────────────────────
router.get('/sales-by-customer', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Invoice = getModel('Invoice', 'invoices');

    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$customerId',
          customerName:  { $first: '$customerName' },
          customerEmail: { $first: '$customerEmail' },
          invoiceCount:  { $sum: 1 },
          totalAmount:   { $sum: '$totalAmount' },
          totalPaid:     { $sum: '$amountPaid' },
          totalDue:      { $sum: '$amountDue' },
      }},
      { $sort: { totalAmount: -1 } },
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        customers: rows.map(r => ({ ...r, totalAmount: fmt(r.totalAmount), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })),
        totals: {
          invoiceCount: rows.reduce((s, r) => s + r.invoiceCount, 0),
          totalAmount:  fmt(rows.reduce((s, r) => s + r.totalAmount, 0)),
          totalPaid:    fmt(rows.reduce((s, r) => s + r.totalPaid,   0)),
          totalDue:     fmt(rows.reduce((s, r) => s + r.totalDue,    0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 2.2 Sales by Item ─────────────────────────────────────────────────────────
router.get('/sales-by-item', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Invoice = getModel('Invoice', 'invoices');

    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $unwind: '$items' },
      { $group: {
          _id: '$items.itemDetails',
          quantity:    { $sum: '$items.quantity' },
          totalAmount: { $sum: '$items.amount' },
          invoiceCount:{ $sum: 1 },
          avgRate:     { $avg: '$items.rate' },
      }},
      { $sort: { totalAmount: -1 } },
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        items: rows.map(r => ({
          itemName:     r._id,
          quantity:     fmt(r.quantity),
          totalAmount:  fmt(r.totalAmount),
          invoiceCount: r.invoiceCount,
          avgRate:      fmt(r.avgRate),
        })),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 2.3 Sales Summary ─────────────────────────────────────────────────────────
router.get('/sales-summary', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Invoice = getModel('Invoice', 'invoices');

    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$invoiceDate' } },
          invoiceCount: { $sum: 1 },
          totalAmount:  { $sum: '$totalAmount' },
          totalTax:     { $sum: { $add: ['$cgst', '$sgst', '$igst'] } },
          totalPaid:    { $sum: '$amountPaid' },
          totalDue:     { $sum: '$amountDue' },
      }},
      { $sort: { _id: 1 } },
    ]);

    const stats = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$status',
          count:  { $sum: 1 },
          amount: { $sum: '$totalAmount' },
      }},
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        dailySummary: rows.map(r => ({ date: r._id, invoiceCount: r.invoiceCount, totalAmount: fmt(r.totalAmount), totalTax: fmt(r.totalTax), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })),
        byStatus: stats,
        totals: {
          invoiceCount: rows.reduce((s, r) => s + r.invoiceCount, 0),
          totalAmount:  fmt(rows.reduce((s, r) => s + r.totalAmount, 0)),
          totalTax:     fmt(rows.reduce((s, r) => s + r.totalTax,    0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 2.4 Sales by Salesperson ──────────────────────────────────────────────────
router.get('/sales-by-salesperson', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Invoice = getModel('Invoice', 'invoices');

    const rows = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT', 'CANCELLED'] }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: { $ifNull: ['$salesperson', 'Unassigned'] },
          invoiceCount: { $sum: 1 },
          totalAmount:  { $sum: '$totalAmount' },
          totalPaid:    { $sum: '$amountPaid' },
          totalDue:     { $sum: '$amountDue' },
      }},
      { $sort: { totalAmount: -1 } },
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        salespersons: rows.map(r => ({ salesperson: r._id, invoiceCount: r.invoiceCount, totalAmount: fmt(r.totalAmount), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// SECTION 3 — RECEIVABLES (8 reports)
// ============================================================================

// ── 3.1 AR Aging Summary ──────────────────────────────────────────────────────
router.get('/ar-aging-summary', authenticate, async (req, res) => {
  try {
    const today = new Date();
    const Invoice = getModel('Invoice', 'invoices');

    const invoices = await Invoice.find({
      status: { $in: ['UNPAID', 'PARTIALLY_PAID', 'OVERDUE', 'SENT'] },
      amountDue: { $gt: 0 },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const buckets = { current: 0, '1-30': 0, '31-60': 0, '61-90': 0, '90+': 0 };
    const counts  = { current: 0, '1-30': 0, '31-60': 0, '61-90': 0, '90+': 0 };

    for (const inv of invoices) {
      const days = Math.floor((today - new Date(inv.dueDate)) / (1000 * 60 * 60 * 24));
      const due  = inv.amountDue || 0;
      if (days <= 0)       { buckets.current += due; counts.current++; }
      else if (days <= 30) { buckets['1-30']  += due; counts['1-30']++; }
      else if (days <= 60) { buckets['31-60'] += due; counts['31-60']++; }
      else if (days <= 90) { buckets['61-90'] += due; counts['61-90']++; }
      else                 { buckets['90+']   += due; counts['90+']++; }
    }

    const total = Object.values(buckets).reduce((s, v) => s + v, 0);

    res.json({
      success: true,
      data: {
        asOf: today,
        buckets: Object.keys(buckets).map(k => ({ range: k, amount: fmt(buckets[k]), count: counts[k], percent: total > 0 ? fmt((buckets[k] / total) * 100) : 0 })),
        total: fmt(total),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3.2 AR Aging Details ─────────────────────────────────────────────────────
router.get('/ar-aging-details', authenticate, async (req, res) => {
  try {
    const today = new Date();
    const Invoice = getModel('Invoice', 'invoices');

    const invoices = await Invoice.find({
      status: { $in: ['UNPAID', 'PARTIALLY_PAID', 'OVERDUE', 'SENT'] },
      amountDue: { $gt: 0 },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ dueDate: 1 }).lean();

    const rows = invoices.map(inv => {
      const daysOverdue = Math.floor((today - new Date(inv.dueDate)) / (1000 * 60 * 60 * 24));
      let bucket;
      if (daysOverdue <= 0)       bucket = 'Current';
      else if (daysOverdue <= 30) bucket = '1-30 days';
      else if (daysOverdue <= 60) bucket = '31-60 days';
      else if (daysOverdue <= 90) bucket = '61-90 days';
      else                        bucket = 'Over 90 days';

      return {
        invoiceNumber: inv.invoiceNumber,
        customerName:  inv.customerName,
        customerEmail: inv.customerEmail,
        invoiceDate:   inv.invoiceDate,
        dueDate:       inv.dueDate,
        totalAmount:   fmt(inv.totalAmount),
        amountPaid:    fmt(inv.amountPaid),
        amountDue:     fmt(inv.amountDue),
        daysOverdue:   Math.max(0, daysOverdue),
        bucket,
        status:        inv.status,
      };
    });

    res.json({
      success: true,
      data: {
        asOf: today,
        invoices: rows,
        total: fmt(rows.reduce((s, r) => s + r.amountDue, 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3.3 Customer Balance Summary ─────────────────────────────────────────────
router.get('/customer-balance', authenticate, async (req, res) => {
  try {
    const Invoice = getModel('Invoice', 'invoices');

    const rows = await Invoice.aggregate([
      { $match: { status: { $nin: ['DRAFT', 'CANCELLED'] }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$customerId',
          customerName:  { $first: '$customerName' },
          customerEmail: { $first: '$customerEmail' },
          invoiceCount:  { $sum: 1 },
          totalInvoiced: { $sum: '$totalAmount' },
          totalPaid:     { $sum: '$amountPaid' },
          totalDue:      { $sum: '$amountDue' },
      }},
      { $sort: { totalDue: -1 } },
    ]);

    res.json({
      success: true,
      data: {
        customers: rows.map(r => ({ customerId: r._id, customerName: r.customerName, customerEmail: r.customerEmail, invoiceCount: r.invoiceCount, totalInvoiced: fmt(r.totalInvoiced), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })),
        totals: {
          totalInvoiced: fmt(rows.reduce((s, r) => s + r.totalInvoiced, 0)),
          totalPaid:     fmt(rows.reduce((s, r) => s + r.totalPaid,     0)),
          totalDue:      fmt(rows.reduce((s, r) => s + r.totalDue,      0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3.4 Invoice Details ───────────────────────────────────────────────────────
router.get('/invoice-details', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const { status, customerId } = req.query;
    const Invoice = getModel('Invoice', 'invoices');

    const query = { invoiceDate: { $gte: start, $lte: end } };
    if (status)     query.status     = status;
    if (customerId) query.customerId = customerId;
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const invoices = await Invoice.find(query).sort({ invoiceDate: -1 }).limit(500).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        invoices: invoices.map(inv => ({
          invoiceNumber: inv.invoiceNumber,
          customerName:  inv.customerName,
          customerEmail: inv.customerEmail,
          invoiceDate:   inv.invoiceDate,
          dueDate:       inv.dueDate,
          status:        inv.status,
          subTotal:      fmt(inv.subTotal),
          totalTax:      fmt((inv.cgst || 0) + (inv.sgst || 0) + (inv.igst || 0)),
          totalAmount:   fmt(inv.totalAmount),
          amountPaid:    fmt(inv.amountPaid),
          amountDue:     fmt(inv.amountDue),
        })),
        totals: {
          count:       invoices.length,
          totalAmount: fmt(invoices.reduce((s, i) => s + i.totalAmount, 0)),
          totalPaid:   fmt(invoices.reduce((s, i) => s + i.amountPaid, 0)),
          totalDue:    fmt(invoices.reduce((s, i) => s + i.amountDue, 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3.5 Payments Received ─────────────────────────────────────────────────────
router.get('/payments-received', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    // payments-received collection uses paymentDate as string DD/MM/YYYY
    // We query from our AccountTransaction with referenceType=Payment
    const txns = await AccountTransaction.find({
      referenceType: 'Payment',
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: -1 }).limit(500).lean();

    // Also get from invoices.payments array
    const Invoice = getModel('Invoice', 'invoices');
    const invoices = await Invoice.find({
      'payments.paymentDate': { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const paymentRows = [];
    for (const inv of invoices) {
      for (const p of (inv.payments || [])) {
        if (new Date(p.paymentDate) >= start && new Date(p.paymentDate) <= end) {
          paymentRows.push({
            invoiceNumber: inv.invoiceNumber,
            customerName:  inv.customerName,
            paymentDate:   p.paymentDate,
            amount:        fmt(p.amount),
            paymentMethod: p.paymentMethod,
            referenceNumber: p.referenceNumber,
          });
        }
      }
    }

    res.json({
      success: true,
      data: {
        period: { start, end },
        payments: paymentRows,
        total: fmt(paymentRows.reduce((s, p) => s + p.amount, 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3.6 Credit Note Details ───────────────────────────────────────────────────
router.get('/credit-note-details', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const CreditNote = getModel('CreditNote', 'creditnotes');

    const notes = await CreditNote.find({
      creditNoteDate: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ creditNoteDate: -1 }).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        creditNotes: notes.map(cn => ({
          creditNoteNumber: cn.creditNoteNumber,
          customerName:     cn.customerName,
          creditNoteDate:   cn.creditNoteDate,
          reason:           cn.reason,
          status:           cn.status,
          totalAmount:      fmt(cn.totalAmount),
          creditBalance:    fmt(cn.creditBalance),
          creditUsed:       fmt(cn.creditUsed),
        })),
        totals: {
          count:       notes.length,
          totalAmount: fmt(notes.reduce((s, n) => s + (n.totalAmount || 0), 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3.7 Receivable Summary ────────────────────────────────────────────────────
router.get('/receivable-summary', authenticate, async (req, res) => {
  try {
    const Invoice = getModel('Invoice', 'invoices');

    const stats = await Invoice.aggregate([
      { $match: { ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$status',
          count:  { $sum: 1 },
          amount: { $sum: '$totalAmount' },
          due:    { $sum: '$amountDue' },
          paid:   { $sum: '$amountPaid' },
      }},
    ]);

    const totalInvoiced = fmt(stats.reduce((s, st) => s + st.amount, 0));
    const totalDue      = fmt(stats.reduce((s, st) => s + st.due,    0));
    const totalPaid     = fmt(stats.reduce((s, st) => s + st.paid,   0));

    res.json({
      success: true,
      data: {
        byStatus: stats.map(st => ({ status: st._id, count: st.count, amount: fmt(st.amount), due: fmt(st.due), paid: fmt(st.paid) })),
        totals: { totalInvoiced, totalDue, totalPaid },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3.8 Refund History (Receivables) ─────────────────────────────────────────
router.get('/refund-history-receivables', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const CreditNote = getModel('CreditNote', 'creditnotes');

    const notes = await CreditNote.find({
      'refunds.0': { $exists: true },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const refunds = [];
    for (const cn of notes) {
      for (const r of (cn.refunds || [])) {
        if (new Date(r.refundDate) >= start && new Date(r.refundDate) <= end) {
          refunds.push({
            creditNoteNumber: cn.creditNoteNumber,
            customerName:     cn.customerName,
            refundDate:       r.refundDate,
            amount:           fmt(r.amount),
            refundMethod:     r.refundMethod,
            referenceNumber:  r.referenceNumber,
            notes:            r.notes,
          });
        }
      }
    }

    res.json({
      success: true,
      data: {
        period: { start, end },
        refunds,
        total: fmt(refunds.reduce((s, r) => s + r.amount, 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// SECTION 4 — PAYABLES (8 reports)
// ============================================================================

// ── 4.1 AP Aging Summary ──────────────────────────────────────────────────────
router.get('/ap-aging-summary', authenticate, async (req, res) => {
  try {
    const today = new Date();
    const Bill = getModel('Bill', 'billingbills');

    const bills = await Bill.find({
      status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] },
      amountDue: { $gt: 0 },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const buckets = { current: 0, '1-30': 0, '31-60': 0, '61-90': 0, '90+': 0 };
    const counts  = { current: 0, '1-30': 0, '31-60': 0, '61-90': 0, '90+': 0 };

    for (const bill of bills) {
      const days = Math.floor((today - new Date(bill.dueDate)) / (1000 * 60 * 60 * 24));
      const due  = bill.amountDue || 0;
      if (days <= 0)       { buckets.current += due; counts.current++; }
      else if (days <= 30) { buckets['1-30']  += due; counts['1-30']++; }
      else if (days <= 60) { buckets['31-60'] += due; counts['31-60']++; }
      else if (days <= 90) { buckets['61-90'] += due; counts['61-90']++; }
      else                 { buckets['90+']   += due; counts['90+']++; }
    }

    const total = Object.values(buckets).reduce((s, v) => s + v, 0);

    res.json({
      success: true,
      data: {
        asOf: today,
        buckets: Object.keys(buckets).map(k => ({ range: k, amount: fmt(buckets[k]), count: counts[k], percent: total > 0 ? fmt((buckets[k] / total) * 100) : 0 })),
        total: fmt(total),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4.2 AP Aging Details ──────────────────────────────────────────────────────
router.get('/ap-aging-details', authenticate, async (req, res) => {
  try {
    const today = new Date();
    const Bill = getModel('Bill', 'billingbills');

    const bills = await Bill.find({
      status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] },
      amountDue: { $gt: 0 },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ dueDate: 1 }).lean();

    const rows = bills.map(bill => {
      const daysOverdue = Math.floor((today - new Date(bill.dueDate)) / (1000 * 60 * 60 * 24));
      let bucket;
      if (daysOverdue <= 0)       bucket = 'Current';
      else if (daysOverdue <= 30) bucket = '1-30 days';
      else if (daysOverdue <= 60) bucket = '31-60 days';
      else if (daysOverdue <= 90) bucket = '61-90 days';
      else                        bucket = 'Over 90 days';

      return {
        billNumber:  bill.billNumber,
        vendorName:  bill.vendorName,
        vendorEmail: bill.vendorEmail,
        billDate:    bill.billDate,
        dueDate:     bill.dueDate,
        totalAmount: fmt(bill.totalAmount),
        amountPaid:  fmt(bill.amountPaid),
        amountDue:   fmt(bill.amountDue),
        daysOverdue: Math.max(0, daysOverdue),
        bucket,
        status:      bill.status,
      };
    });

    res.json({
      success: true,
      data: {
        asOf: today,
        bills: rows,
        total: fmt(rows.reduce((s, r) => s + (r.amountDue || 0), 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4.3 Vendor Balance Summary ────────────────────────────────────────────────
router.get('/vendor-balance', authenticate, async (req, res) => {
  try {
    const Bill = getModel('Bill', 'billingbills');

    const rows = await Bill.aggregate([
      { $match: { status: { $ne: 'DRAFT' }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$vendorId',
          vendorName:    { $first: '$vendorName' },
          vendorEmail:   { $first: '$vendorEmail' },
          billCount:     { $sum: 1 },
          totalBilled:   { $sum: '$totalAmount' },
          totalPaid:     { $sum: '$amountPaid' },
          totalDue:      { $sum: '$amountDue' },
      }},
      { $sort: { totalDue: -1 } },
    ]);

    res.json({
      success: true,
      data: {
        vendors: rows.map(r => ({ vendorId: r._id, vendorName: r.vendorName, vendorEmail: r.vendorEmail, billCount: r.billCount, totalBilled: fmt(r.totalBilled), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })),
        totals: {
          totalBilled: fmt(rows.reduce((s, r) => s + r.totalBilled, 0)),
          totalPaid:   fmt(rows.reduce((s, r) => s + r.totalPaid,   0)),
          totalDue:    fmt(rows.reduce((s, r) => s + r.totalDue,    0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4.4 Bill Details ──────────────────────────────────────────────────────────
router.get('/bill-details', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const { status, vendorId } = req.query;
    const Bill = getModel('Bill', 'billingbills');

    const query = { billDate: { $gte: start, $lte: end } };
    if (status)   query.status   = status;
    if (vendorId) query.vendorId = vendorId;
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const bills = await Bill.find(query).sort({ billDate: -1 }).limit(500).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        bills: bills.map(b => ({
          billNumber:  b.billNumber,
          vendorName:  b.vendorName,
          vendorEmail: b.vendorEmail,
          billDate:    b.billDate,
          dueDate:     b.dueDate,
          status:      b.status,
          subTotal:    fmt(b.subTotal),
          totalTax:    fmt((b.cgst || 0) + (b.sgst || 0) + (b.igst || 0)),
          tdsAmount:   fmt(b.tdsAmount),
          tcsAmount:   fmt(b.tcsAmount),
          totalAmount: fmt(b.totalAmount),
          amountPaid:  fmt(b.amountPaid),
          amountDue:   fmt(b.amountDue),
        })),
        totals: {
          count:       bills.length,
          totalAmount: fmt(bills.reduce((s, b) => s + (b.totalAmount || 0), 0)),
          totalPaid:   fmt(bills.reduce((s, b) => s + (b.amountPaid  || 0), 0)),
          totalDue:    fmt(bills.reduce((s, b) => s + (b.amountDue   || 0), 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4.5 Payments Made ─────────────────────────────────────────────────────────
router.get('/payments-made', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const PaymentMade = getModel('PaymentMade', 'paymentmades');

    const payments = await PaymentMade.find({
      paymentDate: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ paymentDate: -1 }).limit(500).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        payments: payments.map(p => ({
          paymentNumber:   p.paymentNumber,
          vendorName:      p.vendorName,
          vendorEmail:     p.vendorEmail,
          paymentDate:     p.paymentDate,
          paymentMode:     p.paymentMode,
          amount:          fmt(p.amount || p.totalAmount),
          status:          p.status,
          referenceNumber: p.referenceNumber,
          billsApplied:    (p.billsApplied || []).length,
        })),
        total: fmt(payments.reduce((s, p) => s + (p.amount || p.totalAmount || 0), 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4.6 Vendor Credit Details ─────────────────────────────────────────────────
router.get('/vendor-credit-details', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const VendorCredit = getModel('VendorCredit', 'vendorcredits');

    const credits = await VendorCredit.find({
      creditDate: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ creditDate: -1 }).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        vendorCredits: credits.map(vc => ({
          creditNumber:  vc.vendorCreditNumber,
          vendorName:    vc.vendorName,
          creditDate:    vc.creditDate,
          status:        vc.status,
          totalAmount:   fmt(vc.totalAmount),
          creditBalance: fmt(vc.creditBalance),
        })),
        total: fmt(credits.reduce((s, vc) => s + (vc.totalAmount || 0), 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4.7 Payable Summary ───────────────────────────────────────────────────────
router.get('/payable-summary', authenticate, async (req, res) => {
  try {
    const Bill = getModel('Bill', 'billingbills');

    const stats = await Bill.aggregate([
      { $match: { ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$status',
          count:  { $sum: 1 },
          amount: { $sum: '$totalAmount' },
          due:    { $sum: '$amountDue' },
          paid:   { $sum: '$amountPaid' },
      }},
    ]);

    res.json({
      success: true,
      data: {
        byStatus: stats.map(st => ({ status: st._id, count: st.count, amount: fmt(st.amount), due: fmt(st.due), paid: fmt(st.paid) })),
        totals: {
          totalBilled: fmt(stats.reduce((s, st) => s + st.amount, 0)),
          totalDue:    fmt(stats.reduce((s, st) => s + st.due,    0)),
          totalPaid:   fmt(stats.reduce((s, st) => s + st.paid,   0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4.8 Refund History (Payables) ────────────────────────────────────────────
router.get('/refund-history-payables', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const PaymentMade = getModel('PaymentMade', 'paymentmades');

    const payments = await PaymentMade.find({
      'refunds.0': { $exists: true },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    const refunds = [];
    for (const p of payments) {
      for (const r of (p.refunds || [])) {
        const refundDate = new Date(r.refundDate || r.refundedAt);
        if (refundDate >= start && refundDate <= end) {
          refunds.push({
            paymentNumber:   p.paymentNumber,
            vendorName:      p.vendorName,
            refundDate:      refundDate,
            amount:          fmt(r.amount),
            refundMode:      r.refundMode,
            referenceNumber: r.referenceNumber,
            notes:           r.notes,
          });
        }
      }
    }

    res.json({
      success: true,
      data: {
        period: { start, end },
        refunds,
        total: fmt(refunds.reduce((s, r) => s + r.amount, 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// SECTION 5 — PURCHASES & EXPENSES (5 reports)
// ============================================================================

// ── 5.1 Purchases by Vendor ───────────────────────────────────────────────────
router.get('/purchases-by-vendor', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Bill = getModel('Bill', 'billingbills');

    const rows = await Bill.aggregate([
      { $match: { billDate: { $gte: start, $lte: end }, status: { $ne: 'DRAFT' }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$vendorId',
          vendorName:  { $first: '$vendorName' },
          billCount:   { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalPaid:   { $sum: '$amountPaid' },
          totalDue:    { $sum: '$amountDue' },
      }},
      { $sort: { totalAmount: -1 } },
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        vendors: rows.map(r => ({ vendorId: r._id, vendorName: r.vendorName, billCount: r.billCount, totalAmount: fmt(r.totalAmount), totalPaid: fmt(r.totalPaid), totalDue: fmt(r.totalDue) })),
        totals: { totalAmount: fmt(rows.reduce((s, r) => s + r.totalAmount, 0)) },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 5.2 Purchases by Item ─────────────────────────────────────────────────────
router.get('/purchases-by-item', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Bill = getModel('Bill', 'billingbills');

    const rows = await Bill.aggregate([
      { $match: { billDate: { $gte: start, $lte: end }, status: { $ne: 'DRAFT' }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $unwind: '$items' },
      { $group: {
          _id: { $ifNull: ['$items.itemDetails', '$items.account'] },
          quantity:    { $sum: '$items.quantity' },
          totalAmount: { $sum: '$items.amount' },
          billCount:   { $sum: 1 },
          avgRate:     { $avg: '$items.rate' },
      }},
      { $sort: { totalAmount: -1 } },
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        items: rows.map(r => ({ itemName: r._id, quantity: fmt(r.quantity), totalAmount: fmt(r.totalAmount), billCount: r.billCount, avgRate: fmt(r.avgRate) })),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 5.3 Expense Details ───────────────────────────────────────────────────────
router.get('/expense-details', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const { vendor, expenseAccount } = req.query;
    const Expense = getModel('Expense', 'expenses');

    const query = { date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] } };
    if (vendor)         query.vendor         = new RegExp(vendor, 'i');
    if (expenseAccount) query.expenseAccount = expenseAccount;
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const expenses = await Expense.find(query).sort({ date: -1 }).limit(500).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        expenses: expenses.map(e => ({
          id:             e._id,
          date:           e.date,
          expenseAccount: e.expenseAccount,
          amount:         fmt(e.amount),
          tax:            fmt(e.tax),
          total:          fmt(e.total),
          paidThrough:    e.paidThrough,
          vendor:         e.vendor,
          customerName:   e.customerName,
          isBillable:     e.isBillable,
          project:        e.project,
          notes:          e.notes,
        })),
        totals: {
          count:       expenses.length,
          totalAmount: fmt(expenses.reduce((s, e) => s + (e.total || 0), 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 5.4 Expenses by Category ──────────────────────────────────────────────────
router.get('/expenses-by-category', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Expense = getModel('Expense', 'expenses');

    const rows = await Expense.aggregate([
      { $match: { date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: {
          _id: '$expenseAccount',
          count:       { $sum: 1 },
          totalAmount: { $sum: '$amount' },
          totalTax:    { $sum: '$tax' },
          total:       { $sum: '$total' },
      }},
      { $sort: { total: -1 } },
    ]);

    const grandTotal = rows.reduce((s, r) => s + r.total, 0);

    res.json({
      success: true,
      data: {
        period: { start, end },
        categories: rows.map(r => ({ category: r._id, count: r.count, totalAmount: fmt(r.totalAmount), totalTax: fmt(r.totalTax), total: fmt(r.total), percent: grandTotal > 0 ? fmt((r.total / grandTotal) * 100) : 0 })),
        grandTotal: fmt(grandTotal),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 5.5 Billable Expense Details ──────────────────────────────────────────────
router.get('/billable-expenses', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Expense = getModel('Expense', 'expenses');

    const expenses = await Expense.find({
      isBillable: true,
      date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: -1 }).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        expenses: expenses.map(e => ({
          date:           e.date,
          expenseAccount: e.expenseAccount,
          total:          fmt(e.total),
          billableAmount: fmt(e.billableAmount),
          customerName:   e.customerName,
          project:        e.project,
          isBilled:       e.isBilled,
          vendor:         e.vendor,
          notes:          e.notes,
        })),
        totals: {
          unbilled: fmt(expenses.filter(e => !e.isBilled).reduce((s, e) => s + (e.billableAmount || 0), 0)),
          billed:   fmt(expenses.filter(e => e.isBilled).reduce((s, e)  => s + (e.billableAmount || 0), 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// SECTION 6 — TAXES (3 reports)
// ============================================================================

// ── 6.1 TDS Summary ───────────────────────────────────────────────────────────
router.get('/tds-summary', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    const tdsPayableAcc = await ChartOfAccount.findOne({
      accountName: 'TDS Payable',
      isSystemAccount: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    if (!tdsPayableAcc) {
      return res.json({ success: true, data: { period: { start, end }, transactions: [], total: 0, message: 'TDS Payable account not found' } });
    }

    const txns = await AccountTransaction.find({
      accountId: tdsPayableAcc._id,
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: -1 }).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        transactions: txns.map(t => ({
          date:            t.date,
          description:     t.description,
          referenceType:   t.referenceType,
          referenceNumber: t.referenceNumber,
          debit:           fmt(t.debit),
          credit:          fmt(t.credit),
        })),
        totals: {
          totalDeducted: fmt(txns.reduce((s, t) => s + (t.credit || 0), 0)),
          totalPaid:     fmt(txns.reduce((s, t) => s + (t.debit  || 0), 0)),
          balance:       fmt(txns.reduce((s, t) => s + (t.credit - t.debit), 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 6.2 TDS Receivable Summary ────────────────────────────────────────────────
router.get('/tds-receivable', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    const tdsReceivableAcc = await ChartOfAccount.findOne({
      accountName: 'TDS Receivable',
      isSystemAccount: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();

    if (!tdsReceivableAcc) {
      return res.json({ success: true, data: { period: { start, end }, transactions: [], total: 0 } });
    }

    const txns = await AccountTransaction.find({
      accountId: tdsReceivableAcc._id,
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: -1 }).lean();

    const Invoice = getModel('Invoice', 'invoices');
    const invoiceStats = await Invoice.aggregate([
      { $match: { invoiceDate: { $gte: start, $lte: end }, tdsAmount: { $gt: 0 }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: null, totalTDS: { $sum: '$tdsAmount' }, count: { $sum: 1 } } },
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        transactions: txns.map(t => ({ date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit) })),
        totals: {
          totalTDSDeducted:  fmt(txns.reduce((s, t) => s + (t.debit || 0), 0)),
          invoiceCount:      invoiceStats[0]?.count || 0,
          totalFromInvoices: fmt(invoiceStats[0]?.totalTDS || 0),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 6.3 TCS Payable Summary ───────────────────────────────────────────────────
router.get('/tcs-summary', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    const Invoice = getModel('Invoice', 'invoices');
    const Bill    = getModel('Bill', 'billingbills');

    const [invoiceTCS, billTCS] = await Promise.all([
      Invoice.aggregate([
        { $match: { invoiceDate: { $gte: start, $lte: end }, tcsAmount: { $gt: 0 }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
        { $group: { _id: null, totalTCS: { $sum: '$tcsAmount' }, count: { $sum: 1 } } },
      ]),
      Bill.aggregate([
        { $match: { billDate: { $gte: start, $lte: end }, tcsAmount: { $gt: 0 }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
        { $group: { _id: null, totalTCS: { $sum: '$tcsAmount' }, count: { $sum: 1 } } },
      ]),
    ]);

    res.json({
      success: true,
      data: {
        period: { start, end },
        tcsFromSales:     fmt(invoiceTCS[0]?.totalTCS || 0),
        tcsFromPurchases: fmt(billTCS[0]?.totalTCS    || 0),
        salesCount:       invoiceTCS[0]?.count || 0,
        purchasesCount:   billTCS[0]?.count    || 0,
        netTCS:           fmt((invoiceTCS[0]?.totalTCS || 0) - (billTCS[0]?.totalTCS || 0)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// SECTION 7 — ACCOUNTANT (6 reports)
// ============================================================================

// ── 7.1 General Ledger ────────────────────────────────────────────────────────
router.get('/general-ledger', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const { accountId, accountType } = req.query;

    let accQuery = {
      isActive: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    };
    if (accountId)   accQuery._id         = accountId;
    if (accountType) accQuery.accountType = accountType;

    const accounts = await ChartOfAccount.find(accQuery).sort({ accountCode: 1 }).lean();
    const accountIds = accounts.map(a => a._id);

    const txns = await AccountTransaction.find({
      accountId: { $in: accountIds },
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ accountId: 1, date: 1 }).lean();

    // Group by account
    const grouped = {};
    for (const acc of accounts) grouped[acc._id.toString()] = { account: acc, transactions: [] };
    for (const t of txns) {
      const key = t.accountId.toString();
      if (grouped[key]) grouped[key].transactions.push(t);
    }

    const result = Object.values(grouped)
      .filter(g => g.transactions.length > 0)
      .map(g => {
        let balance = 0;
        const rows = g.transactions.map(t => {
          balance += (t.debit || 0) - (t.credit || 0);
          return { date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance) };
        });
        return {
          accountCode: g.account.accountCode,
          accountName: g.account.accountName,
          accountType: g.account.accountType,
          transactions: rows,
          totals: {
            debit:  fmt(rows.reduce((s, r) => s + r.debit,  0)),
            credit: fmt(rows.reduce((s, r) => s + r.credit, 0)),
            closing: fmt(balance),
          },
        };
      });

    res.json({ success: true, data: { period: { start, end }, accounts: result } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 7.2 Detailed General Ledger ───────────────────────────────────────────────
router.get('/general-ledger-detailed', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);

    const accounts = await ChartOfAccount.find({
      isActive: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ accountCode: 1 }).lean();
    const accountIds = accounts.map(a => a._id);

    // Opening balances (before start date)
    const openingTxns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: accountIds }, date: { $lt: start }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', debit: { $sum: '$debit' }, credit: { $sum: '$credit' } } },
    ]);
    const openingMap = {};
    openingTxns.forEach(t => { openingMap[t._id.toString()] = fmt(t.debit - t.credit); });

    // Period transactions
    const txns = await AccountTransaction.find({
      accountId: { $in: accountIds },
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ accountId: 1, date: 1 }).lean();

    const grouped = {};
    accounts.forEach(a => { grouped[a._id.toString()] = { account: a, transactions: [] }; });
    txns.forEach(t => {
      const k = t.accountId.toString();
      if (grouped[k]) grouped[k].transactions.push(t);
    });

    const result = Object.values(grouped)
      .filter(g => g.transactions.length > 0 || openingMap[g.account._id.toString()])
      .map(g => {
        const opening = openingMap[g.account._id.toString()] || 0;
        let balance = opening;
        const rows = g.transactions.map(t => {
          balance += (t.debit || 0) - (t.credit || 0);
          return { date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance) };
        });
        return {
          accountCode: g.account.accountCode,
          accountName: g.account.accountName,
          accountType: g.account.accountType,
          openingBalance: fmt(opening),
          transactions: rows,
          closingBalance: fmt(balance),
        };
      });

    res.json({ success: true, data: { period: { start, end }, accounts: result } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 7.3 Account Transactions (single account drill-down) ──────────────────────
router.get('/account-transactions', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const { accountId } = req.query;

    if (!accountId) return res.status(400).json({ success: false, message: 'accountId is required' });

    const account = await ChartOfAccount.findOne({
      _id: accountId,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });

    const txns = await AccountTransaction.find({
      accountId,
      date: { $gte: start, $lte: end },
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: 1 }).lean();

    let balance = 0;
    const rows = txns.map(t => {
      balance += (t.debit || 0) - (t.credit || 0);
      return { date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance) };
    });

    res.json({
      success: true,
      data: {
        account: { id: account._id, name: account.accountName, code: account.accountCode, type: account.accountType },
        period: { start, end },
        transactions: rows,
        totals: { debit: fmt(rows.reduce((s, r) => s + r.debit, 0)), credit: fmt(rows.reduce((s, r) => s + r.credit, 0)), closingBalance: fmt(balance) },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 7.4 Account Type Summary ──────────────────────────────────────────────────
router.get('/account-type-summary', authenticate, async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);

    const accounts = await ChartOfAccount.find({
      isActive: true,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    const ids = accounts.map(a => a._id);

    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $lte: end }, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) } },
      { $group: { _id: '$accountId', debit: { $sum: '$debit' }, credit: { $sum: '$credit' } } },
    ]);
    const txnMap = {};
    txns.forEach(t => { txnMap[t._id.toString()] = t; });

    const typeMap = {};
    for (const acc of accounts) {
      const t = txnMap[acc._id.toString()] || { debit: 0, credit: 0 };
      if (!typeMap[acc.accountType]) typeMap[acc.accountType] = { accountType: acc.accountType, count: 0, totalDebit: 0, totalCredit: 0 };
      typeMap[acc.accountType].count++;
      typeMap[acc.accountType].totalDebit  += t.debit;
      typeMap[acc.accountType].totalCredit += t.credit;
    }

    res.json({
      success: true,
      data: {
        asOf: end,
        accountTypes: Object.values(typeMap).map(t => ({ ...t, totalDebit: fmt(t.totalDebit), totalCredit: fmt(t.totalCredit), netBalance: fmt(t.totalDebit - t.totalCredit) })),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 7.5 Journal Report ────────────────────────────────────────────────────────
router.get('/journal-report', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const ManualJournal = getModel('ManualJournal', 'manualjournals');

    const journals = await ManualJournal.find({
      date:   { $gte: start, $lte: end },
      status: 'Published',
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).sort({ date: -1 }).lean();

    res.json({
      success: true,
      data: {
        period: { start, end },
        journals: journals.map(j => ({
          journalNumber:   j.journalNumber,
          date:            j.date,
          notes:           j.notes,
          referenceNumber: j.referenceNumber,
          totalDebit:      fmt(j.totalDebit),
          totalCredit:     fmt(j.totalCredit),
          lineItems:       (j.lineItems || []).map(l => ({ accountName: l.accountName, description: l.description, debit: fmt(l.debit), credit: fmt(l.credit) })),
        })),
        totals: {
          count:      journals.length,
          totalDebit: fmt(journals.reduce((s, j) => s + (j.totalDebit  || 0), 0)),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── 7.6 Activity Logs ─────────────────────────────────────────────────────────
router.get('/activity-logs', authenticate, async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const Invoice     = getModel('Invoice',      'invoices');
    const Bill        = getModel('Bill',         'billingbills');
    const PaymentMade = getModel('PaymentMade',  'paymentmades');
    const Expense     = getModel('Expense',      'expenses');

    const orgScope = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const [invoices, bills, payments, expenses] = await Promise.all([
      Invoice.find({ createdAt:     { $gte: start, $lte: end }, ...orgScope }).select('invoiceNumber customerName totalAmount status createdAt createdBy').limit(100).lean(),
      Bill.find({    createdAt:     { $gte: start, $lte: end }, ...orgScope }).select('billNumber vendorName totalAmount status createdAt createdBy').limit(100).lean(),
      PaymentMade.find({ createdAt: { $gte: start, $lte: end }, ...orgScope }).select('paymentNumber vendorName amount status createdAt createdBy').limit(100).lean(),
      Expense.find({  createdAt:   { $gte: start, $lte: end }, ...orgScope }).select('expenseAccount total paidThrough createdAt').limit(100).lean(),
    ]);

    const logs = [
      ...invoices.map(i => ({ type: 'Invoice',      ref: i.invoiceNumber, name: i.customerName, amount: fmt(i.totalAmount), status: i.status, date: i.createdAt, by: i.createdBy })),
      ...bills.map(b =>    ({ type: 'Bill',          ref: b.billNumber,    name: b.vendorName,   amount: fmt(b.totalAmount), status: b.status, date: b.createdAt, by: b.createdBy })),
      ...payments.map(p => ({ type: 'Payment Made',  ref: p.paymentNumber, name: p.vendorName,   amount: fmt(p.amount),     status: p.status, date: p.createdAt, by: p.createdBy })),
      ...expenses.map(e => ({ type: 'Expense',       ref: e._id,           name: e.expenseAccount, amount: fmt(e.total), status: 'Recorded', date: e.createdAt, by: 'system' })),
    ].sort((a, b) => new Date(b.date) - new Date(a.date));

    res.json({ success: true, data: { period: { start, end }, logs, count: logs.length } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// EXPORT ENDPOINTS (PDF + Excel for each report)
// ============================================================================

// ── Generic data fetcher (reuses above routes internally) ────────────────────
async function fetchReportData(reportKey, query, user) {
  // Create mock req/res to reuse route handlers
  return new Promise((resolve, reject) => {
    const mockReq = { query, user };
    const mockRes = {
      json: (data) => resolve(data),
      status: () => ({ json: (data) => reject(new Error(data.message || 'Error')) }),
    };
    // Map report key to handler
    const handlers = {
      'profit-loss':              (req, res) => router.handle({ ...req, method: 'GET', url: '/profit-loss' }, res),
      'balance-sheet':            (req, res) => router.handle({ ...req, method: 'GET', url: '/balance-sheet' }, res),
      'trial-balance':            (req, res) => router.handle({ ...req, method: 'GET', url: '/trial-balance' }, res),
      'ar-aging-summary':         (req, res) => router.handle({ ...req, method: 'GET', url: '/ar-aging-summary' }, res),
      'ap-aging-summary':         (req, res) => router.handle({ ...req, method: 'GET', url: '/ap-aging-summary' }, res),
    };
    reject(new Error('Use individual endpoints directly'));
  });
}

// ── PDF Export endpoint ───────────────────────────────────────────────────────
router.post('/export/pdf', authenticate, async (req, res) => {
  try {
    const { reportName, reportData, companyName, period } = req.body;

    const uploadsDir = path.join(__dirname, '..', 'uploads', 'reports');
    if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

    const filename = `report-${reportName.replace(/\s+/g, '-')}-${Date.now()}.pdf`;
    const filepath = path.join(uploadsDir, filename);

    const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
    const stream = fs.createWriteStream(filepath);
    doc.pipe(stream);

    // Header
    doc.rect(0, 0, 595, 80).fill('#0F172A');
    doc.fontSize(22).fillColor('#FFFFFF').font('Helvetica-Bold').text(companyName || 'Finance Report', 40, 20);
    doc.fontSize(13).fillColor('#94A3B8').font('Helvetica').text(reportName, 40, 50);

    // Period
    if (period) {
      doc.fontSize(9).fillColor('#64748B').text(
        `Period: ${new Date(period.start).toLocaleDateString('en-IN')} – ${new Date(period.end).toLocaleDateString('en-IN')}`,
        40, 90
      );
    }

    doc.moveDown(1);
    let y = period ? 115 : 100;

    // Render rows from reportData (generic table)
    if (reportData && Array.isArray(reportData)) {
      // Table header
      if (reportData.length > 0) {
        const headers = Object.keys(reportData[0]);
        const colWidth = Math.min(150, Math.floor(515 / headers.length));

        doc.rect(40, y, 515, 22).fill('#1E3A5F');
        doc.fontSize(8).fillColor('#FFFFFF').font('Helvetica-Bold');
        headers.forEach((h, i) => {
          doc.text(h.toUpperCase(), 50 + i * colWidth, y + 7, { width: colWidth - 4, ellipsis: true });
        });
        y += 22;

        // Rows
        reportData.forEach((row, rowIdx) => {
          if (y > 700) { doc.addPage(); y = 40; }
          const bg = rowIdx % 2 === 0 ? '#FFFFFF' : '#F8FAFC';
          doc.rect(40, y, 515, 20).fill(bg);
          doc.fontSize(8).fillColor('#374151').font('Helvetica');
          headers.forEach((h, i) => {
            const val = row[h] !== undefined && row[h] !== null ? String(row[h]) : '-';
            doc.text(val, 50 + i * colWidth, y + 6, { width: colWidth - 4, ellipsis: true });
          });
          y += 20;
        });
      }
    }

    // Footer
    const pages = doc.bufferedPageRange();
    for (let i = 0; i < pages.count; i++) {
      doc.switchToPage(i);
      doc.fontSize(7).fillColor('#94A3B8').font('Helvetica')
         .text(`Generated: ${new Date().toLocaleString('en-IN')} | Page ${i + 1} of ${pages.count}`, 40, 780, { align: 'center', width: 515 });
    }

    doc.end();
    stream.on('finish', () => {
      res.download(filepath, filename, () => {
        fs.unlink(filepath, () => {});
      });
    });
    stream.on('error', (err) => res.status(500).json({ success: false, message: err.message }));
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── Excel Export endpoint ─────────────────────────────────────────────────────
router.post('/export/excel', authenticate, async (req, res) => {
  try {
    const { reportName, reportData, companyName, period, headers: customHeaders } = req.body;

    if (!reportData || !Array.isArray(reportData) || reportData.length === 0) {
      return res.status(400).json({ success: false, message: 'No data to export' });
    }

    const wb = XLSX.utils.book_new();

    // Build header row + data rows
    const headers = customHeaders || Object.keys(reportData[0]);
    const wsData  = [
      // Title rows
      [companyName || 'Finance Report'],
      [reportName],
      period ? [`Period: ${new Date(period.start).toLocaleDateString('en-IN')} – ${new Date(period.end).toLocaleDateString('en-IN')}`] : [],
      [], // empty row
      headers,
      ...reportData.map(row => headers.map(h => row[h] !== undefined ? row[h] : '')),
    ];

    const ws = XLSX.utils.aoa_to_sheet(wsData);

    // Column widths
    ws['!cols'] = headers.map(h => ({ wch: Math.max(h.length + 4, 16) }));

    XLSX.utils.book_append_sheet(wb, ws, reportName.slice(0, 31));

    const buffer = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
    const filename = `${reportName.replace(/\s+/g, '-')}-${Date.now()}.xlsx`;

    res.setHeader('Content-Disposition', `attachment; filename=${filename}`);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Length', buffer.length);
    res.send(buffer);
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── Reports meta (list of all available reports) ──────────────────────────────
router.get('/meta', authenticate, (req, res) => {
  res.json({
    success: true,
    data: [
      { category: 'Business Overview', reports: [
        { key: 'profit-loss',              name: 'Profit and Loss',              endpoint: '/api/reports/profit-loss' },
        { key: 'balance-sheet',            name: 'Balance Sheet',                endpoint: '/api/reports/balance-sheet' },
        { key: 'cash-flow',                name: 'Cash Flow Statement',          endpoint: '/api/reports/cash-flow' },
        { key: 'trial-balance',            name: 'Trial Balance',                endpoint: '/api/reports/trial-balance' },
        { key: 'performance-ratios',       name: 'Business Performance Ratios',  endpoint: '/api/reports/performance-ratios' },
        { key: 'profit-loss-horizontal',   name: 'Horizontal Profit and Loss',   endpoint: '/api/reports/profit-loss-horizontal' },
        { key: 'balance-sheet-horizontal', name: 'Horizontal Balance Sheet',     endpoint: '/api/reports/balance-sheet-horizontal' },
        { key: 'movement-of-equity',       name: 'Movement of Equity',           endpoint: '/api/reports/movement-of-equity' },
        { key: 'day-book',                 name: 'Day Book',                     endpoint: '/api/reports/day-book' },
      ]},
      { category: 'Sales', reports: [
        { key: 'sales-by-customer',    name: 'Sales by Customer',    endpoint: '/api/reports/sales-by-customer' },
        { key: 'sales-by-item',        name: 'Sales by Item',        endpoint: '/api/reports/sales-by-item' },
        { key: 'sales-summary',        name: 'Sales Summary',        endpoint: '/api/reports/sales-summary' },
        { key: 'sales-by-salesperson', name: 'Sales by Salesperson', endpoint: '/api/reports/sales-by-salesperson' },
      ]},
      { category: 'Receivables', reports: [
        { key: 'ar-aging-summary',           name: 'AR Aging Summary',          endpoint: '/api/reports/ar-aging-summary' },
        { key: 'ar-aging-details',           name: 'AR Aging Details',          endpoint: '/api/reports/ar-aging-details' },
        { key: 'customer-balance',           name: 'Customer Balance Summary',  endpoint: '/api/reports/customer-balance' },
        { key: 'invoice-details',            name: 'Invoice Details',           endpoint: '/api/reports/invoice-details' },
        { key: 'payments-received',          name: 'Payments Received',         endpoint: '/api/reports/payments-received' },
        { key: 'credit-note-details',        name: 'Credit Note Details',       endpoint: '/api/reports/credit-note-details' },
        { key: 'receivable-summary',         name: 'Receivable Summary',        endpoint: '/api/reports/receivable-summary' },
        { key: 'refund-history-receivables', name: 'Refund History',            endpoint: '/api/reports/refund-history-receivables' },
      ]},
      { category: 'Payables', reports: [
        { key: 'ap-aging-summary',       name: 'AP Aging Summary',         endpoint: '/api/reports/ap-aging-summary' },
        { key: 'ap-aging-details',       name: 'AP Aging Details',         endpoint: '/api/reports/ap-aging-details' },
        { key: 'vendor-balance',         name: 'Vendor Balance Summary',   endpoint: '/api/reports/vendor-balance' },
        { key: 'bill-details',           name: 'Bill Details',             endpoint: '/api/reports/bill-details' },
        { key: 'payments-made',          name: 'Payments Made',            endpoint: '/api/reports/payments-made' },
        { key: 'vendor-credit-details',  name: 'Vendor Credit Details',    endpoint: '/api/reports/vendor-credit-details' },
        { key: 'payable-summary',        name: 'Payable Summary',          endpoint: '/api/reports/payable-summary' },
        { key: 'refund-history-payables',name: 'Refund History',           endpoint: '/api/reports/refund-history-payables' },
      ]},
      { category: 'Purchases and Expenses', reports: [
        { key: 'purchases-by-vendor',  name: 'Purchases by Vendor',        endpoint: '/api/reports/purchases-by-vendor' },
        { key: 'purchases-by-item',    name: 'Purchases by Item',          endpoint: '/api/reports/purchases-by-item' },
        { key: 'expense-details',      name: 'Expense Details',            endpoint: '/api/reports/expense-details' },
        { key: 'expenses-by-category', name: 'Expenses by Category',       endpoint: '/api/reports/expenses-by-category' },
        { key: 'billable-expenses',    name: 'Billable Expense Details',   endpoint: '/api/reports/billable-expenses' },
      ]},
      { category: 'Taxes', reports: [
        { key: 'tds-summary',    name: 'TDS Summary',                endpoint: '/api/reports/tds-summary' },
        { key: 'tds-receivable', name: 'TDS Receivable Summary',     endpoint: '/api/reports/tds-receivable' },
        { key: 'tcs-summary',    name: 'TCS Payable Summary',        endpoint: '/api/reports/tcs-summary' },
      ]},
      { category: 'Accountant', reports: [
        { key: 'general-ledger',          name: 'General Ledger',           endpoint: '/api/reports/general-ledger' },
        { key: 'general-ledger-detailed', name: 'Detailed General Ledger',  endpoint: '/api/reports/general-ledger-detailed' },
        { key: 'account-transactions',    name: 'Account Transactions',     endpoint: '/api/reports/account-transactions' },
        { key: 'account-type-summary',    name: 'Account Type Summary',     endpoint: '/api/reports/account-type-summary' },
        { key: 'journal-report',          name: 'Journal Report',           endpoint: '/api/reports/journal-report' },
        { key: 'activity-logs',           name: 'Activity Logs',            endpoint: '/api/reports/activity-logs' },
      ]},
    ],
  });
});

module.exports = router;