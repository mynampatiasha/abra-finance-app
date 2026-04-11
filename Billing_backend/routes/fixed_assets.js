// ============================================================================
// FIXED ASSETS — BACKEND
// ============================================================================
// File: backend/routes/fixed_assets.js
// Register in index.js:
//   app.use('/api/finance/fixed-assets', verifyFinanceJWT, require('./routes/fixed_assets'));
// ============================================================================

const express   = require('express');
const router    = express.Router();
const mongoose  = require('mongoose');
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');
const { generateNumber } = require('../utils/numberGenerator');

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const depreciationEntrySchema = new mongoose.Schema({
  period:       { type: String },          // e.g. "2025-01"
  date:         { type: Date },
  amount:       { type: Number, default: 0 },
  bookValue:    { type: Number, default: 0 }, // value after this depreciation
  journalPosted:{ type: Boolean, default: false },
}, { _id: false });

const fixedAssetSchema = new mongoose.Schema({
  orgId:         { type: String, index: true, default: null },
  assetNumber:   { type: String, default: null },           // e.g. FA000001

  // Basic Info
  assetName:     { type: String, required: true, trim: true },
  assetType:     {
    type: String,
    enum: ['IT Equipment', 'Furniture & Fixtures', 'Machinery', 'Vehicle',
           'Building', 'Land', 'Office Equipment', 'Other'],
    default: 'IT Equipment',
  },
  description:   { type: String, default: null },
  serialNumber:  { type: String, default: null },
  vendor:        { type: String, default: null },

  // Purchase
  purchaseDate:  { type: String, required: true },   // YYYY-MM-DD
  assetCost:     { type: Number, required: true },
  paidThrough:   { type: String, default: null },    // bank/cash account name or ID

  // COA Accounts
  assetAccountName:       { type: String, default: null }, // Fixed Asset COA account name
  depreciationAccountName:{ type: String, default: null }, // Accumulated Depreciation (contra asset)
  expenseAccountName:     { type: String, default: null }, // Depreciation Expense

  // Depreciation Settings
  depreciationMethod: {
    type: String,
    enum: ['straight_line', 'declining_balance', 'none'],
    default: 'straight_line',
  },
  depreciationFrequency: {
    type: String,
    enum: ['monthly', 'yearly'],
    default: 'yearly',
  },
  usefulLifeMonths:  { type: Number, default: 60 },   // e.g. 60 = 5 years
  salvageValue:      { type: Number, default: 0 },
  depreciationRate:  { type: Number, default: null },  // % for declining balance

  // Computed
  currentValue:      { type: Number, default: 0 },    // book value today
  totalDepreciation: { type: Number, default: 0 },    // accumulated depreciation so far
  depreciationStartDate: { type: String, default: null }, // YYYY-MM-DD

  // Status
  status: {
    type: String,
    enum: ['Draft', 'Active', 'Fully Depreciated', 'Disposed', 'Written Off'],
    default: 'Draft',
  },

  // Disposal
  disposalDate:   { type: String, default: null },
  disposalAmount: { type: Number, default: 0 },
  disposalReason: { type: String, default: null },

  // Depreciation Schedule (computed entries stored for reference)
  depreciationSchedule: [depreciationEntrySchema],

  // Linked purchase (if recorded via bill/expense)
  sourceType:   { type: String, enum: ['Manual', 'Expense', 'Bill'], default: 'Manual' },
  sourceId:     { type: mongoose.Schema.Types.ObjectId, default: null },

  notes: { type: String, default: null },
}, { timestamps: true });

fixedAssetSchema.index({ assetNumber: 1 });
fixedAssetSchema.index({ status: 1 });
fixedAssetSchema.index({ purchaseDate: -1 });

const FixedAsset = mongoose.models.FixedAsset
  || mongoose.model('FixedAsset', fixedAssetSchema);

// Reference PaymentAccount for balance deductions
const PaymentAccount = mongoose.models.PaymentAccount
  || mongoose.model('PaymentAccount', new mongoose.Schema({ currentBalance: { type: Number, default: 0 } }, { strict: false }));

