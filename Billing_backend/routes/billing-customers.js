// ============================================================================
// BILLING CUSTOMERS - COMPLETE BACKEND (ZOHO BOOKS STYLE)
// ============================================================================
// File: routes/billing-customers.js
// Collection: billing-customers
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

// ============================================================================
// FILE UPLOAD CONFIGURATION
// ============================================================================

const uploadsDir = path.join(__dirname, '../uploads/billing-customers');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const category = req.body.category || 'Other Documents';
    const categoryPath = path.join(uploadsDir, category.replace(/[^a-z0-9]/gi, '_').toLowerCase());
    if (!fs.existsSync(categoryPath)) fs.mkdirSync(categoryPath, { recursive: true });
    cb(null, categoryPath);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({
  storage,
  fileFilter: (req, file, cb) => cb(null, true),
  limits: { fileSize: 10 * 1024 * 1024 }
});

// ============================================================================
// ALL 28 INDIAN STATES + 8 UTs
// ============================================================================
const INDIAN_STATES = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh',
  'Assam', 'Bihar', 'Chandigarh', 'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat',
  'Haryana', 'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand',
  'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep', 'Madhya Pradesh',
  'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland',
  'Odisha', 'Puducherry', 'Punjab', 'Rajasthan', 'Sikkim',
  'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
  'West Bengal'
];

// ============================================================================
// SUB-SCHEMAS
// ============================================================================

const addressSchema = new mongoose.Schema({
  attention: { type: String, trim: true },
  street:    { type: String, trim: true },
  street2:   { type: String, trim: true },
  city:      { type: String, trim: true },
  state:     { type: String, trim: true },
  zip:       { type: String, trim: true },
  country:   { type: String, trim: true, default: 'India' },
  phone:     { type: String, trim: true },
  fax:       { type: String, trim: true },
}, { _id: false });

const contactPersonSchema = new mongoose.Schema({
  salutation:  { type: String, enum: ['Mr.', 'Mrs.', 'Ms.', 'Miss.', 'Dr.', ''], default: '' },
  firstName:   { type: String, trim: true },
  lastName:    { type: String, trim: true },
  email:       { type: String, trim: true, lowercase: true },
  workPhone:   { type: String, trim: true },
  mobile:      { type: String, trim: true },
  designation: { type: String, trim: true },
  department:  { type: String, trim: true },
  isPrimary:   { type: Boolean, default: false },
  portalAccess:{ type: Boolean, default: false },
}, { _id: true });

const commentSchema = new mongoose.Schema({
  text:      { type: String, required: true, trim: true },
  createdBy: { type: String, default: 'system' },
  createdAt: { type: Date, default: Date.now },
}, { _id: true });

const uploadedDocumentSchema = new mongoose.Schema({
  category:     { type: String, enum: ['KYC Documents', 'Company Documents', 'Contracts & Agreements', 'Insurance Documents', 'Vehicle Documents', 'Other Documents'], required: true },
  fileName:     { type: String, required: true },
  originalName: { type: String, required: true },
  filePath:     { type: String, required: true },
  fileSize:     { type: Number, required: true },
  fileExtension:{ type: String },
  uploadedAt:   { type: Date, default: Date.now },
  uploadedBy:   { type: String },
}, { _id: true });

const customFieldSchema = new mongoose.Schema({
  fieldName:  { type: String, required: true, trim: true },
  fieldType:  { type: String, enum: ['Text', 'Number', 'Date', 'Dropdown', 'Checkbox', 'Email', 'Phone'], required: true },
  fieldValue: { type: String, trim: true },
  isMandatory:{ type: Boolean, default: false },
}, { _id: true });

// ============================================================================
// MAIN SCHEMA
// ============================================================================

