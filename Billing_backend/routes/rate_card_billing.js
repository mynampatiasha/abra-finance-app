// ============================================================================
// ABRA FLEET — RATE CARD BILLING ENGINE
// ============================================================================
// File: backend/routes/rate_card_billing.js
//
// WHAT THIS FILE DOES:
//   1. Fetches all completed trips for an org domain
//   2. For each trip → applies rate card rules → calculates correct amount
//   3. Stacks surcharges: night → weekend → festival → waiting → toll → escort
//   4. Handles all 4 billing models: PER_KM / PER_TRIP_FIXED / DEDICATED_MONTHLY / HYBRID
//   5. Enforces minimum km guarantee and minimum trip guarantee
//   6. Generates month-end invoice with full line-item breakdown
//   7. Sends invoice to Finance queue — waits for approval
//   8. On Finance approval → auto-sends to organization billing email
//
// API BASE: /api/billing
//
// DEPENDENCIES:
//   rate_cards.js  → RateCard model + getActiveRateCard()
//   invoices.js    → Invoice model (for invoice creation + email)
// ============================================================================

const express   = require('express');
const router    = express.Router();
const mongoose  = require('mongoose');
const nodemailer = require('nodemailer');
const PDFDocument = require('pdfkit');
const fs        = require('fs');
const path      = require('path');

// Import from rate card routes
const { RateCard, getActiveRateCard, getBaseUrl } = require('./rate_cards');

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

// ── Trip Billing Record — stores calculated amount against each trip ──────
const tripBillingSchema = new mongoose.Schema({
  tripId:         { type: String, required: true, index: true },
  tripCollection: {
    type: String,
    enum: ['roster-assigned-trips', 'client_created_trips', 'trips'],
    required: true,
  },
  domain:         { type: String, required: true, index: true, lowercase: true },
  rateCardId:     { type: String, required: true },
  rateCardMongoId:{ type: mongoose.Schema.Types.ObjectId },

  // Trip metadata
  tripDate:        { type: Date, required: true },
  vehicleType:     { type: String },
  vehicleNumber:   { type: String },
  driverName:      { type: String },
  actualKm:        { type: Number, default: 0 },
  billedKm:        { type: Number, default: 0 },   // max(actualKm, minimumKmPerTrip)
  waitingMinutes:  { type: Number, default: 0 },
  isNightTrip:     { type: Boolean, default: false },
  isWeekend:       { type: Boolean, default: false },
  isFestival:      { type: Boolean, default: false },
  isEscortTrip:    { type: Boolean, default: false },
  tollAmount:      { type: Number, default: 0 },
  pickupZone:      { type: String },
  dropZone:        { type: String },
  routeName:       { type: String },
  shiftTime:       { type: String },

  // Billing model used
  billingModel:    { type: String },

  // Calculated amounts (all in ₹)
  baseAmount:         { type: Number, default: 0 },
  nightSurcharge:     { type: Number, default: 0 },
  weekendSurcharge:   { type: Number, default: 0 },
  festivalSurcharge:  { type: Number, default: 0 },
  waitingSurcharge:   { type: Number, default: 0 },
  tollSurcharge:      { type: Number, default: 0 },
  escortSurcharge:    { type: Number, default: 0 },
  totalSurcharges:    { type: Number, default: 0 },
  subtotalBeforeTax:  { type: Number, default: 0 },

  // Status
  status: {
    type: String,
    enum: ['CALCULATED', 'INVOICED', 'PAID'],
    default: 'CALCULATED',
    index: true,
  },

  billingPeriod:   { type: String },   // "2025-03" for March 2025
  invoiceId:       { type: mongoose.Schema.Types.ObjectId },

  calculatedAt:    { type: Date, default: Date.now },
  calculatedBy:    { type: String },
}, { timestamps: true });

tripBillingSchema.index({ domain: 1, billingPeriod: 1, status: 1 });
// Check if model already exists to avoid OverwriteModelError
const TripBilling = mongoose.models.TripBilling || mongoose.model('TripBilling', tripBillingSchema);

// ── Billing Invoice Schema (extends your existing invoice concept) ─────────
const billingInvoiceSchema = new mongoose.Schema({
  invoiceNumber:  { type: String, unique: true, index: true },
  domain:         { type: String, required: true, lowercase: true, index: true },
  rateCardId:     { type: String, required: true },
  organizationName: { type: String, required: true },
  billingEmail:   { type: String, required: true },

  billingPeriodStart: { type: Date, required: true },
  billingPeriodEnd:   { type: Date, required: true },
  billingPeriodLabel: { type: String },   // "March 2025"

  // Line items (one per vehicle type / billing model)
  lineItems: [{
    description:      String,
    vehicleType:      String,
    billingModel:     String,
    quantity:         Number,
    unitDescription:  String,   // "trips", "km", "months"
    unitRate:         Number,
    baseAmount:       Number,
    surchargeBreakdown: {
      nightSurcharge:    { type: Number, default: 0 },
      weekendSurcharge:  { type: Number, default: 0 },
      festivalSurcharge: { type: Number, default: 0 },
      waitingSurcharge:  { type: Number, default: 0 },
      tollSurcharge:     { type: Number, default: 0 },
      escortSurcharge:   { type: Number, default: 0 },
      totalSurcharges:   { type: Number, default: 0 },
    },
    lineTotal: Number,
  }],

  // Minimum guarantee adjustment line
  minimumGuaranteeApplied:  { type: Boolean, default: false },
  minimumGuaranteeAmount:   { type: Number, default: 0 },
  minimumGuaranteeDetails:  { type: String },

  // SLA penalties
  slaBreaches:     { type: Number, default: 0 },
  slaPenaltyAmount: { type: Number, default: 0 },

  // Totals
  subtotal:        { type: Number, required: true },
  gstPercent:      { type: Number, default: 5 },
  gstAmount:       { type: Number, default: 0 },
  cgst:            { type: Number, default: 0 },
  sgst:            { type: Number, default: 0 },
  tdsPercent:      { type: Number, default: 1 },
  tdsAmount:       { type: Number, default: 0 },
  totalAmount:     { type: Number, required: true },

  // Trip summary
  totalTrips:           { type: Number, default: 0 },
  completedTrips:       { type: Number, default: 0 },
  cancelledTrips:       { type: Number, default: 0 },
  totalKm:              { type: Number, default: 0 },

  // Finance workflow
  status: {
    type: String,
    enum: [
      'DRAFT',
      'PENDING_FINANCE_APPROVAL',
      'APPROVED',
      'SENT',
      'PAID',
      'DISPUTED',
    ],
    default: 'DRAFT',
    index: true,
  },

  pdfPath:              String,
  pdfGeneratedAt:       Date,

  financeApprovedBy:    String,
  financeApprovedAt:    Date,
  financeNotes:         String,

  sentToOrgAt:          Date,
  sentToOrgEmail:       String,

  createdBy:   { type: String },
  updatedBy:   { type: String },
}, { timestamps: true });

billingInvoiceSchema.index({ domain: 1, billingPeriodStart: 1 });
// Check if model already exists to avoid OverwriteModelError
const BillingInvoice = mongoose.models.BillingInvoice || mongoose.model('BillingInvoice', billingInvoiceSchema);

// ============================================================================
// CORE BILLING ENGINE — trip amount calculation
// ============================================================================

/**
 * calculateTripAmount()
 * Given a completed trip and its rate card, calculates the full billed amount.
 * Returns a detailed breakdown object.
 */
