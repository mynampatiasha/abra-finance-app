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
const PDFDocument = require('pdfkit');
const { getEffectiveOrgData } = require('./branches');
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
    type: String, trim: true, uppercase: true,
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
// HELPER  get Invoice model safely
// ============================================================================
function getInvoiceModel() {
  return mongoose.models.Invoice
    || mongoose.model('Invoice', new mongoose.Schema({}, { strict: false }), 'invoices');
}
function getCreditNoteModel() {
  return mongoose.models.CreditNote 
    || mongoose.model('CreditNote', new mongoose.Schema({}, { strict: false }), 'credit-notes');
}
function getPaymentReceivedModel() {
  return mongoose.models.PaymentReceived
    || mongoose.model('PaymentReceived', new mongoose.Schema({}, { strict: false }), 'payments_received');
}

// payments_received.paymentDate is saved as a "DD/MM/YYYY" string, not a Date —
// confirmed against records where the day exceeds 12 (so MM/DD would be invalid).
function parsePaymentDate(dateVal) {
  if (!dateVal) return null;
  if (dateVal instanceof Date) return dateVal;
  const str = String(dateVal);
  if (str.includes('/')) {
    const [d, m, y] = str.split('/');
    const parsed = new Date(Number(y), Number(m) - 1, Number(d));
    if (!isNaN(parsed.getTime())) return parsed;
  }
  const parsed = new Date(str);
  return isNaN(parsed.getTime()) ? null : parsed;
}

