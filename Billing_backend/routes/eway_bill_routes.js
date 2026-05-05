// ============================================================================
// E-WAY BILL ROUTES — COMPLETE (with PDF Print + Pending Count)
// ============================================================================
// File: backend/routes/eway_bill_routes.js
// NEW ROUTES ADDED:
//   GET /pending-count  — count invoices needing EWB (smart banner)
//   GET /:id/print      — generate & download EWB PDF
// ============================================================================

const express   = require('express');
const router    = express.Router();
const mongoose  = require('mongoose');
const PDFDocument = require('pdfkit');
const fs        = require('fs');
const path      = require('path');

const { EWayBill, EWBCredentials } = require('../models/EWayBill');
const EWBNICService = require('../services/eway_bill_nic_service');

// ── org filter helper ──────────────────────────────────────────────────────────
const orgFilter = (req) => (req.user?.orgId ? { orgId: req.user.orgId } : {});

// ── get + auto-refresh credentials ────────────────────────────────────────────
async function getCredentials(orgId) {
  const creds = await EWBCredentials.findOne({ orgId }).lean();
  if (!creds || !creds.isConnected) return null;

  // Token still valid
  if (creds.authToken && creds.authTokenExpiresAt > new Date()) {
    return creds;
  }

  // Token expired — re-authenticate silently
  if (!creds.passwordEncrypted) return creds;
  try {
    const password = EWBNICService.decryptPassword(creds.passwordEncrypted);
    const result   = await EWBNICService.validateCredentials(creds.gstin, creds.username, password);
    if (result.success) {
      await EWBCredentials.findOneAndUpdate(
        { orgId },
        {
          authToken:          result.authToken,
          sek:                result.sek,
          authTokenExpiresAt: result.tokenExpiresAt,
          lastValidatedAt:    new Date(),
        }
      );
      return { ...creds, authToken: result.authToken, sek: result.sek };
    }
  } catch (e) {
    console.warn('⚠️ Token refresh failed:', e.message);
  }
  return creds;
}

// ── auto-update expired EWBs ───────────────────────────────────────────────────
async function updateExpiredEWBs(orgId) {
  try {
    await EWayBill.updateMany(
      { orgId, ewbStatus: { $in: ['GENERATED', 'EXTENDED'] }, validUntil: { $lt: new Date() } },
      { $set: { ewbStatus: 'EXPIRED' } }
    );
  } catch (e) {
    console.warn('⚠️ Auto-expire update failed:', e.message);
  }
}

