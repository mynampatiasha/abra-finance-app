// backend/routes/tms.js
// ============================================================================
// 🎫 TICKET MANAGEMENT SYSTEM (TMS) - COMPLETE BACKEND API
// ============================================================================
// FINAL VERSION:
// - Employees fetched from employee_admins collection
// - Email-based ticket filtering (users see tickets assigned to their email)
// - Admin support for viewing all tickets
// - Proper route ordering to avoid conflicts
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// ============================================================================
// 📁 FILE UPLOAD CONFIGURATION (Multer)
// ============================================================================
const uploadDir = path.join(__dirname, '../uploads/tickets');

if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
  console.log('✅ Created tickets upload directory:', uploadDir);
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const uniqueName = `${Date.now()}_${file.originalname}`;
    cb(null, uniqueName);
  }
});

const upload = multer({
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (req, file, cb) => {
    const allowedTypes = /jpeg|jpg|png|gif|pdf|doc|docx|txt/;
    const extname = allowedTypes.test(path.extname(file.originalname).toLowerCase());
    const mimetype = allowedTypes.test(file.mimetype);
    
    if (extname && mimetype) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Allowed: JPG, PNG, PDF, DOC, DOCX, TXT'));
    }
  }
});

// ============================================================================
// 🎫 VALID TICKET STATUSES
// ============================================================================
const VALID_STATUSES = ['Open', 'In Progress', 'Approved', 'Rejected', 'Reply', 'closed'];

// ============================================================================
// 🔐 HELPER: GET CURRENT USER FROM JWT (billing_users, org-scoped)
// ============================================================================
async function getCurrentEmployee(db, user) {
  console.log('🔍 Finding billing user for:', user.email, '/ org:', user.orgId);

  const found = await db.collection('billing_users').findOne({
    email: user.email.toLowerCase(),
    status: 'active',
    'organizations.orgId': user.orgId,
  });

  if (found) {
    const org = (found.organizations || []).find(o => o.orgId === user.orgId);
    // Normalise to the shape the rest of the code expects
    found.name_parson = found.name;
    found.username    = found.name;
    found.role        = org?.role || 'staff';
    console.log('✅ Found billing user:', found.name, '/ role:', found.role);
    return found;
  }

  console.log('❌ Billing user not found for email:', user.email);
  return null;
}

// ============================================================================
// 🔐 HELPER: CHECK IF USER IS ADMIN (billing roles: owner / admin)
// ============================================================================
function isAdmin(employee) {
  return employee && (employee.role === 'owner' || employee.role === 'admin');
}


