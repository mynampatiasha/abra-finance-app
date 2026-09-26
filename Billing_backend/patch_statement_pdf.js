const fs = require('fs');
const path = require('path');

const targetFile = path.join(__dirname, 'routes', 'billing-customers.js');
let content = fs.readFileSync(targetFile, 'utf8');

if (!content.includes("require('pdfkit')")) {
  content = content.replace("const multer = require('multer');", "const multer = require('multer');\nconst PDFDocument = require('pdfkit');\nconst { getEffectiveOrgData } = require('./branches');");
}

const pdfFunction = `
// GET /:id/statement/pdf
const getCustomerStatementPDF = async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const { fromDate, toDate } = req.query;
    const from = fromDate ? new Date(fromDate) : new Date(new Date().setFullYear(new Date().getFullYear() - 1));
    const to   = toDate   ? new Date(toDate)   : new Date();
    to.setHours(23, 59, 59, 999);
    from.setHours(0, 0, 0, 0);

    const Invoice = getInvoiceModel();
    let entries = [];
    let openingBalance = customer.openingBalance || 0;
    const custIdStr = customer._id?.toString();
    const custId2   = customer.customerId;

    const parseCustomDate = (dateVal, timeSource) => {
      if (!dateVal) return null;
      let parsed = null;
      if (dateVal instanceof Date) {
        parsed = new Date(dateVal);
      } else {
        const str = String(dateVal);
        if (str.includes('/')) {
          const parts = str.split('/');
          if (parts.length === 3) {
            parsed = new Date(parts[2], parts[1] - 1, parts[0]);
          }
        } else {
          parsed = new Date(str);
        }
      }
      
      if (parsed && !isNaN(parsed.getTime())) {
        if (timeSource) {
          const tDate = new Date(timeSource);
          if (!isNaN(tDate.getTime())) {
            parsed.setHours(tDate.getHours(), tDate.getMinutes(), tDate.getSeconds());
          }
        }
        return parsed;
      }
      return null;
    };

    if (Invoice) {
      const invoices = await Invoice.find({
        customerId: { $in: [custIdStr, custId2].filter(Boolean) },
        invoiceDate: { $gte: from, $lte: to },
        status: { $nin: ['CANCELLED', 'VOID'] },
        ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
      }).sort({ invoiceDate: 1 }).lean();

      for (const inv of invoices) {
        entries.push({
          date:     inv.invoiceDate,
          type:     'Invoice',
          number:   inv.invoiceNumber,
          details:  inv.subject || inv.orderNumber || '',
          invoices: inv.totalAmount,
          payments: null,
          balance:  null,
        });

        for (const p of (inv.payments || [])) {
          const pDate = parseCustomDate(p.paymentDate || p.recordedAt, p.recordedAt || p.paymentDate);
          if (!pDate) continue;
          if (pDate >= from && pDate <= to) {
            entries.push({
              date:     pDate,
              type:     'Payment',
              number:   inv.invoiceNumber,
              details:  p.paymentMethod || p.paymentMode || 'Payment',
              invoices: null,
              payments: parseFloat(p.amount || 0),
              balance:  null,
            });
          }
        }
      }

      try {
        const { getFinanceDb } = require('../config/database');
        const db = getFinanceDb();
        const paymentsReceived = await db.collection('payments_received').find({
          $or: [{ customerId: custIdStr }, { customerId: custId2 }, { customerId: customer._id }],
          paymentType: { $ne: 'advance' },
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        }).toArray();

        for (const p of paymentsReceived) {
          const pDate = parseCustomDate(p.paymentDate || p.createdAt, p.createdAt);
          if (!pDate) continue;

          if (pDate >= from && pDate <= to) {
            const alreadyAdded = entries.some(e =>
              e.type === 'Payment' &&
              Math.abs(parseFloat(e.payments || 0) - parseFloat(p.amountReceived || p.netAmount || 0)) < 0.01 &&
              e.date.toDateString() === pDate.toDateString()
            );
            if (alreadyAdded) continue;

            let invoiceNum = '';
            if (p.invoicePayments && typeof p.invoicePayments === 'object') {
              const invKeys = Object.keys(p.invoicePayments);
              if (invKeys.length > 0) {
                const invId = invKeys[0];
                const foundInv = invoices.find(i => i._id?.toString() === invId);
                if (foundInv) {
                  invoiceNum = foundInv.invoiceNumber;
                } else {
                  try {
                    const fetchedInv = await Invoice.findOne({ _id: invId }).select('invoiceNumber').lean();
                    if (fetchedInv) invoiceNum = fetchedInv.invoiceNumber;
                  } catch (e) { /* ignore */ }
                }
              }
            }
            if (!invoiceNum) invoiceNum = p.paymentNumber || 'PMT';

            entries.push({
              date:     pDate,
              type:     'Payment',
              number:   invoiceNum,
              details:  p.paymentMode || p.paymentMethod || 'Payment',
              invoices: null,
              payments: parseFloat(p.amountReceived || p.netAmount || 0),
              balance:  null,
            });
          }
        }
      } catch (dbErr) {}

      entries.sort((a, b) => new Date(a.date) - new Date(b.date));

      let runningBalance = openingBalance;
      entries = entries.map(e => {
        if (e.invoices) runningBalance += e.invoices;
        if (e.payments) runningBalance -= e.payments;
        return { ...e, balance: runningBalance };
      });
    }

    // Now generate PDF
    let orgName  = 'Your Company';
    let orgGST   = '';
    let orgAddr  = '';
    let orgEmail = '';
    let orgPhone = '';
    let orgData  = null;
    try {
      orgData  = await getEffectiveOrgData(req.user?.orgId, req.branchFilter?.branchId || null, mongoose.connection.db);
      if (orgData) {
        orgName  = orgData.orgName  || orgName;
        orgGST   = orgData.gstNumber || '';
        orgAddr  = orgData.address  || '';
        orgEmail = orgData.email    || '';
        orgPhone = orgData.phone    || '';
      }
    } catch (e) {}

    const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename="Statement_' + customer.customerDisplayName.replace(/\\s+/g, '_') + '.pdf"');
    doc.pipe(res);

    const pageW = 515;

    // Header
    let logoData = null;
    if (orgData?.logoBase64) {
      const match = orgData.logoBase64.match(/^data:(image\\/\\w+);base64,(.*)$/);
      if (match) logoData = Buffer.from(match[2], 'base64');
    }
    if (!logoData && orgData?.logoUrl) {
      const lp = path.join(__dirname, '..', orgData.logoUrl.replace(/^\\//, ''));
      try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
    }

    const textX = logoData ? 166 : 50;
    const contactLines = [orgAddr, orgGST ? 'GSTIN: ' + orgGST : '', orgPhone, orgEmail].filter(Boolean);
    const textBlockHeight = 14 + 12 + (contactLines.length * 9);
    const textStartY = 35;
    const logoCenterY = textStartY + (textBlockHeight / 2);
    
    const logoH = 82;
    const logoW = 110;
    const logoY = logoCenterY - (logoH / 2);

    if (logoData) {
      try {
        doc.image(logoData, 44, logoY, { width: logoW, height: logoH, fit: [logoW, logoH] });
      } catch (e) {}
    }

    doc.fontSize(13).fillColor('#000000').font('Helvetica-Bold')
       .text(orgName.toUpperCase(), textX, textStartY, { width: 200 });
    const orgNameH = doc.heightOfString(orgName.toUpperCase(), { width: 200 });
    const subtitleY = textStartY + orgNameH + 2;
    doc.fontSize(8).fillColor('#444444').font('Helvetica')
       .text('STATEMENT OF ACCOUNTS', textX, subtitleY, { width: 200, characterSpacing: 1 });

    doc.fontSize(8).fillColor('#000000');
    let contactY = subtitleY + 12;
    contactLines.forEach(line => {
      doc.text(line, textX, contactY, { width: 240 });
      const lineH = doc.heightOfString(line, { width: 240 });
      contactY += Math.max(lineH, 9) + 1;
    });

    doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
       .text('STATEMENT', 380, 52, { width: 170, align: 'right' });
    doc.fontSize(8).fillColor('#000000').font('Helvetica')
       .text('From: ' + from.toLocaleDateString('en-IN') + ' To: ' + to.toLocaleDateString('en-IN'), 380, 76, { width: 170, align: 'right' });

    const metaY = Math.max(132, contactY + 8);
    const colW = pageW / 2;
    
    const billX = 40;
    doc.rect(billX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
    doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
       .text('TO', billX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
    doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold')
       .text(customer.customerDisplayName || 'N/A', billX + 8, metaY + 18, { width: colW - 26 });
    
    const summX = 40 + colW + 10;
    doc.rect(summX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
    doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
       .text('ACCOUNT SUMMARY', summX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
    
    const closingBalance = entries.length > 0 ? entries[entries.length - 1].balance : openingBalance;
    doc.fontSize(10).fillColor('#000000').font('Helvetica')
       .text('Opening Balance:', summX + 8, metaY + 20)
       .text('Rs ' + openingBalance.toFixed(2), summX + 8, metaY + 20, { align: 'right', width: colW - 24 });
    
    let totalInvoiced = 0, totalPaid = 0;
    entries.forEach(e => {
       if (e.invoices) totalInvoiced += e.invoices;
       if (e.payments) totalPaid += e.payments;
    });

    doc.text('Invoiced Amount:', summX + 8, metaY + 35)
       .text('Rs ' + totalInvoiced.toFixed(2), summX + 8, metaY + 35, { align: 'right', width: colW - 24 });
    doc.text('Amount Paid:', summX + 8, metaY + 50)
       .text('Rs ' + totalPaid.toFixed(2), summX + 8, metaY + 50, { align: 'right', width: colW - 24 });
    
    doc.font('Helvetica-Bold').text('Balance Due:', summX + 8, metaY + 65)
       .text('Rs ' + closingBalance.toFixed(2), summX + 8, metaY + 65, { align: 'right', width: colW - 24 });

    const ensureSpace = (currentY, neededHeight = 20) => {
      if (currentY + neededHeight > 780) {
        doc.addPage();
        return 40;
      }
      return currentY;
    };

    let tableStartY = ensureSpace(metaY + 95, 40);

    const cols = {
      date:    { x: 40,  w: 60  },
      details: { x: 100, w: 220 },
      amount:  { x: 320, w: 75  },
      paid:    { x: 395, w: 75  },
      balance: { x: 470, w: 85  },
    };

    doc.rect(40, tableStartY, 515, 20).fill('#0f1e3d');
    doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
    doc.text('DATE',       cols.date.x + 4, tableStartY + 6, { width: cols.date.w });
    doc.text('DETAILS',    cols.details.x + 4, tableStartY + 6, { width: cols.details.w });
    doc.text('AMOUNT',     cols.amount.x + 4, tableStartY + 6, { width: cols.amount.w - 8, align: 'right' });
    doc.text('PAID',       cols.paid.x + 4, tableStartY + 6, { width: cols.paid.w - 8, align: 'right' });
    doc.text('BALANCE',    cols.balance.x + 4, tableStartY + 6, { width: cols.balance.w - 8, align: 'right' });

    let rowY = tableStartY + 20;

    rowY = ensureSpace(rowY, 24);
    doc.rect(40, rowY, 515, 24).fill('#ffffff');
    doc.rect(40, rowY, 515, 24).lineWidth(0.5).strokeColor('#dde4ef').stroke();
    doc.fontSize(8).fillColor('#000000').font('Helvetica');
    doc.text(from.toLocaleDateString('en-IN'), cols.date.x + 4, rowY + 8);
    doc.text('Opening Balance', cols.details.x + 4, rowY + 8);
    doc.font('Helvetica-Bold').text(openingBalance.toFixed(2), cols.balance.x + 4, rowY + 8, { width: cols.balance.w - 8, align: 'right' });
    rowY += 24;

    entries.forEach((e, i) => {
      const rowH = 24;
      rowY = ensureSpace(rowY, rowH);
      const fill = i % 2 === 0 ? '#f7f9fc' : '#ffffff';
      doc.rect(40, rowY, 515, rowH).fill(fill);
      doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();

      doc.fontSize(8).fillColor('#000000').font('Helvetica');
      doc.text(new Date(e.date).toLocaleDateString('en-IN'), cols.date.x + 4, rowY + 8);
      
      const details = e.number + (e.details ? ' - ' + e.details : '');
      doc.text(details, cols.details.x + 4, rowY + 8, { width: cols.details.w - 8, ellipsis: true });
      
      if (e.invoices) doc.text(e.invoices.toFixed(2), cols.amount.x + 4, rowY + 8, { width: cols.amount.w - 8, align: 'right' });
      if (e.payments) doc.text(e.payments.toFixed(2), cols.paid.x + 4, rowY + 8, { width: cols.paid.w - 8, align: 'right' });
      
      doc.font('Helvetica-Bold').text(e.balance.toFixed(2), cols.balance.x + 4, rowY + 8, { width: cols.balance.w - 8, align: 'right' });

      rowY += rowH;
    });

    doc.end();

  } catch (error) {
    console.error('Error generating PDF:', error);
    res.status(500).send('Error generating PDF');
  }
};
`

if (!content.includes('getCustomerStatementPDF')) {
  content = content.replace('module.exports = router;', pdfFunction + '\n\nmodule.exports = router;');
  if (!content.includes("router.get('/:id/statement/pdf'")) {
    content = content.replace("router.get('/:id/statement', getCustomerStatement);", "router.get('/:id/statement', getCustomerStatement);\nrouter.get('/:id/statement/pdf', getCustomerStatementPDF);");
  }
  fs.writeFileSync(targetFile, content);
  console.log('Successfully patched billing-customers.js');
} else {
  console.log('Already patched');
}
