const fs = require('fs');
const jsFile = 'd:/Fleet_Management/Fleet_Management/Abra_finance_system/Billing_backend/routes/billing-customers.js';
let js = fs.readFileSync(jsFile, 'utf8');

const regex = /\/\/ Monthly income - last 6 months[\s\S]*?const now = new Date\(\);\s*for \(let i = 5; i >= 0; i--\) \{/;

const replacement = `// Monthly income - dynamic months
      const months = parseInt(req.query.months) || 6;
      const monthsAgo = new Date();
      monthsAgo.setMonth(monthsAgo.getMonth() - (months - 1));
      monthsAgo.setDate(1);
      monthsAgo.setHours(0, 0, 0, 0);

      const incomeAgg = await Invoice.aggregate([
        {
          $match: {
            customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
            invoiceDate: { $gte: monthsAgo },
            status: { $nin: ['CANCELLED', 'VOID'] },
            ...req.orgFilter,
          },
        },
        {
          $group: {
            _id: { year: { $year: '$invoiceDate' }, month: { $month: '$invoiceDate' } },
            total: { $sum: '$totalAmount' },
            count: { $sum: 1 },
          },
        },
        { $sort: { '_id.year': 1, '_id.month': 1 } },
      ]);

      // Build month slots dynamically
      const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const now = new Date();
      for (let i = months - 1; i >= 0; i--) {`;

js = js.replace(regex, replacement);
fs.writeFileSync(jsFile, js);
console.log('Fixed backend 500 error!');