router.post('/internal/create', async (req, res) => {
  try {
    const INTERNAL_SECRET = process.env.INTERNAL_API_SECRET || 'abra_internal_2026';

    // Verify secret key
    const providedKey = req.headers['x-internal-key'];
    if (providedKey !== INTERNAL_SECRET) {
      return res.status(403).json({ success: false, error: 'Unauthorized' });
    }

    console.log('\n🔒 INTERNAL TICKET CREATE (from PHP CRM)');
    console.log('─'.repeat(80));

    let {
      subject, message, priority, timeline,
      assigned_name, assigned_email,
      creator_name, creator_email,
      ticket_number
    } = req.body;

    // ✅ CRITICAL FIX: Ensure creator_email always has a value
    if (!creator_email || creator_email.trim() === '') {
      creator_email = 'crm@abra-travels.com';
      creator_name = creator_name || 'CRM System';
      console.log('⚠️  No creator_email provided, using default:', creator_email);
    }

    if (!subject || !message || !assigned_email) {
      console.log('❌ Validation failed:');
      console.log('   subject:', subject ? 'OK' : 'MISSING');
      console.log('   message:', message ? 'OK' : 'MISSING');
      console.log('   assigned_email:', assigned_email ? 'OK' : 'MISSING');
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    // Find assigned employee by email
    const assignedEmployee = await req.db.collection('employee_admins').findOne({
      email: assigned_email.toLowerCase()
    });

    // Find creator employee by email
    const creatorEmployee = await req.db.collection('employee_admins').findOne({
      email: creator_email ? creator_email.toLowerCase() : null
    });

    const timelineMinutes = parseInt(timeline) || 1440;
    const deadline = new Date();
    deadline.setMinutes(deadline.getMinutes() + timelineMinutes);

    // Generate ticket number if not provided
    let finalTicketNumber = ticket_number;
    if (!finalTicketNumber) {
      const allTickets = await req.db.collection('tickets')
        .find({ ticket_number: { $regex: '^TICKET\\d' } }, { projection: { ticket_number: 1 } })
        .toArray();
      let maxId = 0;
      for (const t of allTickets) {
        const n = parseInt((t.ticket_number || '').slice('TICKET'.length), 10);
        if (!isNaN(n) && n > maxId) maxId = n;
      }
      finalTicketNumber = `TICKET${String(maxId + 1).padStart(6, '0')}`;
    }

    const newTicket = {
      ticket_number: finalTicketNumber,
      name: creator_name || 'CRM System',
      creator_email: creator_email ? creator_email.toLowerCase() : 'crm@abra-travels.com',
      assigned_email: assigned_email.toLowerCase(),
      subject,
      message,
      priority: priority || 'medium',
      timeline: timelineMinutes,
      deadline,
      status: 'Open',
      attachment: null,
      assigned_to: assignedEmployee ? assignedEmployee._id : null,
      created_by: creatorEmployee ? creatorEmployee._id : null,
      source: 'crm',   // mark it came from PHP CRM
      created_at: new Date(),
      updated_at: new Date()
    };

    const result = await req.db.collection('tickets').insertOne(newTicket);

    console.log('✅ Internal ticket created:', finalTicketNumber);
    console.log('   Creator:', creator_name, '/', creator_email);
    console.log('   Assigned to:', assigned_name, '/', assigned_email);
    console.log('─'.repeat(80) + '\n');

    res.status(201).json({
      success: true,
      message: 'Ticket created successfully',
      ticket_number: finalTicketNumber,
      data: { ...newTicket, _id: result.insertedId }
    });

  } catch (error) {
    console.error('❌ Internal ticket creation error:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// 🔥 SPECIFIC ROUTES FIRST (Must come before dynamic :id routes)
// ============================================================================

// ============================================================================
// 📋 GET ALL EMPLOYEES (FROM billing_users — org-scoped)
// ============================================================================
router.get('/employees', async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    console.log('\n📋 FETCH BILLING USERS FOR ORG:', orgId);
    console.log('─'.repeat(80));

    const users = await req.db.collection('billing_users').find(
      { 'organizations.orgId': orgId, status: 'active' },
      {
        projection: {
          _id: 1,
          name: 1,
          email: 1,
          phone: 1,
          organizations: 1,
        }
      }
    ).sort({ name: 1 }).toArray();

    // Normalise to the shape raise_ticket.dart expects
    const data = users.map(u => {
      const org = (u.organizations || []).find(o => o.orgId === orgId);
      return {
        _id:        u._id,
        name_parson: u.name,   // keep same field name the UI reads
        username:   u.name,
        email:      u.email,
        phone:      u.phone,
        role:       org?.role || 'staff',
      };
    });

    console.log(`✅ Found ${data.length} billing users for org ${orgId}`);
    console.log('─'.repeat(80) + '\n');

    res.json({ success: true, data });
  } catch (error) {
    console.error('❌ Error fetching billing users:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch employees', message: error.message });
  }
});

// ============================================================================
// 📊 GET TICKET STATISTICS
// ============================================================================
router.get('/stats', async (req, res) => {
  try {
    console.log('\n📊 FETCH TICKET STATISTICS');
    console.log('─'.repeat(80));
    
    const currentEmployee = await getCurrentEmployee(req.db, req.user);
    
    if (!currentEmployee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    const userIsAdmin = isAdmin(currentEmployee);
    const baseQuery = { org_id: req.user.orgId };
    
    // Filter by email if not admin
    if (!userIsAdmin) {
      baseQuery.assigned_email = req.user.email.toLowerCase();
    }
    
    const stats = {
      total: 0,
      open: 0,
      in_progress: 0,
      closed: 0,
      high_priority: 0,
      unassigned: 0
    };
    
    const results = await req.db.collection('tickets').aggregate([
      { $match: baseQuery },
      {
        $facet: {
          total: [{ $count: 'count' }],
          open: [{ $match: { status: 'Open' } }, { $count: 'count' }],
          in_progress: [{ $match: { status: 'In Progress' } }, { $count: 'count' }],
          closed: [{ $match: { status: 'closed' } }, { $count: 'count' }],
          high_priority: [{ $match: { priority: 'High' } }, { $count: 'count' }],
          unassigned: [{ $match: { assigned_to: null } }, { $count: 'count' }]
        }
      }
    ]).toArray();
    
    if (results.length > 0) {
      const data = results[0];
      stats.total = data.total[0]?.count || 0;
      stats.open = data.open[0]?.count || 0;
      stats.in_progress = data.in_progress[0]?.count || 0;
      stats.closed = data.closed[0]?.count || 0;
      stats.high_priority = data.high_priority[0]?.count || 0;
      stats.unassigned = data.unassigned[0]?.count || 0;
    }
    
    console.log('✅ Statistics:', stats);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: stats,
      isAdmin: userIsAdmin
    });
    
  } catch (error) {
    console.error('❌ Error fetching statistics:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch statistics',
      message: error.message
    });
  }
});

