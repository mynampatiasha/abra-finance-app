// ============================================================================
// RECURRING EXPENSES SYSTEM - COMPLETE BACKEND IMPLEMENTATION (UPDATED)
// ============================================================================
// File: backend/routes/recurring_expenses.js
// Contains: Routes, Controllers, Models, Automatic Generation (Cron), PDF, Email
// Database: MongoDB with Mongoose
// Features:
// - Create, Edit, Pause, Resume, Stop recurring profiles
// - Automatic expense generation based on schedule (Cron Job)
// - Manual expense generation
// - PDF generation with ABRA Travels logo
// - Email notifications
// - Statistics and analytics
// - TAX SUPPORT: General Tax + GST with rates
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const cron = require('node-cron');
const PDFDocument = require('pdfkit');
const nodemailer = require('nodemailer');
const fs = require('fs');
const path = require('path');

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

// Recurring Expense Profile Schema (UPDATED WITH TAX SUPPORT)
const recurringExpenseSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  profileName: {
    type: String,
    required: true,
    trim: true
  },
  
  // Vendor Information
  vendorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
    required: true
  },
  vendorName: {
    type: String,
    required: true
  },
  vendorEmail: {
    type: String,
    default: ''
  },
  
expenseAccount: {
  type: String,
  required: true,
  trim: true,
},
paidThrough: {
  type: String,
  required: true,
  trim: true,
},
  amount: {
    type: Number,
    required: true,
    min: 0
  },
  
  // Billable flag
  isBillable: {
    type: Boolean,
    default: false
  },
  
  // Tax Settings (UPDATED)
  tax: {
    type: Number,
    default: 0,
    min: 0
  },
  gstRate: {
    type: Number,
    default: 0,
    min: 0
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
    required: true
  },
  endDate: {
    type: Date,
    default: null
  },
  maxOccurrences: {
    type: Number,
    default: null
  },
  
  // Next Expense Generation
  nextExpenseDate: {
    type: Date,
    required: true
  },
  
  // Status
  status: {
    type: String,
    enum: ['ACTIVE', 'PAUSED', 'STOPPED'],
    default: 'ACTIVE',
    index: true
  },
  
  // Tracking
  totalExpensesGenerated: {
    type: Number,
    default: 0
  },
  lastGeneratedDate: {
    type: Date,
    default: null
  },
  
  // Automation Settings
  expenseCreationMode: {
    type: String,
    enum: ['auto_create', 'draft'],
    default: 'auto_create'
  },
  
  // Additional Info
  notes: {
    type: String,
    default: ''
  },
  
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
  }
}, {
  timestamps: true
});

// Pre-save middleware to set nextExpenseDate
recurringExpenseSchema.pre('save', function() {
  if (this.isNew && !this.nextExpenseDate) {
    this.nextExpenseDate = this.startDate;
  }
});

// Indexes
recurringExpenseSchema.index({ status: 1, nextExpenseDate: 1 });
recurringExpenseSchema.index({ vendorId: 1 });

const RecurringExpense = mongoose.models.RecurringExpense || mongoose.model('RecurringExpense', recurringExpenseSchema);

// Expense Schema (linked to recurring profiles) - UPDATED WITH TAX SUPPORT
// const expenseSchema = new mongoose.Schema({
//   expenseNumber: {
//     type: String,
//     required: true,
//     unique: true,
//     index: true
//   },
  
//   // Link to recurring profile
//   recurringProfileId: {
//     type: mongoose.Schema.Types.ObjectId,
//     ref: 'RecurringExpense',
//     default: null
//   },
  
//   vendorId: {
//     type: mongoose.Schema.Types.ObjectId,
//     ref: 'Vendor',
//     required: true
//   },
//   vendorName: String,
  
// expenseAccount: {
//   type: String,
//   required: true,
//   trim: true,
// },
//   paidThrough: {
//     type: String,
//     required: true
//   },
//   amount: {
//     type: Number,
//     required: true,
//     min: 0
//   },
//   customerName: {
//   type: String,
//   default: null,
// },
// customerId: {
//   type: String,
//   default: null,
// },
  
