// ============================================================================
// QUOTES BACKEND API - Complete CRUD Operations with Bulk Import
// ============================================================================
// File: backend/routes/quotes.js
// Comprehensive quote management endpoints matching Zoho Books functionality
// Includes Mongoose model definition + BULK IMPORT ENDPOINT
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const { body, param, validationResult } = require('express-validator');
// Note: Authentication is handled at the app level in index.js with verifyJWT
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
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.png'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.png'),
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

// ============================================================================
// MONGOOSE MODEL DEFINITION (INCLUDED IN ROUTE FILE)
// ============================================================================

const quoteItemSchema = new mongoose.Schema({
  itemDetails: {
    type: String,
    required: true,
    trim: true,
  },
  quantity: {
    type: Number,
    required: true,
    min: 0,
  },
  rate: {
    type: Number,
    required: true,
    min: 0,
  },
  discount: {
    type: Number,
    default: 0,
    min: 0,
  },
  discountType: {
    type: String,
    enum: ['percentage', 'amount'],
    default: 'percentage',
  },
  amount: {
    type: Number,
    required: true,
    min: 0,
  },
}, { _id: false });

const quoteSchema = new mongoose.Schema({
  organizationId: {
    type: String,
    required: false,
    index: true,
  },
  orgId: { type: String, index: true, default: null },
  quoteNumber: {
    type: String,
    required: true,
    unique: true,
    trim: true,
  },
  referenceNumber: {
    type: String,
    trim: true,
  },
  customerId: {
    type: String,
    required: true,
    index: true,
  },
  customerName: {
    type: String,
    required: true,
    trim: true,
  },
  customerEmail: {
    type: String,
    trim: true,
    lowercase: true,
  },
  customerPhone: {
    type: String,
    trim: true,
  },
  quoteDate: {
    type: Date,
    required: true,
    default: Date.now,
  },
  expiryDate: {
    type: Date,
    required: true,
  },
  salesperson: {
    type: String,
    trim: true,
  },
  projectName: {
    type: String,
    trim: true,
  },
  subject: {
    type: String,
    trim: true,
  },
  items: {
    type: [quoteItemSchema],
    required: true,
    validate: {
      validator: function(items) {
        return items && items.length > 0;
      },
      message: 'At least one item is required',
    },
  },
  subTotal: {
    type: Number,
    required: true,
    default: 0,
  },
  tdsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100,
  },
  tdsAmount: {
    type: Number,
    default: 0,
    min: 0,
  },
  tcsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100,
  },
  tcsAmount: {
    type: Number,
    default: 0,
    min: 0,
  },
  gstRate: {
    type: Number,
    default: 18,
    min: 0,
    max: 100,
  },
  cgst: {
    type: Number,
    default: 0,
    min: 0,
  },
  sgst: {
    type: Number,
    default: 0,
    min: 0,
  },
  igst: {
    type: Number,
    default: 0,
    min: 0,
  },
  totalAmount: {
    type: Number,
    required: true,
    default: 0,
  },
  customerNotes: {
    type: String,
    trim: true,
  },
  termsAndConditions: {
    type: String,
    trim: true,
  },
  status: {
    type: String,
    enum: ['DRAFT', 'SENT', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'CONVERTED'],
    default: 'DRAFT',
    index: true,
  },
  sentDate: {
    type: Date,
  },
  acceptedDate: {
    type: Date,
  },
  declinedDate: {
    type: Date,
  },
  declineReason: {
    type: String,
    trim: true,
  },
  convertedDate: {
    type: Date,
  },
  convertedToInvoice: {
    type: Boolean,
    default: false,
  },
  convertedToSalesOrder: {
    type: Boolean,
    default: false,
  },
  createdBy: {
    type: String,
    required: true,
  },
  updatedBy: {
    type: String,
  },
  // Custom email fields — saved when user edits email preview before sending
  customEmailTo:      { type: String, default: null },
  customEmailSubject: { type: String, default: null },
  customEmailHtml:    { type: String, default: null },
}, {
  timestamps: true,
});

// Indexes for better query performance
quoteSchema.index({ orgId: 1, quoteNumber: 1 });
quoteSchema.index({ orgId: 1, customerId: 1 });
quoteSchema.index({ orgId: 1, status: 1 });
quoteSchema.index({ orgId: 1, quoteDate: -1 });
quoteSchema.index({ orgId: 1, createdAt: -1 });

// Virtual for checking if quote is expired
quoteSchema.virtual('isExpired').get(function() {
  return this.status === 'SENT' && new Date() > this.expiryDate;
});

// Method to check if quote can be edited
quoteSchema.methods.canEdit = function() {
  return this.status !== 'CONVERTED';
};

// Method to check if quote can be deleted
quoteSchema.methods.canDelete = function() {
  return this.status === 'DRAFT';
};

// Method to check if quote can be sent
quoteSchema.methods.canSend = function() {
  return ['DRAFT', 'SENT'].includes(this.status) && this.customerEmail;
};

// Method to check if quote can be converted
quoteSchema.methods.canConvert = function() {
  return ['ACCEPTED', 'SENT'].includes(this.status);
};

// Pre-save middleware to update expired quotes
quoteSchema.pre('save', function() {
  if (this.status === 'SENT' && new Date() > this.expiryDate) {
    this.status = 'EXPIRED';
  }
});

// Create the Quote model
const Quote = mongoose.models.Quote || mongoose.model('Quote', quoteSchema);

// ============================================================================
// MIDDLEWARE
// ============================================================================

// Note: Authentication is handled at the app level in index.js with verifyJWT
// No need for route-level authentication middleware

// Validation middleware
const validateRequest = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({ 
      success: false, 
      message: 'Validation failed', 
      errors: errors.array() 
    });
  }
  next();
};

// ============================================================================
// VALIDATION RULES
// ============================================================================

const quoteValidationRules = [
  body('customerId').notEmpty().withMessage('Customer ID is required'),
  body('customerName').notEmpty().withMessage('Customer name is required'),
  body('quoteDate').isISO8601().withMessage('Valid quote date is required'),
  body('expiryDate').isISO8601().withMessage('Valid expiry date is required'),
  body('items').isArray({ min: 1 }).withMessage('At least one item is required'),
  body('items.*.itemDetails').notEmpty().withMessage('Item details are required'),
  body('items.*.quantity').isFloat({ min: 0.01 }).withMessage('Quantity must be greater than 0'),
  body('items.*.rate').isFloat({ min: 0 }).withMessage('Rate must be non-negative'),
  body('status').isIn(['DRAFT', 'SENT', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'CONVERTED'])
    .withMessage('Invalid status'),
];

// ============================================================================
// HELPER FUNCTIONS
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

