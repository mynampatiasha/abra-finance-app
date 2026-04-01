// ============================================================================
// ITEM BILLING BACKEND ROUTES - COMPLETE UPDATED VERSION
// ============================================================================
// Replace your existing backend routes file with this complete version
// File: backend/routes/items.js (or wherever your items routes are)
// ============================================================================

const express = require('express');
const mongoose = require('mongoose');
const multer = require('multer');
const csv = require('csv-parser');
const fs = require('fs');

const router = express.Router();

// MongoDB Connection (if not already connected)
if (mongoose.connection.readyState === 0) {
  const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet_billing';
  
  mongoose.connect(MONGODB_URI, {
    useNewUrlParser: true,
    useUnifiedTopology: true,
  })
  .then(() => console.log('✅ MongoDB connected for Item Billing'))
  .catch(err => console.error('❌ MongoDB connection error:', err));
}

// ==================== SCHEMAS ====================

const itemSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  name: {
    type: String,
    required: true,
    trim: true,
    index: true,
  },
  type: {
    type: String,
    enum: ['Goods', 'Service'],
    required: true,
  },
  unit: {
    type: String,
    trim: true,
  },
  isSellable: {
    type: Boolean,
    default: true,
  },
  isPurchasable: {
    type: Boolean,
    default: true,
  },
  sellingPrice: {
    type: Number,
    min: 0,
  },
  salesAccount: {
    type: String,
    trim: true,
  },
  salesDescription: {
    type: String,
    trim: true,
  },
  costPrice: {
    type: Number,
    min: 0,
  },
  purchaseAccount: {
    type: String,
    trim: true,
  },
  purchaseDescription: {
    type: String,
    trim: true,
  },
  preferredVendor: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Vendor',
  },
  status: {
    type: String,
    enum: ['Active', 'Inactive'],
    default: 'Active',
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
  isActive: {
    type: Boolean,
    default: true,
  },
});

const vendorSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true,
  },
  email: {
    type: String,
    trim: true,
    lowercase: true,
  },
  phone: {
    type: String,
    trim: true,
  },
  address: {
    type: String,
    trim: true,
  },
  isActive: {
    type: Boolean,
    default: true,
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
});

// Create models
// Check if models exist before creating to avoid OverwriteModelError
const Item = mongoose.models.Item || mongoose.model('Item', itemSchema);
const Vendor = mongoose.models.Vendor || mongoose.model('Vendor', vendorSchema);

// ==================== VALIDATION MIDDLEWARE ====================

const validateItemData = (req, res, next) => {
  const { name, type, isSellable, isPurchasable, sellingPrice, salesAccount, costPrice, purchaseAccount } = req.body;

  if (!name || name.trim() === '') {
    return res.status(400).json({ error: 'Item name is required' });
  }

  if (!type || !['Goods', 'Service'].includes(type)) {
    return res.status(400).json({ error: 'Invalid item type. Must be "Goods" or "Service"' });
  }

  if (isSellable) {
    if (sellingPrice === undefined || sellingPrice === null) {
      return res.status(400).json({ error: 'Selling price is required for sellable items' });
    }
    if (typeof sellingPrice !== 'number' || sellingPrice < 0) {
      return res.status(400).json({ error: 'Selling price must be a positive number' });
    }
    if (!salesAccount || salesAccount.trim() === '') {
      return res.status(400).json({ error: 'Sales account is required for sellable items' });
    }
  }

  if (isPurchasable) {
    if (costPrice === undefined || costPrice === null) {
      return res.status(400).json({ error: 'Cost price is required for purchasable items' });
    }
    if (typeof costPrice !== 'number' || costPrice < 0) {
      return res.status(400).json({ error: 'Cost price must be a positive number' });
    }
    if (!purchaseAccount || purchaseAccount.trim() === '') {
      return res.status(400).json({ error: 'Purchase account is required for purchasable items' });
    }
  }

  next();
};

// ==================== ROUTES ====================

// Health Check
router.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    message: 'Item Billing API is running',
    timestamp: new Date().toISOString(),
  });
});

// ==================== ITEM ROUTES ====================

