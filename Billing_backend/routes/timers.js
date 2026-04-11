// ============================================================================
// TIMERS BACKEND — Time Tracking Module
// ============================================================================
// File: backend/routes/timers.js
// Register in app.js:
//   app.use('/api/finance/timers', require('./routes/timers'));
// ============================================================================

const express    = require('express');
const router     = express.Router();
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT } = require('../middleware/finance_jwt');

// ── helper: calculate elapsed seconds ────────────────────────────────────────
function calcElapsed(timer) {
  let elapsed = timer.elapsedSeconds || 0;
  if (timer.status === 'running' && timer.resumedAt) {
    elapsed += Math.floor((Date.now() - new Date(timer.resumedAt).getTime()) / 1000);
  } else if (timer.status === 'running' && timer.startedAt) {
    elapsed += Math.floor((Date.now() - new Date(timer.startedAt).getTime()) / 1000);
  }
  return elapsed;
}

// ── helper: seconds to hours ──────────────────────────────────────────────────
function secondsToHours(seconds) {
  return Math.round((seconds / 3600) * 100) / 100;
}

// ── auto-number for timesheets ────────────────────────────────────────────────
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
// GET /active — get all running/paused timers for current user in this org
// =============================================================================
router.get('/active', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const timers = await db.collection('timers').find({
      orgId,
      status: { $in: ['running', 'paused'] },
    }).sort({ startedAt: -1 }).toArray();

    // Attach live elapsed to each
    const enriched = timers.map(t => ({
      ...t,
      currentElapsedSeconds: calcElapsed(t),
      currentElapsedFormatted: formatDuration(calcElapsed(t)),
    }));

    res.json({ success: true, data: enriched });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /active/:userId — timers for specific staff member
// =============================================================================
router.get('/active/:userId', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const timers = await db.collection('timers').find({
      orgId,
      userId: req.params.userId,
      status: { $in: ['running', 'paused'] },
    }).sort({ startedAt: -1 }).toArray();

    const enriched = timers.map(t => ({
      ...t,
      currentElapsedSeconds: calcElapsed(t),
      currentElapsedFormatted: formatDuration(calcElapsed(t)),
    }));

    res.json({ success: true, data: enriched });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /start — start a new timer
// =============================================================================
router.post('/start', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const {
      projectId, projectName,
      taskId, taskName,
      userId, userName, userEmail,
      isBillable = true,
      notes = '',
    } = req.body;

    if (!projectId) return res.status(400).json({ success: false, message: 'projectId required' });

    // Verify project exists
    const project = await db.collection('projects').findOne({ _id: new ObjectId(projectId), orgId });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });

    // Check if user already has a running timer for this project+task
    const existing = await db.collection('timers').findOne({
      orgId,
      userId: userId || req.user.id || '',
      projectId,
      taskId: taskId || '',
      status: 'running',
    });
    if (existing) {
      return res.status(400).json({
        success: false,
        message: 'A timer is already running for this project/task. Stop it first.',
        data: existing,
      });
    }

    const now = new Date();
    const doc = {
      orgId,
      projectId,
      projectName: projectName || project.projectName || '',
      taskId:    taskId    || '',
      taskName:  taskName  || '',
      userId:    userId    || req.user.id  || '',
      userName:  userName  || req.user.email || '',
      userEmail: userEmail || req.user.email || '',
      isBillable: Boolean(isBillable),
      notes,
      status:         'running',
      startedAt:      now,
      resumedAt:      now,
      pausedAt:       null,
      stoppedAt:      null,
      elapsedSeconds: 0,
      createdBy: req.user.email,
      createdAt: now,
      updatedAt: now,
    };

    const result = await db.collection('timers').insertOne(doc);
    doc._id = result.insertedId;

    res.status(201).json({
      success: true,
      message: 'Timer started',
      data: { ...doc, currentElapsedSeconds: 0, currentElapsedFormatted: '00:00:00' },
    });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /:id/pause — pause a running timer
// =============================================================================
router.post('/:id/pause', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const timer = await db.collection('timers').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!timer) return res.status(404).json({ success: false, message: 'Timer not found' });
    if (timer.status !== 'running') return res.status(400).json({ success: false, message: 'Timer is not running' });

    const now = new Date();
    // Add time since last resume/start to elapsed
    let addedSeconds = 0;
    if (timer.resumedAt) {
      addedSeconds = Math.floor((now.getTime() - new Date(timer.resumedAt).getTime()) / 1000);
    } else if (timer.startedAt) {
      addedSeconds = Math.floor((now.getTime() - new Date(timer.startedAt).getTime()) / 1000);
    }
    const newElapsed = (timer.elapsedSeconds || 0) + addedSeconds;

    await db.collection('timers').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { status: 'paused', pausedAt: now, elapsedSeconds: newElapsed, updatedAt: now } }
    );

    res.json({
      success: true,
      message: 'Timer paused',
      data: {
        elapsedSeconds: newElapsed,
        elapsedFormatted: formatDuration(newElapsed),
      },
    });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /:id/resume — resume a paused timer
