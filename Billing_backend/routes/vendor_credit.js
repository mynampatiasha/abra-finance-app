// ============================================================================
// VENDOR CREDIT BACKEND
// ============================================================================
// File: routes/vendor_credit.js
// Full Express routes + Mongoose model + controller logic
// Register in app.js: app.use('/api/vendor-credits', require('./routes/vendor_credit'))
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');


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

const VendorCreditItemSchema = new mongoose.Schema({
  itemDetails: { type: String, required: true },
  account: { type: String, default: '' },
  quantity: { type: Number, required: true, min: 0 },
  rate: { type: Number, required: true, min: 0 },
  discount: { type: Number, default: 0 },
  discountType: { type: String, enum: ['percentage', 'amount'], default: 'percentage' },
  amount: { type: Number, required: true, min: 0 },
}, { _id: false });

const CreditApplicationSchema = new mongoose.Schema({
  billId: { type: String, default: '' },
  billNumber: { type: String, required: true },
  amount: { type: Number, required: true, min: 0.01 },
  appliedDate: { type: Date, default: Date.now },
});

const CreditRefundSchema = new mongoose.Schema({
  amount: { type: Number, required: true, min: 0.01 },
  refundDate: { type: Date, default: Date.now },
  paymentMode: {
    type: String,
    enum: ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'NEFT', 'RTGS', 'IMPS', 'Online'],
    default: 'Bank Transfer'
  },
  referenceNumber: { type: String, default: '' },
  notes: { type: String, default: '' },
});

const VendorCreditSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  creditNumber: { type: String, unique: true, sparse: true },
  vendorId: { type: String, required: true },
  vendorName: { type: String, required: true },
  vendorEmail: { type: String, default: '' },
  vendorPhone: { type: String, trim: true, default: '' },
  vendorGSTIN: { type: String, default: '' },
  creditDate: { type: Date, required: true, default: Date.now },
  billId: { type: String, default: null },
  billNumber: { type: String, default: null },
  reason: { type: String, required: true },
  status: {
    type: String,
    enum: ['OPEN', 'PARTIALLY_APPLIED', 'CLOSED', 'VOID'],
    default: 'OPEN'
  },
  items: [VendorCreditItemSchema],
  subTotal: { type: Number, default: 0 },
  gstRate: { type: Number, default: 0 },
  cgst: { type: Number, default: 0 },
  sgst: { type: Number, default: 0 },
  tdsAmount: { type: Number, default: 0 },
  tcsAmount: { type: Number, default: 0 },
  totalAmount: { type: Number, required: true, min: 0 },
  appliedAmount: { type: Number, default: 0 },
  balanceAmount: { type: Number, default: 0 },
  applications: [CreditApplicationSchema],
  refunds: [CreditRefundSchema],
  notes: { type: String, default: '' },
  isImported: { type: Boolean, default: false },
}, {
  timestamps: true,
  toJSON: { virtuals: true },
  toObject: { virtuals: true }
});

// Auto-generate credit number
VendorCreditSchema.pre('save', async function () {
  if (!this.creditNumber) {
    const { generateNumber } = require('../utils/numberGenerator');
    this.creditNumber = await generateNumber(
      mongoose.model('VendorCredit'), 'creditNumber', 'VC', this.orgId || null
    );
  }
});

const VendorCredit = mongoose.models.VendorCredit ||
  mongoose.model('VendorCredit', VendorCreditSchema);

// ============================================================================
// HELPER
// ============================================================================

function successResponse(res, data, message = 'Success', statusCode = 200) {
  return res.status(statusCode).json({ success: true, message, data });
}

function errorResponse(res, message = 'Error', statusCode = 500, error = null) {
  console.error(`[VendorCredit] ${message}`, error || '');
  return res.status(statusCode).json({ success: false, message, error: error?.message });
}

// ============================================================================
// ROUTES
// ============================================================================

