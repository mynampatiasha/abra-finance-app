// ============================================================================
// BILLING CUSTOMERS - COMPLETE BACKEND
// ============================================================================
// File: routes/billing-customers.js
// Collection: billing-customers
// 
// This file contains:
// - Mongoose Schema & Model
// - Controllers (CRUD operations)
// - Routes with file upload support
// - All customer types: Individual, Organization, Vendor, Others
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const emailService = require('../services/email_service');

// ============================================================================
// FILE UPLOAD CONFIGURATION
// ============================================================================

// Ensure uploads directory exists
const uploadsDir = path.join(__dirname, '../uploads/billing-customers');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
  console.log('✅ Created uploads directory:', uploadsDir);
}

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const category = req.body.category || 'Other Documents';
    const categoryPath = path.join(uploadsDir, category.replace(/[^a-z0-9]/gi, '_').toLowerCase());
    
    if (!fs.existsSync(categoryPath)) {
      fs.mkdirSync(categoryPath, { recursive: true });
    }
    
    cb(null, categoryPath);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const fileFilter = (req, file, cb) => {
  // Accept all file types
  cb(null, true);
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB limit per file
  }
});

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const contactPersonSchema = new mongoose.Schema({
  contactType: {
    type: String,
    enum: ['Primary Contact', 'Billing Contact', 'Operations Contact', 'Accounts Contact', 'Emergency Contact'],
    required: true
  },
  fullName: { type: String, required: true, trim: true },
  email: { 
    type: String, 
    required: true, 
    trim: true,
    lowercase: true,
    match: [/^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/, 'Invalid email format']
  },
  phoneNumber: { 
    type: String, 
    required: true,
    match: [/^[+]?[0-9]{10,15}$/, 'Invalid phone number']
  },
  designation: { type: String, trim: true },
  department: { type: String, trim: true },
  isPrimary: { type: Boolean, default: false }
}, { _id: true });

const customFieldSchema = new mongoose.Schema({
  fieldName: { type: String, required: true, trim: true },
  fieldType: {
    type: String,
    enum: ['Text', 'Number', 'Date', 'Dropdown', 'Checkbox', 'Email', 'Phone'],
    required: true
  },
  fieldValue: { type: String, trim: true },
  isMandatory: { type: Boolean, default: false }
}, { _id: true });

const uploadedDocumentSchema = new mongoose.Schema({
  category: {
    type: String,
    enum: ['KYC Documents', 'Company Documents', 'Contracts & Agreements', 'Insurance Documents', 'Vehicle Documents', 'Other Documents'],
    required: true
  },
  fileName: { type: String, required: true },
  originalName: { type: String, required: true },
  filePath: { type: String, required: true },
  fileSize: { type: Number, required: true },
  fileExtension: { type: String },
  uploadedAt: { type: Date, default: Date.now },
  uploadedBy: { type: String }
}, { _id: true });