function calculateTripAmount(trip, rateCard) {
  // Find the vehicle rate row for this trip's vehicle type
  const vehicleType = trip.vehicleType || trip.vehicle?.type || 'SEDAN';
  const rateRow = rateCard.vehicleRates.find(r => r.vehicleType === vehicleType && r.isActive);

  if (!rateRow) {
    return {
      error: `No active rate found for vehicle type "${vehicleType}" in rate card ${rateCard.rateCardId}`,
      baseAmount: 0,
      totalSurcharges: 0,
      subtotalBeforeTax: 0,
    };
  }

  const s = rateCard.surchargeRules;
  const actualKm = trip.actualKm || trip.distance || 0;

  // ── STEP 1: Base amount by billing model ─────────────────────────────────
  let baseAmount  = 0;
  let billedKm    = actualKm;
  const billingModel = rateRow.billingModel;

  if (billingModel === 'PER_KM') {
    // Bill at least minimumKmPerTrip
    billedKm   = Math.max(actualKm, rateRow.minimumKmPerTrip || 0);
    baseAmount = billedKm * rateRow.ratePerKm;

  } else if (billingModel === 'PER_TRIP_FIXED') {
    billedKm   = 0;
    baseAmount = rateRow.ratePerTrip;

  } else if (billingModel === 'DEDICATED_MONTHLY') {
    // Per-trip billing = 0. Monthly total handled at invoice generation.
    billedKm   = actualKm;
    baseAmount = 0;

  } else if (billingModel === 'HYBRID') {
    // Monthly base is billed at invoice level.
    // Per trip: only excess km beyond includedKm is billed here.
    billedKm = actualKm;
    // Excess is computed at invoice level, not per trip. Per trip amount = 0.
    baseAmount = 0;
  }

  // ── STEP 2: Determine trip flags ─────────────────────────────────────────
  const tripDate   = new Date(trip.tripDate || trip.scheduledAt || trip.createdAt);
  const tripHour   = tripDate.getHours();
  const dayOfWeek  = tripDate.getDay(); // 0=Sunday, 6=Saturday

  const isNightTrip = s.nightShiftEnabled && (
    tripHour >= s.nightStartHour || tripHour < s.nightEndHour
  );

  const isWeekend = s.weekendEnabled && (dayOfWeek === 0 || dayOfWeek === 6);

  const tripDateStr = tripDate.toISOString().split('T')[0]; // "YYYY-MM-DD"
  const isFestival  = s.festivalEnabled &&
    Array.isArray(s.festivalDates) &&
    s.festivalDates.includes(tripDateStr);

  const isEscortTrip = trip.escortRequired || trip.isWomenOnly || false;

  // ── STEP 3: Stack surcharges ──────────────────────────────────────────────
  let nightSurcharge    = 0;
  let weekendSurcharge  = 0;
  let festivalSurcharge = 0;
  let waitingSurcharge  = 0;
  let tollSurcharge     = 0;
  let escortSurcharge   = 0;

  // Night surcharge: flat ₹ per trip
  if (isNightTrip && s.nightSurchargePerTrip > 0) {
    nightSurcharge = s.nightSurchargePerTrip;
  }

  // Weekend surcharge: % on base
  if (isWeekend && s.weekendSurchargePercent > 0) {
    weekendSurcharge = (baseAmount * s.weekendSurchargePercent) / 100;
  }

  // Festival surcharge: % on base
  if (isFestival && s.festivalSurchargePercent > 0) {
    festivalSurcharge = (baseAmount * s.festivalSurchargePercent) / 100;
  }

  // Waiting surcharge: ₹/min beyond grace period
  if (s.waitingEnabled && s.waitingRatePerMinute > 0) {
    const totalWaitMin  = trip.waitingMinutes || 0;
    const billableMin   = Math.max(0, totalWaitMin - (s.waitingFreeMinutes || 0));
    waitingSurcharge    = billableMin * s.waitingRatePerMinute;
  }

  // Toll surcharge
  if (s.tollType === 'ACTUALS') {
    tollSurcharge = trip.tollAmount || 0;
  } else if (s.tollType === 'INCLUDED') {
    tollSurcharge = s.tollFlatRatePerTrip || 0;
  }
  // If NOT_APPLICABLE → 0

  // Escort surcharge: flat ₹ per women-only trip
  if (isEscortTrip && s.escortEnabled && s.escortSurchargePerTrip > 0) {
    escortSurcharge = s.escortSurchargePerTrip;
  }

  // ── STEP 4: Total ─────────────────────────────────────────────────────────
  const totalSurcharges = round2(
    nightSurcharge + weekendSurcharge + festivalSurcharge +
    waitingSurcharge + tollSurcharge + escortSurcharge
  );

  const subtotalBeforeTax = round2(baseAmount + totalSurcharges);

  return {
    vehicleType,
    billingModel,
    actualKm:        round2(actualKm),
    billedKm:        round2(billedKm),
    baseAmount:      round2(baseAmount),
    nightSurcharge:  round2(nightSurcharge),
    weekendSurcharge:round2(weekendSurcharge),
    festivalSurcharge:round2(festivalSurcharge),
    waitingSurcharge:round2(waitingSurcharge),
    tollSurcharge:   round2(tollSurcharge),
    escortSurcharge: round2(escortSurcharge),
    totalSurcharges,
    subtotalBeforeTax,
    isNightTrip,
    isWeekend,
    isFestival,
    isEscortTrip,
    rateCardId: rateCard.rateCardId,
  };
}

function round2(n) {
  return Math.round((n || 0) * 100) / 100;
}

// ============================================================================
// INVOICE NUMBER GENERATOR
// ============================================================================

async function generateBillingInvoiceNumber(domain) {
  const { generateNumber } = require('../utils/numberGenerator');
  // domain-scoped: treat domain as orgId equivalent for billing invoices
  const query = { invoiceNumber: new RegExp(`^BINV\\d`) };
  if (domain) query.domain = domain.toLowerCase();
  const existing = await BillingInvoice.find(query).select('invoiceNumber').lean();
  let max = 0;
  for (const doc of existing) {
    const n = parseInt((doc.invoiceNumber || '').slice('BINV'.length), 10);
    if (!isNaN(n) && n > max) max = n;
  }
  return `BINV${String(max + 1).padStart(6, '0')}`;
}

// ============================================================================
// EMAIL TRANSPORT (same as invoices.js)
// ============================================================================

const emailTransporter = nodemailer.createTransport({
  host:   process.env.SMTP_HOST || 'smtp.gmail.com',
  port:   parseInt(process.env.SMTP_PORT) || 587,
  secure: false,
  auth:   {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASSWORD,
  },
});

// ============================================================================
// PDF GENERATOR — billing invoice
// ============================================================================

