// routes/tds_sections.js
// TDS Section master list — the named sections (with a default rate each) that
// show up in the invoice's TDS dropdown, e.g. "Commission or Brokerage [2%]".
// Mirrors Zoho Books' "Manage TDS" list. Org-scoped, auto-seeded on first read.

const express     = require('express');
const router      = express.Router();
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT } = require('../middleware/finance_jwt');

// Seed list — matches this org's actual configured Zoho TDS sections.
const DEFAULT_SECTIONS = [
  { name: 'Commission or Brokerage',          rate: 2 },
  { name: 'Commission or Brokerage (Reduced)', rate: 3.75 },
  { name: 'Dividend',                          rate: 10 },
  { name: 'Dividend (Reduced)',                rate: 7.5 },
  { name: 'Other Interest than securities',    rate: 10 },
];

// ─── GET /api/finance/tds-sections — list sections for current org ───────────
router.get('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    let sections = await db.collection('tdsSections').find({ orgId }).sort({ name: 1 }).toArray();

    if (sections.length === 0) {
      const now = new Date();
      const seeded = DEFAULT_SECTIONS.map(s => ({
        _id: new ObjectId(), orgId, name: s.name, rate: s.rate,
        createdAt: now, updatedAt: now,
      }));
      await db.collection('tdsSections').insertMany(seeded);
      sections = seeded;
    }

    return res.json({ success: true, data: { sections } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/tds-sections — add a custom section ───────────────────
router.post('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    const { name, rate } = req.body;
    if (!name || !name.trim()) return res.status(400).json({ success: false, message: 'name is required' });

    const now = new Date();
    const section = {
      _id: new ObjectId(), orgId,
      name: name.trim(),
      rate: parseFloat(rate) || 0,
      createdAt: now, updatedAt: now,
    };
    await db.collection('tdsSections').insertOne(section);
    return res.status(201).json({ success: true, data: { section } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── PUT /api/finance/tds-sections/:id — edit a section ──────────────────────
router.put('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    const { name, rate } = req.body;

    const update = { updatedAt: new Date() };
    if (name !== undefined) update.name = name.trim();
    if (rate !== undefined) update.rate = parseFloat(rate) || 0;

    const result = await db.collection('tdsSections').findOneAndUpdate(
      { _id: new ObjectId(req.params.id), orgId },
      { $set: update },
      { returnDocument: 'after' }
    );
    if (!result) return res.status(404).json({ success: false, message: 'Section not found' });
    return res.json({ success: true, data: { section: result } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── DELETE /api/finance/tds-sections/:id ─────────────────────────────────────
router.delete('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    const result = await db.collection('tdsSections').deleteOne({ _id: new ObjectId(req.params.id), orgId });
    if (result.deletedCount === 0) return res.status(404).json({ success: false, message: 'Section not found' });
    return res.json({ success: true, message: 'Section deleted' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
