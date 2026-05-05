// ============================================================================
// PROJECTS BACKEND � UPDATED (Timer + Dashboard + Task fields + Clone)
// ============================================================================
// File: backend/routes/projects.js
// ============================================================================

const express    = require('express');
const router     = express.Router();
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT } = require('../middleware/finance_jwt');

// -- COA helper ----------------------------------------------------------------
async function postTransactionToCOA(db, orgId, {
  accountName, accountType, transactionDate, description,
  referenceType, referenceId, referenceNumber, debit = 0, credit = 0,
  branchId = null,
}) {
  try {
    const coa = await db.collection('chart_of_accounts').findOne({ orgId, accountName, isActive: true });
    if (!coa) return;
    await db.collection('chart_of_accounts').updateOne(
      { _id: coa._id },
      { $inc: { closingBalance: debit - credit }, $set: { updatedAt: new Date() } }
    );
    await db.collection('account_transactions').insertOne({
      orgId, branchId, accountId: coa._id, accountName, accountType,
      date: new Date(transactionDate),
      description, referenceType, referenceId, referenceNumber,
      debit, credit, createdAt: new Date(),
    });
  } catch (err) { console.error('COA post error (projects):', err.message); }
}

// -- seed COA accounts ---------------------------------------------------------
async function seedProjectCOAAccounts(db, orgId) {
  const accounts = [
    { accountName: 'Unbilled Revenue',    accountType: 'Income', accountCode: 'INC-UNBILLED', isSystemAccount: true },
    { accountName: 'Project Revenue',     accountType: 'Income', accountCode: 'INC-PROJECT',  isSystemAccount: true },
    { accountName: 'Accounts Receivable', accountType: 'Asset',  accountCode: 'ASSET-AR',     isSystemAccount: true },
  ];
  for (const acc of accounts) {
    const exists = await db.collection('chart_of_accounts').findOne({ orgId, accountName: acc.accountName });
    if (!exists) {
      await db.collection('chart_of_accounts').insertOne({
        ...acc, orgId,
        description: `System account � ${acc.accountName}`,
        currency: 'INR', openingBalance: 0, closingBalance: 0,
        isActive: true, createdAt: new Date(), updatedAt: new Date(),
      });
    }
  }
}

// -- auto-number ---------------------------------------------------------------
async function nextProjectNumber(db, orgId) {
  const docs = await db.collection('projects')
    .find({ orgId, projectNumber: { $regex: '^PROJ\\d' } }, { projection: { projectNumber: 1 } })
    .toArray();
  let max = 0;
  for (const d of docs) {
    const n = parseInt((d.projectNumber || '').slice('PROJ'.length), 10);
    if (!isNaN(n) && n > max) max = n;
  }
  return `PROJ${String(max + 1).padStart(6, '0')}`;
}

// -- billing amount calculator -------------------------------------------------
function calcBillableAmount(project, entries) {
  switch (project.billingMethod) {
    case 'Fixed Cost': return project.fixedAmount || 0;
    case 'Based on Project Hours':
      return entries.reduce((s, e) => s + e.hours, 0) * (project.hourlyRate || 0);
    case 'Based on Task Hours':
      return entries.reduce((sum, e) => {
        const task = (project.tasks || []).find(t => t.taskId === e.taskId);
        return sum + e.hours * (task?.hourlyRate || 0);
      }, 0);
    case 'Based on Staff Hours':
      return entries.reduce((sum, e) => {
        const member = (project.staff || []).find(s => s.userId === e.userId);
        return sum + e.hours * (member?.hourlyRate || 0);
      }, 0);
    default: return 0;
  }
}

