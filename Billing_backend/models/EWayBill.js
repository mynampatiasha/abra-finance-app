// ============================================================================
// E-WAY BILL MODEL (FIXED — pre-save hook completely removed)
// ============================================================================
// File: backend/models/EWayBill.js
// ============================================================================

const mongoose = require('mongoose');

const eWayBillSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },

  sourceType: {
    type: String,
    enum: ['INVOICE', 'CREDIT_NOTE', 'DELIVERY_CHALLAN', 'BILL_OF_SUPPLY'],
    required: true,
  },
  sourceId:     { type: mongoose.Schema.Types.ObjectId, default: null, index: true },
  sourceNumber: { type: String, default: '' },

  ewbNumber:  { type: String, index: true, default: null },
  ewbDate:    { type: Date, default: null },
  validUntil: { type: Date, default: null },
  ewbStatus: {
    type: String,
    enum: ['DRAFT', 'PART_A', 'GENERATED', 'CANCELLED', 'EXPIRED', 'EXTENDED'],
    default: 'DRAFT',
    index: true,
  },
  cancelledAt:  { type: Date,   default: null },
  cancelReason: { type: String, default: '' },
  extendedAt:   { type: Date,   default: null },

  supplyType:   { type: String, enum: ['OUTWARD', 'INWARD'], default: 'OUTWARD' },
  subType: {
    type: String,
    enum: ['SUPPLY','EXPORT','JOB_WORK','SKD_CKD','SKD/CKD','RECIPIENT_NOT_KNOWN','FOR_OWN_USE','EXHIBITION_FAIRS','EXHIBITION_OR_FAIRS','LINE_SALES','OTHERS'],
    default: 'SUPPLY',
  },
  documentType: {
    type: String,
    enum: ['INV', 'BILL_OF_SUPPLY', 'CREDIT_NOTE', 'DELIVERY_CHALLAN', 'OTHERS'],
    default: 'INV',
  },
  documentNumber: { type: String, default: '' },
  documentDate:   { type: Date,   default: Date.now },

  fromGstin:     { type: String, default: '' },
  fromTradeName: { type: String, default: '' },
  fromAddress1:  { type: String, default: '' },
  fromAddress2:  { type: String, default: '' },
  fromPlace:     { type: String, default: '' },
  fromPincode:   { type: String, default: '' },
  fromStateCode: { type: String, default: '' },
  fromState:     { type: String, default: '' },

  toGstin:     { type: String, default: '' },
  toTradeName: { type: String, default: '' },
  toAddress1:  { type: String, default: '' },
  toAddress2:  { type: String, default: '' },
  toPlace:     { type: String, default: '' },
  toPincode:   { type: String, default: '' },
  toStateCode: { type: String, default: '' },
  toState:     { type: String, default: '' },

  hsnCode:           { type: String, default: '' },
  productName:       { type: String, default: '' },
  productDesc:       { type: String, default: '' },
  quantity:          { type: Number, default: 1 },
  unit:              { type: String, default: 'NOS' },
  taxableAmount:     { type: Number, default: 0 },
  cgstRate:          { type: Number, default: 0 },
  sgstRate:          { type: Number, default: 0 },
  igstRate:          { type: Number, default: 0 },
  cessRate:          { type: Number, default: 0 },
  cessNonAdvalorem:  { type: Number, default: 0 },
  totalInvoiceValue: { type: Number, default: 0 },

  transportMode:       { type: String, enum: ['ROAD','RAIL','AIR','SHIP'], default: 'ROAD' },
  approximateDistance: { type: Number, default: 0 },
  transporterName:     { type: String, default: '' },
  transporterId:       { type: String, default: '' },
  transDocNo:          { type: String, default: '' },
  transDocDate:        { type: Date,   default: null },

  vehicleType:    { type: String, enum: ['REGULAR','OVER_DIMENSIONAL_CARGO'], default: 'REGULAR' },
  vehicleNumber:  { type: String, default: '' },
  fromPlacePartB: { type: String, default: '' },
  fromStatePartB: { type: String, default: '' },
  reasonCode:     { type: String, default: '1' },
  reasonRemarks:  { type: String, default: '' },

  vehicleHistory: [{
    vehicleNumber: { type: String, default: '' },
    fromPlace:     { type: String, default: '' },
    fromState:     { type: String, default: '' },
    reasonCode:    { type: String, default: '1' },
    transDocNo:    { type: String, default: '' },
    transDocDate:  { type: Date,   default: null },
    updatedAt:     { type: Date,   default: Date.now },
    updatedBy:     { type: String, default: '' },
  }],

  extensionHistory: [{
    extendedFrom:  { type: Date,   default: null },
    extendedTo:    { type: Date,   default: null },
    fromPlace:     { type: String, default: '' },
    fromState:     { type: String, default: '' },
    vehicleNumber: { type: String, default: '' },
    remainingDist: { type: Number, default: 0 },
    reason:        { type: String, default: '' },
    extendedAt:    { type: Date,   default: Date.now },
    extendedBy:    { type: String, default: '' },
  }],

  isConsolidated:        { type: Boolean, default: false },
  consolidatedEwbNumber: { type: String,  default: null },
  consolidatedWith:      [{ type: String }],

  isManuallyAssociated: { type: Boolean, default: false },
  associatedAt:         { type: Date,    default: null },

  createdBy: { type: String, default: 'system' },
  updatedBy: { type: String, default: null },

}, { timestamps: true });

eWayBillSchema.index({ orgId: 1, ewbStatus: 1 });
eWayBillSchema.index({ orgId: 1, validUntil: 1 });
eWayBillSchema.index({ sourceId: 1, sourceType: 1 });
eWayBillSchema.index({ orgId: 1, createdAt: -1 });

const EWayBill = mongoose.models.EWayBill || mongoose.model('EWayBill', eWayBillSchema);

const ewbCredentialsSchema = new mongoose.Schema({
  orgId:             { type: String,  required: true, unique: true, index: true },
  gstin:             { type: String,  required: true },
  username:          { type: String,  required: true },
  passwordEncrypted: { type: String,  required: true },
  isConnected:       { type: Boolean, default: false },
  connectedAt:       { type: Date,    default: null },
  lastValidatedAt:   { type: Date,    default: null },
  authToken:         { type: String,  default: null },
  authTokenExpiresAt:{ type: Date,    default: null },
  sek:               { type: String,  default: null },
}, { timestamps: true });

const EWBCredentials = mongoose.models.EWBCredentials || mongoose.model('EWBCredentials', ewbCredentialsSchema);

module.exports = { EWayBill, EWBCredentials };