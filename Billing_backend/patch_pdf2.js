const fs = require('fs');
let content = fs.readFileSync('routes/budgets.js', 'utf8');

// Replace table header in PDF
content = content.replace(/doc\.text\('ACCOUNT', 50, startY \+ 6\);[\s\S]*?doc\.text\('% USED', 520, startY \+ 6, \{ width: 40, align: 'right' \}\);/g, 
`doc.text('ACCOUNT', 50, startY + 6);
    doc.text('TYPE', 300, startY + 6);
    doc.text('BUDGETED', pageW - 320, startY + 6, { width: 90, align: 'right' });
    doc.text('ACTUAL', pageW - 220, startY + 6, { width: 90, align: 'right' });
    doc.text('VARIANCE', pageW - 120, startY + 6, { width: 90, align: 'right' });
    doc.text('% USED', pageW - 40, startY + 6, { width: 40, align: 'right' });`);

// Replace table rows in PDF
content = content.replace(/doc\.text\(line\.accountName, 50, startY \+ 6, \{ width: 140, height: 12, ellipsis: true \}\);[\s\S]*?doc\.text\(\`\\\$\{line\.percentUsed\.toFixed\(1\)\\}%\`, 520, startY \+ 6, \{ width: 40, align: 'right' \}\);/g,
`doc.text(line.accountName, 50, startY + 6, { width: 230, height: 12, ellipsis: true });
      doc.text(line.accountType, 300, startY + 6);
      doc.text(\`Rs.\${formatCurr(line.totalBudgeted)}\`, pageW - 320, startY + 6, { width: 90, align: 'right' });
      doc.text(\`Rs.\${formatCurr(line.totalActual)}\`, pageW - 220, startY + 6, { width: 90, align: 'right' });
      doc.text(\`Rs.\${formatCurr(line.variance)}\`, pageW - 120, startY + 6, { width: 90, align: 'right' });
      doc.text(\`\${line.percentUsed.toFixed(1)}%\`, pageW - 40, startY + 6, { width: 40, align: 'right' });`);

// Replace totals row in PDF
content = content.replace(/doc\.text\('TOTAL', 50, startY \+ 6\);[\s\S]*?doc\.text\(\`Rs\.\\\$\{formatCurr\(budget\.variance\)\}\`, 440, startY \+ 6, \{ width: 70, align: 'right', color: budget\.variance < 0 \? '#E74C3C' : '#000' \}\);/,
`doc.text('TOTAL', 50, startY + 6);
    doc.text(\`Rs.\${formatCurr(budget.totalBudgeted)}\`, pageW - 320, startY + 6, { width: 90, align: 'right' });
    doc.text(\`Rs.\${formatCurr(budget.totalActual)}\`, pageW - 220, startY + 6, { width: 90, align: 'right', color: '#27AE60' });
    doc.text(\`Rs.\${formatCurr(budget.variance)}\`, pageW - 120, startY + 6, { width: 90, align: 'right', color: budget.variance < 0 ? '#E74C3C' : '#000' });`);

fs.writeFileSync('routes/budgets.js', content);
console.log('Fixed Page 1 scaling');
