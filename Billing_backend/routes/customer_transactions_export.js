// ============================================================================
// CUSTOMER TRANSACTIONS TAB — PER-SECTION EXPORT (PDF + Excel)
// ============================================================================
// One generic route serves all 5 sections (Invoices, Customer Payments,
// Credit Notes, Sales Orders, Quotes) shown on the customer detail page's
// Transactions tab, each in either PDF or Excel — instead of duplicating
// near-identical export logic five times.
//
// GET /api/finance/customers/:id/export/:section?format=pdf|excel
//   :section one of invoices | payments | credit-notes | sales-orders | quotes
// ============================================================================

'use strict';

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const XLSX = require('xlsx');
const PDFDocument = require('pdfkit');

// Only the Payments section needs real business logic (consolidating raw
// payment records into one row per payment) reused from billing-customers.js.
// The other four sections just read each type's own real model — already
// registered with its proper schema by invoices.js / quotes.js /
// sales-order.js / credit-notes.js at server startup — instead of routing
// through billing-customers.js's loose strict:false getters.
const { BillingCustomer, getPaymentSummaryRows } = require('./billing-customers');
require('./invoices');
require('./quotes');
require('./sales-order');
require('./credit-notes');
const getInvoiceModel    = () => mongoose.models.Invoice;
const getQuoteModel      = () => mongoose.models.Quote;
const getSalesOrderModel = () => mongoose.models.SalesOrder;
const getCreditNoteModel = () => mongoose.models.CreditNote;

const fmt = (n) => (parseFloat(n) || 0).toFixed(2);
const dstr = (d) => (d ? new Date(d).toLocaleDateString('en-IN') : '');

// ── Per-section config: how to fetch rows, and how to render them ───────────
const SECTIONS = {
  invoices: {
    label: 'Invoices',
    async rows(customer, req) {
      const Invoice = getInvoiceModel();
      const invoices = await Invoice.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId] },
        ...req.orgFilter,
      }).sort({ invoiceDate: -1 }).lean();
      return invoices.map(inv => ({
        Date: dstr(inv.invoiceDate),
        Number: inv.invoiceNumber,
        Status: inv.status,
        Amount: fmt(inv.totalAmount),
        'Balance Due': fmt(inv.amountDue),
      }));
    },
    columns: ['Date', 'Number', 'Status', 'Amount', 'Balance Due'],
  },

  payments: {
    label: 'Customer Payments',
    async rows(customer, req) {
      const Invoice = getInvoiceModel();
      const invoices = await Invoice.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId] },
        ...req.orgFilter,
      }).lean();
      const summary = await getPaymentSummaryRows(invoices, req.user?.orgId);
      return summary
        .sort((a, b) => new Date(b.date) - new Date(a.date))
        .map(p => ({
          Date: dstr(p.date),
          Number: p.paymentNumber,
          Status: 'PAID',
          Amount: fmt(p.totalAmount),
          'Applied To': p.breakdown.length
            ? p.breakdown.map(b => `${b.invoiceNumber} (₹${fmt(b.amount)})`).join(', ')
            : (p.excessAmount > 0 ? `Unapplied / excess: ₹${fmt(p.excessAmount)}` : ''),
        }));
    },
    columns: ['Date', 'Number', 'Status', 'Amount', 'Applied To'],
  },

  'credit-notes': {
    label: 'Credit Notes',
    async rows(customer, req) {
      const CreditNote = getCreditNoteModel();
      // CreditNote.customerId is a strict ObjectId field (unlike the other
      // types, which store it as a loose string) — only the real _id can be
      // used here, or Mongoose throws a cast error on the non-ObjectId
      // customer.customerId code.
      const validIds = [customer._id?.toString()].filter(id => mongoose.isValidObjectId(id));
      const notes = await CreditNote.find({
        customerId: { $in: validIds },
        ...req.orgFilter,
      }).sort({ creditNoteDate: -1 }).lean();
      return notes.map(cn => ({
        Date: dstr(cn.creditNoteDate),
        Number: cn.creditNoteNumber,
        Status: cn.status,
        Amount: fmt(cn.totalAmount),
        'Credit Balance': fmt(cn.creditBalance),
      }));
    },
    columns: ['Date', 'Number', 'Status', 'Amount', 'Credit Balance'],
  },

  'sales-orders': {
    label: 'Sales Orders',
    async rows(customer, req) {
      const SalesOrder = getSalesOrderModel();
      const orders = await SalesOrder.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId] },
        ...req.orgFilter,
      }).sort({ salesOrderDate: -1 }).lean();
      return orders.map(so => ({
        Date: dstr(so.salesOrderDate),
        Number: so.salesOrderNumber,
        Status: so.status,
        Amount: fmt(so.totalAmount),
      }));
    },
    columns: ['Date', 'Number', 'Status', 'Amount'],
  },

  quotes: {
    label: 'Quotes',
    async rows(customer, req) {
      const Quote = getQuoteModel();
      const quotes = await Quote.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId] },
        ...req.orgFilter,
      }).sort({ quoteDate: -1 }).lean();
      return quotes.map(q => ({
        Date: dstr(q.quoteDate),
        Number: q.quoteNumber,
        Status: q.status,
        Amount: fmt(q.totalAmount),
      }));
    },
    columns: ['Date', 'Number', 'Status', 'Amount'],
  },
};

