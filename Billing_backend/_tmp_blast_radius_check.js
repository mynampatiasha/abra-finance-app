require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const TRACKING_NO_LINE = /^([A-Za-z]{1,6}-[A-Za-z0-9-]+)\s*$/;
function resolveItemTrackingNo(item) {
  let trackingNo = item.shipmentTrackingNumber || item.expenseId || null;
  if (!trackingNo && item.itemDetails) {
    const firstLine = String(item.itemDetails).split('\n')[0].trim();
    const m = firstLine.match(TRACKING_NO_LINE);
    if (m) trackingNo = m[1];
  }
  return trackingNo;
}

async function main() {
  const client = new MongoClient(process.env.MONGODB_URI);
  await client.connect();
  const db = client.db();

  // 1. Check indexes on billedshipments
  const indexes = await db.collection('billedshipments').indexes();
  console.log('=== Indexes on billedshipments ===');
  indexes.forEach(i => console.log(' -', JSON.stringify(i.key), i.unique ? '(UNIQUE)' : ''));

  // 2. Check invoiceId field type consistency in existing records
  const sample = await db.collection('billedshipments').find({}).limit(3).toArray();
  console.log('\n=== Sample existing BilledShipment invoiceId types ===');
  sample.forEach(s => console.log(' -', s.trackingNo, '| invoiceId type:', s.invoiceId?.constructor?.name, '| value:', s.invoiceId?.toString()));

  // 3. Full-system scan: ALL invoices, ALL months — find AL numbers embedded in
  //    itemDetails with null shipmentTrackingNumber, missing from BilledShipment
  const invoices = await db.collection('invoices').find({ items: { $exists: true, $ne: [] } })
    .project({ invoiceNumber: 1, status: 1, items: 1 }).toArray();

  const invoiceTrackingMap = {}; // trackingNo -> [{invoiceNumber, invoiceId}]
  for (const inv of invoices) {
    for (const item of inv.items) {
      const trackingNo = resolveItemTrackingNo(item);
      if (trackingNo && /^[A-Za-z]{1,6}-/.test(trackingNo)) { // only AL-style, exclude expenseId (ObjectId) matches
        if (!invoiceTrackingMap[trackingNo]) invoiceTrackingMap[trackingNo] = [];
        invoiceTrackingMap[trackingNo].push({ invoiceNumber: inv.invoiceNumber, invoiceId: inv._id });
      }
    }
  }
  console.log('\nTotal distinct AL numbers embedded across ALL invoices (all months):', Object.keys(invoiceTrackingMap).length);

  const billed = await db.collection('billedshipments').find({}).toArray();
  const billedSet = new Set(billed.map(b => b.trackingNo));

  const missingFromBilled = Object.keys(invoiceTrackingMap).filter(t => !billedSet.has(t));
  console.log('Total AL numbers in real invoices but MISSING from BilledShipment (ALL months):', missingFromBilled.length);

  // 4. Check for duplicates: same AL number appearing on MULTIPLE different invoices
  const multiInvoice = missingFromBilled.filter(t => {
    const uniqueInvNums = new Set(invoiceTrackingMap[t].map(x => x.invoiceNumber));
    return uniqueInvNums.size > 1;
  });
  console.log('Of those, AL numbers appearing on MORE THAN ONE invoice (ambiguous which to backfill):', multiInvoice.length);
  multiInvoice.forEach(t => console.log('  -', t, '->', [...new Set(invoiceTrackingMap[t].map(x => x.invoiceNumber))]));

  // 5. Double-booking check: is any "missing from billed" AL number ALSO
  //    currently sitting in an active (unapproved) staging draft?
  const drafts = await db.collection('automationdrafts').find({}).toArray();
  const stagingTrackingNos = new Set();
  for (const d of drafts) {
    if (!Array.isArray(d.items)) continue;
    for (const item of d.items) {
      const t = resolveItemTrackingNo(item);
      if (t) stagingTrackingNos.add(t);
    }
  }
  const doubleBooked = missingFromBilled.filter(t => stagingTrackingNos.has(t));
  console.log('\nAL numbers that are BOTH already invoiced AND currently sitting in an active staging draft (double-booking risk, pre-existing, not caused by backfill):', doubleBooked.length);
  doubleBooked.forEach(t => console.log('  -', t, '-> already in invoice(s):', invoiceTrackingMap[t].map(x=>x.invoiceNumber).join(','), '+ currently staged'));

  await client.close();
}
main().catch(e => { console.error(e); process.exit(1); });
