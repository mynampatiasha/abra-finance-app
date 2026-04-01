// ============================================================================
// ADD BANK ACCOUNT BACKEND API - WITH CUSTOM ACCOUNT TYPE SUPPORT
// ============================================================================
// File: backend/routes/add_bank.js
// Purpose: Handle all CRUD operations for payment accounts
// Features:
// - Support for predefined and custom account types
// - Custom account types are automatically added to the system
// - Dynamic custom fields for OTHER account types
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');

// ============================================================================
// MONGOOSE SCHEMA DEFINITIONS
// ============================================================================

const LinkedBankDetailsSchema = new mongoose.Schema({
  bankName: { type: String, default: null },
  accountNumber: { type: String, default: null },
  ifscCode: { type: String, default: null },
}, { _id: false });

// Schema for storing custom field definitions
const CustomFieldSchema = new mongoose.Schema({
  fieldName: { type: String, required: true },
  fieldValue: { type: String, default: null },
}, { _id: false });

// Schema for custom account types
const CustomAccountTypeSchema = new mongoose.Schema({
  typeName: {
    type: String,
    required: true,
    unique: true,
    trim: true,
  },
  displayName: {
    type: String,
    required: true,
    trim: true,
  },
  icon: {
    type: String,
    default: 'add_circle_outline',
  },
  color: {
    type: String,
    default: '#808080',
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
  usageCount: {
    type: Number,
    default: 0,
  },
});

const PaymentAccountSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  // Common fields for all account types
  accountType: {
    type: String,
    required: true,
    // Removed enum to allow custom types
  },
  accountName: {
    type: String,
    required: true,
    trim: true,
  },
  holderName: {
    type: String,
    trim: true,
    default: null,
  },
  openingBalance: {
    type: Number,
    default: 0,
  },
  currentBalance: {
    type: Number,
    default: 0,
  },
  isActive: {
    type: Boolean,
    default: true,
  },

  // For OTHER type - store custom type name
  customTypeName: {
    type: String,
    default: null,
    trim: true,
  },

  // Fuel Card specific fields
  providerName: {
    type: String,
    default: null,
  },
  cardNumber: {
    type: String,
    default: null,
  },

  // Bank Account specific fields
  bankName: {
    type: String,
    default: null,
  },
  accountNumber: {
    type: String,
    default: null,
  },
  ifscCode: {
    type: String,
    default: null,
  },

  // FASTag specific fields
  fastagNumber: {
    type: String,
    default: null,
  },
  vehicleNumber: {
    type: String,
    default: null,
  },

  // Custom fields for OTHER account type
  customFields: {
    type: [CustomFieldSchema],
    default: [],
  },

  // Linked bank details (for non-bank accounts)
  linkedBankDetails: {
    type: LinkedBankDetailsSchema,
    default: null,
  },

  // Audit fields
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
  createdBy: {
    type: String,
    default: 'system',
  },
  updatedBy: {
    type: String,
    default: 'system',
  },
});

// Update the updatedAt timestamp before saving
PaymentAccountSchema.pre('save', function(next) {
  this.updatedAt = Date.now();
  if (!this.currentBalance && this.openingBalance) {
    this.currentBalance = this.openingBalance;
  }
  next();
});

// Create models - check if already exists to prevent overwrite error
const PaymentAccount = mongoose.models.PaymentAccount || mongoose.model('PaymentAccount', PaymentAccountSchema);
const CustomAccountType = mongoose.models.CustomAccountType || mongoose.model('CustomAccountType', CustomAccountTypeSchema);

// ============================================================================
// API ROUTES
// ============================================================================

/**
 * @route   POST /api/accounts/add
 * @desc    Create a new payment account (supports custom types)
 * @access  Private
 */
