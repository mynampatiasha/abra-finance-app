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
    if (branchId !== '69eeecb21234dffba797bee4') {
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
    const draftedTrackingNos = new Set();
    for (const d of drafts) {
      if (d.items && Array.isArray(d.items)) {
        for (const item of d.items) {
          if (item.shipmentTrackingNumber) draftedTrackingNos.add(item.shipmentTrackingNumber);
          if (item.expenseId) draftedTrackingNos.add(item.expenseId);
        }
      }
    }

    // Also exclude already billed shipments (tracked separately)
    const billed = await BilledShipment.find({ orgId }).lean();
    const billedTrackingNos = new Set(billed.map(b => b.trackingNo));

    // Combined exclusion set
    const excludedSet = new Set([...draftedTrackingNos, ...billedTrackingNos]);

    const filteredShipments = shipments.filter(s => {
      const trackingNo = s.tracking_no || s.id;
      return !excludedSet.has(trackingNo?.toString());
    });

    res.json({
      success: true,
      count: filteredShipments.length,
      totalCount: shipments.length,
      draftCount: draftedTrackingNos.size,    // staging only
      billedCount: billedTrackingNos.size,    // billed only
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

    if (branchId !== '69eeecb21234dffba797bee4') {
      return res.status(403).json({ success: false, error: 'Automation feature is restricted to branch 69eeecb21234dffba797bee4 only.' });
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

    if (branchId !== '69eeecb21234dffba797bee4') {
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

    if (branchId !== '69eeecb21234dffba797bee4') {
      return res.status(403).json({ success: false, error: 'Restricted branch' });
    }

    const draft = await AutomationDraft.findOne({ _id: req.params.id, orgId, branchId }).lean();

    if (!draft) {
      return res.status(404).json({ success: false, error: 'Automation Draft not found in staging' });
    }

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

    // Store all tracking nos as billed
    const billedEntries = (draft.items || [])
      .filter(i => i.shipmentTrackingNumber)
      .map(i => ({
        orgId,
        trackingNo: i.shipmentTrackingNumber,
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

    if (branchId !== '69eeecb21234dffba797bee4') {
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