// Get all items with filtering and pagination
router.get('/', async (req, res) => {
  try {
    const { 
      type, 
      isSellable, 
      isPurchasable, 
      page = 1, 
      limit = 50, 
      search,
      startDate,
      endDate 
    } = req.query;

    const filter = { isActive: true };
    if (req.user?.orgId) filter.orgId = req.user.orgId;
    
    if (type) filter.type = type;
    if (isSellable !== undefined) filter.isSellable = isSellable === 'true';
    if (isPurchasable !== undefined) filter.isPurchasable = isPurchasable === 'true';
    
    if (search && search.trim()) {
      filter.$or = [
        { name: { $regex: search.trim(), $options: 'i' } },
        { salesDescription: { $regex: search.trim(), $options: 'i' } },
        { purchaseDescription: { $regex: search.trim(), $options: 'i' } }
      ];
    }
    
    if (startDate || endDate) {
      filter.createdAt = {};
      if (startDate) {
        filter.createdAt.$gte = new Date(startDate);
      }
      if (endDate) {
        const endDateObj = new Date(endDate);
        endDateObj.setDate(endDateObj.getDate() + 1);
        filter.createdAt.$lt = endDateObj;
      }
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);

    const items = await Item.find(filter)
      .populate('preferredVendor', 'name email phone')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    const total = await Item.countDocuments(filter);

    res.json({
      success: true,
      items,
      pagination: {
        total,
        page: parseInt(page),
        limit: parseInt(limit),
        totalPages: Math.ceil(total / parseInt(limit)),
      },
      filters: {
        type,
        isSellable,
        isPurchasable,
        search,
        startDate,
        endDate
      }
    });
  } catch (error) {
    console.error('❌ Error fetching items:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to fetch items',
      message: error.message 
    });
  }
});

// Get item statistics
router.get('/statistics', async (req, res) => {
  try {
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
    const totalItems = await Item.countDocuments({ ...orgFilter, isActive: true });
    const totalGoods = await Item.countDocuments({ ...orgFilter, isActive: true, type: 'Goods' });
    const totalServices = await Item.countDocuments({ ...orgFilter, isActive: true, type: 'Service' });
    const sellableItems = await Item.countDocuments({ ...orgFilter, isActive: true, isSellable: true });
    const purchasableItems = await Item.countDocuments({ ...orgFilter, isActive: true, isPurchasable: true });

    res.json({
      success: true,
      statistics: {
        totalItems,
        totalGoods,
        totalServices,
        sellableItems,
        purchasableItems,
      }
    });
  } catch (error) {
    console.error('❌ Error fetching statistics:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to fetch statistics' 
    });
  }
});

// Get single item by ID
router.get('/:id', async (req, res) => {
  try {
    const item = await Item.findById(req.params.id)
      .populate('preferredVendor', 'name email phone');

    if (!item || !item.isActive) {
      return res.status(404).json({ error: 'Item not found' });
    }

    res.json({ success: true, item });
  } catch (error) {
    console.error('❌ Error fetching item:', error);
    if (error.kind === 'ObjectId') {
      return res.status(404).json({ error: 'Item not found' });
    }
    res.status(500).json({ error: 'Failed to fetch item' });
  }
});

// Create new item
router.post('/', validateItemData, async (req, res) => {
  try {
    const itemData = {
      name: req.body.name.trim(),
      type: req.body.type,
      unit: req.body.unit?.trim(),
      isSellable: req.body.isSellable ?? true,
      isPurchasable: req.body.isPurchasable ?? true,
      status: req.body.status || 'Active',
      orgId: req.user?.orgId || null,
    };

    if (itemData.isSellable) {
      itemData.sellingPrice = req.body.sellingPrice;
      itemData.salesAccount = req.body.salesAccount.trim();
      itemData.salesDescription = req.body.salesDescription?.trim();
    }

    if (itemData.isPurchasable) {
      itemData.costPrice = req.body.costPrice;
      itemData.purchaseAccount = req.body.purchaseAccount.trim();
      itemData.purchaseDescription = req.body.purchaseDescription?.trim();
      if (req.body.preferredVendor) {
        itemData.preferredVendor = req.body.preferredVendor;
      }
    }

    const item = new Item(itemData);
    await item.save();

    console.log('✅ Item created:', item.name);

    res.status(201).json({
      success: true,
      message: 'Item created successfully',
      item,
    });
  } catch (error) {
    console.error('❌ Error creating item:', error);
    if (error.name === 'ValidationError') {
      return res.status(400).json({ error: error.message });
    }
    res.status(500).json({ error: 'Failed to create item' });
  }
});

