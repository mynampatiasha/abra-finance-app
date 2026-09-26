const mongoose = require('mongoose');
mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const orgId = '6a05b2c6aef99160d927b0bf';
    const branchId = '6a05b32faef99160d927b0d1';
    const scope = { orgId, branchId: { $in: [branchId] } };

    const start = new Date('2026-03-31T18:30:00.000Z'); // Exact start from API
    const end = new Date('2027-03-31T18:29:59.000Z');

    const PaymentAccount = mongoose.connection.db.collection('paymentaccounts');
    const ChartOfAccount = mongoose.connection.db.collection('chartofaccounts');
    const AccountTransaction = mongoose.connection.db.collection('accounttransactions');

    const paymentAccounts = await PaymentAccount.find({ ...scope }).toArray();
    const coaIds = [];
    for (const pa of paymentAccounts) {
      const coa = await ChartOfAccount.findOne({ accountName: pa.accountName, ...scope });
      if (coa) coaIds.push(coa._id);
    }

    const allTxns = await AccountTransaction.find({ accountId: { $in: coaIds }, ...scope }).toArray();

    let openingBalance = 0;
    let operatingInflows = 0;
    let operatingOutflows = 0;

    for (const txn of allTxns) {
      const d = txn.date;
      if (!d) continue;
      const debit = txn.debit || 0;
      const credit = txn.credit || 0;

      if (d < start) {
        openingBalance += (debit - credit);
      } else if (d >= start && d <= end) {
        operatingInflows += debit;
        operatingOutflows += credit;
      }
    }
    console.log({ openingBalance, operatingInflows, operatingOutflows });
    process.exit(0);
  });