// Generate unique quote number
const generateQuoteNumber = async (organizationId) => {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(Quote, 'quoteNumber', 'QT', organizationId || null);
};

// Calculate quote totals
const calculateQuoteTotals = (items, tdsRate = 0, tcsRate = 0, gstRate = 18) => {
  let subTotal = 0;
  
  // Calculate subtotal from items
  items.forEach(item => {
    let itemAmount = item.quantity * item.rate;
    
    if (item.discount > 0) {
      if (item.discountType === 'percentage') {
        itemAmount = itemAmount - (itemAmount * item.discount / 100);
      } else {
        itemAmount = itemAmount - item.discount;
      }
    }
    
    item.amount = parseFloat(itemAmount.toFixed(2));
    subTotal += item.amount;
  });
  
  subTotal = parseFloat(subTotal.toFixed(2));
  
  // Calculate TDS
  const tdsAmount = parseFloat((subTotal * tdsRate / 100).toFixed(2));
  
  // Calculate TCS
  const tcsAmount = parseFloat((subTotal * tcsRate / 100).toFixed(2));
  
  // Calculate GST base
  const gstBase = subTotal - tdsAmount + tcsAmount;
  
  // Calculate GST (split into CGST and SGST)
  const totalGst = parseFloat((gstBase * gstRate / 100).toFixed(2));
  const cgst = parseFloat((totalGst / 2).toFixed(2));
  const sgst = parseFloat((totalGst / 2).toFixed(2));
  
  // Calculate total amount
  const totalAmount = parseFloat((subTotal - tdsAmount + tcsAmount + totalGst).toFixed(2));
  
  return {
    subTotal,
    tdsAmount,
    tcsAmount,
    cgst,
    sgst,
    igst: 0, // IGST is 0 when CGST/SGST are used
    totalAmount,
    tdsRate,
    tcsRate,
    gstRate
  };
};

