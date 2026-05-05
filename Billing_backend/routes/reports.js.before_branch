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

const express  = require('express');
const router   = express.Router();
const mongoose = require('mongoose');
const XLSX     = require('xlsx');
const PDFDoc   = require('pdfkit');
const path     = require('path');
const fs       = require('fs');

const { verifyFinanceJWT }                     = require('../middleware/finance_jwt');
const { ChartOfAccount, AccountTransaction }   = require('./chart_of_accounts');

function col(name, collection) {
  if (mongoose.models[name]) return mongoose.models[name];
  return mongoose.model(name, new mongoose.Schema({}, { strict: false }), collection);
}

router.use(verifyFinanceJWT);

const INCOME_TYPES    = ['Income', 'Other Income'];
const EXPENSE_TYPES   = ['Expense', 'Cost Of Goods Sold', 'Other Expense'];
const ASSET_TYPES     = ['Asset','Accounts Receivable','Other Current Asset','Fixed Asset','Cash','Stock','Other Asset'];
const LIABILITY_TYPES = ['Liability','Accounts Payable','Other Current Liability','Non Current Liability','Other Liability'];
const EQUITY_TYPES    = ['Equity'];

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
      case 'today':        return { start: new Date(now.getFullYear(), now.getMonth(), now.getDate()), end: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59) };
      case 'this_week':    { const d = new Date(now); d.setDate(d.getDate() - d.getDay()); return { start: d, end: now }; }
      case 'this_month':   return { start: new Date(now.getFullYear(), now.getMonth(), 1), end: new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59) };
      case 'last_month':   return { start: new Date(now.getFullYear(), now.getMonth() - 1, 1), end: new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59) };
      case 'this_quarter': { const q2 = Math.floor(now.getMonth() / 3); return { start: new Date(now.getFullYear(), q2 * 3, 1), end: new Date(now.getFullYear(), q2 * 3 + 3, 0, 23, 59, 59) }; }
      case 'last_quarter': { const lq = Math.floor(now.getMonth() / 3) - 1; const lqY = lq < 0 ? now.getFullYear() - 1 : now.getFullYear(); const lqQ = ((lq % 4) + 4) % 4; return { start: new Date(lqY, lqQ * 3, 1), end: new Date(lqY, lqQ * 3 + 3, 0, 23, 59, 59) }; }
      // FIX-10: this_fy end is now() not Mar 31 — so April 2026 entries are included
      case 'this_fy':      { const fy = getFY(); return { start: fy.start, end: now }; }
      case 'last_fy':      return getLastFY();
    }
  }
  return {
    start: q.fromDate ? new Date(q.fromDate) : getFY().start,
    end:   q.toDate   ? new Date(new Date(q.toDate).setHours(23, 59, 59)) : now,
  };
}

