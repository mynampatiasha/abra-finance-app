// ============================================================================
// PAYMENTS RECEIVED ROUTES - ZOHO BOOKS EXACT WORKFLOW
// ============================================================================
// File: backend/routes/payments-received.js
// Workflow: Record Payment with Proofs → Update Invoice Status → Send Email with Proofs
// Email is sent ONLY when payment is recorded with proofs (not on "Mark as Paid")
// ============================================================================


const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT: verifyToken } = require('../middleware/finance_jwt');
const { uploadPaymentProofs } = require('../middleware/upload');
const path = require('path');
const fs = require('fs');


// ✅ COA Helper
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

async function getSystemAccountId(name, orgId = null) {
  try {
    const acc = await ChartOfAccount.findOne({
      accountName: name,
      $or: [
        { isSystemAccount: true },
        { isSystemAccount: { $exists: false } }
      ],
      ...(orgId ? { orgId } : {})
    }).select('_id').lean();

    if (!acc) {
      // Fallback: try without orgId filter
      const fallback = await ChartOfAccount.findOne({
        accountName: name,
      }).select('_id').lean();
      return fallback ? fallback._id : null;
    }
    return acc._id;
  } catch (e) {
    console.error(`COA lookup error for "${name}":`, e.message);
    return null;
  }
}
// Import nodemailer - use dynamic import or check if it's properly installed
let nodemailer;
try {
  nodemailer = require('nodemailer');
  if (!nodemailer || !nodemailer.createTransport) {
    console.warn('⚠️ Nodemailer not properly loaded, email features will be disabled');
    nodemailer = null;
  }
} catch (error) {
  console.warn('⚠️ Nodemailer not available, email features will be disabled:', error.message);
  nodemailer = null;
}

// Use shared Finance DB connection
const { getFinanceDb } = require('../config/database');

// Lazy db accessor — resolves to the shared Finance DB on first use
const dbProxy = new Proxy({}, {
  get(_, prop) {
    return getFinanceDb()[prop];
  }
});
const db = dbProxy;

// ============================================================================
// EMAIL SERVICE FOR PAYMENT RECEIPTS
// ============================================================================

let emailTransporter = null;
if (nodemailer) {
  try {
    emailTransporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: process.env.SMTP_PORT || 587,
      secure: false,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASSWORD
      }
    });
    console.log('✅ Email transporter configured for payment receipts');
  } catch (error) {
    console.warn('⚠️ Failed to configure email transporter:', error.message);
  }
}

// Send payment receipt email with proofs attached
async function sendPaymentReceiptEmail(payment, invoice, proofPaths) {
  if (!emailTransporter) {
    console.warn('⚠️ Email transporter not available, skipping email send');
    return false;
  }

  // Fetch org details from DB
  let orgData = null;
  try {
    const mongoose = require('mongoose');
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    orgData = await OrgModel.findOne({ orgId: payment.orgId }).lean();
  } catch (_) {}
  const orgName  = orgData?.orgName   || 'Billing Team';
  const orgGST   = orgData?.gstNumber || '';
  const orgPhone = orgData?.phone     || '';
  const orgEmail = orgData?.email     || '';

  try {
    const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #27ae60 0%, #229954 100%); color: white; padding: 30px; text-align: center; border-radius: 8px 8px 0 0; }
    .content { background: #f8f9fa; padding: 30px; border-radius: 0 0 8px 8px; }
    .success-badge { background: #d4edda; color: #155724; padding: 15px; border-radius: 8px; text-align: center; margin: 20px 0; border: 1px solid #c3e6cb; }
    .payment-box { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #27ae60; }
    .payment-detail { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #ecf0f1; }
    .footer { text-align: center; color: #95a5a6; font-size: 12px; margin-top: 30px; }
    .proof-notice { background: #fff3cd; padding: 15px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #ffc107; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>✅ Payment Received</h1>
      <p>Thank you for your payment!</p>
    </div>
    <div class="content">
      <div class="success-badge">
        <h2 style="margin: 0;">Payment Successful</h2>
        <p style="margin: 10px 0 0 0;">We have received your payment of ₹${payment.amountReceived.toFixed(2)}</p>
      </div>
      
      <div class="payment-box">
        <h3 style="margin-top: 0; color: #2c3e50;">Payment Details:</h3>
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Payment Number:</span>
          <span style="font-weight: bold;">${payment.paymentNumber}</span>
        </div>
        ${invoice ? `
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Invoice Number:</span>
          <span style="font-weight: bold;">${invoice.invoiceNumber}</span>
        </div>
        ` : ''}
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Amount Paid:</span>
          <span style="font-weight: bold; color: #27ae60;">₹${payment.amountReceived.toFixed(2)}</span>
        </div>
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Payment Date:</span>
          <span>${payment.paymentDate}</span>
        </div>
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Payment Mode:</span>
          <span>${payment.paymentMode}</span>
        </div>
        ${payment.reference ? `
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Reference Number:</span>
          <span>${payment.reference}</span>
        </div>
        ` : ''}
        ${payment.bankCharges > 0 ? `
        <div class="payment-detail">
          <span style="color: #7f8c8d;">Bank Charges:</span>
          <span style="color: #e74c3c;">₹${payment.bankCharges.toFixed(2)}</span>
        </div>
        ` : ''}
        ${invoice ? `
        <div class="payment-detail" style="border: none; font-weight: bold; font-size: 16px; margin-top: 15px; padding-top: 15px; border-top: 2px solid #27ae60;">
          <span style="color: #2c3e50;">Remaining Balance:</span>
          <span style="color: ${invoice.amountDue > 0 ? '#e74c3c' : '#27ae60'};">₹${invoice.amountDue.toFixed(2)}</span>
        </div>
        ` : ''}
      </div>
      
      ${proofPaths && proofPaths.length > 0 ? `
      <div class="proof-notice">
        <strong>📎 Payment Proofs Attached:</strong><br>
        We have attached ${proofPaths.length} payment proof document(s) to this email for your records.
      </div>
      ` : ''}
      
      ${payment.notes ? `
      <div style="background: white; padding: 15px; border-radius: 8px; margin: 20px 0;">
        <strong style="color: #2c3e50;">Notes:</strong><br>
        <p style="margin: 10px 0 0 0; color: #7f8c8d;">${payment.notes}</p>
      </div>
      ` : ''}
      
      <div style="background: white; padding: 20px; border-radius: 8px; margin-top: 20px;">
        <h3 style="color: #2c3e50; margin-top: 0;">📞 Need Help?</h3>
        <p>If you have any questions about this payment, please contact us:</p>
        <ul style="list-style: none; padding: 0;">
          ${orgEmail ? `<li style="padding: 5px 0;">📧 Email: ${orgEmail}</li>` : ''}
          ${orgPhone ? `<li style="padding: 5px 0;">📞 Phone: ${orgPhone}</li>` : ''}
          <li style="padding: 5px 0;">🕐 Business Hours: Mon-Fri, 9 AM - 6 PM IST</li>
        </ul>
      </div>
    </div>
    
    <div class="footer">
      <p><strong>${orgName}</strong></p>
      ${orgGST ? `<p>GST: ${orgGST}</p>` : ''}
      <p>This is an automated email. Please do not reply to this message.</p>
    </div>
  </div>
</body>
</html>
    `;

    const attachments = [];
    
    // Attach payment proof files
    if (proofPaths && proofPaths.length > 0) {
      proofPaths.forEach((proofPath, index) => {
        if (fs.existsSync(proofPath)) {
          attachments.push({
            filename: `Payment-Proof-${index + 1}${path.extname(proofPath)}`,
            path: proofPath
          });
        }
      });
    }

    const mailOptions = {
      from: `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
      to: payment.customerEmail || invoice?.customerEmail,
      subject: `Payment Receipt - ${payment.paymentNumber} - Rs.${payment.amountReceived.toFixed(2)}`,
      html: emailHtml,
      attachments: attachments
    };

    await emailTransporter.sendMail(mailOptions);
    console.log(`📧 Payment receipt email sent to ${payment.customerEmail || invoice?.customerEmail}`);
    return true;
  } catch (error) {
    console.error('❌ Failed to send payment receipt email:', error);
    throw error;
  }
}
// ============================================================================
// GET ALL PAYMENTS
// ============================================================================

router.get('/', verifyToken, async (req, res) => {
  try {
    const { filter, sortBy, sortOrder = 'desc' } = req.query;
    
    let query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    // Apply filters
    if (filter && filter !== 'All Payments') {
      switch (filter) {
        case 'Draft':
          query.status = 'draft';
          break;
        case 'Paid':
          query.status = 'paid';
          break;
        case 'Void':
          query.status = 'void';
          break;
      }
    }

    // Build sort object
    let sort = { createdAt: -1 }; // Default sort by creation date
    if (sortBy) {
      sort = {};
      sort[sortBy] = sortOrder === 'asc' ? 1 : -1;
    }

    const payments = await db.collection('payments_received')
      .find(query)
      .sort(sort)
      .toArray();

    // Format payments for frontend
    const formattedPayments = payments.map(payment => ({
      id: payment._id,
      date: payment.paymentDate,
      paymentNumber: payment.paymentNumber,
      referenceNumber: payment.reference || '',
      customerName: payment.customerName,
      invoiceNumber: payment.invoiceNumber || '',
      mode: payment.paymentMode,
      amount: payment.amountReceived,
      status: payment.status || 'paid',
      hasProofs: payment.paymentProofs && payment.paymentProofs.length > 0,
      proofsCount: payment.paymentProofs ? payment.paymentProofs.length : 0,
      createdAt: payment.createdAt,
      updatedAt: payment.updatedAt
    }));

    res.json({
      success: true,
      data: formattedPayments,
      total: formattedPayments.length
    });

  } catch (error) {
    console.error('❌ Error fetching payments:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payments',
      error: error.message
    });
  }
});

router.get('/next-payment-number', verifyToken, async (req, res) => {
  try {
    const orgId = req.user?.orgId || null;
    const orgFilter = orgId ? { orgId } : {};
    const existing = await db.collection('payments_received')
      .find({ ...orgFilter, paymentNumber: { $regex: '^REC\\d' } }, { projection: { paymentNumber: 1 } })
      .toArray();

    let max = 0;
    for (const p of existing) {
      const n = parseInt((p.paymentNumber || '').slice('REC'.length), 10);
      if (!isNaN(n) && n > max) max = n;
    }
    const nextNumber = `REC${String(max + 1).padStart(6, '0')}`;

    res.json({
      success: true,
      data: {
        nextPaymentNumber: nextNumber
      }
    });

  } catch (error) {
    console.error('❌ Error getting next payment number:', error);
    res.status(500).json({
      success: false,
      message: 'Error getting next payment number',
      error: error.message
    });
  }
});

router.get('/stats/summary', verifyToken, async (req, res) => {
  try {
    const { startDate, endDate, customerName } = req.query;

    let matchQuery = {};
    if (req.user?.orgId) matchQuery.orgId = req.user.orgId;
    
    if (startDate && endDate) {
      matchQuery.paymentDate = {
        $gte: startDate,
        $lte: endDate
      };
    }

    if (customerName) {
      matchQuery.customerName = customerName;
    }

    const stats = await db.collection('payments_received').aggregate([
      { $match: matchQuery },
      {
        $group: {
          _id: null,
          totalPayments: { $sum: 1 },
          totalAmount: { $sum: '$amountReceived' },
          totalBankCharges: { $sum: '$bankCharges' },
          totalNetAmount: { $sum: '$netAmount' },
          avgPaymentAmount: { $avg: '$amountReceived' },
        }
      }
    ]).toArray();

    const paymentModeStats = await db.collection('payments_received').aggregate([
      { $match: matchQuery },
      {
        $group: {
          _id: '$paymentMode',
          count: { $sum: 1 },
          totalAmount: { $sum: '$amountReceived' }
        }
      }
    ]).toArray();

    res.json({
      success: true,
      data: {
        summary: stats[0] || {
          totalPayments: 0,
          totalAmount: 0,
          totalBankCharges: 0,
          totalNetAmount: 0,
          avgPaymentAmount: 0
        },
        paymentModeBreakdown: paymentModeStats
      }
    });

  } catch (error) {
    console.error('❌ Error fetching payment statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payment statistics',
      error: error.message
    });
  }
});

router.get('/export/csv', verifyToken, async (req, res) => {
  try {
    const { filter, startDate, endDate } = req.query;
    
    let query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    if (filter && filter !== 'All Payments') {
      switch (filter) {
        case 'Draft':
          query.status = 'draft';
          break;
        case 'Paid':
          query.status = 'paid';
          break;
        case 'Void':
          query.status = 'void';
          break;
      }
    }

    if (startDate && endDate) {
      query.paymentDate = {
        $gte: startDate,
        $lte: endDate
      };
    }

    const payments = await db.collection('payments_received')
      .find(query)
      .sort({ paymentDate: -1 })
      .toArray();

    // Generate CSV content
    const csvHeaders = [
      'Payment Date',
      'Payment Number',
      'Customer Name',
      'Amount Received',
      'Bank Charges',
      'Net Amount',
      'Payment Mode',
      'Deposit To',
      'Reference',
      'Tax Deduction',
      'Status',
      'Has Proofs',
      'Notes'
    ].join(',');

    const csvRows = payments.map(payment => [
      payment.paymentDate,
      payment.paymentNumber,
      payment.customerName,
      payment.amountReceived,
      payment.bankCharges || 0,
      payment.netAmount,
      payment.paymentMode,
      payment.depositTo,
      payment.reference || '',
      payment.taxDeduction,
      payment.status,
      payment.paymentProofs && payment.paymentProofs.length > 0 ? 'Yes' : 'No',
      (payment.notes || '').replace(/,/g, ';')
    ].join(','));

    const csvContent = [csvHeaders, ...csvRows].join('\n');

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=payments_received.csv');
    res.send(csvContent);

  } catch (error) {
    console.error('❌ Error exporting payments:', error);
    res.status(500).json({
      success: false,
      message: 'Error exporting payments',
      error: error.message
    });
  }
});router.get('/customer/:customerId/unpaid-invoices', verifyToken, async (req, res) => {
  try {
    const { customerId } = req.params;
    const { startDate, endDate } = req.query;

    console.log(`🔍 Fetching unpaid invoices for customer: ${customerId}`);

    // Convert customerId to ObjectId if it's a valid ObjectId string
    let customerIdQuery;
    if (ObjectId.isValid(customerId)) {
      customerIdQuery = new ObjectId(customerId);
      console.log(`   Using ObjectId: ${customerIdQuery}`);
    } else {
      customerIdQuery = customerId;
      console.log(`   Using string: ${customerIdQuery}`);
    }

    // Build query - try both ObjectId and string match
    let query = {
      $or: [
        { customerId: customerIdQuery },  // ObjectId match
        { customerId: customerId }  // String match (fallback)
      ],
      status: { $in: ['SENT', 'UNPAID', 'OVERDUE', 'PARTIALLY_PAID'] },
      amountDue: { $gt: 0 }
    };

    // Apply date filter if provided
    if (startDate && endDate) {
      query.invoiceDate = {
        $gte: new Date(startDate),
        $lte: new Date(endDate)
      };
    }

    console.log('📋 Query:', JSON.stringify(query, null, 2));

    // Query MongoDB directly
    const unpaidInvoices = await db.collection('invoices')
      .find(query)
      .sort({ invoiceDate: -1 })
      .toArray();
    
    console.log(`✅ Found ${unpaidInvoices.length} unpaid invoices`);

    // Log each invoice found
    unpaidInvoices.forEach((inv, index) => {
      console.log(`   ${index + 1}. ${inv.invoiceNumber} - Status: ${inv.status} - Due: ₹${inv.amountDue}`);
    });

    res.json({
      success: true,
      data: unpaidInvoices,
      total: unpaidInvoices.length
    });

  } catch (error) {
    console.error('❌ Error fetching unpaid invoices:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching unpaid invoices',
      error: error.message
    });
  }
});
// ============================================================================
// GET PAYMENT BY ID
// ============================================================================

router.get('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const query = { _id: new ObjectId(id) };
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const payment = await db.collection('payments_received').findOne(query);

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    res.json({
      success: true,
      data: payment
    });

  } catch (error) {
    console.error('❌ Error fetching payment:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payment',
      error: error.message
    });
  }
});