// =============================================================================
// GET /stats
// =============================================================================
router.get('/stats', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    await seedProjectCOAAccounts(db, orgId);
    const [total, active, completed, inactive, onHold] = await Promise.all([
      db.collection('projects').countDocuments({ orgId, ...branchFilter }),
      db.collection('projects').countDocuments({ orgId, status: 'Active' }),
      db.collection('projects').countDocuments({ orgId, status: 'Completed' }),
      db.collection('projects').countDocuments({ orgId, status: 'Inactive' }),
      db.collection('projects').countDocuments({ orgId, status: 'On Hold' }),
    ]);
    const billableAgg = await db.collection('timesheets').aggregate([
      { $match: { orgId, ...branchFilter, isBillable: true, status: { $in: ['Approved', 'Billed'] } } },
      { $group: { _id: null, totalHours: { $sum: '$hours' } } },
    ]).toArray();
    const unbilledAgg = await db.collection('timesheets').aggregate([
      { $match: { orgId, ...branchFilter, isBillable: true, status: 'Approved' } },
      { $group: { _id: null, totalHours: { $sum: '$hours' } } },
    ]).toArray();
    // Active timers count
    const activeTimers = await db.collection('timers').countDocuments({ orgId, ...branchFilter, status: 'running' });
    res.json({ success: true, data: {
      total, active, completed, inactive, onHold,
      totalBillableHours: billableAgg[0]?.totalHours || 0,
      unbilledHours: unbilledAgg[0]?.totalHours || 0,
      activeTimers,
    }});
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET / � list
// =============================================================================
router.get('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const { status, billingMethod, customerId, search, page = 1, limit = 20, fromDate, toDate } = req.query;
    const query = { orgId, ...branchFilter };
    if (status)        query.status        = status;
    if (billingMethod) query.billingMethod = billingMethod;
    if (customerId)    query.customerId    = customerId;
    if (fromDate || toDate) {
      query.startDate = {};
      if (fromDate) query.startDate.$gte = new Date(fromDate);
      if (toDate)   query.startDate.$lte = new Date(toDate);
    }
    if (search) {
      query.$or = [
        { projectName:   { $regex: search, $options: 'i' } },
        { projectNumber: { $regex: search, $options: 'i' } },
        { customerName:  { $regex: search, $options: 'i' } },
      ];
    }
    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const total = await db.collection('projects').countDocuments(query);
    const projects = await db.collection('projects').find(query).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).toArray();
    for (const p of projects) {
      const agg = await db.collection('timesheets').aggregate([
        { $match: { orgId, projectId: p._id.toString(), status: 'Approved', isBillable: true } },
        { $group: { _id: null, hours: { $sum: '$hours' } } },
      ]).toArray();
      p.unbilledHours = agg[0]?.hours || 0;
      // Active timers for this project
      p.activeTimerCount = await db.collection('timers').countDocuments({ orgId, projectId: p._id.toString(), status: 'running' });
    }
    res.json({ success: true, data: projects, pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /:id/dashboard � project dashboard data
// =============================================================================
router.get('/:id/dashboard', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const project = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });

    // All timesheet entries for this project
    const entries = await db.collection('timesheets').find({ orgId, ...branchFilter, projectId: req.params.id }).toArray();
    const approvedEntries = entries.filter(e => e.status === 'Approved' && e.isBillable);
    const billedEntries   = entries.filter(e => e.status === 'Billed');

    const totalLoggedHours  = entries.reduce((s, e) => s + e.hours, 0);
    const unbilledHours     = approvedEntries.reduce((s, e) => s + e.hours, 0);
    const billedHours       = billedEntries.reduce((s, e) => s + e.hours, 0);
    const budgetHours       = project.budgetAmount > 0 && project.budgetType === 'Hours' ? project.budgetAmount : 0;
    const burntPercent      = budgetHours > 0 ? Math.min(100, Math.round((totalLoggedHours / budgetHours) * 100)) : 0;

    // Revenue vs cost
    const unbilledAmount = calcBillableAmount(project, approvedEntries);
    const totalBilledAmount = project.totalBilledAmount || 0;

    // Staff breakdown
    const staffMap = {};
    for (const e of entries) {
      const key = e.userId || 'unassigned';
      if (!staffMap[key]) staffMap[key] = { userId: key, userName: e.userName || 'Unassigned', totalHours: 0, billableHours: 0 };
      staffMap[key].totalHours += e.hours;
      if (e.isBillable) staffMap[key].billableHours += e.hours;
    }

    // Task breakdown
    const taskMap = {};
    for (const t of (project.tasks || [])) {
      const taskEntries = entries.filter(e => e.taskId === t.taskId);
      taskMap[t.taskId] = {
        taskId:            t.taskId,
        taskName:          t.taskName,
        status:            t.status || 'Open',
        estimatedHours:    t.estimatedHours || 0,
        loggedHours:       taskEntries.reduce((s, e) => s + e.hours, 0),
        completionPercent: t.completionPercent || 0,
        deadline:          t.deadline || null,
        assignedStaff:     t.assignedStaffName || '',
      };
    }

    // Active timers
    const activeTimers = await db.collection('timers').find({ orgId, projectId: req.params.id, status: { $in: ['running', 'paused'] } }).toArray();

    // Recent entries
    const recentEntries = entries.sort((a, b) => new Date(b.date) - new Date(a.date)).slice(0, 10);

    // Budget utilization
    const budgetAmount   = project.budgetAmount || 0;
    const budgetUsed     = project.budgetType === 'Hours' ? totalLoggedHours : totalBilledAmount;
    const budgetPercent  = budgetAmount > 0 ? Math.min(100, Math.round((budgetUsed / budgetAmount) * 100)) : 0;

    res.json({ success: true, data: {
      project,
      totalLoggedHours, unbilledHours, billedHours,
      budgetHours, burntPercent,
      budgetAmount, budgetUsed, budgetPercent,
      unbilledAmount, totalBilledAmount,
      remainingBudget: Math.max(0, budgetAmount - budgetUsed),
      staffBreakdown:  Object.values(staffMap),
      taskBreakdown:   Object.values(taskMap),
      activeTimers,
      recentEntries,
      entryCounts: {
        total:     entries.length,
        unbilled:  entries.filter(e => e.status === 'Unbilled').length,
        submitted: entries.filter(e => e.status === 'Submitted').length,
        approved:  entries.filter(e => e.status === 'Approved').length,
        billed:    entries.filter(e => e.status === 'Billed').length,
        rejected:  entries.filter(e => e.status === 'Rejected').length,
      },
    }});
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /:id
// =============================================================================
router.get('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const project = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });
    const tsAgg = await db.collection('timesheets').aggregate([
      { $match: { orgId, projectId: req.params.id } },
      { $group: { _id: '$status', hours: { $sum: '$hours' }, count: { $sum: 1 } } },
    ]).toArray();
    project.timesheetSummary = tsAgg;
    project.activeTimerCount = await db.collection('timers').countDocuments({ orgId, ...branchFilter, projectId: req.params.id, status: 'running' });
    res.json({ success: true, data: project });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST / � create
// =============================================================================
router.post('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    await seedProjectCOAAccounts(db, orgId);
    const {
      projectName, customerId, customerName, customerEmail, customerPhone,
      description, billingMethod, fixedAmount, hourlyRate,
      budgetType, budgetAmount, currency = 'INR',
      startDate, endDate, status = 'Active',
      tasks = [], staff = [], notes, termsAndConditions,
    } = req.body;
    if (!projectName)   return res.status(400).json({ success: false, message: 'projectName required' });
    if (!customerId)    return res.status(400).json({ success: false, message: 'customerId required' });
    if (!billingMethod) return res.status(400).json({ success: false, message: 'billingMethod required' });
    const validMethods = ['Fixed Cost','Based on Project Hours','Based on Task Hours','Based on Staff Hours'];
    if (!validMethods.includes(billingMethod))
      return res.status(400).json({ success: false, message: `billingMethod must be one of: ${validMethods.join(', ')}` });
    const projectNumber = await nextProjectNumber(db, orgId);
    const now = new Date();
    const doc = {
      projectNumber, projectName, orgId,
      customerId, customerName: customerName || '',
      customerEmail: customerEmail || '', customerPhone: customerPhone || '',
      description: description || '', billingMethod,
      fixedAmount:  parseFloat(fixedAmount)  || 0,
      hourlyRate:   parseFloat(hourlyRate)   || 0,
      budgetType:   budgetType   || 'Cost',
      budgetAmount: parseFloat(budgetAmount) || 0,
      currency, startDate: startDate ? new Date(startDate) : now,
      endDate: endDate ? new Date(endDate) : null,
      status,
      tasks: (tasks || []).map((t, i) => ({
        taskId:            t.taskId || `TASK-${Date.now()}-${i}`,
        taskName:          t.taskName || '',
        hourlyRate:        parseFloat(t.hourlyRate) || 0,
        estimatedHours:    parseFloat(t.estimatedHours) || 0,
        description:       t.description || '',
        status:            t.status || 'Open',
        completionPercent: parseFloat(t.completionPercent) || 0,
        deadline:          t.deadline ? new Date(t.deadline) : null,
        assignedStaffId:   t.assignedStaffId || '',
        assignedStaffName: t.assignedStaffName || '',
      })),
      staff: (staff || []).map(s => ({
        userId:    s.userId    || '',
        name:      s.name      || '',
        email:     s.email     || '',
        role:      s.role      || 'staff',
        hourlyRate: parseFloat(s.hourlyRate) || 0,
      })),
      notes: notes || '', termsAndConditions: termsAndConditions || '',
      totalLoggedHours: 0, totalBilledAmount: 0, invoicesGenerated: [],
      orgId, branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
      createdBy: req.user.email, createdAt: now, updatedAt: now,
    };
    const result = await db.collection('projects').insertOne(doc);
    doc._id = result.insertedId;
    res.status(201).json({ success: true, message: 'Project created', data: doc });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PUT /:id � update
// =============================================================================
router.put('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const existing = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!existing) return res.status(404).json({ success: false, message: 'Project not found' });
    const $set = { updatedAt: new Date() };
    const fields = ['projectName','customerId','customerName','customerEmail','customerPhone',
      'description','billingMethod','budgetType','currency','status','notes','termsAndConditions'];
    for (const f of fields) { if (req.body[f] !== undefined) $set[f] = req.body[f]; }
    const numFields = ['fixedAmount','hourlyRate','budgetAmount'];
    for (const f of numFields) { if (req.body[f] !== undefined) $set[f] = parseFloat(req.body[f]) || 0; }
    if (req.body.startDate) $set.startDate = new Date(req.body.startDate);
    if (req.body.endDate !== undefined) $set.endDate = req.body.endDate ? new Date(req.body.endDate) : null;
    if (req.body.tasks) {
      $set.tasks = req.body.tasks.map((t, i) => ({
        taskId:            t.taskId || `TASK-${Date.now()}-${i}`,
        taskName:          t.taskName || '',
        hourlyRate:        parseFloat(t.hourlyRate) || 0,
        estimatedHours:    parseFloat(t.estimatedHours) || 0,
        description:       t.description || '',
        status:            t.status || 'Open',
        completionPercent: parseFloat(t.completionPercent) || 0,
        deadline:          t.deadline ? new Date(t.deadline) : null,
        assignedStaffId:   t.assignedStaffId || '',
        assignedStaffName: t.assignedStaffName || '',
      }));
    }
    if (req.body.staff) {
      $set.staff = req.body.staff.map(s => ({
        userId:    s.userId    || '',
        name:      s.name      || '',
        email:     s.email     || '',
        role:      s.role      || 'staff',
        hourlyRate: parseFloat(s.hourlyRate) || 0,
      }));
    }
    await db.collection('projects').updateOne({ _id: new ObjectId(req.params.id) }, { $set });
    const updated = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id) });
    res.json({ success: true, message: 'Project updated', data: updated });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PATCH /:id/status
// =============================================================================
router.patch('/:id/status', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const { status } = req.body;
    const validStatuses = ['Active','Inactive','Completed','On Hold'];
    if (!validStatuses.includes(status))
      return res.status(400).json({ success: false, message: `status must be one of: ${validStatuses.join(', ')}` });
    const result = await db.collection('projects').updateOne(
      { _id: new ObjectId(req.params.id), orgId, ...branchFilter }, { $set: { status, updatedAt: new Date() } }
    );
    if (result.matchedCount === 0) return res.status(404).json({ success: false, message: 'Project not found' });
    res.json({ success: true, message: `Project status updated to ${status}` });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// PATCH /:id/task/:taskId/status � update single task status
// =============================================================================
router.patch('/:id/task/:taskId/status', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const { status, completionPercent } = req.body;
    const project = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });
    const tasks = (project.tasks || []).map(t => {
      if (t.taskId === req.params.taskId) {
        return {
          ...t,
          status: status || t.status,
          completionPercent: completionPercent !== undefined ? parseFloat(completionPercent) : t.completionPercent,
          updatedAt: new Date(),
        };
      }
      return t;
    });
    await db.collection('projects').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { tasks, updatedAt: new Date() } }
    );
    res.json({ success: true, message: 'Task updated' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /:id/clone � clone a project
// =============================================================================
router.post('/:id/clone', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const project = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });
    const projectNumber = await nextProjectNumber(db, orgId);
    const now = new Date();
    const { _id, ...rest } = project;
    const cloned = {
      ...rest,
      branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
      projectNumber,
      projectName: `Copy of ${project.projectName}`,
      status: 'Active',
      totalLoggedHours: 0,
      totalBilledAmount: 0,
      invoicesGenerated: [],
      tasks: (project.tasks || []).map(t => ({ ...t, completionPercent: 0, status: 'Open' })),
      createdBy: req.user.email,
      createdAt: now,
      updatedAt: now,
    };
    const result = await db.collection('projects').insertOne(cloned);
    cloned._id = result.insertedId;
    res.status(201).json({ success: true, message: 'Project cloned', data: cloned });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /:id/unbilled-hours
// =============================================================================
router.get('/:id/unbilled-hours', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const project = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });
    const entries = await db.collection('timesheets').find({
      orgId, projectId: req.params.id, isBillable: true, status: 'Approved',
    }).toArray();
    const totalHours  = entries.reduce((s, e) => s + e.hours, 0);
    const totalAmount = calcBillableAmount(project, entries);
    res.json({ success: true, data: { entries, totalHours, totalAmount } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /:id/generate-invoice
// =============================================================================
router.post('/:id/generate-invoice', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const project = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });
    const entries = await db.collection('timesheets').find({
      orgId, projectId: req.params.id, isBillable: true, status: 'Approved',
    }).toArray();
    if (entries.length === 0)
      return res.status(400).json({ success: false, message: 'No approved unbilled hours to invoice' });

    let lineItems = []; let subTotal = 0;
    if (project.billingMethod === 'Fixed Cost') {
      subTotal = project.fixedAmount || 0;
      lineItems = [{ itemDetails: `${project.projectName} � Fixed Price`, quantity: 1, rate: subTotal, discount: 0, discountType: 'percentage', amount: subTotal }];
    } else if (project.billingMethod === 'Based on Project Hours') {
      const totalHours = entries.reduce((s, e) => s + e.hours, 0);
      const amount = totalHours * (project.hourlyRate || 0); subTotal = amount;
      lineItems = [{ itemDetails: `${project.projectName} � ${totalHours.toFixed(2)} hrs @ ?${project.hourlyRate}/hr`, quantity: totalHours, rate: project.hourlyRate || 0, discount: 0, discountType: 'percentage', amount }];
    } else if (project.billingMethod === 'Based on Task Hours') {
      const taskMap = {};
      for (const e of entries) {
        const task = (project.tasks || []).find(t => t.taskId === e.taskId);
        const key = e.taskId || 'general';
        if (!taskMap[key]) taskMap[key] = { name: task?.taskName || e.taskName || 'General', rate: task?.hourlyRate || 0, hours: 0 };
        taskMap[key].hours += e.hours;
      }
      for (const [, t] of Object.entries(taskMap)) {
        const amount = t.hours * t.rate; subTotal += amount;
        lineItems.push({ itemDetails: `${t.name} � ${t.hours.toFixed(2)} hrs @ ?${t.rate}/hr`, quantity: t.hours, rate: t.rate, discount: 0, discountType: 'percentage', amount });
      }
    } else if (project.billingMethod === 'Based on Staff Hours') {
      const staffMap = {};
      for (const e of entries) {
        const member = (project.staff || []).find(s => s.userId === e.userId);
        const key = e.userId || 'general';
        if (!staffMap[key]) staffMap[key] = { name: member?.name || e.userName || 'Staff', rate: member?.hourlyRate || 0, hours: 0 };
        staffMap[key].hours += e.hours;
      }
      for (const [, s] of Object.entries(staffMap)) {
        const amount = s.hours * s.rate; subTotal += amount;
        lineItems.push({ itemDetails: `${s.name} � ${s.hours.toFixed(2)} hrs @ ?${s.rate}/hr`, quantity: s.hours, rate: s.rate, discount: 0, discountType: 'percentage', amount });
      }
    }

    const gstRate = parseFloat(req.body.gstRate) || 18;
    const gstAmount = subTotal * gstRate / 100;
    const totalAmount = subTotal + gstAmount;

    // Generate invoice number
    const invDocs = await db.collection('invoices').find({ orgId, invoiceNumber: { $regex: '^INV' } }, { projection: { invoiceNumber: 1 } }).toArray();
    let maxInv = 0;
    for (const d of invDocs) {
      const n = parseInt((d.invoiceNumber || '').slice('INV'.length), 10);
      if (!isNaN(n) && n > maxInv) maxInv = n;
    }
    const invNum = `INV${String(maxInv + 1).padStart(6, '0')}`;

    const now = new Date();
    const dueDate = new Date(now); dueDate.setDate(dueDate.getDate() + 30);
    const invoice = {
      invoiceNumber: invNum, orgId,
      branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
      customerId: project.customerId, customerName: project.customerName,
      customerEmail: project.customerEmail, customerPhone: project.customerPhone || '',
      projectId: req.params.id, projectNumber: project.projectNumber,
      invoiceDate: now, dueDate, items: lineItems,
      subTotal, gstRate, gstAmount, tdsRate: 0, tdsAmount: 0, tcsRate: 0, tcsAmount: 0,
      totalAmount, amountPaid: 0, amountDue: totalAmount, status: 'UNPAID', terms: 'Net 30',
      notes: `Generated from project: ${project.projectName}`,
      createdBy: req.user.email, createdAt: now, updatedAt: now,
    };
    const invResult = await db.collection('invoices').insertOne(invoice);
    invoice._id = invResult.insertedId;
    const entryIds = entries.map(e => e._id);
    await db.collection('timesheets').updateMany(
      { _id: { $in: entryIds } },
      { $set: { status: 'Billed', billedInvoiceId: invResult.insertedId.toString(), updatedAt: now } }
    );
    const totalBilledHours = entries.reduce((s, e) => s + e.hours, 0);
    await db.collection('projects').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $inc: { totalBilledAmount: totalAmount, totalLoggedHours: 0 }, $push: { invoicesGenerated: invResult.insertedId.toString() }, $set: { updatedAt: now } }
    );
    // COA: Debit AR, Credit Project Revenue, reverse Unbilled Revenue
    await postTransactionToCOA(db, orgId, { accountName: 'Accounts Receivable', accountType: 'Asset', transactionDate: now, description: `Invoice ${invNum} � ${project.projectName}`, referenceType: 'Invoice', referenceId: invResult.insertedId.toString(), referenceNumber: invNum, debit: totalAmount, credit: 0 });
    await postTransactionToCOA(db, orgId, { accountName: 'Project Revenue', accountType: 'Income', transactionDate: now, description: `Invoice ${invNum} � ${project.projectName}`, referenceType: 'Invoice', referenceId: invResult.insertedId.toString(), referenceNumber: invNum, debit: 0, credit: subTotal });
    // Reverse Unbilled Revenue for billed entries
    await postTransactionToCOA(db, orgId, { accountName: 'Unbilled Revenue', accountType: 'Income', transactionDate: now, description: `Reversal on billing � ${invNum} � ${project.projectName}`, referenceType: 'Invoice', referenceId: invResult.insertedId.toString(), referenceNumber: invNum, debit: subTotal, credit: 0 });
    res.status(201).json({ success: true, message: `Invoice ${invNum} generated successfully`, data: { invoiceId: invResult.insertedId, invoiceNumber: invNum, totalAmount, entriesBilled: entries.length } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// DELETE /:id
// =============================================================================
router.delete('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const project = await db.collection('projects').findOne({ _id: new ObjectId(req.params.id), orgId, ...branchFilter });
    if (!project) return res.status(404).json({ success: false, message: 'Project not found' });
    if (project.invoicesGenerated?.length > 0)
      return res.status(400).json({ success: false, message: 'Cannot delete project with generated invoices. Close the project instead.' });
    await db.collection('timesheets').deleteMany({ orgId, projectId: req.params.id });
    await db.collection('timers').deleteMany({ orgId, projectId: req.params.id });
    await db.collection('projects').deleteOne({ _id: new ObjectId(req.params.id) });
    res.json({ success: true, message: 'Project deleted' });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// POST /import
// =============================================================================
router.post('/import', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    await seedProjectCOAAccounts(db, orgId);
    const { projects = [] } = req.body;
    if (!projects.length) return res.status(400).json({ success: false, message: 'No projects provided' });
    let successCount = 0, failedCount = 0; const errors = [];
    for (let i = 0; i < projects.length; i++) {
      try {
        const p = projects[i];
        if (!p.projectName) throw new Error('projectName required');
        if (!p.billingMethod) throw new Error('billingMethod required');
        const projectNumber = await nextProjectNumber(db, orgId);
        const now = new Date();
        await db.collection('projects').insertOne({
          projectNumber, orgId,
          branchId: req.branchIds?.length > 0 ? req.branchIds[0] : null,
          projectName: p.projectName,
          customerId: p.customerId || '', customerName: p.customerName || '',
          customerEmail: p.customerEmail || '', customerPhone: p.customerPhone || '',
          description: p.description || '', billingMethod: p.billingMethod,
          fixedAmount: parseFloat(p.fixedAmount) || 0, hourlyRate: parseFloat(p.hourlyRate) || 0,
          budgetType: p.budgetType || 'Cost', budgetAmount: parseFloat(p.budgetAmount) || 0,
          currency: p.currency || 'INR',
          startDate: p.startDate ? new Date(p.startDate) : now,
          endDate: p.endDate ? new Date(p.endDate) : null,
          status: p.status || 'Active', tasks: [], staff: [], notes: p.notes || '',
          totalLoggedHours: 0, totalBilledAmount: 0, invoicesGenerated: [],
          createdBy: req.user.email, createdAt: now, updatedAt: now,
        });
        successCount++;
      } catch (e) { failedCount++; errors.push(`Row ${i+1}: ${e.message}`); }
    }
    res.json({ success: true, data: { totalProcessed: projects.length, successCount, failedCount, errors } });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

// =============================================================================
// GET /export/all
// =============================================================================
router.get('/export/all', verifyFinanceJWT, async (req, res) => {
  try {
    const db = req.db; const orgId = req.user.orgId; const branchFilter = req.branchFilter || {};
    const query = { orgId, ...branchFilter };
    if (req.query.status)        query.status        = req.query.status;
    if (req.query.billingMethod) query.billingMethod = req.query.billingMethod;
    const projects = await db.collection('projects').find(query).sort({ createdAt: -1 }).toArray();
    res.json({ success: true, data: projects });
  } catch (err) { res.status(500).json({ success: false, message: err.message }); }
});

module.exports = router;