async function generateBillingInvoicePDF(invoice) {
  return new Promise((resolve, reject) => {
    try {
      const dir = path.join(__dirname, '..', 'uploads', 'billing-invoices');
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

      const filename = `billing-invoice-${invoice.invoiceNumber}.pdf`;
      const filepath = path.join(dir, filename);

      const doc    = new PDFDocument({ size: 'A4', margin: 40, bufferPages: true });
      const stream = fs.createWriteStream(filepath);
      doc.pipe(stream);

      // ── Logo ─────────────────────────────────────────────────────
      const logoCandidates = [
        path.join(__dirname, '..', 'assets', 'abra.jpeg'),
        path.join(__dirname, '..', 'assets', 'abra.jpg'),
        path.join(__dirname, '..', 'assets', 'abra.png'),
        path.join(process.cwd(), 'assets', 'abra.jpeg'),
      ];
      let logoLoaded = false;
      for (const lp of logoCandidates) {
        if (fs.existsSync(lp)) {
          try { doc.image(lp, 40, 35, { width: 120, fit: [120, 60] }); logoLoaded = true; break; }
          catch (_) {}
        }
      }
      if (!logoLoaded) {
        doc.fontSize(20).fillColor('#1a2744').font('Helvetica-Bold').text('ABRA Travels', 40, 40);
      }

      // ── Company info ─────────────────────────────────────────────
      const cy = logoLoaded ? 105 : 80;
      doc.fontSize(8).fillColor('#555').font('Helvetica')
        .text('Bangalore, Karnataka, India', 40, cy)
        .text('GST: 29AABCT1332L1ZM', 40, cy + 11)
        .text('+91 88672 88076', 40, cy + 22);

      // ── Title ────────────────────────────────────────────────────
      doc.fontSize(28).fillColor('#1a2744').font('Helvetica-Bold').text('BILLING INVOICE', 250, 40, { align: 'right' });
      doc.fontSize(9).fillColor('#2563eb').font('Helvetica-Bold').text(invoice.status, 250, 76, { align: 'right' });

      // ── Invoice details box ───────────────────────────────────────
      let boxY = 155;
      doc.rect(40, boxY, 515, 65).fillAndStroke('#f0f5fb', '#dde5f0');
      doc.rect(40, boxY, 515, 2).fillAndStroke('#1a2744', '#1a2744');

      doc.fontSize(8).fillColor('#1a2744').font('Helvetica-Bold');
      doc.text('Invoice Number:',    50, boxY + 10);
      doc.text('Billing Period:',    50, boxY + 24);
      doc.text('Invoice Date:',      50, boxY + 38);
      doc.text('Payment Terms:',     50, boxY + 52);

      doc.fillColor('#000').font('Helvetica');
      doc.text(invoice.invoiceNumber,                                    170, boxY + 10);
      doc.text(invoice.billingPeriodLabel || '',                         170, boxY + 24);
      doc.text(new Date().toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }), 170, boxY + 38);
      doc.text('As per contract',                                        170, boxY + 52);

      doc.fillColor('#1a2744').font('Helvetica-Bold');
      doc.text('Organisation:',  320, boxY + 10);
      doc.text('Domain:',        320, boxY + 24);
      doc.text('Rate Card:',     320, boxY + 38);
      doc.text('Total Trips:',   320, boxY + 52);

      doc.fillColor('#000').font('Helvetica');
      doc.text(invoice.organizationName, 400, boxY + 10);
      doc.text(invoice.domain,           400, boxY + 24);
      doc.text(invoice.rateCardId,       400, boxY + 38);
      doc.text(`${invoice.totalTrips} (${invoice.completedTrips} completed, ${invoice.cancelledTrips} cancelled)`, 400, boxY + 52);

      // ── Bill To ───────────────────────────────────────────────────
      let cY = boxY + 78;
      doc.fontSize(10).fillColor('#2563eb').font('Helvetica-Bold').text('BILL TO:', 40, cY);
      doc.fontSize(10).fillColor('#000').font('Helvetica-Bold').text(invoice.organizationName, 40, cY + 14);
      doc.fontSize(8).fillColor('#555').font('Helvetica').text(`Email: ${invoice.billingEmail}`, 40, cY + 28);

      // ── Line Items Table ──────────────────────────────────────────
      const tY = cY + 55;
      doc.rect(40, tY, 515, 20).fillAndStroke('#1a2744', '#1a2744');
      doc.fontSize(8).fillColor('#fff').font('Helvetica-Bold');
      doc.text('DESCRIPTION',         50, tY + 6);
      doc.text('TRIPS/UNITS',        280, tY + 6, { width: 70, align: 'right' });
      doc.text('RATE',               360, tY + 6, { width: 60, align: 'right' });
      doc.text('BASE AMT',           430, tY + 6, { width: 60, align: 'right' });
      doc.text('SURCHARGES',         495, tY + 6, { width: 55, align: 'right' });

      let yPos = tY + 20;
      invoice.lineItems.forEach((item, i) => {
        const bg = i % 2 === 0 ? '#fff' : '#f8f9fa';
        doc.rect(40, yPos, 515, 24).fillAndStroke(bg, '#e0e8f0');
        doc.fontSize(8).fillColor('#000').font('Helvetica');
        doc.text(item.description || item.vehicleType, 50, yPos + 8, { width: 220, ellipsis: true });
        doc.text(String(item.quantity || 0),           280, yPos + 8, { width: 70, align: 'right' });
        doc.text(`₹${(item.unitRate || 0).toFixed(2)}`,360, yPos + 8, { width: 60, align: 'right' });
        doc.text(`₹${(item.baseAmount || 0).toFixed(2)}`, 430, yPos + 8, { width: 60, align: 'right' });
        doc.text(`₹${((item.surchargeBreakdown?.totalSurcharges) || 0).toFixed(2)}`, 495, yPos + 8, { width: 55, align: 'right' });
        yPos += 24;
      });

      // Minimum guarantee line if applied
      if (invoice.minimumGuaranteeApplied) {
        doc.rect(40, yPos, 515, 22).fillAndStroke('#fff9c4', '#f0c040');
        doc.fontSize(8).fillColor('#7a4f00').font('Helvetica-Bold')
          .text(`Minimum Guarantee Applied: ${invoice.minimumGuaranteeDetails}`, 50, yPos + 7);
        doc.fillColor('#7a4f00').text(`₹${invoice.minimumGuaranteeAmount.toFixed(2)}`, 495, yPos + 7, { width: 55, align: 'right' });
        yPos += 22;
      }

      // SLA penalty if any
      if (invoice.slaPenaltyAmount > 0) {
        doc.rect(40, yPos, 515, 22).fillAndStroke('#fff0f0', '#f0a0a0');
        doc.fontSize(8).fillColor('#800000').font('Helvetica-Bold')
          .text(`SLA Penalty Deduction (${invoice.slaBreaches} breaches)`, 50, yPos + 7);
        doc.text(`-₹${invoice.slaPenaltyAmount.toFixed(2)}`, 495, yPos + 7, { width: 55, align: 'right' });
        yPos += 22;
      }

      // ── Totals ────────────────────────────────────────────────────
      const totY   = yPos + 18;
      const lX     = 370;
      const vX     = 490;
      let   currY  = totY;

      const totLine = (label, value, bold = false, color = '#1a2744') => {
        doc.fontSize(bold ? 9 : 8)
          .fillColor(color)
          .font(bold ? 'Helvetica-Bold' : 'Helvetica')
          .text(label, lX, currY);
        doc.text(value, vX, currY, { width: 65, align: 'right' });
        currY += 14;
      };

      totLine('Subtotal:', `₹ ${invoice.subtotal.toFixed(2)}`);
      if (invoice.cgst > 0) totLine(`CGST (${invoice.gstPercent / 2}%):`, `₹ ${invoice.cgst.toFixed(2)}`);
      if (invoice.sgst > 0) totLine(`SGST (${invoice.gstPercent / 2}%):`, `₹ ${invoice.sgst.toFixed(2)}`);
      if (invoice.tdsAmount > 0) totLine(`TDS (${invoice.tdsPercent}%):`, `-₹ ${invoice.tdsAmount.toFixed(2)}`);

      doc.moveTo(lX, currY + 2).lineTo(555, currY + 2).strokeColor('#1a2744').lineWidth(1).stroke();
      currY += 8;

      doc.rect(lX, currY, 185, 24).strokeColor('#1a2744').lineWidth(2).stroke();
      doc.fontSize(11).fillColor('#1a2744').font('Helvetica-Bold').text('TOTAL:', lX + 5, currY + 7);
      doc.fontSize(13).fillColor('#22c55e').font('Helvetica-Bold').text(`₹ ${invoice.totalAmount.toFixed(2)}`, vX, currY + 5, { width: 60, align: 'right' });

      // ── Footer ────────────────────────────────────────────────────
      const fY = 745;
      doc.moveTo(40, fY).lineTo(555, fY).lineWidth(1.5).strokeColor('#1a2744').stroke();
      doc.fontSize(8).fillColor('#1a2744').font('Helvetica-Bold')
        .text('Thank you for your business with ABRA Travels!', 40, fY + 8, { align: 'center', width: 515 });
      doc.fontSize(7).fillColor('#888').font('Helvetica')
        .text('ABRA Travels | info@abratravels.com | +91 88672 88076 | www.abratravels.com', 40, fY + 20, { align: 'center', width: 515 });

      doc.end();

      stream.on('finish', () => {
        resolve({ filename, filepath, relativePath: `/uploads/billing-invoices/${filename}` });
      });
      stream.on('error', reject);
    } catch (err) {
      reject(err);
    }
  });
}