// GET /api/vendor-credits/stats
router.get('/stats', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const [totalCredits, statusBreakdown, amounts] = await Promise.all([
      VendorCredit.countDocuments(orgFilter),
      VendorCredit.aggregate([
        { $match: orgFilter },
        { $group: { _id: '$status', count: { $sum: 1 } } }
      ]),
      VendorCredit.aggregate([
        { $match: orgFilter },
        {
          $group: {
            _id: null,
            totalCreditAmount: { $sum: '$totalAmount' },
            totalApplied: { $sum: '$appliedAmount' },
            totalBalance: { $sum: '$balanceAmount' },
          }
        }
      ])
    ]);

    const statusMap = {};
    statusBreakdown.forEach(s => { statusMap[s._id] = s.count; });
    const amts = amounts[0] || {};

    return successResponse(res, {
      totalCredits,
      totalCreditAmount: amts.totalCreditAmount || 0,
      totalApplied: amts.totalApplied || 0,
      totalBalance: amts.totalBalance || 0,
      openCredits: statusMap['OPEN'] || 0,
      partiallyApplied: statusMap['PARTIALLY_APPLIED'] || 0,
      closedCredits: statusMap['CLOSED'] || 0,
    }, 'Stats loaded');
  } catch (err) {
    return errorResponse(res, 'Failed to load stats', 500, err);
  }
});

// GET /api/vendor-credits
router.get('/', async (req, res) => {
  try {
    const {
      page = 1, limit = 20, status, search,
      fromDate, toDate, vendorId
    } = req.query;

    const pageNum = Math.max(1, parseInt(page));
    const limitNum = Math.min(100, Math.max(1, parseInt(limit)));
    const skip = (pageNum - 1) * limitNum;

    const filter = {};
    if (req.user?.orgId) filter.orgId = req.user.orgId;

    if (status) filter.status = status;
    if (vendorId) filter.vendorId = vendorId;

    if (fromDate || toDate) {
      filter.creditDate = {};
      if (fromDate) filter.creditDate.$gte = new Date(fromDate);
      if (toDate) {
        const to = new Date(toDate);
        to.setHours(23, 59, 59, 999);
        filter.creditDate.$lte = to;
      }
    }

    if (search) {
      const regex = new RegExp(search, 'i');
      filter.$or = [
        { creditNumber: regex },
        { vendorName: regex },
        { vendorEmail: regex },
        { billNumber: regex },
        { reason: regex },
      ];
    }

    const [credits, total] = await Promise.all([
      VendorCredit.find(filter)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limitNum)
        .lean(),
      VendorCredit.countDocuments(filter),
    ]);

    return successResponse(res, {
      credits,
      pagination: {
        total,
        pages: Math.ceil(total / limitNum),
        page: pageNum,
        limit: limitNum,
      },
    });
  } catch (err) {
    return errorResponse(res, 'Failed to fetch vendor credits', 500, err);
  }
});

// POST /api/vendor-credits/bulk-import  ← before any /:id routes
router.post('/bulk-import', async (req, res) => {
  try {
    const { credits } = req.body;

    if (!credits || !Array.isArray(credits) || credits.length === 0) {
      return errorResponse(res, 'No credits data provided', 400);
    }

    let successCount = 0;
    let failedCount  = 0;
    const errors  = [];
    const created = [];

    for (let i = 0; i < credits.length; i++) {
      try {
        const data = credits[i];

        if (!data.vendorName)
          throw new Error('Vendor Name is required');
        if (!data.reason)
          throw new Error('Reason is required');
        if (!data.totalAmount || data.totalAmount <= 0)
          throw new Error('Total Amount must be > 0');
        if (!data.items || data.items.length === 0)
          throw new Error('At least one item required');

        // ✅ Auto-generate vendorId if missing
        if (!data.vendorId) {
          data.vendorId = `imported_${data.vendorName
            .toLowerCase().replace(/\s+/g, '_')}`;
        }

        const credit = new VendorCredit({
          ...data,
          isImported:    true,
          appliedAmount: 0,
          balanceAmount: data.totalAmount,
          applications:  [],
          refunds:       [],
          orgId:         req.user?.orgId || null,
        });

        await credit.save();
        created.push(credit);
        successCount++;
      } catch (e) {
        failedCount++;
        errors.push(`Row ${i + 1}: ${e.message}`);
      }
    }

    return successResponse(res, {
      totalProcessed: credits.length,
      successCount,
      failedCount,
      errors,
      created: created.map(c => c.creditNumber),
    }, `Import complete: ${successCount} succeeded, ${failedCount} failed`);
  } catch (err) {
    return errorResponse(res, 'Bulk import failed', 500, err);
  }
});

// GET /api/vendor-credits/:id
router.get('/:id', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);
    return successResponse(res, credit);
  } catch (err) {
    return errorResponse(res, 'Failed to fetch vendor credit', 500, err);
  }
});

