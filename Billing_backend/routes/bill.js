// ============================================================================
// BILL SYSTEM - COMPLETE BACKEND
// ============================================================================
// File: backend/routes/bill.js
// Contains: Routes, Controllers, Models, PDF Generation, Email Service
// Database: MongoDB with Mongoose
// Features: Create, Edit, Send, Payment Recording, Recurring Bills, Status Management
// Mirrors Zoho Books Bill functionality exactly
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ✅ COA Helper
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
// MONGOOSE MODELS
// ============================================================================

// Bill Schema - mirrors Zoho Books Bill structure
const billSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  billNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  vendorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
    required: true
  },
  vendorName: {
    type: String,
    required: true
  },
  vendorEmail: String,
  vendorPhone: String,
  vendorGSTIN: String,
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },

  // Bill Details
  purchaseOrderNumber: String,   // Link to PO
  billDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  dueDate: {
    type: Date,
    required: true
  },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },
  subject: String,
  notes: String,
  termsAndConditions: String,

  // Line Items
  items: [{
    itemDetails: {
      type: String,
      required: true
    },
    account: String,           // Expense account (e.g., Office Supplies)
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

  // Attachments
  attachments: [{
    filename: String,
    filepath: String,
    uploadedAt: Date
  }],

  // Financial Calculations
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

  // Status Management - Zoho Books Bill statuses
  status: {
    type: String,
    enum: ['DRAFT', 'OPEN', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'VOID', 'CANCELLED'],
    default: 'DRAFT',
    index: true
  },

  // Payment Information
  amountPaid: {
    type: Number,
    default: 0
  },
  amountDue: {
    type: Number,
    default: 0
  },
  payments: [{
    paymentId: mongoose.Schema.Types.ObjectId,
    amount: Number,
    paymentDate: Date,
    paymentMode: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online', 'NEFT', 'RTGS', 'IMPS']
    },
    referenceNumber: String,
    notes: String,
    recordedBy: String,
    recordedAt: Date
  }],

  // Vendor Credits Applied
  vendorCreditsApplied: [{
    creditId: mongoose.Schema.Types.ObjectId,
    amount: Number,
    appliedDate: Date
  }],

  // ── Currency & Exchange Rate ─────────────────────────────────────────────
  currency: {
    type: String,
    default: 'INR',
    trim: true,
    uppercase: true,
  },
  exchangeRate: {
    // Rate at time of bill creation (e.g. 1 USD = 83.50 INR)
    type: Number,
    default: 1,
    min: 0,
  },
  baseCurrencyAmount: {
    // totalAmount converted to base currency (INR)
    type: Number,
    default: 0,
  },
  // ── End Currency Fields ──────────────────────────────────────────────────

  // Recurring Bill Settings
  isRecurring: {
    type: Boolean,
    default: false
  },
  recurringProfileId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'RecurringBillProfile'
  },

  // PDF
  pdfPath: String,
  pdfGeneratedAt: Date,

  // Approval Workflow
  approvalStatus: {
    type: String,
    enum: ['PENDING_APPROVAL', 'APPROVED', 'REJECTED', null],
    default: null
  },
  approvedBy: String,
  approvedAt: Date,

  // Audit Trail
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

// Pre-save middleware to calculate amounts
billSchema.pre('save', function() {
  this.subTotal = this.items.reduce((sum, item) => sum + item.amount, 0);
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
  const gstBase   = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;
  this.cgst        = gstAmount / 2;
  this.sgst        = gstAmount / 2;
  this.igst        = 0;
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  this.amountDue   = this.totalAmount - this.amountPaid;
  this.baseCurrencyAmount = this.totalAmount * (this.exchangeRate || 1);

  if (this.status !== 'DRAFT' && this.status !== 'VOID' && this.status !== 'CANCELLED') {
    if (this.amountPaid === 0) {
      this.status = 'OPEN';
    } else if (this.amountPaid > 0 && this.amountPaid < this.totalAmount) {
      this.status = 'PARTIALLY_PAID';
    } else if (this.amountPaid >= this.totalAmount) {
      this.status = 'PAID';
    }
    if (this.status !== 'PAID' && this.dueDate < new Date()) {
      this.status = 'OVERDUE';
    }
  }
});

// Indexes for performance
billSchema.index({ vendorId: 1, billDate: -1 });
billSchema.index({ status: 1, dueDate: 1 });
billSchema.index({ createdAt: -1 });

const Bill = mongoose.models.Bill || mongoose.model('Bill', billSchema);

// ============================================================================
// VENDOR SCHEMA
// ============================================================================

const vendorSchema = new mongoose.Schema({
  vendorName: {
    type: String,
    required: true,
    trim: true,
    index: true
  },
  vendorEmail: {
    type: String,
    required: true,
    trim: true,
    lowercase: true,
    index: true
  },
  vendorPhone: {
    type: String,
    required: true,
    trim: true
  },
  companyName: {
    type: String,
    trim: true
  },
  gstNumber: {
    type: String,
    trim: true,
    uppercase: true
  },
  panNumber: {
    type: String,
    trim: true,
    uppercase: true
  },
  billingAddress: {
    street: { type: String, trim: true },
    city: { type: String, trim: true },
    state: { type: String, trim: true },
    pincode: { type: String, trim: true },
    country: { type: String, default: 'India', trim: true }
  },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },
  bankDetails: {
    accountHolder: String,
    accountNumber: String,
    ifscCode: String,
    bankName: String,
    upiId: String
  },
  notes: String,
  isActive: {
    type: Boolean,
    default: true,
    index: true
  },
  createdBy: { type: String, required: true },
  updatedBy: String,
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
}, {
  timestamps: true,
  collection: 'vendors'
});

