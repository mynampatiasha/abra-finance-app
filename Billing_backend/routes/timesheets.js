// ============================================================================
// TIMESHEETS BACKEND � UPDATED (Complete with Submit workflow + COA + Reports)
// ============================================================================
// File: backend/routes/timesheets.js
// ============================================================================

const express    = require('express');
const router     = express.Router();
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT } = require('../middleware/finance_jwt');

// -- auto-number ----------------------------------------------------------------
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

// -- COA helper -----------------------------------------------------------------
async function postUnbilledRevenue(db, orgId, { hours, hourlyRate, entryNumber, projectName, entryId, date, reverse = false }) {
  try {
    const amount = hours * (hourlyRate || 0);
    if (amount <= 0) return;
    const coa = await db.collection('chart_of_accounts').findOne({
      orgId,
      accountName: 'Unbilled Revenue',
      isActive: true,
    });
    if (!coa) return;
    const debit  = reverse ? 0 : 0;
    const credit = reverse ? 0 : amount;
    const drBal  = reverse ? amount : 0;
    const crBal  = reverse ? 0 : amount;

    await db.collection('account_transactions').insertOne({
      orgId,
      accountId:   coa._id,
      accountName: 'Unbilled Revenue',
      accountType: 'Income',
      date:        new Date(date),
      description: `${reverse ? 'Reversal - ' : ''}Time logged - ${entryNumber} - ${projectName}`,
      referenceType:   'Timesheet',
      referenceId:     entryId,
      referenceNumber: entryNumber,
      debit:  drBal,
      credit: crBal,
      createdAt: new Date(),
    });
    await db.collection('chart_of_accounts').updateOne(
      { _id: coa._id },
      { $inc: { closingBalance: crBal - drBal }, $set: { updatedAt: new Date() } }
    );
  } catch (err) {
    console.error('COA Unbilled Revenue error:', err.message);
  }
}