const billingCustomerSchema = new mongoose.Schema({
  // ============================================================================
  // SECTION 1: BASIC INFORMATION
  // ============================================================================
  customerId: { 
    type: String, 
    required: true, 
    unique: true,
    index: true 
  },
  customerType: {
    type: String,
    required: true,
    enum: ['Individual', 'Organization', 'Vendor', 'Others'],
    index: true
  },
  customerDisplayName: { type: String, required: true, trim: true, index: true },
  primaryContactPerson: { type: String, trim: true },
  primaryEmail: {
    type: String,
    required: true,
    trim: true,
    lowercase: true,
    index: true,
    match: [/^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/, 'Invalid email format']
  },
  primaryPhone: {
    type: String,
    required: true,
    index: true,
    match: [/^[+]?[0-9]{10,15}$/, 'Invalid phone number']
  },
  alternatePhone: { 
    type: String,
    match: [/^[+]?[0-9]{10,15}$/, 'Invalid phone number']
  },
  addressLine1: { type: String, required: true, trim: true },
  addressLine2: { type: String, trim: true },
  city: { type: String, required: true, trim: true, index: true },
  state: { type: String, required: true, trim: true },
  postalCode: { type: String, trim: true },
  country: { type: String, required: true, default: 'India' },

  // ============================================================================
  // SECTION 2: COMPANY DETAILS
  // ============================================================================
  companyRegistration: { type: String, trim: true },
  panNumber: { 
    type: String, 
    trim: true,
    uppercase: true,
    match: [/^[A-Z]{5}[0-9]{4}[A-Z]{1}$/, 'Invalid PAN format']
  },
  gstNumber: { 
    type: String, 
    trim: true,
    uppercase: true,
    index: true,
    match: [/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/, 'Invalid GST format']
  },
  tanNumber: { 
    type: String, 
    trim: true,
    uppercase: true 
  },
  industryType: {
    type: String,
    enum: ['IT & Software', 'Manufacturing', 'Retail', 'Healthcare', 'Education', 'Finance', 'Real Estate', 'Transportation', 'Hospitality', 'Other', null]
  },
  employeeStrength: { type: Number, min: 0 },
  annualContractValue: { type: Number, min: 0 },

  // ============================================================================
  // SECTION 3: CONTACT PERSONS
  // ============================================================================
  contactPersons: [contactPersonSchema],

  // ============================================================================
  // SECTION 4: CATEGORIZATION & SEGMENTATION
  // ============================================================================
  customerStatus: {
    type: String,
    required: true,
    enum: ['Active', 'Inactive', 'Blocked', 'Lead', 'Closed'],
    default: 'Active',
    index: true
  },
  reasonForBlocking: { type: String, trim: true },
  customerTier: {
    type: String,
    enum: ['Gold', 'Silver', 'Bronze', 'Platinum', null],
    index: true
  },
  salesTerritory: { 
    type: String, 
    required: true,
    index: true 
  },
  tags: [{
    type: String,
    enum: ['VIP', 'Regular', 'Seasonal', 'Corporate', 'Government', 'High-Value', 'Low-Priority']
  }],

  // ============================================================================
  // SECTION 5: RATE CARD & PRICING
  // ============================================================================
  rateCard: { type: String },
  contractType: {
    type: String,
    enum: ['Fixed Monthly', 'Quarterly', 'Per-trip', 'Pay-as-you-go', null]
  },
  contractStartDate: { type: Date },
  contractEndDate: { type: Date },
  autoRenewal: { type: Boolean, default: false },
  renewalNoticePeriod: { type: Number, min: 0 }, // in days

  // Vendor-specific rate card fields
  vendorCommissionType: {
    type: String,
    enum: ['Percentage', 'Fixed Amount per Trip', 'Revenue Share', null]
  },
  commissionRate: { type: Number, min: 0, max: 100 }, // percentage
  fixedAmountPerTrip: { type: Number, min: 0 },
  revenueShare: { type: Number, min: 0, max: 100 }, // percentage
  minimumGuarantee: { type: Number, min: 0 },
  paymentCycle: {
    type: String,
    enum: ['Daily', 'Weekly', 'Bi-weekly', 'Monthly', 'Quarterly', null]
  },
  vehicleTypesProvided: [{
    type: String,
    enum: ['Sedan', 'SUV', 'Hatchback', 'Bus', 'Mini Van', 'Tempo Traveller', 'Luxury Car']
  }],
  numberOfVehiclesProvided: { type: Number, min: 0 },

  // ============================================================================
  // SECTION 6: PAYMENT TERMS & CREDIT
  // ============================================================================
  paymentTerms: {
    type: String,
    required: true,
    enum: ['Immediate/COD', '7 days', '15 days', '30 days', '45 days', '60 days', 'NET 90'],
    default: 'Immediate/COD'
  },
  preferredPaymentMethod: {
    type: String,
    enum: ['Cash', 'UPI', 'Bank Transfer', 'Credit Card', 'Cheque', 'Online Payment Gateway', null]
  },
  creditLimit: { type: Number, min: 0, default: 0 },
  securityDeposit: { type: Number, min: 0 },
  securityDepositStatus: {
    type: String,
    enum: ['Received', 'Pending', 'Refunded', null]
  },
  blockBookingIfCreditExceeded: { type: Boolean, default: false },
  billingFrequency: {
    type: String,
    required: true,
    enum: ['Per-trip', 'Weekly', 'Bi-weekly', 'Monthly', 'Quarterly'],
    default: 'Per-trip'
  },

  // ============================================================================
  // SECTION 7: BILLING PREFERENCES
  // ============================================================================
  billingEmail: { 
    type: String,
    trim: true,
    lowercase: true,
    match: [/^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/, 'Invalid email format']
  },
  billingAddress: { type: String, trim: true },
  sameAsPrimaryAddress: { type: Boolean, default: true },
  poNumberRequired: { type: Boolean, default: false },
  invoiceDeliveryMethods: [{
    type: String,
    enum: ['Email', 'WhatsApp', 'SMS', 'Portal Download', 'Postal Mail']
  }],
  invoiceLanguage: {
    type: String,
    enum: ['English', 'Hindi', 'Tamil', 'Telugu', 'Kannada', 'Malayalam'],
    default: 'English'
  },
  taxRegistrationType: {
    type: String,
    enum: ['Registered', 'Unregistered', 'Composition', null]
  },

  // ============================================================================
  // SECTION 8: VENDOR-SPECIFIC DETAILS
  // ============================================================================
  vendorVehiclesAvailable: { type: Number, min: 0 },
  vendorVehicleTypes: [{
    type: String,
    enum: ['Sedan', 'SUV', 'Hatchback', 'Bus', 'Mini Van', 'Tempo Traveller', 'Luxury Car']
  }],
  vendorAgreementStart: { type: Date },
  vendorAgreementEnd: { type: Date },
  vendorPerformanceRating: { type: Number, min: 0, max: 5, default: 0 },
  insuranceValidUntil: { type: Date },
  
  // Bank Details
  bankName: { type: String, trim: true },
  bankAccountNumber: { type: String, trim: true },
  ifscCode: { 
    type: String, 
    trim: true,
    uppercase: true 
  },
  accountHolderName: { type: String, trim: true },
  branchName: { type: String, trim: true },
  upiId: { type: String, trim: true },

  // ============================================================================
  // SECTION 9: DOCUMENT UPLOADS
  // ============================================================================
  uploadedDocuments: [uploadedDocumentSchema],

  // ============================================================================
  // SECTION 10: ADDITIONAL INFORMATION
  // ============================================================================
  internalNotes: { type: String, trim: true },
  customerInstructions: { type: String, trim: true },
  specialRequirements: { type: String, trim: true },
  customFields: [customFieldSchema],

  // ============================================================================
  // SECTION 11: AUDIT & TRACKING
  // ============================================================================
  orgId: { type: String, index: true, default: null },
  createdBy: { type: String, required: true },
  createdDate: { type: Date, default: Date.now },
  lastModifiedBy: { type: String },
  lastModifiedDate: { type: Date },
  lastTransactionDate: { type: Date },
  totalRevenueGenerated: { type: Number, default: 0, min: 0 },
  totalTripsCompleted: { type: Number, default: 0, min: 0 },

  // ============================================================================
  // PASSWORD RESET TOKENS
  // ============================================================================
  passwordResetToken: { type: String },
  passwordResetExpires: { type: Date },

  // ============================================================================
  // METADATA
  // ============================================================================
  isDeleted: { type: Boolean, default: false },
  deletedAt: { type: Date },
  deletedBy: { type: String }

}, {
  timestamps: true,
  collection: 'billing-customers'
});

