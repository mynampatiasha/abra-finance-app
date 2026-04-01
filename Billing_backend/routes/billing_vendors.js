// ============================================================================
// BILLING VENDORS API ROUTES
// ============================================================================
// File: routes/billing_vendors.js
// 
// Features:
// - CRUD operations for vendors (both internal employees and external vendors)
// - Support for bank details (optional)
// - Support for address (optional)
// - Search and filter functionality
// - Soft delete support
// - JWT authentication required
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const { verifyFinanceJWT: verifyToken } = require('../middleware/finance_jwt');

// ============================================================================
// VENDOR SCHEMA
// ============================================================================

const vendorSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  // Basic Information
  vendorId: {
    type: String,
    unique: true,
    required: true,
  },
  vendorType: {
    type: String,
    enum: ['Internal Employee', 'External Vendor', 'Contractor', 'Freelancer'],
    required: true,
    default: 'External Vendor',
  },
  vendorName: {
    type: String,
    required: true,
    trim: true,
  },
  companyName: {
    type: String,
    trim: true,
    default: '',
  },
  email: {
    type: String,
    required: true,
    trim: true,
    lowercase: true,
  },
  phoneNumber: {
    type: String,
    required: true,
    trim: true,
  },
  alternatePhone: {
    type: String,
    trim: true,
    default: '',
  },
  
  // Status
  status: {
    type: String,
    enum: ['Active', 'Inactive', 'Blocked', 'Pending Approval'],
    default: 'Active',
  },
  
  // Bank Details (Optional)
  bankDetailsProvided: {
    type: Boolean,
    default: false,
  },
  accountHolderName: {
    type: String,
    trim: true,
    default: '',
  },
  bankName: {
    type: String,
    trim: true,
    default: '',
  },
  accountNumber: {
    type: String,
    trim: true,
    default: '',
  },
  ifscCode: {
    type: String,
    trim: true,
    uppercase: true,
    default: '',
  },
  
  // Address (Optional)
  addressProvided: {
    type: Boolean,
    default: false,
  },
  addressLine1: {
    type: String,
    trim: true,
    default: '',
  },
  addressLine2: {
    type: String,
    trim: true,
    default: '',
  },
  city: {
    type: String,
    trim: true,
    default: '',
  },
  state: {
    type: String,
    trim: true,
    default: '',
  },
  postalCode: {
    type: String,
    trim: true,
    default: '',
  },
  country: {
    type: String,
    trim: true,
    default: 'India',
  },
  
  // Additional Information
  gstNumber: {
    type: String,
    trim: true,
    default: '',
  },
  panNumber: {
    type: String,
    trim: true,
    uppercase: true,
    default: '',
  },
  serviceCategory: {
    type: String,
    trim: true,
    default: '',
  },
  notes: {
    type: String,
    trim: true,
    default: '',
  },
  
  // Audit Fields
  createdBy: {
    type: String,
    required: true,
  },
  createdDate: {
    type: Date,
    default: Date.now,
  },
  lastModifiedBy: {
    type: String,
    default: '',
  },
  lastModifiedDate: {
    type: Date,
    default: Date.now,
  },
  
  // Soft Delete
  isDeleted: {
    type: Boolean,
    default: false,
  },
  deletedBy: {
    type: String,
    default: '',
  },
  deletedDate: {
    type: Date,
    default: null,
  },
});

// Indexes for better query performance
vendorSchema.index({ orgId: 1 });
vendorSchema.index({ vendorId: 1 });
vendorSchema.index({ email: 1 });
vendorSchema.index({ phoneNumber: 1 });
vendorSchema.index({ vendorType: 1 });
vendorSchema.index({ status: 1 });
vendorSchema.index({ isDeleted: 1 });
vendorSchema.index({ createdDate: -1 });

const Vendor = mongoose.models.BillingVendor || mongoose.model('BillingVendor', vendorSchema);

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

// Generate unique vendor ID
async function generateVendorId(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(Vendor, 'vendorId', 'VEN', orgId);
}

// Validate email format
function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

// Validate phone number (Indian format)
function isValidPhone(phone) {
  const phoneRegex = /^[6-9]\d{9}$/;
  return phoneRegex.test(phone.replace(/[\s-]/g, ''));
}

// Validate IFSC code
function isValidIFSC(ifsc) {
  const ifscRegex = /^[A-Z]{4}0[A-Z0-9]{6}$/;
  return ifscRegex.test(ifsc);
}

// Validate PAN number
function isValidPAN(pan) {
  const panRegex = /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/;
  return panRegex.test(pan);
}

