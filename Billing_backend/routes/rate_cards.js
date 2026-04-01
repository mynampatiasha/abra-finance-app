// ============================================================================
// ABRA FLEET — RATE CARD SCHEMA + API ROUTES
// ============================================================================
// File: backend/routes/rate_cards.js
//
// ARCHITECTURE:
//   Layer 1 → Rate Card  (contract, once per org)
//   Layer 2 → Route Master (setup, once per route) — linked via domain
//   Layer 3 → Daily Operations (trips auto-billed via billing engine)
//
// DOMAIN is the universal linking key:
//   rate_card.domain = "infosys.com"
//   trip.stops[].customer.email = "@infosys.com"
//
// BILLING MODELS supported per vehicle type:
//   PER_KM | PER_TRIP_FIXED | DEDICATED_MONTHLY | HYBRID
//
// API BASE: /api/rate-cards
// ============================================================================

const express  = require('express');
const router   = express.Router();
const mongoose = require('mongoose');

// ============================================================================
// RATE CARD SCHEMA
// ============================================================================

const vehicleRateSchema = new mongoose.Schema({
  vehicleType: {
    type: String,
    required: true,
    enum: [
      'SEDAN',
      'SUV',
      'INNOVA_CRYSTA',
      'TEMPO_TRAVELLER_12',
      'MINI_BUS_20',
      'LARGE_BUS_55',
      'LUXURY_BMW',
      'LUXURY_MERCEDES',
      'LUXURY_AUDI',
    ],
  },
  billingModel: {
    type: String,
    required: true,
    enum: ['PER_KM', 'PER_TRIP_FIXED', 'DEDICATED_MONTHLY', 'HYBRID'],
  },

  // ── PER_KM fields ──────────────────────────────────────────────
  ratePerKm:          { type: Number, default: 0 },   // ₹ per km
  minimumKmPerTrip:   { type: Number, default: 0 },   // bill at least this many km

  // ── PER_TRIP_FIXED fields ───────────────────────────────────────
  ratePerTrip:        { type: Number, default: 0 },   // flat ₹ per trip

  // ── DEDICATED_MONTHLY fields ────────────────────────────────────
  monthlyRate:        { type: Number, default: 0 },   // flat ₹/month for vehicle
  includedKmPerMonth: { type: Number, default: 0 },   // km included in monthly rate

  // ── HYBRID fields (monthly base + per-km excess) ────────────────
  hybridMonthlyBase:  { type: Number, default: 0 },
  hybridIncludedKm:   { type: Number, default: 0 },
  hybridExcessRatePerKm: { type: Number, default: 0 },

  // ── Minimum guarantee ──────────────────────────────────────────
  minimumTripsPerMonth: { type: Number, default: 0 }, // if trips < this, bill minimum

  isActive: { type: Boolean, default: true },
}, { _id: true });

const surchargeRulesSchema = new mongoose.Schema({
  // Night shift: trip start time after nightStartHour (24hr) or before nightEndHour
  nightShiftEnabled:  { type: Boolean, default: false },
  nightStartHour:     { type: Number, default: 22 },   // 10 PM
  nightEndHour:       { type: Number, default: 6  },   // 6 AM
  nightSurchargePerTrip: { type: Number, default: 0 }, // ₹ per trip

  // Weekend surcharge (Saturday / Sunday)
  weekendEnabled:     { type: Boolean, default: false },
  weekendSurchargePercent: { type: Number, default: 0 }, // % on base amount

  // Festival days: list of dates "YYYY-MM-DD"
  festivalEnabled:    { type: Boolean, default: false },
  festivalDates:      [{ type: String }],
  festivalSurchargePercent: { type: Number, default: 0 }, // % on base

  // Waiting charges
  waitingEnabled:     { type: Boolean, default: false },
  waitingFreeMinutes: { type: Number, default: 10 },   // grace period
  waitingRatePerMinute: { type: Number, default: 0 },  // ₹ per minute after grace

  // Toll charges
  tollType: {
    type: String,
    enum: ['INCLUDED', 'ACTUALS', 'NOT_APPLICABLE'],
    default: 'ACTUALS',
  },
  tollFlatRatePerTrip: { type: Number, default: 0 },   // only if INCLUDED

  // Escort / women-only trip surcharge
  escortEnabled:       { type: Boolean, default: false },
  escortSurchargePerTrip: { type: Number, default: 0 }, // ₹ per trip for escort
}, { _id: false });

