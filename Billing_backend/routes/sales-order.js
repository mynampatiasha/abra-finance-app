// ============================================================================
// SALES ORDERS BACKEND API - Complete Implementation
// ============================================================================
// File: backend/routes/sales-order.js
// Features: CRUD, Convert from Quote, Bulk Import, PDF, Email, Invoice Conversion
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const { body, param, validationResult } = require('express-validator');
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
// MONGOOSE MODEL DEFINITION
// ============================================================================

const salesOrderItemSchema = new mongoose.Schema({
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
  itemGstRate: {
    type: Number,
    default: 0
  },
  amount: {
    type: Number,
    required: true,
    min: 0,
  },
  // Stock tracking
  quantityPacked: {
    type: Number,
    default: 0,
    min: 0,
  },
  quantityShipped: {
    type: Number,
    default: 0,
    min: 0,
  },
  quantityInvoiced: {
    type: Number,
    default: 0,
    min: 0,
  },
}, { _id: false });

const salesOrderSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null },
  organizationId: {
    type: String,
    required: false,
    index: true,
  },
  salesOrderNumber: {
    type: String,
    required: true,

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
  
  // Dates
  salesOrderDate: {
    type: Date,
    required: true,
    default: Date.now,
  },
  expectedShipmentDate: {
    type: Date,
  },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30',
  },
  deliveryMethod: {
    type: String,
    trim: true,
  },
  
  // Additional Info
  salesperson: {
    type: String,
    trim: true,
  },
  subject: {
    type: String,
    trim: true,
  },
  
  // Items
  items: {
    type: [salesOrderItemSchema],
    required: true,
    validate: {
      validator: function(items) {
        return items && items.length > 0;
      },
      message: 'At least one item is required',
    },
  },
  
  // Financial Calculations
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
  // Zoho-style GST fields
  isInterState:  { type: Boolean, default: false },
  totalCGST:     { type: Number, default: 0 },
  totalSGST:     { type: Number, default: 0 },
  totalIGST:     { type: Number, default: 0 },
  placeOfSupply: { type: String, default: '' },
  billingAddress: {
    street: String, city: String, state: String,
    pincode: String, country: { type: String, default: 'India' },
  },
  shippingAddress: {
    street: String, city: String, state: String,
    pincode: String, country: { type: String, default: 'India' },
  },
  totalAmount: {
    type: Number,
    required: true,
    default: 0,
  },
  
  // Notes
  customerNotes: {
    type: String,
    trim: true,
  },
  termsAndConditions: {
    type: String,
    trim: true,
  },
  
  // Status Management
  status: {
    type: String,
    enum: ['DRAFT', 'OPEN', 'CONFIRMED', 'PACKED', 'SHIPPED', 'INVOICED', 'CLOSED', 'CANCELLED', 'VOID'],
    default: 'DRAFT',
    index: true,
  },
  
  // Approval Workflow
  approvalStatus: {
    type: String,
    enum: ['PENDING', 'APPROVED', 'REJECTED', 'NOT_REQUIRED'],
    default: 'NOT_REQUIRED',
  },
  approvedBy: {
    type: String,
  },
  approvedAt: {
    type: Date,
  },
  
  // Conversion tracking
  convertedFromQuoteId: {
    type: String,
  },
  convertedFromQuoteNumber: {
    type: String,
  },
  convertedToInvoice: {
    type: Boolean,
    default: false,
  },
  convertedToInvoiceId: {
    type: String,
  },
  convertedToInvoiceNumber: {
    type: String,
  },
  convertedDate: {
    type: Date,
  },
  
  // Email tracking
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: {
      type: String,
      enum: ['sales_order', 'shipment_update', 'invoice']
    }
  }],
  
  // PDF Generation
  pdfPath: String,
  pdfGeneratedAt: Date,
  
  // Audit Trail
  createdBy: {
    type: String,
    required: true,
  },
  updatedBy: String,
  // Custom email fields � saved when user edits email preview before sending
  customEmailTo:      { type: String, default: null },
  customEmailSubject: { type: String, default: null },
  customEmailHtml:    { type: String, default: null },
}, {
  timestamps: true,
});

// Indexes for better query performance
salesOrderSchema.index({ orgId: 1, branchId: 1, salesOrderNumber: 1 }, { unique: true });
salesOrderSchema.index({ orgId: 1, customerId: 1 });
salesOrderSchema.index({ orgId: 1, status: 1 });
salesOrderSchema.index({ orgId: 1, salesOrderDate: -1 });
salesOrderSchema.index({ orgId: 1, createdAt: -1 });

// Methods
salesOrderSchema.methods.canEdit = function() {
  return !['INVOICED', 'CLOSED', 'CANCELLED', 'VOID'].includes(this.status);
};

salesOrderSchema.methods.canDelete = function() {
  return this.status === 'DRAFT';
};

salesOrderSchema.methods.canConvert = function() {
  return ['CONFIRMED', 'OPEN', 'PACKED', 'SHIPPED'].includes(this.status);
};

// Create the SalesOrder model
const SalesOrder = mongoose.models.SalesOrder || mongoose.model('SalesOrder', salesOrderSchema);

// ============================================================================
// MIDDLEWARE
// ============================================================================

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