// Update item
router.put('/:id', validateItemData, async (req, res) => {
  try {
    const updateData = {
      name: req.body.name.trim(),
      type: req.body.type,
      unit: req.body.unit?.trim(),
      isSellable: req.body.isSellable ?? true,
      isPurchasable: req.body.isPurchasable ?? true,
      status: req.body.status || 'Active',
      updatedAt: Date.now(),
    };

    if (updateData.isSellable) {
      updateData.sellingPrice = req.body.sellingPrice;
      updateData.salesAccount = req.body.salesAccount.trim();
      updateData.salesDescription = req.body.salesDescription?.trim();
    } else {
      updateData.sellingPrice = null;
      updateData.salesAccount = null;
      updateData.salesDescription = null;
    }

    if (updateData.isPurchasable) {
      updateData.costPrice = req.body.costPrice;
      updateData.purchaseAccount = req.body.purchaseAccount.trim();
      updateData.purchaseDescription = req.body.purchaseDescription?.trim();
      if (req.body.preferredVendor) {
        updateData.preferredVendor = req.body.preferredVendor;
      }
    } else {
      updateData.costPrice = null;
      updateData.purchaseAccount = null;
      updateData.purchaseDescription = null;
      updateData.preferredVendor = null;
    }

    const item = await Item.findByIdAndUpdate(
      req.params.id,
      updateData,
      { new: true, runValidators: true }
    ).populate('preferredVendor', 'name email phone');

    if (!item) {
      return res.status(404).json({ error: 'Item not found' });
    }

    console.log('✅ Item updated:', item.name);

    res.json({
      success: true,
      message: 'Item updated successfully',
      item,
    });
  } catch (error) {
    console.error('❌ Error updating item:', error);
    if (error.kind === 'ObjectId') {
      return res.status(404).json({ error: 'Item not found' });
    }
    if (error.name === 'ValidationError') {
      return res.status(400).json({ error: error.message });
    }
    res.status(500).json({ error: 'Failed to update item' });
  }
});

// Delete item (soft delete)
router.delete('/:id', async (req, res) => {
  try {
    const item = await Item.findByIdAndUpdate(
      req.params.id,
      { isActive: false, updatedAt: Date.now() },
      { new: true }
    );

    if (!item) {
      return res.status(404).json({ error: 'Item not found' });
    }

    console.log('✅ Item deleted:', item.name);

    res.json({ 
      success: true,
      message: 'Item deleted successfully' 
    });
  } catch (error) {
    console.error('❌ Error deleting item:', error);
    if (error.kind === 'ObjectId') {
      return res.status(404).json({ error: 'Item not found' });
    }
    res.status(500).json({ error: 'Failed to delete item' });
  }
});

// Search items
router.get('/search', async (req, res) => {
  try {
    const { q, startDate, endDate, type, limit = 20 } = req.query;
    
    if (!q || q.trim() === '') {
      return res.json({ success: true, items: [] });
    }

    const filter = {
      isActive: true,
      $or: [
        { name: { $regex: q.trim(), $options: 'i' } },
        { salesDescription: { $regex: q.trim(), $options: 'i' } },
        { purchaseDescription: { $regex: q.trim(), $options: 'i' } }
      ]
    };

    if (type) filter.type = type;

    if (startDate || endDate) {
      filter.createdAt = {};
      if (startDate) {
        filter.createdAt.$gte = new Date(startDate);
      }
      if (endDate) {
        const endDateObj = new Date(endDate);
        endDateObj.setDate(endDateObj.getDate() + 1);
        filter.createdAt.$lt = endDateObj;
      }
    }

    const items = await Item.find(filter)
      .populate('preferredVendor', 'name')
      .limit(parseInt(limit))
      .sort({ name: 1 });

    res.json({ 
      success: true, 
      items,
      query: q,
      filters: { startDate, endDate, type }
    });
  } catch (error) {
    console.error('❌ Error searching items:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to search items',
      message: error.message 
    });
  }
});

// Export items to CSV
router.get('/export/csv', async (req, res) => {
  try {
    const { type, isSellable, isPurchasable } = req.query;

    const filter = { isActive: true };
    if (type) filter.type = type;
    if (isSellable !== undefined) filter.isSellable = isSellable === 'true';
    if (isPurchasable !== undefined) filter.isPurchasable = isPurchasable === 'true';

    const items = await Item.find(filter).populate('preferredVendor', 'name');

    let csv = 'Name,Type,Unit,Selling Price,Cost Price,Sales Account,Purchase Account,Sales Description,Purchase Description,Is Sellable,Is Purchasable,Preferred Vendor\n';
    
    items.forEach(item => {
      csv += `"${item.name}","${item.type}","${item.unit || ''}","${item.sellingPrice || ''}","${item.costPrice || ''}","${item.salesAccount || ''}","${item.purchaseAccount || ''}","${item.salesDescription || ''}","${item.purchaseDescription || ''}","${item.isSellable}","${item.isPurchasable}","${item.preferredVendor?.name || ''}"\n`;
    });

    console.log(`✅ Exported ${items.length} items to CSV`);

    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=items_export.csv');
    res.send(csv);
  } catch (error) {
    console.error('❌ Error exporting items:', error);
    res.status(500).json({ error: 'Failed to export items' });
  }
});

