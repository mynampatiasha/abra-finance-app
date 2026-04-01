// ============================================================================
// RECURRING BILL - COMPLETE BACKEND
// ============================================================================
// File: routes/recurring_bill.js
// Includes: Mongoose Model, Controller, Routes, Scheduler (cron)
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const cron = require('node-cron');

// ============================================================================
// MONGOOSE SCHEMA & MODEL
// ============================================================================

const recurringBillItemSchema = new mongoose.Schema({
  itemId: { type: String, default: null },
  itemDetails: { type: String, required: true, trim: true },
  quantity: { type: Number, required: true, min: 0 },
  rate: { type: Number, required: true, min: 0 },
  discount: { type: Number, default: 0, min: 0 },
  discountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
  amount: { type: Number, required: true, min: 0 },
}, { _id: false });

const recurringBillSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  profileName: {
    type: String,
    required: [true, 'Profile name is required'],
    trim: true,
    maxlength: [100, 'Profile name cannot exceed 100 characters'],
  },
  vendorId: {
    type: String,
    required: [true, 'Vendor ID is required'],
  },
  vendorName: {
    type: String,
    required: [true, 'Vendor name is required'],
    trim: true,
  },
  vendorEmail: {
    type: String,
    trim: true,
    default: '',
  },
  status: {
    type: String,
    enum: ['ACTIVE', 'PAUSED', 'STOPPED'],
    default: 'ACTIVE',
  },
  repeatEvery: {
    type: Number,
    required: [true, 'Repeat frequency is required'],
    min: [1, 'Repeat frequency must be at least 1'],
  },
  repeatUnit: {
    type: String,
    enum: ['days', 'weeks', 'months', 'years'],
    required: [true, 'Repeat unit is required'],
  },
  startDate: {
    type: Date,
    required: [true, 'Start date is required'],
  },
  endDate: {
    type: Date,
    default: null,
  },
  nextBillDate: {
    type: Date,
    required: true,
  },
  lastGeneratedDate: {
    type: Date,
    default: null,
  },
  totalBillsGenerated: {
    type: Number,
    default: 0,
  },
  billCreationMode: {
    type: String,
    enum: ['auto_save', 'save_as_draft'],
    default: 'save_as_draft',
  },
  items: {
    type: [recurringBillItemSchema],
    required: true,
    validate: {
      validator: (items) => items && items.length > 0,
      message: 'At least one item is required',
    },
  },
  subTotal: { type: Number, default: 0 },
  tdsRate: { type: Number, default: 0 },
  tdsAmount: { type: Number, default: 0 },
  tcsRate: { type: Number, default: 0 },
  tcsAmount: { type: Number, default: 0 },
  gstRate: { type: Number, default: 18 },
  gstAmount: { type: Number, default: 0 },
  totalAmount: { type: Number, default: 0 },
  paymentTerms: { type: String, default: 'Net 30' },
  notes: { type: String, default: '' },
  childBills: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Bill' }],
  organizationId: { type: String, default: '' },  createdBy: { type: String, default: '' },
}, {
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true },
});

// Index for performance
recurringBillSchema.index({ status: 1, nextBillDate: 1 });
recurringBillSchema.index({ vendorId: 1 });
recurringBillSchema.index({ profileName: 'text', vendorName: 'text' });

const RecurringBill = mongoose.models.RecurringBill || mongoose.model('RecurringBill', recurringBillSchema);

// ============================================================================
// BILL SCHEMA (child bills generated from recurring profile)
// ============================================================================

// Import the Bill model from bill.js (reuse existing model to avoid conflicts)
let Bill;
try {
  Bill = mongoose.model('Bill');
} catch (error) {
  console.error('⚠️ Bill model not found. Make sure bill.js is loaded before recurring_bill.js');
  throw new Error('Bill model must be loaded first');
}

// ============================================================================
// HELPERS
// ============================================================================