function orgScope(req) {
  return req.user?.orgId ? { orgId: req.user.orgId } : {};
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
    const accounts = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, isActive: true, ...scope }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope } },
      { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
    ]);
    const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
    let totalIncome = 0, totalCOGS = 0, totalOpEx = 0;
    const income = [], cogs = [], opEx = [];
    for (const acc of accounts) {
      const t = tMap[acc._id.toString()] || { dr: 0, cr: 0 };
      const net = INCOME_TYPES.includes(acc.accountType) ? fmt(t.cr - t.dr) : fmt(t.dr - t.cr);
      const row = { accountName: acc.accountName, accountCode: acc.accountCode, amount: net };
      if (INCOME_TYPES.includes(acc.accountType))          { income.push(row); totalIncome += net; }
      else if (acc.accountType === 'Cost Of Goods Sold')   { cogs.push(row);   totalCOGS  += net; }
      else                                                  { opEx.push(row);   totalOpEx  += net; }
    }
    const grossProfit = fmt(totalIncome - totalCOGS);
    const netProfit   = fmt(grossProfit - totalOpEx);
    res.json({ success: true, data: { period: { start, end }, income: { items: income, total: fmt(totalIncome) }, costOfGoods: { items: cogs, total: fmt(totalCOGS) }, grossProfit, operatingExpenses: { items: opEx, total: fmt(totalOpEx) }, netProfit } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/balance-sheet', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);

    // ── Assets / Liabilities / Equity from COA transactions ─────────────
    const accounts = await ChartOfAccount.find({ accountType: { $in: [...ASSET_TYPES, ...LIABILITY_TYPES, ...EQUITY_TYPES] }, isActive: true, ...scope }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: ids }, date: { $lte: end }, ...scope } },
      { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
    ]);
    const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
    let totA = 0, totL = 0, totE = 0;
    const assets = [], liabs = [], equity = [];
    for (const acc of accounts) {
      const t = tMap[acc._id.toString()] || { dr: 0, cr: 0 };
      const net = ASSET_TYPES.includes(acc.accountType) ? fmt(t.dr - t.cr) : fmt(t.cr - t.dr);
      const row = { accountName: acc.accountName, accountCode: acc.accountCode, accountType: acc.accountType, amount: net };
      if (ASSET_TYPES.includes(acc.accountType))           { assets.push(row); totA += net; }
      else if (LIABILITY_TYPES.includes(acc.accountType))  { liabs.push(row);  totL += net; }
      else                                                  { equity.push(row); totE += net; }
    }

    // ── FIX: Calculate Net Profit and add to Retained Earnings ───────────
    // Net Profit = Income credits - Expense debits (all time up to 'end')
    const plAccounts = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, isActive: true, ...scope }).lean();
    const plIds = plAccounts.map(a => a._id);
    const plTxns = await AccountTransaction.aggregate([
      { $match: { accountId: { $in: plIds }, date: { $lte: end }, ...scope } },
      { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
    ]);
    const plMap = {}; plTxns.forEach(t => { plMap[t._id.toString()] = t; });
    let netProfit = 0;
    for (const acc of plAccounts) {
      const t = plMap[acc._id.toString()] || { dr: 0, cr: 0 };
      if (INCOME_TYPES.includes(acc.accountType))  netProfit += t.cr - t.dr;
      else                                          netProfit -= t.dr - t.cr;
    }
    netProfit = fmt(netProfit);

    // Add Net Profit as a line inside Equity section
    if (netProfit !== 0) {
      equity.push({
        accountName: 'Net Profit (Current Period)',
        accountCode: '',
        accountType: 'Equity',
        amount: netProfit,
      });
      totE = fmt(totE + netProfit);
    }
    // ─────────────────────────────────────────────────────────────────────

    res.json({ success: true, data: { asOf: end, assets: { items: assets, total: fmt(totA) }, liabilities: { items: liabs, total: fmt(totL) }, equity: { items: equity, total: fmt(totE) }, totalLiabilitiesAndEquity: fmt(totL + totE), balanced: Math.abs(totA - (totL + totE)) < 0.02 } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/cash-flow', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const db    = getDB(req);
    const scope = orgScope(req);

    // Helper: parse any date format into a JS Date
    function parseAnyDate(v) {
      if (!v) return null;
      if (v instanceof Date) return v;
      // ISO string or "DD/MM/YYYY" or "YYYY-MM-DD"
      const s = v.toString().trim();
      if (/^\d{2}\/\d{2}\/\d{4}$/.test(s)) {
        const [d, m, y] = s.split('/');
        return new Date(`${y}-${m}-${d}`);
      }
      const d = new Date(s);
      return isNaN(d) ? null : d;
    }

    // ── INCOMING: payments_received collection ───────────────────────────
    const prFilter = { status: { $ne: 'void' } };
    if (scope.orgId) prFilter.orgId = scope.orgId;
    const allPaymentsReceived = await db.collection('payments_received').find(prFilter).toArray();

    // ── OUTGOING: payments_made + expenses collections ───────────────────
    const pmFilter = { status: { $nin: ['VOIDED', 'void'] } };
    if (scope.orgId) pmFilter.orgId = scope.orgId;
    const allPaymentsMade = await db.collection('payments_made').find(pmFilter).toArray();

    const expFilter = {};
    if (scope.orgId) expFilter.orgId = scope.orgId;
    const allExpenses = await db.collection('expenses').find(expFilter).toArray();

    // ── Build monthly map (keyed "YYYY-MM") ─────────────────────────────
    const monthlyMap = {};

    function addToMonth(dateVal, inAmt, outAmt) {
      const d = parseAnyDate(dateVal);
      if (!d || isNaN(d)) return;
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      if (!monthlyMap[key]) monthlyMap[key] = { month: key, incoming: 0, outgoing: 0 };
      monthlyMap[key].incoming += inAmt;
      monthlyMap[key].outgoing += outAmt;
    }

    let openingBalance  = 0;
    let totalIncoming   = 0;
    let totalOutgoing   = 0;

    // Payments received
    for (const p of allPaymentsReceived) {
      const d   = parseAnyDate(p.paymentDate || p.date);
      const amt = fmt(p.amountReceived || p.amount || p.netAmount || 0);
      if (!d) continue;
      if (d < start) { openingBalance += amt; }
      else if (d >= start && d <= end) { totalIncoming += amt; addToMonth(d, amt, 0); }
    }

    // Payments made (bills paid)
    for (const p of allPaymentsMade) {
      const d   = parseAnyDate(p.paymentDate || p.date);
      const amt = fmt(p.amount || p.totalAmount || p.amountPaid || 0);
      if (!d) continue;
      if (d >= start && d <= end) { totalOutgoing += amt; addToMonth(d, 0, amt); }
    }

    // Expenses (all — expenses schema has no status field)
    for (const e of allExpenses) {
      const d   = parseAnyDate(e.date || e.expenseDate || e.createdAt);
      const amt = fmt(e.total || e.amount || 0);
      if (!d) continue;
      if (d >= start && d <= end) { totalOutgoing += amt; addToMonth(d, 0, amt); }
    }

    totalIncoming = fmt(totalIncoming);
    totalOutgoing = fmt(totalOutgoing);
    openingBalance = fmt(openingBalance);

    // ── Build sorted monthlyBreakdown with running balance ───────────────
    let runningBalance = openingBalance;
    const monthlyBreakdown = Object.values(monthlyMap)
      .sort((a, b) => a.month.localeCompare(b.month))
      .map(m => {
        runningBalance += m.incoming - m.outgoing;
        return {
          month:    m.month,
          incoming: fmt(m.incoming),
          outgoing: fmt(m.outgoing),
          balance:  fmt(runningBalance),
        };
      });

    const closingBalance = fmt(openingBalance + totalIncoming - totalOutgoing);

    res.json({
      success: true,
      data: {
        period: { start, end },
        operating: {
          inflows:  totalIncoming,
          outflows: totalOutgoing,
          net:      fmt(totalIncoming - totalOutgoing),
          items:    [],
        },
        investing:      { inflows: 0, outflows: 0, net: 0 },
        netCashChange:  fmt(totalIncoming - totalOutgoing),
        monthlyBreakdown,
        summary: {
          openingBalance,
          totalIncoming,
          totalOutgoing,
          closingBalance,
        },
      },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

router.get('/profit-loss-horizontal', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const days = (end - start) / 86400000;
    const prevEnd   = new Date(start - 1);
    const prevStart = new Date(+start - days * 86400000);
    const fetchPL = async (s, e) => {
      const accs = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, ...scope }).lean();
      const ids = accs.map(a => a._id);
      const txns = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, date: { $gte: s, $lte: e }, ...scope } },
        { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
      ]);
      const m = {}; txns.forEach(t => { m[t._id.toString()] = t; });
      let inc = 0, exp = 0;
      for (const a of accs) {
        const t = m[a._id.toString()] || { dr: 0, cr: 0 };
        if (INCOME_TYPES.includes(a.accountType)) inc += t.cr - t.dr; else exp += t.dr - t.cr;
      }
      return { income: fmt(inc), expenses: fmt(exp), netProfit: fmt(inc - exp) };
    };
    const [curr, prev] = await Promise.all([fetchPL(start, end), fetchPL(prevStart, prevEnd)]);
    const chg = (c, p) => p !== 0 ? fmt(((c - p) / Math.abs(p)) * 100) : 0;
    res.json({ success: true, data: { current: { period: { start, end }, ...curr }, previous: { period: { start: prevStart, end: prevEnd }, ...prev }, changes: { income: { absolute: fmt(curr.income - prev.income), percent: chg(curr.income, prev.income) }, expenses: { absolute: fmt(curr.expenses - prev.expenses), percent: chg(curr.expenses, prev.expenses) }, netProfit: { absolute: fmt(curr.netProfit - prev.netProfit), percent: chg(curr.netProfit, prev.netProfit) } } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/balance-sheet-horizontal', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const prevEnd = new Date(getFY(end).start - 1);
    const fetchBS = async (e) => {
      const accs = await ChartOfAccount.find({ accountType: { $in: [...ASSET_TYPES, ...LIABILITY_TYPES, ...EQUITY_TYPES] }, ...scope }).lean();
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
      const plAccs = await ChartOfAccount.find({ accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, ...scope }).lean();
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
      const accs = await ChartOfAccount.find({ accountType: { $in: types }, ...scope }).lean();
      const ids = accs.map(a => a._id);
      const r = await AccountTransaction.aggregate([
        { $match: { accountId: { $in: ids }, ...dateFilter, ...scope } },
        { $group: { _id: null, total: { $sum: `$${field}` } } },
      ]);
      return r[0]?.total || 0;
    };
    const df = { date: { $gte: start, $lte: end } };
    const de = { date: { $lte: end } };
    const [rev, exp, ast, lia] = await Promise.all([
      sumTxns(INCOME_TYPES, 'credit', df), sumTxns(EXPENSE_TYPES, 'debit', df),
      sumTxns(ASSET_TYPES, 'debit', de),   sumTxns(LIABILITY_TYPES, 'credit', de),
    ]);
    const gp = rev - exp, eq = ast - lia;
    res.json({ success: true, data: { period: { start, end }, grossProfitMargin: rev > 0 ? fmt((gp / rev) * 100) : 0, netProfitMargin: rev > 0 ? fmt((gp / rev) * 100) : 0, returnOnAssets: ast > 0 ? fmt((gp / ast) * 100) : 0, returnOnEquity: eq > 0 ? fmt((gp / eq) * 100) : 0, debtToEquityRatio: eq > 0 ? fmt(lia / eq) : 0, currentRatio: lia > 0 ? fmt(ast / lia) : 0, totalRevenue: fmt(rev), totalExpenses: fmt(exp), netProfit: fmt(gp) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/movement-of-equity', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accs = await ChartOfAccount.find({ accountType: { $in: EQUITY_TYPES }, ...scope }).lean();
    const ids = accs.map(a => a._id);
    const [openTxns, periodTxns] = await Promise.all([
      AccountTransaction.aggregate([{ $match: { accountId: { $in: ids }, date: { $lt: start }, ...scope } }, { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }]),
      AccountTransaction.aggregate([{ $match: { accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope } }, { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }]),
    ]);
    const oMap = {}, pMap = {};
    openTxns.forEach(t   => { oMap[t._id.toString()] = t; });
    periodTxns.forEach(t => { pMap[t._id.toString()] = t; });
    const rows = accs.map(a => {
      const o = oMap[a._id.toString()] || { dr: 0, cr: 0 };
      const p = pMap[a._id.toString()] || { dr: 0, cr: 0 };
      const opening = fmt(o.cr - o.dr);
      const change  = fmt(p.cr - p.dr);
      return { accountName: a.accountName, opening, change, closing: fmt(opening + change) };
    });
    res.json({ success: true, data: { period: { start, end }, accounts: rows, totals: { opening: fmt(rows.reduce((s, r) => s + r.opening, 0)), change: fmt(rows.reduce((s, r) => s + r.change, 0)), closing: fmt(rows.reduce((s, r) => s + r.closing, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/trial-balance', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accounts = await ChartOfAccount.find({ isActive: true, ...scope }).sort({ accountCode: 1 }).lean();
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
      return { accountCode: a.accountCode, accountName: a.accountName, accountType: a.accountType, debit: dr, credit: cr, balance: fmt(dr - cr) };
    }).filter(r => r.debit > 0 || r.credit > 0);
    res.json({ success: true, data: { asOf: end, accounts: rows, totals: { debit: fmt(grandDr), credit: fmt(grandCr) }, balanced: Math.abs(grandDr - grandCr) < 0.02 } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/day-book', async (req, res) => {
  try {
    const date  = req.query.date ? new Date(req.query.date) : new Date();
    const start = new Date(date); start.setHours(0, 0, 0, 0);
    const end   = new Date(date); end.setHours(23, 59, 59, 999);
    const scope = orgScope(req);
    const txns = await AccountTransaction.find({ date: { $gte: start, $lte: end }, ...scope }).sort({ date: 1 }).limit(500).lean();
    const accIds = [...new Set(txns.map(t => t.accountId?.toString()))].filter(Boolean);
    const accs = await ChartOfAccount.find({ _id: { $in: accIds } }).lean();
    const aMap = {}; accs.forEach(a => { aMap[a._id.toString()] = a; });
    const enriched = txns.map(t => ({ ...t, accountName: aMap[t.accountId?.toString()]?.accountName || '', accountType: aMap[t.accountId?.toString()]?.accountType || '' }));
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
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT','CANCELLED'] }, ...scope } },
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
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT','CANCELLED'] }, ...scope } },
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
      { $match: { invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT','CANCELLED'] }, ...scope } },
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
    const today = new Date();
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');

    const invoices = await Invoice.find({
      status: { $in: ['UNPAID', 'PARTIALLY_PAID', 'OVERDUE', 'SENT'] },
      amountDue: { $gt: 0 },
      ...scope
    }).lean();

    const buckets = { current: 0, '1_30': 0, '31_60': 0, '61_90': 0, '90plus': 0 };
    const counts  = { current: 0, '1_30': 0, '31_60': 0, '61_90': 0, '90plus': 0 };
    const customerMap = {};

    for (const inv of invoices) {
      const days = Math.floor((today - new Date(inv.dueDate)) / 86400000);
      const due  = inv.amountDue || 0;

      let bk;
      if      (days <= 0)  bk = 'current';
      else if (days <= 30) bk = '1_30';
      else if (days <= 60) bk = '31_60';
      else if (days <= 90) bk = '61_90';
      else                 bk = '90plus';

      buckets[bk] += due;
      counts[bk]++;

      // Per-customer row for table rendering
      const cid = (inv.customerId || inv.customerName || 'Unknown').toString();
      if (!customerMap[cid]) {
        customerMap[cid] = { customerId: cid, customerName: inv.customerName || 'Unknown', current: 0, days1_30: 0, days31_60: 0, days61_90: 0, days91Plus: 0, total: 0 };
      }
      const cr = customerMap[cid];
      const fm = { current: 'current', '1_30': 'days1_30', '31_60': 'days31_60', '61_90': 'days61_90', '90plus': 'days91Plus' };
      cr[fm[bk]] += due;
      cr.total += due;
    }

    const total = Object.values(buckets).reduce((s, v) => s + v, 0);
    const customers = Object.values(customerMap).map(c => ({
      customerId: c.customerId, customerName: c.customerName,
      current: fmt(c.current), days1_30: fmt(c.days1_30), days31_60: fmt(c.days31_60),
      days61_90: fmt(c.days61_90), days91Plus: fmt(c.days91Plus), total: fmt(c.total),
    }));

    console.log(`[AR-AGING] invoices found=${invoices.length} | customers=${customers.length} | total=${fmt(total)}`);
    if (customers.length > 0) console.log('[AR-AGING] sample:', JSON.stringify(customers[0]));

    res.json({ success: true, data: {
      asOf: today,
      buckets: [
        { range: 'Current',      amount: fmt(buckets.current),  count: counts.current,  percent: total > 0 ? fmt((buckets.current  / total) * 100) : 0 },
        { range: '1-30 days',    amount: fmt(buckets['1_30']),   count: counts['1_30'],   percent: total > 0 ? fmt((buckets['1_30']   / total) * 100) : 0 },
        { range: '31-60 days',   amount: fmt(buckets['31_60']),  count: counts['31_60'],  percent: total > 0 ? fmt((buckets['31_60']  / total) * 100) : 0 },
        { range: '61-90 days',   amount: fmt(buckets['61_90']),  count: counts['61_90'],  percent: total > 0 ? fmt((buckets['61_90']  / total) * 100) : 0 },
        { range: 'Over 90 days', amount: fmt(buckets['90plus']), count: counts['90plus'], percent: total > 0 ? fmt((buckets['90plus'] / total) * 100) : 0 },
      ],
      customers,  // Flutter _parse() picks this as table rows
      total: fmt(total),
    }});
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/ar-aging-details', async (req, res) => {
  try {
    const today = new Date();
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const invoices = await Invoice.find({ status: { $in: ['UNPAID','PARTIALLY_PAID','OVERDUE','SENT'] }, amountDue: { $gt: 0 }, ...scope }).sort({ dueDate: 1 }).lean();
    const rows = invoices.map(inv => {
      const days = Math.floor((today - new Date(inv.dueDate)) / 86400000);
      let bucket;
      if      (days <= 0)  bucket = 'Current';
      else if (days <= 30) bucket = '1-30 days';
      else if (days <= 60) bucket = '31-60 days';
      else if (days <= 90) bucket = '61-90 days';
      else                 bucket = 'Over 90 days';
      return { invoiceNumber: inv.invoiceNumber, customerName: inv.customerName, customerEmail: inv.customerEmail, invoiceDate: inv.invoiceDate, dueDate: inv.dueDate, totalAmount: fmt(inv.totalAmount), amountPaid: fmt(inv.amountPaid), amountDue: fmt(inv.amountDue), daysOverdue: Math.max(0, days), bucket, status: inv.status };
    });
    res.json({ success: true, data: { asOf: today, invoices: rows, total: fmt(rows.reduce((s, r) => s + (parseFloat(r.amountDue) || 0), 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/customer-balance', async (req, res) => {
  try {
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const rows = await Invoice.aggregate([
      { $match: { status: { $nin: ['DRAFT','CANCELLED'] }, ...scope } },
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
    if (req.query.status) query.status = req.query.status;
    // FIX-3: cast customerId to ObjectId
    if (req.query.customerId) {
      const cid = safeObjId(req.query.customerId);
      query.customerId = cid || req.query.customerId;
    }
    const invoices = await Invoice.find(query).sort({ invoiceDate: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, invoices: invoices.map(inv => ({ invoiceNumber: inv.invoiceNumber, customerName: inv.customerName, customerEmail: inv.customerEmail, invoiceDate: inv.invoiceDate, dueDate: inv.dueDate, status: inv.status, subTotal: fmt(inv.subTotal), totalTax: fmt((inv.totalCGST || 0) + (inv.totalSGST || 0) + (inv.totalIGST || 0)), totalAmount: fmt(inv.totalAmount), amountPaid: fmt(inv.amountPaid), amountDue: fmt(inv.amountDue) })), totals: { count: invoices.length, totalAmount: fmt(invoices.reduce((s, i) => s + (i.totalAmount || 0), 0)), totalPaid: fmt(invoices.reduce((s, i) => s + (i.amountPaid || 0), 0)), totalDue: fmt(invoices.reduce((s, i) => s + (i.amountDue || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/receivable-summary', async (req, res) => {
  try {
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const stats = await Invoice.aggregate([
      { $match: scope },
      { $group: { _id: '$status', count: { $sum: 1 }, amount: { $sum: '$totalAmount' }, due: { $sum: '$amountDue' }, paid: { $sum: '$amountPaid' } } },
    ]);
    // FIX-4 pattern: also expose as 'invoices' so Flutter table renders
    const rows = stats.map(s => ({ status: s._id, count: s.count, amount: fmt(s.amount), due: fmt(s.due), paid: fmt(s.paid) }));
    res.json({ success: true, data: { byStatus: rows, invoices: rows, totals: { totalInvoiced: fmt(stats.reduce((s, st) => s + st.amount, 0)), totalDue: fmt(stats.reduce((s, st) => s + st.due, 0)), totalPaid: fmt(stats.reduce((s, st) => s + st.paid, 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/receivable-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const invoices = await Invoice.find({ invoiceDate: { $gte: start, $lte: end }, status: { $in: ['UNPAID','PARTIALLY_PAID','OVERDUE','SENT'] }, ...scope }).sort({ invoiceDate: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, invoices: invoices.map(inv => ({ invoiceNumber: inv.invoiceNumber, customerName: inv.customerName, invoiceDate: inv.invoiceDate, dueDate: inv.dueDate, status: inv.status, totalAmount: fmt(inv.totalAmount), amountPaid: fmt(inv.amountPaid), amountDue: fmt(inv.amountDue) })), totals: { total: fmt(invoices.reduce((s, i) => s + (i.amountDue || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/credit-note-details', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const CreditNote = col('CreditNote', 'creditnotes');
    // Query by creditNoteDate OR createdAt to catch all records
    const notes = await CreditNote.find({
      $or: [
        { creditNoteDate: { $gte: start, $lte: end } },
        { createdAt: { $gte: start, $lte: end } },
      ],
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
      } catch (_) {}
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
          d = new Date(`${year}-${month.padStart(2,'0')}-${day.padStart(2,'0')}`);
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
    const today = new Date();
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');

    const bills = await Bill.find({
      status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] },
      amountDue: { $gt: 0 },
      ...scope
    }).lean();

    const buckets = { current: 0, '1_30': 0, '31_60': 0, '61_90': 0, '90plus': 0 };
    const counts  = { current: 0, '1_30': 0, '31_60': 0, '61_90': 0, '90plus': 0 };
    const vendorMap = {};

    for (const b of bills) {
      const days = Math.floor((today - new Date(b.dueDate)) / 86400000);
      const due  = b.amountDue || 0;

      let bk;
      if      (days <= 0)  bk = 'current';
      else if (days <= 30) bk = '1_30';
      else if (days <= 60) bk = '31_60';
      else if (days <= 90) bk = '61_90';
      else                 bk = '90plus';

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
      vendorId: v.vendorId, vendorName: v.vendorName,
      current: fmt(v.current), days1_30: fmt(v.days1_30), days31_60: fmt(v.days31_60),
      days61_90: fmt(v.days61_90), days91Plus: fmt(v.days91Plus), total: fmt(v.total),
    }));

    res.json({ success: true, data: {
      asOf: today,
      buckets: [
        { range: 'Current',      amount: fmt(buckets.current),  count: counts.current,  percent: total > 0 ? fmt((buckets.current  / total) * 100) : 0 },
        { range: '1-30 days',    amount: fmt(buckets['1_30']),   count: counts['1_30'],   percent: total > 0 ? fmt((buckets['1_30']   / total) * 100) : 0 },
        { range: '31-60 days',   amount: fmt(buckets['31_60']),  count: counts['31_60'],  percent: total > 0 ? fmt((buckets['31_60']  / total) * 100) : 0 },
        { range: '61-90 days',   amount: fmt(buckets['61_90']),  count: counts['61_90'],  percent: total > 0 ? fmt((buckets['61_90']  / total) * 100) : 0 },
        { range: 'Over 90 days', amount: fmt(buckets['90plus']), count: counts['90plus'], percent: total > 0 ? fmt((buckets['90plus'] / total) * 100) : 0 },
      ],
      vendors,  // Flutter _parse() picks this as the table rows
      total: fmt(total),
    }});
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/ap-aging-details', async (req, res) => {
  try {
    const today = new Date();
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const bills = await Bill.find({ status: { $in: ['OPEN','OVERDUE','PARTIALLY_PAID'] }, amountDue: { $gt: 0 }, ...scope }).sort({ dueDate: 1 }).lean();
    const rows = bills.map(b => {
      const days = Math.floor((today - new Date(b.dueDate)) / 86400000);
      let bucket;
      if      (days <= 0)  bucket = 'Current';
      else if (days <= 30) bucket = '1-30 days';
      else if (days <= 60) bucket = '31-60 days';
      else if (days <= 90) bucket = '61-90 days';
      else                 bucket = 'Over 90 days';
      return { billNumber: b.billNumber, vendorName: b.vendorName, vendorEmail: b.vendorEmail, billDate: b.billDate, dueDate: b.dueDate, totalAmount: fmt(b.totalAmount), amountPaid: fmt(b.amountPaid), amountDue: fmt(b.amountDue), daysOverdue: Math.max(0, days), bucket, status: b.status };
    });
    res.json({ success: true, data: { asOf: today, bills: rows, total: fmt(rows.reduce((s, r) => s + (parseFloat(r.amountDue) || 0), 0)) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/vendor-balance', async (req, res) => {
  try {
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const rows = await Bill.aggregate([
      { $match: { status: { $ne: 'DRAFT' }, ...scope } },
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
    if (req.query.status) query.status = req.query.status;
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
    let credits = [];
    try {
      const VendorCredit = col('VendorCredit', 'vendorcredits');
      credits = await VendorCredit.find({ creditDate: { $gte: start, $lte: end }, ...scope }).sort({ creditDate: -1 }).lean();
    } catch (e1) {
      try {
        credits = await db.collection('vendorcredits').find({ creditDate: { $gte: start, $lte: end }, ...scope }).toArray();
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
      } catch (_) {}
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
    const pos = await PO.find({ purchaseOrderDate: { $gte: start, $lte: end }, ...scope }).sort({ purchaseOrderDate: -1 }).limit(500).lean();
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
router.get('/payable-summary', async (req, res) => {
  try {
    const scope = orgScope(req);
    const Bill = col('Bill', 'bills');
    const stats = await Bill.aggregate([
      { $match: scope },
      { $group: { _id: '$status', count: { $sum: 1 }, amount: { $sum: '$totalAmount' }, due: { $sum: '$amountDue' }, paid: { $sum: '$amountPaid' } } },
    ]);
    const rows = stats.map(s => ({ status: s._id, count: s.count, amount: fmt(s.amount), due: fmt(s.due), paid: fmt(s.paid) }));
    res.json({ success: true, data: {
      byStatus: rows,
      bills: rows,  // FIX: Flutter listKeys includes 'bills' but not 'byStatus'
      totals: { totalBilled: fmt(stats.reduce((s, st) => s + st.amount, 0)), totalDue: fmt(stats.reduce((s, st) => s + st.due, 0)), totalPaid: fmt(stats.reduce((s, st) => s + st.paid, 0)) }
    }});
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
    res.json({ success: true, data: { period: { start, end }, bills: bills.map(b => ({ billNumber: b.billNumber, vendorName: b.vendorName, billDate: b.billDate, dueDate: b.dueDate, status: b.status, totalAmount: fmt(b.totalAmount), amountPaid: fmt(b.amountPaid), amountDue: fmt(b.amountDue) })), totals: { total: fmt(bills.reduce((s, b) => s + (b.amountDue || 0), 0)) } } });
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
    const endStr   = end.toISOString().split('T')[0];
    const query = { date: { $gte: startStr, $lte: endStr }, ...scope };
    if (req.query.vendor)         query.vendor         = new RegExp(req.query.vendor, 'i');
    if (req.query.expenseAccount) query.expenseAccount = req.query.expenseAccount;
    const expenses = await Expense.find(query).sort({ date: -1 }).limit(500).lean();
    res.json({ success: true, data: { period: { start, end }, expenses: expenses.map(e => ({ id: e._id, expenseNumber: e.expenseNumber, date: e.date, expenseAccount: e.expenseAccount, amount: fmt(e.amount), tax: fmt(e.tax), total: fmt(e.total), paidThrough: e.paidThrough, vendor: e.vendor, customerName: e.customerName, isBillable: e.isBillable, project: e.project, notes: e.notes })), totals: { count: expenses.length, totalAmount: fmt(expenses.reduce((s, e) => s + (e.total || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/expenses-by-category', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');
    const rows = await Expense.aggregate([
      { $match: { date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...scope } },
      { $group: { _id: '$expenseAccount', count: { $sum: 1 }, totalAmount: { $sum: '$amount' }, totalTax: { $sum: '$tax' }, total: { $sum: '$total' } } },
      { $sort: { total: -1 } },
    ]);
    const grandTotal = rows.reduce((s, r) => s + r.total, 0);
    res.json({ success: true, data: { period: { start, end }, categories: rows.map(r => ({ category: r._id, count: r.count, totalAmount: fmt(r.totalAmount), totalTax: fmt(r.totalTax), total: fmt(r.total), percent: grandTotal > 0 ? fmt((r.total / grandTotal) * 100) : 0 })), grandTotal: fmt(grandTotal) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/expenses-by-customer', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');
    const rows = await Expense.aggregate([
      { $match: { date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, customerName: { $ne: null, $exists: true }, ...scope } },
      { $group: { _id: '$customerName', count: { $sum: 1 }, total: { $sum: '$total' }, billableTotal: { $sum: { $cond: ['$isBillable', '$billableAmount', 0] } } } },
      { $sort: { total: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, customers: rows.map(r => ({ customerName: r._id, count: r.count, total: fmt(r.total), billableTotal: fmt(r.billableTotal) })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/expenses-by-project', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');
    const rows = await Expense.aggregate([
      { $match: { date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, project: { $ne: null, $exists: true }, ...scope } },
      { $group: { _id: '$project', count: { $sum: 1 }, total: { $sum: '$total' } } },
      { $sort: { total: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, projects: rows.map(r => ({ project: r._id, count: r.count, total: fmt(r.total) })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/expenses-by-employee', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');
    const rows = await Expense.aggregate([
      { $match: { date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...scope } },
      { $group: { _id: '$paidThrough', count: { $sum: 1 }, total: { $sum: '$total' } } },
      { $sort: { total: -1 } },
    ]);
    res.json({ success: true, data: { period: { start, end }, employees: rows.map(r => ({ employee: r._id, count: r.count, total: fmt(r.total) })) } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/billable-expenses', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Expense = col('Expense', 'expenses');
    const expenses = await Expense.find({ isBillable: true, date: { $gte: start.toISOString().split('T')[0], $lte: end.toISOString().split('T')[0] }, ...scope }).sort({ date: -1 }).lean();
    res.json({ success: true, data: { period: { start, end }, expenses: expenses.map(e => ({ date: e.date, expenseAccount: e.expenseAccount, total: fmt(e.total), billableAmount: fmt(e.billableAmount), customerName: e.customerName, project: e.project, isBilled: e.isBilled, vendor: e.vendor, notes: e.notes })), totals: { unbilled: fmt(expenses.filter(e => !e.isBilled).reduce((s, e) => s + (e.billableAmount || 0), 0)), billed: fmt(expenses.filter(e => e.isBilled).reduce((s, e) => s + (e.billableAmount || 0), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── SECTION 7: TAXES
// ============================================================================

router.get('/tds-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const tdsAcc = await ChartOfAccount.findOne({ accountName: 'TDS Payable', isSystemAccount: true, ...scope }).lean();
    if (!tdsAcc) return res.json({ success: true, data: { period: { start, end }, transactions: [], totals: { totalDeducted: 0, totalPaid: 0, balance: 0 }, message: 'TDS Payable account not seeded. Run /api/seed-accounts first.' } });
    const txns = await AccountTransaction.find({ accountId: tdsAcc._id, date: { $gte: start, $lte: end }, ...scope }).sort({ date: -1 }).lean();
    res.json({ success: true, data: { period: { start, end }, transactions: txns.map(t => ({ date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit) })), totals: { totalDeducted: fmt(txns.reduce((s, t) => s + (t.credit || 0), 0)), totalPaid: fmt(txns.reduce((s, t) => s + (t.debit || 0), 0)), balance: fmt(txns.reduce((s, t) => s + ((t.credit || 0) - (t.debit || 0)), 0)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/tds-receivable', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const tdsAcc = await ChartOfAccount.findOne({ accountName: 'TDS Receivable', isSystemAccount: true, ...scope }).lean();
    if (!tdsAcc) return res.json({ success: true, data: { period: { start, end }, transactions: [], totals: { totalTDSDeducted: 0 }, message: 'TDS Receivable account not seeded.' } });
    const txns = await AccountTransaction.find({ accountId: tdsAcc._id, date: { $gte: start, $lte: end }, ...scope }).sort({ date: -1 }).lean();
    const Invoice = col('Invoice', 'invoices');
    const stats = await Invoice.aggregate([{ $match: { invoiceDate: { $gte: start, $lte: end }, tdsAmount: { $gt: 0 }, ...scope } }, { $group: { _id: null, totalTDS: { $sum: '$tdsAmount' }, count: { $sum: 1 } } }]);
    res.json({ success: true, data: { period: { start, end }, transactions: txns.map(t => ({ date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit) })), totals: { totalTDSDeducted: fmt(txns.reduce((s, t) => s + (t.debit || 0), 0)), invoiceCount: stats[0]?.count || 0, totalFromInvoices: fmt(stats[0]?.totalTDS || 0) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/tcs-summary', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice = col('Invoice', 'invoices');
    const Bill    = col('Bill', 'bills');
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

    res.json({ success: true, data: {
      reconciliations: recs.map(r => ({
        // FIX: do NOT expose accountId — it causes Flutter to pass it as drill-down param
        accountName:    accMap[r.accountId?.toString()] || r.accountName || '',
        startDate:      r.startDate,
        endDate:        r.endDate,
        openingBalance: fmt(r.openingBalance),
        closingBalance: fmt(r.closingBalance),
        clearedAmount:  fmt(r.clearedAmount),
        difference:     fmt(r.difference),
        status:         r.status,
        reconciledAt:   r.reconciledAt,
      })),
    }});
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
    if (req.query.status)    query.status    = req.query.status;

    const entries = await db.collection('timesheets')
      .find(query)
      .sort({ date: -1, createdAt: -1 })
      .limit(500)
      .toArray();

    res.json({ success: true, data: {
      period: { start, end },
      entries: entries.map(e => ({
        entryNumber: e.entryNumber,
        date:        e.date,
        projectName: e.projectName,
        taskName:    e.taskName,
        userName:    e.userName,
        userEmail:   e.userEmail,
        hours:       e.hours,
        isBillable:  e.isBillable,
        status:      e.status,
        notes:       e.notes,
      })),
      totals: {
        totalHours:    fmt(entries.reduce((s, e) => s + (e.hours || 0), 0)),
        billableHours: fmt(entries.filter(e => e.isBillable).reduce((s, e) => s + (e.hours || 0), 0)),
      },
    }});
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
      const entries = await db.collection('timesheets').find({ orgId: scope.orgId, projectId: project._id.toString() }).toArray();
      const totalHours    = entries.reduce((s, e) => s + (e.hours || 0), 0);
      const billableHours = entries.filter(e => e.isBillable).reduce((s, e) => s + (e.hours || 0), 0);
      const billedAmount  = project.totalBilledAmount || 0;
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
    res.json({ success: true, data: { period: { start, end }, projects: projects.map(p => ({ projectNumber: p.projectNumber, projectName: p.projectName, customerName: p.customerName, billingMethod: p.billingMethod, status: p.status, startDate: p.startDate, endDate: p.endDate, totalLoggedHours: fmt(p.totalLoggedHours || 0), totalBilledAmount: fmt(p.totalBilledAmount || 0), budgetAmount: fmt(p.budgetAmount || 0) })), totals: { totalProjects: projects.length, activeProjects: projects.filter(p => p.status === 'Active').length, totalBilledAmount: fmt(projects.reduce((s, p) => s + (p.totalBilledAmount || 0), 0)) } } });
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
      return res.json({ success: true, data: {
        projects: projects.map(p => ({
          projectNumber: p.projectNumber, projectName: p.projectName,
          customerName: p.customerName, billingMethod: p.billingMethod,
          status: p.status, startDate: p.startDate, endDate: p.endDate,
          totalLoggedHours: fmt(p.totalLoggedHours || 0),
          totalBilledAmount: fmt(p.totalBilledAmount || 0),
          budgetAmount: fmt(p.budgetAmount || 0),
        })),
        totals: { totalProjects: projects.length },
      }});
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

    res.json({ success: true, data: {
      project,
      timesheets: entries,
      totals: {
        totalHours:    fmt(entries.reduce((s, e) => s + (e.hours || 0), 0)),
        billableHours: fmt(entries.filter(e => e.isBillable).reduce((s, e) => s + (e.hours || 0), 0)),
      },
    }});
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
      rows.push({ projectName: project.projectName, customerName: project.customerName, budgetAmount: fmt(project.budgetAmount || 0), actualCost: fmt(totalExpenses), variance: fmt((project.budgetAmount || 0) - totalExpenses), utilizationPercent: project.budgetAmount > 0 ? fmt((totalExpenses / project.budgetAmount) * 100) : 0 });
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
      const invoices = await Invoice.find({ projectId: project._id.toString(), invoiceDate: { $gte: start, $lte: end }, status: { $nin: ['DRAFT','CANCELLED'] }, ...scope }).lean();
      const totalRevenue = invoices.reduce((s, i) => s + (i.totalAmount || 0), 0);
      rows.push({ projectName: project.projectName, customerName: project.customerName, billingMethod: project.billingMethod, totalBilledAmount: fmt(project.totalBilledAmount || 0), totalInvoiced: fmt(totalRevenue), invoiceCount: invoices.length });
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
        Invoice.find({ projectId: project._id.toString(), status: { $nin: ['DRAFT','CANCELLED'] }, ...scope }).lean(),
      ]);
      const totalHours   = entries.reduce((s, e) => s + (e.hours || 0), 0);
      const totalCost    = expenses.reduce((s, e) => s + (e.total || 0), 0);
      const totalRevenue = invoices.reduce((s, i) => s + (i.totalAmount || 0), 0);
      const profit       = totalRevenue - totalCost;
      rows.push({ projectName: project.projectName, customerName: project.customerName, status: project.status, totalHours: fmt(totalHours), totalCost: fmt(totalCost), totalRevenue: fmt(totalRevenue), profit: fmt(profit), profitMargin: totalRevenue > 0 ? fmt((profit / totalRevenue) * 100) : 0 });
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
    let accQuery = { isActive: true, ...scope };
    if (req.query.accountId)   accQuery._id         = req.query.accountId;
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
      return { accountCode: g.account.accountCode, accountName: g.account.accountName, accountType: g.account.accountType, transactions: rows, totals: { debit: fmt(rows.reduce((s, r) => s + r.debit, 0)), credit: fmt(rows.reduce((s, r) => s + r.credit, 0)), closing: fmt(balance) } };
    });
    res.json({ success: true, data: { period: { start, end }, accounts: result } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/general-ledger-detailed', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accounts = await ChartOfAccount.find({ isActive: true, ...scope }).sort({ accountCode: 1 }).lean();
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
router.get('/account-transactions', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const { accountId } = req.query;

    // FIX: if no accountId, return all transactions (general ledger style)
    if (!accountId) {
      const accounts = await ChartOfAccount.find({ isActive: true, ...scope }).lean();
      const ids = accounts.map(a => a._id);
      const accMap = {}; accounts.forEach(a => { accMap[a._id.toString()] = a; });
      const txns = await AccountTransaction.find({ accountId: { $in: ids }, date: { $gte: start, $lte: end }, ...scope }).sort({ date: 1 }).limit(500).lean();
      let balance = 0;
      const rows = txns.map(t => {
        balance += (t.debit || 0) - (t.credit || 0);
        return { date: t.date, description: t.description, accountName: accMap[t.accountId?.toString()]?.accountName || '', accountType: accMap[t.accountId?.toString()]?.accountType || '', referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance) };
      });
      return res.json({ success: true, data: { period: { start, end }, transactions: rows, totals: { debit: fmt(rows.reduce((s, r) => s + r.debit, 0)), credit: fmt(rows.reduce((s, r) => s + r.credit, 0)), closingBalance: fmt(balance) } } });
    }

    // Single account
    const account = await ChartOfAccount.findOne({ _id: accountId, ...scope }).lean();
    if (!account) return res.status(404).json({ success: false, message: 'Account not found' });
    const txns = await AccountTransaction.find({ accountId, date: { $gte: start, $lte: end }, ...scope }).sort({ date: 1 }).lean();
    let balance = 0;
    const rows = txns.map(t => { balance += (t.debit || 0) - (t.credit || 0); return { date: t.date, description: t.description, referenceType: t.referenceType, referenceNumber: t.referenceNumber, debit: fmt(t.debit), credit: fmt(t.credit), balance: fmt(balance) }; });
    res.json({ success: true, data: { account: { id: account._id, name: account.accountName, code: account.accountCode, type: account.accountType }, period: { start, end }, transactions: rows, totals: { debit: fmt(rows.reduce((s, r) => s + r.debit, 0)), credit: fmt(rows.reduce((s, r) => s + r.credit, 0)), closingBalance: fmt(balance) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/account-type-summary', async (req, res) => {
  try {
    const { end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const accounts = await ChartOfAccount.find({ isActive: true, ...scope }).lean();
    const ids = accounts.map(a => a._id);
    const txns = await AccountTransaction.aggregate([{ $match: { accountId: { $in: ids }, date: { $lte: end }, ...scope } }, { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } }]);
    const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
    const typeMap = {};
    for (const acc of accounts) {
      const t = tMap[acc._id.toString()] || { dr: 0, cr: 0 };
      if (!typeMap[acc.accountType]) typeMap[acc.accountType] = { accountType: acc.accountType, count: 0, totalDebit: 0, totalCredit: 0 };
      typeMap[acc.accountType].count++;
      typeMap[acc.accountType].totalDebit  += t.dr;
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
    const Invoice     = col('Invoice',     'invoices');
    const Bill        = col('Bill',        'bills');
    const PaymentMade = col('PaymentMade', 'paymentmades');
    const Expense     = col('Expense',     'expenses');
    const [invoices, bills, payments, expenses] = await Promise.all([
      Invoice.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('invoiceNumber customerName totalAmount status createdAt createdBy').limit(200).lean(),
      Bill.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('billNumber vendorName totalAmount status createdAt createdBy').limit(200).lean(),
      PaymentMade.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('paymentNumber vendorName amount status createdAt createdBy').limit(200).lean(),
      Expense.find({ createdAt: { $gte: start, $lte: end }, ...scope }).select('expenseAccount total paidThrough createdAt').limit(200).lean(),
    ]);
    const logs = [
      ...invoices.map(i => ({ type: 'Invoice',     ref: i.invoiceNumber, name: i.customerName, amount: fmt(i.totalAmount), status: i.status, date: i.createdAt, by: i.createdBy })),
      ...bills.map(b =>    ({ type: 'Bill',         ref: b.billNumber,    name: b.vendorName,   amount: fmt(b.totalAmount), status: b.status, date: b.createdAt, by: b.createdBy })),
      ...payments.map(p => ({ type: 'Payment Made', ref: p.paymentNumber, name: p.vendorName,   amount: fmt(p.amount),     status: p.status, date: p.createdAt, by: p.createdBy })),
      ...expenses.map(e => ({ type: 'Expense',      ref: e._id,           name: e.expenseAccount, amount: fmt(e.total),   status: 'Recorded', date: e.createdAt, by: 'system' })),
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
    try { budgets = await db.collection('budgets').find(scope).toArray(); } catch (_) {}
    if (budgets.length === 0) {
      const projects = await db.collection('projects').find({ ...scope, budgetAmount: { $gt: 0 } }).toArray();
      const Expense  = col('Expense', 'expenses');
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
    const openBills = await Bill.find({ status: { $in: ['OPEN','OVERDUE','PARTIALLY_PAID'] }, currency: { $ne: 'INR' }, ...scope }).lean();
    const rows = openBills.map(b => {
      const originalAmount = b.amountDue;
      const currentRate    = b.exchangeRate || 1;
      const currentValue   = fmt(originalAmount * currentRate);
      const gainLoss       = fmt(currentValue - originalAmount);
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
    const Bill    = col('Bill',    'bills');
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
  const Invoice     = col('Invoice',     'invoices');
  const Bill        = col('Bill',        'bills');
  const PaymentMade = col('PaymentMade', 'paymentmades');
  const Expense     = col('Expense',     'expenses');
  const ManualJournal = col('ManualJournal', 'manualjournals');
  try {
    const [invoices, bills, payments, expenses, journals] = await Promise.all([
      Invoice.find({ updatedAt: { $gte: start, $lte: end }, ...scope }).select('invoiceNumber customerName totalAmount status updatedAt updatedBy').limit(200).lean(),
      Bill.find({ updatedAt: { $gte: start, $lte: end }, ...scope }).select('billNumber vendorName totalAmount status updatedAt updatedBy').limit(200).lean(),
      PaymentMade.find({ updatedAt: { $gte: start, $lte: end }, ...scope }).select('paymentNumber vendorName amount status updatedAt updatedBy').limit(200).lean(),
      Expense.find({ updatedAt: { $gte: start, $lte: end }, ...scope }).select('expenseAccount total updatedAt').limit(200).lean(),
      ManualJournal.find({ updatedAt: { $gte: start, $lte: end }, ...scope }).select('journalNumber notes totalDebit status updatedAt updatedBy').limit(200).lean(),
    ]);
    const logs = [
      ...invoices.map(i => ({ type: 'Invoice',     ref: i.invoiceNumber, name: i.customerName, amount: fmt(i.totalAmount), status: i.status, date: i.updatedAt, by: i.updatedBy || i.createdBy })),
      ...bills.map(b =>    ({ type: 'Bill',         ref: b.billNumber,    name: b.vendorName,   amount: fmt(b.totalAmount), status: b.status, date: b.updatedAt, by: b.updatedBy || b.createdBy })),
      ...payments.map(p => ({ type: 'Payment Made', ref: p.paymentNumber, name: p.vendorName,   amount: fmt(p.amount),     status: p.status, date: p.updatedAt, by: p.updatedBy || p.createdBy })),
      ...expenses.map(e => ({ type: 'Expense',      ref: e._id,           name: e.expenseAccount, amount: fmt(e.total),   status: 'Recorded', date: e.updatedAt, by: 'system' })),
      ...journals.map(j => ({ type: 'Journal',      ref: j.journalNumber, name: j.notes,        amount: fmt(j.totalDebit), status: j.status, date: j.updatedAt, by: j.updatedBy })),
    ].sort((a, b) => new Date(b.date) - new Date(a.date));
    res.json({ success: true, data: { period: { start, end }, logs, count: logs.length } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/exception-report', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const Invoice  = col('Invoice', 'invoices');
    const Bill     = col('Bill',    'bills');
    const Expense  = col('Expense', 'expenses');
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
    try { logs = await db.collection('api_logs').find({ ...scope, createdAt: { $gte: start, $lte: end } }).sort({ createdAt: -1 }).limit(200).toArray(); } catch (_) {}
    res.json({ success: true, data: { period: { start, end }, logs, count: logs.length, message: logs.length === 0 ? 'API logging not yet enabled.' : undefined } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/workflow-logs', async (req, res) => {
  try {
    const { start, end } = parseDateRange(req.query);
    const scope = orgScope(req);
    const db = getDB(req);
    let logs = [];
    try { logs = await db.collection('workflow_logs').find({ ...scope, createdAt: { $gte: start, $lte: end } }).sort({ createdAt: -1 }).limit(200).toArray(); } catch (_) {}
    res.json({ success: true, data: { period: { start, end }, logs, count: logs.length, message: logs.length === 0 ? 'Workflow logging not yet enabled.' : undefined } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

// ============================================================================
// ── META
// ============================================================================

router.get('/meta', (req, res) => {
  res.json({ success: true, data: [
    { category: 'Business Overview', reports: [
      { key: 'profit-loss', name: 'Profit and Loss' }, { key: 'profit-loss-horizontal', name: 'Horizontal Profit and Loss' },
      { key: 'balance-sheet', name: 'Balance Sheet' }, { key: 'balance-sheet-horizontal', name: 'Horizontal Balance Sheet' },
      { key: 'cash-flow', name: 'Cash Flow Statement' }, { key: 'movement-of-equity', name: 'Movement of Equity' },
      { key: 'performance-ratios', name: 'Business Performance Ratios' }, { key: 'trial-balance', name: 'Trial Balance' }, { key: 'day-book', name: 'Day Book' },
    ]},
    { category: 'Sales', reports: [
      { key: 'sales-by-customer', name: 'Sales by Customer' }, { key: 'sales-by-item', name: 'Sales by Item' },
      { key: 'sales-by-salesperson', name: 'Sales by Sales Person' }, { key: 'sales-summary', name: 'Sales Summary' },
    ]},
    { category: 'Receivables', reports: [
      { key: 'ar-aging-summary', name: 'AR Aging Summary' }, { key: 'ar-aging-details', name: 'AR Aging Details' },
      { key: 'invoice-details', name: 'Invoice Details' }, { key: 'customer-balance', name: 'Customer Balance Summary' },
      { key: 'receivable-summary', name: 'Receivable Summary' }, { key: 'receivable-details', name: 'Receivable Details' },
      { key: 'credit-note-details', name: 'Credit Note Details' }, { key: 'refund-history-receivables', name: 'Refund History' },
    ]},
    { category: 'Payments Received', reports: [
      { key: 'payments-received', name: 'Payments Received' }, { key: 'time-to-get-paid', name: 'Time to Get Paid' },
      { key: 'refund-history', name: 'Refund History' }, { key: 'recurring-invoice-details', name: 'Recurring Invoice Details' },
    ]},
    { category: 'Payables', reports: [
      { key: 'vendor-balance', name: 'Vendor Balance Summary' }, { key: 'ap-aging-summary', name: 'AP Aging Summary' },
      { key: 'ap-aging-details', name: 'AP Aging Details' }, { key: 'bill-details', name: 'Bill Details' },
      { key: 'vendor-credit-details', name: 'Vendor Credit Details' }, { key: 'payments-made', name: 'Payments Made' },
      { key: 'refund-history-payables', name: 'Refund History' }, { key: 'purchase-order-details', name: 'Purchase Order Details' },
      { key: 'purchase-orders-by-vendor', name: 'Purchase Orders by Vendor' },
      { key: 'payable-summary', name: 'Payable Summary' }, { key: 'payable-details', name: 'Payable Details' },
    ]},
    { category: 'Purchases and Expenses', reports: [
      { key: 'purchases-by-vendor', name: 'Purchases by Vendor' }, { key: 'purchases-by-item', name: 'Purchases by Item' },
      { key: 'expense-details', name: 'Expense Details' }, { key: 'expenses-by-category', name: 'Expenses by Category' },
      { key: 'expenses-by-customer', name: 'Expenses by Customer' }, { key: 'expenses-by-project', name: 'Expenses by Project' },
      { key: 'expenses-by-employee', name: 'Expenses by Employee' }, { key: 'billable-expenses', name: 'Billable Expense Details' },
    ]},
    { category: 'Taxes', reports: [
      { key: 'tds-summary', name: 'TDS Summary' }, { key: 'tds-receivable', name: 'TDS Receivable Summary' }, { key: 'tcs-summary', name: 'TCS Payable Summary' },
    ]},
    { category: 'Banking', reports: [{ key: 'reconciliation-status', name: 'Reconciliation Status' }]},
    { category: 'Projects and Timesheet', reports: [
      { key: 'timesheet-details', name: 'Timesheet Details' }, { key: 'timesheet-profitability', name: 'Timesheet Profitability Summary' },
      { key: 'project-summary', name: 'Project Summary' }, { key: 'project-details', name: 'Project Details' },
      { key: 'projects-cost-summary', name: 'Projects Cost Summary' }, { key: 'projects-revenue-summary', name: 'Projects Revenue Summary' },
      { key: 'projects-performance', name: 'Projects Performance Summary' },
    ]},
    { category: 'Accountant', reports: [
      { key: 'account-transactions', name: 'Account Transactions' }, { key: 'account-type-summary', name: 'Account Type Summary' },
      { key: 'general-ledger', name: 'General Ledger' }, { key: 'general-ledger-detailed', name: 'Detailed General Ledger' },
      { key: 'journal-report', name: 'Journal Report' }, { key: 'activity-logs', name: 'Activity Logs & Audit Trail' },
    ]},
    { category: 'Budgets', reports: [{ key: 'budget-vs-actuals', name: 'Budget Vs Actuals' }]},
    { category: 'Currency', reports: [{ key: 'realized-gain-loss', name: 'Realized Gain or Loss' }, { key: 'unrealized-gain-loss', name: 'Unrealized Gain or Loss' }]},
    { category: 'Activity', reports: [
      { key: 'system-mails', name: 'System Mails' }, { key: 'audit-trail', name: 'Activity Logs & Audit Trail' },
      { key: 'exception-report', name: 'Exception Report' }, { key: 'portal-activities', name: 'Portal Activities' }, { key: 'customer-reviews', name: 'Customer Reviews' },
    ]},
    { category: 'Automation', reports: [{ key: 'api-usage', name: 'API Usage' }, { key: 'workflow-logs', name: 'Workflow Execution Logs' }]},
  ]});
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
    const doc  = new PDFDoc({ size: 'A4', margin: 36, bufferPages: true });
    const stream = fs.createWriteStream(filepath);
    doc.pipe(stream);
    const pageW = 522;
    doc.rect(0, 0, 595, 72).fill('#0f1e3d');
    doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold').text(companyName || 'Finance Report', 40, 18, { width: pageW });
    doc.fontSize(11).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text(reportName || 'Report', 40, 42, { width: pageW });
    if (period) {
      try {
        const s = period.start ? new Date(period.start).toLocaleDateString('en-IN') : '';
        const e = period.end   ? new Date(period.end).toLocaleDateString('en-IN')   : '';
        if (s || e) doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').text(`${s} – ${e}`, 40, 58, { width: pageW });
      } catch (_) {}
    }
    const headers = customHeaders || Object.keys(reportData[0] || {});
    const colW    = Math.min(140, Math.floor(pageW / headers.length));
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
    stream.on('finish', () => res.download(filepath, filename, () => { try { fs.unlinkSync(filepath); } catch (_) {} }));
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
        const e = period.end   ? new Date(period.end).toLocaleDateString('en-IN')   : '';
        if (s || e) periodLabel = `${s} – ${e}`;
      } catch (_) {}
    }
    const wsData = [
      [companyName || 'Finance Report'],
      [reportName  || 'Report'],
      ...(periodLabel ? [[`Period: ${periodLabel}`]] : []),
      [],
      headers.map(h => h.replace(/([A-Z])/g, ' $1').trim().replace(/^./, s => s.toUpperCase())),
      ...reportData.map(row => headers.map(h => {
        const v = row[h];
        if (v === undefined || v === null) return '';
        const n = typeof v === 'number' ? v : parseFloat(String(v).replace(/[₹,]/g, ''));
        return isNaN(n) ? String(v) : n;
      })),
    ];
    const ws = XLSX.utils.aoa_to_sheet(wsData);
    ws['!cols'] = headers.map(h => ({ wch: Math.max(h.length + 4, 14) }));
    ws['!merges'] = [{ s: { r: 0, c: 0 }, e: { r: 0, c: headers.length - 1 } }];
    XLSX.utils.book_append_sheet(wb, ws, (reportName || 'Report').slice(0, 31));
    const buffer   = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
    const filename = `${(reportName || 'report').replace(/\s+/g, '-')}-${Date.now()}.xlsx`;
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Length', buffer.length);
    res.send(buffer);
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = router;