router.post('/add', async (req, res) => {
  try {
    const accountData = req.body;

    // Validate required fields
    if (!accountData.accountType || !accountData.accountName) {
      return res.status(400).json({
        success: false,
        message: 'Account type and account name are required',
      });
    }

    // If account type is OTHER and customTypeName is provided, save it
    if (accountData.accountType === 'OTHER' && accountData.customTypeName) {
      const customTypeName = accountData.customTypeName.trim();
      
      // Check if this custom type already exists
      let customType = await CustomAccountType.findOne({ 
        typeName: customTypeName.toUpperCase().replace(/\s+/g, '_') 
      });

      if (!customType) {
        // Create new custom account type
        customType = new CustomAccountType({
          typeName: customTypeName.toUpperCase().replace(/\s+/g, '_'),
          displayName: customTypeName,
          icon: accountData.customIcon || 'add_circle_outline',
          color: accountData.customColor || '#808080',
        });
        await customType.save();
      } else {
        // Increment usage count
        customType.usageCount += 1;
        await customType.save();
      }
    }

    // Create new account
    const newAccount = new PaymentAccount({
      ...accountData,
      currentBalance: accountData.openingBalance || 0,
      orgId: req.user?.orgId || null,
    });

    // Save to database
const savedAccount = await newAccount.save();

// ✅ Auto-create matching COA account
try {
  const { ChartOfAccount, postTransactionToCOA } = require('./chart_of_accounts');
  
  // Map payment account type to COA account type
  const coaTypeMap = {
    'BANK_ACCOUNT': 'Other Current Asset',
    'FUEL_CARD':    'Other Current Asset',
    'UPI':          'Other Current Asset',
    'FASTAG':       'Other Current Asset',
    'PETTY_CASH':   'Cash',
    'OTHER':        'Other Current Asset',
  };
  
  const coaType = coaTypeMap[accountData.accountType] || 'Other Current Asset';
  
  // Check if COA account already exists with this name
  const existingCOA = await ChartOfAccount.findOne({
    accountName: accountData.accountName,
    ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
  });
  
  if (!existingCOA) {
    await ChartOfAccount.create({
      accountName:    accountData.accountName,
      accountType:    coaType,
      accountSubType: accountData.accountType,
      description:    `Auto-created for ${accountData.accountType} - ${accountData.accountName}`,
      currency:       'INR',
      isActive:       true,
      isSystemAccount: false,
      closingBalance: accountData.openingBalance || 0,
      balanceType:    'Dr',
      createdBy:      req.user?.email || 'system',
      orgId:          req.user?.orgId || null,
    });
    console.log(`✅ COA account auto-created: ${accountData.accountName} (${coaType})`);
  } else {
    console.log(`ℹ️ COA account already exists: ${accountData.accountName}`);
  }
} catch (coaErr) {
  console.error('⚠️ COA auto-create error:', coaErr.message);
  // Non-critical — don't fail the bank account creation
}

res.status(201).json({
  success: true,
  message: 'Account created successfully',
  data: savedAccount,
});
  } catch (error) {
    console.error('Error creating account:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create account',
      error: error.message,
    });
  }
});

/**
 * @route   GET /api/accounts/custom-types
 * @desc    Get all custom account types
 * @access  Private
 */
router.get('/custom-types', async (req, res) => {
  try {
    const customTypes = await CustomAccountType.find().sort({ usageCount: -1, createdAt: -1 });

    res.status(200).json({
      success: true,
      count: customTypes.length,
      data: customTypes,
    });
  } catch (error) {
    console.error('Error fetching custom types:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch custom types',
      error: error.message,
    });
  }
});

/**
 * @route   GET /api/accounts
 * @desc    Get all payment accounts
 * @access  Private
 */
router.get('/', async (req, res) => {
  try {
    const { isActive } = req.query;
    
    const filter = {};
    if (req.user?.orgId) filter.orgId = req.user.orgId;
    if (isActive !== undefined) {
      filter.isActive = isActive === 'true';
    }

    const accounts = await PaymentAccount.find(filter).sort({ createdAt: -1 });

    res.status(200).json({
      success: true,
      count: accounts.length,
      data: accounts,
    });
  } catch (error) {
    console.error('Error fetching accounts:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch accounts',
      error: error.message,
    });
  }
});