// =============================================================================
router.post('/:id/resume', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const timer = await db.collection('timers').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!timer) return res.status(404).json({ success: false, message: 'Timer not found' });
    if (timer.status !== 'paused') return res.status(400).json({ success: false, message: 'Timer is not paused' });

    const now = new Date();
    await db.collection('timers').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { status: 'running', resumedAt: now, pausedAt: null, updatedAt: now } }
    );

    res.json({ success: true, message: 'Timer resumed', data: { resumedAt: now } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /:id/stop — stop timer and auto-create timesheet entry
// =============================================================================
router.post('/:id/stop', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const timer = await db.collection('timers').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!timer) return res.status(404).json({ success: false, message: 'Timer not found' });
    if (timer.status === 'stopped') return res.status(400).json({ success: false, message: 'Timer already stopped' });

    const now = new Date();

    // Calculate final elapsed
    let finalElapsed = timer.elapsedSeconds || 0;
    if (timer.status === 'running') {
      const ref = timer.resumedAt || timer.startedAt;
      finalElapsed += Math.floor((now.getTime() - new Date(ref).getTime()) / 1000);
    }

    // Minimum 1 minute
    if (finalElapsed < 60) finalElapsed = 60;

    const finalHours = secondsToHours(finalElapsed);
    const { notes, isBillable, date } = req.body;

    // Mark timer as stopped
    await db.collection('timers').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { status: 'stopped', stoppedAt: now, elapsedSeconds: finalElapsed, updatedAt: now } }
    );

    // Auto-create timesheet entry
    const entryNumber = await nextTimesheetNumber(db, orgId);
    const entryDate = date ? new Date(date) : (timer.startedAt ? new Date(timer.startedAt) : now);

    const timesheetDoc = {
      entryNumber, orgId,
      projectId:   timer.projectId,
      projectName: timer.projectName,
      taskId:      timer.taskId    || '',
      taskName:    timer.taskName  || '',
      userId:      timer.userId    || '',
      userName:    timer.userName  || '',
      userEmail:   timer.userEmail || '',
      date:        entryDate,
      hours:       finalHours,
      isBillable:  isBillable !== undefined ? Boolean(isBillable) : timer.isBillable,
      notes:       notes || timer.notes || '',
      status:      'Unbilled',
      timerId:     timer._id.toString(),
      elapsedSeconds: finalElapsed,
      billedInvoiceId: null,
      approvedBy: null, approvedAt: null,
      rejectedBy: null, rejectedAt: null, rejectionReason: null,
      createdBy: req.user.email, createdAt: now, updatedAt: now,
    };

    const tsResult = await db.collection('timesheets').insertOne(timesheetDoc);
    timesheetDoc._id = tsResult.insertedId;

    // Update project totalLoggedHours
    if (timer.projectId) {
      try {
        await db.collection('projects').updateOne(
          { _id: new ObjectId(timer.projectId), orgId },
          { $inc: { totalLoggedHours: finalHours }, $set: { updatedAt: now } }
        );
      } catch (_) {}
    }

    // Delete the timer record (cleanup)
    await db.collection('timers').deleteOne({ _id: new ObjectId(req.params.id) });

    res.json({
      success: true,
      message: `Timer stopped. ${finalHours} hrs logged.`,
      data: {
        elapsedSeconds: finalElapsed,
        elapsedFormatted: formatDuration(finalElapsed),
        hours: finalHours,
        timesheetEntry: timesheetDoc,
      },
    });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// DELETE /:id — discard timer without creating timesheet
// =============================================================================
router.delete('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const timer = await db.collection('timers').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!timer) return res.status(404).json({ success: false, message: 'Timer not found' });
    await db.collection('timers').deleteOne({ _id: new ObjectId(req.params.id) });
    res.json({ success: true, message: 'Timer discarded' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /:id — get single timer with live elapsed
// =============================================================================
router.get('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId;
    const timer = await db.collection('timers').findOne({ _id: new ObjectId(req.params.id), orgId });
    if (!timer) return res.status(404).json({ success: false, message: 'Timer not found' });
    const elapsed = calcElapsed(timer);
    res.json({
      success: true,
      data: { ...timer, currentElapsedSeconds: elapsed, currentElapsedFormatted: formatDuration(elapsed) },
    });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// ── format seconds to HH:MM:SS ────────────────────────────────────────────────
function formatDuration(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return [h, m, s].map(v => String(v).padStart(2, '0')).join(':');
}

module.exports = router;