// ============================================================================
// EMAIL — send billing invoice to organisation
// ============================================================================

async function sendBillingInvoiceEmail(invoice, pdfPath) {
  const logoPath = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
  ].find(p => fs.existsSync(p));

  let logoBase64 = '';
  if (logoPath) {
    const buf  = fs.readFileSync(logoPath);
    const ext  = path.extname(logoPath).toLowerCase();
    const mime = ext === '.png' ? 'image/png' : 'image/jpeg';
    logoBase64 = `data:${mime};base64,${buf.toString('base64')}`;
  }

  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Billing Invoice ${invoice.invoiceNumber}</title></head>
<body style="margin:0;padding:0;font-family:'Helvetica Neue',Arial,sans-serif;background:#f0f5fb;">
<table width="100%" cellpadding="0" cellspacing="0" style="padding:20px 0;">
<tr><td align="center">
<table width="620" cellpadding="0" cellspacing="0" style="background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 4px 24px rgba(10,22,40,0.13);">

  <!-- Header -->
  <tr><td style="background:linear-gradient(135deg,#0a1628 0%,#1a2744 45%,#1e3a8a 100%);padding:28px 36px;">
    <table width="100%" cellpadding="0" cellspacing="0"><tr>
      <td width="60%">
        ${logoBase64
          ? `<img src="${logoBase64}" alt="ABRA Travels" style="max-width:180px;height:auto;display:block;margin-bottom:8px;">`
          : `<span style="color:#fff;font-size:26px;font-weight:800;">ABRA Travels</span>`}
        <p style="color:rgba(255,255,255,0.7);font-size:11px;letter-spacing:1.2px;margin:6px 0 0;">YOUR JOURNEY, OUR COMMITMENT</p>
      </td>
      <td width="40%" style="text-align:right;vertical-align:top;">
        <h1 style="color:#fff;margin:0;font-size:24px;font-weight:800;">BILLING INVOICE</h1>
        <span style="display:inline-block;padding:5px 14px;background:rgba(255,255,255,0.15);color:#fff;border-radius:20px;font-size:11px;font-weight:700;margin-top:8px;">APPROVED</span>
      </td>
    </tr></table>
  </td></tr>

  <!-- Body -->
  <tr><td style="padding:36px;">

    <h2 style="color:#1a2744;margin:0 0 8px;">Dear ${invoice.organizationName},</h2>
    <p style="color:#555;font-size:14px;line-height:1.8;margin:0 0 20px;">
      Please find attached your billing invoice <strong>${invoice.invoiceNumber}</strong> for the period <strong>${invoice.billingPeriodLabel}</strong>.
    </p>

    <!-- Invoice Summary Card -->
    <table width="100%" cellpadding="18" cellspacing="0" style="background:#f0f5fb;border-left:4px solid #1a2744;border-radius:6px;margin:0 0 20px;">
    <tr><td>
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr>
          <td style="font-size:13px;color:#555;font-weight:600;padding-bottom:10px;">Invoice Number:</td>
          <td style="font-size:13px;color:#1a2744;font-weight:800;text-align:right;padding-bottom:10px;">${invoice.invoiceNumber}</td>
        </tr>
        <tr>
          <td style="font-size:13px;color:#555;font-weight:600;padding-bottom:10px;">Billing Period:</td>
          <td style="font-size:13px;color:#1a2744;font-weight:800;text-align:right;padding-bottom:10px;">${invoice.billingPeriodLabel}</td>
        </tr>
        <tr>
          <td style="font-size:13px;color:#555;font-weight:600;padding-bottom:10px;">Total Trips:</td>
          <td style="font-size:13px;color:#1a2744;font-weight:800;text-align:right;padding-bottom:10px;">${invoice.completedTrips} completed / ${invoice.cancelledTrips} cancelled</td>
        </tr>
        <tr>
          <td style="font-size:13px;color:#555;font-weight:600;padding-bottom:10px;">Total KM:</td>
          <td style="font-size:13px;color:#1a2744;font-weight:800;text-align:right;padding-bottom:10px;">${invoice.totalKm.toFixed(1)} km</td>
        </tr>
        <tr><td colspan="2" style="border-top:1px solid #dde5f0;padding-top:10px;"></td></tr>
        <tr>
          <td style="font-size:16px;color:#555;font-weight:600;">Total Amount:</td>
          <td style="font-size:22px;color:#22c55e;font-weight:800;text-align:right;">₹${invoice.totalAmount.toFixed(2)}</td>
        </tr>
      </table>
    </td></tr></table>

    <!-- Tax Breakdown -->
    <table width="100%" cellpadding="15" cellspacing="0" style="background:#fff;border:1px solid #dde5f0;border-radius:8px;margin:0 0 20px;">
    <tr><td>
      <p style="margin:0 0 12px;font-size:13px;font-weight:700;color:#1a2744;">Tax Breakdown:</p>
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr>
          <td style="font-size:13px;color:#666;padding-bottom:8px;">Subtotal (before tax):</td>
          <td style="font-size:13px;color:#1a2744;font-weight:700;text-align:right;padding-bottom:8px;">₹${invoice.subtotal.toFixed(2)}</td>
        </tr>
        <tr>
          <td style="font-size:13px;color:#666;padding-bottom:8px;">CGST (${invoice.gstPercent / 2}%):</td>
          <td style="font-size:13px;color:#1a2744;font-weight:700;text-align:right;padding-bottom:8px;">₹${invoice.cgst.toFixed(2)}</td>
        </tr>
        <tr>
          <td style="font-size:13px;color:#666;padding-bottom:8px;">SGST (${invoice.gstPercent / 2}%):</td>
          <td style="font-size:13px;color:#1a2744;font-weight:700;text-align:right;padding-bottom:8px;">₹${invoice.sgst.toFixed(2)}</td>
        </tr>
        <tr>
          <td style="font-size:13px;color:#666;">TDS (${invoice.tdsPercent}%) Deduction:</td>
          <td style="font-size:13px;color:#e74c3c;font-weight:700;text-align:right;">-₹${invoice.tdsAmount.toFixed(2)}</td>
        </tr>
      </table>
    </td></tr></table>

    <p style="font-size:13px;color:#555;line-height:1.8;">
      📎 The detailed invoice PDF is attached to this email. Please review and process payment as per your payment terms.
    </p>

    <p style="font-size:14px;color:#2563eb;font-weight:700;text-align:center;margin:24px 0 0;">
      Thank you for your continued partnership with ABRA Travels 🙏
    </p>
  </td></tr>

  <!-- Footer -->
  <tr><td style="background:#1a2744;color:#fff;padding:24px 36px;text-align:center;">
    <p style="margin:0;font-weight:800;font-size:15px;">ABRA Travels</p>
    <p style="margin:6px 0;font-style:italic;color:rgba(255,255,255,0.6);font-size:11px;letter-spacing:1px;">YOUR JOURNEY, OUR COMMITMENT</p>
    <p style="margin:10px 0 0;color:rgba(255,255,255,0.5);font-size:11px;">📍 Bangalore | ✉️ info@abratravels.com | 📞 +91 88672 88076 | 🔖 GST: 29AABCT1332L1ZM</p>
    <p style="margin:12px 0 0;color:rgba(255,255,255,0.3);font-size:10px;">© ${new Date().getFullYear()} ABRA Travels. All rights reserved.</p>
  </td></tr>

