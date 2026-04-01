const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const mongoose = require('mongoose');
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');


// ============================================================================
// MONGOOSE SCHEMA DEFINITION (INLINE - NO SEPARATE MODEL FILE NEEDED)
// ============================================================================

const receiptFileSchema = new mongoose.Schema({
  filename: String,
  originalName: String,
  path: String,
  size: Number,
  mimetype: String
}, { _id: false });

const proofFileSchema = new mongoose.Schema({
  filename:     String,
  originalName: String,
  path:         String,
  size:         Number,
  mimetype:     String,
  uploadedAt:   { type: Date, default: Date.now },
}, { _id: false });

const itemizedExpenseSchema = new mongoose.Schema({
  expenseAccount: String,
  amount: {
    type: Number,
    required: true
  },
  description: String
}, { _id: false });

const expenseSchema = new mongoose.Schema({
  date: {
    type: String,
    required: true
  },
  expenseAccount: {
    type: String,
    required: true
  },
  amount: {
    type: Number,
    required: true
  },
  tax: {
    type: Number,
    default: 0
  },
  total: {
    type: Number,
    required: true
  },
  paidThrough: {
    type: String,
    required: true
  },
  vendor: {
    type: String,
    default: null
  },
  invoiceNumber: {
    type: String,
    default: null
  },
  customerName: {
    type: String,
    default: null
  },
  isBillable: {
    type: Boolean,
    default: false
  },
  project: {
    type: String,
    default: null
  },
  markupPercentage: {
    type: Number,
    default: 0
  },
  billableAmount: {
    type: Number,
    default: 0
  },
  reportingTags: [{
    type: String
  }],
  notes: {
    type: String,
    default: null
  },
  isItemized: {
    type: Boolean,
    default: false
  },
 itemizedExpenses: [itemizedExpenseSchema],
  receiptFile: receiptFileSchema,
  proofFile:   proofFileSchema,
isBilled: {
  type: Boolean,
  default: false
},
// ✅ Recurring expense fields
isRecurring: {
  type: Boolean,
  default: false,
},
recurringProfileId: {
  type: mongoose.Schema.Types.ObjectId,
  default: null,
},
recurringProfileName: {
  type: String,
  default: null,
},
expenseNumber: {
  type: String,
  default: null,
},
  invoiceId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Invoice',
    default: null
  },
  orgId: { type: String, index: true, default: null }
}, {
  timestamps: true // Automatically adds createdAt and updatedAt
});

// Create indexes for better query performance
expenseSchema.index({ date: -1 });
expenseSchema.index({ expenseAccount: 1 });
expenseSchema.index({ vendor: 1 });
expenseSchema.index({ customerName: 1 });
expenseSchema.index({ isBillable: 1 });

// Create or get the Expense model
// Create or get the Expense model
const Expense = mongoose.models.Expense || mongoose.model('Expense', expenseSchema);

// Reference PaymentAccount model for balance updates
const PaymentAccount = mongoose.models.PaymentAccount || mongoose.model('PaymentAccount', new mongoose.Schema({
  currentBalance: { type: Number, default: 0 }
}, { strict: false }));

async function getExpenseAccountId(accountName, orgId = null) {
  try {
    // Step 1: Try exact match first
    let acc = await ChartOfAccount.findOne({
      accountName: { $regex: `^${accountName}$`, $options: 'i' },
      ...(orgId ? { orgId } : {}),
    }).select('_id').lean();
    if (acc) return acc._id;

    // Step 2: Not found — AUTO CREATE the expense account
    console.log(`📝 COA account "${accountName}" not found — creating automatically...`);

    const newAcc = await ChartOfAccount.create({
      accountName:        accountName,
      accountCode:        `EXP-${Date.now().toString().slice(-6)}`,
      accountType:        'Expense',
      orgId:              orgId,
      accountSubType:     'Operating Expense',
      description:        `${accountName} expenses`,
      isSystemAccount:    false,
      isActive:           true,
      openingBalance:     0,
      currentBalance:     0,
      currency:           'INR',
      transactions:       [],
    });

    console.log(`✅ Auto-created COA account: "${accountName}" → ID: ${newAcc._id}`);
    return newAcc._id;

  } catch (e) {
    console.error('COA lookup/create error for expense account:', e.message);
    return null;
  }
}

async function getPaidThroughAccountId(paidThrough, orgId = null) {
  try {
    // Step 1: Check if it's a valid ObjectId
    if (mongoose.Types.ObjectId.isValid(paidThrough)) {
      const acc = await ChartOfAccount.findOne({
        _id: paidThrough,
        ...(orgId ? { orgId } : {}),
      }).select('_id').lean();
      if (acc) return acc._id;
    }

    // Step 2: Try exact name match
    let acc = await ChartOfAccount.findOne({
      accountName: { $regex: `^${paidThrough}$`, $options: 'i' },
      ...(orgId ? { orgId } : {}),
    }).select('_id').lean();
    if (acc) return acc._id;

    // Step 3: Not found — AUTO CREATE the paid-through account
    console.log(`📝 COA account "${paidThrough}" not found — creating automatically...`);

    const newAcc = await ChartOfAccount.create({
      accountName:        paidThrough,
      accountCode:        `CASH-${Date.now().toString().slice(-6)}`,
      accountType:        'Cash and Cash Equivalents',
      orgId:              orgId,
      accountSubType:     'Cash',
      description:        `${paidThrough} account`,
      isSystemAccount:    false,
      isActive:           true,
      openingBalance:     0,
      currentBalance:     0,
      currency:           'INR',
      transactions:       [],
    });

    console.log(`✅ Auto-created COA account: "${paidThrough}" → ID: ${newAcc._id}`);
    return newAcc._id;

  } catch (e) {
    console.error('COA lookup/create error for paid through account:', e.message);
    return null;
  }
}

async function generateExpenseNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(Expense, 'expenseNumber', 'EXP', orgId);
}

// ============================================================================
// MULTER CONFIGURATION - FILE UPLOADS
// ============================================================================

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = './uploads/receipts';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, 'receipt-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const fileFilter = (req, file, cb) => {
  const allowedTypes = /jpeg|jpg|png|pdf|gif/;
  const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
  const mimetype = allowedTypes.test(file.mimetype);

  if (mimetype && extname) {
    return cb(null, true);
  } else {
    cb(new Error('Only images (JPEG, PNG, GIF) and PDF files are allowed!'));
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: { fileSize: 5 * 1024 * 1024 }
});

const importStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = './uploads/imports';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, 'import-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const importFileFilter = (req, file, cb) => {
  console.log('📋 File upload check:');
  console.log('  - Filename:', file.originalname);
  console.log('  - MIME type:', file.mimetype);
  
  // Check file extension (most reliable across web and mobile)
  const allowedExtensions = /\.(xlsx|xls|csv)$/i;
  const hasValidExtension = allowedExtensions.test(file.originalname);
  
  console.log('  - Extension valid:', hasValidExtension);

  if (hasValidExtension) {
    console.log('✅ File accepted');
    return cb(null, true);
  } else {
    console.log('❌ File rejected - invalid extension');
    cb(new Error('Only Excel (.xlsx, .xls) and CSV (.csv) files are allowed!'));
  }
};