//   // Billable flag
//   isBillable: {
//     type: Boolean,
//     default: false
//   },
  
//   // Tax Details (UPDATED)
//   tax: {
//     type: Number,
//     default: 0,
//     min: 0
//   },
//   gstRate: {
//     type: Number,
//     default: 0,
//     min: 0
//   },
//   gstAmount: {
//     type: Number,
//     default: 0,
//     min: 0
//   },
//   totalAmount: {
//     type: Number,
//     required: true
//   },
  
//   // Dates
//   date: {
//     type: Date,
//     required: true,
//     default: Date.now
//   },
  
//   // Status
//   status: {
//     type: String,
//     enum: ['DRAFT', 'RECORDED'],
//     default: 'RECORDED'
//   },
  
//   // Additional
//   notes: String,
  
//   // Audit
//   createdBy: String,
//   createdAt: {
//     type: Date,
//     default: Date.now
//   }
// }, {
//   timestamps: true
// });

// // Pre-save to calculate total (UPDATED WITH TAX CALCULATION)
// expenseSchema.pre('save', function() {
//   const taxAmount  = this.tax || 0;
//   const gstBase    = this.amount + taxAmount;
//   this.gstAmount   = gstBase * ((this.gstRate || 0) / 100);
//   this.totalAmount = this.amount + taxAmount + this.gstAmount;
// });

// Check if model already exists to avoid OverwriteModelError
// ✅ Force save to MAIN "expenses" collection so it shows in Expenses list
const expenseLooseSchema = new mongoose.Schema({}, { 
  strict: false, 
  collection: 'expenses'   // ← same collection as expenses.js
});
const RecurringGeneratedExpense = mongoose.models.RecurringGeneratedExpense
  || mongoose.model('RecurringGeneratedExpense', expenseLooseSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate unique expense number
async function generateExpenseNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(RecurringGeneratedExpense, 'expenseNumber', 'EXP', orgId);
}

