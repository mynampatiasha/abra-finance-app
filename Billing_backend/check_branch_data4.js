const mongoose = require('mongoose');
require('dotenv').config();

const coaSchema = new mongoose.Schema({
  accountName: String,
  accountType: String,
  branchId: mongoose.Schema.Types.ObjectId
}, { collection: 'chartofaccounts' });
const COA = mongoose.model('COA', coaSchema);

const txnSchema = new mongoose.Schema({
  account: mongoose.Schema.Types.ObjectId,
  date: Date,
  debit: Number,
  credit: Number,
  description: String
}, { collection: 'accounttransactions' });
const Txn = mongoose.model('Txn', txnSchema);

async function run() {
  await mongoose.connect(process.env.MONGODB_URI);
  const branchIdStr = '6a05b32faef99160d927b0d1';
  
  const accs = await COA.find({
    branchId: branchIdStr,
    accountType: { $in: ['Cash', 'Bank', 'Other Current Asset', 'Fixed Asset', 'Other Asset', 'Current Asset', 'Stock'] }
  });
  
  let total = 0;
  console.log(`=== Cash/Bank Accounts for Branch ===`);
  for (const a of accs) {
    const txns = await Txn.find({ account: a._id });
    if (txns.length > 0) {
      console.log(`\n[Account: ${a.accountName} (${a.accountType})]`);
      txns.forEach(t => {
        console.log(`  - Date: ${t.date ? t.date.toISOString().split('T')[0] : 'N/A'}, Debit (+): ${t.debit}, Credit (-): ${t.credit}, Desc: ${t.description}`);
        total += (t.debit || 0) - (t.credit || 0);
      });
    }
  }
  
  console.log(`\nTOTAL CASH BALANCE: ${total.toFixed(2)}`);

  console.log(`\n=== Expenses ===`);
  const Expense = mongoose.model('Exp', new mongoose.Schema({
    expenseDate: Date,
    expenseAccount: String,
    total: Number,
    reference: String,
    branchId: mongoose.Schema.Types.ObjectId
  }, { collection: 'expenses' }));

  const expenses = await Expense.find({ branchId: branchIdStr });
  expenses.forEach(e => {
    if (e.total === 17385 || e.total === 17.4) {
      console.log(`- Date: ${e.expenseDate ? e.expenseDate.toISOString().split('T')[0] : 'N/A'}, Account: ${e.expenseAccount}, Total: ${e.total}, Ref: ${e.reference}`);
    }
  });

  mongoose.disconnect();
}
run();
