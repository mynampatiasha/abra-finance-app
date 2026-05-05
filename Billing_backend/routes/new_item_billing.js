// ============================================================================
// ITEM BILLING BACKEND ROUTES � COMPLETE FIXED VERSION
// ============================================================================
// File: backend/routes/items.js
// Fixes applied:
//   1. verifyFinanceJWT added to ALL routes (orgId filter now works correctly)
//   2. /statistics now returns activeItems + inactiveItems + goodsCount
//   3. /search route moved ABOVE /:id (prevents ObjectId cast error)
//   4. Vendor schema REMOVED � import from vendors module to avoid OverwriteModelError
//   5. salesAccountId + purchaseAccountId resolved from COA on item create/update
//   6. Stats response shape matches Flutter: { statistics: { ... } }
// All existing functionality preserved � CRUD, bulk import, export, pagination
// ============================================================================

const express  = require('express');
const mongoose = require('mongoose');
const multer   = require('multer');
const csv      = require('csv-parser');
const fs       = require('fs');
const router   = express.Router();

const { verifyFinanceJWT }      = require('../middleware/finance_jwt');
const { ChartOfAccount }        = require('./chart_of_accounts');

// ============================================================================
// ITEM SCHEMA
// ============================================================================

const itemSchema = new mongoose.Schema({
  orgId:    { type: String, index: true, default: null },
  branchId: { type: String, index: true, default: null }, // null = visible to all branches

  name: { type: String, required: true, trim: true, index: true },
  type: { type: String, enum: ['Goods', 'Service'], required: true },
  unit: { type: String, trim: true },

  isSellable:   { type: Boolean, default: true },
  isPurchasable: { type: Boolean, default: true },

  // Selling side
  sellingPrice:     { type: Number, min: 0 },
  salesAccount:     { type: String, trim: true },        // display name
  salesAccountId:   { type: mongoose.Schema.Types.ObjectId, ref: 'ChartOfAccount', default: null },
  salesDescription: { type: String, trim: true },

  // Purchasing side
  costPrice:           { type: Number, min: 0 },
  purchaseAccount:     { type: String, trim: true },     // display name
  purchaseAccountId:   { type: mongoose.Schema.Types.ObjectId, ref: 'ChartOfAccount', default: null },
  purchaseDescription: { type: String, trim: true },

  preferredVendor: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', default: null },

  status:   { type: String, enum: ['Active', 'Inactive'], default: 'Active' },
  isActive: { type: Boolean, default: true },
}, { timestamps: true });

const Item = mongoose.models.Item || mongoose.model('Item', itemSchema);

// ============================================================================
// VALIDATION MIDDLEWARE
// ============================================================================

const validateItemData = (req, res, next) => {
  const { name, type, isSellable, isPurchasable, sellingPrice, salesAccount, costPrice, purchaseAccount } = req.body;

  if (!name || name.trim() === '') {
    return res.status(400).json({ success: false, error: 'Item name is required' });
  }
  if (!type || !['Goods', 'Service'].includes(type)) {
    return res.status(400).json({ success: false, error: 'Type must be "Goods" or "Service"' });
  }
  if (isSellable) {
    if (sellingPrice === undefined || sellingPrice === null) {
      return res.status(400).json({ success: false, error: 'Selling price is required for sellable items' });
    }
    if (typeof sellingPrice !== 'number' || sellingPrice < 0) {
      return res.status(400).json({ success: false, error: 'Selling price must be a positive number' });
    }
    if (!salesAccount || salesAccount.trim() === '') {
      return res.status(400).json({ success: false, error: 'Sales account is required for sellable items' });
    }
  }
  if (isPurchasable) {
    if (costPrice === undefined || costPrice === null) {
      return res.status(400).json({ success: false, error: 'Cost price is required for purchasable items' });
    }
    if (typeof costPrice !== 'number' || costPrice < 0) {
      return res.status(400).json({ success: false, error: 'Cost price must be a positive number' });
    }
    if (!purchaseAccount || purchaseAccount.trim() === '') {
      return res.status(400).json({ success: false, error: 'Purchase account is required for purchasable items' });
    }
  }
  next();
};