// Calculate next expense date
function calculateNextExpenseDate(currentDate, repeatEvery, repeatUnit) {
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

// Check if profile should generate expense
function shouldGenerateExpense(profile) {
  const now = new Date();
  
  // Check status
  if (profile.status !== 'ACTIVE') {
    return false;
  }
  
  // Check if nextExpenseDate has passed
  if (profile.nextExpenseDate > now) {
    return false;
  }
  
  // Check end date
  if (profile.endDate && now > profile.endDate) {
    return false;
  }
  
  // Check max occurrences
  if (profile.maxOccurrences && profile.totalExpensesGenerated >= profile.maxOccurrences) {
    return false;
  }
  
  return true;
}

// ============================================================================
// AUTOMATIC EXPENSE GENERATION (CRON JOB)
// ============================================================================

// Run every hour to check for expenses to generate
cron.schedule('0 * * * *', async () => {
  console.log('🔄 Running automatic expense generation check...');
  
  try {
    // Find all active profiles that need generation
    const profiles = await RecurringExpense.find({
      status: 'ACTIVE',
      nextExpenseDate: { $lte: new Date() }
    });
    
    console.log(`📊 Found ${profiles.length} profiles to process`);
    
    for (const profile of profiles) {
      try {
        if (shouldGenerateExpense(profile)) {
          await generateExpenseFromProfile(profile, 'system-cron');
          console.log(`✅ Generated expense for profile: ${profile.profileName}`);
        }
      } catch (error) {
        console.error(`❌ Error generating expense for ${profile.profileName}:`, error);
      }
    }
  } catch (error) {
    console.error('❌ Error in automatic expense generation:', error);
  }
});

// Generate expense from recurring profile (UPDATED WITH TAX SUPPORT)
async function generateExpenseFromProfile(profile, createdBy = 'system') {
  const expenseNumber = await generateExpenseNumber(profile.orgId || null);
  const status        = profile.expenseCreationMode === 'auto_create' ? 'RECORDED' : 'DRAFT';

  const taxAmount   = profile.tax    || 0;
  const gstRate     = profile.gstRate || 0;
  const gstBase     = profile.amount + taxAmount;
  const gstAmount   = gstBase * (gstRate / 100);
  const totalAmount = profile.amount + taxAmount + gstAmount;

  // ✅ Handle vendorId safely — convert to ObjectId only if valid
  let vendorId;
  try {
    vendorId = mongoose.Types.ObjectId.isValid(profile.vendorId)
      ? new mongoose.Types.ObjectId(profile.vendorId.toString())
      : new mongoose.Types.ObjectId();
  } catch (e) {
    vendorId = new mongoose.Types.ObjectId();
  }

const expense = new RecurringGeneratedExpense({
  expenseNumber,
  recurringProfileId:    profile._id,
  isRecurring:           true,              // ✅ badge flag for UI
  recurringProfileName:  profile.profileName,
  vendorId,
  vendor:                profile.vendorName, // ✅ expenses.js uses "vendor" not "vendorName"
  vendorName:            profile.vendorName,
  expenseAccount:        profile.expenseAccount,
  paidThrough:           profile.paidThrough,
  amount:                profile.amount,
  isBillable:            profile.isBillable  || false,
  customerName:          profile.customerName || null,
  customerId:            profile.customerId   || null,
  tax:                   taxAmount,
  gstRate,
  gstAmount,
  total:                 totalAmount,        // ✅ expenses.js requires "total"
  totalAmount,
  subtotal:              profile.amount,
  date: new Date(profile.nextExpenseDate)
          .toISOString().split('T')[0],      // ✅ expenses.js stores date as "YYYY-MM-DD" string
  status,
  isBilled:              false,
  notes:                 `Auto-generated from recurring profile: ${profile.profileName}`,
  createdBy,
});

  await expense.save();

  // ✅ COA Posting
  try {
    const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

    const coaOrgId = profile.orgId || null;

    let expAccId = await ChartOfAccount.findOne({
      accountName: { $regex: `^${profile.expenseAccount}$`, $options: 'i' },
      ...(coaOrgId ? { orgId: coaOrgId } : {}),
    }).select('_id').lean().then(a => a?._id);

    if (!expAccId) {
      const newAcc = await ChartOfAccount.create({
        accountName:     profile.expenseAccount,
        accountCode:     `EXP-${Date.now().toString().slice(-6)}`,
        accountType:     'Expense',
        accountSubType:  'Operating Expense',
        isSystemAccount: false,
        isActive:        true,
        openingBalance:  0,
        currentBalance:  0,
        currency:        'INR',
        transactions:    [],
        orgId:           coaOrgId,
      });
      expAccId = newAcc._id;
    }

    const paidAccId = await ChartOfAccount.findOne({
      accountName: { $regex: `^${profile.paidThrough}$`, $options: 'i' },
      ...(coaOrgId ? { orgId: coaOrgId } : {}),
    }).select('_id').lean().then(a => a?._id);

    const txnDate     = new Date(expense.date);
    const description = `Recurring Expense - ${profile.profileName} - ${profile.expenseAccount}`;

    if (expAccId) await postTransactionToCOA({
      accountId:       expAccId,
      orgId:           coaOrgId,
      date:            txnDate,
      description,
      referenceType:   'Expense',
      referenceId:     expense._id,
      referenceNumber: expense.expenseNumber,
      debit:           totalAmount,
      credit:          0,
    });

    if (paidAccId) await postTransactionToCOA({
      accountId:       paidAccId,
      orgId:           coaOrgId,
      date:            txnDate,
      description,
      referenceType:   'Expense',
      referenceId:     expense._id,
      referenceNumber: expense.expenseNumber,
      debit:           0,
      credit:          totalAmount,
    });

    console.log(`✅ COA posted for recurring expense: ${expense.expenseNumber}`);
  } catch (coaErr) {
    console.error('⚠️ COA post error (recurring expense):', coaErr.message);
  }

  // Update profile
  profile.totalExpensesGenerated += 1;
  profile.lastGeneratedDate       = new Date();
  profile.nextExpenseDate         = calculateNextExpenseDate(
    profile.nextExpenseDate,
    profile.repeatEvery,
    profile.repeatUnit
  );

  if (profile.endDate && profile.nextExpenseDate > profile.endDate) {
    profile.status = 'STOPPED';
  }
  if (profile.maxOccurrences && profile.totalExpensesGenerated >= profile.maxOccurrences) {
    profile.status = 'STOPPED';
  }

  await profile.save();

  if (status === 'RECORDED') {
    try {
      await sendExpenseGeneratedEmail(profile, expense);
    } catch (emailError) {
      console.warn('Failed to send email notification:', emailError.message);
    }
  }

  return expense;
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

// Get logo as base64
function getLogoBase64() {
  try {
    const possibleLogoPaths = [
      path.join(__dirname, '..', 'assets', 'abra.jpeg'),
      path.join(__dirname, '..', 'assets', 'abra.jpg'),
      path.join(__dirname, '..', 'assets', 'abra.png'),
      path.join(process.cwd(), 'assets', 'abra.jpeg'),
      path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg')
    ];
    
    for (const logoPath of possibleLogoPaths) {
      if (fs.existsSync(logoPath)) {
        const imageBuffer = fs.readFileSync(logoPath);
        const base64 = imageBuffer.toString('base64');
        const ext = path.extname(logoPath).toLowerCase();
        const mimeType = ext === '.png' ? 'image/png' : 'image/jpeg';
        return `data:${mimeType};base64,${base64}`;
      }
    }
  } catch (error) {
    console.error('❌ Error reading logo:', error);
  }
  return null;
}

// Send expense generated email (UPDATED WITH TAX INFO)
async function sendExpenseGeneratedEmail(profile, expense) {
  // Fetch org details from DB
  let orgName  = '';
  let orgGST   = '';
  let orgPhone = '';
  let orgEmail = '';
  try {
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: profile.orgId }).lean();
    orgName  = org?.orgName   || '';
    orgGST   = org?.gstNumber || '';
    orgPhone = org?.phone     || '';
    orgEmail = org?.email     || '';
  } catch (e) {
    console.warn('⚠️ Could not fetch org details for email:', e.message);
  }

  const taxAmount = expense.tax      || 0;
  const gstAmount = expense.gstAmount || 0;
  const cgst      = gstAmount / 2;
  const sgst      = gstAmount / 2;

  const emailHtml = `<!DOCTYPE html> <html lang="en"> <head>   <meta charset="UTF-8">   <meta name="viewport" content="width=device-width, initial-scale=1.0">   <title>Recurring Expense Generated</title>   <style>     * { margin: 0; padding: 0; box-sizing: border-box; }     body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222; background: #f4f4f4; }     .wrapper { max-width: 620px; margin: 24px auto; background: #fff; border: 1px solid #ddd; }     .header { background: #0f1e3d; padding: 24px 32px; }     .header h1 { color: #fff; font-size: 20px; font-weight: bold; margin-bottom: 2px; }     .header p  { color: rgba(255,255,255,0.7); font-size: 11px; letter-spacing: 0.5px; }     .body { padding: 28px 32px; }     .section-title { font-size: 10px; font-weight: bold; text-transform: uppercase;                      letter-spacing: 1px; color: #666; border-bottom: 1px solid #e0e0e0;                      padding-bottom: 6px; margin: 22px 0 12px; }     table.detail { width: 100%; border-collapse: collapse; font-size: 13px; }     table.detail td { padding: 7px 0; border-bottom: 1px dashed #e8e8e8; vertical-align: top; }     table.detail td:first-child { color: #555; width: 160px; }     table.detail td:last-child  { font-weight: 600; color: #111; text-align: right; }     .total-row td { font-size: 15px; font-weight: bold; border-top: 2px solid #222;                     border-bottom: none; padding-top: 10px; }     .footer { background: #f4f4f4; border-top: 1px solid #ddd; padding: 16px 32px;               font-size: 11px; color: #777; text-align: center; line-height: 1.7; }   </style> </head> <body> <div class="wrapper">   <div class="header">     <h1>${orgName}</h1>     <p>RECURRING EXPENSE GENERATED</p>   </div>   <div class="body">     <p style="font-size:14px;color:#222;margin-bottom:18px;">Dear ${profile.vendorName || 'Vendor'},</p>     <p style="color:#444;line-height:1.7;margin-bottom:6px;">       A new expense has been automatically generated from recurring profile       <strong>${profile.profileName}</strong>.     </p>      <div class="section-title">Expense Details</div>     <table class="detail">       <tr><td>Expense Number</td><td>${expense.expenseNumber}</td></tr>       <tr><td>Profile Name</td>  <td>${profile.profileName}</td></tr>       <tr><td>Vendor</td>        <td>${profile.vendorName}</td></tr>       <tr><td>Category</td>      <td>${profile.expenseAccount}</td></tr>       <tr><td>Paid Through</td>  <td>${profile.paidThrough}</td></tr>       <tr><td>Date</td>          <td>${new Date(expense.date).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</td></tr>       <tr><td>Amount</td>        <td>Rs. ${(expense.amount || 0).toFixed(2)}</td></tr>       ${taxAmount > 0 ? `<tr><td>Tax</td><td>Rs. ${taxAmount.toFixed(2)}</td></tr>` : ''}       ${gstAmount > 0 ? `       <tr><td>CGST (${((profile.gstRate || 0) / 2).toFixed(1)}%)</td><td>Rs. ${cgst.toFixed(2)}</td></tr>       <tr><td>SGST (${((profile.gstRate || 0) / 2).toFixed(1)}%)</td><td>Rs. ${sgst.toFixed(2)}</td></tr>       ` : ''}       <tr class="total-row"><td>Total Amount</td><td>Rs. ${(expense.totalAmount || 0).toFixed(2)}</td></tr>     </table>      <div class="section-title">Recurring Schedule</div>     <table class="detail">       <tr><td>Frequency</td>      <td>Every ${profile.repeatEvery} ${profile.repeatUnit}(s)</td></tr>       <tr><td>Next Expense</td>   <td>${new Date(profile.nextExpenseDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}</td></tr>       <tr><td>Total Generated</td><td>${profile.totalExpensesGenerated}</td></tr>     </table>      <p style="margin-top:22px;font-size:12px;color:#555;line-height:1.7;">       This expense has been automatically       <strong>${expense.status === 'RECORDED' ? 'recorded' : 'saved as draft'}</strong>       in your system.     </p>   </div>   <div class="footer">     <strong>${orgName}</strong><br>     ${orgGST   ? 'GST: '  + orgGST   + ' &nbsp;|&nbsp; ' : ''}     ${orgPhone ? 'Ph: '   + orgPhone  + ' &nbsp;|&nbsp; ' : ''}     ${orgEmail || ''}   </div> </div> </body> </html>`;

  return emailTransporter.sendMail({
    from: `"${orgName} - Expense System" <${process.env.SMTP_USER}>`,
    to: process.env.ADMIN_EMAIL || process.env.SMTP_USER,
    subject: `Expense ${expense.expenseNumber} Generated - ${profile.profileName}`,
    html: emailHtml
  });
}