// POST /api/vendor-credits
router.post('/', async (req, res) => {
  try {
    const body = req.body;

    if (!body.vendorId)   return errorResponse(res, 'Vendor ID is required', 400);
    if (!body.vendorName) return errorResponse(res, 'Vendor Name is required', 400);
    if (!body.reason)     return errorResponse(res, 'Reason is required', 400);
    if (!body.items || body.items.length === 0)
      return errorResponse(res, 'At least one item is required', 400);

    for (const item of body.items) {
      if (!item.itemDetails)               return errorResponse(res, 'Item details required', 400);
      if (!item.quantity || item.quantity <= 0) return errorResponse(res, 'Item quantity must be > 0', 400);
      if (!item.rate     || item.rate     <= 0) return errorResponse(res, 'Item rate must be > 0', 400);
    }

    const credit = new VendorCredit({
      ...body,
      orgId: req.user?.orgId || null,
      balanceAmount: body.totalAmount || 0,
      appliedAmount: 0,
      applications:  [],
      refunds:       [],
    });

    await credit.save();

    // ✅ COA: Debit AP + Credit COGS (reversal of bill)
// ✅ COA: Full breakdown with GST + TDS + TCS
try {
  const currentOrgId = req.user?.orgId || null;
  const [apId, cogsId, taxId, tdsPayableId, tdsReceivableId] = await Promise.all([
    getSystemAccountId('Accounts Payable', currentOrgId),
    getSystemAccountId('Cost of Goods Sold', currentOrgId),
    getSystemAccountId('Tax Payable', currentOrgId),
    getSystemAccountId('TDS Payable', currentOrgId),
    getSystemAccountId('TDS Receivable', currentOrgId),
  ]);
  const txnDate = new Date(credit.creditDate);

  // Debit AP — reduces what we owe vendor
  if (apId) await postTransactionToCOA({
    accountId:       apId,
    orgId:           currentOrgId,
    date:            txnDate,
    description:     `Vendor Credit ${credit.creditNumber} - ${credit.vendorName}`,
    referenceType:   'VendorCredit',
    referenceId:     credit._id,
    referenceNumber: credit.creditNumber,
    debit:           credit.totalAmount,
    credit:          0,
  });

  // Credit COGS — reversal of cost
  if (cogsId) await postTransactionToCOA({
    accountId:       cogsId,
    orgId:           currentOrgId,
    date:            txnDate,
    description:     `Vendor Credit ${credit.creditNumber} - ${credit.vendorName}`,
    referenceType:   'VendorCredit',
    referenceId:     credit._id,
    referenceNumber: credit.creditNumber,
    debit:           0,
    credit:          credit.subTotal || credit.totalAmount,
  });

  // Credit Tax Payable for GST reversal
  if (taxId && (credit.cgst + credit.sgst) > 0) await postTransactionToCOA({
    accountId:       taxId,
    orgId:           currentOrgId,
    date:            txnDate,
    description:     `GST reversal - Vendor Credit ${credit.creditNumber}`,
    referenceType:   'VendorCredit',
    referenceId:     credit._id,
    referenceNumber: credit.creditNumber,
    debit:           0,
    credit:          credit.cgst + credit.sgst,
  });

  // Debit TDS Payable reversal
  if (tdsPayableId && credit.tdsAmount > 0) await postTransactionToCOA({
    accountId:       tdsPayableId,
    orgId:           currentOrgId,
    date:            txnDate,
    description:     `TDS reversal - Vendor Credit ${credit.creditNumber}`,
    referenceType:   'VendorCredit',
    referenceId:     credit._id,
    referenceNumber: credit.creditNumber,
    debit:           credit.tdsAmount,
    credit:          0,
  });

  // Credit TDS Receivable reversal
  if (tdsReceivableId && credit.tcsAmount > 0) await postTransactionToCOA({
    accountId:       tdsReceivableId,
    orgId:           currentOrgId,
    date:            txnDate,
    description:     `TCS reversal - Vendor Credit ${credit.creditNumber}`,
    referenceType:   'VendorCredit',
    referenceId:     credit._id,
    referenceNumber: credit.creditNumber,
    debit:           0,
    credit:          credit.tcsAmount,
  });

console.log(`✅ COA posted for vendor credit: ${credit.creditNumber}`);
} catch (coaErr) {
  console.error('⚠️ COA error (vendor credit create):', coaErr.message);
}

    // ✅ AUTO-APPLY TO BILL if billId is provided at creation time
    if (body.billId) {
      try {
        const Bill = mongoose.models.Bill ||
          mongoose.model('Bill', new mongoose.Schema({}, { strict: false }));

        const bill = await Bill.findById(body.billId);
        if (bill) {
          const creditAmount = parseFloat(credit.totalAmount || 0);

          bill.amountPaid = (bill.amountPaid || 0) + creditAmount;
          bill.amountDue  = Math.max(0, (bill.totalAmount || 0) - bill.amountPaid);

          if (bill.amountDue <= 0.01) {
            bill.status    = 'PAID';
            bill.amountDue = 0;
          } else if (bill.amountPaid > 0) {
            bill.status = 'PARTIALLY_PAID';
          }

          bill.vendorCreditsApplied = bill.vendorCreditsApplied || [];
          bill.vendorCreditsApplied.push({
            creditId:    credit._id,
            amount:      creditAmount,
            appliedDate: new Date(),
          });

          await bill.save();
          console.log(`✅ Bill ${bill.billNumber} auto-updated to ${bill.status}`);

          // ✅ Update credit status
          credit.appliedAmount = creditAmount;
          credit.balanceAmount = credit.totalAmount - creditAmount;
          credit.applications.push({
            billId:      body.billId,
            billNumber:  body.billNumber || bill.billNumber,
            amount:      creditAmount,
            appliedDate: new Date(),
          });

          if (credit.balanceAmount <= 0.01) {
            credit.status        = 'CLOSED';
            credit.balanceAmount = 0;
          } else {
            credit.status = 'PARTIALLY_APPLIED';
          }

          await credit.save();
          console.log(`✅ Vendor Credit ${credit.creditNumber} status → ${credit.status}`);
        }
      } catch (billErr) {
        console.error('⚠️ Bill auto-apply error:', billErr.message);
      }
    }

    // ✅ Re-fetch to return latest status
    const finalCredit = await VendorCredit.findById(credit._id).lean();
    return successResponse(res, finalCredit, 'Vendor credit created', 201);
  } catch (err) {
    if (err.code === 11000) {
      return errorResponse(res, 'Credit number already exists', 400, err);
    }
    return errorResponse(res, 'Failed to create vendor credit', 500, err);
  }
});