</table>
</td></tr>
</table>
</body>
</html>`;

  await emailTransporter.sendMail({
    from:        `"ABRA Travels - Billing" <${process.env.SMTP_USER}>`,
    to:          invoice.billingEmail,
    subject:     `📄 Billing Invoice ${invoice.invoiceNumber} — ${invoice.billingPeriodLabel} — ₹${invoice.totalAmount.toFixed(2)}`,
    html,
    attachments: [{ filename: `BillingInvoice-${invoice.invoiceNumber}.pdf`, path: pdfPath }],
  });

  console.log(`✅ Billing invoice email sent to ${invoice.billingEmail}`);
}

// ============================================================================
// API ROUTES
// ============================================================================

// ── GET /api/billing/trips/:domain — fetch all trips for a domain ─────────
// Returns completed + cancelled trips with billing status
// ============================================================================
// PATCH — replace the existing router.get('/trips/:domain', ...) block
// in rate_card_billing.js with this version.
//
// WHAT CHANGED:
//   OLD: queries TripBilling (Mongoose) — always empty because calculate-trip
//        was never called when trips completed.
//
//   NEW: queries roster-assigned-trips (native req.db) directly, filtering by
//        domain via stop customer emails, then falls back to TripBilling for
//        any already-calculated records. Merges both so the UI always shows
//        real trips regardless of whether billing has been calculated yet.
//
//        Also pulls from the 'trips' collection for manually-created trips
//        whose customerEmail matches the domain.
//
// HOW TO USE:
//   1. Open rate_card_billing.js
//   2. Find the block:
//        router.get('/trips/:domain', async (req, res) => {
//   3. Replace that entire route (up to and including its closing });)
//      with the code below.
// ============================================================================



// ============================================================================
// FILE: rate_card_billing.js
// STEP 1: Copy everything below and use it as your FIND text
// ============================================================================

router.get('/trips/:domain', async (req, res) => {
  try {
    const rawDomain = req.params.domain || '';
    const domain = rawDomain.replace(/^@/, '').toLowerCase().trim();
    const { month, year, dateFrom, dateTo, status } = req.query;

    if (!domain) {
      return res.status(400).json({ success: false, error: 'domain is required' });
    }

    let scheduledDateFrom = null;
    let scheduledDateTo   = null;
    let dateStart         = null;
    let dateEnd           = null;

    if (dateFrom && dateTo) {
      scheduledDateFrom = dateFrom;
      scheduledDateTo   = dateTo;
      dateStart = new Date(dateFrom + 'T00:00:00.000Z');
      dateEnd   = new Date(dateTo   + 'T23:59:59.999Z');
    } else if (month && year) {
      const y = parseInt(year), m = parseInt(month);
      const mm = String(m).padStart(2, '0');
      const lastDay = new Date(y, m, 0).getDate();
      scheduledDateFrom = `${y}-${mm}-01`;
      scheduledDateTo   = `${y}-${mm}-${String(lastDay).padStart(2, '0')}`;
      dateStart = new Date(y, m - 1, 1);
      dateEnd   = new Date(y, m, 0, 23, 59, 59, 999);
    }

    const billingFilter = { domain };
    if (dateStart && dateEnd) billingFilter.tripDate = { $gte: dateStart, $lte: dateEnd };
    const billingRecords = await TripBilling.find(billingFilter).sort({ tripDate: -1 }).lean();
    const billingByTripId = {};
    billingRecords.forEach(r => { billingByTripId[r.tripId] = r; });

    const allowedStatuses = ['completed', 'started', 'in_progress', 'assigned', 'cancelled'];
    const rosterFilter = {
      'stops.customer.email': {
        $regex: `@${domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`,
        $options: 'i',
      },
      status: (status && allowedStatuses.includes(status.toLowerCase()))
        ? status.toLowerCase()
        : { $in: allowedStatuses },
    };
    if (scheduledDateFrom && scheduledDateTo) {
      rosterFilter.scheduledDate = { $gte: scheduledDateFrom, $lte: scheduledDateTo };
    }

    const rosterTrips = await req.db
      .collection('roster-assigned-trips')
      .find(rosterFilter)
      .sort({ scheduledDate: -1 })
      .limit(1000)
      .toArray();

    const manualFilter = {
      $or: [
        { customerEmail:    { $regex: `@${domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, $options: 'i' } },
        { 'customer.email': { $regex: `@${domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, $options: 'i' } },
      ],
      status: (status && allowedStatuses.includes(status.toLowerCase()))
        ? status.toLowerCase()
        : { $in: allowedStatuses },
    };
    if (dateStart && dateEnd) manualFilter.createdAt = { $gte: dateStart, $lte: dateEnd };

    const manualTrips = await req.db
      .collection('trips')
      .find(manualFilter)
      .sort({ createdAt: -1 })
      .limit(500)
      .toArray();

    let rateCard = null;
    try { rateCard = await getActiveRateCard(domain); } catch (_) {}

    const buildTripRow = (rawTrip, collection) => {
      const tripId   = rawTrip._id.toString();
      const existing = billingByTripId[tripId];
      const actualKm = rawTrip.actualDistance || rawTrip.totalDistance || rawTrip.distance || 0;
      const tripDate = rawTrip.actualEndTime || rawTrip.actualStartTime || rawTrip.createdAt || new Date();

      const row = {
        _id: tripId, tripId, tripCollection: collection,
        tripNumber:    rawTrip.tripNumber  || rawTrip.tripGroupId || tripId,
        tripDate:      new Date(tripDate),
        scheduledDate: rawTrip.scheduledDate || '',
        vehicleNumber: rawTrip.vehicleNumber || '',
        driverName:    rawTrip.driverName    || '',
        vehicleType:   rawTrip.vehicleType   || 'SEDAN',
        tripType:      rawTrip.tripType      || '',
        actualKm:      round2(actualKm),
        status:        rawTrip.status        || '',
        billingStatus: existing ? existing.status : 'NOT_CALCULATED',
        customerCount: collection === 'roster-assigned-trips'
          ? (rawTrip.stops || []).filter(s => s.type === 'pickup').length : 1,
        baseAmount:        existing ? existing.baseAmount        : 0,
        nightSurcharge:    existing ? existing.nightSurcharge    : 0,
        weekendSurcharge:  existing ? existing.weekendSurcharge  : 0,
        festivalSurcharge: existing ? existing.festivalSurcharge : 0,
        waitingSurcharge:  existing ? existing.waitingSurcharge  : 0,
        tollSurcharge:     existing ? existing.tollSurcharge     : 0,
        escortSurcharge:   existing ? existing.escortSurcharge   : 0,
        totalSurcharges:   existing ? existing.totalSurcharges   : 0,
        subtotalBeforeTax: existing ? existing.subtotalBeforeTax : 0,
        billedKm:          existing ? existing.billedKm          : round2(actualKm),
        billingModel:      existing ? existing.billingModel      : '',
        isNightTrip:       existing ? existing.isNightTrip       : false,
        isWeekend:         existing ? existing.isWeekend         : false,
        rateCardId:        existing ? existing.rateCardId        : '',
        billingPeriod:     existing ? existing.billingPeriod     : '',
        invoiceId:         existing ? existing.invoiceId         : null,
        calculatedAt:      existing ? existing.calculatedAt      : null,
      };

      if (!existing && rateCard && rawTrip.status === 'completed' && actualKm > 0) {
        try {
          const calc = calculateTripAmount({
            vehicleType: row.vehicleType, actualKm, distance: actualKm,
            tripDate, waitingMinutes: rawTrip.waitingMinutes || 0,
            tollAmount: rawTrip.tollAmount || 0,
            escortRequired: rawTrip.escortRequired || false,
            isWomenOnly: rawTrip.isWomenOnly || false,
          }, rateCard);
          if (!calc.error) {
            row.baseAmount = calc.baseAmount; row.totalSurcharges = calc.totalSurcharges;
            row.subtotalBeforeTax = calc.subtotalBeforeTax; row.billedKm = calc.billedKm;
            row.billingModel = calc.billingModel; row.nightSurcharge = calc.nightSurcharge;
            row.weekendSurcharge = calc.weekendSurcharge; row.festivalSurcharge = calc.festivalSurcharge;
            row.waitingSurcharge = calc.waitingSurcharge; row.tollSurcharge = calc.tollSurcharge;
            row.escortSurcharge = calc.escortSurcharge; row.isNightTrip = calc.isNightTrip;
            row.isWeekend = calc.isWeekend; row.rateCardId = calc.rateCardId;
            row.billingStatus = 'ON_THE_FLY';
          }
        } catch (_) {}
      }
      return row;
    };

    const tripRows = [
      ...rosterTrips.map(t => buildTripRow(t, 'roster-assigned-trips')),
      ...manualTrips.map(t => buildTripRow(t, 'trips')),
    ];

    const seen = new Set();
    const deduped = tripRows.filter(r => {
      if (seen.has(r.tripId)) return false;
      seen.add(r.tripId); return true;
    });

    deduped.sort((a, b) => {
      const sa = a.scheduledDate || '', sb = b.scheduledDate || '';
      if (sa && sb && sa !== sb) return sb.localeCompare(sa);
      return new Date(b.tripDate) - new Date(a.tripDate);
    });

    const stats = {
      totalTrips:        deduped.length,
      completedTrips:    deduped.filter(t => t.status === 'completed').length,
      totalBaseAmount:   round2(deduped.reduce((s, t) => s + t.baseAmount,        0)),
      totalSurcharges:   round2(deduped.reduce((s, t) => s + t.totalSurcharges,   0)),
      totalBilledAmount: round2(deduped.reduce((s, t) => s + t.subtotalBeforeTax, 0)),
      totalKm:           round2(deduped.reduce((s, t) => s + t.actualKm,          0)),
      rateCardActive:    !!rateCard,
      domain,
    };

    res.json({ success: true, data: deduped, stats });

  } catch (err) {
    console.error('❌ billing/trips/:domain error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/billing/calculate-trip — calculate billing for one trip ────
router.post('/calculate-trip', async (req, res) => {
  try {
    const { tripId, tripCollection, domain, tripData } = req.body;

    if (!domain) return res.status(400).json({ success: false, error: 'domain is required' });

    const rateCard = await getActiveRateCard(domain);
    if (!rateCard) {
      return res.status(404).json({
        success: false,
        error: `No active rate card for domain "${domain}"`,
      });
    }

    const calc = calculateTripAmount(tripData, rateCard);
    if (calc.error) {
      return res.status(422).json({ success: false, error: calc.error });
    }

    const period = `${new Date(tripData.tripDate || Date.now()).getFullYear()}-${
      String(new Date(tripData.tripDate || Date.now()).getMonth() + 1).padStart(2, '0')
    }`;

    // Upsert billing record for this trip
    const billing = await TripBilling.findOneAndUpdate(
      { tripId, tripCollection },
      {
        tripId,
        tripCollection,
        domain: domain.toLowerCase(),
        rateCardId: rateCard.rateCardId,
        rateCardMongoId: rateCard._id,
        tripDate: new Date(tripData.tripDate || Date.now()),
        vehicleType: calc.vehicleType,
        vehicleNumber: tripData.vehicleNumber || '',
        driverName: tripData.driverName || '',
        actualKm: calc.actualKm,
        billedKm: calc.billedKm,
        waitingMinutes: tripData.waitingMinutes || 0,
        isNightTrip: calc.isNightTrip,
        isWeekend: calc.isWeekend,
        isFestival: calc.isFestival,
        isEscortTrip: calc.isEscortTrip,
        tollAmount: tripData.tollAmount || 0,
        pickupZone: tripData.pickupZone || '',
        dropZone: tripData.dropZone || '',
        routeName: tripData.routeName || '',
        shiftTime: tripData.shiftTime || '',
        billingModel: calc.billingModel,
        baseAmount: calc.baseAmount,
        nightSurcharge: calc.nightSurcharge,
        weekendSurcharge: calc.weekendSurcharge,
        festivalSurcharge: calc.festivalSurcharge,
        waitingSurcharge: calc.waitingSurcharge,
        tollSurcharge: calc.tollSurcharge,
        escortSurcharge: calc.escortSurcharge,
        totalSurcharges: calc.totalSurcharges,
        subtotalBeforeTax: calc.subtotalBeforeTax,
        status: 'CALCULATED',
        billingPeriod: period,
        calculatedAt: new Date(),
      },
      { upsert: true, new: true }
    );

    res.json({ success: true, data: billing, calculation: calc });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/billing/generate-invoice — generate month-end invoice ───────
router.post('/generate-invoice', async (req, res) => {
  try {
    const { domain, month, year } = req.body;
    // month: 1-12, year: e.g. 2025

    if (!domain || !month || !year) {
      return res.status(400).json({ success: false, error: 'domain, month, year are required' });
    }

    const rateCard = await getActiveRateCard(domain);
    if (!rateCard) {
      return res.status(404).json({ success: false, error: `No active rate card for domain "${domain}"` });
    }

    const periodStart = new Date(parseInt(year), parseInt(month) - 1, 1);
    const periodEnd   = new Date(parseInt(year), parseInt(month), 0, 23, 59, 59);
    const periodLabel = periodStart.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
    const periodKey   = `${year}-${String(month).padStart(2, '0')}`;

    // Check if invoice already exists for this period
    const existing = await BillingInvoice.findOne({
      domain: domain.toLowerCase(),
      billingPeriod: periodKey,
      status: { $nin: ['DRAFT'] },
    });
    if (existing) {
      return res.status(409).json({
        success: false,
        error: `Invoice already exists for ${domain} — ${periodLabel}`,
        existingInvoiceId: existing._id,
        existingInvoiceNumber: existing.invoiceNumber,
      });
    }

    // Fetch all calculated billing records for this domain + period
    const billingRecords = await TripBilling.find({
      domain: domain.toLowerCase(),
      billingPeriod: periodKey,
      status: 'CALCULATED',
    });

    if (billingRecords.length === 0) {
      return res.status(404).json({
        success: false,
        error: `No calculated trip billing records found for ${domain} in ${periodLabel}`,
      });
    }

    // ── Group by vehicle type ────────────────────────────────────────
    const vehicleGroups = {};
    billingRecords.forEach(r => {
      const key = `${r.vehicleType}__${r.billingModel}`;
      if (!vehicleGroups[key]) {
        vehicleGroups[key] = {
          vehicleType:  r.vehicleType,
          billingModel: r.billingModel,
          trips:        [],
          totalKm:      0,
          baseAmount:   0,
          surcharges:   { night: 0, weekend: 0, festival: 0, waiting: 0, toll: 0, escort: 0, total: 0 },
        };
      }
      vehicleGroups[key].trips.push(r);
      vehicleGroups[key].totalKm    += r.actualKm;
      vehicleGroups[key].baseAmount += r.baseAmount;
      vehicleGroups[key].surcharges.night    += r.nightSurcharge;
      vehicleGroups[key].surcharges.weekend  += r.weekendSurcharge;
      vehicleGroups[key].surcharges.festival += r.festivalSurcharge;
      vehicleGroups[key].surcharges.waiting  += r.waitingSurcharge;
      vehicleGroups[key].surcharges.toll     += r.tollSurcharge;
      vehicleGroups[key].surcharges.escort   += r.escortSurcharge;
      vehicleGroups[key].surcharges.total    += r.totalSurcharges;
    });

    // ── Build line items ─────────────────────────────────────────────
    const lineItems = [];
    let   subtotal  = 0;

    for (const [, grp] of Object.entries(vehicleGroups)) {
      const tripCount = grp.trips.length;

      if (grp.billingModel === 'PER_KM') {
        const rateRow = rateCard.vehicleRates.find(r => r.vehicleType === grp.vehicleType);
        const unitRate  = rateRow?.ratePerKm || 0;
        const totalBilledKm = grp.trips.reduce((s, t) => s + t.billedKm, 0);
        const lineTotal = round2(grp.baseAmount + grp.surcharges.total);

        lineItems.push({
          description: `${grp.vehicleType} — Per KM (${tripCount} trips, ${round2(totalBilledKm)} billed km)`,
          vehicleType: grp.vehicleType,
          billingModel: grp.billingModel,
          quantity: round2(totalBilledKm),
          unitDescription: 'km',
          unitRate,
          baseAmount: round2(grp.baseAmount),
          surchargeBreakdown: {
            nightSurcharge:    round2(grp.surcharges.night),
            weekendSurcharge:  round2(grp.surcharges.weekend),
            festivalSurcharge: round2(grp.surcharges.festival),
            waitingSurcharge:  round2(grp.surcharges.waiting),
            tollSurcharge:     round2(grp.surcharges.toll),
            escortSurcharge:   round2(grp.surcharges.escort),
            totalSurcharges:   round2(grp.surcharges.total),
          },
          lineTotal,
        });
        subtotal += lineTotal;

      } else if (grp.billingModel === 'PER_TRIP_FIXED') {
        const rateRow  = rateCard.vehicleRates.find(r => r.vehicleType === grp.vehicleType);
        const unitRate = rateRow?.ratePerTrip || 0;

        // Minimum trip guarantee check
        let effectiveTripCount = tripCount;
        let minGuaranteeApplied = false;
        let minGuaranteeAmount  = 0;
        let minGuaranteeDetails = '';

        if (rateRow?.minimumTripsPerMonth && tripCount < rateRow.minimumTripsPerMonth) {
          effectiveTripCount = rateRow.minimumTripsPerMonth;
          minGuaranteeApplied = true;
          minGuaranteeAmount  = round2((rateRow.minimumTripsPerMonth - tripCount) * unitRate);
          minGuaranteeDetails = `${grp.vehicleType}: ${tripCount} actual trips vs ${rateRow.minimumTripsPerMonth} guaranteed — billing difference of ₹${minGuaranteeAmount}`;
        }

        const baseAmountWithGuarantee = round2(effectiveTripCount * unitRate);
        const lineTotal = round2(baseAmountWithGuarantee + grp.surcharges.total);

        lineItems.push({
          description: `${grp.vehicleType} — Per Trip Fixed (${tripCount} trips${minGuaranteeApplied ? `, ${rateRow.minimumTripsPerMonth} min guaranteed` : ''})`,
          vehicleType: grp.vehicleType,
          billingModel: grp.billingModel,
          quantity: effectiveTripCount,
          unitDescription: 'trips',
          unitRate,
          baseAmount: baseAmountWithGuarantee,
          surchargeBreakdown: {
            nightSurcharge:    round2(grp.surcharges.night),
            weekendSurcharge:  round2(grp.surcharges.weekend),
            festivalSurcharge: round2(grp.surcharges.festival),
            waitingSurcharge:  round2(grp.surcharges.waiting),
            tollSurcharge:     round2(grp.surcharges.toll),
            escortSurcharge:   round2(grp.surcharges.escort),
            totalSurcharges:   round2(grp.surcharges.total),
          },
          lineTotal,
        });
        subtotal += lineTotal;

      } else if (grp.billingModel === 'DEDICATED_MONTHLY') {
        const rateRow   = rateCard.vehicleRates.find(r => r.vehicleType === grp.vehicleType);
        const monthly   = rateRow?.monthlyRate || 0;
        const lineTotal = round2(monthly + grp.surcharges.total);

        lineItems.push({
          description: `${grp.vehicleType} — Dedicated Monthly (${tripCount} trips, flat monthly)`,
          vehicleType: grp.vehicleType,
          billingModel: grp.billingModel,
          quantity: 1,
          unitDescription: 'month',
          unitRate: monthly,
          baseAmount: monthly,
          surchargeBreakdown: {
            nightSurcharge:    round2(grp.surcharges.night),
            weekendSurcharge:  round2(grp.surcharges.weekend),
            festivalSurcharge: round2(grp.surcharges.festival),
            waitingSurcharge:  round2(grp.surcharges.waiting),
            tollSurcharge:     round2(grp.surcharges.toll),
            escortSurcharge:   round2(grp.surcharges.escort),
            totalSurcharges:   round2(grp.surcharges.total),
          },
          lineTotal,
        });
        subtotal += lineTotal;

      } else if (grp.billingModel === 'HYBRID') {
        const rateRow      = rateCard.vehicleRates.find(r => r.vehicleType === grp.vehicleType);
        const monthlyBase  = rateRow?.hybridMonthlyBase || 0;
        const includedKm   = rateRow?.hybridIncludedKm  || 0;
        const excessRate   = rateRow?.hybridExcessRatePerKm || 0;
        const totalActualKm = round2(grp.totalKm);
        const excessKm     = Math.max(0, totalActualKm - includedKm);
        const excessAmount = round2(excessKm * excessRate);
        const baseAmount   = round2(monthlyBase + excessAmount);
        const lineTotal    = round2(baseAmount + grp.surcharges.total);

        lineItems.push({
          description: `${grp.vehicleType} — Hybrid (${round2(monthlyBase)} base + ${round2(excessKm)} excess km × ₹${excessRate})`,
          vehicleType: grp.vehicleType,
          billingModel: grp.billingModel,
          quantity: totalActualKm,
          unitDescription: 'km total',
          unitRate: excessRate,
          baseAmount,
          surchargeBreakdown: {
            nightSurcharge:    round2(grp.surcharges.night),
            weekendSurcharge:  round2(grp.surcharges.weekend),
            festivalSurcharge: round2(grp.surcharges.festival),
            waitingSurcharge:  round2(grp.surcharges.waiting),
            tollSurcharge:     round2(grp.surcharges.toll),
            escortSurcharge:   round2(grp.surcharges.escort),
            totalSurcharges:   round2(grp.surcharges.total),
          },
          lineTotal,
        });
        subtotal += lineTotal;
      }
    }

    subtotal = round2(subtotal);

    // ── GST & TDS calculations ───────────────────────────────────────
    const gstPct    = rateCard.gstPercent || 5;
    const tdsPct    = rateCard.tdsPercent || 1;
    const gstAmount = round2((subtotal * gstPct) / 100);
    const cgst      = round2(gstAmount / 2);
    const sgst      = round2(gstAmount / 2);
    const tdsAmount = round2((subtotal * tdsPct) / 100);
    const total     = round2(subtotal + gstAmount - tdsAmount);

    // ── Totals across all records ────────────────────────────────────
    const totalKm         = round2(billingRecords.reduce((s, r) => s + r.actualKm, 0));
    const completedTrips  = billingRecords.filter(r => r.baseAmount > 0).length;
    const cancelledTrips  = billingRecords.filter(r => r.baseAmount === 0 && r.billingModel !== 'DEDICATED_MONTHLY').length;

    // ── Create billing invoice ───────────────────────────────────────
    const invoiceNumber = await generateBillingInvoiceNumber(domain);

    const billingInvoice = new BillingInvoice({
      invoiceNumber,
      domain:           domain.toLowerCase(),
      rateCardId:       rateCard.rateCardId,
      organizationName: rateCard.organizationName,
      billingEmail:     rateCard.billingEmail,
      billingPeriodStart: periodStart,
      billingPeriodEnd:   periodEnd,
      billingPeriodLabel: periodLabel,
      billingPeriod:      periodKey,
      lineItems,
      subtotal,
      gstPercent: gstPct,
      gstAmount,
      cgst,
      sgst,
      tdsPercent: tdsPct,
      tdsAmount,
      totalAmount: total,
      totalTrips: billingRecords.length,
      completedTrips,
      cancelledTrips,
      totalKm,
      status: 'PENDING_FINANCE_APPROVAL',
      createdBy: req.user?.email || 'system',
    });

    await billingInvoice.save();

    // Mark billing records as invoiced
    await TripBilling.updateMany(
      { domain: domain.toLowerCase(), billingPeriod: periodKey, status: 'CALCULATED' },
      { $set: { status: 'INVOICED', invoiceId: billingInvoice._id } }
    );

    res.status(201).json({
      success: true,
      message: `Invoice ${invoiceNumber} generated — pending Finance approval`,
      data: billingInvoice,
    });
  } catch (err) {
    console.error('❌ Invoice generation error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── GET /api/billing/invoices — list all billing invoices ─────────────────
router.get('/invoices', async (req, res) => {
  try {
    const { status, domain, page = 1, limit = 20 } = req.query;
    const query = {};
    if (status) query.status = status;
    if (domain) query.domain = domain.toLowerCase();

    const skip     = (parseInt(page) - 1) * parseInt(limit);
    const invoices = await BillingInvoice.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .select('-lineItems -__v');
    const total = await BillingInvoice.countDocuments(query);

    res.json({
      success: true,
      data: invoices,
      pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── GET /api/billing/invoices/:id — invoice detail with all line items ────
router.get('/invoices/:id', async (req, res) => {
  try {
    const invoice = await BillingInvoice.findById(req.params.id);
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });
    res.json({ success: true, data: invoice });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/billing/invoices/:id/approve — Finance team approves ────────
router.post('/invoices/:id/approve', async (req, res) => {
  try {
    const invoice = await BillingInvoice.findById(req.params.id);
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });

    if (invoice.status !== 'PENDING_FINANCE_APPROVAL') {
      return res.status(400).json({
        success: false,
        error: `Invoice is in status "${invoice.status}" — only PENDING_FINANCE_APPROVAL invoices can be approved`,
      });
    }

    invoice.status           = 'APPROVED';
    invoice.financeApprovedBy = req.user?.email || req.body.approvedBy || 'finance_team';
    invoice.financeApprovedAt = new Date();
    invoice.financeNotes     = req.body.notes || '';
    invoice.updatedBy        = req.user?.email || 'finance_team';
    await invoice.save();

    // Auto-generate PDF immediately on approval
    try {
      const pdfInfo = await generateBillingInvoicePDF(invoice);
      invoice.pdfPath         = pdfInfo.filepath;
      invoice.pdfGeneratedAt  = new Date();
      await invoice.save();
    } catch (pdfErr) {
      console.error('⚠️ PDF generation failed after approval:', pdfErr.message);
    }

    res.json({
      success: true,
      message: `Invoice ${invoice.invoiceNumber} approved by ${invoice.financeApprovedBy}`,
      data: invoice,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/billing/invoices/:id/send — send approved invoice to org ────
router.post('/invoices/:id/send', async (req, res) => {
  try {
    const invoice = await BillingInvoice.findById(req.params.id);
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });

    if (invoice.status !== 'APPROVED') {
      return res.status(400).json({
        success: false,
        error: `Invoice must be APPROVED before sending. Current status: "${invoice.status}"`,
      });
    }

    // Generate PDF if not already done
    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      const pdfInfo = await generateBillingInvoicePDF(invoice);
      invoice.pdfPath        = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
    }

    // Send email
    await sendBillingInvoiceEmail(invoice, invoice.pdfPath);

    invoice.status         = 'SENT';
    invoice.sentToOrgAt    = new Date();
    invoice.sentToOrgEmail = invoice.billingEmail;
    invoice.updatedBy      = req.user?.email || 'system';
    await invoice.save();

    res.json({
      success: true,
      message: `Invoice ${invoice.invoiceNumber} sent to ${invoice.billingEmail}`,
      data: invoice,
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── POST /api/billing/invoices/:id/reject — Finance rejects invoice ───────
router.post('/invoices/:id/reject', async (req, res) => {
  try {
    const invoice = await BillingInvoice.findById(req.params.id);
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });

    invoice.status     = 'DRAFT';
    invoice.financeNotes = req.body.reason || 'Rejected by finance team';
    invoice.updatedBy  = req.user?.email || 'finance_team';
    await invoice.save();

    res.json({ success: true, message: 'Invoice rejected and returned to DRAFT', data: invoice });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── GET /api/billing/invoices/:id/pdf — download PDF ─────────────────────
router.get('/invoices/:id/pdf', async (req, res) => {
  try {
    const invoice = await BillingInvoice.findById(req.params.id);
    if (!invoice) return res.status(404).json({ success: false, error: 'Invoice not found' });

    if (!invoice.pdfPath || !fs.existsSync(invoice.pdfPath)) {
      const pdfInfo = await generateBillingInvoicePDF(invoice);
      invoice.pdfPath        = pdfInfo.filepath;
      invoice.pdfGeneratedAt = new Date();
      await invoice.save();
    }

    res.download(invoice.pdfPath, `BillingInvoice-${invoice.invoiceNumber}.pdf`);
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── Export the calculateTripAmount function for use in trip routers ────────
module.exports = router;
module.exports.calculateTripAmount = calculateTripAmount;
module.exports.TripBilling         = TripBilling;
module.exports.BillingInvoice      = BillingInvoice;