// ============================================================================
// ROUTES
// ============================================================================

// CREATE NEW VENDOR
router.post('/', verifyToken, async (req, res) => {
  try {
    console.log('📝 Creating new vendor...');
    console.log('Request body:', JSON.stringify(req.body, null, 2));
    
    const {
      vendorType,
      vendorName,
      companyName,
      email,
      phoneNumber,
      alternatePhone,
      status,
      bankDetailsProvided,
      accountHolderName,
      bankName,
      accountNumber,
      accountNumberConfirm,
      ifscCode,
      addressProvided,
      addressLine1,
      addressLine2,
      city,
      state,
      postalCode,
      country,
      gstNumber,
      panNumber,
      serviceCategory,
      notes,
    } = req.body;
    
    // Validation
    const errors = [];
    
    // Required fields
    if (!vendorName || vendorName.trim() === '') {
      errors.push('Vendor name is required');
    }
    if (!email || email.trim() === '') {
      errors.push('Email is required');
    } else if (!isValidEmail(email)) {
      errors.push('Invalid email format');
    }
    if (!phoneNumber || phoneNumber.trim() === '') {
      errors.push('Phone number is required');
    } else if (!isValidPhone(phoneNumber)) {
      errors.push('Invalid phone number format');
    }
    
    // Check for duplicate email
    const existingVendor = await Vendor.findOne({ 
      email: email.toLowerCase().trim(),
      isDeleted: false,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (existingVendor) {
      errors.push('A vendor with this email already exists');
    }
    
    // Bank details validation (if provided)
    if (bankDetailsProvided) {
      if (!accountHolderName || accountHolderName.trim() === '') {
        errors.push('Account holder name is required when bank details are provided');
      }
      if (!bankName || bankName.trim() === '') {
        errors.push('Bank name is required when bank details are provided');
      }
      if (!accountNumber || accountNumber.trim() === '') {
        errors.push('Account number is required when bank details are provided');
      }
      if (!accountNumberConfirm || accountNumberConfirm.trim() === '') {
        errors.push('Please confirm account number');
      }
      if (accountNumber !== accountNumberConfirm) {
        errors.push('Account numbers do not match');
      }
      if (!ifscCode || ifscCode.trim() === '') {
        errors.push('IFSC code is required when bank details are provided');
      } else if (!isValidIFSC(ifscCode)) {
        errors.push('Invalid IFSC code format');
      }
    }
    
    // PAN validation (if provided)
    if (panNumber && panNumber.trim() !== '' && !isValidPAN(panNumber)) {
      errors.push('Invalid PAN number format');
    }
    
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors,
      });
    }
    
    // Generate vendor ID
    const vendorId = await generateVendorId(req.user?.orgId || null);
      vendorType: vendorType || 'External Vendor',
      vendorName: vendorName.trim(),
      companyName: companyName?.trim() || '',
      email: email.toLowerCase().trim(),
      phoneNumber: phoneNumber.trim(),
      alternatePhone: alternatePhone?.trim() || '',
      status: status || 'Active',
      bankDetailsProvided: bankDetailsProvided || false,
      accountHolderName: accountHolderName?.trim() || '',
      bankName: bankName?.trim() || '',
      accountNumber: accountNumber?.trim() || '',
      ifscCode: ifscCode?.toUpperCase().trim() || '',
      addressProvided: addressProvided || false,
      addressLine1: addressLine1?.trim() || '',
      addressLine2: addressLine2?.trim() || '',
      city: city?.trim() || '',
      state: state?.trim() || '',
      postalCode: postalCode?.trim() || '',
      country: country?.trim() || 'India',
      gstNumber: gstNumber?.trim() || '',
      panNumber: panNumber?.toUpperCase().trim() || '',
      serviceCategory: serviceCategory?.trim() || '',
      notes: notes?.trim() || '',
      createdBy: req.user.email || 'system',
      createdDate: new Date(),
      lastModifiedBy: req.user.email || 'system',
      lastModifiedDate: new Date(),
    });
    
    await vendor.save();
    
    console.log('✅ Vendor created successfully:', vendorId);
    
    res.status(201).json({
      success: true,
      message: 'Vendor created successfully',
      data: vendor,
    });
    
  } catch (error) {
    console.error('❌ Error creating vendor:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create vendor',
      error: error.message,
    });
  }
});

