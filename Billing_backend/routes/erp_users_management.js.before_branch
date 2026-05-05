// routes/erp_users_management.js  (Finance version)
// CRUD for billing_users within the caller's org only.
// Org isolation: every query filters by req.user.orgId

const express  = require('express');
const router   = express.Router();
const bcrypt   = require('bcryptjs');
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT, requireOwnerOrAdmin } = require('../middleware/finance_jwt');

const SALT = 12;
const hash = p => bcrypt.hash(p, SALT);

// ─── GET /api/finance/users  (list users in MY org only) ─────────────────────
router.get('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;

    // Only return users who belong to caller's org
    const users = await db.collection('billing_users').find({
      'organizations.orgId': orgId,
    }).toArray();

    const sanitized = users.map(({ passwordHash, ...rest }) => rest);
    return res.json({ success: true, data: sanitized });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── GET /api/finance/users/:id ───────────────────────────────────────────────
router.get('/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    const user  = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.params.id),
      'organizations.orgId': orgId, // ← org isolation
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });
    const { passwordHash, ...rest } = user;
    return res.json({ success: true, data: rest });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/users  (add user to my org) ───────────────────────────
router.post('/', verifyFinanceJWT, requireOwnerOrAdmin, async (req, res) => {
  try {
    const db          = req.db;
    const orgId       = req.user.orgId;
    const orgName     = req.user.orgName;
    const { name, email, phone, password, role = 'staff' } = req.body;

    if (!name || !email || !phone || !password) {
      return res.status(400).json({ success: false, message: 'name, email, phone, password required' });
    }

    const allowedRoles = ['admin', 'accountant', 'staff'];
    if (!allowedRoles.includes(role)) {
      return res.status(400).json({ success: false, message: `role must be one of: ${allowedRoles.join(', ')}` });
    }

    const existing = await db.collection('billing_users').findOne({ email: email.toLowerCase() });

    if (existing) {
      // User exists globally — check if already in THIS org
      const alreadyInOrg = (existing.organizations || []).some(o => o.orgId === orgId);
      if (alreadyInOrg) {
        return res.status(409).json({ success: false, message: 'User already in this organization' });
      }
      // Add them to this org
      await db.collection('billing_users').updateOne(
        { _id: existing._id },
        { $push: { organizations: { orgId, orgName, role } } }
      );
      return res.json({ success: true, message: 'Existing user added to your organization' });
    }

    // Brand new user
    const passwordHash = await hash(password);
    const now          = new Date();
    const newUser = {
      name:          name.trim(),
      email:         email.toLowerCase().trim(),
      passwordHash,
      phone:         phone.trim(),
      status:        'active',
      permissions:   {},
      organizations: [{ orgId, orgName, role }],
      createdAt:     now,
      updatedAt:     now,
      createdBy:     req.user.email,
      lastLogin:     null,
    };

    const result = await db.collection('billing_users').insertOne(newUser);
    const { passwordHash: _, ...safe } = newUser;
    safe._id = result.insertedId;

    return res.status(201).json({ success: true, message: 'User created', data: safe });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── PUT /api/finance/users/:id ───────────────────────────────────────────────
router.put('/:id', verifyFinanceJWT, requireOwnerOrAdmin, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;

    // Confirm user belongs to caller's org
    const user = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.params.id),
      'organizations.orgId': orgId,
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found in your org' });

    const { name, phone, role, status, password } = req.body;
    const $set = { updatedAt: new Date() };

    if (name)   $set.name  = name.trim();
    if (phone)  $set.phone = phone.trim();
    if (status) $set.status = status;
    if (password) $set.passwordHash = await hash(password);

    // Update role inside this org only
    const update = { $set };
    if (role) {
      update.$set['organizations.$[elem].role'] = role;
    }

    const options = role
      ? { arrayFilters: [{ 'elem.orgId': orgId }] }
      : {};

    await db.collection('billing_users').updateOne(
      { _id: new ObjectId(req.params.id) },
      update,
      options
    );

    return res.json({ success: true, message: 'User updated' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── DELETE /api/finance/users/:id  (remove from org, not global delete) ──────
router.delete('/:id', verifyFinanceJWT, requireOwnerOrAdmin, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;

    const user = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.params.id),
      'organizations.orgId': orgId,
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found in your org' });

    // Cannot delete yourself
    if (user._id.toString() === req.user.userId) {
      return res.status(400).json({ success: false, message: 'You cannot remove yourself' });
    }

    // Cannot delete the org owner
    const orgEntry = user.organizations.find(o => o.orgId === orgId);
    if (orgEntry?.role === 'owner') {
      return res.status(400).json({ success: false, message: 'Cannot remove the org owner' });
    }

    // Remove from this org only
    await db.collection('billing_users').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $pull: { organizations: { orgId } } }
    );

    return res.json({ success: true, message: 'User removed from organization' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── GET /api/finance/users/:id/permissions ──────────────────────────────────
router.get('/:id/permissions', verifyFinanceJWT, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    const user  = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.params.id),
      'organizations.orgId': orgId,
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });
    return res.json({ success: true, data: { permissions: user.permissions || {}, role: user.organizations.find(o=>o.orgId===orgId)?.role } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/users/:id/permissions ─────────────────────────────────
router.post('/:id/permissions', verifyFinanceJWT, requireOwnerOrAdmin, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    const { permissions } = req.body;

    if (!permissions || typeof permissions !== 'object') {
      return res.status(400).json({ success: false, message: 'permissions object required' });
    }

    const user = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.params.id),
      'organizations.orgId': orgId,
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found in your org' });

    await db.collection('billing_users').updateOne(
      { _id: new ObjectId(req.params.id) },
      { $set: { permissions, updatedAt: new Date(), permissionsUpdatedBy: req.user.email } }
    );

    return res.json({ success: true, message: 'Permissions saved' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