// ========== CSV BULK IMPORT ==========
const upload = multer({ dest: 'uploads/' });

router.post('/bulk-import', upload.single('file'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded' });
  }

  const results = [];
  const errors = [];

  try {
    console.log('📥 Starting bulk import from:', req.file.originalname);

    fs.createReadStream(req.file.path)
      .pipe(csv())
      .on('data', (data) => results.push(data))
      .on('end', async () => {
        let successCount = 0;
        let errorCount = 0;

        console.log(`📊 Processing ${results.length} rows from CSV...`);

        for (let i = 0; i < results.length; i++) {
          const row = results[i];
          
          try {
            const parseBoolean = (value) => {
              if (typeof value === 'boolean') return value;
              if (typeof value === 'string') {
                const lower = value.toLowerCase().trim();
                return lower === 'true' || lower === '1' || lower === 'yes';
              }
              return true;
            };

            const isSellable = parseBoolean(row['Is Sellable'] || row.isSellable);
            const isPurchasable = parseBoolean(row['Is Purchasable'] || row.isPurchasable);

            const itemData = {
              name: (row.Name || row.name || '').trim(),
              type: (row.Type || row.type || 'Goods').trim(),
              unit: (row.Unit || row.unit || '').trim(),
              isSellable,
              isPurchasable,
              status: (row.Status || row.status || 'Active').trim(),
            };

            if (!itemData.name) {
              throw new Error('Item name is required');
            }

            if (!['Goods', 'Service'].includes(itemData.type)) {
              throw new Error('Invalid type. Must be "Goods" or "Service"');
            }

            if (itemData.isSellable) {
              const sellingPrice = parseFloat(row['Selling Price'] || row.sellingPrice || '0');
              if (isNaN(sellingPrice) || sellingPrice < 0) {
                throw new Error('Invalid selling price for sellable item');
              }
              itemData.sellingPrice = sellingPrice;
              itemData.salesAccount = (row['Sales Account'] || row.salesAccount || 'Sales').trim();
              itemData.salesDescription = (row['Sales Description'] || row.salesDescription || '').trim();
            }

            if (itemData.isPurchasable) {
              const costPrice = parseFloat(row['Cost Price'] || row.costPrice || '0');
              if (isNaN(costPrice) || costPrice < 0) {
                throw new Error('Invalid cost price for purchasable item');
              }
              itemData.costPrice = costPrice;
              itemData.purchaseAccount = (row['Purchase Account'] || row.purchaseAccount || 'Cost of Goods Sold').trim();
              itemData.purchaseDescription = (row['Purchase Description'] || row.purchaseDescription || '').trim();
            }

            const item = new Item({ ...itemData, orgId: req.user?.orgId || null });
            await item.save();
            
            successCount++;
            console.log(`✅ Row ${i + 2}: "${itemData.name}" imported successfully`);
            
          } catch (error) {
            errorCount++;
            const errorMsg = `Row ${i + 2} (${row.Name || 'Unknown'}): ${error.message}`;
            errors.push({ 
              row: `Row ${i + 2}: ${row.Name || 'Unknown'}`, 
              error: error.message 
            });
            console.error(`❌ ${errorMsg}`);
          }
        }

        try {
          fs.unlinkSync(req.file.path);
        } catch (err) {
          console.error('⚠️ Could not delete temp file:', err);
        }

        console.log(`\n📈 Import Summary:`);
        console.log(`   ✅ Successful: ${successCount} items`);
        console.log(`   ❌ Failed: ${errorCount} items`);

        res.json({
          success: true,
          message: 'Bulk import completed',
          successCount,
          errorCount,
          errors,
        });
      })
      .on('error', (error) => {
        console.error('❌ CSV parsing error:', error);
        try {
          if (req.file) fs.unlinkSync(req.file.path);
        } catch (err) {
          console.error('⚠️ Could not delete temp file:', err);
        }
        res.status(500).json({ error: 'Failed to parse CSV file: ' + error.message });
      });
      
  } catch (error) {
    console.error('❌ Error during bulk import:', error);
    try {
      if (req.file) fs.unlinkSync(req.file.path);
    } catch (err) {
      console.error('⚠️ Could not delete temp file:', err);
    }
    res.status(500).json({ error: 'Failed to import items: ' + error.message });
  }
});

