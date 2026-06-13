const mongoose = require('mongoose');
require('dotenv').config();

const INCOME_TYPES    = ['Income', 'Other Income'];
const EXPENSE_TYPES   = ['Expense', 'Cost Of Goods Sold', 'Other Expense'];
const ASSET_TYPES     = ['Asset','Accounts Receivable','Other Current Asset','Fixed Asset','Cash','Stock','Other Asset'];
const LIABILITY_TYPES = ['Liability','Accounts Payable','Other Current Liability','Non Current Liability','Other Liability'];
const EQUITY_TYPES    = ['Equity'];

const fmt = (n) => Math.round((n || 0) * 100) / 100;

async function run() {
  await mongoose.connect(process.env.MONGODB_URI);
  console.log('Connected to DB');

  const ChartOfAccount = mongoose.connection.db.collection('chartofaccounts');
  const AccountTransaction = mongoose.connection.db.collection('accounttransactions');

  const branchId = '6a05b32faef99160d927b0d1';
  const scope = { branchId: { $in: [branchId] } };

  // 1. Get Accounts
  const accounts = await ChartOfAccount.find({ 
    accountType: { $in: [...ASSET_TYPES, ...LIABILITY_TYPES, ...EQUITY_TYPES] }, 
    isActive: true, 
    ...scope 
  }).toArray();
  
  const ids = accounts.map(a => a._id);
  
  // 2. Get Transactions
  const txns = await AccountTransaction.aggregate([
    { $match: { accountId: { $in: ids }, ...scope } },
    { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
  ]).toArray();
  
  const tMap = {}; txns.forEach(t => { tMap[t._id.toString()] = t; });
  let totA = 0, totL = 0, totE = 0;
  
  for (const acc of accounts) {
    const t = tMap[acc._id.toString()] || { dr: 0, cr: 0 };
    const net = ASSET_TYPES.includes(acc.accountType) ? fmt(t.dr - t.cr) : fmt(t.cr - t.dr);
    if (ASSET_TYPES.includes(acc.accountType))           { totA += net; }
    else if (LIABILITY_TYPES.includes(acc.accountType))  { totL += net; }
    else                                                  { totE += net; }
  }

  // 3. Calculate Net Profit
  const plAccounts = await ChartOfAccount.find({ 
    accountType: { $in: [...INCOME_TYPES, ...EXPENSE_TYPES] }, 
    isActive: true, 
    ...scope 
  }).toArray();
  
  const plIds = plAccounts.map(a => a._id);
  const plTxns = await AccountTransaction.aggregate([
    { $match: { accountId: { $in: plIds }, ...scope } },
    { $group: { _id: '$accountId', dr: { $sum: '$debit' }, cr: { $sum: '$credit' } } },
  ]).toArray();
  
  const plMap = {}; plTxns.forEach(t => { plMap[t._id.toString()] = t; });
  let netProfit = 0;
  for (const acc of plAccounts) {
    const t = plMap[acc._id.toString()] || { dr: 0, cr: 0 };
    if (INCOME_TYPES.includes(acc.accountType))  netProfit += t.cr - t.dr;
    else                                          netProfit -= t.dr - t.cr;
  }
  netProfit = fmt(netProfit);
  totE = fmt(totE + netProfit);

  const balanced = Math.abs(totA - (totL + totE)) < 0.02;

  console.log('--- BALANCE SHEET RESULTS ---');
  console.log(`Assets (totA): ${totA.toFixed(2)}`);
  console.log(`Liabilities (totL): ${totL.toFixed(2)}`);
  console.log(`Equity (totE) + Net Profit: ${totE.toFixed(2)}`);
  console.log(`Net Profit: ${netProfit.toFixed(2)}`);
  console.log(`Total Liabilities + Equity: ${(totL + totE).toFixed(2)}`);
  console.log(`Balanced? ${balanced ? 'YES' : 'NO (Difference: ' + Math.abs(totA - (totL + totE)).toFixed(2) + ')'}`);

  mongoose.disconnect();
}
run();