const importUpload = multer({
  storage: importStorage,
  fileFilter: importFileFilter,
  limits: { fileSize: 10 * 1024 * 1024 }
});

// ── Proof upload multer config ────────────────────────────────────────────────
const proofStorage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = './uploads/proofs';
    if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, 'proof-' + uniqueSuffix + path.extname(file.originalname));
  },
});

const proofFileFilter = (req, file, cb) => {
  const allowedExtensions = /jpeg|jpg|png|pdf|gif|webp/;
  const extOk = allowedExtensions.test(path.extname(file.originalname).toLowerCase());
  // Accept application/octet-stream (common from web browsers) + explicit image/pdf types
  const mimeOk = allowedExtensions.test(file.mimetype) || file.mimetype === 'application/octet-stream';
  if (extOk && mimeOk) return cb(null, true);
  cb(new Error('Only images (JPEG, PNG, GIF, WEBP) and PDF files are allowed for proof!'));
};

const proofUpload = multer({
  storage:    proofStorage,
  fileFilter: proofFileFilter,
  limits:     { fileSize: 10 * 1024 * 1024 }, // 10 MB
});

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function handleError(res, statusCode, message, error = null) {
  console.error(`❌ ${message}:`, error);
  res.status(statusCode).json({
    success: false,
    message,
    error: error?.message || error
  });
}

function parseDate(dateValue) {
  if (!dateValue) return null;
  
  if (typeof dateValue === 'number') {
    const excelEpoch = new Date(1899, 11, 30);
    return new Date(excelEpoch.getTime() + dateValue * 86400000);
  }
  
  if (typeof dateValue === 'string') {
    const ddmmyyyy = dateValue.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
    if (ddmmyyyy) {
      const [, day, month, year] = ddmmyyyy;
      return new Date(year, month - 1, day);
    }
    
    const yyyymmdd = dateValue.match(/^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})$/);
    if (yyyymmdd) {
      const [, year, month, day] = yyyymmdd;
      return new Date(year, month - 1, day);
    }
    
    return new Date(dateValue);
  }
  
  return new Date(dateValue);
}

function isValidExpenseAccount(account) {
  const validAccounts = [
    'Fuel',
    'Office Supplies',
    'Travel & Conveyance',
    'Advertising & Marketing',
    'Meals & Entertainment',
    'Utilities',
    'Rent',
    'Professional Fees',
    'Insurance',
    'Other Expenses'
  ];
  
  // Allow any value if it's not empty (for custom expense accounts)
  // Or check if it's in the predefined list
  return account && account.trim().length > 0;
}


// ============================================================================
// GET BILLABLE EXPENSES BY CUSTOMER
// ============================================================================

router.get('/billable/:customerId', async (req, res) => {
  try {
    const { customerId } = req.params;
    console.log(`📥 Fetching billable expenses for customer: ${customerId}`);

    const expenses = await Expense.find({
      isBillable: true,
      isBilled: false,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
      $or: [
        { customerName: customerId },
        { customerId: customerId }
      ]
    }).sort({ date: -1 });

    console.log(`✅ Found ${expenses.length} unbilled expenses`);

    res.json({
      success: true,
      data: expenses,
      total: expenses.length
    });
  } catch (error) {
    console.error('❌ Error fetching billable expenses:', error);
    handleError(res, 500, 'Error fetching billable expenses', error);
  }
});

// ============================================================================
// ROUTES
// ============================================================================

// ============================================================================
// GET ALL EXPENSES
// ============================================================================

router.get('/', async (req, res) => {
  try {
    console.log('📥 Fetching all expenses from MongoDB...');
    
    const { vendor, customerName, startDate, endDate, expenseAccount } = req.query;
    let query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;

    if (vendor) {
      query.vendor = new RegExp(vendor, 'i');
    }

    if (customerName) {
      query.customerName = new RegExp(customerName, 'i');
    }

    if (expenseAccount) {
      query.expenseAccount = expenseAccount;
    }

    if (startDate || endDate) {
      query.date = {};
      if (startDate) query.date.$gte = startDate;
      if (endDate) query.date.$lte = endDate;
    }

    const expenses = await Expense.find(query).sort({ date: -1 });
    
    console.log(`✅ Fetched ${expenses.length} expenses from MongoDB`);

    res.json({
      success: true,
      data: expenses,
      total: expenses.length
    });
  } catch (error) {
    console.error('❌ Error fetching expenses:', error);
    handleError(res, 500, 'Error fetching expenses', error);
  }
});

// ============================================================================
// POST CREATE NEW EXPENSE
// ============================================================================

