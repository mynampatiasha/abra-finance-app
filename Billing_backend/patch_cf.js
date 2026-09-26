const fs = require('fs');
let code = fs.readFileSync('routes/reports.js', 'utf8');

const regex = /const Invoice = mongoose\.models\.Invoice[\s\S]*?const closingBalance = openingBalance \+ totalIncoming - totalOutgoing;/;

const newCode = `const PaymentAccount = mongoose.models.PaymentAccount || mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const paymentAccounts = await PaymentAccount.find({ ...scope }).lean();
    const coaIds = [];
    let openingBalance = 0;

    for (const pa of paymentAccounts) {
      const coa = await ChartOfAccount.findOne({ accountName: pa.accountName, ...scope }).lean();
      if (coa) {
        coaIds.push(coa._id);
        let bal = pa.openingBalance || coa.openingBalance || 0;
        if (coa.balanceType === 'Cr') bal = -bal; 
        openingBalance += bal;
      }
    }

    const allTxns = await AccountTransaction.find({ 
      accountId: { $in: coaIds },
      ...scope 
    }).lean();

    let operatingInflows = 0;
    let operatingOutflows = 0;
    const monthlyMap = {};

    const parseDate = (d) => {
      if (!d) return null;
      if (d instanceof Date) return d;
      return new Date(d);
    };

    const txnGroups = {};
    for (const txn of allTxns) {
       const ref = txn.referenceId ? txn.referenceId.toString() : txn._id.toString();
       if (!txnGroups[ref]) txnGroups[ref] = { date: txn.date, debit: 0, credit: 0 };
       txnGroups[ref].debit += (txn.debit || 0);
       txnGroups[ref].credit += (txn.credit || 0);
    }

    for (const ref in txnGroups) {
      const group = txnGroups[ref];
      const d = parseDate(group.date);
      if (!d) continue;
      
      const netCash = group.debit - group.credit;

      if (d < start) {
        openingBalance += netCash;
      } else if (d >= start && d <= end) {
        const key = \`\${d.getFullYear()}-\${d.getMonth()}\`;
        if (!monthlyMap[key]) monthlyMap[key] = { incoming: 0, outgoing: 0 };
        
        if (netCash > 0) {
          operatingInflows += netCash;
          monthlyMap[key].incoming += netCash;
        } else if (netCash < 0) {
          operatingOutflows += Math.abs(netCash);
          monthlyMap[key].outgoing += Math.abs(netCash);
        }
      }
    }

    const totalIncoming = operatingInflows;
    const totalOutgoing = operatingOutflows;
    const closingBalance = openingBalance + totalIncoming - totalOutgoing;`;

code = code.replace(regex, newCode);
fs.writeFileSync('routes/reports.js', code);
console.log('Replaced successfully.');
