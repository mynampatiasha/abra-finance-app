const mongoose = require('mongoose');

mongoose.connect('mongodb://localhost:27017/abra_finance_system').then(async () => {
  const ChartOfAccount = mongoose.connection.collection('chartofaccounts');
  const AccountTransaction = mongoose.connection.collection('accounttransactions');

  const start = new Date(2026, 3, 1); // April 1, 2026
  const end = new Date(2027, 2, 31, 23, 59, 59); // March 31, 2027
  
  const scope = {};

  const CASH_BANK_TYPES = ['Cash', 'Other Current Asset', 'Fixed Asset', 'Other Asset'];
  const cashAccounts = await ChartOfAccount.find({
    accountType: { $in: CASH_BANK_TYPES },
    isActive: true,
    isSystemAccount: { $ne: true },
    ...scope,
  }).toArray();

  const cashAccountIds = cashAccounts.map(a => a._id);

  console.log("Found Cash Accounts:", cashAccountIds.length);
  
  const periodTxns = await AccountTransaction.find({
    accountId: { $in: cashAccountIds },
    date: { $gte: start, $lte: end },
    ...scope,
  }).toArray();

  console.log("Found Period Txns:", periodTxns.length);

  const monthlyMap = {};
  for (const txn of periodTxns) {
    const d = new Date(txn.date);
    const y = d.getFullYear();
    const m = d.getMonth();
    const key = `${y}-${m}`;
    
    if (!monthlyMap[key]) monthlyMap[key] = { incoming: 0, outgoing: 0 };
    monthlyMap[key].incoming += (txn.debit || 0);
    monthlyMap[key].outgoing += (txn.credit || 0);
  }

  console.log("Monthly Map Generated:", JSON.stringify(monthlyMap, null, 2));

  const abbr = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const fyMonths = [3,4,5,6,7,8,9,10,11,0,1,2];
  const currentFYYear = start.getFullYear();

  for (const mIndex of fyMonths) {
    const isNextYear = mIndex < 3;
    const year = currentFYYear + (isNextYear ? 1 : 0);
    const key = `${year}-${mIndex}`;
    
    console.log(`Checking key: ${key} (${abbr[mIndex]}) -> Incoming: ${monthlyMap[key]?.incoming}, Outgoing: ${monthlyMap[key]?.outgoing}`);
  }

  process.exit(0);
});