// ============================================================================
// HELPER � resolve COA account name ? ObjectId for both sales + purchase
// ============================================================================

async function resolveCOAIds(orgId, salesAccountName, purchaseAccountName) {
  const orgFilter = orgId
    ? { $or: [{ orgId }, { orgId: null }] }
    : {};

  let salesAccountId   = null;
  let purchaseAccountId = null;

  if (salesAccountName) {
    const acc = await ChartOfAccount.findOne({
      accountName: { $regex: `^${salesAccountName}$`, $options: 'i' },
      ...orgFilter,
    }).lean();
    if (acc) salesAccountId = acc._id;
  }

  if (purchaseAccountName) {
    const acc = await ChartOfAccount.findOne({
      accountName: { $regex: `^${purchaseAccountName}$`, $options: 'i' },
      ...orgFilter,
    }).lean();
    if (acc) purchaseAccountId = acc._id;
  }

  return { salesAccountId, purchaseAccountId };
}

// ============================================================================
// HEALTH CHECK
// ============================================================================

router.get('/health', (req, res) => {
  res.json({ status: 'OK', message: 'Item Billing API is running', timestamp: new Date().toISOString() });
});

// ============================================================================
// FIX 3 � /search MUST be above /:id to avoid ObjectId cast error
// ============================================================================

// GET /search � search by name / description
router.get('/search', verifyFinanceJWT, async (req, res) => {
  try {
    const { q, type, startDate, endDate, limit = 20 } = req.query;

    if (!q || q.trim() === '') {
      return res.json({ success: true, items: [], query: '' });
    }

    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;

    let orgFilter = {};
    if (orgId) {
      if (branchId) {
        orgFilter = { orgId, $or: [{ branchId }, { branchId: null }] };
      } else {
        orgFilter = { orgId };
      }
    }

    const searchOr = [
      { name:               { $regex: q.trim(), $options: 'i' } },
      { salesDescription:   { $regex: q.trim(), $options: 'i' } },
      { purchaseDescription:{ $regex: q.trim(), $options: 'i' } },
    ];

    // Combine orgFilter and search using $and to avoid $or conflicts
    const filter = {
      isActive: true,
      $and: [
        orgFilter,
        { $or: searchOr },
      ],
    };

    if (type) filter.type = type;
    if (startDate || endDate) {
      filter.createdAt = {};
      if (startDate) filter.createdAt.$gte = new Date(startDate);
      if (endDate)   { const d = new Date(endDate); d.setDate(d.getDate() + 1); filter.createdAt.$lt = d; }
    }

    const items = await Item.find(filter)
      .populate('preferredVendor', 'name')
      .limit(parseInt(limit))
      .sort({ name: 1 })
      .lean();

    res.json({ success: true, items, query: q });
  } catch (err) {
    console.error('? Error searching items:', err);
    res.status(500).json({ success: false, error: 'Failed to search items', message: err.message });
  }
});

// ============================================================================
// FIX 2 + FIX 3 � GET / with verifyFinanceJWT so orgId filter works
// ============================================================================

router.get('/', verifyFinanceJWT, async (req, res) => {
  try {
    const { type, isSellable, isPurchasable, page = 1, limit = 50, search, startDate, endDate } = req.query;

    // Branch-specific items: show items tagged to the selected branch + org-wide items (branchId=null)
    // All Branches selected: show everything for this org
    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;

    let orgFilter = {};
    if (orgId) {
      if (branchId) {
        // Single branch selected — show branch-specific items + org-wide items
        orgFilter = { orgId, $or: [{ branchId }, { branchId: null }] };
      } else {
        // All Branches — show everything for this org
        orgFilter = { orgId };
      }
    }

    const filter = { ...orgFilter, isActive: true };

    if (type)                    filter.type        = type;
    if (isSellable !== undefined) filter.isSellable  = isSellable === 'true';
    if (isPurchasable !== undefined) filter.isPurchasable = isPurchasable === 'true';

    if (search && search.trim()) {
      const searchOr = [
        { name:               { $regex: search.trim(), $options: 'i' } },
        { salesDescription:   { $regex: search.trim(), $options: 'i' } },
        { purchaseDescription:{ $regex: search.trim(), $options: 'i' } },
      ];
      if (filter.$or) {
        filter.$and = [{ $or: filter.$or }, { $or: searchOr }];
        delete filter.$or;
      } else {
        filter.$or = searchOr;
      }
    }

    if (startDate || endDate) {
      filter.createdAt = {};
      if (startDate) filter.createdAt.$gte = new Date(startDate);
      if (endDate)   { const d = new Date(endDate); d.setDate(d.getDate() + 1); filter.createdAt.$lt = d; }
    }

    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const total = await Item.countDocuments(filter);

    const items = await Item.find(filter)
      .populate('preferredVendor', 'name email phone')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .lean();

    res.json({
      success: true,
      items,
      pagination: {
        total,
        page:       parseInt(page),
        limit:      parseInt(limit),
        totalPages: Math.ceil(total / parseInt(limit)),
      },
    });
  } catch (err) {
    console.error('? Error fetching items:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch items', message: err.message });
  }
});

