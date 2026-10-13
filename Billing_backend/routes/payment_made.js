// ============================================================================
// PAYMENTS MADE - COMPLETE BACKEND (UPDATED)
// ============================================================================
// File: backend/routes/payment_made.js
//
// NEW in this version:
// ✅ GET /vendor-bills/:vendorId  → returns OPEN + OVERDUE + PARTIALLY_PAID
//    bills for that vendor (used by Flutter to show outstanding bills)
// ✅ POST / (create) → after saving payment, calls POST /api/bills/:id/payment
//    for each bill in billsApplied array → marks bills as paid/partially paid
// ✅ COA posting via postTransactionToCOA for payment_made record
// ✅ Balance deduction from paidFromAccount (existing, kept)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');
const multer = require('multer');

// ✅ COA Helper — same pattern as bill.js
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

async function getSystemAccountId(name, orgId = null) {
  try {
    const acc = await ChartOfAccount.findOne({
      accountName: name,
      isSystemAccount: true,
      ...(orgId ? { orgId } : {}),
    }).select('_id').lean();
    return acc ? acc._id : null;
  } catch (e) {
    console.error(`COA lookup error for "${name}":`, e.message);
    return null;
  }
}

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const paymentMadeSchema = new mongoose.Schema(
  {
    paymentNumber: { type: String, required: true, index: true },

    vendorId: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', required: true },
    vendorName: { type: String, required: true },
    vendorEmail: { type: String },

    paymentDate: { type: Date, required: true, default: Date.now },
    paymentMode: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online', 'NEFT', 'RTGS', 'IMPS'],
      required: true,
    },
    referenceNumber: { type: String },
    paidFromAccountId: { type: mongoose.Schema.Types.ObjectId, ref: 'Account', default: null },
    paidFromAccountName: { type: String, default: null },
    amount: { type: Number, required: true, min: 0 },
    notes: { type: String },

    paymentType: {
      type: String,
      enum: ['PAYMENT', 'ADVANCE', 'EXCESS'],
      default: 'PAYMENT',
    },

    status: {
      type: String,
      enum: ['DRAFT', 'RECORDED', 'APPLIED', 'PARTIALLY_APPLIED', 'REFUNDED', 'VOIDED'],
      default: 'RECORDED',
    },

    billsApplied: [
      {
        billId: mongoose.Schema.Types.ObjectId,
        billNumber: String,
        amountApplied: Number,
        appliedDate: Date,
      },
    ],

    amountApplied: { type: Number, default: 0 },
    amountUnused: { type: Number, default: 0 },

    items: [
      {
        itemDetails: { type: String, required: true },
        itemType: { type: String, enum: ['FETCHED', 'MANUAL'], default: 'MANUAL' },
        itemId: { type: mongoose.Schema.Types.ObjectId },
        account: { type: String },
        quantity: { type: Number, default: 1 },
        rate: { type: Number, default: 0 },
        discount: { type: Number, default: 0 },
        discountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
        amount: { type: Number, default: 0 },
      },
    ],

    subTotal: { type: Number, default: 0 },
    tdsRate: { type: Number, default: 0 },
    tdsAmount: { type: Number, default: 0 },
    tcsRate: { type: Number, default: 0 },
    tcsAmount: { type: Number, default: 0 },
    gstRate: { type: Number, default: 18 },
    cgst: { type: Number, default: 0 },
    sgst: { type: Number, default: 0 },
    igst: { type: Number, default: 0 },
    totalAmount: { type: Number, default: 0 },

    refunds: [
      {
        refundId: mongoose.Schema.Types.ObjectId,
        amount: Number,
        refundDate: Date,
        refundMode: String,
        referenceNumber: String,
        notes: String,
        refundedBy: String,
        refundedAt: Date,
      },
    ],
    totalRefunded: { type: Number, default: 0 },

    pdfPath: String,
    pdfGeneratedAt: Date,

    orgId: { type: String, index: true, default: null },
    branchId: { type: String, index: true, default: null },
    providerTransactionId: { type: mongoose.Schema.Types.ObjectId, default: null },
    createdBy: { type: String, required: true },
    updatedBy: String,
  },
  { timestamps: true }
);

// Pre-save: recalculate amounts
paymentMadeSchema.pre('save', function () {
  if (this.items && this.items.length > 0) {
    this.subTotal = this.items.reduce((sum, item) => sum + (item.amount || 0), 0);
    this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
    this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
    const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
    const gstAmount = (gstBase * this.gstRate) / 100;
    this.cgst = gstAmount / 2;
    this.sgst = gstAmount / 2;
    this.igst = 0;
    this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  } else {
    this.totalAmount = this.amount || 0;
    this.subTotal = this.amount || 0;
  }
  this.amountApplied = (this.billsApplied || []).reduce(
    (s, b) => s + (b.amountApplied || 0), 0
  );
  this.amountUnused = Math.max(
    0, this.totalAmount - this.amountApplied - (this.totalRefunded || 0)
  );
  if (this.amountApplied >= this.totalAmount && this.totalAmount > 0)
    this.status = 'APPLIED';
  else if (this.amountApplied > 0)
    this.status = 'PARTIALLY_APPLIED';
  else if (!['DRAFT', 'VOIDED', 'REFUNDED'].includes(this.status))
    this.status = 'RECORDED';
});

paymentMadeSchema.index({ orgId: 1, branchId: 1, paymentNumber: 1 }, { unique: true });
paymentMadeSchema.index({ vendorId: 1, paymentDate: -1 });
paymentMadeSchema.index({ status: 1 });
paymentMadeSchema.index({ createdAt: -1 });

const PaymentMade = mongoose.models.PaymentMade || mongoose.model('PaymentMade', paymentMadeSchema);

// ============================================================================
// HELPERS
// ============================================================================

async function generatePaymentNumber(orgId = null, branchId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(PaymentMade, 'paymentNumber', 'PMT', orgId, branchId);
}

function calcItemAmount(item) {
  let amt = (item.quantity || 1) * (item.rate || 0);
  if (item.discount > 0) {
    if (item.discountType === 'percentage') amt -= amt * (item.discount / 100);
    else amt -= item.discount;
  }
  return Math.max(0, Math.round(amt * 100) / 100);
}

// ============================================================================
// PDF GENERATION (unchanged)
// ============================================================================

function findLogoPath() {
  const candidates = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg'),
  ];
  for (const p of candidates) {
    try { if (fs.existsSync(p) && fs.statSync(p).size > 0) return p; } catch (_) {}
  }
  return null;
}

