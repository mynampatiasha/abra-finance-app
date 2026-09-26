const mongoose = require('mongoose');

mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const db = mongoose.connection.db;
    
    // Find "Other Charges" account
    const oc = await db.collection('chartofaccounts').findOne({ accountName: 'Other Charges' });
    if (!oc) {
      console.log('Other Charges account not found globally');
      process.exit(0);
    }
    console.log('Other Charges account ID:', oc._id);

    // Look for transactions in this year
    const start = new Date('2026-04-01T00:00:00.000Z');
    const end = new Date('2027-03-31T23:59:59.999Z');

    const txns = await db.collection('accounttransactions').find({
      accountId: oc._id,
      date: { $gte: start, $lte: end }
    }).toArray();

    console.log(`Found ${txns.length} transactions for Other Charges in 2026-2027`);
    let dr = 0; let cr = 0;
    txns.forEach(t => {
      dr += t.debit; cr += t.credit;
      console.log(`${t.date.toISOString()} | ${t.description} | Dr: ${t.debit} | Cr: ${t.credit}`);
    });
    console.log(`Total Dr: ${dr}, Total Cr: ${cr}`);

    const allInvoicesThisYear = await db.collection('invoices').find({
      invoiceDate: { $gte: start, $lte: end },
      adjustment: { $exists: true, $ne: 0, $ne: null }
    }).toArray();

    console.log(`\nFound ${allInvoicesThisYear.length} invoices with adjustment in 2026-2027`);
    allInvoicesThisYear.forEach(i => {
      console.log(`${i.invoiceDate.toISOString()} | ${i.invoiceNumber} | Adj: ${i.adjustment} | Branch: ${i.branchId}`);
    });

    process.exit(0);
  })
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
