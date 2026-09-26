const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');

// ============================================================================
// DEDICATED MONGODB SCHEMA FOR AUTOMATION STAGING (Does not touch invoices.js)
// ============================================================================
const automationDraftSchema = new mongoose.Schema({
  orgId: String,
  branchId: String,
  invoiceNumber: String,
  customerName: String,
  customerId: String,
  invoiceDate: Date,
  dueDate: Date,
  terms: String,
  items: Array,
  subTotal: Number,
  taxableTotal: Number,
  totalCGST: Number,
  totalSGST: Number,
  totalTax: Number,
  totalAmount: Number,
  status: { type: String, default: 'AUTOMATION_DRAFT' },
  createdAt: { type: Date, default: Date.now }
}, { strict: false });

const AutomationDraft = mongoose.models.AutomationDraft || mongoose.model('AutomationDraft', automationDraftSchema);

const billedShipmentSchema = new mongoose.Schema({
  orgId: String,
  trackingNo: String,
  billedAt: { type: Date, default: Date.now },
  invoiceNumber: String,
  invoiceId: mongoose.Schema.Types.ObjectId,
}, { strict: false });

const BilledShipment = mongoose.models.BilledShipment ||
  mongoose.model('BilledShipment', billedShipmentSchema);

// Matches an AL/tracking number sitting on its own first line, e.g. "AL-1005699".
// Shared by every place in this file that needs to recover an item's tracking
// number — some items only ever get it saved inside itemDetails text (legacy
// drafts, or one that lost its dedicated field on a reload/edit round-trip),
// never in the shipmentTrackingNumber field itself.
const TRACKING_NO_LINE = /^([A-Za-z]{1,6}-[A-Za-z0-9-]+)\s*$/;

// Resolves an item's tracking number the same way everywhere: prefer the
// dedicated field, fall back to parsing it out of itemDetails' first line.
function resolveItemTrackingNo(item) {
  let trackingNo = item.shipmentTrackingNumber || item.expenseId || null;
  if (!trackingNo && item.itemDetails) {
    const firstLine = String(item.itemDetails).split('\n')[0].trim();
    const m = firstLine.match(TRACKING_NO_LINE);
    if (m) trackingNo = m[1];
  }
  return trackingNo;
}