// ============================================================================
// 📋 GET CLOSED TICKETS
// ============================================================================
router.get('/closed', async (req, res) => {
  try {
    console.log('\n📋 FETCH CLOSED TICKETS');
    console.log('─'.repeat(80));
    
    const { dateFrom, dateTo, admin } = req.query;
    const currentEmployee = await getCurrentEmployee(req.db, req.user);
    
    if (!currentEmployee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    const userIsAdmin = isAdmin(currentEmployee);
    const query = { status: 'closed', org_id: req.user.orgId };
    
    // Filter by email if not admin (unless admin flag is set)
    if (!userIsAdmin && admin !== 'true') {
      query.assigned_email = req.user.email.toLowerCase();
    }
    
    // Date range filter
    if (dateFrom || dateTo) {
      query.updated_at = {};
      if (dateFrom) query.updated_at.$gte = new Date(dateFrom);
      if (dateTo) {
        const endDate = new Date(dateTo);
        endDate.setHours(23, 59, 59, 999);
        query.updated_at.$lte = endDate;
      }
    }
    
    const tickets = await req.db.collection('tickets').aggregate([
      { $match: query },
      {
        $lookup: {
          from: 'employee_admins',
          localField: 'assigned_to',
          foreignField: '_id',
          as: 'assigned_employee'
        }
      },
      {
        $lookup: {
          from: 'employee_admins',
          localField: 'created_by',
          foreignField: '_id',
          as: 'creator_employee'
        }
      },
      {
        $addFields: {
          assigned_to_name: { $arrayElemAt: ['$assigned_employee.name_parson', 0] },
          assigned_to_email: { $arrayElemAt: ['$assigned_employee.email', 0] },
          created_by_name: { $arrayElemAt: ['$creator_employee.name_parson', 0] }
        }
      },
      { $project: { assigned_employee: 0, creator_employee: 0 } },
      { $sort: { updated_at: -1 } }
    ]).toArray();
    
    console.log(`✅ Found ${tickets.length} closed tickets`);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: tickets,
      count: tickets.length,
      isAdmin: userIsAdmin
    });
    
  } catch (error) {
    console.error('❌ Error fetching closed tickets:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch closed tickets',
      message: error.message
    });
  }
});

