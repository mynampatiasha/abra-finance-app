// ============================================================================
// BUDGETS — BACKEND
// ============================================================================
// File: backend/routes/budgets.js
// Register in app.js: app.use('/api/budgets', require('./routes/budgets'));
// ============================================================================

const express  = require('express');
const router   = express.Router();
const mongoose = require('mongoose');
const multer   = require('multer');

// ── COA dependency ────────────────────────────────────────────────────────────
const { ChartOfAccount, AccountTransaction } = require('./chart_of_accounts');

// ── Auth middleware ────────────────────────────────────────────────────────────
const { verifyFinanceJWT } = require('../middleware/finance_jwt');
const authenticate  = verifyFinanceJWT;

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const budgetAccountLineSchema = new mongoose.Schema({
  accountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'ChartOfAccount',
    default: null,
  },
  accountName: { type: String, required: true, trim: true },
  accountType:  { type: String, required: true, trim: true },
  // 12 monthly amounts [Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec, Jan, Feb, Mar]
  monthlyAmounts: {
    type: [Number],
    default: () => Array(12).fill(0),
    validate: { validator: (v) => v.length === 12, message: 'monthlyAmounts must have 12 values' },
  },
}, { _id: false });

const budgetSchema = new mongoose.Schema({
  orgId:         { type: String, index: true, default: null },
  budgetName:    { type: String, required: true, trim: true },
  financialYear: { type: String, required: true, trim: true },  // e.g. "2025-26"
  budgetPeriod:  { type: String, enum: ['Monthly', 'Quarterly', 'Yearly'], default: 'Monthly' },
  currency:      { type: String, default: 'INR' },
  isActive:      { type: Boolean, default: true, index: true },
  notes:         { type: String, default: '' },
  accountLines:  [budgetAccountLineSchema],
  companyId:     { type: String, default: 'default' },
  createdBy:     { type: String, default: 'system' },
  updatedBy:     { type: String, default: 'system' },
}, { timestamps: true });

budgetSchema.index({ financialYear: 1, isActive: 1 });
budgetSchema.index({ budgetName: 1 });

const Budget = mongoose.models.Budget || mongoose.model('Budget', budgetSchema);

// ============================================================================
// HELPERS
// ============================================================================

// Financial year months: Apr=0 … Mar=11
const FY_MONTHS = [
  { month: 3,  label: 'Apr' },
  { month: 4,  label: 'May' },
  { month: 5,  label: 'Jun' },
  { month: 6,  label: 'Jul' },
  { month: 7,  label: 'Aug' },
  { month: 8,  label: 'Sep' },
  { month: 9,  label: 'Oct' },
  { month: 10, label: 'Nov' },
  { month: 11, label: 'Dec' },
  { month: 0,  label: 'Jan' },
  { month: 1,  label: 'Feb' },
  { month: 2,  label: 'Mar' },
];

function parseFYRange(financialYear) {
  // "2025-26" → { startYear: 2025, endYear: 2026 }
  const parts = financialYear.split('-');
  const startYear = parseInt(parts[0]);
  const endYear = parts[1].length === 2
    ? parseInt(parts[0].substring(0, 2) + parts[1])
    : parseInt(parts[1]);
  return { startYear, endYear };
}

function getFYDateRange(financialYear) {
  const { startYear, endYear } = parseFYRange(financialYear);
  return {
    start: new Date(startYear, 3, 1),   // Apr 1
    end:   new Date(endYear,   2, 31),  // Mar 31
  };
}

// Pull actual amounts from AccountTransaction for each account line
async function enrichWithActuals(budget, orgId = null) {
  const { start, end } = getFYDateRange(budget.financialYear);

  const enrichedLines = await Promise.all(
    budget.accountLines.map(async (line) => {
      const actualMonthly = Array(12).fill(0);

      if (!line.accountId) {
        return {
          ...line.toObject ? line.toObject() : line,
          actualMonthly,
          totalBudgeted: line.monthlyAmounts.reduce((s, v) => s + v, 0),
          totalActual: 0,
          variance: line.monthlyAmounts.reduce((s, v) => s + v, 0),
          percentUsed: 0,
        };
      }

      // Get all transactions for this account in this FY
      const txns = await AccountTransaction.find({
        accountId: line.accountId,
        date: { $gte: start, $lte: end },
        ...(orgId ? { orgId } : {}),
      }).lean();

      // Bucket by FY month index
      txns.forEach((txn) => {
        const d = new Date(txn.date);
        const m = d.getMonth(); // 0=Jan … 11=Dec
        const fyIdx = FY_MONTHS.findIndex((fm) => fm.month === m);
        if (fyIdx >= 0) {
          // For income accounts: actual = credit - debit
          // For expense/asset accounts: actual = debit - credit
          const isIncomeType = ['Income', 'Other Income'].includes(line.accountType);
          actualMonthly[fyIdx] += isIncomeType
            ? txn.credit - txn.debit
            : txn.debit - txn.credit;
        }
      });

      const totalBudgeted = line.monthlyAmounts.reduce((s, v) => s + v, 0);
      const totalActual   = actualMonthly.reduce((s, v) => s + v, 0);
      const variance      = totalBudgeted - totalActual;
      const percentUsed   = totalBudgeted > 0 ? (totalActual / totalBudgeted) * 100 : 0;

      return {
        ...line.toObject ? line.toObject() : line,
        actualMonthly,
        totalBudgeted,
        totalActual,
        variance,
        percentUsed,
      };
    })
  );

  const totalBudgeted = enrichedLines.reduce((s, l) => s + l.totalBudgeted, 0);
  const totalActual   = enrichedLines.reduce((s, l) => s + l.totalActual,   0);
  const totalVariance = totalBudgeted - totalActual;

  return {
    ...budget.toObject ? budget.toObject() : budget,
    id: budget._id,
    accountLines: enrichedLines,
    totalBudgeted,
    totalActual,
    totalVariance,
  };
}