// =============================================================================
// ROUTE 1 — POST /setup/connect
// =============================================================================
router.post('/setup/connect', async (req, res) => {
  try {
    const { gstin, username, password } = req.body;
    const orgId = req.user?.orgId;

    if (!gstin || !username || !password) {
      return res.status(400).json({ success: false, message: 'GSTIN, username and password are required' });
    }

    const gstinClean = gstin.trim().toUpperCase();
    if (gstinClean.length !== 15) {
      return res.status(400).json({ success: false, message: 'GSTIN must be exactly 15 characters' });
    }

    // ── Validate with NIC (real or mock) ────────────────────────────────────
    const result = await EWBNICService.validateCredentials(gstinClean, username.trim(), password);
    if (!result.success) {
      return res.status(401).json({ success: false, message: result.message });
    }

    // ── Save encrypted credentials ───────────────────────────────────────────
    const passwordEncrypted = EWBNICService.encryptPassword(password);
    await EWBCredentials.findOneAndUpdate(
      { orgId },
      {
        orgId,
        gstin:              gstinClean,
        username:           username.trim(),
        passwordEncrypted,
        isConnected:        true,
        connectedAt:        new Date(),
        lastValidatedAt:    new Date(),
        authToken:          result.authToken,
        sek:                result.sek || '',
        authTokenExpiresAt: result.tokenExpiresAt,
      },
      { upsert: true, new: true }
    );

    console.log(`✅ EWB connected for org: ${orgId}, GSTIN: ${gstinClean}`);
    res.json({
      success: true,
      message: result.message,
      data:    { gstin: gstinClean, username: username.trim(), connectedAt: new Date() },
    });
  } catch (err) {
    console.error('EWB connect error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 2 — GET /setup/status
// =============================================================================
router.get('/setup/status', async (req, res) => {
  try {
    const creds = await EWBCredentials.findOne({ orgId: req.user?.orgId, ...(req.branchFilter || {}) })
      .select('gstin username isConnected connectedAt lastValidatedAt').lean();
    res.json({
      success: true,
      data: {
        isConnected:     creds?.isConnected     || false,
        gstin:           creds?.gstin           || null,
        username:        creds?.username        || null,
        connectedAt:     creds?.connectedAt     || null,
        lastValidatedAt: creds?.lastValidatedAt || null,
        mockMode:        process.env.EWB_MOCK_MODE !== 'false',
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 3 — DELETE /setup/disconnect
// =============================================================================
router.delete('/setup/disconnect', async (req, res) => {
  try {
    await EWBCredentials.findOneAndUpdate(
      { orgId: req.user?.orgId, ...(req.branchFilter || {}) },
      { isConnected: false, authToken: null, sek: null }
    );
    res.json({ success: true, message: 'Disconnected from EWB portal' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 4 — GET /pending-count — Smart notification: invoices needing EWB
// Must be before /:id
// =============================================================================
router.get('/pending-count', async (req, res) => {
  try {
    const orgId = req.user?.orgId;

    // Get all active EWB sourceIds for this org
    const activeEWBs = await EWayBill.find(
      { orgId, sourceType: 'INVOICE', ewbStatus: { $in: ['GENERATED', 'PART_A', 'EXTENDED'] } },
      { sourceId: 1 }
    ).lean();
    const activeSourceIds = activeEWBs.map(e => e.sourceId?.toString()).filter(Boolean);

    // Count invoices with totalAmount > 50000 and no active EWB
    const Invoice = mongoose.models.Invoice;
    let pendingCount = 0;
    if (Invoice) {
      const invoicesNeedingEWB = await Invoice.find({
        orgId,
        totalAmount: { $gt: 50000 },
        status: { $in: ['UNPAID', 'PARTIALLY_PAID', 'SENT', 'OVERDUE'] },
      }, { _id: 1 }).lean();

      pendingCount = invoicesNeedingEWB.filter(
        inv => !activeSourceIds.includes(inv._id.toString())
      ).length;
    }

    res.json({ success: true, data: { pendingCount } });
  } catch (err) {
    console.error('EWB pending count error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 5 — GET / — List all EWBs with filters
// =============================================================================
router.get('/', async (req, res) => {
  try {
    const { status, sourceType, fromDate, toDate, search, page = 1, limit = 20 } = req.query;
    const orgId = req.user?.orgId;
    const query = { ...orgFilter(req) };

    await updateExpiredEWBs(orgId);

    if (status     && status     !== 'ALL') query.ewbStatus  = status;
    if (sourceType && sourceType !== 'ALL') query.sourceType = sourceType;
    if (fromDate || toDate) {
      query.createdAt = {};
      if (fromDate) query.createdAt.$gte = new Date(fromDate);
      if (toDate)   query.createdAt.$lte = new Date(new Date(toDate).setHours(23, 59, 59, 999));
    }
    if (search) {
      query.$or = [
        { ewbNumber:    { $regex: search, $options: 'i' } },
        { sourceNumber: { $regex: search, $options: 'i' } },
        { toTradeName:  { $regex: search, $options: 'i' } },
        { documentNumber: { $regex: search, $options: 'i' } },
      ];
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [ewbs, total] = await Promise.all([
      EWayBill.find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).select('-__v'),
      EWayBill.countDocuments(query),
    ]);

    const stats = await EWayBill.aggregate([
      { $match: { ...orgFilter(req) } },
      { $group: { _id: '$ewbStatus', count: { $sum: 1 } } },
    ]);
    const statMap = {};
    stats.forEach(s => { statMap[s._id] = s.count; });
    const totalAll = Object.values(statMap).reduce((a, b) => a + b, 0);

    res.json({
      success: true,
      data:    ewbs,
      stats: {
        total:     totalAll,
        generated: statMap['GENERATED'] || 0,
        partA:     statMap['PART_A']    || 0,
        expired:   statMap['EXPIRED']   || 0,
        cancelled: statMap['CANCELLED'] || 0,
        extended:  statMap['EXTENDED']  || 0,
      },
      pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) },
    });
  } catch (err) {
    console.error('EWB list error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 6 — POST /generate
// =============================================================================
router.post('/generate', async (req, res) => {
  try {
    const orgId = req.user?.orgId;

    const {
      sourceType, sourceId, sourceNumber,
      supplyType, subType, documentType, documentNumber, documentDate,
      fromGstin, fromTradeName, fromAddress1, fromPlace, fromPincode, fromStateCode, fromState,
      toGstin, toTradeName, toAddress1, toPlace, toPincode, toStateCode, toState,
      hsnCode, productName, productDesc, unit, cgstRate, sgstRate, igstRate, cessRate,
      transportMode, transporterName, transporterId, transDocNo, transDocDate,
      vehicleType, vehicleNumber, fromPlacePartB, fromStatePartB, reasonCode,
    } = req.body;

    const quantity            = parseFloat(req.body.quantity)            || 1;
    const taxableAmount       = parseFloat(req.body.taxableAmount)       || 0;
    const totalInvoiceValue   = parseFloat(req.body.totalInvoiceValue)   || 0;
    const approximateDistance = parseInt(req.body.approximateDistance)   || 0;

    const missing = [];
    if (!sourceType)              missing.push('sourceType');
    if (!documentNumber)          missing.push('documentNumber');
    if (!fromTradeName)           missing.push('fromTradeName');
    if (!toTradeName)             missing.push('toTradeName');
    if (!fromPlace)               missing.push('fromPlace');
    if (!toPlace)                 missing.push('toPlace');
    if (!hsnCode)                 missing.push('hsnCode');
    if (approximateDistance <= 0) missing.push('approximateDistance');
    if (taxableAmount <= 0)       missing.push('taxableAmount');
    if (totalInvoiceValue <= 0)   missing.push('totalInvoiceValue');

    if (missing.length > 0) {
      return res.status(400).json({ success: false, message: `Missing required fields: ${missing.join(', ')}`, missingFields: missing });
    }

    // Check duplicate active EWB
    if (sourceId && mongoose.Types.ObjectId.isValid(sourceId)) {
      const existing = await EWayBill.findOne({
        sourceId, sourceType, ewbStatus: { $in: ['GENERATED', 'PART_A', 'EXTENDED'] }
      });
      if (existing) {
        return res.status(400).json({
          success: false,
          message: `An active EWB (${existing.ewbNumber || 'Part A'}) already exists for this document`,
        });
      }
    }

    const creds = await getCredentials(orgId);

    const partAData = {
      supplyType: supplyType || 'OUTWARD', subType: subType || 'SUPPLY',
      documentType: documentType || 'INV', documentNumber,
      documentDate: documentDate || new Date().toISOString(),
      fromGstin: fromGstin || '', fromTradeName, fromAddress1: fromAddress1 || '',
      fromPlace, fromPincode: fromPincode || '', fromStateCode: fromStateCode || '',
      toGstin: toGstin || '', toTradeName, toAddress1: toAddress1 || '',
      toPlace, toPincode: toPincode || '', toStateCode: toStateCode || '',
      hsnCode, productName: productName || '', productDesc: productDesc || '',
      quantity, unit: unit || 'NOS', taxableAmount,
      cgstRate:  parseFloat(cgstRate)  || 0,
      sgstRate:  parseFloat(sgstRate)  || 0,
      igstRate:  parseFloat(igstRate)  || 0,
      cessRate:  parseFloat(cessRate)  || 0,
      totalInvoiceValue, transportMode: transportMode || 'ROAD', approximateDistance,
      transporterName: transporterName || '', transporterId: transporterId || '',
      transDocNo: transDocNo || '', transDocDate: transDocDate || null,
    };

    const partBData = (vehicleNumber?.trim())
      ? {
          vehicleType:    vehicleType    || 'REGULAR',
          vehicleNumber:  vehicleNumber.trim().toUpperCase(),
          fromPlacePartB: fromPlacePartB || fromPlace || '',
          fromStatePartB: fromStatePartB || fromState || '',
          reasonCode:     reasonCode     || '1',
        }
      : null;

    const result = await EWBNICService.generateEWayBill(creds, partAData, partBData);
    if (!result.success) {
      return res.status(400).json({ success: false, message: result.message });
    }

    const ewbDoc = new EWayBill({
      orgId, sourceType,
      sourceId:     (sourceId && mongoose.Types.ObjectId.isValid(sourceId)) ? sourceId : undefined,
      sourceNumber: sourceNumber || documentNumber,
      ewbNumber:    result.ewbNumber,
      ewbDate:      result.ewbDate,
      validUntil:   result.validUntil,
      ewbStatus:    result.status,
      ...partAData,
      fromState: fromState || '', toState: toState || '',
      ...(partBData || {}),
      vehicleHistory: partBData?.vehicleNumber ? [{
        vehicleNumber: partBData.vehicleNumber,
        fromPlace:     partBData.fromPlacePartB,
        fromState:     partBData.fromStatePartB,
        reasonCode:    partBData.reasonCode,
        updatedAt:     new Date(),
        updatedBy:     req.user?.email || 'system',
      }] : [],
      createdBy: req.user?.email || 'system',
    });
    await ewbDoc.save();

    if (sourceId && mongoose.Types.ObjectId.isValid(sourceId)) {
      await _updateSourceDocument(sourceType, sourceId, result.ewbNumber, result.ewbDate, result.validUntil, result.status, orgId);
    }

    console.log(`✅ EWB generated: ${result.ewbNumber}`);
    res.status(201).json({ success: true, message: result.message, data: ewbDoc });
  } catch (err) {
    console.error('EWB generate error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 7 — GET /by-source/:sourceType/:sourceId — Must be BEFORE /:id
// =============================================================================
router.get('/by-source/:sourceType/:sourceId', async (req, res) => {
  try {
    const ewbs = await EWayBill.find({
      sourceType: req.params.sourceType,
      sourceId:   req.params.sourceId,
      ...orgFilter(req),
    }).sort({ createdAt: -1 });
    res.json({ success: true, data: ewbs });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 8 — GET /:id/print — Generate EWB PDF
// Must be BEFORE /:id
// =============================================================================
router.get('/:id/print', async (req, res) => {
  // Support token in query string for direct PDF download
  if (!req.user && req.query.token) {
    try {
      const jwt = require('jsonwebtoken');
      req.user  = jwt.verify(req.query.token, process.env.FINANCE_JWT_SECRET || process.env.JWT_SECRET);
    } catch (e) {
      return res.status(401).json({ success: false, message: 'Invalid token' });
    }
  }
  // Set branchFilter from query param (used when opening PDF via direct URL)
  if (!req.branchFilter) {
    const branchIds = req.query.branchIds;
    if (branchIds && branchIds.trim() !== '' && branchIds.trim() !== 'ALL') {
      const ids = branchIds.split(',').map(s => s.trim()).filter(Boolean);
      req.branchFilter = ids.length ? { branchId: { $in: ids } } : {};
    } else {
      req.branchFilter = {};
    }
  }

  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ success: false, message: 'Invalid EWB ID' });
    }

    const ewb = await EWayBill.findOne({ _id: req.params.id, ...orgFilter(req) }).lean();
    if (!ewb) return res.status(404).json({ success: false, message: 'EWB not found' });

    // Fetch org details — branch-aware
    let orgName  = 'Your Company';
    let orgGSTIN = '';
    let orgAddr  = '';
    try {
      const { getEffectiveOrgData } = require('./branches');
      const db = mongoose.connection.db;
      const org = db ? await getEffectiveOrgData(req.user?.orgId, req.branchIds?.length === 1 ? req.branchIds[0] : null, db) : null;
      if (org) {
        orgName  = org.orgName  || orgName;
        orgGSTIN = org.gstNumber || '';
        orgAddr  = org.address   || '';
      }
    } catch (_) {}

    // Generate PDF
    const pdfBuffer = await _generateEWBPDF(ewb, orgName, orgGSTIN, orgAddr);

    const filename = `EWB-${ewb.ewbNumber || ewb._id}.pdf`;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
    res.setHeader('Content-Length', pdfBuffer.length);
    res.send(pdfBuffer);

  } catch (err) {
    console.error('EWB PDF error:', err);
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 9 — GET /:id — EWB detail
// =============================================================================
router.get('/:id', async (req, res) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ success: false, message: 'Invalid EWB ID' });
    }
    const ewb = await EWayBill.findOne({ _id: req.params.id, ...orgFilter(req) });
    if (!ewb) return res.status(404).json({ success: false, message: 'EWB not found' });
    res.json({ success: true, data: ewb });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 10 — PUT /:id/update-part-b
// =============================================================================
router.put('/:id/update-part-b', async (req, res) => {
  try {
    const ewb = await EWayBill.findOne({ _id: req.params.id, ...orgFilter(req) });
    if (!ewb) return res.status(404).json({ success: false, message: 'EWB not found' });
    if (ewb.ewbStatus === 'CANCELLED') {
      return res.status(400).json({ success: false, message: 'Cannot update a cancelled EWB' });
    }
    const { vehicleNumber, fromPlace, fromState, reasonCode, transDocNo, transDocDate } = req.body;
    if (!vehicleNumber) return res.status(400).json({ success: false, message: 'Vehicle number is required' });

    const creds  = await getCredentials(req.user?.orgId);
    const result = await EWBNICService.updatePartB(creds, ewb.ewbNumber, req.body);
    if (!result.success) return res.status(400).json({ success: false, message: result.message });

    ewb.vehicleHistory.push({
      vehicleNumber, fromPlace, fromState, reasonCode, transDocNo, transDocDate,
      updatedAt: new Date(), updatedBy: req.user?.email || 'system',
    });
    ewb.vehicleNumber  = vehicleNumber.trim().toUpperCase();
    ewb.fromPlacePartB = fromPlace  || '';
    ewb.fromStatePartB = fromState  || '';
    ewb.reasonCode     = reasonCode || '1';
    ewb.updatedBy      = req.user?.email;
    if (ewb.ewbStatus === 'PART_A') ewb.ewbStatus = 'GENERATED';
    await ewb.save();

    res.json({ success: true, message: result.message, data: ewb });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 11 — PUT /:id/extend
// =============================================================================
router.put('/:id/extend', async (req, res) => {
  try {
    const ewb = await EWayBill.findOne({ _id: req.params.id, ...orgFilter(req) });
    if (!ewb) return res.status(404).json({ success: false, message: 'EWB not found' });
    if (!['GENERATED', 'EXPIRED', 'EXTENDED'].includes(ewb.ewbStatus)) {
      return res.status(400).json({ success: false, message: 'Only Generated or recently Expired EWBs can be extended' });
    }

    const now     = new Date();
    const fourHrs = 4 * 60 * 60 * 1000;
    const canExtend = ewb.validUntil
      ? ((ewb.validUntil - now) <= fourHrs || (now - ewb.validUntil) <= fourHrs)
      : true;

    if (!canExtend) {
      return res.status(400).json({ success: false, message: 'Extension is only available within 4 hours before or after EWB expiry' });
    }

    const remainingDistance = parseInt(req.body.remainingDistance) || 100;
    const creds  = await getCredentials(req.user?.orgId);
    const result = await EWBNICService.extendValidity(creds, ewb.ewbNumber, { ...req.body, remainingDistance });
    if (!result.success) return res.status(400).json({ success: false, message: result.message });

    ewb.extensionHistory = ewb.extensionHistory || [];
    ewb.extensionHistory.push({
      extendedFrom:  ewb.validUntil, extendedTo: result.newValidUntil,
      fromPlace:     req.body.fromPlace, fromState: req.body.fromState,
      vehicleNumber: req.body.vehicleNumber, remainingDist: remainingDistance,
      reason:        req.body.reason, extendedAt: new Date(), extendedBy: req.user?.email,
    });
    ewb.validUntil = result.newValidUntil;
    ewb.ewbStatus  = 'EXTENDED';
    ewb.extendedAt = new Date();
    ewb.updatedBy  = req.user?.email;
    await ewb.save();

    res.json({ success: true, message: result.message, data: ewb });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 12 — PUT /:id/cancel
// =============================================================================
router.put('/:id/cancel', async (req, res) => {
  try {
    const ewb = await EWayBill.findOne({ _id: req.params.id, ...orgFilter(req) });
    if (!ewb) return res.status(404).json({ success: false, message: 'EWB not found' });
    if (ewb.ewbStatus === 'CANCELLED') {
      return res.status(400).json({ success: false, message: 'EWB is already cancelled' });
    }

    const hoursSince = ewb.ewbDate ? (new Date() - new Date(ewb.ewbDate)) / (1000 * 60 * 60) : 0;
    if (ewb.ewbDate && hoursSince > 24) {
      return res.status(400).json({ success: false, message: `EWB can only be cancelled within 24 hours. Generated ${Math.floor(hoursSince)} hours ago.` });
    }

    const { cancelReason } = req.body;
    if (!cancelReason) return res.status(400).json({ success: false, message: 'Cancel reason is required' });

    const creds  = await getCredentials(req.user?.orgId);
    const result = await EWBNICService.cancelEWayBill(creds, ewb.ewbNumber, cancelReason);
    if (!result.success) return res.status(400).json({ success: false, message: result.message });

    ewb.ewbStatus    = 'CANCELLED';
    ewb.cancelledAt  = new Date();
    ewb.cancelReason = cancelReason;
    ewb.updatedBy    = req.user?.email;
    await ewb.save();

    if (ewb.sourceId) await _clearSourceDocumentEWB(ewb.sourceType, ewb.sourceId);
    res.json({ success: true, message: result.message, data: ewb });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 13 — POST /consolidated
// =============================================================================
router.post('/consolidated', async (req, res) => {
  try {
    const { vehicleNumber, fromPlace, fromState, transportMode, ewbNumbers } = req.body;
    if (!ewbNumbers || ewbNumbers.length < 2) {
      return res.status(400).json({ success: false, message: 'At least 2 EWB numbers are required for consolidation' });
    }
    if (!vehicleNumber) {
      return res.status(400).json({ success: false, message: 'Vehicle number is required' });
    }

    const creds  = await getCredentials(req.user?.orgId);
    const result = await EWBNICService.generateConsolidatedEWB(
      creds, { vehicleNumber, fromPlace, fromState, transportMode }, ewbNumbers
    );
    if (!result.success) return res.status(400).json({ success: false, message: result.message });

    await EWayBill.updateMany(
      { orgId: req.user?.orgId, ewbNumber: { $in: ewbNumbers } },
      { $set: { isConsolidated: true, consolidatedEwbNumber: result.cewbNumber } }
    );

    res.json({ success: true, message: result.message, data: result });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// ROUTE 14 — POST /associate
// =============================================================================
router.post('/associate', async (req, res) => {
  try {
    const { sourceType, sourceId, sourceNumber, ewbNumber, ewbDate, validUntil } = req.body;
    if (!ewbNumber || String(ewbNumber).length !== 12) {
      return res.status(400).json({ success: false, message: 'Valid 12-digit EWB number is required' });
    }
    const { validUntil: calcValidity } = EWBNICService.calculateValidity(100);

    // ── FIX: only set sourceId if it is a valid ObjectId ──────────────────
    const validSourceId = sourceId && mongoose.Types.ObjectId.isValid(sourceId) ? sourceId : undefined;

    const ewb = new EWayBill({
      orgId:        req.user?.orgId,
      sourceType,
      sourceId:     validSourceId,   // ← was: sourceId (broke when empty string)
      sourceNumber,
      ewbNumber:    String(ewbNumber),
      ewbDate:      ewbDate    ? new Date(ewbDate)    : new Date(),
      validUntil:   validUntil ? new Date(validUntil) : calcValidity,
      ewbStatus:    'GENERATED',
      isManuallyAssociated: true,
      associatedAt: new Date(),
      documentNumber: sourceNumber,
      documentDate:   ewbDate ? new Date(ewbDate) : new Date(),
      fromTradeName: '', toTradeName: '', fromPlace: '', toPlace: '', hsnCode: '',
      createdBy: req.user?.email || 'system',
    });
    await ewb.save();

    if (validSourceId) {
      await _updateSourceDocument(sourceType, validSourceId, ewbNumber, ewb.ewbDate, ewb.validUntil, 'GENERATED', req.user?.orgId);
    }

    res.status(201).json({ success: true, message: `EWB ${ewbNumber} associated successfully`, data: ewb });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// =============================================================================
// PDF GENERATION — EWB Document (Government Format)
// =============================================================================
function _generateEWBPDF(ewb, orgName, orgGSTIN, orgAddr) {
  return new Promise((resolve, reject) => {
    try {
      const chunks = [];
      const doc = new PDFDocument({ size: 'A4', margin: 35, bufferPages: true });

      doc.on('data',  chunk => chunks.push(chunk));
      doc.on('end',   ()    => resolve(Buffer.concat(chunks)));
      doc.on('error', reject);

      const pageW  = 525; // usable width
      const navy   = '#0D1B3E';
      const blue   = '#1e3a8a';
      const green  = '#15803D';
      const grey   = '#64748B';
      const light  = '#F0F4F8';
      const border = '#DDE3EE';

      // ── HEADER ─────────────────────────────────────────────────────────────
      doc.rect(35, 35, pageW, 70).fill(navy);

      doc.fontSize(9).fillColor('rgba(255,255,255,0.6)').font('Helvetica')
         .text('e-WAY BILL', 50, 45, { characterSpacing: 2 });

      doc.fontSize(20).fillColor('#ffffff').font('Helvetica-Bold')
         .text(ewb.ewbNumber || 'Part A Initiated', 50, 56, { width: 260 });

      doc.fontSize(8).fillColor('rgba(255,255,255,0.75)').font('Helvetica')
         .text(`Generated: ${ewb.ewbDate ? new Date(ewb.ewbDate).toLocaleString('en-IN') : 'N/A'}`, 50, 82);

      if (ewb.validUntil) {
        doc.text(`Valid Until: ${new Date(ewb.validUntil).toLocaleDateString('en-IN', { day: '2-digit', month: 'long', year: 'numeric' })}`, 50, 93);
      }

      // Status badge (right side of header)
      const statusColors = { GENERATED: '#15803D', PART_A: '#B45309', EXTENDED: '#1D4ED8', EXPIRED: '#DC2626', CANCELLED: '#64748B' };
      const statusBg = statusColors[ewb.ewbStatus] || '#64748B';
      doc.rect(390, 48, 130, 26).fill(statusBg);
      doc.fontSize(11).fillColor('#ffffff').font('Helvetica-Bold')
         .text((ewb.ewbStatus || 'DRAFT').replace(/_/g, ' '), 390, 55, { width: 130, align: 'center' });

      // Org info (right)
      doc.fontSize(7).fillColor('rgba(255,255,255,0.85)').font('Helvetica')
         .text(orgName.toUpperCase(), 390, 80, { width: 130, align: 'right' });
      if (orgGSTIN) {
        doc.fontSize(7).text(`GSTIN: ${orgGSTIN}`, 390, 90, { width: 130, align: 'right' });
      }

      let y = 120;

      // ── SECTION: PART A — FROM & TO ────────────────────────────────────────
      y = _sectionHeader(doc, 'PART A — CONSIGNOR & CONSIGNEE DETAILS', y, pageW, navy, blue);

      const colW = (pageW - 10) / 2;

      // FROM box
      doc.rect(35, y, colW, 90).fillAndStroke(light, border);
      doc.fontSize(7).fillColor(grey).font('Helvetica-Bold')
         .text('FROM (CONSIGNOR / SELLER)', 44, y + 7, { characterSpacing: 0.5 });
      doc.fontSize(8).fillColor('#000').font('Helvetica-Bold')
         .text(ewb.fromTradeName || '—', 44, y + 19, { width: colW - 18, ellipsis: true });
      doc.fontSize(7.5).fillColor('#333').font('Helvetica')
         .text(`GSTIN: ${ewb.fromGstin || 'N/A'}`,  44, y + 32, { width: colW - 18 })
         .text(`${ewb.fromAddress1 || ''}`,          44, y + 43, { width: colW - 18, ellipsis: true })
         .text(`${ewb.fromPlace || ''}, ${ewb.fromState || ''}`, 44, y + 53, { width: colW - 18 })
         .text(`PIN: ${ewb.fromPincode || '—'}`,     44, y + 63, { width: colW - 18 });

      // TO box
      const toX = 35 + colW + 10;
      doc.rect(toX, y, colW, 90).fillAndStroke(light, border);
      doc.fontSize(7).fillColor(grey).font('Helvetica-Bold')
         .text('TO (CONSIGNEE / BUYER)', toX + 9, y + 7, { characterSpacing: 0.5 });
      doc.fontSize(8).fillColor('#000').font('Helvetica-Bold')
         .text(ewb.toTradeName || '—', toX + 9, y + 19, { width: colW - 18, ellipsis: true });
      doc.fontSize(7.5).fillColor('#333').font('Helvetica')
         .text(`GSTIN: ${ewb.toGstin || 'N/A'}`,    toX + 9, y + 32, { width: colW - 18 })
         .text(`${ewb.toAddress1 || ''}`,            toX + 9, y + 43, { width: colW - 18, ellipsis: true })
         .text(`${ewb.toPlace || ''}, ${ewb.toState || ''}`, toX + 9, y + 53, { width: colW - 18 })
         .text(`PIN: ${ewb.toPincode || '—'}`,       toX + 9, y + 63, { width: colW - 18 });

      y += 100;

      // ── SECTION: GOODS DETAILS ─────────────────────────────────────────────
      y = _sectionHeader(doc, 'GOODS DETAILS', y, pageW, navy, blue);

      // Table header
      const gCols = { hsn: { x: 35, w: 70 }, desc: { x: 110, w: 120 }, qty: { x: 235, w: 45 }, unit: { x: 285, w: 40 }, taxable: { x: 330, w: 65 }, gst: { x: 400, w: 35 }, total: { x: 440, w: 120 } };
      doc.rect(35, y, pageW, 18).fill(navy);
      doc.fontSize(7).fillColor('#fff').font('Helvetica-Bold');
      doc.text('HSN/SAC',    gCols.hsn.x  + 3, y + 6, { width: gCols.hsn.w });
      doc.text('DESCRIPTION',gCols.desc.x + 3, y + 6, { width: gCols.desc.w });
      doc.text('QTY',        gCols.qty.x  + 3, y + 6, { width: gCols.qty.w,     align: 'center' });
      doc.text('UNIT',       gCols.unit.x + 3, y + 6, { width: gCols.unit.w });
      doc.text('TAXABLE (₹)',gCols.taxable.x+3,y + 6, { width: gCols.taxable.w, align: 'right' });
      doc.text('GST%',       gCols.gst.x  + 3, y + 6, { width: gCols.gst.w,     align: 'center' });
      doc.text('TOTAL (₹)',  gCols.total.x+ 3, y + 6, { width: gCols.total.w,   align: 'right' });
      y += 18;

      // Single item row
      const rowH = 22;
      doc.rect(35, y, pageW, rowH).fillAndStroke('#ffffff', border);
      doc.fontSize(7.5).fillColor('#000').font('Helvetica');
      doc.text(ewb.hsnCode      || '—', gCols.hsn.x  + 3, y + 7, { width: gCols.hsn.w });
      doc.text(ewb.productName  || '—', gCols.desc.x + 3, y + 7, { width: gCols.desc.w, ellipsis: true });
      doc.text(String(ewb.quantity || 0), gCols.qty.x + 3, y + 7, { width: gCols.qty.w, align: 'center' });
      doc.text(ewb.unit         || 'NOS', gCols.unit.x + 3, y + 7, { width: gCols.unit.w });
      const gstRate = (ewb.cgstRate || 0) * 2 || ewb.igstRate || 0;
      const taxAmt  = ewb.taxableAmount || 0;
      const totAmt  = ewb.totalInvoiceValue || 0;
      doc.text(`₹${taxAmt.toFixed(2)}`,   gCols.taxable.x + 3, y + 7, { width: gCols.taxable.w, align: 'right' });
      doc.text(`${gstRate}%`,             gCols.gst.x    + 3, y + 7, { width: gCols.gst.w,     align: 'center' });
      doc.font('Helvetica-Bold')
         .text(`₹${totAmt.toFixed(2)}`,   gCols.total.x  + 3, y + 7, { width: gCols.total.w,   align: 'right' });
      y += rowH + 8;

      // Tax summary row
      doc.rect(35, y, pageW, 22).fill('#EEF2FF');
      doc.fontSize(7.5).fillColor(navy).font('Helvetica-Bold');
      if (ewb.cgstRate > 0) {
        doc.text(`CGST: ₹${((taxAmt * ewb.cgstRate) / 100).toFixed(2)}`, 50,  y + 7);
        doc.text(`SGST: ₹${((taxAmt * ewb.sgstRate) / 100).toFixed(2)}`, 160, y + 7);
      } else if (ewb.igstRate > 0) {
        doc.text(`IGST: ₹${((taxAmt * ewb.igstRate) / 100).toFixed(2)}`, 50, y + 7);
      }
      doc.text(`TOTAL INVOICE VALUE: ₹${totAmt.toFixed(2)}`, 300, y + 7, { width: 250, align: 'right' });
      y += 32;

      // ── SECTION: TRANSPORT DETAILS ─────────────────────────────────────────
      y = _sectionHeader(doc, 'TRANSPORT DETAILS', y, pageW, navy, blue);

      const tRows = [
        ['Transport Mode', ewb.transportMode || '—'],
        ['Approx. Distance', `${ewb.approximateDistance || 0} km`],
        ['Transporter Name', ewb.transporterName || '—'],
        ['Transporter ID (TRANSIN)', ewb.transporterId || '—'],
        ['Transport Doc No.', ewb.transDocNo || '—'],
        ['Transport Doc Date', ewb.transDocDate ? new Date(ewb.transDocDate).toLocaleDateString('en-IN') : '—'],
      ];

      y = _twoColTable(doc, tRows, y, pageW, light, border);
      y += 8;

      // ── SECTION: PART B — VEHICLE DETAILS ─────────────────────────────────
      if (ewb.vehicleNumber || ewb.ewbStatus === 'PART_A') {
        y = _sectionHeader(doc, 'PART B — VEHICLE DETAILS', y, pageW, navy, blue);

        if (ewb.ewbStatus === 'PART_A' || !ewb.vehicleNumber) {
          doc.rect(35, y, pageW, 28).fillAndStroke('#FEF3C7', '#FCD34D');
          doc.fontSize(8).fillColor('#92400E').font('Helvetica-Bold')
             .text('⚠  Part B not filled yet. Transporter will update vehicle details before moving goods.', 44, y + 10, { width: pageW - 18 });
          y += 38;
        } else {
          const vRows = [
            ['Vehicle Number', ewb.vehicleNumber || '—'],
            ['Vehicle Type',   (ewb.vehicleType || 'REGULAR').replace(/_/g, ' ')],
            ['From Place',     ewb.fromPlacePartB || '—'],
            ['From State',     ewb.fromStatePartB || '—'],
            ['Reason',         _reasonLabel(ewb.reasonCode)],
          ];
          y = _twoColTable(doc, vRows, y, pageW, light, border);
          y += 8;
        }
      }

      // ── SECTION: VEHICLE HISTORY (if multiple updates) ─────────────────────
      if (ewb.vehicleHistory && ewb.vehicleHistory.length > 1) {
        y = _sectionHeader(doc, 'VEHICLE UPDATE HISTORY', y, pageW, navy, blue);
        ewb.vehicleHistory.forEach((vh, i) => {
          const rowFill = i % 2 === 0 ? '#ffffff' : light;
          doc.rect(35, y, pageW, 18).fillAndStroke(rowFill, border);
          doc.fontSize(7).fillColor('#333').font('Helvetica')
             .text(`${i + 1}. ${vh.vehicleNumber || '—'}`, 44, y + 6, { width: 120 })
             .text(vh.fromPlace || '—', 170, y + 6, { width: 120 })
             .text(_reasonLabel(vh.reasonCode), 300, y + 6, { width: 100 })
             .text(vh.updatedAt ? new Date(vh.updatedAt).toLocaleDateString('en-IN') : '—', 410, y + 6, { width: 110, align: 'right' });
          y += 18;
        });
        y += 8;
      }

      // ── DOCUMENT DETAILS ──────────────────────────────────────────────────
      y = _sectionHeader(doc, 'DOCUMENT DETAILS', y, pageW, navy, blue);
      const docRows = [
        ['Supply Type',    ewb.supplyType  || '—'],
        ['Sub Type',       (ewb.subType    || '—').replace(/_/g, ' ')],
        ['Document Type',  ewb.documentType|| '—'],
        ['Document Number',ewb.documentNumber || '—'],
        ['Document Date',  ewb.documentDate ? new Date(ewb.documentDate).toLocaleDateString('en-IN') : '—'],
        ['Source Document',`${(ewb.sourceType || '').replace(/_/g, ' ')} — ${ewb.sourceNumber || '—'}`],
      ];
      y = _twoColTable(doc, docRows, y, pageW, light, border);
      y += 12;

      // ── QR CODE BOX ───────────────────────────────────────────────────────
      if (ewb.ewbNumber) {
        doc.rect(35, y, pageW, 48).fillAndStroke('#F8FAFC', border);
        doc.fontSize(7).fillColor(grey).font('Helvetica-Bold')
           .text('SCAN FOR VERIFICATION', 50, y + 8, { characterSpacing: 0.8 });
        doc.fontSize(8).fillColor(navy).font('Helvetica')
           .text(`EWB Number: ${ewb.ewbNumber}`, 50, y + 20);
        doc.fontSize(7).fillColor(grey)
           .text('Present this document at checkpoints. EWB number is mandatory for transport of goods.', 50, y + 32, { width: pageW - 30 });

        // QR placeholder box
        doc.rect(470, y + 6, 70, 36).stroke(border);
        doc.fontSize(6).fillColor(grey).font('Helvetica')
           .text('QR CODE', 470, y + 20, { width: 70, align: 'center' });
        y += 58;
      }

      // ── FOOTER ────────────────────────────────────────────────────────────
      doc.moveTo(35, 790).lineTo(560, 790).lineWidth(1).strokeColor(border).stroke();
      doc.fontSize(7).fillColor(grey).font('Helvetica')
         .text(`${orgName}${orgGSTIN ? ' · GSTIN: ' + orgGSTIN : ''} · EWB: ${ewb.ewbNumber || 'Part A'}`,
               35, 795, { width: pageW / 2 })
         .text(`Printed: ${new Date().toLocaleString('en-IN')}`, 35, 795, { width: pageW, align: 'right' });

      doc.end();
    } catch (err) {
      reject(err);
    }
  });
}

// ── PDF helper: section header ─────────────────────────────────────────────────
function _sectionHeader(doc, title, y, pageW, navy, blue) {
  doc.rect(35, y, pageW, 18).fill(blue);
  doc.fontSize(7.5).fillColor('#ffffff').font('Helvetica-Bold')
     .text(title, 44, y + 6, { characterSpacing: 0.5 });
  return y + 22;
}

// ── PDF helper: two-column key-value table ─────────────────────────────────────
function _twoColTable(doc, rows, y, pageW, light, border) {
  const colW = (pageW - 10) / 2;
  rows.forEach((row, i) => {
    const col    = i % 2;
    const rowIdx = Math.floor(i / 2);
    const x      = col === 0 ? 35 : 35 + colW + 10;
    if (col === 0) {
      const fill = rowIdx % 2 === 0 ? '#ffffff' : light;
      doc.rect(35, y, pageW, 18).fillAndStroke(fill, border);
    }
    doc.fontSize(7.5).fillColor('#64748B').font('Helvetica-Bold')
       .text(row[0] + ':', x + 8, y + 5, { width: colW / 2.2 });
    doc.fillColor('#000000').font('Helvetica')
       .text(String(row[1] || '—'), x + 8 + colW / 2.2, y + 5, { width: colW / 2 - 8, ellipsis: true });
    if (col === 1) y += 18;
  });
  if (rows.length % 2 !== 0) y += 18;
  return y;
}

function _reasonLabel(code) {
  const map = { '1': 'First Time', '2': 'Vehicle Breakdown', '3': 'Transshipment', '4': 'Others' };
  return map[String(code)] || 'First Time';
}

// ── Helper: update source document ────────────────────────────────────────────
async function _updateSourceDocument(sourceType, sourceId, ewbNumber, ewbDate, validUntil, ewbStatus, orgId) {
  try {
    const data = { ewbNumber, ewbDate, ewbValidUntil: validUntil, ewbStatus };
    const modelMap = { INVOICE: 'Invoice', CREDIT_NOTE: 'CreditNote', DELIVERY_CHALLAN: 'DeliveryChallan' };
    const modelName = modelMap[sourceType];
    if (modelName && mongoose.models[modelName]) {
      await mongoose.models[modelName].findByIdAndUpdate(sourceId, { $set: data });
    }
  } catch (e) {
    console.warn('⚠️ Could not update source document:', e.message);
  }
}

async function _clearSourceDocumentEWB(sourceType, sourceId) {
  try {
    const clearData = { $unset: { ewbNumber: 1, ewbDate: 1, ewbValidUntil: 1, ewbStatus: 1 } };
    const modelMap  = { INVOICE: 'Invoice', CREDIT_NOTE: 'CreditNote', DELIVERY_CHALLAN: 'DeliveryChallan' };
    const modelName = modelMap[sourceType];
    if (modelName && mongoose.models[modelName]) {
      await mongoose.models[modelName].findByIdAndUpdate(sourceId, clearData);
    }
  } catch (e) {
    console.warn('⚠️ Could not clear EWB from source document:', e.message);
  }
}

module.exports = router;