// PUT /api/vendor-credits/:id
router.put('/:id', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'CLOSED' || credit.status === 'VOID') {
      return errorResponse(res, 'Cannot edit a closed or voided credit', 400);
    }

    const forbidden = ['creditNumber', 'applications', 'refunds', 'appliedAmount', '_id'];
    const updates = Object.fromEntries(
      Object.entries(req.body).filter(([k]) => !forbidden.includes(k))
    );

    Object.assign(credit, updates);

    // Recalculate balance
    const applied = credit.applications.reduce((s, a) => s + a.amount, 0);
    const refunded = credit.refunds.reduce((s, r) => s + r.amount, 0);
    credit.appliedAmount = applied + refunded;
    credit.balanceAmount = credit.totalAmount - credit.appliedAmount;

    await credit.save();
    return successResponse(res, credit, 'Vendor credit updated');
  } catch (err) {
    return errorResponse(res, 'Failed to update vendor credit', 500, err);
  }
});

// PUT /api/vendor-credits/:id/void
router.put('/:id/void', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);
    if (credit.status === 'CLOSED') return errorResponse(res, 'Cannot void a closed credit', 400);

    credit.status = 'VOID';
    await credit.save();
    return successResponse(res, credit, 'Vendor credit voided');
  } catch (err) {
    return errorResponse(res, 'Failed to void vendor credit', 500, err);
  }
});