// ============================================================================
// AUTOMATION — Fetch Unbilled Shipments from PHP API and Filter Billed Ones
// ============================================================================
router.get('/unbilled-shipments', async (req, res) => {
  try {
    let { orgId, branchId, startDate, endDate, reportType } = req.query;
    
    // Fallback to headers if not in query
    if (!branchId) branchId = req.headers['x-branch-ids'] || '';
    if (!orgId) orgId = req.user?.orgId || req.headers['x-org-id'] || '';

    // RULE: Only fetch shipments if we are in the specific logistics branch requested!
    if (branchId !== '6a05b32faef99160d927b0d1') {
      return res.json({ success: true, count: 0, shipments: [] });
    }

    const phpApiUrl = `https://crm.abra-logistic.com/dashboard/api-unbilled-shipments.php?org_id=${orgId}&branch_id=${branchId}&start_date=${startDate || ''}&end_date=${endDate || ''}&report_type=${encodeURIComponent(reportType || '')}`;
    
    let shipments = [];
    try {
      const fetchReq = typeof fetch !== "undefined" ? fetch : require("node-fetch");
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 15000); // 15s timeout
      console.log('📡 Fetching from PHP:', phpApiUrl);
      const response = await fetchReq(phpApiUrl, { signal: controller.signal });
      clearTimeout(timeoutId);
      const rawText = await response.text();
      console.log('📦 PHP raw response (first 300 chars):', rawText.substring(0, 300));
      let data;
      try { data = JSON.parse(rawText); } catch(e) {
        console.error('❌ PHP returned invalid JSON:', rawText.substring(0, 200));
        return res.status(500).json({ success: false, error: 'PHP API returned invalid response. Please upload the updated api-unbilled-shipments.php to the CRM server.' });
      }
      if (data.success && data.shipments) {
        shipments = data.shipments;
        // Chargeable weight = whichever is higher between actual weight and
        // volumetric weight (standard freight billing rule) — computed once
        // here so every consumer of this endpoint gets the correct figure,
        // instead of each screen re-deriving its own (previously wrong)
        // version of this from the raw weight/volumetric_weight fields.
        shipments = shipments.map(s => {
          const actualWeight = parseFloat(s.weight) || 0;
          const volumetricWeight = parseFloat(s.volumetric_weight) || 0;
          return { ...s, chargeable_weight: Math.max(actualWeight, volumetricWeight) };
        });
      } else {
        console.error('❌ PHP error response:', data);
        return res.status(500).json({ success: false, error: data.message || 'PHP API error' });
      }
    } catch (phpErr) {
      if (phpErr.name === 'AbortError') {
        console.error('❌ PHP API timed out after 15s');
        return res.status(500).json({ success: false, error: 'Shipment database timed out. Please try again.' });
      }
      console.error('❌ Failed to fetch from PHP API:', phpErr.message);
      return res.status(500).json({ success: false, error: 'Could not communicate with shipment database.' });
    }

    if (!shipments.length) {
      return res.json({ success: true, count: 0, shipments: [] });
    }

    // EXCLUSION LOGIC: Filter out shipments that are already in a staging draft
    const drafts = await AutomationDraft.find({ orgId }).lean();
    // Global — every staged item, regardless of date. MUST stay unscoped: this is what
    // keeps an already-staged shipment from reappearing as "available" just because a
    // different date range is being viewed (would risk double-billing it).
    const draftedTrackingNos = new Set();
    // Date-scoped subset of the same items — used ONLY for the "X in Staging" display
    // count, so it matches the selected range the same way the Billed count does.
    const draftedInRangeTrackingNos = new Set();

    // Matches the "Date: YYYY-MM-DD" line saved alongside the tracking number
    const ITEM_DATE_LINE = /Date:\s*(\d{4}-\d{2}-\d{2})/;

    const rangeStart = startDate ? new Date(startDate) : null;
    const rangeEnd = endDate ? new Date(endDate) : null;
    if (rangeEnd) rangeEnd.setHours(23, 59, 59, 999);

    for (const d of drafts) {
      if (d.items && Array.isArray(d.items)) {
        for (const item of d.items) {
          // Fallback for legacy/broken drafts that never saved shipmentTrackingNumber
          // (or lost it on a reload/edit round-trip): the AL number is still
          // recoverable — it's always the first line of itemDetails.
          const trackingNo = resolveItemTrackingNo(item);
          let itemDate = null;
          if (item.itemDetails) {
            const dm = String(item.itemDetails).match(ITEM_DATE_LINE);
            if (dm) itemDate = new Date(dm[1]);
          }
          if (!trackingNo) continue;

          draftedTrackingNos.add(trackingNo);

          const inRange = !!itemDate &&
            (!rangeStart || itemDate >= rangeStart) &&
            (!rangeEnd || itemDate <= rangeEnd);
          if (inRange) draftedInRangeTrackingNos.add(trackingNo);
        }
      }
    }

    // Also exclude already billed shipments (tracked separately)
    const billed = await BilledShipment.find({ orgId }).lean();
    const billedTrackingNos = new Set(billed.map(b => b.trackingNo));

    // Combined exclusion set — always uses the unscoped global set, never the date-scoped one
    const excludedSet = new Set([...draftedTrackingNos, ...billedTrackingNos]);

    const filteredShipments = shipments.filter(s => {
      const trackingNo = s.tracking_no || s.id;
      return !excludedSet.has(trackingNo?.toString());
    });

    res.json({
      success: true,
      count: filteredShipments.length,
      totalCount: shipments.length,
      draftCount: draftedInRangeTrackingNos.size,   // staging only, scoped to selected dates
      billedCount: billedTrackingNos.size,          // billed only
      shipments: filteredShipments
    });

  } catch (error) {
    console.error('❌ Automation fetch error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// AUTOMATION — Update an Automation Draft
// ============================================================================
router.put('/draft/:id', async (req, res) => {
  try {
    const updated = await AutomationDraft.findByIdAndUpdate(
      req.params.id,
      { ...req.body, updatedAt: new Date() },
      { new: true }
    );
    if (!updated) return res.status(404).json({ success: false, message: 'Draft not found' });
    res.json({ success: true, invoice: updated });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// AUTOMATION — Delete/Revert an Automation Draft
// ============================================================================
router.delete('/draft/:id', async (req, res) => {
  try {
    const deleted = await AutomationDraft.findByIdAndDelete(req.params.id);
    if (!deleted) return res.status(404).json({ success: false, message: 'Draft not found' });
    res.json({ success: true, message: 'Draft deleted and shipments reverted successfully' });
  } catch (error) {
    console.error('❌ Automation draft delete error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// AUTOMATION — Save an Automation Draft
// ============================================================================
router.post('/draft', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const branchId = req.headers['x-branch-ids'] || null;

    if (branchId !== '6a05b32faef99160d927b0d1') {
      return res.status(403).json({ success: false, error: 'Automation feature is restricted to branch 6a05b32faef99160d927b0d1 only.' });
    }

    const invoiceData = { ...req.body, orgId, branchId, status: 'AUTOMATION_DRAFT' };

    if (!invoiceData.invoiceNumber) {
      const count = await AutomationDraft.countDocuments({ orgId, branchId });
      invoiceData.invoiceNumber = `AUTO-DRF-${Date.now().toString().slice(-4)}-${count + 1}`;
    }

    const newDraft = new AutomationDraft(invoiceData);
    await newDraft.save();

    res.json({
      success: true,
      message: 'Automation draft saved successfully in staging',
      invoice: newDraft
    });
  } catch (error) {
    console.error('❌ Automation draft save error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// AUTOMATION — Fetch Automation Drafts
// ============================================================================
router.get('/drafts', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const branchId = req.headers['x-branch-ids'] || null;

    if (branchId !== '6a05b32faef99160d927b0d1') {
      return res.json({ success: true, invoices: [] });
    }

    const drafts = await AutomationDraft.find({ orgId, branchId }).sort({ createdAt: -1 });

    res.json({ success: true, invoices: drafts });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// AUTOMATION — Approve Automation Draft to standard DRAFT
// ============================================================================
router.post('/approve/:id', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const branchId = req.headers['x-branch-ids'] || null;

    if (branchId !== '6a05b32faef99160d927b0d1') {
      return res.status(403).json({ success: false, error: 'Restricted branch' });
    }

    const draft = await AutomationDraft.findOne({ _id: req.params.id, orgId, branchId }).lean();

    if (!draft) {
      return res.status(404).json({ success: false, error: 'Automation Draft not found in staging' });
    }

    // ── MONTH GATE ──────────────────────────────────────────────────────────
    // Block approving this month's automation invoice while the PREVIOUS
    // calendar month still has un-invoiced shipments — either sitting in a
    // Staging Draft, or still unprocessed in Shipment Processing — unless an
    // owner/admin has granted an override for that month. Staging pending is
    // a pure DB check and is always enforced; the "still in processing"
    // count needs the CRM API and is enforced only when the CRM is reachable
    // (fail-open on a CRM outage so third-party downtime can't freeze all
    // invoicing — the outage is logged and surfaced in the response).
    try {
      const gateDate = draft.invoiceDate ? new Date(draft.invoiceDate) : new Date();
      const pend = await computePrevMonthPending(orgId, gateDate);
      const totalPending = pend.pendingInStaging + pend.pendingInProcessing;
      if (totalPending > 0) {
        const override = await AutomationMonthOverride.findOne({
          orgId, month: pend.month, revoked: { $ne: true },
        }).lean();
        if (!override) {
          return res.status(403).json({
            success: false,
            code: 'PREV_MONTH_PENDING',
            month: pend.month,
            monthLabel: pend.monthLabel,
            pendingInStaging: pend.pendingInStaging,
            pendingInProcessing: pend.pendingInProcessing,
            crmChecked: pend.crmChecked,
            error: `You are not allowed to generate invoices through automation — ${pend.monthLabel} still has ${totalPending} pending shipment(s). Contact your management for approval.`,
          });
        }
        console.log(`ℹ️ Month gate overridden for ${pend.month} by ${override.approvedByEmail} — reason: ${override.reason}`);
      }
    } catch (gateErr) {
      console.warn('⚠️ Month-gate check errored (allowing approve to proceed):', gateErr.message);
    }
    // ── END MONTH GATE ─────────────────────────────────────────────────────

    const Invoice = mongoose.model('Invoice');
    
    // We must provide createdBy as a valid ObjectId to satisfy Invoice strict schema
    let creatorId = req.user && req.user._id ? req.user._id : new mongoose.Types.ObjectId();

    // Convert staging Draft to Real Invoice
    const realInvoiceData = {
      ...draft,
      status: 'DRAFT',
      createdBy: creatorId
    };
    
    // Remove the internal AutomationDraft _id so Invoice creates a fresh one
    delete realInvoiceData._id;

    const { generateNumber } = require('../utils/numberGenerator');
    realInvoiceData.invoiceNumber = await generateNumber(Invoice, 'invoiceNumber', 'INV', orgId, branchId);

    const realInvoice = new Invoice(realInvoiceData);
    await realInvoice.save();

    // Delete the staging draft now that it's formally approved
    await AutomationDraft.deleteOne({ _id: draft._id });

    // Store all tracking nos as billed.
    // Resolve via the same fallback /unbilled-shipments already used — an
    // item that lost its dedicated shipmentTrackingNumber field (e.g. on a
    // draft reload/edit round-trip) still has the AL number recoverable from
    // itemDetails' first line. Without this fallback, such items were
    // silently dropped here — the resulting invoice showed the AL number
    // fine, but it never became a BilledShipment, leaving that shipment
    // free to reappear as "unbilled" and be invoiced a second time.
    const billedEntries = (draft.items || [])
      .map(i => ({ item: i, trackingNo: resolveItemTrackingNo(i) }))
      .filter(({ trackingNo }) => trackingNo)
      .map(({ trackingNo }) => ({
        orgId,
        trackingNo,
        invoiceNumber: realInvoice.invoiceNumber,
        invoiceId: realInvoice._id,
      }));
    if (billedEntries.length > 0) {
      await BilledShipment.insertMany(billedEntries);
    }

    res.json({ success: true, message: 'Automation Draft securely approved and pushed to main Finance.', invoice: realInvoice });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// AUTOMATION — Fetch Billed Shipments
// ============================================================================
router.get('/billed-shipments', async (req, res) => {
  try {
    let { orgId, branchId, startDate, endDate, reportType } = req.query;
    if (!branchId) branchId = req.headers['x-branch-ids'] || '';
    if (!orgId) orgId = req.user?.orgId || req.headers['x-org-id'] || '';

    if (branchId !== '6a05b32faef99160d927b0d1') {
      return res.json({ success: true, shipments: [], billedShipments: [] });
    }

    // Get all billed tracking numbers with invoice info
    const billed = await BilledShipment.find({ orgId }).lean();
    if (!billed.length) {
      return res.json({ success: true, shipments: [], billedShipments: [] });
    }

    // Fetch raw shipments from PHP
    const phpApiUrl = `https://crm.abra-logistic.com/dashboard/api-unbilled-shipments.php?org_id=${orgId}&branch_id=${branchId}&start_date=${startDate || ''}&end_date=${endDate || ''}&report_type=${encodeURIComponent(reportType || '')}`;

    let allShipments = [];
    try {
      const fetchReq = typeof fetch !== "undefined" ? fetch : require("node-fetch");
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 15000);
      const response = await fetchReq(phpApiUrl, { signal: controller.signal });
      clearTimeout(timeoutId);
      const data = JSON.parse(await response.text());
      if (data.success && data.shipments) allShipments = data.shipments;
    } catch (e) {
      console.error('❌ PHP fetch error in billed-shipments:', e.message);
    }

    // Build a map of trackingNo -> invoice info
    const billedMap = {};
    for (const b of billed) {
      billedMap[b.trackingNo] = {
        invoiceNumber: b.invoiceNumber,
        invoiceId: b.invoiceId,
        billedAt: b.billedAt,
      };
    }

    // Filter only billed ones and attach invoice info
    const billedShipments = allShipments
      .filter(s => billedMap[(s.tracking_no || s.id)?.toString()])
      .map(s => ({
        ...s,
        invoice_number: billedMap[(s.tracking_no || s.id)?.toString()]?.invoiceNumber,
        invoice_id: billedMap[(s.tracking_no || s.id)?.toString()]?.invoiceId,
        billed_at: billedMap[(s.tracking_no || s.id)?.toString()]?.billedAt,
      }));

    res.json({ success: true, count: billedShipments.length, shipments: billedShipments });
  } catch (error) {
    console.error('❌ Billed shipments fetch error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// AUTOMATION — MONTH GATING + MANUAL BILLED RECONCILIATION
// ----------------------------------------------------------------------------
// Feature 1: a month's automation invoices can't be generated while the
//   previous calendar month still has pending shipments (staging or
//   unprocessed). owner/admin can grant a per-month override; every
//   override is logged.
// Feature 2: an owner/admin tool to pull shipments that were invoiced
//   manually (their AL number is on a real invoice) but never recorded in
//   Billed Shipments — with a required reason and a kept history.
// ============================================================================
const AUTOMATION_BRANCH_ID = '6a05b32faef99160d927b0d1';

const automationMonthOverrideSchema = new mongoose.Schema({
  orgId: String,
  branchId: String,
  month: String,               // "YYYY-MM" that is unlocked
  reason: String,
  approvedByUserId: String,
  approvedByEmail: String,
  approvedByRole: String,
  revoked: { type: Boolean, default: false },
  revokedByEmail: String,
  revokedAt: Date,
  createdAt: { type: Date, default: Date.now },
}, { strict: false });
const AutomationMonthOverride = mongoose.models.AutomationMonthOverride ||
  mongoose.model('AutomationMonthOverride', automationMonthOverrideSchema);

const automationSyncHistorySchema = new mongoose.Schema({
  orgId: String,
  branchId: String,
  action: String,              // 'MANUAL_BILL_SYNC'
  trackingNo: String,
  invoiceNumber: String,
  invoiceId: mongoose.Schema.Types.ObjectId,
  reason: String,
  wasAmbiguous: Boolean,
  performedByUserId: String,
  performedByEmail: String,
  performedByRole: String,
  createdAt: { type: Date, default: Date.now },
}, { strict: false });
const AutomationSyncHistory = mongoose.models.AutomationSyncHistory ||
  mongoose.model('AutomationSyncHistory', automationSyncHistorySchema);

function isApprover(req) {
  const r = (req.user?.role || '').toLowerCase();
  return r === 'owner' || r === 'admin';
}

// "YYYY-MM" of the calendar month immediately before the given date
function prevMonthKey(d) {
  const dt = new Date(d);
  dt.setDate(1);
  dt.setMonth(dt.getMonth() - 1);
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
}
function monthLabelOf(key) {
  const [y, m] = key.split('-').map(Number);
  return new Date(y, m - 1, 1).toLocaleString('en-US', { month: 'long', year: 'numeric' });
}
function monthRangeStrs(key) {
  const [y, m] = key.split('-').map(Number);
  const lastDay = new Date(y, m, 0).getDate();
  return { startStr: `${key}-01`, endStr: `${key}-${String(lastDay).padStart(2, '0')}` };
}

const ITEM_DATE_LINE_G = /Date:\s*(\d{4}-\d{2}-\d{2})/;
function resolveItemDate(item) {
  if (item && item.itemDetails) {
    const m = String(item.itemDetails).match(ITEM_DATE_LINE_G);
    if (m) return m[1];
  }
  return null;
}

// Best-effort CRM shipment fetch for a date window. Returns array, or null on failure.
async function fetchCrmShipments(orgId, startStr, endStr) {
  try {
    const url = `https://crm.abra-logistic.com/dashboard/api-unbilled-shipments.php?org_id=${orgId}&branch_id=${AUTOMATION_BRANCH_ID}&start_date=${startStr}&end_date=${endStr}&report_type=`;
    const fetchReq = typeof fetch !== 'undefined' ? fetch : require('node-fetch');
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), 15000);
    const resp = await fetchReq(url, { signal: controller.signal });
    clearTimeout(t);
    const data = JSON.parse(await resp.text());
    if (data && data.success && Array.isArray(data.shipments)) return data.shipments;
    return null;
  } catch (e) {
    console.warn('⚠️ CRM fetch failed in month-gate check:', e.message);
    return null;
  }
}

// How many of the PREVIOUS month's shipments (relative to forDate) are still
// un-invoiced — in a Staging Draft, or unprocessed in Shipment Processing.
async function computePrevMonthPending(orgId, forDate) {
  const month = prevMonthKey(forDate);
  const { startStr, endStr } = monthRangeStrs(month);

  const drafts = await AutomationDraft.find({ orgId }).lean();
  const stagingInMonth = new Set();
  const allStaged = new Set();
  for (const d of drafts) {
    for (const item of (d.items || [])) {
      const t = resolveItemTrackingNo(item);
      if (!t) continue;
      allStaged.add(t);
      const iso = resolveItemDate(item);
      if (iso && iso >= startStr && iso <= endStr) stagingInMonth.add(t);
    }
  }

  const billed = await BilledShipment.find({ orgId }).lean();
  const billedSet = new Set(billed.map(b => b.trackingNo));

  const crm = await fetchCrmShipments(orgId, startStr, endStr);
  let pendingInProcessing = 0;
  let crmChecked = false;
  if (crm) {
    crmChecked = true;
    for (const s of crm) {
      const t = (s.tracking_no || s.id)?.toString();
      if (!t) continue;
      if (!billedSet.has(t) && !allStaged.has(t)) pendingInProcessing++;
    }
  }

  return {
    month,
    monthLabel: monthLabelOf(month),
    pendingInStaging: stagingInMonth.size,
    pendingInProcessing,
    crmChecked,
  };
}

// GET — prev-month status for the UI (banner + button gating)
router.get('/prev-month-status', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const branchId = req.headers['x-branch-ids'] || '';
    if (branchId !== AUTOMATION_BRANCH_ID) {
      return res.json({ success: true, applicable: false, blocked: false });
    }
    const fromDate = req.query.fromDate ? new Date(req.query.fromDate) : new Date();
    const info = await computePrevMonthPending(orgId, fromDate);
    const totalPending = info.pendingInStaging + info.pendingInProcessing;

    const override = await AutomationMonthOverride.findOne({
      orgId, month: info.month, revoked: { $ne: true },
    }).sort({ createdAt: -1 }).lean();

    res.json({
      success: true,
      applicable: true,
      ...info,
      totalPending,
      overridden: !!override,
      override: override ? {
        reason: override.reason,
        approvedByEmail: override.approvedByEmail,
        approvedByRole: override.approvedByRole,
        at: override.createdAt,
      } : null,
      blocked: totalPending > 0 && !override,
    });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// POST — grant a per-month override (owner/admin only)
router.post('/month-override', async (req, res) => {
  try {
    if (!isApprover(req)) {
      return res.status(403).json({ success: false, code: 'NOT_APPROVER', error: 'Only an owner or admin can grant an automation override.' });
    }
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const branchId = req.headers['x-branch-ids'] || null;
    const { month, reason } = req.body || {};
    if (!month || !/^\d{4}-\d{2}$/.test(month)) {
      return res.status(400).json({ success: false, error: 'month (YYYY-MM) is required' });
    }
    if (!reason || !reason.trim()) {
      return res.status(400).json({ success: false, error: 'A reason is required to grant an override.' });
    }
    const doc = await AutomationMonthOverride.create({
      orgId, branchId, month, reason: reason.trim(),
      approvedByUserId: (req.user?.userId || req.user?._id || '').toString(),
      approvedByEmail: req.user?.email || 'unknown',
      approvedByRole: req.user?.role || 'unknown',
    });
    res.json({ success: true, override: doc });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// GET — override history (visible to all automation users for transparency)
router.get('/month-overrides', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const list = await AutomationMonthOverride.find({ orgId }).sort({ createdAt: -1 }).limit(500).lean();
    res.json({ success: true, overrides: list });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// DELETE — revoke an override (owner/admin only)
router.delete('/month-override/:id', async (req, res) => {
  try {
    if (!isApprover(req)) {
      return res.status(403).json({ success: false, error: 'Only an owner or admin can revoke an override.' });
    }
    const upd = await AutomationMonthOverride.findByIdAndUpdate(req.params.id, {
      revoked: true, revokedByEmail: req.user?.email || 'unknown', revokedAt: new Date(),
    }, { new: true });
    if (!upd) return res.status(404).json({ success: false, error: 'Override not found' });
    res.json({ success: true, override: upd });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// GET — shipments invoiced manually (AL number on a real invoice) but missing
// from Billed Shipments. Split into `clean` (one invoice) and `ambiguous`
// (on 2+ invoices → admin must choose which one, or leave it).
router.get('/manual-billed-candidates', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const branchId = req.headers['x-branch-ids'] || '';
    if (branchId !== AUTOMATION_BRANCH_ID) {
      return res.json({ success: true, clean: [], ambiguous: [], cleanCount: 0, ambiguousCount: 0 });
    }

    // Optional date window — without it the list is the entire historical
    // backlog (thousands of rows), unusable in a dialog. A line qualifies if
    // the shipment date embedded in its "Date: YYYY-MM-DD" text is in range;
    // manually-entered lines usually have no such text, so we fall back to
    // the invoice's own date. The UI passes the Billed Shipments tab range.
    const winStart = req.query.startDate || null; // "YYYY-MM-DD"
    const winEnd = req.query.endDate || null;
    const inWindow = (item, inv) => {
      if (!winStart && !winEnd) return true;
      let iso = resolveItemDate(item);
      if (!iso && inv.invoiceDate) {
        try { iso = new Date(inv.invoiceDate).toISOString().slice(0, 10); } catch (_) {}
      }
      if (!iso) return false;
      if (winStart && iso < winStart) return false;
      if (winEnd && iso > winEnd) return false;
      return true;
    };

    const db = mongoose.connection.db;
    const invoices = await db.collection('invoices')
      .find({ orgId, items: { $exists: true, $ne: [] } })
      .project({ invoiceNumber: 1, status: 1, items: 1, totalAmount: 1, invoiceDate: 1, customerName: 1 })
      .toArray();

    const map = {}; // trackingNo -> [{invoiceNumber, invoiceId, status, totalAmount, invoiceDate, customerName}]
    for (const inv of invoices) {
      for (const item of (inv.items || [])) {
        const t = resolveItemTrackingNo(item);
        if (!t || !/^[A-Za-z]{1,6}-/.test(t)) continue;
        if (!inWindow(item, inv)) continue;
        (map[t] = map[t] || []).push({
          invoiceNumber: inv.invoiceNumber,
          invoiceId: inv._id.toString(),
          status: inv.status,
          totalAmount: inv.totalAmount,
          invoiceDate: inv.invoiceDate,
          customerName: inv.customerName,
        });
      }
    }

    const billed = await BilledShipment.find({ orgId }).lean();
    const billedSet = new Set(billed.map(b => b.trackingNo));

    const drafts = await AutomationDraft.find({ orgId }).lean();
    const stagedSet = new Set();
    for (const d of drafts) for (const item of (d.items || [])) { const t = resolveItemTrackingNo(item); if (t) stagedSet.add(t); }

    const clean = [], ambiguous = [];
    for (const [trackingNo, invs] of Object.entries(map)) {
      if (billedSet.has(trackingNo)) continue;
      const seen = new Set();
      const uniqInv = [];
      for (const x of invs) { if (!seen.has(x.invoiceNumber)) { seen.add(x.invoiceNumber); uniqInv.push(x); } }
      const base = { trackingNo, invoices: uniqInv, alsoInStagingDraft: stagedSet.has(trackingNo) };
      if (uniqInv.length === 1) clean.push({ ...base, invoice: uniqInv[0] });
      else ambiguous.push(base);
    }

    res.json({
      success: true,
      clean, ambiguous,
      cleanCount: clean.length,
      ambiguousCount: ambiguous.length,
    });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// POST — sync selected manual-billed items into Billed Shipments (owner/admin
// only, reason required, idempotent, history kept).
router.post('/manual-billed-sync', async (req, res) => {
  try {
    if (!isApprover(req)) {
      return res.status(403).json({ success: false, code: 'NOT_APPROVER', error: 'Only an owner or admin can sync shipments to Billed.' });
    }
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const branchId = req.headers['x-branch-ids'] || null;
    const { items, reason } = req.body || {};
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ success: false, error: 'No shipments selected.' });
    }
    if (!reason || !reason.trim()) {
      return res.status(400).json({ success: false, error: 'A reason is required to sync shipments to Billed.' });
    }

    const trackingNos = items.map(i => i.trackingNo).filter(Boolean);
    const existing = await BilledShipment.find({ orgId, trackingNo: { $in: trackingNos } }).lean();
    const existingSet = new Set(existing.map(e => e.trackingNo));

    const toInsert = [];
    const historyRows = [];
    for (const it of items) {
      if (!it.trackingNo || !it.invoiceId || !it.invoiceNumber) continue;
      if (existingSet.has(it.trackingNo)) continue; // idempotent — never duplicate
      let invObjId;
      try { invObjId = new mongoose.Types.ObjectId(it.invoiceId); } catch (_) { continue; }
      toInsert.push({
        orgId,
        trackingNo: it.trackingNo,
        invoiceNumber: it.invoiceNumber,
        invoiceId: invObjId,
        billedAt: new Date(),
        source: 'MANUAL_ADMIN_SYNC',
      });
      historyRows.push({
        orgId, branchId, action: 'MANUAL_BILL_SYNC',
        trackingNo: it.trackingNo,
        invoiceNumber: it.invoiceNumber,
        invoiceId: invObjId,
        reason: reason.trim(),
        wasAmbiguous: !!it.wasAmbiguous,
        performedByUserId: (req.user?.userId || req.user?._id || '').toString(),
        performedByEmail: req.user?.email || 'unknown',
        performedByRole: req.user?.role || 'unknown',
      });
    }

    if (toInsert.length > 0) {
      await BilledShipment.insertMany(toInsert);
      await AutomationSyncHistory.insertMany(historyRows);
    }

    res.json({
      success: true,
      inserted: toInsert.length,
      skippedAlreadyBilled: items.length - toInsert.length,
      message: `${toInsert.length} shipment(s) synced to Billed Shipments.`,
    });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

// GET — manual-billed sync history
router.get('/manual-billed-history', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'];
    const list = await AutomationSyncHistory.find({ orgId }).sort({ createdAt: -1 }).limit(500).lean();
    res.json({ success: true, history: list });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

module.exports = router;

// ============================================================================
// BILLED SHIPMENTS — Delete Billed Shipment
// ============================================================================
router.delete('/billed-shipment/:trackingNo', async (req, res) => {
  try {
    const orgId = req.user?.orgId || req.headers['x-org-id'] || '';
    const result = await BilledShipment.deleteOne({
      orgId,
      trackingNo: req.params.trackingNo
    });

    if (result.deletedCount === 0) {
      return res.status(404).json({ success: false, message: 'Billed shipment not found' });
    }

    res.json({ success: true, message: 'Billed shipment removed successfully' });
  } catch (error) {
    console.error('❌ Delete billed shipment error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});