// ── Excel ─────────────────────────────────────────────────────────────────
function sendExcel(res, filenameBase, columns, rows) {
  const ws = XLSX.utils.json_to_sheet(rows, { header: columns });
  ws['!cols'] = columns.map(c => ({ wch: Math.max(12, c.length + 4) }));
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Sheet1');
  const buffer = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
  res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  res.setHeader('Content-Disposition', `attachment; filename="${filenameBase}.xlsx"`);
  res.send(buffer);
}

// ── PDF ───────────────────────────────────────────────────────────────────

async function sendPdf(res, filenameBase, title, customerName, columns, rows, req, customer) {
  const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${filenameBase}.pdf"`);
  doc.pipe(res);

  const pageW = 515;

  let orgName  = 'Your Company';
  let orgGST   = '';
  let orgAddr  = '';
  let orgEmail = '';
  let orgPhone = '';
  let orgData  = null;
  try {
    // getEffectiveOrgData actually lives in branches.js, not billing-customers.js
    // (branch-aware — falls back to org-level data when no branch override exists).
    const { getEffectiveOrgData } = require('./branches');
    if (getEffectiveOrgData) {
      orgData  = await getEffectiveOrgData(req.user?.orgId, req.branchFilter?.branchId || null, mongoose.connection.db);
      if (orgData) {
        orgName  = orgData.orgName  || orgName;
        orgGST   = orgData.gstNumber || '';
        orgAddr  = orgData.address  || '';
        orgEmail = orgData.email    || '';
        orgPhone = orgData.phone    || '';
      }
    }
  } catch (e) {}

  let logoData = null;
  if (orgData?.logoBase64) {
    const match = orgData.logoBase64.match(/^data:(image\/\w+);base64,(.*)$/);
    if (match) logoData = Buffer.from(match[2], 'base64');
  }
  if (!logoData && orgData?.logoUrl) {
    const lp = require('path').join(__dirname, '..', orgData.logoUrl.replace(/^\//, ''));
    try { if (require('fs').existsSync(lp) && require('fs').statSync(lp).size > 0) logoData = lp; } catch (_) {}
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
     .text(title.toUpperCase(), textX, subtitleY, { width: 200, characterSpacing: 1 });

  doc.fontSize(8).fillColor('#000000');
  let contactY = subtitleY + 12;
  contactLines.forEach(line => {
    doc.text(line, textX, contactY, { width: 240 });
    const lineH = doc.heightOfString(line, { width: 240 });
    contactY += Math.max(lineH, 9) + 1;
  });

  doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
     .text(title.toUpperCase(), 380, 52, { width: 170, align: 'right' });
  doc.fontSize(8).fillColor('#000000').font('Helvetica')
     .text('Generated: ' + new Date().toLocaleDateString('en-IN'), 380, 76, { width: 170, align: 'right' });

  const metaY = Math.max(132, contactY + 8);
  const colW = pageW / 2;

  const billX = 40;
  doc.rect(billX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
  doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
     .text('TO', billX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
  doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold')
       .text(customerName || 'N/A', billX + 8, metaY + 18, { width: colW - 26 });

  let custAddr = '';
  if (customer && customer.billingAddress && customer.billingAddress.street) {
    custAddr = [
      customer.billingAddress.street,
      customer.billingAddress.city ? customer.billingAddress.city + ' - ' + (customer.billingAddress.zip || '') : '',
      customer.billingAddress.state,
      customer.billingAddress.country
    ].filter(Boolean).join('\n');
  } else if (customer) {
    custAddr = [
      customer.addressLine1,
      customer.city ? customer.city + ' - ' + (customer.postalCode || '') : '',
      customer.state,
      customer.country
    ].filter(Boolean).join('\n');
  }
  if (custAddr) {
    doc.fontSize(8).font('Helvetica').fillColor('#555555')
       .text(custAddr, billX + 8, metaY + 32, { width: colW - 26 });
  }

  const summX = 40 + colW + 10;
  doc.rect(summX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
  doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
     .text('SUMMARY', summX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
  doc.fontSize(10).fillColor('#000000').font('Helvetica')
     .text('Total Records:', summX + 8, metaY + 20)
     .text(String(rows.length), summX + 8, metaY + 20, { align: 'right', width: colW - 24 });

  let tableTop = metaY + 100;
  const colWidth = pageW / columns.length;

  const drawHeader = (y) => {
    doc.rect(40, y, pageW, 22).fill('#0F172A');
    doc.fontSize(9).font('Helvetica-Bold').fillColor('#FFFFFF');
    columns.forEach((c, i) => {
      doc.text(c.toUpperCase(), 40 + i * colWidth + 6, y + 6, { width: colWidth - 10 });
    });
  };

  const ensureSpace = (y, needed = 22) => {
    if (y + needed > doc.page.height - 40) {
      doc.addPage({ size: 'A4', margin: 40 });
      drawHeader(40);
      return 40 + 22;
    }
    return y;
  };

  drawHeader(tableTop);
  let rowY = tableTop + 22;

  // PDFKit's base font has no glyph for ₹ (U+20B9) — renders as a broken
  // character. Swap it for "Rs." in PDF output only (same known limitation
  // and fix already used elsewhere in this codebase); Excel keeps the real ₹.
  const cellText = (v) => String(v ?? '').replace(/₹/g, 'Rs.');

  doc.fontSize(8.5).font('Helvetica');
  rows.forEach((row, i) => {
    // Size each row to fit its tallest cell, so long "Applied To"-style text
    // that wraps to multiple lines is never clipped by the next row.
    const cellHeight = Math.max(
      ...columns.map(c => doc.heightOfString(cellText(row[c]), { width: colWidth - 10 })),
    );
    const rowH = Math.max(20, cellHeight + 10);

    rowY = ensureSpace(rowY, rowH);
    doc.rect(40, rowY, pageW, rowH).fill(i % 2 === 0 ? '#FFFFFF' : '#F7F9FC');
    doc.fillColor('#111111');
    columns.forEach((c, ci) => {
      doc.text(cellText(row[c]), 40 + ci * colWidth + 6, rowY + 5, {
        width: colWidth - 10,
      });
    });
    rowY += rowH;
  });

  if (rows.length === 0) {
    doc.fontSize(10).fillColor('#888888').text('No records to show.', 40, rowY + 10);
  }

  doc.end();
}


// ── Route ─────────────────────────────────────────────────────────────────
router.get('/:id/export/:section', async (req, res) => {
  try {
    const config = SECTIONS[req.params.section];
    if (!config) {
      return res.status(400).json({ success: false, error: `Unknown section "${req.params.section}"` });
    }
    const format = (req.query.format || 'pdf').toLowerCase();
    if (!['pdf', 'excel'].includes(format)) {
      return res.status(400).json({ success: false, error: 'format must be "pdf" or "excel"' });
    }

    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const rows = await config.rows(customer, req);
    const safeCustomerName = (customer.customerDisplayName || 'Customer').replace(/[^a-z0-9]+/gi, '_');
    const filenameBase = `${config.label.replace(/\s+/g, '_')}_${safeCustomerName}`;

    if (format === 'excel') {
      sendExcel(res, filenameBase, config.columns, rows);
    } else {
      await sendPdf(res, filenameBase, config.label, customer.customerDisplayName || '', config.columns, rows, req, customer);
    }
  } catch (error) {
    console.error('customer_transactions_export error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