// ============================================================================
// FIX 1 + FIX 2 � /statistics returns ALL fields Flutter stat cards need
// ============================================================================

router.get('/statistics', verifyFinanceJWT, async (req, res) => {
  try {
    // Branch-specific items filter
    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;

    let orgFilter = {};
    if (orgId) {
      if (branchId) {
        orgFilter = { orgId, $or: [{ branchId }, { branchId: null }] };
      } else {
        orgFilter = { orgId };
      }
    }

    const base = { ...orgFilter, isActive: true };

    const [totalItems, goodsCount, servicesCount, activeItems, inactiveItems, sellableItems, purchasableItems] =
      await Promise.all([
        Item.countDocuments(base),
        Item.countDocuments({ ...base, type: 'Goods' }),
        Item.countDocuments({ ...base, type: 'Service' }),
        // FIX 1 + FIX 3: activeItems / inactiveItems now computed from status field
        Item.countDocuments({ ...base, status: 'Active' }),
        Item.countDocuments({ ...base, status: 'Inactive' }),
        Item.countDocuments({ ...base, isSellable: true }),
        Item.countDocuments({ ...base, isPurchasable: true }),
      ]);

    // FIX 1: wrapped inside statistics{} key � Flutter reads raw['statistics']
    res.json({
      success: true,
      statistics: {
        totalItems,
        goodsCount,
        servicesCount,
        activeItems,
        inactiveItems,
        sellableItems,
        purchasableItems,
      },
    });
  } catch (err) {
    console.error('? Error fetching statistics:', err);
    res.status(500).json({ success: false, error: 'Failed to fetch statistics' });
  }
});

// ============================================================================
// GET /:id � single item (MUST be below /search and /statistics)
// ============================================================================

router.get('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;
    let orgFilter = {};
    if (orgId) {
      orgFilter = branchId
        ? { orgId, $or: [{ branchId }, { branchId: null }] }
        : { orgId };
    }

    const item = await Item.findOne({ _id: req.params.id, ...orgFilter, isActive: true })
      .populate('preferredVendor', 'name email phone')
      .lean();

    if (!item) return res.status(404).json({ success: false, error: 'Item not found' });

    res.json({ success: true, item });
  } catch (err) {
    console.error('? Error fetching item:', err);
    if (err.kind === 'ObjectId') return res.status(404).json({ success: false, error: 'Item not found' });
    res.status(500).json({ success: false, error: 'Failed to fetch item' });
  }
});

// ============================================================================
// POST / � create item
// FIX 5: resolve COA IDs for salesAccount + purchaseAccount
// ============================================================================