// Generate PDF for quote — styled identical to invoices.js
const generateQuotePDF = async (quote, orgId = null) => {
  return new Promise(async (resolve, reject) => {
    try {
      console.log('📄 Starting PDF generation for quote:', quote.quoteNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'quotes');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `quote-${quote.quoteNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      // ── Fetch org details ──────────────────────────────────────────────────
      let orgName  = 'Your Company';
      let orgGST   = '';
      let orgAddr  = '';
      let orgEmail = '';
      let orgPhone = '';
      let orgTagline = '';
      let orgData  = null;
      try {
        const OrgModel = mongoose.models.Organization ||
          mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
        orgData = await OrgModel.findOne({ orgId }).lean();
        if (orgData) {
          orgName    = orgData.orgName    || orgName;
          orgGST     = orgData.gstNumber  || '';
          orgAddr    = orgData.address    || '';
          orgEmail   = orgData.email      || '';
          orgPhone   = orgData.phone      || '';
          orgTagline = orgData.tagline    || orgData.slogan || '';
        }
      } catch (e) { console.warn('⚠️ Could not fetch org details:', e.message); }

      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      const pageW = 515;

      // ═══════════════════════════════════════════════════════════════════════
      // HEADER — dark navy bar
      // ═══════════════════════════════════════════════════════════════════════
      doc.rect(40, 30, pageW, 90).fill('#0f1e3d');

      const logoPath = getLogoPath(orgId);
      let logoLoaded = false;
      if (logoPath) {
        try {
          doc.image(logoPath, 44, 35, { width: 75, height: 60, fit: [75, 60] });
          logoLoaded = true;
        } catch (e) { console.warn('⚠️ Logo load failed:', e.message); }
      }

      const textX = logoLoaded ? 126 : 50;
      doc.fontSize(12).fillColor('#ffffff').font('Helvetica-Bold')
         .text(orgName.toUpperCase(), textX, 40, { width: 200 });
      doc.fontSize(7).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('BILLING & FINANCE', textX, 56, { width: 200, characterSpacing: 1 });

      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)');
      let contactY = 68;
      contactLines.forEach(line => {
        doc.text(line, textX, contactY, { width: 240 });
        contactY += 9;
      });

      doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').font('Helvetica-Bold')
         .text('QUOTATION', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold')
         .text(quote.quoteNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.8)').font('Helvetica')
         .text(`Date: ${new Date(quote.quoteDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`,
               380, 76, { width: 170, align: 'right' });
      const status = quote.status || 'DRAFT';
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Valid Until: ${new Date(quote.expiryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })} · ${status}`,
               380, 92, { width: 170, align: 'right' });

      // ═══════════════════════════════════════════════════════════════════════
      // META GRID — 2 boxes
      // ═══════════════════════════════════════════════════════════════════════
      const metaY    = 132;
      const metaBoxW = pageW / 2;
      const metas    = [
        { label: 'Quote To',
          val: quote.customerName || 'N/A',
          sub: [quote.billingAddress?.street, quote.billingAddress?.city, quote.customerEmail, quote.customerPhone].filter(Boolean).join(' | ') },
        { label: 'Quote Details',
          val: `Valid Until: ${new Date(quote.expiryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}`,
          sub: `Ref: ${quote.referenceNumber || 'N/A'} | Subject: ${quote.subject || 'N/A'}` },
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
      doc.rect(40, tableY, pageW, 22).fill('#0f1e3d');
      doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
      doc.text('#',           48,  tableY + 7, { width: 20 });
      doc.text('DESCRIPTION', 72,  tableY + 7, { width: 200 });
      doc.text('QTY',         275, tableY + 7, { width: 60,  align: 'center' });
      doc.text('RATE',        340, tableY + 7, { width: 80,  align: 'right' });
      doc.text('AMOUNT',      420, tableY + 7, { width: 90,  align: 'right' });

      let rowY = tableY + 22;
      quote.items.forEach((item, idx) => {
        const rowH = 24;
        const fill = idx % 2 === 0 ? '#ffffff' : '#f7f9fc';
        doc.rect(40, rowY, pageW, rowH).fill(fill);
        doc.rect(40, rowY, pageW, rowH).lineWidth(1.5).strokeColor('#000000').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica-Bold')
           .text(String(idx + 1), 48, rowY + 8, { width: 20 });
        doc.font('Helvetica')
           .text(item.itemDetails || 'N/A', 72, rowY + 8, { width: 200, ellipsis: true });
        doc.text(String(item.quantity || 0), 275, rowY + 8, { width: 60, align: 'center' });
        doc.text(`Rs.${(item.rate || 0).toFixed(2)}`, 340, rowY + 8, { width: 80, align: 'right' });
        doc.font('Helvetica-Bold')
           .text(`Rs.${(item.amount || 0).toFixed(2)}`, 420, rowY + 8, { width: 90, align: 'right' });
        rowY += rowH;
      });

      // ═══════════════════════════════════════════════════════════════════════
      // TOTALS
      // ═══════════════════════════════════════════════════════════════════════
      const totalsX = 355;
      const totalsW = 200;
      const labelX  = totalsX;
      const amountX = totalsX + totalsW;
      let totalsY   = rowY + 16;

      const tRow = (label, amount, bold = false) => {
        doc.fontSize(8).fillColor('#5e6e84').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(label, labelX, totalsY, { width: 120 });
        doc.fillColor('#000000').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(amount, labelX + 120, totalsY, { width: 80, align: 'right' });
        doc.moveTo(labelX, totalsY + 11).lineTo(amountX, totalsY + 11)
           .lineWidth(0.5).strokeColor('#dde4ef').dash(2, { space: 2 }).stroke().undash();
        totalsY += 14;
      };

      tRow('Subtotal:', `Rs. ${(quote.subTotal || 0).toFixed(2)}`);
      if (quote.cgst > 0)      tRow(`CGST (${quote.gstRate / 2}%):`, `Rs. ${quote.cgst.toFixed(2)}`);
      if (quote.sgst > 0)      tRow(`SGST (${quote.gstRate / 2}%):`, `Rs. ${quote.sgst.toFixed(2)}`);
      if (quote.igst > 0)      tRow(`IGST (${quote.gstRate}%):`,     `Rs. ${quote.igst.toFixed(2)}`);
      if (quote.tdsAmount > 0) tRow('TDS Deducted:',                  `- Rs. ${quote.tdsAmount.toFixed(2)}`);
      if (quote.tcsAmount > 0) tRow('TCS Collected:',                 `Rs. ${quote.tcsAmount.toFixed(2)}`);

      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('Grand Total', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Rs. ${(quote.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5,
               { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      // Amount in words
      const wordsY = totalsY + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold')
         .text(`In Words: ${numberToWords(Math.round(quote.totalAmount || 0))} Only`,
               48, wordsY + 5, { width: pageW - 16 });

      // ═══════════════════════════════════════════════════════════════════════
      // TAGLINE / ORG CLOSING (from org profile)
      // ═══════════════════════════════════════════════════════════════════════
      if (orgTagline) {
        const tagY = wordsY + 28;
        doc.rect(40, tagY, pageW, 18).fill('#f7f9fc');
        doc.fontSize(8).fillColor('#0f1e3d').font('Helvetica-Bold')
           .text(orgTagline, 48, tagY + 5, { width: pageW - 16, align: 'center' });
      }

      // ═══════════════════════════════════════════════════════════════════════
      // NOTES
      // ═══════════════════════════════════════════════════════════════════════
      if (quote.customerNotes) {
        const nY = wordsY + (orgTagline ? 56 : 28);
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTES', 40, nY, { characterSpacing: 0.8 });
        doc.moveTo(40, nY + 9).lineTo(555, nY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica')
           .text(quote.customerNotes, 40, nY + 14, { width: pageW });
      }

      // ═══════════════════════════════════════════════════════════════════════
      // TERMS & CONDITIONS
      // ═══════════════════════════════════════════════════════════════════════
      if (quote.termsAndConditions) {
        const tcY = 660;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold')
           .text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(quote.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // ═══════════════════════════════════════════════════════════════════════
      // FOOTER
      // ═══════════════════════════════════════════════════════════════════════
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY)
         .lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName} · ${orgGST ? 'GSTIN: ' + orgGST + ' · ' : ''}${quote.quoteNumber}`,
               40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`,
               40, footY + 6, { width: pageW, align: 'right' });

      doc.end();

      stream.on('finish', () => {
        console.log(`✅ Quote PDF generated: ${filename}`);
        resolve({ filename, filepath, relativePath: `/uploads/quotes/${filename}` });
      });
      stream.on('error', reject);

    } catch (error) {
      console.error('❌ Quote PDF generation error:', error);
      reject(error);
    }
  });
};
// Configure email transporter (use your SMTP settings)
const getEmailTransporter = () => {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: process.env.SMTP_PORT || 587,
    secure: false,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASSWORD,
    },
  });
};

// Send quote email — styled identical to invoices.js
const sendQuoteEmail = async (quote, pdfBufferOrPath, orgId = null) => {
  try {
    if (!process.env.SMTP_USER || !process.env.SMTP_PASSWORD) {
      console.log('⚠️  SMTP not configured - skipping email send');
      return;
    }

    let orgName    = 'Billing Team';
    let orgGST     = '';
    let orgEmail   = '';
    let orgPhone   = '';
    let orgTagline = '';
    let orgData    = null;
    try {
      const OrgModel = mongoose.models.Organization ||
        mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
      orgData = await OrgModel.findOne({ orgId }).lean();
      if (orgData) {
        orgName    = orgData.orgName    || orgName;
        orgGST     = orgData.gstNumber  || '';
        orgEmail   = orgData.email      || '';
        orgPhone   = orgData.phone      || '';
        orgTagline = orgData.tagline    || orgData.slogan || '';
      }
    } catch (_) {}

    const transporter = getEmailTransporter();
    const quoteDateStr  = new Date(quote.quoteDate).toLocaleDateString('en-IN',  { day:'2-digit', month:'long', year:'numeric' });
    const expiryDateStr = new Date(quote.expiryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });

    const htmlBody = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Quotation ${quote.quoteNumber}</title>
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
    .tagline-box { background: #f7f9fc; border-left: 3px solid #0f1e3d;
                   padding: 12px 16px; margin: 8px 0; font-size: 13px;
                   font-weight: bold; color: #0f1e3d; text-align: center; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706;
                 padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;
              font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">

  <div class="header">
    <h1>Quotation</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${quote.quoteNumber}</div>
  </div>

  <div class="body">

    <p class="greeting">Dear ${quote.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached quotation <strong>${quote.quoteNumber}</strong> for your consideration. Kindly review and confirm your acceptance before the expiry date.
    </p>

    <div class="section-title">Quote Details</div>
    <table class="detail">
      <tr><td>Quote Number</td><td>${quote.quoteNumber}</td></tr>
      <tr><td>Quote Date</td>  <td>${quoteDateStr}</td></tr>
      <tr><td>Valid Until</td> <td>${expiryDateStr}</td></tr>
      ${quote.referenceNumber ? `<tr><td>Reference #</td><td>${quote.referenceNumber}</td></tr>` : ''}
      ${quote.subject         ? `<tr><td>Subject</td><td>${quote.subject}</td></tr>` : ''}
    </table>

    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(quote.subTotal || 0).toFixed(2)}</td></tr>
      ${quote.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${quote.cgst.toFixed(2)}</td></tr>` : ''}
      ${quote.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${quote.sgst.toFixed(2)}</td></tr>` : ''}
      ${quote.igst > 0 ? `<tr><td>IGST</td><td>Rs.${quote.igst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs.${(quote.totalAmount || 0).toFixed(2)}</td></tr>
    </table>

    ${orgTagline ? `
    <div class="section-title">From Our Team</div>
    <div class="tagline-box">${orgTagline}</div>` : ''}

    ${quote.customerNotes ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${quote.customerNotes}</div>` : ''}

    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The quotation PDF is attached to this email for your records.<br>
      Please reply to this email or contact us to confirm your acceptance.
    </p>

  </div>

  <div class="footer">
    <strong>Thank you for considering us.</strong><br>
    ${orgData?.orgName || ''} &nbsp;|&nbsp; ${orgData?.email || process.env.SMTP_USER || ''} &nbsp;|&nbsp; This is a system-generated email.
  </div>

</div>
</body>
</html>`;

    // Support both buffer (old) and filepath (new)
    const attachment = typeof pdfBufferOrPath === 'string'
      ? { filename: `${quote.quoteNumber}.pdf`, path: pdfBufferOrPath }
      : { filename: `${quote.quoteNumber}.pdf`, content: pdfBufferOrPath };

    const mailOptions = {
      from: `"Accounts" <${process.env.SMTP_USER}>`,
      to: quote.customerEmail,
      subject: `Quotation ${quote.quoteNumber} — Rs.${(quote.totalAmount || 0).toFixed(2)}`,
      html: htmlBody,
      attachments: [attachment],
    };

    await transporter.sendMail(mailOptions);
    console.log(`✅ Quote email sent to ${quote.customerEmail}`);
  } catch (error) {
    console.error('⚠️  Error sending quote email:', error.message);
  }
};

// Send acceptance email
const sendAcceptanceEmail = async (quote, orgId = null) => {
  try {
    if (!process.env.SMTP_USER || !process.env.SMTP_PASSWORD) return;
    if (!quote.customerEmail) return;

    let orgName  = 'Billing Team';
    let orgGST   = '';
    let orgEmail = '';
    let orgPhone = '';
    try {
      const OrgModel = mongoose.models.Organization ||
        mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
      const orgData = await OrgModel.findOne({ orgId }).lean();
      if (orgData) {
        orgName  = orgData.orgName   || orgName;
        orgGST   = orgData.gstNumber || '';
        orgEmail = orgData.email     || '';
        orgPhone = orgData.phone     || '';
      }
    } catch (_) {}

    const transporter = getEmailTransporter();
    await transporter.sendMail({
      from: `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
      to: quote.customerEmail,
      subject: `Quotation ${quote.quoteNumber} - Accepted ✅`,
      html: `<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;">
        <div style="background:#0f1e3d;color:white;padding:20px;text-align:center;border-radius:8px 8px 0 0;">
          <h2 style="margin:0;">✅ Quote Accepted</h2>
          <p style="margin:4px 0 0 0;opacity:0.8;font-size:13px;">${orgName}</p>
        </div>
        <div style="padding:30px;background:#f8f9fa;border-radius:0 0 8px 8px;">
          <p>Dear ${quote.customerName},</p>
          <p style="margin-top:10px;">Thank you for accepting our quote <strong>${quote.quoteNumber}</strong>!</p>
          <div style="background:white;padding:20px;margin:20px 0;border-radius:8px;border-left:4px solid #27AE60;">
            <p>Quote Number: <strong>${quote.quoteNumber}</strong></p>
            <p>Total Amount: <strong>Rs.${quote.totalAmount.toFixed(2)}</strong></p>
            <p>Accepted Date: ${new Date().toLocaleDateString('en-IN')}</p>
          </div>
          <p>We will proceed with the next steps and keep you updated.</p>
          <p style="margin-top:20px;">Best regards,<br><strong>${orgName}</strong></p>
        </div>
        <div style="text-align:center;color:#999;font-size:11px;padding:12px;">
          ${orgGST ? `GST: ${orgGST} | ` : ''}${orgEmail || ''}${orgPhone ? ` | ${orgPhone}` : ''}
        </div>
      </div>`,
    });
    console.log(`✅ Acceptance email sent to ${quote.customerEmail}`);
  } catch (error) {
    console.error('⚠️  Error sending acceptance email:', error.message);
  }
};

// Send decline email
const sendDeclineEmail = async (quote, reason, orgId = null) => {
  try {
    if (!process.env.SMTP_USER || !process.env.SMTP_PASSWORD) return;
    if (!quote.customerEmail) return;

    let orgName  = 'Billing Team';
    let orgGST   = '';
    let orgEmail = '';
    let orgPhone = '';
    try {
      const OrgModel = mongoose.models.Organization ||
        mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
      const orgData = await OrgModel.findOne({ orgId }).lean();
      if (orgData) {
        orgName  = orgData.orgName   || orgName;
        orgGST   = orgData.gstNumber || '';
        orgEmail = orgData.email     || '';
        orgPhone = orgData.phone     || '';
      }
    } catch (_) {}

    const transporter = getEmailTransporter();
    await transporter.sendMail({
      from: `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
      to: quote.customerEmail,
      subject: `Quotation ${quote.quoteNumber} - Status Update`,
      html: `<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;">
        <div style="background:#E74C3C;color:white;padding:20px;text-align:center;border-radius:8px 8px 0 0;">
          <h2 style="margin:0;">Quote Declined</h2>
          <p style="margin:4px 0 0 0;opacity:0.8;font-size:13px;">${orgName}</p>
        </div>
        <div style="padding:30px;background:#f8f9fa;border-radius:0 0 8px 8px;">
          <p>Dear ${quote.customerName},</p>
          <p style="margin-top:10px;">We have received your decision regarding quote <strong>${quote.quoteNumber}</strong>.</p>
          <div style="background:white;padding:20px;margin:20px 0;border-radius:8px;border-left:4px solid #E74C3C;">
            <p>Quote Number: <strong>${quote.quoteNumber}</strong></p>
            <p>Total Amount: <strong>Rs.${quote.totalAmount.toFixed(2)}</strong></p>
            <p>Declined Date: ${new Date().toLocaleDateString('en-IN')}</p>
            ${reason ? `<p>Reason: ${reason}</p>` : ''}
          </div>
          <p>We appreciate you considering our quote. Please feel free to reach out for alternatives.</p>
          <p style="margin-top:20px;">Best regards,<br><strong>${orgName}</strong></p>
        </div>
        <div style="text-align:center;color:#999;font-size:11px;padding:12px;">
          ${orgGST ? `GST: ${orgGST} | ` : ''}${orgEmail || ''}${orgPhone ? ` | ${orgPhone}` : ''}
        </div>
      </div>`,
    });
    console.log(`✅ Decline email sent to ${quote.customerEmail}`);
  } catch (error) {
    console.error('⚠️  Error sending decline email:', error.message);
  }
};

// ============================================================================
// ROUTES
// ============================================================================

// GET /api/quotes - Get all quotes with filtering and pagination
router.get('/', async (req, res) => {
  try {
    const { 
      status, 
      page = 1, 
      limit = 20,
      search,
      fromDate,
      toDate
    } = req.query;
    
    // ✅ FIX: Use orgId from JWT token
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    if (status && status !== 'All') {
      query.status = status;
    }
    
    if (search) {
      query.$or = [
        { quoteNumber: { $regex: search, $options: 'i' } },
        { customerName: { $regex: search, $options: 'i' } },
        { referenceNumber: { $regex: search, $options: 'i' } },
      ];
    }
    
    if (fromDate || toDate) {
      query.quoteDate = {};
      if (fromDate) {
        query.quoteDate.$gte = new Date(fromDate);
      }
      if (toDate) {
        query.quoteDate.$lte = new Date(toDate);
      }
    }
    
    // Execute query with pagination
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const [quotes, total] = await Promise.all([
      Quote.find(query)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .select('-__v'),
      Quote.countDocuments(query),
    ]);
    
    res.json({
      success: true,
      data: {
        quotes,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total,
          pages: Math.ceil(total / parseInt(limit)),
        },
      },
    });
  } catch (error) {
    console.error('Error fetching quotes:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch quotes', 
      error: error.message 
    });
  }
});

// GET /api/quotes/stats - Get quote statistics
router.get('/stats', async (req, res) => {
  try {
    // ✅ FIX: Use orgId from JWT token
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    
    const [
      totalQuotes,
      draftQuotes,
      sentQuotes,
      acceptedQuotes,
      declinedQuotes,
      expiredQuotes,
      convertedQuotes,
      totalValue,
    ] = await Promise.all([
      Quote.countDocuments({ ...orgFilter }),
      Quote.countDocuments({ ...orgFilter, status: 'DRAFT' }),
      Quote.countDocuments({ ...orgFilter, status: 'SENT' }),
      Quote.countDocuments({ ...orgFilter, status: 'ACCEPTED' }),
      Quote.countDocuments({ ...orgFilter, status: 'DECLINED' }),
      Quote.countDocuments({ ...orgFilter, status: 'EXPIRED' }),
      Quote.countDocuments({ ...orgFilter, status: 'CONVERTED' }),
      Quote.aggregate([
        { $match: { ...orgFilter } },
        { $group: { _id: null, total: { $sum: '$totalAmount' } } },
      ]),
    ]);
    
    res.json({
      success: true,
      data: {
        totalQuotes,
        draftQuotes,
        sentQuotes,
        acceptedQuotes,
        declinedQuotes,
        expiredQuotes,
        convertedQuotes,
        totalValue: totalValue[0]?.total || 0,
      },
    });
  } catch (error) {
    console.error('Error fetching quote stats:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch quote statistics', 
      error: error.message 
    });
  }
});

// GET /api/quotes/:id - Get single quote by ID
router.get('/:id', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    const quote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    res.json({
      success: true,
      data: quote,
    });
  } catch (error) {
    console.error('Error fetching quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch quote', 
      error: error.message 
    });
  }
});

router.post('/', quoteValidationRules, validateRequest, async (req, res) => {
  try {
    // ✅ Use orgId from JWT token
    const orgId = req.user?.orgId || null;
    
    console.log('✅ Creating quote with orgId:', orgId);
    
    const quoteNumber = await generateQuoteNumber(orgId);
    const totals = calculateQuoteTotals(
      req.body.items,
      req.body.tdsRate || 0,
      req.body.tcsRate || 0,
      req.body.gstRate || 18
    );
    
    // ✅ Create quote with orgId from token
    const quote = new Quote({
      ...req.body,
      quoteNumber,
      orgId,  // ✅ Auto-populated from JWT token
      createdBy: req.user.userId,
      ...totals,
    });
    
    await quote.save();
    
    console.log('✅ Quote created successfully:', quote.quoteNumber);
    
    res.status(201).json({
      success: true,
      message: 'Quote created successfully',
      data: quote,
    });
  } catch (error) {
    console.error('❌ Error creating quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to create quote', 
      error: error.message 
    });
  }
});

// ============================================================================
// 🆕 NEW ENDPOINT: BULK IMPORT QUOTES
// ============================================================================

router.post('/bulk-import', [
  body('quotes').isArray({ min: 1 }).withMessage('Quotes array is required with at least one quote'),
  validateRequest,
], async (req, res) => {
  try {
    const orgId = req.user?.orgId || null;
    const userId = req.user.userId;
    const quotesData = req.body.quotes;
    
    console.log(`\n📦 Starting bulk import for ${quotesData.length} quotes...`);
    console.log(`   Org ID: ${orgId}`);
    console.log(`   User ID: ${userId}`);
    
    const results = {
      successCount: 0,
      failedCount: 0,
      totalProcessed: quotesData.length,
      errors: [],
    };
    
    // Process each quote
    for (let i = 0; i < quotesData.length; i++) {
      const quoteData = quotesData[i];
      
      try {
        console.log(`\n🔄 Processing quote ${i + 1}/${quotesData.length}...`);
        
        // Validate required fields
        if (!quoteData.customerName) {
          throw new Error('Customer name is required');
        }
        if (!quoteData.customerEmail) {
          throw new Error('Customer email is required');
        }
        if (!quoteData.customerPhone) {
          throw new Error('Customer phone is required');
        }
        if (!quoteData.quoteDate) {
          throw new Error('Quote date is required');
        }
        if (!quoteData.expiryDate) {
          throw new Error('Expiry date is required');
        }
        if (!quoteData.subject) {
          throw new Error('Subject is required');
        }
        if (!quoteData.subTotal || quoteData.subTotal <= 0) {
          throw new Error('Sub total must be greater than 0');
        }
        if (!quoteData.totalAmount || quoteData.totalAmount <= 0) {
          throw new Error('Total amount must be greater than 0');
        }
        
        // Validate status
        const validStatuses = ['DRAFT', 'SENT', 'ACCEPTED', 'DECLINED', 'EXPIRED', 'CONVERTED'];
        if (!validStatuses.includes(quoteData.status)) {
          throw new Error(`Invalid status. Must be one of: ${validStatuses.join(', ')}`);
        }
        
        // Generate quote number
        let quoteNumber = quoteData.quoteNumber;
        if (!quoteNumber) {
          quoteNumber = await generateQuoteNumber(orgId);
        } else {
          // Check if quote number already exists
          const existingQuote = await Quote.findOne({ orgId, quoteNumber });
          if (existingQuote) {
            quoteNumber = await generateQuoteNumber(orgId);
            console.log(`   ⚠️  Quote number ${quoteData.quoteNumber} already exists, generated new: ${quoteNumber}`);
          }
        }
        
        // Create dummy item if no items provided
        let items = [];
        if (!quoteData.items || quoteData.items.length === 0) {
          items = [{
            itemDetails: quoteData.subject || 'Service',
            quantity: 1,
            rate: quoteData.subTotal || 0,
            discount: 0,
            discountType: 'percentage',
            amount: quoteData.subTotal || 0,
          }];
        } else {
          items = quoteData.items;
        }
        
        // Use customerId or generate from customerName
        const customerId = quoteData.customerId || `CUST-${Date.now()}-${i}`;
        
        // Create quote
        const quote = new Quote({
          orgId,
          quoteNumber,
          referenceNumber: quoteData.referenceNumber || '',
          customerId,
          customerName: quoteData.customerName,
          customerEmail: quoteData.customerEmail,
          customerPhone: quoteData.customerPhone,
          quoteDate: new Date(quoteData.quoteDate),
          expiryDate: new Date(quoteData.expiryDate),
          salesperson: quoteData.salesperson || '',
          projectName: quoteData.projectName || '',
          subject: quoteData.subject,
          items,
          subTotal: quoteData.subTotal,
          tdsRate: quoteData.tdsRate || 0,
          tdsAmount: quoteData.tdsAmount || 0,
          tcsRate: quoteData.tcsRate || 0,
          tcsAmount: quoteData.tcsAmount || 0,
          gstRate: quoteData.gstRate || 18,
          cgst: quoteData.cgst || 0,
          sgst: quoteData.sgst || 0,
          igst: quoteData.igst || 0,
          totalAmount: quoteData.totalAmount,
          customerNotes: quoteData.customerNotes || '',
          termsAndConditions: quoteData.termsConditions || '',
          status: quoteData.status,
          createdBy: userId,
        });
        
        await quote.save();
        
        results.successCount++;
        console.log(`   ✅ Successfully imported quote: ${quoteNumber}`);
        
      } catch (error) {
        results.failedCount++;
        const errorMsg = `Quote ${i + 1} (${quoteData.quoteNumber || 'N/A'}): ${error.message}`;
        results.errors.push(errorMsg);
        console.log(`   ❌ Failed to import: ${errorMsg}`);
      }
    }
    
    console.log(`\n📊 Bulk import completed:`);
    console.log(`   ✅ Success: ${results.successCount}`);
    console.log(`   ❌ Failed: ${results.failedCount}`);
    console.log(`   📦 Total: ${results.totalProcessed}`);
    
    res.status(200).json({
      success: true,
      message: `Bulk import completed. ${results.successCount} quotes imported successfully, ${results.failedCount} failed.`,
      data: results,
    });
    
  } catch (error) {
    console.error('❌ Error in bulk import:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process bulk import',
      error: error.message,
    });
  }
});

// PUT /api/quotes/:id - Update quote
router.put('/:id', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  ...quoteValidationRules,
  validateRequest,
], async (req, res) => {
  try {
    const quote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    // Prevent editing of converted quotes
    if (quote.status === 'CONVERTED') {
      return res.status(400).json({ 
        success: false, 
        message: 'Cannot edit converted quotes' 
      });
    }
    
    // Calculate new totals
    const totals = calculateQuoteTotals(
      req.body.items,
      req.body.tdsRate || 0,
      req.body.tcsRate || 0,
      req.body.gstRate || 18
    );
    
    // Update quote
    Object.assign(quote, req.body, totals);
    quote.updatedBy = req.user.userId;
    
    await quote.save();
    
    res.json({
      success: true,
      message: 'Quote updated successfully',
      data: quote,
    });
  } catch (error) {
    console.error('Error updating quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to update quote', 
      error: error.message 
    });
  }
});

// GET /api/quotes/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const quote = await Quote.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    if (!quote) return res.status(404).json({ success: false, error: 'Quote not found' });

    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();

    const orgName    = org?.orgName    || '';
    const orgGST     = org?.gstNumber  || '';
    const orgPhone   = org?.phone      || '';
    const orgEmail   = org?.email      || '';
    const orgTagline = org?.tagline    || org?.slogan || '';

    const quoteDateStr  = new Date(quote.quoteDate).toLocaleDateString('en-IN',  { day:'2-digit', month:'long', year:'numeric' });
    const expiryDateStr = new Date(quote.expiryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Quotation ${quote.quoteNumber}</title>
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
    .tagline-box { background: #f7f9fc; border-left: 3px solid #0f1e3d;
                   padding: 12px 16px; margin: 8px 0; font-size: 13px;
                   font-weight: bold; color: #0f1e3d; text-align: center; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706;
                 padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;
              font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Quotation</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${quote.quoteNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${quote.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached quotation <strong>${quote.quoteNumber}</strong> for your consideration. Kindly review and confirm your acceptance before the expiry date.
    </p>
    <div class="section-title">Quote Details</div>
    <table class="detail">
      <tr><td>Quote Number</td><td>${quote.quoteNumber}</td></tr>
      <tr><td>Quote Date</td>  <td>${quoteDateStr}</td></tr>
      <tr><td>Valid Until</td> <td>${expiryDateStr}</td></tr>
      ${quote.referenceNumber ? `<tr><td>Reference #</td><td>${quote.referenceNumber}</td></tr>` : ''}
      ${quote.subject         ? `<tr><td>Subject</td><td>${quote.subject}</td></tr>` : ''}
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(quote.subTotal || 0).toFixed(2)}</td></tr>
      ${quote.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${quote.cgst.toFixed(2)}</td></tr>` : ''}
      ${quote.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${quote.sgst.toFixed(2)}</td></tr>` : ''}
      ${quote.igst > 0 ? `<tr><td>IGST</td><td>Rs.${quote.igst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs.${(quote.totalAmount || 0).toFixed(2)}</td></tr>
    </table>
    ${orgTagline ? `
    <div class="section-title">From Our Team</div>
    <div class="tagline-box">${orgTagline}</div>` : ''}
    ${quote.customerNotes ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${quote.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The quotation PDF is attached to this email for your records.<br>
      Please reply to this email or contact us to confirm your acceptance.
    </p>
  </div>
  <div class="footer">
    <strong>Thank you for considering us.</strong><br>
    ${orgName} &nbsp;|&nbsp; ${orgEmail} &nbsp;|&nbsp; This is a system-generated email.
  </div>
</div>
</body>
</html>`;

    res.json({ success: true, data: { subject: `Quotation ${quote.quoteNumber} — Rs.${(quote.totalAmount || 0).toFixed(2)}`, html, to: quote.customerEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const quote = await Quote.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    if (!quote) return res.status(404).json({ success: false, message: 'Quote not found' });
    if (to !== undefined)      quote.customEmailTo      = to;
    if (subject !== undefined) quote.customEmailSubject = subject;
    if (html !== undefined)    quote.customEmailHtml    = html;
    await quote.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/quotes/:id - Delete quote
router.delete('/:id', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    const quote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    // Allow deleting quotes in any status
    await quote.deleteOne();
    
    res.json({
      success: true,
      message: 'Quote deleted successfully',
    });
  } catch (error) {
    console.error('Error deleting quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to delete quote', 
      error: error.message 
    });
  }
});

// POST /api/quotes/:id/send - Send quote to customer
router.post('/:id/send', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    // ✅ FIX: Use orgId from JWT token
    const quote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    if (!quote.customerEmail) {
      return res.status(400).json({ 
        success: false, 
        message: 'Customer email is required to send quote' 
      });
    }
    
    // Generate PDF
    const pdfInfo = await generateQuotePDF(quote, req.user?.orgId);

    // Use custom email content if the user edited it in the preview dialog
    const customTo      = quote.customEmailTo;
    const customSubject = quote.customEmailSubject;
    const customHtml    = quote.customEmailHtml;
    const sendTo        = customTo || quote.customerEmail;

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
        subject: customSubject || `Quotation ${quote.quoteNumber} — Rs.${(quote.totalAmount || 0).toFixed(2)}`,
        html: customHtml,
        attachments: [{ filename: `${quote.quoteNumber}.pdf`, path: pdfInfo.filepath }],
      });
    } else {
      // Send email
      await sendQuoteEmail(quote, pdfInfo.filepath, req.user?.orgId);
    }
    
    // Update quote status
    quote.status = 'SENT';
    quote.sentDate = new Date();
    await quote.save();
    
    res.json({
      success: true,
      message: 'Quote sent successfully',
      data: quote,
    });
  } catch (error) {
    console.error('Error sending quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to send quote', 
      error: error.message 
    });
  }
});