const slaTermsSchema = new mongoose.Schema({
  onTimePickupPercent:   { type: Number, default: 95 },  // target %
  l1EscalationMinutes:   { type: Number, default: 10 },  // delay before L1 alert
  l2EscalationMinutes:   { type: Number, default: 20 },  // delay before L2 alert
  l3EscalationMinutes:   { type: Number, default: 30 },  // delay before L3 alert
  penaltyPerBreachAmount:{ type: Number, default: 0 },   // ₹ deducted per SLA breach
  maxPenaltyPerMonth:    { type: Number, default: 0 },   // cap on monthly penalty
}, { _id: false });

const rateCardSchema = new mongoose.Schema({
  // ── Auto-generated ID ─────────────────────────────────────────
  rateCardId: {
    type: String,
    unique: true,
    index: true,
  },

  // ── Organisation details ──────────────────────────────────────
  organizationName: { type: String, required: true, trim: true },

  // CRITICAL FIELD — links rate card to all trips for this org
  domain: {
    type: String,
    required: true,
    lowercase: true,
    trim: true,
    index: true,
    // e.g. "infosys.com"
  },

  billingEmail: { type: String, required: true, trim: true },
  contactPersonName: { type: String },
  contactPersonPhone: { type: String },
  gstNumber: { type: String },
  billingAddress: {
    street:  String,
    city:    String,
    state:   String,
    pincode: String,
    country: { type: String, default: 'India' },
  },

  // ── Contract period ───────────────────────────────────────────
  contractStartDate: { type: Date, required: true },
  contractEndDate:   { type: Date, required: true },

  // ── Billing cycle & payment terms ────────────────────────────
  billingCycle: {
    type: String,
    enum: ['MONTHLY', 'FORTNIGHTLY', 'WEEKLY'],
    default: 'MONTHLY',
  },
  paymentTerms: {
    type: String,
    enum: ['Due on Receipt', 'Net 15', 'Net 30', 'Net 45', 'Net 60'],
    default: 'Net 30',
  },
  creditPeriodDays: { type: Number, default: 30 },

  // ── Tax rates ─────────────────────────────────────────────────
  gstPercent: { type: Number, default: 5, min: 0, max: 28 },
  tdsPercent: { type: Number, default: 1, min: 0, max: 30 },

  // ── Vehicle rate matrix (one row per vehicle type) ───────────
  vehicleRates: {
    type: [vehicleRateSchema],
    validate: {
      validator: v => v && v.length > 0,
      message: 'At least one vehicle rate must be defined',
    },
  },

  // ── Surcharge rules ───────────────────────────────────────────
  surchargeRules: { type: surchargeRulesSchema, default: () => ({}) },

  // ── SLA terms ─────────────────────────────────────────────────
  slaTerms: { type: slaTermsSchema, default: () => ({}) },

  // ── Rate card status ──────────────────────────────────────────
  status: {
    type: String,
    enum: ['DRAFT', 'ACTIVE', 'EXPIRED', 'SUSPENDED'],
    default: 'DRAFT',
    index: true,
  },

  // ── Notes ─────────────────────────────────────────────────────
  internalNotes: { type: String },
  termsAndConditions: { type: String },

  // ── Documents ─────────────────────────────────────────────────
  documents: [{
    filename:   String,
    storedName: String,
    filepath:   String,
    mimetype:   String,
    size:       Number,
    uploadedBy: String,
    uploadedAt: { type: Date, default: Date.now },
  }],

  // ── Audit ─────────────────────────────────────────────────────
  createdBy: { type: String, required: true },
  updatedBy: { type: String },
}, {
  timestamps: true,
});

// ── Pre-save: generate rateCardId + auto-expire ──────────────────────────
rateCardSchema.pre('save', async function (next) {
  // Generate ID if new
  if (!this.rateCardId) {
    const year = new Date().getFullYear();
    const last = await RateCard.findOne({
      rateCardId: new RegExp(`^RC-${year}-`),
    }).sort({ rateCardId: -1 });

    let seq = 1;
    if (last) {
      const parts = last.rateCardId.split('-');
      seq = parseInt(parts[2]) + 1;
    }
    this.rateCardId = `RC-${year}-${seq.toString().padStart(4, '0')}`;
  }

  // Auto-expire if contract end date has passed
  if (
    this.status === 'ACTIVE' &&
    this.contractEndDate &&
    new Date() > this.contractEndDate
  ) {
    this.status = 'EXPIRED';
  }

  next();
});

