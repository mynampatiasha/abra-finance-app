// ============================================================================
// INVOICE SYSTEM - COMPLETE VERSION WITH PAYMENT ACCOUNT SELECTION
// ============================================================================
// File: backend/routes/invoices.js
// NEW FEATURES:
// ✅ Payment account selection support
// ✅ Fixed PDF to single page (no color boxes)
// ✅ Clean email with selected bank details
// ✅ All existing features preserved
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');
const multer = require('multer');

// ✅ COA Helper
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

async function getSystemAccountId(name, orgId = null) {
  try {
    const acc = await ChartOfAccount.findOne({
      accountName: name,
      isSystemAccount: true,
      orgId: orgId
    }).select('_id').lean();
    return acc ? acc._id : null;
  } catch (e) {
    console.error(`COA lookup error for "${name}":`, e.message);
    return null;
  }
}

// Import payment defaults
const DEFAULT_PAYMENT = require('../config/payment-defaults');

// ============================================================================
// LOGO PATH RESOLVER
// ============================================================================

// ── Per-org logo cache: { orgId -> { logoPath, base64, mtime } } ─────────────
const _orgLogoCache = {};

/**
 * Find the logo file path for a given orgId.
 * Searches uploads/org-logos/ first, then falls back to the original
 * hardcoded abra.jpeg / abra.jpg / abra.png search.
 */
function getOrgLogoPath(orgId) {
  // ── 1. Try org-specific uploaded logo ──────────────────────────────────────
  if (orgId) {
    const orgLogoDir = path.join(__dirname, '..', 'uploads', 'org-logos');
    if (fs.existsSync(orgLogoDir)) {
      try {
        const files = fs.readdirSync(orgLogoDir);
        const match = files.find(f => f.startsWith(`org-${orgId}-`));
        if (match) {
          const fullPath = path.join(orgLogoDir, match);
          const stats    = fs.statSync(fullPath);
          if (stats.isFile() && stats.size > 0) {
            console.log(`✅ ORG LOGO FOUND for org ${orgId}:`, fullPath);
            return fullPath;
          }
        }
      } catch (err) {
        console.warn(`⚠️  Could not scan org-logos dir:`, err.message);
      }
    }
  }

  // ── 2. Fallback: original hardcoded paths ───────────────────────────────────
  const fallbackPaths = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(__dirname, '..', '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'assets', 'abra.png'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.png'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.png'),
  ];

  for (const testPath of fallbackPaths) {
    try {
      if (fs.existsSync(testPath)) {
        const stats = fs.statSync(testPath);
        if (stats.isFile() && stats.size > 0) {
          console.log('✅ FALLBACK LOGO FOUND:', testPath);
          return testPath;
        }
      }
    } catch (_) { /* continue */ }
  }

  console.error('❌ LOGO NOT FOUND for org:', orgId || '(none)');
  return null;
}

/**
 * Returns a base64 data-URI for the org's logo (for email embedding).
 * Uses a simple in-memory cache keyed by orgId.
 */
function getOrgLogoBase64(orgId) {
  const cacheKey = orgId || '__default__';

  // Return cached value if the file hasn't changed
  if (_orgLogoCache[cacheKey]) {
    try {
      const logoPath = _orgLogoCache[cacheKey].logoPath;
      const mtime    = fs.statSync(logoPath).mtimeMs;
      if (mtime === _orgLogoCache[cacheKey].mtime) {
        return _orgLogoCache[cacheKey].base64;
      }
    } catch (_) {
      delete _orgLogoCache[cacheKey];
    }
  }

  try {
    const logoPath = getOrgLogoPath(orgId);
    if (!logoPath || !fs.existsSync(logoPath)) {
      console.warn('⚠️ Logo file not found for email encoding, orgId:', orgId);
      return null;
    }
    const imageBuffer = fs.readFileSync(logoPath);
    const base64      = imageBuffer.toString('base64');
    const ext         = path.extname(logoPath).toLowerCase();
    const mimeType    = ext === '.png'  ? 'image/png'  :
                        ext === '.webp' ? 'image/webp' : 'image/jpeg';
    const dataUri     = `data:${mimeType};base64,${base64}`;
    const mtime       = fs.statSync(logoPath).mtimeMs;
    _orgLogoCache[cacheKey] = { base64: dataUri, logoPath, mtime };
    console.log(`✅ Logo encoded for email (org: ${orgId || 'default'})`);
    return dataUri;
  } catch (error) {
    console.error('❌ Error encoding logo for email:', error.message);
    return null;
  }
}

// ── Backwards-compat shims (used by other routes that call getLogoPath()) ─────
function getLogoPath()   { return getOrgLogoPath(null); }
function getLogoBase64() { return getOrgLogoBase64(null); }

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

const invoiceSchema = new mongoose.Schema({
  invoiceNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  orgId: {
    type: String,
    index: true,
    default: null,
  },
  customerId: {
    type: String,
    required: true
  },
  customerName: String,
  customerEmail: String,
  customerPhone: String,
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  shippingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  orderNumber: String,
  invoiceDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  terms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },
  dueDate: {
    type: Date,
    required: true
  },
  salesperson: String,
  subject: String,
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
  customerNotes: String,
  termsAndConditions: String,
  
  // ✅ NEW: Selected Payment Account
  selectedPaymentAccount: {
    accountId: mongoose.Schema.Types.ObjectId,
    accountType: String,
    accountName: String,
    bankName: String,
    accountNumber: String,
    ifscCode: String,
    accountHolder: String,
    upiId: String,
    providerName: String,
    cardNumber: String,
    fastagNumber: String,
    vehicleNumber: String,
    customFields: [{
      fieldName: String,
      fieldValue: String
    }]
  },
  
  // ✅ NEW: QR Code URL
  qrCodeUrl: {
    type: String,
    default: null
  },
  
  paymentDetails: {
    bankAccount: String,
    ifscCode: String,
    bankName: String,
    accountHolder: String,
    upiId: String,
    officeAddress: String
  },
  attachments: [{
    filename: String,
    filepath: String,
    uploadedAt: Date
  }],
  
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
  
  status: {
    type: String,
    enum: ['DRAFT', 'SENT', 'UNPAID', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED'],
    default: 'DRAFT',
    index: true
  },
  
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
    paymentMethod: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online']
    },
    referenceNumber: String,
    notes: String,
    recordedBy: String,
    recordedAt: Date
  }],
  
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['invoice', 'reminder', 'payment_receipt']
    }
  }],
  
  pdfPath: String,
  pdfGeneratedAt: Date,
  
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
  // Custom email fields — saved when user edits email preview before sending
  customEmailTo:      { type: String, default: null },
  customEmailSubject: { type: String, default: null },
  customEmailHtml:    { type: String, default: null },
}, {
  timestamps: true
});

// Pre-save middleware
invoiceSchema.pre('save', async function() {
  this.subTotal = this.items.reduce((sum, item) => sum + item.amount, 0);
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
  
  const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;
  
  this.cgst = gstAmount / 2;
  this.sgst = gstAmount / 2;
  this.igst = 0;
  
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  this.amountDue = this.totalAmount - this.amountPaid;
  
  if (this.amountPaid === 0 && this.status !== 'DRAFT') {
    this.status = 'UNPAID';
  } else if (this.amountPaid > 0 && this.amountPaid < this.totalAmount) {
    this.status = 'PARTIALLY_PAID';
} else if (this.totalAmount > 0 && this.amountPaid >= this.totalAmount) {
  this.status = 'PAID';
}
  
  if (this.status !== 'PAID' && this.status !== 'DRAFT' && this.dueDate < new Date()) {
    this.status = 'OVERDUE';
  }
});

invoiceSchema.index({ customerId: 1, invoiceDate: -1 });
invoiceSchema.index({ status: 1, dueDate: 1 });
invoiceSchema.index({ createdAt: -1 });

const Invoice = mongoose.models.Invoice || mongoose.model('Invoice', invoiceSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================


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


async function generateInvoiceNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(Invoice, 'invoiceNumber', 'INV', orgId);
}