// ============================================================================
// HELPERS
// ============================================================================

async function generateAssetNumber(orgId = null) {
  return generateNumber(FixedAsset, 'assetNumber', 'FA', orgId);
}

// Get or auto-create a Fixed Asset type COA account
async function getOrCreateCOAAccount(accountName, accountType, orgId = null) {
  try {
    let acc = await ChartOfAccount.findOne({
      accountName: { $regex: `^${accountName}$`, $options: 'i' },
      ...(orgId ? { orgId } : {}),
    }).select('_id accountType').lean();

    if (acc) return acc._id;

    // Auto-create
    const newAcc = await ChartOfAccount.create({
      accountName,
      accountType,
      accountCode:    `FA-${Date.now().toString().slice(-6)}`,
      orgId,
      accountSubType: accountType,
      description:    `${accountName}`,
      isSystemAccount: false,
      isActive:       true,
      openingBalance: 0,
      currentBalance: 0,
      currency:       'INR',
    });
    console.log(`✅ Auto-created COA account: "${accountName}" [${accountType}]`);
    return newAcc._id;
  } catch (e) {
    console.error('COA lookup/create error:', e.message);
    return null;
  }
}

// Compute straight-line annual depreciation
function calcStraightLineDepreciation(cost, salvage, usefulLifeMonths, frequency) {
  const depreciableAmount = cost - salvage;
  if (frequency === 'monthly') {
    return depreciableAmount / usefulLifeMonths;
  }
  return depreciableAmount / (usefulLifeMonths / 12);
}

// Build full depreciation schedule
function buildDepreciationSchedule(asset) {
  const {
    assetCost, salvageValue, usefulLifeMonths,
    depreciationMethod, depreciationFrequency,
    depreciationRate, depreciationStartDate,
  } = asset;

  const schedule = [];
  if (depreciationMethod === 'none') return schedule;

  const startDate = new Date(depreciationStartDate || asset.purchaseDate);
  let bookValue   = assetCost;
  const salvage   = salvageValue || 0;
  const steps     = depreciationFrequency === 'monthly' ? usefulLifeMonths : Math.ceil(usefulLifeMonths / 12);

  for (let i = 0; i < steps; i++) {
    if (bookValue <= salvage) break;

    let periodAmount = 0;
    if (depreciationMethod === 'straight_line') {
      periodAmount = calcStraightLineDepreciation(assetCost, salvage, usefulLifeMonths, depreciationFrequency);
    } else if (depreciationMethod === 'declining_balance') {
      const rate = (depreciationRate || 20) / 100;
      periodAmount = depreciationFrequency === 'monthly'
        ? bookValue * (rate / 12)
        : bookValue * rate;
    }

    // Don't depreciate below salvage
    if (bookValue - periodAmount < salvage) {
      periodAmount = bookValue - salvage;
    }

    const periodDate = new Date(startDate);
    if (depreciationFrequency === 'monthly') {
      periodDate.setMonth(periodDate.getMonth() + i);
    } else {
      periodDate.setFullYear(periodDate.getFullYear() + i);
    }

    bookValue -= periodAmount;

    const period = depreciationFrequency === 'monthly'
      ? `${periodDate.getFullYear()}-${String(periodDate.getMonth() + 1).padStart(2, '0')}`
      : `${periodDate.getFullYear()}`;

    schedule.push({
      period,
      date:          periodDate,
      amount:        Math.round(periodAmount * 100) / 100,
      bookValue:     Math.round(bookValue * 100) / 100,
      journalPosted: false,
    });
  }

  return schedule;
}

// Compute current book value based on today's date
function computeCurrentBookValue(asset) {
  if (!asset.depreciationSchedule || asset.depreciationSchedule.length === 0) {
    return asset.assetCost;
  }
  const today = new Date();
  let totalDep = 0;
  for (const entry of asset.depreciationSchedule) {
    if (new Date(entry.date) <= today) {
      totalDep += entry.amount;
    }
  }
  return Math.max(asset.assetCost - totalDep, asset.salvageValue || 0);
}

