// ============================================================================
// BUDGETS — BACKEND
// ============================================================================
// File: backend/routes/budgets.js
// Register in app.js: app.use('/api/budgets', require('./routes/budgets'));
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');

// ── COA dependency ────────────────────────────────────────────────────────────
const { ChartOfAccount, AccountTransaction } = require('./chart_of_accounts');

// ── Auth middleware ────────────────────────────────────────────────────────────
const { verifyFinanceJWT } = require('../middleware/finance_jwt');
const authenticate = verifyFinanceJWT;

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
  accountType: { type: String, required: true, trim: true },
  // 12 monthly amounts [Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec, Jan, Feb, Mar]
  monthlyAmounts: {
    type: [Number],
    default: () => Array(12).fill(0),
    validate: { validator: (v) => v.length === 12, message: 'monthlyAmounts must have 12 values' },
  },
}, { _id: false });

const budgetSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null },
  budgetName: { type: String, required: true, trim: true },
  financialYear: { type: String, required: true, trim: true },  // e.g. "2025-26"
  budgetPeriod: { type: String, enum: ['Monthly', 'Quarterly', 'Yearly'], default: 'Monthly' },
  currency: { type: String, default: 'INR' },
  isActive: { type: Boolean, default: true, index: true },
  notes: { type: String, default: '' },
  accountLines: [budgetAccountLineSchema],
  companyId: { type: String, default: 'default' },
  createdBy: { type: String, default: 'system' },
  updatedBy: { type: String, default: 'system' },
}, { timestamps: true });

budgetSchema.index({ financialYear: 1, isActive: 1 });
budgetSchema.index({ budgetName: 1 });

const Budget = mongoose.models.Budget || mongoose.model('Budget', budgetSchema);

// ============================================================================
// HELPERS
// ============================================================================

// Financial year months: Apr=0 … Mar=11
const FY_MONTHS = [
  { month: 3, label: 'Apr' },
  { month: 4, label: 'May' },
  { month: 5, label: 'Jun' },
  { month: 6, label: 'Jul' },
  { month: 7, label: 'Aug' },
  { month: 8, label: 'Sep' },
  { month: 9, label: 'Oct' },
  { month: 10, label: 'Nov' },
  { month: 11, label: 'Dec' },
  { month: 0, label: 'Jan' },
  { month: 1, label: 'Feb' },
  { month: 2, label: 'Mar' },
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
    end: new Date(endYear, 2, 31),  // Mar 31
  };
}

