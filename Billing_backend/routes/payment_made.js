// ============================================================================
// PAYMENTS MADE - COMPLETE BACKEND (UPDATED)
// ============================================================================
// File: backend/routes/payment_made.js
//
// NEW in this version:
// ✅ GET /vendor-bills/:vendorId  → returns OPEN + OVERDUE + PARTIALLY_PAID
//    bills for that vendor (used by Flutter to show outstanding bills)
// ✅ POST / (create) → after saving payment, calls POST /api/bills/:id/payment
//    for each bill in billsApplied array → marks bills as paid/partially paid
// ✅ COA posting via postTransactionToCOA for payment_made record
// ✅ Balance deduction from paidFromAccount (existing, kept)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');
const multer = require('multer');

// ✅ COA Helper — same pattern as bill.js
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
// MONGOOSE SCHEMA
// ============================================================================

const paymentMadeSchema = new mongoose.Schema(
  {
    paymentNumber: { type: String, required: true, unique: true, index: true },

    vendorId: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', required: true },
    vendorName: { type: String, required: true },
    vendorEmail: { type: String },

    paymentDate: { type: Date, required: true, default: Date.now },
    paymentMode: {
      type: String,
      enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'Card', 'Online', 'NEFT', 'RTGS', 'IMPS'],
      required: true,
    },
    referenceNumber: { type: String },
    paidFromAccountId: { type: mongoose.Schema.Types.ObjectId, ref: 'Account', default: null },
    paidFromAccountName: { type: String, default: null },
    amount: { type: Number, required: true, min: 0 },
    notes: { type: String },

    paymentType: {
      type: String,
      enum: ['PAYMENT', 'ADVANCE', 'EXCESS'],
      default: 'PAYMENT',
    },

    status: {
      type: String,
      enum: ['DRAFT', 'RECORDED', 'APPLIED', 'PARTIALLY_APPLIED', 'REFUNDED', 'VOIDED'],
      default: 'RECORDED',
      index: true,
    },

    billsApplied: [
      {
        billId: mongoose.Schema.Types.ObjectId,
        billNumber: String,
        amountApplied: Number,
        appliedDate: Date,
      },
    ],

    amountApplied: { type: Number, default: 0 },
    amountUnused: { type: Number, default: 0 },

    items: [
      {
        itemDetails: { type: String, required: true },
        itemType: { type: String, enum: ['FETCHED', 'MANUAL'], default: 'MANUAL' },
        itemId: { type: mongoose.Schema.Types.ObjectId },
        account: { type: String },
        quantity: { type: Number, default: 1 },
        rate: { type: Number, default: 0 },
        discount: { type: Number, default: 0 },
        discountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
        amount: { type: Number, default: 0 },
      },
    ],

    subTotal: { type: Number, default: 0 },
    tdsRate: { type: Number, default: 0 },
    tdsAmount: { type: Number, default: 0 },
    tcsRate: { type: Number, default: 0 },
    tcsAmount: { type: Number, default: 0 },
    gstRate: { type: Number, default: 18 },
    cgst: { type: Number, default: 0 },
    sgst: { type: Number, default: 0 },
    igst: { type: Number, default: 0 },
    totalAmount: { type: Number, default: 0 },

    refunds: [
      {
        refundId: mongoose.Schema.Types.ObjectId,
        amount: Number,
        refundDate: Date,
        refundMode: String,
        referenceNumber: String,
        notes: String,
        refundedBy: String,
        refundedAt: Date,
      },
    ],
    totalRefunded: { type: Number, default: 0 },

    pdfPath: String,
    pdfGeneratedAt: Date,

    orgId: { type: String, index: true, default: null },
    createdBy: { type: String, required: true },
    updatedBy: String,
  },
  { timestamps: true }
);

// Pre-save: recalculate amounts
paymentMadeSchema.pre('save', function () {
  if (this.items && this.items.length > 0) {
    this.subTotal = this.items.reduce((sum, item) => sum + (item.amount || 0), 0);
    this.tdsAmount = (this.subTotal * this.tdsRate) / 100;
    this.tcsAmount = (this.subTotal * this.tcsRate) / 100;
    const gstBase = this.subTotal - this.tdsAmount + this.tcsAmount;
    const gstAmount = (gstBase * this.gstRate) / 100;
    this.cgst = gstAmount / 2;
    this.sgst = gstAmount / 2;
    this.igst = 0;
    this.totalAmount = this.subTotal - this.tdsAmount + this.tcsAmount + gstAmount;
  } else {
    this.totalAmount = this.amount || 0;
    this.subTotal = this.amount || 0;
  }
  this.amountApplied = (this.billsApplied || []).reduce(
    (s, b) => s + (b.amountApplied || 0), 0
  );
  this.amountUnused = Math.max(
    0, this.totalAmount - this.amountApplied - (this.totalRefunded || 0)
  );
  if (this.amountApplied >= this.totalAmount && this.totalAmount > 0)
    this.status = 'APPLIED';
  else if (this.amountApplied > 0)
    this.status = 'PARTIALLY_APPLIED';
  else if (!['DRAFT', 'VOIDED', 'REFUNDED'].includes(this.status))
    this.status = 'RECORDED';
});

