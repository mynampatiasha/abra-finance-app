// ============================================================================
// INVOICE SYSTEM — ZOHO BOOKS STYLE (COMPLETE MERGED VERSION)
// ============================================================================
// File: backend/routes/invoices.js
//
// ORIGINAL FEATURES (all preserved):
// ✅ Payment account selection support
// ✅ PDF generation (single page, no color boxes)
// ✅ Clean email with selected bank details (plain text + HTML)
// ✅ Full payment receipt email (rich HTML, logo embed, gradient header)
// ✅ COA posting (AR, Sales, Tax, TDS, TCS)
// ✅ Billable expense marking
// ✅ QR code upload
// ✅ Bulk import (xlsx/xls/csv) with parseDDMMYYYY + getCol helpers
// ✅ Custom email preview (GET + PATCH)
// ✅ Backward-compat logo shims (getLogoPath / getLogoBase64)
// ✅ All original console.log debug lines preserved
// ✅ All original fallback logo paths preserved (15 paths)
//
// NEW ZOHO BOOKS GST FEATURES (added):
// ✅ GET /org-state — fetch org's state for IGST/CGST+SGST logic
// ✅ Per-item GST (itemGstRate, hsnCode, sacCode, unit per item)
// ✅ IGST vs CGST+SGST based on placeOfSupply vs sourceState
// ✅ Nested billingAddress + shippingAddress (Zoho style with attention/zip/fax)
// ✅ customerGSTIN, customerPAN, gstRegistrationType on invoice
// ✅ referenceNumber, currency (default INR)
// ✅ invoiceLevelDiscount (% or flat), shippingCharges, adjustment
// ✅ taxableTotal, totalCGST, totalSGST, totalIGST, totalTax fields
// ✅ buildTaxSummaryBySlabs() for PDF and email
// ✅ PDF: HSN/SAC column, Unit, GST%, CGST/SGST or IGST per item,
//        tax summary table by slab, Place of Supply, both addresses
// ✅ Email: per-slab tax breakdown, Place of Supply, Reference #
// ============================================================================

const express = require('express');
const router  = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer  = require('nodemailer');
const fs   = require('fs');
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
// LOGO PATH RESOLVER (original — all 15 fallback paths preserved)
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

  // ── 2. Fallback: original hardcoded paths (all 15 preserved) ────────────────
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
// MONGOOSE SCHEMA — ZOHO BOOKS STYLE (original fields + new GST fields)
// ============================================================================

// NEW: Zoho-style nested address schema
const addressSchema = new mongoose.Schema({
  attention: { type: String },
  street:    { type: String },
  city:      { type: String },
  state:     { type: String },
  zip:       { type: String },   // Zoho uses 'zip'; pincode kept as alias below
  pincode:   { type: String },   // kept for backward compat
  country:   { type: String, default: 'India' },
  phone:     { type: String },
  fax:       { type: String },
}, { _id: false });

// NEW: per-item schema with HSN/SAC, unit, per-item GST
const invoiceItemSchema = new mongoose.Schema({
  itemDetails:  { type: String, required: true },
  // ── NEW Zoho fields ─────────────────────────────────────────────────────────
  hsnCode:      { type: String, default: '' },        // HSN for goods
  sacCode:      { type: String, default: '' },        // SAC for services
  unit:         { type: String, default: 'Nos' },     // Nos/Hrs/Kg/Pcs/Box/Mtr/Ltr
  taxableAmount:{ type: Number, default: 0 },         // qty×rate − discount (pre-tax)
  itemGstRate:  { type: Number, default: 0 },         // 0/5/12/18/28
  cgstRate:     { type: Number, default: 0 },         // itemGstRate/2
  sgstRate:     { type: Number, default: 0 },         // itemGstRate/2
  igstRate:     { type: Number, default: 0 },         // itemGstRate (inter-state)
  cgstAmount:   { type: Number, default: 0 },
  sgstAmount:   { type: Number, default: 0 },
  igstAmount:   { type: Number, default: 0 },
  // ── Original fields ─────────────────────────────────────────────────────────
  quantity:     { type: Number, required: true, min: 0 },
  rate:         { type: Number, required: true, min: 0 },
  discount:     { type: Number, default: 0, min: 0 },
  discountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
  amount:       { type: Number, required: true },
  // Link to billable expense
  expenseId:    { type: mongoose.Schema.Types.ObjectId, default: null },
}, { _id: false });

const invoiceSchema = new mongoose.Schema({
  invoiceNumber: { type: String, required: true, unique: true, index: true },
  orgId:         { type: String, index: true, default: null },

  // ── Customer ────────────────────────────────────────────────────────────────
  customerId:    { type: String, required: true },
  customerName:  String,
  customerEmail: String,
  customerPhone: String,
  // NEW: customer tax identity fields
  customerGSTIN:       { type: String, default: '' },
  customerPAN:         { type: String, default: '' },
  gstRegistrationType: { type: String, default: '' },

  // ── Addresses — Zoho nested style (backward-compat: old flat fields still work) ──
  billingAddress:  { type: addressSchema, default: () => ({}) },
  shippingAddress: { type: addressSchema, default: () => ({}) },

  // ── NEW: Place of Supply + GST routing ──────────────────────────────────────
  placeOfSupply: { type: String, default: '' },   // Indian state name
  sourceState:   { type: String, default: '' },   // Org's state (fetched at creation)
  isInterState:  { type: Boolean, default: false },// true → IGST, false → CGST+SGST

  // ── Invoice Header ───────────────────────────────────────────────────────────
  orderNumber:     String,
  referenceNumber: { type: String, default: '' }, // NEW: PO/Reference number
  currency:        { type: String, default: 'INR' }, // NEW: Currency
  invoiceDate:     { type: Date, required: true, default: Date.now },
  terms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30',
  },
  dueDate:    { type: Date, required: true },
  salesperson: String,
  subject:     String,

  // ── Items ────────────────────────────────────────────────────────────────────
  items: [invoiceItemSchema],

  // ── Notes & T&C ──────────────────────────────────────────────────────────────
  customerNotes:      String,
  termsAndConditions: String,

  // ── Payment Account (original) ───────────────────────────────────────────────
  selectedPaymentAccount: {
    accountId:    mongoose.Schema.Types.ObjectId,
    accountType:  String,
    accountName:  String,
    bankName:     String,
    accountNumber:String,
    ifscCode:     String,
    accountHolder:String,
    upiId:        String,
    providerName: String,
    cardNumber:   String,
    fastagNumber: String,
    vehicleNumber:String,
    customFields: [{ fieldName: String, fieldValue: String }],
  },
  qrCodeUrl:      { type: String, default: null },
  paymentDetails: {
    bankAccount: String, ifscCode: String, bankName: String,
    accountHolder: String, upiId: String, officeAddress: String,
  },
  attachments: [{ filename: String, filepath: String, uploadedAt: Date }],

  // ── Totals — original fields kept + new Zoho fields added ───────────────────
  subTotal: { type: Number, default: 0 },

  // NEW: invoice-level discount (applied before tax, Zoho style)
  invoiceLevelDiscount:     { type: Number, default: 0 },
  invoiceLevelDiscountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
  invoiceDiscountAmount:    { type: Number, default: 0 }, // calculated

  // NEW: taxable total after invoice discount
  taxableTotal: { type: Number, default: 0 },

  // NEW: per-slab tax totals
  totalCGST: { type: Number, default: 0 },
  totalSGST: { type: Number, default: 0 },
  totalIGST: { type: Number, default: 0 },
  totalTax:  { type: Number, default: 0 },

  // Original GST fields (kept for backward compat)
  tdsRate:   { type: Number, default: 0, min: 0, max: 100 },
  tdsAmount: { type: Number, default: 0 },
  tcsRate:   { type: Number, default: 0, min: 0, max: 100 },
  tcsAmount: { type: Number, default: 0 },
  gstRate:   { type: Number, default: 18, min: 0, max: 100 }, // legacy
  cgst:      { type: Number, default: 0 },
  sgst:      { type: Number, default: 0 },
  igst:      { type: Number, default: 0 },

  // NEW: shipping + adjustment (Zoho style)
  shippingCharges: { type: Number, default: 0 },
  adjustment:      { type: Number, default: 0 },

  totalAmount: { type: Number, default: 0 },
  amountPaid:  { type: Number, default: 0 },
  amountDue:   { type: Number, default: 0 },

  // ── Status & Payments (original) ─────────────────────────────────────────────
  status: {
    type: String,
    enum: ['DRAFT', 'SENT', 'UNPAID', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED'],
    default: 'DRAFT',
    index: true,
  },
  payments: [{
    paymentId:      mongoose.Schema.Types.ObjectId,
    amount:         Number,
    paymentDate:    Date,
    paymentMethod:  { type: String, enum: ['Cash','Cheque','Bank Transfer','UPI','Card','Online'] },
    referenceNumber:String,
    notes:          String,
    recordedBy:     String,
    recordedAt:     Date,
  }],
  emailsSent: [{
    sentTo:    String,
    sentAt:    Date,
    emailType: { type: String, enum: ['invoice','reminder','payment_receipt'] },
  }],
  pdfPath:        String,
  pdfGeneratedAt: Date,
  createdBy:      { type: String, required: true },
  updatedBy:      String,
  createdAt:      { type: Date, default: Date.now },
  updatedAt:      { type: Date, default: Date.now },
  // Custom email fields (original)
  customEmailTo:      { type: String, default: null },
  customEmailSubject: { type: String, default: null },
  customEmailHtml:    { type: String, default: null },
}, { timestamps: true });