router.post('/', upload.single('receipt'), async (req, res) => {
  try {
    const {
      date, expenseAccount, amount, tax, paidThrough,
      vendor, invoiceNumber, customerName, isBillable,
      project, markupPercentage, reportingTags, notes,
      isItemized, itemizedExpenses
    } = req.body;

    console.log('📥 Creating expense in MongoDB:', { date, expenseAccount, amount, paidThrough });
    console.log('🔍 DEBUG - Raw field values:');
    console.log('  - amount (raw):', amount, 'type:', typeof amount);
    console.log('  - tax (raw):', tax, 'type:', typeof tax);
    console.log('  - isItemized:', isItemized, 'type:', typeof isItemized);

    // Validation
    const errors = [];
    if (!date) errors.push('Date is required');
    if (!expenseAccount) errors.push('Expense Account is required');
    if (!paidThrough) errors.push('Paid Through is required');

    const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
    if (date && !dateRegex.test(date)) {
      errors.push('Invalid date format. Use YYYY-MM-DD');
    }

    if (expenseAccount && !isValidExpenseAccount(expenseAccount)) {
      errors.push(`Invalid expense account: "${expenseAccount}"`);
    }

    if (!isItemized || isItemized === 'false') {
      if (!amount) {
        errors.push('Amount is required for non-itemized expenses');
      } else if (isNaN(parseFloat(amount)) || parseFloat(amount) <= 0) {
        errors.push('Amount must be a positive number');
      }
    }

    if (errors.length > 0) {
      if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      return res.status(400).json({ success: false, message: 'Validation failed', errors });
    }

    // Parse itemized
    let parsedItemizedExpenses = [];
    if (isItemized && itemizedExpenses) {
      try {
        parsedItemizedExpenses = typeof itemizedExpenses === 'string'
          ? JSON.parse(itemizedExpenses) : itemizedExpenses;
      } catch (e) {
        if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
        return res.status(400).json({ success: false, message: 'Invalid itemized expenses format' });
      }
    }

    // Parse reporting tags
    let parsedReportingTags = [];
    if (reportingTags) {
      try {
        parsedReportingTags = typeof reportingTags === 'string'
          ? JSON.parse(reportingTags) : reportingTags;
      } catch (e) { parsedReportingTags = []; }
    }

    // Calculate totals
    const isItemizedBool = isItemized === 'true' || isItemized === true;
    const amountValue = amount ? parseFloat(String(amount).replace(/[^0-9.-]/g, '')) : 0;

    console.log('💰 Amount calculation debug:', { isItemized, isItemizedBool, amount, amountValue });

    const subtotal = isItemizedBool
      ? parsedItemizedExpenses.reduce((sum, item) => sum + parseFloat(item.amount || 0), 0)
      : amountValue;

    console.log('✅ Calculated subtotal:', subtotal);

    const taxAmount = tax ? parseFloat(String(tax).replace(/[^0-9.-]/g, '')) : 0;
    const total = subtotal + taxAmount;
    const billableAmount = isBillable && markupPercentage
      ? total * (1 + parseFloat(markupPercentage) / 100) : total;

    // Create expense
    const newExpense = new Expense({
      date, expenseAccount,
      amount: subtotal, tax: taxAmount, total,
      paidThrough,
      vendor: vendor || null,
      invoiceNumber: invoiceNumber || null,
      customerName: customerName || null,
      isBillable: isBillable === 'true' || isBillable === true,
      project: project || null,
      markupPercentage: parseFloat(markupPercentage || 0),
      billableAmount,
      reportingTags: parsedReportingTags,
      notes: notes || null,
      isItemized: isItemizedBool,
      itemizedExpenses: parsedItemizedExpenses,
      isBilled: false,
      invoiceId: null,
      orgId: req.user?.orgId || null,
      expenseNumber: await generateExpenseNumber(req.user?.orgId || null),
      receiptFile: req.file ? {
        filename: req.file.filename,
        originalName: req.file.originalname,
        path: req.file.path,
        size: req.file.size,
        mimetype: req.file.mimetype
      } : null
    });

    await newExpense.save();
    console.log('✅ Expense created in MongoDB:', newExpense._id);

    // ── BALANCE UPDATE ──────────────────────────────────────────────────────
    try {
      let balanceUpdated = false;
      if (mongoose.Types.ObjectId.isValid(paidThrough)) {
        const result = await PaymentAccount.findByIdAndUpdate(
          paidThrough,
          { $inc: { currentBalance: -newExpense.total }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (result) {
          balanceUpdated = true;
          console.log(`✅ Balance deducted from account ID ${paidThrough}: -₹${newExpense.total} → new balance: ₹${result.currentBalance}`);
        }
      }
      if (!balanceUpdated) {
        const result = await PaymentAccount.findOneAndUpdate(
          { accountName: paidThrough },
          { $inc: { currentBalance: -newExpense.total }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (result) {
          balanceUpdated = true;
          console.log(`✅ Balance deducted from account name "${paidThrough}": -₹${newExpense.total} → new balance: ₹${result.currentBalance}`);
        }
      }
      if (!balanceUpdated) {
        console.warn(`⚠️ BALANCE WARNING: Could not find account "${paidThrough}" to deduct ₹${newExpense.total}.`);
      }
    } catch (balanceErr) {
      console.error(`⚠️ BALANCE ERROR:`, balanceErr.message);
    }
    // ── END BALANCE UPDATE ──────────────────────────────────────────────────

    // ── COA POSTING ─────────────────────────────────────────────────────────
    try {
      const currentOrgId = req.user?.orgId || null;
      const [expAccId, paidAccId] = await Promise.all([
        getExpenseAccountId(expenseAccount, currentOrgId),
        getPaidThroughAccountId(paidThrough, currentOrgId)
      ]);

      const txnDate = new Date(date);
      const description = `Expense - ${expenseAccount}${vendor ? ' | ' + vendor : ''}`;

      if (expAccId) {
        await postTransactionToCOA({
          accountId: expAccId,
          orgId: currentOrgId,
          date: txnDate,
          description,
          referenceType: 'Expense',
          referenceId: newExpense._id,
          referenceNumber: newExpense._id.toString(),
          debit: newExpense.total,
          credit: 0
        });
        console.log(`✅ COA: Debited expense account "${expenseAccount}" ₹${newExpense.total}`);
      } else {
        console.warn(`⚠️ COA: Could not find expense account "${expenseAccount}"`);
      }

      if (paidAccId) {
        await postTransactionToCOA({
          accountId: paidAccId,
          orgId: currentOrgId,
          date: txnDate,
          description,
          referenceType: 'Expense',
          referenceId: newExpense._id,
          referenceNumber: newExpense._id.toString(),
          debit: 0,
          credit: newExpense.total
        });
        console.log(`✅ COA: Credited paid-through account "${paidThrough}" ₹${newExpense.total}`);
      } else {
        console.warn(`⚠️ COA: Could not find paid-through account "${paidThrough}"`);
      }
    } catch (coaErr) {
      console.error('⚠️ COA posting error (expense create):', coaErr.message);
    }
    // ── END COA POSTING ─────────────────────────────────────────────────────

    res.status(201).json({
      success: true,
      message: 'Expense created successfully',
      data: newExpense
    });
  } catch (error) {
    console.error('❌ Error creating expense:', error);
    if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
    handleError(res, 500, 'Error creating expense', error);
  }
});

// ============================================================================
// PUT UPDATE EXPENSE

// ============================================================================
// PUT UPDATE EXPENSE
// ============================================================================

router.put('/:id', upload.single('receipt'), async (req, res) => {
  try {
    console.log(`📝 Updating expense ID: ${req.params.id}`);
    
    const expense = await Expense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!expense) {
      if (req.file && fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(404).json({
        success: false,
        message: 'Expense not found'
      });
    }

    // ✅ Capture old values BEFORE any changes
    const oldTotal       = expense.total;
    const oldPaidThrough = expense.paidThrough;

    const {
      date,
      expenseAccount,
      amount,
      tax,
      paidThrough,
      vendor,
      invoiceNumber,
      customerName,
      isBillable,
      project,
      markupPercentage,
      reportingTags,
      notes,
      isItemized,
      itemizedExpenses,
      deleteReceipt
    } = req.body;

    // Validation
    if (date) {
      const dateRegex = /^\d{4}-\d{2}-\d{2}$/;
      if (!dateRegex.test(date)) {
        if (req.file && fs.existsSync(req.file.path)) {
          fs.unlinkSync(req.file.path);
        }
        return res.status(400).json({
          success: false,
          message: 'Invalid date format. Use YYYY-MM-DD'
        });
      }
    }

    if (expenseAccount && !isValidExpenseAccount(expenseAccount)) {
      if (req.file && fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(400).json({
        success: false,
        message: 'Invalid expense account'
      });
    }

    // Parse data
    let parsedItemizedExpenses = expense.itemizedExpenses;
    if (itemizedExpenses) {
      try {
        parsedItemizedExpenses = typeof itemizedExpenses === 'string'
          ? JSON.parse(itemizedExpenses)
          : itemizedExpenses;
      } catch (e) {
        if (req.file && fs.existsSync(req.file.path)) {
          fs.unlinkSync(req.file.path);
        }
        return res.status(400).json({
          success: false,
          message: 'Invalid itemized expenses format'
        });
      }
    }

    let parsedReportingTags = expense.reportingTags;
    if (reportingTags) {
      try {
        parsedReportingTags = typeof reportingTags === 'string'
          ? JSON.parse(reportingTags)
          : reportingTags;
      } catch (e) {
        parsedReportingTags = expense.reportingTags;
      }
    }

    // Calculate new totals
    const subtotal = (isItemized === 'true' || isItemized === true)
      ? parsedItemizedExpenses.reduce((sum, item) => sum + parseFloat(item.amount || 0), 0)
      : parseFloat(amount !== undefined ? amount : expense.amount);
    
    const taxAmount = parseFloat(tax !== undefined ? tax : expense.tax || 0);
    const total     = subtotal + taxAmount;
    
    const billableAmount = (isBillable === 'true' || isBillable === true) && markupPercentage
      ? total * (1 + parseFloat(markupPercentage) / 100)
      : total;

    // Handle receipt file
    let receiptFile = expense.receiptFile;
    
    if (deleteReceipt === 'true' || req.file) {
      if (expense.receiptFile && fs.existsSync(expense.receiptFile.path)) {
        try {
          fs.unlinkSync(expense.receiptFile.path);
          console.log('🗑️ Deleted old receipt');
        } catch (e) {
          console.error('Error deleting old receipt:', e);
        }
      }
      receiptFile = null;
    }
    
    if (req.file) {
      receiptFile = {
        filename:     req.file.filename,
        originalName: req.file.originalname,
        path:         req.file.path,
        size:         req.file.size,
        mimetype:     req.file.mimetype
      };
    }

    // Update expense fields
    expense.date             = date || expense.date;
    expense.expenseAccount   = expenseAccount || expense.expenseAccount;
    expense.amount           = subtotal;
    expense.tax              = taxAmount;
    expense.total            = total;
    expense.paidThrough      = paidThrough || expense.paidThrough;
    expense.vendor           = vendor !== undefined ? vendor : expense.vendor;
    expense.invoiceNumber    = invoiceNumber !== undefined ? invoiceNumber : expense.invoiceNumber;
    expense.customerName     = customerName !== undefined ? customerName : expense.customerName;
    expense.isBillable       = isBillable !== undefined ? (isBillable === 'true' || isBillable === true) : expense.isBillable;
    expense.project          = project !== undefined ? project : expense.project;
    expense.markupPercentage = markupPercentage !== undefined ? parseFloat(markupPercentage) : expense.markupPercentage;
    expense.billableAmount   = billableAmount;
    expense.reportingTags    = parsedReportingTags;
    expense.notes            = notes !== undefined ? notes : expense.notes;
    expense.isItemized       = isItemized !== undefined ? (isItemized === 'true' || isItemized === true) : expense.isItemized;
    expense.itemizedExpenses = parsedItemizedExpenses;
    expense.receiptFile      = receiptFile;

    await expense.save();
    console.log('✅ Expense updated in MongoDB');

    // ── BALANCE ADJUSTMENT ───────────────────────────────────────────────────
    try {
      const newPaidThrough     = paidThrough || oldPaidThrough;
      const paidThroughChanged = paidThrough && paidThrough !== oldPaidThrough;

      if (paidThroughChanged) {
        // ✅ Account changed — restore balance to OLD account
        let oldRestored = false;

        if (mongoose.Types.ObjectId.isValid(oldPaidThrough)) {
          const r = await PaymentAccount.findByIdAndUpdate(
            oldPaidThrough,
            { $inc: { currentBalance: oldTotal }, $set: { updatedAt: new Date() } },
            { new: true }
          );
          if (r) {
            oldRestored = true;
            console.log(`✅ Restored ₹${oldTotal} to old account ID: ${oldPaidThrough} → balance: ₹${r.currentBalance}`);
          }
        }
        if (!oldRestored) {
          const r = await PaymentAccount.findOneAndUpdate(
            { accountName: oldPaidThrough },
            { $inc: { currentBalance: oldTotal }, $set: { updatedAt: new Date() } },
            { new: true }
          );
          if (r) console.log(`✅ Restored ₹${oldTotal} to old account name: ${oldPaidThrough} → balance: ₹${r.currentBalance}`);
        }

        // ✅ Deduct full new total from NEW account
        let newDeducted = false;

        if (mongoose.Types.ObjectId.isValid(newPaidThrough)) {
          const r = await PaymentAccount.findByIdAndUpdate(
            newPaidThrough,
            { $inc: { currentBalance: -total }, $set: { updatedAt: new Date() } },
            { new: true }
          );
          if (r) {
            newDeducted = true;
            console.log(`✅ Deducted ₹${total} from new account ID: ${newPaidThrough} → balance: ₹${r.currentBalance}`);
          }
        }
        if (!newDeducted) {
          const r = await PaymentAccount.findOneAndUpdate(
            { accountName: newPaidThrough },
            { $inc: { currentBalance: -total }, $set: { updatedAt: new Date() } },
            { new: true }
          );
          if (r) console.log(`✅ Deducted ₹${total} from new account name: ${newPaidThrough} → balance: ₹${r.currentBalance}`);
        }

      } else {
        // ✅ Same account — just adjust the difference
        const difference = oldTotal - total;

        if (difference !== 0) {
          let adjusted = false;

          if (mongoose.Types.ObjectId.isValid(newPaidThrough)) {
            const r = await PaymentAccount.findByIdAndUpdate(
              newPaidThrough,
              { $inc: { currentBalance: difference }, $set: { updatedAt: new Date() } },
              { new: true }
            );
            if (r) {
              adjusted = true;
              console.log(`✅ Balance adjusted by ₹${difference} on account ID: ${newPaidThrough} → balance: ₹${r.currentBalance}`);
            }
          }
          if (!adjusted) {
            const r = await PaymentAccount.findOneAndUpdate(
              { accountName: newPaidThrough },
              { $inc: { currentBalance: difference }, $set: { updatedAt: new Date() } },
              { new: true }
            );
            if (r) console.log(`✅ Balance adjusted by ₹${difference} on account name: ${newPaidThrough} → balance: ₹${r.currentBalance}`);
          }
        } else {
          console.log('ℹ️ No balance change needed — amount unchanged');
        }
      }
    } catch (balanceErr) {
      console.error('⚠️ Balance adjustment error:', balanceErr.message);
    }
    // ── END BALANCE ADJUSTMENT ───────────────────────────────────────────────

    // ── COA ADJUSTMENT ON UPDATE ─────────────────────────────────────────────
    try {
      const currentOrgId   = req.user?.orgId || null;
      const newPaidThrough = paidThrough || oldPaidThrough;
      const paidThroughChanged = paidThrough && paidThrough !== oldPaidThrough;
      const txnDate        = new Date(date || expense.date);
      const description    = `UPDATED - Expense - ${expense.expenseAccount}${expense.vendor ? ' | ' + expense.vendor : ''}`;

      const [expAccId, newPaidAccId, oldPaidAccId] = await Promise.all([
        getExpenseAccountId(expense.expenseAccount, currentOrgId),
        getPaidThroughAccountId(newPaidThrough, currentOrgId),
        paidThroughChanged
          ? getPaidThroughAccountId(oldPaidThrough, currentOrgId)
          : Promise.resolve(null)
      ]);

      if (paidThroughChanged) {
        // Reverse old entries
        if (expAccId) await postTransactionToCOA({
          accountId: expAccId, orgId: currentOrgId, date: txnDate,
          description: `REVERSAL - ${description}`,
          referenceType: 'Expense', referenceId: expense._id,
          referenceNumber: expense.expenseNumber || expense._id.toString(),
          debit: 0, credit: oldTotal
        });
        if (oldPaidAccId) await postTransactionToCOA({
          accountId: oldPaidAccId, orgId: currentOrgId, date: txnDate,
          description: `REVERSAL - ${description}`,
          referenceType: 'Expense', referenceId: expense._id,
          referenceNumber: expense.expenseNumber || expense._id.toString(),
          debit: oldTotal, credit: 0
        });

        // Post new entries
        if (expAccId) await postTransactionToCOA({
          accountId: expAccId, orgId: currentOrgId, date: txnDate,
          description, referenceType: 'Expense', referenceId: expense._id,
          referenceNumber: expense.expenseNumber || expense._id.toString(),
          debit: total, credit: 0
        });
        if (newPaidAccId) await postTransactionToCOA({
          accountId: newPaidAccId, orgId: currentOrgId, date: txnDate,
          description, referenceType: 'Expense', referenceId: expense._id,
          referenceNumber: expense.expenseNumber || expense._id.toString(),
          debit: 0, credit: total
        });

      } else {
        // Same account — post difference only
        const difference = total - oldTotal;
        if (difference !== 0) {
          if (expAccId) await postTransactionToCOA({
            accountId: expAccId, orgId: currentOrgId, date: txnDate,
            description, referenceType: 'Expense', referenceId: expense._id,
            referenceNumber: expense.expenseNumber || expense._id.toString(),
            debit:  difference > 0 ? difference : 0,
            credit: difference < 0 ? Math.abs(difference) : 0
          });
          if (newPaidAccId) await postTransactionToCOA({
            accountId: newPaidAccId, orgId: currentOrgId, date: txnDate,
            description, referenceType: 'Expense', referenceId: expense._id,
            referenceNumber: expense.expenseNumber || expense._id.toString(),
            debit:  difference < 0 ? Math.abs(difference) : 0,
            credit: difference > 0 ? difference : 0
          });
        } else {
          console.log('ℹ️ No COA change needed — amount unchanged');
        }
      }
      console.log('✅ COA adjustment posted for expense update');
    } catch (coaErr) {
      console.error('⚠️ COA adjustment error (expense update):', coaErr.message);
    }
    // ── END COA ADJUSTMENT ───────────────────────────────────────────────────

    res.json({
      success: true,
      message: 'Expense updated successfully',
      data: expense
    });

  } catch (error) {
    console.error('❌ Error updating expense:', error);
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    handleError(res, 500, 'Error updating expense', error);
  }
});

// ============================================================================
// DELETE EXPENSE
// ============================================================================

router.delete('/:id', async (req, res) => {
  try {
    console.log(`🗑️ Deleting expense ID: ${req.params.id}`);

    const expense = await Expense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!expense) {
      return res.status(404).json({ success: false, message: 'Expense not found' });
    }

    if (expense.receiptFile && fs.existsSync(expense.receiptFile.path)) {
      try {
        fs.unlinkSync(expense.receiptFile.path);
        console.log('🗑️ Deleted receipt file');
      } catch (e) {
        console.error('Error deleting receipt file:', e);
      }
    }

    await expense.deleteOne();
    console.log('✅ Expense deleted from MongoDB');

    // ── BALANCE RESTORE ─────────────────────────────────────────────────────
    try {
      let balanceRestored = false;
      const paidThrough = expense.paidThrough;

      if (mongoose.Types.ObjectId.isValid(paidThrough)) {
        const result = await PaymentAccount.findByIdAndUpdate(
          paidThrough,
          { $inc: { currentBalance: expense.total }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (result) {
          balanceRestored = true;
          console.log(`✅ Balance restored to account ID ${paidThrough}: +₹${expense.total}`);
        }
      }
      if (!balanceRestored) {
        const result = await PaymentAccount.findOneAndUpdate(
          { accountName: paidThrough },
          { $inc: { currentBalance: expense.total }, $set: { updatedAt: new Date() } },
          { new: true }
        );
        if (result) {
          balanceRestored = true;
          console.log(`✅ Balance restored to account name "${paidThrough}": +₹${expense.total}`);
        }
      }
      if (!balanceRestored) {
        console.warn(`⚠️ BALANCE WARNING: Could not find account "${paidThrough}" to restore ₹${expense.total}.`);
      }
    } catch (balanceErr) {
      console.error(`⚠️ BALANCE ERROR:`, balanceErr.message);
    }
    // ── END BALANCE RESTORE ─────────────────────────────────────────────────

    // ── COA REVERSAL ────────────────────────────────────────────────────────
    try {
      const currentOrgId = req.user?.orgId || null;
      const [expAccId, paidAccId] = await Promise.all([
        getExpenseAccountId(expense.expenseAccount, currentOrgId),
        getPaidThroughAccountId(expense.paidThrough, currentOrgId)
      ]);

      const txnDate = new Date();
      const description = `REVERSAL - Expense ${expense._id} - ${expense.expenseAccount}`;

      if (expAccId) {
        await postTransactionToCOA({
          accountId: expAccId,
          orgId: currentOrgId,
          date: txnDate,
          description,
          referenceType: 'Expense',
          referenceId: expense._id,
          referenceNumber: expense._id.toString(),
          debit: 0,
          credit: expense.total
        });
        console.log(`✅ COA REVERSAL: Credited expense account "${expense.expenseAccount}" ₹${expense.total}`);
      }

      if (paidAccId) {
        await postTransactionToCOA({
          accountId: paidAccId,
          orgId: currentOrgId,
          date: txnDate,
          description,
          referenceType: 'Expense',
          referenceId: expense._id,
          referenceNumber: expense._id.toString(),
          debit: expense.total,
          credit: 0
        });
        console.log(`✅ COA REVERSAL: Debited paid-through account "${expense.paidThrough}" ₹${expense.total}`);
      }
    } catch (coaErr) {
      console.error('⚠️ COA reversal error (expense delete):', coaErr.message);
    }
    // ── END COA REVERSAL ────────────────────────────────────────────────────

    res.json({ success: true, message: 'Expense deleted successfully' });
  } catch (error) {
    console.error('❌ Error deleting expense:', error);
    handleError(res, 500, 'Error deleting expense', error);
  }
});

// ============================================================================
// GET EXPENSE STATISTICS
// ============================================================================

router.get('/stats/summary', async (req, res) => {
  try {
    console.log('📊 Fetching expense statistics from MongoDB...');
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const expenses = await Expense.find(orgFilter);
    
    const totalExpenses = expenses.reduce((sum, exp) => sum + exp.total, 0);
    const totalBillable = expenses
      .filter(exp => exp.isBillable)
      .reduce((sum, exp) => sum + exp.billableAmount, 0);
    
    const expensesByAccount = expenses.reduce((acc, exp) => {
      if (!acc[exp.expenseAccount]) {
        acc[exp.expenseAccount] = 0;
      }
      acc[exp.expenseAccount] += exp.total;
      return acc;
    }, {});

    const expensesByVendor = expenses.reduce((acc, exp) => {
      if (exp.vendor) {
        if (!acc[exp.vendor]) {
          acc[exp.vendor] = 0;
        }
        acc[exp.vendor] += exp.total;
      }
      return acc;
    }, {});

    console.log('✅ Statistics fetched from MongoDB');

    res.json({
      success: true,
      data: {
        totalExpenses,
        totalBillable,
        expenseCount: expenses.length,
        expensesByAccount,
        expensesByVendor
      }
    });
  } catch (error) {
    console.error('❌ Error fetching statistics:', error);
    handleError(res, 500, 'Error fetching statistics', error);
  }
});

// ============================================================================
// POST BULK IMPORT
// ============================================================================

// ============================================================================
// GET IMPORT TEMPLATE
// ============================================================================

router.get('/import/template', async (req, res) => {
  try {
    const XLSX = require('xlsx');

    console.log('📥 Generating import template...');

    const templateData = [
      {
        'Date': '28/01/2026',
        'Expense Account': 'Fuel',
        'Amount': 1000.00,
        'Tax': 180.00,
        'Paid Through': 'Cash',
        'Vendor': 'Amazon India',
        'Invoice #': 'INV-001',
        'Customer Name': 'Acme Corp',
        'Billable': 'Yes',
        'Project': 'Website Redesign',
        'Markup %': 10,
        'Notes': 'SAMPLE ROW - DELETE BEFORE IMPORT'
      },
      {
        'Date': '27/01/2026',
        'Expense Account': 'Office Supplies',
        'Amount': 500.00,
        'Tax': 90.00,
        'Paid Through': 'Petty Cash',
        'Vendor': 'Local Store',
        'Invoice #': 'INV-002',
        'Customer Name': '',
        'Billable': 'No',
        'Project': '',
        'Markup %': 0,
        'Notes': 'SAMPLE ROW - DELETE BEFORE IMPORT'
      }
    ];

    const worksheet = XLSX.utils.json_to_sheet(templateData);
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, worksheet, 'Expenses');

    worksheet['!cols'] = [
      { wch: 12 }, { wch: 25 }, { wch: 12 }, { wch: 10 },
      { wch: 22 }, { wch: 20 }, { wch: 15 }, { wch: 20 },
      { wch: 10 }, { wch: 20 }, { wch: 10 }, { wch: 40 }
    ];

    const instructionsData = [
      { 'Field': 'Date', 'Required': 'YES', 'Format': 'DD/MM/YYYY', 'Example': '28/01/2026', 'Notes': 'Date of expense' },
      { 'Field': 'Expense Account', 'Required': 'YES', 'Format': 'Text', 'Example': 'Fuel', 'Notes': 'Must be: Fuel, Office Supplies, Travel & Conveyance, Advertising & Marketing, Meals & Entertainment, Utilities, Rent, Professional Fees, Insurance, or Other Expenses' },
      { 'Field': 'Amount', 'Required': 'YES', 'Format': 'Number', 'Example': '1000.00', 'Notes': 'Expense amount (without tax)' },
      { 'Field': 'Tax', 'Required': 'NO', 'Format': 'Number', 'Example': '180.00', 'Notes': 'Tax amount' },
      { 'Field': 'Paid Through', 'Required': 'YES', 'Format': 'Text', 'Example': 'Cash', 'Notes': 'Payment method' },
      { 'Field': 'Vendor', 'Required': 'NO', 'Format': 'Text', 'Example': 'Amazon India', 'Notes': 'Vendor name' },
      { 'Field': 'Invoice #', 'Required': 'NO', 'Format': 'Text', 'Example': 'INV-001', 'Notes': 'Invoice number' },
      { 'Field': 'Customer Name', 'Required': 'NO', 'Format': 'Text', 'Example': 'Acme Corp', 'Notes': 'Customer (if billable)' },
      { 'Field': 'Billable', 'Required': 'NO', 'Format': 'Yes/No', 'Example': 'Yes', 'Notes': 'Is billable?' },
      { 'Field': 'Project', 'Required': 'NO', 'Format': 'Text', 'Example': 'Website', 'Notes': 'Project name' },
      { 'Field': 'Markup %', 'Required': 'NO', 'Format': 'Number', 'Example': '10', 'Notes': 'Markup %' },
      { 'Field': 'Notes', 'Required': 'NO', 'Format': 'Text', 'Example': 'Details', 'Notes': 'Additional notes' }
    ];

    const instructionsSheet = XLSX.utils.json_to_sheet(instructionsData);
    instructionsSheet['!cols'] = [{ wch: 20 }, { wch: 12 }, { wch: 15 }, { wch: 25 }, { wch: 50 }];
    XLSX.utils.book_append_sheet(workbook, instructionsSheet, 'Instructions');

    const buffer = XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' });

    res.setHeader('Content-Disposition', 'attachment; filename=expenses_import_template.xlsx');
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Length', buffer.length);

    res.send(buffer);

    console.log('✅ Template sent');
  } catch (error) {
    console.error('❌ Error generating template:', error);
    handleError(res, 500, 'Error generating template', error);
  }
});

// ============================================================================
// TESTING ENDPOINTS
// ============================================================================

router.get('/test', (req, res) => {
  res.json({
    success: true,
    message: 'Expenses API is working with MongoDB!',
    timestamp: new Date().toISOString(),
    database: 'MongoDB',
    collection: 'expenses'
  });
});

router.get('/health', async (req, res) => {
  try {
    const count = await Expense.countDocuments();
    res.json({
      success: true,
      status: 'healthy',
      expenses_count: count,
      database: 'MongoDB',
      collection: 'expenses',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      status: 'unhealthy',
      error: error.message
    });
  }
});

// ============================================================================
// GET SINGLE EXPENSE BY ID  ← must be AFTER all named routes
// ============================================================================

// ============================================================================
// POST /:id/proof  — upload or replace proof file
// ============================================================================

router.post('/:id/proof', proofUpload.single('proof'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No proof file uploaded' });
    }

    console.log(`📎 Uploading proof for expense: ${req.params.id}`);

    const expense = await Expense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!expense) {
      if (fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
      return res.status(404).json({ success: false, message: 'Expense not found' });
    }

    // Delete old proof from disk if replacing
    if (expense.proofFile && expense.proofFile.path) {
      try {
        if (fs.existsSync(expense.proofFile.path)) {
          fs.unlinkSync(expense.proofFile.path);
          console.log('🗑️  Deleted old proof file:', expense.proofFile.originalName);
        }
      } catch (e) {
        console.error('⚠️  Could not delete old proof file:', e.message);
      }
    }

    expense.proofFile = {
      filename:     req.file.filename,
      originalName: req.file.originalname,
      path:         req.file.path,
      size:         req.file.size,
      mimetype:     req.file.mimetype,
      uploadedAt:   new Date(),
    };

    await expense.save();
    console.log('✅ Proof uploaded:', req.file.originalname);

    res.json({
      success: true,
      message: 'Proof uploaded successfully',
      data: {
        filename:     expense.proofFile.filename,
        originalName: expense.proofFile.originalName,
        size:         expense.proofFile.size,
        mimetype:     expense.proofFile.mimetype,
        uploadedAt:   expense.proofFile.uploadedAt,
      },
    });
  } catch (error) {
    console.error('❌ Error uploading proof:', error);
    if (req.file && fs.existsSync(req.file.path)) fs.unlinkSync(req.file.path);
    handleError(res, 500, 'Error uploading proof', error);
  }
});

// ============================================================================
// GET /:id/proof  — download / view proof file
// ============================================================================

router.get('/:id/proof', async (req, res) => {
  try {
    const expense = await Expense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!expense)         return res.status(404).json({ success: false, message: 'Expense not found' });
    if (!expense.proofFile) return res.status(404).json({ success: false, message: 'No proof attached' });
    if (!fs.existsSync(expense.proofFile.path))
      return res.status(404).json({ success: false, message: 'Proof file not found on server' });

    const isImage = /image\//i.test(expense.proofFile.mimetype);
    res.setHeader('Content-Type', expense.proofFile.mimetype);
    res.setHeader(
      'Content-Disposition',
      `${isImage ? 'inline' : 'attachment'}; filename="${expense.proofFile.originalName}"`,
    );
    res.sendFile(path.resolve(expense.proofFile.path));
  } catch (error) {
    handleError(res, 500, 'Error retrieving proof', error);
  }
});

// ============================================================================
// DELETE /:id/proof  — remove proof
// ============================================================================

router.delete('/:id/proof', async (req, res) => {
  try {
    const expense = await Expense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!expense)            return res.status(404).json({ success: false, message: 'Expense not found' });
    if (!expense.proofFile)  return res.status(404).json({ success: false, message: 'No proof to delete' });

    if (expense.proofFile.path && fs.existsSync(expense.proofFile.path)) {
      fs.unlinkSync(expense.proofFile.path);
      console.log('🗑️  Proof deleted:', expense.proofFile.originalName);
    }

    expense.proofFile = null;
    await expense.save();

    res.json({ success: true, message: 'Proof deleted successfully' });
  } catch (error) {
    handleError(res, 500, 'Error deleting proof', error);
  }
});

// ============================================================================
// GET SINGLE EXPENSE BY ID  ← must be AFTER all named routes
// ============================================================================

router.get('/:id', async (req, res) => {
  try {
    console.log(`📥 Fetching expense ID: ${req.params.id}`);

    const expense = await Expense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!expense) {
      return res.status(404).json({
        success: false,
        message: 'Expense not found'
      });
    }

    console.log(`✅ Fetched expense: ${expense.expenseAccount}`);

    res.json({
      success: true,
      data: expense
    });
  } catch (error) {
    console.error('❌ Error fetching expense:', error);
    handleError(res, 500, 'Error fetching expense', error);
  }
});

