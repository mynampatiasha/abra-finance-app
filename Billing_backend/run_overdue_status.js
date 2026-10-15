// One-off run of the daily overdue-status job (same code the 6 AM job uses).
//   node run_overdue_status.js          -> DRY RUN: lists what would change, writes nothing
//   node run_overdue_status.js --apply  -> saves a restore file, then marks those invoices OVERDUE
// Only UNPAID / SENT invoices that are past their due date with nothing paid are touched.
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');

(async () => {
  const apply = process.argv.includes('--apply');
  await mongoose.connect(process.env.MONGODB_URI || process.env.MONGO_URI);
  require('./routes/invoices'); // registers the Invoice model
  const { runOverdueStatusJob } = require('./jobs/reminderScheduler');

  const before = await runOverdueStatusJob({ dryRun: true });
  console.log(`${before.matched} invoice(s) match:`);
  before.invoices.forEach(i =>
    console.log(`  ${i.invoiceNumber}  ${i.status}  due ${new Date(i.dueDate).toISOString().slice(0, 10)}`));

  if (!apply) {
    console.log('\nDRY RUN - nothing was changed. Run again with --apply to apply.');
  } else if (before.matched === 0) {
    console.log('\nNothing to do.');
  } else {
    // restore file: the _id and old status of every invoice about to change
    const dir = path.join(__dirname, 'backups');
    fs.mkdirSync(dir, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const file = path.join(dir, `overdue_status_before_${stamp}.json`);
    fs.writeFileSync(file, JSON.stringify(before.invoices, null, 2));
    console.log(`\nRestore file saved: ${file}`);
    const r = await runOverdueStatusJob({ dryRun: false });
    console.log(`APPLIED - marked OVERDUE: ${r.updated}`);
  }
  await mongoose.disconnect();
  process.exit(0);
})().catch(e => { console.error('FAILED:', e.message); process.exit(1); });
