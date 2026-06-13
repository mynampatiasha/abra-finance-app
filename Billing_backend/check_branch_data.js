const mongoose = require('mongoose');
const dotenv = require('dotenv');

// Load environment variables
dotenv.config();

// Define minimal schemas to read data
const branchSchema = new mongoose.Schema({ name: String, organization: mongoose.Schema.Types.ObjectId });
const Branch = mongoose.model('Branch', branchSchema);

const expenseSchema = new mongoose.Schema({
  expenseAccount: String,
  amount: Number,
  total: Number,
  expenseDate: Date,
  branchId: mongoose.Schema.Types.ObjectId,
  reference: String,
  notes: String
}, { collection: 'expenses' });
const Expense = mongoose.model('Expense', expenseSchema);

const billSchema = new mongoose.Schema({
  vendorName: String,
  totalAmount: Number,
  balanceDue: Number,
  billDate: Date,
  branchId: mongoose.Schema.Types.ObjectId
}, { collection: 'bills' });
const Bill = mongoose.model('Bill', billSchema);

const accountTransactionSchema = new mongoose.Schema({
  account: mongoose.Schema.Types.ObjectId,
  date: Date,
  debit: Number,
  credit: Number,
  description: String,
  referenceType: String,
  branchId: mongoose.Schema.Types.ObjectId
});
const AccountTransaction = mongoose.model('AccountTransaction', accountTransactionSchema);

const chartOfAccountSchema = new mongoose.Schema({
  accountName: String,
  accountType: String,
  branchId: mongoose.Schema.Types.ObjectId
});
const ChartOfAccount = mongoose.model('ChartOfAccount', chartOfAccountSchema);

async function run() {
  await mongoose.connect(process.env.MONGODB_URI);
  console.log('Connected to DB');

  const branchIdStr = '6a05b32faef99160d927b0d1';
  const branchId = new mongoose.Types.ObjectId(branchIdStr);

  const branch = await Branch.findById(branchId);
  console.log(`\n=== Branch Info ===`);
  console.log(`Name: ${branch ? branch.name : 'Unknown'}`);

  console.log(`\n=== Expenses ===`);
  const expenses = await Expense.find({ branchId });
  expenses.forEach(e => {
    console.log(`- Date: ${e.expenseDate?.toISOString().split('T')[0]}, Total: ${e.total || e.amount}, Account: ${e.expenseAccount}, Ref: ${e.reference}, Notes: ${e.notes}`);
  });

  console.log(`\n=== Bills ===`);
  const bills = await Bill.find({ branchId });
  bills.forEach(b => {
    console.log(`- Date: ${b.billDate?.toISOString().split('T')[0]}, Vendor: ${b.vendorName}, Total: ${b.totalAmount}`);
  });

  console.log(`\n=== Account Transactions (Cash & Bank) ===`);
  const cashAccounts = await ChartOfAccount.find({
    branchId,
    accountType: { $in: ['Cash', 'Bank', 'Other Current Asset', 'Fixed Asset', 'Other Asset', 'Current Asset', 'Stock'] }
  });
  
  let openingSum = 0;
  for (const acc of cashAccounts) {
    const txns = await AccountTransaction.find({ account: acc._id });
    if (txns.length > 0) {
      console.log(`\nAccount: ${acc.accountName} (${acc.accountType})`);
      txns.forEach(t => {
        console.log(`  - Date: ${t.date?.toISOString().split('T')[0]}, Debit (+): ${t.debit}, Credit (-): ${t.credit}, Desc: ${t.description}, Type: ${t.referenceType}`);
        openingSum += (t.debit || 0) - (t.credit || 0);
      });
    }
  }
  
  console.log(`\n=== Total Calculated Cash Balance ===`);
  console.log(`Sum of Debits - Credits across all Cash/Asset accounts: ${openingSum.toFixed(2)}`);

  mongoose.disconnect();
}

run().catch(err => {
  console.error(err);
  mongoose.disconnect();
});
