// ============================================================================
// PURCHASE ORDER SYSTEM - COMPLETE BACKEND
// ============================================================================
// File: backend/routes/purchase_order.js
// Contains: Routes, Controllers, Schema, PDF Generation, Email Service
// Database: MongoDB with Mongoose
// Features: Create, Edit, Send, Record Receive, Convert to Bill,
//           Issue, Cancel, Close, Bulk Import, Stats, PDF Download
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ============================================================================
// LOGO PATH RESOLVER
// ============================================================================

let CACHED_LOGO_PATH = null;

function findLogoPath(orgId = null) {
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
    path.join(__dirname, '..', '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'assets', 'abra.png'),
  ];
  for (const testPath of possiblePaths) {
    try {
      if (fs.existsSync(testPath)) {
        const stats = fs.statSync(testPath);
        if (stats.isFile() && stats.size > 0) return testPath;
      }
    } catch (_) {}
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
// MONGOOSE SCHEMAS
// ============================================================================

// Purchase Order Schema
const purchaseOrderSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  purchaseOrderNumber: {
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
  vendorName: { type: String, required: true },
  vendorEmail: String,
  vendorPhone: String,

  referenceNumber: String,

  purchaseOrderDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  expectedDeliveryDate: Date,

  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
  },

  deliveryAddress: String,
  shipmentPreference: String,
  salesperson: String,
  subject: String,

  items: [{
    itemDetails: { type: String, required: true },
    quantity: { type: Number, required: true, min: 0 },
    rate: { type: Number, required: true, min: 0 },
    discount: { type: Number, default: 0, min: 0 },
    discountType: {
      type: String,
      enum: ['percentage', 'amount'],
      default: 'percentage'
    },
    amount: { type: Number, required: true }
  }],

  vendorNotes: String,
  termsAndConditions: String,

  // Financial
  subTotal: { type: Number, required: true, default: 0 },
  tdsRate: { type: Number, default: 0, min: 0, max: 100 },
  tdsAmount: { type: Number, default: 0 },
  tcsRate: { type: Number, default: 0, min: 0, max: 100 },
  tcsAmount: { type: Number, default: 0 },
  gstRate: { type: Number, default: 18, min: 0, max: 100 },
  cgst: { type: Number, default: 0 },
  sgst: { type: Number, default: 0 },
  igst: { type: Number, default: 0 },
  totalAmount: { type: Number, required: true, default: 0 },

  // Status
  status: {
    type: String,
    enum: [
      'DRAFT',
      'ISSUED',
      'PARTIALLY_RECEIVED',
      'RECEIVED',
      'PARTIALLY_BILLED',
      'BILLED',
      'CLOSED',
      'CANCELLED'
    ],
    default: 'DRAFT',
    index: true
  },

  receiveStatus: {
    type: String,
    enum: ['NOT_RECEIVED', 'PARTIALLY_RECEIVED', 'RECEIVED'],
    default: 'NOT_RECEIVED'
  },

  billingStatus: {
    type: String,
    enum: ['NOT_BILLED', 'PARTIALLY_BILLED', 'BILLED'],
    default: 'NOT_BILLED'
  },

  // Purchase Receives
  receives: [{
    receiveId: { type: mongoose.Schema.Types.ObjectId, default: () => new mongoose.Types.ObjectId() },
    receiveDate: { type: Date, required: true },
    items: [{
      itemDetails: String,
      quantityOrdered: Number,
      quantityReceived: Number
    }],
    notes: String,
    recordedBy: String,
    recordedAt: { type: Date, default: Date.now }
  }],

  // Linked Bills
  linkedBills: [{
    billId: mongoose.Schema.Types.ObjectId,
    billNumber: String,
    createdAt: { type: Date, default: Date.now }
  }],

  // Email Tracking
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['purchase_order', 'reminder']
    }
  }],

  // PDF
  pdfPath: String,
  pdfGeneratedAt: Date,

  // Audit
  createdBy: { type: String, required: true },
  updatedBy: String,

  // Custom email fields — saved when user edits email preview before sending
  customEmailTo:      { type: String, default: null },
  customEmailSubject: { type: String, default: null },
  customEmailHtml:    { type: String, default: null },

}, { timestamps: true });

// Pre-save: calculate amounts
purchaseOrderSchema.pre('save', function () {
  this.subTotal = this.items.reduce((sum, item) => sum + (item.amount || 0), 0);
  this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
  this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
  const gstBase   = this.subTotal - this.tdsAmount + this.tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;
  this.cgst        = gstAmount / 2;
  this.sgst        = gstAmount / 2;
  this.igst        = 0;
  this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
});

purchaseOrderSchema.index({ vendorId: 1, purchaseOrderDate: -1 });
purchaseOrderSchema.index({ status: 1, expectedDeliveryDate: 1 });
purchaseOrderSchema.index({ createdAt: -1 });

const PurchaseOrder = mongoose.models.PurchaseOrder || mongoose.model('PurchaseOrder', purchaseOrderSchema);

// ============================================================================
// VENDOR SCHEMA
// ============================================================================