router.post('/', verifyFinanceJWT, validateItemData, async (req, res) => {
  try {
    const orgId    = req.user?.orgId || null;
    // If exactly one branch is selected, tag the item to that branch.
    // If "All Branches" is selected, branchId = null (visible to all branches).
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;

    const itemData = {
      orgId,
      branchId,
      name:          req.body.name.trim(),
      type:          req.body.type,
      unit:          req.body.unit?.trim(),
      isSellable:    req.body.isSellable  ?? true,
      isPurchasable: req.body.isPurchasable ?? true,
      status:        req.body.status || 'Active',
    };

    if (itemData.isSellable) {
      itemData.sellingPrice     = req.body.sellingPrice;
      itemData.salesAccount     = req.body.salesAccount.trim();
      itemData.salesDescription = req.body.salesDescription?.trim();
    }

    if (itemData.isPurchasable) {
      itemData.costPrice           = req.body.costPrice;
      itemData.purchaseAccount     = req.body.purchaseAccount.trim();
      itemData.purchaseDescription = req.body.purchaseDescription?.trim();
      if (req.body.preferredVendor) itemData.preferredVendor = req.body.preferredVendor;
    }

    // FIX 5: resolve COA ObjectIds so reports can link back correctly
    const { salesAccountId, purchaseAccountId } = await resolveCOAIds(
      orgId,
      itemData.salesAccount,
      itemData.purchaseAccount,
    );
    itemData.salesAccountId    = salesAccountId;
    itemData.purchaseAccountId = purchaseAccountId;

    const item = await Item.create(itemData);
    console.log('? Item created:', item.name);

    res.status(201).json({ success: true, message: 'Item created successfully', item });
  } catch (err) {
    console.error('? Error creating item:', err);
    if (err.name === 'ValidationError') return res.status(400).json({ success: false, error: err.message });
    res.status(500).json({ success: false, error: 'Failed to create item' });
  }
});

// ============================================================================
// PUT /:id � update item
// FIX 5: re-resolve COA IDs on every update
// ============================================================================

router.put('/:id', verifyFinanceJWT, validateItemData, async (req, res) => {
  try {
    const orgId = req.user?.orgId || null;

    const updateData = {
      name:          req.body.name.trim(),
      type:          req.body.type,
      unit:          req.body.unit?.trim(),
      isSellable:    req.body.isSellable  ?? true,
      isPurchasable: req.body.isPurchasable ?? true,
      status:        req.body.status || 'Active',
      updatedAt:     new Date(),
    };

    if (updateData.isSellable) {
      updateData.sellingPrice     = req.body.sellingPrice;
      updateData.salesAccount     = req.body.salesAccount.trim();
      updateData.salesDescription = req.body.salesDescription?.trim();
    } else {
      updateData.sellingPrice     = null;
      updateData.salesAccount     = null;
      updateData.salesDescription = null;
      updateData.salesAccountId   = null;
    }

    if (updateData.isPurchasable) {
      updateData.costPrice           = req.body.costPrice;
      updateData.purchaseAccount     = req.body.purchaseAccount.trim();
      updateData.purchaseDescription = req.body.purchaseDescription?.trim();
      if (req.body.preferredVendor) updateData.preferredVendor = req.body.preferredVendor;
    } else {
      updateData.costPrice            = null;
      updateData.purchaseAccount      = null;
      updateData.purchaseDescription  = null;
      updateData.purchaseAccountId    = null;
      updateData.preferredVendor      = null;
    }

    // FIX 5: re-resolve COA IDs
    const { salesAccountId, purchaseAccountId } = await resolveCOAIds(
      orgId,
      updateData.salesAccount,
      updateData.purchaseAccount,
    );
    if (updateData.isSellable)    updateData.salesAccountId    = salesAccountId;
    if (updateData.isPurchasable) updateData.purchaseAccountId = purchaseAccountId;

    const orgFilter = orgId
      ? { $or: [{ orgId }, { orgId: null }] }
      : {};

    const item = await Item.findOneAndUpdate(
      { _id: req.params.id, ...orgFilter },
      updateData,
      { new: true, runValidators: true }
    ).populate('preferredVendor', 'name email phone');

    if (!item) return res.status(404).json({ success: false, error: 'Item not found' });

    console.log('? Item updated:', item.name);
    res.json({ success: true, message: 'Item updated successfully', item });
  } catch (err) {
    console.error('? Error updating item:', err);
    if (err.kind === 'ObjectId') return res.status(404).json({ success: false, error: 'Item not found' });
    if (err.name === 'ValidationError') return res.status(400).json({ success: false, error: err.message });
    res.status(500).json({ success: false, error: 'Failed to update item' });
  }
});