// ============================================================================
// API ROUTES
// ============================================================================

// GET /api/recurring-expenses - List all recurring expense profiles
router.get('/', async (req, res) => {
  try {
    const { status, fromDate, toDate, page = 1, limit = 20 } = req.query;
    
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (status && status !== 'All') {
      query.status = status;
    }
    
    if (fromDate || toDate) {
      query.startDate = {};
      if (fromDate) query.startDate.$gte = new Date(fromDate);
      if (toDate) query.startDate.$lte = new Date(toDate);
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const profiles = await RecurringExpense.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    
    const total = await RecurringExpense.countDocuments(query);
    
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
    console.error('Error fetching recurring expenses:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recurring-expenses/stats - Get statistics
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const totalProfiles = await RecurringExpense.countDocuments(orgFilter);
    const activeProfiles = await RecurringExpense.countDocuments({ ...orgFilter, status: 'ACTIVE' });
    const pausedProfiles = await RecurringExpense.countDocuments({ ...orgFilter, status: 'PAUSED' });
    const stoppedProfiles = await RecurringExpense.countDocuments({ ...orgFilter, status: 'STOPPED' });
    
    // Calculate total expenses generated and amount (UPDATED WITH TAX)
    const generationStats = await RecurringExpense.aggregate([
      { $match: orgFilter },
      {
        $group: {
          _id: null,
          totalExpensesGenerated: { $sum: '$totalExpensesGenerated' },
          totalAmount: { 
            $sum: { 
              $multiply: [
                '$totalExpensesGenerated',
                {
                  $add: [
                    '$amount',
                    { $ifNull: ['$tax', 0] },
                    {
                      $multiply: [
                        { $add: ['$amount', { $ifNull: ['$tax', 0] }] },
                        { $divide: [{ $ifNull: ['$gstRate', 0] }, 100] }
                      ]
                    }
                  ]
                }
              ]
            } 
          }
        }
      }
    ]);
    
    const stats = {
      totalProfiles,
      activeProfiles,
      pausedProfiles,
      stoppedProfiles,
      totalExpensesGenerated: generationStats[0]?.totalExpensesGenerated || 0,
      totalAmountGenerated: generationStats[0]?.totalAmount || 0
    };
    
    res.json({ success: true, data: stats });
  } catch (error) {
    console.error('Error fetching stats:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recurring-expenses/:id - Get single recurring expense
router.get('/:id', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    res.json({ success: true, data: profile });
  } catch (error) {
    console.error('Error fetching recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses - Create new recurring expense
router.post('/', async (req, res) => {
  try {
    const profileData = req.body;
    
    // Handle vendorId
    if (profileData.vendorId) {
      if (typeof profileData.vendorId === 'string') {
        if (mongoose.Types.ObjectId.isValid(profileData.vendorId)) {
          profileData.vendorId = new mongoose.Types.ObjectId(profileData.vendorId);
        } else {
          profileData.vendorId = new mongoose.Types.ObjectId();
        }
      }
    }
    
    // Set creator
    profileData.createdBy = req.user?.email || req.user?.uid || 'system';
    profileData.orgId = req.user?.orgId || null;
    
    // Set initial nextExpenseDate to startDate
    if (!profileData.nextExpenseDate) {
      profileData.nextExpenseDate = profileData.startDate;
    }
    
    // Ensure tax fields are numbers
    if (profileData.tax) {
      profileData.tax = Number(profileData.tax);
    }
    if (profileData.gstRate) {
      profileData.gstRate = Number(profileData.gstRate);
    }
    
    const profile = new RecurringExpense(profileData);
    await profile.save();
    
    console.log(`✅ Recurring expense profile created: ${profile.profileName}`);
    
    res.status(201).json({
      success: true,
      message: 'Recurring expense profile created successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error creating recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// PUT /api/recurring-expenses/:id - Update recurring expense
router.put('/:id', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'system';
    
    // Ensure tax fields are numbers
    if (updates.tax) {
      updates.tax = Number(updates.tax);
    }
    if (updates.gstRate) {
      updates.gstRate = Number(updates.gstRate);
    }
    
    Object.assign(profile, updates);
    await profile.save();
    
    console.log(`✅ Recurring expense updated: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense updated successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error updating recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/pause - Pause profile
router.post('/:id/pause', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    if (profile.status !== 'ACTIVE') {
      return res.status(400).json({ success: false, error: 'Only active profiles can be paused' });
    }
    
    profile.status = 'PAUSED';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`⏸️ Recurring expense paused: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense paused successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error pausing recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/resume - Resume profile
router.post('/:id/resume', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    if (profile.status !== 'PAUSED') {
      return res.status(400).json({ success: false, error: 'Only paused profiles can be resumed' });
    }
    
    profile.status = 'ACTIVE';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`▶️ Recurring expense resumed: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense resumed successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error resuming recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/stop - Stop profile permanently
router.post('/:id/stop', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    profile.status = 'STOPPED';
    profile.updatedBy = req.user?.email || req.user?.uid || 'system';
    await profile.save();
    
    console.log(`⏹️ Recurring expense stopped: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense stopped successfully',
      data: profile
    });
  } catch (error) {
    console.error('Error stopping recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/recurring-expenses/:id/generate - Generate expense manually
router.post('/:id/generate', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    const createdBy = req.user?.email || req.user?.uid || 'manual-generation';
    const expense = await generateExpenseFromProfile(profile, createdBy);
    
    console.log(`✅ Manual expense generated: ${expense.expenseNumber}`);
    
    res.status(201).json({
      success: true,
      message: 'Expense generated successfully',
      data: {
        expenseId: expense._id,
        expenseNumber: expense.expenseNumber,
        amount: expense.totalAmount,
        expenseDate: expense.date
      }
    });
  } catch (error) {
    console.error('Error generating expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recurring-expenses/:id/child-expenses - Get child expenses
router.get('/:id/child-expenses', async (req, res) => {
  try {
    const expenses = await RecurringGeneratedExpense.find({
      recurringProfileId: req.params.id
    }).sort({ date: -1 });
    
    res.json({
      success: true,
      data: expenses
    });
  } catch (error) {
    console.error('Error fetching child expenses:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/recurring-expenses/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!profile) return res.status(404).json({ success: false, error: 'Profile not found' });
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();
    const orgName = org?.orgName || '';
    const orgGST  = org?.gstNumber || '';
    const orgPhone = org?.phone || '';
    const orgEmail = org?.email || '';
    const html = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Recurring Expense ${profile.profileName}</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;font-size:13px;color:#222;background:#f4f4f4}.wrapper{max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd}.header{background:#0f1e3d;padding:24px 32px}.header h1{color:#fff;font-size:20px;font-weight:bold}.body{padding:28px 32px}.st{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px}table.d{width:100%;border-collapse:collapse;font-size:13px}table.d td{padding:7px 0;border-bottom:1px dashed #e8e8e8;vertical-align:top}table.d td:first-child{color:#555;width:160px}table.d td:last-child{font-weight:600;color:#111;text-align:right}.footer{background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7}</style>
</head><body><div class="wrapper">
<div class="header"><h1>Recurring Expense Generated</h1></div>
<div class="body">
<p style="font-size:14px;margin-bottom:18px;">Dear ${profile.vendorName || 'Vendor'},</p>
<p style="color:#444;line-height:1.7;margin-bottom:6px;">A recurring expense has been generated for profile <strong>${profile.profileName}</strong>.</p>
<div class="st">Expense Details</div>
<table class="d">
<tr><td>Profile</td><td>${profile.profileName}</td></tr>
<tr><td>Expense Account</td><td>${profile.expenseAccount || ''}</td></tr>
<tr><td>Paid Through</td><td>${profile.paidThrough || ''}</td></tr>
<tr><td>Amount</td><td>₹${(profile.amount || 0).toFixed(2)}</td></tr>
${profile.tax > 0 ? `<tr><td>Tax</td><td>₹${profile.tax.toFixed(2)}</td></tr>` : ''}
</table>
</div>
<div class="footer"><strong>${orgName}</strong><br>${orgGST ? 'GST: ' + orgGST + ' | ' : ''}${orgPhone ? 'Ph: ' + orgPhone + ' | ' : ''}${orgEmail}</div>
</div></body></html>`;
    res.json({ success: true, data: { subject: `Recurring Expense — ${profile.profileName}`, html, to: profile.vendorEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/recurring-expenses/:id - Delete profile
router.delete('/:id', async (req, res) => {
  try {
    const profile = await RecurringExpense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Recurring expense not found' });
    }
    
    await profile.deleteOne();
    
    console.log(`✅ Recurring expense deleted: ${profile.profileName}`);
    
    res.json({
      success: true,
      message: 'Recurring expense deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting recurring expense:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// EXPORT MODULE
// ============================================================================

module.exports = router;