vendorSchema.index({ vendorName: 1, vendorEmail: 1 });
vendorSchema.index({ createdAt: -1 });

vendorSchema.pre('save', function() {
  this.updatedAt = new Date();
});

// Check if model exists before creating to avoid OverwriteModelError
const Vendor = mongoose.models.Vendor || mongoose.model('Vendor', vendorSchema);

// ============================================================================
// RECURRING BILL PROFILE SCHEMA
// ============================================================================

const recurringBillProfileSchema = new mongoose.Schema({
  profileName: {
    type: String,
    required: true
  },
  vendorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
    required: true
  },
  vendorName: String,
  vendorEmail: String,

  // Recurrence Settings
  repeatEvery: {
    type: Number,
    required: true,
    default: 1
  },
  repeatUnit: {
    type: String,
    enum: ['days', 'weeks', 'months', 'years'],
    default: 'months'
  },
  startDate: {
    type: Date,
    required: true
  },
  endDate: Date,
  maxOccurrences: Number,
  occurrencesCount: {
    type: Number,
    default: 0
  },

  // Bill Template
  billTemplate: {
    items: [{
      itemDetails: String,
      account: String,
      quantity: Number,
      rate: Number,
      discount: Number,
      discountType: String,
      amount: Number
    }],
    paymentTerms: String,
    subject: String,
    notes: String,
    tdsRate: Number,
    tcsRate: Number,
    gstRate: Number
  },

  // Status
  status: {
    type: String,
    enum: ['ACTIVE', 'PAUSED', 'EXPIRED', 'STOPPED'],
    default: 'ACTIVE'
  },

  // Next bill date
  nextBillDate: Date,
  lastBillDate: Date,

  // Bills generated from this profile
  generatedBills: [{
    billId: mongoose.Schema.Types.ObjectId,
    billNumber: String,
    createdDate: Date
  }],

  createdBy: String,
  updatedBy: String,
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
}, { timestamps: true });

const RecurringBillProfile = mongoose.models.RecurringBillProfile || mongoose.model('RecurringBillProfile', recurringBillProfileSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate unique bill number
async function generateBillNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(Bill, 'billNumber', 'BILL', orgId);
}

