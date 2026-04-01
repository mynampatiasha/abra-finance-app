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

async function getSystemAccountId(name) {
  try {
    const acc = await ChartOfAccount.findOne({
      accountName: name,
      isSystemAccount: true
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

let CACHED_LOGO_PATH = null;
let CACHED_LOGO_BASE64 = null;

function findLogoPath() {
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
        if (stats.isFile() && stats.size > 0) {
          console.log('✅ LOGO FOUND:', testPath);
          return testPath;
        }
      }
    } catch (err) {
      // Continue searching
    }
  }
  
  console.error('❌ LOGO NOT FOUND!');
  return null;
}

function getLogoPath() {
  if (!CACHED_LOGO_PATH) {
    CACHED_LOGO_PATH = findLogoPath();
  }
  return CACHED_LOGO_PATH;
}

function getLogoBase64() {
  if (CACHED_LOGO_BASE64) {
    return CACHED_LOGO_BASE64;
  }
  
  try {
    const logoPath = getLogoPath();
    
    if (logoPath && fs.existsSync(logoPath)) {
      const imageBuffer = fs.readFileSync(logoPath);
      const base64 = imageBuffer.toString('base64');
      const ext = path.extname(logoPath).toLowerCase();
      const mimeType = ext === '.png' ? 'image/png' : 'image/jpeg';
      
      CACHED_LOGO_BASE64 = `data:${mimeType};base64,${base64}`;
      console.log('✅ Logo encoded for email');
      
      return CACHED_LOGO_BASE64;
    }
    
    console.warn('⚠️ Logo file not found for email encoding');
  } catch (error) {
    console.error('❌ Error encoding logo for email:', error.message);
  }
  
  return null;
}

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
  }
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

function getPaymentInfo(invoice) {
  // If payment account is selected, use it
  if (invoice.selectedPaymentAccount && invoice.selectedPaymentAccount.accountId) {
    const account = invoice.selectedPaymentAccount;
    
    return {
      accountHolder: account.accountHolder || DEFAULT_PAYMENT.bankAccount.accountHolder,
      bankAccount: account.accountNumber || '',
      ifscCode: account.ifscCode || '',
      bankName: account.bankName || '',
      upiId: account.upiId || '',
      officeAddress: DEFAULT_PAYMENT.office.fullAddress,
      accountType: account.accountType || 'BANK_ACCOUNT',
      accountName: account.accountName || '',
      // Additional fields for other account types
      providerName: account.providerName || '',
      cardNumber: account.cardNumber || '',
      fastagNumber: account.fastagNumber || '',
      vehicleNumber: account.vehicleNumber || '',
      customFields: account.customFields || []
    };
  }
  
  // Otherwise use defaults
  return {
    accountHolder: DEFAULT_PAYMENT.bankAccount.accountHolder,
    bankAccount: DEFAULT_PAYMENT.bankAccount.accountNumber,
    ifscCode: DEFAULT_PAYMENT.bankAccount.ifscCode,
    bankName: DEFAULT_PAYMENT.bankAccount.bankName,
    upiId: DEFAULT_PAYMENT.upi.upiId,
    officeAddress: DEFAULT_PAYMENT.office.fullAddress,
    accountType: 'BANK_ACCOUNT',
    accountName: 'Default Bank Account'
  };
}

// ============================================================================
// PDF GENERATION - FIXED TO SINGLE PAGE, NO COLOR BOXES
// ============================================================================

