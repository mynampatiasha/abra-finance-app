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
const { sendMail } = require('../utils/mailer');


// Import Invoice model — reuse the already-registered model (invoices.js must be required first)
const Invoice = mongoose.models.Invoice ||
  (() => { throw new Error('Invoice model not loaded. Ensure invoices.js is required before credit-notes.js'); })();

// Resolve a system Chart-of-Accounts id, preferring the branch-specific record
// (orgs can have one "Sales"/"AR"/"Other Charges"/etc. account per branch),
// falling back to an org-wide (branchId: null) record if no branch match exists.
// Without the branchId match, findOne() could return any branch's account,
// silently posting a branch's transactions onto a different branch's ledger.
async function resolveSystemAccountId(ChartOfAccount, accountName, orgId, branchId) {
  const query = { accountName, isSystemAccount: true, orgId };
  if (branchId) {
    const branchAcc = await ChartOfAccount.findOne({ ...query, branchId }).select('_id').lean();
    if (branchAcc) return branchAcc._id;
  }
  const orgAcc = await ChartOfAccount.findOne({ ...query, branchId: null }).select('_id').lean();
  return orgAcc?._id || null;
}

// ============================================================================
// MONGOOSE MODEL - CREDIT NOTE SCHEMA
// ============================================================================

const creditNoteSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null },
  creditNoteNumber: {
    type: String,
    required: true,
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
  customerGSTIN: { type: String, default: '' },
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
    itemGstRate: {
      type: Number,
      default: 0
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
  
  // NEW: Adjustments
  invoiceLevelDiscount: { type: Number, default: 0 },
  invoiceLevelDiscountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
  invoiceDiscountAmount: { type: Number, default: 0 }, // calculated
  taxableTotal: { type: Number, default: 0 }, // calculated (subtotal - discount)
  
  shippingCharges: { type: Number, default: 0 },
  adjustment: { type: Number, default: 0 },
  
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
  },
  providerTransactionId: {
    type: mongoose.Schema.Types.ObjectId,
    default: null
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
  
  // Invoice-level discount calculation
  let invoiceDiscountAmount = 0;
  if (this.invoiceLevelDiscount > 0) {
    invoiceDiscountAmount = this.invoiceLevelDiscountType === 'percentage'
      ? Math.round(this.subTotal * this.invoiceLevelDiscount / 100 * 100) / 100
      : Math.min(this.invoiceLevelDiscount, this.subTotal);
  }
  this.invoiceDiscountAmount = invoiceDiscountAmount;
  this.taxableTotal = Math.round((this.subTotal - invoiceDiscountAmount) * 100) / 100;
  
  // Apportion discount ratio for tax calculation
  const discountRatio = this.subTotal > 0 ? (this.taxableTotal / this.subTotal) : 1;
  
  // Calculate TDS
  this.tdsAmount = (this.taxableTotal * this.tdsRate) / 100;
  
  // Calculate TCS
  this.tcsAmount = (this.taxableTotal * this.tcsRate) / 100;
  
  // Calculate GST dynamically from items
  let totalGstAmount = 0;
  const hasItemGst = this.items.some(item => typeof item.itemGstRate === 'number');
  
  if (hasItemGst) {
    // Calculate per item
    this.items.forEach(item => {
      // Apportion TDS and TCS to this item's amount proportionally to subtotal
      const itemProportion = this.subTotal > 0 ? (item.amount / this.subTotal) : 0;
      const itemTds = this.tdsAmount * itemProportion;
      const itemTcs = this.tcsAmount * itemProportion;
      
      const adjTaxable = Math.round(item.amount * discountRatio * 100) / 100;
      const itemGstBase = adjTaxable - itemTds + itemTcs;
      const itemTax = (itemGstBase * (item.itemGstRate || 0)) / 100;
      totalGstAmount += itemTax;
    });
  } else {
    // Fallback to global for old documents
    const gstBase = this.taxableTotal - this.tdsAmount + this.tcsAmount;
    totalGstAmount = (gstBase * (this.gstRate || 18)) / 100;
  }
  
  this.cgst = totalGstAmount / 2;
  this.sgst = totalGstAmount / 2;
  this.igst = 0;
  
  // Calculate total
  let rawTotal = this.taxableTotal + totalGstAmount - this.tdsAmount + this.tcsAmount + (this.shippingCharges || 0);
  this.totalAmount = Math.round((rawTotal + (this.adjustment || 0)) * 100) / 100;
  
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
creditNoteSchema.index({ orgId: 1, branchId: 1, creditNoteNumber: 1 }, { unique: true });

const CreditNote = mongoose.models.CreditNote || mongoose.model('CreditNote', creditNoteSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate credit note number
async function generateCreditNoteNumber(orgId = null, branchId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(CreditNote, 'creditNoteNumber', 'CN', orgId, branchId);
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

// Branch-aware org data helper
const { getEffectiveOrgData } = require('./branches');

async function getCnOrgData(orgId, branchId = null) {
  try {
    const mongoose = require('mongoose');
    const db = mongoose.connection.db;
    if (!db) return null;
    return await getEffectiveOrgData(orgId, branchId, db);
  } catch (e) {
    console.warn('⚠️ getCnOrgData error (orgId=%s branchId=%s):', orgId, branchId, e.message);
    return null;
  }
}

async function generateCreditNotePDF(creditNote, orgId, branchId = null) {
  return new Promise(async (resolve, reject) => {
    try {
      console.log('📄 Generating Credit Note PDF:', creditNote.creditNoteNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'credit-notes');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `credit-note-${creditNote.creditNoteNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      let orgName = 'Your Company', orgGST = '', orgAddr = '', orgEmail = '', orgPhone = '', orgTagline = '', orgData = null;
      try {
        orgData = await getCnOrgData(orgId, branchId);
        if (orgData) { orgName = orgData.orgName || orgName; orgGST = orgData.gstNumber || ''; orgAddr = orgData.address || ''; orgEmail = orgData.email || ''; orgPhone = orgData.phone || ''; orgTagline = orgData.tagline || orgData.slogan || ''; }
      } catch (e) { console.warn('⚠️ Org fetch failed:', e.message); }

      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);
      const pageW = 515;

      // ── Header (plain white background, like invoices.js) ──────────────────────
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
        const lp = getLogoPath(orgId);
        try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
      }
      let logoLoaded = false;

      const textX = logoData ? 166 : 50;
      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);

      const textBlockHeight = 14 + 12 + (contactLines.length * 9);
      const textStartY = 35;
      const logoCenterY = textStartY + (textBlockHeight / 2);
      
      const logoH = 82; // Increased to match invoice
      const logoW = 110; // Increased to match invoice
      const logoY = textStartY; // Align top of logo with top of text

      if (logoData) {
        try {
          doc.image(logoData, 44, logoY, { width: logoW, height: logoH, fit: [logoW, logoH] });
          logoLoaded = true;
        } catch (e) { console.warn('⚠️ Logo load failed:', e.message); }
      }

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
         .text('CREDIT NOTE', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
         .text(creditNote.creditNoteNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`Date: ${new Date(creditNote.creditNoteDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });

      // 3-column meta grid (like invoices.js)
      const metaY = Math.max(132, contactY + 8);
      const colW  = pageW / 3;

      const billingStr = [
        creditNote.billingAddress?.street,
        creditNote.billingAddress?.city,
        creditNote.billingAddress?.state,
        creditNote.billingAddress?.pincode,
      ].filter(Boolean).join(', ');

      // Dynamic box height
      doc.fontSize(9).font('Helvetica-Bold');
      const _custNameH = doc.heightOfString(creditNote.customerName || 'N/A', { width: colW - 16 });
      doc.fontSize(7).font('Helvetica');
      const _addrH = billingStr ? doc.heightOfString(billingStr, { width: colW - 16 }) : 0;
      const _gstH  = creditNote.customerGSTIN ? 10 : 0;
      const metaH  = Math.max(90, 18 + _custNameH + 2 + _addrH + _gstH + 10);

      // Col 1: Bill To
      const billX = 40;
      doc.rect(billX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('BILL TO', billX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold')
         .text(creditNote.customerName || 'N/A', billX + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(9).font('Helvetica-Bold');
      const custNameH = doc.heightOfString(creditNote.customerName || 'N/A', { width: colW - 16 });
      const billAddrY = metaY + 18 + custNameH + 2;
      if (billingStr) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(billingStr, billX + 8, billAddrY, { width: colW - 16, ellipsis: true });
      }
      if (creditNote.customerGSTIN) {
        doc.fontSize(7).font('Helvetica');
        const addrH = billingStr ? doc.heightOfString(billingStr, { width: colW - 16 }) : 0;
        doc.fillColor('#000000')
           .text(`GSTIN: ${creditNote.customerGSTIN}`, billX + 8, billAddrY + addrH + 2, { width: colW - 16 });
      }

      // Col 2: Ship To (same as bill to for credit notes)
      const shipX = 40 + colW;
      doc.rect(shipX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('SHIP TO', shipX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      if (billingStr) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(billingStr, shipX + 8, metaY + 18, { width: colW - 16, ellipsis: true });
      } else {
        doc.fontSize(7).fillColor('#aaaaaa').font('Helvetica')
           .text('Same as billing address', shipX + 8, metaY + 18, { width: colW - 16 });
      }

      // Col 3: Credit Note Details
      const detX = 40 + colW * 2;
      doc.rect(detX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('CREDIT NOTE DETAILS', detX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`CN #: ${creditNote.creditNoteNumber}`, detX + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(7).fillColor('#000000').font('Helvetica')
         .text(`Date: ${new Date(creditNote.creditNoteDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}`, detX + 8, metaY + 29, { width: colW - 16 });
      let currentDetY = metaY + 29;
      if (creditNote.invoiceNumber) {
        currentDetY += 10;
        doc.text(`Invoice Ref: ${creditNote.invoiceNumber}`, detX + 8, currentDetY, { width: colW - 16 });
      }
      currentDetY += 10;
      doc.text(`Reason: ${creditNote.reason || 'N/A'}`, detX + 8, currentDetY, { width: colW - 16, ellipsis: true });
      if (creditNote.reasonDescription) {
        currentDetY += 10;
        doc.fillColor('#666666').text(creditNote.reasonDescription, detX + 8, currentDetY, { width: colW - 16, ellipsis: true });
        doc.fillColor('#000000');
      }

      let tableStartY = metaY + metaH + 12;

      // Items table — invoice-style columns
      const isInterState = false; // Credit notes default to intra-state (CGST+SGST)

      const cols = {
        num:     { x: 40,  w: 16  },
        desc:    { x: 56,  w: 90  },
        hsn:     { x: 146, w: 44  },
        unit:    { x: 190, w: 24  },
        qty:     { x: 214, w: 24  },
        rate:    { x: 238, w: 36  },
        disc:    { x: 274, w: 26  },
        taxable: { x: 300, w: 38  },
        gst:     { x: 338, w: 24  },
        tax1:    { x: 362, w: 46  },
        tax2:    { x: 408, w: 46  },
        amount:  { x: 454, w: 61  },
      };

      doc.rect(40, tableStartY, 515, 20).fill('#0f1e3d');
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold');
      doc.text('#',       cols.num.x  + 2, tableStartY + 7, { width: cols.num.w });
      doc.text('ITEM',    cols.desc.x + 2, tableStartY + 7, { width: cols.desc.w });
      doc.text('HSN/SAC', cols.hsn.x  + 2, tableStartY + 7, { width: cols.hsn.w });
      doc.text('UNIT',    cols.unit.x + 2, tableStartY + 7, { width: cols.unit.w });
      doc.text('QTY',     cols.qty.x  + 2, tableStartY + 7, { width: cols.qty.w,     align: 'center' });
      doc.text('RATE',    cols.rate.x + 2, tableStartY + 7, { width: cols.rate.w,    align: 'right' });
      doc.text('DISC',    cols.disc.x + 2, tableStartY + 7, { width: cols.disc.w,    align: 'right' });
      doc.text('TAXABLE', cols.taxable.x+2,tableStartY + 7, { width: cols.taxable.w, align: 'right' });
      doc.text('GST%',    cols.gst.x  + 2, tableStartY + 7, { width: cols.gst.w,     align: 'center' });
      doc.text('CGST',    cols.tax1.x + 2, tableStartY + 7, { width: cols.tax1.w,    align: 'right' });
      doc.text('SGST',    cols.tax2.x + 2, tableStartY + 7, { width: cols.tax2.w,    align: 'right' });
      doc.text('AMOUNT',  cols.amount.x+2, tableStartY + 7, { width: cols.amount.w,  align: 'right' });

      let rowY = tableStartY + 20;

      (creditNote.items || []).forEach((item, idx) => {
        const descText  = item.itemDetails || 'N/A';
        const descWidth = cols.desc.w - 4;
        const vPad      = 8;
        doc.font('Helvetica').fontSize(7);
        const descH = doc.heightOfString(descText, { width: descWidth, lineGap: 1 });
        const rowH  = Math.max(20, descH + vPad * 2);

        const fill  = idx % 2 === 0 ? '#ffffff' : '#f7f9fc';
        doc.rect(40, rowY, 515, rowH).fill(fill);
        doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();

        const hsnSac  = item.hsnCode || item.sacCode || '';
        const discStr = item.discount > 0
          ? (item.discountType === 'percentage' ? `${item.discount}%` : `${item.discount}`)
          : '—';

        const gstRate  = item.itemGstRate !== undefined ? item.itemGstRate : (item.gstRate || 18);
        const taxable  = item.amount || 0;
        const cgstAmt  = Math.round(taxable * (gstRate / 2) / 100 * 100) / 100;
        const sgstAmt  = cgstAmt;
        const totalAmt = taxable + cgstAmt + sgstAmt;

        const cellY = rowY + vPad;
        doc.fontSize(7).fillColor('#000000');
        doc.font('Helvetica-Bold').text(String(idx + 1), cols.num.x + 2, cellY, { width: cols.num.w });
        doc.font('Helvetica').text(descText, cols.desc.x + 2, cellY, { width: descWidth, lineGap: 1 });
        doc.text(hsnSac,                           cols.hsn.x  + 2, cellY, { width: cols.hsn.w - 2,  ellipsis: true });
        doc.text(item.unit || 'Nos',               cols.unit.x + 2, cellY, { width: cols.unit.w });
        doc.text(String(item.quantity || 0),       cols.qty.x  + 2, cellY, { width: cols.qty.w,     align: 'center' });
        doc.text(`${(item.rate || 0).toFixed(2)}`, cols.rate.x + 2, cellY, { width: cols.rate.w,    align: 'right' });
        doc.text(discStr,                          cols.disc.x + 2, cellY, { width: cols.disc.w,    align: 'right' });
        doc.text(`${taxable.toFixed(2)}`,          cols.taxable.x+2, cellY, { width: cols.taxable.w, align: 'right' });
        doc.text(`${gstRate}%`,                    cols.gst.x  + 2, cellY, { width: cols.gst.w,     align: 'center' });
        doc.text(`${cgstAmt.toFixed(2)}`,          cols.tax1.x + 2, cellY, { width: cols.tax1.w,    align: 'right' });
        doc.text(`${sgstAmt.toFixed(2)}`,          cols.tax2.x + 2, cellY, { width: cols.tax2.w,    align: 'right' });
        doc.font('Helvetica-Bold')
           .text(`${totalAmt.toFixed(2)}`,         cols.amount.x+2, cellY, { width: cols.amount.w,  align: 'right' });
        rowY += rowH;
      });

      // Totals
      const totalsX = 315;
      const totalsW = 240;
      let totalsY   = rowY + 12;
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

      tRow('Subtotal:', `Rs. ${(creditNote.subTotal || 0).toFixed(2)}`);
      if ((creditNote.invoiceDiscountAmount || 0) > 0) {
        tRow(`Discount (${creditNote.invoiceLevelDiscountType === 'percentage' ? creditNote.invoiceLevelDiscount + '%' : 'Rs.' + creditNote.invoiceLevelDiscount}):`, `-Rs. ${creditNote.invoiceDiscountAmount.toFixed(2)}`);
      }
      if (creditNote.cgst > 0) tRow(`CGST (${creditNote.gstRate / 2}%):`, `Rs. ${creditNote.cgst.toFixed(2)}`);
      if (creditNote.sgst > 0) tRow(`SGST (${creditNote.gstRate / 2}%):`, `Rs. ${creditNote.sgst.toFixed(2)}`);
      if (creditNote.igst > 0) tRow(`IGST (${creditNote.gstRate}%):`,     `Rs. ${creditNote.igst.toFixed(2)}`);
      if (creditNote.tdsAmount > 0) tRow('TDS Deducted:', `- Rs. ${creditNote.tdsAmount.toFixed(2)}`);

      if ((creditNote.shippingCharges || 0) > 0) tRow('Shipping:', `Rs. ${creditNote.shippingCharges.toFixed(2)}`);
      if (creditNote.adjustment && creditNote.adjustment !== 0) {
        tRow('Adjustment:', `${creditNote.adjustment > 0 ? '+' : ''}Rs. ${creditNote.adjustment.toFixed(2)}`);
      }

      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('Credit Amount', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Rs. ${(creditNote.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      if ((creditNote.creditUsed || 0) > 0)
        tRow('Credit Used:',       `Rs. ${creditNote.creditUsed.toFixed(2)}`);
      if ((creditNote.creditBalance || 0) > 0)
        tRow('Available Balance:', `Rs. ${creditNote.creditBalance.toFixed(2)}`, true);

      // Amount in words
      const wordsY = totalsY + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold')
         .text(`In Words: ${numberToWords(Math.round(creditNote.totalAmount || 0))} Only`,
               48, wordsY + 5, { width: pageW - 16 });

      // Notes
      let notesY = wordsY + 28;
      if (creditNote.customerNotes || creditNote.reasonDescription) {
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTES', 40, notesY, { characterSpacing: 0.8 });
        doc.moveTo(40, notesY + 9).lineTo(555, notesY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica')
           .text(creditNote.reasonDescription || creditNote.customerNotes, 40, notesY + 14, { width: pageW });
        notesY += 40;
      }

      // Terms & Conditions
      if (creditNote.termsAndConditions) {
        const tcY = notesY + 6;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold')
           .text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(creditNote.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
        notesY = tcY + 30;
      }

      // ── AUTHORIZED SIGNATORY ─────────────────────────────────────────────
      const signSectionY = notesY + 10;
      const signBoxW     = 220;
      const authBoxX     = 555 - signBoxW;

      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text(`For ${orgName.toUpperCase()}`, authBoxX, signSectionY, { width: signBoxW, characterSpacing: 0.5, ellipsis: true });

      const _cnSigRelPath = orgData?.digitalSignaturePath;
      const _cnSigSize    = 200;
      let   _cnActualSigH = _cnSigSize;
      
      let sigBuf = null;
      let sigExt = '.png';
      if (orgData?.signatureBase64) {
        const match = orgData.signatureBase64.match(/^data:image\/(\w+);base64,(.*)$/);
        if (match) {
          sigExt = '.' + match[1].replace('jpeg', 'jpg');
          sigBuf = Buffer.from(match[2], 'base64');
        }
      } else if (_cnSigRelPath) {
        const _cnSigAbs = path.join(__dirname, '..', _cnSigRelPath.replace(/^\//, ''));
        try { if (fs.existsSync(_cnSigAbs)) { sigBuf = fs.readFileSync(_cnSigAbs); sigExt = path.extname(_cnSigAbs).toLowerCase(); } } catch (_) {}
      }

      if (sigBuf) {
        try {
            let _cnW = _cnSigSize, _cnH = _cnSigSize;
            try {
              if (sigExt === '.png' && sigBuf.length > 24) { _cnW = sigBuf.readUInt32BE(16); _cnH = sigBuf.readUInt32BE(20); }
              else if ((sigExt === '.jpg' || sigExt === '.jpeg') && sigBuf.length > 4) {
                let _cni = 2;
                while (_cni < sigBuf.length - 8) {
                  if (sigBuf[_cni] === 0xFF && sigBuf[_cni+1] >= 0xC0 && sigBuf[_cni+1] <= 0xC3) { _cnH = sigBuf.readUInt16BE(_cni+5); _cnW = sigBuf.readUInt16BE(_cni+7); break; }
                  _cni += 2 + sigBuf.readUInt16BE(_cni + 2);
                }
              }
            } catch (_) {}
            const _cnScale = Math.min(_cnSigSize / _cnW, _cnSigSize / _cnH);
            _cnActualSigH  = Math.round(_cnH * _cnScale);
            const _cnActualSigW = Math.round(_cnW * _cnScale);
            doc.image(sigBuf, authBoxX + (signBoxW - _cnActualSigW) / 2, signSectionY + 10, { width: _cnActualSigW, height: _cnActualSigH });
        } catch (_e) { console.warn('⚠️ Signature render failed:', _e.message); }
      }

      const _cnSigLineY = signSectionY + 10 + _cnActualSigH + 14;
      doc.moveTo(authBoxX, _cnSigLineY).lineTo(authBoxX + signBoxW, _cnSigLineY)
         .lineWidth(0.5).strokeColor('#aaaaaa').stroke();
      doc.fontSize(6.5).fillColor('#000000').font('Helvetica-Bold')
         .text('Authorized Signatory', authBoxX, _cnSigLineY + 3, { width: signBoxW, align: 'center' });

      // Footer
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY).lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName} · ${orgGST ? 'GSTIN: ' + orgGST + ' · ' : ''}${creditNote.creditNoteNumber}`,
               40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`,
               40, footY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => {
        console.log(`✅ Credit Note PDF generated: ${filename}`);
        resolve({ filename, filepath, relativePath: `/uploads/credit-notes/${filename}` });
      });
      stream.on('error', reject);
    } catch (error) { console.error('❌ PDF generation error:', error); reject(error); }
  });
}

// ============================================================================
// EMAIL SERVICE
// ============================================================================

async function sendCreditNoteEmail(creditNote, pdfPath, orgId, branchId = null) {
  console.log('📧 Sending credit note email to:', creditNote.customerEmail);

  let orgName = '', orgGST = '', orgPhone = '', orgEmail = '', orgData = null;
  try {
    orgData = await getCnOrgData(orgId, branchId);
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
      ${(creditNote.invoiceDiscountAmount || 0) > 0 ? `<tr><td>Discount</td><td>-Rs.${creditNote.invoiceDiscountAmount.toFixed(2)}</td></tr>` : ''}
      ${creditNote.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${creditNote.cgst.toFixed(2)}</td></tr>` : ''}
      ${creditNote.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${creditNote.sgst.toFixed(2)}</td></tr>` : ''}
      ${(creditNote.shippingCharges || 0) > 0 ? `<tr><td>Shipping</td><td>Rs.${creditNote.shippingCharges.toFixed(2)}</td></tr>` : ''}
      ${creditNote.adjustment && creditNote.adjustment !== 0 ? `<tr><td>Adjustment</td><td>${creditNote.adjustment > 0 ? '+' : ''}Rs.${creditNote.adjustment.toFixed(2)}</td></tr>` : ''}
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
  const result = await sendMail({
    orgId, branchId, db: mongoose.connection.db,
    to:          creditNote.customerEmail,
    subject:     mailOptions.subject,
    html:        mailOptions.html,
    attachments: mailOptions.attachments,
  });
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
    Object.assign(query, req.branchFilter || {});
    
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
    const orgFilter = {
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    };
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
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
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
      creditNoteData.creditNoteNumber = await generateCreditNoteNumber(req.user?.orgId || null, req.branchIds?.length > 0 ? req.branchIds[0] : null);
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
    creditNoteData.branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    if (creditNoteData.providerTransactionId && typeof creditNoteData.providerTransactionId === 'string' && mongoose.Types.ObjectId.isValid(creditNoteData.providerTransactionId)) {
      creditNoteData.providerTransactionId = new mongoose.Types.ObjectId(creditNoteData.providerTransactionId);
    }
    const creditNote = new CreditNote(creditNoteData);
    await creditNote.save();
    
    console.log(`✅ Credit Note created: ${creditNote.creditNoteNumber}`);

    // ✅ COA Posting
    // Credit Note = reverse of invoice
    // Debit: Sales (reverse revenue)
    // Credit: Accounts Receivable (reduce what customer owes)
    if (creditNote.status !== 'DRAFT') {
    try {
      const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

      const currentOrgId = req.user?.orgId || null;
      const currentBranchId = creditNote.branchId || (req.branchIds?.length > 0 ? req.branchIds[0] : null);
      const [salesId, arId, otherChargesId] = await Promise.all([
        resolveSystemAccountId(ChartOfAccount, 'Sales', currentOrgId, currentBranchId),
        resolveSystemAccountId(ChartOfAccount, 'Accounts Receivable', currentOrgId, currentBranchId),
        resolveSystemAccountId(ChartOfAccount, 'Other Charges', currentOrgId, currentBranchId),
      ]);

      const txnDate = new Date(creditNote.creditNoteDate);

      // Debit Sales (reverse revenue)
      if (salesId) await postTransactionToCOA({
        accountId:       salesId,
        orgId: currentOrgId,
        branchId:        currentBranchId,
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
        orgId: currentOrgId,
        branchId:        currentBranchId,
        date:            txnDate,
        description:     `Credit Note ${creditNote.creditNoteNumber} - ${creditNote.customerName}`,
        referenceType:   'Credit Note',
        referenceId:     creditNote._id,
        referenceNumber: creditNote.creditNoteNumber,
        debit:           0,
        credit:          creditNote.totalAmount,
      });

      // Reverse Adjustments if any
      if (otherChargesId && creditNote.adjustment) {
        if (creditNote.adjustment < 0) {
          // Negative adjustment on CN = Credit
          await postTransactionToCOA({
            accountId:       otherChargesId,
            orgId: currentOrgId,
            branchId:        currentBranchId,
            date:            txnDate,
            description:     `Adjustment Reversal - Credit Note ${creditNote.creditNoteNumber}`,
            referenceType:   'Credit Note',
            referenceId:     creditNote._id,
            referenceNumber: creditNote.creditNoteNumber,
            debit:           0,
            credit:          Math.abs(creditNote.adjustment),
          });
        } else {
          // Positive adjustment on CN = Debit
          await postTransactionToCOA({
            accountId:       otherChargesId,
            orgId: currentOrgId,
            branchId:        currentBranchId,
            date:            txnDate,
            description:     `Adjustment Reversal - Credit Note ${creditNote.creditNoteNumber}`,
            referenceType:   'Credit Note',
            referenceId:     creditNote._id,
            referenceNumber: creditNote.creditNoteNumber,
            debit:           creditNote.adjustment,
            credit:          0,
          });
        }
      }

      // Also reverse Tax Payable if GST exists
      if (creditNote.cgst + creditNote.sgst > 0) {
        const taxId = await resolveSystemAccountId(ChartOfAccount, 'Tax Payable', currentOrgId, currentBranchId);

        if (taxId) await postTransactionToCOA({
          accountId:       taxId,
          orgId: currentOrgId,
          branchId:        currentBranchId,
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
    } // End if not DRAFT

    // ── Update Customer Profile ──────────────────────────────────────────────
    // Add the credit note amount to customer's unusedCredits ONLY if status is OPEN
    // DRAFT credit notes should NOT add to unused credits until they are finalized
    console.log('═══════════════════════════════════════════════════════════════════');
    console.log('🔍 [CREDIT NOTE CREATION] Starting customer unusedCredits update check');
    console.log(`   Credit Note Number: ${creditNote.creditNoteNumber}`);
    console.log(`   Credit Note ID: ${creditNote._id}`);
    console.log(`   Customer ID: ${creditNote.customerId}`);
    console.log(`   Customer Name: ${creditNote.customerName}`);
    console.log(`   Credit Note Status: ${creditNote.status}`);
    console.log(`   Credit Note Amount: ₹${creditNote.totalAmount}`);
    console.log(`   Credit Balance: ₹${creditNote.creditBalance}`);
    console.log('═══════════════════════════════════════════════════════════════════');
    
    try {
      const Customer = mongoose.models.BillingCustomer
        || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
      
      if (creditNote.status === 'OPEN') {
        console.log(`✅ [CN Creation] Status is OPEN - WILL UPDATE customer unusedCredits`);
        
        const customerBefore = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Creation] Customer BEFORE update:`);
        console.log(`   - Customer Name: ${customerBefore?.customerDisplayName || 'N/A'}`);
        console.log(`   - Current unusedCredits: ₹${customerBefore?.unusedCredits || 0}`);
        console.log(`   - Outstanding Receivables: ₹${customerBefore?.outstandingReceivables || 0}`);
        
        console.log(`🔄 [CN Creation] Incrementing unusedCredits by ₹${creditNote.totalAmount}...`);
        
        await Customer.findByIdAndUpdate(creditNote.customerId, {
          $inc: { unusedCredits: creditNote.totalAmount }
        });
        
        const customerAfter = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Creation] Customer AFTER update:`);
        console.log(`   - New unusedCredits: ₹${customerAfter?.unusedCredits || 0}`);
        console.log(`   - Change: +₹${creditNote.totalAmount}`);
        console.log(`   - Calculation: ₹${customerBefore?.unusedCredits || 0} + ₹${creditNote.totalAmount} = ₹${customerAfter?.unusedCredits || 0}`);
        console.log(`✅ [CN Creation] Customer unusedCredits SUCCESSFULLY UPDATED!`);
      } else {
        console.log(`⚠️ [CN Creation] Status is ${creditNote.status} - NOT UPDATING customer unusedCredits`);
        console.log(`   Reason: Only OPEN credit notes add to unusedCredits`);
        console.log(`   Action: Credit will be added when status changes to OPEN`);
      }
    } catch (custErr) {
      console.error('❌ [CN Creation] ERROR updating customer unusedCredits:', custErr.message);
      console.error('   Stack:', custErr.stack);
    }
    console.log('═══════════════════════════════════════════════════════════════════\n');
    
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
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
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
    const oldStatus = creditNote.status;
    const oldTotalAmount = creditNote.totalAmount;
    
    // Calculate item amounts
    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    // Force PDF regeneration on edit so new data like Reason Description reflects
    updates.pdfPath = null;
    
    Object.assign(creditNote, updates);
    await creditNote.save();

    // 🔸 COA Reversal & Re-posting on Edit
    try {
      const { postTransactionToCOA, ChartOfAccount, AccountTransaction } = require('./chart_of_accounts');
      const currentOrgId = req.user?.orgId || null;
      const branchId = creditNote.branchId || (req.branchIds?.length > 0 ? req.branchIds[0] : null);
      
      // 1. Delete old COA entries for this credit note
      await AccountTransaction.deleteMany({
        referenceType: 'Credit Note',
        referenceId: creditNote._id,
        ...(currentOrgId ? { orgId: currentOrgId } : {})
      });
      
      // 2. Repost the new amounts ONLY IF NOT DRAFT
      if (creditNote.status !== 'DRAFT') {
        const [salesId, arId, otherChargesId, taxId] = await Promise.all([
          resolveSystemAccountId(ChartOfAccount, 'Sales', currentOrgId, branchId),
          resolveSystemAccountId(ChartOfAccount, 'Accounts Receivable', currentOrgId, branchId),
          resolveSystemAccountId(ChartOfAccount, 'Other Charges', currentOrgId, branchId),
          resolveSystemAccountId(ChartOfAccount, 'Tax Payable', currentOrgId, branchId),
        ]);
        const txnDate = new Date(creditNote.creditNoteDate);
        
        if (salesId) await postTransactionToCOA({
          accountId: salesId, orgId: currentOrgId, branchId,
          date: txnDate, description: `Credit Note ${creditNote.creditNoteNumber} - ${creditNote.customerName}`,
          referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber,
          debit: creditNote.subTotal, credit: 0,
        });
        if (arId) await postTransactionToCOA({
          accountId: arId, orgId: currentOrgId, branchId,
          date: txnDate, description: `Credit Note ${creditNote.creditNoteNumber} - ${creditNote.customerName}`,
          referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber,
          debit: 0, credit: creditNote.totalAmount,
        });
        if (otherChargesId && creditNote.adjustment) {
          await postTransactionToCOA({
            accountId: otherChargesId, orgId: currentOrgId, branchId,
            date: txnDate, description: `Adjustment Reversal - Credit Note ${creditNote.creditNoteNumber}`,
            referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber,
            debit: creditNote.adjustment > 0 ? creditNote.adjustment : 0, credit: creditNote.adjustment < 0 ? Math.abs(creditNote.adjustment) : 0,
          });
        }
        if (taxId && (creditNote.cgst + creditNote.sgst + (creditNote.igst || 0)) > 0) {
          await postTransactionToCOA({
            accountId: taxId, orgId: currentOrgId, branchId,
            date: txnDate, description: `GST Reversal - Credit Note ${creditNote.creditNoteNumber}`,
            referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber,
            debit: creditNote.cgst + creditNote.sgst + (creditNote.igst || 0), credit: 0,
          });
        }
        console.log(`✅ COA reversed & posted for credit note edit: ${creditNote.creditNoteNumber}`);
      }
    } catch (coaErr) {
      console.error('⚠️ COA post error (credit note edit):', coaErr.message);
    }
    
    console.log(`✅ Credit Note updated: ${creditNote.creditNoteNumber}`);
    
    // ── Handle Status Change: DRAFT → OPEN ────────────────────────────────────
    // When credit note changes from DRAFT to OPEN, add to customer's unusedCredits
    if (oldStatus === 'DRAFT' && creditNote.status === 'OPEN') {
      console.log('═══════════════════════════════════════════════════════════════════');
      console.log('🔍 [CREDIT NOTE UPDATE] Status changed DRAFT → OPEN');
      console.log(`   Credit Note Number: ${creditNote.creditNoteNumber}`);
      console.log(`   Customer ID: ${creditNote.customerId}`);
      console.log(`   Customer Name: ${creditNote.customerName}`);
      console.log(`   Credit Amount: ₹${creditNote.totalAmount}`);
      console.log('═══════════════════════════════════════════════════════════════════');
      
      try {
        const Customer = mongoose.models.BillingCustomer
          || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
        
        const customerBefore = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Update] Customer BEFORE status change:`);
        console.log(`   - Customer Name: ${customerBefore?.customerDisplayName || 'N/A'}`);
        console.log(`   - Current unusedCredits: ₹${customerBefore?.unusedCredits || 0}`);
        
        console.log(`🔄 [CN Update] Adding ₹${creditNote.totalAmount} to unusedCredits...`);
        
        await Customer.findByIdAndUpdate(creditNote.customerId, {
          $inc: { unusedCredits: creditNote.totalAmount }
        });
        
        const customerAfter = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Update] Customer AFTER status change:`);
        console.log(`   - New unusedCredits: ₹${customerAfter?.unusedCredits || 0}`);
        console.log(`   - Change: +₹${creditNote.totalAmount}`);
        console.log(`✅ [CN Update] Customer unusedCredits SUCCESSFULLY UPDATED!`);
      } catch (custErr) {
        console.error('❌ [CN Update] ERROR updating customer unusedCredits:', custErr.message);
        console.error('   Stack:', custErr.stack);
      }
      
      console.log('═══════════════════════════════════════════════════════════════════\n');
    }
    // ── Handle Amount Change for OPEN Credit Notes ────────────────────────────
    // If credit note is OPEN and amount changed, adjust customer's unusedCredits
    else if (creditNote.status === 'OPEN' && oldTotalAmount !== creditNote.totalAmount) {
      console.log('═══════════════════════════════════════════════════════════════════');
      console.log('🔍 [CREDIT NOTE UPDATE] Amount changed for OPEN credit note');
      console.log(`   Credit Note Number: ${creditNote.creditNoteNumber}`);
      console.log(`   Old Amount: ₹${oldTotalAmount}`);
      console.log(`   New Amount: ₹${creditNote.totalAmount}`);
      console.log(`   Difference: ₹${creditNote.totalAmount - oldTotalAmount}`);
      console.log('═══════════════════════════════════════════════════════════════════');
      
      try {
        const Customer = mongoose.models.BillingCustomer
          || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
        
        const amountDiff = creditNote.totalAmount - oldTotalAmount;
        
        const customerBefore = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Update] Customer BEFORE amount change:`);
        console.log(`   - Current unusedCredits: ₹${customerBefore?.unusedCredits || 0}`);
        
        console.log(`🔄 [CN Update] Adjusting unusedCredits by ₹${amountDiff}...`);
        
        await Customer.findByIdAndUpdate(creditNote.customerId, {
          $inc: { unusedCredits: amountDiff }
        });
        
        const customerAfter = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Update] Customer AFTER amount change:`);
        console.log(`   - New unusedCredits: ₹${customerAfter?.unusedCredits || 0}`);
        console.log(`✅ [CN Update] Customer unusedCredits adjusted!`);
      } catch (custErr) {
        console.error('❌ [CN Update] ERROR adjusting customer unusedCredits:', custErr.message);
        console.error('   Stack:', custErr.stack);
      }
      console.log('═══════════════════════════════════════════════════════════════════\n');
    }
    
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
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
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
      pdfInfo = await generateCreditNotePDF(creditNote, creditNote.orgId, creditNote.branchId);
      creditNote.pdfPath = pdfInfo.filepath;
      creditNote.pdfGeneratedAt = new Date();
    }
    
    // Send email
    await sendCreditNoteEmail(creditNote, creditNote.pdfPath, creditNote.orgId, creditNote.branchId);
    
    // Track old status before update
    const oldStatus = creditNote.status;
    
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
    
    // ── Handle Status Change: DRAFT → OPEN ────────────────────────────────────
    // When credit note is sent and changes from DRAFT to OPEN, add to customer's unusedCredits
    if (oldStatus === 'DRAFT' && creditNote.status === 'OPEN') {
      console.log('═══════════════════════════════════════════════════════════════════');
      console.log('🔍 [CREDIT NOTE SEND] Status changed DRAFT → OPEN via email send');
      console.log(`   Credit Note Number: ${creditNote.creditNoteNumber}`);
      console.log(`   Customer ID: ${creditNote.customerId}`);
      console.log(`   Customer Name: ${creditNote.customerName}`);
      console.log(`   Customer Email: ${creditNote.customerEmail}`);
      console.log(`   Credit Amount: ₹${creditNote.totalAmount}`);
      console.log('═══════════════════════════════════════════════════════════════════');
      
      try {
        const Customer = mongoose.models.BillingCustomer
          || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
        
        const customerBefore = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Send] Customer BEFORE send:`);
        console.log(`   - Customer Name: ${customerBefore?.customerDisplayName || 'N/A'}`);
        console.log(`   - Current unusedCredits: ₹${customerBefore?.unusedCredits || 0}`);
        
        console.log(`🔄 [CN Send] Adding ₹${creditNote.totalAmount} to unusedCredits...`);
        
        await Customer.findByIdAndUpdate(creditNote.customerId, {
          $inc: { unusedCredits: creditNote.totalAmount }
        });
        
        const customerAfter = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Send] Customer AFTER send:`);
        console.log(`   - New unusedCredits: ₹${customerAfter?.unusedCredits || 0}`);
        console.log(`   - Change: +₹${creditNote.totalAmount}`);
        console.log(`✅ [CN Send] Customer unusedCredits SUCCESSFULLY UPDATED!`);
      } catch (custErr) {
        console.error('❌ [CN Send] ERROR updating customer unusedCredits:', custErr.message);
        console.error('   Stack:', custErr.stack);
      }
      console.log('═══════════════════════════════════════════════════════════════════\n');
    }
    
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

// MARK AS SENT (no email)
router.patch('/:id/mark-as-sent', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({ _id: req.params.id, orgId: req.user?.orgId, ...(req.branchFilter || {}) });
    if (!creditNote) return res.status(404).json({ success: false, error: 'Credit note not found' });
    if (['VOID', 'CANCELLED'].includes(creditNote.status)) {
      return res.status(400).json({ success: false, error: `Cannot mark a ${creditNote.status} credit note as sent` });
    }
    
    const oldStatus = creditNote.status;
    creditNote.status    = creditNote.status === 'DRAFT' ? 'OPEN' : creditNote.status;
    creditNote.updatedBy = req.user?.email || req.user?.uid || 'system';
    await creditNote.save();
    
    // ── Handle Status Change: DRAFT → OPEN ────────────────────────────────────
    // When credit note is marked as sent and changes from DRAFT to OPEN, add to customer's unusedCredits
    if (oldStatus === 'DRAFT' && creditNote.status === 'OPEN') {
      console.log('═══════════════════════════════════════════════════════════════════');
      console.log('🔍 [CREDIT NOTE MARK SENT] Status changed DRAFT → OPEN via mark as sent');
      console.log(`   Credit Note Number: ${creditNote.creditNoteNumber}`);
      console.log(`   Customer ID: ${creditNote.customerId}`);
      console.log(`   Customer Name: ${creditNote.customerName}`);
      console.log(`   Credit Amount: ₹${creditNote.totalAmount}`);
      console.log('═══════════════════════════════════════════════════════════════════');
      
      try {
        const Customer = mongoose.models.BillingCustomer
          || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
        
        const customerBefore = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Mark Sent] Customer BEFORE mark sent:`);
        console.log(`   - Customer Name: ${customerBefore?.customerDisplayName || 'N/A'}`);
        console.log(`   - Current unusedCredits: ₹${customerBefore?.unusedCredits || 0}`);
        
        console.log(`🔄 [CN Mark Sent] Adding ₹${creditNote.totalAmount} to unusedCredits...`);
        
        await Customer.findByIdAndUpdate(creditNote.customerId, {
          $inc: { unusedCredits: creditNote.totalAmount }
        });
        
        const customerAfter = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Mark Sent] Customer AFTER mark sent:`);
        console.log(`   - New unusedCredits: ₹${customerAfter?.unusedCredits || 0}`);
        console.log(`   - Change: +₹${creditNote.totalAmount}`);
        console.log(`✅ [CN Mark Sent] Customer unusedCredits SUCCESSFULLY UPDATED!`);
      } catch (custErr) {
        console.error('❌ [CN Mark Sent] ERROR updating customer unusedCredits:', custErr.message);
        console.error('   Stack:', custErr.stack);
      }
      console.log('═══════════════════════════════════════════════════════════════════\n');
    }
    
    console.log(`✅ Credit note marked as sent (no email): ${creditNote.creditNoteNumber}`);
    res.json({ success: true, message: 'Credit note marked as sent', data: creditNote });
  } catch (error) {
    console.error('Error marking credit note as sent:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// RECORD refund
router.post('/:id/refund', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
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

    // ── COA Posting ──────────────────────────────────────────────────────────
    // Dr Accounts Receivable  (clearing the customer liability)
    // Cr Bank Account         (money leaving the bank)
    // If bankAccountId is provided (called from bank transaction categorization),
    // use the actual bank COA; otherwise fall back to a generic Bank account.
    try {
      const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');
      const currentOrgId = req.user?.orgId || null;
      const branchId     = req.branchIds?.length > 0 ? req.branchIds[0] : null;
      const txnDate      = refundDate ? new Date(refundDate) : new Date();
      const desc         = `Credit Note ${creditNote.creditNoteNumber} refund to ${creditNote.customerName}`;

      // Resolve AR account
      const arId = await ChartOfAccount.findOne({
        accountName: { $regex: /^Accounts Receivable$/i },
        isActive: true,
        $or: [{ orgId: currentOrgId }, { orgId: null }],
      }).select('_id').lean().then(a => a?._id);

      // Resolve bank/cash account — prefer the specific bank account passed in body
      let bankId = null;
      const { bankAccountId } = req.body;
      if (bankAccountId) {
        // bankAccountId is a PaymentAccount _id — resolve its linked COA
        const PaymentAccount = mongoose.models.PaymentAccount
          || mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
        const pa = await PaymentAccount.findById(bankAccountId).lean();
        if (pa) {
          bankId = await ChartOfAccount.findOne({
            accountName: pa.accountName,
            $or: [{ orgId: currentOrgId }, { orgId: null }],
          }).select('_id').lean().then(a => a?._id);
        }
      }
      if (!bankId) {
        // Fallback to generic Bank / Cash account
        bankId = await ChartOfAccount.findOne({
          accountName: { $regex: /^(Bank|Cash)$/i },
          isActive: true,
          $or: [{ orgId: currentOrgId }, { orgId: null }],
        }).select('_id').lean().then(a => a?._id);
      }

      const newRefundDoc = creditNote.refunds[creditNote.refunds.length - 1];
      const refundRef    = newRefundDoc?._id?.toString() || creditNote.creditNoteNumber;

      if (arId) await postTransactionToCOA({
        accountId:       arId,
        orgId:           currentOrgId,
        branchId,
        date:            txnDate,
        description:     desc,
        referenceType:   'CreditNote',
        referenceId:     creditNote._id,
        referenceNumber: refundRef,
        debit:           parseFloat(amount),
        credit:          0,
      });

      if (bankId) await postTransactionToCOA({
        accountId:       bankId,
        orgId:           currentOrgId,
        branchId,
        date:            txnDate,
        description:     desc,
        referenceType:   'CreditNote',
        referenceId:     creditNote._id,
        referenceNumber: refundRef,
        debit:           0,
        credit:          parseFloat(amount),
      });

      console.log(`✅ COA posted for credit note refund: ${creditNote.creditNoteNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA error (credit note refund):', coaErr.message);
    }

    // ── Update PaymentAccount Balance ────────────────────────────────────────
    // Reduce the bank account balance when refund is issued
    const { bankAccountId } = req.body;
    if (bankAccountId) {
      try {
        const PaymentAccount = mongoose.models.PaymentAccount
          || mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
        
        console.log(`🔍 [CN Refund] Updating PaymentAccount balance: accountId=${bankAccountId}, amount=-₹${amount}`);
        
        const accountBefore = await PaymentAccount.findById(bankAccountId).lean();
        console.log(`🔍 [CN Refund] PaymentAccount BEFORE: currentBalance = ₹${accountBefore?.currentBalance}`);
        
        await PaymentAccount.findByIdAndUpdate(bankAccountId, {
          $inc: { currentBalance: -parseFloat(amount) }
        });
        
        const accountAfter = await PaymentAccount.findById(bankAccountId).lean();
        console.log(`✅ [CN Refund] PaymentAccount balance reduced: -₹${amount} → new balance: ₹${accountAfter?.currentBalance}`);
      } catch (paErr) {
        console.error('⚠️ PaymentAccount update error (credit note refund):', paErr.message);
      }
    } else {
      console.log('⚠️ [CN Refund] No bankAccountId provided, skipping PaymentAccount balance update');
    }

    // ── ProviderTransaction Handling ─────────────────────────────────────────
    // NOTE: ProviderTransaction should be created/updated by the caller:
    // - If called from bank categorization: caller uses mark-categorized endpoint
    // - If standalone refund: caller creates ProviderTransaction separately
    // We do NOT create it here to avoid duplicates.
    console.log(`✅ [CN Refund] Refund recorded. ProviderTransaction should be handled by caller.`);

    // ── Update Customer Profile ──────────────────────────────────────────────
    // Reduce unusedCredits (credit consumed by refund)
    try {
      const Customer = mongoose.models.BillingCustomer
        || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
      
      console.log(`🔍 [CN Refund] Updating customer unusedCredits: customerId=${creditNote.customerId}, amount=-₹${amount}`);
      
      const customerBefore = await Customer.findById(creditNote.customerId).lean();
      console.log(`🔍 [CN Refund] Customer BEFORE: unusedCredits = ₹${customerBefore?.unusedCredits || 0}`);
      
      await Customer.findByIdAndUpdate(creditNote.customerId, {
        $inc: { unusedCredits: -parseFloat(amount) }
      });
      
      const customerAfter = await Customer.findById(creditNote.customerId).lean();
      console.log(`✅ [CN Refund] Customer unusedCredits updated: -₹${amount} → new balance: ₹${customerAfter?.unusedCredits || 0}`);
    } catch (custErr) {
      console.error('⚠️ Customer unusedCredits update error (credit note refund):', custErr.message);
    }
    
    console.log(`✅ Refund recorded: ${creditNote.creditNoteNumber} - ₹${amount}`);

    // Return the credit note AND the new refund sub-doc _id so the frontend
    // can store it as journalRef for precise reversal on uncategorize.
    const newRefund = creditNote.refunds[creditNote.refunds.length - 1];
    res.json({
      success: true,
      message: 'Refund recorded successfully',
      data: {
        ...creditNote.toObject(),
        refundId: newRefund?._id?.toString() || null,
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
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
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
    // STEP 4 — Update Customer Profile
    // ================================================================
    // Reduce unusedCredits (credit consumed) and outstanding (invoice due reduced)
    try {
      const Customer = mongoose.models.BillingCustomer
        || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');
      
      console.log(`🔍 [CN Apply] Updating customer profile: customerId=${creditNote.customerId}`);
      console.log(`  - unusedCredits: -₹${applyAmount}`);
      console.log(`  - outstanding: -₹${applyAmount}`);
      
      const customerBefore = await Customer.findById(creditNote.customerId).lean();
      console.log(`🔍 [CN Apply] Customer BEFORE: unusedCredits=₹${customerBefore?.unusedCredits || 0}, outstanding=₹${customerBefore?.outstanding || 0}`);
      
      await Customer.findByIdAndUpdate(creditNote.customerId, {
        $inc: { 
          unusedCredits: -applyAmount,  // Credit consumed
          outstanding: -applyAmount      // Invoice due reduced
        }
      });
      
      const customerAfter = await Customer.findById(creditNote.customerId).lean();
      console.log(`✅ [CN Apply] Customer profile updated:`);
      console.log(`  - unusedCredits: ₹${customerBefore?.unusedCredits || 0} → ₹${customerAfter?.unusedCredits || 0}`);
      console.log(`  - outstanding: ₹${customerBefore?.outstanding || 0} → ₹${customerAfter?.outstanding || 0}`);
    } catch (custErr) {
      console.error('⚠️ Customer profile update error (credit note apply):', custErr.message);
    }

    // ================================================================
    // STEP 5 — COA Posting
    // No new COA entry needed here because:
    // - When CN was created: Sales debited + AR credited already
    // - The AR reduction already happened at CN creation
    // We just log it for clarity
    // ================================================================
    console.log(`✅ COA already handled at Credit Note creation — no additional entry needed`);

    // ================================================================
    // STEP 6 — Return response
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

// ============================================================================
// DELETE APPLICATION (UNAPPLY CREDIT FROM INVOICE) — PART 5
// ============================================================================
// DELETE /api/finance/credit-notes/:id/applications/:appId
// Reverses a credit application — restores invoice due, credit note balance,
// and customer profile (unusedCredits + outstanding).
// NO COA posting needed (AR to AR was net zero at application time).
// ============================================================================
router.delete('/:id/applications/:appId', async (req, res) => {
  try {
    console.log('═══════════════════════════════════════════════════════════════');
    console.log(`🔍 [DELETE Application] START — creditNoteId=${req.params.id} appId=${req.params.appId}`);
    console.log('═══════════════════════════════════════════════════════════════');

    // ================================================================
    // STEP 1 — Find and validate credit note
    // ================================================================
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
    });

    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }

    console.log(`🔍 [DELETE Application] Credit Note: ${creditNote.creditNoteNumber}`);
    console.log(`  - Status: ${creditNote.status}`);
    console.log(`  - Total: ₹${creditNote.totalAmount}`);
    console.log(`  - Used: ₹${creditNote.creditUsed}`);
    console.log(`  - Balance: ₹${creditNote.creditBalance}`);
    console.log(`  - Applications: ${creditNote.creditApplications?.length || 0}`);

    // ================================================================
    // STEP 2 — Find the application in creditApplications array
    // ================================================================
    const appId = req.params.appId;
    const appIndex = creditNote.creditApplications.findIndex(
      app => app._id.toString() === appId
    );

    if (appIndex === -1) {
      return res.status(404).json({
        success: false,
        error: `Application ${appId} not found in credit note ${creditNote.creditNoteNumber}`
      });
    }

    const application = creditNote.creditApplications[appIndex];
    const appliedAmount = application.amount;
    const invoiceId = application.invoiceId;
    const invoiceNumber = application.invoiceNumber;

    console.log(`🔍 [DELETE Application] Found application:`, {
      appId,
      invoiceId: invoiceId?.toString(),
      invoiceNumber,
      amount: appliedAmount,
      appliedDate: application.appliedDate,
    });

    // ================================================================
    // STEP 3 — Find and validate the invoice
    // ================================================================
    const invoice = await Invoice.findById(invoiceId);

    if (!invoice) {
      return res.status(404).json({
        success: false,
        error: `Invoice ${invoiceNumber || invoiceId} not found`
      });
    }

    console.log(`🔍 [DELETE Application] Invoice BEFORE:`, {
      invoiceNumber: invoice.invoiceNumber,
      totalAmount: invoice.totalAmount,
      amountPaid: invoice.amountPaid,
      amountDue: invoice.amountDue,
      status: invoice.status,
    });

    // ================================================================
    // STEP 4 — Restore Invoice (reduce amountPaid, increase amountDue)
    // ================================================================
    const newAmountPaid = Math.max(0, (invoice.amountPaid || 0) - appliedAmount);
    const newAmountDue = invoice.totalAmount - newAmountPaid;

    // Determine new invoice status
    let newStatus = invoice.status;
    if (newAmountDue >= invoice.totalAmount) {
      newStatus = 'OPEN';
    } else if (newAmountPaid > 0 && newAmountDue > 0) {
      newStatus = 'PARTIALLY_PAID';
    } else if (newAmountDue <= 0) {
      newStatus = 'PAID';
    }

    // Remove the payment record from invoice.payments array
    await Invoice.findByIdAndUpdate(
      invoice._id,
      {
        $set: {
          amountPaid: newAmountPaid,
          amountDue: newAmountDue,
          status: newStatus,
          updatedAt: new Date()
        },
        $pull: {
          payments: { referenceNumber: creditNote.creditNoteNumber }
        }
      },
      { new: true }
    );

    console.log(`✅ [DELETE Application] Invoice AFTER:`, {
      invoiceNumber: invoice.invoiceNumber,
      amountPaid: newAmountPaid,
      amountDue: newAmountDue,
      status: newStatus,
    });

    // ================================================================
    // STEP 5 — Remove application from credit note
    // ================================================================
    creditNote.creditApplications.splice(appIndex, 1);
    await creditNote.save(); // pre-save hook recalculates creditUsed + creditBalance

    console.log(`✅ [DELETE Application] Credit Note AFTER:`, {
      creditNoteNumber: creditNote.creditNoteNumber,
      totalAmount: creditNote.totalAmount,
      creditUsed: creditNote.creditUsed,
      creditBalance: creditNote.creditBalance,
      status: creditNote.status,
      applications: creditNote.creditApplications.length,
    });

    // ================================================================
    // STEP 6 — Restore Customer Profile (unusedCredits + outstanding)
    // ================================================================
    try {
      const Customer = mongoose.models.BillingCustomer
        || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');

      console.log(`🔍 [DELETE Application] Updating customer profile: customerId=${creditNote.customerId}`);
      console.log(`  - unusedCredits: +₹${appliedAmount}`);
      console.log(`  - outstanding: +₹${appliedAmount}`);

      const customerBefore = await Customer.findById(creditNote.customerId).lean();
      console.log(`🔍 [DELETE Application] Customer BEFORE:`, {
        unusedCredits: customerBefore?.unusedCredits || 0,
        outstanding: customerBefore?.outstanding || 0,
      });

      await Customer.findByIdAndUpdate(creditNote.customerId, {
        $inc: {
          unusedCredits: appliedAmount,  // Restore credit
          outstanding: appliedAmount      // Restore invoice due
        }
      });

      const customerAfter = await Customer.findById(creditNote.customerId).lean();
      console.log(`✅ [DELETE Application] Customer AFTER:`, {
        unusedCredits: customerAfter?.unusedCredits || 0,
        outstanding: customerAfter?.outstanding || 0,
      });
    } catch (custErr) {
      console.error('⚠️ [DELETE Application] Customer profile update error:', custErr.message);
    }

    // ================================================================
    // STEP 7 — NO COA Posting (AR to AR was net zero)
    // ================================================================
    console.log(`✅ [DELETE Application] NO COA posting needed (AR to AR net zero)`);

    // ================================================================
    // STEP 8 — Return response
    // ================================================================
    console.log('═══════════════════════════════════════════════════════════════');
    console.log(`✅ [DELETE Application] COMPLETE — Application deleted successfully`);
    console.log('═══════════════════════════════════════════════════════════════');

    res.json({
      success: true,
      message: `Credit application of ₹${appliedAmount} removed from ${invoice.invoiceNumber} successfully`,
      data: {
        creditNote: {
          creditNoteNumber: creditNote.creditNoteNumber,
          totalAmount: creditNote.totalAmount,
          creditUsed: creditNote.creditUsed,
          creditBalance: creditNote.creditBalance,
          status: creditNote.status,
        },
        invoice: {
          invoiceNumber: invoice.invoiceNumber,
          totalAmount: invoice.totalAmount,
          amountPaid: newAmountPaid,
          amountDue: newAmountDue,
          status: newStatus,
        },
        deletedApplication: {
          appId,
          amount: appliedAmount,
          invoiceNumber,
        }
      }
    });

  } catch (error) {
    console.error('❌ [DELETE Application] Error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});


// DOWNLOAD PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    const pdfInfo = await generateCreditNotePDF(creditNote, creditNote.orgId, creditNote.branchId);
    creditNote.pdfPath = pdfInfo.filepath;
    creditNote.pdfGeneratedAt = new Date();
    await creditNote.save();
    
    res.download(pdfInfo.filepath, `CreditNote-${creditNote.creditNoteNumber}.pdf`);
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
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
    });
    
    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }
    
    const pdfInfo = await generateCreditNotePDF(creditNote, creditNote.orgId, creditNote.branchId);
    creditNote.pdfPath = pdfInfo.filepath;
    creditNote.pdfGeneratedAt = new Date();
    await creditNote.save();
    
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
    const creditNote = await CreditNote.findOne({ _id: req.params.id, orgId: req.user?.orgId, ...(req.branchFilter || {}) });
    if (!creditNote) return res.status(404).json({ success: false, error: 'Credit note not found' });
    const org = await getCnOrgData(req.user?.orgId, req.branchIds?.length === 1 ? req.branchIds[0] : null);
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
      ${(creditNote.invoiceDiscountAmount || 0) > 0 ? `<tr><td>Discount</td><td>-Rs.${creditNote.invoiceDiscountAmount.toFixed(2)}</td></tr>` : ''}
      ${creditNote.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${creditNote.cgst.toFixed(2)}</td></tr>` : ''}
      ${creditNote.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${creditNote.sgst.toFixed(2)}</td></tr>` : ''}
      ${(creditNote.shippingCharges || 0) > 0 ? `<tr><td>Shipping</td><td>Rs.${creditNote.shippingCharges.toFixed(2)}</td></tr>` : ''}
      ${creditNote.adjustment && creditNote.adjustment !== 0 ? `<tr><td>Adjustment</td><td>${creditNote.adjustment > 0 ? '+' : ''}Rs.${creditNote.adjustment.toFixed(2)}</td></tr>` : ''}
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

// DELETE credit note — allowed for any status, fully reverses COA + invoice balances
router.delete('/:id', async (req, res) => {
  try {
    const creditNote = await CreditNote.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId,
      ...(req.branchFilter || {}),
    });

    if (!creditNote) {
      return res.status(404).json({ success: false, error: 'Credit note not found' });
    }

    // ── STEP 1: REVERSE INVOICE APPLICATIONS ────────────────────────────────
    // Walk every creditApplication and roll back the invoice's amountPaid/amountDue/status
    try {
      if (creditNote.creditApplications && creditNote.creditApplications.length > 0) {
        for (const app of creditNote.creditApplications) {
          if (!app.invoiceId) continue;
          const invoice = await Invoice.findById(app.invoiceId);
          if (!invoice) continue;

          const reversedAmountPaid = Math.max(0, (invoice.amountPaid || 0) - app.amount);
          const reversedAmountDue  = invoice.totalAmount - reversedAmountPaid;

          let newStatus = invoice.status;
          if (reversedAmountPaid <= 0) {
            newStatus = 'SENT';
          } else if (reversedAmountPaid > 0 && reversedAmountDue > 0) {
            newStatus = 'PARTIALLY_PAID';
          }

          await Invoice.findByIdAndUpdate(invoice._id, {
            $pull:  { payments: { referenceNumber: creditNote.creditNoteNumber } },
            $set:   { amountPaid: reversedAmountPaid, amountDue: reversedAmountDue, status: newStatus, updatedAt: new Date() }
          });

          console.log(`✅ Invoice ${invoice.invoiceNumber} rolled back — amountPaid: ${reversedAmountPaid}, status: ${newStatus}`);
        }
      }
    } catch (invoiceReverseErr) {
      console.error('⚠️ Invoice rollback error (credit note delete):', invoiceReverseErr.message);
    }
    // ── END INVOICE REVERSAL ─────────────────────────────────────────────────

    // ── STEP 2: REVERSE COA ENTRIES ──────────────────────────────────────────
    // Reverse the 3 entries posted at creation:
    //   Creation posted: Dr Sales, Cr AR, Dr Tax Payable
    //   Reversal posts:  Cr Sales, Dr AR, Cr Tax Payable
    try {
      const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');
      const currentOrgId = req.user?.orgId || null;
      const currentBranchId = creditNote.branchId || (req.branchIds?.length > 0 ? req.branchIds[0] : null);
      const txnDate      = new Date(creditNote.creditNoteDate);
      const desc         = `REVERSAL - Credit Note ${creditNote.creditNoteNumber} - ${creditNote.customerName}`;

      const [salesId, arId, otherChargesId] = await Promise.all([
        resolveSystemAccountId(ChartOfAccount, 'Sales', currentOrgId, currentBranchId),
        resolveSystemAccountId(ChartOfAccount, 'Accounts Receivable', currentOrgId, currentBranchId),
        resolveSystemAccountId(ChartOfAccount, 'Other Charges', currentOrgId, currentBranchId),
      ]);

      // Cr Sales (reverses the Dr posted at creation)
      if (salesId) await postTransactionToCOA({
        accountId: salesId, orgId: currentOrgId, branchId: currentBranchId, date: txnDate, description: desc,
        referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber,
        debit: 0, credit: creditNote.subTotal,
      });

      // Dr Accounts Receivable (reverses the Cr posted at creation)
      if (arId) await postTransactionToCOA({
        accountId: arId, orgId: currentOrgId, branchId: currentBranchId, date: txnDate, description: desc,
        referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber,
        debit: creditNote.totalAmount, credit: 0,
      });

      // Reverse Adjustment if any (Reverse of Create COA)
      if (otherChargesId && creditNote.adjustment) {
        if (creditNote.adjustment < 0) {
          // Reverses Credit posted at creation = Debit
          await postTransactionToCOA({ accountId: otherChargesId, orgId: currentOrgId, branchId: currentBranchId, date: txnDate, description: desc, referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber, debit: Math.abs(creditNote.adjustment), credit: 0 });
        } else {
          // Reverses Debit posted at creation = Credit
          await postTransactionToCOA({ accountId: otherChargesId, orgId: currentOrgId, branchId: currentBranchId, date: txnDate, description: desc, referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber, debit: 0, credit: creditNote.adjustment });
        }
      }

      // Cr Tax Payable (reverses the Dr posted at creation, if GST existed)
      if ((creditNote.cgst || 0) + (creditNote.sgst || 0) > 0) {
        const taxId = await resolveSystemAccountId(ChartOfAccount, 'Tax Payable', currentOrgId, currentBranchId);
        if (taxId) await postTransactionToCOA({
          accountId: taxId, orgId: currentOrgId, branchId: currentBranchId, date: txnDate, description: desc,
          referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber,
          debit: 0, credit: (creditNote.cgst || 0) + (creditNote.sgst || 0),
        });
      }

      console.log(`✅ COA reversed for deleted credit note: ${creditNote.creditNoteNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA reversal error (credit note delete):', coaErr.message);
    }
    // ── END COA REVERSAL ─────────────────────────────────────────────────────

    // ── STEP 3: UPDATE CUSTOMER PROFILE ──────────────────────────────────────
    // Remove the unused credit balance from customer's unusedCredits
    // ONLY if the credit note was OPEN (DRAFT credit notes never added to unusedCredits)
    console.log('═══════════════════════════════════════════════════════════════════');
    console.log('🔍 [CREDIT NOTE DELETE] Checking if unusedCredits should be removed');
    console.log(`   Credit Note Number: ${creditNote.creditNoteNumber}`);
    console.log(`   Credit Note Status: ${creditNote.status}`);
    console.log(`   Credit Balance: ₹${creditNote.creditBalance || 0}`);
    console.log(`   Customer ID: ${creditNote.customerId}`);
    console.log('═══════════════════════════════════════════════════════════════════');
    
    try {
      const Customer = mongoose.models.BillingCustomer
        || mongoose.model('BillingCustomer', new mongoose.Schema({}, { strict: false }), 'billing-customers');

      const unusedBalance = creditNote.creditBalance || 0;

      if (creditNote.status === 'OPEN' || creditNote.status === 'CLOSED') {
        console.log(`✅ [CN Delete] Status is ${creditNote.status} - WILL REMOVE from unusedCredits`);
        
        const customerBefore = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Delete] Customer BEFORE delete:`);
        console.log(`   - Customer Name: ${customerBefore?.customerDisplayName || 'N/A'}`);
        console.log(`   - Current unusedCredits: ₹${customerBefore?.unusedCredits || 0}`);
        
        console.log(`🔄 [CN Delete] Removing ₹${unusedBalance} from unusedCredits...`);

        await Customer.findByIdAndUpdate(creditNote.customerId, {
          $inc: { unusedCredits: -unusedBalance }
        });

        const customerAfter = await Customer.findById(creditNote.customerId).lean();
        console.log(`📊 [CN Delete] Customer AFTER delete:`);
        console.log(`   - New unusedCredits: ₹${customerAfter?.unusedCredits || 0}`);
        console.log(`   - Change: -₹${unusedBalance}`);
        console.log(`✅ [CN Delete] Customer unusedCredits SUCCESSFULLY UPDATED!`);
      } else {
        console.log(`⚠️ [CN Delete] Status is ${creditNote.status} - NOT REMOVING from unusedCredits`);
        console.log(`   Reason: DRAFT credit notes never added to unusedCredits`);
      }
    } catch (custErr) {
      console.error('❌ [CN Delete] ERROR updating customer unusedCredits:', custErr.message);
      console.error('   Stack:', custErr.stack);
    }
    console.log('═══════════════════════════════════════════════════════════════════\n');
    // ── END CUSTOMER UPDATE ──────────────────────────────────────────────────

    // ── STEP 4: DELETE ───────────────────────────────────────────────────────
    await creditNote.deleteOne();

    console.log(`✅ Credit Note deleted: ${creditNote.creditNoteNumber}`);

    res.json({ success: true, message: 'Credit note deleted successfully' });
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
          branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
        };
        
        // Calculate item amount
        creditNoteData.items[0].amount = calculateItemAmount(creditNoteData.items[0]);
        
        // Generate credit note number
        creditNoteData.creditNoteNumber = await generateCreditNoteNumber(req.user?.orgId || null, req.branchIds?.length > 0 ? req.branchIds[0] : null);
        
        // Create credit note
        const creditNote = new CreditNote(creditNoteData);
        await creditNote.save();

        // ── COA posting (same as regular create) ─────────────────────────────
        try {
          const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');
          const currentOrgId = req.user?.orgId || null;
          const [salesId, arId] = await Promise.all([
            ChartOfAccount.findOne({ accountName: 'Sales', isSystemAccount: true, orgId: currentOrgId }).select('_id').lean().then(a => a?._id),
            ChartOfAccount.findOne({ accountName: 'Accounts Receivable', isSystemAccount: true, orgId: currentOrgId }).select('_id').lean().then(a => a?._id),
          ]);
          const txnDate = new Date(creditNote.creditNoteDate);
          const desc    = `Credit Note ${creditNote.creditNoteNumber} - ${creditNote.customerName}`;

          // Dr Sales (reverse revenue)
          if (salesId) await postTransactionToCOA({ accountId: salesId, orgId: currentOrgId, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, date: txnDate, description: desc, referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber, debit: creditNote.subTotal, credit: 0 });
          // Cr Accounts Receivable (reduce AR)
          if (arId)    await postTransactionToCOA({ accountId: arId,    orgId: currentOrgId, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, date: txnDate, description: desc, referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber, debit: 0, credit: creditNote.totalAmount });

          // Dr Tax Payable if GST exists
          const gstTotal = (creditNote.cgst || 0) + (creditNote.sgst || 0) + (creditNote.igst || 0);
          if (gstTotal > 0) {
            const taxId = await ChartOfAccount.findOne({ accountName: 'Tax Payable', isSystemAccount: true, orgId: currentOrgId }).select('_id').lean().then(a => a?._id);
            if (taxId) await postTransactionToCOA({ accountId: taxId, orgId: currentOrgId, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, date: txnDate, description: `GST Reversal - ${desc}`, referenceType: 'Credit Note', referenceId: creditNote._id, referenceNumber: creditNote.creditNoteNumber, debit: gstTotal, credit: 0 });
          }
          console.log(`   ✅ COA posted for imported credit note: ${creditNote.creditNoteNumber}`);
        } catch (coaErr) {
          console.error(`   ⚠️ COA post error (credit note import line ${lineNumber}):`, coaErr.message);
        }
        // ── END COA ──────────────────────────────────────────────────────────

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
    Object.assign(query, req.branchFilter || {});
    
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