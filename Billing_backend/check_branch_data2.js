const mongoose = require('mongoose');
require('dotenv').config();

async function run() {
  await mongoose.connect(process.env.MONGODB_URI);
  const branchId = '6a05b32faef99160d927b0d1';
  
  const accs = await mongoose.connection.db.collection('chartofaccounts').find({
    branchId,
    accountType: { $in: ['Cash', 'Bank', 'Other Current Asset', 'Fixed Asset', 'Other Asset', 'Current Asset', 'Stock'] }
  }).toArray();
  
  let total = 0;
  console.log(`=== Cash/Bank Accounts for Branch ===`);
  for (const a of accs) {
    const txns = await mongoose.connection.db.collection('accounttransactions').find({ account: a._id }).toArray();
    if (txns.length > 0) {
      console.log(`\n[Account: ${a.accountName} (${a.accountType})]`);
      txns.forEach(t => {
        console.log(`  - Date: ${t.date.toISOString().split('T')[0]}, Debit (+): ${t.debit}, Credit (-): ${t.credit}, Desc: ${t.description}`);
        total += (t.debit || 0) - (t.credit || 0);
      });
    }
  }
  
  console.log(`\nTOTAL CASH BALANCE: ${total.toFixed(2)}`);

  console.log(`\n=== Expenses ===`);
  const expenses = await mongoose.connection.db.collection('expenses').find({ branchId }).toArray();
  let expTotal = 0;
  expenses.forEach(e => {
    console.log(`- Date: ${e.expenseDate ? e.expenseDate.toISOString().split('T')[0] : 'N/A'}, Account: ${e.expenseAccount}, Total: ${e.total}, Ref: ${e.reference}`);
    expTotal += e.total || 0;
  });
  console.log(`TOTAL EXPENSES: ${expTotal}`);

  mongoose.disconnect();
}
run();
