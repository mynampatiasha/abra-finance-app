const mongoose = require('mongoose');

async function run() {
  await mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority');
  const db = mongoose.connection.db;
  
  const start = new Date('2026-07-01T00:00:00.000Z');
  const end = new Date('2026-07-31T23:59:59.999Z');

  // 1. Get Invoices for July (used by dashboard Accrual)
  const invoices = await db.collection('invoices').find({
    $or: [
      { invoiceDate: { $gte: start, $lte: end } },
      { date: { $gte: start, $lte: end } },
      { createdAt: { $gte: start, $lte: end } }
    ]
  }).toArray();
  
  let dashboardIncome = 0;
  for (const inv of invoices) {
    const totalAmount = inv.subTotal || (inv.totalAmount - (inv.taxAmount || 0)) || 0;
    dashboardIncome += totalAmount;
  }
  
  console.log('--- DASHBOARD CALCULATION ---');
  console.log('Total Invoices Count:', invoices.length);
  console.log('Dashboard Calculated Income (from invoices):', dashboardIncome);

  // 2. Get Account Transactions for Sales / Income
  const coa = await db.collection('chartofaccounts').find({
    accountType: { $in: ['Income', 'Other Income'] }
  }).toArray();
  const coaIds = coa.map(c => c._id);
  const coaMap = {};
  coa.forEach(c => coaMap[c._id.toString()] = c.accountName);

  const txns = await db.collection('accounttransactions').find({
    accountId: { $in: coaIds },
    date: { $gte: start, $lte: end }
  }).toArray();
  
  console.log('\n--- P&L CALCULATION ---');
  let plIncome = 0;
  let plOtherIncome = 0;
  for (const t of txns) {
    const acc = coa.find(c => c._id.toString() === t.accountId.toString());
    const net = (t.credit || 0) - (t.debit || 0);
    if (acc.accountType === 'Income') {
      plIncome += net;
    } else {
      plOtherIncome += net;
    }
  }
  
  console.log('P&L Operating Income (Income):', plIncome);
  console.log('P&L Non-Operating Income (Other Income):', plOtherIncome);
  
  console.log('\n--- DISCREPANCY ANALYSIS ---');
  console.log('Difference (Dashboard - P&L Operating):', dashboardIncome - plIncome);
  
  // Find invoices that might have missing or different amounts in AccountTransaction
  for (const inv of invoices) {
    const invAmount = inv.subTotal || (inv.totalAmount - (inv.taxAmount || 0)) || 0;
    // Find corresponding transactions for this invoice
    const invTxns = await db.collection('accounttransactions').find({
      $or: [
        { referenceId: inv._id },
        { referenceNumber: inv.invoiceNumber }
      ],
      accountId: { $in: coaIds }
    }).toArray();
    
    let txnNet = 0;
    invTxns.forEach(t => txnNet += (t.credit || 0) - (t.debit || 0));
    
    if (Math.abs(invAmount - txnNet) > 0.01) {
      console.log(`Mismatch on Invoice ${inv.invoiceNumber} (${inv._id}):`);
      console.log(`  Invoice Amount (subTotal/calculated): ${invAmount}`);
      console.log(`  Posted to Income Accounts: ${txnNet}`);
      console.log(`  Difference: ${invAmount - txnNet}`);
    }
  }
  
  await mongoose.disconnect();
}

run().catch(console.error);