const billingCustomerSchema = new mongoose.Schema({

  // -- Identity --------------------------------------------------------------
  customerId: { type: String, unique: true, index: true },

  // -- Basic -----------------------------------------------------------------
  customerType: {
    type: String,
    required: true,
    enum: ['Individual', 'Business'],   // Zoho: Individual / Business
    default: 'Individual',
    index: true,
  },
  salutation:          { type: String, enum: ['Mr.', 'Mrs.', 'Ms.', 'Miss.', 'Dr.', ''], default: '' },
  firstName:           { type: String, trim: true },
  lastName:            { type: String, trim: true },
  customerDisplayName: { type: String, required: true, trim: true, index: true },
  companyName:         { type: String, trim: true },

  // -- Contact ---------------------------------------------------------------
  primaryEmail:  { type: String, required: true, trim: true, lowercase: true, index: true },
  primaryPhone:  { type: String, required: true, index: true },
  workPhone:     { type: String, trim: true },
  mobile:        { type: String, trim: true },
  fax:           { type: String, trim: true },
  website:       { type: String, trim: true },
  facebook:      { type: String, trim: true },
  twitter:       { type: String, trim: true },

  // -- Address ---------------------------------------------------------------
  billingAddress:  { type: addressSchema, default: () => ({}) },
  shippingAddress: { type: addressSchema, default: () => ({}) },

  // -- Tax Info (Zoho style) -------------------------------------------------
  gstNumber: {
    type: String, trim: true, uppercase: true, index: true,
    match: [/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$|^$/, 'Invalid GST format'],
  },
  gstRegistrationType: {
    type: String,
    enum: [
      'Registered Business - Regular',
      'Registered Business - Composition',
      'Unregistered Business',
      'Consumer',
      'Overseas',
      'Special Economic Zone',
      'Deemed Export',
      '',
    ],
    default: '',
  },
  placeOfSupply: { type: String, enum: [...INDIAN_STATES, ''], default: '' },
  panNumber: {
    type: String, trim: true, uppercase: true,
    match: [/^[A-Z]{5}[0-9]{4}[A-Z]{1}$|^$/, 'Invalid PAN format'],
  },
  taxPreference:  { type: String, enum: ['Taxable', 'Tax Exempt', ''], default: 'Taxable' },
  exemptionReason:{ type: String, trim: true },

  // -- Financials ------------------------------------------------------------
  defaultCurrency: { type: String, default: 'INR' },
  openingBalance:  { type: Number, default: 0 },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60', 'NET 90', 'Custom', ''],
    default: 'Due on Receipt',
  },
  creditLimit:   { type: Number, min: 0, default: 0 },

  // -- Portal ----------------------------------------------------------------
  portalLanguage: { type: String, default: 'English' },
  portalEnabled:  { type: Boolean, default: false },

  // -- Contact Persons -------------------------------------------------------
  contactPersons: [contactPersonSchema],

  // -- Remarks / Comments ----------------------------------------------------
  remarks:  { type: String, trim: true },
  comments: [commentSchema],

  // -- Categorization (kept from your original) ------------------------------
  customerStatus: {
    type: String,
    required: true,
    enum: ['Active', 'Inactive', 'Blocked', 'Lead', 'Closed'],
    default: 'Active',
    index: true,
  },
  reasonForBlocking: { type: String, trim: true },
  customerTier: { type: String, enum: ['Gold', 'Silver', 'Bronze', 'Platinum', ''], default: '' },
  salesTerritory: { type: String, default: '', index: true },
  tags: [{ type: String }],

  // -- Rate Card / Contract -------------------------------------------------
  rateCard:             { type: String },
  contractType:         { type: String },
  contractStartDate:    { type: Date },
  contractEndDate:      { type: Date },
  autoRenewal:          { type: Boolean, default: false },
  renewalNoticePeriod:  { type: Number, min: 0 },

  // -- Payment / Billing -----------------------------------------------------
  preferredPaymentMethod: { type: String },
  securityDeposit:        { type: Number, min: 0 },
  securityDepositStatus:  { type: String, enum: ['Received', 'Pending', 'Refunded', ''], default: '' },
  billingFrequency: {
    type: String,
    enum: ['Per-trip', 'Weekly', 'Bi-weekly', 'Monthly', 'Quarterly', ''],
    default: 'Per-trip',
  },
  billingEmail:        { type: String, trim: true, lowercase: true },
  poNumberRequired:    { type: Boolean, default: false },
  invoiceDeliveryMethods: [{ type: String }],
  invoiceLanguage:     { type: String, default: 'English' },

  // -- Vendor fields ---------------------------------------------------------
  vendorCommissionType:      { type: String },
  commissionRate:            { type: Number },
  fixedAmountPerTrip:        { type: Number },
  revenueShare:              { type: Number },
  minimumGuarantee:          { type: Number },
  paymentCycle:              { type: String },
  vehicleTypesProvided:      [{ type: String }],
  numberOfVehiclesProvided:  { type: Number },
  vendorVehiclesAvailable:   { type: Number },
  vendorVehicleTypes:        [{ type: String }],
  vendorAgreementStart:      { type: Date },
  vendorAgreementEnd:        { type: Date },
  vendorPerformanceRating:   { type: Number, min: 0, max: 5, default: 0 },
  insuranceValidUntil:       { type: Date },

  // -- Bank Details ----------------------------------------------------------
  bankName:           { type: String, trim: true },
  bankAccountNumber:  { type: String, trim: true },
  ifscCode:           { type: String, trim: true, uppercase: true },
  accountHolderName:  { type: String, trim: true },
  branchName:         { type: String, trim: true },
  upiId:              { type: String, trim: true },

  // -- Documents / Custom Fields ---------------------------------------------
  uploadedDocuments: [uploadedDocumentSchema],
  customFields:      [customFieldSchema],

  // -- Internal Notes --------------------------------------------------------
  internalNotes:        { type: String, trim: true },
  customerInstructions: { type: String, trim: true },
  specialRequirements:  { type: String, trim: true },

  // -- Stats (denormalized for speed) ----------------------------------------
  totalRevenueGenerated:  { type: Number, default: 0 },
  totalTripsCompleted:    { type: Number, default: 0 },
  lastTransactionDate:    { type: Date },

  // -- Unused Credits (excess payments not yet applied to invoices) ----------
  unusedCredits: { type: Number, default: 0, min: 0 },

  // -- Org / Audit -----------------------------------------------------------
  orgId:           { type: String, index: true, default: null },
  branchId:        { type: String, index: true, default: null },
  createdBy:       { type: String, required: true },
  createdDate:     { type: Date, default: Date.now },
  lastModifiedBy:  { type: String },
  lastModifiedDate:{ type: Date },

  // -- Soft delete -----------------------------------------------------------
  isDeleted:  { type: Boolean, default: false },
  deletedAt:  { type: Date },
  deletedBy:  { type: String },

  // -- Legacy flat address fields (kept for backward compat) -----------------
  addressLine1: { type: String },
  addressLine2: { type: String },
  city:         { type: String },
  state:        { type: String },
  postalCode:   { type: String },
  country:      { type: String, default: 'India' },
  primaryContactPerson: { type: String },
  alternatePhone:       { type: String },
  annualContractValue:  { type: Number },
  employeeStrength:     { type: Number },
  industryType:         { type: String },
  companyRegistration:  { type: String },
  tanNumber:            { type: String },
  taxRegistrationType:  { type: String },   // old field � kept
  sameAsPrimaryAddress: { type: Boolean, default: true },
  blockBookingIfCreditExceeded: { type: Boolean, default: false },

}, { timestamps: true, collection: 'billing-customers' });