// ============================================================================
// ➕ CREATE NEW TICKET
// ============================================================================
router.post('/', upload.single('attachment'), async (req, res) => {
  try {
    console.log('\n➕ CREATE NEW TICKET');
    console.log('─'.repeat(80));
    console.log('User Email:', req.user.email);
    
    const { subject, message, priority, timeline, assigned_to, status } = req.body;
    
    if (!subject || !message || !priority || !timeline || !assigned_to) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields'
      });
    }
    
    const currentEmployee = await getCurrentEmployee(req.db, req.user);
    
    if (!currentEmployee) {
      return res.status(404).json({
        success: false,
        error: 'Employee not found'
      });
    }
    
    const assignedEmployee = await req.db.collection('billing_users').findOne({
      _id: new ObjectId(assigned_to),
      'organizations.orgId': req.user.orgId,
    });
    
    if (!assignedEmployee) {
      return res.status(404).json({
        success: false,
        error: 'Assigned user not found in your organization'
      });
    }
    
    // Find the last ticket number to generate the next sequential ID
    const allTickets = await req.db.collection('tickets')
      .find({ ticket_number: { $regex: '^TICKET\\d' } }, { projection: { ticket_number: 1 } })
      .toArray();
    let nextId = 1;
    let maxId = 0;
    for (const t of allTickets) {
      const n = parseInt((t.ticket_number || '').slice('TICKET'.length), 10);
      if (!isNaN(n) && n > maxId) maxId = n;
    }
    nextId = maxId + 1;

    const ticket_number = `TICKET${String(nextId).padStart(6, '0')}`;
    
    const timelineMinutes = parseInt(timeline);
    const deadline = new Date();
    deadline.setMinutes(deadline.getMinutes() + timelineMinutes);
    
    const newTicket = {
      ticket_number,
      name: currentEmployee.name_parson || currentEmployee.username,
      creator_email: currentEmployee.email.toLowerCase(),
      assigned_email: assignedEmployee.email.toLowerCase(), // 🔥 Email for filtering
      subject,
      message,
      priority,
      timeline: timelineMinutes,
      deadline: deadline,
      status: status || 'Open',
      attachment: req.file ? req.file.filename : null,
      assigned_to: new ObjectId(assigned_to),
      created_by: currentEmployee._id,
      org_id: req.user.orgId,   // 🔒 org isolation
      created_at: new Date(),
      updated_at: new Date()
    };
    
    const result = await req.db.collection('tickets').insertOne(newTicket);
    
    console.log('✅ Ticket created:', ticket_number);
    console.log('   Assigned to:', assignedEmployee.email);
    console.log('─'.repeat(80) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'Ticket created successfully',
      data: {
        ...newTicket,
        _id: result.insertedId
      }
    });
    
  } catch (error) {
    console.error('❌ Error creating ticket:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create ticket',
      message: error.message
    });
  }
});