// ============================================================================
// CREATE NEW PAYMENT WITH PROOFS - ZOHO BOOKS WORKFLOW
// ============================================================================

router.post('/', verifyToken, uploadPaymentProofs, async (req, res) => {
  try {
    console.log('\n' + '💰'.repeat(50));
    console.log('ZOHO BOOKS WORKFLOW: RECORD PAYMENT WITH PROOFS');
    console.log('💰'.repeat(50));
    
    // Parse payment data from form field
    let paymentData;
    try {
      paymentData = JSON.parse(req.body.paymentData);
    } catch (e) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment data format'
      });
    }

    const {
      customerId,
      customerName,
      customerEmail,
      amountReceived,
      bankCharges = 0,
      paymentDate,
      paymentMode = 'Cash',
      depositTo,
      reference = '',
      taxDeduction = 'No Tax deducted',
      notes = '',
      sendThankYouNote = false,
      invoicePayments = {},
      status = 'paid',
      providerTransactionId = null
    } = paymentData;

    // Auto-generate paymentNumber if not provided
    let paymentNumber = paymentData.paymentNumber;
    if (!paymentNumber) {
      const orgId = req.user?.orgId || null;
      const orgFilter = orgId ? { orgId } : {};
      const existing = await db.collection('payments_received')
        .find({ ...orgFilter, paymentNumber: { $regex: '^REC\\d' } }, { projection: { paymentNumber: 1 } })
        .toArray();
      let max = 0;
      for (const p of existing) {
        const n = parseInt((p.paymentNumber || '').slice('REC'.length), 10);
        if (!isNaN(n) && n > max) max = n;
      }
      paymentNumber = `REC${String(max + 1).padStart(6, '0')}`;
    }

    console.log('📋 Payment Details:');
    console.log('   Customer:', customerName);
    console.log('   Amount:', amountReceived);
    console.log('   Payment #:', paymentNumber);
    console.log('   Files uploaded:', req.files ? req.files.length : 0);
    console.log('   Invoices to update:', Object.keys(invoicePayments).length);

    // Validation
    if (!customerName || !amountReceived || !paymentDate || !depositTo) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields: customerName, amountReceived, paymentDate, depositTo'
      });
    }

    // Check if payment number already exists
const existingPayment = await db.collection('payments_received')
  .findOne({ 
    paymentNumber: paymentNumber,
    orgId: req.user?.orgId || null  // ← add this one line
  });

