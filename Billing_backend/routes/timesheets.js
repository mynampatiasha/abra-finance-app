// ============================================================================
// TIMESHEETS BACKEND — Time Tracking Module
// ============================================================================
// File: backend/routes/timesheets.js
// Register in app.js:
//   app.use('/api/finance/timesheets', require('./routes/timesheets'));
// ============================================================================

const express    = require('express');
const router     = express.Router();
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT } = require('../middleware/finance_jwt');

// ── auto-number ───────────────────────────────────────────────────────────────
async function nextTimesheetNumber(db, orgId) {
  const docs = await db.collection('timesheets')
    .find({ orgId, entryNumber: { $regex: '^TS\\d' } }, { projection: { entryNumber: 1 } })
    .toArray();
  let max = 0;
  for (const d of docs) {
    const n = parseInt((d.entryNumber || '').slice('TS'.length), 10);
    if (!isNaN(n) && n > max) max = n;
  }
  return `TS${String(max + 1).padStart(6, '0')}`;
}

// =============================================================================
// GET /stats
// =============================================================================
router.get('/stats', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { projectId } = req.query;
    const baseQuery = { orgId };
    if (projectId) baseQuery.projectId = projectId;

    const [total, unbilled, approved, billed, rejected] = await Promise.all([
      db.collection('timesheets').countDocuments({ ...baseQuery }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Unbilled' }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Approved' }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Billed' }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Rejected' }),
    ]);
    const totalHoursAgg = await db.collection('timesheets').aggregate([
      { $match: { ...baseQuery } },
      { $group: { _id: null, totalHours: { $sum: '$hours' }, billableHours: { $sum: { $cond: ['$isBillable', '$hours', 0] } } } },
    ]).toArray();
    res.json({ success: true, data: {
      total, unbilled, approved, billed, rejected,
      totalHours:    totalHoursAgg[0]?.totalHours    || 0,
      billableHours: totalHoursAgg[0]?.billableHours || 0,
    }});
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET / — list
// =============================================================================
router.get('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { status, projectId, userId, isBillable, search, page = 1, limit = 20, fromDate, toDate } = req.query;
    const query = { orgId };
    if (status)    query.status    = status;
    if (projectId) query.projectId = projectId;
    if (userId)    query.userId    = userId;
    if (isBillable !== undefined) query.isBillable = isBillable === 'true';
    if (fromDate || toDate) {
      query.date = {};
      if (fromDate) query.date.$gte = new Date(fromDate);
      if (toDate)   query.date.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { projectName: { $regex: search, $options: 'i' } },
        { taskName:    { $regex: search, $options: 'i' } },
        { userName:    { $regex: search, $options: 'i' } },
        { notes:       { $regex: search, $options: 'i' } },
        { entryNumber: { $regex: search, $options: 'i' } },
      ];
    }
    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const total = await db.collection('timesheets').countDocuments(query);
    const timesheets = await db.collection('timesheets').find(query).sort({ date: -1, createdAt: -1 }).skip(skip).limit(parseInt(limit)).toArray();
    res.json({ success: true, data: timesheets, pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /by-project/:projectId
// =============================================================================
router.get('/by-project/:projectId', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { status } = req.query;
    const query = { orgId, projectId: req.params.projectId };
    if (status) query.status = status;
    const entries = await db.collection('timesheets').find(query).sort({ date: -1 }).toArray();
    const totalHours = entries.reduce((s, e) => s + e.hours, 0);
    const billableHours = entries.filter(e => e.isBillable).reduce((s, e) => s + e.hours, 0);
    res.json({ success: true, data: { entries, totalHours, billableHours } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /:id
// =============================================================================
router.get('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!entry) return res.status(404).json({ success: false, message: 'Time entry not found' });
    res.json({ success: true, data: entry });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST / — create time entry
// =============================================================================
router.post('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const {
      projectId, projectName, taskId, taskName,
      userId, userName, userEmail,
      date, hours, isBillable = true, notes,
    } = req.body;
    if (!projectId)   return res.status(400).json({ success: false, message: 'projectId required' });
    if (!hours || hours <= 0) return res.status(400).json({ success: false, message: 'hours must be > 0' });

    // Verify project exists in this org
    const project = await db.collection('projects').findOne({ _id: new ObjectId(projectId), orgId });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });

    const entryNumber = await nextTimesheetNumber(db, orgId);
    const now = new Date();
    const doc = {
      entryNumber, orgId,
      projectId, projectName:  projectName  || project.projectName || '',
      taskId:    taskId    || '', taskName:  taskName   || '',
      userId:    userId    || '', userName:  userName   || '',
      userEmail: userEmail || '',
      date:      date ? new Date(date) : now,
      hours:     parseFloat(hours),
      isBillable: Boolean(isBillable),
      notes:     notes || '',
      status:    'Unbilled',
      billedInvoiceId: null,
      approvedBy: null, approvedAt: null,
      rejectedBy: null, rejectedAt: null, rejectionReason: null,
      createdBy: req.user.email, createdAt: now, updatedAt: now,
    };
    const result = await db.collection('timesheets').insertOne(doc);
    doc._id = result.insertedId;

    // Update project totalLoggedHours
    await db.collection('projects').updateOne(
      { _id: new ObjectId(projectId) },
      { $inc: { totalLoggedHours: parseFloat(hours) }, $set: { updatedAt: now } }
    );

    res.status(201).json({ success: true, message: 'Time entry created', data: doc });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PUT /:id — update
// =============================================================================
router.put('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!entry) return res.status(404).json({ success: false, message: 'Time entry not found' });
    if (entry.status === 'Billed')
      return res.status(400).json({ success: false, message: 'Cannot edit a billed time entry' });
    const $set = { updatedAt: new Date() };
    const fields = ['projectId','projectName','taskId','taskName','userId','userName','userEmail','notes'];
    for (const f of fields) { if (req.body[f] !== undefined) $set[f] = req.body[f]; }
    if (req.body.hours !== undefined) $set.hours = parseFloat(req.body.hours) || 0;
    if (req.body.isBillable !== undefined) $set.isBillable = Boolean(req.body.isBillable);
    if (req.body.date) $set.date = new Date(req.body.date);
    $set.status = 'Unbilled'; // reset to unbilled on edit
    await db.collection('timesheets').updateOne({ _id: new ObjectId(req.params.id) }, { $set });
    const updated = await db.collection('timesheets').findOne({ _id: new ObjectId(req.params.id) });
    res.json({ success: true, message: 'Time entry updated', data: updated });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PATCH /:id/approve
// =============================================================================
router.patch('/:id/approve', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!entry) return res.status(404).json({ success: false, message: 'Time entry not found' });
    if (entry.status === 'Billed')
      return res.status(400).json({ success: false, message: 'Entry already billed' });
    const now = new Date();
    await db.collection('timesheets').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { status: 'Approved', approvedBy: req.user.email, approvedAt: now, updatedAt: now } }
    );
    res.json({ success: true, message: 'Time entry approved' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PATCH /:id/reject
// =============================================================================
router.patch('/:id/reject', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { reason } = req.body;
    const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!entry) return res.status(404).json({ success: false, message: 'Time entry not found' });
    if (entry.status === 'Billed')
      return res.status(400).json({ success: false, message: 'Cannot reject a billed entry' });
    const now = new Date();
    await db.collection('timesheets').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { status: 'Rejected', rejectedBy: req.user.email, rejectedAt: now, rejectionReason: reason || '', updatedAt: now } }
    );
    res.json({ success: true, message: 'Time entry rejected' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PATCH /:id/mark-billed
// =============================================================================
router.patch('/:id/mark-billed', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { invoiceId } = req.body;
    const now = new Date();
    await db.collection('timesheets').updateOne(
      { _id: new ObjectId(req.params.id), orgId },
      { $set: { status: 'Billed', billedInvoiceId: invoiceId || null, updatedAt: now } }
    );
    res.json({ success: true, message: 'Time entry marked as billed' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// DELETE /:id
// =============================================================================
router.delete('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!entry) return res.status(404).json({ success: false, message: 'Time entry not found' });
    if (entry.status === 'Billed')
      return res.status(400).json({ success: false, message: 'Cannot delete a billed time entry' });
    await db.collection('timesheets').deleteOne({ _id: new ObjectId(req.params.id) });
    // Subtract from project hours
    if (entry.projectId) {
      await db.collection('projects').updateOne(
        { _id: new ObjectId(entry.projectId), orgId },
        { $inc: { totalLoggedHours: -entry.hours }, $set: { updatedAt: new Date() } }
      );
    }
    res.json({ success: true, message: 'Time entry deleted' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /import — bulk import
// =============================================================================
router.post('/import', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { timesheets = [] } = req.body;
    if (!timesheets.length) return res.status(400).json({ success: false, message: 'No timesheets provided' });
    let successCount = 0, failedCount = 0; const errors = [];
    for (let i = 0; i < timesheets.length; i++) {
      try {
        const t = timesheets[i];
        if (!t.projectId) throw new Error('projectId required');
        if (!t.hours || parseFloat(t.hours) <= 0) throw new Error('hours must be > 0');
        const entryNumber = await nextTimesheetNumber(db, orgId);
        const now = new Date();
        await db.collection('timesheets').insertOne({
          entryNumber, orgId,
          projectId:   t.projectId,   projectName: t.projectName || '',
          taskId:      t.taskId || '', taskName:    t.taskName || '',
          userId:      t.userId || '', userName:    t.userName || '',
          userEmail:   t.userEmail || '',
          date:        t.date ? new Date(t.date) : now,
          hours:       parseFloat(t.hours),
          isBillable:  t.isBillable !== undefined ? Boolean(t.isBillable) : true,
          notes:       t.notes || '', status: 'Unbilled',
          billedInvoiceId: null, approvedBy: null, approvedAt: null,
          rejectedBy: null, rejectedAt: null, rejectionReason: null,
          createdBy: req.user.email, createdAt: now, updatedAt: now,
        });
        successCount++;
      } catch (e) { failedCount++; errors.push(`Row ${i+1}: ${e.message}`); }
    }
    res.json({ success: true, data: { totalProcessed: timesheets.length, successCount, failedCount, errors } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /export/all
// =============================================================================
router.get('/export/all', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const query = { orgId };
    if (req.query.status)    query.status    = req.query.status;
    if (req.query.projectId) query.projectId = req.query.projectId;
    const timesheets = await db.collection('timesheets').find(query).sort({ date: -1 }).toArray();
    res.json({ success: true, data: timesheets });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

module.exports = router;
