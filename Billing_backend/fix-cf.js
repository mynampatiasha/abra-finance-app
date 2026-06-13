const fs = require('fs');

let content = fs.readFileSync('routes/reports.js', 'utf8');

const newCashFlowLogic = `
    // Calculate opening and closing balance from cash accounts
    const CASH_BANK_TYPES = ['Cash', 'Other Current Asset', 'Fixed Asset', 'Other Asset'];
    const cashAccounts = await ChartOfAccount.find({
      accountType: { $in: CASH_BANK_TYPES },
      isActive: true,
      isSystemAccount: { $ne: true },
      ...scope,
    }).lean();

    const cashAccountIds = cashAccounts.map(a => a._id);
    
    let openingBalance = 0;
    if (cashAccountIds.length > 0) {
      const openingAgg = await AccountTransaction.aggregate([
        {
          $match: {
            accountId: { $in: cashAccountIds },
            date: { $lt: start },
            ...scope,
          },
        },
        { $group: { _id: null, totalDebit: { $sum: '$debit' }, totalCredit: { $sum: '$credit' } } },
      ]);
      openingBalance = (openingAgg[0]?.totalDebit || 0) - (openingAgg[0]?.totalCredit || 0);
    }

    // Get all AccountTransactions for the cash accounts within the current period
    let operatingInflows = 0, operatingOutflows = 0;
    const monthlyMap = {};

    if (cashAccountIds.length > 0) {
      const periodTxns = await AccountTransaction.find({
        accountId: { $in: cashAccountIds },
        date: { $gte: start, $lte: end },
        ...scope,
      }).lean();

      for (const txn of periodTxns) {
        // Debit to a cash account means money came IN
        if (txn.debit > 0) {
          operatingInflows += txn.debit;
        }
        // Credit to a cash account means money went OUT
        if (txn.credit > 0) {
          operatingOutflows += txn.credit;
        }

        const d = new Date(txn.date);
        const y = d.getFullYear();
        const m = d.getMonth();
        const key = \`\${y}-\${m}\`;
        
        if (!monthlyMap[key]) monthlyMap[key] = { incoming: 0, outgoing: 0 };
        monthlyMap[key].incoming += (txn.debit || 0);
        monthlyMap[key].outgoing += (txn.credit || 0);
      }
    }

    const totalIncoming = operatingInflows;
    const totalOutgoing = operatingOutflows;
    const closingBalance = openingBalance + totalIncoming - totalOutgoing;

    // Build monthly breakdown
    const monthlyBreakdown = [];
    const abbr = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    
    let runningBalance = openingBalance;
    
    // FY months from April to March
    const fyMonths = [3,4,5,6,7,8,9,10,11,0,1,2];
    const currentFYYear = start.getFullYear();
    
    for (const mIndex of fyMonths) {
      const isNextYear = mIndex < 3;
      const year = currentFYYear + (isNextYear ? 1 : 0);
      const key = \`\${year}-\${mIndex}\`;
      
      const incoming = monthlyMap[key]?.incoming || 0;
      const outgoing = monthlyMap[key]?.outgoing || 0;
      runningBalance += (incoming - outgoing);
      
      monthlyBreakdown.push({
        month: abbr[mIndex],
        incoming: fmt(incoming),
        outgoing: fmt(outgoing),
        endingBalance: fmt(runningBalance)
      });
    }

    res.json({
      success: true,
      data: {
        period: { start, end },
        operating: {
          inflows:  fmt(operatingInflows),
          outflows: fmt(operatingOutflows),
          net:      fmt(operatingInflows - operatingOutflows),
          items:    [],
        },
        investing: {
          inflows:  "0.00",
          outflows: "0.00",
          net:      "0.00",
        },
        financing: {
          inflows:  "0.00",
          outflows: "0.00",
          net:      "0.00",
        },
        netCashChange: fmt(totalIncoming - totalOutgoing),
        monthlyBreakdown,
        summary: {
          openingBalance: fmt(openingBalance),
          totalIncoming: fmt(totalIncoming),
          totalOutgoing: fmt(totalOutgoing),
          closingBalance: fmt(closingBalance),
        },
      },
    });
  } catch (e) { 
    console.error('❌ cash-flow error:', e.message);
    res.status(500).json({ success: false, message: e.message }); 
  }
});
`;

content = content.replace(/\/\/ ✅ FIX: Use ProviderTransaction[\s\S]*?res\.status\(500\)\.json\(\{ success: false, message: e\.message \};\s*\}\s*\n\}\);/g, newCashFlowLogic);

fs.writeFileSync('routes/reports.js', content);
console.log('Processed reports.js');
