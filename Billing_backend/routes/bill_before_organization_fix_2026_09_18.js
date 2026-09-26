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

// ? COA Helper
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');
const { sendMail } = require('../utils/mailer');

async function getSystemAccountId(name, orgId = null, branchId = null) {
  try {
    let query = { accountName: name, isSystemAccount: true };
    if (orgId) query.orgId = orgId;
    
    if (branchId) {
      let branchAcc = await ChartOfAccount.findOne({ ...query, branchId }).select('_id').lean();
      if (branchAcc) return branchAcc._id;
    }
    
    let globalAcc = await ChartOfAccount.findOne({ ...query, branchId: null }).select('_id').lean();
    if (globalAcc) return globalAcc._id;
    
    let legacyAcc = await ChartOfAccount.findOne(query).select('_id').lean();
    return legacyAcc ? legacyAcc._id : null;
  } catch (e) {
    console.error(`COA lookup error for "${name}":`, e.message);
    return null;
  }
}

// Looks up (or auto-creates) an expense/COGS account by name — mirrors expenses.js getExpenseAccountId
async function getBillExpenseAccountId(accountName, orgId = null) {
  try {
    const EXPENSE_TYPES = ['Expense', 'Other Expense', 'Cost Of Goods Sold', 'Equity'];

    // Step 1: exact match on an expense-type account
    let acc = await ChartOfAccount.findOne({
      accountName: { $regex: `^${accountName}$`, $options: 'i' },
      accountType: { $in: EXPENSE_TYPES },
      ...(orgId ? { orgId } : {}),
    }).select('_id').lean();
    if (acc) return acc._id;

    // Step 1b: account exists but is the wrong type — skip COA post safely
    const wrongTypeAcc = await ChartOfAccount.findOne({
      accountName: { $regex: `^${accountName}$`, $options: 'i' },
      accountType: { $nin: EXPENSE_TYPES },
      ...(orgId ? { orgId } : {}),
    }).select('_id accountType').lean();
    if (wrongTypeAcc) {
      console.warn(`⚠️ Bill COA: account "${accountName}" is type "${wrongTypeAcc.accountType}" — not an expense account. Skipping.`);
      return null;
    }

    // Step 2: not found — auto-create as Expense type
    console.log(`📝 Bill COA: account "${accountName}" not found — creating automatically as Expense type...`);
    const newAcc = await ChartOfAccount.create({
      accountName:     accountName,
      accountCode:     `EXP-${Date.now().toString().slice(-6)}`,
      accountType:     'Expense',
      orgId:           orgId,
      accountSubType:  'Operating Expense',
      description:     `${accountName} expenses`,
      isSystemAccount: false,
      isActive:        true,
      openingBalance:  0,
      currentBalance:  0,
      currency:        'INR',
      transactions:    [],
    });
    console.log(`✅ Bill COA: auto-created account "${accountName}" → ID: ${newAcc._id}`);
    return newAcc._id;
  } catch (e) {
    console.error(`COA lookup/create error for bill expense account "${accountName}":`, e.message);
    return null;
  }
}

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