// -- Indexes -------------------------------------------------------------------
billingCustomerSchema.index({ customerType: 1, customerStatus: 1 });
billingCustomerSchema.index({ salesTerritory: 1, customerStatus: 1 });
billingCustomerSchema.index({ createdDate: -1 });
billingCustomerSchema.index({ gstNumber: 1 }, { sparse: true });

// -- Virtuals ------------------------------------------------------------------
billingCustomerSchema.virtual('isActive').get(function () {
  return this.customerStatus === 'Active';
});
billingCustomerSchema.virtual('fullName').get(function () {
  return [this.salutation, this.firstName, this.lastName].filter(Boolean).join(' ');
});

// -- Pre-save ------------------------------------------------------------------
billingCustomerSchema.pre('save', async function () {
  if (!this.customerId) {
    const ts = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
    this.customerId = `CUST-${ts}`;
  }
  if (!this.billingEmail && this.primaryEmail) {
    this.billingEmail = this.primaryEmail;
  }
  // Sync legacy flat fields from billingAddress if present
  if (this.billingAddress && this.billingAddress.street) {
    this.addressLine1 = this.billingAddress.street;
    this.city         = this.billingAddress.city;
    this.state        = this.billingAddress.state;
    this.postalCode   = this.billingAddress.zip;
    this.country      = this.billingAddress.country || 'India';
  }
});

billingCustomerSchema.methods.toSafeObject = function () {
  const obj = this.toObject({ virtuals: true });
  delete obj.__v;
  return obj;
};

if (mongoose.models.BillingCustomer) delete mongoose.models.BillingCustomer;
const BillingCustomer = mongoose.model('BillingCustomer', billingCustomerSchema);

// ============================================================================
// HELPER � get Invoice model safely
// ============================================================================
function getInvoiceModel() {
  return mongoose.models.Invoice
    || mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');
}

// ============================================================================
// CONTROLLERS
// ============================================================================