// GET ALL VENDORS (with filters and pagination)
router.get('/', verifyToken, async (req, res) => {
  try {
    console.log('📋 Fetching vendors...');
    
    const {
      search,
      vendorType,
      status,
      page = 1,
      limit = 1000,
      sortBy = 'createdDate',
      sortOrder = 'desc',
    } = req.query;
    
    // Build query
    const query = { isDeleted: false };
    if (req.user?.orgId) query.orgId = req.user.orgId;
    
    // Search filter
    if (search) {
      query.$or = [
        { vendorName: { $regex: search, $options: 'i' } },
        { companyName: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { phoneNumber: { $regex: search, $options: 'i' } },
        { vendorId: { $regex: search, $options: 'i' } },
      ];
    }
    
    // Type filter
    if (vendorType && vendorType !== 'All Types') {
      query.vendorType = vendorType;
    }
    
    // Status filter
    if (status && status !== 'All Statuses') {
      query.status = status;
    }
    
    // Pagination
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Sort
    const sortOptions = {};
    sortOptions[sortBy] = sortOrder === 'asc' ? 1 : -1;
    
    // Execute query
    const [vendors, totalCount] = await Promise.all([
      Vendor.find(query)
        .sort(sortOptions)
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      Vendor.countDocuments(query),
    ]);
    
    // Get statistics
    const orgFilter = { isDeleted: false };
    if (req.user?.orgId) orgFilter.orgId = req.user.orgId;
    const statistics = await Vendor.aggregate([
      { $match: orgFilter },
      {
        $group: {
          _id: null,
          total: { $sum: 1 },
          active: {
            $sum: { $cond: [{ $eq: ['$status', 'Active'] }, 1, 0] },
          },
          inactive: {
            $sum: { $cond: [{ $eq: ['$status', 'Inactive'] }, 1, 0] },
          },
          internal: {
            $sum: { $cond: [{ $eq: ['$vendorType', 'Internal Employee'] }, 1, 0] },
          },
          external: {
            $sum: { $cond: [{ $eq: ['$vendorType', 'External Vendor'] }, 1, 0] },
          },
        },
      },
    ]);
    
    console.log(`✅ Found ${vendors.length} vendors`);
    
    res.json({
      success: true,
      data: {
        vendors,
        pagination: {
          currentPage: parseInt(page),
          totalPages: Math.ceil(totalCount / parseInt(limit)),
          totalCount,
          limit: parseInt(limit),
        },
        statistics: statistics[0] || {
          total: 0,
          active: 0,
          inactive: 0,
          internal: 0,
          external: 0,
        },
      },
    });
    
  } catch (error) {
    console.error('❌ Error fetching vendors:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch vendors',
      error: error.message,
    });
  }
});

// GET VENDOR BY ID
router.get('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    console.log(`📄 Fetching vendor: ${id}`);
    
    const vendor = await Vendor.findOne({
      $or: [
        { _id: mongoose.Types.ObjectId.isValid(id) ? id : null },
        { vendorId: id },
      ],
      isDeleted: false,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!vendor) {
      return res.status(404).json({
        success: false,
        message: 'Vendor not found',
      });
    }
    
    console.log('✅ Vendor found');
    
    res.json({
      success: true,
      data: vendor,
    });
    
  } catch (error) {
    console.error('❌ Error fetching vendor:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch vendor',
      error: error.message,
    });
  }
});