if (existingPayment) {
  return res.status(400).json({
    success: false,
    message: 'Payment number already exists'
  });
}

    // Process uploaded files
    const paymentProofs = [];
    const proofPaths = [];
    if (req.files && req.files.length > 0) {
      console.log('📎 Processing uploaded files...');
      for (const file of req.files) {
        paymentProofs.push({
          filename: file.filename,
          originalName: file.originalname,
          filepath: file.path,
          fileType: file.mimetype,
          fileSize: file.size,
          uploadedAt: new Date()
        });
        proofPaths.push(file.path);
        console.log(`   ✅ ${file.originalname} (${(file.size / 1024).toFixed(1)} KB)`);
      }
    }

    // Calculate amounts
    const totalInvoicePayments = Object.values(invoicePayments).reduce((sum, amt) => sum + parseFloat(amt), 0);
    const netAmount = parseFloat(amountReceived) - parseFloat(bankCharges);

    // Create payment record
    const paymentRecord = {
      customerId,
      customerName,
      customerEmail,
      amountReceived: parseFloat(amountReceived),
      bankCharges: parseFloat(bankCharges),
      paymentDate,
      paymentNumber,
      paymentMode,
      depositTo,
      depositedToAccountId: ['Cash', 'Cheque'].includes(paymentMode)
        ? null        // undeposited — shows in Record Deposit dialog
        : depositTo,  // already in bank — won't show in Record Deposit
      depositedAt: ['Cash', 'Cheque'].includes(paymentMode)
        ? null
        : new Date(),
      isUndeposited: ['Cash', 'Cheque'].includes(paymentMode),
      reference,
      taxDeduction,
      notes,
      sendThankYouNote,
      status,
      
      // Invoice payments
      invoicePayments,
      
      // Calculated fields
      netAmount,
      amountUsedForPayments: totalInvoicePayments,
      amountRefunded: 0,
      amountInExcess: netAmount - totalInvoicePayments,
      orgId: req.user?.orgId || null,
      providerTransactionId: providerTransactionId ? (ObjectId.isValid(providerTransactionId) ? new ObjectId(providerTransactionId) : providerTransactionId) : null,
      // Payment proofs
      paymentProofs,
      
      // Metadata
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user?.email || req.user?.uid || 'system',
      emailSent: false
    };

    // Insert payment
    const result = await db.collection('payments_received').insertOne(paymentRecord);
    console.log('✅ Payment created:', result.insertedId);

    // ============================================================================
    // UPDATE LINKED INVOICES - ZOHO BOOKS WORKFLOW
    // ============================================================================
    let updatedInvoices = [];
    if (Object.keys(invoicePayments).length > 0) {
      console.log('🔗 Updating linked invoices...');
      
      for (const [invoiceId, amount] of Object.entries(invoicePayments)) {
        if (parseFloat(amount) > 0) {
          try {
            // Convert invoiceId to ObjectId if needed
            const invoiceObjectId = ObjectId.isValid(invoiceId) ? new ObjectId(invoiceId) : invoiceId;
            
            // Find invoice
            const invoice = await db.collection('invoices').findOne({ _id: invoiceObjectId });
            
            if (invoice) {
              // Prepare payment record for invoice
              const paymentRecord = {
                paymentId: result.insertedId.toString(),
                amount: parseFloat(amount),
                paymentDate: new Date(paymentDate),
                paymentMethod: paymentMode,
                referenceNumber: reference,
                notes: `Payment #${paymentNumber}`,
                recordedBy: req.user?.email || req.user?.uid || 'system',
                recordedAt: new Date()
              };
              
              // Calculate new amounts
              const newAmountPaid = (invoice.amountPaid || 0) + parseFloat(amount);
              const newAmountDue = invoice.totalAmount - newAmountPaid;
              
              // Determine new status
              let newStatus = invoice.status;
              if (newAmountDue <= 0) {
                newStatus = 'PAID';
              } else if (newAmountPaid > 0 && newAmountDue > 0) {
                newStatus = 'PARTIALLY_PAID';
              }
              
              // Update invoice
              await db.collection('invoices').updateOne(
                { _id: invoiceObjectId },
                {
                  $push: { payments: paymentRecord },
                  $set: {
                    amountPaid: newAmountPaid,
                    amountDue: newAmountDue,
                    status: newStatus,
                    updatedAt: new Date()
                  }
                }
              );
              
              // Get updated invoice for response
              const updatedInvoice = await db.collection('invoices').findOne({ _id: invoiceObjectId });
              updatedInvoices.push(updatedInvoice);
              
              console.log(`   ✅ Updated invoice ${invoice.invoiceNumber} (+₹${amount}) - Status: ${newStatus}`);
            } else {
              console.log(`   ⚠️  Invoice ${invoiceId} not found`);
            }
          } catch (err) {
            console.error(`   ⚠️  Failed to update invoice ${invoiceId}:`, err.message);
          }
        }
      }
    }

