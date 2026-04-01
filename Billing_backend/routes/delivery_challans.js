// ============================================================================
// DELIVERY CHALLAN SYSTEM - COMPLETE BACKEND API
// ============================================================================
// File: backend/routes/delivery_challans.js
// Features:
// ? Complete CRUD operations
// ? Status workflow management (Draft ? Open ? Delivered ? Invoiced/Returned)
// ? Convert to Invoice (automatic)
// ? Partial invoicing & returns tracking
// ? PDF generation
// ? Email sending
// ? Quantity tracking (dispatched, delivered, invoiced, returned)
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
  if (!CACHED_LOGO_PATH) CACHED_LOGO_PATH = findLogoPath();
  return CACHED_LOGO_PATH;
}

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const deliveryChallanSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  challanNumber: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  customerId: {
    type: String,
    required: true
  },
  customerName: {
    type: String,
    required: true
  },
  customerEmail: String,
  customerPhone: String,
  
  // Address
  deliveryAddress: {
    street: String,
    city: String,
    state: String,
    pincode: String,
    country: { type: String, default: 'India' }
  },
  
  // Dates
  challanDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  expectedDeliveryDate: Date,
  actualDeliveryDate: Date,
  
  // References
  referenceNumber: String,
  orderNumber: String,
  
  // Purpose
  purpose: {
    type: String,
    enum: [
      'Supply on Approval',
      'Job Work',
      'Stock Transfer',
      'Exhibition/Display',
      'Replacement/Repair',
      'Sales',
      'Other'
    ],
    default: 'Sales'
  },
  
  // Transport Details
  transportMode: {
    type: String,
    enum: ['Road', 'Rail', 'Air', 'Ship'],
    default: 'Road'
  },
  vehicleNumber: String,
  driverName: String,
  driverPhone: String,
  transporterName: String,
  lrNumber: String, // Lorry Receipt Number
  
  // Items with quantity tracking
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
    unit: {
      type: String,
      default: 'Pcs'
    },
    hsnCode: String,
    notes: String,
    
    // Quantity tracking
    quantityDispatched: {
      type: Number,
      default: 0
    },
    quantityDelivered: {
      type: Number,
      default: 0
    },
    quantityInvoiced: {
      type: Number,
      default: 0
    },
    quantityReturned: {
      type: Number,
      default: 0
    }
  }],
  
  // Notes
  customerNotes: String,
  internalNotes: String,
  termsAndConditions: String,
  
  // Status tracking
  status: {
    type: String,
    enum: [
      'DRAFT',
      'OPEN',
      'DELIVERED',
      'INVOICED',
      'PARTIALLY_INVOICED',
      'RETURNED',
      'PARTIALLY_RETURNED',
      'CANCELLED'
    ],
    default: 'DRAFT',
    index: true
  },
  
  // Linked documents
  linkedInvoices: [{
    invoiceId: String,
    invoiceNumber: String,
    invoicedDate: Date,
    amount: Number
  }],
  
  // PDF & Email
  pdfPath: String,
  pdfGeneratedAt: Date,
  emailsSent: [{
    sentTo: String,
    sentAt: Date,
    emailType: String
  }],
  
  // Audit
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
deliveryChallanSchema.pre('save', function() {
  // Initialize quantity tracking for items
  this.items.forEach(item => {
    if (item.quantityDispatched === 0 && this.status !== 'DRAFT') {
      item.quantityDispatched = item.quantity;
    }
  });

  // Auto-update status based on quantities
  this._updateStatusBasedOnQuantities();
});

// Method to update status based on quantities
deliveryChallanSchema.methods._updateStatusBasedOnQuantities = function() {
  try {
    if (this.status === 'DRAFT' || this.status === 'CANCELLED') {
      return;
    }

    let totalQuantity = 0;
    let totalInvoiced = 0;
    let totalReturned = 0;

    this.items.forEach(item => {
      totalQuantity  += (item.quantity         || 0);
      totalInvoiced  += (item.quantityInvoiced || 0);
      totalReturned  += (item.quantityReturned || 0);
    });

    if (totalQuantity === 0) return;

    if (totalInvoiced > 0 && totalInvoiced < totalQuantity) {
      this.status = 'PARTIALLY_INVOICED';
    } else if (totalInvoiced >= totalQuantity) {
      this.status = 'INVOICED';
    } else if (totalReturned > 0 && totalReturned < totalQuantity) {
      this.status = 'PARTIALLY_RETURNED';
    } else if (totalReturned >= totalQuantity) {
      this.status = 'RETURNED';
    }
  } catch (err) {
    console.error('?? Error in _updateStatusBasedOnQuantities:', err.message);
  }
};