// UPDATE VENDOR
router.put('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    console.log(`✏️ Updating vendor: ${id}`);
    
    const vendor = await Vendor.findOne({
      $or: [
        { _id: mongoose.Types.ObjectId.isValid(id) ? id : null },
        { vendorId: id },
      ],
      isDeleted: false,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!vendor) {
      return res.status(404).json({
        success: false,
        message: 'Vendor not found',
      });
    }
    
    const {
      vendorType,
      vendorName,
      companyName,
      email,
      phoneNumber,
      alternatePhone,
      status,
      bankDetailsProvided,
      accountHolderName,
      bankName,
      accountNumber,
      accountNumberConfirm,
      ifscCode,
      addressProvided,
      addressLine1,
      addressLine2,
      city,
      state,
      postalCode,
      country,
      gstNumber,
      panNumber,
      serviceCategory,
      notes,
    } = req.body;
    
    // Validation
    const errors = [];
    
    // Required fields
    if (vendorName !== undefined && vendorName.trim() === '') {
      errors.push('Vendor name is required');
    }
    if (email !== undefined) {
      if (email.trim() === '') {
        errors.push('Email is required');
      } else if (!isValidEmail(email)) {
        errors.push('Invalid email format');
      } else if (email.toLowerCase().trim() !== vendor.email) {
        // Check for duplicate email (only if email is being changed)
        const existingVendor = await Vendor.findOne({
          email: email.toLowerCase().trim(),
          isDeleted: false,
          _id: { $ne: vendor._id },
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        });
        if (existingVendor) {
          errors.push('A vendor with this email already exists');
        }
      }
    }
    if (phoneNumber !== undefined && phoneNumber.trim() === '') {
      errors.push('Phone number is required');
    } else if (phoneNumber !== undefined && !isValidPhone(phoneNumber)) {
      errors.push('Invalid phone number format');
    }
    
    // Bank details validation (if provided)
    if (bankDetailsProvided) {
      if (accountHolderName !== undefined && accountHolderName.trim() === '') {
        errors.push('Account holder name is required when bank details are provided');
      }
      if (bankName !== undefined && bankName.trim() === '') {
        errors.push('Bank name is required when bank details are provided');
      }
      if (accountNumber !== undefined && accountNumber.trim() === '') {
        errors.push('Account number is required when bank details are provided');
      }
      if (accountNumber && accountNumberConfirm && accountNumber !== accountNumberConfirm) {
        errors.push('Account numbers do not match');
      }
      if (ifscCode !== undefined && ifscCode.trim() === '') {
        errors.push('IFSC code is required when bank details are provided');
      } else if (ifscCode !== undefined && !isValidIFSC(ifscCode)) {
        errors.push('Invalid IFSC code format');
      }
    }
    
    // PAN validation (if provided)
    if (panNumber && panNumber.trim() !== '' && !isValidPAN(panNumber)) {
      errors.push('Invalid PAN number format');
    }
    
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors,
      });
    }
    
    // Update fields
    if (vendorType !== undefined) vendor.vendorType = vendorType;
    if (vendorName !== undefined) vendor.vendorName = vendorName.trim();
    if (companyName !== undefined) vendor.companyName = companyName.trim();
    if (email !== undefined) vendor.email = email.toLowerCase().trim();
    if (phoneNumber !== undefined) vendor.phoneNumber = phoneNumber.trim();
    if (alternatePhone !== undefined) vendor.alternatePhone = alternatePhone.trim();
    if (status !== undefined) vendor.status = status;
    
    // Bank details
    if (bankDetailsProvided !== undefined) vendor.bankDetailsProvided = bankDetailsProvided;
    if (accountHolderName !== undefined) vendor.accountHolderName = accountHolderName.trim();
    if (bankName !== undefined) vendor.bankName = bankName.trim();
    if (accountNumber !== undefined) vendor.accountNumber = accountNumber.trim();
    if (ifscCode !== undefined) vendor.ifscCode = ifscCode.toUpperCase().trim();
    
    // Address
    if (addressProvided !== undefined) vendor.addressProvided = addressProvided;
    if (addressLine1 !== undefined) vendor.addressLine1 = addressLine1.trim();
    if (addressLine2 !== undefined) vendor.addressLine2 = addressLine2.trim();
    if (city !== undefined) vendor.city = city.trim();
    if (state !== undefined) vendor.state = state.trim();
    if (postalCode !== undefined) vendor.postalCode = postalCode.trim();
    if (country !== undefined) vendor.country = country.trim();
    
    // Additional info
    if (gstNumber !== undefined) vendor.gstNumber = gstNumber.trim();
    if (panNumber !== undefined) vendor.panNumber = panNumber.toUpperCase().trim();
    if (serviceCategory !== undefined) vendor.serviceCategory = serviceCategory.trim();
    if (notes !== undefined) vendor.notes = notes.trim();
    
    // Update audit fields
    vendor.lastModifiedBy = req.user.email || 'system';
    vendor.lastModifiedDate = new Date();
    
    await vendor.save();
    
    console.log('✅ Vendor updated successfully');
    
    res.json({
      success: true,
      message: 'Vendor updated successfully',
      data: vendor,
    });
    
  } catch (error) {
    console.error('❌ Error updating vendor:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update vendor',
      error: error.message,
    });
  }
});

// DELETE VENDOR (Soft delete)
router.delete('/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    console.log(`🗑️ Deleting vendor: ${id}`);
    
    const vendor = await Vendor.findOne({
      $or: [
        { _id: mongoose.Types.ObjectId.isValid(id) ? id : null },
        { vendorId: id },
      ],
      isDeleted: false,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!vendor) {
      return res.status(404).json({
        success: false,
        message: 'Vendor not found',
      });
    }
    
    // Soft delete
    vendor.isDeleted = true;
    vendor.deletedBy = req.user.email || 'system';
    vendor.deletedDate = new Date();
    
    await vendor.save();
    
    console.log('✅ Vendor deleted successfully');
    
    res.json({
      success: true,
      message: 'Vendor deleted successfully',
    });
    
  } catch (error) {
    console.error('❌ Error deleting vendor:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete vendor',
      error: error.message,
    });
  }
});