// Bill Schema - mirrors Zoho Books Bill structure
const billSchema = new mongoose.Schema({
  orgId    : { type: String, index: true, default: null },
  branchId : { type: String, index: true, default: null },
  billNumber: {
    type: String,
    required: true,

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
    // ── GST / HSN fields (mirrors invoices.js) ──────────────────────────────
    hsnCode:      { type: String, default: '' },
    sacCode:      { type: String, default: '' },
    unit:         { type: String, default: 'Nos' },
    taxableAmount:{ type: Number, default: 0 },
    itemGstRate:  { type: Number, default: 0 },
    cgstAmount:   { type: Number, default: 0 },
    sgstAmount:   { type: Number, default: 0 },
    igstAmount:   { type: Number, default: 0 },
    // ── Original fields ──────────────────────────────────────────────────────
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
    creditId:      mongoose.Schema.Types.ObjectId,
    paymentNumber: String,
    amount:        Number,
    appliedDate:   Date,
  }],

  // -- Currency & Exchange Rate ---------------------------------------------
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
  // -- End Currency Fields --------------------------------------------------

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

// Pre-save middleware to calculate amounts — per-item GST (mirrors invoices.js)
billSchema.pre('save', function() {
  // ── 1. Per-item taxable + GST calculation ──────────────────────────────────
  let subTotal = 0;
  let totalCGST = 0, totalSGST = 0, totalIGST = 0;

  for (const item of this.items) {
    // taxable = qty × rate − discount
    let taxable = (item.quantity || 0) * (item.rate || 0);
    if (item.discount > 0) {
      taxable = item.discountType === 'percentage'
        ? taxable - (taxable * item.discount / 100)
        : taxable - item.discount;
    }
    taxable = Math.round(taxable * 100) / 100;
    item.taxableAmount = taxable;

    const gstRate = item.itemGstRate !== undefined ? item.itemGstRate : (this.gstRate || 0);
    item.cgstAmount = Math.round(taxable * (gstRate / 2) / 100 * 100) / 100;
    item.sgstAmount = item.cgstAmount;
    item.igstAmount = 0;

    item.amount = Math.round((taxable + item.cgstAmount + item.sgstAmount) * 100) / 100;

    subTotal   += taxable;
    totalCGST  += item.cgstAmount;
    totalSGST  += item.sgstAmount;
  }

  this.subTotal = Math.round(subTotal * 100) / 100;
  this.cgst     = Math.round(totalCGST * 100) / 100;
  this.sgst     = Math.round(totalSGST * 100) / 100;
  this.igst     = 0;

  // ── 2. TDS / TCS ───────────────────────────────────────────────────────────
  this.tdsAmount = Math.round(this.subTotal * (this.tdsRate || 0) / 100 * 100) / 100;
  this.tcsAmount = Math.round(this.subTotal * (this.tcsRate || 0) / 100 * 100) / 100;

  // ── 3. Grand total ─────────────────────────────────────────────────────────
  const totalTax = this.cgst + this.sgst;
  this.totalAmount = Math.round(
    (this.subTotal - this.tdsAmount + this.tcsAmount + totalTax) * 100
  ) / 100;
  this.amountDue  = Math.round((this.totalAmount - (this.amountPaid || 0)) * 100) / 100;
  this.baseCurrencyAmount = this.totalAmount * (this.exchangeRate || 1);

  // ── 4. Status logic ────────────────────────────────────────────────────────
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
billSchema.index({ orgId: 1, branchId: 1, billNumber: 1 }, { unique: true });
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
async function generateBillNumber(orgId = null, branchId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(Bill, 'billNumber', 'BILL', orgId, branchId);
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
// ORG LOGO HELPER (mirrors invoices.js getOrgLogoPath)
// ============================================================================
function getBillOrgLogoPath(orgId) {
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
  const fallbacks = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
  ];
  for (const p of fallbacks) {
    try { if (fs.existsSync(p)) return p; } catch (_) {}
  }
  return null;
}

// ============================================================================
// PDF GENERATION — mirrors invoices.js exactly
// ============================================================================

async function generateBillPDF(bill, orgId, branchId = null) {
  return new Promise(async (resolve, reject) => {
    try {
      console.log('PDF generation for bill:', bill.billNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'bills');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
      const filename = `bill-${bill.billNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      let orgName = 'Your Company', orgGST = '', orgAddr = '', orgEmail = '', orgPhone = '';
      let orgData = null;
      try {
        const { getEffectiveOrgData } = require('./branches');
        const db = mongoose.connection.db;
        if (db) orgData = await getEffectiveOrgData(orgId, branchId, db);
        if (orgData) {
          orgName = orgData.orgName   || orgName;
          orgGST  = orgData.gstNumber || '';
          orgAddr = orgData.address   || '';
          orgEmail= orgData.email     || '';
          orgPhone= orgData.phone     || '';
        }
      } catch (e) { console.warn('Could not fetch org details:', e.message); }

      const doc    = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);
      const pageW = 515;

      // HEADER - white background, black text (same as invoices.js)
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
        const lp = getBillOrgLogoPath(orgId || null);
        try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
      }
      let logoLoaded = false;

      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      const textBlockHeight = 14 + 12 + (contactLines.length * 9);
      const textStartY  = 35;
      const logoCenterY = textStartY + (textBlockHeight / 2);
      
      const logoH = 82; // Increased to match invoice
      const logoW = 110; // Increased to match invoice
      const logoY = textStartY; // Align top of logo with top of text
      const textX = logoData ? 166 : 50;

      if (logoData) {
        try { doc.image(logoData, 44, logoY, { width: logoW, height: logoH, fit: [logoW, logoH] }); logoLoaded = true; }
        catch (e) { console.warn('Logo load failed:', e.message); }
      }

      doc.fontSize(12).fillColor('#000000').font('Helvetica-Bold')
         .text(orgName.toUpperCase(), textX, textStartY, { width: 200 });
      doc.fontSize(12).font('Helvetica-Bold');
      const orgNameH = doc.heightOfString(orgName.toUpperCase(), { width: 200 });
      const subtitleY = textStartY + orgNameH + 2;
      doc.fontSize(7).fillColor('#444444').font('Helvetica')
         .text('BILLING & FINANCE', textX, subtitleY, { width: 200, characterSpacing: 1 });
      doc.fontSize(7).fillColor('#000000');
      let cY = subtitleY + 12;
      contactLines.forEach(l => {
        doc.text(l, textX, cY, { width: 240 });
        const lineH = doc.heightOfString(l, { width: 240 });
        cY += Math.max(lineH, 9) + 1;
      });

      doc.fontSize(8).fillColor('#444444').font('Helvetica-Bold')
         .text('BILL', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
         .text(bill.billNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`Date: ${new Date(bill.billDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#000000').font('Helvetica-Bold')
         .text(`${(bill.status || 'DRAFT').replace(/_/g, ' ')}`, 380, 92, { width: 170, align: 'right' });

      // META GRID - 3 columns (same as invoices.js)
      const metaY = Math.max(132, cY + 8);
      const colW = pageW / 3;

      const billingStr = [bill.billingAddress?.street, bill.billingAddress?.city,
                          bill.billingAddress?.state, bill.billingAddress?.pincode]
                         .filter(Boolean).join(', ');

      // Dynamic box height based on vendor name + address content
      doc.fontSize(9).font('Helvetica-Bold');
      const _vendorNameH = doc.heightOfString(bill.vendorName || 'N/A', { width: colW - 16 });
      doc.fontSize(7).font('Helvetica');
      const _billAddrH = billingStr ? doc.heightOfString(billingStr, { width: colW - 16 }) : 0;
      const _billGstH  = bill.vendorGSTIN ? 10 : 0;
      const metaH = Math.max(90, 18 + _vendorNameH + 2 + _billAddrH + _billGstH + 10);

      // Col 1: Bill From
      const billX = 40;
      doc.rect(billX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('BILL FROM', billX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold')
         .text(bill.vendorName || 'N/A', billX + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(9).font('Helvetica-Bold');
      const vendorNameH = doc.heightOfString(bill.vendorName || 'N/A', { width: colW - 16 });
      const billAddrY = metaY + 18 + vendorNameH + 2;
      if (billingStr) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(billingStr, billX + 8, billAddrY, { width: colW - 16, ellipsis: true });
      }
      if (bill.vendorGSTIN) {
        doc.fontSize(7).font('Helvetica');
        const addrH = billingStr ? doc.heightOfString(billingStr, { width: colW - 16 }) : 0;
        doc.fillColor('#000000').text(`GSTIN: ${bill.vendorGSTIN}`, billX + 8, billAddrY + addrH + 2, { width: colW - 16, ellipsis: true });
      }

      // Col 2: Bill To (our org)
      const shipX = 40 + colW;
      doc.rect(shipX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('BILL TO', shipX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold')
         .text(orgName, shipX + 8, metaY + 18, { width: colW - 16, ellipsis: true });
      if (orgAddr) doc.fontSize(7).fillColor('#000000').font('Helvetica')
         .text(orgAddr, shipX + 8, metaY + 30, { width: colW - 16, ellipsis: true });

      // Col 3: Bill Details
      const detX = 40 + colW * 2;
      doc.rect(detX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('BILL DETAILS', detX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`Bill #: ${bill.billNumber}`, detX + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(7).fillColor('#000000').font('Helvetica')
         .text(`Due: ${new Date(bill.dueDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}`, detX + 8, metaY + 29, { width: colW - 16 });
      doc.text(`Terms: ${bill.paymentTerms || 'Net 30'}`, detX + 8, metaY + 39, { width: colW - 16 });
      if (bill.purchaseOrderNumber)
        doc.text(`PO #: ${bill.purchaseOrderNumber}`, detX + 8, metaY + 49, { width: colW - 16 });

      let tableStartY = metaY + metaH + 12;

      // ITEMS TABLE - same columns as invoices.js
      const isInterState = bill.isInterState || false;
      const cols = {
        num:     { x: 40,  w: 16  }, desc:    { x: 56,  w: 90  },
        hsn:     { x: 146, w: 44  }, unit:    { x: 190, w: 24  },
        qty:     { x: 214, w: 24  }, rate:    { x: 238, w: 36  },
        disc:    { x: 274, w: 26  }, taxable: { x: 300, w: 38  },
        gst:     { x: 338, w: 24  }, tax1:    { x: 362, w: 46  },
        tax2:    { x: 408, w: 46  }, amount:  { x: 454, w: 61  },
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
      if (isInterState) {
        doc.text('IGST',  cols.tax1.x + 2, tableStartY + 7, { width: cols.tax1.w + cols.tax2.w, align: 'right' });
      } else {
        doc.text('CGST',  cols.tax1.x + 2, tableStartY + 7, { width: cols.tax1.w, align: 'right' });
        doc.text('SGST',  cols.tax2.x + 2, tableStartY + 7, { width: cols.tax2.w, align: 'right' });
      }
      doc.text('AMOUNT',  cols.amount.x+2, tableStartY + 7, { width: cols.amount.w, align: 'right' });

      let rowY = tableStartY + 20;
      (bill.items || []).forEach((item, idx) => {
        const descText  = item.itemDetails || 'N/A';
        const descWidth = cols.desc.w - 4;
        const vPad      = 8;
        doc.font('Helvetica').fontSize(7);
        const descH = doc.heightOfString(descText, { width: descWidth, lineGap: 1 });
        const rowH  = Math.max(20, descH + vPad * 2);

        doc.rect(40, rowY, 515, rowH).fill(idx % 2 === 0 ? '#ffffff' : '#f7f9fc');
        doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();

        const hsnSac  = item.hsnCode || item.sacCode || '';
        const discStr = item.discount > 0
          ? (item.discountType === 'percentage' ? `${item.discount}%` : `${item.discount}`) : '-';
        const taxable = item.taxableAmount || 0;
        const gstRate = item.itemGstRate !== undefined ? item.itemGstRate : (bill.gstRate || 0);
        const cellY   = rowY + vPad;

        doc.fontSize(7).fillColor('#000000');
        doc.font('Helvetica-Bold').text(String(idx + 1), cols.num.x + 2, cellY, { width: cols.num.w });
        doc.font('Helvetica').text(descText, cols.desc.x + 2, cellY, { width: descWidth, lineGap: 1 });
        doc.text(hsnSac,                           cols.hsn.x  + 2, cellY, { width: cols.hsn.w - 2,  ellipsis: true });
        doc.text(item.unit || 'Nos',               cols.unit.x + 2, cellY, { width: cols.unit.w });
        doc.text(String(item.quantity || 0),       cols.qty.x  + 2, cellY, { width: cols.qty.w,     align: 'center' });
        doc.text(`${(item.rate||0).toFixed(2)}`,   cols.rate.x + 2, cellY, { width: cols.rate.w,    align: 'right' });
        doc.text(discStr,                          cols.disc.x + 2, cellY, { width: cols.disc.w,    align: 'right' });
        doc.text(`${taxable.toFixed(2)}`,          cols.taxable.x+2, cellY, { width: cols.taxable.w, align: 'right' });
        doc.text(`${gstRate}%`,                    cols.gst.x  + 2, cellY, { width: cols.gst.w,     align: 'center' });
        if (isInterState) {
          doc.text(`${(item.igstAmount||0).toFixed(2)}`, cols.tax1.x + 2, cellY, { width: cols.tax1.w + cols.tax2.w, align: 'right' });
        } else {
          doc.text(`${(item.cgstAmount||0).toFixed(2)}`, cols.tax1.x + 2, cellY, { width: cols.tax1.w, align: 'right' });
          doc.text(`${(item.sgstAmount||0).toFixed(2)}`, cols.tax2.x + 2, cellY, { width: cols.tax2.w, align: 'right' });
        }
        doc.font('Helvetica-Bold')
           .text(`${(item.amount||0).toFixed(2)}`, cols.amount.x + 2, cellY, { width: cols.amount.w, align: 'right' });
        rowY += rowH;
      });

      // TOTALS - identical to invoices.js
      const totalsX = 315, totalsW = 240;
      const summaryY = rowY + 12;
      let totalsY = summaryY;
      const labelX = totalsX, amountX = totalsX + totalsW;

      const tRow = (label, amount, bold = false) => {
        doc.fontSize(8).fillColor('#5e6e84').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(label, labelX, totalsY, { width: 140 });
        doc.fillColor('#000000').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(amount, labelX + 140, totalsY, { width: 100, align: 'right' });
        doc.moveTo(labelX, totalsY + 11).lineTo(amountX, totalsY + 11)
           .lineWidth(0.5).strokeColor('#dde4ef').dash(2, { space: 2 }).stroke().undash();
        totalsY += 14;
      };

      tRow('Subtotal:', `Rs. ${(bill.subTotal || 0).toFixed(2)}`);
      if (isInterState) {
        if ((bill.igst || bill.totalIGST || 0) > 0) tRow('IGST:', `Rs. ${(bill.igst || bill.totalIGST || 0).toFixed(2)}`);
      } else {
        if ((bill.cgst || bill.totalCGST || 0) > 0) tRow('CGST:', `Rs. ${(bill.cgst || bill.totalCGST || 0).toFixed(2)}`);
        if ((bill.sgst || bill.totalSGST || 0) > 0) tRow('SGST:', `Rs. ${(bill.sgst || bill.totalSGST || 0).toFixed(2)}`);
      }
      if ((bill.tdsAmount || 0) > 0) tRow('TDS Deducted:',  `- Rs. ${bill.tdsAmount.toFixed(2)}`);
      if ((bill.tcsAmount || 0) > 0) tRow('TCS Collected:', `Rs. ${bill.tcsAmount.toFixed(2)}`);

      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text('Grand Total', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Rs. ${(bill.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      if ((bill.amountPaid || 0) > 0) {
        tRow('Amount Paid:', `Rs. ${bill.amountPaid.toFixed(2)}`);
        tRow('Balance Due:', `Rs. ${(bill.amountDue || 0).toFixed(2)}`, true);
      }

      // Amount in words
      const wordsY = Math.max(summaryY, totalsY) + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold')
         .text(`In Words: ${numberToWords(Math.round(bill.totalAmount || 0))} Only`, 48, wordsY + 5, { width: pageW - 16 });

      // Bottom section: Notes (left) + Signatory (right) - same as invoices.js
      const bottomSectionY = wordsY + 28;
      const signBoxW = 220, authBoxX = 555 - signBoxW;
      let notesY = bottomSectionY;

      if (bill.notes) {
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold').text('NOTES', 40, notesY, { characterSpacing: 0.8 });
        doc.moveTo(40, notesY + 9).lineTo(555, notesY + 9).lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica').text(bill.notes, 40, notesY + 14, { width: pageW });
        notesY += 40;
      }

      if (bill.termsAndConditions) {
        const tcY = notesY + 6;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold').text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica').text(bill.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // AUTHORIZED SIGNATORY - identical to invoices.js
      const signSectionY = bottomSectionY;
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text(`For ${orgName.toUpperCase()}`, authBoxX, signSectionY, { width: signBoxW, characterSpacing: 0.5, ellipsis: true });

      const sigRelPath = orgData && orgData.digitalSignaturePath;
      const sigImgSize = 200;
      let actualSigH   = sigImgSize;
      
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
                imgW = sigBuf.readUInt32BE(16); imgH = sigBuf.readUInt32BE(20);
              } else if ((sigExt === '.jpg' || sigExt === '.jpeg') && sigBuf.length > 4) {
                let i = 2;
                while (i < sigBuf.length - 8) {
                  if (sigBuf[i] === 0xFF && sigBuf[i+1] >= 0xC0 && sigBuf[i+1] <= 0xC3) {
                    imgH = sigBuf.readUInt16BE(i + 5); imgW = sigBuf.readUInt16BE(i + 7); break;
                  }
                  i += 2 + sigBuf.readUInt16BE(i + 2);
                }
              }
            } catch (_) {}
            const scale      = Math.min(sigImgSize / imgW, sigImgSize / imgH);
            actualSigH       = Math.round(imgH * scale);
            const actualSigW = Math.round(imgW * scale);
            doc.image(sigBuf, authBoxX + (signBoxW - actualSigW) / 2, signSectionY + 10, { width: actualSigW, height: actualSigH });
        } catch (sigErr) { console.warn('Could not render digital signature:', sigErr.message); }
      }

      const sigLineY = signSectionY + 10 + actualSigH + 14;
      doc.moveTo(authBoxX, sigLineY).lineTo(authBoxX + signBoxW, sigLineY).lineWidth(0.5).strokeColor('#aaaaaa').stroke();
      doc.fontSize(6.5).fillColor('#000000').font('Helvetica-Bold')
         .text('Authorized Signatory', authBoxX, sigLineY + 3, { width: signBoxW, align: 'center' });

      // Footer
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY).lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName} - ${orgGST ? 'GSTIN: ' + orgGST + ' - ' : ''}${bill.billNumber}`, 40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`, 40, footY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => {
        console.log(`Bill PDF generated: ${filename} | Logo: ${logoLoaded ? 'YES' : 'NO'}`);
        resolve({ filename, filepath, relativePath: `/uploads/bills/${filename}` });
      });
      stream.on('error', reject);
    } catch (error) {
      console.error('Bill PDF generation error:', error);
      reject(error);
    }
  });
}
// EMAIL SERVICE
// ============================================================================

async function sendBillEmail(bill, pdfPath, orgId, branchId = null) {
  let orgName = '', orgGST = '', orgPhone = '', orgEmail = '', orgData = null;
  try {
    const { getEffectiveOrgData } = require('./branches');
    const db = mongoose.connection.db;
    if (db) orgData = await getEffectiveOrgData(orgId, branchId, db);
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

  return sendMail({
    orgId, branchId, db: mongoose.connection.db,
    to:          bill.vendorEmail || process.env.BILLING_EMAIL || process.env.SMTP_USER,
    subject:     `Bill ${bill.billNumber} — Rs.${(bill.totalAmount || 0).toFixed(2)}`,
    html:        emailHtml,
    attachments: [{ filename: `Bill-${bill.billNumber}.pdf`, path: pdfPath }],
  });
}
async function sendPaymentConfirmationEmail(bill, payment, orgId = null, branchId = null) {
  let orgName  = '';
  let orgGST   = '';
  let orgPhone = '';
  let orgEmail = '';
  try {
    const { getEffectiveOrgData } = require('./branches');
    const db = mongoose.connection.db;
    const org = db ? await getEffectiveOrgData(orgId, branchId, db) : null;
    orgName  = org?.orgName   || '';
    orgGST   = org?.gstNumber || '';
    orgPhone = org?.phone     || '';
    orgEmail = org?.email     || '';
  } catch (e) {
    console.warn('Could not fetch org details for payment email:', e.message);
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
      <h2>? Payment of ?${payment.amount.toFixed(2)} recorded</h2>
      <p>For Bill: ${bill.billNumber} � ${bill.vendorName}</p>
    </div>

    <div class="section-title">Payment Details</div>
    <table class="detail">
      <tr><td>Bill Number</td>    <td>${bill.billNumber}</td></tr>
      <tr><td>Vendor</td>         <td>${bill.vendorName}</td></tr>
      <tr><td>Amount Paid</td>    <td>?${payment.amount.toFixed(2)}</td></tr>
      <tr><td>Payment Date</td>   <td>${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}</td></tr>
      <tr><td>Payment Mode</td>   <td>${payment.paymentMode}</td></tr>
      ${payment.referenceNumber ? `<tr><td>Reference</td><td>${payment.referenceNumber}</td></tr>` : ''}
      <tr class="balance-row"><td>Remaining Balance</td><td>?${bill.amountDue.toFixed(2)}</td></tr>
    </table>

    ${bill.amountDue <= 0 ? `<div class="paid-badge">?? Bill Fully Paid � Thank You!</div>` : ''}
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

  return sendMail({
    orgId, branchId, db: mongoose.connection.db,
    to:      process.env.BILLING_EMAIL || process.env.SMTP_USER,
    subject: `Payment Recorded — ${bill.billNumber} — Rs.${payment.amount.toFixed(2)}`,
    html:    emailHtml,
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
    Object.assign(query, req.branchFilter || {});

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
    const orgFilter = {
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    };
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
      ...req.orgFilter,
      ...(req.branchFilter || {}),
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

    if (!body.vendorId)   return res.status(400).json({ success: false, error: 'Vendor ID is required' });
    if (!body.vendorName) return res.status(400).json({ success: false, error: 'Vendor Name is required' });
    if (!body.items || body.items.length === 0)
      return res.status(400).json({ success: false, error: 'At least one item is required' });

    body.vendorId = mongoose.Types.ObjectId.isValid(body.vendorId)
      ? new mongoose.Types.ObjectId(body.vendorId)
      : new mongoose.Types.ObjectId();

    if (!body.billNumber) {
      body.billNumber = await generateBillNumber(req.user?.orgId || null, req.branchIds?.length > 0 ? req.branchIds[0] : null);
    }

    if (!body.dueDate) {
      body.dueDate = calculateDueDate(body.billDate || new Date(), body.paymentTerms || 'Net 30');
    }

    body.items = body.items.map(item => ({ ...item, amount: calculateItemAmount(item) }));
    body.createdBy = req.user?.email || req.user?.uid || 'system';
    body.orgId = req.user?.orgId || null;
    body.branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    body.amountPaid = 0;

    const bill = new Bill(body);
    await bill.save();

    // ✅ COA: Debit each line item's expense account + Credit Accounts Payable
    try {
      const currentOrgId = req.user?.orgId || null;
      const apId = await getSystemAccountId('Accounts Payable', currentOrgId, branchId);
      const txnDate = new Date(bill.billDate);
      const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;

      // Debit each line item to its own expense account
      for (const item of bill.items) {
        const accountName = item.account || 'Cost of Goods Sold';
        const itemAccId = await getBillExpenseAccountId(accountName, currentOrgId);
        if (itemAccId) {
          await postTransactionToCOA({
            accountId: itemAccId, orgId: currentOrgId, branchId, date: txnDate,
            description: `Bill created - ${bill.billNumber} - ${bill.vendorName} - ${item.itemDetails}`,
            referenceType: 'Bill', referenceId: bill._id,
            referenceNumber: bill.billNumber,
            debit: item.amount, credit: 0
          });
        } else {
          console.warn(`⚠️ COA: Could not resolve expense account "${accountName}" for bill line item`);
        }
      }

      // Credit Accounts Payable once for the full bill total
      if (apId) await postTransactionToCOA({
        accountId: apId, orgId: currentOrgId, branchId, date: txnDate,
        description: `Bill created - ${bill.billNumber} - ${bill.vendorName}`,
        referenceType: 'Bill', referenceId: bill._id,
        referenceNumber: bill.billNumber,
        debit: 0, credit: bill.totalAmount
      });
      console.log(`✅ COA posted for bill: ${bill.billNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA post error (bill create):', coaErr.message);
    }

    console.log(`? Bill created: ${bill.billNumber}`);
    res.status(201).json({ success: true, message: 'Bill created successfully', data: bill });
  } catch (error) {
    console.error('Error creating bill:', error);
    if (error.code === 11000) {
      return res.status(400).json({ success: false, error: 'Bill number already exists' });
    }
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/bills/:id - Update bill
router.put('/:id', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
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
    bill.pdfPath = null; // Force PDF regeneration on edit
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
      ...req.orgFilter,
      ...(req.branchFilter || {}),
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

// PATCH /api/bills/:id/mark-as-sent — mark as OPEN without sending email
router.patch('/:id/mark-as-sent', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (!['DRAFT', 'OPEN'].includes(bill.status)) {
      return res.status(400).json({ success: false, error: `Cannot mark a ${bill.status} bill as sent` });
    }

    // Already OPEN — nothing to do, return success idempotently
    if (bill.status === 'OPEN') {
      return res.json({ success: true, message: 'Bill already marked as sent', data: bill });
    }

    bill.status    = 'OPEN';
    bill.updatedBy = req.user?.email || req.user?.uid || 'system';
    await bill.save();

    console.log(`✅ Bill marked as sent (no email): ${bill.billNumber}`);
    res.json({ success: true, message: 'Bill marked as sent', data: bill });
  } catch (error) {
    console.error('Error marking bill as sent:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/bills/:id/void - Void a bill
router.post('/:id/void', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (bill.status === 'PAID') {
      return res.status(400).json({ success: false, error: 'Cannot void a paid bill' });
    }
    if (bill.status === 'VOID') {
      return res.status(400).json({ success: false, error: 'Bill is already voided' });
    }

    const currentOrgId = req.user?.orgId || null;
    const branchId     = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const txnDate      = new Date();

    // ── STEP 1: Reverse COA entries from bill creation ──────────────────────
    // Creation posted: Dr Expense accounts / Cr Accounts Payable
    // Void reversal:   Cr Expense accounts / Dr Accounts Payable
    try {
      const apId = await getSystemAccountId('Accounts Payable', currentOrgId, branchId);

      // Cr each line item's expense account (reverses the original Dr)
      for (const item of bill.items || []) {
        const accountName = item.account || 'Cost of Goods Sold';
        const itemAccId   = await getBillExpenseAccountId(accountName, currentOrgId);
        if (itemAccId && item.amount > 0) {
          await postTransactionToCOA({
            accountId:       itemAccId,
            orgId:           currentOrgId,
            branchId,
            date:            txnDate,
            description:     `VOID - Bill ${bill.billNumber} - ${bill.vendorName} - ${item.itemDetails}`,
            referenceType:   'Bill',
            referenceId:     bill._id,
            referenceNumber: bill.billNumber,
            debit:           0,
            credit:          item.amount,   // reverses original Dr
          });
        }
      }

      // Dr Accounts Payable (reverses the original Cr)
      if (apId && bill.totalAmount > 0) {
        await postTransactionToCOA({
          accountId:       apId,
          orgId:           currentOrgId,
          branchId,
          date:            txnDate,
          description:     `VOID - Bill ${bill.billNumber} - ${bill.vendorName}`,
          referenceType:   'Bill',
          referenceId:     bill._id,
          referenceNumber: bill.billNumber,
          debit:           bill.totalAmount,  // reverses original Cr
          credit:          0,
        });
      }

      console.log(`✅ COA reversed for voided bill: ${bill.billNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA reversal error on void:', coaErr.message);
    }

    // ── STEP 2: If partially paid, reverse payment COA entries too ──────────
    if (bill.amountPaid > 0) {
      try {
        const apId   = await getSystemAccountId('Accounts Payable', currentOrgId, branchId);
        const cashId = await getSystemAccountId('Undeposited Funds', currentOrgId);

        // Reverse: Cr AP / Dr Undeposited Funds (undoes the payment posting)
        if (apId && bill.amountPaid > 0) {
          await postTransactionToCOA({
            accountId:       apId,
            orgId:           currentOrgId,
            branchId,
            date:            txnDate,
            description:     `VOID - Payment reversal for Bill ${bill.billNumber}`,
            referenceType:   'Bill',
            referenceId:     bill._id,
            referenceNumber: bill.billNumber,
            debit:           0,
            credit:          bill.amountPaid,
          });
        }
        if (cashId && bill.amountPaid > 0) {
          await postTransactionToCOA({
            accountId:       cashId,
            orgId:           currentOrgId,
            branchId,
            date:            txnDate,
            description:     `VOID - Payment reversal for Bill ${bill.billNumber}`,
            referenceType:   'Bill',
            referenceId:     bill._id,
            referenceNumber: bill.billNumber,
            debit:           bill.amountPaid,
            credit:          0,
          });
        }
        console.log(`✅ Payment COA reversed for voided bill: ${bill.billNumber} (₹${bill.amountPaid})`);
      } catch (payErr) {
        console.error('⚠️ Payment COA reversal error on void:', payErr.message);
      }
    }

    // ── STEP 3: Void the bill ────────────────────────────────────────────────
    bill.status    = 'VOID';
    bill.amountPaid = 0;
    bill.amountDue  = 0;
    bill.payments   = [];
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
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    let pdfInfo;
    if (!bill.pdfPath || !fs.existsSync(bill.pdfPath)) {
      pdfInfo = await generateBillPDF(bill, req.user?.orgId, bill.branchId || null);
      bill.pdfPath = pdfInfo.filepath;
      bill.pdfGeneratedAt = new Date();
    }

    try {
      await sendBillEmail(bill, bill.pdfPath, req.user?.orgId, bill.branchId || null);
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
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    const { amount, paymentDate, paymentMode, referenceNumber, notes } = req.body;

    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid payment amount' });
    }

    if (bill.amountDue < amount) {
      return res.status(400).json({ success: false, error: `Payment exceeds due amount (?${bill.amountDue.toFixed(2)})` });
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


    // ? COA: Debit Accounts Payable + Credit Undeposited Funds
try {
  const currentOrgId = req.user?.orgId || null;
  const [apId, cashId] = await Promise.all([
    getSystemAccountId('Accounts Payable', currentOrgId, branchId),
    getSystemAccountId('Undeposited Funds', currentOrgId),
  ]);
  const txnDate = new Date(payment.paymentDate);
  if (apId) await postTransactionToCOA({
    accountId: apId, orgId: currentOrgId, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, date: txnDate,
    description: `Payment made - ${bill.billNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: bill.billNumber,
    debit: payment.amount, credit: 0
  });
  if (cashId) await postTransactionToCOA({
    accountId: cashId, orgId: currentOrgId, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null, date: txnDate,
    description: `Payment made - ${bill.billNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: bill.billNumber,
    debit: 0, credit: payment.amount
  });
  console.log(`? COA posted for payment on: ${bill.billNumber}`);
} catch (coaErr) {
  console.error('?? COA post error (bill payment):', coaErr.message);
}

    try {
      await sendPaymentConfirmationEmail(bill, payment, req.user?.orgId || null, bill.branchId || null);
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
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (!bill.pdfPath || !fs.existsSync(bill.pdfPath)) {
      const pdfInfo = await generateBillPDF(bill, req.user?.orgId, bill.branchId || null);
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
      ...req.orgFilter,
      ...(req.branchFilter || {}),
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
    cloneData.billNumber = await generateBillNumber(req.user?.orgId || null, req.branchIds?.length > 0 ? req.branchIds[0] : null);
    cloneData.orgId = req.user?.orgId || null;
    cloneData.branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
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
    const bill = await Bill.findOne({ _id: req.params.id, orgId: req.user?.orgId, ...(req.branchFilter || {}) });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });
    const { getEffectiveOrgData } = require('./branches');
    const db = mongoose.connection.db;
    const org = db ? await getEffectiveOrgData(req.user?.orgId, req.branchIds?.length === 1 ? req.branchIds[0] : null, db) : null;
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
<tr><td>Subtotal</td><td>Rs.${bill.subTotal.toFixed(2)}</td></tr>
${bill.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${bill.cgst.toFixed(2)}</td></tr>` : ''}
${bill.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${bill.sgst.toFixed(2)}</td></tr>` : ''}
<tr class="tr"><td>Total Amount</td><td>Rs.${bill.totalAmount.toFixed(2)}</td></tr>
${bill.amountDue > 0 ? `<tr><td style="color:#b91c1c">Balance Due</td><td style="color:#b91c1c">Rs.${bill.amountDue.toFixed(2)}</td></tr>` : ''}
</table>
${bill.notes ? `<div class="st">Notes</div><p style="font-size:12px;line-height:1.7;color:#444;">${bill.notes}</p>` : ''}
</div>
<div class="footer"><strong>${orgName}</strong><br>${orgGST ? 'GST: ' + orgGST + ' | ' : ''}${orgPhone ? 'Ph: ' + orgPhone + ' | ' : ''}${orgEmail}</div>
</div></body></html>`;
    res.json({ success: true, data: { subject: `Bill ${bill.billNumber} - Rs.${bill.totalAmount.toFixed(2)}`, html, to: bill.vendorEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview � save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const bill = await Bill.findOne({ _id: req.params.id, ...req.orgFilter, ...(req.branchFilter || {}) });
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

// ============================================================================
// APPLY VENDOR CREDITS (ADVANCE) TO BILL — Zoho Books style
// ============================================================================

// GET /api/finance/bills/:id/available-credits
// Returns all ADVANCE payments for this bill's vendor that still have unused balance
router.get('/:id/available-credits', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    }).lean();
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    const PaymentMade = mongoose.models.PaymentMade ||
      mongoose.model('PaymentMade', new mongoose.Schema({}, { strict: false }));

    const orgFilter = req.user?.orgId
      ? { $or: [{ orgId: req.user.orgId }, { orgId: null }, { orgId: { $exists: false } }] }
      : {};

    const advances = await PaymentMade.find({
      vendorId: bill.vendorId,
      paymentType: 'ADVANCE',
      ...orgFilter,
      ...(req.branchFilter || {}),
    }).sort({ paymentDate: -1 }).lean();

    const available = advances
      .map(a => ({
        _id:            a._id,
        paymentNumber:  a.paymentNumber,
        paymentDate:    a.paymentDate,
        paymentMode:    a.paymentMode,
        amount:         a.totalAmount || a.amount || 0,
        amountApplied:  a.amountApplied || 0,
        amountUnused:   a.amountUnused != null
          ? a.amountUnused
          : Math.max(0, (a.totalAmount || a.amount || 0) - (a.amountApplied || 0)),
        status:         a.status,
        referenceNumber: a.referenceNumber || '',
        notes:          a.notes || '',
      }))
      .filter(a => a.amountUnused > 0.001);

    res.json({ success: true, data: available, amountDue: bill.amountDue });
  } catch (err) {
    console.error('Error fetching available credits:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/finance/bills/:id/apply-credits
// Body: { advanceId, amount }
// Accounting: Dr Accounts Payable / Cr Advance to Vendor
router.post('/:id/apply-credits', async (req, res) => {
  try {
    const { advanceId, amount } = req.body;
    if (!advanceId || !amount || parseFloat(amount) <= 0) {
      return res.status(400).json({ success: false, error: 'advanceId and a positive amount are required' });
    }
    const applyAmt = parseFloat(amount);

    const bill = await Bill.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    if (!['OPEN', 'PARTIALLY_PAID', 'OVERDUE'].includes(bill.status)) {
      return res.status(400).json({ success: false, error: `Cannot apply credits to a bill with status ${bill.status}` });
    }
    if (applyAmt > bill.amountDue + 0.001) {
      return res.status(400).json({ success: false, error: `Amount (₹${applyAmt}) exceeds amount due (₹${bill.amountDue.toFixed(2)})` });
    }

    const PaymentMade = mongoose.models.PaymentMade ||
      mongoose.model('PaymentMade', new mongoose.Schema({}, { strict: false }));

    const advance = await PaymentMade.findById(advanceId);
    if (!advance) return res.status(404).json({ success: false, error: 'Advance payment not found' });

    const unused = advance.amountUnused != null
      ? advance.amountUnused
      : Math.max(0, (advance.totalAmount || advance.amount || 0) - (advance.amountApplied || 0));

    if (applyAmt > unused + 0.001) {
      return res.status(400).json({ success: false, error: `Amount exceeds available advance balance (₹${unused.toFixed(2)})` });
    }

    // ── 1. Update Bill ────────────────────────────────────────────────────────
    bill.vendorCreditsApplied = bill.vendorCreditsApplied || [];
    bill.vendorCreditsApplied.push({
      creditId:    advance._id,
      amount:      applyAmt,
      appliedDate: new Date(),
      paymentNumber: advance.paymentNumber,
    });
    bill.amountPaid += applyAmt;
    // amountDue is recalculated by pre-save
    await bill.save();

    // ── 2. Update Advance (PaymentMade) ───────────────────────────────────────
    advance.amountApplied = (advance.amountApplied || 0) + applyAmt;
    advance.amountUnused  = Math.max(0, unused - applyAmt);
    advance.billsApplied  = advance.billsApplied || [];
    advance.billsApplied.push({
      billId:        bill._id,
      billNumber:    bill.billNumber,
      amountApplied: applyAmt,
      appliedDate:   new Date(),
    });
    // Update status
    if (advance.amountUnused < 0.001) {
      advance.status = 'APPLIED';
    } else {
      advance.status = 'PARTIALLY_APPLIED';
    }
    await advance.save();

    // ── 3. COA Postings ───────────────────────────────────────────────────────
    // Dr Accounts Payable (reduces liability — we owe less)
    // Cr Advance to Vendor  (reduces asset — advance is consumed)
    try {
      const currentOrgId = req.user?.orgId || null;
      const branchId     = req.branchIds?.length > 0 ? req.branchIds[0] : null;
      const txnDate      = new Date();
      const desc         = `Vendor advance applied to ${bill.billNumber} (${advance.paymentNumber})`;

      const [apId, advId] = await Promise.all([
        getSystemAccountId('Accounts Payable', currentOrgId, branchId),
        getSystemAccountId('Advance to Vendor', currentOrgId),
      ]);

      if (apId) await postTransactionToCOA({
        accountId: apId, orgId: currentOrgId, branchId, date: txnDate,
        description: desc,
        referenceType: 'CreditApplication', referenceId: bill._id,
        referenceNumber: bill.billNumber,
        debit: applyAmt, credit: 0,
      });
      if (advId) await postTransactionToCOA({
        accountId: advId, orgId: currentOrgId, branchId, date: txnDate,
        description: desc,
        referenceType: 'CreditApplication', referenceId: bill._id,
        referenceNumber: bill.billNumber,
        debit: 0, credit: applyAmt,
      });
      console.log(`✅ COA posted for credit application: ${bill.billNumber} ← ${advance.paymentNumber} ₹${applyAmt}`);
    } catch (coaErr) {
      console.error('⚠️ COA post error (apply credits):', coaErr.message);
    }

    res.json({
      success: true,
      message: `₹${applyAmt.toFixed(2)} advance applied to ${bill.billNumber}`,
      data: { bill, advanceAmountUnused: advance.amountUnused },
    });
  } catch (err) {
    console.error('Error applying credits:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// DELETE /api/finance/bills/:id/apply-credits/:creditEntryId
// Reverses a previously applied credit
router.delete('/:id/apply-credits/:creditEntryId', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!bill) return res.status(404).json({ success: false, error: 'Bill not found' });

    // Find the applied credit entry by its _id (Mongoose subdoc id)
    const entry = (bill.vendorCreditsApplied || []).id(req.params.creditEntryId);
    if (!entry) return res.status(404).json({ success: false, error: 'Applied credit entry not found' });

    const reverseAmt = entry.amount;
    const advanceId  = entry.creditId;

    // ── 1. Remove from Bill ───────────────────────────────────────────────────
    entry.deleteOne();
    bill.amountPaid = Math.max(0, bill.amountPaid - reverseAmt);
    await bill.save();

    // ── 2. Restore Advance balance ────────────────────────────────────────────
    const PaymentMade = mongoose.models.PaymentMade ||
      mongoose.model('PaymentMade', new mongoose.Schema({}, { strict: false }));

    const advance = await PaymentMade.findById(advanceId);
    if (advance) {
      advance.amountApplied = Math.max(0, (advance.amountApplied || 0) - reverseAmt);
      advance.amountUnused  = (advance.amountUnused || 0) + reverseAmt;
      // Remove the billsApplied entry for this bill
      advance.billsApplied = (advance.billsApplied || []).filter(
        b => !(b.billId?.toString() === bill._id.toString() && Math.abs(b.amountApplied - reverseAmt) < 0.001)
      );
      // Restore status
      if (advance.amountUnused > 0.001 && advance.amountApplied < 0.001) {
        advance.status = 'RECORDED';
      } else if (advance.amountUnused > 0.001) {
        advance.status = 'PARTIALLY_APPLIED';
      }
      await advance.save();
    }

    // ── 3. COA Reversal ───────────────────────────────────────────────────────
    // Reverse: Cr Accounts Payable (liability goes back up)
    //          Dr Advance to Vendor (asset restored)
    try {
      const currentOrgId = req.user?.orgId || null;
      const branchId     = req.branchIds?.length > 0 ? req.branchIds[0] : null;
      const txnDate      = new Date();
      const desc         = `Reversal: vendor advance removed from ${bill.billNumber}`;

      const [apId, advId] = await Promise.all([
        getSystemAccountId('Accounts Payable', currentOrgId, branchId),
        getSystemAccountId('Advance to Vendor', currentOrgId),
      ]);

      if (apId) await postTransactionToCOA({
        accountId: apId, orgId: currentOrgId, branchId, date: txnDate,
        description: desc,
        referenceType: 'CreditReversal', referenceId: bill._id,
        referenceNumber: bill.billNumber,
        debit: 0, credit: reverseAmt,
      });
      if (advId) await postTransactionToCOA({
        accountId: advId, orgId: currentOrgId, branchId, date: txnDate,
        description: desc,
        referenceType: 'CreditReversal', referenceId: bill._id,
        referenceNumber: bill.billNumber,
        debit: reverseAmt, credit: 0,
      });
      console.log(`✅ COA reversal posted for credit removal: ${bill.billNumber} ₹${reverseAmt}`);
    } catch (coaErr) {
      console.error('⚠️ COA reversal error:', coaErr.message);
    }

    res.json({
      success: true,
      message: `₹${reverseAmt.toFixed(2)} credit reversed from ${bill.billNumber}`,
      data: { bill },
    });
  } catch (err) {
    console.error('Error removing credit:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// DELETE /api/bills/:id - Delete (only drafts)
router.delete('/:id', async (req, res) => {
  try {
    const bill = await Bill.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
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
          billData.billNumber = await generateBillNumber(req.user?.orgId || null, req.branchIds?.length > 0 ? req.branchIds[0] : null);
        }

        if (!billData.dueDate) {
          billData.dueDate = calculateDueDate(billData.billDate || new Date(), billData.paymentTerms || 'Net 30');
        }

        if (!billData.items || billData.items.length === 0) {
          billData.items = [{ itemDetails: 'Imported Bill', quantity: 1, rate: billData.totalAmount || 0, amount: billData.totalAmount || 0 }];
        }

        billData.createdBy = req.user?.email || req.user?.uid || 'system';
        billData.orgId = req.user?.orgId || null;
        billData.branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;

        const bill = new Bill(billData);
        await bill.save();

        // ── COA posting: debit each line item's expense account, credit AP ──
        try {
          const currentOrgId = req.user?.orgId || null;
          const apId = await getSystemAccountId('Accounts Payable', currentOrgId, branchId);
          const txnDate = new Date(bill.billDate);
          const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;

          for (const item of bill.items) {
            const accountName = item.account || 'Cost of Goods Sold';
            const itemAccId = await getBillExpenseAccountId(accountName, currentOrgId);
            if (itemAccId) {
              await postTransactionToCOA({ accountId: itemAccId, orgId: currentOrgId, branchId, date: txnDate, description: `Bill created - ${bill.billNumber} - ${bill.vendorName} - ${item.itemDetails}`, referenceType: 'Bill', referenceId: bill._id, referenceNumber: bill.billNumber, debit: item.amount, credit: 0 });
            }
          }
          if (apId) await postTransactionToCOA({ accountId: apId, orgId: currentOrgId, branchId, date: txnDate, description: `Bill created - ${bill.billNumber} - ${bill.vendorName}`, referenceType: 'Bill', referenceId: bill._id, referenceNumber: bill.billNumber, debit: 0, credit: bill.totalAmount });
          console.log(`   ✅ COA posted for imported bill: ${bill.billNumber}`);
        } catch (coaErr) {
          console.error(`   ⚠️ COA post error (bill bulk import):`, coaErr.message);
        }
        // ── END COA ──────────────────────────────────────────────────────────

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