// ============================================================================
// PRE-SAVE MIDDLEWARE — NEW ZOHO BOOKS GST LOGIC (replaces original single-rate)
// ============================================================================
invoiceSchema.pre('save', async function () {

  // ── 1. Determine inter-state ─────────────────────────────────────────────────
  const placeOfSupply = (this.placeOfSupply || '').trim().toLowerCase();
  const sourceState   = (this.sourceState   || '').trim().toLowerCase();
  this.isInterState   = placeOfSupply !== '' && sourceState !== '' &&
                        placeOfSupply !== sourceState;

  // ── 2. Per-item GST calculation ──────────────────────────────────────────────
  let subTotal = 0;
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
    subTotal += taxable;

    // Per-item tax rates
    const gstRate = item.itemGstRate || 0;
    if (this.isInterState) {
      item.igstRate   = gstRate;
      item.cgstRate   = 0;
      item.sgstRate   = 0;
      item.igstAmount = Math.round(taxable * gstRate / 100 * 100) / 100;
      item.cgstAmount = 0;
      item.sgstAmount = 0;
    } else {
      item.cgstRate   = gstRate / 2;
      item.sgstRate   = gstRate / 2;
      item.igstRate   = 0;
      item.cgstAmount = Math.round(taxable * (gstRate / 2) / 100 * 100) / 100;
      item.sgstAmount = Math.round(taxable * (gstRate / 2) / 100 * 100) / 100;
      item.igstAmount = 0;
    }
    item.amount = Math.round(
      (taxable + item.cgstAmount + item.sgstAmount + item.igstAmount) * 100
    ) / 100;
  }
  this.subTotal = Math.round(subTotal * 100) / 100;

  // ── 3. Invoice-level discount ────────────────────────────────────────────────
  let invoiceDiscountAmount = 0;
  if (this.invoiceLevelDiscount > 0) {
    invoiceDiscountAmount = this.invoiceLevelDiscountType === 'percentage'
      ? Math.round(this.subTotal * this.invoiceLevelDiscount / 100 * 100) / 100
      : Math.min(this.invoiceLevelDiscount, this.subTotal);
  }
  this.invoiceDiscountAmount = invoiceDiscountAmount;
  this.taxableTotal = Math.round((this.subTotal - invoiceDiscountAmount) * 100) / 100;

  // ── 4. Sum tax across items (proportional to invoice discount) ───────────────
  const discountRatio = subTotal > 0 ? (this.taxableTotal / subTotal) : 1;
  let totalCGST = 0, totalSGST = 0, totalIGST = 0;
  for (const item of this.items) {
    const adjTaxable = Math.round(item.taxableAmount * discountRatio * 100) / 100;
    const gstRate    = item.itemGstRate || 0;
    if (this.isInterState) {
      totalIGST += Math.round(adjTaxable * gstRate / 100 * 100) / 100;
    } else {
      totalCGST += Math.round(adjTaxable * (gstRate / 2) / 100 * 100) / 100;
      totalSGST += Math.round(adjTaxable * (gstRate / 2) / 100 * 100) / 100;
    }
  }
  this.totalCGST = Math.round(totalCGST * 100) / 100;
  this.totalSGST = Math.round(totalSGST * 100) / 100;
  this.totalIGST = Math.round(totalIGST * 100) / 100;
  this.totalTax  = Math.round((totalCGST + totalSGST + totalIGST) * 100) / 100;

  // Legacy compat fields
  this.cgst    = this.totalCGST;
  this.sgst    = this.totalSGST;
  this.igst    = this.totalIGST;

  // ── 5. TDS / TCS (on taxableTotal) ──────────────────────────────────────────
  this.tdsAmount = Math.round(this.taxableTotal * (this.tdsRate || 0) / 100 * 100) / 100;
  this.tcsAmount = Math.round(this.taxableTotal * (this.tcsRate || 0) / 100 * 100) / 100;

  // ── 6. Grand Total = taxableTotal + tax − TDS + TCS + shipping + adjustment ──
  this.totalAmount = Math.round(
    (this.taxableTotal + this.totalTax - this.tdsAmount + this.tcsAmount +
     (this.shippingCharges || 0) + (this.adjustment || 0)) * 100
  ) / 100;

  this.amountDue = Math.round((this.totalAmount - (this.amountPaid || 0)) * 100) / 100;

  // ── 7. Status logic (original) ───────────────────────────────────────────────
  if (this.amountPaid === 0 && this.status !== 'DRAFT' && this.status !== 'CANCELLED') {
    this.status = 'UNPAID';
  } else if (this.amountPaid > 0 && this.amountPaid < this.totalAmount) {
    this.status = 'PARTIALLY_PAID';
  } else if (this.totalAmount > 0 && this.amountPaid >= this.totalAmount) {
    this.status = 'PAID';
  }
  if (this.status !== 'PAID' && this.status !== 'DRAFT' &&
      this.status !== 'CANCELLED' && this.dueDate < new Date()) {
    this.status = 'OVERDUE';
  }
});

invoiceSchema.index({ customerId: 1, invoiceDate: -1 });
invoiceSchema.index({ status: 1, dueDate: 1 });
invoiceSchema.index({ createdAt: -1 });

const Invoice = mongoose.models.Invoice || mongoose.model('Invoice', invoiceSchema);

// ============================================================================
// HELPER FUNCTIONS (all original + new ones)
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
    case 'Due on Receipt': return date;
    case 'Net 15': date.setDate(date.getDate() + 15); return date;
    case 'Net 30': date.setDate(date.getDate() + 30); return date;
    case 'Net 45': date.setDate(date.getDate() + 45); return date;
    case 'Net 60': date.setDate(date.getDate() + 60); return date;
    default: date.setDate(date.getDate() + 30); return date;
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

// ── NEW: Get org data (shared helper for PDF + email + org-state route) ────────
async function getOrgData(orgId) {
  try {
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({
        orgId: String, orgName: String, gstNumber: String,
        address: String, email: String, phone: String, state: String,
      }), 'organizations');
    return await OrgModel.findOne({ orgId }).lean();
  } catch (e) {
    console.warn('⚠️ Could not fetch org data:', e.message);
    return null;
  }
}

// ── NEW: Build tax summary by slab (mirrors Zoho Books) ─────────────────────
function buildTaxSummaryBySlabs(invoice) {
  const slabs = {};
  const isInterState = invoice.isInterState;
  for (const item of (invoice.items || [])) {
    const rate = item.itemGstRate || 0;
    if (!slabs[rate]) {
      slabs[rate] = { gstRate: rate, taxableAmount: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0 };
    }
    slabs[rate].taxableAmount += item.taxableAmount || 0;
    if (isInterState) {
      slabs[rate].igst     += item.igstAmount || 0;
      slabs[rate].totalTax += item.igstAmount || 0;
    } else {
      slabs[rate].cgst     += item.cgstAmount || 0;
      slabs[rate].sgst     += item.sgstAmount || 0;
      slabs[rate].totalTax += (item.cgstAmount || 0) + (item.sgstAmount || 0);
    }
  }
  return Object.values(slabs)
    .sort((a, b) => a.gstRate - b.gstRate)
    .map(s => ({
      ...s,
      taxableAmount: Math.round(s.taxableAmount * 100) / 100,
      cgst:          Math.round(s.cgst          * 100) / 100,
      sgst:          Math.round(s.sgst          * 100) / 100,
      igst:          Math.round(s.igst          * 100) / 100,
      totalTax:      Math.round(s.totalTax      * 100) / 100,
    }));
}

// ── NEW: Format address object to readable string ─────────────────────────────
function formatAddress(addr) {
  if (!addr) return '';
  return [addr.attention, addr.street, addr.city, addr.state,
          addr.zip || addr.pincode, addr.country]
    .filter(Boolean).join(', ');
}

// ============================================================================
// ✅ ORIGINAL: Get Payment Info (Selected or Default)
// ============================================================================