// POST /api/vendor-credits/:id/apply
router.post('/:id/apply', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'VOID')   return errorResponse(res, 'Cannot apply a voided credit', 400);
    if (credit.status === 'CLOSED') return errorResponse(res, 'Credit is fully closed', 400);

    const { billId, billNumber, amount, appliedDate } = req.body;

    if (!billNumber)           return errorResponse(res, 'Bill number is required', 400);
    if (!amount || amount <= 0) return errorResponse(res, 'Amount must be greater than 0', 400);
    if (amount > credit.balanceAmount + 0.01) {
      return errorResponse(res,
        `Amount exceeds available balance (₹${credit.balanceAmount.toFixed(2)})`, 400);
    }

    credit.applications.push({
      billId:      billId || '',
      billNumber,
      amount:      parseFloat(amount),
      appliedDate: appliedDate ? new Date(appliedDate) : new Date(),
    });

    const totalApplied = credit.applications.reduce((s, a) => s + a.amount, 0)
      + credit.refunds.reduce((s, r) => s + r.amount, 0);
    credit.appliedAmount = totalApplied;
    credit.balanceAmount = credit.totalAmount - totalApplied;

    if (credit.balanceAmount <= 0.01) {
      credit.status        = 'CLOSED';
      credit.balanceAmount = 0;
    } else {
      credit.status = 'PARTIALLY_APPLIED';
    }

    await credit.save();
    // ✅ Auto-update bill status when credit is applied
