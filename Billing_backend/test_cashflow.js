const mongoose = require('mongoose');

mongoose.connect('mongodb+srv://mynampatiasha:Asha%40123@cluster0.p7x4m.mongodb.net/Abra_Finance?retryWrites=true&w=majority&appName=Cluster0')
.then(async () => {
  try {
    const db = mongoose.connection.db;
    const branchId = '6a05b32faef99160d927b0d1';
    
    console.log('--- DB TRANSACTIONS CHECK ---');
    
    // 1. Get all Chart of Accounts of type Bank or Cash
    const coas = await db.collection('chartofaccounts').find({ accountType: { $in: ['Bank', 'Cash'] } }).toArray();
    console.log('Found ' + coas.length + ' Bank/Cash COAs.');
    
    // 2. Aggregate AccountTransactions for each Bank/Cash COA for the given branch
    let grandTotal = 0;
    
    for (const coa of coas) {
      const agg = await db.collection('accounttransactions').aggregate([
        { $match: { accountId: coa._id, branchId: new mongoose.Types.ObjectId(branchId) } },
        { $group: { _id: null, totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } }
      ]).toArray();
      
      const balance = agg.length > 0 ? agg[0].totalDebit - agg[0].totalCredit : 0;
      
      if (balance !== 0 || agg.length > 0) {
        console.log(`COA: ${coa.accountName} (Type: ${coa.accountType}) -> Balance: ₹${balance}`);
        grandTotal += balance;
      }
    }
    
    console.log('-----------------------------');
    console.log(`TOTAL CASH FLOW BALANCE FOR BRANCH: ₹${grandTotal}`);
    console.log('-----------------------------');
    
    process.exit(0);
  } catch(e) { console.error(e); process.exit(1); }
});