const DeliveryChallan = mongoose.models.DeliveryChallan || mongoose.model('DeliveryChallan', deliveryChallanSchema);

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

async function generateChallanNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(DeliveryChallan, 'challanNumber', 'DC', orgId);
}

// ============================================================================
// PDF GENERATION
// ============================================================================

async function generateChallanPDF(challan, orgId) {
  // Fetch org details
  let orgName    = 'Your Company';
  let orgGST     = '';
  let orgAddr    = '';
  let orgEmail   = '';
  let orgPhone   = '';
  try {
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const orgData = await OrgModel.findOne({ orgId }).lean();
    if (orgData) {
      orgName  = orgData.orgName    || orgName;
      orgGST   = orgData.gstNumber  || '';
      orgAddr  = orgData.address    || '';
      orgEmail = orgData.email      || '';
      orgPhone = orgData.phone      || '';
    }
  } catch (_) {}

  return new Promise((resolve, reject) => {
    try {
      console.log('?? Starting PDF generation for challan:', challan.challanNumber);

      const uploadsDir = path.join(__dirname, '..', 'uploads', 'challans');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

      const filename = `challan-${challan.challanNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);

      const doc    = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      const pageW    = 515;
      const logoPath = getLogoPath(orgId);

      // -- Header bar ------------------------------------------------------
      doc.rect(40, 30, pageW, 90).fill('#0f1e3d');

      let logoLoaded = false;
      if (logoPath) {
        try {
          doc.image(logoPath, 44, 35, { width: 75, height: 60, fit: [75, 60] });
          logoLoaded = true;
        } catch (e) { console.warn('Logo load failed:', e.message); }
      }

      const textX = logoLoaded ? 126 : 50;
      doc.fontSize(12).fillColor('#ffffff').font('Helvetica-Bold')
         .text(orgName.toUpperCase(), textX, 40, { width: 200 });
      doc.fontSize(7).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('BILLING & FINANCE', textX, 56, { width: 200 });

      const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)');
      let cY = 68;
      contactLines.forEach(line => { doc.text(line, textX, cY, { width: 240 }); cY += 9; });

      doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').font('Helvetica-Bold')
         .text('DELIVERY CHALLAN', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(18).fillColor('#ffffff').font('Helvetica-Bold')
         .text(challan.challanNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.8)').font('Helvetica')
         .text(`Date: ${new Date(challan.challanDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`,
               380, 76, { width: 170, align: 'right' });
      doc.fontSize(7).fillColor('#ffffff').font('Helvetica-Bold')
         .text(`Status: ${challan.status.replace(/_/g, ' ')}`, 380, 92, { width: 170, align: 'right' });

      // -- Meta boxes ------------------------------------------------------
      const metaY    = 132;
      const metaBoxW = pageW / 2;

      const deliveryAddrParts = challan.deliveryAddress
        ? [challan.deliveryAddress.street, challan.deliveryAddress.city,
           challan.deliveryAddress.state, challan.deliveryAddress.pincode].filter(Boolean).join(', ')
        : '';

      const metas = [
        {
          label: 'Deliver To',
          val:   challan.customerName || 'N/A',
          sub:   [deliveryAddrParts, challan.customerEmail, challan.customerPhone].filter(Boolean).join(' | ')
        },
        {
          label: 'Challan Details',
          val:   `Purpose: ${challan.purpose || 'Sales'}`,
          sub:   `Ref: ${challan.referenceNumber || 'N/A'}${challan.vehicleNumber ? ' | Vehicle: ' + challan.vehicleNumber : ''}`
        },
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

      // -- Items table ------------------------------------------------------
      const tableTop = metaY + 58;
      doc.rect(40, tableTop, pageW, 22).fill('#0f1e3d');
      doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
      doc.text('#',           48,  tableTop + 7, { width: 20 });
      doc.text('DESCRIPTION', 72,  tableTop + 7, { width: 200 });
      doc.text('QTY',         275, tableTop + 7, { width: 60,  align: 'center' });
      doc.text('UNIT',        340, tableTop + 7, { width: 80,  align: 'center' });
      doc.text('HSN',         420, tableTop + 7, { width: 90,  align: 'right' });

      let rowY = tableTop + 22;
      challan.items.forEach((item, idx) => {
        const rowH = 24;
        doc.rect(40, rowY, pageW, rowH).fill(idx % 2 === 0 ? '#ffffff' : '#f7f9fc');
        doc.rect(40, rowY, pageW, rowH).lineWidth(1.5).strokeColor('#000000').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica-Bold')
           .text(String(idx + 1), 48, rowY + 8, { width: 20 });
        doc.font('Helvetica')
           .text(item.itemDetails || 'N/A', 72, rowY + 8, { width: 200, ellipsis: true });
        doc.text(String(item.quantity || 0), 275, rowY + 8, { width: 60, align: 'center' });
        doc.text(item.unit || 'Pcs',         340, rowY + 8, { width: 80, align: 'center' });
        doc.text(item.hsnCode || '-',        420, rowY + 8, { width: 90, align: 'right' });
        rowY += rowH;
      });

      // -- Total Quantity box -----------------------------------------------
      const totalsX = 355;
      const totalsW = 200;
      const totalQty = challan.items.reduce((sum, item) => sum + (item.quantity || 0), 0);

      rowY += 10;
      doc.rect(totalsX, rowY, totalsW, 24).fill('#0f1e3d');
      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('Total Quantity', totalsX + 6, rowY + 7);
      doc.fontSize(13).fillColor('#ffffff').font('Helvetica-Bold')
         .text(String(totalQty), totalsX, rowY + 5, { width: totalsW - 6, align: 'right' });
      rowY += 32;

      // -- Transport details ------------------------------------------------
      if (challan.transportMode || challan.vehicleNumber || challan.transporterName) {
        const tY = rowY + 10;
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('TRANSPORT DETAILS', 40, tY, { characterSpacing: 0.8 });
        doc.moveTo(40, tY + 9).lineTo(555, tY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        let ty2 = tY + 14;
        const tLine = (label, val) => {
          doc.fontSize(7.5).fillColor('#5e6e84').font('Helvetica-Bold')
             .text(`${label}:`, 40, ty2, { continued: true });
          doc.fillColor('#000000').font('Helvetica').text(` ${val}`);
          ty2 += 11;
        };
        if (challan.transportMode)    tLine('Mode',        challan.transportMode);
        if (challan.vehicleNumber)    tLine('Vehicle',     challan.vehicleNumber);
        if (challan.transporterName)  tLine('Transporter', challan.transporterName);
        if (challan.driverName)       tLine('Driver',      challan.driverName);
        if (challan.lrNumber)         tLine('LR Number',   challan.lrNumber);
        rowY = ty2 + 8;
      }

      // -- Notes -------------------------------------------------------------
      if (challan.customerNotes) {
        const nY = rowY + 10;
        doc.fontSize(7.5).fillColor('#8a9ab5').font('Helvetica-Bold')
           .text('NOTES', 40, nY, { characterSpacing: 0.8 });
        doc.moveTo(40, nY + 9).lineTo(555, nY + 9)
           .lineWidth(0.5).strokeColor('#dde4ef').stroke();
        doc.fontSize(8).fillColor('#000000').font('Helvetica')
           .text(challan.customerNotes, 40, nY + 14, { width: pageW });
        rowY = nY + 30;
      }

      // -- Terms -------------------------------------------------------------
      if (challan.termsAndConditions) {
        const tcY = 660;
        doc.rect(40, tcY, pageW, 14).fill('#f9f9f9').stroke();
        doc.fontSize(7.5).fillColor('#000000').font('Helvetica-Bold')
           .text('TERMS & CONDITIONS', 48, tcY + 3, { characterSpacing: 0.8 });
        doc.fontSize(7).fillColor('#000000').font('Helvetica')
           .text(challan.termsAndConditions, 48, tcY + 16, { width: pageW - 16 });
      }

      // -- Footer ------------------------------------------------------------
      const footY = 760;
      doc.moveTo(40, footY).lineTo(555, footY)
         .lineWidth(1.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName} � ${orgGST ? 'GSTIN: ' + orgGST + ' � ' : ''}${challan.challanNumber}`,
               40, footY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`,
               40, footY + 6, { width: pageW, align: 'right' });

      doc.end();

      stream.on('finish', () => {
        console.log(`? PDF generated: ${filename}`);
        resolve({ filename, filepath, relativePath: `/uploads/challans/${filename}` });
      });
      stream.on('error', reject);

    } catch (error) {
      console.error('? PDF generation error:', error);
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

async function sendChallanEmail(challan, pdfPath, orgId) {
  console.log('?? Preparing to send challan email to:', challan.customerEmail);

  let orgName  = 'Billing Team';
  let orgGST   = '';
  let orgEmail = '';
  let orgPhone = '';
  let orgAddr  = '';
  try {
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const orgData = await OrgModel.findOne({ orgId }).lean();
    if (orgData) {
      orgName  = orgData.orgName    || orgName;
      orgGST   = orgData.gstNumber  || '';
      orgEmail = orgData.email      || '';
      orgPhone = orgData.phone      || '';
      orgAddr  = orgData.address    || '';
    }
  } catch (_) {}

  const dateStr = new Date(challan.challanDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });

  const emailHtml = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:Arial,sans-serif;font-size:13px;color:#222;background:#f4f4f4}
.wrapper{max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd}
.header{background:#0f1e3d;padding:24px 32px}
.header h1{color:#fff;font-size:20px;font-weight:bold}
.header .num{color:#fff;font-size:14px;font-weight:bold;margin-top:8px}
.body{padding:28px 32px}
.st{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px}
table.d{width:100%;border-collapse:collapse;font-size:13px}
table.d td{padding:7px 0;border-bottom:1px dashed #e8e8e8;vertical-align:top}
table.d td:first-child{color:#555;width:160px}
table.d td:last-child{font-weight:600;color:#111;text-align:right}
.info-box{background:#f8f9fa;border-left:3px solid #0f1e3d;padding:12px 16px;margin:8px 0;font-size:12px;line-height:1.8}
.footer{background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7}
</style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>${orgName}</h1>
    <div class="num">${challan.challanNumber}</div>
  </div>
  <div class="body">
    <p style="font-size:14px;margin-bottom:18px;">Dear ${challan.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      This is to inform you that we have dispatched goods as per delivery challan <strong>${challan.challanNumber}</strong>.
    </p>

    <div class="st">Challan Details</div>
    <table class="d">
      <tr><td>Challan Number</td> <td>${challan.challanNumber}</td></tr>
      <tr><td>Date</td>           <td>${dateStr}</td></tr>
      <tr><td>Purpose</td>        <td>${challan.purpose || 'Sales'}</td></tr>
      <tr><td>Status</td>         <td>${challan.status.replace(/_/g, ' ')}</td></tr>
      ${challan.expectedDeliveryDate ? `<tr><td>Expected Delivery</td><td>${new Date(challan.expectedDeliveryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}</td></tr>` : ''}
      ${challan.referenceNumber ? `<tr><td>Reference</td><td>${challan.referenceNumber}</td></tr>` : ''}
    </table>

    <div class="st">Items Summary</div>
    <table class="d">
      <tr><td>Total Items</td>    <td>${challan.items.length}</td></tr>
      <tr><td>Total Quantity</td> <td>${challan.items.reduce((sum, item) => sum + item.quantity, 0)}</td></tr>
    </table>

    ${challan.transportMode || challan.vehicleNumber ? `
    <div class="st">Transport Details</div>
    <div class="info-box">
      ${challan.transportMode   ? `<strong>Mode:</strong> ${challan.transportMode}<br>` : ''}
      ${challan.vehicleNumber   ? `<strong>Vehicle:</strong> ${challan.vehicleNumber}<br>` : ''}
      ${challan.transporterName ? `<strong>Transporter:</strong> ${challan.transporterName}<br>` : ''}
      ${challan.driverName      ? `<strong>Driver:</strong> ${challan.driverName}<br>` : ''}
    </div>` : ''}

    ${challan.customerNotes ? `
    <div class="st">Notes</div>
    <p style="font-size:12px;line-height:1.7;color:#444;">${challan.customerNotes}</p>` : ''}

    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The delivery challan PDF is attached for your records.<br>
      Please verify the items upon delivery and contact us immediately if there are any discrepancies.
    </p>
  </div>
  <div class="footer">
    <strong>${orgName}</strong><br>
    ${orgGST   ? `GST: ${orgGST} &nbsp;|&nbsp; ` : ''}
    ${orgPhone ? `Ph: ${orgPhone} &nbsp;|&nbsp; ` : ''}
    ${orgEmail || ''}
  </div>
</div>
</body>
</html>`;

  const mailOptions = {
    from: `"${orgName} - Dispatch" <${process.env.SMTP_USER}>`,
    to: challan.customerEmail,
    subject: `Delivery Challan ${challan.challanNumber} - ${orgName}`,
    html: emailHtml,
    attachments: [{ filename: `Challan-${challan.challanNumber}.pdf`, path: pdfPath }]
  };

  const result = await emailTransporter.sendMail(mailOptions);
  console.log('   ? Email sent! Message ID:', result.messageId);
  return result;
}

// ============================================================================
// API ROUTES
// ============================================================================

// Get all delivery challans with filters and pagination
router.get('/', async (req, res) => {
  try {
    const { status, customerId, fromDate, toDate, page = 1, limit = 20 } = req.query;
    
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    if (fromDate || toDate) {
      query.challanDate = {};
      if (fromDate) query.challanDate.$gte = new Date(fromDate);
      if (toDate) query.challanDate.$lte = new Date(toDate);
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const challans = await DeliveryChallan.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await DeliveryChallan.countDocuments(query);
    
    res.json({
      success: true,
      data: challans,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching delivery challans:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get statistics
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const stats = await DeliveryChallan.aggregate([
      { $match: orgFilter },
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      }
    ]);
    
    const overallStats = {
      totalChallans: 0,
      byStatus: {}
    };
    
    stats.forEach(stat => {
      overallStats.totalChallans += stat.count;
      overallStats.byStatus[stat._id] = stat.count;
    });
    
    res.json({ success: true, data: overallStats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get single delivery challan
router.get('/:id', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    res.json({ success: true, data: challan });
  } catch (error) {
    console.error('Error fetching delivery challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Create new delivery challan
router.post('/', async (req, res) => {
  try {
    const challanData = req.body;
    
    // Ensure customerId is a string
    if (!challanData.customerId) {
      challanData.customerId = `CUST-${Date.now()}`;
    }
    
    // Generate challan number if not provided
    if (!challanData.challanNumber) {
      challanData.challanNumber = await generateChallanNumber(req.user?.orgId || null);
    }
    
    // Set created by
    challanData.createdBy = req.user?.email || req.user?.uid || 'system';
    challanData.orgId = req.user?.orgId || null;
    
    const challan = new DeliveryChallan(challanData);
    await challan.save();
    
    console.log(`? Delivery challan created: ${challan.challanNumber}`);
    
    res.status(201).json({
      success: true,
      message: 'Delivery challan created successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error creating delivery challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Update delivery challan
router.put('/:id', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status === 'INVOICED') {
      return res.status(400).json({
        success: false,
        error: 'Cannot edit fully invoiced challans'
      });
    }
    
    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    Object.assign(challan, updates);
    await challan.save();
    
    console.log(`? Delivery challan updated: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan updated successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error updating delivery challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Mark as Open (dispatch)
router.post('/:id/dispatch', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft challans can be dispatched'
      });
    }
    
    challan.status = 'OPEN';
    challan.items.forEach(item => {
      item.quantityDispatched = item.quantity;
    });
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`? Delivery challan dispatched: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan marked as dispatched',
      data: challan
    });
  } catch (error) {
    console.error('Error dispatching challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Mark as Delivered
router.post('/:id/delivered', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status !== 'OPEN') {
      return res.status(400).json({
        success: false,
        error: 'Only dispatched challans can be marked as delivered'
      });
    }
    
    challan.status = 'DELIVERED';
    challan.actualDeliveryDate = new Date();
    challan.items.forEach(item => {
      item.quantityDelivered = item.quantityDispatched;
    });
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`? Delivery challan marked as delivered: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan marked as delivered',
      data: challan
    });
  } catch (error) {
    console.error('Error marking as delivered:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Convert to Invoice (AUTOMATIC)
router.post('/:id/convert-to-invoice', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });

    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }

    if (challan.status !== 'DELIVERED' && challan.status !== 'PARTIALLY_INVOICED') {
      return res.status(400).json({
        success: false,
        error: 'Only delivered challans can be converted to invoice'
      });
    }

    // ? Get Invoice model
    const Invoice = mongoose.models.Invoice;
    if (!Invoice) {
      return res.status(500).json({
        success: false,
        error: 'Invoice model not loaded. Ensure invoices.js is loaded before delivery_challans.js'
      });
    }

    // ? Generate real invoice number
    const { generateNumber } = require('../utils/numberGenerator');
    const invoiceNumber = await generateNumber(Invoice, 'invoiceNumber', 'INV', req.user?.orgId || null);

    // ? Calculate due date (Net 30)
    const invoiceDate = new Date();
    const dueDate     = new Date(invoiceDate);
    dueDate.setDate(dueDate.getDate() + 30);

    // Get quantities from request body (for partial invoicing)
    const { items: itemsToInvoice, createInvoice = true } = req.body;

    // ? Build invoice items
    const invoiceItems = [];
    let allItemsInvoiced = true;

    if (itemsToInvoice && Array.isArray(itemsToInvoice)) {
      // Partial invoicing � user specified which items + rates
      itemsToInvoice.forEach(invoiceItem => {
        const challanItem = challan.items.id(invoiceItem.itemId);
        if (challanItem) {
          const qtyToInvoice = invoiceItem.quantity || 0;
          const rate         = invoiceItem.rate     || 0;
          const discount     = invoiceItem.discount || 0;
          const discountType = invoiceItem.discountType || 'percentage';

          let amount = qtyToInvoice * rate;
          if (discount > 0) {
            amount = discountType === 'percentage'
              ? amount - (amount * discount / 100)
              : amount - discount;
          }

          invoiceItems.push({
            itemDetails:  challanItem.itemDetails,
            quantity:     qtyToInvoice,
            rate,
            discount,
            discountType,
            amount:       parseFloat(amount.toFixed(2)),
          });

          challanItem.quantityInvoiced += qtyToInvoice;

          if (challanItem.quantityInvoiced < challanItem.quantity) {
            allItemsInvoiced = false;
          }
        }
      });
    } else {
      // Full invoicing � use all remaining un-invoiced quantities
      challan.items.forEach(item => {
        const remainingQty = item.quantity - (item.quantityInvoiced || 0);

        if (remainingQty > 0) {
          invoiceItems.push({
            itemDetails:  item.itemDetails,
            quantity:     remainingQty,
            rate:         0,  // ?? No rate on challan � user edits invoice later
            discount:     0,
            discountType: 'percentage',
            amount:       0,
          });

          item.quantityInvoiced = item.quantity;
        }
      });
    }

    if (invoiceItems.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No items available to invoice'
      });
    }

    // ? Calculate totals
const subTotal = invoiceItems.reduce((sum, item) => sum + item.amount, 0);

// ? If all rates are 0, invoice is created as DRAFT with 0 amount
// User must edit invoice to add rates
if (subTotal === 0) {
  console.log(`?? Challan ${challan.challanNumber} � all item rates are 0. Invoice created as DRAFT, please add rates.`);
}
    const gstRate     = 18;
    const gstAmount   = (subTotal * gstRate) / 100;
    const cgst        = parseFloat((gstAmount / 2).toFixed(2));
    const sgst        = parseFloat((gstAmount / 2).toFixed(2));
    const totalAmount = parseFloat((subTotal + gstAmount).toFixed(2));

    // ? Convert customerId safely
    const customerId = challan.customerId
      ? challan.customerId.toString()
      : req.user.userId || 'unknown';

    // ? Create REAL invoice
    const invoice = new Invoice({
      invoiceNumber,
      orgId: req.user?.orgId || null,
      customerId,
      customerName:       challan.customerName,
      customerEmail:      challan.customerEmail  || '',
      customerPhone:      challan.customerPhone  || '',
      billingAddress:     challan.deliveryAddress,
      shippingAddress:    challan.deliveryAddress,
      orderNumber:        challan.referenceNumber || challan.challanNumber,
      invoiceDate,
      terms:              'Net 30',
      dueDate,
      items:              invoiceItems,
      customerNotes:      `Generated from Delivery Challan: ${challan.challanNumber}`,
      termsAndConditions: challan.termsAndConditions || '',
      subTotal,
      tdsRate:            0,
      tdsAmount:          0,
      tcsRate:            0,
      tcsAmount:          0,
      gstRate,
      cgst,
      sgst,
      igst:               0,
      totalAmount,
      status:             'DRAFT',
      amountPaid:         0,
      amountDue:          totalAmount,
      createdBy:          req.user?.email || req.user?.uid || 'system',
    });

    await invoice.save();
    console.log(`? Real invoice created from challan: ${invoiceNumber}`);

    // ? Update challan status
    challan._updateStatusBasedOnQuantities();

    // ? Link REAL invoice to challan
    challan.linkedInvoices.push({
      invoiceId:     invoice._id.toString(),
      invoiceNumber: invoiceNumber,
      invoicedDate:  new Date(),
      amount:        totalAmount,
    });

    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    await challan.save();

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
      const gst     = (invoice.cgst || 0) + (invoice.sgst || 0);

      // Debit Accounts Receivable
      if (arId) await postTransactionToCOA({
        accountId:       arId,
        orgId:           currentOrgId,
        date:            txnDate,
        description:     `Invoice ${invoiceNumber} from Challan ${challan.challanNumber} - ${challan.customerName}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoiceNumber,
        debit:           totalAmount,
        credit:          0,
      });

      // Credit Sales
      if (salesId) await postTransactionToCOA({
        accountId:       salesId,
        orgId:           currentOrgId,
        date:            txnDate,
        description:     `Invoice ${invoiceNumber} from Challan ${challan.challanNumber} - ${challan.customerName}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoiceNumber,
        debit:           0,
        credit:          subTotal,
      });

      // Credit Tax Payable
      if (taxId && gst > 0) await postTransactionToCOA({
        accountId:       taxId,
        orgId:           currentOrgId,
        date:            txnDate,
        description:     `GST on Invoice ${invoiceNumber}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoiceNumber,
        debit:           0,
        credit:          gst,
      });

      console.log(`? COA posted for challan converted invoice: ${invoiceNumber}`);
    } catch (coaErr) {
      console.error('?? COA post error (challan convert):', coaErr.message);
      // Non-critical � invoice already saved
    }

    console.log(`? Delivery challan ${challan.challanNumber} converted to invoice ${invoiceNumber}`);

    res.json({
      success: true,
      message: 'Delivery challan converted to invoice successfully',
      data: {
        challan,
        invoice,
      }
    });
  } catch (error) {
    console.error('Error converting challan to invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});


// Record Partial Return
router.post('/:id/partial-return', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    const { items: returnedItems } = req.body;
    
    if (!returnedItems || !Array.isArray(returnedItems)) {
      return res.status(400).json({
        success: false,
        error: 'Returned items data is required'
      });
    }
    
    // Update returned quantities
    returnedItems.forEach(returnItem => {
      const challanItem = challan.items.id(returnItem.itemId);
      if (challanItem) {
        challanItem.quantityReturned += returnItem.quantity || 0;
      }
    });
    
    // Update status
    challan._updateStatusBasedOnQuantities();
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`? Partial return recorded for: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Partial return recorded successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error recording partial return:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Mark as Returned (Full)
router.post('/:id/returned', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    challan.status = 'RETURNED';
    challan.items.forEach(item => {
      item.quantityReturned = item.quantity;
    });
    challan.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    await challan.save();
    
    console.log(`? Delivery challan marked as returned: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan marked as returned',
      data: challan
    });
  } catch (error) {
    console.error('Error marking as returned:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Send challan via email
router.post('/:id/send', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (!challan.customerEmail) {
      return res.status(400).json({
        success: false,
        error: 'Customer email is required to send challan'
      });
    }
    
    // Generate PDF if not exists
    let pdfInfo;
    if (!challan.pdfPath || !fs.existsSync(challan.pdfPath)) {
      pdfInfo = await generateChallanPDF(challan, req.user?.orgId);
      challan.pdfPath = pdfInfo.filepath;
      challan.pdfGeneratedAt = new Date();
    }

    // Use custom email content if the user edited it in the preview dialog
    const customTo      = challan.customEmailTo;
    const customSubject = challan.customEmailSubject;
    const customHtml    = challan.customEmailHtml;
    const sendTo        = customTo || challan.customerEmail;

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
        subject: customSubject || `Delivery Challan ${challan.challanNumber}`,
        html: customHtml,
        attachments: [{ filename: `Challan-${challan.challanNumber}.pdf`, path: challan.pdfPath }],
      });
    } else {
      // Send email
      await sendChallanEmail(challan, challan.pdfPath, req.user?.orgId);
    }
    
    // Update status if draft
    if (challan.status === 'DRAFT') {
      challan.status = 'OPEN';
      challan.items.forEach(item => {
        item.quantityDispatched = item.quantity;
      });
    }
    
    challan.emailsSent.push({
      sentTo: sendTo,
      sentAt: new Date(),
      emailType: 'delivery_challan'
    });
    
    await challan.save();
    
    console.log(`? Delivery challan sent: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan sent successfully',
      data: challan
    });
  } catch (error) {
    console.error('Error sending challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Download PDF
router.get('/:id/pdf', async (req, res) => {
  // Support token from query param (used by frontend blob-fetch for preview)
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
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    // Generate PDF if not exists
    if (!challan.pdfPath || !fs.existsSync(challan.pdfPath)) {
      const pdfInfo = await generateChallanPDF(challan, req.user?.orgId);
      challan.pdfPath = pdfInfo.filepath;
      challan.pdfGeneratedAt = new Date();
      await challan.save();
    }
    
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="Challan-${challan.challanNumber}.pdf"`);
    res.download(challan.pdfPath, `Challan-${challan.challanNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get download URL
router.get('/:id/download-url', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    // Generate PDF if not exists
    if (!challan.pdfPath || !fs.existsSync(challan.pdfPath)) {
      const pdfInfo = await generateChallanPDF(challan, req.user?.orgId);
      challan.pdfPath = pdfInfo.filepath;
      challan.pdfGeneratedAt = new Date();
      await challan.save();
    }
    
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    const downloadUrl = `${baseUrl}/uploads/challans/${path.basename(challan.pdfPath)}`;
    
    res.json({
      success: true,
      downloadUrl: downloadUrl,
      filename: `Challan-${challan.challanNumber}.pdf`
    });
  } catch (error) {
    console.error('Error generating PDF URL:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/delivery-challans/:id/email-preview
// GET /api/delivery-challans/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!challan) return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();
    const orgName  = org?.orgName    || '';
    const orgGST   = org?.gstNumber  || '';
    const orgPhone = org?.phone      || '';
    const orgEmail = org?.email      || '';
    const dateStr = new Date(challan.challanDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const deliveryDateStr = challan.expectedDeliveryDate
      ? new Date(challan.expectedDeliveryDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })
      : null;
    const totalQty = challan.items.reduce((sum, item) => sum + (item.quantity || 0), 0);
    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Delivery Challan ${challan.challanNumber}</title>
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
    .info-box { background: #f9f9f9; border-left: 3px solid #0f1e3d;
                padding: 12px 16px; margin: 8px 0; font-size: 12px; line-height: 1.8; }
    .notes-box { background: #fffbeb; border-left: 3px solid #d97706;
                 padding: 12px 16px; font-size: 12px; line-height: 1.7; margin-top: 8px; }
    .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;
              font-size: 11px; color: #777; text-align: center; line-height: 1.7; }
  </style>
</head>
<body>
<div class="wrapper">
  <div class="header">
    <h1>Delivery Challan</h1>
    <p>DISPATCH DOCUMENT</p>
    <div class="inv-num">${challan.challanNumber}</div>
  </div>
  <div class="body">
    <p class="greeting">Dear ${challan.customerName},</p>
    <p style="color:#444;line-height:1.7;margin-bottom:6px;">
      This is to inform you that we have dispatched goods as per delivery challan <strong>${challan.challanNumber}</strong>.
    </p>
    <div class="section-title">Challan Details</div>
    <table class="detail">
      <tr><td>Challan Number</td>  <td>${challan.challanNumber}</td></tr>
      <tr><td>Date</td>            <td>${dateStr}</td></tr>
      <tr><td>Purpose</td>         <td>${challan.purpose || 'Sales'}</td></tr>
      <tr><td>Status</td>          <td>${(challan.status || '').replace(/_/g, ' ')}</td></tr>
      ${deliveryDateStr ? `<tr><td>Expected Delivery</td><td>${deliveryDateStr}</td></tr>` : ''}
      ${challan.referenceNumber ? `<tr><td>Reference #</td><td>${challan.referenceNumber}</td></tr>` : ''}
      ${challan.vehicleNumber ? `<tr><td>Vehicle Number</td><td>${challan.vehicleNumber}</td></tr>` : ''}
    </table>
    <div class="section-title">Items Summary</div>
    <table class="detail">
      <tr><td>Total Items</td>    <td>${challan.items.length}</td></tr>
      <tr><td>Total Quantity</td> <td>${totalQty}</td></tr>
    </table>
    ${challan.transportMode || challan.vehicleNumber ? `
    <div class="section-title">Transport Details</div>
    <div class="info-box">
      ${challan.transportMode    ? `<strong>Mode:</strong> ${challan.transportMode}<br>` : ''}
      ${challan.vehicleNumber    ? `<strong>Vehicle:</strong> ${challan.vehicleNumber}<br>` : ''}
      ${challan.transporterName  ? `<strong>Transporter:</strong> ${challan.transporterName}<br>` : ''}
      ${challan.driverName       ? `<strong>Driver:</strong> ${challan.driverName}<br>` : ''}
    </div>` : ''}
    ${challan.customerNotes ? `
    <div class="section-title">Notes</div>
    <div class="notes-box">${challan.customerNotes}</div>` : ''}
    <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">
      The delivery challan PDF is attached for your records.<br>
      Please verify the items upon delivery and contact us immediately if there are any discrepancies.
    </p>
  </div>
  <div class="footer">
    <strong>Thank you for your business.</strong><br>
    ${orgName} &nbsp;|&nbsp; ${orgEmail} &nbsp;|&nbsp; This is a system-generated email.
  </div>
</div>
</body>
</html>`;
    res.json({ success: true, data: { subject: `Delivery Challan ${challan.challanNumber} — ${orgName}`, html, to: challan.customerEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!challan) return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    if (to !== undefined)      challan.customEmailTo      = to;
    if (subject !== undefined) challan.customEmailSubject = subject;
    if (html !== undefined)    challan.customEmailHtml    = html;
    await challan.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Delete delivery challan
router.delete('/:id', async (req, res) => {
  try {
    const challan = await DeliveryChallan.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    
    if (!challan) {
      return res.status(404).json({ success: false, error: 'Delivery challan not found' });
    }
    
    if (challan.status !== 'DRAFT') {
      return res.status(400).json({
        success: false,
        error: 'Only draft challans can be deleted'
      });
    }
    
    await challan.deleteOne();
    
    console.log(`? Delivery challan deleted: ${challan.challanNumber}`);
    
    res.json({
      success: true,
      message: 'Delivery challan deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting challan:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;