paymentMadeSchema.index({ vendorId: 1, paymentDate: -1 });
paymentMadeSchema.index({ status: 1 });
paymentMadeSchema.index({ createdAt: -1 });

const PaymentMade = mongoose.models.PaymentMade || mongoose.model('PaymentMade', paymentMadeSchema);

// ============================================================================
// HELPERS
// ============================================================================

async function generatePaymentNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(PaymentMade, 'paymentNumber', 'PMT', orgId);
}

function calcItemAmount(item) {
  let amt = (item.quantity || 1) * (item.rate || 0);
  if (item.discount > 0) {
    if (item.discountType === 'percentage') amt -= amt * (item.discount / 100);
    else amt -= item.discount;
  }
  return Math.max(0, Math.round(amt * 100) / 100);
}

// ============================================================================
// PDF GENERATION (unchanged)
// ============================================================================

function findLogoPath() {
  const candidates = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg'),
  ];
  for (const p of candidates) {
    try { if (fs.existsSync(p) && fs.statSync(p).size > 0) return p; } catch (_) {}
  }
  return null;
}

async function generatePaymentPDF(payment, orgId) {
  const OrgModel = mongoose.models.Organization || mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
  const org = await OrgModel.findOne({ orgId }).lean();
  const orgName = org?.orgName || '';
  const orgGST = org?.gstNumber || '';
  const orgPhone = org?.phone || '';
  const orgWhatsapp = org?.whatsappNumber || '';
  const orgEmail = org?.email || '';
  const orgAddress = org?.address || '';
  return new Promise((resolve, reject) => {
    try {
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'payments');
      if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });
      const filename = `payment-${payment.paymentNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      // Dark navy header bar matching invoice/bill style
      const pageW = 515;
      doc.rect(40, 30, pageW, 90).fill('#0f1e3d');

      doc.fontSize(12).fillColor('#ffffff').font('Helvetica-Bold')
         .text(orgName.toUpperCase(), 50, 40, { width: 220 });
      doc.fontSize(7).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text('PAYMENT MADE', 50, 56, { width: 220, characterSpacing: 1 });

      const contactLines = [orgAddress, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)');
      let contactY = 68;
      contactLines.forEach(line => {
        doc.text(line, 50, contactY, { width: 240 });
        contactY += 9;
      });

      doc.fontSize(8).fillColor('rgba(255,255,255,0.6)').font('Helvetica-Bold')
         .text('PAYMENT MADE', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
      doc.fontSize(16).fillColor('#ffffff').font('Helvetica-Bold')
         .text(payment.paymentNumber, 380, 52, { width: 170, align: 'right' });
      doc.fontSize(8).fillColor('rgba(255,255,255,0.8)').font('Helvetica')
         .text(`Date: ${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' })}`, 380, 74, { width: 170, align: 'right' });

      const boxY = 155;
      doc.rect(40, boxY, 515, 60).fillAndStroke('#F8F9FA', '#DDDDDD');
      doc.rect(40, boxY, 515, 2).fillAndStroke('#0066CC', '#0066CC');
      doc.fontSize(8).fillColor('#2C3E50').font('Helvetica-Bold');
      ['Payment Number:', 'Payment Date:', 'Payment Mode:'].forEach((lbl, i) =>
        doc.text(lbl, 50, boxY + 12 + i * 15));
      doc.fillColor('#000000').font('Helvetica');
      doc.text(payment.paymentNumber, 160, boxY + 12);
      doc.text(new Date(payment.paymentDate).toLocaleDateString('en-IN', {
        day: '2-digit', month: 'short', year: 'numeric'
      }), 160, boxY + 27);
      doc.text(payment.paymentMode, 160, boxY + 42);
      doc.fillColor('#2C3E50').font('Helvetica-Bold');
      ['Reference #:', 'Status:', 'Type:'].forEach((lbl, i) =>
        doc.text(lbl, 305, boxY + 12 + i * 15));
      doc.fillColor('#000000').font('Helvetica');
      doc.text(payment.referenceNumber || 'N/A', 395, boxY + 12);
      doc.text(payment.status, 395, boxY + 27);
      doc.text(payment.paymentType, 395, boxY + 42);

      const vY = boxY + 72;
      doc.fontSize(11).fillColor('#0066CC').font('Helvetica-Bold').text('PAID TO:', 40, vY);
      doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold').text(payment.vendorName, 40, vY + 18);
      if (payment.vendorEmail) {
        doc.fontSize(8).fillColor('#555555').font('Helvetica')
          .text(`Email: ${payment.vendorEmail}`, 40, vY + 32);
      }

      // Bills applied section
      if (payment.billsApplied && payment.billsApplied.length > 0) {
        const billsY = vY + 55;
        doc.fontSize(11).fillColor('#0066CC').font('Helvetica-Bold').text('BILLS PAID:', 40, billsY);
        let bY = billsY + 18;
        doc.rect(40, bY, 515, 20).fillAndStroke('#8E44AD', '#8E44AD');
        doc.fontSize(8).fillColor('#FFFFFF').font('Helvetica-Bold');
        doc.text('Bill #', 50, bY + 6);
        doc.text('Amount Applied', 400, bY + 6, { width: 145, align: 'right' });
        bY += 20;
        payment.billsApplied.forEach((b, idx) => {
          const rc = idx % 2 === 0 ? '#FFFFFF' : '#F8F9FA';
          doc.rect(40, bY, 515, 20).fillAndStroke(rc, '#E8E8E8');
          doc.fontSize(8).fillColor('#000000').font('Helvetica');
          doc.text(b.billNumber || '-', 50, bY + 6);
          doc.text(`₹${(b.amountApplied || 0).toFixed(2)}`, 400, bY + 6, { width: 145, align: 'right' });
          bY += 20;
        });
      }

      const tableTop = 370;
      doc.rect(40, tableTop, 515, 22).fillAndStroke('#2C3E50', '#2C3E50');
      doc.fontSize(8).fillColor('#FFFFFF').font('Helvetica-Bold');
      doc.text('ITEM DETAILS', 50, tableTop + 8);
      doc.text('QTY', 330, tableTop + 8, { width: 40, align: 'center' });
      doc.text('RATE', 380, tableTop + 8, { width: 60, align: 'right' });
      doc.text('AMOUNT', 455, tableTop + 8, { width: 90, align: 'right' });

      let yPos = tableTop + 22;
      (payment.items || []).forEach((item, idx) => {
        const rc = idx % 2 === 0 ? '#FFFFFF' : '#F8F9FA';
        doc.rect(40, yPos, 515, 26).fillAndStroke(rc, '#E8E8E8');
        doc.fontSize(8).fillColor('#000000').font('Helvetica');
        doc.text(item.itemDetails || 'N/A', 50, yPos + 9, { width: 260, ellipsis: true });
        doc.text((item.quantity || 0).toString(), 330, yPos + 9, { width: 40, align: 'center' });
        doc.text(`₹${(item.rate || 0).toFixed(2)}`, 380, yPos + 9, { width: 60, align: 'right' });
        doc.text(`₹${(item.amount || 0).toFixed(2)}`, 455, yPos + 9, { width: 90, align: 'right' });
        yPos += 26;
      });

      const stY = yPos + 20;
      let curY = stY;
      const lX = 370, vX = 485;
      doc.fontSize(8).fillColor('#2C3E50').font('Helvetica-Bold').text('Subtotal:', lX, curY);
      doc.fillColor('#000000').font('Helvetica')
        .text(`₹ ${(payment.subTotal || 0).toFixed(2)}`, vX, curY, { width: 70, align: 'right' });
      curY += 14;
      if ((payment.cgst || 0) > 0) {
        doc.fillColor('#2C3E50').font('Helvetica-Bold').text('CGST:', lX, curY);
        doc.fillColor('#000000').font('Helvetica')
          .text(`₹ ${payment.cgst.toFixed(2)}`, vX, curY, { width: 70, align: 'right' });
        curY += 14;
      }
      if ((payment.sgst || 0) > 0) {
        doc.fillColor('#2C3E50').font('Helvetica-Bold').text('SGST:', lX, curY);
        doc.fillColor('#000000').font('Helvetica')
          .text(`₹ ${payment.sgst.toFixed(2)}`, vX, curY, { width: 70, align: 'right' });
        curY += 14;
      }
      doc.moveTo(370, curY + 3).lineTo(555, curY + 3).strokeColor('#2C3E50').lineWidth(1).stroke();
      curY += 10;
      doc.rect(370, curY, 185, 22).strokeColor('#2C3E50').lineWidth(2).stroke();
      doc.fontSize(10).fillColor('#2C3E50').font('Helvetica-Bold').text('Total Payment:', lX + 5, curY + 6);
      doc.fontSize(12).fillColor('#27AE60').font('Helvetica-Bold')
        .text(`₹ ${(payment.totalAmount || 0).toFixed(2)}`, vX, curY + 5, { width: 65, align: 'right' });

      const footerY = 730;
      doc.moveTo(40, footerY).lineTo(555, footerY).lineWidth(1).strokeColor('#dde4ef').stroke();
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
         .text(`${orgName}${orgGST ? ' · GSTIN: ' + orgGST : ''} · ${payment.paymentNumber}`,
               40, footerY + 6, { width: pageW / 2 });
      doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`,
               40, footerY + 6, { width: pageW, align: 'right' });

      doc.end();
      stream.on('finish', () => resolve({ filename, filepath, relativePath: `/uploads/payments/${filename}` }));
      stream.on('error', reject);
    } catch (err) { reject(err); }
  });
}

// ============================================================================
// EMAIL (unchanged)
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: false,
  auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
});

async function sendPaymentEmail(payment, orgId = null) {
  if (!payment.vendorEmail) return;

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

  const html = `<!DOCTYPE html> <html lang="en"> <head>   <meta charset="UTF-8">   <title>Payment ${payment.paymentNumber}</title>   <style>     * { margin: 0; padding: 0; box-sizing: border-box; }     body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }     .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }     .header { background: #0f1e3d; padding: 24px 32px; }     .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }     .header p  { color: rgba(255,255,255,0.7); font-size: 11px; letter-spacing: 0.5px; }     .header .num { color: #fff; font-size: 14px; font-weight: bold; margin-top: 8px; }     .body { padding: 28px 32px; }     .success-badge { background: #d4edda; border: 1px solid #28a745; border-radius: 6px;                      padding: 16px; text-align: center; margin: 18px 0; }     .success-badge h2 { color: #155724; font-size: 18px; margin-bottom: 4px; }     .success-badge p  { color: #155724; font-size: 13px; }     .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase;                      letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0;                      padding-bottom: 6px; margin: 22px 0 12px; }     table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }     table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }     table.detail td:first-child { color: #555; width: 160px; }     table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }     .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222;                     border-bottom: none; padding-top: 10px; }     .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;               font-size: 11px; color: #777; text-align: center; line-height: 1.7; }   </style> </head> <body> <div class="wrapper">   <div class="header">     <h1>Payment Confirmation</h1>     <p>FROM ${orgName.toUpperCase()}</p>     <div class="num">${payment.paymentNumber}</div>   </div>   <div class="body">     <p style="font-size:14px;color:#222;margin-bottom:18px;">Dear ${payment.vendorName},</p>      <div class="success-badge">       <h2>✅ Payment of ₹${(payment.totalAmount || payment.amount || 0).toFixed(2)} recorded</h2>       <p>Payment Number: ${payment.paymentNumber}</p>     </div>      <div class="section-title">Payment Details</div>     <table class="detail">       <tr><td>Payment Number</td><td>${payment.paymentNumber}</td></tr>       <tr><td>Payment Date</td><td>${new Date(payment.paymentDate).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' })}</td></tr>       <tr><td>Payment Mode</td><td>${payment.paymentMode}</td></tr>       ${payment.referenceNumber ? `<tr><td>Reference #</td><td>${payment.referenceNumber}</td></tr>` : ''}       <tr><td>Payment Type</td><td>${payment.paymentType}</td></tr>       <tr class="total-row"><td>Total Amount</td><td>₹${(payment.totalAmount || payment.amount || 0).toFixed(2)}</td></tr>     </table>      ${payment.billsApplied && payment.billsApplied.length > 0 ? `     <div class="section-title">Bills Paid</div>     <table class="detail">       ${payment.billsApplied.map(b => `         <tr><td>${b.billNumber || '-'}</td><td>₹${(b.amountApplied || 0).toFixed(2)}</td></tr>       `).join('')}     </table>` : ''}      ${payment.notes ? `     <div class="section-title">Notes</div>     <p style="font-size:12px;color:#444;line-height:1.7;">${payment.notes}</p>` : ''}      <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">       Please keep this confirmation for your records.     </p>   </div>   <div class="footer">     <strong>${orgName}</strong><br>     ${orgGST   ? 'GST: '  + orgGST   + ' &nbsp;|&nbsp; ' : ''}     ${orgPhone ? 'Ph: '   + orgPhone  + ' &nbsp;|&nbsp; ' : ''}     ${orgEmail || ''}   </div> </div> </body> </html>`;

  return emailTransporter.sendMail({
    from: `"${orgName} - Payments" <${process.env.SMTP_USER}>`,
    to: payment.vendorEmail,
    subject: `Payment Confirmation ${payment.paymentNumber} — ₹${(payment.totalAmount || payment.amount || 0).toFixed(2)}`,
    html,
  });
}