// ============================================================================
    // UPDATE ACCOUNT BALANCE - CREDIT RECEIVED AMOUNT
    // ============================================================================
    try {
      const PaymentAccount = db.collection('paymentaccounts');
      const depositAccountId = depositTo;
      let balanceCredited = false;
      const creditAmount = parseFloat(amountReceived);

      // Only credit bank balance immediately for non-cash/cheque payments
      // Cash/Cheque goes to Undeposited Funds first
      const creditImmediately = !['Cash', 'Cheque'].includes(paymentMode);

      if (creditImmediately) {
        if (ObjectId.isValid(depositAccountId)) {
          await PaymentAccount.findOneAndUpdate(
            { _id: new ObjectId(depositAccountId) },
            { $inc: { currentBalance: creditAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          balanceCredited = true;
          console.log(`✅ Balance credited to account ID ${depositAccountId}: +₹${creditAmount}`);
        }

        // If ObjectId lookup failed, try by account name
        if (!balanceCredited) {
          const updateResult = await PaymentAccount.findOneAndUpdate(
            { accountName: depositAccountId },
            { $inc: { currentBalance: creditAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (updateResult) {
            balanceCredited = true;
            console.log(`✅ Balance credited to account name "${depositAccountId}": +₹${creditAmount}`);
          }
        }

        if (!balanceCredited) {
          console.warn(`⚠️ BALANCE WARNING: Could not find deposit account "${depositAccountId}" to credit ₹${creditAmount}. Payment saved but balance NOT updated.`);
        }
      } else {
        // For Cash/Cheque — balance will be credited when Record Deposit is done
        console.log(`ℹ️ Cash/Cheque payment — balance will be credited on Record Deposit`);
      }
    } catch (balanceErr) {
      console.error(`⚠️ BALANCE ERROR: Failed to credit balance for payment ${result.insertedId}:`, balanceErr.message);
    }

// ✅ COA: Debit deposit account + Credit Accounts Receivable
const currentOrgId = req.user?.orgId || null;
try {
  // Resolve deposit account name
  let cleanDepositName = 'Undeposited Funds';
  try {
    const PaymentAccountCol = db.collection('paymentaccounts');
    if (ObjectId.isValid(depositTo)) {
      const depositAccount = await PaymentAccountCol.findOne({ _id: new ObjectId(depositTo) });
      if (depositAccount) {
        cleanDepositName = depositAccount.accountName;
        console.log(`💰 Resolved deposit account name: "${cleanDepositName}"`);
      }
    }
  } catch (e) {
    console.warn('⚠️ Could not resolve deposit account name:', e.message);
  }

  // Look up COA IDs
  const [cashId, arId] = await Promise.all([
    ChartOfAccount.findOne({
      accountName: { $regex: new RegExp(`^${cleanDepositName}$`, 'i') },
      ...(currentOrgId ? { orgId: currentOrgId } : {})
    }).select('_id').lean().then(acc => {
      if (acc) return acc._id;
      console.log(`⚠️ COA not found for "${cleanDepositName}", trying Undeposited Funds`);
      return getSystemAccountId('Undeposited Funds', currentOrgId);
    }),
    getSystemAccountId('Accounts Receivable', currentOrgId),
  ]);

  // Parse payment date — supports DD/MM/YYYY and ISO formats
  let txnDate;
  if (paymentDate && typeof paymentDate === 'string' && paymentDate.includes('/')) {
    const [day, month, year] = paymentDate.split('/');
    txnDate = new Date(`${year}-${month.padStart(2,'0')}-${day.padStart(2,'0')}`);
  } else {
    txnDate = new Date(paymentDate);
  }
  if (isNaN(txnDate)) txnDate = new Date();

  const paymentAmount = parseFloat(amountReceived);

  console.log(`💰 Posting COA for payment ${paymentNumber}:`);
  console.log(`   cashId (${cleanDepositName}): ${cashId}`);
  console.log(`   arId (Accounts Receivable): ${arId}`);
  console.log(`   amount: ${paymentAmount}`);
  console.log(`   orgId: ${currentOrgId}`);

  // For Cash/Cheque → Dr Undeposited Funds (not the bank yet)
  // For others → Dr Bank directly
  const depositCOAId = ['Cash', 'Cheque'].includes(paymentMode)
    ? await getSystemAccountId('Undeposited Funds', currentOrgId)
    : cashId;

  if (depositCOAId) {
    await postTransactionToCOA({
      accountId: depositCOAId, orgId: currentOrgId, date: txnDate,
      description: `Payment received - ${paymentNumber} - ${customerName}`,
      referenceType: 'Payment',
      referenceId: result.insertedId,
      referenceNumber: paymentNumber,
      debit: paymentAmount, credit: 0
    });
    console.log(`✅ COA Debit posted to: ${['Cash', 'Cheque'].includes(paymentMode) ? 'Undeposited Funds' : cleanDepositName}`);
  } else {
    console.warn(`⚠️ COA depositCOAId not found for "${cleanDepositName}" — debit NOT posted`);
  }

  if (arId) {
    await postTransactionToCOA({
      accountId: arId, orgId: currentOrgId, date: txnDate,
      description: `Payment received - ${paymentNumber} - ${customerName}`,
      referenceType: 'Payment',
      referenceId: result.insertedId,
      referenceNumber: paymentNumber,
      debit: 0, credit: paymentAmount
    });
    console.log(`✅ COA Credit posted to: Accounts Receivable`);
  } else {
    console.warn(`⚠️ COA arId not found for "Accounts Receivable" — credit NOT posted`);
  }

  console.log(`✅ COA posted for payment: ${paymentNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA post error (payment received):', coaErr.message);
}

    // ── CREATE PROVIDER TRANSACTION (for All Transactions tab) ──────────────
    try {
      const mongoose = require('mongoose');
      const ProviderTransaction = mongoose.models.ProviderTransaction
        || mongoose.model('ProviderTransaction',
            new mongoose.Schema({}, { strict: false }),
            'providertransactions');

      // Only create for non-Cash/Cheque (those go through Record Deposit)
      const creditImmediately = !['Cash', 'Cheque'].includes(paymentMode);
      if (creditImmediately && depositTo && mongoose.Types.ObjectId.isValid(depositTo)) {
        await ProviderTransaction.create({
          accountId:            new mongoose.Types.ObjectId(depositTo),
          orgId:                req.user?.orgId || null,
          transactionDate:      new Date(paymentDate),
          description:          `Customer Payment: ${customerName}`,
          amount:               parseFloat(amountReceived),
          transactionType:      'CREDIT',
          reconciliationStatus: 'CATEGORIZED',
          categoryLabel:        'Customer Payment',
          source:               'SYSTEM_ENTRY',
          linkedRecordId:       result.insertedId,
          linkedRecordType:     'PaymentReceived',
          journalRef:           paymentNumber,
          categorizedAt:        new Date(),
          categorizedBy:        req.user?.email || 'system',
          importedAt:           new Date(),
          importedBy:           req.user?.email || 'system',
        });
        console.log(`✅ ProviderTransaction created for payment received: ${paymentNumber}`);
      }
    } catch (ptErr) {
      console.error('⚠️ ProviderTransaction create error (payment received):', ptErr.message);
    }
    // ── END PROVIDER TRANSACTION ─────────────────────────────────────────────

    // ============================================================================
    // SEND PAYMENT RECEIPT EMAIL WITH PROOFS - ZOHO BOOKS WORKFLOW
    // ============================================================================
    let emailSent = false;
    if (sendThankYouNote && (customerEmail || updatedInvoices[0]?.customerEmail)) {
      try {
        console.log('📧 Sending payment receipt email with proofs...');
        await sendPaymentReceiptEmail(
          paymentRecord,
          updatedInvoices[0], // Primary invoice
          proofPaths
        );
        
        // Update payment record
        await db.collection('payments_received').updateOne(
          { _id: result.insertedId },
          { $set: { emailSent: true, emailSentAt: new Date() } }
        );
        
        emailSent = true;
        console.log('✅ Payment receipt email sent successfully');
      } catch (emailError) {
        console.error('⚠️  Failed to send email (non-critical):', emailError.message);
      }
    }

    console.log('✅ PAYMENT RECORDING COMPLETE');
    console.log('💰'.repeat(50) + '\n');

    res.status(201).json({
      success: true,
      message: 'Payment recorded successfully',
      data: {
        id: result.insertedId,
        paymentNumber,
        proofsUploaded: paymentProofs.length,
        invoicesUpdated: updatedInvoices.length,
        emailSent,
        ...paymentRecord
      }
    });

  } catch (error) {
    console.error('❌ Error creating payment:', error);
    
    // Clean up uploaded files on error
    if (req.files && req.files.length > 0) {
      req.files.forEach(file => {
        try {
          fs.unlinkSync(file.path);
        } catch (err) {
          console.error('Failed to delete file:', err);
        }
      });
    }
    
    res.status(500).json({
      success: false,
      message: 'Error creating payment',
      error: error.message
    });
  }
});

// ============================================================================
// UPDATE PAYMENT
// ============================================================================

router.put('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;

    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const getQuery = { _id: new ObjectId(id) };
    if (req.user?.orgId) getQuery.orgId = req.user.orgId;

    // ✅ Fetch old payment BEFORE updating
    const oldPayment = await db.collection('payments_received').findOne(getQuery);

    if (!oldPayment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    const oldAmount    = parseFloat(oldPayment.amountReceived || 0);
    const oldDepositTo = oldPayment.depositTo;

    const updateData = {
      ...req.body,
      updatedAt: new Date(),
      updatedBy: req.user?.email || req.user?.uid || 'system'
    };

    // Remove fields that shouldn't be updated
    delete updateData._id;
    delete updateData.createdAt;
    delete updateData.createdBy;
    delete updateData.paymentProofs;

    const result = await db.collection('payments_received')
      .updateOne(getQuery, { $set: updateData });

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    // ── BALANCE ADJUSTMENT ON UPDATE ─────────────────────────────────────────
    try {
      const newAmount    = parseFloat(req.body.amountReceived || oldAmount);
      const newDepositTo = req.body.depositTo || oldDepositTo;
      const depositChanged = req.body.depositTo && req.body.depositTo !== oldDepositTo;
      const PaymentAccountCol = db.collection('paymentaccounts');

      if (depositChanged) {
        // ✅ Account changed — reverse full amount from OLD account
        let oldReversed = false;

        if (ObjectId.isValid(oldDepositTo)) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { _id: new ObjectId(oldDepositTo) },
            { $inc: { currentBalance: -oldAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) {
            oldReversed = true;
            console.log(`✅ Reversed ₹${oldAmount} from old account ID ${oldDepositTo}`);
          }
        }
        if (!oldReversed) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { accountName: oldDepositTo },
            { $inc: { currentBalance: -oldAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) console.log(`✅ Reversed ₹${oldAmount} from old account name "${oldDepositTo}"`);
        }

        // ✅ Credit full new amount to NEW account
        let newCredited = false;

        if (ObjectId.isValid(newDepositTo)) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { _id: new ObjectId(newDepositTo) },
            { $inc: { currentBalance: newAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) {
            newCredited = true;
            console.log(`✅ Credited ₹${newAmount} to new account ID ${newDepositTo}`);
          }
        }
        if (!newCredited) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { accountName: newDepositTo },
            { $inc: { currentBalance: newAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) console.log(`✅ Credited ₹${newAmount} to new account name "${newDepositTo}"`);
        }

      } else {
        // ✅ Same account — adjust the difference only
        const difference = newAmount - oldAmount;

        if (difference !== 0) {
          let adjusted = false;

          if (ObjectId.isValid(newDepositTo)) {
            const r = await PaymentAccountCol.findOneAndUpdate(
              { _id: new ObjectId(newDepositTo) },
              { $inc: { currentBalance: difference }, $set: { updatedAt: new Date() } },
              { returnDocument: 'after' }
            );
            if (r) {
              adjusted = true;
              console.log(`✅ Balance adjusted by ₹${difference} on account ID ${newDepositTo} → new balance: ₹${r.currentBalance}`);
            }
          }
          if (!adjusted) {
            const r = await PaymentAccountCol.findOneAndUpdate(
              { accountName: newDepositTo },
              { $inc: { currentBalance: difference }, $set: { updatedAt: new Date() } },
              { returnDocument: 'after' }
            );
            if (r) console.log(`✅ Balance adjusted by ₹${difference} on account name "${newDepositTo}"`);
          }
        } else {
          console.log('ℹ️ No balance change needed — amount unchanged');
        }
      }
    } catch (balanceErr) {
      console.error('⚠️ Balance adjustment error (payment update):', balanceErr.message);
    }
    // ── END BALANCE ADJUSTMENT ───────────────────────────────────────────────

    // ── COA ADJUSTMENT ON UPDATE ─────────────────────────────────────────────
    try {
      const currentOrgId = req.user?.orgId || null;
      const newAmount    = parseFloat(req.body.amountReceived || oldAmount);
      const newDepositTo = req.body.depositTo || oldDepositTo;
      const depositChanged = req.body.depositTo && req.body.depositTo !== oldDepositTo;

      // Resolve deposit account names for COA lookup
      const resolveDepositName = async (depositId) => {
        if (!depositId) return 'Undeposited Funds';
        if (ObjectId.isValid(depositId)) {
          const acc = await db.collection('paymentaccounts')
            .findOne({ _id: new ObjectId(depositId) });
          return acc?.accountName || 'Undeposited Funds';
        }
        return depositId;
      };

      const [oldDepositName, newDepositName] = await Promise.all([
        resolveDepositName(oldDepositTo),
        resolveDepositName(newDepositTo),
      ]);

      const getCOAId = async (name) => {
        const acc = await ChartOfAccount.findOne({
          accountName: { $regex: new RegExp(`^${name}$`, 'i') },
          orgId: currentOrgId
        }).select('_id').lean();
        return acc ? acc._id : await getSystemAccountId('Undeposited Funds', currentOrgId);
      };

      const [oldCashId, newCashId, arId] = await Promise.all([
        getCOAId(oldDepositName),
        getCOAId(newDepositName),
        getSystemAccountId('Accounts Receivable', currentOrgId),
      ]);

      const paymentDate = req.body.paymentDate || oldPayment.paymentDate;
      const paymentNumber = oldPayment.paymentNumber;
      const customerName = req.body.customerName || oldPayment.customerName;

      let txnDate;
      if (paymentDate && paymentDate.includes('/')) {
        const [day, month, year] = paymentDate.split('/');
        txnDate = new Date(`${year}-${month}-${day}`);
      } else {
        txnDate = new Date(paymentDate);
      }
      if (isNaN(txnDate)) txnDate = new Date();

      const paymentObjId = new ObjectId(id);

      if (depositChanged) {
        // Reverse old COA entries
        if (oldCashId) await postTransactionToCOA({
          accountId: oldCashId, orgId: currentOrgId, date: txnDate,
          description: `REVERSAL - Payment ${paymentNumber} - ${customerName}`,
          referenceType: 'Payment', referenceId: paymentObjId,
          referenceNumber: paymentNumber,
          debit: 0, credit: oldAmount
        });
        if (arId) await postTransactionToCOA({
          accountId: arId, orgId: currentOrgId, date: txnDate,
          description: `REVERSAL - Payment ${paymentNumber} - ${customerName}`,
          referenceType: 'Payment', referenceId: paymentObjId,
          referenceNumber: paymentNumber,
          debit: oldAmount, credit: 0
        });

        // Post new COA entries
        if (newCashId) await postTransactionToCOA({
          accountId: newCashId, orgId: currentOrgId, date: txnDate,
          description: `UPDATED - Payment ${paymentNumber} - ${customerName}`,
          referenceType: 'Payment', referenceId: paymentObjId,
          referenceNumber: paymentNumber,
          debit: newAmount, credit: 0
        });
        if (arId) await postTransactionToCOA({
          accountId: arId, orgId: currentOrgId, date: txnDate,
          description: `UPDATED - Payment ${paymentNumber} - ${customerName}`,
          referenceType: 'Payment', referenceId: paymentObjId,
          referenceNumber: paymentNumber,
          debit: 0, credit: newAmount
        });

      } else {
        // Same account — post difference only
        const difference = newAmount - oldAmount;
        if (difference !== 0) {
          if (newCashId) await postTransactionToCOA({
            accountId: newCashId, orgId: currentOrgId, date: txnDate,
            description: `UPDATED - Payment ${paymentNumber} - ${customerName}`,
            referenceType: 'Payment', referenceId: paymentObjId,
            referenceNumber: paymentNumber,
            debit:  difference > 0 ? difference : 0,
            credit: difference < 0 ? Math.abs(difference) : 0
          });
          if (arId) await postTransactionToCOA({
            accountId: arId, orgId: currentOrgId, date: txnDate,
            description: `UPDATED - Payment ${paymentNumber} - ${customerName}`,
            referenceType: 'Payment', referenceId: paymentObjId,
            referenceNumber: paymentNumber,
            debit:  difference < 0 ? Math.abs(difference) : 0,
            credit: difference > 0 ? difference : 0
          });
        } else {
          console.log('ℹ️ No COA change needed — amount unchanged');
        }
      }

      console.log('✅ COA adjustment posted for payment update');
    } catch (coaErr) {
      console.error('⚠️ COA adjustment error (payment update):', coaErr.message);
    }
    // ── END COA ADJUSTMENT ───────────────────────────────────────────────────

    res.json({
      success: true,
      message: 'Payment updated successfully'
    });

  } catch (error) {
    console.error('❌ Error updating payment:', error);
    res.status(500).json({
      success: false,
      message: 'Error updating payment',
      error: error.message
    });
  }
});

// ============================================================================
// DELETE PAYMENT
// ============================================================================

router.delete('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    // Get payment before deleting — we need depositTo and amountReceived for balance reversal
    const deleteQuery = { _id: new ObjectId(id) };
    if (req.user?.orgId) deleteQuery.orgId = req.user.orgId;

    const payment = await db.collection('payments_received').findOne(deleteQuery);

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    // Delete associated proof files
    if (payment.paymentProofs && payment.paymentProofs.length > 0) {
      payment.paymentProofs.forEach(proof => {
        try {
          if (fs.existsSync(proof.filepath)) {
            fs.unlinkSync(proof.filepath);
            console.log(`🗑️  Deleted proof file: ${proof.filename}`);
          }
        } catch (err) {
          console.error(`Failed to delete file ${proof.filename}:`, err);
        }
      });
    }

    // Delete payment record
    const result = await db.collection('payments_received')
      .deleteOne({ _id: new ObjectId(id) });

    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    // ── REVERSE INVOICE PAYMENTS ON DELETE ──────────────────────────────────
    try {
      if (payment.invoicePayments && Object.keys(payment.invoicePayments).length > 0) {
        for (const [invoiceId, amount] of Object.entries(payment.invoicePayments)) {
          if (!ObjectId.isValid(invoiceId)) continue;
          const invoice = await db.collection('invoices')
            .findOne({ _id: new ObjectId(invoiceId) });
          if (!invoice) continue;

          const reversedAmountPaid = (invoice.amountPaid || 0) - parseFloat(amount);
          const reversedAmountDue  = invoice.totalAmount - reversedAmountPaid;

          let newStatus = invoice.status;
          if (reversedAmountPaid <= 0) {
            newStatus = 'SENT';
          } else if (reversedAmountPaid > 0 && reversedAmountDue > 0) {
            newStatus = 'PARTIALLY_PAID';
          }

          await db.collection('invoices').updateOne(
            { _id: new ObjectId(invoiceId) },
            {
              $pull: { payments: { paymentId: id } },
              $set: {
                amountPaid: Math.max(0, reversedAmountPaid),
                amountDue:  Math.max(0, reversedAmountDue),
                status:     newStatus,
                updatedAt:  new Date()
              }
            }
          );
          console.log(`✅ Invoice ${invoice.invoiceNumber} reversed — status: ${newStatus}`);
        }
      }
    } catch (invoiceReverseErr) {
      console.error('⚠️ Invoice reversal error (payment delete):', invoiceReverseErr.message);
    }
    // ── END INVOICE REVERSAL ─────────────────────────────────────────────────

    // ── BALANCE REVERSE ON DELETE ────────────────────────────────────────────
    // When a payment is deleted, reverse the credit — deduct the amount back from the account
    try {
      const depositAccountId = payment.depositTo;
      const deductAmount = parseFloat(payment.amountReceived);
      let balanceReversed = false;

      // Skip if already deposited — Block 2 (deposit reversal) will handle it
      if (payment.depositedToAccountId) {
        console.log('ℹ️ Skipping balance reverse — deposit reversal block will handle it');
        balanceReversed = true; // prevents Block 1 from running
      }

      if (depositAccountId && deductAmount > 0) {
        const PaymentAccountCol = db.collection('paymentaccounts');

        if (ObjectId.isValid(depositAccountId)) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { _id: new ObjectId(depositAccountId) },
            { $inc: { currentBalance: -deductAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) {
            balanceReversed = true;
            console.log(`✅ Balance reversed on payment delete: -₹${deductAmount} from account ID ${depositAccountId}`);
          }
        }

        if (!balanceReversed) {
          const r = await PaymentAccountCol.findOneAndUpdate(
            { accountName: depositAccountId },
            { $inc: { currentBalance: -deductAmount }, $set: { updatedAt: new Date() } },
            { returnDocument: 'after' }
          );
          if (r) {
            balanceReversed = true;
            console.log(`✅ Balance reversed on payment delete: -₹${deductAmount} from account name "${depositAccountId}"`);
          }
        }

        if (!balanceReversed) {
          console.warn(`⚠️ BALANCE WARNING: Could not reverse balance. Account "${depositAccountId}" not found. Payment deleted but balance NOT updated.`);
        }
      }
    } catch (balanceErr) {
      console.error(`⚠️ BALANCE ERROR: Failed to reverse balance on payment delete:`, balanceErr.message);
    }
    // ── END BALANCE REVERSE ──────────────────────────────────────────────────

    // ── COA REVERSAL ON DELETE ───────────────────────────────────────────────
    try {
      const currentOrgId  = req.user?.orgId || null;
      const deleteAmount  = parseFloat(payment.amountReceived);
      const paymentMode   = payment.paymentMode;
      const paymentNumber = payment.paymentNumber;
      const customerName  = payment.customerName;

      // Parse payment date
      let txnDate;
      if (payment.paymentDate && payment.paymentDate.includes('/')) {
        const [day, month, year] = payment.paymentDate.split('/');
        txnDate = new Date(`${year}-${month.padStart(2,'0')}-${day.padStart(2,'0')}`);
      } else {
        txnDate = new Date(payment.paymentDate);
      }
      if (isNaN(txnDate)) txnDate = new Date();

      // Resolve which COA account was debited
      // Cash/Cheque → Undeposited Funds, others → actual bank account
      let depositCOAId;
      if (['Cash', 'Cheque'].includes(paymentMode)) {
        depositCOAId = await getSystemAccountId('Undeposited Funds', currentOrgId);
      } else {
        let depositName = 'Undeposited Funds';
        if (payment.depositTo && ObjectId.isValid(payment.depositTo)) {
          const acc = await db.collection('paymentaccounts')
            .findOne({ _id: new ObjectId(payment.depositTo) });
          if (acc) depositName = acc.accountName;
        }
        const coaAcc = await ChartOfAccount.findOne({
          accountName: { $regex: new RegExp(`^${depositName}$`, 'i') },
          ...(currentOrgId ? { orgId: currentOrgId } : {})
        }).select('_id').lean();
        depositCOAId = coaAcc ? coaAcc._id
                               : await getSystemAccountId('Undeposited Funds', currentOrgId);
      }

      const arId         = await getSystemAccountId('Accounts Receivable', currentOrgId);
      const paymentObjId = new ObjectId(id);

      // REVERSE: Cr Undeposited Funds / Bank (was Dr before)
      if (depositCOAId) {
        await postTransactionToCOA({
          accountId:       depositCOAId,
          orgId:           currentOrgId,
          date:            txnDate,
          description:     `REVERSAL - Payment ${paymentNumber} - ${customerName}`,
          referenceType:   'Payment',
          referenceId:     paymentObjId,
          referenceNumber: paymentNumber,
          debit:           0,
          credit:          deleteAmount,  // ← reverses the Dr
        });
        console.log(`✅ COA Reversal: Cr Undeposited/Bank ₹${deleteAmount}`);
      }

      // REVERSE: Dr Accounts Receivable (was Cr before)
      if (arId) {
        await postTransactionToCOA({
          accountId:       arId,
          orgId:           currentOrgId,
          date:            txnDate,
          description:     `REVERSAL - Payment ${paymentNumber} - ${customerName}`,
          referenceType:   'Payment',
          referenceId:     paymentObjId,
          referenceNumber: paymentNumber,
          debit:           deleteAmount,  // ← reverses the Cr
          credit:          0,
        });
        console.log(`✅ COA Reversal: Dr Accounts Receivable ₹${deleteAmount}`);
      }

      console.log(`✅ COA fully reversed for deleted payment: ${paymentNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA reversal error (payment delete):', coaErr.message);
    }
    // ── END COA REVERSAL ─────────────────────────────────────────────────────

    // ── REVERSE DEPOSIT COA IF ALREADY DEPOSITED ─────────────────────────────
    try {
      if (payment.depositedToAccountId) {
        const bankAccount = await db.collection('paymentaccounts')
          .findOne({ _id: new ObjectId(payment.depositedToAccountId) });

        if (bankAccount) {
          const bankCOA = await ChartOfAccount.findOne({
            accountName: { $regex: new RegExp(`^${bankAccount.accountName}$`, 'i') },
            ...(req.user?.orgId ? { orgId: req.user.orgId } : {})
          }).lean();

          if (bankCOA) {
            // Reverse: Cr Bank (was Dr on deposit)
            await postTransactionToCOA({
              accountId:       bankCOA._id,
              orgId:           req.user?.orgId || null,
              date:            new Date(),
              description:     `REVERSAL - Deposit for Payment ${payment.paymentNumber}`,
              referenceType:   'Payment',
              referenceId:     new ObjectId(id),
              referenceNumber: payment.paymentNumber,
              debit:           0,
              credit:          parseFloat(payment.amountReceived),
            });

            // Reverse PaymentAccount balance
            await db.collection('paymentaccounts').updateOne(
              { _id: new ObjectId(payment.depositedToAccountId) },
              { $inc: { currentBalance: -parseFloat(payment.amountReceived) } }
            );

            console.log(`✅ Bank COA reversed for deposited payment: ${payment.paymentNumber}`);
          }
        }
      }
    } catch (depositReversalErr) {
      console.error('⚠️ Deposit reversal error:', depositReversalErr.message);
    }
    // ── END DEPOSIT REVERSAL ──────────────────────────────────────────────────

    res.json({
      success: true,
      message: 'Payment deleted successfully'
    });

  } catch (error) {
    console.error('❌ Error deleting payment:', error);
    res.status(500).json({
      success: false,
      message: 'Error deleting payment',
      error: error.message
    });
  }
});

// ============================================================================
// GET /:id/pdf — generate and download payment receipt PDF
// ============================================================================

router.get('/:id/pdf', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, message: 'Invalid payment ID' });
    }
    const query = { _id: new ObjectId(id) };
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const payment = await db.collection('payments_received').findOne(query);
    if (!payment) {
      return res.status(404).json({ success: false, message: 'Payment not found' });
    }

    // Fetch linked invoice
    let linkedInvoice = null;
    try {
      const invoiceIds = Object.keys(payment.invoicePayments || {});
      if (invoiceIds.length > 0 && ObjectId.isValid(invoiceIds[0])) {
        linkedInvoice = await db.collection('invoices').findOne({ _id: new ObjectId(invoiceIds[0]) });
      }
    } catch (_) {}

    // Fetch org details
    let orgData = null;
    try {
      const mongoose = require('mongoose');
      const OrgModel = mongoose.models.Organization ||
        mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
      orgData = await OrgModel.findOne({ orgId: payment.orgId }).lean();
    } catch (_) {}
    const orgName  = orgData?.orgName   || 'Billing Team';
    const orgGST   = orgData?.gstNumber || '';
    const orgPhone = orgData?.phone     || '';
    const orgEmail = orgData?.email     || '';
    const orgAddr  = orgData?.address   || '';

    const PDFDocument = require('pdfkit');
    const uploadsDir  = path.join(__dirname, '..', 'uploads', 'payments');
    if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

    const filename = `payment-${payment.paymentNumber}.pdf`;
    const filepath = path.join(uploadsDir, filename);

    const doc    = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
    const stream = fs.createWriteStream(filepath);
    doc.pipe(stream);

    const pageW = 515;
    const amountReceived = parseFloat(payment.amountReceived || 0);
    const bankCharges    = parseFloat(payment.bankCharges    || 0);
    const amountDue      = linkedInvoice ? parseFloat(linkedInvoice.amountDue || 0) : 0;

    // ── Logo ──────────────────────────────────────────────────────────────────
    const logoPath = getOrgLogoPath ? getOrgLogoPath(payment.orgId) : null;
    const textX    = logoPath ? 126 : 50;
    const contactLines = [orgAddr, orgGST ? `GSTIN: ${orgGST}` : '', orgPhone, orgEmail].filter(Boolean);
    const textBlockH   = 14 + 12 + contactLines.length * 9;
    const logoY        = 35 + textBlockH / 2 - 27;

    if (logoPath) {
      try { doc.image(logoPath, 44, logoY, { width: 72, height: 55, fit: [72, 55] }); } catch (_) {}
    }

    doc.fontSize(12).fillColor('#000000').font('Helvetica-Bold')
       .text(orgName.toUpperCase(), textX, 35, { width: 200 });
    doc.fontSize(7).fillColor('#444444').font('Helvetica')
       .text('BILLING & FINANCE', textX, 49, { width: 200, characterSpacing: 1 });
    doc.fontSize(7).fillColor('#000000');
    let cy = 61;
    contactLines.forEach(l => { doc.text(l, textX, cy, { width: 240 }); cy += 9; });

    doc.fontSize(8).fillColor('#444444').font('Helvetica-Bold')
       .text('PAYMENT RECEIPT', 380, 40, { width: 170, align: 'right', characterSpacing: 2 });
    doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
       .text(payment.paymentNumber, 380, 52, { width: 170, align: 'right' });
    doc.fontSize(8).fillColor('#000000').font('Helvetica')
       .text(`Date: ${payment.paymentDate}`, 380, 74, { width: 170, align: 'right' });

    // ── Divider ───────────────────────────────────────────────────────────────
    const headerBottom = Math.max(cy + 4, 90);
    doc.moveTo(40, headerBottom).lineTo(555, headerBottom).lineWidth(0.5).strokeColor('#CCCCCC').stroke();

    // ── Customer info ─────────────────────────────────────────────────────────
    let y = headerBottom + 16;
    doc.fontSize(9).fillColor('#666666').font('Helvetica-Bold').text('RECEIVED FROM', 40, y);
    y += 14;
    doc.fontSize(11).fillColor('#000000').font('Helvetica-Bold').text(payment.customerName || '', 40, y);
    y += 14;
    if (payment.customerEmail) {
      doc.fontSize(9).fillColor('#444444').font('Helvetica').text(payment.customerEmail, 40, y);
      y += 12;
    }

    // ── Payment details table ─────────────────────────────────────────────────
    y += 10;
    doc.moveTo(40, y).lineTo(555, y).lineWidth(0.5).strokeColor('#CCCCCC').stroke();
    y += 12;

    const rows = [
      ['Payment Number',  payment.paymentNumber],
      ['Payment Date',    payment.paymentDate],
      ['Payment Mode',    payment.paymentMode],
      linkedInvoice ? ['Invoice Number', linkedInvoice.invoiceNumber] : null,
      payment.reference ? ['Reference Number', payment.reference] : null,
      bankCharges > 0 ? ['Bank Charges', `Rs.${bankCharges.toFixed(2)}`] : null,
    ].filter(Boolean);

    rows.forEach(([label, value]) => {
      doc.fontSize(9).fillColor('#666666').font('Helvetica').text(label, 40, y, { width: 200 });
      doc.fontSize(9).fillColor('#000000').font('Helvetica').text(value, 250, y, { width: 305, align: 'right' });
      y += 16;
    });

    y += 4;
    doc.moveTo(40, y).lineTo(555, y).lineWidth(0.5).strokeColor('#CCCCCC').stroke();
    y += 12;

    // ── Amount received ───────────────────────────────────────────────────────
    doc.fontSize(11).fillColor('#000000').font('Helvetica-Bold').text('Amount Received', 40, y, { width: 300 });
    doc.fontSize(14).fillColor('#27AE60').font('Helvetica-Bold').text(`Rs.${amountReceived.toFixed(2)}`, 250, y - 2, { width: 305, align: 'right' });
    y += 20;

    if (linkedInvoice && amountDue >= 0) {
      doc.fontSize(9).fillColor('#666666').font('Helvetica').text('Remaining Balance', 40, y, { width: 300 });
      const balColor = amountDue > 0 ? '#DC2626' : '#27AE60';
      doc.fontSize(9).fillColor(balColor).font('Helvetica-Bold').text(`Rs.${amountDue.toFixed(2)}`, 250, y, { width: 305, align: 'right' });
      y += 16;
    }

    if (payment.notes) {
      y += 10;
      doc.fontSize(9).fillColor('#666666').font('Helvetica-Bold').text('Notes:', 40, y);
      y += 12;
      doc.fontSize(9).fillColor('#444444').font('Helvetica').text(payment.notes, 40, y, { width: pageW });
    }

    // ── Authorized Signatory ──────────────────────────────────────────────────
    const signBoxW = 220;
    const authBoxX = 555 - signBoxW;
    const signSectionY = 700;
    doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
       .text(`For ${orgName.toUpperCase()}`, authBoxX, signSectionY, { width: signBoxW, characterSpacing: 0.5, ellipsis: true });
    doc.moveTo(authBoxX, signSectionY + 30)
       .lineTo(authBoxX + signBoxW, signSectionY + 30)
       .lineWidth(0.5).strokeColor('#aaaaaa').stroke();
    doc.fontSize(6.5).fillColor('#000000').font('Helvetica-Bold')
       .text('Authorized Signatory', authBoxX, signSectionY + 33, { width: signBoxW, align: 'center' });

    // ── Footer ────────────────────────────────────────────────────────────────
    doc.moveTo(40, 760).lineTo(555, 760).lineWidth(1.5).strokeColor('#dde4ef').stroke();
    doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica')
       .text(`${orgName}${orgGST ? ' · GSTIN: ' + orgGST : ''} · ${payment.paymentNumber}`, 40, 766, { width: pageW / 2 });
    doc.text(`Generated on ${new Date().toLocaleDateString('en-IN')}`, 40, 766, { width: pageW, align: 'right' });

    doc.end();

    await new Promise((resolve, reject) => {
      stream.on('finish', resolve);
      stream.on('error', reject);
    });

    res.download(filepath, `Payment-${payment.paymentNumber}.pdf`);
  } catch (error) {
    console.error('❌ Error generating payment PDF:', error);
    res.status(500).json({ success: false, message: 'Error generating PDF', error: error.message });
  }
});

