const fs = require('fs');

const appendCode = `
// ============================================================================
// PDF & EXCEL EXPORT ROUTES
// ============================================================================
const fsCore = require('fs');
const path = require('path');
const PDFDocument = require('pdfkit');
const xlsx = require('xlsx');
const { getEffectiveOrgData } = require('./branches');

// Helper to format currency
const formatCurr = (num) => {
  if (num === null || num === undefined) return '0.00';
  return parseFloat(num).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
};

// -- PDF Export -------------------------------------------------------------
router.get('/:id/export-pdf', authenticate, async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    let budget = await Budget.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!budget) return res.status(404).json({ success: false, error: 'Budget not found' });
    
    // Enrich with actuals matching the UI
    budget = await enrichWithActuals(budget, req.user?.orgId, startDate, endDate);
    
    // Get organization data for header
    const orgData = await getEffectiveOrgData(budget.orgId, budget.branchId, mongoose.connection.db);
    
    // Build PDF
    const doc = new PDFDocument({ size: 'A4', margin: 40 });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', \`attachment; filename="Budget-\${budget.budgetName}.pdf"\`);
    doc.pipe(res);
    
    const pageW = doc.page.width;
    
    // Draw Header (similar to invoices.js)
    if (orgData.logoBase64) {
      try {
        const logoBuffer = Buffer.from(orgData.logoBase64, 'base64');
        doc.image(logoBuffer, 40, 40, { width: 80, height: 80, fit: [80, 80], align: 'center' });
      } catch (e) { }
    }
    
    const orgName = orgData.registeredName || orgData.name || 'ABRA FINANCE';
    const textX = 130;
    let subtitleY = 40;
    
    doc.fontSize(12).fillColor('#000000').font('Helvetica-Bold').text(orgName, textX, subtitleY, { width: 240 });
    subtitleY += 15;
    
    doc.fontSize(8).fillColor('#666666').font('Helvetica');
    const contactLines = [
      'BILLING & FINANCE',
      orgData.address?.street,
      (orgData.address?.city || '') + (orgData.address?.city && orgData.address?.state ? ', ' : '') + (orgData.address?.state || '') + (orgData.address?.pincode ? '-' + orgData.address?.pincode : ''),
      orgData.address?.country,
      orgData.website ? orgData.website : null,
      orgData.gstin ? 'GSTIN: ' + orgData.gstin : null,
      orgData.phone,
      orgData.email
    ].filter(Boolean);
    
    let contactY = subtitleY + 5;
    contactLines.forEach(line => {
      doc.text(line, textX, contactY, { width: 240 });
      contactY += 11;
    });
    
    // Title
    doc.fontSize(8).fillColor('#444444').font('Helvetica-Bold')
       .text('BUDGET VS ACTUALS', 380, 40, { width: 170, align: 'right', characterSpacing: 1 });
    doc.fontSize(16).fillColor('#000000').font('Helvetica-Bold')
       .text(budget.financialYear, 380, 52, { width: 170, align: 'right' });
    doc.fontSize(8).fillColor('#000000').font('Helvetica')
       .text(budget.budgetName, 380, 76, { width: 170, align: 'right' });
    if (startDate && endDate) {
      doc.text(\`Period: \${startDate} to \${endDate}\`, 380, 90, { width: 170, align: 'right' });
    }
       
    doc.moveDown(4);
    let startY = Math.max(contactY, 120) + 20;
    
    // Draw Summary Grid
    const colW = (pageW - 80) / 4;
    doc.rect(40, startY, pageW - 80, 40).fill('#f9fbff').stroke('#e0e0e0');
    doc.fillColor('#0D1B3E').fontSize(7).font('Helvetica-Bold');
    doc.text('TOTAL BUDGETED', 45, startY + 8, { width: colW - 10, align: 'center' });
    doc.text('TOTAL ACTUAL', 45 + colW, startY + 8, { width: colW - 10, align: 'center' });
    doc.text('VARIANCE', 45 + colW * 2, startY + 8, { width: colW - 10, align: 'center' });
    doc.text('% UTILISED', 45 + colW * 3, startY + 8, { width: colW - 10, align: 'center' });
    
    doc.fontSize(10).fillColor('#1A3A6B').font('Helvetica-Bold');
    doc.text(\`Rs.\${formatCurr(budget.totalBudgeted)}\`, 45, startY + 20, { width: colW - 10, align: 'center' });
    doc.text(\`Rs.\${formatCurr(budget.totalActual)}\`, 45 + colW, startY + 20, { width: colW - 10, align: 'center' });
    doc.text(\`Rs.\${formatCurr(budget.variance)}\`, 45 + colW * 2, startY + 20, { width: colW - 10, align: 'center' });
    doc.text(\`\${budget.percentUsed.toFixed(1)}%\`, 45 + colW * 3, startY + 20, { width: colW - 10, align: 'center' });
    
    startY += 60;
    
    // Draw Table Header
    doc.rect(40, startY, pageW - 80, 20).fill('#0D1B3E');
    doc.fillColor('#FFFFFF').fontSize(8).font('Helvetica-Bold');
    doc.text('ACCOUNT', 50, startY + 6);
    doc.text('TYPE', 200, startY + 6);
    doc.text('BUDGETED', 280, startY + 6, { width: 70, align: 'right' });
    doc.text('ACTUAL', 360, startY + 6, { width: 70, align: 'right' });
    doc.text('VARIANCE', 440, startY + 6, { width: 70, align: 'right' });
    doc.text('% USED', 520, startY + 6, { width: 40, align: 'right' });
    
    startY += 20;
    
    // Draw Table Rows
    doc.fillColor('#000000').fontSize(8).font('Helvetica');
    budget.accountLines.forEach((line, i) => {
      if (startY > doc.page.height - 80) {
        doc.addPage();
        startY = 40;
        doc.rect(40, startY, pageW - 80, 20).fill('#0D1B3E');
        doc.fillColor('#FFFFFF').fontSize(8).font('Helvetica-Bold');
        doc.text('ACCOUNT', 50, startY + 6);
        doc.text('TYPE', 200, startY + 6);
        doc.text('BUDGETED', 280, startY + 6, { width: 70, align: 'right' });
        doc.text('ACTUAL', 360, startY + 6, { width: 70, align: 'right' });
        doc.text('VARIANCE', 440, startY + 6, { width: 70, align: 'right' });
        doc.text('% USED', 520, startY + 6, { width: 40, align: 'right' });
        startY += 20;
        doc.fillColor('#000000').fontSize(8).font('Helvetica');
      }
      
      const isEven = i % 2 === 0;
      if (isEven) {
        doc.rect(40, startY, pageW - 80, 20).fill('#f8f9fa');
        doc.fillColor('#000000');
      }
      
      doc.text(line.accountName, 50, startY + 6, { width: 140, height: 12, ellipsis: true });
      doc.text(line.accountType, 200, startY + 6);
      doc.text(\`Rs.\${formatCurr(line.budgetedTotal)}\`, 280, startY + 6, { width: 70, align: 'right' });
      doc.text(\`Rs.\${formatCurr(line.actualTotal)}\`, 360, startY + 6, { width: 70, align: 'right' });
      doc.text(\`Rs.\${formatCurr(line.variance)}\`, 440, startY + 6, { width: 70, align: 'right' });
      doc.text(\`\${line.percentUsed.toFixed(1)}%\`, 520, startY + 6, { width: 40, align: 'right' });
      
      startY += 20;
    });
    
    // Bottom Border
    doc.moveTo(40, startY).lineTo(pageW - 40, startY).lineWidth(1).stroke('#0D1B3E');
    
    doc.end();
  } catch (err) {
    console.error('PDF Export Error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// -- Excel Export -----------------------------------------------------------
router.get('/:id/export-excel', authenticate, async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    let budget = await Budget.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!budget) return res.status(404).json({ success: false, error: 'Budget not found' });
    
    budget = await enrichWithActuals(budget, req.user?.orgId, startDate, endDate);
    
    const rows = budget.accountLines.map(line => ({
      'Account': line.accountName,
      'Type': line.accountType,
      'Budgeted Amount': line.budgetedTotal,
      'Actual Amount': line.actualTotal,
      'Variance': line.variance,
      '% Used': parseFloat(line.percentUsed.toFixed(2))
    }));
    
    // Add summary row
    rows.push({
      'Account': 'TOTAL',
      'Type': '',
      'Budgeted Amount': budget.totalBudgeted,
      'Actual Amount': budget.totalActual,
      'Variance': budget.variance,
      '% Used': parseFloat(budget.percentUsed.toFixed(2))
    });
    
    const ws = xlsx.utils.json_to_sheet(rows);
    
    // Set column widths
    ws['!cols'] = [
      { wch: 30 },
      { wch: 15 },
      { wch: 15 },
      { wch: 15 },
      { wch: 15 },
      { wch: 10 }
    ];
    
    const wb = xlsx.utils.book_new();
    xlsx.utils.book_append_sheet(wb, ws, 'Budget vs Actuals');
    
    const buffer = xlsx.write(wb, { type: 'buffer', bookType: 'xlsx' });
    
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', \`attachment; filename="Budget-\${budget.budgetName}.xlsx"\`);
    res.send(buffer);
  } catch (err) {
    console.error('Excel Export Error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});
`;

let content = fs.readFileSync('routes/budgets.js', 'utf8');
content = content.replace('module.exports = router;', appendCode + '\n\nmodule.exports = router;');
fs.writeFileSync('routes/budgets.js', content);
console.log('Appended export routes to budgets.js');