// ============================================================================
// INDEXES FOR PERFORMANCE
// ============================================================================
billingCustomerSchema.index({ customerType: 1, customerStatus: 1 });
billingCustomerSchema.index({ salesTerritory: 1, customerStatus: 1 });
billingCustomerSchema.index({ customerTier: 1, customerStatus: 1 });
billingCustomerSchema.index({ createdDate: -1 });
billingCustomerSchema.index({ gstNumber: 1 }, { sparse: true });
billingCustomerSchema.index({ tags: 1 });

// ============================================================================
// VIRTUAL FIELDS
// ============================================================================
billingCustomerSchema.virtual('displayType').get(function() {
  return this.customerType;
});

billingCustomerSchema.virtual('isActive').get(function() {
  return this.customerStatus === 'Active';
});

billingCustomerSchema.virtual('hasDocuments').get(function() {
  return this.uploadedDocuments && this.uploadedDocuments.length > 0;
});

// ============================================================================
// METHODS
// ============================================================================
billingCustomerSchema.methods.toSafeObject = function() {
  const obj = this.toObject({ virtuals: true });
  delete obj.__v;
  return obj;
};

// ============================================================================
// STATIC METHODS
// ============================================================================
billingCustomerSchema.statics.findByType = function(customerType) {
  return this.find({ customerType, isDeleted: false }).sort({ createdDate: -1 });
};