// ============================================================================
// GET /:id/email-preview — return payment receipt email HTML for preview
// ============================================================================

router.get('/:id/email-preview', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, message: 'Invalid payment ID' });
    }
    const query = { _id: new ObjectId(id) };
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const payment = await db.collection('payments_received').findOne(query);
    if (!payment) {
      return res.status(404).json({ success: false, message: 'Payment not found' });
    }

    let linkedInvoice = null;
    try {
      const invoiceIds = Object.keys(payment.invoicePayments || {});
      if (invoiceIds.length > 0 && ObjectId.isValid(invoiceIds[0])) {
        linkedInvoice = await db.collection('invoices').findOne({ _id: new ObjectId(invoiceIds[0]) });
      }
    } catch (_) {}

    let orgData = null;
    try {
      const mongoose = require('mongoose');
      const OrgModel = mongoose.models.Organization ||
        mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
      orgData = await OrgModel.findOne({ orgId: payment.orgId }).lean();
    } catch (_) {}
    const orgName  = orgData?.orgName   || 'Billing Team';
    const orgGST   = orgData?.gstNumber || '';
    const orgPhone = orgData?.phone     || '';
    const orgEmail = orgData?.email     || '';

    const amountReceived = parseFloat(payment.amountReceived || 0);
    const bankCharges    = parseFloat(payment.bankCharges    || 0);
    const amountDue      = linkedInvoice ? parseFloat(linkedInvoice.amountDue || 0) : 0;

    const html = `<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #0f1e3d 0%, #1a3a6b 50%, #2463ae 100%); color: white; padding: 30px 32px; border-radius: 8px 8px 0 0; }
    .header h1 { margin: 0 0 6px 0; font-size: 22px; }
    .header p  { margin: 0; font-size: 13px; opacity: 0.85; }
    .content { background: #f8f9fa; padding: 28px 32px; border-radius: 0 0 8px 8px; }
    .success-badge { background: #d4edda; color: #155724; padding: 14px 18px; border-radius: 8px; text-align: center; margin: 0 0 20px 0; border: 1px solid #c3e6cb; }
    .payment-box { background: white; padding: 20px; border-radius: 8px; margin: 0 0 20px 0; border-left: 4px solid #1a3a6b; }
    .payment-box h3 { margin: 0 0 14px 0; color: #0f1e3d; font-size: 15px; }
    .detail-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #f0f0f0; font-size: 13px; }
    .detail-row:last-child { border-bottom: none; }
    .detail-label { color: #666; }
    .detail-value { font-weight: 600; color: #222; }
    .total-row { padding-top: 12px; margin-top: 8px; border-top: 2px solid #1a3a6b; font-size: 15px; font-weight: bold; }
    .balance-due { color: #dc2626; }
    .balance-paid { color: #15803d; }
    .footer { text-align: center; color: #888; font-size: 11px; margin-top: 24px; line-height: 1.8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>✅ Payment Receipt</h1>
      <p>${orgName} — Billing &amp; Finance</p>
    </div>
    <div class="content">
      <div class="success-badge">
        <h2 style="margin:0 0 4px 0;font-size:17px;">Payment Received Successfully</h2>
        <p style="margin:0;font-size:13px;">We have received your payment of ₹${amountReceived.toFixed(2)}</p>
      </div>
      <div class="payment-box">
        <h3>Payment Details</h3>
        <div class="detail-row"><span class="detail-label">Payment Number</span><span class="detail-value">${payment.paymentNumber}</span></div>
        <div class="detail-row"><span class="detail-label">Payment Date</span><span class="detail-value">${payment.paymentDate}</span></div>
        <div class="detail-row"><span class="detail-label">Payment Mode</span><span class="detail-value">${payment.paymentMode}</span></div>
        ${linkedInvoice ? `<div class="detail-row"><span class="detail-label">Invoice Number</span><span class="detail-value">${linkedInvoice.invoiceNumber}</span></div>` : ''}
        ${payment.reference ? `<div class="detail-row"><span class="detail-label">Reference Number</span><span class="detail-value">${payment.reference}</span></div>` : ''}
        ${bankCharges > 0 ? `<div class="detail-row"><span class="detail-label">Bank Charges</span><span class="detail-value" style="color:#dc2626;">-₹${bankCharges.toFixed(2)}</span></div>` : ''}
        <div class="detail-row total-row"><span>Amount Received</span><span class="balance-paid">₹${amountReceived.toFixed(2)}</span></div>
        ${linkedInvoice ? `<div class="detail-row" style="padding-top:8px;"><span class="detail-label">Remaining Balance</span><span class="detail-value ${amountDue > 0 ? 'balance-due' : 'balance-paid'}">₹${amountDue.toFixed(2)}</span></div>` : ''}
      </div>
      ${payment.notes ? `<div style="background:white;padding:14px 18px;border-radius:8px;margin-bottom:20px;font-size:13px;"><strong style="color:#0f1e3d;">Notes:</strong><p style="margin:6px 0 0 0;color:#555;">${payment.notes}</p></div>` : ''}
    </div>
    <div class="footer">
      <strong>${orgName}</strong><br>
      ${orgGST ? `GST: ${orgGST}<br>` : ''}
      ${orgPhone ? `Ph: ${orgPhone}<br>` : ''}
      ${orgEmail || ''}
    </div>
  </div>
</body>
</html>`;

    res.json({
      success: true,
      data: {
        subject: `Payment Receipt - ${payment.paymentNumber} - Rs.${amountReceived.toFixed(2)}`,
        html,
        to: payment.customerEmail || '',
      }
    });
  } catch (error) {
    console.error('❌ Error generating payment email preview:', error);
    res.status(500).json({ success: false, message: 'Error generating email preview', error: error.message });
  }
});

