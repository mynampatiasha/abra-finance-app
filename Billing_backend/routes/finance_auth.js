// routes/finance_auth.js
// Register, Login, Select-Org, My-Orgs, Profile, Change-Password, Create-Org
// ✅ NEW: Org Logo Upload per organisation

const express = require('express');
const router  = express.Router();
const bcrypt  = require('bcryptjs');
const { ObjectId } = require('mongodb');
const { generateFinanceToken, verifyFinanceJWT } = require('../middleware/finance_jwt');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');
const { seedSystemAccounts } = require('./chart_of_accounts');

const SALT_ROUNDS = 12;

const hashPwd  = (p)    => bcrypt.hash(p, SALT_ROUNDS);
const checkPwd = (p, h) => bcrypt.compare(p, h);

function makeOrgId() {
  return new ObjectId().toString();
}

// ============================================================================
// MULTER — Org Logo Upload
// Saves to: uploads/org-logos/<orgId>-<timestamp>.<ext>
// ============================================================================
const orgLogoStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'org-logos');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const orgId = req.user?.orgId || 'unknown';
    const ext   = path.extname(file.originalname).toLowerCase();
    cb(null, `org-${orgId}-${Date.now()}${ext}`);
  },
});

const orgLogoUpload = multer({
  storage: orgLogoStorage,
  limits:  { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter: (req, file, cb) => {
    const allowed = /jpeg|jpg|png|webp/;
    const okExt  = allowed.test(path.extname(file.originalname).toLowerCase());
    const okMime = allowed.test(file.mimetype) ||
                   file.mimetype === 'image/jpeg' ||
                   file.mimetype === 'image/png'  ||
                   file.mimetype === 'image/webp';
    if (okExt && okMime) cb(null, true);
    else cb(new Error('Only JPEG, PNG or WebP images are allowed'));
  },
});

// ── Helper: fetch org logo URL from organizations collection ──────────────────
async function getOrgLogoUrl(db, orgId) {
  try {
    const org = await db.collection('organizations').findOne({ orgId });
    return org?.logoUrl || null;
  } catch (_) {
    return null;
  }
}

// ── Helper: enrich organizations array with per-org logoUrl ──────────────────
async function enrichOrgsWithLogos(db, orgs) {
  if (!orgs || !orgs.length) return orgs;
  return Promise.all(orgs.map(async (o) => ({
    ...o,
    logoUrl: await getOrgLogoUrl(db, o.orgId),
  })));
}

// ─── POST /api/finance/auth/register ─────────────────────────────────────────
router.post('/register', async (req, res) => {
  console.log('\n📝 FINANCE REGISTER');
  try {
    const { name, email, password, phone, orgName } = req.body;

    if (!name || !email || !password || !phone || !orgName) {
      return res.status(400).json({
        success: false,
        message: 'name, email, password, phone, and orgName are required',
      });
    }

    const db = req.db;
    const existing = await db.collection('billing_users').findOne({ email: email.toLowerCase() });
    if (existing) {
      return res.status(409).json({ success: false, message: 'Email already registered' });
    }

    const passwordHash = await hashPwd(password);
    const orgId        = makeOrgId();
    const now          = new Date();

    const org = {
      _id:           new ObjectId(orgId),
      orgId,
      orgName:       orgName.trim(),
      currency:      'INR',
      timezone:      'Asia/Kolkata',
      logoUrl:       null,           // ✅ logo field initialised
      gstNumber:     '',
      phone:         '',
      whatsappNumber:'',
      email:         '',
      address:       '',
      website:       '',
      panNumber:     '',
      createdAt:     now,
    };
    await db.collection('organizations').insertOne(org);

    const newUser = {
      name:          name.trim(),
      email:         email.toLowerCase().trim(),
      passwordHash,
      phone:         phone.trim(),
      status:        'active',
      permissions:   {},
      organizations: [{ orgId, orgName: orgName.trim(), role: 'owner' }],
      createdAt:     now,
      updatedAt:     now,
      lastLogin:     null,
    };

    const result = await db.collection('billing_users').insertOne(newUser);
    newUser._id  = result.insertedId;

    await db.collection('organizations').updateOne(
      { orgId },
      { $set: { ownerId: result.insertedId.toString() } }
    );

    const token = generateFinanceToken(newUser, newUser.organizations[0]);

    console.log(`✅ Registered: ${email} | Org: ${orgName}`);
    return res.status(201).json({
      success: true,
      message: 'Registration successful',
      data: {
        token,
        user: {
          id:            newUser._id,
          name:          newUser.name,
          email:         newUser.email,
          phone:         newUser.phone,
          role:          'owner',
          orgId,
          orgName:       orgName.trim(),
          orgLogoUrl:    null,       // ✅
          organizations: newUser.organizations,
          permissions:   {},
          createdBy:     null,
        },
      },
    });
  } catch (err) {
    console.error('❌ Register error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/auth/login ─────────────────────────────────────────────
router.post('/login', async (req, res) => {
  console.log('\n🔐 FINANCE LOGIN');
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ success: false, message: 'Email and password required' });
    }

    const db   = req.db;
    const user = await db.collection('billing_users').findOne({ email: email.toLowerCase().trim() });

    if (!user) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }
    if (user.status !== 'active') {
      return res.status(403).json({ success: false, message: 'Account inactive. Contact your admin.' });
    }

    const valid = await checkPwd(password, user.passwordHash);
    if (!valid) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    await db.collection('billing_users').updateOne(
      { _id: user._id },
      { $set: { lastLogin: new Date() } }
    );

    const orgs = user.organizations || [];

    if (orgs.length === 1) {
      // ✅ Fetch logo for the single org
      const orgLogoUrl  = await getOrgLogoUrl(db, orgs[0].orgId);
      const enrichedOrgs = await enrichOrgsWithLogos(db, orgs);
      const token = generateFinanceToken(user, orgs[0]);
      await seedSystemAccounts(orgs[0].orgId).catch(e => console.warn('Seed warning:', e.message));

      return res.json({
        success:          true,
        requireOrgSelect: false,
        data: {
          token,
          user: {
            id:            user._id,
            name:          user.name,
            email:         user.email,
            phone:         user.phone,
            role:          orgs[0].role,
            orgId:         orgs[0].orgId,
            orgName:       orgs[0].orgName,
            orgLogoUrl,                   // ✅
            organizations: enrichedOrgs,  // ✅ each org has logoUrl
            permissions:   user.permissions || {},
            createdBy:     user.createdBy || null,
          },
        },
      });
    }

    // Multiple orgs — temp token path
    const enrichedOrgs = await enrichOrgsWithLogos(db, orgs);
    const tempToken = generateFinanceToken(user, null);

    return res.json({
      success:          true,
      requireOrgSelect: orgs.length > 1,
      data: {
        tempToken,
        organizations: enrichedOrgs,   // ✅
        user: {
          id:        user._id,
          name:      user.name,
          email:     user.email,
          phone:     user.phone,
          createdBy: user.createdBy || null,
        },
      },
    });
  } catch (err) {
    console.error('❌ Login error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/auth/select-org ───────────────────────────────────────
router.post('/select-org', async (req, res) => {
  try {
    const { orgId } = req.body;
    if (!orgId) return res.status(400).json({ success: false, message: 'orgId required' });

    const authHeader = req.headers['authorization'];
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, message: 'No token provided' });
    }

    const token = authHeader.split(' ')[1];
    let decoded;
    try {
      const jwt = require('jsonwebtoken');
      decoded = jwt.verify(token, process.env.JWT_FINANCE_SECRET);
    } catch (e) {
      return res.status(401).json({ success: false, message: 'Invalid or expired token' });
    }

    const db   = req.db;
    const user = await db.collection('billing_users').findOne({
      _id: new ObjectId(decoded.userId),
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    const org = (user.organizations || []).find(o => o.orgId === orgId);
    if (!org) return res.status(403).json({ success: false, message: 'You do not belong to this org' });

    // ✅ Fetch logo for selected org + enrich full list
    const orgLogoUrl   = await getOrgLogoUrl(db, orgId);
    const enrichedOrgs = await enrichOrgsWithLogos(db, user.organizations || []);
    const newToken     = generateFinanceToken(user, org);
    await seedSystemAccounts(orgId).catch(e => console.warn('Seed warning:', e.message));

    console.log(`✅ select-org: userId=${decoded.userId} → orgId=${orgId} | logo=${orgLogoUrl || 'none'}`);
    return res.json({
      success: true,
      data: {
        token: newToken,
        user: {
          id:            user._id,
          name:          user.name,
          email:         user.email,
          phone:         user.phone,
          role:          org.role,
          orgId:         org.orgId,
          orgName:       org.orgName,
          orgLogoUrl,                   // ✅
          organizations: enrichedOrgs,  // ✅
          permissions:   user.permissions || {},
          createdBy:     user.createdBy || null,
        },
      },
    });
  } catch (err) {
    console.error('❌ select-org error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── GET /api/finance/auth/my-orgs ───────────────────────────────────────────
router.get('/my-orgs', verifyFinanceJWT, async (req, res) => {
  try {
    const db   = req.db;
    const user = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.user.userId),
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    const enrichedOrgs = await enrichOrgsWithLogos(db, user.organizations || []);
    return res.json({ success: true, data: { organizations: enrichedOrgs } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── GET /api/finance/auth/me ─────────────────────────────────────────────────
router.get('/me', verifyFinanceJWT, async (req, res) => {
  return res.json({ success: true, data: { user: req.user } });
});

// ─── POST /api/finance/auth/logout ───────────────────────────────────────────
router.post('/logout', (req, res) => {
  return res.json({ success: true, message: 'Logged out. Remove token from client storage.' });
});

// ═══════════════════════════════════════════════════════════════════════════════
// ─── POST /api/finance/auth/upload-org-logo ──────────────────────────────────
// Uploads a logo for the currently active organisation.
// Only owners/admins can upload.
// Stores file at: uploads/org-logos/org-<orgId>-<ts>.<ext>
// Saves path in:  organizations.logoUrl (relative URL served as /uploads/...)
// ═══════════════════════════════════════════════════════════════════════════════
router.post(
  '/upload-org-logo',
  verifyFinanceJWT,
  orgLogoUpload.single('logo'),
  async (req, res) => {
    console.log('\n🖼️  ORG LOGO UPLOAD');
    try {
      if (!req.file) {
        return res.status(400).json({ success: false, message: 'No file uploaded' });
      }

      const orgId = req.user?.orgId;
      if (!orgId) {
        return res.status(400).json({ success: false, message: 'orgId not found in token' });
      }

      const db = req.db;

      // ── Check org exists ──────────────────────────────────────────────────
      const org = await db.collection('organizations').findOne({ orgId });
      if (!org) {
        return res.status(404).json({ success: false, message: 'Organisation not found' });
      }

      // ── Delete old logo file if it exists ─────────────────────────────────
      if (org.logoUrl) {
        try {
          const oldPath = path.join(__dirname, '..', org.logoUrl.replace(/^\//, ''));
          if (fs.existsSync(oldPath)) {
            fs.unlinkSync(oldPath);
            console.log(`   🗑️  Deleted old logo: ${oldPath}`);
          }
        } catch (delErr) {
          console.warn('   ⚠️  Could not delete old logo:', delErr.message);
        }
      }

      // ── Build relative URL (served by express.static) ─────────────────────
      const logoUrl = `/uploads/org-logos/${req.file.filename}`;

      // ── Persist in organizations collection ───────────────────────────────
      await db.collection('organizations').updateOne(
        { orgId },
        { $set: { logoUrl, logoUpdatedAt: new Date() } }
      );

      console.log(`✅ Logo uploaded for org ${orgId}: ${logoUrl}`);

      return res.json({
        success: true,
        message: 'Logo uploaded successfully',
        data: {
          orgId,
          logoUrl,
          filename: req.file.filename,
          size:     req.file.size,
        },
      });
    } catch (err) {
      console.error('❌ upload-org-logo error:', err.message);
      return res.status(500).json({ success: false, message: err.message });
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// ─── DELETE /api/finance/auth/delete-org-logo ────────────────────────────────
// Removes the logo for the currently active organisation.
// ═══════════════════════════════════════════════════════════════════════════════
router.delete('/delete-org-logo', verifyFinanceJWT, async (req, res) => {
  console.log('\n🗑️  DELETE ORG LOGO');
  try {
    const orgId = req.user?.orgId;
    if (!orgId) {
      return res.status(400).json({ success: false, message: 'orgId not found in token' });
    }

    const db  = req.db;
    const org = await db.collection('organizations').findOne({ orgId });
    if (!org) {
      return res.status(404).json({ success: false, message: 'Organisation not found' });
    }

    if (!org.logoUrl) {
      return res.json({ success: true, message: 'No logo to delete' });
    }

    // Delete file
    try {
      const filePath = path.join(__dirname, '..', org.logoUrl.replace(/^\//, ''));
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    } catch (delErr) {
      console.warn('   ⚠️  Could not delete logo file:', delErr.message);
    }

    await db.collection('organizations').updateOne(
      { orgId },
      { $set: { logoUrl: null, logoUpdatedAt: new Date() } }
    );

    console.log(`✅ Logo deleted for org ${orgId}`);
    return res.json({ success: true, message: 'Logo removed successfully', data: { orgId, logoUrl: null } });
  } catch (err) {
    console.error('❌ delete-org-logo error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// ─── PUT /api/finance/auth/update-profile ────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
router.put('/update-profile', verifyFinanceJWT, async (req, res) => {
  console.log('\n✏️  FINANCE UPDATE PROFILE');
  try {
    const { name, phone, email } = req.body;

    if (!name && !phone && !email) {
      return res.status(400).json({ success: false, message: 'At least one field required' });
    }

    const db  = req.db;
    const uid = new ObjectId(req.user.userId);

    const user = await db.collection('billing_users').findOne({ _id: uid });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    if (email && email.toLowerCase() !== user.email) {
      const emailExists = await db.collection('billing_users').findOne({
        email: email.toLowerCase(),
        _id:   { $ne: uid },
      });
      if (emailExists) {
        return res.status(409).json({ success: false, message: 'Email already in use by another account' });
      }
    }

    const updateFields = { updatedAt: new Date() };
    if (name)  updateFields.name  = name.trim();
    if (phone) updateFields.phone = phone.trim();
    if (email) updateFields.email = email.toLowerCase().trim();

    await db.collection('billing_users').updateOne(
      { _id: uid },
      { $set: updateFields }
    );

    const updated = await db.collection('billing_users').findOne({ _id: uid });

    console.log(`✅ Profile updated for userId: ${req.user.userId}`);
    return res.json({
      success: true,
      message: 'Profile updated successfully',
      data: {
        user: {
          id:    updated._id,
          name:  updated.name,
          email: updated.email,
          phone: updated.phone,
        },
      },
    });
  } catch (err) {
    console.error('❌ update-profile error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// ─── PUT /api/finance/auth/change-password ────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
router.put('/change-password', verifyFinanceJWT, async (req, res) => {
  console.log('\n🔑 FINANCE CHANGE PASSWORD');
  try {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ success: false, message: 'currentPassword and newPassword are required' });
    }
    if (newPassword.length < 6) {
      return res.status(400).json({ success: false, message: 'New password must be at least 6 characters' });
    }

    const db   = req.db;
    const user = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.user.userId),
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    const valid = await checkPwd(currentPassword, user.passwordHash);
    if (!valid) {
      return res.status(401).json({ success: false, message: 'Current password is incorrect' });
    }

    const newHash = await hashPwd(newPassword);
    await db.collection('billing_users').updateOne(
      { _id: user._id },
      { $set: { passwordHash: newHash, updatedAt: new Date() } }
    );

    console.log(`✅ Password changed for userId: ${req.user.userId}`);
    return res.json({ success: true, message: 'Password changed successfully' });
  } catch (err) {
    console.error('❌ change-password error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// ─── POST /api/finance/auth/create-org ───────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
router.post('/create-org', verifyFinanceJWT, async (req, res) => {
  console.log('\n🏢 FINANCE CREATE ORG');
  try {
    const { orgName } = req.body;
    if (!orgName || !orgName.trim()) {
      return res.status(400).json({ success: false, message: 'orgName is required' });
    }

    const db   = req.db;
    const user = await db.collection('billing_users').findOne({
      _id: new ObjectId(req.user.userId),
    });
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    if (user.createdBy) {
      return res.status(403).json({
        success: false,
        message: 'Only self-registered owners can create organisations',
      });
    }

    const currentOrg = (user.organizations || []).find(o => o.orgId === req.user.orgId);
    if (!currentOrg || currentOrg.role !== 'owner') {
      return res.status(403).json({
        success: false,
        message: 'Only owners can create new organisations',
      });
    }

    const orgId = makeOrgId();
    const now   = new Date();

    const org = {
      _id:           new ObjectId(orgId),
      orgId,
      orgName:       orgName.trim(),
      currency:      'INR',
      timezone:      'Asia/Kolkata',
      ownerId:       user._id.toString(),
      logoUrl:       null,   // ✅
      gstNumber:     '',
      phone:         '',
      whatsappNumber:'',
      email:         '',
      address:       '',
      website:       '',
      panNumber:     '',
      createdAt:     now,
    };
    await db.collection('organizations').insertOne(org);

    const newOrgEntry = { orgId, orgName: orgName.trim(), role: 'owner' };
    await db.collection('billing_users').updateOne(
      { _id: user._id },
      {
        $push: { organizations: newOrgEntry },
        $set:  { updatedAt: now },
      }
    );

    const updatedUser  = await db.collection('billing_users').findOne({ _id: user._id });
    const enrichedOrgs = await enrichOrgsWithLogos(db, updatedUser.organizations || []);

    console.log(`✅ New org created: ${orgName} by userId: ${req.user.userId}`);
    return res.status(201).json({
      success: true,
      message: `Organisation "${orgName.trim()}" created successfully`,
      data: {
        newOrg:        { ...newOrgEntry, logoUrl: null },
        organizations: enrichedOrgs,
      },
    });
  } catch (err) {
    console.error('❌ create-org error:', err.message);
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── GET /api/finance/auth/org-profile ───────────────────────────────────────
router.get('/org-profile', verifyFinanceJWT, async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    if (!orgId) return res.status(400).json({ success: false, message: 'orgId not found in token' });
    const db  = req.db;
    const org = await db.collection('organizations').findOne({ orgId });
    if (!org) return res.status(404).json({ success: false, message: 'Organisation not found' });
    return res.json({
      success: true,
      data: {
        orgId,
        orgName:             org.orgName             || '',
        gstNumber:           org.gstNumber           || '',
        phone:               org.phone               || '',
        whatsappNumber:      org.whatsappNumber      || '',
        email:               org.email               || '',
        address:             org.address             || '',
        website:             org.website             || '',
        panNumber:           org.panNumber           || '',
        logoUrl:             org.logoUrl             || null,
        // Banking fields
        bankAccountHolder:   org.bankAccountHolder   || '',
        bankAccountNumber:   org.bankAccountNumber   || '',
        bankIfscCode:        org.bankIfscCode        || '',
        bankName:            org.bankName            || '',
        upiId:               org.upiId               || '',
        qrCodePath:          org.qrCodePath          || '',
        otherPaymentOptions: org.otherPaymentOptions || '',
        documents:           org.documents           || [],
      },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── PUT /api/finance/auth/update-org-profile ─────────────────────────────────
router.put('/update-org-profile', verifyFinanceJWT, async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    if (!orgId) return res.status(400).json({ success: false, message: 'orgId not found in token' });
    const {
      gstNumber, phone, whatsappNumber, email, address, website, panNumber,
      bankAccountHolder, bankAccountNumber, bankIfscCode, bankName, upiId, otherPaymentOptions,
    } = req.body;
    const db  = req.db;
    const org = await db.collection('organizations').findOne({ orgId });
    if (!org) return res.status(404).json({ success: false, message: 'Organisation not found' });
    const updateFields = { updatedAt: new Date() };
    if (gstNumber            !== undefined) updateFields.gstNumber            = gstNumber.trim();
    if (phone                !== undefined) updateFields.phone                = phone.trim();
    if (whatsappNumber       !== undefined) updateFields.whatsappNumber       = whatsappNumber.trim();
    if (email                !== undefined) updateFields.email                = email.trim();
    if (address              !== undefined) updateFields.address              = address.trim();
    if (website              !== undefined) updateFields.website              = website.trim();
    if (panNumber            !== undefined) updateFields.panNumber            = panNumber.trim();
    if (bankAccountHolder    !== undefined) updateFields.bankAccountHolder    = bankAccountHolder.trim();
    if (bankAccountNumber    !== undefined) updateFields.bankAccountNumber    = bankAccountNumber.trim();
    if (bankIfscCode         !== undefined) updateFields.bankIfscCode         = bankIfscCode.trim();
    if (bankName             !== undefined) updateFields.bankName             = bankName.trim();
    if (upiId                !== undefined) updateFields.upiId                = upiId.trim();
    if (otherPaymentOptions  !== undefined) updateFields.otherPaymentOptions  = otherPaymentOptions.trim();
    await db.collection('organizations').updateOne({ orgId }, { $set: updateFields });
    const updated = await db.collection('organizations').findOne({ orgId });
    return res.json({
      success: true,
      message: 'Organisation profile updated successfully',
      data: {
        orgId,
        orgName:             updated.orgName             || '',
        gstNumber:           updated.gstNumber           || '',
        phone:               updated.phone               || '',
        whatsappNumber:      updated.whatsappNumber      || '',
        email:               updated.email               || '',
        address:             updated.address             || '',
        website:             updated.website             || '',
        panNumber:           updated.panNumber           || '',
        logoUrl:             updated.logoUrl             || null,
        bankAccountHolder:   updated.bankAccountHolder   || '',
        bankAccountNumber:   updated.bankAccountNumber   || '',
        bankIfscCode:        updated.bankIfscCode        || '',
        bankName:            updated.bankName            || '',
        upiId:               updated.upiId               || '',
        qrCodePath:          updated.qrCodePath          || '',
        otherPaymentOptions: updated.otherPaymentOptions || '',
        documents:           updated.documents           || [],
      },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// ─── POST /api/finance/auth/upload-org-qr ────────────────────────────────────
// Uploads a QR code image for the org's payment section
// ═══════════════════════════════════════════════════════════════════════════════
const orgQrStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'org-qr');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const orgId = req.user?.orgId || 'unknown';
    const ext   = path.extname(file.originalname).toLowerCase();
    cb(null, `qr-${orgId}-${Date.now()}${ext}`);
  },
});
const orgQrUpload = multer({
  storage: orgQrStorage,
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ok = /jpeg|jpg|png|webp/.test(path.extname(file.originalname).toLowerCase());
    ok ? cb(null, true) : cb(new Error('Only image files allowed'));
  },
});

router.post('/upload-org-qr', verifyFinanceJWT, orgQrUpload.single('qr'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
    const orgId = req.user?.orgId;
    if (!orgId) return res.status(400).json({ success: false, message: 'orgId not found in token' });
    const db = req.db;
    const org = await db.collection('organizations').findOne({ orgId });
    if (!org) return res.status(404).json({ success: false, message: 'Organisation not found' });
    // Delete old QR if exists
    if (org.qrCodePath) {
      try {
        const oldPath = path.join(__dirname, '..', org.qrCodePath.replace(/^\//, ''));
        if (fs.existsSync(oldPath)) fs.unlinkSync(oldPath);
      } catch (_) {}
    }
    const qrCodePath = `/uploads/org-qr/${req.file.filename}`;
    await db.collection('organizations').updateOne({ orgId }, { $set: { qrCodePath, updatedAt: new Date() } });
    return res.json({ success: true, message: 'QR code uploaded', data: { orgId, qrCodePath } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// ─── POST /api/finance/auth/upload-org-document ──────────────────────────────
// Uploads a document (GST cert, PAN, etc.) with a user-defined label
// ═══════════════════════════════════════════════════════════════════════════════
const orgDocStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'org-documents');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const orgId = req.user?.orgId || 'unknown';
    const ext   = path.extname(file.originalname).toLowerCase();
    cb(null, `doc-${orgId}-${Date.now()}${ext}`);
  },
});
const orgDocUpload = multer({ storage: orgDocStorage, limits: { fileSize: 10 * 1024 * 1024 } });

router.post('/upload-org-document', verifyFinanceJWT, orgDocUpload.single('document'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
    const orgId = req.user?.orgId;
    if (!orgId) return res.status(400).json({ success: false, message: 'orgId not found in token' });
    const { label } = req.body;
    if (!label || !label.trim()) return res.status(400).json({ success: false, message: 'Document label is required' });
    const db = req.db;
    const { ObjectId } = require('mongodb');
    const docEntry = {
      _id:        new ObjectId(),
      label:      label.trim(),
      filePath:   `/uploads/org-documents/${req.file.filename}`,
      uploadedAt: new Date(),
    };
    await db.collection('organizations').updateOne(
      { orgId },
      { $push: { documents: docEntry }, $set: { updatedAt: new Date() } }
    );
    return res.json({ success: true, message: 'Document uploaded', data: docEntry });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── DELETE /api/finance/auth/org-document/:docId ────────────────────────────
router.delete('/org-document/:docId', verifyFinanceJWT, async (req, res) => {
  try {
    const orgId = req.user?.orgId;
    if (!orgId) return res.status(400).json({ success: false, message: 'orgId not found in token' });
    const { ObjectId } = require('mongodb');
    const db  = req.db;
    const org = await db.collection('organizations').findOne({ orgId });
    if (!org) return res.status(404).json({ success: false, message: 'Organisation not found' });
    const doc = (org.documents || []).find(d => d._id.toString() === req.params.docId);
    if (doc?.filePath) {
      try {
        const fp = path.join(__dirname, '..', doc.filePath.replace(/^\//, ''));
        if (fs.existsSync(fp)) fs.unlinkSync(fp);
      } catch (_) {}
    }
    await db.collection('organizations').updateOne(
      { orgId },
      { $pull: { documents: { _id: new ObjectId(req.params.docId) } }, $set: { updatedAt: new Date() } }
    );
    return res.json({ success: true, message: 'Document deleted' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;