// Pull actual amounts from AccountTransaction for each account line
async function enrichWithActuals(budget, orgId = null, filterStartDate = null, filterEndDate = null) {
  let { start, end } = getFYDateRange(budget.financialYear);
  const { startYear, endYear } = parseFYRange(budget.financialYear);

  if (filterStartDate) {
    const fs = new Date(filterStartDate);
    fs.setHours(0, 0, 0, 0);
    start = new Date(Math.max(start.getTime(), fs.getTime()));
  }
  if (filterEndDate) {
    const fe = new Date(filterEndDate);
    fe.setHours(23, 59, 59, 999);
    end = new Date(Math.min(end.getTime(), fe.getTime()));
  }

  const enrichedLines = await Promise.all(
    budget.accountLines.map(async (line) => {
      const actualMonthly = Array(12).fill(0);
      let calculatedBudgeted = 0;

      // Calculate prorated budget based on overlap with each FY month
      for (let i = 0; i < 12; i++) {
        const fm = FY_MONTHS[i];
        const monthYear = fm.month >= 3 ? startYear : endYear;
        const monthStart = new Date(monthYear, fm.month, 1);
        const monthEnd = new Date(monthYear, fm.month + 1, 0, 23, 59, 59, 999);

        const overlapStart = new Date(Math.max(start.getTime(), monthStart.getTime()));
        const overlapEnd = new Date(Math.min(end.getTime(), monthEnd.getTime()));

        if (overlapStart <= overlapEnd) {
          const overlapDays = (overlapEnd.getTime() - overlapStart.getTime() + 1) / (1000 * 60 * 60 * 24);
          const daysInMonth = monthEnd.getDate();
          const fraction = Math.min(1, Math.max(0, overlapDays / daysInMonth));
          calculatedBudgeted += (line.monthlyAmounts[i] || 0) * fraction;
        }
      }

      if (!line.accountId) {
        return {
          ...line.toObject ? line.toObject() : line,
          actualMonthly,
          totalBudgeted: calculatedBudgeted,
          totalActual: 0,
          variance: calculatedBudgeted,
          percentUsed: 0,
        };
      }

      // Get all transactions for this account in this filtered date range
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
          const isIncomeType = ['Income', 'Other Income'].includes(line.accountType);
          actualMonthly[fyIdx] += isIncomeType
            ? txn.credit - txn.debit
            : txn.debit - txn.credit;
        }
      });

      const totalActual = actualMonthly.reduce((s, v) => s + v, 0);
      const variance = calculatedBudgeted - totalActual;
      const percentUsed = calculatedBudgeted > 0 ? (totalActual / calculatedBudgeted) * 100 : 0;

      return {
        ...line.toObject ? line.toObject() : line,
        actualMonthly,
        totalBudgeted: calculatedBudgeted,
        totalActual,
        variance,
        percentUsed,
      };
    })
  );

  const totalBudgeted = enrichedLines.reduce((s, l) => s + l.totalBudgeted, 0);
  const totalActual = enrichedLines.reduce((s, l) => s + l.totalActual, 0);
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
    const scopedFilter = {};
    if (req.user?.orgId) {
      scopedFilter.$or = [{ orgId: req.user.orgId }, { orgId: null }];
    }

    if (req.branchFilter && Object.keys(req.branchFilter).length > 0) {
      const branchIds = req.branchIds || [];
      if (scopedFilter.$or) {
        scopedFilter.$and = [{ $or: scopedFilter.$or }, { $or: [{ branchId: { $in: branchIds } }, { branchId: null }] }];
        delete scopedFilter.$or;
      } else {
        scopedFilter.$or = [{ branchId: { $in: branchIds } }, { branchId: null }];
      }
    }

    const [total, active, inactive, budgets] = await Promise.all([
      Budget.countDocuments(scopedFilter),
      Budget.countDocuments({ ...scopedFilter, isActive: true }),
      Budget.countDocuments({ ...scopedFilter, isActive: false }),
      Budget.find(scopedFilter, { accountLines: 1 }).lean(),
    ]);

    let totalBudgeted = 0;
    let totalActual = 0;

    // We can use enrichWithActuals to get the true total actuals
    const enrichedBudgets = await Promise.all(budgets.map(b => enrichWithActuals(b, req.user?.orgId)));
    enrichedBudgets.forEach((b) => {
      totalBudgeted += b.totalBudgeted;
      totalActual += b.totalActual;
    });

    res.json({
      success: true,
      data: { totalBudgets: total, activeBudgets: active, inactiveBudgets: inactive, totalBudgeted, totalActual },
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

    // Support treating branchId: null as global across branches
    if (req.branchFilter && Object.keys(req.branchFilter).length > 0) {
      const branchIds = req.branchIds || [];
      query.$or = [{ branchId: { $in: branchIds } }, { branchId: null }];
    }
    if (isActive !== undefined && isActive !== 'null') query.isActive = isActive === 'true';
    if (financialYear && financialYear !== 'All') query.financialYear = financialYear;
    if (budgetPeriod && budgetPeriod !== 'All') query.budgetPeriod = budgetPeriod;
    if (search && search.trim()) {
      query.$or = [
        { budgetName: { $regex: search.trim(), $options: 'i' } },
        { financialYear: { $regex: search.trim(), $options: 'i' } },
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const total = await Budget.countDocuments(query);

    const budgets = await Budget.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    // Fetch actuals for the list view to ensure dashboard numbers are accurate
    const enriched = await Promise.all(budgets.map(async (b) => {
      const e = await enrichWithActuals(b, req.user?.orgId);
      e.id = e._id;
      return e;
    }));

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
    const { startDate, endDate } = req.query;
    const budget = await Budget.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });
    const enriched = await enrichWithActuals(budget, req.user?.orgId, startDate, endDate);
    res.json({ success: true, data: enriched });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /:id/actuals ──────────────────────────────────────────────────────────
router.get('/:id/actuals', authenticate, async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    const budget = await Budget.findOne({
      _id: req.params.id,
      ...req.orgFilter,
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });
    const enriched = await enrichWithActuals(budget, req.user?.orgId, startDate, endDate);
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
            ...req.orgFilter,
          }).lean();
          if (acc) {
            line.accountId = acc._id;
            line.accountType = acc.accountType;
          }
        }
      }
    }

    const budget = await Budget.create({
      ...data,
      orgId: req.user?.orgId || null,
      branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
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
      ...req.orgFilter,
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
      ...req.orgFilter,
    });
    if (!budget) return res.status(404).json({ success: false, message: 'Budget not found' });

    budget.isActive = req.body.isActive ?? !budget.isActive;
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
      ...req.orgFilter,
    }).lean();
    if (!original) return res.status(404).json({ success: false, message: 'Budget not found' });

    const { budgetName, financialYear } = req.body;

    const cloned = await Budget.create({
      budgetName: budgetName || `${original.budgetName} (Copy)`,
      financialYear: financialYear || original.financialYear,
      budgetPeriod: original.budgetPeriod,
      currency: original.currency,
      notes: original.notes,
      isActive: true,
      accountLines: original.accountLines.map((l) => ({ ...l, _id: undefined })),
      orgId: req.user?.orgId || null,
      branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
      createdBy: req.user?.email || 'system',
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
      ...req.orgFilter,
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
    let failedCount = 0;
    const errors = [];

    for (let i = 0; i < budgetsData.length; i++) {
      const item = budgetsData[i];
      try {
        // Resolve account
        if (!item.accountId && item.accountName) {
          const acc = await ChartOfAccount.findOne({
            accountName: { $regex: `^${item.accountName}$`, $options: 'i' },
            ...req.orgFilter,
          }).lean();
          if (acc) { item.accountId = acc._id; item.accountType = acc.accountType; }
        }

        // Find or create budget
        let budget = await Budget.findOne({
          budgetName: item.budgetName,
          financialYear: item.financialYear,
          ...req.orgFilter,
        });
        if (!budget) {
          budget = await Budget.create({
            budgetName: item.budgetName,
            financialYear: item.financialYear,
            budgetPeriod: item.budgetPeriod || 'Monthly',
            currency: item.currency || 'INR',
            notes: item.notes || '',
            isActive: true,
            accountLines: [],
            orgId: req.user?.orgId || null,
            branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
            createdBy: req.user?.email || 'system',
          });
        }

        // Add account line
        const monthlyAmounts = Array.isArray(item.monthlyAmounts) && item.monthlyAmounts.length === 12
          ? item.monthlyAmounts.map(Number)
          : Array(12).fill(Number(item.annualAmount || 0) / 12);

        budget.accountLines.push({
          accountId: item.accountId || null,
          accountName: item.accountName || '',
          accountType: item.accountType || 'Expense',
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

// ============================================================================
// BUDGET MONITOR OBSERVER
// ============================================================================

async function checkBudgetExceedance(accountId, date, orgId = null, createdByEmail = 'system') {
  try {
    const d = new Date(date);
    const m = d.getMonth();
    const fyIdx = FY_MONTHS.findIndex(fm => fm.month === m);
    if (fyIdx === -1) return;

    const budgets = await Budget.find({
      isActive: true,
      'accountLines.accountId': accountId,
      ...(orgId ? { orgId } : {})
    });

    for (const budget of budgets) {
      const { start, end } = getFYDateRange(budget.financialYear);
      if (d < start || d > end) continue;

      const line = budget.accountLines.find(l => l.accountId && l.accountId.toString() === accountId.toString());
      if (!line) continue;

      const budgetedAmount = line.monthlyAmounts[fyIdx] || 0;
      if (budgetedAmount <= 0) continue;

      const monthYear = m >= 3 ? parseFYRange(budget.financialYear).startYear : parseFYRange(budget.financialYear).endYear;
      const monthStart = new Date(monthYear, m, 1);
      const monthEnd = new Date(monthYear, m + 1, 0, 23, 59, 59, 999);

      const txns = await mongoose.models.AccountTransaction.find({
        accountId: line.accountId,
        date: { $gte: monthStart, $lte: monthEnd },
        ...(orgId ? { orgId } : {})
      }).lean();

      let actualMonthly = 0;
      txns.forEach(txn => {
        const isIncomeType = ['Income', 'Other Income'].includes(line.accountType);
        actualMonthly += isIncomeType ? txn.credit - txn.debit : txn.debit - txn.credit;
      });

      if (actualMonthly >= budgetedAmount * 0.8) {
        const db = mongoose.connection.db;
        const creatorEmailToUse = (budget.createdBy || 'system').toLowerCase();
        let creator = await db.collection('billing_users').findOne({ email: creatorEmailToUse, 'organizations.orgId': orgId });

        // Fallback: If budget creator not found or is system, assign to the organization owner/admin
        if (!creator) {
          creator = await db.collection('billing_users').findOne({
            'organizations.orgId': orgId,
            role: { $in: ['owner', 'admin'] }
          });
        }

        if (!creator) {
          console.error(`[BUDGET OBSERVER] No valid user found to assign ticket in org: ${orgId}`);
          return; // Can't assign ticket without a user
        }

        const creatorId = creator._id;

        const isBreach = actualMonthly >= budgetedAmount;
        const subjectPrefix = isBreach ? 'Budget Exceeded' : 'Budget Warning';
        const fullSubject = `${subjectPrefix}: ${line.accountName}`;

        const existingTicket = await db.collection('tickets').findOne({
          assigned_email: creator.email,
          subject: fullSubject,
          status: { $in: ['Open', 'In Progress'] }
        });

        if (!existingTicket) {
          const allTickets = await db.collection('tickets').find({ ticket_number: { $regex: '^TICKET\\d' } }, { projection: { ticket_number: 1 } }).toArray();
          let maxId = 0;
          for (const t of allTickets) {
            const n = parseInt((t.ticket_number || '').slice(6), 10);
            if (!isNaN(n) && n > maxId) maxId = n;
          }
          const ticketNumberStr = `TICKET${String(maxId + 1).padStart(6, '0')}`;

          const variance = (budgetedAmount - actualMonthly).toFixed(2);
          const lineCount = budget.accountLines ? budget.accountLines.length : 0;
          const statusStr = budget.isActive ? 'Active' : 'Inactive';
          const notesStr = budget.notes && budget.notes.trim() !== '' ? budget.notes : 'None';

          const message = `Budget "${budget.budgetName}" requires attention.

Budget Details:
• Budget Name    : ${budget.budgetName}
• Financial Year : ${budget.financialYear}
• Period         : ${budget.budgetPeriod}
• Status         : ${statusStr}
• Total Budgeted : ₹${budgetedAmount.toFixed(2)}
• Total Actual   : ₹${actualMonthly.toFixed(2)}
• Variance       : ₹${variance}
• Accounts       : ${lineCount} line(s)
• Notes          : ${notesStr}

Please review and take necessary action.`;

          await db.collection('tickets').insertOne({
            ticket_number: ticketNumberStr,
            name: 'Budget Monitor System',
            creator_email: 'system@abra-travels.com',
            assigned_email: creator.email,
            subject: fullSubject,
            message: message,
            priority: isBreach ? 'High' : 'Medium',
            timeline: 1440,
            deadline: new Date(Date.now() + 1440 * 60000),
            status: 'Open',
            attachment: null,
            assigned_to: creatorId,
            created_by: null,
            org_id: orgId,
            branch_id: budget.branchId || null,
            source: 'budget_monitor',
            created_at: new Date(),
            updated_at: new Date()
          });
          console.log(`🎫 Auto-Ticket created for ${subjectPrefix}: ${line.accountName}`);
        }
      }
    }
  } catch (err) {
    console.error('Budget Monitor Error:', err);
  }
}

module.exports = router;
module.exports.Budget = Budget;
module.exports.checkBudgetExceedance = checkBudgetExceedance;