// Deduct balance from payment account
async function deductBalance(paidThrough, amount) {
  try {
    if (!paidThrough || !amount) return;
    let updated = false;
    if (mongoose.Types.ObjectId.isValid(paidThrough)) {
      const r = await PaymentAccount.findByIdAndUpdate(
        paidThrough,
        { $inc: { currentBalance: -amount }, $set: { updatedAt: new Date() } },
        { new: true }
      );
      if (r) { updated = true; console.log(`✅ Balance deducted from ID ${paidThrough}: -₹${amount}`); }
    }
    if (!updated) {
      const r = await PaymentAccount.findOneAndUpdate(
        { accountName: paidThrough },
        { $inc: { currentBalance: -amount }, $set: { updatedAt: new Date() } },
        { new: true }
      );
      if (r) console.log(`✅ Balance deducted from "${paidThrough}": -₹${amount}`);
      else    console.warn(`⚠️ Could not find account "${paidThrough}" to deduct ₹${amount}`);
    }
  } catch (e) {
    console.error('Balance deduction error:', e.message);
  }
}

// Restore balance to payment account
async function restoreBalance(paidThrough, amount) {
  try {
    if (!paidThrough || !amount) return;
    let updated = false;
    if (mongoose.Types.ObjectId.isValid(paidThrough)) {
      const r = await PaymentAccount.findByIdAndUpdate(
        paidThrough,
        { $inc: { currentBalance: amount }, $set: { updatedAt: new Date() } },
        { new: true }
      );
      if (r) { updated = true; console.log(`✅ Balance restored to ID ${paidThrough}: +₹${amount}`); }
    }
    if (!updated) {
      const r = await PaymentAccount.findOneAndUpdate(
        { accountName: paidThrough },
        { $inc: { currentBalance: amount }, $set: { updatedAt: new Date() } },
        { new: true }
      );
      if (r) console.log(`✅ Balance restored to "${paidThrough}": +₹${amount}`);
    }
  } catch (e) {
    console.error('Balance restore error:', e.message);
  }
}

// ============================================================================
// GET ALL FIXED ASSETS
// ============================================================================

