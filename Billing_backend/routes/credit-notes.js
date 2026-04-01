// ============================================================================
// CREDIT NOTES SYSTEM - COMPLETE WITH MODEL
// ============================================================================
// File: backend/routes/credit-notes.js
// Features:
// ✅ Complete CRUD operations
// ✅ Create from invoice or manual
// ✅ Refund tracking
// ✅ Credit application to future invoices
// ✅ PDF generation
// ✅ Email notifications
// ✅ Import/Export functionality
// ✅ Status management (Open, Closed, Refunded, Void)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const csv = require('csv-parser');
const { Parser } = require('json2csv');


// Import Invoice model — reuse the already-registered model (invoices.js must be required first)
const Invoice = mongoose.models.Invoice ||
  (() => { throw new Error('Invoice model not loaded. Ensure invoices.js is required before credit-notes.js'); })();

// ============================================================================
// MONGOOSE MODEL - CREDIT NOTE SCHEMA
// ============================================================================

const creditNoteSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  creditNoteNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  
  // Customer Information
  customerId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Customer',
    required: true
  },
  customerName: {
    type: String,
    required: true
  },
  customerEmail: String,
  customerPhone: String,
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  
  // Reference Information
  invoiceId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Invoice'
  },
  invoiceNumber: String,
  referenceNumber: String,
  
  // Dates
  creditNoteDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  
  // Reason for Credit Note
  reason: {
    type: String,
    enum: ['Product Returned', 'Order Cancelled', 'Pricing Error', 'Damaged Goods', 'Quality Issue', 'Other'],
    required: true
  },
  reasonDescription: String,
  
  // Items
  items: [{
    itemDetails: {
      type: String,
      required: true
    },
    quantity: {
      type: Number,
      required: true,
      min: 0
    },
    rate: {
      type: Number,
      required: true,
      min: 0
    },
    discount: {
      type: Number,
      default: 0,
      min: 0
    },
    discountType: {
      type: String,
      enum: ['percentage', 'amount'],
      default: 'percentage'
    },
    amount: {
      type: Number,
      required: true
    }
  }],
  
  // Notes
  customerNotes: String,
  internalNotes: String,
  
  // Tax Calculations
  subTotal: {
    type: Number,
    required: true,
    default: 0
  },
  tdsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  tdsAmount: {
    type: Number,
    default: 0
  },
  tcsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  tcsAmount: {
    type: Number,
    default: 0
  },
  gstRate: {
    type: Number,
    default: 18,
    min: 0,
    max: 100
  },
  cgst: {
    type: Number,
    default: 0
  },
  sgst: {
    type: Number,
    default: 0
  },
  igst: {
    type: Number,
    default: 0
  },
  totalAmount: {
    type: Number,
    required: true,
    default: 0
  },
  
  // Credit Status & Usage
  status: {
    type: String,
    enum: ['DRAFT', 'OPEN', 'CLOSED', 'REFUNDED', 'VOID'],
    default: 'DRAFT',
    index: true
  },
  
  creditBalance: {
    type: Number,
    default: 0
  },
  
  creditUsed: {
    type: Number,
    default: 0
  },
  
  // Refund Information
  refunds: [{
    refundId: mongoose.Schema.Types.ObjectId,
    amount: Number,
    refundDate: Date,
    refundMethod: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online']
    },
    referenceNumber: String,
    notes: String,
    recordedBy: String,
    recordedAt: Date
  }],
  
  // Credit Applications (when applied to future invoices)
  creditApplications: [{
    invoiceId: mongoose.Schema.Types.ObjectId,
    invoiceNumber: String,
    amount: Number,
    appliedDate: Date,
    appliedBy: String
  }],
  
  // Email tracking
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['credit_note', 'refund_confirmation']
    }
  }],
  
  // PDF & Files
  pdfPath: String,
  pdfGeneratedAt: Date,
  
  attachments: [{
    filename: String,
    filepath: String,
    uploadedAt: Date
  }],
  
  // Audit fields
  createdBy: {
    type: String,
    required: true
  },
  updatedBy: String,
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// ============================================================================
// PRE-SAVE MIDDLEWARE - AUTO CALCULATIONS
// ============================================================================

creditNoteSchema.pre('save', function() {
  // Calculate subtotal
  this.subTotal = this.items.reduce((sum, item) => sum + item.amount, 0);
  
  // Calculate TDS
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
  
  // Calculate TCS
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
  
  // Calculate GST
  const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;
  
  this.cgst = gstAmount / 2;
  this.sgst = gstAmount / 2;
  this.igst = 0;
  
  // Calculate total
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  
  // Calculate credit balance
  const totalRefunded = this.refunds.reduce((sum, refund) => sum + refund.amount, 0);
  const totalApplied = this.creditApplications.reduce((sum, app) => sum + app.amount, 0);
  
  this.creditUsed = totalRefunded + totalApplied;
  this.creditBalance = this.totalAmount - this.creditUsed;
  
  // Auto-update status
  if (this.creditBalance <= 0 && this.status === 'OPEN') {
    this.status = 'CLOSED';
  }
});

// Create indexes
creditNoteSchema.index({ customerId: 1, creditNoteDate: -1 });
creditNoteSchema.index({ status: 1, creditNoteDate: -1 });
creditNoteSchema.index({ createdAt: -1 });

const CreditNote = mongoose.models.CreditNote || mongoose.model('CreditNote', creditNoteSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate credit note number
async function generateCreditNoteNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(CreditNote, 'creditNoteNumber', 'CN', orgId);
}

// Calculate item amount
function calculateItemAmount(item) {
  let amount = item.quantity * item.rate;
  
  if (item.discount > 0) {
    if (item.discountType === 'percentage') {
      amount = amount - (amount * item.discount / 100);
    } else {
      amount = amount - item.discount;
    }
  }
  
  return Math.round(amount * 100) / 100;
}