// GET /api/quotes/:id/download - Download quote PDF
router.get('/:id/download', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
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
    const quote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    // Generate PDF
    const pdfInfo = await generateQuotePDF(quote, req.user?.orgId);
    
    // Set response headers
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${quote.quoteNumber}.pdf"`);
    
    res.download(pdfInfo.filepath, `${quote.quoteNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to download quote', 
      error: error.message 
    });
  }
});

// POST /api/quotes/:id/accept - Mark quote as accepted
router.post('/:id/accept', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    const quote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    quote.status = 'ACCEPTED';
    quote.acceptedDate = new Date();
    await quote.save();
    
    // Send acceptance email to customer
    await sendAcceptanceEmail(quote, req.user?.orgId);
    
    res.json({
      success: true,
      message: 'Quote marked as accepted',
      data: quote,
    });
  } catch (error) {
    console.error('Error accepting quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to accept quote', 
      error: error.message 
    });
  }
});

// POST /api/quotes/:id/decline - Mark quote as declined
router.post('/:id/decline', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    const quote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    quote.status = 'DECLINED';
    quote.declinedDate = new Date();
    
    if (req.body.declineReason) {
      quote.declineReason = req.body.declineReason;
    }
    
    await quote.save();
    
    // Send decline email to customer
    await sendDeclineEmail(quote, req.body.declineReason, req.user?.orgId);
    
    res.json({
      success: true,
      message: 'Quote marked as declined',
      data: quote,
    });
  } catch (error) {
    console.error('Error declining quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to decline quote', 
      error: error.message 
    });
  }
});

// POST /api/quotes/:id/clone - Duplicate quote
router.post('/:id/clone', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    const originalQuote = await Quote.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!originalQuote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    // Generate new quote number
    const quoteNumber = await generateQuoteNumber(req.user?.orgId || null);
    
    // Create new quote
    const newQuote = new Quote({
      ...originalQuote.toObject(),
      _id: undefined,
      quoteNumber,
      status: 'DRAFT',
      quoteDate: new Date(),
      expiryDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days from now
      createdBy: req.user.userId,
      createdAt: undefined,
      updatedAt: undefined,
      sentDate: undefined,
      acceptedDate: undefined,
      declinedDate: undefined,
    });
    
    await newQuote.save();
    
    res.status(201).json({
      success: true,
      message: 'Quote duplicated successfully',
      data: newQuote,
    });
  } catch (error) {
    console.error('Error cloning quote:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to clone quote', 
      error: error.message 
    });
  }
});

// POST /api/quotes/:id/convert-to-invoice - Convert quote to invoice
router.post('/:id/convert-to-invoice', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    const orgId = req.user?.orgId || null;
    
    const quote = await Quote.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    // ✅ FIX: Allow ACCEPTED or SENT quotes to be converted
    if (quote.status !== 'ACCEPTED' && quote.status !== 'SENT') {
      return res.status(400).json({ 
        success: false, 
        message: `Only accepted or sent quotes can be converted to invoices. Current status: ${quote.status}` 
      });
    }
    
    // Check if already converted
    if (quote.convertedToInvoice) {
      return res.status(400).json({ 
        success: false, 
        message: 'Quote has already been converted to an invoice' 
      });
    }
    
    // Import Invoice model from invoice.js
    const Invoice = mongoose.model('Invoice');
    
    // Generate invoice number
    const { generateNumber } = require('../utils/numberGenerator');
    const invoiceNumber = await generateNumber(Invoice, 'invoiceNumber', 'INV', orgId || null);
    
    // Calculate due date (default Net 30)
    const invoiceDate = new Date(currentDate);
    const dueDate = new Date(currentDate);
    dueDate.setDate(dueDate.getDate() + 30);
    
    // Create invoice from quote data
    const invoice = new Invoice({
      orgId,
      invoiceNumber,
      customerId: quote.customerId,
      customerName: quote.customerName,
      customerEmail: quote.customerEmail || '',
      customerPhone: quote.customerPhone || '',
      orderNumber: quote.referenceNumber || '',
      invoiceDate,
      terms: 'Net 30',
      dueDate,
      salesperson: quote.salesperson || '',
      subject: quote.subject || '',
      items: quote.items.map(item => ({
        itemDetails: item.itemDetails,
        quantity: item.quantity,
        rate: item.rate,
        discount: item.discount || 0,
        discountType: item.discountType || 'percentage',
        amount: item.amount
      })),
      customerNotes: quote.customerNotes || '',
      termsAndConditions: quote.termsAndConditions || '',
      subTotal: quote.subTotal,
      tdsRate: quote.tdsRate || 0,
      tdsAmount: quote.tdsAmount || 0,
      tcsRate: quote.tcsRate || 0,
      tcsAmount: quote.tcsAmount || 0,
      gstRate: quote.gstRate || 18,
      cgst: quote.cgst || 0,
      sgst: quote.sgst || 0,
      igst: quote.igst || 0,
      totalAmount: quote.totalAmount,
      status: 'DRAFT',
      amountPaid: 0,
      amountDue: quote.totalAmount,
      createdBy: req.user.userId,
    });
    
await invoice.save();

// ✅ COA Posting
try {
  const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

  const currentOrgId = req.user?.orgId || null;
  const [arId, salesId, taxId] = await Promise.all([
    ChartOfAccount.findOne({ accountName: 'Accounts Receivable', isSystemAccount: true, orgId: currentOrgId }).select('_id').lean().then(a => a?._id),
    ChartOfAccount.findOne({ accountName: 'Sales', isSystemAccount: true, orgId: currentOrgId }).select('_id').lean().then(a => a?._id),
    ChartOfAccount.findOne({ accountName: 'Tax Payable', isSystemAccount: true, orgId: currentOrgId }).select('_id').lean().then(a => a?._id),
  ]);

  const txnDate = new Date(invoice.invoiceDate);
  const gst = (invoice.cgst || 0) + (invoice.sgst || 0);

  if (arId) await postTransactionToCOA({
    accountId: arId, orgId: currentOrgId, date: txnDate,
    description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: invoice.totalAmount, credit: 0,
  });

  if (salesId) await postTransactionToCOA({
    accountId: salesId, orgId: currentOrgId, date: txnDate,
    description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: invoice.subTotal,
  });

  if (taxId && gst > 0) await postTransactionToCOA({
    accountId: taxId, orgId: currentOrgId, date: txnDate,
    description: `GST on Invoice ${invoice.invoiceNumber}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: gst,
  });

  console.log(`✅ COA posted for converted invoice: ${invoice.invoiceNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (quote convert):', coaErr.message);
}

// Update quote status
quote.status = 'CONVERTED';
quote.convertedToInvoice = true;
quote.convertedDate = currentDate;
await quote.save();

console.log(`✅ Quote ${quote.quoteNumber} converted to invoice ${invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Quote converted to invoice successfully',
      data: {
        quote,
        invoice
      },
    });
  } catch (error) {
    console.error('❌ Error converting quote to invoice:', error);
    console.error('   Error details:', error.message);
    console.error('   Stack trace:', error.stack);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to convert quote to invoice', 
      error: error.message 
    });
  }
});