// ============================================================================
// PATCH /:id/mark-as-sent — mark payment as sent without sending email
// ============================================================================

router.patch('/:id/mark-as-sent', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, message: 'Invalid payment ID' });
    }
    const query = { _id: new ObjectId(id) };
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const payment = await db.collection('payments_received').findOne(query);
    if (!payment) {
      return res.status(404).json({ success: false, message: 'Payment not found' });
    }

    await db.collection('payments_received').updateOne(query, {
      $set: { status: 'sent', markedAsSentAt: new Date(), updatedAt: new Date() }
    });

    console.log(`✅ Payment marked as sent (no email): ${payment.paymentNumber}`);
    res.json({ success: true, message: 'Payment marked as sent' });
  } catch (error) {
    console.error('❌ Error marking payment as sent:', error);
    res.status(500).json({ success: false, message: 'Error marking payment as sent', error: error.message });
  }
});

// ============================================================================
// POST /:id/send-email — send payment receipt email to customer
// ============================================================================

router.post('/:id/send-email', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, message: 'Invalid payment ID' });
    }
    const query = { _id: new ObjectId(id) };
    if (req.user?.orgId) query.orgId = req.user.orgId;

    const payment = await db.collection('payments_received').findOne(query);
    if (!payment) {
      return res.status(404).json({ success: false, message: 'Payment not found' });
    }

    const toEmail = payment.customerEmail;
    if (!toEmail) {
      return res.status(400).json({ success: false, message: 'Customer email not available on this payment' });
    }

    if (!emailTransporter) {
      return res.status(503).json({ success: false, message: 'Email service not configured' });
    }

    // Fetch linked invoice for balance info
    let linkedInvoice = null;
    try {
      const invoiceIds = Object.keys(payment.invoicePayments || {});
      if (invoiceIds.length > 0 && ObjectId.isValid(invoiceIds[0])) {
        linkedInvoice = await db.collection('invoices').findOne({ _id: new ObjectId(invoiceIds[0]) });
      }
    } catch (_) {}

    // Fetch org details
    let orgData = null;
    try {
      const mongoose = require('mongoose');
      const OrgModel = mongoose.models.Organization ||
        mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
      orgData = await OrgModel.findOne({ orgId: payment.orgId }).lean();
    } catch (_) {}
    const orgName  = orgData?.orgName   || 'Billing Team';
    const orgGST   = orgData?.gstNumber || '';
    const orgPhone = orgData?.phone     || '';
    const orgEmail = orgData?.email     || '';

    const amountReceived = parseFloat(payment.amountReceived || 0);
    const bankCharges    = parseFloat(payment.bankCharges    || 0);
    const amountDue      = linkedInvoice ? parseFloat(linkedInvoice.amountDue || 0) : 0;

    const emailHtml = `<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #0f1e3d 0%, #1a3a6b 50%, #2463ae 100%); color: white; padding: 30px 32px; border-radius: 8px 8px 0 0; }
    .header h1 { margin: 0 0 6px 0; font-size: 22px; }
    .header p  { margin: 0; font-size: 13px; opacity: 0.85; }
    .content { background: #f8f9fa; padding: 28px 32px; border-radius: 0 0 8px 8px; }
    .success-badge { background: #d4edda; color: #155724; padding: 14px 18px; border-radius: 8px; text-align: center; margin: 0 0 20px 0; border: 1px solid #c3e6cb; }
    .success-badge h2 { margin: 0 0 4px 0; font-size: 17px; }
    .success-badge p  { margin: 0; font-size: 13px; }
    .payment-box { background: white; padding: 20px; border-radius: 8px; margin: 0 0 20px 0; border-left: 4px solid #1a3a6b; }
    .payment-box h3 { margin: 0 0 14px 0; color: #0f1e3d; font-size: 15px; }
    .detail-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #f0f0f0; font-size: 13px; }
    .detail-row:last-child { border-bottom: none; }
    .detail-label { color: #666; }
    .detail-value { font-weight: 600; color: #222; }
    .total-row { padding-top: 12px; margin-top: 8px; border-top: 2px solid #1a3a6b; font-size: 15px; font-weight: bold; }
    .balance-due { color: #dc2626; }
    .balance-paid { color: #15803d; }
    .footer { text-align: center; color: #888; font-size: 11px; margin-top: 24px; line-height: 1.8; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>✅ Payment Receipt</h1>
      <p>${orgName} — Billing &amp; Finance</p>
    </div>
    <div class="content">
      <div class="success-badge">
        <h2>Payment Received Successfully</h2>
        <p>We have received your payment of ₹${amountReceived.toFixed(2)}</p>
      </div>

      <div class="payment-box">
        <h3>Payment Details</h3>
        <div class="detail-row">
          <span class="detail-label">Payment Number</span>
          <span class="detail-value">${payment.paymentNumber}</span>
        </div>
        <div class="detail-row">
          <span class="detail-label">Payment Date</span>
          <span class="detail-value">${payment.paymentDate}</span>
        </div>
        <div class="detail-row">
          <span class="detail-label">Payment Mode</span>
          <span class="detail-value">${payment.paymentMode}</span>
        </div>
        ${linkedInvoice ? `
        <div class="detail-row">
          <span class="detail-label">Invoice Number</span>
          <span class="detail-value">${linkedInvoice.invoiceNumber}</span>
        </div>` : ''}
        ${payment.reference ? `
        <div class="detail-row">
          <span class="detail-label">Reference Number</span>
          <span class="detail-value">${payment.reference}</span>
        </div>` : ''}
        ${bankCharges > 0 ? `
        <div class="detail-row">
          <span class="detail-label">Bank Charges</span>
          <span class="detail-value" style="color:#dc2626;">-₹${bankCharges.toFixed(2)}</span>
        </div>` : ''}
        <div class="detail-row total-row">
          <span>Amount Received</span>
          <span class="balance-paid">₹${amountReceived.toFixed(2)}</span>
        </div>
        ${linkedInvoice ? `
        <div class="detail-row" style="padding-top:8px;">
          <span class="detail-label">Remaining Balance</span>
          <span class="detail-value ${amountDue > 0 ? 'balance-due' : 'balance-paid'}">₹${amountDue.toFixed(2)}</span>
        </div>` : ''}
      </div>

      ${payment.notes ? `
      <div style="background:white;padding:14px 18px;border-radius:8px;margin-bottom:20px;font-size:13px;">
        <strong style="color:#0f1e3d;">Notes:</strong>
        <p style="margin:6px 0 0 0;color:#555;">${payment.notes}</p>
      </div>` : ''}

      <div style="background:white;padding:16px 18px;border-radius:8px;font-size:13px;">
        <strong style="color:#0f1e3d;">Need Help?</strong>
        <p style="margin:8px 0 0 0;color:#555;">
          ${orgEmail ? `📧 ${orgEmail}<br>` : ''}
          ${orgPhone ? `📞 ${orgPhone}<br>` : ''}
          🕐 Mon–Fri, 9 AM – 6 PM IST
        </p>
      </div>
    </div>
    <div class="footer">
      <strong>${orgName}</strong><br>
      ${orgGST ? `GST: ${orgGST}<br>` : ''}
      This is an automated email. Please do not reply.
    </div>
  </div>
</body>
</html>`;

    await emailTransporter.sendMail({
      from:    `"${orgName} - Billing" <${process.env.SMTP_USER}>`,
      to:      toEmail,
      subject: `Payment Receipt - ${payment.paymentNumber} - ₹${amountReceived.toFixed(2)}`,
      html:    emailHtml,
    });

    // Update payment record
    await db.collection('payments_received').updateOne(query, {
      $set: { emailSent: true, emailSentAt: new Date(), status: 'sent', updatedAt: new Date() },
      $push: { emailsSent: { sentTo: toEmail, sentAt: new Date() } }
    });

    console.log(`📧 Payment receipt email sent to ${toEmail} for ${payment.paymentNumber}`);
    res.json({ success: true, message: `Payment receipt email sent to ${toEmail}` });
  } catch (error) {
    console.error('❌ Error sending payment email:', error);
    res.status(500).json({ success: false, message: 'Error sending email', error: error.message });
  }
});