// Logo path resolver
let CACHED_LOGO_PATH = null;

function findLogoPath(orgId = null) {
  // Check org-specific logo first
  if (orgId) {
    const orgLogoDir = path.join(__dirname, '..', 'uploads', 'org-logos');
    if (fs.existsSync(orgLogoDir)) {
      try {
        const files = fs.readdirSync(orgLogoDir);
        const match = files.find(f => f.startsWith(`org-${orgId}-`));
        if (match) {
          const fullPath = path.join(orgLogoDir, match);
          if (fs.existsSync(fullPath)) return fullPath;
        }
      } catch (_) {}
    }
  }
  const possiblePaths = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
  ];
  
  for (const testPath of possiblePaths) {
    try {
      if (fs.existsSync(testPath)) {
        return testPath;
      }
    } catch (err) {
      // Continue
    }
  }
  
  return null;
}

function getLogoPath(orgId = null) {
  if (orgId) return findLogoPath(orgId);
  if (!CACHED_LOGO_PATH) {
    CACHED_LOGO_PATH = findLogoPath();
  }
  return CACHED_LOGO_PATH;
}

// Number to words (for PDF amount in words)
function numberToWords(n) {
  const a = ['','One','Two','Three','Four','Five','Six','Seven','Eight','Nine','Ten','Eleven','Twelve','Thirteen','Fourteen','Fifteen','Sixteen','Seventeen','Eighteen','Nineteen'];
  const b = ['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];
  function w(x) {
    if (x < 20) return a[x];
    if (x < 100) return b[Math.floor(x/10)] + (x%10 ? ' ' + a[x%10] : '');
    return a[Math.floor(x/100)] + ' Hundred' + (x%100 ? ' ' + w(x%100) : '');
  }
  if (!n) return 'Zero';
  let s = '';
  if (n >= 10000000) { s += w(Math.floor(n/10000000)) + ' Crore '; n %= 10000000; }
  if (n >= 100000)   { s += w(Math.floor(n/100000))   + ' Lakh ';  n %= 100000;  }
  if (n >= 1000)     { s += w(Math.floor(n/1000))     + ' Thousand '; n %= 1000; }
  if (n > 0)           s += w(n);
  return s.trim();
}

// ============================================================================
// PDF GENERATION - CREDIT NOTE (invoices.js style)
// ============================================================================

async function generateCreditNotePDF(creditNote, orgId) {
  return new Promise(async (resolve, reject) => {
    try {
      console.log('📄 Generating Credit Note PDF:', creditNote.creditNoteNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'credit-notes');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `credit-note-${creditNote.creditNoteNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      let orgName = 'Your Company', orgGST = '', orgAddr = '', orgEmail = '', orgPhone = '', orgTagline = '';
      try {
        const OrgModel = mongoose.models.Organization || mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
        const org = await OrgModel.findOne({ orgId }).lean();
        if (org) { orgName = org.orgName || orgName; orgGST = org.gstNumber || ''; orgAddr = org.address || ''; orgEmail = org.email || ''; orgPhone = org.phone || ''; orgTagline = org.tagline || org.slogan || ''; }
      } catch (e) { console.warn('⚠️ Org fetch failed:', e.message); }

      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);
      const pageW = 515;

      // Header
      doc.rect(40, 30, pageW, 90).fill('#0f1e3d');
      const logoPath = getLogoPath(orgId);
      let logoLoaded = false;
      if (logoPath) { try { doc.image(logoPath, 44, 35, { width: 75, height: 60, fit: [75, 60] }); logoLoaded = true; } catch (e) {} }
      const textX = logoLoaded ? 126 : 50;
      doc.fontSize(12).fillColor('#ffffff').font('Helvetica-Bold').text(orgName.toUpperCase(), textX, 40, { width: 200 });
      doc.fontSize(7).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text('BILLING & FINANCE', textX, 56, { width: 200, characterSpacing: 1 });
      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)');
      let cY = 68; contactLines.forEach(l => { doc.text(l, textX, cY, { width: 240 }); cY += 9; });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').font('Helvetica-Bold').text('CREDIT NOTE', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold').text(creditNote.creditNoteNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.8)').font('Helvetica').text(`Date: ${new Date(creditNote.creditNoteDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold').text(`${(creditNote.status || 'DRAFT').replace(/_/g,' ')}`, 380, 92, { width: 170, align: 'right' });

      // Meta boxes
      const metaY = 132, metaBoxW = pageW / 2;
      const metas = [
        { label: 'Credit To', val: creditNote.customerName || 'N/A', sub: [creditNote.billingAddress?.street, creditNote.billingAddress?.city, creditNote.customerEmail, creditNote.customerPhone].filter(Boolean).join(' | ') },
        { label: 'Credit Note Details', val: `Ref: ${creditNote.invoiceNumber || creditNote.referenceNumber || 'N/A'}`, sub: `Reason: ${creditNote.reason || 'N/A'}` },
      ];
      metas.forEach((m, i) => {
        const bx = 40 + i * metaBoxW;
        doc.rect(bx, metaY, metaBoxW, 46).fillAndStroke('#f7f9fc', '#dde4ef');
        doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold').text(m.label.toUpperCase(), bx + 8, metaY + 7, { width: metaBoxW - 16, characterSpacing: 0.8 });
        doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold').text(m.val, bx + 8, metaY + 18, { width: metaBoxW - 16, ellipsis: true });
        doc.fontSize(7).fillColor('#000000').font('Helvetica').text(m.sub, bx + 8, metaY + 30, { width: metaBoxW - 16, ellipsis: true });
      });

      // Items table
      const tableY = metaY + 58;
      doc.rect(40, tableY, pageW, 22).fill('#0f1e3d');
      doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
      doc.text('#', 48, tableY + 7, { width: 20 }); doc.text('DESCRIPTION', 72, tableY + 7, { width: 200 });
      doc.text('QTY', 275, tableY + 7, { width: 60, align: 'center' }); doc.text('RATE', 340, tableY + 7, { width: 80, align: 'right' }); doc.text('AMOUNT', 420, tableY + 7, { width: 90, align: 'right' });
      let rowY = tableY + 22;
      creditNote.items.forEach((item, idx) => {
        const rowH = 24;
        doc.rect(40, rowY, pageW, rowH).fill(idx % 2 === 0 ? '#ffffff' : '#f7f9fc');
        doc.rect(40, rowY, pageW, rowH).lineWidth(1.5).strokeColor('#000000').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica-Bold').text(String(idx + 1), 48, rowY + 8, { width: 20 });
        doc.font('Helvetica').text(item.itemDetails || 'N/A', 72, rowY + 8, { width: 200, ellipsis: true });
        doc.text(String(item.quantity || 0), 275, rowY + 8, { width: 60, align: 'center' });
        doc.text(`Rs.${(item.rate || 0).toFixed(2)}`, 340, rowY + 8, { width: 80, align: 'right' });
        doc.font('Helvetica-Bold').text(`Rs.${(item.amount || 0).toFixed(2)}`, 420, rowY + 8, { width: 90, align: 'right' });
        rowY += rowH;
      });

      // Totals
      const totalsX = 355, totalsW = 200, labelX = totalsX, amountX = totalsX + totalsW;
      let totalsY = rowY + 16;
      const tRow = (label, amount, bold = false) => {
        doc.fontSize(8).fillColor('#5e6e84').font(bold ? 'Helvetica-Bold' : 'Helvetica').text(label, labelX, totalsY, { width: 120 });
        doc.fillColor('#000000').font(bold ? 'Helvetica-Bold' : 'Helvetica').text(amount, labelX + 120, totalsY, { width: 80, align: 'right' });
        doc.moveTo(labelX, totalsY + 11).lineTo(amountX, totalsY + 11).lineWidth(0.5).strokeColor('#dde4ef').dash(2, { space: 2 }).stroke().undash();
        totalsY += 14;
      };
      tRow('Subtotal:', `Rs. ${(creditNote.subTotal || 0).toFixed(2)}`);
      if (creditNote.cgst > 0) tRow(`CGST (${creditNote.gstRate / 2}%):`, `Rs. ${creditNote.cgst.toFixed(2)}`);
      if (creditNote.sgst > 0) tRow(`SGST (${creditNote.gstRate / 2}%):`, `Rs. ${creditNote.sgst.toFixed(2)}`);
      if (creditNote.igst > 0) tRow(`IGST (${creditNote.gstRate}%):`, `Rs. ${creditNote.igst.toFixed(2)}`);
      if (creditNote.tdsAmount > 0) tRow('TDS Deducted:', `- Rs. ${creditNote.tdsAmount.toFixed(2)}`);
      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text('Credit Amount', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold').text(`Rs. ${(creditNote.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;
      if ((creditNote.creditUsed || 0) > 0) tRow('Credit Used:', `Rs. ${creditNote.creditUsed.toFixed(2)}`);
      if ((creditNote.creditBalance || 0) > 0) tRow('Available Balance:', `Rs. ${creditNote.creditBalance.toFixed(2)}`, true);

      // Amount in words
      const wordsY = totalsY + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold').text(`In Words: ${numberToWords(Math.round(creditNote.totalAmount || 0))} Only`, 48, wordsY + 5, { width: pageW - 16 });

      // Notes
      if (creditNote.customerNotes || creditNote.reasonDescription) {
        const nY = wordsY + 28;
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold').text('NOTES', 40, nY, { characterSpacing: 0.8 });
        doc.moveTo(40, nY + 9).lineTo(555, nY + 9).lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica').text(creditNote.reasonDescription || creditNote.customerNotes, 40, nY + 14, { width: pageW });
      }

      // T&C
      if (creditNote.termsAndConditions) {
        const tcY = 660;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold').text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica').text(creditNote.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // Footer
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY).lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica').text(`${orgName} · ${orgGST ? 'GSTIN: ' + orgGST + ' · ' : ''}${creditNote.creditNoteNumber}`, 40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`, 40, footY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => { console.log(`✅ Credit Note PDF generated: ${filename}`); resolve({ filename, filepath, relativePath: `/uploads/credit-notes/${filename}` }); });
      stream.on('error', reject);
    } catch (error) { console.error('❌ PDF generation error:', error); reject(error); }
  });
}

// ============================================================================
// EMAIL SERVICE
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD
  }
});

async function sendCreditNoteEmail(creditNote, pdfPath, orgId) {
  console.log('📧 Sending credit note email to:', creditNote.customerEmail);

  let orgName = '', orgGST = '', orgPhone = '', orgEmail = '', orgData = null;
  try {
    const OrgModel = mongoose.models.Organization || mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    orgData = await OrgModel.findOne({ orgId }).lean();
    if (orgData) { orgName = orgData.orgName || ''; orgGST = orgData.gstNumber || ''; orgPhone = orgData.phone || ''; orgEmail = orgData.email || ''; }
  } catch (_) {}

  const dateStr = new Date(creditNote.creditNoteDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });

  const emailHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Credit Note ${creditNote.creditNoteNumber}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }
    .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }
    .header { background: #0f1e3d; padding: 24px 32px; }
    .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }
    .header p  { color: rgba(255,255,255,0.7); font-size: 11px; letter-spacing: 0.5px; }
    .header .inv-num { color: #fff; font-size: 14px; font-weight: bold; margin-top: 8px; }
    .body { padding: 28px 32px; }
    .greeting { font-size: 14px; color: #222; margin-bottom: 18px; }
    .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase; letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0; padding-bottom: 6px; margin: 22px 0 12px; }
    table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }
    table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }
    table.detail td:first-child { color: #555; width: 160px; }
    table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }
    .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222; border-bottom: none; padding-top: 10px; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706; padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px; font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Credit Note</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${creditNote.creditNoteNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${creditNote.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached credit note <strong>${creditNote.creditNoteNumber}</strong> issued against your account.
      ${creditNote.invoiceNumber ? `This credit note is against invoice <strong>${creditNote.invoiceNumber}</strong>.` : ''}
    </p>
    <div class="section-title">Credit Note Details</div>
    <table class="detail">
      <tr><td>Credit Note #</td><td>${creditNote.creditNoteNumber}</td></tr>
      <tr><td>Date</td>         <td>${dateStr}</td></tr>
      ${creditNote.invoiceNumber ? `<tr><td>Against Invoice</td><td>${creditNote.invoiceNumber}</td></tr>` : ''}
      <tr><td>Reason</td>       <td>${creditNote.reason || ''}</td></tr>
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(creditNote.subTotal || 0).toFixed(2)}</td></tr>
      ${creditNote.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${creditNote.cgst.toFixed(2)}</td></tr>` : ''}
      ${creditNote.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${creditNote.sgst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Credit Amount</td><td>Rs.${(creditNote.totalAmount || 0).toFixed(2)}</td></tr>
      ${(creditNote.creditBalance || 0) > 0 ? `<tr><td>Available Balance</td><td style="color:#27ae60;">Rs.${creditNote.creditBalance.toFixed(2)}</td></tr>` : ''}
    </table>
    ${creditNote.customerNotes || creditNote.reasonDescription ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${creditNote.reasonDescription || creditNote.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The credit note PDF is attached to this email for your records.<br>
      Please contact us if you have any questions.
    </p>
  </div>
  <div class="footer">
    <strong>Thank you for your business.</strong><br>
    ${orgData?.orgName || ''} &nbsp;|&nbsp; ${orgData?.email || process.env.SMTP_USER || ''} &nbsp;|&nbsp; This is a system-generated email.
  </div>
</div>
</body>
</html>`;

  const mailOptions = {
    from: `"Accounts" <${process.env.SMTP_USER}>`,
    to: creditNote.customerEmail,
    subject: `Credit Note ${creditNote.creditNoteNumber} — Rs.${(creditNote.totalAmount || 0).toFixed(2)}`,
    html: emailHtml,
    attachments: [{ filename: `CreditNote-${creditNote.creditNoteNumber}.pdf`, path: pdfPath }]
  };

  console.log('   📤 Sending credit note email...');
  const result = await emailTransporter.sendMail(mailOptions);
  console.log('   ✅ Email sent! Message ID:', result.messageId);
  return result;
}

// ============================================================================
// API ROUTES
// ============================================================================

// GET all credit notes with filters
router.get('/', async (req, res) => {
  try {
    const { status, customerId, fromDate, toDate, page = 1, limit = 20, search } = req.query;
    
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.creditNoteDate = {};
      if (fromDate) query.creditNoteDate.$gte = new Date(fromDate);
      if (toDate) query.creditNoteDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { creditNoteNumber: new RegExp(search, 'i') },
        { customerName: new RegExp(search, 'i') },
        { invoiceNumber: new RegExp(search, 'i') }
      ];
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const creditNotes = await CreditNote.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await CreditNote.countDocuments(query);
    
    res.json({
      success: true,
      data: creditNotes,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching credit notes:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET statistics
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const stats = await CreditNote.aggregate([
      { $match: orgFilter },
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalBalance: { $sum: '$creditBalance' },
          totalUsed: { $sum: '$creditUsed' }
        }
      }
    ]);
    
    const overallStats = {
      totalCreditNotes: 0,
      totalCreditAmount: 0,
      totalCreditBalance: 0,
      totalCreditUsed: 0,
      byStatus: {}
    };
    
    stats.forEach(stat => {
      overallStats.totalCreditNotes += stat.count;
      overallStats.totalCreditAmount += stat.totalAmount;
      overallStats.totalCreditBalance += stat.totalBalance;
      overallStats.totalCreditUsed += stat.totalUsed;
      overallStats.byStatus[stat._id] = {
        count: stat.count,
        amount: stat.totalAmount
      };
    });
    
    res.json({ success: true, data: overallStats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET single credit note
router.get('/:id', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    res.json({ success: true, data: creditNote });
  } catch (error) {
    console.error('Error fetching credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// CREATE new credit note
// CREATE new credit note
router.post('/', async (req, res) => {
  try {
    const creditNoteData = req.body;
    
    // Handle customer ID
    if (creditNoteData.customerId) {
      if (typeof creditNoteData.customerId === 'string') {
        if (mongoose.Types.ObjectId.isValid(creditNoteData.customerId)) {
          creditNoteData.customerId = new mongoose.Types.ObjectId(creditNoteData.customerId);
        } else {
          creditNoteData.customerId = new mongoose.Types.ObjectId();
        }
      }
    } else {
      creditNoteData.customerId = new mongoose.Types.ObjectId();
    }
    
    // Generate credit note number
    if (!creditNoteData.creditNoteNumber) {
      creditNoteData.creditNoteNumber = await generateCreditNoteNumber(req.user?.orgId || null);
    }
    
    // Calculate item amounts
    if (creditNoteData.items) {
      creditNoteData.items = creditNoteData.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    creditNoteData.createdBy = req.user?.email || req.user?.uid || 'system';
    creditNoteData.orgId = req.user?.orgId || null;
    const creditNote = new CreditNote(creditNoteData);
    await creditNote.save();
    
    console.log(`✅ Credit Note created: ${creditNote.creditNoteNumber}`);

    // ✅ COA Posting
    // Credit Note = reverse of invoice
    // Debit: Sales (reverse revenue)
    // Credit: Accounts Receivable (reduce what customer owes)
    try {
      const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

      const currentOrgId = req.user?.orgId || null;
      const [salesId, arId] = await Promise.all([
        ChartOfAccount.findOne({ accountName: 'Sales', isSystemAccount: true, orgId: currentOrgId })
          .select('_id').lean().then(a => a?._id),
        ChartOfAccount.findOne({ accountName: 'Accounts Receivable', isSystemAccount: true, orgId: currentOrgId })
          .select('_id').lean().then(a => a?._id),
      ]);

      const txnDate = new Date(creditNote.creditNoteDate);

      // Debit Sales (reverse revenue)
      if (salesId) await postTransactionToCOA({
        accountId:       salesId,
        orgId:           currentOrgId,
        date:            txnDate,
        description:     `Credit Note ${creditNote.creditNoteNumber} - ${creditNote.customerName}`,
        referenceType:   'Credit Note',
        referenceId:     creditNote._id,
        referenceNumber: creditNote.creditNoteNumber,
        debit:           creditNote.subTotal,
        credit:          0,
      });

      // Credit Accounts Receivable (reduce AR)
      if (arId) await postTransactionToCOA({
        accountId:       arId,
        orgId:           currentOrgId,
        date:            txnDate,
        description:     `Credit Note ${creditNote.creditNoteNumber} - ${creditNote.customerName}`,
        referenceType:   'Credit Note',
        referenceId:     creditNote._id,
        referenceNumber: creditNote.creditNoteNumber,
        debit:           0,
        credit:          creditNote.totalAmount,
      });

      // Also reverse Tax Payable if GST exists
      if (creditNote.cgst + creditNote.sgst > 0) {
        const taxId = await ChartOfAccount.findOne({
          accountName: 'Tax Payable',
          isSystemAccount: true,
          orgId: currentOrgId
        }).select('_id').lean().then(a => a?._id);

        if (taxId) await postTransactionToCOA({
          accountId:       taxId,
          orgId:           currentOrgId,
          date:            txnDate,
          description:     `GST Reversal - Credit Note ${creditNote.creditNoteNumber}`,
          referenceType:   'Credit Note',
          referenceId:     creditNote._id,
          referenceNumber: creditNote.creditNoteNumber,
          debit:           creditNote.cgst + creditNote.sgst,
          credit:          0,
        });
      }

      console.log(`✅ COA posted for credit note: ${creditNote.creditNoteNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA post error (credit note):', coaErr.message);
      // Non-critical — credit note already saved
    }
    
    res.status(201).json({
      success: true,
      message: 'Credit note created successfully',
      data: creditNote
    });
  } catch (error) {
    console.error('Error creating credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// UPDATE credit note
router.put('/:id', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (creditNote.status === 'CLOSED' || creditNote.status === 'VOID') {
      return res.status(400).json({
        success: false,
        error: 'Cannot edit closed or void credit notes'
      });
    }
    
    const updates = req.body;
    
    // Calculate item amounts
    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    Object.assign(creditNote, updates);
    await creditNote.save();
    
    console.log(`✅ Credit Note updated: ${creditNote.creditNoteNumber}`);
    
    res.json({
      success: true,
      message: 'Credit note updated successfully',
      data: creditNote
    });
  } catch (error) {
    console.error('Error updating credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// SEND credit note via email
router.post('/:id/send', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (!creditNote.customerEmail) {
      return res.status(400).json({ success: false, error: 'Customer email not found' });
    }
    
    // Generate PDF if not exists
    let pdfInfo;
    if (!creditNote.pdfPath || !fs.existsSync(creditNote.pdfPath)) {
      pdfInfo = await generateCreditNotePDF(creditNote, req.user?.orgId);
      creditNote.pdfPath = pdfInfo.filepath;
      creditNote.pdfGeneratedAt = new Date();
    }
    
    // Send email
    await sendCreditNoteEmail(creditNote, creditNote.pdfPath, req.user?.orgId);
    
    // Update status
    if (creditNote.status === 'DRAFT') {
      creditNote.status = 'OPEN';
    }
    
    creditNote.emailsSent.push({
      sentTo: creditNote.customerEmail,
      sentAt: new Date(),
      emailType: 'credit_note'
    });
    
    await creditNote.save();
    
    console.log(`✅ Credit Note sent: ${creditNote.creditNoteNumber}`);
    
    res.json({
      success: true,
      message: 'Credit note sent successfully',
      data: creditNote
    });
  } catch (error) {
    console.error('Error sending credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// RECORD refund
router.post('/:id/refund', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    const { amount, refundDate, refundMethod, referenceNumber, notes } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid refund amount' });
    }
    
    if (creditNote.creditBalance < amount) {
      return res.status(400).json({
        success: false,
        error: `Refund amount exceeds available balance (₹${creditNote.creditBalance.toFixed(2)})`
      });
    }
    
    const refund = {
      refundId: new mongoose.Types.ObjectId(),
      amount: parseFloat(amount),
      refundDate: refundDate ? new Date(refundDate) : new Date(),
      refundMethod: refundMethod || 'Bank Transfer',
      referenceNumber,
      notes,
      recordedBy: req.user?.email || req.user?.uid || 'system',
      recordedAt: new Date()
    };
    
    creditNote.refunds.push(refund);
    await creditNote.save();
    
    console.log(`✅ Refund recorded: ${creditNote.creditNoteNumber} - ₹${amount}`);
    
    res.json({
      success: true,
      message: 'Refund recorded successfully',
      data: {
        creditNote,
        refund
      }
    });
  } catch (error) {
    console.error('Error recording refund:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// APPLY credit to invoice
// APPLY credit to invoice
router.post('/:id/apply', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }

    // Check credit note status
    if (creditNote.status === 'VOID' || creditNote.status === 'CLOSED') {
      return res.status(400).json({
        success: false,
        error: `Cannot apply a ${creditNote.status} credit note`
      });
    }

    const { invoiceId, invoiceNumber, amount } = req.body;

    // Validate amount
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid amount' });
    }

    // Check available balance
    if (creditNote.creditBalance < amount) {
      return res.status(400).json({
        success: false,
        error: `Amount exceeds available balance (₹${creditNote.creditBalance.toFixed(2)})`
      });
    }

    // ================================================================
    // STEP 1 — Find and validate the invoice
    // ================================================================
    let invoice = null;
    if (invoiceId && mongoose.Types.ObjectId.isValid(invoiceId)) {
      invoice = await Invoice.findById(invoiceId);
    }

    // If not found by ID, try by invoice number
    if (!invoice && invoiceNumber) {
      invoice = await mongoose.model('Invoice').findOne({ invoiceNumber });
    }

    if (!invoice) {
      return res.status(404).json({
        success: false,
        error: `Invoice ${invoiceNumber || invoiceId} not found`
      });
    }

    // Check invoice belongs to same customer (soft check — prefer customerId, fall back to name)
    if (invoice.customerId && creditNote.customerId &&
        invoice.customerId.toString() !== creditNote.customerId.toString()) {
      // Both have IDs and they don't match — also allow name match as fallback
      if (invoice.customerName?.trim().toLowerCase() !==
          creditNote.customerName?.trim().toLowerCase()) {
        return res.status(400).json({
          success: false,
          error: 'Credit note and invoice must belong to the same customer'
        });
      }
    }

    // Check invoice has amount due
    if (invoice.amountDue <= 0) {
      return res.status(400).json({
        success: false,
        error: `Invoice ${invoice.invoiceNumber} is already fully paid`
      });
    }

    // Cap amount to invoice's amountDue
    const applyAmount = Math.min(parseFloat(amount), invoice.amountDue);

    // ================================================================
    // STEP 2 — Update Credit Note
    // ================================================================
    const application = {
      invoiceId:   invoice._id,
      invoiceNumber: invoice.invoiceNumber,
      amount:      applyAmount,
      appliedDate: new Date(),
      appliedBy:   req.user?.email || req.user?.uid || 'system'
    };

    creditNote.creditApplications.push(application);
    await creditNote.save(); // pre-save recalculates creditUsed + creditBalance

    console.log(`✅ Credit application saved: ${creditNote.creditNoteNumber} → ${invoice.invoiceNumber} ₹${applyAmount}`);

    // ================================================================
    // STEP 3 — Update Invoice amountPaid, amountDue, status
    // ================================================================
    const newAmountPaid = (invoice.amountPaid || 0) + applyAmount;
    const newAmountDue  = invoice.totalAmount - newAmountPaid;

    // Determine new invoice status
    let newStatus = invoice.status;
    if (newAmountDue <= 0) {
      newStatus = 'PAID';
    } else if (newAmountPaid > 0 && newAmountDue > 0) {
      newStatus = 'PARTIALLY_PAID';
    }

    // Add payment record to invoice
    const paymentRecord = {
      paymentId:       new mongoose.Types.ObjectId(),
      amount:          applyAmount,
      paymentDate:     new Date(),
      paymentMethod:   'Credit Note',
      referenceNumber: creditNote.creditNoteNumber,
      notes:           `Credit Note ${creditNote.creditNoteNumber} applied`,
      recordedAt:      new Date()
    };

    await Invoice.findByIdAndUpdate(
      invoice._id,
      {
        $set: {
          amountPaid: newAmountPaid,
          amountDue:  newAmountDue,
          status:     newStatus,
          updatedAt:  new Date()
        },
        $push: { payments: paymentRecord }
      },
      { new: true }
    );

    console.log(`✅ Invoice updated: ${invoice.invoiceNumber} — Paid ₹${newAmountPaid}, Due ₹${newAmountDue}, Status: ${newStatus}`);

    // ================================================================
    // STEP 4 — COA Posting
    // No new COA entry needed here because:
    // - When CN was created: Sales debited + AR credited already
    // - The AR reduction already happened at CN creation
    // We just log it for clarity
    // ================================================================
    console.log(`✅ COA already handled at Credit Note creation — no additional entry needed`);

    // ================================================================
    // STEP 5 — Return response
    // ================================================================
    res.json({
      success: true,
      message: `Credit of ₹${applyAmount} applied to ${invoice.invoiceNumber} successfully`,
      data: {
        creditNote: {
          creditNoteNumber: creditNote.creditNoteNumber,
          totalAmount:      creditNote.totalAmount,
          creditUsed:       creditNote.creditUsed,
          creditBalance:    creditNote.creditBalance,
          status:           creditNote.status,
        },
        invoice: {
          invoiceNumber: invoice.invoiceNumber,
          totalAmount:   invoice.totalAmount,
          amountPaid:    newAmountPaid,
          amountDue:     newAmountDue,
          status:        newStatus,
        },
        application,
      }
    });

  } catch (error) {
    console.error('Error applying credit:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});


// DOWNLOAD PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (!creditNote.pdfPath || !fs.existsSync(creditNote.pdfPath)) {
      const pdfInfo = await generateCreditNotePDF(creditNote, req.user?.orgId);
      creditNote.pdfPath = pdfInfo.filepath;
      creditNote.pdfGeneratedAt = new Date();
      await creditNote.save();
    }
    
    res.download(creditNote.pdfPath, `CreditNote-${creditNote.creditNoteNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET PDF download URL
router.get('/:id/download-url', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (!creditNote.pdfPath || !fs.existsSync(creditNote.pdfPath)) {
      const pdfInfo = await generateCreditNotePDF(creditNote, req.user?.orgId);
      creditNote.pdfPath = pdfInfo.filepath;
      creditNote.pdfGeneratedAt = new Date();
      await creditNote.save();
    }
    
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    const downloadUrl = `${baseUrl}/uploads/credit-notes/${path.basename(creditNote.pdfPath)}`;
    
    res.json({
      success: true,
      downloadUrl: downloadUrl,
      filename: `CreditNote-${creditNote.creditNoteNumber}.pdf`
    });
  } catch (error) {
    console.error('Error generating PDF URL:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/credit-notes/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!creditNote) return res.status(404).json({ success: false, error: 'Credit note not found' });
    const OrgModel = mongoose.models.Organization || mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();
    const orgName = org?.orgName || ''; const orgGST = org?.gstNumber || ''; const orgPhone = org?.phone || ''; const orgEmail = org?.email || '';
    const dateStr = new Date(creditNote.creditNoteDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Credit Note ${creditNote.creditNoteNumber}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }
    .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }
    .header { background: #0f1e3d; padding: 24px 32px; }
    .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }
    .header p  { color: rgba(255,255,255,0.7); font-size: 11px; letter-spacing: 0.5px; }
    .header .inv-num { color: #fff; font-size: 14px; font-weight: bold; margin-top: 8px; }
    .body { padding: 28px 32px; }
    .greeting { font-size: 14px; color: #222; margin-bottom: 18px; }
    .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase; letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0; padding-bottom: 6px; margin: 22px 0 12px; }
    table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }
    table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }
    table.detail td:first-child { color: #555; width: 160px; }
    table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }
    .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222; border-bottom: none; padding-top: 10px; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706; padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px; font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Credit Note</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${creditNote.creditNoteNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${creditNote.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached credit note <strong>${creditNote.creditNoteNumber}</strong> issued against your account.
      ${creditNote.invoiceNumber ? `This credit note is against invoice <strong>${creditNote.invoiceNumber}</strong>.` : ''}
    </p>
    <div class="section-title">Credit Note Details</div>
    <table class="detail">
      <tr><td>Credit Note #</td><td>${creditNote.creditNoteNumber}</td></tr>
      <tr><td>Date</td>         <td>${dateStr}</td></tr>
      ${creditNote.invoiceNumber ? `<tr><td>Against Invoice</td><td>${creditNote.invoiceNumber}</td></tr>` : ''}
      <tr><td>Reason</td>       <td>${creditNote.reason || ''}</td></tr>
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(creditNote.subTotal || 0).toFixed(2)}</td></tr>
      ${creditNote.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${creditNote.cgst.toFixed(2)}</td></tr>` : ''}
      ${creditNote.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${creditNote.sgst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Credit Amount</td><td>Rs.${(creditNote.totalAmount || 0).toFixed(2)}</td></tr>
      ${(creditNote.creditBalance || 0) > 0 ? `<tr><td>Available Balance</td><td style="color:#27ae60;">Rs.${creditNote.creditBalance.toFixed(2)}</td></tr>` : ''}
    </table>
    ${creditNote.customerNotes || creditNote.reasonDescription ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${creditNote.reasonDescription || creditNote.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The credit note PDF is attached to this email for your records.<br>
      Please contact us if you have any questions.
    </p>
  </div>
  <div class="footer">
    <strong>Thank you for your business.</strong><br>
    ${orgName} &nbsp;|&nbsp; ${orgEmail} &nbsp;|&nbsp; This is a system-generated email.
  </div>
</div>
</body>
</html>`;
    res.json({ success: true, data: { subject: `Credit Note ${creditNote.creditNoteNumber} — Rs.${(creditNote.totalAmount || 0).toFixed(2)}`, html, to: creditNote.customerEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE credit note (only drafts)
router.delete('/:id', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    if (creditNote.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft credit notes can be deleted'
      });
    }
    
    await creditNote.deleteOne();
    
    console.log(`✅ Credit Note deleted: ${creditNote.creditNoteNumber}`);
    
    res.json({
      success: true,
      message: 'Credit note deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting credit note:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// IMPORT/EXPORT ROUTES
// ============================================================================

// Configure multer for CSV upload
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const uploadDir = path.join(__dirname, '..', 'uploads', 'temp');
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }
      cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
      cb(null, `import-${Date.now()}-${file.originalname}`);
    }
  }),
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'text/csv' || file.originalname.endsWith('.csv')) {
      cb(null, true);
    } else {
      cb(new Error('Only CSV files are allowed'));
    }
  }
});

// DOWNLOAD import template
router.get('/template/download', async (req, res) => {
  try {
    const templateData = [
      {
        'Customer Name': 'John Doe',
        'Customer Email': 'john@example.com',
        'Customer Phone': '+91 9876543210',
        'Invoice Number': 'INV-2501-0001',
        'Credit Note Date': '2025-01-15',
        'Reason': 'Product Returned',
        'Reason Description': 'Customer returned defective product',
        'Item Details': 'Laptop Dell Inspiron 15',
        'Quantity': '1',
        'Rate': '45000',
        'Discount': '0',
        'Discount Type': 'percentage',
        'GST Rate': '18',
        'Customer Notes': 'Refund processed to original payment method'
      },
      {
        'Customer Name': 'Jane Smith',
        'Customer Email': 'jane@example.com',
        'Customer Phone': '+91 8765432109',
        'Invoice Number': 'INV-2501-0002',
        'Credit Note Date': '2025-01-16',
        'Reason': 'Order Cancelled',
        'Reason Description': 'Order cancelled by customer before delivery',
        'Item Details': 'Office Chair Premium',
        'Quantity': '2',
        'Rate': '8500',
        'Discount': '5',
        'Discount Type': 'percentage',
        'GST Rate': '18',
        'Customer Notes': 'Credit available for future purchases'
      }
    ];
    
    const parser = new Parser();
    const csv = parser.parse(templateData);
    
    res.header('Content-Type', 'text/csv');
    res.header('Content-Disposition', 'attachment; filename=credit_notes_import_template.csv');
    res.send(csv);
    
    console.log('✅ Template downloaded');
  } catch (error) {
    console.error('Error generating template:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// IMPORT credit notes from CSV
router.post('/import', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No file uploaded' });
    }
    
    console.log('📥 Processing import file:', req.file.filename);
    
    const results = [];
    const errors = [];
    let lineNumber = 1;
    
    // Parse CSV
    const stream = fs.createReadStream(req.file.path)
      .pipe(csv());
    
    for await (const row of stream) {
      lineNumber++;
      
      try {
        // Validate required fields
        if (!row['Customer Name'] || !row['Customer Email']) {
          throw new Error('Customer Name and Email are required');
        }
        
        // Prepare credit note data
        const creditNoteData = {
          customerId: new mongoose.Types.ObjectId(),
          customerName: row['Customer Name'].trim(),
          customerEmail: row['Customer Email'].trim(),
          customerPhone: row['Customer Phone']?.trim(),
          invoiceNumber: row['Invoice Number']?.trim(),
          creditNoteDate: row['Credit Note Date'] ? new Date(row['Credit Note Date']) : new Date(),
          reason: row['Reason']?.trim() || 'Other',
          reasonDescription: row['Reason Description']?.trim(),
          items: [{
            itemDetails: row['Item Details']?.trim() || 'Item',
            quantity: parseFloat(row['Quantity']) || 1,
            rate: parseFloat(row['Rate']) || 0,
            discount: parseFloat(row['Discount']) || 0,
            discountType: row['Discount Type']?.trim() || 'percentage',
            amount: 0 // Will be calculated by pre-save
          }],
          gstRate: parseFloat(row['GST Rate']) || 18,
          customerNotes: row['Customer Notes']?.trim(),
          status: 'OPEN',
          createdBy: req.user?.email || 'import',
          orgId: req.user?.orgId || null,
        };
        
        // Calculate item amount
        creditNoteData.items[0].amount = calculateItemAmount(creditNoteData.items[0]);
        
        // Generate credit note number
        creditNoteData.creditNoteNumber = await generateCreditNoteNumber(req.user?.orgId || null);
        
        // Create credit note
        const creditNote = new CreditNote(creditNoteData);
        await creditNote.save();
        
        results.push({
          line: lineNumber,
          creditNoteNumber: creditNote.creditNoteNumber,
          customerName: creditNote.customerName,
          amount: creditNote.totalAmount
        });
        
      } catch (error) {
        errors.push({
          line: lineNumber,
          error: error.message,
          data: row
        });
      }
    }
    
    // Delete temp file
    fs.unlinkSync(req.file.path);
    
    console.log(`✅ Import completed: ${results.length} successful, ${errors.length} failed`);
    
    res.json({
      success: true,
      message: 'Import completed',
      successCount: results.length,
      errorCount: errors.length,
      results,
      errors
    });
    
  } catch (error) {
    console.error('Error importing credit notes:', error);
    
    // Clean up temp file
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ success: false, error: error.message });
  }
});

// EXPORT credit notes to CSV
router.get('/export', async (req, res) => {
  try {
    const { status, customerId, fromDate, toDate } = req.query;
    
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.creditNoteDate = {};
      if (fromDate) query.creditNoteDate.$gte = new Date(fromDate);
      if (toDate) query.creditNoteDate.$lte = new Date(toDate);
    }
    
    const creditNotes = await CreditNote.find(query).sort({ createdAt: -1 });
    
    if (creditNotes.length === 0) {
      return res.status(404).json({ success: false, error: 'No credit notes to export' });
    }
    
    const exportData = creditNotes.map(cn => ({
      'Credit Note Number': cn.creditNoteNumber,
      'Customer Name': cn.customerName,
      'Customer Email': cn.customerEmail || '',
      'Invoice Number': cn.invoiceNumber || '',
      'Credit Note Date': cn.creditNoteDate.toISOString().split('T')[0],
      'Reason': cn.reason,
      'Status': cn.status,
      'Subtotal': cn.subTotal.toFixed(2),
      'CGST': cn.cgst.toFixed(2),
      'SGST': cn.sgst.toFixed(2),
      'Total Amount': cn.totalAmount.toFixed(2),
      'Credit Used': cn.creditUsed.toFixed(2),
      'Credit Balance': cn.creditBalance.toFixed(2),
      'Created Date': cn.createdAt.toISOString().split('T')[0]
    }));
    
    const parser = new Parser();
    const csv = parser.parse(exportData);
    
    const filename = `credit_notes_export_${Date.now()}.csv`;
    
    res.header('Content-Type', 'text/csv');
    res.header('Content-Disposition', `attachment; filename=${filename}`);
    res.send(csv);
    
    console.log(`✅ Exported ${creditNotes.length} credit notes`);
    
  } catch (error) {
    console.error('Error exporting credit notes:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;