const fs = require('fs');
let code = fs.readFileSync('routes/reports.js', 'utf8');

const regex = /\/\/ 1\. Find all Bank\/Cash\/Credit Card COA IDs[\s\S]*?\/\/ Build monthly breakdown/;

const originalCode = `// 1. Find all Bank/Cash/Credit Card COA IDs
    const paymentAccounts = await PaymentAccount.find({ ...scope }).lean();
    const coaIds = [];
    for (const pa of paymentAccounts) {
      const coa = await ChartOfAccount.findOne({ accountName: pa.accountName, ...scope }).lean();
      if (coa) {
        coaIds.push(coa._id);
      }
    }

    // 2. Fetch all transactions for these accounts
    const allTxns = await AccountTransaction.find({ 
      accountId: { $in: coaIds },
      ...scope 
    }).lean();

    let openingBalance = 0;
    let operatingInflows = 0;
    let operatingOutflows = 0;
    const monthlyMap = {};

    const parseDate = (d) => {
      if (!d) return null;
      if (d instanceof Date) return d;
      return new Date(d);
    };

    // 3. Process Transactions
    for (const txn of allTxns) {
      const d = parseDate(txn.date);
      if (!d) continue;
      
      const debit = txn.debit || 0;
      const credit = txn.credit || 0;

      if (d < start) {
        // True cash position is always Debit - Credit
        openingBalance += (debit - credit);
      } else if (d >= start && d <= end) {
        operatingInflows += debit;
        operatingOutflows += credit;
        
        const key = \`\${d.getFullYear()}-\${d.getMonth()}\`;
        if (!monthlyMap[key]) monthlyMap[key] = { incoming: 0, outgoing: 0 };
        monthlyMap[key].incoming += debit;
        monthlyMap[key].outgoing += credit;
      }
    }

    // Build monthly breakdown`;

code = code.replace(regex, originalCode);
fs.writeFileSync('routes/reports.js', code);
console.log('Reverted reports.js to original state.');