function getPaymentInfo(invoice, org) {
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
// PDF GENERATION — ZOHO BOOKS STYLE (original structure + new GST columns)
// ============================================================================

async function generateInvoicePDF(invoice, orgId) {
  return new Promise(async (resolve, reject) => {
    try {
      console.log('📄 Starting PDF generation for invoice:', invoice.invoiceNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'invoices');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `invoice-${invoice.invoiceNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      // ── Fetch org details from DB (original) ────────────────────────────────
      let orgName  = 'Your Company';
      let orgGST   = '';
      let orgAddr  = '';
      let orgEmail = '';
      let orgPhone = '';
      let orgState = '';
      let orgData  = null;
      try {
        orgData  = await getOrgData(orgId);
        if (orgData) {
          orgName  = orgData.orgName  || orgName;
          orgGST   = orgData.gstNumber || '';
          orgAddr  = orgData.address  || '';
          orgEmail = orgData.email    || '';
          orgPhone = orgData.phone    || '';
          orgState = orgData.state    || '';
        }
      } catch (e) { console.warn('⚠️ Could not fetch org details:', e.message); }

      const doc    = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      const pageW = 515; // usable width (595 - 40*2)

      // ═══════════════════════════════════════════════════════════════════════
      // HEADER — white background, black text
      // ═══════════════════════════════════════════════════════════════════════
      const logoPath = getOrgLogoPath(orgId || null);
      let logoLoaded = false;

      const textX = logoPath ? 126 : 50;

      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail]
        .filter(Boolean);

      // Calculate total text block height for vertical centering of logo
      const textBlockHeight = 14 + 12 + (contactLines.length * 9);
      const textStartY = 35;
      const logoCenterY = textStartY + (textBlockHeight / 2);
      const logoH = 55;
      const logoY = logoCenterY - (logoH / 2);

      if (logoPath) {
        try {
          doc.image(logoPath, 44, logoY, { width: 72, height: logoH, fit: [72, logoH] });
          logoLoaded = true;
        } catch (e) { console.warn('⚠️ Logo load failed:', e.message); }
      }

      doc.fontSize(12).fillColor('#000000').font('Helvetica-Bold')
         .text(orgName.toUpperCase(), textX, textStartY, { width: 200 });
      doc.fontSize(7).fillColor('#444444').font('Helvetica')
         .text('BILLING & FINANCE', textX, textStartY + 14, { width: 200, characterSpacing: 1 });

      doc.fontSize(7).fillColor('#000000');
      let contactY = textStartY + 26;
      contactLines.forEach(line => { doc.text(line, textX, contactY, { width: 240 }); contactY += 9; });

      doc.fontSize(8).fillColor('#444444').font('Helvetica-Bold')
         .text('TAX INVOICE', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
         .text(invoice.invoiceNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`Date: ${new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#000000').font('Helvetica-Bold')
         .text(`✓ ${(invoice.status || 'DRAFT').replace(/_/g, ' ')}`, 380, 92, { width: 170, align: 'right' });

      // ═══════════════════════════════════════════════════════════════════════
      // META GRID — Single row: Bill To | Ship To | Invoice Details
      // ═══════════════════════════════════════════════════════════════════════
      const metaY    = 132;
      const colW     = pageW / 3;   // three equal columns
      const billingStr = formatAddress(invoice.billingAddress);
      const shipStr    = formatAddress(invoice.shippingAddress);
      const metaH      = 90;  // fixed taller height to fit name + address + GSTIN comfortably

      // ── Col 1: Bill To ──────────────────────────────────────────────────
      const billX = 40;
      doc.rect(billX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('BILL TO', billX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold')
         .text(invoice.customerName || 'N/A', billX + 8, metaY + 18, { width: colW - 16, ellipsis: true });
      if (billingStr) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(billingStr, billX + 8, metaY + 30, { width: colW - 16, ellipsis: true });
      }
      if (invoice.customerGSTIN) {
        const billingStr = formatAddress(invoice.billingAddress);
        // estimate lines used by address text
        const addrLineCount = billingStr ? Math.ceil(billingStr.length / 35) : 0;
        const gstY = metaY + 30 + (addrLineCount * 9);
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(`GSTIN: ${invoice.customerGSTIN}`, billX + 8, gstY, { width: colW - 16 });
      }

      // ── Col 2: Ship To ──────────────────────────────────────────────────
      const shipX = 40 + colW;
      doc.rect(shipX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('SHIP TO', shipX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      if (shipStr) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(shipStr, shipX + 8, metaY + 18, { width: colW - 16, ellipsis: true });
      } else {
        doc.fontSize(7).fillColor('#aaaaaa').font('Helvetica')
           .text('Same as billing address', shipX + 8, metaY + 18, { width: colW - 16 });
      }

      // ── Col 3: Invoice Details ──────────────────────────────────────────
      const detX = 40 + colW * 2;
      doc.rect(detX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('INVOICE DETAILS', detX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`Invoice #: ${invoice.invoiceNumber}`, detX + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(7).fillColor('#000000').font('Helvetica')
         .text(`Due: ${new Date(invoice.dueDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}`, detX + 8, metaY + 29, { width: colW - 16 });
      doc.text(`Terms: ${invoice.terms || 'Net 30'}`, detX + 8, metaY + 39, { width: colW - 16 });
      if (invoice.placeOfSupply) {
        doc.text(`Place of Supply: ${invoice.placeOfSupply}`, detX + 8, metaY + 49, { width: colW - 16 });
      }

      let tableStartY = metaY + metaH + 12;

      // ═══════════════════════════════════════════════════════════════════════
      // ITEMS TABLE — NEW: HSN/SAC + Unit + GST% + CGST/SGST or IGST columns
      // ═══════════════════════════════════════════════════════════════════════
      const isInterState = invoice.isInterState;

      // Column definitions — adaptive for inter/intra state
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
        tax1:    { x: 362, w: 46  },  // CGST or IGST
        tax2:    { x: 408, w: 46  },  // SGST
        amount:  { x: 454, w: 61  },  // ends at 515 relative to page ✅
      };

      // Header row
      doc.rect(40, tableStartY, 515, 20).fill('#0f1e3d');
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold');
      doc.text('#',        cols.num.x  + 2, tableStartY + 7, { width: cols.num.w });
      doc.text('ITEM',     cols.desc.x + 2, tableStartY + 7, { width: cols.desc.w });
      doc.text('HSN/SAC',  cols.hsn.x  + 2, tableStartY + 7, { width: cols.hsn.w });
      doc.text('UNIT',     cols.unit.x + 2, tableStartY + 7, { width: cols.unit.w });
      doc.text('QTY',      cols.qty.x  + 2, tableStartY + 7, { width: cols.qty.w,     align: 'center' });
      doc.text('RATE',     cols.rate.x + 2, tableStartY + 7, { width: cols.rate.w,    align: 'right' });
      doc.text('DISC',     cols.disc.x + 2, tableStartY + 7, { width: cols.disc.w,    align: 'right' });
      doc.text('TAXABLE',  cols.taxable.x+2,tableStartY + 7, { width: cols.taxable.w, align: 'right' });
      doc.text('GST%',     cols.gst.x  + 2, tableStartY + 7, { width: cols.gst.w,     align: 'center' });
      if (isInterState) {
        doc.text('IGST',   cols.tax1.x + 2, tableStartY + 7, { width: cols.tax1.w + cols.tax2.w, align: 'right' });
      } else {
        doc.text('CGST',   cols.tax1.x + 2, tableStartY + 7, { width: cols.tax1.w, align: 'right' });
        doc.text('SGST',   cols.tax2.x + 2, tableStartY + 7, { width: cols.tax2.w, align: 'right' });
      }
      doc.text('AMOUNT',   cols.amount.x+2, tableStartY + 7, { width: cols.amount.w,  align: 'right' });

      let rowY = tableStartY + 20;
      (invoice.items || []).forEach((item, idx) => {
        const descText   = item.itemDetails || 'N/A';
        const descWidth  = cols.desc.w - 4;
        const lineHeight = 9;
        const vPad       = 8; // top + bottom padding

        // Measure how tall the description will be when wrapped
        doc.font('Helvetica').fontSize(7);
        const descH = doc.heightOfString(descText, { width: descWidth, lineGap: 1 });
        const rowH  = Math.max(20, descH + vPad * 2);

        const fill = idx % 2 === 0 ? '#ffffff' : '#f7f9fc';
        doc.rect(40, rowY, 515, rowH).fill(fill);
        doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();

        doc.fontSize(7).fillColor('#000000');
        const hsnSac = item.hsnCode || item.sacCode || '';
        const discStr = item.discount > 0
          ? (item.discountType === 'percentage' ? `${item.discount}%` : `${item.discount}`)
          : '—';

        // vertically center single-line cells relative to rowH
        const cellY = rowY + vPad;

        doc.font('Helvetica-Bold').text(String(idx + 1), cols.num.x + 2, cellY, { width: cols.num.w });
        doc.font('Helvetica').text(descText, cols.desc.x + 2, cellY, { width: descWidth, lineGap: 1 });
        doc.text(hsnSac,                               cols.hsn.x  + 2, cellY, { width: cols.hsn.w - 2,  ellipsis: true });
        doc.text(item.unit || 'Nos',                   cols.unit.x + 2, cellY, { width: cols.unit.w });
        doc.text(String(item.quantity || 0),           cols.qty.x  + 2, cellY, { width: cols.qty.w,     align: 'center' });
        doc.text(`${(item.rate || 0).toFixed(2)}`,  cols.rate.x + 2, cellY, { width: cols.rate.w,    align: 'right' });
        doc.text(discStr,                              cols.disc.x + 2, cellY, { width: cols.disc.w,    align: 'right' });
        doc.text(`${(item.taxableAmount || 0).toFixed(2)}`, cols.taxable.x + 2, cellY, { width: cols.taxable.w, align: 'right' });
        doc.text(`${item.itemGstRate || 0}%`,          cols.gst.x  + 2, cellY, { width: cols.gst.w,     align: 'center' });
        if (isInterState) {
          doc.text(`${(item.igstAmount || 0).toFixed(2)}`, cols.tax1.x + 2, cellY, { width: cols.tax1.w + cols.tax2.w, align: 'right' });
        } else {
          doc.text(`${(item.cgstAmount || 0).toFixed(2)}`, cols.tax1.x + 2, cellY, { width: cols.tax1.w, align: 'right' });
          doc.text(`${(item.sgstAmount || 0).toFixed(2)}`, cols.tax2.x + 2, cellY, { width: cols.tax2.w, align: 'right' });
        }
        doc.font('Helvetica-Bold')
           .text(`${(item.amount || 0).toFixed(2)}`, cols.amount.x + 2, cellY, { width: cols.amount.w, align: 'right' });
        rowY += rowH;
      });

      // ═══════════════════════════════════════════════════════════════════════
      // TOTALS SECTION (right side — original structure + new fields)
      // ═══════════════════════════════════════════════════════════════════════
      const totalsX   = 315;
      const totalsW   = 240;
      let totalsY = rowY + 12;
      const summaryY  = rowY + 12;
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

      tRow('Subtotal:', `Rs. ${(invoice.subTotal || 0).toFixed(2)}`);
      if ((invoice.invoiceDiscountAmount || 0) > 0) {
        tRow(`Discount (${invoice.invoiceLevelDiscountType === 'percentage' ? invoice.invoiceLevelDiscount + '%' : 'Rs.' + invoice.invoiceLevelDiscount}):`,
             `-Rs. ${invoice.invoiceDiscountAmount.toFixed(2)}`);
      }
      if (isInterState) {
        if ((invoice.totalIGST || 0) > 0) tRow(`IGST:`, `Rs. ${invoice.totalIGST.toFixed(2)}`);
      } else {
        if ((invoice.totalCGST || 0) > 0) tRow(`CGST:`, `Rs. ${invoice.totalCGST.toFixed(2)}`);
        if ((invoice.totalSGST || 0) > 0) tRow(`SGST:`, `Rs. ${invoice.totalSGST.toFixed(2)}`);
      }
      if ((invoice.tdsAmount || 0) > 0) tRow('TDS Deducted:',  `- Rs. ${invoice.tdsAmount.toFixed(2)}`);
      if ((invoice.tcsAmount || 0) > 0) tRow('TCS Collected:',  `Rs. ${invoice.tcsAmount.toFixed(2)}`);
      if ((invoice.shippingCharges || 0) > 0) tRow('Shipping:', `Rs. ${invoice.shippingCharges.toFixed(2)}`);
      if (invoice.adjustment && invoice.adjustment !== 0) {
        tRow('Adjustment:', `${invoice.adjustment > 0 ? '+' : ''}Rs. ${invoice.adjustment.toFixed(2)}`);
      }

      // Grand total box — dark navy (original)
      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('Grand Total', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Rs. ${(invoice.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      if ((invoice.amountPaid || 0) > 0) {
        tRow('Amount Paid:', `Rs. ${invoice.amountPaid.toFixed(2)}`);
        tRow('Balance Due:', `Rs. ${(invoice.amountDue || 0).toFixed(2)}`, true);
      }

      // Amount in words (original)
      const wordsY = Math.max(summaryY, totalsY) + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold')
         .text(`In Words: ${numberToWords(Math.round(invoice.totalAmount || 0))} Only`,
               48, wordsY + 5, { width: pageW - 16 });

      // ═══════════════════════════════════════════════════════════════════════
      // PAYMENT DETAILS (original)
      // ═══════════════════════════════════════════════════════════════════════
      const payInfo = getPaymentInfo(invoice, orgData);
      let notesY    = wordsY + 28;

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
        notesY = py + 8;
      }

      // ── BOTTOM SECTION: Note (left) + Signatory (right) side by side ───────
      const bottomSectionY = notesY;
      const signBoxW       = 220;
      const authBoxX       = 555 - signBoxW;

      // Org invoice note — left column only (x: 40, width: 260)
      if (orgData?.invoiceNote) {
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTE', 40, bottomSectionY, { characterSpacing: 0.8 });
        doc.moveTo(40, bottomSectionY + 9).lineTo(300, bottomSectionY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(7.5).fillColor('#374151').font('Helvetica')
           .text(orgData.invoiceNote, 40, bottomSectionY + 14, { width: 260 });
        notesY = bottomSectionY + Math.ceil(orgData.invoiceNote.length / 55) * 10 + 28;
      }

      // Notes (original)
      if (invoice.customerNotes) {
        const nY = notesY;
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTES', 40, nY, { characterSpacing: 0.8 });
        doc.moveTo(40, nY + 9).lineTo(555, nY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica')
           .text(invoice.customerNotes, 40, nY + 14, { width: pageW });
        notesY = nY + 40;
      }

      // Terms & Conditions (original)
      if (invoice.termsAndConditions) {
        const tcY = notesY + 6;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold')
           .text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(invoice.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // ── AUTHORIZED SIGNATORY — always right-aligned at bottomSectionY ────
      const signSectionY = bottomSectionY;

      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text(`For ${orgName.toUpperCase()}`, authBoxX, signSectionY, { width: signBoxW, characterSpacing: 0.5, ellipsis: true });
      doc.moveTo(authBoxX, signSectionY + 30)
         .lineTo(authBoxX + signBoxW, signSectionY + 30)
         .lineWidth(0.5).strokeColor('#aaaaaa').stroke();
      doc.fontSize(6.5).fillColor('#000000').font('Helvetica-Bold')
         .text('Authorized Signatory', authBoxX, signSectionY + 33, { width: signBoxW, align: 'center' });

      // Footer (original)
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY).lineWidth(1.5).strokeColor('#dde4ef').stroke();
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
// ✅ EMAIL SERVICE — ORIGINAL PRESERVED (plain text + HTML + QR attachment)
// New: tax summary by slab in HTML, Place of Supply, Reference # in details
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
  tls: { rejectUnauthorized: false }
});

async function sendInvoiceEmail(invoice, pdfPath, orgId) {
  console.log('📧 Sending invoice email to:', invoice.customerEmail);

  let orgData = null;
  try {
    orgData = await getOrgData(orgId);
  } catch (_) {}

  const paymentInfo  = getPaymentInfo(invoice, orgData);
  const taxSlabs     = buildTaxSummaryBySlabs(invoice);
  const isInterState = invoice.isInterState;

  const invoiceDateStr = new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
  const dueDateStr     = new Date(invoice.dueDate).toLocaleDateString('en-IN',    { day:'2-digit', month:'long', year:'numeric' });

  // ── Plain text body (original preserved) ────────────────────────────────────
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

  // Tax summary lines for plain text
  const taxLines = taxSlabs.map(s => isInterState
    ? `IGST @${s.gstRate}%      : Rs.${s.igst.toFixed(2)}  (Taxable: Rs.${s.taxableAmount.toFixed(2)})`
    : `CGST @${s.gstRate/2}%    : Rs.${s.cgst.toFixed(2)}\n  SGST @${s.gstRate/2}%    : Rs.${s.sgst.toFixed(2)}`
  ).join('\n  ');

  const textBody = `
Dear ${invoice.customerName},

Please find attached invoice ${invoice.invoiceNumber} for your reference.

INVOICE DETAILS
---------------
Invoice Number : ${invoice.invoiceNumber}
Invoice Date   : ${invoiceDateStr}
Due Date       : ${dueDateStr}
${invoice.orderNumber    ? 'Order Number   : ' + invoice.orderNumber    : ''}
${invoice.referenceNumber? 'Reference #    : ' + invoice.referenceNumber : ''}
${invoice.placeOfSupply  ? 'Place of Supply: ' + invoice.placeOfSupply  : ''}

AMOUNT SUMMARY
--------------
Subtotal       : Rs.${(invoice.subTotal || 0).toFixed(2)}
${(invoice.invoiceDiscountAmount||0) > 0 ? 'Discount       : -Rs.' + invoice.invoiceDiscountAmount.toFixed(2) : ''}
${taxLines ? 'TAX BREAKUP\n  ' + taxLines : ''}
Total Tax      : Rs.${(invoice.totalTax || 0).toFixed(2)}
${(invoice.tdsAmount||0) > 0 ? 'TDS Deducted   : -Rs.' + invoice.tdsAmount.toFixed(2) : ''}
${(invoice.shippingCharges||0) > 0 ? 'Shipping       : Rs.' + invoice.shippingCharges.toFixed(2) : ''}
Total Amount   : Rs.${(invoice.totalAmount || 0).toFixed(2)}
${invoice.amountPaid > 0 ? 'Amount Paid    : Rs.' + invoice.amountPaid.toFixed(2)  : ''}
${invoice.amountDue  > 0 ? 'Balance Due    : Rs.' + invoice.amountDue.toFixed(2)   : ''}

PAYMENT INFORMATION
-------------------
${paymentLines}

${invoice.customerNotes ? 'NOTES\n-----\n' + invoice.customerNotes + '\n' : ''}
Please send payment confirmation to ${process.env.SMTP_USER || 'accounts@yourcompany.com'}.

Thank you for your business.

Regards,
Accounts Team
`.trim();

  // ── Tax summary rows for HTML ─────────────────────────────────────────────
  const taxSummaryHtmlRows = taxSlabs.map(s => `
    <tr><td style="padding:6px 0;border-bottom:1px dashed #e8e8e8;">Taxable @${s.gstRate}%</td><td style="text-align:right;padding:6px 0;border-bottom:1px dashed #e8e8e8;">Rs.${s.taxableAmount.toFixed(2)}</td></tr>
    ${isInterState
      ? `<tr><td style="padding:6px 0;border-bottom:1px dashed #e8e8e8;">IGST @${s.gstRate}%</td><td style="text-align:right;padding:6px 0;border-bottom:1px dashed #e8e8e8;">Rs.${s.igst.toFixed(2)}</td></tr>`
      : `<tr><td style="padding:6px 0;border-bottom:1px dashed #e8e8e8;">CGST @${s.gstRate/2}%</td><td style="text-align:right;padding:6px 0;border-bottom:1px dashed #e8e8e8;">Rs.${s.cgst.toFixed(2)}</td></tr>
         <tr><td style="padding:6px 0;border-bottom:1px dashed #e8e8e8;">SGST @${s.gstRate/2}%</td><td style="text-align:right;padding:6px 0;border-bottom:1px dashed #e8e8e8;">Rs.${s.sgst.toFixed(2)}</td></tr>`
    }`).join('');

  // ── HTML body (original structure preserved + new tax slab rows) ──────────
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
  <div class="header">
    <h1>Tax Invoice</h1>
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
      ${invoice.orderNumber     ? `<tr><td>Order Number</td>   <td>${invoice.orderNumber}</td></tr>`     : ''}
      ${invoice.referenceNumber ? `<tr><td>Reference #</td>    <td>${invoice.referenceNumber}</td></tr>` : ''}
      ${invoice.placeOfSupply   ? `<tr><td>Place of Supply</td><td>${invoice.placeOfSupply}</td></tr>`   : ''}
      <tr><td>Payment Terms</td><td>${invoice.terms || 'Net 30'}</td></tr>
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(invoice.subTotal || 0).toFixed(2)}</td></tr>
      ${(invoice.invoiceDiscountAmount||0)>0 ? `<tr><td>Discount</td><td>-Rs.${invoice.invoiceDiscountAmount.toFixed(2)}</td></tr>` : ''}
      ${taxSummaryHtmlRows}
      ${(invoice.tdsAmount||0)>0 ? `<tr><td>TDS Deducted</td><td>-Rs.${invoice.tdsAmount.toFixed(2)}</td></tr>` : ''}
      ${(invoice.tcsAmount||0)>0 ? `<tr><td>TCS Collected</td><td>Rs.${invoice.tcsAmount.toFixed(2)}</td></tr>` : ''}
      ${(invoice.shippingCharges||0)>0 ? `<tr><td>Shipping</td><td>Rs.${invoice.shippingCharges.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs.${(invoice.totalAmount || 0).toFixed(2)}</td></tr>
      ${invoice.amountPaid > 0 ? `<tr><td>Amount Paid</td><td>Rs.${invoice.amountPaid.toFixed(2)}</td></tr>` : ''}
      ${invoice.amountDue  > 0 ? `<tr class="balance-row"><td>Balance Due</td><td>Rs.${invoice.amountDue.toFixed(2)}</td></tr>` : ''}
    </table>
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
    ${invoice.customerNotes ? `<div class="section-title">Notes</div><div class="notes-box">${invoice.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The invoice PDF is attached to this email for your records.<br>
      For any queries, please reply to this email or contact us directly.
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
    to:   invoice.customerEmail,
    subject: `Invoice ${invoice.invoiceNumber} — Rs.${(invoice.totalAmount || 0).toFixed(2)}`,
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

// ── sendPaymentReceiptEmail (ORIGINAL — full rich HTML preserved) ─────────────
async function sendPaymentReceiptEmail(invoice, payment, orgId = null) {
  console.log('📧 Preparing payment receipt email to:', invoice.customerEmail);
  let orgData = null;
  try {
    orgData = await getOrgData(orgId);
  } catch (_) {}
  const orgName    = orgData?.orgName   || 'Accounts Team';
  const orgGST     = orgData?.gstNumber || '';
  const orgPhone   = orgData?.phone     || '';
  const orgEmail   = orgData?.email     || '';
  const logoBase64 = getOrgLogoBase64(orgId);

  const emailHtml = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Payment Receipt - Invoice ${invoice.invoiceNumber}</title>
</head>
<body style="margin:0;padding:0;font-family:Arial,sans-serif;background-color:#f4f4f4;">
  <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background-color:#f4f4f4;">
    <tr><td align="center">
      <table width="600" cellpadding="0" cellspacing="0" border="0" style="background-color:#ffffff;border-radius:10px;overflow:hidden;box-shadow:0 4px 15px rgba(0,0,0,0.1);">
        <!-- Header -->
        <tr>
          <td style="background:linear-gradient(135deg,#27ae60 0%,#229954 100%);color:white;padding:35px;text-align:left;">
            ${logoBase64 ? `<img src="${logoBase64}" alt="${orgName}" style="max-width:180px;height:auto;display:block;margin-bottom:10px;filter:brightness(0) invert(1);">` : `<h1 style="color:#ffffff;margin:0 0 5px 0;font-size:28px;">${orgName}</h1>`}
            <p style="color:#ffffff;margin:0;letter-spacing:1px;font-size:13px;">${orgGST ? 'GSTIN: ' + orgGST : ''}</p>
            <h1 style="margin:20px 0 0 0;font-size:32px;color:#ffffff;">✅ Payment Received</h1>
            <p style="margin:5px 0 0 0;font-size:15px;color:#ffffff;">Thank you for your payment!</p>
          </td>
        </tr>
        <!-- Content -->
        <tr>
          <td style="background:#f8f9fa;padding:35px;">
            <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background:linear-gradient(135deg,#d4edda 0%,#c3e6cb 100%);border-radius:10px;text-align:center;border:2px solid #28a745;margin:25px 0;">
              <tr><td>
                <h2 style="margin:0;font-size:22px;color:#155724;">Payment Successful ✓</h2>
                <p style="margin:12px 0 0 0;font-size:16px;color:#155724;">We have received your payment of <strong>Rs.${payment.amount.toFixed(2)}</strong></p>
              </td></tr>
            </table>
            <table width="100%" cellpadding="25" cellspacing="0" border="0" style="background:white;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,0.1);margin:25px 0;">
              <tr><td>
                <h3 style="color:#27ae60;margin:0 0 20px 0;">Payment Details:</h3>
                <table width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr><td style="padding:12px 0;border-bottom:1px solid #ecf0f1;"><strong>Invoice Number:</strong></td><td style="text-align:right;padding:12px 0;border-bottom:1px solid #ecf0f1;">${invoice.invoiceNumber}</td></tr>
                  <tr><td style="padding:12px 0;border-bottom:1px solid #ecf0f1;"><strong>Amount Paid:</strong></td><td style="text-align:right;padding:12px 0;border-bottom:1px solid #ecf0f1;color:#27ae60;font-weight:bold;font-size:16px;">Rs.${payment.amount.toFixed(2)}</td></tr>
                  <tr><td style="padding:12px 0;border-bottom:1px solid #ecf0f1;"><strong>Payment Date:</strong></td><td style="text-align:right;padding:12px 0;border-bottom:1px solid #ecf0f1;">${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}</td></tr>
                  <tr><td style="padding:12px 0;border-bottom:1px solid #ecf0f1;"><strong>Payment Method:</strong></td><td style="text-align:right;padding:12px 0;border-bottom:1px solid #ecf0f1;">${payment.paymentMethod}</td></tr>
                  ${payment.referenceNumber ? `<tr><td style="padding:12px 0;border-bottom:1px solid #ecf0f1;"><strong>Reference Number:</strong></td><td style="text-align:right;padding:12px 0;border-bottom:1px solid #ecf0f1;">${payment.referenceNumber}</td></tr>` : ''}
                </table>
                <table width="100%" cellpadding="15" cellspacing="0" border="0" style="background:#fff9c4;border-radius:6px;margin-top:15px;">
                  <tr>
                    <td style="font-size:16px;"><strong>Remaining Balance:</strong></td>
                    <td style="text-align:right;color:${invoice.amountDue > 0 ? '#e74c3c' : '#27ae60'};font-weight:bold;font-size:18px;">Rs.${invoice.amountDue.toFixed(2)}</td>
                  </tr>
                </table>
              </td></tr>
            </table>
            ${invoice.amountDue === 0 ? `<table width="100%" cellpadding="18" cellspacing="0" border="0" style="background:#d4edda;border-radius:8px;text-align:center;border:2px solid #28a745;"><tr><td><p style="margin:0;color:#155724;font-size:16px;font-weight:bold;">🎉 Invoice Fully Paid - Thank You!</p></td></tr></table>` : ''}
          </td>
        </tr>
        <!-- Footer -->
        <tr>
          <td style="background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7;">
            <p style="margin:0 0 10px 0;"><strong>${orgName}</strong></p>
            <p style="margin:0;">${orgEmail}${orgPhone ? ' | ' + orgPhone : ''}${orgGST ? ' | GST: ' + orgGST : ''}</p>
            <p style="margin:15px 0 0 0;font-size:11px;">© ${new Date().getFullYear()} ${orgName}. All rights reserved.</p>
          </td>
        </tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`;

  console.log('   📤 Sending payment receipt email...');
  const result = await emailTransporter.sendMail({
    from:    `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
    to:      invoice.customerEmail,
    subject: `✅ Payment Receipt - Invoice ${invoice.invoiceNumber}`,
    html:    emailHtml
  });
  console.log('   ✅ Payment receipt sent! Message ID:', result.messageId);
  return result;
}

// ============================================================================
// API ROUTES (original order preserved)
// ============================================================================

// ── NEW: GET /org-state — fetch org's state for IGST/CGST+SGST logic ─────────
router.get('/org-state', async (req, res) => {
  try {
    const orgData = await getOrgData(req.user?.orgId);
    res.json({
      success: true,
      data: {
        state:     orgData?.state     || '',
        orgName:   orgData?.orgName   || '',
        gstNumber: orgData?.gstNumber || '',
      },
    });
  } catch (error) {
    console.error('Error fetching org state:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── GET / — list invoices (original) ─────────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    console.log('🔍 req.user full object:', JSON.stringify(req.user));
    console.log('🔍 orgId from token:', req.user?.orgId);
    console.log('🔍 query being used:', JSON.stringify({ orgId: req.user?.orgId }));

    const { status, customerId, fromDate, toDate, page = 1, limit = 20 } = req.query;
    const query = { orgId: req.user?.orgId };
    if (status)     query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.invoiceDate = {};
      if (fromDate) query.invoiceDate.$gte = new Date(fromDate);
      if (toDate)   query.invoiceDate.$lte = new Date(toDate);
    }
    const skip     = (parseInt(page) - 1) * parseInt(limit);
    const invoices = await Invoice.find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).select('-__v');
    const total    = await Invoice.countDocuments(query);
    res.json({ success: true, data: invoices, pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) } });
  } catch (error) {
    console.error('Error fetching invoices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── GET /stats (original) ─────────────────────────────────────────────────────
router.get('/stats', async (req, res) => {
  try {
    const stats = await Invoice.aggregate([
      { $match: { orgId: req.user?.orgId } },
      { $group: { _id: '$status', count: { $sum: 1 }, totalAmount: { $sum: '$totalAmount' }, totalPaid: { $sum: '$amountPaid' }, totalDue: { $sum: '$amountDue' } } }
    ]);
    const overallStats = { totalInvoices: 0, totalRevenue: 0, totalPaid: 0, totalDue: 0, byStatus: {} };
    stats.forEach(stat => {
      overallStats.totalInvoices += stat.count;
      overallStats.totalRevenue  += stat.totalAmount;
      overallStats.totalPaid     += stat.totalPaid;
      overallStats.totalDue      += stat.totalDue;
      overallStats.byStatus[stat._id] = { count: stat.count, amount: stat.totalAmount };
    });
    res.json({ success: true, data: overallStats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── Multer config for bulk import (original) ──────────────────────────────────
const importStorage = multer.memoryStorage();
const importUpload  = multer({
  storage: importStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = /xlsx|xls|csv/;
    const ext     = allowed.test(path.extname(file.originalname).toLowerCase());
    const mime    = allowed.test(file.mimetype) ||
      file.mimetype === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ||
      file.mimetype === 'application/vnd.ms-excel' ||
      file.mimetype === 'text/csv';
    if (ext || mime) cb(null, true);
    else cb(new Error('Only .xlsx, .xls, or .csv files are allowed'));
  },
});

// ── POST /import/bulk (original + new GST fields in import row) ───────────────
router.post('/import/bulk', importUpload.single('file'), async (req, res) => {
  const results = { imported: 0, errors: 0, errorDetails: [] };
  try {
    if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
    console.log('📥 Invoice bulk import started:', req.file.originalname);
    const XLSX     = require('xlsx');
    const workbook = XLSX.read(req.file.buffer, { type: 'buffer', cellDates: true });
    const rows     = XLSX.utils.sheet_to_json(workbook.Sheets[workbook.SheetNames[0]], { defval: '', raw: true, cellDates: true });
    if (!rows || rows.length === 0) return res.status(400).json({ success: false, message: 'File is empty or has no data rows' });
    console.log(`   📊 Found ${rows.length} rows`);
    const orgData = await getOrgData(req.user?.orgId);
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i]; const rowNum = i + 2;
      try {
        const customerName = getCol(row, 'customer name', 'customername', 'customer');
        if (!customerName || customerName.toLowerCase().startsWith('instruction') || customerName.toLowerCase().startsWith('sample') || customerName === '') {
          console.log(`   ⏭️  Skipping row ${rowNum}: empty or instruction row`); continue;
        }
        const customerEmail  = getCol(row, 'customer email', 'customeremail', 'email');
        const invoiceDateRaw = getCol(row, 'invoice date', 'invoicedate', 'date');
        const itemDetails    = getCol(row, 'item details', 'itemdetails', 'item', 'description');
        const quantityRaw    = getCol(row, 'quantity', 'qty', 'quantity*', 'qty*');
        const rateRaw        = getCol(row, 'rate', 'rate*', 'unit price', 'price');
        const missingFields  = [];
        if (!customerName)   missingFields.push('Customer Name');
        if (!customerEmail)  missingFields.push('Customer Email');
        if (!invoiceDateRaw) missingFields.push('Invoice Date');
        if (!itemDetails)    missingFields.push('Item Details');
        if (!quantityRaw)    missingFields.push('Quantity');
        if (!rateRaw)        missingFields.push('Rate');
        if (missingFields.length > 0) throw new Error(`Missing required fields: ${missingFields.join(', ')}`);
        const invoiceDate = parseDDMMYYYY(invoiceDateRaw);
        if (!invoiceDate) throw new Error(`Invalid Invoice Date: "${invoiceDateRaw}" — use DD/MM/YYYY`);
        const dueDateRaw = getCol(row, 'due date', 'duedate');
        const terms      = getCol(row, 'payment terms', 'paymentterms', 'terms') || 'Net 30';
        const dueDate    = dueDateRaw ? parseDDMMYYYY(dueDateRaw) : calculateDueDate(invoiceDate, terms);
        const quantity   = parseFloat(quantityRaw); const rate = parseFloat(rateRaw);
        if (isNaN(quantity) || quantity <= 0) throw new Error(`Invalid Quantity: "${quantityRaw}"`);
        if (isNaN(rate)     || rate     <= 0) throw new Error(`Invalid Rate: "${rateRaw}"`);
        const discount     = parseFloat(getCol(row, 'discount') || '0') || 0;
        const discountType = getCol(row, 'discount type', 'discounttype') === 'amount' ? 'amount' : 'percentage';
        const gstRateRaw   = getCol(row, 'gst rate', 'gstrate', 'gst rate (%)', 'gst %');
        const gstRate      = gstRateRaw ? (parseFloat(gstRateRaw) || 18) : 18;
        // NEW: per-item GST fields from import
        const itemGstRate  = parseFloat(getCol(row, 'item gst rate', 'itemgstrate') || gstRateRaw || '18') || 18;
        const hsnCode      = getCol(row, 'hsn', 'hsncode', 'hsn code') || '';
        const sacCode      = getCol(row, 'sac', 'saccode', 'sac code') || '';
        const unit         = getCol(row, 'unit') || 'Nos';
        let amount = quantity * rate;
        if (discount > 0) amount = discountType === 'percentage' ? amount - (amount * discount / 100) : amount - discount;
        amount = Math.round(amount * 100) / 100;
        const orderNumber = getCol(row, 'order number', 'ordernumber', 'order #', 'po number');
        const notes       = getCol(row, 'notes', 'customer notes', 'customernotes', 'remarks');
        const statusRaw   = getCol(row, 'status');
        const validStatuses = ['DRAFT','SENT','UNPAID','PARTIALLY_PAID','PAID','OVERDUE','CANCELLED'];
        const status      = statusRaw && validStatuses.includes(statusRaw.toUpperCase()) ? statusRaw.toUpperCase() : 'DRAFT';
        const crypto      = require('crypto');
        const customerId  = `CUST-${crypto.createHash('md5').update(customerEmail).digest('hex').substring(0,12)}`;
        const invoiceData = {
          invoiceNumber:  await generateInvoiceNumber(req.user?.orgId || null),
          customerId, customerName, customerEmail,
          orderNumber:    orderNumber || undefined,
          invoiceDate, terms, dueDate,
          placeOfSupply:  getCol(row, 'place of supply', 'placeofsupply') || '',
          sourceState:    orgData?.state || '',
          items: [{
            itemDetails, hsnCode, sacCode, unit, quantity, rate,
            discount, discountType, taxableAmount: amount,
            itemGstRate, amount,
          }],
          customerNotes:  notes || undefined,
          tdsRate: 0, tcsRate: 0, gstRate,
          status,
          createdBy:      req.user?.email || req.user?.uid || 'bulk-import',
          orgId:          req.user?.orgId || null,
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
    }
    console.log(`✅ Import complete. Imported: ${results.imported}, Errors: ${results.errors}`);
    return res.json({ success: true, message: `Import complete. ${results.imported} invoices imported, ${results.errors} failed.`, data: results });
  } catch (err) {
    console.error('❌ Bulk import fatal error:', err);
    return res.status(500).json({ success: false, message: err.message || 'Import failed' });
  }
});

// ── GET /:id (original) ───────────────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    res.json({ success: true, data: invoice });
  } catch (error) {
    console.error('Error fetching invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── POST / — create (original + new fields + org state fetch) ─────────────────
router.post('/', async (req, res) => {
  try {
    const invoiceData = req.body;
    if (!invoiceData.customerId) invoiceData.customerId = `CUST-${Date.now()}`;
    if (!invoiceData.invoiceNumber) invoiceData.invoiceNumber = await generateInvoiceNumber(req.user?.orgId || null);
    if (!invoiceData.dueDate) {
      invoiceData.dueDate = calculateDueDate(invoiceData.invoiceDate || new Date(), invoiceData.terms || 'Net 30');
    }
    // Fetch org state if not provided (for IGST logic)
    if (!invoiceData.sourceState) {
      const orgData = await getOrgData(req.user?.orgId);
      invoiceData.sourceState = orgData?.state || '';
    }
    if (invoiceData.items) {
      invoiceData.items = invoiceData.items.map(item => ({
        ...item,
        taxableAmount: calculateItemAmount(item),
        amount:        calculateItemAmount(item),
      }));
    }
    invoiceData.createdBy = req.user?.email || req.user?.uid || 'system';
    invoiceData.orgId     = req.user?.orgId || null;
    const invoice = new Invoice(invoiceData);
    await invoice.save();

    // ✅ COA posting (original preserved + totalTax instead of cgst+sgst)
    try {
      const currentOrgId = req.user?.orgId || null;
      const [arId, salesId, taxId, tdsReceivableId, tcsPayableId] = await Promise.all([
        getSystemAccountId('Accounts Receivable', currentOrgId),
        getSystemAccountId('Sales',               currentOrgId),
        getSystemAccountId('Tax Payable',          currentOrgId),
        getSystemAccountId('TDS Receivable',       currentOrgId),
        getSystemAccountId('TDS Payable',          currentOrgId),
      ]);
      const txnDate = new Date(invoice.invoiceDate);
      if (arId)    await postTransactionToCOA({ accountId: arId,    orgId: currentOrgId, date: txnDate, description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: invoice.totalAmount, credit: 0 });
      if (salesId) await postTransactionToCOA({ accountId: salesId, orgId: currentOrgId, date: txnDate, description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: 0, credit: invoice.subTotal });
      if (taxId && invoice.totalTax > 0) await postTransactionToCOA({ accountId: taxId, orgId: currentOrgId, date: txnDate, description: `GST on Invoice ${invoice.invoiceNumber}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: 0, credit: invoice.totalTax });
      if (tdsReceivableId && invoice.tdsAmount > 0) await postTransactionToCOA({ accountId: tdsReceivableId, orgId: currentOrgId, date: txnDate, description: `TDS on Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: invoice.tdsAmount, credit: 0 });
      if (tcsPayableId    && invoice.tcsAmount > 0) await postTransactionToCOA({ accountId: tcsPayableId,    orgId: currentOrgId, date: txnDate, description: `TCS on Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`, referenceType: 'Invoice', referenceId: invoice._id, referenceNumber: invoice.invoiceNumber, debit: 0, credit: invoice.tcsAmount });
      console.log(`✅ COA posted for invoice: ${invoice.invoiceNumber}`);
    } catch (coaErr) { console.error('⚠️ COA post error (invoice create):', coaErr.message); }

    // ── Mark billable expenses as billed (original) ───────────────────────────
    try {
      const expenseIds = (invoiceData.items || []).filter(item => item.expenseId).map(item => item.expenseId);
      if (expenseIds.length > 0) {
        const Expense = mongoose.models.Expense;
        if (Expense) {
          await Expense.updateMany({ _id: { $in: expenseIds } }, { $set: { isBilled: true, invoiceId: invoice._id, updatedAt: new Date() } });
          console.log(`✅ Marked ${expenseIds.length} expense(s) as billed for invoice ${invoice.invoiceNumber}`);
        }
      }
    } catch (expErr) { console.error('⚠️ Error marking expenses as billed:', expErr.message); }

    console.log(`✅ Invoice created: ${invoice.invoiceNumber}`);
    res.status(201).json({ success: true, message: 'Invoice created successfully', data: invoice });
  } catch (error) {
    console.error('Error creating invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── PUT /:id (original) ───────────────────────────────────────────────────────
router.put('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    if (invoice.status === 'PAID') return res.status(400).json({ success: false, error: 'Cannot edit paid invoices' });
    const updates = req.body;
    if (updates.items) {
      updates.items = updates.items.map(item => ({ ...item, taxableAmount: calculateItemAmount(item), amount: calculateItemAmount(item) }));
    }
    if (updates.terms && updates.terms !== invoice.terms) {
      updates.dueDate = calculateDueDate(updates.invoiceDate || invoice.invoiceDate, updates.terms);
    }
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    Object.assign(invoice, updates);
    await invoice.save();
    console.log(`✅ Invoice updated: ${invoice.invoiceNumber}`);
    res.json({ success: true, message: 'Invoice updated successfully', data: invoice });
  } catch (error) {
    console.error('Error updating invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── POST /:id/send (original) ─────────────────────────────────────────────────
router.post('/:id/send', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    let pdfInfo;
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      pdfInfo = await generateInvoicePDF(invoice, req.user?.orgId);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
    }
    const customTo      = invoice.customEmailTo;
    const customSubject = invoice.customEmailSubject;
    const customHtml    = invoice.customEmailHtml;
    const sendTo        = customTo || invoice.customerEmail;
    if (customHtml) {
      const transporter = nodemailer.createTransport({ host: process.env.SMTP_HOST || 'smtp.gmail.com', port: parseInt(process.env.SMTP_PORT || '587'), secure: false, auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD } });
      await transporter.sendMail({ from: `"Accounts" <${process.env.SMTP_USER}>`, to: sendTo, subject: customSubject || `Invoice ${invoice.invoiceNumber} — Rs.${invoice.totalAmount.toFixed(2)}`, html: customHtml, attachments: [{ filename: `Invoice-${invoice.invoiceNumber}.pdf`, path: invoice.pdfPath }] });
    } else {
      await sendInvoiceEmail(invoice, invoice.pdfPath, req.user?.orgId);
    }
    if (invoice.status === 'DRAFT') invoice.status = 'SENT';
    invoice.emailsSent.push({ sentTo: sendTo, sentAt: new Date(), emailType: 'invoice' });
    await invoice.save();
    console.log(`✅ Invoice sent: ${invoice.invoiceNumber}`);
    res.json({ success: true, message: 'Invoice sent successfully', data: invoice });
  } catch (error) {
    console.error('Error sending invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── PATCH /:id/mark-as-sent — mark invoice as SENT without sending email ──────
router.patch('/:id/mark-as-sent', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    if (['PAID', 'CANCELLED'].includes(invoice.status)) {
      return res.status(400).json({ success: false, error: `Cannot mark a ${invoice.status} invoice as sent` });
    }
    invoice.status    = 'SENT';
    invoice.updatedBy = req.user?.email || req.user?.uid || 'system';
    await invoice.save();
    console.log(`✅ Invoice marked as sent (no email): ${invoice.invoiceNumber}`);
    res.json({ success: true, message: 'Invoice marked as sent', data: invoice });
  } catch (error) {
    console.error('Error marking invoice as sent:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── POST /:id/payment (original) ──────────────────────────────────────────────
router.post('/:id/payment', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    const { amount, paymentDate, paymentMethod, referenceNumber, notes } = req.body;
    if (!amount || amount <= 0) return res.status(400).json({ success: false, error: 'Invalid payment amount' });
    if (invoice.amountDue < amount) return res.status(400).json({ success: false, error: `Payment amount exceeds due amount (Rs.${invoice.amountDue.toFixed(2)})` });
    const payment = {
      paymentId:       new mongoose.Types.ObjectId(),
      amount:          parseFloat(amount),
      paymentDate:     paymentDate ? new Date(paymentDate) : new Date(),
      paymentMethod:   paymentMethod || 'Bank Transfer',
      referenceNumber, notes,
      recordedBy:      req.user?.email || req.user?.uid || 'system',
      recordedAt:      new Date(),
    };
    invoice.payments.push(payment);
    invoice.amountPaid += payment.amount;
    await invoice.save();
    // COA (original)
    try {
      const currentOrgId = req.user?.orgId || null;
      const [cashId, arId] = await Promise.all([
        getSystemAccountId('Undeposited Funds',   currentOrgId),
        getSystemAccountId('Accounts Receivable', currentOrgId),
      ]);
      const txnDate = new Date(payment.paymentDate);
      if (cashId) await postTransactionToCOA({ accountId: cashId, orgId: currentOrgId, date: txnDate, description: `Payment received - ${invoice.invoiceNumber}`, referenceType: 'Payment', referenceId: payment.paymentId, referenceNumber: invoice.invoiceNumber, debit: payment.amount, credit: 0 });
      if (arId)   await postTransactionToCOA({ accountId: arId,   orgId: currentOrgId, date: txnDate, description: `Payment received - ${invoice.invoiceNumber}`, referenceType: 'Payment', referenceId: payment.paymentId, referenceNumber: invoice.invoiceNumber, debit: 0, credit: payment.amount });
      console.log(`✅ COA posted for payment on: ${invoice.invoiceNumber}`);
    } catch (coaErr) { console.error('⚠️ COA post error (invoice payment):', coaErr.message); }
    try { await sendPaymentReceiptEmail(invoice, payment, req.user?.orgId); }
    catch (emailError) { console.warn('Failed to send payment receipt email:', emailError.message); }
    console.log(`✅ Payment recorded: ${invoice.invoiceNumber} - Rs.${amount}`);
    res.json({ success: true, message: 'Payment recorded successfully', data: { invoice, payment } });
  } catch (error) {
    console.error('Error recording payment:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── GET /:id/pdf (original — always regenerates) ──────────────────────────────
router.get('/:id/pdf', async (req, res) => {
  if (!req.user && req.query.token) {
    try {
      const jwt = require('jsonwebtoken');
      req.user  = jwt.verify(req.query.token, process.env.FINANCE_JWT_SECRET || process.env.JWT_SECRET);
    } catch (e) { return res.status(401).json({ success: false, message: 'Invalid token' }); }
  }
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    // ✅ Always regenerate so the latest org logo is embedded
    const pdfInfo = await generateInvoicePDF(invoice, req.user?.orgId);
    invoice.pdfPath        = pdfInfo.filepath;
    invoice.pdfGeneratedAt = new Date();
    await invoice.save();
    res.download(invoice.pdfPath, `Invoice-${invoice.invoiceNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── GET /:id/download-url (original) ─────────────────────────────────────────
router.get('/:id/download-url', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      const pdfInfo = await generateInvoicePDF(invoice, req.user?.orgId);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
      await invoice.save();
    }
    const baseUrl     = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    const downloadUrl = `${baseUrl}/uploads/invoices/${path.basename(invoice.pdfPath)}`;
    res.json({ success: true, downloadUrl, filename: `Invoice-${invoice.invoiceNumber}.pdf` });
  } catch (error) {
    console.error('Error generating PDF URL:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── GET /:id/email-preview (original structure + new Zoho fields) ─────────────
router.get('/:id/email-preview', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    const org         = await getOrgData(req.user?.orgId);
    const paymentInfo = getPaymentInfo(invoice, org);
    const taxSlabs    = buildTaxSummaryBySlabs(invoice);
    const isInterState= invoice.isInterState;
    const orgName     = org?.orgName   || '';
    const orgGST      = org?.gstNumber || '';
    const orgPhone    = org?.phone     || '';
    const orgEmail    = org?.email     || '';
    const invoiceDateStr = new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const dueDateStr     = new Date(invoice.dueDate).toLocaleDateString('en-IN',    { day:'2-digit', month:'long', year:'numeric' });
    const taxSummaryRows = taxSlabs.map(s => `
      <tr><td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;">Taxable @${s.gstRate}%</td><td style="text-align:right;font-weight:600;">Rs.${s.taxableAmount.toFixed(2)}</td></tr>
      ${isInterState
        ? `<tr><td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;">IGST @${s.gstRate}%</td><td style="text-align:right;font-weight:600;">Rs.${s.igst.toFixed(2)}</td></tr>`
        : `<tr><td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;">CGST @${s.gstRate/2}%</td><td style="text-align:right;font-weight:600;">Rs.${s.cgst.toFixed(2)}</td></tr>
           <tr><td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;">SGST @${s.gstRate/2}%</td><td style="text-align:right;font-weight:600;">Rs.${s.sgst.toFixed(2)}</td></tr>`}`).join('');
    const html = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><style>
      *{margin:0;padding:0;box-sizing:border-box;}body{font-family:Arial,sans-serif;font-size:13px;color:#222;background:#f4f4f4;}
      .wrapper{max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd;}
      .header{background:#0f1e3d;padding:24px 32px;}.header h1{color:#fff;font-size:20px;font-weight:bold;margin-bottom:2px;}
      .header .inv-num{color:#fff;font-size:14px;font-weight:bold;margin-top:8px;}.body{padding:28px 32px;}
      .section-title{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px;}
      table.detail{width:100%;border-collapse:collapse;font-size:13px;}table.detail td{padding:7px 0;border-bottom:1px dashed #e8e8e8;vertical-align:top;}
      table.detail td:first-child{color:#555;width:160px;}table.detail td:last-child{font-weight:600;color:#111;text-align:right;}
      .total-row td{font-size:15px;font-weight:bold;border-top:2px solid #222;border-bottom:none;padding-top:10px;}
      .balance-row td{color:#b91c1c;}.pay-block{background:#f9f9f9;border-left:3px solid #0f1e3d;padding:12px 16px;margin:8px 0;font-size:12px;line-height:1.8;}
      .pay-block strong{display:block;font-size:11px;text-transform:uppercase;letter-spacing:0.5px;color:#555;margin-bottom:4px;}
      .footer{background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7;}
    </style></head><body><div class="wrapper">
      <div class="header"><h1>Tax Invoice</h1><p>BILLING DOCUMENT</p><div class="inv-num">${invoice.invoiceNumber}</div></div>
      <div class="body">
        <p style="font-size:14px;margin-bottom:18px;">Dear ${invoice.customerName},</p>
        <p style="color:#444;line-height:1.7;margin-bottom:6px;">Please find attached invoice <strong>${invoice.invoiceNumber}</strong>. Kindly arrange payment before the due date.</p>
        <div class="section-title">Invoice Details</div>
        <table class="detail">
          <tr><td>Invoice Number</td><td>${invoice.invoiceNumber}</td></tr>
          <tr><td>Invoice Date</td><td>${invoiceDateStr}</td></tr>
          <tr><td>Due Date</td><td>${dueDateStr}</td></tr>
          ${invoice.orderNumber     ? `<tr><td>Order Number</td><td>${invoice.orderNumber}</td></tr>`     : ''}
          ${invoice.referenceNumber ? `<tr><td>Reference #</td><td>${invoice.referenceNumber}</td></tr>`  : ''}
          ${invoice.placeOfSupply   ? `<tr><td>Place of Supply</td><td>${invoice.placeOfSupply}</td></tr>`: ''}
          <tr><td>Payment Terms</td><td>${invoice.terms || 'Net 30'}</td></tr>
        </table>
        <div class="section-title">Amount Summary</div>
        <table class="detail">
          <tr><td>Subtotal</td><td>Rs.${(invoice.subTotal||0).toFixed(2)}</td></tr>
          ${(invoice.invoiceDiscountAmount||0)>0?`<tr><td>Discount</td><td>-Rs.${invoice.invoiceDiscountAmount.toFixed(2)}</td></tr>`:''}
          ${taxSummaryRows}
          ${(invoice.tdsAmount||0)>0?`<tr><td>TDS</td><td>-Rs.${invoice.tdsAmount.toFixed(2)}</td></tr>`:''}
          ${(invoice.shippingCharges||0)>0?`<tr><td>Shipping</td><td>Rs.${invoice.shippingCharges.toFixed(2)}</td></tr>`:''}
          <tr class="total-row"><td>Total Amount</td><td>Rs.${(invoice.totalAmount||0).toFixed(2)}</td></tr>
          ${invoice.amountPaid>0?`<tr><td>Amount Paid</td><td>Rs.${invoice.amountPaid.toFixed(2)}</td></tr>`:''}
          ${invoice.amountDue>0?`<tr class="balance-row"><td>Balance Due</td><td>Rs.${invoice.amountDue.toFixed(2)}</td></tr>`:''}
        </table>
        <div class="section-title">Payment Information</div>
        ${paymentInfo.bankAccount?`<div class="pay-block"><strong>Bank Transfer</strong>Account Holder: ${paymentInfo.accountHolder||''}<br>Account: ${paymentInfo.bankAccount}<br>IFSC: ${paymentInfo.ifscCode}<br>Bank: ${paymentInfo.bankName}</div>`:''}
        ${paymentInfo.upiId?`<div class="pay-block"><strong>UPI Payment</strong>UPI ID: <strong>${paymentInfo.upiId}</strong></div>`:''}
        ${invoice.customerNotes?`<div class="section-title">Notes</div><div style="background:#fffbeb;border-left:3px solid #d97706;padding:12px 16px;font-size:12px;">${invoice.customerNotes}</div>`:''}
        <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">The invoice PDF is attached to this email for your records.</p>
      </div>
      <div class="footer"><strong>${orgName}</strong><br>${orgGST?'GST: '+orgGST+' &nbsp;|&nbsp; ':''}${orgPhone?'Ph: '+orgPhone+' &nbsp;|&nbsp; ':''}${orgEmail||''}</div>
    </div></body></html>`;
    res.json({ success: true, data: { subject: `Invoice ${invoice.invoiceNumber} — Rs.${(invoice.totalAmount||0).toFixed(2)}`, html, to: invoice.customerEmail } });
  } catch (error) {
    console.error('Error generating email preview:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── PATCH /:id/email-preview (original) ──────────────────────────────────────
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    if (to      !== undefined) invoice.customEmailTo      = to;
    if (subject !== undefined) invoice.customEmailSubject = subject;
    if (html    !== undefined) invoice.customEmailHtml    = html;
    await invoice.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    console.error('Error saving email preview:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ── DELETE /:id (original) ────────────────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    if (invoice.status !== 'DRAFT') return res.status(400).json({ success: false, error: 'Only draft invoices can be deleted' });

    // ── COA REVERSAL ON DELETE ───────────────────────────────────────────────
    try {
      const currentOrgId = req.user?.orgId || null;
      const txnDate = new Date(invoice.invoiceDate);

      const [arId, salesId, taxId, tdsReceivableId, tcsPayableId] = await Promise.all([
        getSystemAccountId('Accounts Receivable', currentOrgId),
        getSystemAccountId('Sales',               currentOrgId),
        getSystemAccountId('Tax Payable',          currentOrgId),
        getSystemAccountId('TDS Receivable',       currentOrgId),
        getSystemAccountId('TDS Payable',          currentOrgId),
      ]);

      const desc = `REVERSAL - Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`;

      // REVERSE: Cr Accounts Receivable (was Dr on create)
      if (arId) await postTransactionToCOA({
        accountId: arId, orgId: currentOrgId, date: txnDate,
        description: desc,
        referenceType: 'Invoice', referenceId: invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit: 0, credit: invoice.totalAmount,
      });

      // REVERSE: Dr Sales (was Cr on create)
      if (salesId) await postTransactionToCOA({
        accountId: salesId, orgId: currentOrgId, date: txnDate,
        description: desc,
        referenceType: 'Invoice', referenceId: invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit: invoice.subTotal, credit: 0,
      });

      // REVERSE: Dr Tax Payable (was Cr on create)
      if (taxId && invoice.totalTax > 0) await postTransactionToCOA({
        accountId: taxId, orgId: currentOrgId, date: txnDate,
        description: desc,
        referenceType: 'Invoice', referenceId: invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit: invoice.totalTax, credit: 0,
      });

      // REVERSE: Cr TDS Receivable (was Dr on create)
      if (tdsReceivableId && invoice.tdsAmount > 0) await postTransactionToCOA({
        accountId: tdsReceivableId, orgId: currentOrgId, date: txnDate,
        description: desc,
        referenceType: 'Invoice', referenceId: invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit: 0, credit: invoice.tdsAmount,
      });

      // REVERSE: Dr TCS Payable (was Cr on create)
      if (tcsPayableId && invoice.tcsAmount > 0) await postTransactionToCOA({
        accountId: tcsPayableId, orgId: currentOrgId, date: txnDate,
        description: desc,
        referenceType: 'Invoice', referenceId: invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit: invoice.tcsAmount, credit: 0,
      });

      console.log(`✅ COA reversed for deleted invoice: ${invoice.invoiceNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA reversal error (invoice delete):', coaErr.message);
    }
    // ── END COA REVERSAL ─────────────────────────────────────────────────────

    await invoice.deleteOne();
    console.log(`✅ Invoice deleted: ${invoice.invoiceNumber}`);
    res.json({ success: true, message: 'Invoice deleted successfully' });
  } catch (error) {
    console.error('Error deleting invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// ✅ QR CODE UPLOAD ROUTE (original)
// ============================================================================

const qrStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = path.join(__dirname, '..', 'uploads', 'qr-codes');
    if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    cb(null, `qr-${Date.now()}-${Math.round(Math.random() * 1E9)}${path.extname(file.originalname)}`);
  }
});

const qrUpload = multer({
  storage: qrStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    if (extname && mimetype) cb(null, true);
    else cb(new Error('Only image files (JPEG, JPG, PNG) are allowed'));
  }
});

router.post('/upload/qr-code', qrUpload.single('qrCode'), (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });
    const fileUrl = `/uploads/qr-codes/${req.file.filename}`;
    console.log('✅ QR code uploaded:', req.file.filename);
    res.json({ success: true, data: { filename: req.file.filename, url: fileUrl, size: req.file.size } });
  } catch (error) {
    console.error('QR code upload error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// HELPER FUNCTIONS (original — parseDDMMYYYY + getCol)
// ============================================================================

function parseDDMMYYYY(val) {
  if (!val) return null;
  if (val instanceof Date && !isNaN(val)) return val;
  const str = String(val).trim();
  if (str.includes('T') || /^\d{4}-\d{2}-\d{2}/.test(str)) {
    const d = new Date(str); return isNaN(d) ? null : d;
  }
  if (str.includes('/')) {
    const parts = str.split('/');
    if (parts.length === 3) {
      const a = parseInt(parts[0]), b = parseInt(parts[1]), c = parseInt(parts[2]);
      let dd, mm, yyyy;
      if (c > 1000) {
        yyyy = c;
        if (a > 12) { dd = a; mm = b; }
        else if (b > 12) { dd = b; mm = a; }
        else { dd = a; mm = b; }
      } else { yyyy = a; mm = b; dd = c; }
      const d = new Date(`${yyyy}-${String(mm).padStart(2,'0')}-${String(dd).padStart(2,'0')}`);
      return isNaN(d) ? null : d;
    }
  }
  if (str.includes('-') && str.length <= 10) {
    const parts = str.split('-');
    if (parts.length === 3 && parts[2].length === 4) {
      const d = new Date(`${parts[2]}-${parts[1].padStart(2,'0')}-${parts[0].padStart(2,'0')}`);
      return isNaN(d) ? null : d;
    }
  }
  const num = parseFloat(str);
  if (!isNaN(num) && num > 1000 && num < 100000) {
    const d = new Date((num - 25569) * 86400 * 1000); return isNaN(d) ? null : d;
  }
  const d = new Date(str); return isNaN(d) ? null : d;
}

function getCol(row, ...names) {
  for (const name of names) {
    const normalizedTarget = name.toLowerCase().replace(/[^a-z0-9]/g, '');
    const key = Object.keys(row).find(k => {
      const normalizedKey = k.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
      return normalizedKey === normalizedTarget || normalizedKey.startsWith(normalizedTarget);
    });
    if (key !== undefined && row[key] !== undefined && row[key] !== '') return String(row[key]).trim();
  }
  return null;
}

module.exports = router;