// ============================================================================
// GET RECEIPT FILE
// ============================================================================

router.get('/:id/receipt', async (req, res) => {
  try {
    const expense = await Expense.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!expense) {
      return res.status(404).json({
        success: false,
        message: 'Expense not found'
      });
    }

    if (!expense.receiptFile) {
      return res.status(404).json({
        success: false,
        message: 'No receipt attached to this expense'
      });
    }

    if (!fs.existsSync(expense.receiptFile.path)) {
      return res.status(404).json({
        success: false,
        message: 'Receipt file not found on server'
      });
    }

    console.log('📥 Downloading receipt:', expense.receiptFile.originalName);

    res.download(expense.receiptFile.path, expense.receiptFile.originalName);
  } catch (error) {
    console.error('❌ Error downloading receipt:', error);
    handleError(res, 500, 'Error downloading receipt', error);
  }
});

// ============================================================================
// POST BULK IMPORT
// ============================================================================

router.post('/import/bulk', importUpload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file uploaded'
      });
    }

    console.log('📊 Starting bulk import to MongoDB...');
    console.log('📄 File:', req.file.originalname);

    const XLSX = require('xlsx');
    
    let workbook;
    try {
      workbook = XLSX.readFile(req.file.path);
    } catch (e) {
      console.error('❌ Error reading file:', e);
      if (fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(400).json({
        success: false,
        message: 'Invalid file format',
        error: e.message
      });
    }
    
    const sheetName = workbook.SheetNames[0];
    const worksheet = workbook.Sheets[sheetName];
    
    const data = XLSX.utils.sheet_to_json(worksheet, { 
      defval: '',
      raw: false
    });

    console.log(`📊 Processing ${data.length} rows (excluding header)`);

    if (data.length === 0) {
      if (fs.existsSync(req.file.path)) {
        fs.unlinkSync(req.file.path);
      }
      return res.status(400).json({
        success: false,
        message: 'File is empty or contains only headers'
      });
    }

    const imported = [];
    const errors = [];

    for (let i = 0; i < data.length; i++) {
      const row = data[i];
      const rowNumber = i + 2;
      
      try {
        const dateField = row['Date* (DD/MM/YYYY)'] || row['Date'] || row['date'];
        const expenseAccountField = row['Expense Account*'] || row['Expense Account'] || row['expenseAccount'];
        const paidThroughField = row['Paid Through*'] || row['Paid Through'] || row['paidThrough'];
        const amountField = row['Amount*'] || row['Amount'] || row['amount'];
        const taxField = row['Tax'] || row['tax'];
        const vendorField = row['Vendor'] || row['vendor'];
        const invoiceField = row['Invoice Number'] || row['Invoice #'] || row['invoiceNumber'];
        const customerField = row['Customer Name'] || row['customerName'];
        const billableField = row['Billable (Yes/No)'] || row['Billable'] || row['billable'];
        const projectField = row['Project'] || row['project'];
        const notesField = row['Notes'] || row['notes'];

        const firstCell = String(dateField || '').toLowerCase();
        if (firstCell.includes('instruction') || 
            firstCell.includes('sample') || 
            firstCell.includes('delete') ||
            firstCell.includes('dd/mm/yyyy') ||
            firstCell === 'date' ||
            firstCell === '') {
          console.log(`⏭️  Skipping row ${rowNumber}: ${firstCell}`);
          continue;
        }

        const missingFields = [];
        if (!dateField || String(dateField).trim() === '') missingFields.push('Date');
        if (!expenseAccountField || String(expenseAccountField).trim() === '') missingFields.push('Expense Account');
        if (!paidThroughField || String(paidThroughField).trim() === '') missingFields.push('Paid Through');
        if (!amountField || String(amountField).trim() === '') missingFields.push('Amount');
        
        if (missingFields.length > 0) {
          console.log(`❌ Row ${rowNumber}: Missing fields: ${missingFields.join(', ')}`);
          errors.push({ row: rowNumber, error: `Missing required fields: ${missingFields.join(', ')}` });
          continue;
        }

        const parsedDate = parseDate(dateField);
        if (!parsedDate || isNaN(parsedDate.getTime())) {
          errors.push({ row: rowNumber, error: `Invalid date format: "${dateField}"` });
          continue;
        }

        const dateStr = parsedDate.toISOString().split('T')[0];
        
        const amount = parseFloat(String(amountField).replace(/[^0-9.-]/g, '') || 0);
        const tax = parseFloat(String(taxField || 0).replace(/[^0-9.-]/g, '') || 0);
        
        if (isNaN(amount) || amount <= 0) {
          errors.push({ row: rowNumber, error: `Invalid amount: "${amountField}"` });
          continue;
        }
        
        const total = amount + tax;
        const expenseAccountValue = String(expenseAccountField).trim();
        
        if (!isValidExpenseAccount(expenseAccountValue)) {
          errors.push({ row: rowNumber, error: `Invalid expense account: "${expenseAccountValue}"` });
          continue;
        }

        const isBillable = ['yes', 'true', '1', 'y'].includes(
          String(billableField || '').toLowerCase().trim()
        );

        const newExpense = new Expense({
          date: dateStr,
          expenseAccount: expenseAccountValue,
          amount: amount,
          tax: tax,
          total: total,
          paidThrough: String(paidThroughField).trim(),
          vendor: vendorField ? String(vendorField).trim() : null,
          invoiceNumber: invoiceField ? String(invoiceField).trim() : null,
          customerName: customerField ? String(customerField).trim() : null,
          isBillable: isBillable,
          project: projectField ? String(projectField).trim() : null,
          markupPercentage: 0,
          billableAmount: total,
          reportingTags: [],
          notes: notesField ? String(notesField).trim() : null,
          isItemized: false,
          itemizedExpenses: [],
          orgId: req.user?.orgId || null,
          expenseNumber: await generateExpenseNumber(req.user?.orgId || null),
        });

        await newExpense.save();
        imported.push(newExpense);

// ✅ COA for bulk imported expense
try {
  const currentOrgId = req.user?.orgId || null;
  const [expAccId, paidAccId] = await Promise.all([
    getExpenseAccountId(expenseAccountValue, currentOrgId),
    getPaidThroughAccountId(String(paidThroughField).trim(), currentOrgId)
  ]);

  const txnDate = new Date(dateStr);
  const desc = `Bulk Import - ${expenseAccountValue}`;

  if (expAccId) await postTransactionToCOA({
    accountId:       expAccId,
    orgId:           currentOrgId,
    date:            txnDate,
    description:     desc,
    referenceType:   'Expense',
    referenceId:     newExpense._id,
    referenceNumber: newExpense._id.toString(),
    debit:           total,
    credit:          0,
  });

  if (paidAccId) await postTransactionToCOA({
    accountId:       paidAccId,
    orgId:           currentOrgId,
    date:            txnDate,
    description:     desc,
    referenceType:   'Expense',
    referenceId:     newExpense._id,
    referenceNumber: newExpense._id.toString(),
    debit:           0,
    credit:          total,
  });
} catch (coaErr) {
  console.error(`⚠️ Row ${rowNumber}: COA post failed:`, coaErr.message);
}

        // ── BALANCE DEDUCTION FOR BULK IMPORT ──────────────────────────────
        try {
          const pt = String(paidThroughField).trim();
          let bulkBalanceUpdated = false;

          if (mongoose.Types.ObjectId.isValid(pt)) {
            const r = await PaymentAccount.findByIdAndUpdate(
              pt,
              { $inc: { currentBalance: -total }, $set: { updatedAt: new Date() } },
              { new: true }
            );
            if (r) {
              bulkBalanceUpdated = true;
              console.log(`✅ Row ${rowNumber}: Balance deducted from account ID "${pt}": -₹${total} → new balance: ₹${r.currentBalance}`);
            }
          }

          if (!bulkBalanceUpdated) {
            const r = await PaymentAccount.findOneAndUpdate(
              { accountName: pt },
              { $inc: { currentBalance: -total }, $set: { updatedAt: new Date() } },
              { new: true }
            );
            if (r) {
              bulkBalanceUpdated = true;
              console.log(`✅ Row ${rowNumber}: Balance deducted from account name "${pt}": -₹${total} → new balance: ₹${r.currentBalance}`);
            }
          }

          if (!bulkBalanceUpdated) {
            console.warn(`⚠️ Row ${rowNumber}: Could not find account "${pt}" to deduct ₹${total}. Expense saved but balance NOT updated.`);
          }
        } catch (balanceErr) {
          console.error(`⚠️ Row ${rowNumber}: Balance deduction failed:`, balanceErr.message);
        }
        // ── END BALANCE DEDUCTION ───────────────────────────────────────────

        console.log(`✅ Row ${rowNumber}: Imported - ${expenseAccountValue} - ₹${amount}`);

      } catch (error) {
        console.error(`❌ Row ${rowNumber} error:`, error.message);
        errors.push({ row: rowNumber, error: error.message });
      }
    }

    if (fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }

    console.log(`✅ Import complete: ${imported.length} imported, ${errors.length} errors`);

    res.json({
      success: true,
      message: `Successfully imported ${imported.length} expense(s)`,
      data: {
        imported: imported.length,
        errors: errors.length,
        errorDetails: errors
      }
    });

  } catch (error) {
    console.error('❌ Error importing expenses:', error);
    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    handleError(res, 500, 'Error importing expenses', error);
  }
});

module.exports = router;