// Calculate due date based on payment terms
function calculateDueDate(billDate, terms) {
  const date = new Date(billDate);
  switch (terms) {
    case 'Due on Receipt': return date;
    case 'Net 15': date.setDate(date.getDate() + 15); return date;
    case 'Net 30': date.setDate(date.getDate() + 30); return date;
    case 'Net 45': date.setDate(date.getDate() + 45); return date;
    case 'Net 60': date.setDate(date.getDate() + 60); return date;
    default: date.setDate(date.getDate() + 30); return date;
  }
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
// PDF GENERATION (invoices.js style)
// ============================================================================

async function generateBillPDF(bill, orgId) {
  return new Promise(async (resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'bills');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
      const filename = `bill-${bill.billNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      let orgName = 'Your Company', orgGST = '', orgAddr = '', orgEmail = '', orgPhone = '', orgData = null;
      try {
        const OrgModel = mongoose.models.Organization || mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
        orgData = await OrgModel.findOne({ orgId }).lean();
        if (orgData) { orgName = orgData.orgName || orgName; orgGST = orgData.gstNumber || ''; orgAddr = orgData.address || ''; orgEmail = orgData.email || ''; orgPhone = orgData.phone || ''; }
      } catch (e) {}

      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);
      const pageW = 515;

      // Header
      doc.rect(40, 30, pageW, 90).fill('#0f1e3d');
      let logoLoaded = false;
      const logoPath = (() => { try { const d = path.join(__dirname, '..', 'uploads', 'org-logos'); if (fs.existsSync(d)) { const f = fs.readdirSync(d).find(x => x.startsWith(`org-${orgId}-`)); if (f) return path.join(d, f); } } catch (_) {} const fb = [path.join(__dirname,'..','assets','abra.jpeg'),path.join(__dirname,'..','assets','abra.jpg'),path.join(__dirname,'..','assets','abra.png')]; for (const p of fb) { try { if (fs.existsSync(p)) return p; } catch (_) {} } return null; })();
      if (logoPath) { try { doc.image(logoPath, 44, 35, { width: 75, height: 60, fit: [75, 60] }); logoLoaded = true; } catch (e) {} }
      const textX = logoLoaded ? 126 : 50;
      doc.fontSize(12).fillColor('#ffffff').font('Helvetica-Bold').text(orgName.toUpperCase(), textX, 40, { width: 200 });
      doc.fontSize(7).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text('BILLING & FINANCE', textX, 56, { width: 200, characterSpacing: 1 });
      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)');
      let cY = 68; contactLines.forEach(l => { doc.text(l, textX, cY, { width: 240 }); cY += 9; });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').font('Helvetica-Bold').text('BILL', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold').text(bill.billNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.8)').font('Helvetica').text(`Date: ${new Date(bill.billDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold').text(`Due: ${new Date(bill.dueDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })} · ${(bill.status || 'DRAFT').replace(/_/g,' ')}`, 380, 92, { width: 170, align: 'right' });

      // Meta boxes
      const metaY = 132, metaBoxW = pageW / 2;
      const metas = [
        { label: 'Bill From', val: bill.vendorName || 'N/A', sub: [bill.billingAddress?.street, bill.billingAddress?.city, bill.vendorEmail, bill.vendorPhone].filter(Boolean).join(' | ') },
        { label: 'Bill Details', val: `Due: ${new Date(bill.dueDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}`, sub: `Terms: ${bill.paymentTerms || 'Net 30'}${bill.purchaseOrderNumber ? ' | PO: ' + bill.purchaseOrderNumber : ''}` },
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
      bill.items.forEach((item, idx) => {
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
      tRow('Subtotal:', `Rs. ${(bill.subTotal || 0).toFixed(2)}`);
      if (bill.cgst > 0) tRow(`CGST (${bill.gstRate / 2}%):`, `Rs. ${bill.cgst.toFixed(2)}`);
      if (bill.sgst > 0) tRow(`SGST (${bill.gstRate / 2}%):`, `Rs. ${bill.sgst.toFixed(2)}`);
      if (bill.igst > 0) tRow(`IGST (${bill.gstRate}%):`, `Rs. ${bill.igst.toFixed(2)}`);
      if (bill.tdsAmount > 0) tRow('TDS Deducted:', `- Rs. ${bill.tdsAmount.toFixed(2)}`);
      if (bill.tcsAmount > 0) tRow('TCS Collected:', `Rs. ${bill.tcsAmount.toFixed(2)}`);
      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text('Grand Total', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold').text(`Rs. ${(bill.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;
      if (bill.amountPaid > 0) { tRow('Amount Paid:', `Rs. ${bill.amountPaid.toFixed(2)}`); tRow('Balance Due:', `Rs. ${(bill.amountDue || 0).toFixed(2)}`, true); }

      // Amount in words
      const wordsY = totalsY + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold').text(`In Words: ${numberToWords(Math.round(bill.totalAmount || 0))} Only`, 48, wordsY + 5, { width: pageW - 16 });

      // Notes
      if (bill.notes) {
        const nY = wordsY + 28;
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold').text('NOTES', 40, nY, { characterSpacing: 0.8 });
        doc.moveTo(40, nY + 9).lineTo(555, nY + 9).lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica').text(bill.notes, 40, nY + 14, { width: pageW });
      }

      // T&C
      if (bill.termsAndConditions) {
        const tcY = 660;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold').text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica').text(bill.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // Footer
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY).lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica').text(`${orgName} · ${orgGST ? 'GSTIN: ' + orgGST + ' · ' : ''}${bill.billNumber}`, 40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`, 40, footY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => { resolve({ filename, filepath, relativePath: `/uploads/bills/${filename}` }); });
      stream.on('error', reject);
    } catch (error) { reject(error); }
  });
}
// ============================================================================
// EMAIL SERVICE
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD }
});

async function sendBillEmail(bill, pdfPath, orgId) {
  let orgName = '', orgGST = '', orgPhone = '', orgEmail = '', orgData = null;
  try {
    const OrgModel = mongoose.models.Organization || mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    orgData = await OrgModel.findOne({ orgId }).lean();
    if (orgData) { orgName = orgData.orgName || ''; orgGST = orgData.gstNumber || ''; orgPhone = orgData.phone || ''; orgEmail = orgData.email || ''; }
  } catch (e) {}

  const billDateStr = new Date(bill.billDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
  const dueDateStr  = new Date(bill.dueDate).toLocaleDateString('en-IN',  { day:'2-digit', month:'long', year:'numeric' });

  const emailHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Bill ${bill.billNumber}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }
    .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }
    .header { background: #0f1e3d; padding: 24px 32px; }
    .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }
    .header p  { color: rgba(255,255,255,0.7); font-size: 11px; letter-spacing: 0.5px; }
    .header .inv-num { color: #fff; font-size: 14px; font-weight: bold; margin-top: 8px; }
    .body { padding: 28px 32px; }
    .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase; letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0; padding-bottom: 6px; margin: 22px 0 12px; }
    table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }
    table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }
    table.detail td:first-child { color: #555; width: 160px; }
    table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }
    .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222; border-bottom: none; padding-top: 10px; }
    .balance-row td { color: #b91c1c; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706; padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px; font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Bill</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${bill.billNumber}</div>
  </div>
  <div class="body">
    <p style="font-size:14px;color:#222;margin-bottom:18px;">Dear ${bill.vendorName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached bill <strong>${bill.billNumber}</strong> for your reference.
    </p>
    <div class="section-title">Bill Details</div>
    <table class="detail">
      <tr><td>Bill Number</td>   <td>${bill.billNumber}</td></tr>
      <tr><td>Bill Date</td>     <td>${billDateStr}</td></tr>
      <tr><td>Due Date</td>      <td>${dueDateStr}</td></tr>
      <tr><td>Payment Terms</td> <td>${bill.paymentTerms || 'Net 30'}</td></tr>
      ${bill.purchaseOrderNumber ? `<tr><td>PO Number</td><td>${bill.purchaseOrderNumber}</td></tr>` : ''}
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(bill.subTotal || 0).toFixed(2)}</td></tr>
      ${bill.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${bill.cgst.toFixed(2)}</td></tr>` : ''}
      ${bill.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${bill.sgst.toFixed(2)}</td></tr>` : ''}
      ${bill.tdsAmount > 0 ? `<tr><td>TDS Deducted</td><td>- Rs.${bill.tdsAmount.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs.${(bill.totalAmount || 0).toFixed(2)}</td></tr>
      ${bill.amountPaid > 0 ? `<tr><td>Amount Paid</td><td>Rs.${bill.amountPaid.toFixed(2)}</td></tr>` : ''}
      ${bill.amountDue > 0 ? `<tr class="balance-row"><td>Balance Due</td><td>Rs.${bill.amountDue.toFixed(2)}</td></tr>` : ''}
    </table>
    ${bill.notes ? `<div class="section-title">Notes</div><div class="notes-box">${bill.notes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The bill PDF is attached to this email for your records.
    </p>
  </div>
  <div class="footer">
    <strong>Thank you for your business.</strong><br>
    ${orgData?.orgName || ''} &nbsp;|&nbsp; ${orgData?.email || process.env.SMTP_USER || ''} &nbsp;|&nbsp; This is a system-generated email.
  </div>
</div>
</body>
</html>`;

  return emailTransporter.sendMail({
    from: `"Accounts" <${process.env.SMTP_USER}>`,
    to: bill.vendorEmail || process.env.BILLING_EMAIL || process.env.SMTP_USER,
    subject: `Bill ${bill.billNumber} — Rs.${(bill.totalAmount || 0).toFixed(2)}`,
    html: emailHtml,
    attachments: [{ filename: `Bill-${bill.billNumber}.pdf`, path: pdfPath }]
  });
}
async function sendPaymentConfirmationEmail(bill, payment, orgId = null) {
  let orgName  = '';
  let orgGST   = '';
  let orgPhone = '';
  let orgEmail = '';
  try {
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId }).lean();
    orgName  = org?.orgName   || '';
    orgGST   = org?.gstNumber || '';
    orgPhone = org?.phone     || '';
    orgEmail = org?.email     || '';
  } catch (e) {
    console.warn('⚠️ Could not fetch org details for payment email:', e.message);
  }

  const emailHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Payment Recorded - ${bill.billNumber}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }
    .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }
    .header { background: #0f1e3d; padding: 24px 32px; }
    .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }
    .header p  { color: rgba(255,255,255,0.7); font-size: 11px; }
    .body { padding: 28px 32px; }
    .success-badge { background: #d4edda; border: 1px solid #28a745; border-radius: 6px;
                     padding: 16px; text-align: center; margin: 18px 0; }
    .success-badge h2 { color: #155724; font-size: 18px; margin-bottom: 4px; }
    .success-badge p  { color: #155724; font-size: 13px; }
    .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase;
                     letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0;
                     padding-bottom: 6px; margin: 22px 0 12px; }
    table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }
    table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }
    table.detail td:first-child { color: #555; width: 180px; }
    table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }
    .balance-row td { color: ${bill.amountDue > 0 ? '#b91c1c' : '#155724'}; }
    .paid-badge { background: #d4edda; border-radius: 4px; padding: 10px 16px;
                  text-align: center; color: #155724; font-weight: bold; margin-top: 16px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;
              font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Payment Recorded</h1>
    <p>${orgName}</p>
  </div>
  <div class="body">
    <div class="success-badge">
      <h2>✅ Payment of ₹${payment.amount.toFixed(2)} recorded</h2>
      <p>For Bill: ${bill.billNumber} — ${bill.vendorName}</p>
    </div>

    <div class="section-title">Payment Details</div>
    <table class="detail">
      <tr><td>Bill Number</td>    <td>${bill.billNumber}</td></tr>
      <tr><td>Vendor</td>         <td>${bill.vendorName}</td></tr>
      <tr><td>Amount Paid</td>    <td>₹${payment.amount.toFixed(2)}</td></tr>
      <tr><td>Payment Date</td>   <td>${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}</td></tr>
      <tr><td>Payment Mode</td>   <td>${payment.paymentMode}</td></tr>
      ${payment.referenceNumber ? `<tr><td>Reference</td><td>${payment.referenceNumber}</td></tr>` : ''}
      <tr class="balance-row"><td>Remaining Balance</td><td>₹${bill.amountDue.toFixed(2)}</td></tr>
    </table>

    ${bill.amountDue <= 0 ? `<div class="paid-badge">🎉 Bill Fully Paid — Thank You!</div>` : ''}
  </div>
  <div class="footer">
    <strong>${orgName}</strong><br>
    ${orgGST   ? 'GST: '  + orgGST   + ' &nbsp;|&nbsp; ' : ''}
    ${orgPhone ? 'Ph: '   + orgPhone  + ' &nbsp;|&nbsp; ' : ''}
    ${orgEmail || ''}
  </div>
</div>
</body>
</html>`;

  return emailTransporter.sendMail({
    from: `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
    to: process.env.BILLING_EMAIL || process.env.SMTP_USER,
    subject: `Payment Recorded — ${bill.billNumber} — ₹${payment.amount.toFixed(2)}`,
    html: emailHtml
  });
}

// ============================================================================
// API ROUTES - BILLS
// ============================================================================

// GET /api/bills - List all bills with filters
router.get('/', async (req, res) => {
  try {
    const { status, vendorId, fromDate, toDate, search, page = 1, limit = 20 } = req.query;
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;

    if (status && status !== 'All') query.status = status;
    if (vendorId) query.vendorId = vendorId;
    if (fromDate || toDate) {
      query.billDate = {};
      if (fromDate) query.billDate.$gte = new Date(fromDate);
      if (toDate) query.billDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { billNumber: { $regex: search, $options: 'i' } },
        { vendorName: { $regex: search, $options: 'i' } },
        { purchaseOrderNumber: { $regex: search, $options: 'i' } }
      ];
    }

    if (req.query.currency) query.currency = req.query.currency.toUpperCase();

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const bills = await Bill.find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).select('-__v');
    const total = await Bill.countDocuments(query);

    res.json({
      success: true,
      data: bills,
      pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) }
    });
  } catch (error) {
    console.error('Error fetching bills:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bills/stats
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const stats = await Bill.aggregate([
      { $match: orgFilter },
      { $group: { _id: '$status', count: { $sum: 1 }, totalAmount: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } }
    ]);

    const overallStats = { totalBills: 0, totalPayable: 0, totalPaid: 0, totalDue: 0, byStatus: {} };
    stats.forEach(stat => {
      overallStats.totalBills += stat.count;
      overallStats.totalPayable += stat.totalAmount;
      overallStats.totalPaid += stat.totalPaid;
      overallStats.totalDue += stat.totalDue;
      overallStats.byStatus[stat._id] = { count: stat.count, amount: stat.totalAmount };
    });

    res.json({ success: true, data: overallStats });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// VENDOR ROUTES - Before /:id to avoid conflicts
// ============================================================================

// GET /api/bills/vendors
router.get('/vendors', async (req, res) => {
  try {
    const { search, page = 1, limit = 50, active = 'true' } = req.query;
    const query = {};
    if (active !== 'all') query.isActive = active === 'true';
    if (search) {
      query.$or = [
        { vendorName: { $regex: search, $options: 'i' } },
        { vendorEmail: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } }
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const vendors = await Vendor.find(query).sort({ vendorName: 1 }).skip(skip).limit(parseInt(limit)).select('-__v');
    const total = await Vendor.countDocuments(query);

    res.json({ success: true, data: vendors, pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/vendors
router.post('/vendors', async (req, res) => {
  try {
    const vendorData = req.body;
    if (!vendorData.vendorName || !vendorData.vendorEmail || !vendorData.vendorPhone) {
      return res.status(400).json({ success: false, error: 'Vendor name, email, and phone are required' });
    }

    const existingVendor = await Vendor.findOne({ vendorEmail: vendorData.vendorEmail.toLowerCase(), isActive: true });
    if (existingVendor) {
      return res.status(400).json({ success: false, error: 'Vendor with this email already exists' });
    }

    vendorData.createdBy = req.user?.email || req.user?.uid || 'system';
    const vendor = new Vendor(vendorData);
    await vendor.save();

    res.status(201).json({ success: true, message: 'Vendor created successfully', data: vendor });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/vendors/:id
router.put('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findById(req.params.id);
    if (!vendor) return res.status(404).json({ success: false, error: 'Vendor not found' });

    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    Object.assign(vendor, updates);
    await vendor.save();

    res.json({ success: true, message: 'Vendor updated successfully', data: vendor });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/bills/vendors/:id - Soft delete
router.delete('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findById(req.params.id);
    if (!vendor) return res.status(404).json({ success: false, error: 'Vendor not found' });

    vendor.isActive = false;
    vendor.updatedBy = req.user?.email || req.user?.uid || 'system';
    await vendor.save();

    res.json({ success: true, message: 'Vendor deactivated successfully' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bills/vendors/:id
router.get('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findById(req.params.id);
    if (!vendor) return res.status(404).json({ success: false, error: 'Vendor not found' });
    res.json({ success: true, data: vendor });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// RECURRING BILL PROFILE ROUTES
// ============================================================================

// GET /api/bills/recurring-profiles
router.get('/recurring-profiles', async (req, res) => {
  try {
    const { status } = req.query;
    const query = {};
    if (status) query.status = status;

    const profiles = await RecurringBillProfile.find(query).sort({ createdAt: -1 });
    res.json({ success: true, data: profiles });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/recurring-profiles
router.post('/recurring-profiles', async (req, res) => {
  try {
    const profileData = req.body;
    profileData.createdBy = req.user?.email || req.user?.uid || 'system';

    // Calculate next bill date
    const startDate = new Date(profileData.startDate);
    profileData.nextBillDate = startDate;

    const profile = new RecurringBillProfile(profileData);
    await profile.save();

    res.status(201).json({ success: true, message: 'Recurring profile created', data: profile });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/recurring-profiles/:id/pause
router.put('/recurring-profiles/:id/pause', async (req, res) => {
  try {
    const profile = await RecurringBillProfile.findById(req.params.id);
    if (!profile) return res.status(404).json({ success: false, error: 'Profile not found' });
    profile.status = 'PAUSED';
    await profile.save();
    res.json({ success: true, message: 'Profile paused', data: profile });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/recurring-profiles/:id/resume
router.put('/recurring-profiles/:id/resume', async (req, res) => {
  try {
    const profile = await RecurringBillProfile.findById(req.params.id);
    if (!profile) return res.status(404).json({ success: false, error: 'Profile not found' });
    profile.status = 'ACTIVE';
    await profile.save();
    res.json({ success: true, message: 'Profile resumed', data: profile });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/bills/recurring-profiles/:id
router.delete('/recurring-profiles/:id', async (req, res) => {
  try {
    const profile = await RecurringBillProfile.findById(req.params.id);
    if (!profile) return res.status(404).json({ success: false, error: 'Profile not found' });
    profile.status = 'STOPPED';
    await profile.save();
    res.json({ success: true, message: 'Profile stopped' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// BILL CRUD ROUTES
// ============================================================================

// GET /api/bills/:id
router.get('/:id', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });
    res.json({ success: true, data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills - Create new bill
// POST /api/bills - Create new bill
// POST /api/vendor-credits
router.post('/', async (req, res) => {
  try {
    const body = req.body;

    if (!body.vendorId)   return errorResponse(res, 'Vendor ID is required', 400);
    if (!body.vendorName) return errorResponse(res, 'Vendor Name is required', 400);
    if (!body.reason)     return errorResponse(res, 'Reason is required', 400);
    if (!body.items || body.items.length === 0)
      return errorResponse(res, 'At least one item is required', 400);

    for (const item of body.items) {
      if (!item.itemDetails)                    return errorResponse(res, 'Item details required', 400);
      if (!item.quantity || item.quantity <= 0) return errorResponse(res, 'Item quantity must be > 0', 400);
      if (!item.rate     || item.rate     <= 0) return errorResponse(res, 'Item rate must be > 0', 400);
    }

    const credit = new VendorCredit({
      ...body,
      balanceAmount: body.totalAmount || 0,
      appliedAmount: 0,
      applications:  [],
      refunds:       [],
    });

    await credit.save();

    // ✅ COA: Full breakdown with GST + TDS + TCS
    try {
      const currentOrgId = req.user?.orgId || null;
      const [apId, cogsId, taxId, tdsPayableId, tdsReceivableId] = await Promise.all([
        getSystemAccountId('Accounts Payable', currentOrgId),
        getSystemAccountId('Cost of Goods Sold', currentOrgId),
        getSystemAccountId('Tax Payable', currentOrgId),
        getSystemAccountId('TDS Payable', currentOrgId),
        getSystemAccountId('TDS Receivable', currentOrgId),
      ]);
      const txnDate = new Date(credit.creditDate);

      if (apId) await postTransactionToCOA({
        accountId: apId, orgId: currentOrgId, date: txnDate,
        description: `Vendor Credit ${credit.creditNumber} - ${credit.vendorName}`,
        referenceType: 'VendorCredit', referenceId: credit._id,
        referenceNumber: credit.creditNumber,
        debit: credit.totalAmount, credit: 0,
      });

      if (cogsId) await postTransactionToCOA({
        accountId: cogsId, orgId: currentOrgId, date: txnDate,
        description: `Vendor Credit ${credit.creditNumber} - ${credit.vendorName}`,
        referenceType: 'VendorCredit', referenceId: credit._id,
        referenceNumber: credit.creditNumber,
        debit: 0, credit: credit.subTotal || credit.totalAmount,
      });

      if (taxId && (credit.cgst + credit.sgst) > 0) await postTransactionToCOA({
        accountId: taxId, orgId: currentOrgId, date: txnDate,
        description: `GST reversal - Vendor Credit ${credit.creditNumber}`,
        referenceType: 'VendorCredit', referenceId: credit._id,
        referenceNumber: credit.creditNumber,
        debit: 0, credit: credit.cgst + credit.sgst,
      });

      if (tdsPayableId && credit.tdsAmount > 0) await postTransactionToCOA({
        accountId: tdsPayableId, orgId: currentOrgId, date: txnDate,
        description: `TDS reversal - Vendor Credit ${credit.creditNumber}`,
        referenceType: 'VendorCredit', referenceId: credit._id,
        referenceNumber: credit.creditNumber,
        debit: credit.tdsAmount, credit: 0,
      });

      if (tdsReceivableId && credit.tcsAmount > 0) await postTransactionToCOA({
        accountId: tdsReceivableId, orgId: currentOrgId, date: txnDate,
        description: `TCS reversal - Vendor Credit ${credit.creditNumber}`,
        referenceType: 'VendorCredit', referenceId: credit._id,
        referenceNumber: credit.creditNumber,
        debit: 0, credit: credit.tcsAmount,
      });

      console.log(`✅ COA posted for vendor credit: ${credit.creditNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA error (vendor credit create):', coaErr.message);
    }

    // ✅ AUTO-APPLY TO BILL if billId is provided at creation time
    if (body.billId) {
      try {
        const Bill = mongoose.models.Bill ||
          mongoose.model('Bill', new mongoose.Schema({}, { strict: false }));

        const bill = await Bill.findById(body.billId);
        if (bill) {
          const creditAmount = parseFloat(credit.totalAmount || 0);

          // Deduct credit amount from bill
          bill.amountPaid = (bill.amountPaid || 0) + creditAmount;
          bill.amountDue  = Math.max(0, (bill.totalAmount || 0) - bill.amountPaid);

          // Update bill status
          if (bill.amountDue <= 0.01) {
            bill.status    = 'PAID';
            bill.amountDue = 0;
          } else if (bill.amountPaid > 0) {
            bill.status = 'PARTIALLY_PAID';
          }

          // Track credit applied on the bill side
          bill.vendorCreditsApplied = bill.vendorCreditsApplied || [];
          bill.vendorCreditsApplied.push({
            creditId:    credit._id,
            amount:      creditAmount,
            appliedDate: new Date(),
          });

          await bill.save();
          console.log(`✅ Bill ${bill.billNumber} auto-updated to ${bill.status}`);

          // ✅ Also update credit status to reflect it's been applied
          const totalApplied = creditAmount;
          credit.appliedAmount = totalApplied;
          credit.balanceAmount = credit.totalAmount - totalApplied;
          credit.applications.push({
            billId:      body.billId,
            billNumber:  body.billNumber || bill.billNumber,
            amount:      creditAmount,
            appliedDate: new Date(),
          });

          if (credit.balanceAmount <= 0.01) {
            credit.status        = 'CLOSED';
            credit.balanceAmount = 0;
          } else {
            credit.status = 'PARTIALLY_APPLIED';
          }

          await credit.save();
          console.log(`✅ Vendor Credit ${credit.creditNumber} auto-closed after apply`);
        } else {
          console.warn(`⚠️ Bill not found for auto-apply: ${body.billId}`);
        }
      } catch (billErr) {
        console.error('⚠️ Bill auto-apply error:', billErr.message);
      }
    }

    return successResponse(res, credit, 'Vendor credit created', 201);
  } catch (err) {
    if (err.code === 11000) {
      return errorResponse(res, 'Credit number already exists', 400, err);
    }
    return errorResponse(res, 'Failed to create vendor credit', 500, err);
  }
});

// PUT /api/bills/:id - Update bill
router.put('/:id', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status === 'PAID') {
      return res.status(400).json({ success: false, error: 'Cannot edit paid bills' });
    }

    const updates = req.body;

    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }

    if (updates.paymentTerms && updates.paymentTerms !== bill.paymentTerms) {
      updates.dueDate = calculateDueDate(updates.billDate || bill.billDate, updates.paymentTerms);
    }

    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    Object.assign(bill, updates);
    await bill.save();

    res.json({ success: true, message: 'Bill updated successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/submit - Submit draft for approval or to Open
router.post('/:id/submit', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status !== 'DRAFT') {
      return res.status(400).json({ success: false, error: 'Only draft bills can be submitted' });
    }

    bill.status = 'OPEN';
    await bill.save();

    res.json({ success: true, message: 'Bill submitted successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/void - Void a bill
router.post('/:id/void', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status === 'PAID') {
      return res.status(400).json({ success: false, error: 'Cannot void a paid bill' });
    }

    bill.status = 'VOID';
    await bill.save();

    res.json({ success: true, message: 'Bill voided successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/send - Generate PDF and send notification
router.post('/:id/send', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    let pdfInfo;
    if (!bill.pdfPath || !fs.existsSync(bill.pdfPath)) {
      pdfInfo = await generateBillPDF(bill, req.user?.orgId);
      bill.pdfPath = pdfInfo.filepath;
      bill.pdfGeneratedAt = new Date();
    }

    try {
      await sendBillEmail(bill, bill.pdfPath, req.user?.orgId);
    } catch (emailErr) {
      console.warn('Email send failed:', emailErr.message);
    }

    if (bill.status === 'DRAFT') bill.status = 'OPEN';
    await bill.save();

    res.json({ success: true, message: 'Bill sent successfully', data: bill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/payment - Record payment against bill
router.post('/:id/payment', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    const { amount, paymentDate, paymentMode, referenceNumber, notes } = req.body;

    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid payment amount' });
    }

    if (bill.amountDue < amount) {
      return res.status(400).json({ success: false, error: `Payment exceeds due amount (₹${bill.amountDue.toFixed(2)})` });
    }

    const payment = {
      paymentId: new mongoose.Types.ObjectId(),
      amount: parseFloat(amount),
      paymentDate: paymentDate ? new Date(paymentDate) : new Date(),
      paymentMode: paymentMode || 'Bank Transfer',
      referenceNumber,
      notes,
      recordedBy: req.user?.email || req.user?.uid || 'system',
      recordedAt: new Date()
    };

    bill.payments.push(payment);
    bill.amountPaid += payment.amount;
    await bill.save();


    // ✅ COA: Debit Accounts Payable + Credit Undeposited Funds
try {
  const currentOrgId = req.user?.orgId || null;
  const [apId, cashId] = await Promise.all([
    getSystemAccountId('Accounts Payable', currentOrgId),
    getSystemAccountId('Undeposited Funds', currentOrgId),
  ]);
  const txnDate = new Date(payment.paymentDate);
  if (apId) await postTransactionToCOA({
    accountId: apId, orgId: currentOrgId, date: txnDate,
    description: `Payment made - ${bill.billNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: bill.billNumber,
    debit: payment.amount, credit: 0
  });
  if (cashId) await postTransactionToCOA({
    accountId: cashId, orgId: currentOrgId, date: txnDate,
    description: `Payment made - ${bill.billNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: bill.billNumber,
    debit: 0, credit: payment.amount
  });
  console.log(`✅ COA posted for payment on: ${bill.billNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (bill payment):', coaErr.message);
}

    try {
      await sendPaymentConfirmationEmail(bill, payment, req.user?.orgId || null);
    } catch (emailErr) {
      console.warn('Payment email failed:', emailErr.message);
    }

    res.json({ success: true, message: 'Payment recorded successfully', data: { bill, payment } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bills/:id/pdf - Download PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (!bill.pdfPath || !fs.existsSync(bill.pdfPath)) {
      const pdfInfo = await generateBillPDF(bill, req.user?.orgId);
      bill.pdfPath = pdfInfo.filepath;
      bill.pdfGeneratedAt = new Date();
      await bill.save();
    }

    res.download(bill.pdfPath, `Bill-${bill.billNumber}.pdf`);
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/clone - Clone a bill
router.post('/:id/clone', async (req, res) => {
  try {
    const sourceBill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!sourceBill) return res.status(404).json({ success: false, error: 'Bill not found' });

    const cloneData = sourceBill.toObject();
    delete cloneData._id;
    delete cloneData.billNumber;
    delete cloneData.pdfPath;
    delete cloneData.pdfGeneratedAt;
    delete cloneData.payments;
    delete cloneData.amountPaid;
    delete cloneData.amountDue;
    cloneData.status = 'DRAFT';
    cloneData.billDate = new Date();
    cloneData.dueDate = calculateDueDate(new Date(), cloneData.paymentTerms);
    cloneData.billNumber = await generateBillNumber(req.user?.orgId || null);
    cloneData.orgId = req.user?.orgId || null;
    cloneData.createdBy = req.user?.email || req.user?.uid || 'system';
    cloneData.amountPaid = 0;

    const clonedBill = new Bill(cloneData);
    await clonedBill.save();

    res.status(201).json({ success: true, message: 'Bill cloned successfully', data: clonedBill });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/bills/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const bill = await Bill.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();
    const orgName = org?.orgName || '';
    const orgGST  = org?.gstNumber || '';
    const orgPhone = org?.phone || '';
    const orgEmail = org?.email || '';
    const billDateStr = new Date(bill.billDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const dueDateStr  = new Date(bill.dueDate).toLocaleDateString('en-IN',  { day:'2-digit', month:'long', year:'numeric' });
    const html = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Bill ${bill.billNumber}</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;font-size:13px;color:#222;background:#f4f4f4}.wrapper{max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd}.header{background:#0f1e3d;padding:24px 32px}.header h1{color:#fff;font-size:20px;font-weight:bold}.header .num{color:#fff;font-size:14px;font-weight:bold;margin-top:8px}.body{padding:28px 32px}.st{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px}table.d{width:100%;border-collapse:collapse;font-size:13px}table.d td{padding:7px 0;border-bottom:1px dashed #e8e8e8;vertical-align:top}table.d td:first-child{color:#555;width:160px}table.d td:last-child{font-weight:600;color:#111;text-align:right}.tr td{font-size:15px;font-weight:bold;border-top:2px solid #222;border-bottom:none;padding-top:10px}.footer{background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7}</style>
</head><body><div class="wrapper">
<div class="header"><h1>Bill</h1><div class="num">${bill.billNumber}</div></div>
<div class="body">
<p style="font-size:14px;margin-bottom:18px;">Dear ${bill.vendorName},</p>
<p style="color:#444;line-height:1.7;margin-bottom:6px;">Please find attached bill <strong>${bill.billNumber}</strong> for your reference.</p>
<div class="st">Bill Details</div>
<table class="d">
<tr><td>Bill Number</td><td>${bill.billNumber}</td></tr>
<tr><td>Bill Date</td><td>${billDateStr}</td></tr>
<tr><td>Due Date</td><td>${dueDateStr}</td></tr>
<tr><td>Payment Terms</td><td>${bill.paymentTerms || 'Net 30'}</td></tr>
</table>
<div class="st">Amount Summary</div>
<table class="d">
<tr><td>Subtotal</td><td>₹${bill.subTotal.toFixed(2)}</td></tr>
${bill.cgst > 0 ? `<tr><td>CGST</td><td>₹${bill.cgst.toFixed(2)}</td></tr>` : ''}
${bill.sgst > 0 ? `<tr><td>SGST</td><td>₹${bill.sgst.toFixed(2)}</td></tr>` : ''}
<tr class="tr"><td>Total Amount</td><td>₹${bill.totalAmount.toFixed(2)}</td></tr>
${bill.amountDue > 0 ? `<tr><td style="color:#b91c1c">Balance Due</td><td style="color:#b91c1c">₹${bill.amountDue.toFixed(2)}</td></tr>` : ''}
</table>
${bill.notes ? `<div class="st">Notes</div><p style="font-size:12px;line-height:1.7;color:#444;">${bill.notes}</p>` : ''}
</div>
<div class="footer"><strong>${orgName}</strong><br>${orgGST ? 'GST: ' + orgGST + ' | ' : ''}${orgPhone ? 'Ph: ' + orgPhone + ' | ' : ''}${orgEmail}</div>
</div></body></html>`;
    res.json({ success: true, data: { subject: `Bill ${bill.billNumber} — ₹${bill.totalAmount.toFixed(2)}`, html, to: bill.vendorEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const bill = await Bill.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });
    if (to !== undefined)      bill.set('customEmailTo',      to);
    if (subject !== undefined) bill.set('customEmailSubject', subject);
    if (html !== undefined)    bill.set('customEmailHtml',    html);
    await bill.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/bills/:id - Delete (only drafts)
router.delete('/:id', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status !== 'DRAFT') {
      return res.status(400).json({ success: false, error: 'Only draft bills can be deleted' });
    }

    await bill.deleteOne();
    res.json({ success: true, message: 'Bill deleted successfully' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// BULK IMPORT BILLS
// ============================================================================

router.post('/bulk-import', async (req, res) => {
  try {
    const { bills } = req.body;
    if (!bills || !Array.isArray(bills) || bills.length === 0) {
      return res.status(400).json({ success: false, error: 'No bills data provided' });
    }

    let successCount = 0;
    let failedCount = 0;
    const errors = [];

    for (const billData of bills) {
      try {
        billData.vendorId = billData.vendorId || new mongoose.Types.ObjectId();
        if (typeof billData.vendorId === 'string' && !mongoose.Types.ObjectId.isValid(billData.vendorId)) {
          billData.vendorId = new mongoose.Types.ObjectId();
        }

        if (!billData.billNumber) {
          billData.billNumber = await generateBillNumber(req.user?.orgId || null);
        }

        if (!billData.dueDate) {
          billData.dueDate = calculateDueDate(billData.billDate || new Date(), billData.paymentTerms || 'Net 30');
        }

        if (!billData.items || billData.items.length === 0) {
          billData.items = [{ itemDetails: 'Imported Bill', quantity: 1, rate: billData.totalAmount || 0, amount: billData.totalAmount || 0 }];
        }

        billData.createdBy = req.user?.email || req.user?.uid || 'system';
        billData.orgId = req.user?.orgId || null;

        const bill = new Bill(billData);
        await bill.save();
        successCount++;
      } catch (err) {
        failedCount++;
        errors.push(`Bill ${billData.billNumber || 'unknown'}: ${err.message}`);
      }
    }

    res.json({
      success: true,
      message: `Import complete: ${successCount} succeeded, ${failedCount} failed`,
      data: { totalProcessed: bills.length, successCount, failedCount, errors }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
module.exports.Bill = Bill;
module.exports.BillModel = Bill;
module.exports.generateBillNumber = generateBillNumber;