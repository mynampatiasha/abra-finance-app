const fs = require('fs');
const path = require('path');

let content = fs.readFileSync('routes/budgets.js', 'utf8');

// The PDF route starts at: router.get('/:id/export-pdf', ...
// The Excel route starts at: router.get('/:id/export-excel', ...

const pdfRouteOldRegex = /router\.get\('\/:id\/export-pdf'[\s\S]*?(?=router\.get\('\/:id\/export-excel')/;

const newPdfRoute = `router.get('/:id/export-pdf', async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    let budget = await Budget.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!budget) return res.status(404).json({ success: false, error: 'Budget not found' });
    
    // Enrich with actuals matching the UI
    budget = await enrichWithActuals(budget, req.user?.orgId, startDate, endDate);
    budget.variance = budget.totalVariance || 0;
    budget.percentUsed = budget.totalBudgeted > 0 ? (budget.totalActual / budget.totalBudgeted) * 100 : 0;
    
    // Get organization data for header
    const orgData = await getEffectiveOrgData(budget.orgId, budget.branchId, mongoose.connection.db);
    
    // Helper for robust logo extraction (like invoices.js)
    function getOrgLogoPath(orgId) {
      if (orgId) {
        const orgPath = path.join(__dirname, '..', 'public', 'uploads', orgId.toString(), 'logo.png');
        if (fs.existsSync(orgPath)) return orgPath;
        const orgJpg = path.join(__dirname, '..', 'public', 'uploads', orgId.toString(), 'logo.jpg');
        if (fs.existsSync(orgJpg)) return orgJpg;
      }
      return path.join(__dirname, '..', 'public', 'logo.png');
    }
    
    // Build PDF
    const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', \`attachment; filename="Budget_\${budget.budgetName.replace(/[^a-zA-Z0-9_-]/g, '_')}.pdf"\`);
    doc.pipe(res);
    
    const pageW = doc.page.width;
    
    // ═══════════════════════════════════════════════════════════════════════
    // HEADER — robust like invoices.js
    // ═══════════════════════════════════════════════════════════════════════
    let logoData = null;
    if (orgData?.logoBase64) {
      const match = orgData.logoBase64.match(/^data:(image\\/\\w+);base64,(.*)$/);
      if (match) logoData = Buffer.from(match[2], 'base64');
    }
    if (!logoData && orgData?.logoUrl) {
      const lp = path.join(__dirname, '..', orgData.logoUrl.replace(/^\\//, ''));
      try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
    }
    if (!logoData) {
      const lp = getOrgLogoPath(budget.orgId || null);
      try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
    }

    const textX = logoData ? 166 : 50;
    const textStartY = 35;
    const logoY = textStartY;

    if (logoData) {
      try {
        doc.image(logoData, 44, logoY, { width: 110, height: 82, fit: [110, 82] });
      } catch (e) { console.warn('Logo load failed:', e.message); }
    }

    const orgName = orgData.registeredName || orgData.name || 'ABRA FINANCE';
    doc.fontSize(13).fillColor('#000000').font('Helvetica-Bold')
       .text(orgName.toUpperCase(), textX, textStartY, { width: 200 });
       
    const orgNameH = doc.heightOfString(orgName.toUpperCase(), { width: 200 });
    const subtitleY = textStartY + orgNameH + 2;
    doc.fontSize(8).fillColor('#444444').font('Helvetica')
       .text('BILLING & FINANCE', textX, subtitleY, { width: 200, characterSpacing: 1 });

    doc.fontSize(8).fillColor('#000000');
    let contactY = subtitleY + 12;
    const orgAddr = [orgData.address?.street, orgData.address?.city, orgData.address?.state].filter(Boolean).join(', ');
    const orgPhone = orgData.phone;
    const orgEmail = orgData.email;
    const orgGST = orgData.gstin;

    const contactLines = [orgAddr, orgGST ? \`GSTIN: \${orgGST}\` : '', orgPhone, orgEmail].filter(Boolean);
    contactLines.forEach(line => {
      doc.text(line, textX, contactY, { width: 200 });
      contactY += 9;
    });

    // Right side text
    doc.fontSize(8).fillColor('#444444').font('Helvetica-Bold')
       .text('BUDGET VS ACTUALS', pageW - 210, 40, { width: 170, align: 'right', characterSpacing: 1 });
    doc.fontSize(16).fillColor('#000000').font('Helvetica-Bold')
       .text(budget.financialYear, pageW - 210, 52, { width: 170, align: 'right' });
    doc.fontSize(8).fillColor('#666666').font('Helvetica')
       .text(\`FY \${budget.financialYear} Expenses Budget\`, pageW - 210, 72, { width: 170, align: 'right' });
       
    let startY = 160;
    
    // Top Summary Blocks
    doc.fillColor('#0D1B3E').rect(40, startY - 20, (pageW - 80) / 4 - 5, 40).stroke();
    doc.fontSize(8).text('TOTAL BUDGETED', 40, startY - 10, { width: (pageW - 80) / 4 - 5, align: 'center' });
    doc.fontSize(10).font('Helvetica-Bold').text(\`Rs.\${formatCurr(budget.totalBudgeted)}\`, 40, startY + 2, { width: (pageW - 80) / 4 - 5, align: 'center' });
    
    doc.text('TOTAL ACTUAL', 40 + (pageW - 80) / 4, startY - 10, { width: (pageW - 80) / 4 - 5, align: 'center' });
    doc.text(\`Rs.\${formatCurr(budget.totalActual)}\`, 40 + (pageW - 80) / 4, startY + 2, { width: (pageW - 80) / 4 - 5, align: 'center' });
    
    doc.text('VARIANCE', 40 + (pageW - 80) / 2, startY - 10, { width: (pageW - 80) / 4 - 5, align: 'center' });
    doc.text(\`Rs.\${formatCurr(budget.variance)}\`, 40 + (pageW - 80) / 2, startY + 2, { width: (pageW - 80) / 4 - 5, align: 'center' });
    
    doc.text('% UTILISED', 40 + ((pageW - 80) / 4) * 3, startY - 10, { width: (pageW - 80) / 4 - 5, align: 'center' });
    doc.text(\`\${budget.percentUsed.toFixed(1)}%\`, 40 + ((pageW - 80) / 4) * 3, startY + 2, { width: (pageW - 80) / 4 - 5, align: 'center' });
    
    startY += 40;
    
    // Draw Main Table Header
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
      doc.text(\`Rs.\${formatCurr(line.totalBudgeted)}\`, 280, startY + 6, { width: 70, align: 'right' });
      doc.text(\`Rs.\${formatCurr(line.totalActual)}\`, 360, startY + 6, { width: 70, align: 'right' });
      doc.text(\`Rs.\${formatCurr(line.variance)}\`, 440, startY + 6, { width: 70, align: 'right' });
      doc.text(\`\${line.percentUsed.toFixed(1)}%\`, 520, startY + 6, { width: 40, align: 'right' });
      
      startY += 20;
    });
    
    // Draw Main Table TOTAL ROW
    if (startY > doc.page.height - 80) {
        doc.addPage();
        startY = 40;
    }
    doc.rect(40, startY, pageW - 80, 20).fill('#e9ecef');
    doc.fillColor('#000000').fontSize(8).font('Helvetica-Bold');
    doc.text('TOTAL', 50, startY + 6);
    doc.text(\`Rs.\${formatCurr(budget.totalBudgeted)}\`, 280, startY + 6, { width: 70, align: 'right' });
    doc.text(\`Rs.\${formatCurr(budget.totalActual)}\`, 360, startY + 6, { width: 70, align: 'right', color: '#27AE60' });
    doc.text(\`Rs.\${formatCurr(budget.variance)}\`, 440, startY + 6, { width: 70, align: 'right', color: budget.variance < 0 ? '#E74C3C' : '#000' });
    
    
    // ═══════════════════════════════════════════════════════════════════════
    // LANDSCAPE PAGE — MONTHLY BREAKDOWN
    // ═══════════════════════════════════════════════════════════════════════
    doc.addPage({ size: 'A4', layout: 'landscape', margin: 40 });
    const lsPageW = doc.page.width;
    
    doc.fontSize(12).fillColor('#000000').font('Helvetica-Bold').text('Monthly Breakdown (Budgeted vs Actual)', 40, 40);
    
    let msY = 70;
    doc.rect(40, msY, lsPageW - 80, 20).fill('#0D1B3E');
    doc.fillColor('#FFFFFF').fontSize(8).font('Helvetica-Bold');
    doc.text('ACCOUNT', 45, msY + 6, { width: 120 });
    
    const colW = (lsPageW - 160) / 12;
    FY_MONTHS.forEach((m, i) => {
      doc.text(m.label, 160 + (i * colW), msY + 6, { width: colW, align: 'center' });
    });
    
    msY += 20;
    
    budget.accountLines.forEach((line, i) => {
      if (msY > doc.page.height - 80) {
        doc.addPage({ size: 'A4', layout: 'landscape', margin: 40 });
        msY = 40;
        doc.rect(40, msY, lsPageW - 80, 20).fill('#0D1B3E');
        doc.fillColor('#FFFFFF').fontSize(8).font('Helvetica-Bold');
        doc.text('ACCOUNT', 45, msY + 6, { width: 120 });
        FY_MONTHS.forEach((m, i) => {
          doc.text(m.label, 160 + (i * colW), msY + 6, { width: colW, align: 'center' });
        });
        msY += 20;
      }
      
      const isEven = i % 2 === 0;
      if (isEven) {
        doc.rect(40, msY, lsPageW - 80, 24).fill('#f8f9fa');
      }
      
      doc.fillColor('#000000').fontSize(7).font('Helvetica-Bold');
      doc.text(line.accountName, 45, msY + 6, { width: 110, height: 20, ellipsis: true });
      
      FY_MONTHS.forEach((m, mi) => {
        const bdg = line.monthlyAmounts[mi] || 0;
        const act = line.actualMonthly[mi] || 0;
        
        doc.fontSize(6).font('Helvetica-Bold').fillColor('#000000');
        doc.text(formatCurr(bdg), 160 + (mi * colW), msY + 4, { width: colW, align: 'center' });
        
        doc.fontSize(6).font('Helvetica').fillColor('#27AE60');
        doc.text(formatCurr(act), 160 + (mi * colW), msY + 12, { width: colW, align: 'center' });
      });
      
      msY += 24;
    });
    
    // Monthly Totals Row
    if (msY > doc.page.height - 80) {
        doc.addPage({ size: 'A4', layout: 'landscape', margin: 40 });
        msY = 40;
    }
    doc.rect(40, msY, lsPageW - 80, 24).fill('#e9ecef');
    doc.fillColor('#000000').fontSize(8).font('Helvetica-Bold');
    doc.text('TOTAL', 45, msY + 8);
    
    FY_MONTHS.forEach((m, mi) => {
      let mBdg = 0;
      let mAct = 0;
      budget.accountLines.forEach(line => {
        mBdg += line.monthlyAmounts[mi] || 0;
        mAct += line.actualMonthly[mi] || 0;
      });
      
      doc.fontSize(6).font('Helvetica-Bold').fillColor('#000000');
      doc.text(formatCurr(mBdg), 160 + (mi * colW), msY + 4, { width: colW, align: 'center' });
      
      doc.fontSize(6).font('Helvetica').fillColor('#27AE60');
      doc.text(formatCurr(mAct), 160 + (mi * colW), msY + 12, { width: colW, align: 'center' });
    });
    
    doc.end();
  } catch (err) {
    console.error('Export PDF Error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});
`;

content = content.replace(pdfRouteOldRegex, newPdfRoute);

// Fix Excel filename too
const excelRouteRegex = /res\.setHeader\('Content-Disposition',\s*`attachment;\s*filename="Budget-\${budget\.budgetName}\.xlsx"`\);/;
content = content.replace(excelRouteRegex, 'res.setHeader(\'Content-Disposition\', \`attachment; filename="Budget_\${budget.budgetName.replace(/[^a-zA-Z0-9_-]/g, \'_\')}.xlsx"\`);');

fs.writeFileSync('routes/budgets.js', content);
console.log('Successfully updated budgets.js PDF route');
