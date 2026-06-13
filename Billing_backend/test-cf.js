require('dotenv').config();
const mongoose = require('mongoose');

async function test() {
  await mongoose.connect(process.env.MONGODB_URI);
  const { ChartOfAccount, AccountTransaction } = require('./routes/chart_of_accounts');
  const branchId = '6a05b32faef99160d927b0d1';
  const orgId = '6a05b2c6aef99160d927b0bf';
  
  const CASH_BANK_TYPES = ['Cash', 'Other Current Asset', 'Fixed Asset', 'Other Asset'];
  const cashAccounts = await ChartOfAccount.find({
    accountType: { $in: CASH_BANK_TYPES },
    isActive: true,
    isSystemAccount: { $ne: true },
    orgId: orgId,
    branchId: branchId
  }).lean();
  
  console.log("Found cash accounts:", cashAccounts.length, cashAccounts.map(a => a.accountName));
  
  const cashAccountIds = cashAccounts.map(a => a._id);
  
  const openingAgg = await AccountTransaction.aggregate([
    {
      $match: {
        accountId: { $in: cashAccountIds },
        date: { $lt: new Date() },
        orgId: orgId,
        branchId: branchId
      },
    },
    { $group: { _id: null, totalDebit: { $sum: "$debit" }, totalCredit: { $sum: "$credit" } } },
  ]);
  
  console.log("Opening agg:", openingAgg);
  
  process.exit(0);
}

test();