billingCustomerSchema.statics.findActive = function() {
  return this.find({ customerStatus: 'Active', isDeleted: false }).sort({ createdDate: -1 });
};

billingCustomerSchema.statics.findByTerritory = function(territory) {
  return this.find({ salesTerritory: territory, isDeleted: false }).sort({ createdDate: -1 });
};

billingCustomerSchema.statics.findByTier = function(tier) {
  return this.find({ customerTier: tier, isDeleted: false }).sort({ createdDate: -1 });
};

// ============================================================================
// PRE-SAVE MIDDLEWARE
// ============================================================================
billingCustomerSchema.pre('save', async function() {
  if (!this.customerId) {
    const timestamp = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
    this.customerId = `CUST-${timestamp}`;
  }
  if (!this.billingEmail && this.primaryEmail) {
    this.billingEmail = this.primaryEmail;
  }
  if (this.sameAsPrimaryAddress) {
    this.billingAddress = `${this.addressLine1 || ''} ${this.city || ''} ${this.state || ''}`.trim();
  }
});


// Delete cached model first, then recreate
if (mongoose.models.BillingCustomer) {
  delete mongoose.models.BillingCustomer;
}
const BillingCustomer = mongoose.model('BillingCustomer', billingCustomerSchema);
// ============================================================================
// CREATE MODEL (SAFE - CHECK IF ALREADY EXISTS)
// ============================================================================
// const BillingCustomer = mongoose.models.BillingCustomer || mongoose.model('BillingCustomer', billingCustomerSchema);

// ============================================================================
// CONTROLLERS
// ============================================================================

/**
 * @desc    Get all billing customers with filters
 * @route   GET /api/billing-customers
 * @access  Private
 */