// ============================================================================
// DELETE /:id � soft delete
// ============================================================================

router.delete('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;

    let orgFilter = {};
    if (orgId) {
      if (branchId) {
        orgFilter = { orgId, $or: [{ branchId }, { branchId: null }] };
      } else {
        orgFilter = { orgId };
      }
    }

    const item = await Item.findOneAndUpdate(
      { _id: req.params.id, ...orgFilter },
      { isActive: false, updatedAt: new Date() },
      { new: true }
    );

    if (!item) return res.status(404).json({ success: false, error: 'Item not found' });

    console.log('? Item deleted (soft):', item.name);
    res.json({ success: true, message: 'Item deleted successfully' });
  } catch (err) {
    console.error('? Error deleting item:', err);
    if (err.kind === 'ObjectId') return res.status(404).json({ success: false, error: 'Item not found' });
    res.status(500).json({ success: false, error: 'Failed to delete item' });
  }
});

// ============================================================================
// GET /export/csv � export all items as CSV
// ============================================================================

router.get('/export/csv', verifyFinanceJWT, async (req, res) => {
  try {
    // Branch-specific items filter
    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;

    let orgFilter = {};
    if (orgId) {
      if (branchId) {
        orgFilter = { orgId, $or: [{ branchId }, { branchId: null }] };
      } else {
        orgFilter = { orgId };
      }
    }

    const { type, isSellable, isPurchasable } = req.query;
    const filter = { ...orgFilter, isActive: true };
    if (type)                     filter.type          = type;
    if (isSellable !== undefined)  filter.isSellable    = isSellable === 'true';
    if (isPurchasable !== undefined) filter.isPurchasable = isPurchasable === 'true';

    const items = await Item.find(filter).populate('preferredVendor', 'name').lean();

    let csvContent = 'Name,Type,Unit,Selling Price,Cost Price,Sales Account,Purchase Account,Sales Description,Purchase Description,Is Sellable,Is Purchasable,Preferred Vendor\n';
    items.forEach(i => {
      csvContent += `"${i.name}","${i.type}","${i.unit || ''}","${i.sellingPrice || ''}","${i.costPrice || ''}","${i.salesAccount || ''}","${i.purchaseAccount || ''}","${i.salesDescription || ''}","${i.purchaseDescription || ''}","${i.isSellable}","${i.isPurchasable}","${i.preferredVendor?.name || ''}"\n`;
    });

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=items_export.csv');
    res.send(csvContent);
  } catch (err) {
    console.error('? Error exporting items:', err);
    res.status(500).json({ success: false, error: 'Failed to export items' });
  }
});

// ============================================================================
// POST /bulk-import � CSV bulk import
// FIX 4: removed duplicate Vendor schema � uses multer only, no Vendor model here
// ============================================================================

const upload = multer({ dest: 'uploads/' });