router.get('/', async (req, res) => {
  try {
    const { status, assetType, search } = req.query;
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (status)          query.status = status;
    if (assetType)       query.assetType = assetType;
    if (search)          query.assetName = { $regex: search, $options: 'i' };

    const assets = await FixedAsset.find(query).sort({ createdAt: -1 });

    // Update current book values before returning
    const enriched = assets.map(a => {
      const currentValue = computeCurrentBookValue(a);
      const totalDep     = a.assetCost - currentValue;
      return {
        ...a.toObject(),
        currentValue,
        totalDepreciation: Math.max(0, totalDep),
      };
    });

    res.json({ success: true, data: enriched, total: enriched.length });
  } catch (e) {
    console.error('❌ Error fetching fixed assets:', e);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// GET STATS SUMMARY
// ============================================================================

router.get('/stats/summary', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const assets    = await FixedAsset.find(orgFilter);

    const totalAssets     = assets.length;
    const totalCost       = assets.reduce((s, a) => s + a.assetCost, 0);
    const totalCurrentVal = assets.reduce((s, a) => s + computeCurrentBookValue(a), 0);
    const totalDepreciated= totalCost - totalCurrentVal;

    const byStatus = assets.reduce((acc, a) => {
      acc[a.status] = (acc[a.status] || 0) + 1;
      return acc;
    }, {});

    const byType = assets.reduce((acc, a) => {
      acc[a.assetType] = (acc[a.assetType] || 0) + 1;
      return acc;
    }, {});

    res.json({
      success: true,
      data: { totalAssets, totalCost, totalCurrentVal, totalDepreciated, byStatus, byType },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// GET SINGLE FIXED ASSET
// ============================================================================

router.get('/:id', async (req, res) => {
  try {
    const asset = await FixedAsset.findOne({
      _id:  req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!asset) return res.status(404).json({ success: false, message: 'Asset not found' });

    const currentValue    = computeCurrentBookValue(asset);
    const totalDepreciation = Math.max(0, asset.assetCost - currentValue);

    res.json({ success: true, data: { ...asset.toObject(), currentValue, totalDepreciation } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// POST CREATE FIXED ASSET
// ============================================================================

router.post('/', async (req, res) => {
  try {
    const {
      assetName, assetType, description, serialNumber, vendor,
      purchaseDate, assetCost, paidThrough,
      assetAccountName, depreciationAccountName, expenseAccountName,
      depreciationMethod, depreciationFrequency, usefulLifeMonths,
      salvageValue, depreciationRate, depreciationStartDate,
      notes, sourceType, sourceId,
    } = req.body;

    // Validation
    const errors = [];
    if (!assetName)    errors.push('Asset name is required');
    if (!purchaseDate) errors.push('Purchase date is required');
    if (!assetCost || isNaN(parseFloat(assetCost)) || parseFloat(assetCost) <= 0)
      errors.push('Asset cost must be a positive number');

    if (errors.length > 0) {
      return res.status(400).json({ success: false, message: 'Validation failed', errors });
    }

    const orgId       = req.user?.orgId || null;
    const costValue   = parseFloat(assetCost);
    const salvage     = parseFloat(salvageValue || 0);
    const lifeMonths  = parseInt(usefulLifeMonths || 60);
    const method      = depreciationMethod || 'straight_line';
    const frequency   = depreciationFrequency || 'yearly';
    const startDate   = depreciationStartDate || purchaseDate;

    // Default COA account names
    const assetAccName = assetAccountName || `${assetType || 'Fixed Asset'} - ${assetName}`;
    const depAccName   = depreciationAccountName || `Accumulated Depreciation - ${assetName}`;
    const expAccName   = expenseAccountName || 'Depreciation Expense';

    // Build depreciation schedule
    const tempAsset = {
      assetCost: costValue, salvageValue: salvage,
      usefulLifeMonths: lifeMonths, depreciationMethod: method,
      depreciationFrequency: frequency, depreciationRate: parseFloat(depreciationRate || 20),
      depreciationStartDate: startDate, purchaseDate,
    };
    const schedule = buildDepreciationSchedule(tempAsset);

    const newAsset = new FixedAsset({
      orgId,
      assetNumber:            await generateAssetNumber(orgId),
      assetName,
      assetType:              assetType || 'IT Equipment',
      description:            description || null,
      serialNumber:           serialNumber || null,
      vendor:                 vendor || null,
      purchaseDate,
      assetCost:              costValue,
      paidThrough:            paidThrough || null,
      assetAccountName:       assetAccName,
      depreciationAccountName:depAccName,
      expenseAccountName:     expAccName,
      depreciationMethod:     method,
      depreciationFrequency:  frequency,
      usefulLifeMonths:       lifeMonths,
      salvageValue:           salvage,
      depreciationRate:       parseFloat(depreciationRate || 20),
      depreciationStartDate:  startDate,
      currentValue:           costValue,  // full cost at purchase
      totalDepreciation:      0,
      depreciationSchedule:   schedule,
      status:                 'Draft',
      notes:                  notes || null,
      sourceType:             sourceType || 'Manual',
      sourceId:               sourceId || null,
    });

    await newAsset.save();
    console.log(`✅ Fixed Asset created: ${newAsset.assetNumber} - ${assetName}`);

    // Deduct from payment account if paidThrough provided
    if (paidThrough) {
      await deductBalance(paidThrough, costValue);
    }

    // COA: DR Fixed Asset Account / CR Paid Through Account
    try {
      const [assetAccId, paidAccId] = await Promise.all([
        getOrCreateCOAAccount(assetAccName, 'Fixed Asset', orgId),
        paidThrough ? getOrCreateCOAAccount(
          paidThrough,
          mongoose.Types.ObjectId.isValid(paidThrough) ? null : 'Cash',
          orgId
        ) : Promise.resolve(null),
      ]);

      const txnDate   = new Date(purchaseDate);
      const desc      = `Fixed Asset Purchase - ${assetName} [${newAsset.assetNumber}]`;

      if (assetAccId) {
        await postTransactionToCOA({
          accountId: assetAccId, orgId, date: txnDate, description: desc,
          referenceType: 'Journal', referenceId: newAsset._id,
          referenceNumber: newAsset.assetNumber,
          debit: costValue, credit: 0,
        });
      }

      if (paidAccId) {
        await postTransactionToCOA({
          accountId: paidAccId, orgId, date: txnDate, description: desc,
          referenceType: 'Journal', referenceId: newAsset._id,
          referenceNumber: newAsset.assetNumber,
          debit: 0, credit: costValue,
        });
      }
    } catch (coaErr) {
      console.error('⚠️ COA posting error (asset create):', coaErr.message);
    }

    res.status(201).json({ success: true, message: 'Fixed asset created successfully', data: newAsset });
  } catch (e) {
    console.error('❌ Error creating fixed asset:', e);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// PATCH /:id/activate — Mark Draft → Active
// ============================================================================

router.patch('/:id/activate', async (req, res) => {
  try {
    const asset = await FixedAsset.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!asset) return res.status(404).json({ success: false, message: 'Asset not found' });
    if (asset.status !== 'Draft')
      return res.status(400).json({ success: false, message: 'Only Draft assets can be activated' });

    asset.status       = 'Active';
    asset.currentValue = computeCurrentBookValue(asset);
    await asset.save();

    res.json({ success: true, message: 'Asset activated successfully', data: asset });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// POST /:id/depreciate — Run depreciation for current period
// ============================================================================

router.post('/:id/depreciate', async (req, res) => {
  try {
    const asset = await FixedAsset.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!asset) return res.status(404).json({ success: false, message: 'Asset not found' });
    if (asset.status !== 'Active')
      return res.status(400).json({ success: false, message: 'Only Active assets can be depreciated' });
    if (asset.depreciationMethod === 'none')
      return res.status(400).json({ success: false, message: 'This asset has no depreciation method' });

    const orgId = req.user?.orgId || null;
    const today = new Date();

    // Find the next un-posted depreciation entry that is due
    const nextEntry = asset.depreciationSchedule.find(
      e => !e.journalPosted && new Date(e.date) <= today
    );

    if (!nextEntry) {
      return res.status(400).json({
        success: false,
        message: 'No pending depreciation entries due for today',
      });
    }

    // COA: DR Depreciation Expense / CR Accumulated Depreciation
    try {
      const [expAccId, accumAccId] = await Promise.all([
        getOrCreateCOAAccount(asset.expenseAccountName || 'Depreciation Expense', 'Expense', orgId),
        getOrCreateCOAAccount(asset.depreciationAccountName || `Accumulated Depreciation - ${asset.assetName}`, 'Fixed Asset', orgId),
      ]);

      const desc = `Depreciation - ${asset.assetName} [${asset.assetNumber}] - ${nextEntry.period}`;

      if (expAccId) await postTransactionToCOA({
        accountId: expAccId, orgId, date: nextEntry.date, description: desc,
        referenceType: 'Journal', referenceId: asset._id,
        referenceNumber: asset.assetNumber,
        debit: nextEntry.amount, credit: 0,
      });

      if (accumAccId) await postTransactionToCOA({
        accountId: accumAccId, orgId, date: nextEntry.date, description: desc,
        referenceType: 'Journal', referenceId: asset._id,
        referenceNumber: asset.assetNumber,
        debit: 0, credit: nextEntry.amount,
      });
    } catch (coaErr) {
      console.error('⚠️ COA posting error (depreciation):', coaErr.message);
    }

    // Mark entry as posted
    nextEntry.journalPosted = true;
    asset.totalDepreciation += nextEntry.amount;
    asset.currentValue       = nextEntry.bookValue;

    // Check if fully depreciated
    if (nextEntry.bookValue <= (asset.salvageValue || 0)) {
      asset.status = 'Fully Depreciated';
    }

    await asset.save();

    res.json({
      success: true,
      message: `Depreciation posted for period ${nextEntry.period}: ₹${nextEntry.amount}`,
      data: {
        period:         nextEntry.period,
        amount:         nextEntry.amount,
        bookValue:      nextEntry.bookValue,
        assetStatus:    asset.status,
      },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// POST /:id/dispose — Dispose / Sell / Write-off asset
// ============================================================================

router.post('/:id/dispose', async (req, res) => {
  try {
    const { disposalDate, disposalAmount, disposalReason } = req.body;

    const asset = await FixedAsset.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!asset) return res.status(404).json({ success: false, message: 'Asset not found' });
    if (['Disposed', 'Written Off'].includes(asset.status))
      return res.status(400).json({ success: false, message: 'Asset already disposed' });

    const orgId        = req.user?.orgId || null;
    const saleAmount   = parseFloat(disposalAmount || 0);
    const currentBV    = computeCurrentBookValue(asset);
    const gainLoss     = saleAmount - currentBV;
    const dispDate     = disposalDate ? new Date(disposalDate) : new Date();
    const reason       = disposalReason || 'Disposed';

    // COA entries for disposal:
    // DR Cash/Bank (sale amount)
    // DR Accumulated Depreciation (total depreciation so far)
    // DR Loss on Disposal (if loss) OR CR Gain on Disposal (if gain)
    // CR Fixed Asset Account (original cost)
    try {
      const [assetAccId, accumAccId] = await Promise.all([
        getOrCreateCOAAccount(asset.assetAccountName || 'Fixed Asset', 'Fixed Asset', orgId),
        getOrCreateCOAAccount(asset.depreciationAccountName || `Accumulated Depreciation - ${asset.assetName}`, 'Fixed Asset', orgId),
      ]);

      const desc = `Asset Disposal - ${asset.assetName} [${asset.assetNumber}] - ${reason}`;

      // Remove asset from books
      if (assetAccId) await postTransactionToCOA({
        accountId: assetAccId, orgId, date: dispDate, description: desc,
        referenceType: 'Journal', referenceId: asset._id,
        referenceNumber: asset.assetNumber,
        debit: 0, credit: asset.assetCost, // CR to remove asset
      });

      // Clear accumulated depreciation
      if (accumAccId && asset.totalDepreciation > 0) await postTransactionToCOA({
        accountId: accumAccId, orgId, date: dispDate, description: desc,
        referenceType: 'Journal', referenceId: asset._id,
        referenceNumber: asset.assetNumber,
        debit: asset.totalDepreciation, credit: 0, // DR to clear accumulated
      });

      // Record sale proceeds if any
      if (saleAmount > 0) {
        const cashAccId = await getOrCreateCOAAccount('Cash', 'Cash', orgId);
        if (cashAccId) await postTransactionToCOA({
          accountId: cashAccId, orgId, date: dispDate, description: `Proceeds - ${desc}`,
          referenceType: 'Journal', referenceId: asset._id,
          referenceNumber: asset.assetNumber,
          debit: saleAmount, credit: 0,
        });
      }

      // Gain or Loss
      if (gainLoss !== 0) {
        const glAccId = await getOrCreateCOAAccount(
          gainLoss > 0 ? 'Gain on Asset Disposal' : 'Loss on Asset Disposal',
          gainLoss > 0 ? 'Other Income' : 'Other Expense',
          orgId
        );
        if (glAccId) await postTransactionToCOA({
          accountId: glAccId, orgId, date: dispDate, description: desc,
          referenceType: 'Journal', referenceId: asset._id,
          referenceNumber: asset.assetNumber,
          debit:  gainLoss < 0 ? Math.abs(gainLoss) : 0,
          credit: gainLoss > 0 ? gainLoss : 0,
        });
      }
    } catch (coaErr) {
      console.error('⚠️ COA posting error (disposal):', coaErr.message);
    }

    asset.status        = reason === 'Written Off' ? 'Written Off' : 'Disposed';
    asset.disposalDate  = disposalDate || new Date().toISOString().split('T')[0];
    asset.disposalAmount= saleAmount;
    asset.disposalReason= reason;
    asset.currentValue  = 0;
    await asset.save();

    res.json({
      success: true,
      message: `Asset ${asset.status.toLowerCase()} successfully`,
      data: {
        assetNumber:   asset.assetNumber,
        originalCost:  asset.assetCost,
        bookValue:     currentBV,
        saleAmount,
        gainLoss,
        status:        asset.status,
      },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// PUT /:id — Update fixed asset (only Draft assets can be edited freely)
// ============================================================================

router.put('/:id', async (req, res) => {
  try {
    const asset = await FixedAsset.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!asset) return res.status(404).json({ success: false, message: 'Asset not found' });

    const allowedFields = [
      'assetName', 'assetType', 'description', 'serialNumber', 'vendor',
      'purchaseDate', 'assetCost', 'paidThrough',
      'assetAccountName', 'depreciationAccountName', 'expenseAccountName',
      'depreciationMethod', 'depreciationFrequency', 'usefulLifeMonths',
      'salvageValue', 'depreciationRate', 'depreciationStartDate', 'notes',
    ];

    if (asset.status !== 'Draft') {
      // Active assets: only allow notes update
      if (req.body.notes !== undefined) asset.notes = req.body.notes;
      await asset.save();
      return res.json({ success: true, message: 'Asset notes updated', data: asset });
    }

    allowedFields.forEach(k => { if (req.body[k] !== undefined) asset[k] = req.body[k]; });

    // Rebuild depreciation schedule
    asset.depreciationSchedule = buildDepreciationSchedule(asset);
    asset.currentValue         = asset.assetCost;

    await asset.save();
    res.json({ success: true, message: 'Asset updated successfully', data: asset });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// DELETE /:id — Delete draft asset only
// ============================================================================

router.delete('/:id', async (req, res) => {
  try {
    const asset = await FixedAsset.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!asset) return res.status(404).json({ success: false, message: 'Asset not found' });
    if (asset.status !== 'Draft')
      return res.status(400).json({ success: false, message: 'Only Draft assets can be deleted. Dispose active assets instead.' });

    // Restore payment account balance if applicable
    if (asset.paidThrough && asset.assetCost) {
      await restoreBalance(asset.paidThrough, asset.assetCost);
    }

    await asset.deleteOne();
    res.json({ success: true, message: 'Asset deleted successfully' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// GET /depreciation/schedule — Get depreciation schedule for all active assets
// ============================================================================

router.get('/depreciation/schedule', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const assets = await FixedAsset.find({ ...orgFilter, status: 'Active' });

    const schedule = assets.flatMap(a =>
      a.depreciationSchedule.map(e => ({
        assetNumber: a.assetNumber,
        assetName:   a.assetName,
        assetType:   a.assetType,
        period:      e.period,
        date:        e.date,
        amount:      e.amount,
        bookValue:   e.bookValue,
        posted:      e.journalPosted,
      }))
    ).sort((a, b) => new Date(a.date) - new Date(b.date));

    res.json({ success: true, data: schedule });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// TEST & HEALTH
// ============================================================================

router.get('/test',   (_, res) => res.json({ success: true, message: 'Fixed Assets API is working!' }));
router.get('/health', async (_, res) => {
  try {
    const count = await FixedAsset.countDocuments();
    res.json({ success: true, status: 'healthy', asset_count: count });
  } catch (e) {
    res.status(500).json({ success: false, status: 'unhealthy', error: e.message });
  }
});

module.exports = router;
module.exports.FixedAsset = FixedAsset;