// POST /api/quotes/:id/convert-to-sales-order - Convert quote to sales order
router.post('/:id/convert-to-sales-order', [
  param('id').isMongoId().withMessage('Invalid quote ID'),
  validateRequest,
], async (req, res) => {
  try {
    const orgId = req.user?.orgId || null;
    
    const quote = await Quote.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    
    if (!quote) {
      return res.status(404).json({ 
        success: false, 
        message: 'Quote not found' 
      });
    }
    
    // ✅ FIX: Allow ACCEPTED or SENT quotes to be converted
    if (quote.status !== 'ACCEPTED' && quote.status !== 'SENT') {
      return res.status(400).json({ 
        success: false, 
        message: `Only accepted or sent quotes can be converted to sales orders. Current status: ${quote.status}` 
      });
    }
    
    // Check if already converted
    if (quote.convertedToSalesOrder) {
      return res.status(400).json({ 
        success: false, 
        message: 'Quote has already been converted to a sales order' 
      });
    }
    
    // Import SalesOrder model (assuming it's in the same directory structure)
    const SalesOrder = mongoose.model('SalesOrder');
    
    // Generate unique sales order number
    const { generateNumber } = require('../utils/numberGenerator');
    const salesOrderNumber = await generateNumber(SalesOrder, 'salesOrderNumber', 'SO', orgId || null);
    
    // Convert quote items to sales order items format
    const salesOrderItems = quote.items.map(item => ({
      itemDetails: item.itemDetails,
      quantity: item.quantity,
      rate: item.rate,
      discount: item.discount || 0,
      discountType: item.discountType || 'percentage',
      amount: item.amount,
      quantityPacked: 0,
      quantityShipped: 0,
      quantityInvoiced: 0,
    }));
    
    // ✅ FIX: Create proper date object
    const currentDate = new Date();
    
    // Create sales order from quote data
    const salesOrder = new SalesOrder({
      orgId,
      salesOrderNumber,
      referenceNumber: quote.referenceNumber || quote.quoteNumber,
      customerId: quote.customerId,
      customerName: quote.customerName,
      customerEmail: quote.customerEmail || '',
      customerPhone: quote.customerPhone || '',
      salesOrderDate: currentDate,  // ✅ Use proper Date object
      expectedShipmentDate: null,
      paymentTerms: 'Net 30',
      deliveryMethod: '',
      salesperson: quote.salesperson || '',
      subject: quote.subject || '',
      items: salesOrderItems,
      subTotal: quote.subTotal,
      tdsRate: quote.tdsRate || 0,
      tdsAmount: quote.tdsAmount || 0,
      tcsRate: quote.tcsRate || 0,
      tcsAmount: quote.tcsAmount || 0,
      gstRate: quote.gstRate || 18,
      cgst: quote.cgst || 0,
      sgst: quote.sgst || 0,
      igst: quote.igst || 0,
      totalAmount: quote.totalAmount,
      customerNotes: quote.customerNotes || '',
      termsAndConditions: quote.termsAndConditions || '',
      status: 'DRAFT',
      approvalStatus: 'NOT_REQUIRED',
      convertedFromQuoteId: quote._id.toString(),
      convertedFromQuoteNumber: quote.quoteNumber,
      convertedToInvoice: false,
      createdBy: req.user.userId,
    });
    
    await salesOrder.save();
    
    console.log('✅ Sales order created from quote:', salesOrderNumber);
    
    // Update quote status
    quote.status = 'CONVERTED';
    quote.convertedToSalesOrder = true;
    quote.convertedDate = currentDate;
    await quote.save();
    
    res.json({
      success: true,
      message: 'Quote converted to sales order successfully',
      data: {
        quote,
        salesOrder,
      },
    });
  } catch (error) {
    console.error('❌ Error converting quote to sales order:', error);
    console.error('   Error details:', error.message);
    console.error('   Stack trace:', error.stack);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to convert quote to sales order', 
      error: error.message 
    });
  }
});

module.exports = router;