// Org-specific logo lookup (same logic as invoices.js)
function getPmOrgLogoPath(orgId, branchLogoUrl = null) {
  // If branch has its own logo URL, use it
  if (branchLogoUrl) {
    const branchLogoPath = path.join(__dirname, '..', branchLogoUrl.replace(/^\//, ''));
    try {
      if (fs.existsSync(branchLogoPath) && fs.statSync(branchLogoPath).size > 0) return branchLogoPath;
    } catch (_) {}
  }
  if (orgId) {
    const orgLogoDir = path.join(__dirname, '..', 'uploads', 'org-logos');
    if (fs.existsSync(orgLogoDir)) {
      try {
        const files = fs.readdirSync(orgLogoDir);
        const match = files.find(f => f.startsWith(`org-${orgId}-`));
        if (match) {
          const fullPath = path.join(orgLogoDir, match);
          const stats    = fs.statSync(fullPath);
          if (stats.isFile() && stats.size > 0) return fullPath;
        }
      } catch (_) {}
    }
  }
  // fallback to generic logo
  return findLogoPath();
}

// Branch-aware org data helper
const { getEffectiveOrgData } = require('./branches');

async function getPmOrgData(orgId, branchId = null) {
  try {
    const mongoose = require('mongoose');
    const db = mongoose.connection.db;
    if (!db) return null;
    return await getEffectiveOrgData(orgId, branchId, db);
  } catch (_) { return null; }
}

async function generatePaymentPDF(payment, orgId, branchId = null) {
  const orgData = await getPmOrgData(orgId, branchId);
  const orgName    = orgData?.orgName    || '';
  const orgGST     = orgData?.gstNumber  || '';
  const orgPhone   = orgData?.phone      || '';
  const orgEmail   = orgData?.email      || '';
  const orgAddress = orgData?.address    || '';

  // The vendor's saved address, printed under "PAID TO".
  let vendorAddrStr = '';
  try {
    if (payment.vendorId) {
      const _vend = await mongoose.connection.collection('billingvendors')
        .findOne({ _id: new mongoose.Types.ObjectId(String(payment.vendorId)) });
      const _a = _vend?.billingAddress;
      vendorAddrStr = [_a?.street, _a?.street2, _a?.city, _a?.state, _a?.pincode || _a?.zip]
        .filter(Boolean).join(', ');
    }
  } catch (_) { /* no address — print the voucher as before */ }

  return new Promise((resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'payments');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
      const filename = `payment-${payment.paymentNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      const pageW = 515; // usable width (595 - 40*2)

      // ═══════════════════════════════════════════════════════════════════════
      // HEADER — white background with logo (invoice.js style)
      // ═══════════════════════════════════════════════════════════════════════
      let logoData = null;
      if (orgData?.logoBase64) {
        const match = orgData.logoBase64.match(/^data:(image\/\w+);base64,(.*)$/);
        if (match) logoData = Buffer.from(match[2], 'base64');
      }
      if (!logoData && orgData?.logoUrl) {
        const lp = path.join(__dirname, '..', orgData.logoUrl.replace(/^\//, ''));
        try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
      }
      if (!logoData) {
        const lp = getPmOrgLogoPath(orgId, null);
        try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
      }

      const contactLines = [orgAddress, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      const textBlockHeight = 14 + 12 + (contactLines.length * 9);
      const textStartY  = 35;
      const logoCenterY = textStartY + (textBlockHeight / 2);
      
      const logoH = 82; // Increased to match invoice
      const logoW = 110; // Increased to match invoice
      const logoY = textStartY; // Align top of logo with top of text

      if (logoData) {
        try {
          doc.image(logoData, 44, logoY, { width: logoW, height: logoH, fit: [logoW, logoH] });
        } catch (e) { console.warn('?? Logo load failed:', e.message); }
      }
      const textX = logoData ? 166 : 50;

      doc.fontSize(12).fillColor('#000000').font('Helvetica-Bold')
         .text(orgName.toUpperCase(), textX, textStartY, { width: 200 });
      doc.fontSize(12).font('Helvetica-Bold');
      const orgNameH = doc.heightOfString(orgName.toUpperCase(), { width: 200 });
      const subtitleY = textStartY + orgNameH + 2;
      doc.fontSize(7).fillColor('#444444').font('Helvetica')
         .text('BILLING & FINANCE', textX, subtitleY, { width: 200, characterSpacing: 1 });
      doc.fontSize(7).fillColor('#000000');
      let contactY = subtitleY + 12;
      contactLines.forEach(line => {
        doc.text(line, textX, contactY, { width: 240 });
        const lineH = doc.heightOfString(line, { width: 240 });
        contactY += Math.max(lineH, 9) + 1;
      });

      doc.fontSize(8).fillColor('#444444').font('Helvetica-Bold')
         .text('PAYMENT MADE', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
         .text(payment.paymentNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`Date: ${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#000000').font('Helvetica-Bold')
         .text(`${(payment.status || 'RECORDED').replace(/_/g, ' ')}`, 380, 92, { width: 170, align: 'right' });

      // ═══════════════════════════════════════════════════════════════════════
      // META GRID — Paid To | Payment Details (invoice.js style)
      // ═══════════════════════════════════════════════════════════════════════
      const metaY = Math.max(132, contactY + 8);
      const colW  = pageW / 2;
      // Grow the "Paid To" box when the vendor address needs extra lines.
      doc.fontSize(7).font('Helvetica');
      const _vAddrH = vendorAddrStr ? doc.heightOfString(vendorAddrStr, { width: colW - 16 }) : 0;
      doc.fontSize(9).font('Helvetica-Bold');
      const _vNameH = doc.heightOfString(payment.vendorName || 'N/A', { width: colW - 16 });
      const metaH = Math.max(80, 18 + _vNameH + 2 + (_vAddrH ? _vAddrH + 2 : 0) + (payment.vendorEmail ? 10 : 0) + 10);

      // Col 1: Paid To
      const col1X = 40;
      doc.rect(col1X, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('PAID TO', col1X + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold')
         .text(payment.vendorName || 'N/A', col1X + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(9).font('Helvetica-Bold');
      const vendorNameH = doc.heightOfString(payment.vendorName || 'N/A', { width: colW - 16 });
      let _vendY = metaY + 18 + vendorNameH + 2;
      if (vendorAddrStr) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(vendorAddrStr, col1X + 8, _vendY, { width: colW - 16 });
        _vendY += _vAddrH + 2;
      }
      if (payment.vendorEmail) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(payment.vendorEmail, col1X + 8, _vendY, { width: colW - 16, ellipsis: true });
      }

      // Col 2: Payment Details
      const col2X = 40 + colW;
      doc.rect(col2X, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('PAYMENT DETAILS', col2X + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(7).fillColor('#000000').font('Helvetica')
         .text(`Payment #: ${payment.paymentNumber}`, col2X + 8, metaY + 18, { width: colW - 16 });
      doc.text(`Mode: ${payment.paymentMode}`, col2X + 8, metaY + 29, { width: colW - 16 });
      doc.text(`Type: ${payment.paymentType}`, col2X + 8, metaY + 40, { width: colW - 16 });
      if (payment.referenceNumber) {
        doc.text(`Ref #: ${payment.referenceNumber}`, col2X + 8, metaY + 51, { width: colW - 16 });
      }

      let tableStartY = metaY + metaH + 12;

      // ═══════════════════════════════════════════════════════════════════════
      // BILLS APPLIED TABLE (if any)
      // ═══════════════════════════════════════════════════════════════════════
      if (payment.billsApplied && payment.billsApplied.length > 0) {
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('BILLS PAID', 40, tableStartY, { characterSpacing: 0.8 });
        doc.moveTo(40, tableStartY + 9).lineTo(555, tableStartY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        tableStartY += 14;

        // Bills table header
        doc.rect(40, tableStartY, pageW, 20).fill('#0f1e3d');
        doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold');
        doc.text('BILL #',          52, tableStartY + 7, { width: 200 });
        doc.text('AMOUNT APPLIED',  52, tableStartY + 7, { width: pageW - 24, align: 'right' });
        tableStartY += 20;

        payment.billsApplied.forEach((b, idx) => {
          const fill = idx % 2 === 0 ? '#ffffff' : '#f7f9fc';
          doc.rect(40, tableStartY, pageW, 20).fill(fill);
          doc.rect(40, tableStartY, pageW, 20).lineWidth(0.5).strokeColor('#dde4ef').stroke();
          doc.fontSize(7).fillColor('#000000').font('Helvetica');
          doc.text(b.billNumber || '-', 52, tableStartY + 7, { width: 200 });
          doc.font('Helvetica-Bold')
             .text(`Rs. ${(b.amountApplied || 0).toFixed(2)}`, 52, tableStartY + 7, { width: pageW - 24, align: 'right' });
          tableStartY += 20;
        });
        tableStartY += 12;
      }

      // ═══════════════════════════════════════════════════════════════════════
      // ITEMS TABLE
      // ═══════════════════════════════════════════════════════════════════════
      if (payment.items && payment.items.length > 0) {
        // Table header — navy (invoice style)
        doc.rect(40, tableStartY, pageW, 20).fill('#0f1e3d');
        doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold');
        doc.text('ITEM DETAILS', 52,  tableStartY + 7, { width: 260 });
        doc.text('QTY',          316, tableStartY + 7, { width: 50,  align: 'center' });
        doc.text('RATE',         366, tableStartY + 7, { width: 70,  align: 'right' });
        doc.text('AMOUNT',       436, tableStartY + 7, { width: 79,  align: 'right' });

        let rowY = tableStartY + 20;
        payment.items.forEach((item, idx) => {
          const fill = idx % 2 === 0 ? '#ffffff' : '#f7f9fc';
          doc.rect(40, rowY, pageW, 22).fill(fill);
          doc.rect(40, rowY, pageW, 22).lineWidth(0.5).strokeColor('#dde4ef').stroke();
          doc.fontSize(7).fillColor('#000000').font('Helvetica');
          doc.text(item.itemDetails || 'N/A', 52,  rowY + 8, { width: 260, ellipsis: true });
          doc.text(String(item.quantity || 0),  316, rowY + 8, { width: 50,  align: 'center' });
          doc.text(`Rs. ${(item.rate || 0).toFixed(2)}`,   366, rowY + 8, { width: 70,  align: 'right' });
          doc.font('Helvetica-Bold')
             .text(`Rs. ${(item.amount || 0).toFixed(2)}`, 436, rowY + 8, { width: 79,  align: 'right' });
          rowY += 22;
        });
        tableStartY = rowY;
      }

      // ═══════════════════════════════════════════════════════════════════════
      // TOTALS — right-aligned (invoice.js style)
      // ═══════════════════════════════════════════════════════════════════════
      const totalsX = 315;
      const totalsW = 240;
      let totalsY   = tableStartY + 12;
      const labelX  = totalsX;
      const amountX = totalsX + totalsW;

      const tRow = (label, amount, bold = false) => {
        doc.fontSize(8)
           .fillColor('#5e6e84').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(label, labelX, totalsY, { width: 140 });
        doc.fillColor('#000000').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(amount, labelX + 140, totalsY, { width: 100, align: 'right' });
        doc.moveTo(labelX, totalsY + 11).lineTo(amountX, totalsY + 11)
           .lineWidth(0.5).strokeColor('#dde4ef').dash(2, { space: 2 }).stroke().undash();
        totalsY += 14;
      };

      tRow('Subtotal:', `Rs. ${(payment.subTotal || 0).toFixed(2)}`);
      if ((payment.cgst || 0) > 0) tRow('CGST:', `Rs. ${payment.cgst.toFixed(2)}`);
      if ((payment.sgst || 0) > 0) tRow('SGST:', `Rs. ${payment.sgst.toFixed(2)}`);
      if ((payment.igst || 0) > 0) tRow('IGST:', `Rs. ${payment.igst.toFixed(2)}`);
      if ((payment.tdsAmount || 0) > 0) tRow('TDS Deducted:', `- Rs. ${payment.tdsAmount.toFixed(2)}`);
      if ((payment.tcsAmount || 0) > 0) tRow('TCS Collected:', `Rs. ${payment.tcsAmount.toFixed(2)}`);

      // Grand total box — dark navy (invoice style)
      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('Total Payment', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Rs. ${(payment.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      // ═══════════════════════════════════════════════════════════════════════
      // NOTES
      // ═══════════════════════════════════════════════════════════════════════
      let notesY = Math.max(tableStartY + 12, totalsY) + 12;
      if (payment.notes) {
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTES', 40, notesY, { characterSpacing: 0.8 });
        doc.moveTo(40, notesY + 9).lineTo(555, notesY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica')
           .text(payment.notes, 40, notesY + 14, { width: pageW });
        notesY += 40;
      }

      // ═══════════════════════════════════════════════════════════════════════
      // AUTHORIZED SIGNATORY — right-aligned (invoice.js style)
      // ═══════════════════════════════════════════════════════════════════════
      const signBoxW     = 220;
      const authBoxX     = 555 - signBoxW;
      const signSectionY = Math.max(tableStartY + 12, totalsY) + 12;

      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text(`For ${orgName.toUpperCase()}`, authBoxX, signSectionY, { width: signBoxW, characterSpacing: 0.5, ellipsis: true });

      const sigRelPath = orgData?.digitalSignaturePath;
      const sigImgSize = 200;
      let   actualSigH = sigImgSize;
      
      let sigBuf = null;
      let sigExt = '.png';
      if (orgData?.signatureBase64) {
        const match = orgData.signatureBase64.match(/^data:image\/(\w+);base64,(.*)$/);
        if (match) {
          sigExt = '.' + match[1].replace('jpeg', 'jpg');
          sigBuf = Buffer.from(match[2], 'base64');
        }
      } else if (sigRelPath) {
        const sigAbsPath = path.join(__dirname, '..', sigRelPath.replace(/^\//, ''));
        try { if (fs.existsSync(sigAbsPath)) { sigBuf = fs.readFileSync(sigAbsPath); sigExt = path.extname(sigAbsPath).toLowerCase(); } } catch (_) {}
      }

      if (sigBuf) {
        try {
            let imgW = sigImgSize, imgH = sigImgSize;
            try {
              if (sigExt === '.png' && sigBuf.length > 24) {
                imgW = sigBuf.readUInt32BE(16);
                imgH = sigBuf.readUInt32BE(20);
              } else if ((sigExt === '.jpg' || sigExt === '.jpeg') && sigBuf.length > 4) {
                let i = 2;
                while (i < sigBuf.length - 8) {
                  if (sigBuf[i] === 0xFF && sigBuf[i+1] >= 0xC0 && sigBuf[i+1] <= 0xC3) {
                    imgH = sigBuf.readUInt16BE(i + 5);
                    imgW = sigBuf.readUInt16BE(i + 7);
                    break;
                  }
                  i += 2 + sigBuf.readUInt16BE(i + 2);
                }
              }
            } catch (_) {}
            const scale      = Math.min(sigImgSize / imgW, sigImgSize / imgH);
            actualSigH       = Math.round(imgH * scale);
            const actualSigW = Math.round(imgW * scale);
            const centeredX  = authBoxX + (signBoxW - actualSigW) / 2;
            doc.image(sigBuf, centeredX, signSectionY + 10, { width: actualSigW, height: actualSigH });
        } catch (_e) { console.warn('⚠️ Signature render failed:', _e.message); }
      }

      const sigLineY = signSectionY + 10 + actualSigH + 14;
      doc.moveTo(authBoxX, sigLineY).lineTo(authBoxX + signBoxW, sigLineY)
         .lineWidth(0.5).strokeColor('#aaaaaa').stroke();
      doc.fontSize(6.5).fillColor('#000000').font('Helvetica-Bold')
         .text('Authorized Signatory', authBoxX, sigLineY + 3, { width: signBoxW, align: 'center' });

      // ═══════════════════════════════════════════════════════════════════════
      // FOOTER (invoice.js style)
      // ═══════════════════════════════════════════════════════════════════════
      const footerY = 730;
      doc.moveTo(40, footerY).lineTo(555, footerY).lineWidth(1).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName}${orgGST ? ' · GSTIN: ' + orgGST : ''} · ${payment.paymentNumber}`,
               40, footerY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`,
               40, footerY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => resolve({ filename, filepath, relativePath: `/uploads/payments/${filename}` }));
      stream.on('error', reject);
    } catch (err) { reject(err); }
  });
}

// ============================================================================
// EMAIL (unchanged)
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: false,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
});

async function sendPaymentEmail(payment, orgId = null, branchId = null) {
  if (!payment.vendorEmail) return;

  let orgName  = '';
  let orgGST   = '';
  let orgPhone = '';
  let orgEmail = '';
  try {
    const orgData = await getPmOrgData(orgId, branchId);
    orgName  = orgData?.orgName   || '';
    orgGST   = orgData?.gstNumber || '';
    orgPhone = orgData?.phone     || '';
    orgEmail = orgData?.email     || '';
  } catch (e) {
    console.warn('⚠️ Could not fetch org details for payment email:', e.message);
  }

  const html = `<!DOCTYPE html> <html lang="en"> <head>   <meta charset="UTF-8">   <title>Payment ${payment.paymentNumber}</title>   <style>     * { margin: 0; padding: 0; box-sizing: border-box; }     body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }     .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }     .header { background: #0f1e3d; padding: 24px 32px; }     .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }     .header p  { color: rgba(255,255,255,0.7); font-size: 11px; letter-spacing: 0.5px; }     .header .num { color: #fff; font-size: 14px; font-weight: bold; margin-top: 8px; }     .body { padding: 28px 32px; }     .success-badge { background: #d4edda; border: 1px solid #28a745; border-radius: 6px;                      padding: 16px; text-align: center; margin: 18px 0; }     .success-badge h2 { color: #155724; font-size: 18px; margin-bottom: 4px; }     .success-badge p  { color: #155724; font-size: 13px; }     .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase;                      letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0;                      padding-bottom: 6px; margin: 22px 0 12px; }     table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }     table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }     table.detail td:first-child { color: #555; width: 160px; }     table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }     .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222;                     border-bottom: none; padding-top: 10px; }     .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;               font-size: 11px; color: #777; text-align: center; line-height: 1.7; }   </style> </head> <body> <div class="wrapper">   <div class="header">     <h1>Payment Confirmation</h1>     <p>FROM ${orgName.toUpperCase()}</p>     <div class="num">${payment.paymentNumber}</div>   </div>   <div class="body">     <p style="font-size:14px;color:#222;margin-bottom:18px;">Dear ${payment.vendorName},</p>      <div class="success-badge">       <h2>✅ Payment of ₹${(payment.totalAmount || payment.amount || 0).toFixed(2)} recorded</h2>       <p>Payment Number: ${payment.paymentNumber}</p>     </div>      <div class="section-title">Payment Details</div>     <table class="detail">       <tr><td>Payment Number</td><td>${payment.paymentNumber}</td></tr>       <tr><td>Payment Date</td><td>${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}</td></tr>       <tr><td>Payment Mode</td><td>${payment.paymentMode}</td></tr>       ${payment.referenceNumber ? `<tr><td>Reference #</td><td>${payment.referenceNumber}</td></tr>` : ''}       <tr><td>Payment Type</td><td>${payment.paymentType}</td></tr>       <tr class="total-row"><td>Total Amount</td><td>₹${(payment.totalAmount || payment.amount || 0).toFixed(2)}</td></tr>     </table>      ${payment.billsApplied && payment.billsApplied.length > 0 ? `     <div class="section-title">Bills Paid</div>     <table class="detail">       ${payment.billsApplied.map(b => `         <tr><td>${b.billNumber || '-'}</td><td>₹${(b.amountApplied || 0).toFixed(2)}</td></tr>       `).join('')}     </table>` : ''}      ${payment.notes ? `     <div class="section-title">Notes</div>     <p style="font-size:12px;color:#444;line-height:1.7;">${payment.notes}</p>` : ''}      <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">       Please keep this confirmation for your records.     </p>   </div>   <div class="footer">     <strong>${orgName}</strong><br>     ${orgGST   ? 'GST: '  + orgGST   + ' &nbsp;|&nbsp; ' : ''}     ${orgPhone ? 'Ph: '   + orgPhone  + ' &nbsp;|&nbsp; ' : ''}     ${orgEmail || ''}   </div> </div> </body> </html>`;

  return emailTransporter.sendMail({
    from: `"${orgName} - Payments" <${process.env.SMTP_USER}>`,
    to: payment.vendorEmail,
    subject: `Payment Confirmation ${payment.paymentNumber} — ₹${(payment.totalAmount || payment.amount || 0).toFixed(2)}`,
    html,
  });
}

// ============================================================================
// MULTER FOR IMPORT
// ============================================================================

const importUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/\.(xlsx|xls|csv)$/i.test(file.originalname)) cb(null, true);
    else cb(new Error('Only Excel/CSV files allowed'));
  },
});

// ============================================================================
// ROUTES
// ============================================================================

// ── NEW: GET /vendor-bills/:vendorId ─────────────────────────────────────────
// Returns all OPEN + OVERDUE + PARTIALLY_PAID bills for a vendor
// Used by Flutter Payment Made screen to show outstanding bills
router.get('/vendor-bills/:vendorId', async (req, res) => {
  try {
    const { vendorId } = req.params;

    if (!mongoose.Types.ObjectId.isValid(vendorId)) {
      return res.status(400).json({ success: false, error: 'Invalid vendor ID' });
    }

    // Dynamically get the Bill model (registered in bill.js)
    const Bill = mongoose.models.Bill ||
      mongoose.model('Bill', new mongoose.Schema({}, { strict: false }));

    const bills = await Bill.find({
      vendorId: new mongoose.Types.ObjectId(vendorId),
      status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] },
    })
      .select('billNumber billDate dueDate totalAmount amountDue amountPaid status')
      .sort({ billDate: 1 }) // oldest first for auto-allocation
      .lean();

    res.json({
      success: true,
      count: bills.length,
      data: bills,
    });
  } catch (err) {
    console.error('Error fetching vendor bills:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /vendor-payments-with-balance/:vendorId
// Returns all payments for a vendor that still have amountUnused > 0
// (i.e. eligible for a refund). Used by the Vendor Payment Refund flow.
router.get('/vendor-payments-with-balance/:vendorId', async (req, res) => {
  try {
    const { vendorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(vendorId)) {
      return res.status(400).json({ success: false, error: 'Invalid vendor ID' });
    }

    const orgFilter = req.user?.orgId
      ? { $or: [{ orgId: req.user.orgId }, { orgId: null }, { orgId: { $exists: false } }] }
      : {};

    const payments = await PaymentMade.find({
      vendorId: new mongoose.Types.ObjectId(vendorId),
      status: { $in: ['RECORDED', 'PARTIALLY_APPLIED', 'APPLIED'] },
      ...orgFilter,
      ...(req.branchFilter || {}),
    })
      .sort({ paymentDate: -1 })
      .lean();

    // Filter to only those with a refundable balance
    const withBalance = payments
      .map(p => ({
        _id:             p._id,
        paymentNumber:   p.paymentNumber,
        paymentDate:     p.paymentDate,
        paymentMode:     p.paymentMode,
        paymentType:     p.paymentType,
        amount:          p.totalAmount || p.amount || 0,
        amountApplied:   p.amountApplied || 0,
        totalRefunded:   p.totalRefunded || 0,
        amountUnused:    p.amountUnused != null
          ? p.amountUnused
          : Math.max(0, (p.totalAmount || p.amount || 0) - (p.amountApplied || 0) - (p.totalRefunded || 0)),
        status:          p.status,
        referenceNumber: p.referenceNumber || '',
        notes:           p.notes || '',
      }))
      .filter(p => p.amountUnused > 0.001); // only refundable ones

    res.json({
      success: true,
      count: withBalance.length,
      data: withBalance,
    });
  } catch (err) {
    console.error('Error fetching vendor payments with balance:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /vendor-advances/:vendorId — returns all ADVANCE payments for a vendor
router.get('/vendor-advances/:vendorId', async (req, res) => {
  try {
    const { vendorId } = req.params;
    if (!mongoose.Types.ObjectId.isValid(vendorId)) {
      return res.status(400).json({ success: false, error: 'Invalid vendor ID' });
    }

    const orgFilter = req.user?.orgId
      ? { $or: [{ orgId: req.user.orgId }, { orgId: null }, { orgId: { $exists: false } }] }
      : {};

    const advances = await PaymentMade.find({
      vendorId: new mongoose.Types.ObjectId(vendorId),
      paymentType: 'ADVANCE',
      ...orgFilter,
      ...(req.branchFilter || {}),
    })
      .sort({ paymentDate: -1 })
      .lean();

    const result = advances.map(a => ({
      _id:            a._id,
      paymentNumber:  a.paymentNumber,
      paymentDate:    a.paymentDate,
      paymentMode:    a.paymentMode,
      amount:         a.totalAmount || a.amount || 0,
      amountApplied:  a.amountApplied || 0,
      amountUnused:   a.amountUnused ?? Math.max(0, (a.totalAmount || a.amount || 0) - (a.amountApplied || 0)),
      status:         a.status,
      referenceNumber: a.referenceNumber || '',
      notes:          a.notes || '',
    }));

    const totalAdvance = result.reduce((s, a) => s + a.amount, 0);
    const totalUnused  = result.reduce((s, a) => s + a.amountUnused, 0);

    res.json({
      success: true,
      count: result.length,
      totalAdvance,
      totalUnused,
      data: result,
    });
  } catch (err) {
    console.error('Error fetching vendor advances:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET all
router.get('/', async (req, res) => {
  try {
    const {
      status, vendorId, fromDate, toDate, paymentMode,
      paymentType, page = 1, limit = 20, search,
    } = req.query;
    const query = {};
    // FIX: orgId filter — also match records where orgId is null/missing
    // (records created before orgId enforcement will have orgId: null).
    // Uses req.orgIds (array) rather than req.orgFilter directly so a
    // multi-org / "All Organizations" selection still matches, while
    // keeping the legacy null-orgId fallback intact.
    if (req.orgIds && req.orgIds.length > 0) {
      query.$or = [
        { orgId: { $in: req.orgIds } },
        { orgId: null },
        { orgId: { $exists: false } },
      ];
    }
    Object.assign(query, req.branchFilter || {});
    if (status) query.status = status;
    if (vendorId) query.vendorId = vendorId;
    if (paymentMode) query.paymentMode = paymentMode;
    if (paymentType) query.paymentType = paymentType;
    if (fromDate || toDate) {
      query.paymentDate = {};
      if (fromDate) query.paymentDate.$gte = new Date(fromDate);
      if (toDate) query.paymentDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { paymentNumber: new RegExp(search, 'i') },
        { vendorName: new RegExp(search, 'i') },
        { referenceNumber: new RegExp(search, 'i') },
      ];
    }
    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [payments, total] = await Promise.all([
      PaymentMade.find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).select('-__v'),
      PaymentMade.countDocuments(query),
    ]);
    res.json({
      success: true,
      data: payments,
      pagination: {
        total, page: parseInt(page), limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET stats
router.get('/stats', async (req, res) => {
  try {
    // FIX: also include records with orgId: null
    const orgFilter = {
      ...(req.user?.orgId
        ? { $or: [{ orgId: req.user.orgId }, { orgId: null }, { orgId: { $exists: false } }] }
        : {}),
      ...(req.branchFilter || {}),
    };
    const stats = await PaymentMade.aggregate([
      { $match: orgFilter },
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalApplied: { $sum: '$amountApplied' },
          totalUnused: { $sum: '$amountUnused' },
        },
      },
    ]);
    const overall = { totalPayments: 0, totalAmount: 0, totalApplied: 0, totalUnused: 0, byStatus: {} };
    stats.forEach((s) => {
      overall.totalPayments += s.count;
      overall.totalAmount += s.totalAmount;
      overall.totalApplied += s.totalApplied;
      overall.totalUnused += s.totalUnused;
      overall.byStatus[s._id] = { count: s.count, amount: s.totalAmount };
    });
    res.json({ success: true, data: overall });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET single
router.get('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    res.json({ success: true, data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST / — Create payment ───────────────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const data = { ...req.body };
    if (!data.paymentNumber) data.paymentNumber = await generatePaymentNumber(req.user?.orgId || null, req.branchIds?.length > 0 ? req.branchIds[0] : null);
    if (!data.vendorId) return res.status(400).json({ success: false, error: 'Vendor is required' });

    if (typeof data.vendorId === 'string' && mongoose.Types.ObjectId.isValid(data.vendorId)) {
      data.vendorId = new mongoose.Types.ObjectId(data.vendorId);
    }
    if (data.items) {
      data.items = data.items.map((item) => ({ ...item, amount: calcItemAmount(item) }));
    }
    data.createdBy = req.user?.email || req.user?.uid || 'system';
    data.orgId = req.user?.orgId || null;
    data.branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;

    const payment = new PaymentMade(data);
    await payment.save();

    // ── STEP 1: Deduct balance from paidFromAccount ───────────────────────────
    if (data.paidFromAccountId && !data.providerTransactionId) {
      try {
        const PaymentAccount = mongoose.models.PaymentAccount ||
          mongoose.model('PaymentAccount', new mongoose.Schema(
            { currentBalance: { type: Number, default: 0 } },
            { strict: false }
          ));
        const deductAmount = payment.totalAmount || payment.amount || 0;
        const updatedAccount = await PaymentAccount.findByIdAndUpdate(
          data.paidFromAccountId,
          { $inc: { currentBalance: -deductAmount }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (updatedAccount) {
          console.log(`✅ Balance deducted from "${updatedAccount.accountName}": -₹${deductAmount} → ₹${updatedAccount.currentBalance}`);
        } else {
          console.warn(`⚠️ Account ${data.paidFromAccountId} not found — balance NOT updated`);
        }
      } catch (balErr) {
        console.error(`⚠️ Balance deduction error:`, balErr.message);
      }
    }

    // ── STEP 2: Apply payment to each bill via bill.js payment route ──────────
    // This marks each bill as PAID / PARTIALLY_PAID and posts bill-level COA
    const billsApplied = data.billsApplied || [];
    for (const ba of billsApplied) {
      if (!ba.billId || !ba.amountApplied || ba.amountApplied <= 0) continue;
      try {
        const Bill = mongoose.models.Bill;
        if (!Bill) { console.warn('Bill model not loaded — skipping bill payment update'); continue; }

        const bill = await Bill.findById(ba.billId);
        if (!bill) { console.warn(`Bill ${ba.billId} not found`); continue; }

        const billPayment = {
          paymentId: payment._id,
          amount: ba.amountApplied,
          paymentDate: payment.paymentDate,
          paymentMode: payment.paymentMode,
          referenceNumber: payment.paymentNumber,
          notes: `Payment Made: ${payment.paymentNumber}`,
          recordedBy: data.createdBy,
          recordedAt: new Date(),
        };

        bill.payments = bill.payments || [];
        bill.payments.push(billPayment);
        bill.amountPaid = (bill.amountPaid || 0) + ba.amountApplied;
        await bill.save();

        // ── COA for bill payment: Debit AP + Credit Bank/Cash ───────────────
        try {
          const currentOrgId = req.user?.orgId || null;
const apId = await getSystemAccountId('Accounts Payable', currentOrgId);

// Resolve paidFromAccountId → COA ID (may be a PaymentAccount, not a COA directly)
let bankId = null;
if (data.paidFromAccountId) {
  // Try direct COA lookup first
  const directCOA = await ChartOfAccount.findById(data.paidFromAccountId).lean();
  if (directCOA) {
    bankId = directCOA._id;
  } else {
    // paidFromAccountId is a PaymentAccount — resolve by name
    const PaymentAccount = mongoose.models.PaymentAccount ||
      mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const pa = await PaymentAccount.findById(data.paidFromAccountId).lean();
    if (pa) {
      const coa = await ChartOfAccount.findOne({
        accountName: pa.accountName,
        $or: [
          { orgId: currentOrgId },
          { orgId: null },
          { orgId: { $exists: false } }
        ]
      }).lean();
      if (coa) bankId = coa._id;
    }
  }
}
if (!bankId) {
  bankId = await getSystemAccountId('Undeposited Funds', currentOrgId);
}
          const txnDate = new Date(payment.paymentDate);
          if (apId) {
            await postTransactionToCOA({
              accountId: apId,
              orgId: currentOrgId,
              branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
              date: txnDate,
              description: `Payment ${payment.paymentNumber} - ${bill.billNumber}`,
              referenceType: 'Payment',
              referenceId: payment._id,
              referenceNumber: payment.paymentNumber,
              debit: ba.amountApplied,
              credit: 0,
            });
          }
          if (bankId) {
            await postTransactionToCOA({
              accountId: bankId,
              orgId: currentOrgId,
              branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
              date: txnDate,
              description: `Payment ${payment.paymentNumber} - ${bill.billNumber}`,
              referenceType: 'Payment',
              referenceId: payment._id,
              referenceNumber: payment.paymentNumber,
              debit: 0,
              credit: ba.amountApplied,
            });
          }
          console.log(`✅ COA posted for bill payment: ${bill.billNumber} ← ₹${ba.amountApplied}`);
        } catch (coaErr) {
          console.error(`⚠️ COA post error for bill ${ba.billId}:`, coaErr.message);
        }

        console.log(`✅ Bill ${bill.billNumber} updated: paid ₹${ba.amountApplied}, status: ${bill.status}`);
      } catch (billErr) {
        console.error(`⚠️ Bill payment update error for ${ba.billId}:`, billErr.message);
      }
    }

    // ── STEP 2b: COA for ADVANCE payment (no bills) ──────────────────────────
    if (payment.paymentType === 'ADVANCE' && billsApplied.length === 0) {
      console.log('🔵 [ADVANCE COA] Starting advance COA posting...');
      console.log('🔵 [ADVANCE COA] paymentNumber:', payment.paymentNumber);
      console.log('🔵 [ADVANCE COA] amount:', payment.totalAmount);
      console.log('🔵 [ADVANCE COA] paidFromAccountId:', data.paidFromAccountId);
      console.log('🔵 [ADVANCE COA] orgId:', req.user?.orgId);

      try {
        const currentOrgId = req.user?.orgId || null;
        const txnDate = new Date(payment.paymentDate);

        // ── Find Advance to Vendor COA (NOT system account lookup) ──
        const advanceAcc = await ChartOfAccount.findOne({
          accountName: 'Advance to Vendor',
          $or: [
            { orgId: currentOrgId },
            { orgId: null },
            { orgId: { $exists: false } }
          ]
        }).lean();

        console.log('🔵 [ADVANCE COA] advanceAcc found:',
          advanceAcc ? `YES — id=${advanceAcc._id}` : 'NO ❌');

        // ── Find Bank COA account ──
        let bankCOAId   = null;
        let bankCOAName = null;

        if (data.paidFromAccountId) {
          // Try direct COA lookup first
          const directCOA = await ChartOfAccount.findById(data.paidFromAccountId).lean();

          if (directCOA) {
            bankCOAId   = directCOA._id;
            bankCOAName = directCOA.accountName;
            console.log('🔵 [ADVANCE COA] bankCOA direct hit:', bankCOAName);
          } else {
            // paidFromAccountId is a PaymentAccount — resolve by name
            const PaymentAccount = mongoose.models.PaymentAccount ||
              mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');

            const pa = await PaymentAccount.findById(data.paidFromAccountId).lean();
            console.log('🔵 [ADVANCE COA] PaymentAccount found:',
              pa ? pa.accountName : 'NO ❌');

            if (pa) {
              const coa = await ChartOfAccount.findOne({
                accountName: pa.accountName,
                $or: [
                  { orgId: currentOrgId },
                  { orgId: null },
                  { orgId: { $exists: false } }
                ]
              }).lean();

              if (coa) {
                bankCOAId   = coa._id;
                bankCOAName = coa.accountName;
                console.log('🔵 [ADVANCE COA] bankCOA via name lookup:', bankCOAName);
              } else {
                console.log('🔵 [ADVANCE COA] bankCOA NOT found by name:', pa.accountName, '❌');
              }
            }
          }
        }

        console.log('🔵 [ADVANCE COA] Final IDs — advanceAccId:',
          advanceAcc?._id, '| bankCOAId:', bankCOAId);

        if (!advanceAcc?._id) {
          console.error('❌ [ADVANCE COA] Advance to Vendor account missing!');
        }
        if (!bankCOAId) {
          console.error('❌ [ADVANCE COA] Bank COA account missing!');
        }

        if (advanceAcc?._id && bankCOAId) {
          // DEBIT: Advance to Vendor (Asset increases)
          await postTransactionToCOA({
            accountId:       advanceAcc._id,
            orgId:           currentOrgId,
            branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
            date:            txnDate,
            description:     `Vendor Advance ${payment.paymentNumber} - ${payment.vendorName}`,
            referenceType:   'PaymentMade',
            referenceId:     payment._id,
            referenceNumber: payment.paymentNumber,
            debit:           payment.totalAmount,
            credit:          0,
          });
          console.log('✅ [ADVANCE COA] Dr Advance to Vendor:', payment.totalAmount);

          // CREDIT: Bank Account (Asset decreases)
          await postTransactionToCOA({
            accountId:       bankCOAId,
            orgId:           currentOrgId,
            branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
            date:            txnDate,
            description:     `Vendor Advance ${payment.paymentNumber} - ${payment.vendorName}`,
            referenceType:   'PaymentMade',
            referenceId:     payment._id,
            referenceNumber: payment.paymentNumber,
            debit:           0,
            credit:          payment.totalAmount,
          });
          console.log('✅ [ADVANCE COA] Cr Bank:', bankCOAName, payment.totalAmount);
          console.log('✅ [ADVANCE COA] Complete for:', payment.paymentNumber);
        }
      } catch (coaErr) {
        console.error('❌ [ADVANCE COA] Error:', coaErr.message);
      }
    }

    // ── STEP 3: COA for payment_made record (items-based portion) ─────────────
    // Only posts if there are line items (advance / extra payment)
    if (payment.items && payment.items.length > 0 && payment.subTotal > 0 && payment.paymentType !== 'ADVANCE') {
      console.log('🔵 [STEP3] Running items COA for:', payment.paymentNumber,
        '| type:', payment.paymentType,
        '| items:', payment.items?.length,
        '| subTotal:', payment.subTotal);
      try {
        const currentOrgId = req.user?.orgId || null;
        const [expenseId, apId] = await Promise.all([
          getSystemAccountId('Cost of Goods Sold', currentOrgId),
          getSystemAccountId('Accounts Payable', currentOrgId),
        ]);
        const txnDate = new Date(payment.paymentDate);
        if (expenseId) {
          await postTransactionToCOA({
            accountId: expenseId,
            orgId: currentOrgId,
            branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
            date: txnDate,
            description: `Payment Made ${payment.paymentNumber} - ${payment.vendorName} (items)`,
            referenceType: 'PaymentMade',
            referenceId: payment._id,
            referenceNumber: payment.paymentNumber,
            debit: payment.subTotal,
            credit: 0,
          });
        }
        if (apId) {
          await postTransactionToCOA({
            accountId: apId,
            orgId: currentOrgId,
            branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
            date: txnDate,
            description: `Payment Made ${payment.paymentNumber} - ${payment.vendorName} (items)`,
            referenceType: 'PaymentMade',
            referenceId: payment._id,
            referenceNumber: payment.paymentNumber,
            debit: 0,
            credit: payment.subTotal,
          });
        }
        console.log(`✅ COA posted for payment_made items: ${payment.paymentNumber}`);
      } catch (coaErr) {
        console.error(`⚠️ COA post error (payment items):`, coaErr.message);
      }
    }

    // ── CREATE PROVIDER TRANSACTION (for All Transactions tab) ──────────────
    // Skip if this payment was created from the banking categorization flow
    // (providerTransactionId present means the original bank txn already exists
    //  and will be marked via /mark-categorized — creating a duplicate here
    //  would cause ghost entries that survive uncategorization)
    try {
      const ProviderTransaction = mongoose.models.ProviderTransaction
        || mongoose.model('ProviderTransaction',
            new mongoose.Schema({}, { strict: false }),
            'providertransactions');

      if (data.paidFromAccountId && mongoose.Types.ObjectId.isValid(data.paidFromAccountId)
          && !data.providerTransactionId) {
        await ProviderTransaction.create({
          accountId:            new mongoose.Types.ObjectId(data.paidFromAccountId),
          orgId:                req.user?.orgId || null,
          branchId:             req.branchIds?.length > 0 ? req.branchIds[0] : null,
          transactionDate:      new Date(payment.paymentDate),
          description:          `Vendor Payment: ${payment.vendorName}`,
          amount:               payment.totalAmount || payment.amount || 0,
          transactionType:      'DEBIT',
          reconciliationStatus: 'CATEGORIZED',
          categoryLabel:        'Vendor Payment',
          source:               'SYSTEM_ENTRY',
          linkedRecordId:       payment._id,
          linkedRecordType:     'PaymentMade',
          journalRef:           payment.paymentNumber,
          categorizedAt:        new Date(),
          categorizedBy:        req.user?.email || 'system',
          importedAt:           new Date(),
          importedBy:           req.user?.email || 'system',
        });
        console.log(`✅ ProviderTransaction created for payment made: ${payment.paymentNumber}`);
      }
    } catch (ptErr) {
      console.error('⚠️ ProviderTransaction create error (payment made):', ptErr.message);
    }
    // ── END PROVIDER TRANSACTION ─────────────────────────────────────────────

    try { await sendPaymentEmail(payment, req.user?.orgId || null, payment.branchId || null); } catch (_) {}

    console.log(`✅ Payment Made created: ${payment.paymentNumber}`);
    res.status(201).json({ success: true, message: 'Payment recorded', data: payment });
  } catch (err) {
    console.error('Error creating payment:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});




// PUT update
router.put('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (payment.status === 'APPLIED')
      return res.status(400).json({ success: false, error: 'Cannot edit fully applied payments' });

    const oldAmount      = payment.totalAmount || payment.amount || 0;
    const oldPaidFromId  = payment.paidFromAccountId;

    const updates = { ...req.body };
    if (updates.items) updates.items = updates.items.map((item) => ({ ...item, amount: calcItemAmount(item) }));
    updates.updatedBy = req.user?.email || 'system';
    Object.assign(payment, updates);
    await payment.save();

    const newAmount     = payment.totalAmount || payment.amount || 0;
    const newPaidFromId = payment.paidFromAccountId;
    const orgId         = req.user?.orgId || null;

    // ── BALANCE ADJUSTMENT ────────────────────────────────────────────────────
    try {
      const paidFromChanged = newPaidFromId?.toString() !== oldPaidFromId?.toString();
      if (paidFromChanged) {
        if (oldPaidFromId) await PaymentAccount.findByIdAndUpdate(oldPaidFromId, { $inc: { currentBalance: oldAmount } });
        if (newPaidFromId) await PaymentAccount.findByIdAndUpdate(newPaidFromId, { $inc: { currentBalance: -newAmount } });
      } else {
        const diff = newAmount - oldAmount;
        if (diff !== 0 && newPaidFromId) {
          await PaymentAccount.findByIdAndUpdate(newPaidFromId, { $inc: { currentBalance: -diff } });
        }
      }
    } catch (balErr) {
      console.error('⚠️ Balance adjustment error (payment_made update):', balErr.message);
    }

    // ── COA ADJUSTMENT ────────────────────────────────────────────────────────
    try {
      const diff = newAmount - oldAmount;
      if (diff !== 0) {
        const apCOA = await ChartOfAccount.findOne({
          accountName: 'Accounts Payable', ...(orgId ? { orgId } : {}),
        }).lean();
        let bankCOAId = null;
        if (newPaidFromId) {
          bankCOAId = await ChartOfAccount.findById(newPaidFromId).then(a => a?._id).catch(() => null);
          if (!bankCOAId && payment.paidFromAccountName) {
            bankCOAId = await ChartOfAccount.findOne({
              accountName: payment.paidFromAccountName, ...(orgId ? { orgId } : {}),
            }).then(a => a?._id).catch(() => null);
          }
        }
        const txnDate = new Date(payment.paymentDate || new Date());
        const desc = `UPDATED - Payment ${payment.paymentNumber} - ${payment.vendorName}`;
        if (apCOA) await postTransactionToCOA({
          accountId: apCOA._id, orgId, date: txnDate,
          branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
          description: desc,
          referenceType: 'Bill', referenceId: payment._id,
          referenceNumber: payment.paymentNumber,
          debit: diff > 0 ? diff : 0, credit: diff < 0 ? Math.abs(diff) : 0,
        });
        if (bankCOAId) await postTransactionToCOA({
          accountId: bankCOAId, orgId, date: txnDate,
          branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
          description: desc,
          referenceType: 'Bill', referenceId: payment._id,
          referenceNumber: payment.paymentNumber,
          debit: diff < 0 ? Math.abs(diff) : 0, credit: diff > 0 ? diff : 0,
        });
      }
    } catch (coaErr) {
      console.error('⚠️ COA adjustment error (payment_made update):', coaErr.message);
    }
    // ── END COA ADJUSTMENT ────────────────────────────────────────────────────

    res.json({ success: true, message: 'Payment updated', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST apply to bills
router.post('/:id/apply', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const { bills } = req.body;
    if (!Array.isArray(bills)) return res.status(400).json({ success: false, error: 'Bills array required' });
    for (const b of bills) {
      payment.billsApplied.push({
        billId: b.billId, billNumber: b.billNumber,
        amountApplied: b.amountApplied, appliedDate: new Date(),
      });
    }
    await payment.save();
    res.json({ success: true, message: 'Payment applied to bills', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST refund
router.post('/:id/refund', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const { amount, refundMode, referenceNumber, notes } = req.body;
    if (!amount || amount <= 0) return res.status(400).json({ success: false, error: 'Invalid refund amount' });
    if (amount > (payment.amountUnused || 0))
      return res.status(400).json({ success: false, error: 'Refund exceeds unused amount' });
    payment.refunds.push({
      refundId: new mongoose.Types.ObjectId(), amount, refundDate: new Date(),
      refundMode, referenceNumber, notes,
      refundedBy: req.user?.email || 'system', refundedAt: new Date(),
    });
    payment.totalRefunded = (payment.totalRefunded || 0) + amount;
    if (payment.totalRefunded >= payment.totalAmount) payment.status = 'REFUNDED';
    await payment.save();
    res.json({ success: true, message: 'Refund recorded', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/payments-made/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({ _id: req.params.id, orgId: req.user?.orgId, ...(req.branchFilter || {}) });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const org = await getPmOrgData(req.user?.orgId, req.branchIds?.length === 1 ? req.branchIds[0] : null);
    const orgName = org?.orgName || '';
    const orgGST  = org?.gstNumber || '';
    const orgPhone = org?.phone || '';
    const orgEmail = org?.email || '';
    const dateStr = new Date(payment.paymentDate || payment.createdAt).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const html = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Payment ${payment.paymentNumber}</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;font-size:13px;color:#222;background:#f4f4f4}.wrapper{max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd}.header{background:#0f1e3d;padding:24px 32px}.header h1{color:#fff;font-size:20px;font-weight:bold}.header .num{color:#fff;font-size:14px;font-weight:bold;margin-top:8px}.body{padding:28px 32px}.st{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px}table.d{width:100%;border-collapse:collapse;font-size:13px}table.d td{padding:7px 0;border-bottom:1px dashed #e8e8e8;vertical-align:top}table.d td:first-child{color:#555;width:160px}table.d td:last-child{font-weight:600;color:#111;text-align:right}.tr td{font-size:15px;font-weight:bold;border-top:2px solid #222;border-bottom:none;padding-top:10px}.footer{background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7}</style>
</head><body><div class="wrapper">
<div class="header"><h1>Payment Confirmation</h1><div class="num">${payment.paymentNumber}</div></div>
<div class="body">
<p style="font-size:14px;margin-bottom:18px;">Dear ${payment.vendorName || 'Vendor'},</p>
<p style="color:#444;line-height:1.7;margin-bottom:6px;">We confirm receipt of your payment <strong>${payment.paymentNumber}</strong>.</p>
<div class="st">Payment Details</div>
<table class="d">
<tr><td>Payment Number</td><td>${payment.paymentNumber}</td></tr>
<tr><td>Date</td><td>${dateStr}</td></tr>
<tr><td>Payment Mode</td><td>${payment.paymentMode || ''}</td></tr>
${payment.referenceNumber ? `<tr><td>Reference</td><td>${payment.referenceNumber}</td></tr>` : ''}
<tr class="tr"><td>Amount Paid</td><td>₹${(payment.totalAmount || 0).toFixed(2)}</td></tr>
</table>
${payment.notes ? `<div class="st">Notes</div><p style="font-size:12px;line-height:1.7;color:#444;">${payment.notes}</p>` : ''}
</div>
<div class="footer"><strong>${orgName}</strong><br>${orgGST ? 'GST: ' + orgGST + ' | ' : ''}${orgPhone ? 'Ph: ' + orgPhone + ' | ' : ''}${orgEmail}</div>
</div></body></html>`;
    res.json({ success: true, data: { subject: `Payment Confirmation ${payment.paymentNumber} — ₹${(payment.totalAmount || 0).toFixed(2)}`, html, to: payment.vendorEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const payment = await PaymentMade.findOne({ _id: req.params.id, ...req.orgFilter });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (to !== undefined)      payment.set('customEmailTo',      to);
    if (subject !== undefined) payment.set('customEmailSubject', subject);
    if (html !== undefined)    payment.set('customEmailHtml',    html);
    await payment.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE
router.delete('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!['DRAFT', 'RECORDED'].includes(payment.status)) {
      return res.status(400).json({ success: false, error: 'Only Draft or Recorded payments can be deleted' });
    }
    await payment.deleteOne();

    // Restore balance on delete
    if (payment.paidFromAccountId) {
      try {
        const PaymentAccount = mongoose.models.PaymentAccount ||
          mongoose.model('PaymentAccount', new mongoose.Schema(
            { currentBalance: { type: Number, default: 0 } }, { strict: false }
          ));
        const restoreAmount = payment.totalAmount || payment.amount || 0;
        const restoredAccount = await PaymentAccount.findByIdAndUpdate(
          payment.paidFromAccountId,
          { $inc: { currentBalance: restoreAmount }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (restoredAccount) {
          console.log(`✅ Balance restored: +₹${restoreAmount} → "${restoredAccount.accountName}" ₹${restoredAccount.currentBalance}`);
        }
      } catch (balErr) {
        console.error(`⚠️ Balance restore error:`, balErr.message);
      }
    }

    // ── CLEAN UP PROVIDER TRANSACTIONS ──────────────────────────────────────
    try {
      const ProviderTransaction = mongoose.models.ProviderTransaction
        || mongoose.model('ProviderTransaction',
            new mongoose.Schema({}, { strict: false }),
            'providertransactions');

      // Delete any system-created ProviderTransaction linked to this payment
      await ProviderTransaction.deleteMany({
        linkedRecordId:   payment._id,
        linkedRecordType: 'PaymentMade',
        source:           'SYSTEM_ENTRY',
        ...req.orgFilter,
      });

      // If this payment was created from the banking flow, reset the original
      // imported bank ProviderTransaction back to UNCATEGORIZED
      if (payment.providerTransactionId) {
        await ProviderTransaction.findByIdAndUpdate(payment.providerTransactionId, {
          $set: {
            reconciliationStatus: 'UNCATEGORIZED',
            categorizedAt:    null,
            categorizedBy:    null,
            journalRef:       null,
            categoryLabel:    null,
            linkedRecordId:   null,
            linkedRecordType: null,
          }
        });
      }
      console.log(`✅ ProviderTransaction cleaned up for payment made: ${payment._id}`);
    } catch (ptErr) {
      console.error('⚠️ ProviderTransaction cleanup error (payment made delete):', ptErr.message);
    }
    // ── END PROVIDER TRANSACTION CLEANUP ─────────────────────────────────────

    res.json({ success: true, message: 'Payment deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!payment.pdfPath || !fs.existsSync(payment.pdfPath)) {
      const info = await generatePaymentPDF(payment, req.user?.orgId, payment.branchId || null);
      payment.pdfPath = info.filepath;
      payment.pdfGeneratedAt = new Date();
      await payment.save();
    }
    res.download(payment.pdfPath, `Payment-${payment.paymentNumber}.pdf`);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET download URL
router.get('/:id/download-url', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!payment.pdfPath || !fs.existsSync(payment.pdfPath)) {
    const info = await generatePaymentPDF(payment, req.user?.orgId || null, payment.branchId || null);
      payment.pdfPath = info.filepath;
      payment.pdfGeneratedAt = new Date();
      await payment.save();
    }
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    res.json({
      success: true,
      downloadUrl: `${baseUrl}/uploads/payments/${path.basename(payment.pdfPath)}`,
      filename: `Payment-${payment.paymentNumber}.pdf`,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST bulk import
router.post('/bulk-import', importUpload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });
    const paymentsData = JSON.parse(req.body.paymentsData || '[]');
    if (!paymentsData.length) return res.status(400).json({ success: false, error: 'No payment data' });
    const results = { totalProcessed: paymentsData.length, successCount: 0, failedCount: 0, errors: [] };
    for (const [i, pd] of paymentsData.entries()) {
      try {
        pd.paymentNumber = await generatePaymentNumber(req.user?.orgId || null, req.branchIds?.length > 0 ? req.branchIds[0] : null);
        pd.createdBy = req.user?.email || 'import';
        pd.orgId = req.user?.orgId || null;
        pd.branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
        if (!pd.vendorId) pd.vendorId = new mongoose.Types.ObjectId();
        const p = new PaymentMade(pd);
        await p.save();

        const orgId = req.user?.orgId || null;

        // ── STEP 1: Deduct PaymentAccount balance ─────────────────────────────
        if (pd.paidFromAccountId) {
          try {
            const PaymentAccount = mongoose.models.PaymentAccount ||
              mongoose.model('PaymentAccount', new mongoose.Schema({ currentBalance: { type: Number, default: 0 } }, { strict: false }));
            const deductAmt = p.totalAmount || p.amount || 0;
            await PaymentAccount.findByIdAndUpdate(pd.paidFromAccountId, {
              $inc: { currentBalance: -deductAmt }, $set: { updatedAt: new Date() }
            });
          } catch (balErr) {
            console.error(`⚠️ Balance deduction error (bulk import row ${i + 2}):`, balErr.message);
          }
        }

        // ── STEP 2: Apply to bills + COA per bill ─────────────────────────────
        const billsApplied = pd.billsApplied || [];
        for (const ba of billsApplied) {
          if (!ba.billId || !ba.amountApplied || ba.amountApplied <= 0) continue;
          try {
            const Bill = mongoose.models.Bill;
            if (!Bill) continue;
            const bill = await Bill.findById(ba.billId);
            if (!bill) continue;
            bill.payments = bill.payments || [];
            bill.payments.push({ paymentId: p._id, amount: ba.amountApplied, paymentDate: p.paymentDate, paymentMode: p.paymentMode, referenceNumber: p.paymentNumber, recordedBy: pd.createdBy, recordedAt: new Date() });
            bill.amountPaid = (bill.amountPaid || 0) + ba.amountApplied;
            await bill.save();

            // COA: Dr AP / Cr Bank
            const apId = await getSystemAccountId('Accounts Payable', orgId);
            const bankId = pd.paidFromAccountId || await getSystemAccountId('Undeposited Funds', orgId);
            const txnDate = new Date(p.paymentDate);
            if (apId)   await postTransactionToCOA({ accountId: apId,   orgId, date: txnDate, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, description: `Payment ${p.paymentNumber} - ${bill.billNumber}`, referenceType: 'Payment', referenceId: p._id, referenceNumber: p.paymentNumber, debit: ba.amountApplied, credit: 0 });
            if (bankId) await postTransactionToCOA({ accountId: bankId, orgId, date: txnDate, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, description: `Payment ${p.paymentNumber} - ${bill.billNumber}`, referenceType: 'Payment', referenceId: p._id, referenceNumber: p.paymentNumber, debit: 0, credit: ba.amountApplied });
          } catch (billErr) {
            console.error(`⚠️ Bill update error (bulk import row ${i + 2}):`, billErr.message);
          }
        }

        // ── STEP 3: COA for items-based portion ───────────────────────────────
        if (p.items && p.items.length > 0 && p.subTotal > 0) {
          try {
            const [expenseId, apId] = await Promise.all([
              getSystemAccountId('Cost of Goods Sold', orgId),
              getSystemAccountId('Accounts Payable',   orgId),
            ]);
            const txnDate = new Date(p.paymentDate);
            if (expenseId) await postTransactionToCOA({ accountId: expenseId, orgId, date: txnDate, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, description: `Payment Made ${p.paymentNumber} - ${p.vendorName} (items)`, referenceType: 'PaymentMade', referenceId: p._id, referenceNumber: p.paymentNumber, debit: p.subTotal, credit: 0 });
            if (apId)      await postTransactionToCOA({ accountId: apId,      orgId, date: txnDate, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, description: `Payment Made ${p.paymentNumber} - ${p.vendorName} (items)`, referenceType: 'PaymentMade', referenceId: p._id, referenceNumber: p.paymentNumber, debit: 0, credit: p.subTotal });
          } catch (coaErr) {
            console.error(`⚠️ COA post error (bulk import row ${i + 2}):`, coaErr.message);
          }
        }

        console.log(`   ✅ Row ${i + 2}: imported payment ${p.paymentNumber}`);
        results.successCount++;
      } catch (e) {
        results.failedCount++;
        results.errors.push(`Row ${i + 2}: ${e.message}`);
      }
    }
    res.json({ success: true, message: 'Import completed', data: results });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});


// PATCH /:id/mark-sent
router.patch('/:id/mark-sent', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    payment.status = 'RECORDED';
    payment.emailsSent = payment.emailsSent || [];
    payment.emailsSent.push({ sentAt: new Date(), emailType: 'payment_confirmation', markedManually: true });
    payment.updatedBy = req.user?.email || 'system';
    await payment.save();
    res.json({ success: true, message: 'Payment marked as sent', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/payments-made/:id/vendor-phone
// Looks up vendor phone directly from DB — no need to store it on payment
router.get('/:id/vendor-phone', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    }).select('vendorId vendorName');
    if (!payment) {
      return res.status(404).json({ success: false, error: 'Payment not found' });
    }

    // Try billing vendors collection first, then fall back to admin vendors
    const BillingVendor = mongoose.models.BillingVendor ||
      mongoose.model('BillingVendor', new mongoose.Schema({}, { strict: false }));

    const AdminVendor = mongoose.models.Vendor ||
      mongoose.model('Vendor', new mongoose.Schema({}, { strict: false }));

    let phone = '';

    const billingVendor = await BillingVendor.findById(payment.vendorId)
      .select('phone primaryPhone vendorPhone').lean();

    if (billingVendor) {
      phone = billingVendor.phone ?? billingVendor.primaryPhone ?? billingVendor.vendorPhone ?? '';
    }

    // Fallback to admin vendors collection if not found in billing
    if (!phone) {
      const adminVendor = await AdminVendor.findById(payment.vendorId)
        .select('phone primaryPhone vendorPhone').lean();
      if (adminVendor) {
        phone = adminVendor.phone ?? adminVendor.primaryPhone ?? adminVendor.vendorPhone ?? '';
      }
    }

    res.json({
      success: true,
      phone: phone.toString().trim(),
      vendorName: payment.vendorName,
    });

  } catch (err) {
    console.error('Error fetching vendor phone:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;