async function generateInvoicePDF(invoice) {
  return new Promise((resolve, reject) => {
    try {
      console.log('📄 Starting PDF generation for invoice:', invoice.invoiceNumber);
      
      const uploadsDir = path.join(__dirname, '..', 'uploads', 'invoices');
      if (!fs.existsSync(uploadsDir)) {
        fs.mkdirSync(uploadsDir, { recursive: true });
      }
      
      const filename = `invoice-${invoice.invoiceNumber}.pdf`;
      const filepath = path.join(uploadsDir, filename);
      
      const doc = new PDFDocument({ 
        size: 'A4', 
        margin: 40,  // Reduced margin for more space
        bufferPages: true
      });
      const stream = fs.createWriteStream(filepath);
      
      doc.pipe(stream);
      
      // ========================================================================
      // LOGO LOADING
      // ========================================================================
      
      const logoPath = getLogoPath();
      let logoLoaded = false;
      
      if (logoPath) {
        try {
          doc.image(logoPath, 40, 35, { 
            width: 120,
            height: 60,
            fit: [120, 60]
          });
          logoLoaded = true;
          console.log('   ✅ Logo embedded in PDF');
        } catch (logoError) {
          console.error('   ❌ Logo loading failed:', logoError.message);
        }
      }
      
      if (!logoLoaded) {
        doc.fontSize(22)
           .fillColor('#0066CC')
           .font('Helvetica-Bold')
           .text('ABRA Travels', 40, 40);
        
        doc.fontSize(9)
           .fillColor('#666666')
           .font('Helvetica')
           .text('YOUR JOURNEY, OUR COMMITMENT', 40, 67);
      }
      
      // Company details (compact)
      const companyY = logoLoaded ? 105 : 85;
      
      doc.fontSize(8)
         .fillColor('#555555')
         .font('Helvetica')
         .text('Bangalore, Karnataka, India', 40, companyY)
         .text('GST: 29AABCT1332L1ZM', 40, companyY + 11)
         .text('Contact: +91 88672 88076', 40, companyY + 22)
         .text('Email: info@abratravels.com', 40, companyY + 33);
      
      // INVOICE Title (RIGHT SIDE)
      doc.fontSize(32)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('INVOICE', 350, 40, { align: 'right' });
      
      // Status badge
      const status = invoice.status || 'DRAFT';
      const statusColors = {
        'PAID': '#27AE60',
        'UNPAID': '#E67E22',
        'PARTIALLY_PAID': '#3498DB',
        'OVERDUE': '#E74C3C',
        'DRAFT': '#95A5A6',
        'SENT': '#F39C12',
        'CANCELLED': '#7F8C8D'
      };
      
      const statusColor = statusColors[status] || '#95A5A6';
      doc.fontSize(10)
         .fillColor(statusColor)
         .font('Helvetica-Bold')
         .text(status.replace(/_/g, ' '), 350, 80, { align: 'right' });
      
      // ========================================================================
      // INVOICE DETAILS BOX (Compact)
      // ========================================================================
      
      let invoiceBoxY = 155;
      
      doc.rect(40, invoiceBoxY, 515, 60)
         .fillAndStroke('#F8F9FA', '#DDDDDD');
      
      doc.rect(40, invoiceBoxY, 515, 2)
         .fillAndStroke('#0066CC', '#0066CC');
      
      doc.fontSize(8)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold');
      
      // Compact layout
      doc.text('Invoice Number:', 50, invoiceBoxY + 12);
      doc.text('Invoice Date:', 50, invoiceBoxY + 27);
      doc.text('Due Date:', 50, invoiceBoxY + 42);
      
      doc.fillColor('#000000')
         .font('Helvetica');
      
      doc.text(invoice.invoiceNumber || 'N/A', 145, invoiceBoxY + 12);
      doc.text(new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { 
        day: '2-digit', month: 'short', year: 'numeric' 
      }), 145, invoiceBoxY + 27);
      doc.text(new Date(invoice.dueDate).toLocaleDateString('en-IN', { 
        day: '2-digit', month: 'short', year: 'numeric' 
      }), 145, invoiceBoxY + 42);
      
      // Right column
      doc.fillColor('#2C3E50')
         .font('Helvetica-Bold');
      
      doc.text('Order Number:', 305, invoiceBoxY + 12);
      doc.text('Payment Terms:', 305, invoiceBoxY + 27);
      doc.text('GST Number:', 305, invoiceBoxY + 42);
      
      doc.fillColor('#000000')
         .font('Helvetica');
      
      doc.text(invoice.orderNumber || 'N/A', 400, invoiceBoxY + 12);
      doc.text(invoice.terms || 'Due on Receipt', 400, invoiceBoxY + 27);
      doc.text('29AABCT1332L1ZM', 400, invoiceBoxY + 42);
      
      // ========================================================================
      // CUSTOMER INFORMATION (Compact)
      // ========================================================================
      
      let customerY = invoiceBoxY + 72;
      
      doc.fontSize(11)
         .fillColor('#0066CC')
         .font('Helvetica-Bold')
         .text('BILL TO:', 40, customerY);
      
      doc.fontSize(10)
         .fillColor('#000000')
         .font('Helvetica-Bold')
         .text(invoice.customerName || 'N/A', 40, customerY + 18);
      
      doc.fontSize(8)
         .fillColor('#555555')
         .font('Helvetica');
      
      customerY += 32;
      
      if (invoice.billingAddress) {
        const addr = invoice.billingAddress;
        if (addr.street) {
          doc.text(addr.street, 40, customerY);
          customerY += 11;
        }
        if (addr.city || addr.state || addr.pincode) {
          doc.text(`${addr.city || ''}, ${addr.state || ''} ${addr.pincode || ''}`, 40, customerY);
          customerY += 11;
        }
      }
      
      if (invoice.customerEmail) {
        doc.text(`Email: ${invoice.customerEmail}`, 40, customerY);
        customerY += 11;
      }
      
      if (invoice.customerPhone) {
        doc.text(`Phone: ${invoice.customerPhone}`, 40, customerY);
      }
      
      // ========================================================================
      // LINE ITEMS TABLE (Compact)
      // ========================================================================
      
      const tableTop = 360;
      
      doc.rect(40, tableTop, 515, 22)
         .fillAndStroke('#2C3E50', '#2C3E50');
      
      doc.fontSize(8)
         .fillColor('#FFFFFF')
         .font('Helvetica-Bold');
      
      doc.text('ITEM DETAILS', 50, tableTop + 8);
      doc.text('QTY', 330, tableTop + 8, { width: 40, align: 'center' });
      doc.text('RATE', 380, tableTop + 8, { width: 60, align: 'right' });
      doc.text('AMOUNT', 455, tableTop + 8, { width: 90, align: 'right' });
      
      let yPosition = tableTop + 22;
      
      invoice.items.forEach((item, index) => {
        const rowColor = index % 2 === 0 ? '#FFFFFF' : '#F8F9FA';
        
        doc.rect(40, yPosition, 515, 26)
           .fillAndStroke(rowColor, '#E8E8E8');
        
        doc.fontSize(8)
           .fillColor('#000000')
           .font('Helvetica');
        
        const itemText = item.itemDetails || 'N/A';
        doc.text(itemText, 50, yPosition + 9, { width: 260, height: 26, ellipsis: true });
        
        doc.text(item.quantity?.toString() || '0', 330, yPosition + 9, { width: 40, align: 'center' });
        doc.text(`₹${(item.rate || 0).toFixed(2)}`, 380, yPosition + 9, { width: 60, align: 'right' });
        doc.text(`₹${(item.amount || 0).toFixed(2)}`, 455, yPosition + 9, { width: 90, align: 'right' });
        
        yPosition += 26;
      });
      
      // ========================================================================
      // ✅ TOTALS SECTION - NO COLOR BOXES, CLEAN FORMAT
      // ========================================================================
      
      const startY = yPosition + 20;
      const labelX = 370;
      const valueX = 485;
      let currentY = startY;
      
      doc.fontSize(8)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold');
      
      // Subtotal
      doc.text('Subtotal:', labelX, currentY);
      doc.fillColor('#000000')
         .font('Helvetica')
         .text(`₹ ${invoice.subTotal.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
      
      currentY += 14;
      
      // CGST
      if (invoice.cgst > 0) {
        doc.fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('CGST:', labelX, currentY);
        doc.fillColor('#000000')
           .font('Helvetica')
           .text(`₹ ${invoice.cgst.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
        currentY += 14;
      }
      
      // SGST
      if (invoice.sgst > 0) {
        doc.fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('SGST:', labelX, currentY);
        doc.fillColor('#000000')
           .font('Helvetica')
           .text(`₹ ${invoice.sgst.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
        currentY += 14;
      }
      
      // IGST
      if (invoice.igst > 0) {
        doc.fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('IGST:', labelX, currentY);
        doc.fillColor('#000000')
           .font('Helvetica')
           .text(`₹ ${invoice.igst.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
        currentY += 14;
      }
      
      // Divider line
      doc.moveTo(370, currentY + 3)
         .lineTo(555, currentY + 3)
         .strokeColor('#2C3E50')
         .lineWidth(1)
         .stroke();
      
      currentY += 10;
      
      // ✅ TOTAL AMOUNT - NO GREEN BOX, JUST BORDER
      doc.rect(370, currentY, 185, 22)
         .strokeColor('#2C3E50')
         .lineWidth(2)
         .stroke();
      
      doc.fontSize(10)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('Total Amount:', labelX + 5, currentY + 6);
      
      doc.fontSize(12)
         .fillColor('#27AE60')
         .font('Helvetica-Bold')
         .text(`₹ ${invoice.totalAmount.toFixed(2)}`, valueX, currentY + 5, { width: 65, align: 'right' });
      
      currentY += 28;
      
      // Amount Paid
      if (invoice.amountPaid > 0) {
        doc.fontSize(8)
           .fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('Amount Paid:', labelX, currentY);
        doc.fillColor('#27AE60')
           .font('Helvetica')
           .text(`₹ ${invoice.amountPaid.toFixed(2)}`, valueX, currentY, { width: 70, align: 'right' });
        currentY += 14;
      }
      
      // ✅ BALANCE DUE - NO RED BOX, JUST BORDER
      if (invoice.amountDue > 0) {
        doc.rect(370, currentY - 2, 185, 20)
           .strokeColor('#E74C3C')
           .lineWidth(2)
           .stroke();
        
        doc.fontSize(9)
           .fillColor('#2C3E50')
           .font('Helvetica-Bold')
           .text('Balance Due:', labelX + 5, currentY + 2);
        doc.fillColor('#E74C3C')
           .font('Helvetica-Bold')
           .text(`₹ ${invoice.amountDue.toFixed(2)}`, valueX, currentY + 2, { width: 65, align: 'right' });
      }
      
      // ========================================================================
      // ✅ QR CODE SECTION (if present)
      // ========================================================================
      
      if (invoice.qrCodeUrl) {
        const qrY = 650;
        
        doc.fontSize(11)
           .fillColor('#0066CC')
           .font('Helvetica-Bold')
           .text('Scan to Pay:', 40, qrY);
        
        try {
          const qrImagePath = path.join(__dirname, '..', invoice.qrCodeUrl);
          if (fs.existsSync(qrImagePath)) {
            doc.image(qrImagePath, 40, qrY + 15, {
              width: 120,
              height: 120
            });
            
            doc.fontSize(8)
               .fillColor('#555555')
               .font('Helvetica')
               .text('Scan with any UPI app', 40, qrY + 140, { width: 120, align: 'center' });
            
            console.log('   ✅ QR code embedded in PDF');
          }
        } catch (qrError) {
          console.error('   ❌ Failed to embed QR code in PDF:', qrError);
        }
      }
      
      // ========================================================================
      // NOTES (Compact if present)
      // ========================================================================
      
      if (invoice.customerNotes) {
        const notesY = invoice.qrCodeUrl ? 710 : 675;
        
        doc.fontSize(9)
           .fillColor('#0066CC')
           .font('Helvetica-Bold')
           .text('Notes:', 40, notesY);
        
        doc.fontSize(8)
           .fillColor('#555555')
           .font('Helvetica')
           .text(invoice.customerNotes, 40, notesY + 14, { width: 515, align: 'left' });
      }
      
      // ========================================================================
      // FOOTER (Compact)
      // ========================================================================
      
      const footerY = 730;
      
      doc.moveTo(40, footerY)
         .lineTo(555, footerY)
         .lineWidth(1.5)
         .strokeColor('#0066CC')
         .stroke();
      
      doc.fontSize(8)
         .fillColor('#2C3E50')
         .font('Helvetica-Bold')
         .text('Thank you for choosing ABRA Travels!', 40, footerY + 8, { align: 'center', width: 515 });
      
      doc.fontSize(6)
         .fillColor('#888888')
         .font('Helvetica')
         .text('ABRA Travels | YOUR JOURNEY, OUR COMMITMENT', 40, footerY + 20, { align: 'center', width: 515 });
      
      doc.fontSize(6)
         .fillColor('#AAAAAA')
         .text('www.abratravels.com | info@abratravels.com | +91 88672 88076', 40, footerY + 30, { align: 'center', width: 515 });
      
      doc.end();
      
      stream.on('finish', () => {
        console.log(`✅ PDF generated successfully: ${filename}`);
        console.log(`   🖼️  Logo included: ${logoLoaded ? 'YES' : 'NO (text fallback)'}`);
        
        resolve({
          filename: filename,
          filepath: filepath,
          relativePath: `/uploads/invoices/${filename}`,
          logoIncluded: logoLoaded
        });
      });
      
      stream.on('error', (error) => {
        console.error('❌ PDF stream error:', error);
        reject(error);
      });
      
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

async function sendInvoiceEmail(invoice, pdfPath) {
  console.log('📧 Preparing to send invoice email to:', invoice.customerEmail);
  
  // ✅ Use selected payment account or fallback to default
  const paymentInfo = getPaymentInfo(invoice);
  
  const logoBase64 = getLogoBase64();
  
  if (logoBase64) {
    console.log('   ✅ Logo will be embedded in email header');
  }

  // ✅ Build payment options HTML based on account type
  let paymentOptionsHtml = '';
  
  if (paymentInfo.accountType === 'BANK_ACCOUNT' && paymentInfo.bankAccount) {
    paymentOptionsHtml += `
    <!-- Bank Transfer -->
    <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E3F2FD 0%, #BBDEFB 100%); border-radius: 8px; border-left: 4px solid #0066CC; margin-bottom: 12px;">
      <tr>
        <td>
          <h4 style="margin: 0 0 12px 0; color: #0066CC; font-size: 15px;">🏦 Bank Transfer / NEFT / RTGS / IMPS</h4>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Account Holder:</strong> ${paymentInfo.accountHolder || 'ABRA Travels'}</p>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Account Number:</strong> ${paymentInfo.bankAccount}</p>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>IFSC Code:</strong> ${paymentInfo.ifscCode}</p>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Bank Name:</strong> ${paymentInfo.bankName}</p>
          <table width="100%" cellpadding="12" cellspacing="0" border="0" style="background: #FFF9C4; border-radius: 6px; border-left: 4px solid #FBC02D; margin-top: 12px;">
            <tr>
              <td style="font-size: 13px; color: #333;">
                💡 <strong>Important:</strong> Please mention invoice number <strong>${invoice.invoiceNumber}</strong> in payment remarks
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
    `;
  }
  
  if (paymentInfo.upiId) {
    paymentOptionsHtml += `
    <!-- UPI Payment -->
    <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E3F2FD 0%, #BBDEFB 100%); border-radius: 8px; border-left: 4px solid #0066CC; margin-bottom: 12px;">
      <tr>
        <td>
          <h4 style="margin: 0 0 12px 0; color: #0066CC; font-size: 15px;">📱 UPI Payment (Instant)</h4>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>UPI ID:</strong> <span style="color: #0066CC; font-weight: bold; font-size: 15px;">${paymentInfo.upiId}</span></p>
          <table width="100%" cellpadding="12" cellspacing="0" border="0" style="background: #E8F5E9; border-radius: 6px; border-left: 4px solid #27AE60; margin-top: 12px;">
            <tr>
              <td style="font-size: 13px; color: #333;">
                💡 Pay instantly using Google Pay, PhonePe, Paytm, or any UPI app
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
    `;
  }
  
  if (paymentInfo.accountType === 'FUEL_CARD' && paymentInfo.cardNumber) {
    paymentOptionsHtml += `
    <!-- Fuel Card -->
    <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E3F2FD 0%, #BBDEFB 100%); border-radius: 8px; border-left: 4px solid #0066CC; margin-bottom: 12px;">
      <tr>
        <td>
          <h4 style="margin: 0 0 12px 0; color: #0066CC; font-size: 15px;">⛽ Fuel Card Payment</h4>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Provider:</strong> ${paymentInfo.providerName}</p>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Card Number:</strong> ${paymentInfo.cardNumber}</p>
        </td>
      </tr>
    </table>
    `;
  }
  
  if (paymentInfo.accountType === 'FASTAG' && paymentInfo.fastagNumber) {
    paymentOptionsHtml += `
    <!-- FASTag -->
    <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E3F2FD 0%, #BBDEFB 100%); border-radius: 8px; border-left: 4px solid #0066CC; margin-bottom: 12px;">
      <tr>
        <td>
          <h4 style="margin: 0 0 12px 0; color: #0066CC; font-size: 15px;">🛣️ FASTag Payment</h4>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>FASTag Number:</strong> ${paymentInfo.fastagNumber}</p>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Vehicle Number:</strong> ${paymentInfo.vehicleNumber}</p>
        </td>
      </tr>
    </table>
    `;
  }
  
  if (paymentInfo.officeAddress) {
    paymentOptionsHtml += `
    <!-- Cash/Cheque -->
    <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E3F2FD 0%, #BBDEFB 100%); border-radius: 8px; border-left: 4px solid #0066CC; margin-bottom: 12px;">
      <tr>
        <td>
          <h4 style="margin: 0 0 12px 0; color: #0066CC; font-size: 15px;">💵 Cash / Cheque Payment</h4>
          <p style="margin: 6px 0; font-size: 13px; color: #333;"><strong>Visit Office:</strong></p>
          <table width="100%" cellpadding="12" cellspacing="0" border="0" style="background: #f8f9fa; border-radius: 6px; border: 1px solid #dee2e6; margin-top: 8px;">
            <tr>
              <td style="font-size: 13px; color: #333;">
                📍 ${paymentInfo.officeAddress}
              </td>
            </tr>
          </table>
          <table width="100%" cellpadding="12" cellspacing="0" border="0" style="background: #E3F2FD; border-radius: 6px; border-left: 4px solid #2196F3; margin-top: 12px;">
            <tr>
              <td style="font-size: 13px; color: #333;">
                💡 Cheques should be drawn in favor of "<strong>${paymentInfo.accountHolder || 'ABRA Travels'}</strong>"
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
    `;
  }

  const emailHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Invoice ${invoice.invoiceNumber} - ABRA Travels</title>
</head>
<body style="margin: 0; padding: 0; font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; background-color: #f4f4f4;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #f4f4f4; padding: 20px 0;">
    <tr>
      <td align="center">
        <!-- Main Container -->
        <table width="600" cellpadding="0" cellspacing="0" border="0" style="background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.1);">
          
          <!-- Header with Logo -->
          <tr>
            <td style="background: linear-gradient(135deg, #0066CC 0%, #0052A3 100%); padding: 30px 40px; position: relative;">
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td width="60%" style="vertical-align: top;">
                    ${logoBase64 ? `
                    <img src="${logoBase64}" alt="ABRA Travels" style="max-width: 200px; height: auto; display: block; margin-bottom: 10px;">
                    <p style="color: #ffffff; font-size: 13px; letter-spacing: 1.2px; margin: 8px 0 0 0; font-weight: 500;">YOUR JOURNEY, OUR COMMITMENT</p>
                    ` : `
                    <h1 style="color: #ffffff; margin: 0; font-size: 32px;">ABRA Travels</h1>
                    <p style="color: #ffffff; font-size: 13px; letter-spacing: 1.2px; margin: 8px 0 0 0; font-weight: 500;">YOUR JOURNEY, OUR COMMITMENT</p>
                    `}
                  </td>
                  <td width="40%" style="text-align: right; vertical-align: top;">
                    <h1 style="color: #ffffff; margin: 0; font-size: 28px; font-weight: bold;">INVOICE</h1>
                    <span style="display: inline-block; padding: 6px 14px; background-color: rgba(255,255,255,0.2); color: #ffffff; border-radius: 20px; font-size: 11px; font-weight: bold; letter-spacing: 0.5px; text-transform: uppercase; margin-top: 10px;">${invoice.status.replace(/_/g, ' ')}</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          
          <!-- Main Content -->
          <tr>
            <td style="padding: 40px;">
              
              <!-- Greeting -->
              <h2 style="font-size: 18px; font-weight: bold; color: #2C3E50; margin: 0 0 10px 0;">Dear ${invoice.customerName},</h2>
              
              <p style="font-size: 14px; color: #555555; margin: 0 0 20px 0; line-height: 1.8;">
                Thank you for choosing <strong>ABRA Travels</strong>. We're pleased to send you invoice <strong>${invoice.invoiceNumber}</strong> for your recent booking.
              </p>

              <!-- Trust Badge -->
              <table width="100%" cellpadding="15" cellspacing="0" border="0" style="background: #E8F5E9; border-left: 4px solid #27AE60; border-radius: 6px; margin: 20px 0;">
                <tr>
                  <td style="color: #1B5E20; font-size: 13px;">
                    ✅ <strong>Verified Invoice</strong> - This is an official invoice from ABRA Travels with GST registration 29AABCT1332L1ZM
                  </td>
                </tr>
              </table>

              <!-- Invoice Details Card -->
              <table width="100%" cellpadding="20" cellspacing="0" border="0" style="background-color: #F8F9FA; border-left: 4px solid #0066CC; border-radius: 6px; margin: 25px 0;">
                <tr>
                  <td>
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">Invoice Number:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">${invoice.invoiceNumber}</td>
                      </tr>
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">Invoice Date:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">${new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</td>
                      </tr>
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: ${invoice.orderNumber ? '12px' : '0'};">Due Date:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: ${invoice.orderNumber ? '12px' : '0'};">${new Date(invoice.dueDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</td>
                      </tr>
                      ${invoice.orderNumber ? `
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600;">Order Number:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right;">${invoice.orderNumber}</td>
                      </tr>
                      ` : ''}
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Amount Summary -->
              <table width="100%" cellpadding="22" cellspacing="0" border="0" style="background: linear-gradient(135deg, #F8F9FA 0%, #E8E8E8 100%); border-radius: 8px; border: 1px solid #DDDDDD; margin: 20px 0;">
                <tr>
                  <td>
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">Subtotal:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">₹${invoice.subTotal.toFixed(2)}</td>
                      </tr>
                      ${invoice.cgst > 0 ? `
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">CGST:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">₹${invoice.cgst.toFixed(2)}</td>
                      </tr>
                      ` : ''}
                      ${invoice.sgst > 0 ? `
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">SGST:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">₹${invoice.sgst.toFixed(2)}</td>
                      </tr>
                      ` : ''}
                      ${invoice.igst > 0 ? `
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: 12px;">IGST:</td>
                        <td style="font-size: 14px; color: #2C3E50; font-weight: bold; text-align: right; padding-bottom: 12px;">₹${invoice.igst.toFixed(2)}</td>
                      </tr>
                      ` : ''}
                      <tr>
                        <td colspan="2" style="border-top: 1px solid #DDDDDD; padding-top: 12px;"></td>
                      </tr>
                      <tr>
                        <td style="font-size: 17px; color: #666666; font-weight: 600; padding-top: 12px; padding-bottom: ${invoice.amountPaid > 0 ? '12px' : '0'};">Total Amount:</td>
                        <td style="font-size: 20px; color: #27AE60; font-weight: bold; text-align: right; padding-top: 12px; padding-bottom: ${invoice.amountPaid > 0 ? '12px' : '0'};">₹${invoice.totalAmount.toFixed(2)}</td>
                      </tr>
                      ${invoice.amountPaid > 0 ? `
                      <tr>
                        <td style="font-size: 14px; color: #666666; font-weight: 600; padding-bottom: ${invoice.amountDue > 0 ? '12px' : '0'};">Amount Paid:</td>
                        <td style="font-size: 14px; color: #27AE60; text-align: right; padding-bottom: ${invoice.amountDue > 0 ? '12px' : '0'};">₹${invoice.amountPaid.toFixed(2)}</td>
                      </tr>
                      ` : ''}
                      ${invoice.amountDue > 0 ? `
                      <tr>
                        <td style="font-size: 17px; color: #666666; font-weight: 600;">Balance Due:</td>
                        <td style="font-size: 20px; color: #E74C3C; font-weight: bold; text-align: right;">₹${invoice.amountDue.toFixed(2)}</td>
                      </tr>
                      ` : ''}
                    </table>
                  </td>
                </tr>
              </table>

              ${invoice.amountDue > 0 ? `
              <!-- Amount Due Highlight -->
              <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #FFEBEE 0%, #FFCDD2 100%); border-radius: 8px; border: 2px solid #E74C3C; margin: 20px 0;">
                <tr>
                  <td style="text-align: center;">
                    <p style="font-size: 24px; color: #E74C3C; font-weight: bold; margin: 0;">💰 Amount Due: ₹${invoice.amountDue.toFixed(2)}</p>
                  </td>
                </tr>
              </table>
              ` : ''}

              <hr style="border: none; height: 1px; background: linear-gradient(to right, transparent, #E0E0E0, transparent); margin: 30px 0;">

              <!-- ✅ Payment Information - Uses Selected Account -->
              <table width="100%" cellpadding="25" cellspacing="0" border="0" style="background: white; border-radius: 10px; border: 2px solid #0066CC; box-shadow: 0 2px 8px rgba(0,102,204,0.1); margin: 25px 0;">
                <tr>
                  <td>
                    <h3 style="color: #0066CC; margin: 0 0 20px 0; text-align: center; font-size: 18px;">💳 Secure Payment Methods</h3>
                    
                    ${paymentOptionsHtml}
                    
                    ${invoice.qrCodeUrl ? `
                    <!-- QR Code Payment -->
                    <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E8F5E9 0%, #C8E6C9 100%); border-radius: 8px; border-left: 4px solid #27AE60; margin-top: 20px;">
                      <tr>
                        <td style="text-align: center;">
                          <h4 style="margin: 0 0 15px 0; color: #27AE60; font-size: 16px;">📱 Scan QR Code to Pay Instantly</h4>
                          <img src="cid:qrcode" alt="Payment QR Code" style="width: 200px; height: 200px; border: 3px solid #27AE60; border-radius: 8px; display: block; margin: 0 auto;">
                          <p style="margin: 15px 0 0 0; font-size: 13px; color: #333;">Scan with Google Pay, PhonePe, Paytm, or any UPI app</p>
                        </td>
                      </tr>
                    </table>
                    ` : ''}
                    
                    <!-- Payment Proof -->
                    <table width="100%" cellpadding="18" cellspacing="0" border="0" style="background: linear-gradient(135deg, #E3F2FD 0%, #BBDEFB 100%); border-radius: 8px; border-left: 4px solid #0066CC; margin-top: 20px;">
                      <tr>
                        <td>
                          <p style="margin: 0 0 12px 0; font-size: 14px; color: #333;"><strong>📸 After Payment - Send Proof:</strong></p>
                          <ul style="margin: 12px 0; padding-left: 20px;">
                            <li style="margin: 8px 0; font-size: 13px; color: #333;">📧 Email: <a href="mailto:info@abratravels.com" style="color: #0066CC; text-decoration: none; font-weight: bold;">info@abratravels.com</a></li>
                            <li style="margin: 8px 0; font-size: 13px; color: #333;">📱 WhatsApp: <a href="https://wa.me/918867288076" style="color: #25D366; text-decoration: none; font-weight: bold;">+91 88672 88076</a></li>
                          </ul>
                          <p style="font-size: 12px; color: #555; margin: 10px 0 0 0;">
                            Include invoice number <strong>${invoice.invoiceNumber}</strong> when sharing payment proof
                          </p>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              ${invoice.customerNotes ? `
              <hr style="border: none; height: 1px; background: linear-gradient(to right, transparent, #E0E0E0, transparent); margin: 30px 0;">
              <table width="100%" cellpadding="15" cellspacing="0" border="0" style="background: #FFF9C4; border-radius: 6px; border-left: 4px solid #FBC02D;">
                <tr>
                  <td>
                    <p style="margin: 0 0 10px 0; color: #F57F17; font-weight: bold;">📝 Important Notes:</p>
                    <p style="margin: 0; color: #555; font-size: 14px;">${invoice.customerNotes}</p>
                  </td>
                </tr>
              </table>
              ` : ''}

              <hr style="border: none; height: 1px; background: linear-gradient(to right, transparent, #E0E0E0, transparent); margin: 30px 0;">

              <p style="font-size: 14px; color: #555555; margin: 25px 0; line-height: 1.8;">
                📎 The invoice PDF is attached to this email for your records. You can also download it anytime from your customer portal.
              </p>

              <p style="font-size: 16px; font-weight: bold; color: #0066CC; text-align: center; margin: 25px 0;">
                Thank you for trusting ABRA Travels! 🙏
              </p>
              
            </td>
          </tr>
          
          <!-- Footer -->
          <tr>
            <td style="background-color: #2C3E50; color: #ffffff; padding: 30px 40px; text-align: center;">
              <p style="margin: 0; font-weight: bold; font-size: 16px; color: #ffffff;">ABRA Travels</p>
              <p style="margin: 8px 0; font-style: italic; color: #ECF0F1; letter-spacing: 1px; font-size: 12px;">YOUR JOURNEY, OUR COMMITMENT</p>
              
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top: 15px;">
                <tr>
                  <td style="text-align: center;">
                    <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">📍 Bangalore, Karnataka, India</p>
                    <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">📧 info@abratravels.com</p>
                    <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">📱 +91 88672 88076</p>
                    <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">🌐 www.abratravels.com</p>
                    <p style="margin: 8px 0; color: #95A5A6; font-size: 12px;">🔖 GST: 29AABCT1332L1ZM</p>
                  </td>
                </tr>
              </table>

              <p style="margin-top: 25px; color: #7F8C8D; font-size: 11px;">
                © ${new Date().getFullYear()} ABRA Travels. All rights reserved.
              </p>
            </td>
          </tr>
          
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
  
  const mailOptions = {
    from: `"ABRA Travels - Billing" <${process.env.SMTP_USER}>`,
    to: invoice.customerEmail,
    subject: `📄 Invoice ${invoice.invoiceNumber} from ABRA Travels - ₹${invoice.totalAmount.toFixed(2)}`,
    html: emailHtml,
    attachments: [
      {
        filename: `Invoice-${invoice.invoiceNumber}.pdf`,
        path: pdfPath
      },
      ...(invoice.qrCodeUrl ? [{
        filename: 'qr-code.png',
        path: path.join(__dirname, '..', invoice.qrCodeUrl),
        cid: 'qrcode' // Content ID for embedding in email
      }] : [])
    ]
  };
  
  console.log('   📤 Sending email with selected payment account:', paymentInfo.accountName || 'Default');
  const result = await emailTransporter.sendMail(mailOptions);
  console.log('   ✅ Email sent successfully! Message ID:', result.messageId);
  
  return result;
}

async function sendPaymentReceiptEmail(invoice, payment) {
  console.log('📧 Preparing payment receipt email to:', invoice.customerEmail);
  
  const logoBase64 = getLogoBase64();
  
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
              <h1 style="color: #ffffff; margin: 0 0 5px 0; font-size: 28px;">ABRA Travels</h1>
              `}
              <p style="color: #ffffff; margin: 0; letter-spacing: 1px; font-size: 13px;">YOUR JOURNEY, OUR COMMITMENT</p>
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
            <td style="text-align: center; color: #95a5a6; font-size: 12px; padding: 35px 20px 20px 20px; border-top: 2px solid #27ae60;">
              <p style="margin: 0 0 10px 0;"><strong>ABRA Travels</strong> | YOUR JOURNEY, OUR COMMITMENT</p>
              <p style="margin: 0;">info@abratravels.com | +91 88672 88076 | GST: 29AABCT1332L1ZM</p>
              <p style="margin: 15px 0 0 0; font-size: 11px;">© ${new Date().getFullYear()} ABRA Travels. All rights reserved.</p>
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
    from: `"ABRA Travels - Billing" <${process.env.SMTP_USER}>`,
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
    const { status, customerId, fromDate, toDate, page = 1, limit = 20 } = req.query;
    
    const query = {};
    
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
    const invoice = await Invoice.findById(req.params.id);
    
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
    
    const invoice = new Invoice(invoiceData);
    await invoice.save();

    // ✅ COA: Debit Accounts Receivable + Credit Sales
// ✅ COA: Debit Accounts Receivable + Credit Sales + TDS + TCS
try {
  const [arId, salesId, taxId, tdsReceivableId, tcsPayableId] = await Promise.all([
    getSystemAccountId('Accounts Receivable'),
    getSystemAccountId('Sales'),
    getSystemAccountId('Tax Payable'),
    getSystemAccountId('TDS Receivable'),
    getSystemAccountId('TDS Payable'),
  ]);
  const txnDate = new Date(invoice.invoiceDate);

  if (arId) await postTransactionToCOA({
    accountId: arId, date: txnDate,
    description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: invoice.totalAmount, credit: 0
  });

  if (salesId) await postTransactionToCOA({
    accountId: salesId, date: txnDate,
    description: `Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: invoice.subTotal
  });

  if (taxId && (invoice.cgst + invoice.sgst) > 0) await postTransactionToCOA({
    accountId: taxId, date: txnDate,
    description: `GST on Invoice ${invoice.invoiceNumber}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: 0, credit: invoice.cgst + invoice.sgst
  });

  // ✅ TDS on Invoice (customer deducts TDS before paying)
  if (tdsReceivableId && invoice.tdsAmount > 0) await postTransactionToCOA({
    accountId: tdsReceivableId, date: txnDate,
    description: `TDS on Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
    referenceType: 'Invoice', referenceId: invoice._id,
    referenceNumber: invoice.invoiceNumber,
    debit: invoice.tdsAmount, credit: 0
  });

  // ✅ TCS on Invoice (you collect TCS from customer)
  if (tcsPayableId && invoice.tcsAmount > 0) await postTransactionToCOA({
    accountId: tcsPayableId, date: txnDate,
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
    const invoice = await Invoice.findById(req.params.id);
    
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
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    let pdfInfo;
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      pdfInfo = await generateInvoicePDF(invoice);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
    }
    
    await sendInvoiceEmail(invoice, invoice.pdfPath);
    
    if (invoice.status === 'DRAFT') {
      invoice.status = 'SENT';
    }
    
    invoice.emailsSent.push({
      sentTo: invoice.customerEmail,
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
    const invoice = await Invoice.findById(req.params.id);
    
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
  const [cashId, arId] = await Promise.all([
    getSystemAccountId('Undeposited Funds'),
    getSystemAccountId('Accounts Receivable'),
  ]);
  const txnDate = new Date(payment.paymentDate);
  if (cashId) await postTransactionToCOA({
    accountId: cashId, date: txnDate,
    description: `Payment received - ${invoice.invoiceNumber}`,
    referenceType: 'Payment', referenceId: payment.paymentId,
    referenceNumber: invoice.invoiceNumber,
    debit: payment.amount, credit: 0
  });
  if (arId) await postTransactionToCOA({
    accountId: arId, date: txnDate,
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
      await sendPaymentReceiptEmail(invoice, payment);
    } catch (emailError) {
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
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      const pdfInfo = await generateInvoicePDF(invoice);
      invoice.pdfPath = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
      await invoice.save();
    }
    
    res.download(invoice.pdfPath, `Invoice-${invoice.invoiceNumber}.pdf`);
  } catch (error) {
    console.error('Error downloading PDF:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

router.get('/:id/download-url', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
    if (!invoice) {
      return res.status(404).json({ success: false, error: 'Invoice not found' });
    }
    
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      const pdfInfo = await generateInvoicePDF(invoice);
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

router.delete('/:id', async (req, res) => {
  try {
    const invoice = await Invoice.findById(req.params.id);
    
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