// ==================== VENDOR ROUTES ====================

// Get all vendors
router.get('/vendors', async (req, res) => {
  try {
    const vendors = await Vendor.find({ isActive: true }).sort({ name: 1 });
    
    console.log(`✅ Fetched ${vendors.length} vendors`);
    
    res.json({
      success: true,
      vendors: vendors,
      count: vendors.length
    });
  } catch (error) {
    console.error('❌ Error fetching vendors:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to fetch vendors',
      vendors: []
    });
  }
});

// Create new vendor
router.post('/vendors', async (req, res) => {
  try {
    const { name, email, phone, address } = req.body;

    if (!name || name.trim() === '') {
      return res.status(400).json({ error: 'Vendor name is required' });
    }

    const vendor = new Vendor({
      name: name.trim(),
      email: email?.trim(),
      phone: phone?.trim(),
      address: address?.trim(),
    });

    await vendor.save();
    
    console.log('✅ Vendor created:', vendor.name);
    
    res.status(201).json({
      success: true,
      message: 'Vendor created successfully',
      vendor,
    });
  } catch (error) {
    console.error('❌ Error creating vendor:', error);
    res.status(500).json({ 
      success: false,
      error: 'Failed to create vendor' 
    });
  }
});

// Get single vendor by ID
router.get('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findById(req.params.id);

    if (!vendor || !vendor.isActive) {
      return res.status(404).json({ error: 'Vendor not found' });
    }

    res.json({ success: true, vendor });
  } catch (error) {
    console.error('❌ Error fetching vendor:', error);
    if (error.kind === 'ObjectId') {
      return res.status(404).json({ error: 'Vendor not found' });
    }
    res.status(500).json({ error: 'Failed to fetch vendor' });
  }
});

// Update vendor
router.put('/vendors/:id', async (req, res) => {
  try {
    const { name, email, phone, address } = req.body;

    if (!name || name.trim() === '') {
      return res.status(400).json({ error: 'Vendor name is required' });
    }

    const vendor = await Vendor.findByIdAndUpdate(
      req.params.id,
      {
        name: name.trim(),
        email: email?.trim(),
        phone: phone?.trim(),
        address: address?.trim(),
      },
      { new: true, runValidators: true }
    );

    if (!vendor) {
      return res.status(404).json({ error: 'Vendor not found' });
    }

    console.log('✅ Vendor updated:', vendor.name);

    res.json({
      success: true,
      message: 'Vendor updated successfully',
      vendor,
    });
  } catch (error) {
    console.error('❌ Error updating vendor:', error);
    if (error.kind === 'ObjectId') {
      return res.status(404).json({ error: 'Vendor not found' });
    }
    res.status(500).json({ error: 'Failed to update vendor' });
  }
});

// Delete vendor (soft delete)
router.delete('/vendors/:id', async (req, res) => {
  try {
    const vendor = await Vendor.findByIdAndUpdate(
      req.params.id,
      { isActive: false },
      { new: true }
    );

    if (!vendor) {
      return res.status(404).json({ error: 'Vendor not found' });
    }

    console.log('✅ Vendor deleted:', vendor.name);

    res.json({ 
      success: true,
      message: 'Vendor deleted successfully' 
    });
  } catch (error) {
    console.error('❌ Error deleting vendor:', error);
    if (error.kind === 'ObjectId') {
      return res.status(404).json({ error: 'Vendor not found' });
    }
    res.status(500).json({ error: 'Failed to delete vendor' });
  }
});

// ==================== UTILITY ROUTES ====================

// Get units
router.get('/units', (req, res) => {
  res.json({
    success: true,
    units: ['pcs', 'dz', 'kg', 'ltr', 'box', 'carton', 'unit', 'dozen', 'gram', 'ton', 'hour']
  });
});

// Get sales accounts
router.get('/accounts/sales', (req, res) => {
  res.json({
    success: true,
    accounts: ['Sales', 'Service Revenue', 'Other Income', 'Consulting Revenue']
  });
});

// Get purchase accounts
router.get('/accounts/purchase', (req, res) => {
  res.json({
    success: true,
    accounts: ['Cost of Goods Sold', 'Purchases', 'Direct Expenses', 'Materials']
  });
});

module.exports = router;