// Builds one "Payment" row per invoice a payments_received record was actually applied
// to (via its invoicePayments allocation map) — this is the authoritative source.
// Each invoice's own embedded `payments[]` array is NOT used here: it can carry
// duplicate/corrupted entries (confirmed — some with a payment date defaulted to the
// 1970 Unix epoch, roughly doubling what a given invoice appears to have received)
// that don't reconcile with the invoice's own trusted amountPaid/amountDue fields.
async function getPaymentRowsForInvoices(invoices, orgId) {
  if (!invoices || !invoices.length) return [];
  const invoiceById = {};
  invoices.forEach(inv => { invoiceById[inv._id?.toString()] = inv; });

  const customerIds = [...new Set(invoices.map(inv => inv.customerId?.toString()).filter(Boolean))];
  if (!customerIds.length) return [];

  const PaymentReceived = getPaymentReceivedModel();
  const payments = await PaymentReceived.find({
    customerId: { $in: customerIds },
    paymentType: { $ne: 'advance' },
    ...(orgId ? { orgId } : {}),
  }).lean();

  const rows = [];
  for (const pr of payments) {
    if (!pr.invoicePayments || typeof pr.invoicePayments !== 'object') continue;
    for (const invId of Object.keys(pr.invoicePayments)) {
      const inv = invoiceById[invId];
      const amount = parseFloat(pr.invoicePayments[invId] || 0);
      if (!inv || amount <= 0) continue;
      rows.push({
        invoiceId:     invId,
        invoiceNumber: inv.invoiceNumber,
        paymentId:     pr._id,
        paymentNumber: pr.paymentNumber,
        date:          parsePaymentDate(pr.paymentDate) || pr.createdAt || null,
        amount,
        method:        pr.paymentMode,
      });
    }
  }
  return rows;
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

    // Unused Credits — computed live from actual unused credit notes + excess
    // payments (same source the customer Overview page already trusts),
    // instead of the cached customer.unusedCredits field, which can drift
    // out of sync with the real records over time.
    const CreditNote = getCreditNoteModel();
    const PaymentReceived = getPaymentReceivedModel();
    let unusedCreditsMap = {};
    try {
      const custIdStrs  = customers.map(c => c._id?.toString()).filter(Boolean);
      const custCodeIds = customers.map(c => c.customerId).filter(Boolean);
      const allCustIds  = [...new Set([...custIdStrs, ...custCodeIds])];

      const [cnAgg, excessPmtAgg] = await Promise.all([
        CreditNote.aggregate([
          {
            $match: {
              customerId: { $in: allCustIds },
              creditBalance: { $gt: 0 },
              status: { $nin: ['VOID', 'DRAFT'] },
              ...req.orgFilter,
              ...(req.branchFilter || {}),
            },
          },
          { $group: { _id: '$customerId', total: { $sum: '$creditBalance' } } },
        ]),
        PaymentReceived.aggregate([
          {
            $match: {
              customerId: { $in: allCustIds },
              amountInExcess: { $gt: 0 },
              ...req.orgFilter,
              ...(req.branchFilter || {}),
            },
          },
          { $group: { _id: '$customerId', total: { $sum: '$amountInExcess' } } },
        ]),
      ]);

      const addToMap = (agg) => {
        agg.forEach(r => {
          const key = r._id?.toString();
          customers.forEach(c => {
            if (c._id?.toString() === key || c.customerId === key) {
              const cid = c._id.toString();
              unusedCreditsMap[cid] = (unusedCreditsMap[cid] || 0) + r.total;
            }
          });
        });
      };
      addToMap(cnAgg);
      addToMap(excessPmtAgg);
    } catch (e) {
      // CreditNote/PaymentReceived collection may not exist yet — safe to ignore
    }

    const customersWithReceivables = customers.map(c => ({
      ...c,
      outstandingReceivables: receivablesMap[c._id?.toString()] || 0,
      unusedCredits: unusedCreditsMap[c._id?.toString()] || 0,
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
    const CreditNote = getCreditNoteModel();
    const PaymentReceived = getPaymentReceivedModel();

    let outstandingReceivables = 0;
    let unusedCredits = customer.unusedCredits || 0;
    let monthlyIncome = [];
    
    let unpaidInvoicesList = [];
    let unusedCreditsList = [];

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

      // Monthly income - dynamic months
      const months = parseInt(req.query.months) || 6;
      const monthsAgo = new Date();
      monthsAgo.setMonth(monthsAgo.getMonth() - (months - 1));
      monthsAgo.setDate(1);
      monthsAgo.setHours(0, 0, 0, 0);

      const incomeAgg = await Invoice.aggregate([
        {
          $match: {
            customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
            invoiceDate: { $gte: monthsAgo },
            status: { $nin: ['CANCELLED', 'VOID'] },
            ...req.orgFilter,
          },
        },
        {
          $group: {
            _id: { year: { $year: '$invoiceDate' }, month: { $month: '$invoiceDate' } },
            total: { $sum: '$subTotal' },
            count: { $sum: 1 },
          },
        },
        { $sort: { '_id.year': 1, '_id.month': 1 } },
      ]);

      // Build month slots dynamically
      const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const now = new Date();
      for (let i = months - 1; i >= 0; i--) {
        const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
        const found = incomeAgg.find(a => a._id.year === d.getFullYear() && a._id.month === d.getMonth() + 1);
        monthlyIncome.push({
          month: monthNames[d.getMonth()],
          year:  d.getFullYear(),
          total: found?.total || 0,
          count: found?.count || 0,
        });
      }

      // Fetch unpaid invoices list for drilldown
      unpaidInvoicesList = await Invoice.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId, customer._id].filter(Boolean) },
        status: { $in: ['SENT', 'UNPAID', 'PARTIALLY_PAID', 'OVERDUE'] },
        ...req.orgFilter,
      }).select('_id invoiceNumber invoiceDate amountDue').sort({ invoiceDate: -1 }).lean();
    }

    if (CreditNote && PaymentReceived) {
      const validCustomerObjectIds = [customer._id?.toString(), customer.customerId, customer._id]
        .filter(id => mongoose.isValidObjectId(id));

      // Fetch unused credit notes
      const unusedCreditNotes = await CreditNote.find({
        customerId: { $in: validCustomerObjectIds },
        creditBalance: { $gt: 0 },
        status: { $nin: ['VOID', 'DRAFT'] },
        ...req.orgFilter,
      }).select('_id creditNoteNumber creditNoteDate creditBalance').sort({ creditNoteDate: -1 }).lean();

      // Fetch unused payments (amountInExcess)
      const unusedPayments = await PaymentReceived.find({
        customerId: { $in: validCustomerObjectIds },
        amountInExcess: { $gt: 0 },
        ...req.orgFilter,
      }).select('_id paymentNumber paymentDate amountInExcess paymentMode').sort({ paymentDate: -1 }).lean();

      // Combine them into a single list
      unusedCreditsList = [
        ...unusedCreditNotes.map(cn => ({
          _id: cn._id,
          type: 'Credit Note',
          number: cn.creditNoteNumber,
          date: cn.creditNoteDate,
          unusedAmount: cn.creditBalance
        })),
        ...unusedPayments.map(p => ({
          _id: p._id,
          type: 'Excess Payment',
          number: p.paymentNumber,
          date: p.paymentDate,
          unusedAmount: p.amountInExcess
        }))
      ].sort((a, b) => new Date(b.date) - new Date(a.date));

      // Keep the Overview badge in sync with the drilldown list it opens
      unusedCredits = unusedCreditsList.reduce((sum, c) => sum + (parseFloat(c.unusedAmount) || 0), 0);
    }

    res.json({
      success: true,
      data: {
        customer,
        receivables: {
          currency: customer.defaultCurrency || 'INR',
          outstandingReceivables,
          unusedCredits,
          unpaidInvoicesList,
          unusedCreditsList,
        },
        monthlyIncome,
      },
    });
  } catch (error) {
    console.error('? getCustomerOverview:', error);
    res.status(500).json({ success: false, error: error.message, stack: String(error.stack) });
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

      // Payments — sourced from payments_received (authoritative), not each
      // invoice's own embedded `payments[]` array, which can carry duplicates.
      const paymentRows = await getPaymentRowsForInvoices(invoices, req.user?.orgId);
      for (const p of paymentRows) {
        transactions.push({
          type:   'Payment',
          id:     p.paymentId,
          number: p.invoiceNumber,
          date:   p.date,
          status: 'PAID',
          amount: p.amount,
          balance: 0,
          method: p.method,
        });
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
    let closingBalance = openingBalance;
    const custIdStr = customer._id?.toString();
    const custId2   = customer.customerId;



    if (Invoice) {
      // ── Helper: read the invoice's own paid/due fields (same source the
      //    Invoice list & edit pages use — avoids re-deriving from payment history) ──
      const getPaidAndDue = (inv) => {
        const invoiceAmt = parseFloat(inv.totalAmount || 0);
        const paidAmt = parseFloat(inv.amountPaid || 0);
        const dueAmt = (inv.amountDue !== undefined && inv.amountDue !== null)
          ? parseFloat(inv.amountDue)
          : (invoiceAmt - paidAmt);
        return { invoiceAmt, paidAmt, dueAmt };
      };

      // ── Calculate Dynamic Opening Balance (invoices BEFORE 'from' date) ───
      let dynamicOpeningBalance = customer.openingBalance || 0;
      const pastInvoices = await Invoice.find({
        customerId: { $in: [custIdStr, custId2].filter(Boolean) },
        invoiceDate: { $lt: from },
        status: { $nin: ['CANCELLED', 'VOID'] },
        ...req.orgFilter,
      }).lean();

      for (const inv of pastInvoices) {
        const { dueAmt } = getPaidAndDue(inv);
        dynamicOpeningBalance += dueAmt;
      }
      openingBalance = dynamicOpeningBalance;

      // ── Fetch invoices in date range ──────────────────────────────────────
      const invoices = await Invoice.find({
        customerId: { $in: [custIdStr, custId2].filter(Boolean) },
        invoiceDate: { $gte: from, $lte: to },
        status: { $nin: ['CANCELLED', 'VOID'] },
        ...req.orgFilter,
      }).sort({ invoiceDate: 1 }).lean();

      // ── Build ONE row per invoice ─────────────────────────────────────────
      closingBalance = openingBalance;
      for (const inv of invoices) {
        const { invoiceAmt, paidAmt, dueAmt } = getPaidAndDue(inv);
        closingBalance += dueAmt;

        entries.push({
          date:        inv.invoiceDate,
          type:        'Invoice',
          number:      inv.invoiceNumber,
          details:     inv.subject || inv.orderNumber || '',
          invoices:    invoiceAmt,
          payments:    paidAmt > 0 ? paidAmt : null,
          balance:     dueAmt,
        });
      }
    }

    res.json({
      success: true,
      data: {
        customer: { name: customer.customerDisplayName, email: customer.primaryEmail },
        openingBalance,
        entries,
        closingBalance,
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
router.get('/:id/statement/pdf',  getCustomerStatementPDF);
router.get('/:id/transactions/pdf', getCustomerTransactionsPDF);
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
          availableBalance: totalAdvanced - totalUtilized,
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


// GET /:id/statement/pdf
async function getCustomerStatementPDF(req, res) {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const { fromDate, toDate, transactionsOnly } = req.query;
    const isTxnOnly = transactionsOnly === 'true';
    const from = fromDate ? new Date(fromDate) : new Date(new Date().setFullYear(new Date().getFullYear() - 1));
    const to   = toDate   ? new Date(toDate)   : new Date();
    to.setHours(23, 59, 59, 999);
    from.setHours(0, 0, 0, 0);

    const Invoice = getInvoiceModel();
    let entries = [];
    let openingBalance = customer.openingBalance || 0;
    let closingBalance = openingBalance;
    const custIdStr = customer._id?.toString();
    const custId2   = customer.customerId;

    if (Invoice) {

      // ── Helper: read the invoice's own paid/due fields (same source the
      //    Invoice list & edit pages use — avoids re-deriving from payment history) ──
      const getPaidAndDue = (inv) => {
        const invoiceAmt = parseFloat(inv.totalAmount || 0);
        const paidAmt = parseFloat(inv.amountPaid || 0);
        const dueAmt = (inv.amountDue !== undefined && inv.amountDue !== null)
          ? parseFloat(inv.amountDue)
          : (invoiceAmt - paidAmt);
        return { invoiceAmt, paidAmt, dueAmt };
      };

      // ── Dynamic Opening Balance (invoices before 'from' date) ────────────
      let dynamicOpeningBalance = customer.openingBalance || 0;
      const pastInvoices = await Invoice.find({
        customerId: { $in: [custIdStr, custId2].filter(Boolean) },
        invoiceDate: { $lt: from },
        status: { $nin: ['CANCELLED', 'VOID'] },
        ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
      }).lean();
      for (const inv of pastInvoices) {
        const { dueAmt } = getPaidAndDue(inv);
        dynamicOpeningBalance += dueAmt;
      }
      openingBalance = dynamicOpeningBalance;

      // ── Fetch invoices in date range ──────────────────────────────────────
      const invoices = await Invoice.find({
        customerId: { $in: [custIdStr, custId2].filter(Boolean) },
        invoiceDate: { $gte: from, $lte: to },
        status: { $nin: ['CANCELLED', 'VOID'] },
        ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
      }).sort({ invoiceDate: 1 }).lean();

      // ── Build ONE row per invoice ─────────────────────────────────────────
      closingBalance = openingBalance;
      for (const inv of invoices) {
        const { invoiceAmt, paidAmt, dueAmt } = getPaidAndDue(inv);
        closingBalance += dueAmt;
        entries.push({
          date:     inv.invoiceDate,
          type:     'Invoice',
          number:   inv.invoiceNumber,
          details:  inv.subject || inv.orderNumber || '',
          invoices: invoiceAmt,
          payments: paidAmt > 0 ? paidAmt : null,
          balance:  dueAmt,
        });
      }
    }


    // Now generate PDF
    let orgName  = 'Your Company';
    let orgGST   = '';
    let orgAddr  = '';
    let orgEmail = '';
    let orgPhone = '';
    let orgData  = null;
    try {
      orgData  = await getEffectiveOrgData(req.user?.orgId, req.branchFilter?.branchId || null, mongoose.connection.db);
      if (orgData) {
        orgName  = orgData.orgName  || orgName;
        orgGST   = orgData.gstNumber || '';
        orgAddr  = orgData.address  || '';
        orgEmail = orgData.email    || '';
        orgPhone = orgData.phone    || '';
      }
    } catch (e) {}

    const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename="Statement_' + customer.customerDisplayName.replace(/\s+/g, '_') + '.pdf"');
    doc.pipe(res);

    const pageW = 515;

    // Header
    let logoData = null;
    if (orgData?.logoBase64) {
      const match = orgData.logoBase64.match(/^data:(image\/\w+);base64,(.*)$/);
      if (match) logoData = Buffer.from(match[2], 'base64');
    }
    if (!logoData && orgData?.logoUrl) {
      const lp = path.join(__dirname, '..', orgData.logoUrl.replace(/^\//, ''));
      try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
    }

    const textX = logoData ? 166 : 50;
    const contactLines = [orgAddr, orgGST ? 'GSTIN: ' + orgGST : '', orgPhone, orgEmail].filter(Boolean);
    const textBlockHeight = 14 + 12 + (contactLines.length * 9);
    const textStartY = 35;
    const logoCenterY = textStartY + (textBlockHeight / 2);
    
    const logoH = 82;
    const logoW = 110;
    const logoY = logoCenterY - (logoH / 2);

    if (logoData) {
      try {
        doc.image(logoData, 44, logoY, { width: logoW, height: logoH, fit: [logoW, logoH] });
      } catch (e) {}
    }

    doc.fontSize(13).fillColor('#000000').font('Helvetica-Bold')
       .text(orgName.toUpperCase(), textX, textStartY, { width: 200 });
    const orgNameH = doc.heightOfString(orgName.toUpperCase(), { width: 200 });
    const subtitleY = textStartY + orgNameH + 2;
    doc.fontSize(8).fillColor('#444444').font('Helvetica')
       .text(isTxnOnly ? 'TRANSACTION HISTORY' : 'STATEMENT OF ACCOUNTS', textX, subtitleY, { width: 200, characterSpacing: 1 });

    doc.fontSize(8).fillColor('#000000');
    let contactY = subtitleY + 12;
    contactLines.forEach(line => {
      doc.text(line, textX, contactY, { width: 240 });
      const lineH = doc.heightOfString(line, { width: 240 });
      contactY += Math.max(lineH, 9) + 1;
    });

    doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
       .text(isTxnOnly ? 'TRANSACTIONS' : 'STATEMENT', 380, 52, { width: 170, align: 'right' });
    doc.fontSize(8).fillColor('#000000').font('Helvetica')
       .text('From: ' + from.toLocaleDateString('en-IN') + ' To: ' + to.toLocaleDateString('en-IN'), 380, 76, { width: 170, align: 'right' });

    const metaY = Math.max(132, contactY + 8);
    const colW = pageW / 2;
    
    const billX = 40;
    doc.rect(billX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
    doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
       .text('TO', billX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
    doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold')
         .text(customer.customerDisplayName || 'N/A', billX + 8, metaY + 18, { width: colW - 26 });

      let custAddr = '';
      if (customer.billingAddress && customer.billingAddress.street) {
        custAddr = [
          customer.billingAddress.street,
          customer.billingAddress.city ? customer.billingAddress.city + ' - ' + (customer.billingAddress.zip || '') : '',
          customer.billingAddress.state,
          customer.billingAddress.country
        ].filter(Boolean).join('\n');
      } else {
        custAddr = [
          customer.addressLine1,
          customer.city ? customer.city + ' - ' + (customer.postalCode || '') : '',
          customer.state,
          customer.country
        ].filter(Boolean).join('\n');
      }
      if (custAddr) {
        doc.fontSize(8).font('Helvetica').fillColor('#555555')
           .text(custAddr, billX + 8, metaY + 32, { width: colW - 26 });
      }
    
    if (!isTxnOnly) {
      const summX = 40 + colW + 10;
      doc.rect(summX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
      doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
         .text('ACCOUNT SUMMARY', summX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
      
      doc.fontSize(10).fillColor('#000000').font('Helvetica')
         .text('Opening Balance:', summX + 8, metaY + 20)
         .text('Rs ' + openingBalance.toFixed(2), summX + 8, metaY + 20, { align: 'right', width: colW - 24 });
      
      let totalInvoiced = 0, totalPaid = 0;
      entries.forEach(e => {
         if (e.invoices) totalInvoiced += e.invoices;
         if (e.payments) totalPaid += e.payments;
      });

      doc.text('Invoiced Amount:', summX + 8, metaY + 35)
         .text('Rs ' + totalInvoiced.toFixed(2), summX + 8, metaY + 35, { align: 'right', width: colW - 24 });
      doc.text('Amount Paid:', summX + 8, metaY + 50)
         .text('Rs ' + totalPaid.toFixed(2), summX + 8, metaY + 50, { align: 'right', width: colW - 24 });
      
      doc.font('Helvetica-Bold').text('Balance Due:', summX + 8, metaY + 65)
         .text('Rs ' + closingBalance.toFixed(2), summX + 8, metaY + 65, { align: 'right', width: colW - 24 });
    }

    const ensureSpace = (currentY, neededHeight = 20) => {
      if (currentY + neededHeight > 780) {
        doc.addPage();
        return 40;
      }
      return currentY;
    };

    let tableStartY = ensureSpace(metaY + 95, 40);

    const cols = {
      date:    { x: 40,  w: 60  },
      details: { x: 100, w: 220 },
      amount:  { x: 320, w: 75  },
      paid:    { x: 395, w: 75  },
      balance: { x: 470, w: 85  },
    };

    doc.rect(40, tableStartY, 515, 20).fill('#0f1e3d');
    doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
    doc.text('DATE',       cols.date.x + 4, tableStartY + 6, { width: cols.date.w });
    doc.text('DETAILS',    cols.details.x + 4, tableStartY + 6, { width: cols.details.w });
    doc.text('INVOICE AMOUNT', cols.amount.x + 4, tableStartY + 6, { width: cols.amount.w - 8, align: 'right' });
    doc.text('PAID',       cols.paid.x + 4, tableStartY + 6, { width: cols.paid.w - 8, align: 'right' });
    doc.text('BALANCE',    cols.balance.x + 4, tableStartY + 6, { width: cols.balance.w - 8, align: 'right' });

    let rowY = tableStartY + 20;

    if (!isTxnOnly) {
      rowY = ensureSpace(rowY, 24);
      doc.rect(40, rowY, 515, 24).fill('#ffffff');
      doc.rect(40, rowY, 515, 24).lineWidth(0.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(8).fillColor('#000000').font('Helvetica');
      doc.text(from.toLocaleDateString('en-IN'), cols.date.x + 4, rowY + 8);
      doc.text('Opening Balance', cols.details.x + 4, rowY + 8);
      doc.font('Helvetica-Bold').text(openingBalance.toFixed(2), cols.balance.x + 4, rowY + 8, { width: cols.balance.w - 8, align: 'right' });
      rowY += 24;
    }

    entries.forEach((e, i) => {
      const rowH = 24;
      rowY = ensureSpace(rowY, rowH);
      const fill = i % 2 === 0 ? '#f7f9fc' : '#ffffff';
      doc.rect(40, rowY, 515, rowH).fill(fill);
      doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();

      doc.fontSize(8).fillColor('#000000').font('Helvetica');
      doc.text(new Date(e.date).toLocaleDateString('en-IN'), cols.date.x + 4, rowY + 8);
      
      const details = e.number + (e.details ? ' - ' + e.details : '');
      doc.text(details, cols.details.x + 4, rowY + 8, { width: cols.details.w - 8, ellipsis: true });
      
      if (e.invoices) doc.text(e.invoices.toFixed(2), cols.amount.x + 4, rowY + 8, { width: cols.amount.w - 8, align: 'right' });
      if (e.payments) doc.text(e.payments.toFixed(2), cols.paid.x + 4, rowY + 8, { width: cols.paid.w - 8, align: 'right' });
      
      doc.font('Helvetica-Bold').text(e.balance.toFixed(2), cols.balance.x + 4, rowY + 8, { width: cols.balance.w - 8, align: 'right' });

      rowY += rowH;
    });

    // ── TOTALS row ────────────────────────────────────────────────────────
    if (!isTxnOnly && entries.length > 0) {
      let totalInvoiced = 0, totalPaid = 0;
      entries.forEach(e => {
        if (e.invoices) totalInvoiced += e.invoices;
        if (e.payments) totalPaid += e.payments;
      });
      const rowH = 24;
      rowY = ensureSpace(rowY, rowH);
      doc.rect(40, rowY, 515, rowH).fill('#e8edf5');
      doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();
      doc.fontSize(8).fillColor('#000000').font('Helvetica-Bold');
      doc.text('TOTAL', cols.details.x + 4, rowY + 8, { width: cols.details.w - 8 });
      doc.text(totalInvoiced.toFixed(2), cols.amount.x + 4, rowY + 8, { width: cols.amount.w - 8, align: 'right' });
      doc.text(totalPaid.toFixed(2), cols.paid.x + 4, rowY + 8, { width: cols.paid.w - 8, align: 'right' });
      doc.text(closingBalance.toFixed(2), cols.balance.x + 4, rowY + 8, { width: cols.balance.w - 8, align: 'right' });
      rowY += rowH;
    }

    doc.end();

  } catch (error) {
    console.error('Error generating PDF:', error);
    res.status(500).send('Error generating PDF');
  }
};

// GET /:id/transactions/pdf — exports exactly what the Transactions tab shows
// (DATE / NUMBER / TYPE / STATUS / AMOUNT / BALANCE, per-row — not a running statement)
async function getCustomerTransactionsPDF(req, res) {
  try {
    const customer = await BillingCustomer.findOne({ _id: req.params.id, isDeleted: false }).lean();
    if (!customer) return res.status(404).json({ success: false, error: 'Customer not found' });

    const { fromDate, toDate } = req.query;
    const from = fromDate ? new Date(fromDate) : new Date(new Date().setFullYear(new Date().getFullYear() - 1));
    const to   = toDate   ? new Date(toDate)   : new Date();
    to.setHours(23, 59, 59, 999);
    from.setHours(0, 0, 0, 0);

    const Invoice = getInvoiceModel();
    let transactions = [];

    if (Invoice) {
      const invoices = await Invoice.find({
        customerId: { $in: [customer._id?.toString(), customer.customerId] },
        // Drafts haven't been issued to the customer yet — they aren't a real
        // transaction or a real outstanding balance until sent.
        status: { $nin: ['DRAFT', 'CANCELLED', 'VOID'] },
        ...req.orgFilter,
      }).lean();

      transactions = invoices.map(inv => ({
        type:    'Invoice',
        number:  inv.invoiceNumber,
        date:    inv.invoiceDate,
        status:  inv.status,
        amount:  parseFloat(inv.totalAmount || 0),
        balance: parseFloat(inv.amountDue || 0),
      }));

      // Payments — sourced from payments_received (authoritative), not each
      // invoice's own embedded `payments[]` array, which can carry duplicates.
      const paymentRows = await getPaymentRowsForInvoices(invoices, req.user?.orgId);
      for (const p of paymentRows) {
        transactions.push({
          type:    'Payment',
          number:  p.invoiceNumber,
          date:    p.date,
          status:  'PAID',
          amount:  parseFloat(p.amount || 0),
          balance: 0,
        });
      }
    }

    transactions = transactions.filter(t => {
      const d = new Date(t.date);
      return d >= from && d <= to;
    });
    transactions.sort((a, b) => new Date(b.date) - new Date(a.date));

    let orgName  = 'Your Company';
    let orgGST   = '';
    let orgAddr  = '';
    let orgEmail = '';
    let orgPhone = '';
    let orgData  = null;
    try {
      orgData  = await getEffectiveOrgData(req.user?.orgId, req.branchFilter?.branchId || null, mongoose.connection.db);
      if (orgData) {
        orgName  = orgData.orgName  || orgName;
        orgGST   = orgData.gstNumber || '';
        orgAddr  = orgData.address  || '';
        orgEmail = orgData.email    || '';
        orgPhone = orgData.phone    || '';
      }
    } catch (e) {}

    const doc = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', 'attachment; filename="Transactions_' + customer.customerDisplayName.replace(/\s+/g, '_') + '.pdf"');
    doc.pipe(res);

    const pageW = 515;

    let logoData = null;
    if (orgData?.logoBase64) {
      const match = orgData.logoBase64.match(/^data:(image\/\w+);base64,(.*)$/);
      if (match) logoData = Buffer.from(match[2], 'base64');
    }
    if (!logoData && orgData?.logoUrl) {
      const lp = path.join(__dirname, '..', orgData.logoUrl.replace(/^\//, ''));
      try { if (fs.existsSync(lp) && fs.statSync(lp).size > 0) logoData = lp; } catch (_) {}
    }

    const textX = logoData ? 166 : 50;
    const contactLines = [orgAddr, orgGST ? 'GSTIN: ' + orgGST : '', orgPhone, orgEmail].filter(Boolean);
    const textBlockHeight = 14 + 12 + (contactLines.length * 9);
    const textStartY = 35;
    const logoCenterY = textStartY + (textBlockHeight / 2);

    const logoH = 82;
    const logoW = 110;
    const logoY = logoCenterY - (logoH / 2);

    if (logoData) {
      try {
        doc.image(logoData, 44, logoY, { width: logoW, height: logoH, fit: [logoW, logoH] });
      } catch (e) {}
    }

    doc.fontSize(13).fillColor('#000000').font('Helvetica-Bold')
       .text(orgName.toUpperCase(), textX, textStartY, { width: 200 });
    const orgNameH = doc.heightOfString(orgName.toUpperCase(), { width: 200 });
    const subtitleY = textStartY + orgNameH + 2;
    doc.fontSize(8).fillColor('#444444').font('Helvetica')
       .text('TRANSACTION HISTORY', textX, subtitleY, { width: 200, characterSpacing: 1 });

    doc.fontSize(8).fillColor('#000000');
    let contactY = subtitleY + 12;
    contactLines.forEach(line => {
      doc.text(line, textX, contactY, { width: 240 });
      const lineH = doc.heightOfString(line, { width: 240 });
      contactY += Math.max(lineH, 9) + 1;
    });

    doc.fontSize(18).fillColor('#000000').font('Helvetica-Bold')
       .text('TRANSACTIONS', 380, 52, { width: 170, align: 'right' });
    doc.fontSize(8).fillColor('#000000').font('Helvetica')
       .text('From: ' + from.toLocaleDateString('en-IN') + ' To: ' + to.toLocaleDateString('en-IN'), 380, 76, { width: 170, align: 'right' });

    const metaY = Math.max(132, contactY + 8);
    const colW = pageW / 2;

    const billX = 40;
    doc.rect(billX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
    doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
       .text('TO', billX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
    doc.fontSize(10).fillColor('#000000').font('Helvetica-Bold')
         .text(customer.customerDisplayName || 'N/A', billX + 8, metaY + 18, { width: colW - 26 });

    let custAddr = '';
    if (customer.billingAddress && customer.billingAddress.street) {
      custAddr = [
        customer.billingAddress.street,
        customer.billingAddress.city ? customer.billingAddress.city + ' - ' + (customer.billingAddress.zip || '') : '',
        customer.billingAddress.state,
        customer.billingAddress.country
      ].filter(Boolean).join('\n');
    } else {
      custAddr = [
        customer.addressLine1,
        customer.city ? customer.city + ' - ' + (customer.postalCode || '') : '',
        customer.state,
        customer.country
      ].filter(Boolean).join('\n');
    }
    if (custAddr) {
      doc.fontSize(8).font('Helvetica').fillColor('#555555')
         .text(custAddr, billX + 8, metaY + 32, { width: colW - 26 });
    }

    const summX = 40 + colW + 10;
    doc.rect(summX, metaY, colW - 10, 80).fillAndStroke('#f7f9fc', '#dde4ef');
    doc.fontSize(7).fillColor('#8a9ab5').font('Helvetica-Bold')
       .text('SUMMARY', summX + 8, metaY + 7, { width: colW - 26, characterSpacing: 0.8 });
    doc.fontSize(10).fillColor('#000000').font('Helvetica')
       .text('Transactions:', summX + 8, metaY + 20)
       .text(String(transactions.length), summX + 8, metaY + 20, { align: 'right', width: colW - 24 });
    const totalOutstanding = transactions.reduce((sum, t) => sum + (t.balance || 0), 0);
    doc.font('Helvetica-Bold').text('Total Outstanding:', summX + 8, metaY + 35)
       .text('Rs ' + totalOutstanding.toFixed(2), summX + 8, metaY + 35, { align: 'right', width: colW - 24 });

    const ensureSpace = (currentY, neededHeight = 20) => {
      if (currentY + neededHeight > 780) {
        doc.addPage();
        return 40;
      }
      return currentY;
    };

    let tableStartY = ensureSpace(metaY + 95, 40);

    const cols = {
      date:    { x: 40,  w: 60  },
      number:  { x: 100, w: 100 },
      type:    { x: 200, w: 65  },
      status:  { x: 265, w: 90  },
      amount:  { x: 355, w: 95  },
      balance: { x: 450, w: 105 },
    };

    doc.rect(40, tableStartY, 515, 20).fill('#0f1e3d');
    doc.fontSize(8).fillColor('#ffffff').font('Helvetica-Bold');
    doc.text('DATE',    cols.date.x + 4,   tableStartY + 6, { width: cols.date.w });
    doc.text('NUMBER',  cols.number.x + 4, tableStartY + 6, { width: cols.number.w });
    doc.text('TYPE',    cols.type.x + 4,   tableStartY + 6, { width: cols.type.w });
    doc.text('STATUS',  cols.status.x + 4, tableStartY + 6, { width: cols.status.w });
    doc.text('AMOUNT',  cols.amount.x + 4, tableStartY + 6, { width: cols.amount.w - 8, align: 'right' });
    doc.text('BALANCE', cols.balance.x + 4, tableStartY + 6, { width: cols.balance.w - 8, align: 'right' });

    let rowY = tableStartY + 20;

    transactions.forEach((t, i) => {
      const rowH = 22;
      rowY = ensureSpace(rowY, rowH);
      const fill = i % 2 === 0 ? '#f7f9fc' : '#ffffff';
      doc.rect(40, rowY, 515, rowH).fill(fill);
      doc.rect(40, rowY, 515, rowH).lineWidth(0.5).strokeColor('#dde4ef').stroke();

      doc.fontSize(8).fillColor('#000000').font('Helvetica');
      doc.text(new Date(t.date).toLocaleDateString('en-IN'), cols.date.x + 4, rowY + 7, { width: cols.date.w });
      doc.fillColor('#1d4ed8').text(t.number || '', cols.number.x + 4, rowY + 7, { width: cols.number.w - 8, ellipsis: true });
      doc.fillColor('#000000').text(t.type || '', cols.type.x + 4, rowY + 7, { width: cols.type.w });
      doc.text(String(t.status || '').replace(/_/g, ' '), cols.status.x + 4, rowY + 7, { width: cols.status.w });
      doc.text((t.amount || 0).toFixed(2), cols.amount.x + 4, rowY + 7, { width: cols.amount.w - 8, align: 'right' });
      doc.font('Helvetica-Bold')
         .fillColor(t.balance > 0 ? '#dc2626' : '#6b7280')
         .text(t.balance > 0 ? (t.balance).toFixed(2) : '-', cols.balance.x + 4, rowY + 7, { width: cols.balance.w - 8, align: 'right' });

      rowY += rowH;
    });

    doc.end();

  } catch (error) {
    console.error('Error generating transactions PDF:', error);
    res.status(500).send('Error generating PDF');
  }
};


module.exports = router;
module.exports.BillingCustomer = BillingCustomer;
module.exports.INDIAN_STATES   = INDIAN_STATES;

console.log('? Billing Customers module loaded (Zoho Books style)');      



