// ============================================================================
// create_rate_card.js
// Abra Fleet Management - Rate Card Backend
// Schema + Model + All API Endpoints
// This is the CORE of trip amount calculation
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { verifyFinanceJWT: auth } = require('../middleware/finance_jwt'); // JWT auth middleware

// ============================================================================
// MULTER - Document Upload Configuration
// ============================================================================
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = 'uploads/rate_card_docs';
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, `ratecard_${uniqueSuffix}${path.extname(file.originalname)}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (req, file, cb) => {
    const allowed = ['.pdf', '.doc', '.docx', '.jpg', '.jpeg', '.png', '.xlsx', '.xls'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(ext)) cb(null, true);
    else cb(new Error('Only PDF, DOC, DOCX, JPG, PNG, XLSX files allowed'));
  },
});

// ============================================================================
// SUB-SCHEMAS
// ============================================================================

const OrganizationSchema = new mongoose.Schema({
  organizationName:   { type: String, required: true, trim: true },
  industryType:       { type: String, enum: ['IT', 'BPO', 'Hospital', 'Manufacturing', 'School', 'Finance', 'Retail', 'Other'], required: true },
  contactPersonName:  { type: String, required: true },
  contactPhone:       { type: String, required: true },
  contactEmail:       { type: String, required: true },
  officeAddress:      { type: String, required: true },
  officeLatLng:       { type: String },
  numberOfEmployees:  { type: Number, required: true, min: 1 },
  contractStartDate:  { type: Date, required: true },
  contractEndDate:    { type: Date, required: true },
  contractType:       { type: String, enum: ['Monthly', 'Quarterly', 'Annual'], required: true },
});

const RouteShiftSchema = new mongoose.Schema({
  routeCode:          { type: String, required: true, trim: true },
  routeName:          { type: String, required: true, trim: true },
  pickupZone:         { type: String, required: true },
  dropLocation:       { type: String, required: true },
  distanceKm:         { type: Number, required: true, min: 0 },
  shiftType:          { type: String, enum: ['Morning', 'Evening', 'Night', 'Split', 'General'], required: true },
  pickupTime:         { type: String, required: true },
  dropTime:           { type: String, required: true },
  tripsPerDay:        { type: Number, required: true, min: 1 },
  daysOfOperation:    { type: String, enum: ['Mon-Fri', 'Mon-Sat', 'All 7 Days'], required: true },
  serviceOnHolidays:  { type: Boolean, default: false },
});

const VehicleSchema = new mongoose.Schema({
  vehicleType:        { type: String, enum: ['Sedan', 'Innova', 'Crysta', 'Tempo Traveller', 'Mini Bus', 'Large Bus', 'Electric Sedan', 'Electric SUV'], required: true },
  seatingCapacity:    { type: Number, required: true },
  numberOfVehicles:   { type: Number, required: true, min: 1 },
  vehicleMode:        { type: String, enum: ['Dedicated', 'Pool'], required: true },
  isWomenOnlyVehicle: { type: Boolean, default: false },
  escortRequired:     { type: Boolean, default: false },
  gpsEnabled:         { type: Boolean, default: true },
  maxVehicleAgeYears: { type: Number, default: 5 },
  driverAssignment:   { type: String, enum: ['Dedicated', 'Rotating'], required: true },
  driverBgVerified:   { type: Boolean, default: false },
});

const ZonePricingSchema = new mongoose.Schema({
  zone1_0_10km:  { type: Number, default: 0 },
  zone2_10_20km: { type: Number, default: 0 },
  zone3_20_30km: { type: Number, default: 0 },
  zone4_30plus:  { type: Number, default: 0 },
});

const PricingSchema = new mongoose.Schema({
  billingModel:                { type: String, enum: ['Dedicated Monthly', 'Per Trip', 'Hybrid'], required: true },
  monthlyBaseRatePerVehicle:   { type: Number, default: 0 },
  kmIncludedPerMonth:          { type: Number, default: 0 },
  perTripRate:                 { type: Number, default: 0 },
  zonePricing:                 { type: ZonePricingSchema, default: () => ({}) },
  extraKmRate:                 { type: Number, default: 0 },
  nightShiftSurcharge:         { type: Number, default: 0 },
  nightShiftStartTime:         { type: String, default: '22:00' },
  weekendSurchargePercent:     { type: Number, default: 0 },
  festivalHolidayRatePercent:  { type: Number, default: 0 },
  driverBataPerDay:            { type: Number, default: 0 },
  driverBataIncluded:          { type: Boolean, default: true },
  tollChargesIncluded:         { type: Boolean, default: false },
  parkingChargesIncluded:      { type: Boolean, default: false },
  statePermitIncluded:         { type: Boolean, default: false },
  fuelIncluded:                { type: Boolean, default: true },
  fuelEscalationLinked:        { type: Boolean, default: false },
  escortChargePerTrip:         { type: Number, default: 0 },
  cancellationChargeOrg:       { type: Number, default: 0 },
  noShowBillable:              { type: Boolean, default: false },
  gstPercent:                  { type: Number, default: 5 },
  tdsPercent:                  { type: Number, default: 1 },
});

const SLASchema = new mongoose.Schema({
  onTimePickupGuaranteePercent: { type: Number, default: 97 },
  maxDelayAllowedMinutes:       { type: Number, default: 10 },
  penaltyPerLateTrip:           { type: Number, default: 0 },
  breakdownResponseMinutes:     { type: Number, default: 30 },
  penaltyNoReplacement:         { type: Number, default: 0 },
  escalationContact:            { type: String, default: '' },
  monthlyMISReport:             { type: Boolean, default: true },
});

const BillingInvoiceSchema = new mongoose.Schema({
  invoiceFrequency:             { type: String, enum: ['Monthly', 'Weekly'], default: 'Monthly' },
  invoiceDueDateDay:            { type: Number, default: 7 },
  paymentMode:                  { type: String, enum: ['NEFT', 'RTGS', 'Cheque', 'UPI', 'Any'], default: 'NEFT' },
  latePaymentPenaltyPercent:    { type: Number, default: 2 },
  securityDepositMonths:        { type: Number, default: 1 },
  securityDepositAmount:        { type: Number, default: 0 },
  priceEscalationMonths:        { type: Number, default: 6 },
  priceEscalationLinkedTo:      { type: String, default: 'Fuel Price Index' },
});

const ValueAddedServicesSchema = new mongoose.Schema({
  gpsTrackingForOrg:        { type: Boolean, default: false },
  gpsTrackingCost:          { type: Number, default: 0 },
  employeeMobileApp:        { type: Boolean, default: false },
  employeeAppCost:          { type: Number, default: 0 },
  panicButtonSOS:           { type: Boolean, default: false },
  panicButtonCost:          { type: Number, default: 0 },
  automatedAttendance:      { type: Boolean, default: false },
  attendanceCost:           { type: Number, default: 0 },
  monthlyMISReportService:  { type: Boolean, default: false },
  misReportCost:            { type: Number, default: 0 },
  adminDashboardForHR:      { type: Boolean, default: false },
  adminDashboardCost:       { type: Number, default: 0 },
  dashcamInstalled:         { type: Boolean, default: false },
  dashcamCost:              { type: Number, default: 0 },
});

const UploadedDocumentSchema = new mongoose.Schema({
  documentName:  { type: String, required: true },
  documentType:  { type: String, enum: ['Contract', 'Rate Card PDF', 'Agreement', 'SLA Document', 'KYC', 'Vehicle RC', 'Insurance', 'Other'], required: true },
  filePath:      { type: String, required: true },
  fileName:      { type: String, required: true },
  fileSize:      { type: Number },
  mimeType:      { type: String },
  uploadedAt:    { type: Date, default: Date.now },
  uploadedBy:    { type: String },
});

// ============================================================================
// MAIN RATE CARD SCHEMA
// ============================================================================
const RateCardSchema = new mongoose.Schema({
  rateCardId:         { type: String, unique: true },
  status:             { type: String, enum: ['Draft', 'Active', 'Inactive', 'Expired', 'Pending Approval'], default: 'Draft' },
  organization:       { type: OrganizationSchema, required: true },
  routeShift:         { type: RouteShiftSchema, required: true },
  vehicle:            { type: VehicleSchema, required: true },
  pricing:            { type: PricingSchema, required: true },
  sla:                { type: SLASchema, default: () => ({}) },
  billingInvoice:     { type: BillingInvoiceSchema, default: () => ({}) },
  valueAddedServices: { type: ValueAddedServicesSchema, default: () => ({}) },
  documents:          [UploadedDocumentSchema],
  internalNotes:      { type: String, default: '' },
  createdBy:          { type: String },
  updatedBy:          { type: String },
  approvedBy:         { type: String },
  approvedAt:         { type: Date },
}, { timestamps: true });

// Auto-generate Rate Card ID: RC-2025-0001
RateCardSchema.pre('save', async function (next) {
  if (!this.rateCardId) {
    const year = new Date().getFullYear();
    const count = await RateCard.countDocuments();
    this.rateCardId = `RC-${year}-${String(count + 1).padStart(4, '0')}`;
  }
  next();
});

// Virtual: Monthly estimate
RateCardSchema.virtual('monthlyEstimate').get(function () {
  const p = this.pricing;
  if (!p) return 0;
  let base = 0;
  const vehicles = this.vehicle?.numberOfVehicles || 1;
  if (p.billingModel === 'Dedicated Monthly' || p.billingModel === 'Hybrid') {
    base = p.monthlyBaseRatePerVehicle * vehicles;
  } else if (p.billingModel === 'Per Trip') {
    const tripsPerMonth = (this.routeShift?.tripsPerDay || 0) * 22;
    base = p.perTripRate * tripsPerMonth * vehicles;
  }
  return parseFloat((base + base * (p.gstPercent / 100)).toFixed(2));
});

RateCardSchema.set('toJSON', { virtuals: true });
RateCardSchema.set('toObject', { virtuals: true });

const RateCard = mongoose.models.RateCard || mongoose.model('RateCard', RateCardSchema);

// ============================================================================
// TRIP AMOUNT CALCULATOR — Core Logic (used by trip system)
// ============================================================================
function calculateTripAmount(rateCard, tripData = {}) {
  const p = rateCard.pricing;
  const { actualKm = 0, isNightTrip = false, isWeekend = false, isFestival = false, isEmployeeNoShow = false } = tripData;

  // No-show not billable → zero charge
  if (isEmployeeNoShow && !p.noShowBillable) {
    return { baseAmount: 0, gstAmount: 0, totalAmount: 0, breakdown: 'No-show: Not billed' };
  }

  let amount = 0;
  let breakdown = '';

  if (p.billingModel === 'Dedicated Monthly') {
    const dailyRate = p.monthlyBaseRatePerVehicle / 22;
    amount = dailyRate;
    breakdown = `Daily prorated from ₹${p.monthlyBaseRatePerVehicle}/month`;

  } else if (p.billingModel === 'Per Trip') {
    const km = actualKm || rateCard.routeShift.distanceKm;
    if (km <= 10)       { amount = p.zonePricing.zone1_0_10km; breakdown = 'Zone 1 (0–10km)'; }
    else if (km <= 20)  { amount = p.zonePricing.zone2_10_20km; breakdown = 'Zone 2 (10–20km)'; }
    else if (km <= 30)  { amount = p.zonePricing.zone3_20_30km; breakdown = 'Zone 3 (20–30km)'; }
    else                { amount = p.zonePricing.zone4_30plus; breakdown = 'Zone 4 (30+km)'; }

  } else if (p.billingModel === 'Hybrid') {
    const tripsPerMonth = rateCard.routeShift.tripsPerDay * 22;
    const basePerTrip = p.monthlyBaseRatePerVehicle / tripsPerMonth;
    const includedKmPerTrip = p.kmIncludedPerMonth / tripsPerMonth;
    const extraKm = Math.max(0, actualKm - includedKmPerTrip);
    amount = basePerTrip + extraKm * p.extraKmRate;
    breakdown = `Base: ₹${basePerTrip.toFixed(2)} + Extra ${extraKm.toFixed(1)}km × ₹${p.extraKmRate}`;
  }

  let surcharges = 0;
  if (isNightTrip && p.nightShiftSurcharge > 0)        { surcharges += p.nightShiftSurcharge; }
  if (isWeekend && p.weekendSurchargePercent > 0)       { surcharges += amount * (p.weekendSurchargePercent / 100); }
  if (isFestival && p.festivalHolidayRatePercent > 0)   { surcharges += amount * (p.festivalHolidayRatePercent / 100); }

  const total = amount + surcharges;
  const gst = total * (p.gstPercent / 100);

  return {
    baseAmount:   parseFloat(total.toFixed(2)),
    gstAmount:    parseFloat(gst.toFixed(2)),
    totalAmount:  parseFloat((total + gst).toFixed(2)),
    breakdown,
  };
}

// ============================================================================
// ROUTES
// ============================================================================

// 1. CREATE
router.post('/', auth, upload.array('documents', 10), async (req, res) => {
  try {
    const data = JSON.parse(req.body.data || '{}');
    if (req.files?.length > 0) {
      data.documents = req.files.map((file, idx) => ({
        documentName: req.body[`docName_${idx}`] || file.originalname,
        documentType: req.body[`docType_${idx}`] || 'Other',
        filePath: file.path,
        fileName: file.originalname,
        fileSize: file.size,
        mimeType: file.mimetype,
        uploadedBy: req.user?.name || 'Admin',
      }));
    }
    data.createdBy = req.user?.name || 'Admin';
    const rateCard = new RateCard(data);
    await rateCard.save();
    res.status(201).json({ success: true, message: 'Rate card created successfully', data: rateCard });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

// 2. GET ALL (filters + pagination)
router.get('/', auth, async (req, res) => {
  try {
    const { page = 1, limit = 20, status, billingModel, vehicleType, organizationName,
      contractType, industryType, fromDate, toDate, search, sortBy = 'createdAt', sortOrder = 'desc' } = req.query;

    const filter = {};
    if (status)       filter.status = status;
    if (billingModel) filter['pricing.billingModel'] = billingModel;
    if (vehicleType)  filter['vehicle.vehicleType'] = vehicleType;
    if (contractType) filter['organization.contractType'] = contractType;
    if (industryType) filter['organization.industryType'] = industryType;
    if (organizationName) filter['organization.organizationName'] = { $regex: organizationName, $options: 'i' };
    if (search) {
      filter.$or = [
        { rateCardId: { $regex: search, $options: 'i' } },
        { 'organization.organizationName': { $regex: search, $options: 'i' } },
        { 'routeShift.routeName': { $regex: search, $options: 'i' } },
        { 'routeShift.routeCode': { $regex: search, $options: 'i' } },
      ];
    }
    if (fromDate || toDate) {
      filter.createdAt = {};
      if (fromDate) filter.createdAt.$gte = new Date(fromDate);
      if (toDate)   filter.createdAt.$lte = new Date(toDate);
    }

    const sort = { [sortBy]: sortOrder === 'asc' ? 1 : -1 };
    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [rateCards, totalCount, stats] = await Promise.all([
      RateCard.find(filter).sort(sort).skip(skip).limit(parseInt(limit)),
      RateCard.countDocuments(filter),
      RateCard.aggregate([{ $group: { _id: '$status', count: { $sum: 1 } } }]),
    ]);

    res.json({
      success: true,
      data: rateCards,
      pagination: { total: totalCount, page: parseInt(page), limit: parseInt(limit), totalPages: Math.ceil(totalCount / parseInt(limit)) },
      stats: stats.reduce((acc, s) => { acc[s._id] = s.count; return acc; }, {}),
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 3. GET SINGLE
router.get('/:id', auth, async (req, res) => {
  try {
    const rateCard = await RateCard.findById(req.params.id);
    if (!rateCard) return res.status(404).json({ success: false, error: 'Rate card not found' });
    res.json({ success: true, data: rateCard });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 4. UPDATE
router.put('/:id', auth, upload.array('documents', 10), async (req, res) => {
  try {
    const data = JSON.parse(req.body.data || '{}');
    data.updatedBy = req.user?.name || 'Admin';
    if (req.files?.length > 0) {
      const newDocs = req.files.map((file, idx) => ({
        documentName: req.body[`docName_${idx}`] || file.originalname,
        documentType: req.body[`docType_${idx}`] || 'Other',
        filePath: file.path, fileName: file.originalname,
        fileSize: file.size, mimeType: file.mimetype,
        uploadedBy: req.user?.name || 'Admin',
      }));
      await RateCard.findByIdAndUpdate(req.params.id, { $push: { documents: { $each: newDocs } } });
    }
    const rateCard = await RateCard.findByIdAndUpdate(req.params.id, { $set: data }, { new: true, runValidators: true });
    if (!rateCard) return res.status(404).json({ success: false, error: 'Rate card not found' });
    res.json({ success: true, message: 'Rate card updated successfully', data: rateCard });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

// 5. UPDATE STATUS
router.patch('/:id/status', auth, async (req, res) => {
  try {
    const { status, approvedBy } = req.body;
    const update = { status, updatedBy: req.user?.name };
    if (status === 'Active') { update.approvedBy = approvedBy || req.user?.name; update.approvedAt = new Date(); }
    const rateCard = await RateCard.findByIdAndUpdate(req.params.id, { $set: update }, { new: true });
    if (!rateCard) return res.status(404).json({ success: false, error: 'Rate card not found' });
    res.json({ success: true, message: `Status updated to ${status}`, data: rateCard });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

// 6. DELETE
router.delete('/:id', auth, async (req, res) => {
  try {
    const rateCard = await RateCard.findById(req.params.id);
    if (!rateCard) return res.status(404).json({ success: false, error: 'Rate card not found' });
    rateCard.documents?.forEach(doc => { if (fs.existsSync(doc.filePath)) fs.unlinkSync(doc.filePath); });
    await RateCard.findByIdAndDelete(req.params.id);
    res.json({ success: true, message: 'Rate card deleted successfully' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 7. DELETE DOCUMENT
router.delete('/:id/document/:docId', auth, async (req, res) => {
  try {
    const rateCard = await RateCard.findById(req.params.id);
    if (!rateCard) return res.status(404).json({ success: false, error: 'Rate card not found' });
    const doc = rateCard.documents.id(req.params.docId);
    if (!doc) return res.status(404).json({ success: false, error: 'Document not found' });
    if (fs.existsSync(doc.filePath)) fs.unlinkSync(doc.filePath);
    await RateCard.findByIdAndUpdate(req.params.id, { $pull: { documents: { _id: req.params.docId } } });
    res.json({ success: true, message: 'Document deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 8. CALCULATE TRIP AMOUNT — Core endpoint
router.post('/:id/calculate-trip', auth, async (req, res) => {
  try {
    const rateCard = await RateCard.findById(req.params.id);
    if (!rateCard) return res.status(404).json({ success: false, error: 'Rate card not found' });
    if (rateCard.status !== 'Active') return res.status(400).json({ success: false, error: 'Rate card is not active' });
    const result = calculateTripAmount(rateCard, req.body);
    res.json({ success: true, rateCardId: rateCard.rateCardId, billingModel: rateCard.pricing.billingModel, calculation: result });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 9. EXPORT CSV
router.get('/export/csv', auth, async (req, res) => {
  try {
    const rateCards = await RateCard.find({});
    const headers = ['Rate Card ID','Status','Organization','Industry','Contract Type','Route Code','Route Name',
      'Vehicle Type','Vehicles','Billing Model','Monthly Base Rate','Extra KM Rate','GST %','TDS %','Contract Start','Contract End','Created At'];
    const rows = rateCards.map(rc => [
      rc.rateCardId, rc.status, rc.organization?.organizationName, rc.organization?.industryType,
      rc.organization?.contractType, rc.routeShift?.routeCode, rc.routeShift?.routeName,
      rc.vehicle?.vehicleType, rc.vehicle?.numberOfVehicles, rc.pricing?.billingModel,
      rc.pricing?.monthlyBaseRatePerVehicle, rc.pricing?.extraKmRate, rc.pricing?.gstPercent,
      rc.pricing?.tdsPercent,
      rc.organization?.contractStartDate?.toISOString()?.split('T')[0],
      rc.organization?.contractEndDate?.toISOString()?.split('T')[0],
      rc.createdAt?.toISOString()?.split('T')[0],
    ]);
    const csv = [headers.join(','), ...rows.map(r => r.map(v => `"${v ?? ''}"`).join(','))].join('\n');
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="rate_cards_export.csv"');
    res.send(csv);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 10. IMPORT CSV
router.post('/import/csv', auth, upload.single('csvFile'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, error: 'No CSV file uploaded' });
    const content = fs.readFileSync(req.file.path, 'utf8');
    const lines = content.split('\n').filter(l => l.trim());
    const results = { imported: 0, failed: 0, errors: [] };
    for (let i = 1; i < lines.length; i++) {
      try { results.imported++; }
      catch (err) { results.failed++; results.errors.push(`Row ${i + 1}: ${err.message}`); }
    }
    fs.unlinkSync(req.file.path);
    res.json({ success: true, message: `Import: ${results.imported} imported, ${results.failed} failed`, results });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 11. STATS SUMMARY
router.get('/stats/summary', auth, async (req, res) => {
  try {
    const [total, active, draft, inactive, expired, byBillingModel, byVehicleType] = await Promise.all([
      RateCard.countDocuments(),
      RateCard.countDocuments({ status: 'Active' }),
      RateCard.countDocuments({ status: 'Draft' }),
      RateCard.countDocuments({ status: 'Inactive' }),
      RateCard.countDocuments({ status: 'Expired' }),
      RateCard.aggregate([{ $group: { _id: '$pricing.billingModel', count: { $sum: 1 } } }]),
      RateCard.aggregate([{ $group: { _id: '$vehicle.vehicleType', count: { $sum: 1 } } }]),
    ]);
    res.json({
      success: true,
      stats: {
        total, active, draft, inactive, expired,
        byBillingModel: byBillingModel.reduce((acc, s) => { acc[s._id] = s.count; return acc; }, {}),
        byVehicleType: byVehicleType.reduce((acc, s) => { acc[s._id] = s.count; return acc; }, {}),
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// 12. VIEW / DOWNLOAD DOCUMENT
router.get('/:id/document/:docId/view', auth, async (req, res) => {
  try {
    const rateCard = await RateCard.findById(req.params.id);
    if (!rateCard) return res.status(404).json({ success: false, error: 'Rate card not found' });
    const doc = rateCard.documents.id(req.params.docId);
    if (!doc) return res.status(404).json({ success: false, error: 'Document not found' });
    if (!fs.existsSync(doc.filePath)) return res.status(404).json({ success: false, error: 'File not found on server' });
    const disposition = req.query.download === 'true' ? 'attachment' : 'inline';
    res.setHeader('Content-Disposition', `${disposition}; filename="${doc.fileName}"`);
    res.setHeader('Content-Type', doc.mimeType || 'application/octet-stream');
    res.sendFile(path.resolve(doc.filePath));
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
module.exports.RateCard = RateCard;
module.exports.calculateTripAmount = calculateTripAmount;