const getAllCustomers = async (req, res) => {
  try {
    console.log('\n📋 GET ALL BILLING CUSTOMERS');
    console.log('─'.repeat(80));

    const {
      customerType,
      customerStatus,
      salesTerritory,
      customerTier,
      search,
      page = 1,
      limit = 50,
      sortBy = 'createdDate',
      sortOrder = 'desc',
      skipStats = 'false'
    } = req.query;

    // Build query
    const query = { isDeleted: false };
    if (req.user?.orgId) query.orgId = req.user.orgId;

    if (customerType) query.customerType = customerType;
    if (customerStatus) query.customerStatus = customerStatus;
    if (salesTerritory) query.salesTerritory = salesTerritory;
    if (customerTier) query.customerTier = customerTier;

    // Search functionality
    if (search) {
      query.$or = [
        { customerDisplayName: { $regex: search, $options: 'i' } },
        { customerId: { $regex: search, $options: 'i' } },
        { primaryEmail: { $regex: search, $options: 'i' } },
        { primaryPhone: { $regex: search, $options: 'i' } },
        { gstNumber: { $regex: search, $options: 'i' } }
      ];
    }

    console.log('   Query:', JSON.stringify(query));

    // Execute query with pagination
    const skip = (parseInt(page) - 1) * parseInt(limit);
    const sort = { [sortBy]: sortOrder === 'desc' ? -1 : 1 };

    const [customers, totalCount] = await Promise.all([
      BillingCustomer.find(query)
        .sort(sort)
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      BillingCustomer.countDocuments(query)
    ]);

    console.log(`   ✅ Found ${customers.length} customers (Total: ${totalCount})`);

    // Calculate statistics (skip when caller just needs the list)
    let statistics = { totalCustomers: 0, activeCustomers: 0, inactiveCustomers: 0, blockedCustomers: 0, totalRevenue: 0, totalTrips: 0 };
    if (skipStats !== 'true') {
      const stats = await BillingCustomer.aggregate([
        { $match: { isDeleted: false } },
        {
          $group: {
            _id: null,
            totalCustomers: { $sum: 1 },
            activeCustomers: { $sum: { $cond: [{ $eq: ['$customerStatus', 'Active'] }, 1, 0] } },
            inactiveCustomers: { $sum: { $cond: [{ $eq: ['$customerStatus', 'Inactive'] }, 1, 0] } },
            blockedCustomers: { $sum: { $cond: [{ $eq: ['$customerStatus', 'Blocked'] }, 1, 0] } },
            totalRevenue: { $sum: '$totalRevenueGenerated' },
            totalTrips: { $sum: '$totalTripsCompleted' }
          }
        }
      ]);
      statistics = stats[0] || statistics;
    }

    res.json({
      success: true,
      message: 'Billing customers retrieved successfully',
      data: {
        customers,
        pagination: {
          currentPage: parseInt(page),
          totalPages: Math.ceil(totalCount / parseInt(limit)),
          totalCount,
          pageSize: parseInt(limit),
          hasMore: skip + customers.length < totalCount
        },
        statistics
      }
    });

  } catch (error) {
    console.error('❌ GET ALL CUSTOMERS FAILED:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve billing customers',
      message: error.message
    });
  }
};

/**
 * @desc    Get single billing customer by ID
 * @route   GET /api/billing-customers/:id
 * @access  Private
 */
const getCustomerById = async (req, res) => {
  try {
    console.log('\n🔍 GET BILLING CUSTOMER BY ID');
    console.log('─'.repeat(80));
    console.log('   ID:', req.params.id);

    const customer = await BillingCustomer.findOne({
      _id: req.params.id,
      isDeleted: false
    }).lean();

    if (!customer) {
      console.log('   ❌ Customer not found');
      return res.status(404).json({
        success: false,
        error: 'Customer not found',
        message: 'No billing customer found with this ID'
      });
    }

    console.log('   ✅ Customer found:', customer.customerDisplayName);

    res.json({
      success: true,
      message: 'Billing customer retrieved successfully',
      data: customer
    });

  } catch (error) {
    console.error('❌ GET CUSTOMER BY ID FAILED:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve billing customer',
      message: error.message
    });
  }
};

/**
 * @desc    Create new billing customer
 * @route   POST /api/billing-customers
 * @access  Private
 */
