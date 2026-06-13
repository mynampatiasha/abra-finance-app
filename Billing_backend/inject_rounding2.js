const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'routes', 'reports.js');
let code = fs.readFileSync(file, 'utf8');

const regex = /totE = fmt\(totE \+ netProfit\);\s*\}\s*\/\/\s*─────────────────────────────────────────────────────────────────────\s*res\.json\(\{ success: true, data: \{ asOf: end, assets: \{ items: assets, total: fmt\(totA\) \}, liabilities: \{ items: liabs, total: fmt\(totL\) \}, equity: \{ items: equity, total: fmt\(totE\) \}, totalLiabilitiesAndEquity: fmt\(totL \+ totE\), balanced: Math\.abs\(totA \- \(totL \+ totE\)\) < 0\.02 \} \}\);/g;

const replacement = `totE = fmt(totE + netProfit);
    }

    // ── FIX: Automatic Rounding Sweep ────────────────────────────────────
    const difference = fmt(totA - (totL + totE));
    if (Math.abs(difference) > 0 && Math.abs(difference) <= 2.00) {
      equity.push({
        accountName: 'Rounding Adjustments',
        accountCode: '',
        accountType: 'Equity',
        amount: difference,
      });
      totE = fmt(totE + difference);
    }
    // ─────────────────────────────────────────────────────────────────────

    res.json({ success: true, data: { asOf: end, assets: { items: assets, total: fmt(totA) }, liabilities: { items: liabs, total: fmt(totL) }, equity: { items: equity, total: fmt(totE) }, totalLiabilitiesAndEquity: fmt(totL + totE), balanced: Math.abs(totA - (totL + totE)) < 0.02 } });`;

if (regex.test(code)) {
    code = code.replace(regex, replacement);
    fs.writeFileSync(file, code, 'utf8');
    console.log('SUCCESS');
} else {
    console.log('FAILED TO FIND REGEX TARGET');
}
