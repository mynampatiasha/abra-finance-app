const mongoose = require('mongoose');
mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const scope = { orgId: '69bd251dd852a7f1531cb66d' };
    const start = new Date('2026-04-01T00:00:00.000Z');
    const end = new Date('2027-03-31T23:59:59.999Z');

    const PaymentAccount = mongoose.connection.db.collection('paymentaccounts');
    const ChartOfAccount = mongoose.connection.db.collection('chartofaccounts');
    const AccountTransaction = mongoose.connection.db.collection('accounttransactions');

    const paymentAccounts = await PaymentAccount.find({ ...scope }).toArray();
    const coaIds = [];
    let openingBalance = 0;
    
    for (const pa of paymentAccounts) {
      const coa = await ChartOfAccount.findOne({ accountName: pa.accountName, ...scope });
      if (coa) {
        coaIds.push(coa._id);
        let bal = pa.openingBalance || coa.openingBalance || 0;
        if (coa.balanceType === 'Cr') bal = -bal; 
        console.log(`PA ${pa.accountName}: bal=${bal}, balanceType=${coa.balanceType}`);
        openingBalance += bal;
      }
    }

    const allTxns = await AccountTransaction.find({ 
      accountId: { $in: coaIds },
      ...scope 
    }).toArray();
    
    console.log(`Found ${allTxns.length} txns for these COAs.`);

    let operatingInflows = 0;
    let operatingOutflows = 0;

    const txnGroups = {};
    for (const txn of allTxns) {
       const ref = txn.referenceId ? txn.referenceId.toString() : txn._id.toString();
       if (!txnGroups[ref]) txnGroups[ref] = { date: txn.date, debit: 0, credit: 0 };
       txnGroups[ref].debit += (txn.debit || 0);
       txnGroups[ref].credit += (txn.credit || 0);
    }
    
    let beforeStart = 0;
    for (const ref in txnGroups) {
      const group = txnGroups[ref];
      const d = group.date;
      if (!d) continue;
      
      const netCash = group.debit - group.credit;

      if (d < start) {
        beforeStart += netCash;
        openingBalance += netCash;
      } else if (d >= start && d <= end) {
        if (netCash > 0) {
          operatingInflows += netCash;
        } else if (netCash < 0) {
          operatingOutflows += Math.abs(netCash);
        }
      }
    }
    
    console.log({ nativeOpening: openingBalance - beforeStart, beforeStart, finalOpeningBalance: openingBalance, operatingInflows, operatingOutflows });
    process.exit(0);
  });