// ============================================================================
// ROUTES
// ============================================================================

// ── GET /stats ────────────────────────────────────────────────────────────────
router.get('/stats', authenticate, async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const [total, active, inactive, budgets] = await Promise.all([
      Budget.countDocuments(orgFilter),
      Budget.countDocuments({ ...orgFilter, isActive: true }),
      Budget.countDocuments({ ...orgFilter, isActive: false }),
      Budget.find(orgFilter, { accountLines: 1 }).lean(),
    ]);

    let totalBudgeted = 0;
    budgets.forEach((b) => {
      b.accountLines.forEach((l) => {
        totalBudgeted += (l.monthlyAmounts || []).reduce((s, v) => s + v, 0);
      });
    });

    res.json({
      success: true,
      data: { totalBudgets: total, activeBudgets: active, inactiveBudgets: inactive, totalBudgeted, totalActual: 0 },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET / (list) ──────────────────────────────────────────────────────────────
router.get('/', authenticate, async (req, res) => {
  try {
    const { isActive, financialYear, budgetPeriod, search, page = 1, limit = 20 } = req.query;

    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (isActive !== undefined && isActive !== 'null') query.isActive = isActive === 'true';
    if (financialYear && financialYear !== 'All') query.financialYear = financialYear;
    if (budgetPeriod && budgetPeriod !== 'All') query.budgetPeriod = budgetPeriod;
    if (search && search.trim()) {
      query.$or = [
        { budgetName:    { $regex: search.trim(), $options: 'i' } },
        { financialYear: { $regex: search.trim(), $options: 'i' } },
      ];
    }

    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const total = await Budget.countDocuments(query);

    const budgets = await Budget.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    // Add basic totals (no COA actuals for list — performance)
    const enriched = budgets.map((b) => {
      const obj = b.toObject();
      obj.id = obj._id;
      obj.totalBudgeted = obj.accountLines.reduce(
        (s, l) => s + (l.monthlyAmounts || []).reduce((a, v) => a + v, 0), 0
      );
      obj.totalActual  = 0;
      obj.totalVariance = obj.totalBudgeted;
      return obj;
    });

    res.json({
      success: true,
      data: {
        budgets: enriched,
        pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) },
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /:id ──────────────────────────────────────────────────────────────────
router.get('/:id', authenticate, async (req, res) => {
  try {
    const budget = await Budget.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });
    const enriched = await enrichWithActuals(budget, req.user?.orgId);
    res.json({ success: true, data: enriched });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /:id/actuals ──────────────────────────────────────────────────────────
router.get('/:id/actuals', authenticate, async (req, res) => {
  try {
    const budget = await Budget.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });
    const enriched = await enrichWithActuals(budget, req.user?.orgId);
    res.json({ success: true, data: enriched });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST / (create) ───────────────────────────────────────────────────────────
router.post('/', authenticate, async (req, res) => {
  try {
    const data = req.body;

    // Validate account lines: ensure each has 12 monthly amounts
    if (data.accountLines) {
      data.accountLines = data.accountLines.map((line) => ({
        ...line,
        monthlyAmounts: Array.isArray(line.monthlyAmounts) && line.monthlyAmounts.length === 12
          ? line.monthlyAmounts.map(Number)
          : Array(12).fill(0),
      }));
    }

    // Resolve accountIds by name if not provided
    if (data.accountLines) {
      for (const line of data.accountLines) {
        if (!line.accountId && line.accountName) {
          const acc = await ChartOfAccount.findOne({
            accountName: { $regex: `^${line.accountName}$`, $options: 'i' },
            ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
          }).lean();
          if (acc) {
            line.accountId   = acc._id;
            line.accountType = acc.accountType;
          }
        }
      }
    }

    const budget = await Budget.create({
      ...data,
      orgId: req.user?.orgId || null,
      createdBy: req.user?.email || 'system',
    });

    console.log(`✅ Budget created: ${budget.budgetName} (${budget.financialYear})`);
    const enriched = await enrichWithActuals(budget, req.user?.orgId);
    res.status(201).json({ success: true, message: 'Budget created successfully', data: enriched });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── PUT /:id (update) ─────────────────────────────────────────────────────────
router.put('/:id', authenticate, async (req, res) => {
  try {
    const budget = await Budget.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });

    const allowed = ['budgetName', 'financialYear', 'budgetPeriod', 'currency', 'isActive', 'notes', 'accountLines'];
    allowed.forEach((k) => {
      if (req.body[k] !== undefined) budget[k] = req.body[k];
    });

    // Normalize monthly amounts
    if (budget.accountLines) {
      budget.accountLines = budget.accountLines.map((line) => ({
        ...line.toObject ? line.toObject() : line,
        monthlyAmounts: Array.isArray(line.monthlyAmounts) && line.monthlyAmounts.length === 12
          ? line.monthlyAmounts.map(Number)
          : Array(12).fill(0),
      }));
    }

    budget.updatedBy = req.user?.email || 'system';
    await budget.save();

    const enriched = await enrichWithActuals(budget, req.user?.orgId);
    res.json({ success: true, message: 'Budget updated successfully', data: enriched });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── PATCH /:id/toggle-active ──────────────────────────────────────────────────
router.patch('/:id/toggle-active', authenticate, async (req, res) => {
  try {
    const budget = await Budget.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });

    budget.isActive  = req.body.isActive ?? !budget.isActive;
    budget.updatedBy = req.user?.email || 'system';
    await budget.save();

    res.json({ success: true, message: `Budget ${budget.isActive ? 'activated' : 'deactivated'}`, data: { ...budget.toObject(), id: budget._id } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST /:id/clone ────────────────────────────────────────────────────────────
router.post('/:id/clone', authenticate, async (req, res) => {
  try {
    const original = await Budget.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!original) return res.status(404).json({ success: false, message: 'Budget not found' });

    const { budgetName, financialYear } = req.body;

    const cloned = await Budget.create({
      budgetName:    budgetName    || `${original.budgetName} (Copy)`,
      financialYear: financialYear || original.financialYear,
      budgetPeriod:  original.budgetPeriod,
      currency:      original.currency,
      notes:         original.notes,
      isActive:      true,
      accountLines:  original.accountLines.map((l) => ({ ...l, _id: undefined })),
      orgId:         req.user?.orgId || null,
      createdBy:     req.user?.email || 'system',
    });

    const enriched = await enrichWithActuals(cloned, req.user?.orgId);
    res.status(201).json({ success: true, message: 'Budget cloned successfully', data: enriched });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── DELETE /:id ────────────────────────────────────────────────────────────────
router.delete('/:id', authenticate, async (req, res) => {
  try {
    const budget = await Budget.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });
    await budget.deleteOne();
    res.json({ success: true, message: 'Budget deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST /import (bulk import) ─────────────────────────────────────────────────
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

router.post('/import', authenticate, upload.single('file'), async (req, res) => {
  try {
    const budgetsData = JSON.parse(req.body.budgets || '[]');
    let successCount = 0;
    let failedCount  = 0;
    const errors     = [];

    for (let i = 0; i < budgetsData.length; i++) {
      const item = budgetsData[i];
      try {
        // Resolve account
        if (!item.accountId && item.accountName) {
          const acc = await ChartOfAccount.findOne({
            accountName: { $regex: `^${item.accountName}$`, $options: 'i' },
            ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
          }).lean();
          if (acc) { item.accountId = acc._id; item.accountType = acc.accountType; }
        }

        // Find or create budget
        let budget = await Budget.findOne({
          budgetName: item.budgetName,
          financialYear: item.financialYear,
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        });
        if (!budget) {
          budget = await Budget.create({
            budgetName:    item.budgetName,
            financialYear: item.financialYear,
            budgetPeriod:  item.budgetPeriod || 'Monthly',
            currency:      item.currency || 'INR',
            notes:         item.notes || '',
            isActive:      true,
            accountLines:  [],
            orgId:         req.user?.orgId || null,
            createdBy:     req.user?.email || 'system',
          });
        }

        // Add account line
        const monthlyAmounts = Array.isArray(item.monthlyAmounts) && item.monthlyAmounts.length === 12
          ? item.monthlyAmounts.map(Number)
          : Array(12).fill(Number(item.annualAmount || 0) / 12);

        budget.accountLines.push({
          accountId:     item.accountId   || null,
          accountName:   item.accountName || '',
          accountType:   item.accountType || 'Expense',
          monthlyAmounts,
        });
        await budget.save();
        successCount++;
      } catch (err) {
        errors.push(`Row ${i + 2}: ${err.message}`);
        failedCount++;
      }
    }

    res.json({
      success: true,
      message: `Imported ${successCount} account lines`,
      data: { totalProcessed: budgetsData.length, successCount, failedCount, errors },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
module.exports.Budget = Budget;