// ============================================================================
// 📋 GET TICKETS (EMAIL-BASED FILTERING)
// ============================================================================
router.get('/', async (req, res) => {
  try {
    console.log('\n📋 FETCH TICKETS (EMAIL-BASED FILTERING)');
    console.log('─'.repeat(80));
    
    const { status, priority, dateFrom, dateTo, admin } = req.query;
    
    const currentEmployee = await getCurrentEmployee(req.db, req.user);
    
    if (!currentEmployee) {
      console.error('❌ Employee not found for email:', req.user.email);
      return res.status(404).json({
        success: false,
        error: 'Employee not found',
        message: 'Your employee account could not be found.'
      });
    }
    
    const userIsAdmin = isAdmin(currentEmployee);
    console.log('User Email:', req.user.email);
    console.log('User Name:', currentEmployee.name_parson || currentEmployee.username);
    console.log('Role:', currentEmployee.role);
    console.log('Is Admin:', userIsAdmin);
    console.log('Admin flag:', admin);
    
    const query = {};
    
    // 🔒 Always scope to current org (new tickets have org_id; old ones without it are excluded)
    query.org_id = req.user.orgId;

    // 🔥 CRITICAL: Filter by assigned email (unless admin flag is set)
    if (!userIsAdmin && admin !== 'true') {
      if (req.query.raised_by_me === 'true') {
        // Tickets raised BY this user, filtered to only show actioned ones
        query.creator_email = { $regex: new RegExp(`^${req.user.email}$`, 'i') };
        query.status = { $in: ['Approved', 'Rejected', 'Reply'] };
        console.log('📤 Filtering by creator_email (raised by me):', req.user.email);
      } else {
        query.assigned_email = req.user.email.toLowerCase();
        console.log('🔒 Filtering by assigned_email:', req.user.email);
      }
    } else if (admin === 'true') {
      console.log('👑 Admin mode: Showing ALL tickets');
    }
    
    // Status filter (skip if raised_by_me already set status)
    if (status && req.query.raised_by_me !== 'true') {
      if (status === 'active') {
        query.status = { $in: ['Open', 'In Progress'] };
      } else {
        query.status = status;
      }
    }
    
    // Priority filter
    if (priority) {
      query.priority = priority;
    }
    
    // Date range filter
    if (dateFrom || dateTo) {
      query.created_at = {};
      if (dateFrom) query.created_at.$gte = new Date(dateFrom);
      if (dateTo) {
        const endDate = new Date(dateTo);
        endDate.setHours(23, 59, 59, 999);
        query.created_at.$lte = endDate;
      }
    }
    
    console.log('Query:', JSON.stringify(query, null, 2));
    
    const tickets = await req.db.collection('tickets').aggregate([
      { $match: query },
      {
        $lookup: {
          from: 'employee_admins',
          localField: 'assigned_to',
          foreignField: '_id',
          as: 'assigned_employee'
        }
      },
      {
        $lookup: {
          from: 'employee_admins',
          localField: 'created_by',
          foreignField: '_id',
          as: 'creator_employee'
        }
      },
      {
        $addFields: {
          assigned_to_name: { $arrayElemAt: ['$assigned_employee.name_parson', 0] },
          assigned_to_email: { $arrayElemAt: ['$assigned_employee.email', 0] },
          created_by_name: { $arrayElemAt: ['$creator_employee.name_parson', 0] },
          created_by_email: { $arrayElemAt: ['$creator_employee.email', 0] }
        }
      },
      { $project: { assigned_employee: 0, creator_employee: 0 } },
      { $sort: { created_at: -1 } }
    ]).toArray();
    
    console.log(`✅ Found ${tickets.length} tickets`);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: tickets,
      count: tickets.length,
      isAdmin: userIsAdmin,
      userEmail: req.user.email
    });
    
  } catch (error) {
    console.error('❌ Error fetching tickets:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch tickets',
      message: error.message
    });
  }
});

// ============================================================================
// 🔥 DYNAMIC ROUTES (Must come AFTER specific routes)
// ============================================================================

// ============================================================================
// 🔍 GET SINGLE TICKET
// ============================================================================
router.get('/:id', async (req, res) => {
  try {
    console.log('\n🔍 FETCH SINGLE TICKET');
    console.log('─'.repeat(80));
    
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid ticket ID format'
      });
    }
    
    const ticket = await req.db.collection('tickets').aggregate([
      { $match: { _id: new ObjectId(id) } },
      {
        $lookup: {
          from: 'employee_admins',
          localField: 'assigned_to',
          foreignField: '_id',
          as: 'assigned_employee'
        }
      },
      {
        $lookup: {
          from: 'employee_admins',
          localField: 'created_by',
          foreignField: '_id',
          as: 'creator_employee'
        }
      },
      {
        $addFields: {
          assigned_to_name: { $arrayElemAt: ['$assigned_employee.name_parson', 0] },
          assigned_to_email: { $arrayElemAt: ['$assigned_employee.email', 0] },
          created_by_name: { $arrayElemAt: ['$creator_employee.name_parson', 0] },
          created_by_email: { $arrayElemAt: ['$creator_employee.email', 0] }
        }
      },
      { $project: { assigned_employee: 0, creator_employee: 0 } }
    ]).toArray();
    
    if (!ticket || ticket.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found'
      });
    }
    
    console.log('✅ Found ticket:', ticket[0].ticket_number);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: ticket[0]
    });
    
  } catch (error) {
    console.error('❌ Error fetching ticket:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch ticket',
      message: error.message
    });
  }
});