// ============================================================================
// GET PAYMENT PROOFS
// ============================================================================

router.get('/:id/proofs', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const payment = await db.collection('payments_received')
      .findOne({ _id: new ObjectId(id) });

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    res.json({
      success: true,
      data: payment.paymentProofs || []
    });

  } catch (error) {
    console.error('❌ Error fetching payment proofs:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching payment proofs',
      error: error.message
    });
  }
});

// ============================================================================
// DOWNLOAD PAYMENT PROOF
// ============================================================================

router.get('/:id/proofs/:proofIndex/download', verifyToken, async (req, res) => {
  try {
    const { id, proofIndex } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid payment ID'
      });
    }

    const payment = await db.collection('payments_received')
      .findOne({ _id: new ObjectId(id) });

    if (!payment) {
      return res.status(404).json({
        success: false,
        message: 'Payment not found'
      });
    }

    const index = parseInt(proofIndex);
    if (!payment.paymentProofs || index >= payment.paymentProofs.length) {
      return res.status(404).json({
        success: false,
        message: 'Proof not found'
      });
    }

    const proof = payment.paymentProofs[index];
    
    if (!fs.existsSync(proof.filepath)) {
      return res.status(404).json({
        success: false,
        message: 'Proof file not found on server'
      });
    }

    res.download(proof.filepath, proof.originalName);

  } catch (error) {
    console.error('❌ Error downloading payment proof:', error);
    res.status(500).json({
      success: false,
      message: 'Error downloading payment proof',
      error: error.message
    });
  }
});