// Calculate next bill date
function calculateNextBillDate(currentDate, repeatEvery, repeatUnit) {
  const next = new Date(currentDate);
  switch (repeatUnit) {
    case 'days':
      next.setDate(next.getDate() + repeatEvery);
      break;
    case 'weeks':
      next.setDate(next.getDate() + repeatEvery * 7);
      break;
    case 'months':
      next.setMonth(next.getMonth() + repeatEvery);
      break;
    case 'years':
      next.setFullYear(next.getFullYear() + repeatEvery);
      break;
    default:
      next.setMonth(next.getMonth() + repeatEvery);
  }
  return next;
}

// Calculate due date from payment terms
function calculateDueDate(billDate, paymentTerms) {
  const due = new Date(billDate);
  switch (paymentTerms) {
    case 'Due on Receipt':
      return due;
    case 'Net 15':
      due.setDate(due.getDate() + 15);
      return due;
    case 'Net 30':
      due.setDate(due.getDate() + 30);
      return due;
    case 'Net 45':
      due.setDate(due.getDate() + 45);
      return due;
    case 'Net 60':
      due.setDate(due.getDate() + 60);
      return due;
    default:
      due.setDate(due.getDate() + 30);
      return due;
  }
}

// Generate a bill from a recurring profile
async function generateBillFromProfile(profile, userId = 'SYSTEM') {
  const billDate = new Date();
  const dueDate = calculateDueDate(billDate, profile.paymentTerms || 'Net 30');

  // Generate bill number
  const orgId = profile.orgId || null;
  const { generateNumber } = require('../utils/numberGenerator');
  const billNumber = await generateNumber(Bill, 'billNumber', 'BILL', orgId);

  // Ensure vendorId is ObjectId (handle both string and ObjectId)
  let vendorObjectId;
  try {
    vendorObjectId = mongoose.Types.ObjectId.isValid(profile.vendorId) 
      ? (typeof profile.vendorId === 'string' ? new mongoose.Types.ObjectId(profile.vendorId) : profile.vendorId)
      : null;
  } catch (err) {
    console.error('⚠️ Invalid vendorId, setting to null:', profile.vendorId);
    vendorObjectId = null;
  }

  const bill = new Bill({
    billNumber,
    recurringProfileId: profile._id,
    vendorId: vendorObjectId,
    vendorName: profile.vendorName,
    vendorEmail: profile.vendorEmail || '',
    billDate,
    dueDate,
    paymentTerms: profile.paymentTerms || 'Net 30',
    status: 'OPEN',
    items: profile.items,
    subTotal: profile.subTotal,
    tdsRate: profile.tdsRate || 0,
    tdsAmount: profile.tdsAmount || 0,
    tcsRate: profile.tcsRate || 0,
    tcsAmount: profile.tcsAmount || 0,
    gstRate: profile.gstRate || 18,
    cgst: profile.cgst || 0,
    sgst: profile.sgst || 0,
    igst: profile.igst || 0,
    totalAmount: profile.totalAmount,
    amountPaid: 0,
    amountDue: profile.totalAmount,
    notes: profile.notes || '',
    isRecurring: true,
    createdBy: userId, // Required field
  });

 await bill.save();

// ✅ COA Posting — same as bill.js POST route
try {
  const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

  async function getAccId(name, orgId = null) {
    const acc = await ChartOfAccount.findOne({
      accountName: name,
      isSystemAccount: true,
      ...(orgId ? { orgId } : {}),
    }).select('_id').lean();
    return acc?._id || null;
  }

  const orgId = profile.orgId || null;
  const [expenseId, apId] = await Promise.all([
    getAccId('Cost of Goods Sold', orgId),
    getAccId('Accounts Payable', orgId),
  ]);
  const txnDate = new Date(bill.billDate);

  if (expenseId) await postTransactionToCOA({
    accountId: expenseId, orgId: orgId, date: txnDate,
    description: `Recurring Bill ${bill.billNumber} - ${profile.vendorName}`,
    referenceType: 'Bill', referenceId: bill._id,
    referenceNumber: bill.billNumber,
    debit: bill.totalAmount, credit: 0,
  });

  if (apId) await postTransactionToCOA({
    accountId: apId, orgId: orgId, date: txnDate,
    description: `Recurring Bill ${bill.billNumber} - ${profile.vendorName}`,
    referenceType: 'Bill', referenceId: bill._id,
    referenceNumber: bill.billNumber,
    debit: 0, credit: bill.totalAmount,
  });

  console.log(`✅ COA posted for recurring bill: ${bill.billNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA error (recurring bill):', coaErr.message);
}


  // Update recurring profile
  const nextDate = calculateNextBillDate(
    profile.nextBillDate,
    profile.repeatEvery,
    profile.repeatUnit
  );

  await RecurringBill.findByIdAndUpdate(profile._id, {
    $push: { childBills: bill._id },
    $inc: { totalBillsGenerated: 1 },
    lastGeneratedDate: new Date(),
    nextBillDate: nextDate,
  });

  return bill;
}

// ============================================================================
// CRON SCHEDULER - Runs every day at 8:00 AM
// ============================================================================

cron.schedule('0 8 * * *', async () => {
  console.log('🔄 Running recurring bills scheduler...');
  try {
    const today = new Date();
    today.setHours(23, 59, 59, 999);

    // Find all active profiles due today or overdue
    const dueProfiles = await RecurringBill.find({
      status: 'ACTIVE',
      nextBillDate: { $lte: today },
      $or: [
        { endDate: null },
        { endDate: { $gte: new Date() } },
      ],
    });

    console.log(`📋 Found ${dueProfiles.length} profiles due for bill generation`);

    let generated = 0;
    let errors = 0;

    for (const profile of dueProfiles) {
      try {
        await generateBillFromProfile(profile);
        generated++;
        console.log(`✅ Generated bill for profile: ${profile.profileName}`);
      } catch (err) {
        errors++;
        console.error(`❌ Failed to generate bill for ${profile.profileName}:`, err.message);
      }
    }

    // Also update OVERDUE status for unpaid bills
    await Bill.updateMany(
      {
        status: 'OPEN',
        dueDate: { $lt: new Date() },
      },
      { $set: { status: 'OVERDUE' } }
    );

    console.log(`✅ Scheduler done. Generated: ${generated}, Errors: ${errors}`);
  } catch (err) {
    console.error('❌ Scheduler error:', err);
  }
});

// ============================================================================
// MIDDLEWARE - Auth (use your existing auth middleware)
// ============================================================================

// Replace with your actual auth middleware import
const authMiddleware = (req, res, next) => {
  // Your JWT auth logic here
  // e.g.: const token = req.headers.authorization?.split(' ')[1];
  next(); // Remove this and use real auth in production
};

// ============================================================================
// CONTROLLERS
// ============================================================================

// GET /api/recurring-bills/stats
const getStats = async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const [totalProfiles, activeProfiles, pausedProfiles, stoppedProfiles] = await Promise.all([
      RecurringBill.countDocuments(orgFilter),
      RecurringBill.countDocuments({ ...orgFilter, status: 'ACTIVE' }),
      RecurringBill.countDocuments({ ...orgFilter, status: 'PAUSED' }),
      RecurringBill.countDocuments({ ...orgFilter, status: 'STOPPED' }),
    ]);

    const totalBillsResult = await RecurringBill.aggregate([
      { $match: orgFilter },
      { $group: { _id: null, total: { $sum: '$totalBillsGenerated' } } },
    ]);

    res.json({
      success: true,
      data: {
        totalProfiles,
        activeProfiles,
        pausedProfiles,
        stoppedProfiles,
        totalBillsGenerated: totalBillsResult[0]?.total || 0,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// GET /api/recurring-bills
const getAllRecurringBills = async (req, res) => {
  try {
    const {
      status,
      page = 1,
      limit = 20,
      fromDate,
      toDate,
      search,
    } = req.query;

    const filter = {};
    if (req.user?.orgId) filter.orgId = req.user.orgId;

    if (status && status !== 'All') filter.status = status;

    if (fromDate || toDate) {
      filter.startDate = {};
      if (fromDate) filter.startDate.$gte = new Date(fromDate);
      if (toDate) filter.startDate.$lte = new Date(toDate);
    }

    if (search) {
      filter.$or = [
        { profileName: { $regex: search, $options: 'i' } },
        { vendorName: { $regex: search, $options: 'i' } },
      ];
    }

    const total = await RecurringBill.countDocuments(filter);
    const pages = Math.ceil(total / Number(limit));

    const recurringBills = await RecurringBill.find(filter)
      .sort({ createdAt: -1 })
      .skip((Number(page) - 1) * Number(limit))
      .limit(Number(limit))
      .lean();

    res.json({
      success: true,
      data: {
        recurringBills,
        pagination: {
          total,
          pages,
          page: Number(page),
          limit: Number(limit),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// GET /api/recurring-bills/:id
const getRecurringBillById = async (req, res) => {
  try {
    const bill = await RecurringBill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!bill) {
      return res.status(404).json({ success: false, message: 'Recurring bill profile not found' });
    }
    res.json({ success: true, data: bill });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// POST /api/recurring-bills
const createRecurringBill = async (req, res) => {
  try {
    const {
      profileName, vendorId, vendorName, vendorEmail,
      repeatEvery, repeatUnit, startDate, endDate,
      billCreationMode, items, paymentTerms, notes,
      tdsRate = 0, tcsRate = 0, gstRate = 18,
    } = req.body;

    // Validate required fields
    if (!profileName) return res.status(400).json({ success: false, message: 'Profile name is required' });
    if (!vendorId) return res.status(400).json({ success: false, message: 'Vendor is required' });
    if (!items || items.length === 0) return res.status(400).json({ success: false, message: 'At least one item is required' });

    // Calculate totals
    let subTotal = 0;
    const processedItems = items.map((item) => {
      let amount = item.quantity * item.rate;
      if (item.discount > 0) {
        if (item.discountType === 'percentage') {
          amount -= amount * (item.discount / 100);
        } else {
          amount -= item.discount;
        }
      }
      item.amount = Math.max(0, amount);
      subTotal += item.amount;
      return item;
    });

    const tdsAmount = (subTotal * tdsRate) / 100;
    const tcsAmount = (subTotal * tcsRate) / 100;
    const gstAmount = ((subTotal - tdsAmount + tcsAmount) * gstRate) / 100;
    const totalAmount = subTotal - tdsAmount + tcsAmount + gstAmount;

    const recurringBill = new RecurringBill({
      profileName,
      vendorId,
      vendorName,
      vendorEmail: vendorEmail || '',
      repeatEvery: Number(repeatEvery),
      repeatUnit,
      startDate: new Date(startDate),
      endDate: endDate ? new Date(endDate) : null,
      nextBillDate: new Date(startDate),
      billCreationMode: billCreationMode || 'save_as_draft',
      items: processedItems,
      subTotal,
      tdsRate, tdsAmount,
      tcsRate, tcsAmount,
      gstRate, gstAmount,
      totalAmount,
      paymentTerms: paymentTerms || 'Net 30',
      notes: notes || '',
      organizationId: req.user?.organizationId || '',
      orgId: req.user?.orgId || null,
      createdBy: req.user?.id || '',
    });

    await recurringBill.save();
    res.status(201).json({ success: true, data: recurringBill, message: 'Recurring bill profile created successfully' });
  } catch (err) {
    if (err.name === 'ValidationError') {
      const messages = Object.values(err.errors).map((e) => e.message);
      return res.status(400).json({ success: false, message: messages.join(', ') });
    }
    res.status(500).json({ success: false, message: err.message });
  }
};

// PUT /api/recurring-bills/:id
const updateRecurringBill = async (req, res) => {
  try {
    const {
      profileName, vendorId, vendorName, vendorEmail,
      repeatEvery, repeatUnit, startDate, endDate,
      billCreationMode, items, paymentTerms, notes,
      tdsRate = 0, tcsRate = 0, gstRate = 18,
    } = req.body;

    if (!items || items.length === 0) {
      return res.status(400).json({ success: false, message: 'At least one item is required' });
    }

    // Recalculate totals
    let subTotal = 0;
    const processedItems = items.map((item) => {
      let amount = item.quantity * item.rate;
      if (item.discount > 0) {
        if (item.discountType === 'percentage') {
          amount -= amount * (item.discount / 100);
        } else {
          amount -= item.discount;
        }
      }
      item.amount = Math.max(0, amount);
      subTotal += item.amount;
      return item;
    });

    const tdsAmount = (subTotal * tdsRate) / 100;
    const tcsAmount = (subTotal * tcsRate) / 100;
    const gstAmount = ((subTotal - tdsAmount + tcsAmount) * gstRate) / 100;
    const totalAmount = subTotal - tdsAmount + tcsAmount + gstAmount;

    const updated = await RecurringBill.findOneAndUpdate(
      { _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) },
      {
        profileName, vendorId, vendorName,
        vendorEmail: vendorEmail || '',
        repeatEvery: Number(repeatEvery),
        repeatUnit,
        startDate: new Date(startDate),
        endDate: endDate ? new Date(endDate) : null,
        billCreationMode: billCreationMode || 'save_as_draft',
        items: processedItems,
        subTotal, tdsRate, tdsAmount,
        tcsRate, tcsAmount, gstRate, gstAmount,
        totalAmount,
        paymentTerms: paymentTerms || 'Net 30',
        notes: notes || '',
      },
      { new: true, runValidators: true }
    );

    if (!updated) {
      return res.status(404).json({ success: false, message: 'Recurring bill profile not found' });
    }

    res.json({ success: true, data: updated, message: 'Recurring bill profile updated successfully' });
  } catch (err) {
    if (err.name === 'ValidationError') {
      const messages = Object.values(err.errors).map((e) => e.message);
      return res.status(400).json({ success: false, message: messages.join(', ') });
    }
    res.status(500).json({ success: false, message: err.message });
  }
};

// DELETE /api/recurring-bills/:id
const deleteRecurringBill = async (req, res) => {
  try {
    const deleted = await RecurringBill.findOneAndDelete({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!deleted) {
      return res.status(404).json({ success: false, message: 'Recurring bill profile not found' });
    }
    res.json({ success: true, message: 'Recurring bill profile deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// PATCH /api/recurring-bills/:id/pause
const pauseRecurringBill = async (req, res) => {
  try {
    const bill = await RecurringBill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, message: 'Profile not found' });
    if (bill.status !== 'ACTIVE') {
      return res.status(400).json({ success: false, message: 'Only active profiles can be paused' });
    }
    bill.status = 'PAUSED';
    await bill.save();
    res.json({ success: true, message: 'Profile paused successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// PATCH /api/recurring-bills/:id/resume
const resumeRecurringBill = async (req, res) => {
  try {
    const bill = await RecurringBill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!bill) return res.status(404).json({ success: false, message: 'Profile not found' });
    if (bill.status !== 'PAUSED') {
      return res.status(400).json({ success: false, message: 'Only paused profiles can be resumed' });
    }
    bill.status = 'ACTIVE';
    await bill.save();
    res.json({ success: true, message: 'Profile resumed successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// PATCH /api/recurring-bills/:id/stop
const stopRecurringBill = async (req, res) => {
  try {
    const bill = await RecurringBill.findOneAndUpdate(
      { _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) },
      { status: 'STOPPED' },
      { new: true }
    );
    if (!bill) return res.status(404).json({ success: false, message: 'Profile not found' });
    res.json({ success: true, message: 'Profile stopped successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// POST /api/recurring-bills/:id/generate
const generateManualBill = async (req, res) => {
  try {
    const profile = await RecurringBill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!profile) return res.status(404).json({ success: false, message: 'Profile not found' });
    if (profile.status === 'STOPPED') {
      return res.status(400).json({ success: false, message: 'Cannot generate bill from stopped profile' });
    }
    
    // Get user ID from request (from JWT token)
    const userId = req.user?.email || req.user?.userId || 'SYSTEM';
    
    const bill = await generateBillFromProfile(profile, userId);
    res.status(201).json({
      success: true,
      data: { billId: bill._id, billNumber: bill.billNumber },
      message: `Bill ${bill.billNumber} generated successfully`,
    });
  } catch (err) {
    console.error('❌ Generate bill error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
};

// GET /api/recurring-bills/:id/child-bills
const getChildBills = async (req, res) => {
  try {
    const profile = await RecurringBill.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!profile) return res.status(404).json({ success: false, message: 'Profile not found' });

    const bills = await Bill.find({ recurringProfileId: req.params.id })
      .sort({ createdAt: -1 })
      .lean();

    res.json({ success: true, data: { bills } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// POST /api/recurring-bills/bulk-import
const bulkImportRecurringBills = async (req, res) => {
  try {
    const { recurringBills } = req.body;
    if (!recurringBills || !Array.isArray(recurringBills) || recurringBills.length === 0) {
      return res.status(400).json({ success: false, message: 'No recurring bills data provided' });
    }

    let successCount = 0;
    let failedCount = 0;
    const errors = [];

    for (let i = 0; i < recurringBills.length; i++) {
      try {
        const b = recurringBills[i];
        if (!b.profileName || !b.vendorName || !b.repeatEvery || !b.repeatUnit || !b.startDate) {
          throw new Error('Missing required fields: profileName, vendorName, repeatEvery, repeatUnit, startDate');
        }

        const items = b.items || [{
          itemDetails: b.itemDescription || 'Service',
          quantity: Number(b.quantity) || 1,
          rate: Number(b.rate) || 0,
          discount: 0,
          discountType: 'percentage',
          amount: (Number(b.quantity) || 1) * (Number(b.rate) || 0),
        }];

        let subTotal = items.reduce((sum, item) => sum + (item.amount || 0), 0);
        const gstRate = Number(b.gstRate) || 18;
        const gstAmount = (subTotal * gstRate) / 100;
        const totalAmount = subTotal + gstAmount;

        const recurring = new RecurringBill({
          profileName: b.profileName,
          vendorId: b.vendorId || 'imported',
          vendorName: b.vendorName,
          vendorEmail: b.vendorEmail || '',
          repeatEvery: Number(b.repeatEvery),
          repeatUnit: b.repeatUnit,
          startDate: new Date(b.startDate),
          endDate: b.endDate ? new Date(b.endDate) : null,
          nextBillDate: new Date(b.startDate),
          billCreationMode: b.billCreationMode || 'save_as_draft',
          items,
          subTotal,
          gstRate,
          gstAmount,
          totalAmount,
          paymentTerms: b.paymentTerms || 'Net 30',
          notes: b.notes || '',
          orgId: req.user?.orgId || null,
        });

        await recurring.save();
        successCount++;
      } catch (err) {
        failedCount++;
        errors.push(`Row ${i + 1}: ${err.message}`);
      }
    }

    res.json({
      success: true,
      data: {
        totalProcessed: recurringBills.length,
        successCount,
        failedCount,
        errors,
      },
      message: `Import completed. ${successCount} succeeded, ${failedCount} failed.`,
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// ============================================================================
// ROUTES
// ============================================================================

router.get('/stats', authMiddleware, getStats);
router.get('/', authMiddleware, getAllRecurringBills);
router.get('/:id', authMiddleware, getRecurringBillById);
router.post('/', authMiddleware, createRecurringBill);
router.put('/:id', authMiddleware, updateRecurringBill);
router.delete('/:id', authMiddleware, deleteRecurringBill);
router.patch('/:id/pause', authMiddleware, pauseRecurringBill);
router.patch('/:id/resume', authMiddleware, resumeRecurringBill);
router.patch('/:id/stop', authMiddleware, stopRecurringBill);
router.post('/:id/generate', authMiddleware, generateManualBill);
router.get('/:id/child-bills', authMiddleware, getChildBills);
router.post('/bulk-import', authMiddleware, bulkImportRecurringBills);

module.exports = router;

// ============================================================================
// HOW TO REGISTER IN app.js / server.js:
// ============================================================================
// const recurringBillRoutes = require('./routes/recurring_bill');
// app.use('/api/recurring-bills', recurringBillRoutes);
//
// INSTALL node-cron if not already:
// npm install node-cron
// ============================================================================