// =============================================================================
// GET /stats
// =============================================================================
router.get('/stats', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const branchFilter = req.branchFilter || {};
    const { projectId } = req.query;
    const baseQuery = { orgId, ...branchFilter };
    if (projectId) baseQuery.projectId = projectId;

    const [total, unbilled, submitted, approved, billed, rejected] = await Promise.all([
      db.collection('timesheets').countDocuments({ ...baseQuery }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Unbilled' }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Submitted' }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Approved' }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Billed' }),
      db.collection('timesheets').countDocuments({ ...baseQuery, status: 'Rejected' }),
    ]);
    const totalHoursAgg = await db.collection('timesheets').aggregate([
      { $match: { ...baseQuery } },
      { $group: { _id: null, totalHours: { $sum: '$hours' }, billableHours: { $sum: { $cond: ['$isBillable', '$hours', 0] } } } },
    ]).toArray();
    res.json({ success: true, data: {
      total, unbilled, submitted, approved, billed, rejected,
      totalHours:    totalHoursAgg[0]?.totalHours    || 0,
      billableHours: totalHoursAgg[0]?.billableHours || 0,
    }});
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /weekly-summary � group by day of week
// =============================================================================
router.get('/weekly-summary', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { projectId, fromDate, toDate } = req.query;

    // Default to current week Mon�Sun
    const now = new Date();
    const dayOfWeek = now.getDay(); // 0=Sun
    const monday = new Date(now);
    monday.setDate(now.getDate() - (dayOfWeek === 0 ? 6 : dayOfWeek - 1));
    monday.setHours(0, 0, 0, 0);
    const sunday = new Date(monday);
    sunday.setDate(monday.getDate() + 6);
    sunday.setHours(23, 59, 59, 999);

    const from = fromDate ? new Date(fromDate) : monday;
    const to   = toDate   ? new Date(toDate)   : sunday;

    const query = { orgId, date: { $gte: from, $lte: to } };
    if (projectId) query.projectId = projectId;

    const entries = await db.collection('timesheets').find(query).sort({ date: 1 }).toArray();

    // Group by date
    const days = {};
    for (let d = new Date(from); d <= to; d.setDate(d.getDate() + 1)) {
      const key = d.toISOString().split('T')[0];
      days[key] = { date: key, totalHours: 0, billableHours: 0, entries: [] };
    }
    for (const e of entries) {
      const key = new Date(e.date).toISOString().split('T')[0];
      if (days[key]) {
        days[key].totalHours    += e.hours;
        days[key].billableHours += e.isBillable ? e.hours : 0;
        days[key].entries.push(e);
      }
    }

    const weekTotal    = entries.reduce((s, e) => s + e.hours, 0);
    const weekBillable = entries.filter(e => e.isBillable).reduce((s, e) => s + e.hours, 0);

    res.json({ success: true, data: {
      days: Object.values(days),
      weekTotal, weekBillable,
      weekNonBillable: weekTotal - weekBillable,
      fromDate: from, toDate: to,
    }});
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /staff-utilization
// =============================================================================
router.get('/staff-utilization', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const branchFilter = req.branchFilter || {};
    const { fromDate, toDate } = req.query;
    const query = { orgId, ...branchFilter };
    if (fromDate || toDate) {
      query.date = {};
      if (fromDate) query.date.$gte = new Date(fromDate);
      if (toDate)   query.date.$lte = new Date(toDate);
    }
    const agg = await db.collection('timesheets').aggregate([
      { $match: query },
      { $group: {
        _id: '$userId',
        userName:      { $first: '$userName' },
        userEmail:     { $first: '$userEmail' },
        totalHours:    { $sum: '$hours' },
        billableHours: { $sum: { $cond: ['$isBillable', '$hours', 0] } },
        entryCount:    { $sum: 1 },
      }},
      { $sort: { totalHours: -1 } },
    ]).toArray();

    const result = agg.map(s => ({
      ...s,
      nonBillableHours:  s.totalHours - s.billableHours,
      utilizationPercent: s.totalHours > 0 ? Math.round((s.billableHours / s.totalHours) * 100) : 0,
    }));

    res.json({ success: true, data: result });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /unbilled-report � approved entries not yet billed
// =============================================================================
router.get('/unbilled-report', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const entries = await db.collection('timesheets').find({
      orgId, isBillable: true, status: 'Approved',
    }).sort({ projectId: 1, date: 1 }).toArray();

    // Group by project
    const projects = {};
    for (const e of entries) {
      if (!projects[e.projectId]) {
        projects[e.projectId] = {
          projectId: e.projectId, projectName: e.projectName,
          totalHours: 0, entries: [],
        };
      }
      projects[e.projectId].totalHours += e.hours;
      projects[e.projectId].entries.push(e);
    }

    const totalUnbilledHours = entries.reduce((s, e) => s + e.hours, 0);
    res.json({ success: true, data: {
      projects: Object.values(projects),
      totalUnbilledHours,
      totalEntries: entries.length,
    }});
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET / � list
// =============================================================================
router.get('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const branchFilter = req.branchFilter || {};
    const { status, projectId, userId, isBillable, search, page = 1, limit = 20, fromDate, toDate } = req.query;
    const query = { orgId, ...branchFilter };
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
    const branchFilter = req.branchFilter || {};
    const { status } = req.query;
    const query = { orgId, ...branchFilter, projectId: req.params.projectId };
    if (status) query.status = status;
    const entries = await db.collection('timesheets').find(query).sort({ date: -1 }).toArray();
    const totalHours    = entries.reduce((s, e) => s + e.hours, 0);
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
// POST / � create time entry
// =============================================================================
router.post('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const branchFilter = req.branchFilter || {};
    const {
      projectId, projectName, taskId, taskName,
      userId, userName, userEmail,
      date, hours, isBillable = true, notes,
      submitForApproval = false,
    } = req.body;
    if (!projectId)   return res.status(400).json({ success: false, message: 'projectId required' });
    if (!hours || hours <= 0) return res.status(400).json({ success: false, message: 'hours must be > 0' });

    const project = await db.collection('projects').findOne({ _id: new ObjectId(projectId), orgId });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });

    const entryNumber = await nextTimesheetNumber(db, orgId);
    const now = new Date();
    const status = submitForApproval ? 'Submitted' : 'Unbilled';

    const doc = {
      entryNumber, orgId, branchId: branchFilter.branchId || null,
      projectId, projectName:  projectName  || project.projectName || '',
      taskId:    taskId    || '', taskName:  taskName   || '',
      userId:    userId    || '', userName:  userName   || '',
      userEmail: userEmail || '',
      date:      date ? new Date(date) : now,
      hours:     parseFloat(hours),
      isBillable: Boolean(isBillable),
      notes:     notes || '',
      status,
      billedInvoiceId: null,
      approvedBy: null, approvedAt: null,
      rejectedBy: null, rejectedAt: null, rejectionReason: null,
      submittedAt: submitForApproval ? now : null,
      createdBy: req.user.email, createdAt: now, updatedAt: now,
    };
    const result = await db.collection('timesheets').insertOne(doc);
    doc._id = result.insertedId;

    // Update project totalLoggedHours
    await db.collection('projects').updateOne(
      { _id: new ObjectId(projectId) },
      { $inc: { totalLoggedHours: parseFloat(hours) }, $set: { updatedAt: now } }
    );

    // COA: Post to Unbilled Revenue
    await postUnbilledRevenue(db, orgId, {
      hours: parseFloat(hours),
      hourlyRate: project.hourlyRate || 0,
      entryNumber,
      projectName: project.projectName,
      entryId: result.insertedId.toString(),
      date: doc.date,
    });

    res.status(201).json({ success: true, message: 'Time entry created', data: doc });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PUT /:id � update
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
// PATCH /:id/submit � submit for approval
// =============================================================================
router.patch('/:id/submit', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!entry) return res.status(404).json({ success: false, message: 'Time entry not found' });
    if (!['Unbilled', 'Rejected'].includes(entry.status))
      return res.status(400).json({ success: false, message: `Cannot submit entry with status: ${entry.status}` });
    const now = new Date();
    await db.collection('timesheets').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { status: 'Submitted', submittedAt: now, updatedAt: now } }
    );
    res.json({ success: true, message: 'Time entry submitted for approval' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /bulk-submit
// =============================================================================
router.post('/bulk-submit', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { ids = [] } = req.body;
    if (!ids.length) return res.status(400).json({ success: false, message: 'No IDs provided' });
    const now = new Date();
    let success = 0, failed = 0;
    for (const id of ids) {
      try {
        const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(id), orgId });
        if (entry && ['Unbilled', 'Rejected'].includes(entry.status)) {
          await db.collection('timesheets').updateOne(
            { _id: new ObjectId(id) },
            { $set: { status: 'Submitted', submittedAt: now, updatedAt: now } }
          );
          success++;
        } else { failed++; }
      } catch (_) { failed++; }
    }
    res.json({ success: true, data: { success, failed, total: ids.length } });
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
// POST /bulk-reject
// =============================================================================
router.post('/bulk-reject', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const { ids = [], reason = '' } = req.body;
    if (!ids.length) return res.status(400).json({ success: false, message: 'No IDs provided' });
    const now = new Date();
    let success = 0, failed = 0;
    for (const id of ids) {
      try {
        const entry = await db.collection('timesheets').findOne({ _id: new ObjectId(id), orgId });
        if (entry && entry.status !== 'Billed') {
          await db.collection('timesheets').updateOne(
            { _id: new ObjectId(id) },
            { $set: { status: 'Rejected', rejectedBy: req.user.email, rejectedAt: now, rejectionReason: reason, updatedAt: now } }
          );
          success++;
        } else { failed++; }
      } catch (_) { failed++; }
    }
    res.json({ success: true, data: { success, failed, total: ids.length } });
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
// POST /import � bulk import
// =============================================================================
router.post('/import', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const branchFilter = req.branchFilter || {};
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
          entryNumber, orgId, branchId: branchFilter.branchId || null,
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
          submittedAt: null,
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
    const query = { orgId, ...branchFilter };
    if (req.query.status)    query.status    = req.query.status;
    if (req.query.projectId) query.projectId = req.query.projectId;
    const timesheets = await db.collection('timesheets').find(query).sort({ date: -1 }).toArray();
    res.json({ success: true, data: timesheets });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

module.exports = router;