// ============================================================================
// GET UNPAID INVOICES FOR CUSTOMER
// ============================================================================

// GET UNPAID INVOICES FOR CUSTOMER - FIXED TO HANDLE OBJECTID

























// ============================================================================
// GET PAYMENT STATISTICS
// ============================================================================


// ============================================================================
// EXPORT PAYMENTS TO CSV
// ============================================================================



// ============================================================================
// GET NEXT PAYMENT NUMBER
// ============================================================================


// ============================================================================
// DEBUG: COA ACCOUNT CHECK
// ============================================================================

router.get('/debug/coa-check', verifyToken, async (req, res) => {
  try {
    const orgId = req.user?.orgId || null;

    const accounts = await ChartOfAccount.find({
      accountName: { $in: ['Accounts Receivable', 'Undeposited Funds', 'Cash', 'Bank'] },
      ...(orgId ? { orgId } : {})
    }).select('accountName isSystemAccount orgId').lean();

    const allAccounts = await ChartOfAccount.find(
      orgId ? { orgId } : {}
    ).select('accountName isSystemAccount').lean();

    res.json({
      orgId,
      matchingAccounts: accounts,
      totalOrgAccounts: allAccounts.length,
      allAccountNames: allAccounts.map(a => a.accountName)
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});


module.exports = router;