const createCustomer = async (req, res) => {
  try {
    console.log('\n➕ CREATE BILLING CUSTOMER');
    console.log('─'.repeat(80));
    console.log('   Data:', JSON.stringify(req.body, null, 2));

    const customerData = {
      ...req.body,
      orgId: req.user?.orgId || null,
      createdBy: req.user?.email || req.user?.name || 'System',
      createdDate: new Date()
    };

    const customer = new BillingCustomer(customerData);
    await customer.save();

    console.log('   ✅ Customer created:', customer.customerId);

    // Send welcome email
    if (customer.primaryEmail) {
      try {
        console.log('\n📧 Sending welcome email to customer...');

        const resetToken = crypto.randomBytes(32).toString('hex');
        const resetTokenExpiry = new Date(Date.now() + 3600000);

        // Use findByIdAndUpdate to avoid triggering pre-save again
        await BillingCustomer.findByIdAndUpdate(customer._id, {
          passwordResetToken: resetToken,
          passwordResetExpires: resetTokenExpiry,
        });

        const resetLink = `${process.env.FRONTEND_URL}/reset-password?token=${resetToken}&email=${encodeURIComponent(customer.primaryEmail)}`;

        await emailService.sendCustomerApprovalEmail({
          email: customer.primaryEmail,
          name: customer.customerDisplayName || customer.primaryContactPerson || 'Customer',
          companyName: customer.customerType === 'Organization' ? customer.customerDisplayName : null,
          passwordResetLink: resetLink
        });

        console.log('   ✅ Welcome email sent to:', customer.primaryEmail);
      } catch (emailError) {
        console.error('   ⚠️ Failed to send welcome email:', emailError.message);
      }
    }

    res.status(201).json({
      success: true,
      message: 'Billing customer created successfully',
      data: customer.toSafeObject()
    });

  } catch (error) {
    console.error('❌ CREATE CUSTOMER FAILED:', error);

    if (error.name === 'ValidationError') {
      const errors = Object.values(error.errors).map(err => err.message);
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: errors.join(', '),
        details: errors
      });
    }

    if (error.code === 11000) {
      return res.status(409).json({
        success: false,
        error: 'Duplicate entry',
        message: 'A customer with this ID or email already exists'
      });
    }

    res.status(500).json({
      success: false,
      error: 'Failed to create billing customer',
      message: error.message
    });
  }
};

/**
 * @desc    Update billing customer
 * @route   PUT /api/billing-customers/:id
 * @access  Private
 */
const updateCustomer = async (req, res) => {
  try {
    console.log('\n✏️  UPDATE BILLING CUSTOMER');
    console.log('─'.repeat(80));
    console.log('   ID:', req.params.id);

    // Find customer
    const customer = await BillingCustomer.findOne({
      _id: req.params.id,
      isDeleted: false
    });

    if (!customer) {
      console.log('   ❌ Customer not found');
      return res.status(404).json({
        success: false,
        error: 'Customer not found',
        message: 'No billing customer found with this ID'
      });
    }

    // Update fields
    Object.assign(customer, req.body);
    customer.lastModifiedBy = req.user?.email || req.user?.name || 'System';
    customer.lastModifiedDate = new Date();

    await customer.save();

    console.log('   ✅ Customer updated:', customer.customerId);

    res.json({
      success: true,
      message: 'Billing customer updated successfully',
      data: customer.toSafeObject()
    });

  } catch (error) {
    console.error('❌ UPDATE CUSTOMER FAILED:', error);

    if (error.name === 'ValidationError') {
      const errors = Object.values(error.errors).map(err => err.message);
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: errors.join(', '),
        details: errors
      });
    }

    res.status(500).json({
      success: false,
      error: 'Failed to update billing customer',
      message: error.message
    });
  }
};

/**
 * @desc    Delete billing customer (soft delete)
 * @route   DELETE /api/billing-customers/:id
 * @access  Private
 */
const deleteCustomer = async (req, res) => {
  try {
    console.log('\n🗑️  DELETE BILLING CUSTOMER');
    console.log('─'.repeat(80));
    console.log('   ID:', req.params.id);

    const customer = await BillingCustomer.findOne({
      _id: req.params.id,
      isDeleted: false
    });

    if (!customer) {
      console.log('   ❌ Customer not found');
      return res.status(404).json({
        success: false,
        error: 'Customer not found',
        message: 'No billing customer found with this ID'
      });
    }

    // Soft delete
    customer.isDeleted = true;
    customer.deletedAt = new Date();
    customer.deletedBy = req.user?.email || req.user?.name || 'System';
    await customer.save();

    console.log('   ✅ Customer deleted:', customer.customerId);

    res.json({
      success: true,
      message: 'Billing customer deleted successfully',
      data: { customerId: customer.customerId }
    });

  } catch (error) {
    console.error('❌ DELETE CUSTOMER FAILED:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete billing customer',
      message: error.message
    });
  }
};

