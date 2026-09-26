const mongoose = require('mongoose');

mongoose.connect('mongodb://fleetadmin:fleetadmin@ac-vutbslh-shard-00-00.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-01.cnb4jvy.mongodb.net:27017,ac-vutbslh-shard-00-02.cnb4jvy.mongodb.net:27017/abra_finance_module?ssl=true&replicaSet=atlas-h68c5g-shard-0&authSource=admin&retryWrites=true&w=majority')
  .then(async () => {
    const orgId = '6a05b2c6aef99160d927b0bf';
    const branchId = '6a05b32faef99160d927b0d1';
    
    // Exact scope from orgScope(req)
    const scope = { orgId };
    if (branchId && branchId !== 'all') {
      scope.branchId = branchId;
    }

    const start = new Date('2026-04-01T00:00:00.000Z');
    const end = new Date('2027-03-31T23:59:59.999Z');

    const PaymentAccount = mongoose.connection.db.collection('paymentaccounts');
    const ChartOfAccount = mongoose.connection.db.collection('chartofaccounts');
    const AccountTransaction = mongoose.connection.db.collection('accounttransactions');

    // From reports.js (ORIGINAL CODE that we reverted to)
    const paymentAccounts = await PaymentAccount.find({ ...scope }).toArray();
    console.log(`Found ${paymentAccounts.length} payment accounts for scope`);
    
    const coaIds = [];
    for (const pa of paymentAccounts) {
      const coa = await ChartOfAccount.findOne({ accountName: pa.accountName, ...scope });
      if (coa) {
        coaIds.push(coa._id);
      }
    }
    
    console.log(`Found ${coaIds.length} Chart of Accounts linked to PaymentAccounts`);

    // Let's also find ANY Bank accounts not in PaymentAccount
    const allBankCoas = await ChartOfAccount.find({ accountType: { $in: ['Bank', 'Cash', 'Credit Card'] }, ...scope }).toArray();
    console.log(`Total Bank/Cash COAs in database for this scope: ${allBankCoas.length}`);
    for(const b of allBankCoas) {
      const inCoaIds = coaIds.some(id => id.toString() === b._id.toString());
      if(!inCoaIds) {
        console.log(`  WARNING: Missing bank COA in coaIds: ${b.accountName} (balance: ${b.openingBalance})`);
      }
    }

    const allTxns = await AccountTransaction.find({ 
      accountId: { $in: coaIds },
      ...scope 
    }).toArray();
    
    console.log(`Fetched ${allTxns.length} transactions for these accounts`);

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

    console.log('--- ORIGINAL LOGIC RESULTS ---');
    console.log({ openingBalance, operatingInflows, operatingOutflows });
    
    // Now let's test the PROPER logic (Contra + Native Opening Balance)
    let properOpeningBalance = 0;
    for (const pa of paymentAccounts) {
      const coa = await ChartOfAccount.findOne({ accountName: pa.accountName, ...scope });
      if (coa) {
        let bal = pa.openingBalance || coa.openingBalance || 0;
        if (coa.balanceType === 'Cr') bal = -bal; 
        properOpeningBalance += bal;
      }
    }
    
    let properInflows = 0;
    let properOutflows = 0;
    const txnGroups = {};
    for (const txn of allTxns) {
       const ref = txn.referenceId ? txn.referenceId.toString() : txn._id.toString();
       if (!txnGroups[ref]) txnGroups[ref] = { date: txn.date, debit: 0, credit: 0 };
       txnGroups[ref].debit += (txn.debit || 0);
       txnGroups[ref].credit += (txn.credit || 0);
    }
    
    for (const ref in txnGroups) {
      const group = txnGroups[ref];
      const d = group.date;
      if (!d) continue;
      const netCash = group.debit - group.credit;

      if (d < start) {
        properOpeningBalance += netCash;
      } else if (d >= start && d <= end) {
        if (netCash > 0) {
          properInflows += netCash;
        } else if (netCash < 0) {
          properOutflows += Math.abs(netCash);
        }
      }
    }

    console.log('--- PROPER LOGIC RESULTS ---');
    console.log({ properOpeningBalance, properInflows, properOutflows });

    process.exit(0);
  });
