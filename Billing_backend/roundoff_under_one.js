// =============================================================================
// ROUND OFF leftovers under Rs 1 on partly-paid invoices.
//
// An invoice paid to the rupee (total 73,759.44, paid 73,759) stays "PARTIALLY
// PAID" with Rs 0.44 "due". This writes the leftover off with the invoice's own
// Adjustment (round-off), so total - paid = 0 and the invoice becomes PAID.
//
//   node roundoff_under_one.js --org <orgId>                 DRY RUN (writes nothing real)
//   node roundoff_under_one.js --org <orgId> --apply         apply to every eligible invoice
//   node roundoff_under_one.js --org <orgId> --apply --limit 3        only the first 3
//   node roundoff_under_one.js --org <orgId> --apply --only INV000023,INV000025
//
// Each invoice is changed through the app's own invoice-edit route (PUT /:id), the
// same code the Edit screen uses: the invoice is recalculated and saved, its old
// ledger rows are removed and re-posted (Accounts Receivable, Sales, GST, TDS,
// Other Charges for the adjustment). Nothing is written directly to the ledger.
//
// Only invoices that are partly paid (or unpaid/overdue/sent with a payment) and
// have a balance of MORE than 0 and LESS than Rs 1 are touched. Invoices with
// "auto round-off" turned on are skipped (their save rule would undo the change).
// =============================================================================
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');
const express = require('express');

const r2 = (x) => Math.round(x * 100) / 100;
const arg = (name) => { const i = process.argv.indexOf(name); return i >= 0 ? process.argv[i + 1] : undefined; };