const vendorSchema = new mongoose.Schema({
  vendorName: { type: String, required: true, trim: true, index: true },
  vendorEmail: { type: String, required: true, trim: true, lowercase: true, index: true },
  vendorPhone: { type: String, required: true, trim: true },
  companyName: { type: String, trim: true },
  gstNumber: { type: String, trim: true, uppercase: true },
  billingAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  isActive: { type: Boolean, default: true, index: true },
  createdBy: { type: String, required: true },
  updatedBy: String
}, { timestamps: true, collection: 'vendors' });

// Check if model exists before creating to avoid OverwriteModelError
const Vendor = mongoose.models.Vendor || mongoose.model('Vendor', vendorSchema);

// ============================================================================
// HELPERS
// ============================================================================

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

async function generatePONumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(PurchaseOrder, 'purchaseOrderNumber', 'PO', orgId);
}

function calcItemAmount(item) {
  let amount = (item.quantity || 0) * (item.rate || 0);
  if (item.discount > 0) {
    if (item.discountType === 'percentage') {
      amount = amount - (amount * item.discount / 100);
    } else {
      amount = amount - item.discount;
    }
  }
  return Math.round(amount * 100) / 100;
}

function getCreator(req) {
  return req.user?.email || req.user?.uid || 'system';
}

// ============================================================================
// PDF GENERATION
// ============================================================================