/**
 * @desc    Upload documents for billing customer
 * @route   POST /api/billing-customers/:id/upload-documents
 * @access  Private
 */
const uploadDocuments = async (req, res) => {
  try {
    console.log('\n📤 UPLOAD DOCUMENTS');
    console.log('─'.repeat(80));
    console.log('   Customer ID:', req.params.id);
    console.log('   Category:', req.body.category);
    console.log('   Files:', req.files?.length || 0);

    const customer = await BillingCustomer.findOne({
      _id: req.params.id,
      isDeleted: false
    });

    if (!customer) {
      return res.status(404).json({
        success: false,
        error: 'Customer not found'
      });
    }

    if (!req.files || req.files.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No files uploaded'
      });
    }

    // Add uploaded files to customer documents
    const uploadedDocs = req.files.map(file => ({
      category: req.body.category || 'Other Documents',
      fileName: file.filename,
      originalName: file.originalname,
      filePath: file.path,
      fileSize: file.size,
      fileExtension: path.extname(file.originalname),
      uploadedAt: new Date(),
      uploadedBy: req.user?.email || 'System'
    }));

    customer.uploadedDocuments.push(...uploadedDocs);
    customer.lastModifiedBy = req.user?.email || 'System';
    customer.lastModifiedDate = new Date();

    await customer.save();

    console.log(`   ✅ Uploaded ${uploadedDocs.length} documents`);

    res.json({
      success: true,
      message: 'Documents uploaded successfully',
      data: {
        uploadedCount: uploadedDocs.length,
        documents: uploadedDocs
      }
    });

  } catch (error) {
    console.error('❌ UPLOAD DOCUMENTS FAILED:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to upload documents',
      message: error.message
    });
  }
};

/**
 * @desc    Get customers by type
 * @route   GET /api/billing-customers/type/:customerType
 * @access  Private
 */
const getCustomersByType = async (req, res) => {
  try {
    console.log('\n📊 GET CUSTOMERS BY TYPE');
    console.log('─'.repeat(80));
    console.log('   Type:', req.params.customerType);

    const customers = await BillingCustomer.findByType(req.params.customerType);

    console.log(`   ✅ Found ${customers.length} customers`);

    res.json({
      success: true,
      message: `${req.params.customerType} customers retrieved successfully`,
      data: {
        customerType: req.params.customerType,
        count: customers.length,
        customers
      }
    });

  } catch (error) {
    console.error('❌ GET CUSTOMERS BY TYPE FAILED:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve customers',
      message: error.message
    });
  }
};

/**
 * @desc    Get customer statistics
 * @route   GET /api/billing-customers/statistics/overview
 * @access  Private
 */
const getStatistics = async (req, res) => {
  try {
    console.log('\n📊 GET CUSTOMER STATISTICS');
    console.log('─'.repeat(80));

    const stats = await BillingCustomer.aggregate([
      { $match: { isDeleted: false } },
      {
        $facet: {
          byType: [
            { $group: { _id: '$customerType', count: { $sum: 1 } } }
          ],
          byStatus: [
            { $group: { _id: '$customerStatus', count: { $sum: 1 } } }
          ],
          byTier: [
            { $group: { _id: '$customerTier', count: { $sum: 1 } } }
          ],
          byTerritory: [
            { $group: { _id: '$salesTerritory', count: { $sum: 1 } } }
          ],
          revenue: [
            {
              $group: {
                _id: null,
                totalRevenue: { $sum: '$totalRevenueGenerated' },
                totalTrips: { $sum: '$totalTripsCompleted' },
                avgRevenue: { $avg: '$totalRevenueGenerated' }
              }
            }
          ]
        }
      }
    ]);

    console.log('   ✅ Statistics calculated');

    res.json({
      success: true,
      message: 'Customer statistics retrieved successfully',
      data: stats[0]
    });

  } catch (error) {
    console.error('❌ GET STATISTICS FAILED:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve statistics',
      message: error.message
    });
  }
};