// GET /  � list with filters
const getAllCustomers = async (req, res) => {
  try {
    const {
      customerType, customerStatus, salesTerritory, customerTier,
      search, page = 1, limit = 50,
      sortBy = 'createdDate', sortOrder = 'desc',
      skipStats = 'false',
    } = req.query;

    const query = { isDeleted: false };
    if (req.user?.orgId) query.orgId = req.user.orgId;
    Object.assign(query, req.branchFilter || {});
    if (customerType)   query.customerType   = customerType;
    if (customerStatus) query.customerStatus = customerStatus;
    if (salesTerritory) query.salesTerritory = salesTerritory;
    if (customerTier)   query.customerTier   = customerTier;
    if (search) {
      query.$or = [
        { customerDisplayName: { $regex: search, $options: 'i' } },
        { customerId:          { $regex: search, $options: 'i' } },
        { primaryEmail:        { $regex: search, $options: 'i' } },
        { primaryPhone:        { $regex: search, $options: 'i' } },
        { companyName:         { $regex: search, $options: 'i' } },
        { gstNumber:           { $regex: search, $options: 'i' } },
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const sort = { [sortBy]: sortOrder === 'desc' ? -1 : 1 };

    const [customers, totalCount] = await Promise.all([
      BillingCustomer.find(query).sort(sort).skip(skip).limit(parseInt(limit)).lean(),
      BillingCustomer.countDocuments(query),
    ]);

    const Invoice = getInvoiceModel();
    let receivablesMap = {};
    try {
      const customerIds = customers.map(c => c._id?.toString());
      const receivablesAgg = await Invoice.aggregate([
        {
          $match: {
            customerId: { $in: customerIds },
            status: { $in: ['SENT', 'UNPAID', 'PARTIALLY_PAID', 'OVERDUE'] },
            ...req.orgFilter,
            ...(req.branchFilter || {}),
          },
        },
        {
          $group: {
            _id: '$customerId',
            outstandingReceivables: { $sum: '$amountDue' },
          },
        },
      ]);
      receivablesAgg.forEach(r => { receivablesMap[r._id] = r.outstandingReceivables; });
    } catch (e) {
      // Invoice collection may not exist yet � safe to ignore
    }

    const customersWithReceivables = customers.map(c => ({
      ...c,
      outstandingReceivables: receivablesMap[c._id?.toString()] || 0,
      unusedCredits: c.unusedCredits || 0,
    }));

    let statistics = { totalCustomers: 0, activeCustomers: 0, inactiveCustomers: 0, blockedCustomers: 0 };
    if (skipStats !== 'true') {
      const stats = await BillingCustomer.aggregate([
        { $match: { isDeleted: false, ...req.orgFilter, ...(req.branchFilter || {}) } },
        {
          $group: {
            _id: null,
            totalCustomers:    { $sum: 1 },
            activeCustomers:   { $sum: { $cond: [{ $eq: ['$customerStatus', 'Active'] },   1, 0] } },
            inactiveCustomers: { $sum: { $cond: [{ $eq: ['$customerStatus', 'Inactive'] }, 1, 0] } },
            blockedCustomers:  { $sum: { $cond: [{ $eq: ['$customerStatus', 'Blocked'] },  1, 0] } },
          },
        },
      ]);
      if (stats[0]) statistics = stats[0];
    }

    res.json({
      success: true,
      data: {
        customers: customersWithReceivables,
        pagination: {
          currentPage: parseInt(page),
          totalPages:  Math.ceil(totalCount / parseInt(limit)),
          totalCount,
          pageSize:    parseInt(limit),
          hasMore:     skip + customers.length < totalCount,
        },
        statistics,
      },
    });
  } catch (error) {
    console.error('? getAllCustomers:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// GET /:id
const getCustomerById = async (req, res) => {
  try {
    const query = { _id: req.params.id, isDeleted: false };
    if (req.user?.orgId) query.orgId = req.user.orgId;
    Object.assign(query, req.branchFilter || {});
    const customer = await BillingCustomer.findOne(query).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });
    res.json({ success: true, data: customer });
  } catch (error) {
    console.error('? getCustomerById:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// GET /:id/overview  � receivables + income chart data
const getCustomerOverview = async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const Invoice = getInvoiceModel();
    let outstandingReceivables = 0;
    let unusedCredits = customer.unusedCredits || 0;
    let monthlyIncome = [];

    if (Invoice) {
      // Outstanding receivables
      const receivablesAgg = await Invoice.aggregate([
        {
          $match: {
            customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
            status: { $in: ['SENT', 'UNPAID', 'PARTIALLY_PAID', 'OVERDUE'] },
            ...req.orgFilter,
          },
        },
        { $group: { _id: null, total: { $sum: '$amountDue' } } },
      ]);
      outstandingReceivables = receivablesAgg[0]?.total || 0;

      // Monthly income - last 6 months
      const sixMonthsAgo = new Date();
      sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 5);
      sixMonthsAgo.setDate(1);
      sixMonthsAgo.setHours(0, 0, 0, 0);

      const incomeAgg = await Invoice.aggregate([
        {
          $match: {
            customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
            invoiceDate: { $gte: sixMonthsAgo },
            status: { $nin: ['CANCELLED', 'VOID'] },
            ...req.orgFilter,
          },
        },
        {
          $group: {
            _id: { year: { $year: '$invoiceDate' }, month: { $month: '$invoiceDate' } },
            total: { $sum: '$totalAmount' },
            count: { $sum: 1 },
          },
        },
        { $sort: { '_id.year': 1, '_id.month': 1 } },
      ]);

      // Build all 6 month slots
      const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const now = new Date();
      for (let i = 5; i >= 0; i--) {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        const found = incomeAgg.find(a => a._id.year === d.getFullYear() && a._id.month === d.getMonth() + 1);
        monthlyIncome.push({
          month: monthNames[d.getMonth()],
          year:  d.getFullYear(),
          total: found?.total || 0,
          count: found?.count || 0,
        });
      }
    }

    res.json({
      success: true,
      data: {
        customer,
        receivables: {
          currency: customer.defaultCurrency || 'INR',
          outstandingReceivables,
          unusedCredits,
        },
        monthlyIncome,
      },
    });
  } catch (error) {
    console.error('? getCustomerOverview:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// GET /:id/transactions
const getCustomerTransactions = async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const Invoice = getInvoiceModel();
    let transactions = [];

    if (Invoice) {
      const invoices = await Invoice.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId] },
        ...req.orgFilter,
      }).sort({ invoiceDate: -1 }).lean();

      // Invoices
      transactions = invoices.map(inv => ({
        type:     'Invoice',
        id:       inv._id,
        number:   inv.invoiceNumber,
        date:     inv.invoiceDate,
        dueDate:  inv.dueDate,
        status:   inv.status,
        amount:   inv.totalAmount,
        balance:  inv.amountDue,
      }));

      // Payments from each invoice
      for (const inv of invoices) {
        for (const p of (inv.payments || [])) {
          transactions.push({
            type:   'Payment',
            id:     p.paymentId,
            number: inv.invoiceNumber,
            date:   p.paymentDate || p.recordedAt,
            status: 'PAID',
            amount: p.amount,
            balance: 0,
            method: p.paymentMethod,
          });
        }
      }

      // Sort by date desc
      transactions.sort((a, b) => new Date(b.date) - new Date(a.date));
    }

    res.json({ success: true, data: transactions });
  } catch (error) {
    console.error('? getCustomerTransactions:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// GET /:id/mails
const getCustomerMails = async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const Invoice = getInvoiceModel();
    let mails = [];

    if (Invoice) {
      const customerIdValues = [
        customer._id?.toString(),
        customer.customerId,
      ].filter(Boolean);

      const orConditions = [{ customerId: { $in: customerIdValues } }];
      if (customer.primaryEmail) orConditions.push({ customerEmail: customer.primaryEmail });

      const invoices = await Invoice.find({
        $or: orConditions,
        $or: [
          { 'emailsSent.0': { $exists: true } },
          { 'reminderLog.0': { $exists: true } },
        ],
        ...req.orgFilter,
      }).lean();

      for (const inv of invoices) {
        // ── Email entries ──────────────────────────────────────────────────
        for (const email of (inv.emailsSent || [])) {
          mails.push({
            invoiceNumber: inv.invoiceNumber,
            invoiceId:     inv._id,
            customerName:  inv.customerName  || customer.customerDisplayName || '',
            sentTo:        email.sentTo,
            sentAt:        email.sentAt,
            emailType:     email.emailType || 'invoice',
            channel:       'email',
            subject:       `Invoice ${inv.invoiceNumber} — ₹${(inv.totalAmount || 0).toFixed(2)}`,
            amount:        inv.totalAmount || 0,
            success:       true,
            reminderType:  null,
          });
        }

        // ── WhatsApp / reminder log entries ───────────────────────────────
        for (const log of (inv.reminderLog || [])) {
          mails.push({
            invoiceNumber: inv.invoiceNumber,
            invoiceId:     inv._id,
            customerName:  inv.customerName  || customer.customerDisplayName || '',
            customerPhone: inv.customerPhone || customer.primaryPhone || '',
            sentTo:        log.recipientPhone || log.recipientEmail || '',
            sentAt:        log.sentAt,
            emailType:     log.channel === 'whatsapp' ? 'whatsapp' : 'reminder',
            channel:       log.channel || 'email',
            subject:       log.channel === 'whatsapp'
              ? `WhatsApp ${log.type === 'predue' ? 'Pre-Due' : 'Overdue'} — Invoice ${inv.invoiceNumber}`
              : `Reminder Email — Invoice ${inv.invoiceNumber}`,
            amount:        inv.totalAmount || 0,
            success:       log.success !== false,
            failReason:    log.failReason || null,
            reminderType:  log.type || 'overdue',
            // Pass invoice data for message preview
            amountDue:     inv.amountDue || 0,
            dueDate:       inv.dueDate,
            daysOverdue:   log.type === 'overdue'
              ? String(Math.max(0, Math.floor((new Date(log.sentAt) - new Date(inv.dueDate)) / 86400000)))
              : '0',
          });
        }
      }

      mails.sort((a, b) => new Date(b.sentAt) - new Date(a.sentAt));
    }

    res.json({ success: true, data: mails });
  } catch (error) {
    console.error('❌ getCustomerMails:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// GET /:id/statement
const getCustomerStatement = async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const { fromDate, toDate } = req.query;
    const from = fromDate ? new Date(fromDate) : new Date(new Date().setFullYear(new Date().getFullYear() - 1));
    const to   = toDate   ? new Date(toDate)   : new Date();
    to.setHours(23, 59, 59, 999);
    from.setHours(0, 0, 0, 0);

    const Invoice = getInvoiceModel();
    let entries = [];
    let openingBalance = customer.openingBalance || 0;
    const custIdStr = customer._id?.toString();
    const custId2   = customer.customerId;

    // Helper to parse dates which might be 'DD/MM/YYYY' strings or Date objects
    const parseCustomDate = (dateVal, timeSource) => {
      if (!dateVal) return null;
      let parsed = null;
      if (dateVal instanceof Date) {
        parsed = new Date(dateVal);
      } else {
        const str = String(dateVal);
        if (str.includes('/')) {
          const parts = str.split('/');
          if (parts.length === 3) {
            // DD/MM/YYYY
            parsed = new Date(parts[2], parts[1] - 1, parts[0]);
          }
        } else {
          parsed = new Date(str);
        }
      }
      
      if (parsed && !isNaN(parsed.getTime())) {
        if (timeSource) {
          const tDate = new Date(timeSource);
          if (!isNaN(tDate.getTime())) {
            parsed.setHours(tDate.getHours(), tDate.getMinutes(), tDate.getSeconds());
          }
        }
        return parsed;
      }
      return null;
    };

    if (Invoice) {
      // ── 1. Fetch all invoices in date range ─────────────────────────────
      const invoices = await Invoice.find({
        customerId: { $in: [custIdStr, custId2].filter(Boolean) },
        invoiceDate: { $gte: from, $lte: to },
        status: { $nin: ['CANCELLED', 'VOID'] },
        ...req.orgFilter,
      }).sort({ invoiceDate: 1 }).lean();

      // Add invoice entries
      for (const inv of invoices) {
        entries.push({
          date:     inv.invoiceDate,
          type:     'Invoice',
          number:   inv.invoiceNumber,
          details:  inv.subject || inv.orderNumber || '',
          invoices: inv.totalAmount,
          payments: null,
          balance:  null,
        });

        // ── 2a. Payments embedded inside invoice.payments[] ──────────────
        for (const p of (inv.payments || [])) {
          const pDate = parseCustomDate(p.paymentDate || p.recordedAt, p.recordedAt || p.paymentDate);
          if (!pDate) continue;
          // include all payments within range
          if (pDate >= from && pDate <= to) {
            entries.push({
              date:     pDate,
              type:     'Payment',
              number:   inv.invoiceNumber,
              details:  p.paymentMethod || p.paymentMode || 'Payment',
              invoices: null,
              payments: parseFloat(p.amount || 0),
              balance:  null,
            });
          }
        }
      }

      // ── 2b. Payments from payments_received collection (account_detail categorizations) ──
      try {
        const { getFinanceDb } = require('../config/database');
        const db = getFinanceDb();
        // Remove date filter from mongo query because dates are stored as 'DD/MM/YYYY' strings
        const paymentsReceived = await db.collection('payments_received').find({
          $or: [{ customerId: custIdStr }, { customerId: custId2 }, { customerId: customer._id }],
          paymentType: { $ne: 'advance' }, // exclude advance payments from statement
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        }).toArray();

        for (const p of paymentsReceived) {
          const pDate = parseCustomDate(p.paymentDate || p.createdAt, p.createdAt);
          if (!pDate) continue;

          
          // Filter by date manually
          if (pDate >= from && pDate <= to) {
            // Avoid duplicates — skip if already added via inv.payments[]
            const alreadyAdded = entries.some(e =>
              e.type === 'Payment' &&
              Math.abs(parseFloat(e.payments || 0) - parseFloat(p.amountReceived || p.netAmount || 0)) < 0.01 &&
              e.date.toDateString() === pDate.toDateString()
            );
            if (alreadyAdded) continue;

            // Find the invoice number for this payment
            let invoiceNum = '';
            if (p.invoicePayments && typeof p.invoicePayments === 'object') {
              const invKeys = Object.keys(p.invoicePayments);
              if (invKeys.length > 0) {
                const invId = invKeys[0];
                const foundInv = invoices.find(i => i._id?.toString() === invId);
                if (foundInv) {
                  invoiceNum = foundInv.invoiceNumber;
                } else {
                  try {
                    const fetchedInv = await Invoice.findOne({ _id: invId }).select('invoiceNumber').lean();
                    if (fetchedInv) invoiceNum = fetchedInv.invoiceNumber;
                  } catch (e) { /* ignore */ }
                }
              }
            }
            if (!invoiceNum) invoiceNum = p.paymentNumber || 'PMT';

            entries.push({
              date:     pDate,
              type:     'Payment',
              number:   invoiceNum,
              details:  p.paymentMode || p.paymentMethod || 'Payment',
              invoices: null,
              payments: parseFloat(p.amountReceived || p.netAmount || 0),
              balance:  null,
            });
          }
        }
      } catch (dbErr) {
        console.warn('⚠️ Could not fetch payments_received:', dbErr.message);
        // Non-fatal — continue with invoice-embedded payments only
      }

      // ── 3. Sort all entries by date ──────────────────────────────────────
      entries.sort((a, b) => new Date(a.date) - new Date(b.date));

      // ── 4. Running balance ───────────────────────────────────────────────
      let runningBalance = openingBalance;
      entries = entries.map(e => {
        if (e.invoices) runningBalance += e.invoices;
        if (e.payments) runningBalance -= e.payments;
        return { ...e, balance: runningBalance };
      });
    }

    res.json({
      success: true,
      data: {
        customer: { name: customer.customerDisplayName, email: customer.primaryEmail },
        openingBalance,
        entries,
        closingBalance: entries.length > 0 ? entries[entries.length - 1].balance : openingBalance,
        fromDate: from,
        toDate:   to,
      },
    });
  } catch (error) {
    console.error('❌ getCustomerStatement:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// POST /:id/comments
const addComment = async (req, res) => {
  try {
    const { text } = req.body;
    if (!text?.trim()) return res.status(400).json({ success: false, error: 'Comment text required' });

    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false });
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const comment = { text: text.trim(), createdBy: req.user?.email || 'system', createdAt: new Date() };
    customer.comments.push(comment);
    await customer.save();

    res.json({ success: true, data: customer.comments[customer.comments.length - 1] });
  } catch (error) {
    console.error('? addComment:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// DELETE /:id/comments/:commentId
const deleteComment = async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false });
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    customer.comments = customer.comments.filter(c => c._id.toString() !== req.params.commentId);
    await customer.save();
    res.json({ success: true, message: 'Comment deleted' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// POST /  � create
const createCustomer = async (req, res) => {
  try {
    console.log('🔍 branchIds:', req.branchIds);
    console.log('🔍 header:', req.headers['x-branch-ids']);
    // req.branchIds is the array of selected branch IDs (set by finance_jwt middleware)
    // Use the first selected branch ID as the customer's branch
    const branchId = (req.branchIds && req.branchIds.length > 0) ? req.branchIds[0] : null;
    const customerData = {
      ...req.body,
      orgId:     req.user?.orgId || null,
      branchId,
      createdBy: req.user?.email || req.user?.name || 'System',
      createdDate: new Date(),
    };
    const customer = new BillingCustomer(customerData);
    await customer.save();
    console.log('? Customer created:', customer.customerId);
    res.status(201).json({ success: true, message: 'Customer created successfully', data: customer.toSafeObject() });
  } catch (error) {
    console.error('? createCustomer:', error);
    if (error.name === 'ValidationError') {
      const errors = Object.values(error.errors).map(e => e.message);
      return res.status(400).json({ success: false, error: 'Validation failed', message: errors.join(', ') });
    }
    if (error.code === 11000) return res.status(409).json({ success: false, error: 'Duplicate entry', message: 'A customer with this ID already exists' });
    res.status(500).json({ success: false, error: error.message });
  }
};

// PUT /:id
const updateCustomer = async (req, res) => {
  try {
    const query = { _id: req.params.id, isDeleted: false };
    if (req.user?.orgId) query.orgId = req.user.orgId;
    Object.assign(query, req.branchFilter || {});
    const customer = await BillingCustomer.findOne(query);
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    Object.assign(customer, req.body);
    customer.lastModifiedBy   = req.user?.email || req.user?.name || 'System';
    customer.lastModifiedDate = new Date();
    await customer.save();
    res.json({ success: true, message: 'Customer updated successfully', data: customer.toSafeObject() });
  } catch (error) {
    console.error('? updateCustomer:', error);
    if (error.name === 'ValidationError') {
      const errors = Object.values(error.errors).map(e => e.message);
      return res.status(400).json({ success: false, error: 'Validation failed', message: errors.join(', ') });
    }
    res.status(500).json({ success: false, error: error.message });
  }
};

// DELETE /:id  — soft delete
const deleteCustomer = async (req, res) => {
  try {
    const query = { _id: req.params.id, isDeleted: false };
    if (req.user?.orgId) query.orgId = req.user.orgId;
    Object.assign(query, req.branchFilter || {});
    const customer = await BillingCustomer.findOne(query);
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });
    customer.isDeleted = true;
    customer.deletedAt = new Date();
    customer.deletedBy = req.user?.email || req.user?.name || 'System';
    await customer.save();
    res.json({ success: true, message: 'Customer deleted successfully' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// POST /:id/upload-documents
const uploadDocuments = async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false });
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });
    if (!req.files || req.files.length === 0) return res.status(400).json({ success: false, error: 'No files uploaded' });

    const docs = req.files.map(file => ({
      category:     req.body.category || 'Other Documents',
      fileName:     file.filename,
      originalName: file.originalname,
      filePath:     file.path,
      fileSize:     file.size,
      fileExtension: path.extname(file.originalname),
      uploadedAt:   new Date(),
      uploadedBy:   req.user?.email || 'System',
    }));
    customer.uploadedDocuments.push(...docs);
    customer.lastModifiedBy   = req.user?.email || 'System';
    customer.lastModifiedDate = new Date();
    await customer.save();
    res.json({ success: true, message: 'Documents uploaded', data: { uploadedCount: docs.length, documents: docs } });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// GET /statistics/overview
const getStatistics = async (req, res) => {
  try {
    const match = { isDeleted: false };
    if (req.user?.orgId) match.orgId = req.user.orgId;
    Object.assign(match, req.branchFilter || {});

    const stats = await BillingCustomer.aggregate([
      { $match: match },
      {
        $facet: {
          byType:      [{ $group: { _id: '$customerType',   count: { $sum: 1 } } }],
          byStatus:    [{ $group: { _id: '$customerStatus', count: { $sum: 1 } } }],
          byTier:      [{ $group: { _id: '$customerTier',   count: { $sum: 1 } } }],
          byTerritory: [{ $group: { _id: '$salesTerritory', count: { $sum: 1 } } }],
          revenue: [{
            $group: {
              _id: null,
              totalRevenue: { $sum: '$totalRevenueGenerated' },
              totalTrips:   { $sum: '$totalTripsCompleted' },
              avgRevenue:   { $avg: '$totalRevenueGenerated' },
            },
          }],
        },
      },
    ]);
    res.json({ success: true, data: stats[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// Bulk import
const bulkImportCustomers = async (req, res) => {
  try {
    const { customers } = req.body;
    if (!customers || !Array.isArray(customers) || customers.length === 0)
      return res.status(400).json({ success: false, error: 'No customers data provided' });

    let successCount = 0, failedCount = 0;
    const errors = [];

    for (let i = 0; i < customers.length; i++) {
      try {
        const data = { ...customers[i] };
        if (!data.customerId) {
          const ts = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
          data.customerId = `CUST-${ts}-${i}`;
        }
        data.createdBy  = req.user?.email || 'System';
        data.createdDate = new Date();
        data.orgId      = req.user?.orgId || null;
        data.branchId   = req.branchIds?.length > 0 ? req.branchIds[0] : null;

        // Strip invalid optional regex fields
        ['panNumber', 'gstNumber', 'tanNumber'].forEach(f => {
          if (data[f] === '' || data[f] == null) delete data[f];
        });

        await new BillingCustomer(data).save();
        successCount++;
      } catch (e) {
        failedCount++;
        errors.push(`Row ${i + 1}: ${e.message}`);
      }
    }

    res.json({
      success: true,
      message: `Import complete. ${successCount} succeeded, ${failedCount} failed.`,
      data: { totalProcessed: customers.length, successCount, failedCount, errors: errors.length ? errors : undefined },
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

// GET /indian-states  � for dropdowns
router.get('/indian-states', (req, res) => {
  res.json({ success: true, data: INDIAN_STATES });
});

// ============================================================================
// ROUTES
// ============================================================================

router.get('/statistics/overview', getStatistics);
router.get('/type/:customerType',  async (req, res) => {
  try {
    const customers = await BillingCustomer.find({ customerType: req.params.customerType, isDeleted: false }).sort({ createdDate: -1 }).lean();
    res.json({ success: true, data: { customerType: req.params.customerType, count: customers.length, customers } });
  } catch (e) { res.status(500).json({ success: false, error: e.message }); }
});
router.post('/bulk-import', bulkImportCustomers);

// Customer CRUD
router.get('/',     getAllCustomers);
router.get('/:id',  getCustomerById);
router.post('/',    createCustomer);
router.put('/:id',  updateCustomer);
router.delete('/:id', deleteCustomer);

// Detail sub-routes
router.get('/:id/overview',       getCustomerOverview);
router.get('/:id/transactions',   getCustomerTransactions);
router.get('/:id/mails',          getCustomerMails);
router.get('/:id/statement',      getCustomerStatement);
router.post('/:id/comments',      addComment);
router.delete('/:id/comments/:commentId', deleteComment);

// Unused credits
router.get('/:id/unused-credits', async (req, res) => {
  try {
    const customer = await BillingCustomer.findOne({
      _id: req.params.id,
      isDeleted: false,
      ...req.orgFilter,
    }).select('unusedCredits customerDisplayName').lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });
    res.json({ success: true, data: { unusedCredits: customer.unusedCredits || 0 } });
  } catch (e) { res.status(500).json({ success: false, error: e.message }); }
});

// Advance register — all advance payments for a customer with utilization summary
router.get('/:id/advance-register', async (req, res) => {
  try {
    const { getFinanceDb } = require('../config/database');
    const { ObjectId } = require('mongodb');
    const db = getFinanceDb();

    const customer = await BillingCustomer.findOne({
      _id: req.params.id,
      isDeleted: false,
      ...req.orgFilter,
    }).select('unusedCredits customerDisplayName primaryEmail').lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const custIdStr = customer._id.toString();
    const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};

    // Fetch all advance payments for this customer
    const advances = await db.collection('payments_received').find({
      paymentType: 'advance',
      $or: [{ customerId: custIdStr }, { customerId: customer._id }],
      ...orgFilter,
    }).sort({ createdAt: -1 }).toArray();

    // For each advance, compute how much has been utilized
    // Utilization = original netAmount - current contribution to unusedCredits
    // We track this by looking at normal payments that had creditsApplied > 0
    // and summing creditsApplied across all normal payments for this customer
    const normalPayments = await db.collection('payments_received').find({
      paymentType: { $ne: 'advance' },
      creditsApplied: { $gt: 0 },
      $or: [{ customerId: custIdStr }, { customerId: customer._id }],
      ...orgFilter,
    }).sort({ createdAt: 1 }).toArray();

    // Build a simple utilization ledger: total credits consumed
    const totalUtilized = normalPayments.reduce((s, p) => s + parseFloat(p.creditsApplied || 0), 0);
    const totalAdvanced = advances.reduce((s, a) => s + parseFloat(a.netAmount || a.amountReceived || 0), 0);

    const advanceList = advances.map(a => ({
      id:             a._id,
      paymentNumber:  a.paymentNumber,
      date:           a.paymentDate,
      amount:         parseFloat(a.amountReceived || 0),
      bankCharges:    parseFloat(a.bankCharges || 0),
      netAmount:      parseFloat(a.netAmount || a.amountReceived || 0),
      paymentMode:    a.paymentMode,
      reference:      a.reference || '',
      notes:          a.notes || '',
      status:         a.status || 'paid',
      createdAt:      a.createdAt,
    }));

    res.json({
      success: true,
      data: {
        customer: {
          id:           customer._id,
          name:         customer.customerDisplayName,
          email:        customer.primaryEmail,
          unusedCredits: customer.unusedCredits || 0,
        },
        summary: {
          totalAdvanced,
          totalUtilized,
          availableBalance: customer.unusedCredits || 0,
        },
        advances: advanceList,
        utilizationHistory: normalPayments.map(p => ({
          id:            p._id,
          paymentNumber: p.paymentNumber,
          date:          p.paymentDate,
          creditsApplied: parseFloat(p.creditsApplied || 0),
          invoicePayments: p.invoicePayments || {},
        })),
      },
    });
  } catch (e) {
    console.error('❌ advance-register error:', e);
    res.status(500).json({ success: false, error: e.message });
  }
});

// Document upload
router.post('/:id/upload-documents', upload.array('documents', 10), uploadDocuments);

module.exports = router;
module.exports.BillingCustomer = BillingCustomer;
module.exports.INDIAN_STATES   = INDIAN_STATES;

console.log('? Billing Customers module loaded (Zoho Books style)');      