async function run({ orgId, apply = false, limit = 0, only = null, log = console.log, dbName = 'abra_finance_module', skipConnect = false }) {
  if (!orgId) throw new Error('--org <orgId> is required');
  if (!skipConnect) await mongoose.connect(process.env.MONGODB_URI || process.env.MONGO_URI, { dbName });
  const db = mongoose.connection.db;
  const invRouter = require('./routes/invoices'); // registers the Invoice model
  const Invoice = mongoose.models.Invoice;
  const cInv = db.collection('invoices');
  const cTx = db.collection('accounttransactions');

  const filter = {
    orgId,
    status: { $in: ['PARTIALLY_PAID', 'OVERDUE', 'UNPAID', 'SENT'] },
    amountPaid: { $gt: 0 },
    amountDue: { $gt: 0, $lt: 1 },
  };
  let all = await cInv.find(filter).sort({ invoiceNumber: 1 }).toArray();
  if (only) all = all.filter((i) => only.includes(i.invoiceNumber));
  const skippedAuto = all.filter((i) => i.autoRoundOff === true);
  let targets = all.filter((i) => i.autoRoundOff !== true);
  log(`org ${orgId}: ${all.length} invoice(s) with a balance under Rs 1; ${skippedAuto.length} skipped (auto round-off on); ${targets.length} eligible`);
  skippedAuto.forEach((i) => log(`   skipped (auto round-off on): ${i.invoiceNumber}`));

  // ---- pre-check: would the invoice's own save rule turn each one into PAID with
  // everything else unchanged?  Runs on a scratch collection that is dropped after.
  const scratchName = 'zz_roundoff_precheck_tmp';
  let Dry = mongoose.models.InvoiceDryRun;
  if (!Dry) {
    const scratchSchema = Invoice.schema.clone();
    scratchSchema.set('autoCreate', false);
    scratchSchema.set('autoIndex', false);
    Dry = mongoose.model('InvoiceDryRun', scratchSchema, scratchName);
  }
  const plan = [];
  const rejected = [];
  const { ChartOfAccount } = require('./routes/chart_of_accounts');
  const hasAccount = async (name, branchId) => {
    let acc = await ChartOfAccount.findOne({ accountName: name, isSystemAccount: true, orgId, branchId: branchId || null }).select('_id').lean();
    if (!acc && branchId) acc = await ChartOfAccount.findOne({ accountName: name, isSystemAccount: true, orgId, branchId: null }).select('_id').lean();
    return !!acc;
  };
  try {
    for (const inv of targets) {
      // the edit route re-posts to these accounts; if one is missing it would remove
      // the old ledger rows and post nothing, so such an invoice is left alone
      const need = ['Accounts Receivable', 'Sales', 'Other Charges'];
      if (inv.totalTax > 0) need.push('Tax Payable');
      if (inv.tdsAmount > 0) need.push('TDS Receivable');
      if (inv.tcsAmount > 0) need.push('TDS Payable');
      const missing = [];
      for (const n of need) if (!(await hasAccount(n, inv.branchId))) missing.push(n);
      if (missing.length) { rejected.push({ no: inv.invoiceNumber, why: 'accounts missing: ' + missing.join(', ') }); continue; }

      const bal = r2(inv.amountDue);
      const newAdj = r2((inv.adjustment || 0) - bal);
      const doc = new Dry({ ...inv, _id: new mongoose.Types.ObjectId() });
      doc.adjustment = newAdj;
      let why = null;
      try { await doc.save(); } catch (e) { why = 'precheck save failed: ' + e.message; }
      if (!why) {
        const same = (a, b) => Math.abs((a || 0) - (b || 0)) < 0.005;
        if (doc.status !== 'PAID') why = `would be ${doc.status}, not PAID`;
        else if (!same(doc.totalAmount, inv.amountPaid)) why = `new total ${doc.totalAmount} != paid ${inv.amountPaid}`;
        else if (!same(doc.subTotal, inv.subTotal) || !same(doc.totalTax, inv.totalTax) || !same(doc.tdsAmount, inv.tdsAmount) || !same(doc.taxableTotal, inv.taxableTotal)) why = 'recalculation would change subtotal/tax/TDS';
        else if (!same(doc.totalAmount, r2((inv.totalAmount) - bal))) why = `new total ${doc.totalAmount} != old total - leftover`;
      }
      if (why) rejected.push({ no: inv.invoiceNumber, why }); else plan.push({ inv, bal, newAdj, newTotal: r2(inv.totalAmount - bal) });
    }
  } finally {
    try { await db.collection(scratchName).drop(); } catch (_) {}
  }
  rejected.forEach((r) => log(`   NOT eligible (left alone): ${r.no} - ${r.why}`));
  let toDo = plan;
  if (limit > 0) toDo = plan.slice(0, limit);
  log(`passed the pre-check: ${plan.length}${limit > 0 ? ` | this run: first ${toDo.length}` : ''}`);
  toDo.forEach((p) => log(`   ${p.inv.invoiceNumber}  ${String(p.inv.customerName || '').slice(0, 24).padEnd(24)} total ${p.inv.totalAmount} -> ${p.newTotal} | write off ${p.bal} | adjustment ${p.inv.adjustment || 0} -> ${p.newAdj}`));
  log(`total to write off this run: Rs ${r2(toDo.reduce((s, p) => s + p.bal, 0))}`);

  const result = { eligible: plan.length, rejected, applied: [], stopped: null, dryRun: !apply };
  if (!apply) { log('\nDRY RUN - nothing was changed.'); return result; }
  if (toDo.length === 0) { log('\nNothing to do.'); return result; }

  // ---- restore snapshot of exactly what is about to change
  const { EJSON } = require('bson');
  const ids = toDo.map((p) => p.inv._id);
  const snapInv = await cInv.find({ _id: { $in: ids } }).toArray();
  const snapTx = await cTx.find({ referenceType: 'Invoice', referenceId: { $in: [...ids, ...ids.map(String)] } }).toArray();
  const stamp = new Date(Date.now() + 5.5 * 3600e3).toISOString().replace(/[-:]/g, '').replace('T', '_').slice(0, 13);
  const dir = path.join(__dirname, 'backups', `roundoff_applied_${stamp}_EJSON`);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'invoices_before.json'), EJSON.stringify(snapInv, null, 2, { relaxed: false }));
  fs.writeFileSync(path.join(dir, 'accounttransactions_before.json'), EJSON.stringify(snapTx, null, 2, { relaxed: false }));
  log(`\nrestore snapshot saved: ${dir}  (invoices ${snapInv.length}, ledger rows ${snapTx.length})`);

  // ---- apply through the real edit route
  const app = express();
  app.use(express.json());
  app.use('/t', (q, s, n) => { q.user = { orgId, email: 'roundoff-script' }; q.orgFilter = { orgId }; q.branchFilter = {}; q.branchIds = []; n(); }, invRouter);
  const srv = app.listen(0);
  const port = srv.address().port;
  try {
    for (const p of toDo) {
      const id = p.inv._id;
      const now = await cInv.findOne({ _id: id });
      // re-check right before changing (someone may have fixed it by hand meanwhile)
      if (!now || now.status === 'PAID' || !(now.amountDue > 0 && now.amountDue < 1) || now.autoRoundOff === true || r2(now.amountDue) !== p.bal) {
        log(`   ${p.inv.invoiceNumber}: changed since the list - skipped`);
        continue;
      }
      const res = await fetch(`http://localhost:${port}/t/${id}`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ adjustment: p.newAdj }) });
      const body = await res.json().catch(() => ({}));
      const after = await cInv.findOne({ _id: id });
      const rows = await cTx.find({ referenceType: 'Invoice', referenceId: id, orgId }).toArray();
      const dr = r2(rows.reduce((s, t) => s + (t.debit || 0), 0));
      const cr = r2(rows.reduce((s, t) => s + (t.credit || 0), 0));
      const checks = [
        [res.status === 200 && body.success === true, `route replied ${res.status} ${body.error || ''}`],
        [after.status === 'PAID', `status ${after.status}`],
        [Math.abs(after.amountDue) < 0.005, `amountDue ${after.amountDue}`],
        [Math.abs(after.totalAmount - p.newTotal) < 0.005, `total ${after.totalAmount} != ${p.newTotal}`],
        [Math.abs(after.amountPaid - p.inv.amountPaid) < 0.005, `amountPaid changed to ${after.amountPaid}`],
        [Math.abs(after.adjustment - p.newAdj) < 0.005, `adjustment ${after.adjustment} != ${p.newAdj}`],
        [rows.length > 0, 'no ledger rows after re-post'],
        [Math.abs(dr - cr) < 0.011, `ledger not balanced: Dr ${dr} Cr ${cr}`],
        [rows.some((t) => Math.abs((t.debit || 0) - after.totalAmount) < 0.005), 'Accounts Receivable debit != new total'],
      ];
      const bad = checks.filter((c) => !c[0]);
      if (bad.length) {
        result.stopped = { no: p.inv.invoiceNumber, problems: bad.map((b) => b[1]) };
        log(`   !! ${p.inv.invoiceNumber}: STOPPED - ${bad.map((b) => b[1]).join('; ')}`);
        break;
      }
      result.applied.push({ no: p.inv.invoiceNumber, writeOff: p.bal, newTotal: after.totalAmount, ledgerRows: rows.length });
      log(`   ok ${p.inv.invoiceNumber}  ${p.inv.totalAmount} -> ${after.totalAmount}  PAID  | ledger Dr ${dr} = Cr ${cr} (${rows.length} rows)`);
    }
  } finally {
    srv.close();
  }
  fs.writeFileSync(path.join(dir, 'result.json'), JSON.stringify(result, null, 2));
  log(`\napplied: ${result.applied.length} | written off: Rs ${r2(result.applied.reduce((s, a) => s + a.writeOff, 0))}${result.stopped ? ' | STOPPED at ' + result.stopped.no : ''}`);
  return result;
}

module.exports = { run };

if (require.main === module) {
  run({
    orgId: arg('--org'),
    apply: process.argv.includes('--apply'),
    limit: Number(arg('--limit') || 0),
    only: arg('--only') ? arg('--only').split(',').map((s) => s.trim()) : null,
  })
    .then(async () => { await mongoose.disconnect(); process.exit(0); })
    .catch(async (e) => { console.error('FAILED:', e.message); try { await mongoose.disconnect(); } catch (_) {} process.exit(1); });
}