function calculateDueDate(invoiceDate, terms) {
  const date = new Date(invoiceDate);
  
  switch (terms) {
    case 'Due on Receipt':
      return date;
    case 'Net 15':
      date.setDate(date.getDate() + 15);
      return date;
    case 'Net 30':
      date.setDate(date.getDate() + 30);
      return date;
    case 'Net 45':
      date.setDate(date.getDate() + 45);
      return date;
    case 'Net 60':
      date.setDate(date.getDate() + 60);
      return date;
    default:
      date.setDate(date.getDate() + 30);
      return date;
  }
}

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

// ============================================================================
// ✅ NEW: Get Payment Info (Selected or Default)
// ============================================================================

function getPaymentInfo(invoice, org) {
  // If payment account is selected on the invoice, use it (invoice-level override)
  if (invoice.selectedPaymentAccount && invoice.selectedPaymentAccount.accountId) {
    const account = invoice.selectedPaymentAccount;
    return {
      accountHolder: account.accountHolder || org?.bankAccountHolder || DEFAULT_PAYMENT.bankAccount.accountHolder,
      bankAccount:   account.accountNumber || '',
      ifscCode:      account.ifscCode      || '',
      bankName:      account.bankName      || '',
      upiId:         account.upiId         || org?.upiId || DEFAULT_PAYMENT.upi.upiId,
      officeAddress: org?.address          || DEFAULT_PAYMENT.office.fullAddress,
      qrCodePath:    org?.qrCodePath       || '',
      accountType:   account.accountType   || 'BANK_ACCOUNT',
      accountName:   account.accountName   || '',
      providerName:  account.providerName  || '',
      cardNumber:    account.cardNumber    || '',
      fastagNumber:  account.fastagNumber  || '',
      vehicleNumber: account.vehicleNumber || '',
      customFields:  account.customFields  || [],
      otherPayment:  org?.otherPaymentOptions || '',
    };
  }

  // Fallback: use org banking profile, then hardcoded defaults
  return {
    accountHolder: org?.bankAccountHolder   || DEFAULT_PAYMENT.bankAccount.accountHolder,
    bankAccount:   org?.bankAccountNumber   || DEFAULT_PAYMENT.bankAccount.accountNumber,
    ifscCode:      org?.bankIfscCode        || DEFAULT_PAYMENT.bankAccount.ifscCode,
    bankName:      org?.bankName            || DEFAULT_PAYMENT.bankAccount.bankName,
    upiId:         org?.upiId               || DEFAULT_PAYMENT.upi.upiId,
    officeAddress: org?.address             || DEFAULT_PAYMENT.office.fullAddress,
    qrCodePath:    org?.qrCodePath          || '',
    accountType:   'BANK_ACCOUNT',
    accountName:   'Default Bank Account',
    otherPayment:  org?.otherPaymentOptions || '',
  };
}

// ============================================================================
// PDF GENERATION - FIXED TO SINGLE PAGE, NO COLOR BOXES
// ============================================================================