// ============================================================================
// ROUTES
// ============================================================================

// Statistics
router.get('/statistics/overview', getStatistics);

// Get by type
router.get('/type/:customerType', getCustomersByType);

// CRUD operations
router.get('/', getAllCustomers);
router.get('/:id', getCustomerById);
router.post('/', createCustomer);
router.put('/:id', updateCustomer);
router.delete('/:id', deleteCustomer);

// Document upload
router.post('/:id/upload-documents', upload.array('documents', 10), uploadDocuments);

// ============================================================================
// EXPORT
// ============================================================================

const bulkImportCustomers = async (req, res) => {
  try {
    console.log('\n📤 BULK IMPORT CUSTOMERS');
    console.log('─'.repeat(80));

    const { customers } = req.body;

    if (!customers || !Array.isArray(customers) || customers.length === 0) {
      return res.status(400).json({
        success: false,
        error: 'No customers data provided',
      });
    }

    console.log(`   Processing ${customers.length} customers...`);

    let successCount = 0;
    let failedCount  = 0;
    const errors = [];

    for (let i = 0; i < customers.length; i++) {
      try {
        const customerData = { ...customers[i] };

        // Generate customer ID
        if (!customerData.customerId) {
          const timestamp = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
          customerData.customerId = `CUST-${timestamp}-${i}`;
        }

        customerData.createdBy   = req.user?.email || req.user?.name || 'System';
        customerData.createdDate = new Date();

        // Strip empty strings from regex-validated optional fields
        const optionalRegexFields = [
          'panNumber', 'gstNumber', 'tanNumber', 'companyRegistration',
          'alternatePhone', 'postalCode', 'addressLine2', 'primaryContactPerson',
          'billingEmail', 'upiId', 'ifscCode', 'bankAccountNumber',
          'bankName', 'accountHolderName', 'branchName'
        ];
        for (const field of optionalRegexFields) {
          if (customerData[field] === '' || customerData[field] === null || customerData[field] === undefined) {
            delete customerData[field];
          }
        }

        // Strip invalid enum values
        const validIndustryTypes = [
          'IT & Software', 'Manufacturing', 'Retail', 'Healthcare',
          'Education', 'Finance', 'Real Estate', 'Transportation', 'Hospitality', 'Other'
        ];
        if (customerData.industryType && !validIndustryTypes.includes(customerData.industryType)) {
          delete customerData.industryType;
        }

        const validTiers = ['Gold', 'Silver', 'Bronze', 'Platinum'];
        if (customerData.customerTier && !validTiers.includes(customerData.customerTier)) {
          delete customerData.customerTier;
        }

        // Save customer
        const customer = new BillingCustomer({ ...customerData, orgId: req.user?.orgId || null });
        await customer.save();

        successCount++;
        console.log(`   ✅ Customer ${i + 1}/${customers.length}: ${customerData.customerDisplayName}`);

      } catch (error) {
        failedCount++;
        errors.push(`Row ${i + 1}: ${error.message}`);
        console.log(`   ❌ Customer ${i + 1}/${customers.length}: ${error.message}`);
      }
    }

    console.log(`   📊 Import Summary: Success=${successCount} Failed=${failedCount}`);

    res.json({
      success: true,
      message: 'Bulk import completed',
      data: {
        totalProcessed: customers.length,
        successCount,
        failedCount,
        emailsSent: 0,
        emailsFailed: 0,
        errors: errors.length > 0 ? errors : undefined,
      }
    });

  } catch (error) {
    console.error('❌ BULK IMPORT FAILED:', error);
    res.status(500).json({
      success: false,
      error: 'Bulk import failed',
      message: error.message
    });
  }
};

// Add route
router.post('/bulk-import', bulkImportCustomers);

module.exports = router;

console.log('✅ Billing Customers module loaded successfully');
console.log('   Collection: billing-customers');
console.log('   Customer Types: Individual, Organization, Vendor, Others');
console.log('   Features: CRUD, File Upload, Statistics, Search, Filtering');