rateCardSchema.index({ domain: 1, status: 1 });
rateCardSchema.index({ contractStartDate: 1, contractEndDate: 1 });

const RateCard = mongoose.models.RateCard || mongoose.model('RateCard', rateCardSchema);

// ============================================================================
// HELPER — build API base URL that works locally AND in production
// ============================================================================

function getBaseUrl(req) {
  // In production, BASE_URL env var is set (e.g. https://api.abratravels.com)
  // Locally it falls back to the request protocol + host
  return process.env.BASE_URL || `${req.protocol}://${req.get('host')}`;
}

// ============================================================================
// HELPER — get active rate card for a domain
// ============================================================================

async function getActiveRateCard(domain) {
  const d = domain.toLowerCase().trim();
  const card = await RateCard.findOne({
    domain: d,
    status: 'ACTIVE',
    contractStartDate: { $lte: new Date() },
    contractEndDate:   { $gte: new Date() },
  });
  return card;
}

// ============================================================================
// ROUTES
// ============================================================================

// ── GET /api/rate-cards — list all (admin) ───────────────────────────────
router.get('/', async (req, res) => {
  try {
    const { status, domain, page = 1, limit = 20 } = req.query;
    const query = {};
    if (status) query.status = status;
    if (domain) query.domain = domain.toLowerCase();

    const skip    = (parseInt(page) - 1) * parseInt(limit);
    const cards   = await RateCard.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-__v');
    const total   = await RateCard.countDocuments(query);

    res.json({
      success: true,
      data: cards,
      pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── GET /api/rate-cards/active/:domain — fetch active card for domain ────
router.get('/active/:domain', async (req, res) => {
  try {
    const card = await getActiveRateCard(req.params.domain);
    if (!card) {
      return res.status(404).json({
        success: false,
        error: `No active rate card found for domain: ${req.params.domain}`,
      });
    }
    res.json({ success: true, data: card });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── GET /api/rate-cards/:id ───────────────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });
    res.json({ success: true, data: card });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/rate-cards — create ────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const body = req.body;

    // Check: only one ACTIVE card per domain allowed
    if (body.status === 'ACTIVE' || !body.status) {
      const existing = await getActiveRateCard(body.domain);
      if (existing) {
        return res.status(409).json({
          success: false,
          error: `An active rate card already exists for domain "${body.domain}" (${existing.rateCardId}). Suspend the existing one before creating a new active card.`,
          existingCardId: existing.rateCardId,
        });
      }
    }

    body.createdBy = req.user?.email || req.user?.uid || 'admin';
    const card = new RateCard(body);
    await card.save();

    res.status(201).json({
      success: true,
      message: `Rate card ${card.rateCardId} created successfully`,
      data: card,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── PUT /api/rate-cards/:id — update ─────────────────────────────────────
router.put('/:id', async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    const updates = req.body;
    updates.updatedBy = req.user?.email || req.user?.uid || 'admin';

    Object.assign(card, updates);
    await card.save();

    res.json({ success: true, message: 'Rate card updated', data: card });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/rate-cards/:id/activate ────────────────────────────────────
router.post('/:id/activate', async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    // Only one active card per domain
    const existing = await getActiveRateCard(card.domain);
    if (existing && existing._id.toString() !== card._id.toString()) {
      return res.status(409).json({
        success: false,
        error: `Rate card ${existing.rateCardId} is already active for domain "${card.domain}". Suspend it first.`,
      });
    }

    card.status = 'ACTIVE';
    card.updatedBy = req.user?.email || 'admin';
    await card.save();

    res.json({ success: true, message: `Rate card ${card.rateCardId} is now ACTIVE`, data: card });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/rate-cards/:id/suspend ─────────────────────────────────────
router.post('/:id/suspend', async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    card.status = 'SUSPENDED';
    card.updatedBy = req.user?.email || 'admin';
    await card.save();

    res.json({ success: true, message: `Rate card ${card.rateCardId} suspended`, data: card });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── PATCH /api/rate-cards/:id/status ─────────────────────────────────────
router.patch('/:id/status', async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    let { status, approvedBy } = req.body;
    
    // Normalize status to uppercase and map frontend values
    const statusMap = {
      'active': 'ACTIVE',
      'inactive': 'SUSPENDED',
      'suspended': 'SUSPENDED',
      'draft': 'DRAFT',
      'expired': 'EXPIRED'
    };
    
    const normalizedStatus = statusMap[status.toLowerCase()] || status.toUpperCase();
    
    // Validate status
    const validStatuses = ['DRAFT', 'ACTIVE', 'EXPIRED', 'SUSPENDED'];
    if (!validStatuses.includes(normalizedStatus)) {
      return res.status(400).json({ 
        success: false, 
        error: `Invalid status. Must be one of: ${validStatuses.join(', ')}` 
      });
    }

    // If activating, check for existing active card
    if (normalizedStatus === 'ACTIVE') {
      const existing = await getActiveRateCard(card.domain);
      if (existing && existing._id.toString() !== card._id.toString()) {
        return res.status(409).json({
          success: false,
          error: `Rate card ${existing.rateCardId} is already active for domain "${card.domain}". Suspend it first.`,
        });
      }
    }

    card.status = normalizedStatus;
    card.updatedBy = approvedBy || req.user?.email || 'admin';
    await card.save();

    res.json({ 
      success: true, 
      message: `Rate card ${card.rateCardId} status updated to ${normalizedStatus}`, 
      data: card 
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── DELETE /api/rate-cards/:id — only DRAFT can be deleted ───────────────
router.delete('/:id', async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    if (card.status !== 'DRAFT') {
      return res.status(400).json({ success: false, error: 'Only DRAFT rate cards can be deleted' });
    }

    await card.deleteOne();
    res.json({ success: true, message: 'Rate card deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================================
// DOCUMENT UPLOAD ROUTES
// ============================================================================

const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');

// ── Storage config ────────────────────────────────────────────────────────
const docStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'rate-card-documents');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `rc-doc-${Date.now()}-${safe}`);
  },
});

const docUpload = multer({
  storage: docStorage,
  limits: { fileSize: 20 * 1024 * 1024 }, // 20 MB
  fileFilter: (req, file, cb) => {
    const allowed = /pdf|jpg|jpeg|png|doc|docx/;
    const ext     = allowed.test(path.extname(file.originalname).toLowerCase());
    const mime    = allowed.test(file.mimetype);
    if (ext || mime) cb(null, true);
    else cb(new Error('Only PDF, JPG, PNG, DOC files allowed'));
  },
});

// ── POST /api/rate-cards/:id/upload-document ──────────────────────────────
router.post('/:id/upload-document', docUpload.single('document'), async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    if (!req.file) return res.status(400).json({ success: false, error: 'No file uploaded' });

    // Add to documents array on the rate card
    if (!card.documents) card.documents = [];
    card.documents.push({
      filename:    req.file.originalname,
      storedName:  req.file.filename,
      filepath:    `/uploads/rate-card-documents/${req.file.filename}`,
      mimetype:    req.file.mimetype,
      size:        req.file.size,
      uploadedBy:  req.user?.email || 'admin',
      uploadedAt:  new Date(),
    });

    card.updatedBy = req.user?.email || 'admin';
    await card.save();

    console.log(`✅ Document uploaded for rate card ${card.rateCardId}: ${req.file.originalname}`);

    res.json({
      success: true,
      message: `${req.file.originalname} uploaded successfully`,
      data: {
        filename:  req.file.originalname,
        filepath:  `/uploads/rate-card-documents/${req.file.filename}`,
        size:      req.file.size,
        uploadedAt: new Date(),
      },
    });
  } catch (err) {
    console.error('Document upload error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── DELETE /api/rate-cards/:id/documents/:filename ────────────────────────
router.delete('/:id/documents/:filename', async (req, res) => {
  try {
    const card = await RateCard.findById(req.params.id);
    if (!card) return res.status(404).json({ success: false, error: 'Rate card not found' });

    const docIndex = (card.documents || []).findIndex(
      d => d.storedName === req.params.filename || d.filename === req.params.filename
    );

    if (docIndex === -1) {
      return res.status(404).json({ success: false, error: 'Document not found' });
    }

    const doc = card.documents[docIndex];

    // Delete file from disk
    const fullPath = path.join(__dirname, '..', 'uploads', 'rate-card-documents', doc.storedName);
    if (fs.existsSync(fullPath)) fs.unlinkSync(fullPath);

    card.documents.splice(docIndex, 1);
    card.updatedBy = req.user?.email || 'admin';
    await card.save();

    res.json({ success: true, message: 'Document deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── Export helper for use in billing engine ───────────────────────────────
module.exports = router;
module.exports.RateCard           = RateCard;
module.exports.getActiveRateCard  = getActiveRateCard;
module.exports.getBaseUrl         = getBaseUrl;