async function generatePurchaseOrderPDF(po, orgId) {
  return new Promise(async (resolve, reject) => {
    try {
      console.log('📄 Starting PDF generation for PO:', po.purchaseOrderNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'purchase-orders');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `po-${po.purchaseOrderNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      let orgName = 'Your Company', orgGST = '', orgAddr = '', orgEmail = '', orgPhone = '', orgData = null;
      try {
        const OrgModel = mongoose.models.Organization ||
          mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
        orgData = await OrgModel.findOne({ orgId }).lean();
        if (orgData) {
          orgName  = orgData.orgName    || orgName;
          orgGST   = orgData.gstNumber  || '';
          orgAddr  = orgData.address    || '';
          orgEmail = orgData.email      || '';
          orgPhone = orgData.phone      || '';
        }
      } catch (e) { console.warn('⚠️ Org fetch failed:', e.message); }

      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);
      const pageW = 515;

      // ── Header ──────────────────────────────────────────────────────────────
      doc.rect(40, 30, pageW, 90).fill('#0f1e3d');

      const logoPath = getLogoPath(orgId);
      let logoLoaded = false;
      if (logoPath) {
        try { doc.image(logoPath, 44, 35, { width: 75, height: 60, fit: [75, 60] }); logoLoaded = true; }
        catch (e) { console.warn('⚠️ Logo load failed:', e.message); }
      }
      const textX = logoLoaded ? 126 : 50;
      doc.fontSize(12).fillColor('#ffffff').font('Helvetica-Bold').text(orgName.toUpperCase(), textX, 40, { width: 200 });
      doc.fontSize(7).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text('BILLING & FINANCE', textX, 56, { width: 200, characterSpacing: 1 });
      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)');
      let cY = 68; contactLines.forEach(l => { doc.text(l, textX, cY, { width: 240 }); cY += 9; });

      doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').font('Helvetica-Bold').text('PURCHASE ORDER', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold').text(po.purchaseOrderNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.8)').font('Helvetica')
         .text(`Date: ${new Date(po.purchaseOrderDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`${(po.status || 'DRAFT').replace(/_/g,' ')}${po.expectedDeliveryDate ? ' · Del: ' + new Date(po.expectedDeliveryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' }) : ''}`, 380, 92, { width: 170, align: 'right' });

      // ── Meta boxes ───────────────────────────────────────────────────────────
      const metaY = 132, metaBoxW = pageW / 2;
      const metas = [
        { label: 'Vendor / Ship To',
          val: po.vendorName || 'N/A',
          sub: [po.vendorEmail, po.vendorPhone, po.deliveryAddress].filter(Boolean).join(' | ') },
        { label: 'PO Details',
          val: `Terms: ${po.paymentTerms || 'Net 30'}`,
          sub: `${po.referenceNumber ? 'Ref: ' + po.referenceNumber : ''}${po.expectedDeliveryDate ? ' | Del: ' + new Date(po.expectedDeliveryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' }) : ''}` },
      ];
      metas.forEach((m, i) => {
        const bx = 40 + i * metaBoxW;
        doc.rect(bx, metaY, metaBoxW, 46).fillAndStroke('#f7f9fc', '#dde4ef');
        doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold').text(m.label.toUpperCase(), bx + 8, metaY + 7, { width: metaBoxW - 16, characterSpacing: 0.8 });
        doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold').text(m.val, bx + 8, metaY + 18, { width: metaBoxW - 16, ellipsis: true });
        doc.fontSize(7).fillColor('#000000').font('Helvetica').text(m.sub, bx + 8, metaY + 30, { width: metaBoxW - 16, ellipsis: true });
      });

      // ── Items table ──────────────────────────────────────────────────────────
      const tableY = metaY + 58;
      doc.rect(40, tableY, pageW, 22).fill('#0f1e3d');
      doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
      doc.text('#', 48, tableY + 7, { width: 20 });
      doc.text('DESCRIPTION', 72, tableY + 7, { width: 200 });
      doc.text('QTY', 275, tableY + 7, { width: 60, align: 'center' });
      doc.text('RATE', 340, tableY + 7, { width: 80, align: 'right' });
      doc.text('AMOUNT', 420, tableY + 7, { width: 90, align: 'right' });

      let rowY = tableY + 22;
      po.items.forEach((item, idx) => {
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

      // ── Totals ───────────────────────────────────────────────────────────────
      const totalsX = 355, totalsW = 200, labelX = totalsX, amountX = totalsX + totalsW;
      let totalsY = rowY + 16;
      const tRow = (label, amount, bold = false) => {
        doc.fontSize(8).fillColor('#5e6e84').font(bold ? 'Helvetica-Bold' : 'Helvetica').text(label, labelX, totalsY, { width: 120 });
        doc.fillColor('#000000').font(bold ? 'Helvetica-Bold' : 'Helvetica').text(amount, labelX + 120, totalsY, { width: 80, align: 'right' });
        doc.moveTo(labelX, totalsY + 11).lineTo(amountX, totalsY + 11).lineWidth(0.5).strokeColor('#dde4ef').dash(2, { space: 2 }).stroke().undash();
        totalsY += 14;
      };
      tRow('Subtotal:', `Rs. ${(po.subTotal || 0).toFixed(2)}`);
      if (po.cgst > 0)      tRow(`CGST (${po.gstRate / 2}%):`, `Rs. ${po.cgst.toFixed(2)}`);
      if (po.sgst > 0)      tRow(`SGST (${po.gstRate / 2}%):`, `Rs. ${po.sgst.toFixed(2)}`);
      if (po.igst > 0)      tRow(`IGST (${po.gstRate}%):`,     `Rs. ${po.igst.toFixed(2)}`);
      if (po.tdsAmount > 0) tRow('TDS Deducted:',               `- Rs. ${po.tdsAmount.toFixed(2)}`);
      if (po.tcsAmount > 0) tRow('TCS Collected:',              `Rs. ${po.tcsAmount.toFixed(2)}`);
      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica').text('Grand Total', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold').text(`Rs. ${(po.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5, { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      // Amount in words
      const wordsY = totalsY + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold').text(`In Words: ${numberToWords(Math.round(po.totalAmount || 0))} Only`, 48, wordsY + 5, { width: pageW - 16 });

      // Notes
      if (po.vendorNotes || po.notes) {
        const nY = wordsY + 28;
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold').text('NOTES', 40, nY, { characterSpacing: 0.8 });
        doc.moveTo(40, nY + 9).lineTo(555, nY + 9).lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica').text(po.vendorNotes || po.notes, 40, nY + 14, { width: pageW });
      }

      // T&C
      if (po.termsAndConditions) {
        const tcY = 660;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold').text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica').text(po.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // Footer
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY).lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName} · ${orgGST ? 'GSTIN: ' + orgGST + ' · ' : ''}${po.purchaseOrderNumber}`, 40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`, 40, footY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => {
        console.log(`✅ PO PDF generated: ${filename}`);
        resolve({ filename, filepath, relativePath: `/uploads/purchase-orders/${filename}` });
      });
      stream.on('error', reject);
    } catch (error) {
      console.error('❌ PO PDF generation error:', error);
      reject(error);
    }
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

async function sendPurchaseOrderEmail(po, pdfPath, orgId) {
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
    console.warn('⚠️ Could not fetch org details for PO email:', e.message);
  }

  const itemsHtml = po.items.map(item => `
    <tr>
      <td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;">${item.itemDetails}</td>
      <td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;text-align:center;">${item.quantity}</td>
      <td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;text-align:right;">Rs. ${item.rate.toFixed(2)}</td>
      <td style="padding:7px 0;border-bottom:1px dashed #e8e8e8;text-align:right;">Rs. ${item.amount.toFixed(2)}</td>
    </tr>
  `).join('');

  const emailHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Purchase Order ${po.purchaseOrderNumber}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }
    .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }
    .header { background: #0f1e3d; padding: 24px 32px; }
    .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }
    .header p  { color: rgba(255,255,255,0.7); font-size: 11px; letter-spacing: 0.5px; }
    .header .po-num { color: #fff; font-size: 14px; font-weight: bold; margin-top: 8px; }
    .body { padding: 28px 32px; }
    .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase;
                     letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0;
                     padding-bottom: 6px; margin: 22px 0 12px; }
    table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }
    table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }
    table.detail td:first-child { color: #555; width: 160px; }
    table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }
    table.items { width: 100%; border-collapse: collapse; font-size: 12px; margin: 8px 0; }
    table.items th { background: #0f1e3d; color: #fff; padding: 8px; text-align: left; font-size: 11px; }
    table.items th:last-child, table.items th:nth-child(2), table.items th:nth-child(3) { text-align: right; }
    table.items th:nth-child(2) { text-align: center; }
    .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222;
                    border-bottom: none; padding-top: 10px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;
              font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Purchase Order</h1>
    <p>FROM ${orgName.toUpperCase()}</p>
    <div class="po-num">${po.purchaseOrderNumber}</div>
  </div>
  <div class="body">
    <p style="font-size:14px;color:#222;margin-bottom:18px;">Dear ${po.vendorName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find below our purchase order <strong>${po.purchaseOrderNumber}</strong>.
      Kindly confirm the order and arrange delivery as per the expected delivery date.
    </p>

    <div class="section-title">PO Details</div>
    <table class="detail">
      <tr><td>PO Number</td>      <td>${po.purchaseOrderNumber}</td></tr>
      <tr><td>PO Date</td>        <td>${new Date(po.purchaseOrderDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}</td></tr>
      ${po.expectedDeliveryDate ? `<tr><td>Expected Delivery</td><td>${new Date(po.expectedDeliveryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}</td></tr>` : ''}
      <tr><td>Payment Terms</td>  <td>${po.paymentTerms}</td></tr>
      ${po.referenceNumber ? `<tr><td>Reference #</td><td>${po.referenceNumber}</td></tr>` : ''}
    </table>

    <div class="section-title">Items</div>
    <table class="items">
      <thead>
        <tr>
          <th>Item Details</th>
          <th style="text-align:center;">Qty</th>
          <th style="text-align:right;">Rate</th>
          <th style="text-align:right;">Amount</th>
        </tr>
      </thead>
      <tbody>
        ${itemsHtml}
      </tbody>
    </table>

    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs. ${po.subTotal.toFixed(2)}</td></tr>
      ${po.tdsAmount > 0 ? `<tr><td>TDS (${po.tdsRate}%)</td><td>- Rs. ${po.tdsAmount.toFixed(2)}</td></tr>` : ''}
      ${po.tcsAmount > 0 ? `<tr><td>TCS (${po.tcsRate}%)</td><td>Rs. ${po.tcsAmount.toFixed(2)}</td></tr>` : ''}
      ${po.cgst > 0 ? `<tr><td>CGST (${(po.gstRate/2).toFixed(1)}%)</td><td>Rs. ${po.cgst.toFixed(2)}</td></tr>` : ''}
      ${po.sgst > 0 ? `<tr><td>SGST (${(po.gstRate/2).toFixed(1)}%)</td><td>Rs. ${po.sgst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs. ${po.totalAmount.toFixed(2)}</td></tr>
    </table>

    ${po.deliveryAddress ? `
    <div class="section-title">Delivery Address</div>
    <p style="font-size:12px;color:#444;line-height:1.7;">${po.deliveryAddress}</p>` : ''}

    ${po.vendorNotes ? `
    <div class="section-title">Notes</div>
    <p style="font-size:12px;color:#444;line-height:1.7;">${po.vendorNotes}</p>` : ''}

    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The purchase order PDF is attached to this email for your reference.<br>
      Please confirm receipt and expected delivery schedule.
    </p>
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
    from: `"${orgName} - Purchase" <${process.env.SMTP_USER}>`,
    to: po.vendorEmail,
    subject: `Purchase Order ${po.purchaseOrderNumber} — Rs. ${po.totalAmount.toFixed(2)}`,
    html: emailHtml,
    attachments: [{
      filename: `PO-${po.purchaseOrderNumber}.pdf`,
      path: pdfPath
    }]
  });
}

// ============================================================================
// VENDOR ROUTES
// ============================================================================

// GET /api/vendors - Get all vendors
router.get('/vendors', async (req, res) => {
  try {
    const { search, page = 1, limit = 50 } = req.query;
    const query = { isActive: true };

    if (search) {
      query.$or = [
        { vendorName: { $regex: search, $options: 'i' } },
        { vendorEmail: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } }
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const vendors = await Vendor.find(query).sort({ vendorName: 1 }).skip(skip).limit(parseInt(limit));
    const total = await Vendor.countDocuments(query);

    res.json({
      success: true,
      data: {
        vendors,
        pagination: {
          total,
          page: parseInt(page),
          limit: parseInt(limit),
          pages: Math.ceil(total / parseInt(limit))
        }
      }
    });
  } catch (error) {
    console.error('Error fetching vendors:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/vendors - Create vendor
router.post('/vendors', async (req, res) => {
  try {
    const data = req.body;

    if (!data.vendorName || !data.vendorEmail || !data.vendorPhone) {
      return res.status(400).json({
        success: false,
        error: 'Vendor name, email, and phone are required'
      });
    }

    const existing = await Vendor.findOne({
      vendorEmail: data.vendorEmail.toLowerCase(),
      isActive: true
    });
    if (existing) {
      return res.status(400).json({
        success: false,
        error: 'Vendor with this email already exists'
      });
    }

    data.createdBy = getCreator(req);
    const vendor = new Vendor(data);
    await vendor.save();

    console.log(`✅ Vendor created: ${vendor.vendorName}`);
    res.status(201).json({ success: true, message: 'Vendor created', data: vendor });
  } catch (error) {
    console.error('Error creating vendor:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// PURCHASE ORDER ROUTES
// ============================================================================

// GET /api/purchase-orders/stats
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const [
      total,
      draft,
      issued,
      received,
      billed,
      totalValueResult
    ] = await Promise.all([
      PurchaseOrder.countDocuments(orgFilter),
      PurchaseOrder.countDocuments({ ...orgFilter, status: 'DRAFT' }),
      PurchaseOrder.countDocuments({ ...orgFilter, status: 'ISSUED' }),
      PurchaseOrder.countDocuments({ ...orgFilter, status: { $in: ['RECEIVED', 'PARTIALLY_RECEIVED'] } }),
      PurchaseOrder.countDocuments({ ...orgFilter, status: { $in: ['BILLED', 'CLOSED'] } }),
      PurchaseOrder.aggregate([
        { $match: orgFilter },
        { $group: { _id: null, total: { $sum: '$totalAmount' } } }
      ])
    ]);

    res.json({
      success: true,
      data: {
        totalPurchaseOrders: total,
        draftPurchaseOrders: draft,
        issuedPurchaseOrders: issued,
        receivedPurchaseOrders: received,
        billedPurchaseOrders: billed,
        totalValue: totalValueResult[0]?.total || 0
      }
    });
  } catch (error) {
    console.error('Error fetching PO stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/purchase-orders - List all
router.get('/', async (req, res) => {
  try {
    const { status, fromDate, toDate, page = 1, limit = 20, search } = req.query;

    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (status) query.status = status;
    if (fromDate || toDate) {
      query.purchaseOrderDate = {};
      if (fromDate) query.purchaseOrderDate.$gte = new Date(fromDate);
      if (toDate) query.purchaseOrderDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { purchaseOrderNumber: { $regex: search, $options: 'i' } },
        { vendorName: { $regex: search, $options: 'i' } },
        { referenceNumber: { $regex: search, $options: 'i' } }
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const pos = await PurchaseOrder.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');

    const total = await PurchaseOrder.countDocuments(query);

    res.json({
      success: true,
      data: pos,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching purchase orders:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/purchase-orders/:id - Get single PO
router.get('/:id', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });
    res.json({ success: true, data: po });
  } catch (error) {
    console.error('Error fetching PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders - Create new PO
router.post('/', async (req, res) => {
  try {
    const data = { ...req.body };

    // Handle vendorId
    if (data.vendorId) {
      if (typeof data.vendorId === 'string') {
        if (mongoose.Types.ObjectId.isValid(data.vendorId)) {
          data.vendorId = new mongoose.Types.ObjectId(data.vendorId);
        } else {
          data.vendorId = new mongoose.Types.ObjectId();
        }
      }
    } else {
      data.vendorId = new mongoose.Types.ObjectId();
    }

    // Generate PO number
    if (!data.purchaseOrderNumber) {
      data.purchaseOrderNumber = await generatePONumber(req.user?.orgId || null);
    }

    // Calculate item amounts
    if (data.items) {
      data.items = data.items.map(item => ({
        ...item,
        amount: calcItemAmount(item)
      }));
    }

    data.createdBy = getCreator(req);
    data.orgId = req.user?.orgId || null;
    const po = new PurchaseOrder(data);
    await po.save();
// ✅ COA: Debit Expense + Credit Accounts Payable + TDS + TCS
try {
  const currentOrgId = req.user?.orgId || null;
  const [expenseId, apId, taxId, tdsPayableId, tdsReceivableId] = await Promise.all([
    getSystemAccountId('Cost of Goods Sold', currentOrgId),
    getSystemAccountId('Accounts Payable', currentOrgId),
    getSystemAccountId('Tax Payable', currentOrgId),
    getSystemAccountId('TDS Payable', currentOrgId),
    getSystemAccountId('TDS Receivable', currentOrgId),
  ]);
  const txnDate = new Date(po.purchaseOrderDate);

  if (expenseId) await postTransactionToCOA({
    accountId: expenseId, orgId: currentOrgId, date: txnDate,
    description: `PO ${po.purchaseOrderNumber} - ${po.vendorName}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: po.subTotal, credit: 0
  });

  if (apId) await postTransactionToCOA({
    accountId: apId, orgId: currentOrgId, date: txnDate,
    description: `PO ${po.purchaseOrderNumber} - ${po.vendorName}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: 0, credit: po.totalAmount
  });

  if (taxId && (po.cgst + po.sgst) > 0) await postTransactionToCOA({
    accountId: taxId, orgId: currentOrgId, date: txnDate,
    description: `GST on PO ${po.purchaseOrderNumber}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: po.cgst + po.sgst, credit: 0
  });

  if (tdsPayableId && po.tdsAmount > 0) await postTransactionToCOA({
    accountId: tdsPayableId, orgId: currentOrgId, date: txnDate,
    description: `TDS on PO ${po.purchaseOrderNumber}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: 0, credit: po.tdsAmount
  });

  if (tdsReceivableId && po.tcsAmount > 0) await postTransactionToCOA({
    accountId: tdsReceivableId, orgId: currentOrgId, date: txnDate,
    description: `TCS on PO ${po.purchaseOrderNumber}`,
    referenceType: 'Bill', referenceId: po._id,
    referenceNumber: po.purchaseOrderNumber,
    debit: po.tcsAmount, credit: 0
  });

  console.log(`✅ COA posted for PO: ${po.purchaseOrderNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (PO create):', coaErr.message);
}

    console.log(`✅ Purchase order created: ${po.purchaseOrderNumber}`);
    res.status(201).json({ success: true, message: 'Purchase order created', data: po });
  } catch (error) {
    console.error('Error creating PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/purchase-orders/:id - Update PO
router.put('/:id', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (['BILLED', 'CLOSED', 'CANCELLED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: `Cannot edit a purchase order with status: ${po.status}`
      });
    }

    const updates = { ...req.body };

    if (updates.items) {
      updates.items = updates.items.map(item => ({
        ...item,
        amount: calcItemAmount(item)
      }));
    }

    updates.updatedBy = getCreator(req);
    Object.assign(po, updates);
    await po.save();

    console.log(`✅ Purchase order updated: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order updated', data: po });
  } catch (error) {
    console.error('Error updating PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/issue - Issue PO (DRAFT → ISSUED)
router.post('/:id/issue', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (po.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: `Only DRAFT purchase orders can be issued. Current status: ${po.status}`
      });
    }

    po.status = 'ISSUED';
    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order issued: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order issued', data: po });
  } catch (error) {
    console.error('Error issuing PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/send - Send PO via email
router.post('/:id/send', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!po.vendorEmail) {
      return res.status(400).json({
        success: false,
        error: 'Vendor email is required to send purchase order'
      });
    }

    // Generate PDF if not exists
    if (!po.pdfPath || !fs.existsSync(po.pdfPath)) {
      const pdfInfo = await generatePurchaseOrderPDF(po, req.user?.orgId);
      po.pdfPath = pdfInfo.filepath;
      po.pdfGeneratedAt = new Date();
    }

    // Use custom email content if the user edited it in the preview dialog
    const customTo      = po.customEmailTo;
    const customSubject = po.customEmailSubject;
    const customHtml    = po.customEmailHtml;
    const sendTo        = customTo || po.vendorEmail;

    if (customHtml) {
      const transporter = nodemailer.createTransport({
        host: process.env.SMTP_HOST || 'smtp.gmail.com',
        port: parseInt(process.env.SMTP_PORT || '587'),
        secure: false,
        auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
      });
      await transporter.sendMail({
        from: `"Accounts" <${process.env.SMTP_USER}>`,
        to: sendTo,
        subject: customSubject || `Purchase Order ${po.purchaseOrderNumber}`,
        html: customHtml,
        attachments: [{ filename: `PO-${po.purchaseOrderNumber}.pdf`, path: po.pdfPath }],
      });
    } else {
      // Send email
      await sendPurchaseOrderEmail(po, po.pdfPath, req.user?.orgId);
    }

    // Update status to ISSUED if still DRAFT
    if (po.status === 'DRAFT') {
      po.status = 'ISSUED';
    }

    po.emailsSent.push({
      sentTo: sendTo,
      sentAt: new Date(),
      emailType: 'purchase_order'
    });

    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order sent: ${po.purchaseOrderNumber} to ${po.vendorEmail}`);
    res.json({ success: true, message: 'Purchase order sent successfully', data: po });
  } catch (error) {
    console.error('Error sending PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/receive - Record purchase receive
router.post('/:id/receive', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!['ISSUED', 'PARTIALLY_RECEIVED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: 'Only ISSUED or PARTIALLY_RECEIVED purchase orders can record a receive'
      });
    }

    const { receiveDate, items, notes } = req.body;

    if (!items || items.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'At least one item is required for receive'
      });
    }

    // Add receive record
    po.receives.push({
      receiveDate: receiveDate ? new Date(receiveDate) : new Date(),
      items,
      notes,
      recordedBy: getCreator(req),
      recordedAt: new Date()
    });

    // Calculate total received vs ordered
    const orderedQtyMap = {};
    po.items.forEach(item => {
      orderedQtyMap[item.itemDetails] = item.quantity;
    });

    const receivedQtyMap = {};
    po.receives.forEach(receive => {
      receive.items.forEach(rItem => {
        receivedQtyMap[rItem.itemDetails] =
          (receivedQtyMap[rItem.itemDetails] || 0) + (rItem.quantityReceived || 0);
      });
    });

    // Determine receive status
    let allReceived = true;
    let anyReceived = false;

    po.items.forEach(item => {
      const ordered = orderedQtyMap[item.itemDetails] || 0;
      const received = receivedQtyMap[item.itemDetails] || 0;
      if (received > 0) anyReceived = true;
      if (received < ordered) allReceived = false;
    });

    if (allReceived) {
      po.receiveStatus = 'RECEIVED';
      po.status = 'RECEIVED';
    } else if (anyReceived) {
      po.receiveStatus = 'PARTIALLY_RECEIVED';
      po.status = 'PARTIALLY_RECEIVED';
    }

    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase receive recorded for: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase receive recorded', data: po });
  } catch (error) {
    console.error('Error recording receive:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/convert-to-bill - Convert PO to Bill
router.post('/:id/convert-to-bill', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!['RECEIVED', 'PARTIALLY_RECEIVED', 'PARTIALLY_BILLED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: 'Only RECEIVED or PARTIALLY_RECEIVED purchase orders can be converted to bill'
      });
    }

    // Build bill data from PO
    const Bill = mongoose.model('Bill') || null;

    // If Bill model is not loaded, create a placeholder response
    // (The actual Bill model should be in bills.js)
    const billData = {
      purchaseOrderId: po._id,
      purchaseOrderNumber: po.purchaseOrderNumber,
      vendorId: po.vendorId,
      vendorName: po.vendorName,
      vendorEmail: po.vendorEmail,
      vendorPhone: po.vendorPhone,
      billDate: new Date(),
      dueDate: calculateBillDueDate(new Date(), po.paymentTerms),
      paymentTerms: po.paymentTerms,
      items: po.items,
      vendorNotes: po.vendorNotes,
      termsAndConditions: po.termsAndConditions,
      subTotal: po.subTotal,
      tdsRate: po.tdsRate,
      tdsAmount: po.tdsAmount,
      tcsRate: po.tcsRate,
      tcsAmount: po.tcsAmount,
      gstRate: po.gstRate,
      cgst: po.cgst,
      sgst: po.sgst,
      igst: po.igst,
      totalAmount: po.totalAmount,
      status: 'OPEN',
      createdBy: getCreator(req),
      orgId: req.user?.orgId || null,
    };

    // Try to create bill via Bill model if available
    let savedBill = null;
    try {
      const BillModel = require('./bill').BillModel;
      savedBill = new BillModel(billData);
      await savedBill.save();
    } catch (billModelError) {
      // Bill model may not be available — create a raw document
      const dynamicBillSchema = new mongoose.Schema({}, { strict: false, timestamps: true });
      let DynamicBill;
      try {
        DynamicBill = mongoose.model('Bill');
      } catch (_) {
        DynamicBill = mongoose.model('Bill', dynamicBillSchema, 'bills');
      }
      savedBill = new DynamicBill({ ...billData, billNumber: await generateBillNumber(req.user?.orgId || null) });
      await savedBill.save();
    }

    // Update PO billing status
    po.billingStatus = 'BILLED';
    po.status = 'BILLED';

    if (savedBill) {
      po.linkedBills.push({
        billId: savedBill._id,
        billNumber: savedBill.billNumber || 'BILL-AUTO',
        createdAt: new Date()
      });
    }

    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order converted to bill: ${po.purchaseOrderNumber}`);
    res.json({
      success: true,
      message: 'Purchase order converted to bill successfully',
      data: { purchaseOrder: po, bill: savedBill }
    });
  } catch (error) {
    console.error('Error converting PO to bill:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

async function generateBillNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  const BillModel = require('./bill').BillModel;
  return generateNumber(BillModel, 'billNumber', 'BILL', orgId);
}

function calculateBillDueDate(date, terms) {
  const d = new Date(date);
  switch (terms) {
    case 'Net 15': d.setDate(d.getDate() + 15); break;
    case 'Net 30': d.setDate(d.getDate() + 30); break;
    case 'Net 45': d.setDate(d.getDate() + 45); break;
    case 'Net 60': d.setDate(d.getDate() + 60); break;
    default: break;
  }
  return d;
}

// POST /api/purchase-orders/:id/cancel - Cancel PO
router.post('/:id/cancel', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (['CANCELLED', 'BILLED', 'CLOSED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: `Cannot cancel a purchase order with status: ${po.status}`
      });
    }

    po.status = 'CANCELLED';
    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order cancelled: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order cancelled', data: po });
  } catch (error) {
    console.error('Error cancelling PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/:id/close - Close PO manually
router.post('/:id/close', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (['CANCELLED', 'CLOSED'].includes(po.status)) {
      return res.status(400).json({
        success: false,
        error: `Purchase order is already ${po.status}`
      });
    }

    po.status = 'CLOSED';
    po.updatedBy = getCreator(req);
    await po.save();

    console.log(`✅ Purchase order closed: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order closed', data: po });
  } catch (error) {
    console.error('Error closing PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/purchase-orders/:id/pdf - Download PDF
router.get('/:id/pdf', async (req, res) => {
  // Support token from query param for frontend blob-fetch preview
  if (!req.user && req.query.token) {
    try {
      const jwt = require('jsonwebtoken');
      req.user = jwt.verify(req.query.token, process.env.FINANCE_JWT_SECRET || process.env.JWT_SECRET);
    } catch (e) {
      return res.status(401).json({ success: false, message: 'Invalid token' });
    }
  }
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (!po.pdfPath || !fs.existsSync(po.pdfPath)) {
      const pdfInfo = await generatePurchaseOrderPDF(po, req.user?.orgId);
      po.pdfPath = pdfInfo.filepath;
      po.pdfGeneratedAt = new Date();
      await po.save();
    }

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="PO-${po.purchaseOrderNumber}.pdf"`);
    res.download(po.pdfPath, `PO-${po.purchaseOrderNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/purchase-orders/:id/email-preview
// GET /api/purchase-orders/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();
    const orgName  = org?.orgName    || '';
    const orgGST   = org?.gstNumber  || '';
    const orgPhone = org?.phone      || '';
    const orgEmail = org?.email      || '';
    const dateStr = new Date(po.purchaseOrderDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const deliveryDateStr = po.expectedDeliveryDate
      ? new Date(po.expectedDeliveryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })
      : null;
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Purchase Order ${po.purchaseOrderNumber}</title>
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
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706;
                 padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;
              font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Purchase Order</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${po.purchaseOrderNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${po.vendorName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached purchase order <strong>${po.purchaseOrderNumber}</strong>. Kindly confirm and arrange delivery as per the expected date.
    </p>
    <div class="section-title">PO Details</div>
    <table class="detail">
      <tr><td>PO Number</td>      <td>${po.purchaseOrderNumber}</td></tr>
      <tr><td>PO Date</td>        <td>${dateStr}</td></tr>
      <tr><td>Payment Terms</td>  <td>${po.paymentTerms || 'Net 30'}</td></tr>
      ${deliveryDateStr ? `<tr><td>Expected Delivery</td><td>${deliveryDateStr}</td></tr>` : ''}
      ${po.referenceNumber ? `<tr><td>Reference #</td><td>${po.referenceNumber}</td></tr>` : ''}
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(po.subTotal || 0).toFixed(2)}</td></tr>
      ${po.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${po.cgst.toFixed(2)}</td></tr>` : ''}
      ${po.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${po.sgst.toFixed(2)}</td></tr>` : ''}
      ${po.igst > 0 ? `<tr><td>IGST</td><td>Rs.${po.igst.toFixed(2)}</td></tr>` : ''}
      ${po.tdsAmount > 0 ? `<tr><td>TDS Deducted</td><td>- Rs.${po.tdsAmount.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs.${(po.totalAmount || 0).toFixed(2)}</td></tr>
    </table>
    ${po.vendorNotes || po.notes ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${po.vendorNotes || po.notes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The purchase order PDF is attached to this email for your reference.<br>
      Please confirm receipt and expected delivery schedule.
    </p>
  </div>
  <div class="footer">
    <strong>Thank you for your partnership.</strong><br>
    ${orgName} &nbsp;|&nbsp; ${orgEmail} &nbsp;|&nbsp; This is a system-generated email.
  </div>
</div>
</body>
</html>`;
    res.json({ success: true, data: { subject: `Purchase Order ${po.purchaseOrderNumber} — Rs.${(po.totalAmount || 0).toFixed(2)}`, html, to: po.vendorEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const po = await PurchaseOrder.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });
    if (to !== undefined)      po.customEmailTo      = to;
    if (subject !== undefined) po.customEmailSubject = subject;
    if (html !== undefined)    po.customEmailHtml    = html;
    await po.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/purchase-orders/:id - Delete (only DRAFT)
router.delete('/:id', async (req, res) => {
  try {
    const po = await PurchaseOrder.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!po) return res.status(404).json({ success: false, error: 'Purchase order not found' });

    if (po.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only DRAFT purchase orders can be deleted'
      });
    }

    await po.deleteOne();
    console.log(`✅ Purchase order deleted: ${po.purchaseOrderNumber}`);
    res.json({ success: true, message: 'Purchase order deleted' });
  } catch (error) {
    console.error('Error deleting PO:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/purchase-orders/bulk-import - Bulk Import
router.post('/bulk-import', async (req, res) => {
  try {
    const { purchaseOrders } = req.body;

    if (!purchaseOrders || !Array.isArray(purchaseOrders) || purchaseOrders.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'purchaseOrders array is required'
      });
    }

    const creator = getCreator(req);
    let successCount = 0;
    let failedCount = 0;
    const errors = [];

    for (let i = 0; i < purchaseOrders.length; i++) {
      try {
        const poData = { ...purchaseOrders[i] };

        // Generate PO number if not provided
        if (!poData.purchaseOrderNumber) {
          poData.purchaseOrderNumber = await generatePONumber(req.user?.orgId || null);
        }

        // Handle vendorId
        poData.vendorId = new mongoose.Types.ObjectId();

        // Set creator
        poData.createdBy = creator;
        poData.orgId = req.user?.orgId || null;

        // Build basic items if not provided
        if (!poData.items || poData.items.length === 0) {
          poData.items = [{
            itemDetails: 'Imported Item',
            quantity: 1,
            rate: poData.subTotal || 0,
            discount: 0,
            discountType: 'percentage',
            amount: poData.subTotal || 0
          }];
        }

        const po = new PurchaseOrder(poData);
        await po.save();
        successCount++;
      } catch (e) {
        failedCount++;
        errors.push(`Row ${i + 1}: ${e.message}`);
      }
    }

    console.log(`✅ Bulk import: ${successCount} success, ${failedCount} failed`);

    res.json({
      success: true,
      message: `Imported ${successCount} purchase orders`,
      data: {
        successCount,
        failedCount,
        totalProcessed: purchaseOrders.length,
        errors
      }
    });
  } catch (error) {
    console.error('Error bulk importing:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;