// ============================================================================
// ✏️ UPDATE TICKET
// ============================================================================
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const updates = req.body;
 
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ success: false, error: 'Invalid ticket ID format' });
    }
 
    const ticket = await req.db.collection('tickets').findOne({ _id: new ObjectId(id) });
    if (!ticket) {
      return res.status(404).json({ success: false, error: 'Ticket not found' });
    }
 
    // Get current employee for replied_by
    const currentEmployee = await getCurrentEmployee(req.db, req.user);
 
    const updateData = { updated_at: new Date() };
    const allowedFields = ['status', 'priority', 'subject', 'message', 'timeline', 'assigned_to'];
 
    for (const field of allowedFields) {
      if (updates[field] !== undefined) {
        if (field === 'assigned_to' && updates[field]) {
          const newEmp = await req.db.collection('employee_admins').findOne({
            _id: new ObjectId(updates[field])
          });
          if (newEmp) {
            updateData.assigned_to = new ObjectId(updates[field]);
            updateData.assigned_email = newEmp.email.toLowerCase();
          }
        } else if (field === 'timeline' && updates[field]) {
          const mins = parseInt(updates[field]);
          updateData.timeline = mins;
          const newDeadline = new Date();
          newDeadline.setMinutes(newDeadline.getMinutes() + mins);
          updateData.deadline = newDeadline;
        } else if (field === 'status') {
          if (VALID_STATUSES.includes(updates[field])) {
            updateData.status = updates[field];
          } else {
            return res.status(400).json({
              success: false,
              error: `Invalid status. Valid values: ${VALID_STATUSES.join(', ')}`
            });
          }
        } else {
          updateData[field] = updates[field];
        }
      }
    }
 
    // ── Reply / Approve / Reject message fields ────────────────────────────
    // When status changes to Approved, Rejected, or Reply,
    // the Flutter client sends reply_subject + reply_message
    if (updates.reply_message !== undefined) {
      updateData.reply_message   = updates.reply_message;
      updateData.reply_subject   = updates.reply_subject || null;
      updateData.replied_by      = currentEmployee
          ? (currentEmployee.name_parson || currentEmployee.username)
          : req.user.email;
      updateData.replied_at      = new Date();
    }
 
    const result = await req.db.collection('tickets').updateOne(
      { _id: new ObjectId(id) },
      { $set: updateData }
    );
 
    if (result.modifiedCount === 0) {
      return res.status(400).json({ success: false, error: 'No changes made' });
    }
 
    res.json({ success: true, message: 'Ticket updated successfully' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// 🔄 REASSIGN TICKET (Admin only)
// ============================================================================
router.post('/:id/reassign', async (req, res) => {
  try {
    console.log('\n🔄 REASSIGN TICKET');
    console.log('─'.repeat(80));
    
    const { id } = req.params;
    const { new_employee_id } = req.body;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid ticket ID format'
      });
    }
    
    const currentEmployee = await getCurrentEmployee(req.db, req.user);
    
    if (!currentEmployee || !isAdmin(currentEmployee)) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Only admins can reassign tickets'
      });
    }
    
    const ticket = await req.db.collection('tickets').findOne({
      _id: new ObjectId(id)
    });
    
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found'
      });
    }
    
    let newAssignedTo = null;
    let newAssignedEmail = null;
    let newAssignedName = 'Unassigned';
    
    if (new_employee_id && new_employee_id !== '0') {
      if (!ObjectId.isValid(new_employee_id)) {
        return res.status(400).json({
          success: false,
          error: 'Invalid employee ID format'
        });
      }
      
      newAssignedTo = new ObjectId(new_employee_id);
      
      const newEmployee = await req.db.collection('billing_users').findOne({
        _id: newAssignedTo,
        'organizations.orgId': req.user.orgId,
      });
      
      if (newEmployee) {
        newAssignedName = newEmployee.name || newEmployee.name_parson || newEmployee.username;
        newAssignedEmail = newEmployee.email.toLowerCase();
      }
    }
    
    const result = await req.db.collection('tickets').updateOne(
      { _id: new ObjectId(id) },
      {
        $set: {
          assigned_to: newAssignedTo,
          assigned_email: newAssignedEmail, // 🔥 Update email
          updated_at: new Date()
        }
      }
    );
    
    if (result.modifiedCount === 0) {
      return res.status(400).json({
        success: false,
        error: 'Reassignment failed'
      });
    }
    
    console.log('✅ Ticket reassigned to:', newAssignedName);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Ticket reassigned successfully',
      new_assigned_name: newAssignedName,
      new_assigned_email: newAssignedEmail
    });
    
  } catch (error) {
    console.error('❌ Error reassigning ticket:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to reassign ticket',
      message: error.message
    });
  }
});