// BULK IMPORT VENDORS
router.post('/bulk-import', verifyToken, async (req, res) => {
  try {
    console.log('📦 BULK IMPORT VENDORS');
    
    const { vendors } = req.body;
    
    if (!vendors || !Array.isArray(vendors) || vendors.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No vendor data provided',
      });
    }
    
    console.log(`Processing ${vendors.length} vendors...`);
    
    const results = {
      successCount: 0,
      failedCount: 0,
      totalProcessed: vendors.length,
      errors: [],
    };
    
    for (let i = 0; i < vendors.length; i++) {
      try {
        const vendorData = vendors[i];
        
        // Check for duplicate email
        const existingVendor = await Vendor.findOne({
          email: vendorData.email.toLowerCase().trim(),
          isDeleted: false,
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        });
        
        if (existingVendor) {
          results.failedCount++;
          results.errors.push(`Row ${i + 2}: Email ${vendorData.email} already exists`);
          continue;
        }
        
        // Validate phone number
        if (!isValidPhone(vendorData.phoneNumber)) {
          results.failedCount++;
          results.errors.push(`Row ${i + 2}: Invalid phone number format`);
          continue;
        }
        
        // Validate bank details if provided
        if (vendorData.bankDetailsProvided) {
          if (!vendorData.accountHolderName || !vendorData.bankName || 
              !vendorData.accountNumber || !vendorData.ifscCode) {
            results.failedCount++;
            results.errors.push(`Row ${i + 2}: Missing required bank details`);
            continue;
          }
          
          if (!isValidIFSC(vendorData.ifscCode)) {
            results.failedCount++;
            results.errors.push(`Row ${i + 2}: Invalid IFSC code format`);
            continue;
          }
        }
        
        // Validate PAN if provided
        if (vendorData.panNumber && vendorData.panNumber.trim() !== '' && 
            !isValidPAN(vendorData.panNumber)) {
          results.failedCount++;
          results.errors.push(`Row ${i + 2}: Invalid PAN number format`);
          continue;
        }
        
        // Generate vendor ID
        const vendorId = await generateVendorId(req.user?.orgId || null);
        
        // Create vendor
        const vendor = new Vendor({
          vendorId,
          orgId: req.user?.orgId || null,
          vendorType: vendorData.vendorType,
          vendorName: vendorData.vendorName.trim(),
          companyName: vendorData.companyName?.trim() || '',
          email: vendorData.email.toLowerCase().trim(),
          phoneNumber: vendorData.phoneNumber.trim(),
          alternatePhone: vendorData.alternatePhone?.trim() || '',
          status: vendorData.status || 'Active',
          bankDetailsProvided: vendorData.bankDetailsProvided || false,
          accountHolderName: vendorData.accountHolderName?.trim() || '',
          bankName: vendorData.bankName?.trim() || '',
          accountNumber: vendorData.accountNumber?.trim() || '',
          ifscCode: vendorData.ifscCode?.toUpperCase().trim() || '',
          addressProvided: vendorData.addressProvided || false,
          addressLine1: vendorData.addressLine1?.trim() || '',
          addressLine2: vendorData.addressLine2?.trim() || '',
          city: vendorData.city?.trim() || '',
          state: vendorData.state?.trim() || '',
          postalCode: vendorData.postalCode?.trim() || '',
          country: vendorData.country?.trim() || 'India',
          gstNumber: vendorData.gstNumber?.trim() || '',
          panNumber: vendorData.panNumber?.toUpperCase().trim() || '',
          serviceCategory: vendorData.serviceCategory?.trim() || '',
          notes: vendorData.notes?.trim() || '',
          createdBy: req.user.email || 'system',
          createdDate: new Date(),
          lastModifiedBy: req.user.email || 'system',
          lastModifiedDate: new Date(),
        });
        
        await vendor.save();
        results.successCount++;
        
      } catch (error) {
        results.failedCount++;
        results.errors.push(`Row ${i + 2}: ${error.message}`);
      }
    }
    
    console.log(`✅ Import complete: ${results.successCount} success, ${results.failedCount} failed`);
    
    res.status(200).json({
      success: true,
      message: 'Bulk import completed',
      data: results,
    });
    
  } catch (error) {
    console.error('❌ Error in bulk import:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to import vendors',
      error: error.message,
    });
  }
});

module.exports = router;