/**
 * @route   GET /api/accounts/:id
 * @desc    Get a single account by ID
 * @access  Private
 */
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid account ID',
      });
    }

    const account = await PaymentAccount.findOne({
      _id: id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!account) {
      return res.status(404).json({
        success: false,
        message: 'Account not found',
      });
    }

    res.status(200).json({
      success: true,
      data: account,
    });
  } catch (error) {
    console.error('Error fetching account:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch account',
      error: error.message,
    });
  }
});

/**
 * @route   PUT /api/accounts/:id
 * @desc    Update an account
 * @access  Private
 */
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid account ID',
      });
    }

    // Don't allow updating certain fields
    delete updateData._id;
    delete updateData.createdAt;
    delete updateData.createdBy;

    // Update the account
    const updatedAccount = await PaymentAccount.findOneAndUpdate(
      { _id: id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) },
      { ...updateData, updatedAt: Date.now() },
      { new: true, runValidators: true }
    );

    if (!updatedAccount) {
      return res.status(404).json({
        success: false,
        message: 'Account not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Account updated successfully',
      data: updatedAccount,
    });
  } catch (error) {
    console.error('Error updating account:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update account',
      error: error.message,
    });
  }
});

/**
 * @route   DELETE /api/accounts/:id
 * @desc    Delete an account
 * @access  Private
 */
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid account ID',
      });
    }

    const deletedAccount = await PaymentAccount.findOneAndDelete({
      _id: id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!deletedAccount) {
      return res.status(404).json({
        success: false,
        message: 'Account not found',
      });
    }

    res.status(200).json({
      success: true,
      message: 'Account deleted successfully',
      data: deletedAccount,
    });
  } catch (error) {
    console.error('Error deleting account:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete account',
      error: error.message,
    });
  }
});

/**
 * @route   GET /api/accounts/:id/balance
 * @desc    Get account balance
 * @access  Private
 */
router.get('/:id/balance', async (req, res) => {
  try {
    const { id } = req.params;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid account ID',
      });
    }

    const account = await PaymentAccount.findOne({
      _id: id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).select('currentBalance accountName');

    if (!account) {
      return res.status(404).json({
        success: false,
        message: 'Account not found',
      });
    }

    res.status(200).json({
      success: true,
      data: {
        accountId: id,
        accountName: account.accountName,
        balance: account.currentBalance,
      },
    });
  } catch (error) {
    console.error('Error fetching account balance:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch account balance',
      error: error.message,
    });
  }
});

/**
 * @route   PATCH /api/accounts/:id/status
 * @desc    Update account status (active/inactive)
 * @access  Private
 */
router.patch('/:id/status', async (req, res) => {
  try {
    const { id } = req.params;
    const { isActive } = req.body;

    if (!mongoose.Types.ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid account ID',
      });
    }

    if (typeof isActive !== 'boolean') {
      return res.status(400).json({
        success: false,
        message: 'isActive must be a boolean value',
      });
    }

    const updatedAccount = await PaymentAccount.findOneAndUpdate(
      { _id: id, ...(req.user?.orgId ? { orgId: req.user.orgId } : {}) },
      { isActive, updatedAt: Date.now() },
      { new: true }
    );

    if (!updatedAccount) {
      return res.status(404).json({
        success: false,
        message: 'Account not found',
      });
    }

    res.status(200).json({
      success: true,
      message: `Account ${isActive ? 'activated' : 'deactivated'} successfully`,
      data: updatedAccount,
    });
  } catch (error) {
    console.error('Error updating account status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update account status',
      error: error.message,
    });
  }
});

// ============================================================================
// EXPORT ROUTER
// ============================================================================

module.exports = router;