// ============================================================================
// 🔄 REOPEN TICKET
// ============================================================================
router.post('/:id/reopen', async (req, res) => {
  try {
    console.log('\n🔄 REOPEN TICKET');
    console.log('─'.repeat(80));
    
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid ticket ID format'
      });
    }
    
    const ticket = await req.db.collection('tickets').findOne({
      _id: new ObjectId(id)
    });
    
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found'
      });
    }
    
    if (ticket.status !== 'closed') {
      return res.status(400).json({
        success: false,
        error: 'Only closed tickets can be reopened'
      });
    }
    
    const result = await req.db.collection('tickets').updateOne(
      { _id: new ObjectId(id) },
      { $set: { status: 'Open', updated_at: new Date() } }
    );
    
    if (result.modifiedCount === 0) {
      return res.status(400).json({
        success: false,
        error: 'Failed to reopen ticket'
      });
    }
    
    console.log('✅ Ticket reopened:', ticket.ticket_number);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Ticket reopened successfully'
    });
    
  } catch (error) {
    console.error('❌ Error reopening ticket:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to reopen ticket',
      message: error.message
    });
  }
});

// ============================================================================
// 🗑️ DELETE TICKET (Admin only)
// ============================================================================
router.delete('/:id', async (req, res) => {
  try {
    console.log('\n🗑️ DELETE TICKET');
    console.log('─'.repeat(80));
    
    const { id } = req.params;
    
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid ticket ID format'
      });
    }
    
    const currentEmployee = await getCurrentEmployee(req.db, req.user);
    
    if (!currentEmployee || !isAdmin(currentEmployee)) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Only admins can delete tickets'
      });
    }
    
    const ticket = await req.db.collection('tickets').findOne({
      _id: new ObjectId(id)
    });
    
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found'
      });
    }
    
    const result = await req.db.collection('tickets').deleteOne({
      _id: new ObjectId(id)
    });
    
    if (result.deletedCount === 0) {
      return res.status(400).json({
        success: false,
        error: 'Failed to delete ticket'
      });
    }
    
    // Delete attachment file if exists
    if (ticket.attachment) {
      const filePath = path.join(uploadDir, ticket.attachment);
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        console.log('✅ Deleted attachment:', ticket.attachment);
      }
    }
    
    console.log('✅ Ticket deleted:', ticket.ticket_number);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Ticket deleted successfully'
    });
    
  } catch (error) {
    console.error('❌ Error deleting ticket:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete ticket',
      message: error.message
    });
  }
});

module.exports = router;