router.post('/bulk-import', verifyFinanceJWT, upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });

  const rows    = [];
  const errors  = [];
  let successCount = 0;
  let errorCount   = 0;

  try {
    await new Promise((resolve, reject) => {
      fs.createReadStream(req.file.path)
        .pipe(csv())
        .on('data', d => rows.push(d))
        .on('end',  resolve)
        .on('error', reject);
    });

    const orgId = req.user?.orgId || null;

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      try {
        const parseBool = v => {
          if (typeof v === 'boolean') return v;
          const s = (v || '').toString().toLowerCase().trim();
          return s === 'true' || s === '1' || s === 'yes';
        };

        const isSellable   = parseBool(row['Is Sellable']   || row.isSellable);
        const isPurchasable = parseBool(row['Is Purchasable'] || row.isPurchasable);

        const name = (row.Name || row.name || '').trim();
        const type = (row.Type || row.type || 'Goods').trim();

        if (!name)                                    throw new Error('Name is required');
        if (!['Goods','Service'].includes(type))      throw new Error('Type must be Goods or Service');

        const itemData = { orgId, name, type, unit: (row.Unit || row.unit || '').trim(), isSellable, isPurchasable, status: 'Active' };

        if (isSellable) {
          const sp = parseFloat(row['Selling Price'] || row.sellingPrice || '0');
          if (isNaN(sp) || sp < 0) throw new Error('Invalid selling price');
          itemData.sellingPrice     = sp;
          itemData.salesAccount     = (row['Sales Account'] || row.salesAccount || 'Sales').trim();
          itemData.salesDescription = (row['Sales Description'] || row.salesDescription || '').trim();
        }

        if (isPurchasable) {
          const cp = parseFloat(row['Cost Price'] || row.costPrice || '0');
          if (isNaN(cp) || cp < 0) throw new Error('Invalid cost price');
          itemData.costPrice           = cp;
          itemData.purchaseAccount     = (row['Purchase Account'] || row.purchaseAccount || 'Cost of Goods Sold').trim();
          itemData.purchaseDescription = (row['Purchase Description'] || row.purchaseDescription || '').trim();
        }

        // Resolve COA IDs
        const { salesAccountId, purchaseAccountId } = await resolveCOAIds(
          orgId, itemData.salesAccount, itemData.purchaseAccount,
        );
        itemData.salesAccountId    = salesAccountId;
        itemData.purchaseAccountId = purchaseAccountId;

        await Item.create(itemData);
        successCount++;
      } catch (err) {
        errorCount++;
        errors.push({ row: `Row ${i + 2}: ${row.Name || 'Unknown'}`, error: err.message });
      }
    }

    try { fs.unlinkSync(req.file.path); } catch (_) {}

    res.json({ success: true, message: 'Bulk import completed', successCount, errorCount, errors });
  } catch (err) {
    try { fs.unlinkSync(req.file.path); } catch (_) {}
    console.error('? Bulk import error:', err);
    res.status(500).json({ success: false, error: 'Failed to import: ' + err.message });
  }
});

// ============================================================================
// UTILITY ROUTES � units, sales accounts, purchase accounts
// These read from COA so dropdowns reflect actual accounts in the org
// ============================================================================

router.get('/units', verifyFinanceJWT, (req, res) => {
  res.json({
    success: true,
    units: ['pcs', 'dz', 'kg', 'g', 'ltr', 'ml', 'box', 'carton', 'unit', 'dozen', 'ton', 'hour'],
  });
});

// Sales accounts � pulled from COA (Income types)
router.get('/accounts/sales', verifyFinanceJWT, async (req, res) => {
  try {
    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;
    let orgFilter = {};
    if (orgId) {
      orgFilter = branchId
        ? { orgId, $or: [{ branchId }, { branchId: null }] }
        : { orgId };
    }

    const accounts = await ChartOfAccount.find({
      ...orgFilter,
      isActive: true,
      accountType: { $in: ['Income', 'Other Income'] },
    }).sort({ accountName: 1 }).lean();

    const names = accounts.length > 0
      ? accounts.map(a => a.accountName)
      : ['Sales', 'Service Revenue', 'Other Income', 'Consulting Revenue'];

    res.json({ success: true, accounts: names });
  } catch (err) {
    res.json({ success: true, accounts: ['Sales', 'Service Revenue', 'Other Income'] });
  }
});

// Purchase accounts � pulled from COA (Expense / COGS types)
router.get('/accounts/purchase', verifyFinanceJWT, async (req, res) => {
  try {
    const orgId    = req.user?.orgId;
    const branchId = req.branchIds?.length === 1 ? req.branchIds[0] : null;
    let orgFilter = {};
    if (orgId) {
      orgFilter = branchId
        ? { orgId, $or: [{ branchId }, { branchId: null }] }
        : { orgId };
    }

    const accounts = await ChartOfAccount.find({
      ...orgFilter,
      isActive: true,
      accountType: { $in: ['Expense', 'Cost Of Goods Sold', 'Other Expense'] },
    }).sort({ accountName: 1 }).lean();

    const names = accounts.length > 0
      ? accounts.map(a => a.accountName)
      : ['Cost of Goods Sold', 'Purchases', 'Direct Expenses', 'Materials'];

    res.json({ success: true, accounts: names });
  } catch (err) {
    res.json({ success: true, accounts: ['Cost of Goods Sold', 'Purchases', 'Direct Expenses'] });
  }
});

module.exports = router;
module.exports.Item = Item;