async function generateInvoicePDF(invoice, orgId) {
  return new Promise(async (resolve, reject) => {
    try {
      console.log('📄 Starting PDF generation for invoice:', invoice.invoiceNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'invoices');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `invoice-${invoice.invoiceNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      // ── Fetch org details from DB ──────────────────────────────────────────
      let orgName = 'Your Company';
      let orgGST  = '';
      let orgAddr = '';
      let orgEmail = '';
      let orgPhone = '';
      let orgData  = null;
      try {
        const OrgModel = mongoose.models.Organization ||
          mongoose.model('Organization', new mongoose.Schema({
            orgId: String, orgName: String, gstNumber: String,
            address: String, email: String, phone: String
          }), 'organizations');
        orgData = await OrgModel.findOne({ orgId }).lean();
        if (orgData) {
          orgName  = orgData.orgName  || orgName;
          orgGST   = orgData.gstNumber || '';
          orgAddr  = orgData.address  || '';
          orgEmail = orgData.email    || '';
          orgPhone = orgData.phone    || '';
        }
      } catch (e) { console.warn('⚠️ Could not fetch org details:', e.message); }

      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      const pageW = 515; // usable width (595 - 40*2)

      // ═══════════════════════════════════════════════════════════════════════
      // HEADER — dark navy bar (matches PHP style)
      // ═══════════════════════════════════════════════════════════════════════
      doc.rect(40, 30, pageW, 90).fill('#0f1e3d');

      // Logo (left side of header)
      const logoPath = getOrgLogoPath(orgId || null);
      let logoLoaded = false;
      if (logoPath) {
        try {
          doc.image(logoPath, 44, 35, { width: 75, height: 60, fit: [75, 60] });
          logoLoaded = true;
        } catch (e) { console.warn('⚠️ Logo load failed:', e.message); }
      }

      // Company name + details (right of logo)
      const textX = logoLoaded ? 126 : 50;
      doc.fontSize(12).fillColor('#ffffff').font('Helvetica-Bold')
         .text(orgName.toUpperCase(), textX, 40, { width: 200 });
      doc.fontSize(7).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('BILLING & FINANCE', textX, 56, { width: 200, characterSpacing: 1 });

      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail]
        .filter(Boolean);
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)');
      let contactY = 68;
      contactLines.forEach(line => {
        doc.text(line, textX, contactY, { width: 240 });
        contactY += 9;
      });

      // Document type + number (top-right of header)
      doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').font('Helvetica-Bold')
         .text('INVOICE', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold')
         .text(invoice.invoiceNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.8)').font('Helvetica')
         .text(`Date: ${new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });

      // Valid chip (status badge)
      const status = invoice.status || 'DRAFT';
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`✓ ${status.replace(/_/g,' ')}`, 380, 92, { width: 170, align: 'right' });

      // ═══════════════════════════════════════════════════════════════════════
      // META GRID — 4 boxes below header
      // ═══════════════════════════════════════════════════════════════════════
      const metaY = 132;
      const metaBoxW = pageW / 2;
      const metas = [
        { label: 'Bill To', val: invoice.customerName || 'N/A',
          sub: [invoice.billingAddress?.street, invoice.billingAddress?.city, invoice.customerEmail, invoice.customerPhone].filter(Boolean).join(' | ') },
        { label: 'Invoice Details', val: `Due: ${new Date(invoice.dueDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}`,
          sub: `Terms: ${invoice.terms || 'Net 30'} | Order: ${invoice.orderNumber || 'N/A'}` },
      ];

      metas.forEach((m, i) => {
        const bx = 40 + i * metaBoxW;
        doc.rect(bx, metaY, metaBoxW, 46).fillAndStroke('#f7f9fc', '#dde4ef');
        doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text(m.label.toUpperCase(), bx + 8, metaY + 7, { width: metaBoxW - 16, characterSpacing: 0.8 });
        doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold')
           .text(m.val, bx + 8, metaY + 18, { width: metaBoxW - 16, ellipsis: true });
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(m.sub, bx + 8, metaY + 30, { width: metaBoxW - 16, ellipsis: true });
      });

      // ═══════════════════════════════════════════════════════════════════════
      // ITEMS TABLE
      // ═══════════════════════════════════════════════════════════════════════
      const tableY = metaY + 58;

      // Table header — dark navy
      doc.rect(40, tableY, pageW, 22).fill('#0f1e3d');
      doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
      doc.text('#',           48,  tableY + 7, { width: 20 });
doc.text('DESCRIPTION', 72,  tableY + 7, { width: 200 });
doc.text('QTY',         275, tableY + 7, { width: 60,  align: 'center' });
doc.text('RATE',        340, tableY + 7, { width: 80,  align: 'right' });
doc.text('AMOUNT',      420, tableY + 7, { width: 90,  align: 'right' });

      let rowY = tableY + 22;
      const borderColor = '#000000';
      const borderWidth = 1.5;

      invoice.items.forEach((item, idx) => {
        const rowH = 24;
        const fill = idx % 2 === 0 ? '#ffffff' : '#f7f9fc';
        doc.rect(40, rowY, pageW, rowH).fill(fill);

        // row border
        doc.rect(40, rowY, pageW, rowH)
           .lineWidth(borderWidth).strokeColor(borderColor).stroke();

        doc.fontSize(8).fillColor('#000000').font('Helvetica-Bold');
doc.text(String(idx + 1), 48, rowY + 8, { width: 20 });
doc.font('Helvetica')
   .text(item.itemDetails || 'N/A', 72, rowY + 8, { width: 200, ellipsis: true });
doc.text(String(item.quantity || 0), 275, rowY + 8, { width: 60, align: 'center' });
doc.text(`Rs.${(item.rate || 0).toFixed(2)}`, 340, rowY + 8, { width: 80, align: 'right' });
doc.font('Helvetica-Bold')
   .text(`Rs.${(item.amount || 0).toFixed(2)}`, 420, rowY + 8, { width: 90, align: 'right' });
        rowY += rowH;
      });

      // ═══════════════════════════════════════════════════════════════════════
      // TOTALS SECTION (right-aligned, clean lines — no colored boxes)
      // ═══════════════════════════════════════════════════════════════════════
      const totalsX   = 355;
      const totalsW   = 200;
      const labelX    = totalsX;
      const amountX   = totalsX + totalsW;
      let   totalsY   = rowY + 16;

      const tRow = (label, amount, bold = false) => {
        doc.fontSize(8)
           .fillColor('#5e6e84').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(label, labelX, totalsY, { width: 120 });
        doc.fillColor('#000000').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(amount, labelX + 120, totalsY, { width: 80, align: 'right' });
        // dashed separator
        doc.moveTo(labelX, totalsY + 11).lineTo(amountX, totalsY + 11)
           .lineWidth(0.5).strokeColor('#dde4ef').dash(2, { space: 2 }).stroke().undash();
        totalsY += 14;
      };

      tRow('Subtotal:', `Rs. ${(invoice.subTotal || 0).toFixed(2)}`);
      if (invoice.cgst > 0)    tRow(`CGST (${invoice.gstRate / 2}%):`, `Rs. ${invoice.cgst.toFixed(2)}`);
if (invoice.sgst > 0)    tRow(`SGST (${invoice.gstRate / 2}%):`, `Rs. ${invoice.sgst.toFixed(2)}`);
if (invoice.igst > 0)    tRow(`IGST (${invoice.gstRate}%):`,     `Rs. ${invoice.igst.toFixed(2)}`);
if (invoice.tdsAmount > 0) tRow('TDS Deducted:',                  `- Rs. ${invoice.tdsAmount.toFixed(2)}`);
if (invoice.tcsAmount > 0) tRow('TCS Collected:',                 `Rs. ${invoice.tcsAmount.toFixed(2)}`);

      // Grand total box — dark navy (matches PHP grand-box)
      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('Grand Total', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
   .text(`Rs. ${(invoice.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      // Amount paid / balance due (plain lines, no colored boxes)
if (invoice.amountPaid > 0) {
  tRow('Amount Paid:', `Rs. ${invoice.amountPaid.toFixed(2)}`);
  tRow('Balance Due:', `Rs. ${(invoice.amountDue || 0).toFixed(2)}`, true);
}

      // Amount in words
      const wordsY = totalsY + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold')
         .text(`In Words: ${numberToWords(Math.round(invoice.totalAmount || 0))} Only`,
               48, wordsY + 5, { width: pageW - 16 });

      // ═══════════════════════════════════════════════════════════════════════
      // PAYMENT DETAILS (left side, if payment account selected)
      // ═══════════════════════════════════════════════════════════════════════
      const payInfo = getPaymentInfo(invoice, orgData);
      const notesY  = wordsY + 28;

      if (payInfo.bankAccount || payInfo.upiId) {
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('PAYMENT DETAILS', 40, notesY, { characterSpacing: 0.8 });
        doc.moveTo(40, notesY + 9).lineTo(555, notesY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();

        let py = notesY + 14;
        const payLine = (label, val) => {
          doc.fontSize(7.5).fillColor('#5e6e84').font('Helvetica-Bold')
             .text(`${label}:`, 40, py, { continued: true });
          doc.fillColor('#000000').font('Helvetica').text(` ${val}`);
          py += 11;
        };

        if (payInfo.accountHolder) payLine('Account Holder', payInfo.accountHolder);
        if (payInfo.bankAccount)   payLine('Account Number', payInfo.bankAccount);
        if (payInfo.ifscCode)      payLine('IFSC Code',      payInfo.ifscCode);
        if (payInfo.bankName)      payLine('Bank Name',      payInfo.bankName);
        if (payInfo.upiId)         payLine('UPI ID',         payInfo.upiId);
      }

      // Notes
      if (invoice.customerNotes) {
        const nY = notesY + (payInfo.bankAccount || payInfo.upiId ? 70 : 0);
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTES', 40, nY, { characterSpacing: 0.8 });
        doc.moveTo(40, nY + 9).lineTo(555, nY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica')
           .text(invoice.customerNotes, 40, nY + 14, { width: pageW });
      }

      // ═══════════════════════════════════════════════════════════════════════
      // TERMS & CONDITIONS
      // ═══════════════════════════════════════════════════════════════════════
      if (invoice.termsAndConditions) {
        const tcY = 660;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold')
           .text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(invoice.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // ═══════════════════════════════════════════════════════════════════════
      // FOOTER
      // ═══════════════════════════════════════════════════════════════════════
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY)
         .lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName} · ${orgGST ? 'GSTIN: ' + orgGST + ' · ' : ''}${invoice.invoiceNumber}`,
               40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`,
               40, footY + 6, { width: pageW, align: 'right' });

      doc.end();

      stream.on('finish', () => {
        console.log(`✅ PDF generated: ${filename} | Logo: ${logoLoaded ? 'YES' : 'NO'}`);
        resolve({ filename, filepath, relativePath: `/uploads/invoices/${filename}`, logoIncluded: logoLoaded });
      });
      stream.on('error', reject);

    } catch (error) {
      console.error('❌ PDF generation error:', error);
      reject(error);
    }
  });
}

// ============================================================================
// ✅ EMAIL SERVICE - USES SELECTED PAYMENT ACCOUNT
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD
  },
    tls: {
    rejectUnauthorized: false  // ← ADD THIS
  }
});

async function sendInvoiceEmail(invoice, pdfPath, orgId) {
  console.log('📧 Sending invoice email to:', invoice.customerEmail);

  // Fetch org banking details
  let orgData = null;
  try {
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    orgData = await OrgModel.findOne({ orgId }).lean();
  } catch (_) {}

  const paymentInfo = getPaymentInfo(invoice, orgData);

  // ── Build plain payment section ──────────────────────────────────────────
  let paymentLines = '';
  if (paymentInfo.bankAccount) {
    paymentLines += `
Bank Transfer / NEFT / RTGS / IMPS
  Account Holder : ${paymentInfo.accountHolder || ''}
  Account Number : ${paymentInfo.bankAccount}
  IFSC Code      : ${paymentInfo.ifscCode}
  Bank Name      : ${paymentInfo.bankName}
  Reference      : Please mention invoice number ${invoice.invoiceNumber} in remarks
`;
  }
  if (paymentInfo.upiId) {
    paymentLines += `
UPI Payment
  UPI ID : ${paymentInfo.upiId}
  (Google Pay / PhonePe / Paytm or any UPI app)
`;
  }
  if (paymentInfo.officeAddress) {
    paymentLines += `
Cash / Cheque
  Office : ${paymentInfo.officeAddress}
  Cheques in favour of: ${paymentInfo.accountHolder || ''}
`;
  }

  const invoiceDateStr = new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
  const dueDateStr     = new Date(invoice.dueDate).toLocaleDateString('en-IN',    { day:'2-digit', month:'long', year:'numeric' });

  // ── Plain text body ───────────────────────────────────────────────────────
  const textBody = `
Dear ${invoice.customerName},

Please find attached invoice ${invoice.invoiceNumber} for your reference.

INVOICE DETAILS
---------------
Invoice Number : ${invoice.invoiceNumber}
Invoice Date   : ${invoiceDateStr}
Due Date       : ${dueDateStr}
${invoice.orderNumber ? 'Order Number   : ' + invoice.orderNumber : ''}

AMOUNT SUMMARY
--------------
Subtotal       : ₹${invoice.subTotal.toFixed(2)}
${invoice.cgst > 0 ? 'CGST           : ₹' + invoice.cgst.toFixed(2) : ''}
${invoice.sgst > 0 ? 'SGST           : ₹' + invoice.sgst.toFixed(2) : ''}
${invoice.igst > 0 ? 'IGST           : ₹' + invoice.igst.toFixed(2) : ''}
Total Amount   : ₹${invoice.totalAmount.toFixed(2)}
${invoice.amountPaid > 0 ? 'Amount Paid    : ₹' + invoice.amountPaid.toFixed(2) : ''}
${invoice.amountDue  > 0 ? 'Balance Due    : ₹' + invoice.amountDue.toFixed(2)  : ''}

PAYMENT INFORMATION
-------------------
${paymentLines}

${invoice.customerNotes ? 'NOTES\n-----\n' + invoice.customerNotes + '\n' : ''}
Please send payment confirmation to ${process.env.SMTP_USER || 'accounts@yourcompany.com'}.

Thank you for your business.

Regards,
Accounts Team
`.trim();

  // ── HTML body — professional plain layout, no colors/gradients ────────────
  const htmlBody = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Invoice ${invoice.invoiceNumber}</title>
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
    .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase;
                     letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0;
                     padding-bottom: 6px; margin: 22px 0 12px; }
    table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }
    table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }
    table.detail td:first-child { color: #555; width: 160px; }
    table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }
    .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222;
                    border-bottom: none; padding-top: 10px; }
    .balance-row td { color: #b91c1c; }
    .pay-block { background: #f9f9f9; border-left: 3px solid #0f1e3d;
                 padding: 12px 16px; margin: 8px 0; font-size: 12px; line-height: 1.8; }
    .pay-block strong { display: block; font-size: 11px; text-transform: uppercase;
                        letter-spacing: 0.5px; color: #555; margin-bottom: 4px; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706;
                 padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;
              font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">

  <!-- Header -->
  <div class="header">
    <h1>Invoice</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${invoice.invoiceNumber}</div>
  </div>

  <!-- Body -->
  <div class="body">

    <p class="greeting">Dear ${invoice.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached invoice <strong>${invoice.invoiceNumber}</strong>. Kindly arrange payment before the due date.
    </p>

    <!-- Invoice Details -->
    <div class="section-title">Invoice Details</div>
    <table class="detail">
      <tr><td>Invoice Number</td><td>${invoice.invoiceNumber}</td></tr>
      <tr><td>Invoice Date</td>  <td>${invoiceDateStr}</td></tr>
      <tr><td>Due Date</td>      <td>${dueDateStr}</td></tr>
      ${invoice.orderNumber ? `<tr><td>Order Number</td><td>${invoice.orderNumber}</td></tr>` : ''}
      <tr><td>Payment Terms</td> <td>${invoice.terms || 'Net 30'}</td></tr>
    </table>

    <!-- Amount Summary -->
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>₹${invoice.subTotal.toFixed(2)}</td></tr>
      ${invoice.cgst > 0 ? `<tr><td>CGST</td><td>₹${invoice.cgst.toFixed(2)}</td></tr>` : ''}
      ${invoice.sgst > 0 ? `<tr><td>SGST</td><td>₹${invoice.sgst.toFixed(2)}</td></tr>` : ''}
      ${invoice.igst > 0 ? `<tr><td>IGST</td><td>₹${invoice.igst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>₹${invoice.totalAmount.toFixed(2)}</td></tr>
      ${invoice.amountPaid > 0 ? `<tr><td>Amount Paid</td><td>₹${invoice.amountPaid.toFixed(2)}</td></tr>` : ''}
      ${invoice.amountDue  > 0 ? `<tr class="balance-row"><td>Balance Due</td><td>₹${invoice.amountDue.toFixed(2)}</td></tr>` : ''}
    </table>

    <!-- Payment Information -->
    <div class="section-title">Payment Information</div>

    ${paymentInfo.bankAccount ? `
    <div class="pay-block">
      <strong>Bank Transfer / NEFT / RTGS / IMPS</strong>
      Account Holder : ${paymentInfo.accountHolder || ''}<br>
      Account Number : ${paymentInfo.bankAccount}<br>
      IFSC Code      : ${paymentInfo.ifscCode}<br>
      Bank Name      : ${paymentInfo.bankName}<br>
      <em style="font-size:11px;color:#555;">Please mention invoice number <strong>${invoice.invoiceNumber}</strong> in payment remarks.</em>
    </div>` : ''}

    ${paymentInfo.upiId ? `
    <div class="pay-block">
      <strong>UPI Payment</strong>
      UPI ID : <strong>${paymentInfo.upiId}</strong><br>
      <em style="font-size:11px;color:#555;">Pay via Google Pay, PhonePe, Paytm or any UPI app.</em>
    </div>` : ''}

    ${paymentInfo.officeAddress ? `
    <div class="pay-block">
      <strong>Cash / Cheque</strong>
      ${paymentInfo.officeAddress}<br>
      <em style="font-size:11px;color:#555;">Cheques in favour of "${paymentInfo.accountHolder || ''}".</em>
    </div>` : ''}

    ${invoice.customerNotes ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${invoice.customerNotes}</div>` : ''}

    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The invoice PDF is attached to this email for your records.<br>
      For any queries, please reply to this email or contact us directly.
    </p>

  </div>

  <!-- Footer -->
  <div class="footer">
    <strong>Thank you for your business.</strong><br>
    ${orgData?.orgName || ''} &nbsp;|&nbsp; ${orgData?.email || process.env.SMTP_USER || ''} &nbsp;|&nbsp; This is a system-generated email.
  </div>

</div>
</body>
</html>`;

  const mailOptions = {
    from: `"Accounts" <${process.env.SMTP_USER}>`,
    to: invoice.customerEmail,
    subject: `Invoice ${invoice.invoiceNumber} — ₹${invoice.totalAmount.toFixed(2)}`,
    text: textBody,
    html: htmlBody,
    attachments: [
      { filename: `Invoice-${invoice.invoiceNumber}.pdf`, path: pdfPath },
      ...(invoice.qrCodeUrl ? [{
        filename: 'qr-code.png',
        path: path.join(__dirname, '..', invoice.qrCodeUrl),
        cid: 'qrcode'
      }] : [])
    ]
  };

  const result = await emailTransporter.sendMail(mailOptions);
  console.log('✅ Email sent:', result.messageId);
  return result;
}

async function sendPaymentReceiptEmail(invoice, payment, orgId = null) {
  console.log('📧 Preparing payment receipt email to:', invoice.customerEmail);
  let orgData = null;
  try {
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    orgData = await OrgModel.findOne({ orgId }).lean();
  } catch (_) {}
  const orgName  = orgData?.orgName    || 'Accounts Team';
  const orgGST   = orgData?.gstNumber  || '';
  const orgPhone = orgData?.phone      || '';
  const orgEmail = orgData?.email      || '';
  const logoBase64 = getOrgLogoBase64(orgId);
  
  const emailHtml = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Payment Receipt - Invoice ${invoice.invoiceNumber}</title>
</head>
<body style="margin: 0; padding: 0; font-family: Arial, sans-serif; background-color: #f4f4f4;">
  <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background-color: #f4f4f4;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" border="0" style="background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.1);">
          
          <!-- Header -->
          <tr>
            <td style="background: linear-gradient(135deg, #27ae60 0%, #229954 100%); color: white; padding: 35px; text-align: left;">
              ${logoBase64 ? `
              <img src="${logoBase64}" alt="ABRA Travels" style="max-width: 180px; height: auto; display: block; margin-bottom: 10px; filter: brightness(0) invert(1);">
              ` : `
              <h1 style="color: #ffffff; margin: 0 0 5px 0; font-size: 28px;">${orgName}</h1>
              `}
              <p style="color: #ffffff; margin: 0; letter-spacing: 1px; font-size: 13px;">${orgGST ? 'GSTIN: ' + orgGST : ''}</p>
              <h1 style="margin: 20px 0 0 0; font-size: 32px; color: #ffffff;">✅ Payment Received</h1>
              <p style="margin: 5px 0 0 0; font-size: 15px; color: #ffffff;">Thank you for your payment!</p>
            </td>
          </tr>
          
          <!-- Content -->
          <tr>
            <td style="background: #f8f9fa; padding: 35px;">
              
              <!-- Success Badge -->
              <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background: linear-gradient(135deg, #d4edda 0%, #c3e6cb 100%); border-radius: 10px; text-align: center; border: 2px solid #28a745; margin: 25px 0;">
                <tr>
                  <td>
                    <h2 style="margin: 0; font-size: 22px; color: #155724;">Payment Successful ✓</h2>
                    <p style="margin: 12px 0 0 0; font-size: 16px; color: #155724;">We have received your payment of <strong>₹${payment.amount.toFixed(2)}</strong></p>
                  </td>
                </tr>
              </table>
              
              <!-- Payment Details Box -->
              <table width="100%" cellpadding="25" cellspacing="0" border="0" style="background: white; border-radius: 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin: 25px 0;">
                <tr>
                  <td>
                    <h3 style="color: #27ae60; margin: 0 0 20px 0;">Payment Details:</h3>
                    
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          <strong>Invoice Number:</strong>
                        </td>
                        <td style="text-align: right; padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          ${invoice.invoiceNumber}
                        </td>
                      </tr>
                      <tr>
                        <td style="padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          <strong>Amount Paid:</strong>
                        </td>
                        <td style="text-align: right; padding: 12px 0; border-bottom: 1px solid #ecf0f1; color: #27ae60; font-weight: bold; font-size: 16px;">
                          ₹${payment.amount.toFixed(2)}
                        </td>
                      </tr>
                      <tr>
                        <td style="padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          <strong>Payment Date:</strong>
                        </td>
                        <td style="text-align: right; padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          ${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}
                        </td>
                      </tr>
                      <tr>
                        <td style="padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          <strong>Payment Method:</strong>
                        </td>
                        <td style="text-align: right; padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          ${payment.paymentMethod}
                        </td>
                      </tr>
                      ${payment.referenceNumber ? `
                      <tr>
                        <td style="padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          <strong>Reference Number:</strong>
                        </td>
                        <td style="text-align: right; padding: 12px 0; border-bottom: 1px solid #ecf0f1;">
                          ${payment.referenceNumber}
                        </td>
                      </tr>
                      ` : ''}
                    </table>
                    
                    <table width="100%" cellpadding="15" cellspacing="0" border="0" style="background: #fff9c4; border-radius: 6px; margin-top: 15px;">
                      <tr>
                        <td style="font-size: 16px;">
                          <strong>Remaining Balance:</strong>
                        </td>
                        <td style="text-align: right; color: ${invoice.amountDue > 0 ? '#e74c3c' : '#27ae60'}; font-weight: bold; font-size: 18px;">
                          ₹${invoice.amountDue.toFixed(2)}
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              
              ${invoice.amountDue === 0 ? `
              <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: #d4edda; border-radius: 8px; text-align: center; border: 2px solid #28a745;">
                <tr>
                  <td>
                    <p style="margin: 0; color: #155724; font-size: 16px; font-weight: bold;">🎉 Invoice Fully Paid - Thank You!</p>
                  </td>
                </tr>
              </table>
              ` : ''}
              
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7;">
              <p style="margin: 0 0 10px 0;"><strong>${orgName}</strong></p>
              <p style="margin: 0;">${orgEmail}${orgPhone ? ' | ' + orgPhone : ''}${orgGST ? ' | GST: ' + orgGST : ''}</p>
              <p style="margin: 15px 0 0 0; font-size: 11px;">© ${new Date().getFullYear()} ${orgName}. All rights reserved.</p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
  
  console.log('   📤 Sending payment receipt email...');
  const result = await emailTransporter.sendMail({
    from: `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
    to: invoice.customerEmail,
    subject: `✅ Payment Receipt - Invoice ${invoice.invoiceNumber}`,
    html: emailHtml
  });
  console.log('   ✅ Payment receipt sent! Message ID:', result.messageId);
  
  return result;
}

// ============================================================================
// API ROUTES
// ============================================================================

router.get('/', async (req, res) => {
  try {
    console.log('🔍 req.user full object:', JSON.stringify(req.user));
    console.log('🔍 orgId from token:', req.user?.orgId);
    console.log('🔍 query being used:', JSON.stringify({ orgId: req.user?.orgId }));

    const { status, customerId, fromDate, toDate, page = 1, limit = 20 } = req.query;
    
    const query = { orgId: req.user?.orgId };
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.invoiceDate = {};
      if (fromDate) query.invoiceDate.$gte = new Date(fromDate);
      if (toDate) query.invoiceDate.$lte = new Date(toDate);
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const invoices = await Invoice.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await Invoice.countDocuments(query);
    
    res.json({
      success: true,
      data: invoices,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching invoices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/stats', async (req, res) => {
  try {
    const stats = await Invoice.aggregate([
      {
        $match: { orgId: req.user?.orgId }    // ← ADD THIS BLOCK
      },
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalPaid: { $sum: '$amountPaid' },
          totalDue: { $sum: '$amountDue' }
        }
      }
    ]);
    
    const overallStats = {
      totalInvoices: 0,
      totalRevenue: 0,
      totalPaid: 0,
      totalDue: 0,
      byStatus: {}
    };
    
    stats.forEach(stat => {
      overallStats.totalInvoices += stat.count;
      overallStats.totalRevenue += stat.totalAmount;
      overallStats.totalPaid += stat.totalPaid;
      overallStats.totalDue += stat.totalDue;
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

// ── Multer config for bulk import uploads ─────────────────────────────────────
const importStorage = multer.memoryStorage();
const importUpload = multer({
  storage: importStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = /xlsx|xls|csv/;
    const ext = allowed.test(path.extname(file.originalname).toLowerCase());
    const mime = allowed.test(file.mimetype) ||
      file.mimetype === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
      file.mimetype === 'application/vnd.ms-excel' ||
      file.mimetype === 'text/csv';
    if (ext || mime) cb(null, true);
    else cb(new Error('Only .xlsx, .xls, or .csv files are allowed'));
  },
});

router.post('/import/bulk', importUpload.single('file'), async (req, res) => {
  const results = { imported: 0, errors: 0, errorDetails: [] };

  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No file uploaded' });
    }

    console.log('📥 Invoice bulk import started:', req.file.originalname);

    // ── Parse workbook ────────────────────────────────────────────────────────
    const XLSX = require('xlsx');
    const workbook = XLSX.read(req.file.buffer, { type: 'buffer', cellDates: true });
    const sheetName = workbook.SheetNames[0];
const rows = XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], {
  defval: '',
  raw: true,
  cellDates: true,
});

    if (!rows || rows.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'File is empty or has no data rows',
      });
    }

    console.log(`   📊 Found ${rows.length} rows`);

    // ── Process each row ──────────────────────────────────────────────────────
    for (let i = 0; i < rows.length; i++) {
      const row     = rows[i];
      const rowNum  = i + 2; // +2 because row 1 = header

      try {
        // ── Skip instruction / empty rows ─────────────────────────────────────
        const customerName = getCol(row,
          'customer name', 'customername', 'customer');
        if (!customerName ||
            customerName.toLowerCase().startsWith('instruction') ||
            customerName.toLowerCase().startsWith('sample') ||
            customerName === '') {
          console.log(`   ⏭️  Skipping row ${rowNum}: empty or instruction row`);
          continue;
        }

        // ── Required fields ───────────────────────────────────────────────────
        const customerEmail = getCol(row,
          'customer email', 'customeremail', 'email');
        const invoiceDateRaw = getCol(row,
          'invoice date', 'invoicedate', 'date');
        const itemDetails = getCol(row,
          'item details', 'itemdetails', 'item', 'description');
        const quantityRaw = getCol(row,
          'quantity', 'qty', 'quantity*', 'qty*');
        const rateRaw = getCol(row,
          'rate', 'rate*', 'unit price', 'price');

        const missingFields = [];
        if (!customerName)  missingFields.push('Customer Name');
        if (!customerEmail) missingFields.push('Customer Email');
        if (!invoiceDateRaw) missingFields.push('Invoice Date');
        if (!itemDetails)   missingFields.push('Item Details');
        if (!quantityRaw)   missingFields.push('Quantity');
        if (!rateRaw)       missingFields.push('Rate');

        if (missingFields.length > 0) {
          throw new Error(`Missing required fields: ${missingFields.join(', ')}`);
        }

        // ── Parse dates ───────────────────────────────────────────────────────
        const invoiceDate = parseDDMMYYYY(invoiceDateRaw);
        if (!invoiceDate) {
          throw new Error(`Invalid Invoice Date: "${invoiceDateRaw}" — use DD/MM/YYYY`);
        }

        const dueDateRaw = getCol(row, 'due date', 'duedate');
        const terms = getCol(row,
          'payment terms', 'paymentterms', 'terms') || 'Net 30';
        const dueDate = dueDateRaw
          ? parseDDMMYYYY(dueDateRaw)
          : calculateDueDate(invoiceDate, terms);

        // ── Parse numbers ─────────────────────────────────────────────────────
        const quantity = parseFloat(quantityRaw);
        const rate     = parseFloat(rateRaw);
        if (isNaN(quantity) || quantity <= 0) {
          throw new Error(`Invalid Quantity: "${quantityRaw}"`);
        }
        if (isNaN(rate) || rate <= 0) {
          throw new Error(`Invalid Rate: "${rateRaw}"`);
        }

        const discountRaw = getCol(row, 'discount');
        const discount    = discountRaw ? (parseFloat(discountRaw) || 0) : 0;
        const discountType = getCol(row,
          'discount type', 'discounttype') === 'amount' ? 'amount' : 'percentage';

        const gstRateRaw = getCol(row,
          'gst rate', 'gstrate', 'gst rate (%)', 'gst %');
        const gstRate = gstRateRaw ? (parseFloat(gstRateRaw) || 18) : 18;

        // ── Calculate item amount ─────────────────────────────────────────────
        let amount = quantity * rate;
        if (discount > 0) {
          amount = discountType === 'percentage'
            ? amount - (amount * discount / 100)
            : amount - discount;
        }
        amount = Math.round(amount * 100) / 100;

        // ── Optional fields ───────────────────────────────────────────────────
        const orderNumber = getCol(row,
          'order number', 'ordernumber', 'order #', 'po number');
        const notes = getCol(row,
          'notes', 'customer notes', 'customernotes', 'remarks');
        const statusRaw = getCol(row, 'status');
        const validStatuses = ['DRAFT', 'SENT', 'UNPAID', 'PARTIALLY_PAID',
                               'PAID', 'OVERDUE', 'CANCELLED'];
        const status = statusRaw && validStatuses.includes(statusRaw.toUpperCase())
          ? statusRaw.toUpperCase()
          : 'DRAFT';

        // ── Find or use customer id ───────────────────────────────────────────
        const crypto = require('crypto');
        const hash   = crypto.createHash('md5').update(customerEmail).digest('hex');
        const customerId = `CUST-${hash.substring(0, 12)}`;

        // ── Build invoice data ────────────────────────────────────────────────
        const invoiceData = {
          invoiceNumber:  await generateInvoiceNumber(req.user?.orgId || null),
          customerId,
          customerName,
          customerEmail,
          orderNumber:    orderNumber || undefined,
          invoiceDate,
          terms,
          dueDate,
          items: [{
            itemDetails,
            quantity,
            rate,
            discount,
            discountType,
            amount,
          }],
          customerNotes:  notes || undefined,
          tdsRate:        0,
          tcsRate:        0,
          gstRate,
          status,
          createdBy:      req.user?.email || req.user?.uid || 'bulk-import',
          orgId:     req.user?.orgId || null,
        };

        const invoice = new Invoice(invoiceData);
        await invoice.save();

        results.imported++;
        console.log(`   ✅ Row ${rowNum}: imported invoice ${invoice.invoiceNumber}`);

      } catch (rowErr) {
        results.errors++;
        results.errorDetails.push({ row: rowNum, error: rowErr.message });
        console.warn(`   ⚠️  Row ${rowNum} error: ${rowErr.message}`);
      }
    } // end for loop

    console.log(
      `✅ Import complete. Imported: ${results.imported}, Errors: ${results.errors}`
    );

    return res.json({
      success: true,
      message: `Import complete. ${results.imported} invoices imported, ${results.errors} failed.`,
      data: results,
    });

  } catch (err) {
    console.error('❌ Bulk import fatal error:', err);
    return res.status(500).json({
      success: false,
      message: err.message || 'Import failed',
    });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    res.json({ success: true, data: invoice });
  } catch (error) {
    console.error('Error fetching invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.post('/', async (req, res) => {
  try {
    const invoiceData = req.body;
    
    if (!invoiceData.customerId) {
      invoiceData.customerId = `CUST-${Date.now()}`;
    }
    
    if (!invoiceData.invoiceNumber) {
      invoiceData.invoiceNumber = await generateInvoiceNumber(req.user?.orgId || null);
    }
    
    if (!invoiceData.dueDate) {
      invoiceData.dueDate = calculateDueDate(
        invoiceData.invoiceDate || new Date(),
        invoiceData.terms || 'Net 30'
      );
    }
    
    if (invoiceData.items) {
      invoiceData.items = invoiceData.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    invoiceData.createdBy = req.user?.email || req.user?.uid || 'system';
    invoiceData.orgId = req.user?.orgId || null;   // ← ADD THIS LINE
    
    const invoice = new Invoice(invoiceData);
    await invoice.save();

    // ✅ COA: Debit Accounts Receivable + Credit Sales
// ✅ COA: Debit Accounts Receivable + Credit Sales + TDS + TCS
try {
const currentOrgId = req.user?.orgId || null;
  const [arId, salesId, taxId, tdsReceivableId, tcsPayableId] = await Promise.all([
    getSystemAccountId('Accounts Receivable', currentOrgId),
    getSystemAccountId('Sales', currentOrgId),
    getSystemAccountId('Tax Payable', currentOrgId),
    getSystemAccountId('TDS Receivable', currentOrgId),
    getSystemAccountId('TDS Payable', currentOrgId),
  ]);
  const txnDate = new Date(invoice.invoiceDate);

  if (arId) await postTransactionToCOA({
     accountId: arId, orgId: currentOrgId,  date: txnDate,
    description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: invoice.totalAmount, credit: 0
  });

  if (salesId) await postTransactionToCOA({
    accountId: salesId, orgId: currentOrgId,  date: txnDate,
    description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: invoice.subTotal
  });

  if (taxId && (invoice.cgst + invoice.sgst) > 0) await postTransactionToCOA({
     accountId: taxId, orgId: currentOrgId,  date: txnDate,
    description: `GST on Invoice ${invoice.invoiceNumber}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: invoice.cgst + invoice.sgst
  });

  // ✅ TDS on Invoice (customer deducts TDS before paying)
  if (tdsReceivableId && invoice.tdsAmount > 0) await postTransactionToCOA({
    accountId: tdsReceivableId, orgId: currentOrgId,  date: txnDate,
    description: `TDS on Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: invoice.tdsAmount, credit: 0
  });

  // ✅ TCS on Invoice (you collect TCS from customer)
  if (tcsPayableId && invoice.tcsAmount > 0) await postTransactionToCOA({
    accountId: tcsPayableId, orgId: currentOrgId,  date: txnDate,
    description: `TCS on Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: invoice.tcsAmount
  });

  console.log(`✅ COA posted for invoice: ${invoice.invoiceNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (invoice create):', coaErr.message);
}

// ── MARK BILLABLE EXPENSES AS BILLED ───────────────────────────────────────
try {
  const expenseIds = (invoiceData.items || [])
    .filter(item => item.expenseId)
    .map(item => item.expenseId);

  if (expenseIds.length > 0) {
    const Expense = mongoose.models.Expense;
    if (Expense) {
      await Expense.updateMany(
        { _id: { $in: expenseIds } },
        {
          $set: {
            isBilled: true,
            invoiceId: invoice._id,
            updatedAt: new Date()
          }
        }
      );
      console.log(`✅ Marked ${expenseIds.length} expense(s) as billed for invoice ${invoice.invoiceNumber}`);
    }
  }
} catch (expErr) {
  console.error('⚠️ Error marking expenses as billed:', expErr.message);
}
// ── END MARK BILLABLE EXPENSES ──────────────────────────────────────────────
    
    console.log(`✅ Invoice created: ${invoice.invoiceNumber}`);
    
    res.status(201).json({
      success: true,
      message: 'Invoice created successfully',
      data: invoice
    });
  } catch (error) {
    console.error('Error creating invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.put('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    if (invoice.status === 'PAID') {
      return res.status(400).json({
        success: false,
        error: 'Cannot edit paid invoices'
      });
    }
    
    const updates = req.body;
    
    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calculateItemAmount(item)
      }));
    }
    
    if (updates.terms && updates.terms !== invoice.terms) {
      updates.dueDate = calculateDueDate(
        updates.invoiceDate || invoice.invoiceDate,
        updates.terms
      );
    }
    
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    Object.assign(invoice, updates);
    await invoice.save();
    
    console.log(`✅ Invoice updated: ${invoice.invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Invoice updated successfully',
      data: invoice
    });
  } catch (error) {
    console.error('Error updating invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.post('/:id/send', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    let pdfInfo;
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      pdfInfo = await generateInvoicePDF(invoice, req.user?.orgId);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
    }

    // Use custom email content if the user edited it in the preview dialog
    const customTo      = invoice.customEmailTo;
    const customSubject = invoice.customEmailSubject;
    const customHtml    = invoice.customEmailHtml;
    const sendTo        = customTo || invoice.customerEmail;

    if (customHtml) {
      // Send with the user-edited HTML directly
      const transporter = nodemailer.createTransport({
        host: process.env.SMTP_HOST || 'smtp.gmail.com',
        port: parseInt(process.env.SMTP_PORT || '587'),
        secure: false,
        auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
      });
      await transporter.sendMail({
        from: `"Accounts" <${process.env.SMTP_USER}>`,
        to: sendTo,
        subject: customSubject || `Invoice ${invoice.invoiceNumber} — ₹${invoice.totalAmount.toFixed(2)}`,
        html: customHtml,
        attachments: [{ filename: `Invoice-${invoice.invoiceNumber}.pdf`, path: invoice.pdfPath }],
      });
    } else {
      await sendInvoiceEmail(invoice, invoice.pdfPath, req.user?.orgId);
    }
    
    if (invoice.status === 'DRAFT') {
      invoice.status = 'SENT';
    }
    
    invoice.emailsSent.push({
      sentTo: sendTo,
      sentAt: new Date(),
      emailType: 'invoice'
    });
    
    await invoice.save();
    
    console.log(`✅ Invoice sent: ${invoice.invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Invoice sent successfully',
      data: invoice
    });
  } catch (error) {
    console.error('Error sending invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.post('/:id/payment', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    const { amount, paymentDate, paymentMethod, referenceNumber, notes } = req.body;
    
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid payment amount' });
    }
    
    if (invoice.amountDue < amount) {
      return res.status(400).json({
        success: false,
        error: `Payment amount exceeds due amount (₹${invoice.amountDue.toFixed(2)})`
      });
    }
    
    const payment = {
      paymentId: new mongoose.Types.ObjectId(),
      amount: parseFloat(amount),
      paymentDate: paymentDate ? new Date(paymentDate) : new Date(),
      paymentMethod: paymentMethod || 'Bank Transfer',
      referenceNumber,
      notes,
      recordedBy: req.user?.email || req.user?.uid || 'system',
      recordedAt: new Date()
    };
    
    invoice.payments.push(payment);
    invoice.amountPaid += payment.amount;
    await invoice.save();

    // ✅ COA: Debit Undeposited Funds + Credit Accounts Receivable
try {
const currentOrgId = req.user?.orgId || null;
  const [cashId, arId] = await Promise.all([
    getSystemAccountId('Undeposited Funds', currentOrgId),
    getSystemAccountId('Accounts Receivable', currentOrgId),
  ]);
  const txnDate = new Date(payment.paymentDate);
  if (cashId) await postTransactionToCOA({
    accountId: cashId, orgId: currentOrgId,  date: txnDate,
    description: `Payment received - ${invoice.invoiceNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: invoice.invoiceNumber,
    debit: payment.amount, credit: 0
  });
  if (arId) await postTransactionToCOA({
     accountId: arId, orgId: currentOrgId,  date: txnDate,
    description: `Payment received - ${invoice.invoiceNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: payment.amount
  });
  console.log(`✅ COA posted for payment on: ${invoice.invoiceNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (invoice payment):', coaErr.message);
}
    
    try {
      await sendPaymentReceiptEmail(invoice, payment, req.user?.orgId);    } catch (emailError) {
      console.warn('Failed to send payment receipt email:', emailError.message);
    }
    
    console.log(`✅ Payment recorded: ${invoice.invoiceNumber} - ₹${amount}`);
    
    res.json({
      success: true,
      message: 'Payment recorded successfully',
      data: {
        invoice,
        payment
      }
    });
  } catch (error) {
    console.error('Error recording payment:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/:id/pdf', async (req, res) => {
  // ✅ Support token from query param for PDF download
  if (!req.user && req.query.token) {
    try {
      const jwt = require('jsonwebtoken');
      req.user = jwt.verify(
        req.query.token,
        process.env.FINANCE_JWT_SECRET || process.env.JWT_SECRET
      );
    } catch (e) {
      return res.status(401).json({ success: false, message: 'Invalid token' });
    }
  }
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    // ✅ Always regenerate so the latest org logo is embedded
    const pdfInfo = await generateInvoicePDF(invoice, req.user?.orgId);
    invoice.pdfPath = pdfInfo.filepath;
    invoice.pdfGeneratedAt = new Date();
    await invoice.save();
    
    res.download(invoice.pdfPath, `Invoice-${invoice.invoiceNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/:id/download-url', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      const pdfInfo = await generateInvoicePDF(invoice, req.user?.orgId);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
      await invoice.save();
    }
    
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    const downloadUrl = `${baseUrl}/uploads/invoices/${path.basename(invoice.pdfPath)}`;
    
    res.json({
      success: true,
      downloadUrl: downloadUrl,
      filename: `Invoice-${invoice.invoiceNumber}.pdf`
    });
  } catch (error) {
    console.error('Error generating PDF URL:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /:id/email-preview — returns the email HTML for preview without sending
router.get('/:id/email-preview', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });

    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();

    const paymentInfo = getPaymentInfo(invoice, org);
    const invoiceDateStr = new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const dueDateStr     = new Date(invoice.dueDate).toLocaleDateString('en-IN',    { day:'2-digit', month:'long', year:'numeric' });

    const orgName    = org?.orgName    || '';
    const orgGST     = org?.gstNumber  || '';
    const orgPhone   = org?.phone      || '';
    const orgEmail   = org?.email      || '';

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Invoice ${invoice.invoiceNumber}</title>
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
    .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase;
                     letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0;
                     padding-bottom: 6px; margin: 22px 0 12px; }
    table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }
    table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }
    table.detail td:first-child { color: #555; width: 160px; }
    table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }
    .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222; border-bottom: none; padding-top: 10px; }
    .balance-row td { color: #b91c1c; }
    .pay-block { background: #f9f9f9; border-left: 3px solid #0f1e3d; padding: 12px 16px; margin: 8px 0; font-size: 12px; line-height: 1.8; }
    .pay-block strong { display: block; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; color: #555; margin-bottom: 4px; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706; padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px; font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Invoice</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${invoice.invoiceNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${invoice.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached invoice <strong>${invoice.invoiceNumber}</strong>. Kindly arrange payment before the due date.
    </p>
    <div class="section-title">Invoice Details</div>
    <table class="detail">
      <tr><td>Invoice Number</td><td>${invoice.invoiceNumber}</td></tr>
      <tr><td>Invoice Date</td>  <td>${invoiceDateStr}</td></tr>
      <tr><td>Due Date</td>      <td>${dueDateStr}</td></tr>
      ${invoice.orderNumber ? `<tr><td>Order Number</td><td>${invoice.orderNumber}</td></tr>` : ''}
      <tr><td>Payment Terms</td> <td>${invoice.terms || 'Net 30'}</td></tr>
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>₹${invoice.subTotal.toFixed(2)}</td></tr>
      ${invoice.cgst > 0 ? `<tr><td>CGST</td><td>₹${invoice.cgst.toFixed(2)}</td></tr>` : ''}
      ${invoice.sgst > 0 ? `<tr><td>SGST</td><td>₹${invoice.sgst.toFixed(2)}</td></tr>` : ''}
      ${invoice.igst > 0 ? `<tr><td>IGST</td><td>₹${invoice.igst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>₹${invoice.totalAmount.toFixed(2)}</td></tr>
      ${invoice.amountPaid > 0 ? `<tr><td>Amount Paid</td><td>₹${invoice.amountPaid.toFixed(2)}</td></tr>` : ''}
      ${invoice.amountDue  > 0 ? `<tr class="balance-row"><td>Balance Due</td><td>₹${invoice.amountDue.toFixed(2)}</td></tr>` : ''}
    </table>
    <div class="section-title">Payment Information</div>
    ${paymentInfo.bankAccount ? `<div class="pay-block"><strong>Bank Transfer / NEFT / RTGS / IMPS</strong>Account Holder : ${paymentInfo.accountHolder || ''}<br>Account Number : ${paymentInfo.bankAccount}<br>IFSC Code : ${paymentInfo.ifscCode}<br>Bank Name : ${paymentInfo.bankName}</div>` : ''}
    ${paymentInfo.upiId ? `<div class="pay-block"><strong>UPI Payment</strong>UPI ID : <strong>${paymentInfo.upiId}</strong></div>` : ''}
    ${invoice.customerNotes ? `<div class="section-title">Notes</div><div class="notes-box">${invoice.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">The invoice PDF is attached to this email for your records.</p>
  </div>
  <div class="footer">
    <strong>${orgName}</strong><br>
    ${orgGST ? 'GST: ' + orgGST + ' &nbsp;|&nbsp; ' : ''}${orgPhone ? 'Ph: ' + orgPhone + ' &nbsp;|&nbsp; ' : ''}${orgEmail || ''}
  </div>
</div>
</body>
</html>`;

    res.json({
      success: true,
      data: {
        subject: `Invoice ${invoice.invoiceNumber} — ₹${invoice.totalAmount.toFixed(2)}`,
        html,
        to: invoice.customerEmail,
      }
    });
  } catch (error) {
    console.error('Error generating email preview:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    // Persist custom email fields if the model supports them
    if (to !== undefined)      invoice.customEmailTo      = to;
    if (subject !== undefined) invoice.customEmailSubject = subject;
    if (html !== undefined)    invoice.customEmailHtml    = html;
    await invoice.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    console.error('Error saving email preview:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.delete('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    if (invoice.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft invoices can be deleted'
      });
    }
    
    await invoice.deleteOne();
    
    console.log(`✅ Invoice deleted: ${invoice.invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Invoice deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// ✅ QR CODE UPLOAD ROUTE
// ============================================================================




const qrStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = path.join(__dirname, '..', 'uploads', 'qr-codes');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueName = `qr-${Date.now()}-${Math.round(Math.random() * 1E9)}${path.extname(file.originalname)}`;
    cb(null, uniqueName);
  }
});

const qrUpload = multer({
  storage: qrStorage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB limit
  fileFilter: (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    
    if (extname && mimetype) {
      cb(null, true);
    } else {
      cb(new Error('Only image files (JPEG, JPG, PNG) are allowed'));
    }
  }
});

router.post('/upload/qr-code', qrUpload.single('qrCode'), (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No file uploaded' });
    }
    
    const fileUrl = `/uploads/qr-codes/${req.file.filename}`;
    
    console.log('✅ QR code uploaded:', req.file.filename);
    
    res.json({
      success: true,
      data: {
        filename: req.file.filename,
        url: fileUrl,
        size: req.file.size
      }
    });
  } catch (error) {
    console.error('QR code upload error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// ADD THIS ENTIRE BLOCK TO backend/routes/invoices.js
// ============================================================================
// STEP 1: At the top of invoices.js, add these requires (if not already there):
//

//   const XLSX   = require('xlsx');           // npm install xlsx
//
// STEP 2: Paste the entire route below BEFORE the `module.exports = router;` line
// ============================================================================

// ── Helper: parse DD/MM/YYYY → JS Date ───────────────────────────────────────
function parseDDMMYYYY(val) {
  if (!val) return null;
  
  // Already a JS Date object (when cellDates:true)
  if (val instanceof Date && !isNaN(val)) return val;
  
  const str = String(val).trim();
  
  // ISO format: 2026-01-15 or 2026-01-15T...
  if (str.includes('T') || /^\d{4}-\d{2}-\d{2}/.test(str)) {
    const d = new Date(str);
    return isNaN(d) ? null : d;
  }
  
  // DD/MM/YYYY or M/D/YYYY or MM/DD/YYYY
  if (str.includes('/')) {
    const parts = str.split('/');
    if (parts.length === 3) {
      const a = parseInt(parts[0]);
      const b = parseInt(parts[1]);
      const c = parseInt(parts[2]);
      // If first part > 12, must be DD/MM/YYYY
      // If second part > 12, must be MM/DD/YYYY (Excel default US format)
      // Otherwise assume DD/MM/YYYY (template format)
      let dd, mm, yyyy;
      if (c > 1000) {
        // third part is year
        yyyy = c;
        if (a > 12) { dd = a; mm = b; }       // DD/MM/YYYY
        else if (b > 12) { dd = b; mm = a; }  // MM/DD/YYYY
        else { dd = a; mm = b; }              // assume DD/MM/YYYY
      } else {
        // first part is year (YYYY/MM/DD)
        yyyy = a; mm = b; dd = c;
      }
      const d = new Date(`${yyyy}-${String(mm).padStart(2,'0')}-${String(dd).padStart(2,'0')}`);
      return isNaN(d) ? null : d;
    }
  }
  
  // DD-MM-YYYY
  if (str.includes('-') && str.length <= 10) {
    const parts = str.split('-');
    if (parts.length === 3 && parts[2].length === 4) {
      const d = new Date(`${parts[2]}-${parts[1].padStart(2,'0')}-${parts[0].padStart(2,'0')}`);
      return isNaN(d) ? null : d;
    }
  }
  
  // Excel serial number (e.g. 45672)
  const num = parseFloat(str);
  if (!isNaN(num) && num > 1000 && num < 100000) {
    const d = new Date((num - 25569) * 86400 * 1000);
    return isNaN(d) ? null : d;
  }
  
  // Last resort
  const d = new Date(str);
  return isNaN(d) ? null : d;
}
function getCol(row, ...names) {
  for (const name of names) {
    const normalizedTarget = name.toLowerCase().replace(/[^a-z0-9]/g, '');
    const key = Object.keys(row).find(k => {
      const normalizedKey = k.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
      return normalizedKey === normalizedTarget ||
             normalizedKey.startsWith(normalizedTarget);
    });
    if (key !== undefined && row[key] !== undefined && row[key] !== '') {
      return String(row[key]).trim();
    }
  }
  return null;
}

// ============================================================================
// POST /api/invoices/import/bulk
// =============================router===============================================


// ============================================================================
// END OF IMPORT ROUTE — paste above `module.exports = router;`
// ============================================================================

module.exports = router;