if (billId) {
  try {
    const Bill = mongoose.models.Bill ||
      mongoose.model('Bill', new mongoose.Schema({}, { strict: false }));

    const bill = await Bill.findById(billId);
    if (bill) {
      const creditApplied = parseFloat(amount);
      bill.amountPaid = (bill.amountPaid || 0) + creditApplied;
      bill.amountDue  = Math.max(0, (bill.totalAmount || 0) - bill.amountPaid);

      if (bill.amountDue <= 0.01) {
        bill.status    = 'PAID';
        bill.amountDue = 0;
      } else if (bill.amountPaid > 0) {
        bill.status = 'PARTIALLY_PAID';
      }

      await bill.save();
      console.log(`✅ Bill ${billNumber} status updated to ${bill.status}`);
    }
  } catch (billErr) {
    console.error('⚠️ Bill status update error:', billErr.message);
  }
}

    // ✅ COA: Debit AP — credit applied reduces AP balance
    try {
      const apId = await getSystemAccountId('Accounts Payable', req.user?.orgId || null);
      const txnDate = new Date();

      if (apId) await postTransactionToCOA({
        accountId:       apId,
        orgId:           req.user?.orgId || null,
        date:            txnDate,
        description:     `Vendor Credit ${credit.creditNumber} applied to Bill ${billNumber}`,
        referenceType:   'VendorCredit',
        referenceId:     credit._id,
        referenceNumber: credit.creditNumber,
        debit:           parseFloat(amount),
        credit:          0,
      });

      console.log(`✅ COA posted for vendor credit application: ${credit.creditNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA error (vendor credit apply):', coaErr.message);
    }

    return successResponse(res, credit, `Credit applied to bill ${billNumber}`);
  } catch (err) {
    return errorResponse(res, 'Failed to apply credit', 500, err);
  }
});
// POST /api/vendor-credits/:id/refund
router.post('/:id/refund', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'VOID')   return errorResponse(res, 'Cannot refund a voided credit', 400);
    if (credit.status === 'CLOSED') return errorResponse(res, 'Credit is fully closed', 400);

    const { amount, refundDate, paymentMode, referenceNumber, notes } = req.body;

    if (!amount || amount <= 0) return errorResponse(res, 'Amount must be greater than 0', 400);
    if (amount > credit.balanceAmount + 0.01) {
      return errorResponse(res,
        `Amount exceeds available balance (₹${credit.balanceAmount.toFixed(2)})`, 400);
    }

    credit.refunds.push({
      amount:          parseFloat(amount),
      refundDate:      refundDate ? new Date(refundDate) : new Date(),
      paymentMode:     paymentMode || 'Bank Transfer',
      referenceNumber: referenceNumber || '',
      notes:           notes || '',
    });

    const totalUsed = credit.applications.reduce((s, a) => s + a.amount, 0)
      + credit.refunds.reduce((s, r) => s + r.amount, 0);
    credit.appliedAmount = totalUsed;
    credit.balanceAmount = credit.totalAmount - totalUsed;

    if (credit.balanceAmount <= 0.01) {
      credit.status        = 'CLOSED';
      credit.balanceAmount = 0;
    } else {
      credit.status = 'PARTIALLY_APPLIED';
    }

    await credit.save();

    // ✅ COA: Debit AP + Credit Undeposited Funds (cash back to you)
    try {
      const [apId, bankId] = await Promise.all([
        getSystemAccountId('Accounts Payable', req.user?.orgId || null),
        getSystemAccountId('Undeposited Funds', req.user?.orgId || null),
      ]);
      const txnDate = new Date();

      if (apId) await postTransactionToCOA({
        accountId:       apId,
        orgId:           req.user?.orgId || null,
        date:            txnDate,
        description:     `Vendor Credit ${credit.creditNumber} refund`,
        referenceType:   'VendorCredit',
        referenceId:     credit._id,
        referenceNumber: credit.creditNumber,
        debit:           parseFloat(amount),
        credit:          0,
      });

      if (bankId) await postTransactionToCOA({
        accountId:       bankId,
        orgId:           req.user?.orgId || null,
        date:            txnDate,
        description:     `Vendor Credit ${credit.creditNumber} refund`,
        referenceType:   'VendorCredit',
        referenceId:     credit._id,
        referenceNumber: credit.creditNumber,
        debit:           0,
        credit:          parseFloat(amount),
      });

      console.log(`✅ COA posted for vendor credit refund: ${credit.creditNumber}`);
    } catch (coaErr) {
      console.error('⚠️ COA error (vendor credit refund):', coaErr.message);
    }

    return successResponse(res, credit, 'Refund recorded successfully');
  } catch (err) {
    return errorResponse(res, 'Failed to record refund', 500, err);
  }
});
// TEMP FIX ROUTE — remove after use
router.post('/fix-bill/:billId', async (req, res) => {
  try {
    const Bill = mongoose.models.Bill ||
      mongoose.model('Bill', new mongoose.Schema({}, { strict: false }));

    const bill = await Bill.findById(req.params.billId);
    if (!bill) return res.status(404).json({ message: 'Bill not found' });

    const { creditAmount } = req.body;

    bill.amountPaid = (bill.amountPaid || 0) + parseFloat(creditAmount);
    bill.amountDue  = Math.max(0, bill.totalAmount - bill.amountPaid);

    if (bill.amountDue <= 0.01) {
      bill.status    = 'PAID';
      bill.amountDue = 0;
    } else {
      bill.status = 'PARTIALLY_PAID';
    }

    await bill.save();
    res.json({ success: true, status: bill.status, amountDue: bill.amountDue });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


// GET /api/vendor-credits/:id/email-preview
router.get('/:id/email-preview', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({ _id: req.params.id, orgId: req.user?.orgId });
    if (!credit) return res.status(404).json({ success: false, error: 'Vendor credit not found' });
    const OrgModel = mongoose.models.Organization ||
      mongoose.model('Organization', new mongoose.Schema({}, { strict: false }), 'organizations');
    const org = await OrgModel.findOne({ orgId: req.user?.orgId }).lean();
    const orgName = org?.orgName || '';
    const orgGST  = org?.gstNumber || '';
    const orgPhone = org?.phone || '';
    const orgEmail = org?.email || '';
    const dateStr = new Date(credit.creditDate).toLocaleDateString('en-IN', { day:'2-digit', month:'long', year:'numeric' });
    const html = `<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>Vendor Credit ${credit.creditNumber}</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:Arial,sans-serif;font-size:13px;color:#222;background:#f4f4f4}.wrapper{max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd}.header{background:#0f1e3d;padding:24px 32px}.header h1{color:#fff;font-size:20px;font-weight:bold}.header .num{color:#fff;font-size:14px;font-weight:bold;margin-top:8px}.body{padding:28px 32px}.st{font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px}table.d{width:100%;border-collapse:collapse;font-size:13px}table.d td{padding:7px 0;border-bottom:1px dashed #e8e8e8;vertical-align:top}table.d td:first-child{color:#555;width:160px}table.d td:last-child{font-weight:600;color:#111;text-align:right}.tr td{font-size:15px;font-weight:bold;border-top:2px solid #222;border-bottom:none;padding-top:10px}.footer{background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7}</style>
</head><body><div class="wrapper">
<div class="header"><h1>Vendor Credit Note</h1><div class="num">${credit.creditNumber}</div></div>
<div class="body">
<p style="font-size:14px;margin-bottom:18px;">Dear ${credit.vendorName},</p>
<p style="color:#444;line-height:1.7;margin-bottom:6px;">Please find attached vendor credit note <strong>${credit.creditNumber}</strong>.</p>
<div class="st">Credit Details</div>
<table class="d">
<tr><td>Credit Number</td><td>${credit.creditNumber}</td></tr>
<tr><td>Date</td><td>${dateStr}</td></tr>
<tr><td>Reason</td><td>${credit.reason || ''}</td></tr>
${credit.billNumber ? `<tr><td>Against Bill</td><td>${credit.billNumber}</td></tr>` : ''}
</table>
<div class="st">Amount Summary</div>
<table class="d">
<tr><td>Subtotal</td><td>₹${credit.subTotal.toFixed(2)}</td></tr>
${credit.cgst > 0 ? `<tr><td>CGST</td><td>₹${credit.cgst.toFixed(2)}</td></tr>` : ''}
${credit.sgst > 0 ? `<tr><td>SGST</td><td>₹${credit.sgst.toFixed(2)}</td></tr>` : ''}
<tr class="tr"><td>Credit Amount</td><td>₹${credit.totalAmount.toFixed(2)}</td></tr>
<tr><td>Balance Available</td><td>₹${credit.balanceAmount.toFixed(2)}</td></tr>
</table>
${credit.notes ? `<div class="st">Notes</div><p style="font-size:12px;line-height:1.7;color:#444;">${credit.notes}</p>` : ''}
</div>
<div class="footer"><strong>${orgName}</strong><br>${orgGST ? 'GST: ' + orgGST + ' | ' : ''}${orgPhone ? 'Ph: ' + orgPhone + ' | ' : ''}${orgEmail}</div>
</div></body></html>`;
    res.json({ success: true, data: { subject: `Vendor Credit Note ${credit.creditNumber} — ₹${credit.totalAmount.toFixed(2)}`, html, to: credit.vendorEmail } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// PATCH /:id/email-preview — save custom email content
router.patch('/:id/email-preview', async (req, res) => {
  try {
    const { to, subject, html } = req.body;
    const credit = await VendorCredit.findOne({ _id: req.params.id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) });
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);
    if (to !== undefined)      credit.set('customEmailTo',      to);
    if (subject !== undefined) credit.set('customEmailSubject', subject);
    if (html !== undefined)    credit.set('customEmailHtml',    html);
    await credit.save();
    res.json({ success: true, data: { to, subject, html } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// DELETE /api/vendor-credits/:id
router.delete('/:id', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!credit) return errorResponse(res, 'Vendor credit not found', 404);

    if (credit.status === 'CLOSED') {
      return errorResponse(res, 'Cannot delete a closed credit', 400);
    }

    await credit.deleteOne();
    return successResponse(res, null, 'Vendor credit deleted');
  } catch (err) {
    return errorResponse(res, 'Failed to delete vendor credit', 500, err);
  }
});

// GET /api/vendor-credits/:id/vendor-phone
// Looks up vendor phone directly from DB — no need to store it on the credit
router.get('/:id/vendor-phone', async (req, res) => {
  try {
    const credit = await VendorCredit.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).select('vendorId vendorName');
    if (!credit) {
      return res.status(404).json({ success: false, message: 'Credit not found' });
    }

    // Try BillingVendor collection first, fall back to admin Vendor
    const BillingVendor = mongoose.models.BillingVendor ||
      mongoose.model('BillingVendor', new mongoose.Schema({}, { strict: false }));
    const AdminVendor = mongoose.models.Vendor ||
      mongoose.model('Vendor', new mongoose.Schema({}, { strict: false }));

    let phone = '';

    const bv = await BillingVendor.findById(credit.vendorId)
      .select('phone primaryPhone phoneNumber vendorPhone').lean();
    if (bv) {
      phone = bv.phone ?? bv.primaryPhone ?? bv.phoneNumber ?? bv.vendorPhone ?? '';
    }

    if (!phone) {
      const av = await AdminVendor.findById(credit.vendorId)
        .select('phone primaryPhone phoneNumber vendorPhone').lean();
      if (av) {
        phone = av.phone ?? av.primaryPhone ?? av.phoneNumber ?? av.vendorPhone ?? '';
      }
    }

    // Handle scientific notation (e.g. 9.88E+09)
    if (phone && phone.toString().toUpperCase().includes('E')) {
      phone = Math.round(parseFloat(phone)).toString();
    }

    res.json({
      success: true,
      phone: phone.toString().replace(/[^\d+]/g, '').trim(),
      vendorName: credit.vendorName,
    });

  } catch (err) {
    console.error('Error fetching vendor phone for credit:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;