// ============================================================================
// MULTER FOR IMPORT
// ============================================================================

const importUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/\.(xlsx|xls|csv)$/i.test(file.originalname)) cb(null, true);
    else cb(new Error('Only Excel/CSV files allowed'));
  },
});

// ============================================================================
// ROUTES
// ============================================================================

// ── NEW: GET /vendor-bills/:vendorId ─────────────────────────────────────────
// Returns all OPEN + OVERDUE + PARTIALLY_PAID bills for a vendor
// Used by Flutter Payment Made screen to show outstanding bills
router.get('/vendor-bills/:vendorId', async (req, res) => {
  try {
    const { vendorId } = req.params;

    if (!mongoose.Types.ObjectId.isValid(vendorId)) {
      return res.status(400).json({ success: false, error: 'Invalid vendor ID' });
    }

    // Dynamically get the Bill model (registered in bill.js)
    const Bill = mongoose.models.Bill ||
      mongoose.model('Bill', new mongoose.Schema({}, { strict: false }));

    const bills = await Bill.find({
      vendorId: new mongoose.Types.ObjectId(vendorId),
      status: { $in: ['OPEN', 'OVERDUE', 'PARTIALLY_PAID'] },
    })
      .select('billNumber billDate dueDate totalAmount amountDue amountPaid status')
      .sort({ billDate: 1 }) // oldest first for auto-allocation
      .lean();

    res.json({
      success: true,
      count: bills.length,
      data: bills,
    });
  } catch (err) {
    console.error('Error fetching vendor bills:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET all
router.get('/', async (req, res) => {
  try {
    const {
      status, vendorId, fromDate, toDate, paymentMode,
      paymentType, page = 1, limit = 20, search,
    } = req.query;
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (status) query.status = status;
    if (vendorId) query.vendorId = vendorId;
    if (paymentMode) query.paymentMode = paymentMode;
    if (paymentType) query.paymentType = paymentType;
    if (fromDate || toDate) {
      query.paymentDate = {};
      if (fromDate) query.paymentDate.$gte = new Date(fromDate);
      if (toDate) query.paymentDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { paymentNumber: new RegExp(search, 'i') },
        { vendorName: new RegExp(search, 'i') },
        { referenceNumber: new RegExp(search, 'i') },
      ];
    }
    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [payments, total] = await Promise.all([
      PaymentMade.find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).select('-__v'),
      PaymentMade.countDocuments(query),
    ]);
    res.json({
      success: true,
      data: payments,
      pagination: {
        total, page: parseInt(page), limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET stats
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const stats = await PaymentMade.aggregate([
      { $match: orgFilter },
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalAmount: { $sum: '$totalAmount' },
          totalApplied: { $sum: '$amountApplied' },
          totalUnused: { $sum: '$amountUnused' },
        },
      },
    ]);
    const overall = { totalPayments: 0, totalAmount: 0, totalApplied: 0, totalUnused: 0, byStatus: {} };
    stats.forEach((s) => {
      overall.totalPayments += s.count;
      overall.totalAmount += s.totalAmount;
      overall.totalApplied += s.totalApplied;
      overall.totalUnused += s.totalUnused;
      overall.byStatus[s._id] = { count: s.count, amount: s.totalAmount };
    });
    res.json({ success: true, data: overall });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET single
router.get('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    res.json({ success: true, data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST / — Create payment ───────────────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const data = { ...req.body };
    if (!data.paymentNumber) data.paymentNumber = await generatePaymentNumber(req.user?.orgId || null);
    if (!data.vendorId) return res.status(400).json({ success: false, error: 'Vendor is required' });

    if (typeof data.vendorId === 'string' && mongoose.Types.ObjectId.isValid(data.vendorId)) {
      data.vendorId = new mongoose.Types.ObjectId(data.vendorId);
    }
    if (data.items) {
      data.items = data.items.map((item) => ({ ...item, amount: calcItemAmount(item) }));
    }
    data.createdBy = req.user?.email || req.user?.uid || 'system';
    data.orgId = req.user?.orgId || null;

    const payment = new PaymentMade(data);
    await payment.save();

    // ── STEP 1: Deduct balance from paidFromAccount ───────────────────────────
    if (data.paidFromAccountId) {
      try {
        const PaymentAccount = mongoose.models.PaymentAccount ||
          mongoose.model('PaymentAccount', new mongoose.Schema(
            { currentBalance: { type: Number, default: 0 } },
            { strict: false }
          ));
        const deductAmount = payment.totalAmount || payment.amount || 0;
        const updatedAccount = await PaymentAccount.findByIdAndUpdate(
          data.paidFromAccountId,
          { $inc: { currentBalance: -deductAmount }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (updatedAccount) {
          console.log(`✅ Balance deducted from "${updatedAccount.accountName}": -₹${deductAmount} → ₹${updatedAccount.currentBalance}`);
        } else {
          console.warn(`⚠️ Account ${data.paidFromAccountId} not found — balance NOT updated`);
        }
      } catch (balErr) {
        console.error(`⚠️ Balance deduction error:`, balErr.message);
      }
    }

    // ── STEP 2: Apply payment to each bill via bill.js payment route ──────────
    // This marks each bill as PAID / PARTIALLY_PAID and posts bill-level COA
    const billsApplied = data.billsApplied || [];
    for (const ba of billsApplied) {
      if (!ba.billId || !ba.amountApplied || ba.amountApplied <= 0) continue;
      try {
        const Bill = mongoose.models.Bill;
        if (!Bill) { console.warn('Bill model not loaded — skipping bill payment update'); continue; }

        const bill = await Bill.findById(ba.billId);
        if (!bill) { console.warn(`Bill ${ba.billId} not found`); continue; }

        const billPayment = {
          paymentId: payment._id,
          amount: ba.amountApplied,
          paymentDate: payment.paymentDate,
          paymentMode: payment.paymentMode,
          referenceNumber: payment.paymentNumber,
          notes: `Payment Made: ${payment.paymentNumber}`,
          recordedBy: data.createdBy,
          recordedAt: new Date(),
        };

        bill.payments = bill.payments || [];
        bill.payments.push(billPayment);
        bill.amountPaid = (bill.amountPaid || 0) + ba.amountApplied;
        await bill.save();

        // ── COA for bill payment: Debit AP + Credit Bank/Cash ───────────────
        try {
          const currentOrgId = req.user?.orgId || null;
          const [apId, bankId] = await Promise.all([
            getSystemAccountId('Accounts Payable', currentOrgId),
            getSystemAccountId('Undeposited Funds', currentOrgId),
          ]);
          const txnDate = new Date(payment.paymentDate);
          if (apId) {
            await postTransactionToCOA({
              accountId: apId,
              orgId: currentOrgId,
              date: txnDate,
              description: `Payment ${payment.paymentNumber} - ${bill.billNumber}`,
              referenceType: 'Payment',
              referenceId: payment._id,
              referenceNumber: payment.paymentNumber,
              debit: ba.amountApplied,
              credit: 0,
            });
          }
          if (bankId) {
            await postTransactionToCOA({
              accountId: bankId,
              orgId: currentOrgId,
              date: txnDate,
              description: `Payment ${payment.paymentNumber} - ${bill.billNumber}`,
              referenceType: 'Payment',
              referenceId: payment._id,
              referenceNumber: payment.paymentNumber,
              debit: 0,
              credit: ba.amountApplied,
            });
          }
          console.log(`✅ COA posted for bill payment: ${bill.billNumber} ← ₹${ba.amountApplied}`);
        } catch (coaErr) {
          console.error(`⚠️ COA post error for bill ${ba.billId}:`, coaErr.message);
        }

        console.log(`✅ Bill ${bill.billNumber} updated: paid ₹${ba.amountApplied}, status: ${bill.status}`);
      } catch (billErr) {
        console.error(`⚠️ Bill payment update error for ${ba.billId}:`, billErr.message);
      }
    }

    // ── STEP 3: COA for payment_made record (items-based portion) ─────────────
    // Only posts if there are line items (advance / extra payment)
    if (payment.items && payment.items.length > 0 && payment.subTotal > 0) {
      try {
        const currentOrgId = req.user?.orgId || null;
        const [expenseId, apId] = await Promise.all([
          getSystemAccountId('Cost of Goods Sold', currentOrgId),
          getSystemAccountId('Accounts Payable', currentOrgId),
        ]);
        const txnDate = new Date(payment.paymentDate);
        if (expenseId) {
          await postTransactionToCOA({
            accountId: expenseId,
            orgId: currentOrgId,
            date: txnDate,
            description: `Payment Made ${payment.paymentNumber} - ${payment.vendorName} (items)`,
            referenceType: 'PaymentMade',
            referenceId: payment._id,
            referenceNumber: payment.paymentNumber,
            debit: payment.subTotal,
            credit: 0,
          });
        }
        if (apId) {
          await postTransactionToCOA({
            accountId: apId,
            orgId: currentOrgId,
            date: txnDate,
            description: `Payment Made ${payment.paymentNumber} - ${payment.vendorName} (items)`,
            referenceType: 'PaymentMade',
            referenceId: payment._id,
            referenceNumber: payment.paymentNumber,
            debit: 0,
            credit: payment.subTotal,
          });
        }
        console.log(`✅ COA posted for payment_made items: ${payment.paymentNumber}`);
      } catch (coaErr) {
        console.error(`⚠️ COA post error (payment items):`, coaErr.message);
      }
    }

    try { await sendPaymentEmail(payment, req.user?.orgId || null); } catch (_) {}

    console.log(`✅ Payment Made created: ${payment.paymentNumber}`);
    res.status(201).json({ success: true, message: 'Payment recorded', data: payment });
  } catch (err) {
    console.error('Error creating payment:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});




// PUT update
router.put('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (payment.status === 'APPLIED')
      return res.status(400).json({ success: false, error: 'Cannot edit fully applied payments' });
    const updates = { ...req.body };
    if (updates.items) updates.items = updates.items.map((item) => ({ ...item, amount: calcItemAmount(item) }));
    updates.updatedBy = req.user?.email || 'system';
    Object.assign(payment, updates);
    await payment.save();
    res.json({ success: true, message: 'Payment updated', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST apply to bills
router.post('/:id/apply', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const { bills } = req.body;
    if (!Array.isArray(bills)) return res.status(400).json({ success: false, error: 'Bills array required' });
    for (const b of bills) {
      payment.billsApplied.push({
        billId: b.billId, billNumber: b.billNumber,
        amountApplied: b.amountApplied, appliedDate: new Date(),
      });
    }
    await payment.save();
    res.json({ success: true, message: 'Payment applied to bills', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST refund
router.post('/:id/refund', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const { amount, refundMode, referenceNumber, notes } = req.body;
    if (!amount || amount <= 0) return res.status(400).json({ success: false, error: 'Invalid refund amount' });
    if (amount > (payment.amountUnused || 0))
      return res.status(400).json({ success: false, error: 'Refund exceeds unused amount' });
    payment.refunds.push({
      refundId: new mongoose.Types.ObjectId(), amount, refundDate: new Date(),
      refundMode, referenceNumber, notes,
      refundedBy: req.user?.email || 'system', refundedAt: new Date(),
    });
    payment.totalRefunded = (payment.totalRefunded || 0) + amount;
    if (payment.totalRefunded >= payment.totalAmount) payment.status = 'REFUNDED';
    await payment.save();
    res.json({ success: true, message: 'Refund recorded', data: payment });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/payments-made/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();
    const orgName = org?.orgName || '';
    const orgGST  = org?.gstNumber || '';
    const orgPhone = org?.phone || '';
    const orgEmail = org?.email || '';
    const dateStr = new Date(payment.paymentDate || payment.createdAt).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const html = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Payment ${payment.paymentNumber}</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;font-size:13px;color:#222;background:#f4f4f4}.wrapper{max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd}.header{background:#0f1e3d;padding:24px 32px}.header h1{color:#fff;font-size:20px;font-weight:bold}.header .num{color:#fff;font-size:14px;font-weight:bold;margin-top:8px}.body{padding:28px 32px}.st{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px}table.d{width:100%;border-collapse:collapse;font-size:13px}table.d td{padding:7px 0;border-bottom:1px dashed #e8e8e8;vertical-align:top}table.d td:first-child{color:#555;width:160px}table.d td:last-child{font-weight:600;color:#111;text-align:right}.tr td{font-size:15px;font-weight:bold;border-top:2px solid #222;border-bottom:none;padding-top:10px}.footer{background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7}</style>
</head><body><div class="wrapper">
<div class="header"><h1>Payment Confirmation</h1><div class="num">${payment.paymentNumber}</div></div>
<div class="body">
<p style="font-size:14px;margin-bottom:18px;">Dear ${payment.vendorName || 'Vendor'},</p>
<p style="color:#444;line-height:1.7;margin-bottom:6px;">We confirm receipt of your payment <strong>${payment.paymentNumber}</strong>.</p>
<div class="st">Payment Details</div>
<table class="d">
<tr><td>Payment Number</td><td>${payment.paymentNumber}</td></tr>
<tr><td>Date</td><td>${dateStr}</td></tr>
<tr><td>Payment Mode</td><td>${payment.paymentMode || ''}</td></tr>
${payment.referenceNumber ? `<tr><td>Reference</td><td>${payment.referenceNumber}</td></tr>` : ''}
<tr class="tr"><td>Amount Paid</td><td>₹${(payment.totalAmount || 0).toFixed(2)}</td></tr>
</table>
${payment.notes ? `<div class="st">Notes</div><p style="font-size:12px;line-height:1.7;color:#444;">${payment.notes}</p>` : ''}
</div>
<div class="footer"><strong>${orgName}</strong><br>${orgGST ? 'GST: ' + orgGST + ' | ' : ''}${orgPhone ? 'Ph: ' + orgPhone + ' | ' : ''}${orgEmail}</div>
</div></body></html>`;
    res.json({ success: true, data: { subject: `Payment Confirmation ${payment.paymentNumber} — ₹${(payment.totalAmount || 0).toFixed(2)}`, html, to: payment.vendorEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const payment = await PaymentMade.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (to !== undefined)      payment.set('customEmailTo',      to);
    if (subject !== undefined) payment.set('customEmailSubject', subject);
    if (html !== undefined)    payment.set('customEmailHtml',    html);
    await payment.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE
router.delete('/:id', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!['DRAFT', 'RECORDED'].includes(payment.status)) {
      return res.status(400).json({ success: false, error: 'Only Draft or Recorded payments can be deleted' });
    }
    await payment.deleteOne();

    // Restore balance on delete
    if (payment.paidFromAccountId) {
      try {
        const PaymentAccount = mongoose.models.PaymentAccount ||
          mongoose.model('PaymentAccount', new mongoose.Schema(
            { currentBalance: { type: Number, default: 0 } }, { strict: false }
          ));
        const restoreAmount = payment.totalAmount || payment.amount || 0;
        const restoredAccount = await PaymentAccount.findByIdAndUpdate(
          payment.paidFromAccountId,
          { $inc: { currentBalance: restoreAmount }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (restoredAccount) {
          console.log(`✅ Balance restored: +₹${restoreAmount} → "${restoredAccount.accountName}" ₹${restoredAccount.currentBalance}`);
        }
      } catch (balErr) {
        console.error(`⚠️ Balance restore error:`, balErr.message);
      }
    }

    res.json({ success: true, message: 'Payment deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET PDF
router.get('/:id/pdf', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!payment.pdfPath || !fs.existsSync(payment.pdfPath)) {
      const info = await generatePaymentPDF(payment, req.user?.orgId);
      payment.pdfPath = info.filepath;
      payment.pdfGeneratedAt = new Date();
      await payment.save();
    }
    res.download(payment.pdfPath, `Payment-${payment.paymentNumber}.pdf`);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET download URL
router.get('/:id/download-url', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!payment) return res.status(404).json({ success: false, error: 'Payment not found' });
    if (!payment.pdfPath || !fs.existsSync(payment.pdfPath)) {
    const info = await generatePaymentPDF(payment, req.user?.orgId || null);
      payment.pdfPath = info.filepath;
      payment.pdfGeneratedAt = new Date();
      await payment.save();
    }
    const baseUrl = process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
    res.json({
      success: true,
      downloadUrl: `${baseUrl}/uploads/payments/${path.basename(payment.pdfPath)}`,
      filename: `Payment-${payment.paymentNumber}.pdf`,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST bulk import
router.post('/bulk-import', importUpload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });
    const paymentsData = JSON.parse(req.body.paymentsData || '[]');
    if (!paymentsData.length) return res.status(400).json({ success: false, error: 'No payment data' });
    const results = { totalProcessed: paymentsData.length, successCount: 0, failedCount: 0, errors: [] };
    for (const [i, pd] of paymentsData.entries()) {
      try {
        pd.paymentNumber = await generatePaymentNumber(req.user?.orgId || null);
        pd.createdBy = req.user?.email || 'import';
        pd.orgId = req.user?.orgId || null;
        if (!pd.vendorId) pd.vendorId = new mongoose.Types.ObjectId();
        const p = new PaymentMade(pd);
        await p.save();
        results.successCount++;
      } catch (e) {
        results.failedCount++;
        results.errors.push(`Row ${i + 2}: ${e.message}`);
      }
    }
    res.json({ success: true, message: 'Import completed', data: results });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});


// GET /api/payments-made/:id/vendor-phone
// Looks up vendor phone directly from DB — no need to store it on payment
router.get('/:id/vendor-phone', async (req, res) => {
  try {
    const payment = await PaymentMade.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).select('vendorId vendorName');
    if (!payment) {
      return res.status(404).json({ success: false, error: 'Payment not found' });
    }

    // Try billing vendors collection first, then fall back to admin vendors
    const BillingVendor = mongoose.models.BillingVendor ||
      mongoose.model('BillingVendor', new mongoose.Schema({}, { strict: false }));

    const AdminVendor = mongoose.models.Vendor ||
      mongoose.model('Vendor', new mongoose.Schema({}, { strict: false }));

    let phone = '';

    const billingVendor = await BillingVendor.findById(payment.vendorId)
      .select('phone primaryPhone vendorPhone').lean();

    if (billingVendor) {
      phone = billingVendor.phone ?? billingVendor.primaryPhone ?? billingVendor.vendorPhone ?? '';
    }

    // Fallback to admin vendors collection if not found in billing
    if (!phone) {
      const adminVendor = await AdminVendor.findById(payment.vendorId)
        .select('phone primaryPhone vendorPhone').lean();
      if (adminVendor) {
        phone = adminVendor.phone ?? adminVendor.primaryPhone ?? adminVendor.vendorPhone ?? '';
      }
    }

    res.json({
      success: true,
      phone: phone.toString().trim(),
      vendorName: payment.vendorName,
    });

  } catch (err) {
    console.error('Error fetching vendor phone:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;