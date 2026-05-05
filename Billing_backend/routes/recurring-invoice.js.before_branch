// ============================================================================
// RECURRING INVOICE ROUTES - Complete Backend Implementation
// ============================================================================
// File: backend/routes/recurring-invoice.js
// Handles all recurring invoice operations including auto-generation
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const cron = require('node-cron');
const nodemailer = require('nodemailer');
const { verifyFinanceJWT: verifyToken } = require('../middleware/finance_jwt');

// Invoice Schema for child invoices lookup
const invoiceSchema = new mongoose.Schema({}, { strict: false });
const Invoice = mongoose.models.Invoice || mongoose.model('Invoice', invoiceSchema);

// ============================================================================
// RECURRING INVOICE SCHEMA
// ============================================================================

const recurringInvoiceSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  profileName: {
    type: String,
    required: true,
    trim: true,
    index: true
  },
  
  // Customer Information
  customerId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Customer',
    required: true,
    index: true
  },
  customerName: {
    type: String,
    required: true
  },
  customerEmail: {
    type: String,
    required: true
  },
  customerPhone: {
  type: String,
  default: ''
},
  // Recurrence Settings
  repeatEvery: {
    type: Number,
    required: true,
    min: 1,
    default: 1
  },
  repeatUnit: {
    type: String,
    required: true,
    enum: ['day', 'week', 'month', 'year'],
    default: 'month'
  },
  startDate: {
    type: Date,
    required: true,
    default: Date.now
  },
  endDate: {
    type: Date,
    default: null // null means never ends
  },
  maxOccurrences: {
    type: Number,
    default: null // null means unlimited
  },
  nextInvoiceDate: {
    type: Date,
    required: true,
    index: true
  },
  
  // Invoice Template Settings
  orderNumber: String,
  terms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30'
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
  
  // Tax Settings
  tdsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  tcsRate: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  gstRate: {
    type: Number,
    default: 18,
    min: 0,
    max: 100
  },
  
  // Automation Settings
  invoiceCreationMode: {
    type: String,
    enum: ['draft', 'auto_send'],
    default: 'draft'
  },
  autoApplyPayments: {
    type: Boolean,
    default: false
  },
  autoApplyCreditNotes: {
    type: Boolean,
    default: false
  },
  suspendOnFailure: {
    type: Boolean,
    default: false
  },
  disableAutoSaveCard: {
    type: Boolean,
    default: true
  },
  
  // Calculated Amounts (template preview)
  subTotal: {
    type: Number,
    default: 0
  },
  totalAmount: {
    type: Number,
    default: 0
  },
  
  // Status & Tracking
  status: {
    type: String,
    enum: ['ACTIVE', 'PAUSED', 'STOPPED'],
    default: 'ACTIVE',
    index: true
  },
  childInvoices: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Invoice'
  }],
  lastGeneratedDate: Date,
  totalInvoicesGenerated: {
    type: Number,
    default: 0
  },
  
  // Audit Trail
  createdBy: {
    type: String,
    required: true
  },
  updatedBy: String,
  createdAt: {
    type: Date,
    default: Date.now,
    index: true
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Pre-save middleware to calculate amounts
recurringInvoiceSchema.pre('save', async function() {
  this.subTotal = this.items.reduce((sum, item) => sum + item.amount, 0);
  const tdsAmount = (this.subTotal * this.tdsRate) / 100;
  const tcsAmount = (this.subTotal * this.tcsRate) / 100;
  const gstBase = this.subTotal - tdsAmount + tcsAmount;
  const gstAmount = (gstBase * this.gstRate) / 100;
  this.totalAmount = this.subTotal - tdsAmount + tcsAmount + gstAmount;
});

// Indexes for performance
recurringInvoiceSchema.index({ status: 1, nextInvoiceDate: 1 });
recurringInvoiceSchema.index({ customerId: 1, status: 1 });

const RecurringInvoice = mongoose.models.RecurringInvoice || mongoose.model('RecurringInvoice', recurringInvoiceSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Calculate next invoice date
function calculateNextInvoiceDate(currentDate, repeatEvery, repeatUnit) {
  const nextDate = new Date(currentDate);
  
  switch (repeatUnit) {
    case 'day':
      nextDate.setDate(nextDate.getDate() + repeatEvery);
      break;
    case 'week':
      nextDate.setDate(nextDate.getDate() + (repeatEvery * 7));
      break;
    case 'month':
      nextDate.setMonth(nextDate.getMonth() + repeatEvery);
      break;
    case 'year':
      nextDate.setFullYear(nextDate.getFullYear() + repeatEvery);
      break;
  }
  
  return nextDate;
}

// Calculate due date based on terms
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

// Generate invoice number (org-scoped)
async function generateInvoiceNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(Invoice, 'invoiceNumber', 'INV', orgId);
}

// ============================================================================
// CHILD INVOICE GENERATION LOGIC
// ============================================================================

async function generateChildInvoice(profile) {
  try {
    console.log(`🔄 Generating invoice for profile: ${profile.profileName}`);
    
    // Generate invoice number
    const invoiceNumber = await generateInvoiceNumber(profile.orgId || null);
    const invoiceDate = new Date();
    const dueDate = calculateDueDate(invoiceDate, profile.terms);
    
    // Calculate amounts
    const subTotal    = profile.items.reduce((sum, item) => sum + item.amount, 0);
    const tdsAmount   = (subTotal * (profile.tdsRate || 0)) / 100;
    const tcsAmount   = (subTotal * (profile.tcsRate || 0)) / 100;
    const gstBase     = subTotal - tdsAmount + tcsAmount;
    const gstAmount   = (gstBase * (profile.gstRate || 18)) / 100;
    const totalAmount = subTotal - tdsAmount + tcsAmount + gstAmount;
    const cgst        = gstAmount / 2;
    const sgst        = gstAmount / 2;

    // Create invoice data from profile template
    const invoiceData = {
      invoiceNumber,
      orgId:               profile.orgId || null,
      customerId:          profile.customerId,
      customerName:        profile.customerName,
      customerEmail:       profile.customerEmail,
      orderNumber:         profile.orderNumber,
      invoiceDate,
      terms:               profile.terms,
      dueDate,
      salesperson:         profile.salesperson,
      subject:             profile.subject,
      items:               profile.items,
      customerNotes:       profile.customerNotes,
      termsAndConditions:  profile.termsAndConditions,
      tdsRate:             profile.tdsRate,
      tdsAmount,
      tcsRate:             profile.tcsRate,
      tcsAmount,
      gstRate:             profile.gstRate,
      cgst,
      sgst,
      igst:                0,
      subTotal,
      totalAmount,
      amountPaid:          0,
      amountDue:           totalAmount,
      status:              profile.invoiceCreationMode === 'auto_send' ? 'SENT' : 'DRAFT',
      payments:            [],
      createdBy:           'RECURRING_SYSTEM'
    };
    
    // Create the invoice
    const invoice = new Invoice(invoiceData);
    await invoice.save();
    
    console.log(`✅ Invoice created: ${invoice.invoiceNumber}`);

    // ✅ COA Posting
    try {
      const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

      const profileOrgId = profile.orgId || null;
      const [arId, salesId, taxId] = await Promise.all([
        ChartOfAccount.findOne({ accountName: 'Accounts Receivable', isSystemAccount: true, orgId: profileOrgId }).select('_id').lean().then(a => a?._id),
        ChartOfAccount.findOne({ accountName: 'Sales',               isSystemAccount: true, orgId: profileOrgId }).select('_id').lean().then(a => a?._id),
        ChartOfAccount.findOne({ accountName: 'Tax Payable',         isSystemAccount: true, orgId: profileOrgId }).select('_id').lean().then(a => a?._id),
      ]);

      // Debit Accounts Receivable
      if (arId) await postTransactionToCOA({
        accountId:       arId,
        orgId:           profileOrgId,
        date:            invoiceDate,
        description:     `Recurring Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit:           totalAmount,
        credit:          0,
      });

      // Credit Sales
      if (salesId) await postTransactionToCOA({
        accountId:       salesId,
        orgId:           profileOrgId,
        date:            invoiceDate,
        description:     `Recurring Invoice ${invoice.invoiceNumber} - ${invoice.customerName}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit:           0,
        credit:          subTotal,
      });

      // Credit Tax Payable
      if (taxId && gstAmount > 0) await postTransactionToCOA({
        accountId:       taxId,
        orgId:           profileOrgId,
        date:            invoiceDate,
        description:     `GST on Recurring Invoice ${invoice.invoiceNumber}`,
        referenceType:   'Invoice',
        referenceId:     invoice._id,
        referenceNumber: invoice.invoiceNumber,
        debit:           0,
        credit:          cgst + sgst,
      });

      console.log(`✅ COA posted for recurring invoice: ${invoice.invoiceNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA post error (recurring invoice):', coaErr.message);
      // Non-critical — invoice is already saved
    }
    
    // Update profile
    profile.childInvoices.push(invoice._id);
    profile.lastGeneratedDate = new Date();
    profile.totalInvoicesGenerated += 1;
    
    // Calculate next invoice date
    profile.nextInvoiceDate = calculateNextInvoiceDate(
      invoiceDate,
      profile.repeatEvery,
      profile.repeatUnit
    );
    
    // Check if we should stop (max occurrences reached)
    if (profile.maxOccurrences && profile.totalInvoicesGenerated >= profile.maxOccurrences) {
      profile.status = 'STOPPED';
      console.log(`🛑 Profile stopped: Max occurrences (${profile.maxOccurrences}) reached`);
    }
    
    // Check if we should stop (end date reached)
    if (profile.endDate && profile.nextInvoiceDate > profile.endDate) {
      profile.status = 'STOPPED';
      console.log(`🛑 Profile stopped: End date reached`);
    }
    
    await profile.save();
    
    // Send email if auto-send is enabled
    if (profile.invoiceCreationMode === 'auto_send') {
      try {
        await sendInvoiceEmail(invoice);
        console.log(`📧 Invoice emailed to: ${invoice.customerEmail}`);
      } catch (emailError) {
        console.error(`❌ Email failed:`, emailError.message);
      }
    }
    
    return invoice;
    
  } catch (error) {
    console.error(`❌ Error generating child invoice:`, error);
    throw error;
  }
}


// ============================================================================
// EMAIL SERVICE FOR RECURRING INVOICES
// ============================================================================

// Email transporter configuration
const emailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: process.env.SMTP_PORT || 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD
  }
});

// Import payment defaults
const DEFAULT_PAYMENT = require('../config/payment-defaults');

// Send invoice email for recurring invoices
async function sendInvoiceEmail(invoice) {
  try {
    // Fetch org details from DB
    let orgData = null;
    try {
      const OrgModel = mongoose.models.Organization ||
        mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
      orgData = await OrgModel.findOne({ orgId: invoice.orgId }).lean();
    } catch (_) {}

    const orgName  = orgData?.orgName   || 'Billing Team';
    const orgGST   = orgData?.gstNumber || '';
    const orgPhone = orgData?.phone     || '';
    const orgEmail = orgData?.email     || '';

    // Use custom payment details if provided, otherwise use org banking then defaults
    const paymentInfo = invoice.paymentDetails && Object.keys(invoice.paymentDetails).length > 0
      ? invoice.paymentDetails
      : {
          accountHolder: DEFAULT_PAYMENT.bankAccount.accountHolder,
          bankAccount: DEFAULT_PAYMENT.bankAccount.accountNumber,
          ifscCode: DEFAULT_PAYMENT.bankAccount.ifscCode,
          bankName: DEFAULT_PAYMENT.bankAccount.bankName,
          upiId: DEFAULT_PAYMENT.upi.upiId,
          officeAddress: DEFAULT_PAYMENT.office.fullAddress
        };

    const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #2C3E50 0%, #34495E 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
    .header h1 { margin: 0; font-size: 28px; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
    .recurring-badge { background: #e3f2fd; color: #1976d2; padding: 10px 15px; border-radius: 20px; display: inline-block; margin: 10px 0; font-size: 12px; font-weight: bold; }
    .invoice-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #3498DB; }
    .invoice-detail { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ecf0f1; }
    .invoice-detail:last-child { border-bottom: none; }
    .label { font-weight: bold; color: #7f8c8d; }
    .value { color: #2c3e50; font-weight: 600; }
    .total-amount { font-size: 24px; color: #27ae60; text-align: center; margin: 20px 0; padding: 15px; background: #e8f8f5; border-radius: 8px; }
    .payment-section { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border: 2px solid #3498DB; }
    .payment-method { background: #f8f9fa; padding: 15px; border-radius: 8px; margin: 10px 0; border-left: 4px solid #3498DB; }
    .payment-method h4 { margin: 0 0 10px 0; color: #2c3e50; }
    .payment-detail-item { padding: 5px 0; }
    .button { display: inline-block; padding: 12px 30px; background: #3498DB; color: white; text-decoration: none; border-radius: 5px; margin: 20px 0; }
    .button:hover { background: #2980B9; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ecf0f1; }
    .warning-box { background: #fff3cd; padding: 15px; border-radius: 8px; border-left: 4px solid #ffc107; margin: 20px 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>${orgName}</h1>
      ${orgGST   ? `<p style="margin: 4px 0 0 0; opacity: 0.8; font-size: 12px;">GST: ${orgGST}</p>`   : ''}
      ${orgPhone ? `<p style="margin: 4px 0 0 0; opacity: 0.8; font-size: 12px;">${orgPhone}</p>`       : ''}
      ${orgEmail ? `<p style="margin: 4px 0 0 0; opacity: 0.8; font-size: 12px;">${orgEmail}</p>`       : ''}
      <div class="recurring-badge">🔄 RECURRING INVOICE</div>
    </div>
    
    <div class="content">
      <h2 style="color: #2c3e50; margin-top: 0;">Your Recurring Invoice is Ready</h2>
      
      <p>Dear <strong>${invoice.customerName}</strong>,</p>
      
      <p>This is your automatically generated recurring invoice. Please find the details below:</p>
      
      <div class="invoice-box">
        <div class="invoice-detail">
          <span class="label">Invoice Number:</span>
          <span class="value">${invoice.invoiceNumber}</span>
        </div>
        <div class="invoice-detail">
          <span class="label">Invoice Date:</span>
          <span class="value">${new Date(invoice.invoiceDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        <div class="invoice-detail">
          <span class="label">Due Date:</span>
          <span class="value">${new Date(invoice.dueDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</span>
        </div>
        <div class="invoice-detail">
          <span class="label">Payment Terms:</span>
          <span class="value">${invoice.terms}</span>
        </div>
      </div>
      
      <div class="total-amount">
        <div style="font-size: 14px; color: #7f8c8d; margin-bottom: 5px;">Total Amount Due</div>
        <strong>Rs.${invoice.totalAmount.toFixed(2)}</strong>
      </div>
      
      <div class="warning-box">
        <strong>⚠️ Payment Instructions:</strong><br>
        Please make the payment before <strong>${new Date(invoice.dueDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</strong> to avoid late fees.
      </div>
      
      <div class="payment-section">
        <h3 style="color: #2c3e50; margin-top: 0; text-align: center;">💳 Payment Methods</h3>
        
        <!-- Bank Transfer -->
        <div class="payment-method">
          <h4>🏦 Option 1: Bank Transfer / NEFT / RTGS / IMPS</h4>
          <div class="payment-detail-item"><strong>Account Holder:</strong> ${paymentInfo.accountHolder || 'Abra Fleet Management'}</div>
          <div class="payment-detail-item"><strong>Account Number:</strong> ${paymentInfo.bankAccount || 'Not provided'}</div>
          <div class="payment-detail-item"><strong>IFSC Code:</strong> ${paymentInfo.ifscCode || 'Not provided'}</div>
          <div class="payment-detail-item"><strong>Bank Name:</strong> ${paymentInfo.bankName || 'Not provided'}</div>
          <div style="margin-top: 10px; padding: 10px; background: #e8f4f8; border-radius: 5px; font-size: 13px;">
            💡 <strong>Note:</strong> Please mention invoice number <strong>${invoice.invoiceNumber}</strong> in payment remarks
          </div>
        </div>
        
        <!-- UPI Payment -->
        ${paymentInfo.upiId ? `
        <div class="payment-method">
          <h4>📱 Option 2: UPI Payment</h4>
          <div class="payment-detail-item"><strong>UPI ID:</strong> <span style="color: #3498DB; font-weight: bold;">${paymentInfo.upiId}</span></div>
          <div style="margin-top: 10px; padding: 10px; background: #e8f4f8; border-radius: 5px; font-size: 13px;">
            💡 Pay instantly using Google Pay, PhonePe, Paytm, or any UPI app
          </div>
        </div>
        ` : ''}
        
        <!-- Cash/Cheque -->
        ${paymentInfo.officeAddress ? `
        <div class="payment-method">
          <h4>💵 Option 3: Cash / Cheque Payment</h4>
          <div class="payment-detail-item"><strong>Visit Office:</strong></div>
          <div style="padding: 10px; background: #f8f9fa; border-radius: 5px; margin-top: 5px;">
            ${paymentInfo.officeAddress}
          </div>
          <div style="margin-top: 10px; padding: 10px; background: #e8f4f8; border-radius: 5px; font-size: 13px;">
            💡 Cheques should be drawn in favor of "<strong>${paymentInfo.accountHolder || 'Abra Fleet Management'}</strong>"
          </div>
        </div>
        ` : ''}
        
        <!-- Payment Proof -->
        <div style="margin-top: 20px; padding: 15px; background: #fff3cd; border-radius: 8px; border-left: 4px solid #ffc107;">
          <strong>📸 Important:</strong> Please share payment proof after making the payment:
          <ul style="margin: 10px 0;">
            ${orgEmail ? `<li>📧 Email: ${orgEmail}</li>` : ''}
            ${orgPhone ? `<li>📞 WhatsApp: ${orgPhone}</li>` : ''}
          </ul>
        </div>
      </div>
      
      <div style="text-align: center; margin: 30px 0;">
        <p style="background: #e3f2fd; padding: 15px; border-radius: 8px; border-left: 4px solid #1976d2;">
          <strong>🔄 This is a recurring invoice</strong><br>
          <span style="font-size: 14px; color: #666;">You will receive this invoice automatically based on your subscription schedule.</span>
        </p>
      </div>
      
      <div style="background: white; padding: 20px; border-radius: 8px; margin-top: 20px;">
        <h3 style="color: #2c3e50; margin-top: 0;">📞 Need Help?</h3>
        <p>If you have any questions about this invoice or your recurring billing, please contact us:</p>
        <ul style="list-style: none; padding: 0;">
          ${orgEmail ? `<li style="padding: 5px 0;">📧 Email: ${orgEmail}</li>` : ''}
          ${orgPhone ? `<li style="padding: 5px 0;">📞 Phone: ${orgPhone}</li>` : ''}
          </ul>
      </div>
    </div>
    
    <div class="footer">
      <p><strong>${orgName}</strong></p>
      ${orgGST   ? `<p>GST: ${orgGST}</p>`   : ''}
      ${orgEmail ? `<p>${orgEmail}</p>`        : ''}
      ${orgPhone ? `<p>${orgPhone}</p>`        : ''}
      <p>This is an automated email from your recurring invoice subscription.</p>
    </div>
  </div>
</body>
</html>
    `;
    
    const mailOptions = {
      from: `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
      to: invoice.customerEmail,
      subject: `🔄 Recurring Invoice ${invoice.invoiceNumber} - Rs.${invoice.totalAmount.toFixed(2)}`,
      html: emailHtml
    };
    
    await emailTransporter.sendMail(mailOptions);
    console.log(`✅ Recurring invoice email sent successfully to: ${invoice.customerEmail}`);
    return true;
    
  } catch (error) {
    console.error(`❌ Failed to send recurring invoice email:`, error);
    throw error;
  }
}

// ============================================================================
// CRON JOB - Auto-generate invoices daily at 6 AM
// ============================================================================

cron.schedule('0 6 * * *', async () => {
  console.log('🔄 Running recurring invoice cron job...');
  
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0); // Start of day
    
    // Find all active profiles where nextInvoiceDate is today or earlier
    const profiles = await RecurringInvoice.find({
      status: 'ACTIVE',
      nextInvoiceDate: { $lte: today }
    });
    
    console.log(`📋 Found ${profiles.length} profiles ready for invoice generation`);
    
    for (const profile of profiles) {
      try {
        await generateChildInvoice(profile);
      } catch (error) {
        console.error(`❌ Failed to generate invoice for profile ${profile.profileName}:`, error);
        
        // If suspendOnFailure is enabled, pause the profile
        if (profile.suspendOnFailure) {
          profile.status = 'PAUSED';
          await profile.save();
          console.log(`⏸️  Profile paused due to failure: ${profile.profileName}`);
        }
      }
    }
    
    console.log('✅ Recurring invoice cron job completed');
    
  } catch (error) {
    console.error('❌ Cron job error:', error);
  }
});

console.log('⏰ Recurring invoice cron job scheduled (daily at 6 AM)');

// ============================================================================
// API ROUTES
// ============================================================================

// GET /api/invoices/recurring - List all recurring invoice profiles
router.get('/', async (req, res) => {
  try {
    const { status, customerId, page = 1, limit = 20 } = req.query;
    
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    if (status) query.status = status;
    if (customerId) query.customerId = customerId;
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const profiles = await RecurringInvoice.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await RecurringInvoice.countDocuments(query);
    
    console.log(`📋 Retrieved ${profiles.length} recurring invoice profiles`);
    
    res.json({
      success: true,
      data: profiles,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('Error fetching recurring invoices:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/invoices/recurring/stats - Get statistics
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const stats = await RecurringInvoice.aggregate([
      { $match: orgFilter },
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 },
          totalRevenue: { $sum: '$totalAmount' },
          totalInvoices: { $sum: '$totalInvoicesGenerated' }
        }
      }
    ]);
    
    const overallStats = {
      totalProfiles: 0,
      activeProfiles: 0,
      pausedProfiles: 0,
      stoppedProfiles: 0,
      totalInvoicesGenerated: 0,
      totalRecurringRevenue: 0
    };
    
    stats.forEach(stat => {
      overallStats.totalProfiles += stat.count;
      overallStats.totalInvoicesGenerated += stat.totalInvoices;
      overallStats.totalRecurringRevenue += stat.totalRevenue;
      
      if (stat._id === 'ACTIVE') overallStats.activeProfiles = stat.count;
      if (stat._id === 'PAUSED') overallStats.pausedProfiles = stat.count;
      if (stat._id === 'STOPPED') overallStats.stoppedProfiles = stat.count;
    });
    
    res.json({ success: true, data: overallStats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/invoices/recurring/:id - Get single profile
router.get('/:id', async (req, res) => {
  try {
    const profile = await RecurringInvoice.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring invoice profile not found' });
    }
    
    res.json({ success: true, data: profile });
  } catch (error) {
    console.error('Error fetching recurring invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices/recurring - Create new profile
router.post('/', async (req, res) => {
  try {
    const profileData = req.body;
    
    // Validate required fields
    if (!profileData.profileName || !profileData.customerId || !profileData.customerName) {
      return res.status(400).json({
        success: false,
        error: 'Profile name, customer ID, and customer name are required'
      });
    }
    
    // Set creator
    profileData.createdBy = req.user?.email || req.user?.uid || 'system';
    profileData.orgId = req.user?.orgId || null;
    
    // Set next invoice date if not provided
    if (!profileData.nextInvoiceDate) {
      profileData.nextInvoiceDate = calculateNextInvoiceDate(
        profileData.startDate || new Date(),
        profileData.repeatEvery || 1,
        profileData.repeatUnit || 'month'
      );
    }
    
    const profile = new RecurringInvoice(profileData);
    await profile.save();
    
    console.log(`✅ Recurring invoice profile created: ${profile.profileName}`);
    
    res.status(201).json({
      success: true,
      message: 'Recurring invoice profile created successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error creating recurring invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/invoices/recurring/:id - Update profile
router.put('/:id', async (req, res) => {
  try {
    const profile = await RecurringInvoice.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring invoice profile not found' });
    }
    
    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    // Recalculate next invoice date if recurrence settings changed
    if (updates.repeatEvery || updates.repeatUnit || updates.startDate) {
      updates.nextInvoiceDate = calculateNextInvoiceDate(
        updates.startDate || profile.startDate,
        updates.repeatEvery || profile.repeatEvery,
        updates.repeatUnit || profile.repeatUnit
      );
    }
    
    Object.assign(profile, updates);
    await profile.save();
    
    console.log(`✅ Recurring invoice profile updated: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring invoice profile updated successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error updating recurring invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices/recurring/:id/pause - Pause profile
router.post('/:id/pause', async (req, res) => {
  try {
    const profile = await RecurringInvoice.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring invoice profile not found' });
    }
    
    profile.status = 'PAUSED';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`⏸️  Recurring invoice profile paused: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring invoice profile paused successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error pausing recurring invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices/recurring/:id/resume - Resume profile
router.post('/:id/resume', async (req, res) => {
  try {
    const profile = await RecurringInvoice.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring invoice profile not found' });
    }
    
    profile.status = 'ACTIVE';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`▶️  Recurring invoice profile resumed: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring invoice profile resumed successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error resuming recurring invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices/recurring/:id/stop - Stop profile permanently
router.post('/:id/stop', async (req, res) => {
  try {
    const profile = await RecurringInvoice.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring invoice profile not found' });
    }
    
    profile.status = 'STOPPED';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`🛑 Recurring invoice profile stopped: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring invoice profile stopped successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error stopping recurring invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/invoices/recurring/:id/generate - Manually generate invoice
router.post('/:id/generate', async (req, res) => {
  try {
    const profile = await RecurringInvoice.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring invoice profile not found' });
    }
    
    const invoice = await generateChildInvoice(profile);
    
    console.log(`✅ Manual invoice generated: ${invoice.invoiceNumber}`);
    
    res.json({
      success: true,
      message: 'Invoice generated successfully',
      data: {
        invoiceId: invoice._id,
        invoiceNumber: invoice.invoiceNumber,
        message: 'Invoice generated successfully from recurring profile'
      }
    });
  } catch (error) {
    console.error('Error generating manual invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/invoices/recurring/:id/child-invoices - Get child invoices
router.get('/:id/child-invoices', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({ 
        success: false, 
        error: 'Invalid recurring invoice ID' 
      });
    }
    
    const profile = await RecurringInvoice.findOne({
      _id: id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ 
        success: false, 
        error: 'Recurring invoice profile not found' 
      });
    }
    
    // Get child invoices
    const childInvoiceIds = profile.childInvoices || [];
    
    if (childInvoiceIds.length === 0) {
      return res.json({
        success: true,
        data: {
          invoices: [],
          total: 0
        }
      });
    }
    
    const invoices = await Invoice.find({
      _id: { $in: childInvoiceIds }
    })
    .sort({ createdAt: -1 })
    .select('invoiceNumber invoiceDate dueDate totalAmount status createdAt')
    .lean();
    
    res.json({
      success: true,
      data: {
        invoices,
        total: invoices.length
      }
    });
  } catch (error) {
    console.error('❌ Error fetching child invoices:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// DELETE /api/invoices/recurring/:id - Delete profile
router.delete('/:id', async (req, res) => {
  try {
    const profile = await RecurringInvoice.findOne({
      _id: req.params.id,
      orgId: req.user?.orgId
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring invoice profile not found' });
    }
    
    await profile.deleteOne();
    
    console.log(`✅ Recurring invoice profile deleted: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring invoice profile deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting recurring invoice:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Export router and model
module.exports = router;
module.exports.RecurringInvoice = RecurringInvoice;