const salesOrderValidationRules = [
  body('customerId').notEmpty().withMessage('Customer ID is required'),
  body('customerName').notEmpty().withMessage('Customer name is required'),
  body('salesOrderDate').isISO8601().withMessage('Valid sales order date is required'),
  body('items').isArray({ min: 1 }).withMessage('At least one item is required'),
  body('items.*.itemDetails').notEmpty().withMessage('Item details are required'),
  body('items.*.quantity').isFloat({ min: 0.01 }).withMessage('Quantity must be greater than 0'),
  body('items.*.rate').isFloat({ min: 0 }).withMessage('Rate must be non-negative'),
  body('status').isIn(['DRAFT', 'OPEN', 'CONFIRMED', 'PACKED', 'SHIPPED', 'INVOICED', 'CLOSED', 'CANCELLED', 'VOID'])
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

const generateSalesOrderNumber = async (organizationId, branchId = null) => {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(SalesOrder, 'salesOrderNumber', 'SO', organizationId || null, branchId);
};

// Calculate sales order totals
const calculateSalesOrderTotals = (items, tdsRate = 0, tcsRate = 0, gstRate = 18) => {
  let subTotal = 0;
  
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
  
  const tdsAmount = parseFloat((subTotal * tdsRate / 100).toFixed(2));
  const tcsAmount = parseFloat((subTotal * tcsRate / 100).toFixed(2));
  
  // Calculate GST dynamically
  let totalGst = 0;
  const hasItemGst = items.some(item => typeof item.itemGstRate === 'number');
  
  if (hasItemGst) {
    items.forEach(item => {
      const itemProportion = subTotal > 0 ? (item.amount / subTotal) : 0;
      const itemTds = tdsAmount * itemProportion;
      const itemTcs = tcsAmount * itemProportion;
      const itemGstBase = item.amount - itemTds + itemTcs;
      const itemTax = (itemGstBase * (item.itemGstRate || 0)) / 100;
      totalGst += itemTax;
    });
  } else {
    const gstBase = subTotal - tdsAmount + tcsAmount;
    totalGst = (gstBase * gstRate) / 100;
  }
  
  totalGst = parseFloat(totalGst.toFixed(2));
  const cgst = parseFloat((totalGst / 2).toFixed(2));
  const sgst = parseFloat((totalGst / 2).toFixed(2));
  const totalAmount = parseFloat((subTotal - tdsAmount + tcsAmount + totalGst).toFixed(2));
  
  return {
    subTotal,
    tdsAmount,
    tcsAmount,
    cgst,
    sgst,
    igst: 0,
    totalAmount,
    tdsRate,
    tcsRate,
    gstRate
  };
};

// Generate PDF for sales order
const generateSalesOrderPDF = async (salesOrder, orgId = null, branchId = null) => {
  return new Promise(async (resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'sales-orders');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `sales-order-${salesOrder.salesOrderNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      let orgName  = 'Your Company';
      let orgGST   = '';
      let orgAddr  = '';
      let orgEmail = '';
      let orgPhone = '';
      let orgData  = null;
      try {
        const { getEffectiveOrgData } = require('./branches');
        const db = mongoose.connection.db;
        if (db) orgData = await getEffectiveOrgData(orgId, branchId, db);
        if (orgData) {
          orgName  = orgData.orgName   || orgName;
          orgGST   = orgData.gstNumber || '';
          orgAddr  = orgData.address   || '';
          orgEmail = orgData.email     || '';
          orgPhone = orgData.phone     || '';
        }
      } catch (_) {}

      const doc    = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      const pageW = 515;

      // -- HEADER - plain white background like invoices.js -----------------
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
      const textStartY  = 35;
      const logoCenterY = textStartY + (textBlockHeight / 2);
      
      const logoH = 82; // Increased to match invoice
      const logoW = 110; // Increased to match invoice
      const logoY = textStartY; // Align top of logo with top of text

      if (logoData) {
        try {
          doc.image(logoData, 44, logoY, { width: logoW, height: logoH, fit: [logoW, logoH] });
          logoLoaded = true;
        } catch (e) { console.warn('?? Logo load failed:', e.message); }
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
         .text('SALES ORDER', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
         .text(salesOrder.salesOrderNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`Date: ${new Date(salesOrder.salesOrderDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`,
               380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#000000').font('Helvetica-Bold')
         .text(`${(salesOrder.status || 'DRAFT')}`, 380, 92, { width: 170, align: 'right' });

      // -- META GRID � 3 columns: Bill To | Ship To | SO Details -------------
      const metaY = Math.max(132, contactY + 8);
      const colW  = pageW / 3;

      const billingStr = [
        salesOrder.billingAddress?.street,
        salesOrder.billingAddress?.city,
        salesOrder.billingAddress?.state,
        salesOrder.billingAddress?.pincode,
      ].filter(Boolean).join(', ');

      // Dynamic box height
      doc.fontSize(9).font('Helvetica-Bold');
      const _custNameH = doc.heightOfString(salesOrder.customerName || 'N/A', { width: colW - 16 });
      doc.fontSize(7).font('Helvetica');
      const _addrH = billingStr ? doc.heightOfString(billingStr, { width: colW - 16 }) : 0;
      const metaH  = Math.max(90, 18 + _custNameH + 2 + _addrH + 20);

      // Col 1: Bill To
      const billX = 40;
      doc.rect(billX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('BILL TO', billX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(9).fillColor('#000000').font('Helvetica-Bold')
         .text(salesOrder.customerName || 'N/A', billX + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(9).font('Helvetica-Bold');
      const custNameH = doc.heightOfString(salesOrder.customerName || 'N/A', { width: colW - 16 });
      const billAddrY = metaY + 18 + custNameH + 2;
      if (billingStr) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(billingStr, billX + 8, billAddrY, { width: colW - 16, ellipsis: true });
      }
      if (salesOrder.customerEmail) {
        doc.fontSize(7).font('Helvetica');
        const addrH = billingStr ? doc.heightOfString(billingStr, { width: colW - 16 }) : 0;
        doc.fillColor('#000000')
           .text(salesOrder.customerEmail, billX + 8, billAddrY + addrH + 2, { width: colW - 16, ellipsis: true });
      }

      // Col 2: Ship To
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
      if (salesOrder.deliveryMethod) {
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(`Via: ${salesOrder.deliveryMethod}`, shipX + 8, metaY + 60, { width: colW - 16 });
      }

      // Col 3: SO Details
      const detX = 40 + colW * 2;
      doc.rect(detX, metaY, colW, metaH).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('SALES ORDER DETAILS', detX + 8, metaY + 7, { width: colW - 16, characterSpacing: 0.8 });
      doc.fontSize(8).fillColor('#000000').font('Helvetica')
         .text(`SO #: ${salesOrder.salesOrderNumber}`, detX + 8, metaY + 18, { width: colW - 16 });
      doc.fontSize(7).fillColor('#000000').font('Helvetica')
         .text(`Terms: ${salesOrder.paymentTerms || 'Net 30'}`, detX + 8, metaY + 29, { width: colW - 16 });
      if (salesOrder.expectedShipmentDate) {
        doc.text(`Ship By: ${new Date(salesOrder.expectedShipmentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}`,
                 detX + 8, metaY + 39, { width: colW - 16 });
      }
      if (salesOrder.referenceNumber) {
        doc.text(`Ref: ${salesOrder.referenceNumber}`, detX + 8, metaY + 49, { width: colW - 16, ellipsis: true });
      }

      let tableStartY = metaY + metaH + 12;

      // -- ITEMS TABLE � same columns as invoices.js -------------------------
      const isInterState = salesOrder.isInterState || false;

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
      (salesOrder.items || []).forEach((item, idx) => {
        const descText  = item.itemDetails || 'N/A';
        const descWidth = cols.desc.w - 4;
        const vPad      = 8;
        doc.font('Helvetica').fontSize(7);
        const descH = doc.heightOfString(descText, { width: descWidth, lineGap: 1 });
        const rowH  = Math.max(20, descH + vPad * 2);

        const fill = idx % 2 === 0 ? '#ffffff' : '#f7f9fc';
        doc.rect(40, rowY, 515, rowH).fill(fill);
        doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();

        const hsnSac  = item.hsnCode || item.sacCode || '';
        const discStr = item.discount > 0
          ? (item.discountType === 'percentage' ? `${item.discount}%` : `${item.discount}`)
          : '�';

        const gstRate  = item.itemGstRate !== undefined ? item.itemGstRate : (salesOrder.gstRate || 18);
        const taxable  = item.taxableAmount || item.amount || 0;
        const cgstAmt  = isInterState ? 0 : Math.round(taxable * (gstRate / 2) / 100 * 100) / 100;
        const sgstAmt  = cgstAmt;
        const igstAmt  = isInterState ? Math.round(taxable * gstRate / 100 * 100) / 100 : 0;
        const totalAmt = item.amount || (taxable + cgstAmt + sgstAmt + igstAmt);

        const cellY = rowY + vPad;
        doc.fontSize(7).fillColor('#000000');
        doc.font('Helvetica-Bold').text(String(idx + 1), cols.num.x + 2, cellY, { width: cols.num.w });
        doc.font('Helvetica').text(descText, cols.desc.x + 2, cellY, { width: descWidth, lineGap: 1 });
        doc.text(hsnSac,                              cols.hsn.x  + 2, cellY, { width: cols.hsn.w - 2,  ellipsis: true });
        doc.text(item.unit || 'Nos',                  cols.unit.x + 2, cellY, { width: cols.unit.w });
        doc.text(String(item.quantity || 0),          cols.qty.x  + 2, cellY, { width: cols.qty.w,     align: 'center' });
        doc.text(`${(item.rate || 0).toFixed(2)}`,    cols.rate.x + 2, cellY, { width: cols.rate.w,    align: 'right' });
        doc.text(discStr,                             cols.disc.x + 2, cellY, { width: cols.disc.w,    align: 'right' });
        doc.text(`${taxable.toFixed(2)}`,             cols.taxable.x+2, cellY, { width: cols.taxable.w, align: 'right' });
        doc.text(`${gstRate}%`,                       cols.gst.x  + 2, cellY, { width: cols.gst.w,     align: 'center' });
        if (isInterState) {
          doc.text(`${igstAmt.toFixed(2)}`,           cols.tax1.x + 2, cellY, { width: cols.tax1.w + cols.tax2.w, align: 'right' });
        } else {
          doc.text(`${cgstAmt.toFixed(2)}`,           cols.tax1.x + 2, cellY, { width: cols.tax1.w, align: 'right' });
          doc.text(`${sgstAmt.toFixed(2)}`,           cols.tax2.x + 2, cellY, { width: cols.tax2.w, align: 'right' });
        }
        doc.font('Helvetica-Bold')
           .text(`${totalAmt.toFixed(2)}`,            cols.amount.x+2, cellY, { width: cols.amount.w, align: 'right' });
        rowY += rowH;
      });

      // -- TOTALS ------------------------------------------------------------
      const totalsX = 315;
      const totalsW = 240;
      let totalsY   = rowY + 12;
      const labelX  = totalsX;
      const amountX = totalsX + totalsW;

      const tRow = (label, amount, bold = false) => {
        doc.fontSize(8).fillColor('#5e6e84').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(label, labelX, totalsY, { width: 140 });
        doc.fillColor('#000000').font(bold ? 'Helvetica-Bold' : 'Helvetica')
           .text(amount, labelX + 140, totalsY, { width: 100, align: 'right' });
        doc.moveTo(labelX, totalsY + 11).lineTo(amountX, totalsY + 11)
           .lineWidth(0.5).strokeColor('#dde4ef').dash(2, { space: 2 }).stroke().undash();
        totalsY += 14;
      };

      tRow('Subtotal:', `Rs. ${(salesOrder.subTotal || 0).toFixed(2)}`);
      if ((salesOrder.totalCGST || salesOrder.cgst || 0) > 0)
        tRow('CGST:', `Rs. ${(salesOrder.totalCGST || salesOrder.cgst || 0).toFixed(2)}`);
      if ((salesOrder.totalSGST || salesOrder.sgst || 0) > 0)
        tRow('SGST:', `Rs. ${(salesOrder.totalSGST || salesOrder.sgst || 0).toFixed(2)}`);
      if ((salesOrder.totalIGST || salesOrder.igst || 0) > 0)
        tRow('IGST:', `Rs. ${(salesOrder.totalIGST || salesOrder.igst || 0).toFixed(2)}`);
      if ((salesOrder.tdsAmount || 0) > 0)
        tRow('TDS Deducted:', `- Rs. ${salesOrder.tdsAmount.toFixed(2)}`);
      if ((salesOrder.tcsAmount || 0) > 0)
        tRow('TCS Collected:', `Rs. ${salesOrder.tcsAmount.toFixed(2)}`);

      totalsY += 4;
      doc.rect(labelX, totalsY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('Grand Total', labelX + 6, totalsY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Rs. ${(salesOrder.totalAmount || 0).toFixed(2)}`, labelX, totalsY + 5,
               { width: totalsW - 6, align: 'right' });
      totalsY += 32;

      // Amount in words
      const wordsY = totalsY + 8;
      doc.rect(40, wordsY, pageW, 18).fill('#f0fdf4');
      doc.fontSize(7.5).fillColor('#065f46').font('Helvetica-Bold')
         .text(`In Words: ${numberToWords(Math.round(salesOrder.totalAmount || 0))} Only`,
               48, wordsY + 5, { width: pageW - 16 });

      // Notes
      let notesY = wordsY + 28;
      if (salesOrder.customerNotes) {
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTES', 40, notesY, { characterSpacing: 0.8 });
        doc.moveTo(40, notesY + 9).lineTo(555, notesY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica')
           .text(salesOrder.customerNotes, 40, notesY + 14, { width: pageW });
        notesY += 40;
      }

      // Terms
      if (salesOrder.termsAndConditions) {
        const tcY = notesY + 6;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold')
           .text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(salesOrder.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
        notesY = tcY + 30;
      }

      // Authorized Signatory
      const signSectionY = notesY + 10;
      const signBoxW     = 220;
      const authBoxX     = 555 - signBoxW;
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text(`For ${orgName.toUpperCase()}`, authBoxX, signSectionY, { width: signBoxW, characterSpacing: 0.5, ellipsis: true });

      const _soSigRelPath = orgData?.digitalSignaturePath;
      const _soSigSize    = 200;
      let   _soActualSigH = _soSigSize;
      
      let sigBuf = null;
      let sigExt = '.png';
      if (orgData?.signatureBase64) {
        const match = orgData.signatureBase64.match(/^data:image\/(\w+);base64,(.*)$/);
        if (match) {
          sigExt = '.' + match[1].replace('jpeg', 'jpg');
          sigBuf = Buffer.from(match[2], 'base64');
        }
      } else if (_soSigRelPath) {
        const _soSigAbs = path.join(__dirname, '..', _soSigRelPath.replace(/^\//, ''));
        try { if (fs.existsSync(_soSigAbs)) { sigBuf = fs.readFileSync(_soSigAbs); sigExt = path.extname(_soSigAbs).toLowerCase(); } } catch (_) {}
      }

      if (sigBuf) {
        try {
            let _soW = _soSigSize, _soH = _soSigSize;
            try {
              if (sigExt === '.png' && sigBuf.length > 24) { _soW = sigBuf.readUInt32BE(16); _soH = sigBuf.readUInt32BE(20); }
              else if ((sigExt === '.jpg' || sigExt === '.jpeg') && sigBuf.length > 4) {
                let _soi = 2;
                while (_soi < sigBuf.length - 8) {
                  if (sigBuf[_soi] === 0xFF && sigBuf[_soi+1] >= 0xC0 && sigBuf[_soi+1] <= 0xC3) { _soH = sigBuf.readUInt16BE(_soi+5); _soW = sigBuf.readUInt16BE(_soi+7); break; }
                  _soi += 2 + sigBuf.readUInt16BE(_soi + 2);
                }
              }
            } catch (_) {}
            const _soScale = Math.min(_soSigSize / _soW, _soSigSize / _soH);
            _soActualSigH  = Math.round(_soH * _soScale);
            const _soActualSigW = Math.round(_soW * _soScale);
            doc.image(sigBuf, authBoxX + (signBoxW - _soActualSigW) / 2, signSectionY + 10, { width: _soActualSigW, height: _soActualSigH });
        } catch (_e) { console.warn('⚠️ Signature render failed:', _e.message); }
      }

      const _soSigLineY = signSectionY + 10 + _soActualSigH + 14;
      doc.moveTo(authBoxX, _soSigLineY).lineTo(authBoxX + signBoxW, _soSigLineY)
         .lineWidth(0.5).strokeColor('#aaaaaa').stroke();
      doc.fontSize(6.5).fillColor('#000000').font('Helvetica-Bold')
         .text('Authorized Signatory', authBoxX, _soSigLineY + 3, { width: signBoxW, align: 'center' });

      // Footer
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY).lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName} � ${orgGST ? 'GSTIN: ' + orgGST + ' � ' : ''}${salesOrder.salesOrderNumber}`,
               40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`,
               40, footY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => {
        console.log(`? Sales Order PDF generated: ${filename}`);
        resolve({ filename, filepath, relativePath: `/uploads/sales-orders/${filename}` });
      });
      stream.on('error', reject);

    } catch (error) {
      console.error('? Sales Order PDF error:', error);
      reject(error);
    }
  });
};

// Email transporter
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

// Send sales order email � styled identical to invoices.js
const sendSalesOrderEmail = async (salesOrder, pdfPathOrBuffer, orgId = null, branchId = null) => {
  try {
    if (!process.env.SMTP_USER || !process.env.SMTP_PASSWORD) {
      console.log('SMTP not configured - skipping email send');
      return;
    }

    let orgName  = 'Billing Team';
    let orgGST   = '';
    let orgEmail = '';
    let orgPhone = '';
    let orgData  = null;
    try {
      const { getEffectiveOrgData } = require('./branches');
      const db = mongoose.connection.db;
      if (db) orgData = await getEffectiveOrgData(orgId, branchId, db);
      if (orgData) {
        orgName  = orgData.orgName    || orgName;
        orgGST   = orgData.gstNumber  || '';
        orgEmail = orgData.email      || '';
        orgPhone = orgData.phone      || '';
      }
    } catch (_) {}

    const transporter = getEmailTransporter();
    const dateStr = new Date(salesOrder.salesOrderDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const shipDateStr = salesOrder.expectedShipmentDate
      ? new Date(salesOrder.expectedShipmentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })
      : null;

    const htmlBody = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Sales Order ${salesOrder.salesOrderNumber}</title>
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
    <h1>Sales Order</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${salesOrder.salesOrderNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${salesOrder.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached sales order <strong>${salesOrder.salesOrderNumber}</strong> for your reference.
    </p>
    <div class="section-title">Order Details</div>
    <table class="detail">
      <tr><td>SO Number</td>     <td>${salesOrder.salesOrderNumber}</td></tr>
      <tr><td>Date</td>          <td>${dateStr}</td></tr>
      <tr><td>Payment Terms</td> <td>${salesOrder.paymentTerms || 'Net 30'}</td></tr>
      <tr><td>Status</td>        <td>${salesOrder.status}</td></tr>
      ${shipDateStr ? `<tr><td>Expected Shipment</td><td>${shipDateStr}</td></tr>` : ''}
      ${salesOrder.referenceNumber ? `<tr><td>Reference #</td><td>${salesOrder.referenceNumber}</td></tr>` : ''}
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(salesOrder.subTotal || 0).toFixed(2)}</td></tr>
      ${salesOrder.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${salesOrder.cgst.toFixed(2)}</td></tr>` : ''}
      ${salesOrder.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${salesOrder.sgst.toFixed(2)}</td></tr>` : ''}
      ${salesOrder.igst > 0 ? `<tr><td>IGST</td><td>Rs.${salesOrder.igst.toFixed(2)}</td></tr>` : ''}
      ${salesOrder.tdsAmount > 0 ? `<tr><td>TDS Deducted</td><td>- Rs.${salesOrder.tdsAmount.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs.${(salesOrder.totalAmount || 0).toFixed(2)}</td></tr>
    </table>
    ${salesOrder.customerNotes ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${salesOrder.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The sales order PDF is attached to this email for your records.<br>
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

    const attachment = typeof pdfPathOrBuffer === 'string'
      ? { filename: `${salesOrder.salesOrderNumber}.pdf`, path: pdfPathOrBuffer }
      : { filename: `${salesOrder.salesOrderNumber}.pdf`, content: pdfPathOrBuffer };

    await transporter.sendMail({
      from: `"Accounts" <${process.env.SMTP_USER}>`,
      to: salesOrder.customerEmail,
      subject: `Sales Order ${salesOrder.salesOrderNumber} � Rs.${(salesOrder.totalAmount || 0).toFixed(2)}`,
      html: htmlBody,
      attachments: [attachment],
    });

    console.log(`? Sales order email sent to ${salesOrder.customerEmail}`);
  } catch (error) {
    console.error('??  Error sending sales order email:', error.message);
  }
};

// ============================================================================
// API ROUTES
// ============================================================================

// GET /api/sales-orders - Get all sales orders
router.get('/', async (req, res) => {
  try {
    const {
      status,
      customerId,
      page = 1,
      limit = 20,
      search,
      fromDate,
      toDate
    } = req.query;

    const orgId = req.user?.orgId;

    const query = { orgId };
    Object.assign(query, req.branchFilter || {});

    if (customerId) query.customerId = customerId;

    if (status && status !== 'All') {
      query.status = status;
    }
    
    if (search) {
      query.$or = [
        { salesOrderNumber: { $regex: search, $options: 'i' } },
        { customerName: { $regex: search, $options: 'i' } },
        { referenceNumber: { $regex: search, $options: 'i' } },
      ];
    }
    
    if (fromDate || toDate) {
      query.salesOrderDate = {};
      if (fromDate) {
        query.salesOrderDate.$gte = new Date(fromDate);
      }
      if (toDate) {
        query.salesOrderDate.$lte = new Date(toDate);
      }
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const [salesOrders, total] = await Promise.all([
      SalesOrder.find(query)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .select('-__v'),
      SalesOrder.countDocuments(query),
    ]);
    
    res.json({
      success: true,
      data: {
        salesOrders,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total,
          pages: Math.ceil(total / parseInt(limit)),
        },
      },
    });
  } catch (error) {
    console.error('Error fetching sales orders:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch sales orders', 
      error: error.message 
    });
  }
});

// GET /api/sales-orders/stats - Get statistics
router.get('/stats', async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    const orgFilter = { orgId, ...(req.branchFilter || {}) };
    
    const [
      totalSalesOrders,
      draftSalesOrders,
      openSalesOrders,
      confirmedSalesOrders,
      shippedSalesOrders,
      invoicedSalesOrders,
      totalValue,
    ] = await Promise.all([
      SalesOrder.countDocuments(orgFilter),
      SalesOrder.countDocuments({ ...orgFilter, status: 'DRAFT' }),
      SalesOrder.countDocuments({ ...orgFilter, status: 'OPEN' }),
      SalesOrder.countDocuments({ ...orgFilter, status: 'CONFIRMED' }),
      SalesOrder.countDocuments({ ...orgFilter, status: 'SHIPPED' }),
      SalesOrder.countDocuments({ ...orgFilter, status: 'INVOICED' }),
      SalesOrder.aggregate([
        { $match: orgFilter },
        { $group: { _id: null, total: { $sum: '$totalAmount' } } },
      ]),
    ]);
    
    res.json({
      success: true,
      data: {
        totalSalesOrders,
        draftSalesOrders,
        openSalesOrders,
        confirmedSalesOrders,
        shippedSalesOrders,
        invoicedSalesOrders,
        totalValue: totalValue[0]?.total || 0,
      },
    });
  } catch (error) {
    console.error('Error fetching sales order stats:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch sales order statistics', 
      error: error.message 
    });
  }
});

// GET /api/sales-orders/:id - Get single sales order
router.get('/:id', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    res.json({
      success: true,
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error fetching sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders - Create new sales order
router.post('/', salesOrderValidationRules, validateRequest, async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    
    console.log('? Creating sales order with orgId:', orgId);
    
    const salesOrderNumber = await generateSalesOrderNumber(orgId, req.branchIds?.length > 0 ? req.branchIds[0] : null);
    const totals = calculateSalesOrderTotals(
      req.body.items,
      req.body.tdsRate || 0,
      req.body.tcsRate || 0,
      req.body.gstRate || 18
    );
    
    const salesOrder = new SalesOrder({
      ...req.body,
      salesOrderNumber,
      orgId,
      branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
            createdBy: req.user.userId,
      ...totals,
    });
    
    await salesOrder.save();
    
    console.log('? Sales order created successfully:', salesOrder.salesOrderNumber);
    
    res.status(201).json({
      success: true,
      message: 'Sales order created successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('? Error creating sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to create sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/bulk-import - Bulk import sales orders
router.post('/bulk-import', [
  body('salesOrders').isArray({ min: 1 }).withMessage('Sales orders array is required'),
  validateRequest,
], async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    const userId = req.user.userId;
    const salesOrdersData = req.body.salesOrders;
    
    console.log(`\n?? Starting bulk import for ${salesOrdersData.length} sales orders...`);
    
    const results = {
      successCount: 0,
      failedCount: 0,
      totalProcessed: salesOrdersData.length,
      errors: [],
    };
    
    for (let i = 0; i < salesOrdersData.length; i++) {
      const soData = salesOrdersData[i];
      
      try {
        // Validate required fields
        if (!soData.customerName) throw new Error('Customer name is required');
        if (!soData.customerEmail) throw new Error('Customer email is required');
        if (!soData.salesOrderDate) throw new Error('Sales order date is required');
        if (!soData.subTotal || soData.subTotal <= 0) throw new Error('Sub total must be greater than 0');
        if (!soData.totalAmount || soData.totalAmount <= 0) throw new Error('Total amount must be greater than 0');
        
        // Validate status
        const validStatuses = ['DRAFT', 'OPEN', 'CONFIRMED', 'PACKED', 'SHIPPED', 'INVOICED', 'CLOSED', 'CANCELLED'];
        if (!validStatuses.includes(soData.status)) {
          throw new Error(`Invalid status. Must be one of: ${validStatuses.join(', ')}`);
        }
        
        // Generate sales order number
        let salesOrderNumber = soData.salesOrderNumber;
        if (!salesOrderNumber) {
          salesOrderNumber = await generateSalesOrderNumber(orgId, req.branchIds?.length > 0 ? req.branchIds[0] : null);
        } else {
const existingSO = await SalesOrder.findOne({ salesOrderNumber });
if (existingSO) {
  salesOrderNumber = await generateSalesOrderNumber(orgId, req.branchIds?.length > 0 ? req.branchIds[0] : null);
            console.log(`   ??  SO number ${soData.salesOrderNumber} exists, generated new: ${salesOrderNumber}`);
          }
        }
        
        // Create dummy item if no items provided
        let items = [];
        if (!soData.items || soData.items.length === 0) {
          items = [{
            itemDetails: soData.subject || 'Service',
            quantity: 1,
            rate: soData.subTotal || 0,
            discount: 0,
            discountType: 'percentage',
            amount: soData.subTotal || 0,
          }];
        } else {
          items = soData.items;
        }
        
        const customerId = soData.customerId || `CUST-${Date.now()}-${i}`;
        
        const salesOrder = new SalesOrder({
          orgId,
          branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
          salesOrderNumber,
          referenceNumber: soData.referenceNumber || '',
          customerId,
          customerName: soData.customerName,
          customerEmail: soData.customerEmail,
          customerPhone: soData.customerPhone || '',
          salesOrderDate: new Date(soData.salesOrderDate),
          expectedShipmentDate: soData.expectedShipmentDate ? new Date(soData.expectedShipmentDate) : null,
          paymentTerms: soData.paymentTerms || 'Net 30',
          deliveryMethod: soData.deliveryMethod || '',
          salesperson: soData.salesperson || '',
          subject: soData.subject || '',
          items,
          subTotal: soData.subTotal,
          tdsRate: soData.tdsRate || 0,
          tdsAmount: soData.tdsAmount || 0,
          tcsRate: soData.tcsRate || 0,
          tcsAmount: soData.tcsAmount || 0,
          gstRate: soData.gstRate || 18,
          cgst: soData.cgst || 0,
          sgst: soData.sgst || 0,
          igst: soData.igst || 0,
          totalAmount: soData.totalAmount,
          customerNotes: soData.customerNotes || '',
          termsAndConditions: soData.termsConditions || '',
          status: soData.status,
          createdBy: userId,
        });
        
        await salesOrder.save();
        
        results.successCount++;
        console.log(`   ? Successfully imported sales order: ${salesOrderNumber}`);
        
      } catch (error) {
        results.failedCount++;
        const errorMsg = `SO ${i + 1} (${soData.salesOrderNumber || 'N/A'}): ${error.message}`;
        results.errors.push(errorMsg);
        console.log(`   ? Failed to import: ${errorMsg}`);
      }
    }
    
    console.log(`\n?? Bulk import completed:`);
    console.log(`   ? Success: ${results.successCount}`);
    console.log(`   ? Failed: ${results.failedCount}`);
    
    res.status(200).json({
      success: true,
      message: `Bulk import completed. ${results.successCount} sales orders imported, ${results.failedCount} failed.`,
      data: results,
    });
    
  } catch (error) {
    console.error('? Error in bulk import:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process bulk import',
      error: error.message,
    });
  }
});

// PUT /api/sales-orders/:id - Update sales order
router.put('/:id', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  ...salesOrderValidationRules,
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    if (!salesOrder.canEdit()) {
      return res.status(400).json({ 
        success: false, 
        message: 'Cannot edit invoiced, closed, cancelled, or void sales orders' 
      });
    }
    
    const totals = calculateSalesOrderTotals(
      req.body.items,
      req.body.tdsRate || 0,
      req.body.tcsRate || 0,
      req.body.gstRate || 18
    );
    
    Object.assign(salesOrder, req.body, totals);
    salesOrder.updatedBy = req.user.userId;
    salesOrder.pdfPath = null; // Force PDF regeneration on edit
    
    await salesOrder.save();
    
    res.json({
      success: true,
      message: 'Sales order updated successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error updating sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to update sales order', 
      error: error.message 
    });
  }
});

// GET /api/sales-orders/:id/email-preview
// GET /api/sales-orders/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const so = await SalesOrder.findOne({ _id: req.params.id, ...req.orgFilter });
    if (!so) return res.status(404).json({ success: false, error: 'Sales order not found' });
    const { getEffectiveOrgData } = require('./branches');
    const db = mongoose.connection.db;
    const org = db ? await getEffectiveOrgData(req.user?.orgId, req.branchIds?.length === 1 ? req.branchIds[0] : null, db) : null;
    const orgName  = org?.orgName    || '';
    const orgGST   = org?.gstNumber  || '';
    const orgPhone = org?.phone      || '';
    const orgEmail = org?.email      || '';
    const dateStr = new Date(so.salesOrderDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const shipDateStr = so.expectedShipmentDate
      ? new Date(so.expectedShipmentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })
      : null;
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Sales Order ${so.salesOrderNumber}</title>
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
    <h1>Sales Order</h1>
    <p>BILLING DOCUMENT</p>
    <div class="inv-num">${so.salesOrderNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${so.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      Please find attached sales order <strong>${so.salesOrderNumber}</strong> for your reference.
    </p>
    <div class="section-title">Order Details</div>
    <table class="detail">
      <tr><td>SO Number</td>     <td>${so.salesOrderNumber}</td></tr>
      <tr><td>Date</td>          <td>${dateStr}</td></tr>
      <tr><td>Payment Terms</td> <td>${so.paymentTerms || 'Net 30'}</td></tr>
      <tr><td>Status</td>        <td>${so.status}</td></tr>
      ${shipDateStr ? `<tr><td>Expected Shipment</td><td>${shipDateStr}</td></tr>` : ''}
      ${so.referenceNumber ? `<tr><td>Reference #</td><td>${so.referenceNumber}</td></tr>` : ''}
    </table>
    <div class="section-title">Amount Summary</div>
    <table class="detail">
      <tr><td>Subtotal</td><td>Rs.${(so.subTotal || 0).toFixed(2)}</td></tr>
      ${so.cgst > 0 ? `<tr><td>CGST</td><td>Rs.${so.cgst.toFixed(2)}</td></tr>` : ''}
      ${so.sgst > 0 ? `<tr><td>SGST</td><td>Rs.${so.sgst.toFixed(2)}</td></tr>` : ''}
      ${so.igst > 0 ? `<tr><td>IGST</td><td>Rs.${so.igst.toFixed(2)}</td></tr>` : ''}
      <tr class="total-row"><td>Total Amount</td><td>Rs.${(so.totalAmount || 0).toFixed(2)}</td></tr>
    </table>
    ${so.customerNotes ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${so.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The sales order PDF is attached to this email for your records.<br>
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
    res.json({ success: true, data: { subject: `Sales Order ${so.salesOrderNumber} � Rs.${(so.totalAmount || 0).toFixed(2)}`, html, to: so.customerEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview � save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const so = await SalesOrder.findOne({ _id: req.params.id, ...req.orgFilter });
    if (!so) return res.status(404).json({ success: false, message: 'Sales order not found' });
    if (to !== undefined)      so.set('customEmailTo',      to);
    if (subject !== undefined) so.set('customEmailSubject', subject);
    if (html !== undefined)    so.set('customEmailHtml',    html);
    await so.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/sales-orders/:id - Delete sales order
router.delete('/:id', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    await salesOrder.deleteOne();
    
    res.json({
      success: true,
      message: 'Sales order deleted successfully',
    });
  } catch (error) {
    console.error('Error deleting sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to delete sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/:id/send - Send sales order via email
router.post('/:id/send', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      orgId: orgId,
      ...(req.branchFilter || {}),
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    if (!salesOrder.customerEmail) {
      return res.status(400).json({ 
        success: false, 
        message: 'Customer email is required to send sales order' 
      });
    }
    
    // Generate PDF
    const pdfInfo = await generateSalesOrderPDF(salesOrder, orgId, salesOrder.branchId || null);
    const pdfBuffer = fs.readFileSync(pdfInfo.filepath);

    // Use custom email content if the user edited it in the preview dialog
    const customTo      = salesOrder.customEmailTo;
    const customSubject = salesOrder.customEmailSubject;
    const customHtml    = salesOrder.customEmailHtml;
    const sendTo        = customTo || salesOrder.customerEmail;

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
        subject: customSubject || `Sales Order ${salesOrder.salesOrderNumber}`,
        html: customHtml,
        attachments: [{ filename: `${salesOrder.salesOrderNumber}.pdf`, path: pdfInfo.filepath }],
      });
    } else {
      // Send email
      await sendSalesOrderEmail(salesOrder, pdfBuffer, orgId, salesOrder.branchId || null);
    }
    
    // Update status
    if (salesOrder.status === 'DRAFT') {
      salesOrder.status = 'OPEN';
    }
    
    salesOrder.emailsSent.push({
      sentTo: sendTo,
      sentAt: new Date(),
      emailType: 'sales_order',
    });
    
    salesOrder.pdfPath = pdfInfo.filepath;
    salesOrder.pdfGeneratedAt = new Date();
    
    await salesOrder.save();
    
    res.json({
      success: true,
      message: 'Sales order sent successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error sending sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to send sales order', 
      error: error.message 
    });
  }
});

// PATCH /api/sales-orders/:id/mark-as-sent - Mark as sent without sending email
router.patch('/:id/mark-as-sent', async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({ _id: req.params.id, orgId: req.user?.orgId, ...(req.branchFilter || {}) });
    if (!salesOrder) return res.status(404).json({ success: false, message: 'Sales order not found' });
    if (salesOrder.status === 'DRAFT') salesOrder.status = 'OPEN';
    salesOrder.emailsSent.push({ sentTo: salesOrder.customerEmail || '', sentAt: new Date(), emailType: 'sales_order' });
    await salesOrder.save();
    res.json({ success: true, message: 'Sales order marked as sent', data: salesOrder });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Failed to mark as sent', error: error.message });
  }
});

// GET /api/sales-orders/:id/pdf - Preview/download sales order PDF (used by document_preview_buttons)
router.get('/:id/pdf', async (req, res) => {
  if (!req.user && req.query.token) {
    try {
      const jwt = require('jsonwebtoken');
      req.user  = jwt.verify(req.query.token, process.env.FINANCE_JWT_SECRET || process.env.JWT_SECRET);
    } catch (e) { return res.status(401).json({ success: false, message: 'Invalid token' }); }
  }
  // Set branchFilter from query param (used when opening PDF via direct URL)
  if (!req.branchFilter) {
    const branchIds = req.query.branchIds;
    if (branchIds && branchIds.trim() !== '' && branchIds.trim() !== 'ALL') {
      const ids = branchIds.split(',').map(s => s.trim()).filter(Boolean);
      req.branchFilter = ids.length ? { branchId: { $in: ids } } : {};
    } else {
      req.branchFilter = {};
    }
  }
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    if (!salesOrder) return res.status(404).json({ success: false, message: 'Sales order not found' });
    const pdfInfo = await generateSalesOrderPDF(salesOrder, req.user?.orgId, salesOrder.branchId || null);
    salesOrder.pdfPath        = pdfInfo.filepath;
    salesOrder.pdfGeneratedAt = new Date();
    await salesOrder.save();
    res.download(pdfInfo.filepath, `${salesOrder.salesOrderNumber}.pdf`);
  } catch (error) {
    console.error('Error generating sales order PDF:', error);
    res.status(500).json({ success: false, message: 'Failed to generate PDF', error: error.message });
  }
});

// GET /api/sales-orders/:id/download - Download PDF
router.get('/:id/download', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    // Generate PDF
    if (!salesOrder.pdfPath || !fs.existsSync(salesOrder.pdfPath)) {
      const pdfInfo = await generateSalesOrderPDF(salesOrder, req.user?.orgId, salesOrder.branchId || null);
      salesOrder.pdfPath = pdfInfo.filepath;
      salesOrder.pdfGeneratedAt = new Date();
      await salesOrder.save();
    }
    
    res.download(salesOrder.pdfPath, `${salesOrder.salesOrderNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to download PDF', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/:id/confirm - Confirm sales order
router.post('/:id/confirm', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });
    
    if (!salesOrder) {
      return res.status(404).json({ 
        success: false, 
        message: 'Sales order not found' 
      });
    }
    
    salesOrder.status = 'CONFIRMED';
    await salesOrder.save();
    
    res.json({
      success: true,
      message: 'Sales order confirmed successfully',
      data: salesOrder,
    });
  } catch (error) {
    console.error('Error confirming sales order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to confirm sales order', 
      error: error.message 
    });
  }
});

// POST /api/sales-orders/:id/convert-to-invoice - Convert to invoice
router.post('/:id/convert-to-invoice', [
  param('id').isMongoId().withMessage('Invalid sales order ID'),
  validateRequest,
], async (req, res) => {
  try {
    const salesOrder = await SalesOrder.findOne({
      _id: req.params.id,
      ...req.orgFilter,
      ...(req.branchFilter || {}),
    });

    if (!salesOrder) {
      return res.status(404).json({
        success: false,
        message: 'Sales order not found'
      });
    }

    if (!salesOrder.canConvert()) {
      return res.status(400).json({
        success: false,
        message: 'Only confirmed, open, packed, or shipped sales orders can be converted to invoices'
      });
    }

    const orgId = req.user?.orgId || null;
    const Invoice = mongoose.model('Invoice');

    const { generateNumber } = require('../utils/numberGenerator');
    const invoiceNumber = await generateNumber(Invoice, 'invoiceNumber', 'INV', orgId, req.branchIds?.length > 0 ? req.branchIds[0] : null);

    const invoiceDate = new Date();
    const dueDate = new Date(invoiceDate);

    switch (salesOrder.paymentTerms) {
      case 'Due on Receipt': break;
      case 'Net 15': dueDate.setDate(dueDate.getDate() + 15); break;
      case 'Net 30': dueDate.setDate(dueDate.getDate() + 30); break;
      case 'Net 45': dueDate.setDate(dueDate.getDate() + 45); break;
      case 'Net 60': dueDate.setDate(dueDate.getDate() + 60); break;
      default: dueDate.setDate(dueDate.getDate() + 30);
    }

    // ? Convert customerId safely to string to avoid ObjectId cast error
    const customerId = salesOrder.customerId
      ? salesOrder.customerId.toString()
      : req.user.userId;

    const invoice = new Invoice({
      orgId,
      branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
      invoiceNumber,
      customerId,                          // ? always a string now
      customerName:        salesOrder.customerName,
      customerEmail:       salesOrder.customerEmail  || '',
      customerPhone:       salesOrder.customerPhone  || '',
      orderNumber:         salesOrder.salesOrderNumber,
      invoiceDate,
      terms:               salesOrder.paymentTerms   || 'Net 30',
      dueDate,
      salesperson:         salesOrder.salesperson    || '',
      subject:             salesOrder.subject        || '',
      items: salesOrder.items.map(item => ({
        itemDetails:  item.itemDetails,
        quantity:     item.quantity,
        rate:         item.rate,
        discount:     item.discount     || 0,
        discountType: item.discountType || 'percentage',
        amount:       item.amount,
      })),
      customerNotes:      salesOrder.customerNotes      || '',
      termsAndConditions: salesOrder.termsAndConditions || '',
      subTotal:           salesOrder.subTotal,
      tdsRate:            salesOrder.tdsRate   || 0,
      tdsAmount:          salesOrder.tdsAmount || 0,
      tcsRate:            salesOrder.tcsRate   || 0,
      tcsAmount:          salesOrder.tcsAmount || 0,
      gstRate:            salesOrder.gstRate   || 18,
      cgst:               salesOrder.cgst      || 0,
      sgst:               salesOrder.sgst      || 0,
      igst:               salesOrder.igst      || 0,
      totalAmount:        salesOrder.totalAmount,
      status:             'DRAFT',
      amountPaid:         0,
      amountDue:          salesOrder.totalAmount,
      createdBy:          req.user.userId,
    });

    await invoice.save();

    // ? COA Posting
    try {
      const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

      const currentOrgId = req.user?.orgId || null;
      const [arId, salesId, taxId] = await Promise.all([
        ChartOfAccount.findOne({ accountName: 'Accounts Receivable', isSystemAccount: true, orgId: currentOrgId })
          .select('_id').lean().then(a => a?._id),
        ChartOfAccount.findOne({ accountName: 'Sales', isSystemAccount: true, orgId: currentOrgId })
          .select('_id').lean().then(a => a?._id),
        ChartOfAccount.findOne({ accountName: 'Tax Payable', isSystemAccount: true, orgId: currentOrgId })
          .select('_id').lean().then(a => a?._id),
      ]);

      const txnDate = new Date(invoice.invoiceDate);
      const gst = (invoice.cgst || 0) + (invoice.sgst || 0);

      if (arId) await postTransactionToCOA({
        accountId:       arId,
        orgId:           currentOrgId,
        branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
        date:            txnDate,
        description:     `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit:           invoice.totalAmount,
        credit:          0,
      });

      if (salesId) await postTransactionToCOA({
        accountId:       salesId,
        orgId:           currentOrgId,
        branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
        date:            txnDate,
        description:     `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit:           0,
        credit:          invoice.subTotal,
      });

      if (taxId && gst > 0) await postTransactionToCOA({
        accountId:       taxId,
        orgId:           currentOrgId,
        branchId:        req.branchIds?.length > 0 ? req.branchIds[0] : null,
        date:            txnDate,
        description:     `GST on Invoice ${invoice.invoiceNumber}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit:           0,
        credit:          gst,
      });

      console.log(`? COA posted for SO converted invoice: ${invoice.invoiceNumber}`);
    } catch (coaErr) {
      console.error('?? COA post error (SO convert):', coaErr.message);
    }

    // Update sales order
    salesOrder.status                   = 'INVOICED';
    salesOrder.convertedToInvoice       = true;
    salesOrder.convertedToInvoiceId     = invoice._id.toString();
    salesOrder.convertedToInvoiceNumber = invoiceNumber;
    salesOrder.convertedDate            = new Date();
    await salesOrder.save();

    console.log(`? Sales order ${salesOrder.salesOrderNumber} converted to invoice ${invoiceNumber}`);

    res.json({
      success: true,
      message: 'Sales order converted to invoice successfully',
      data: {
        salesOrder,
        invoice,
      },
    });
  } catch (error) {
    console.error('? Error converting sales order to invoice:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to convert sales order to invoice',
      error: error.message
    });
  }
});

module.exports = router;