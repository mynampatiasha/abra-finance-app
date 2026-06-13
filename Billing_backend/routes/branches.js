// routes/branches.js
// Branch management — CRUD for branches under an organisation
// Each org can have multiple branches (e.g. Bengaluru, Hyderabad)
//
// ✅ BRANCH-LEVEL PROFILE SUPPORT:
//   Each branch can override org-level profile fields (GST, address, bank, logo,
//   signature, invoice note, etc.).  PDF/email generation uses branch data first,
//   falling back to org data for any field not set on the branch.
//
//   New endpoints:
//     GET  /api/finance/branches/:branchId/profile
//     PUT  /api/finance/branches/:branchId/profile
//     POST /api/finance/branches/:branchId/upload-logo
//     DELETE /api/finance/branches/:branchId/delete-logo
//     POST /api/finance/branches/:branchId/upload-signature
//     DELETE /api/finance/branches/:branchId/delete-signature
//
//   Exported helper (used by all PDF routes):
//     getEffectiveOrgData(orgId, branchId, db)
//       → merges branch profile on top of org profile; branch fields win.

const express    = require('express');
const router     = express.Router();
const { ObjectId } = require('mongodb');
const { verifyFinanceJWT, requireOwnerOrAdmin } = require('../middleware/finance_jwt');
const { encrypt, decrypt } = require('../utils/encryption');
const multer  = require('multer');
const path    = require('path');
const fs      = require('fs');
const { seedSystemAccounts } = require('./chart_of_accounts');

// ── Helper: generate a short branch ID ───────────────────────────────────────
function makeBranchId() {
  return new ObjectId().toString();
}

// ============================================================================
// EXPORTED HELPER — used by invoices.js, payment_made.js, credit-notes.js, etc.
// ============================================================================

/**
 * Returns a merged "effective" org profile for PDF/email generation.
 *
 * Priority: branch field (if non-empty) > org field
 *
 * @param {string}  orgId
 * @param {string|null} branchId  — pass null / undefined to get org-only data
 * @param {object}  db            — raw MongoDB db handle (mongoose.connection.db)
 * @returns {object|null}
 */
async function getEffectiveOrgData(orgId, branchId, db) {
  try {
    if (!db) return null;

    // Always fetch org data as the base
    let org = await db.collection('organizations').findOne({ orgId });
    if (!org) org = {}; // If org is missing, still allow branch to provide data

    // No branch requested → return org data as-is (backward-compatible)
    if (!branchId) return Object.keys(org).length > 0 ? org : null;

    // Fetch branch data
    const branch = await db.collection('branches').findOne({ branchId });
    if (!branch && Object.keys(org).length === 0) return null; // neither found

    if (!branch) return org; // branch not found → fall back to org

    // Merge: branch value wins if it is a non-empty string; otherwise use org value
    const pick = (branchVal, orgVal) => {
      if (branchVal !== undefined && branchVal !== null && String(branchVal).trim() !== '') {
        return branchVal;
      }
      return orgVal;
    };

    return {
      // Spread org first so all org fields are present
      ...org,

      // Identity / contact — branch overrides
      orgName:    pick(branch.branchName, org.orgName),   // branch name shown on PDFs
      gstNumber:  pick(branch.gstin,      org.gstNumber),
      address:    pick(branch.address,    org.address),
      phone:      pick(branch.phone,      org.phone),
      email:      pick(branch.email,      org.email),
      state:      pick(branch.state,      org.state),

      // Extended profile fields — branch overrides
      whatsappNumber:    pick(branch.whatsappNumber,    org.whatsappNumber),
      panNumber:         pick(branch.panNumber,         org.panNumber),
      invoiceNote:       pick(branch.invoiceNote,       org.invoiceNote),

      // Banking — branch overrides
      bankAccountHolder: pick(branch.bankAccountHolder, org.bankAccountHolder),
      bankAccountNumber: pick(branch.bankAccountNumber, org.bankAccountNumber),
      bankIfscCode:      pick(branch.bankIfscCode,      org.bankIfscCode),
      bankName:          pick(branch.bankName,          org.bankName),
      upiId:             pick(branch.upiId,             org.upiId),
      qrCodePath:        pick(branch.qrCodePath,        org.qrCodePath),
      otherPaymentOptions: pick(branch.otherPaymentOptions, org.otherPaymentOptions),

      // Files — branch overrides
      logoUrl:              pick(branch.logoUrl,              org.logoUrl),
      digitalSignaturePath: pick(branch.digitalSignaturePath, org.digitalSignaturePath),

      // SMTP — branch overrides
      smtpHost:        pick(branch.smtpHost,        org.smtpHost),
      smtpPort:        pick(branch.smtpPort,        org.smtpPort),
      smtpUser:        pick(branch.smtpUser,        org.smtpUser),
      smtpPasswordEnc: pick(branch.smtpPasswordEnc, org.smtpPasswordEnc),
      smtpFromName:    pick(branch.smtpFromName,    org.smtpFromName),
      smtpVerified:    pick(branch.smtpVerified,    org.smtpVerified),

      // WhatsApp Meta credentials — branch overrides
      whatsappMetaPhoneNumberId: pick(branch.whatsappMetaPhoneNumberId, org.whatsappMetaPhoneNumberId),
      whatsappMetaWabaId:        pick(branch.whatsappMetaWabaId,        org.whatsappMetaWabaId),
      whatsappMetaAccessToken:   pick(branch.whatsappMetaAccessToken,   org.whatsappMetaAccessToken),
      whatsappMetaVerified:      pick(branch.whatsappMetaVerified,      org.whatsappMetaVerified),

      // Keep a reference to the original org name for display purposes
      _orgName: org.orgName,
    };
  } catch (e) {
    console.warn('⚠️ getEffectiveOrgData error:', e.message);
    return null;
  }
}

// ── Helper: resolve logo file path from a logoUrl string ─────────────────────
function resolveLogoFilePath(logoUrl) {
  if (!logoUrl) return null;
  const rel = logoUrl.replace(/^\//, '');
  const full = path.join(__dirname, '..', rel);
  try {
    if (fs.existsSync(full) && fs.statSync(full).size > 0) return full;
  } catch (_) {}
  return null;
}

// ============================================================================
// MULTER — Branch Logo Upload
// ============================================================================
const branchLogoStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'branch-logos');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const branchId = req.params.branchId || 'unknown';
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `branch-${branchId}-${Date.now()}${ext}`);
  },
});
const branchLogoUpload = multer({
  storage: branchLogoStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ok = /jpeg|jpg|png|webp/.test(path.extname(file.originalname).toLowerCase());
    ok ? cb(null, true) : cb(new Error('Only image files allowed'));
  },
});

// ============================================================================
// MULTER — Branch Signature Upload
// ============================================================================
const branchSigStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'branch-signatures');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const branchId = req.params.branchId || 'unknown';
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `bsig-${branchId}-${Date.now()}${ext}`);
  },
});
const branchSigUpload = multer({
  storage: branchSigStorage,
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ok = /jpeg|jpg|png|webp/.test(path.extname(file.originalname).toLowerCase());
    ok ? cb(null, true) : cb(new Error('Only image files allowed'));
  },
});

// ============================================================================
// EXISTING BRANCH CRUD ROUTES (unchanged)
// ============================================================================

// ─── GET /api/finance/branches — list branches for current org ────────────────
router.get('/', verifyFinanceJWT, async (req, res) => {
  try {
    const db      = req.db;
    const orgId   = req.user.orgId;
    const branches = await db.collection('branches')
      .find({ orgId })
      .sort({ createdAt: 1 })
      .toArray();
    return res.json({ success: true, data: { branches } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/branches — create a branch (owner/admin only) ─────────
router.post('/', verifyFinanceJWT, requireOwnerOrAdmin, async (req, res) => {
  try {
    const db    = req.db;
    const orgId = req.user.orgId;
    const { branchName, city, address, phone, email, gstin } = req.body;

    if (!branchName || !branchName.trim()) {
      return res.status(400).json({ success: false, message: 'branchName is required' });
    }

    const branchId = makeBranchId();
    const now      = new Date();

    const branch = {
      _id:        new ObjectId(branchId),
      branchId,
      orgId,
      branchName: branchName.trim(),
      city:       city?.trim()    || '',
      address:    address?.trim() || '',
      phone:      phone?.trim()   || '',
      email:      email?.trim()   || '',
      gstin:      gstin?.trim()   || '',
      isDefault:  false,
      createdBy:  req.user.email,
      createdAt:  now,
      updatedAt:  now,
    };

    await db.collection('branches').insertOne(branch);
    // ✅ FIX: Seed system accounts for new branch
    await seedSystemAccounts(orgId, branchId)
      .catch(e => console.warn(`Seed warning for new branch ${branchId}:`, e.message));
    return res.status(201).json({ success: true, data: { branch } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── PUT /api/finance/branches/:branchId — update a branch ───────────────────
router.put('/:branchId', verifyFinanceJWT, requireOwnerOrAdmin, async (req, res) => {
  try {
    const db       = req.db;
    const orgId    = req.user.orgId;
    const { branchId } = req.params;
    const { branchName, city, address, phone, email, gstin } = req.body;

    const update = { updatedAt: new Date() };
    if (branchName) update.branchName = branchName.trim();
    if (city       !== undefined) update.city    = city.trim();
    if (address    !== undefined) update.address = address.trim();
    if (phone      !== undefined) update.phone   = phone.trim();
    if (email      !== undefined) update.email   = email.trim();
    if (gstin      !== undefined) update.gstin   = gstin.trim();

    const result = await db.collection('branches').findOneAndUpdate(
      { branchId, orgId },
      { $set: update },
      { returnDocument: 'after' }
    );

    if (!result) return res.status(404).json({ success: false, message: 'Branch not found' });
    return res.json({ success: true, data: { branch: result } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── DELETE /api/finance/branches/:branchId — delete a branch ────────────────
router.delete('/:branchId', verifyFinanceJWT, requireOwnerOrAdmin, async (req, res) => {
  try {
    const db       = req.db;
    const orgId    = req.user.orgId;
    const { branchId } = req.params;

    const result = await db.collection('branches').deleteOne({ branchId, orgId });
    if (result.deletedCount === 0) {
      return res.status(404).json({ success: false, message: 'Branch not found' });
    }
    return res.json({ success: true, message: 'Branch deleted' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// BRANCH PROFILE ENDPOINTS (NEW)
// ============================================================================

// ─── GET /api/finance/branches/:branchId/profile ─────────────────────────────
// Returns the branch's own profile fields merged with org defaults.
// Frontend uses this to pre-fill the branch profile form.
router.get('/:branchId/profile', verifyFinanceJWT, async (req, res) => {
  try {
    const db       = req.db;
    const orgId    = req.user.orgId;
    const { branchId } = req.params;

    const branch = await db.collection('branches').findOne({ branchId, orgId });
    if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

    // Also fetch org so frontend can show what the fallback value is
    const org = await db.collection('organizations').findOne({ orgId });

    return res.json({
      success: true,
      data: {
        branchId,
        branchName:          branch.branchName          || '',
        // Branch-specific overrides (empty string = "use org default")
        gstNumber:           branch.gstin               || '',
        phone:               branch.phone               || '',
        email:               branch.email               || '',
        address:             branch.address             || '',
        state:               branch.state               || '',
        whatsappNumber:      branch.whatsappNumber      || '',
        panNumber:           branch.panNumber           || '',
        invoiceNote:         branch.invoiceNote         || '',
        bankAccountHolder:   branch.bankAccountHolder   || '',
        bankAccountNumber:   branch.bankAccountNumber   || '',
        bankIfscCode:        branch.bankIfscCode        || '',
        bankName:            branch.bankName            || '',
        upiId:               branch.upiId               || '',
        qrCodePath:          branch.qrCodePath          || null,
        otherPaymentOptions: branch.otherPaymentOptions || '',
        logoUrl:             branch.logoUrl             || null,
        digitalSignaturePath:branch.digitalSignaturePath|| null,
        smtpHost:     branch.smtpHost     || '',
        smtpPort:     branch.smtpPort     || 587,
        smtpUser:     branch.smtpUser     || '',
        smtpFromName: branch.smtpFromName || '',
        smtpVerified: branch.smtpVerified || false,
        // WhatsApp Meta credentials
        whatsappMetaPhoneNumberId: branch.whatsappMetaPhoneNumberId || '',
        whatsappMetaWabaId:        branch.whatsappMetaWabaId        || '',
        whatsappMetaVerified:      branch.whatsappMetaVerified      || false,
        // Access token: return masked if set, empty if not
        whatsappMetaAccessToken:   branch.whatsappMetaAccessToken ? '••••••••' : '',
        // Org fallback values (for placeholder hints in the UI)
        orgDefaults: {
          gstNumber:           org?.gstNumber            || '',
          phone:               org?.phone                || '',
          email:               org?.email                || '',
          address:             org?.address              || '',
          state:               org?.state                || '',
          invoiceNote:         org?.invoiceNote          || '',
          bankAccountHolder:   org?.bankAccountHolder    || '',
          bankAccountNumber:   org?.bankAccountNumber    || '',
          bankIfscCode:        org?.bankIfscCode         || '',
          bankName:            org?.bankName             || '',
          upiId:               org?.upiId                || '',
          otherPaymentOptions: org?.otherPaymentOptions  || '',
          logoUrl:             org?.logoUrl              || null,
          digitalSignaturePath:org?.digitalSignaturePath || null,
        },
      },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── PUT /api/finance/branches/:branchId/profile ─────────────────────────────
// Saves branch-specific profile overrides.
// Only fields explicitly sent are updated (partial update).
router.put('/:branchId/profile', verifyFinanceJWT, async (req, res) => {
  try {
    const db       = req.db;
    const orgId    = req.user.orgId;
    const { branchId } = req.params;

    const branch = await db.collection('branches').findOne({ branchId, orgId });
    if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

    const {
      gstNumber, phone, email, address, state, whatsappNumber, panNumber,
      invoiceNote, bankAccountHolder, bankAccountNumber, bankIfscCode,
      bankName, upiId, otherPaymentOptions,
    } = req.body;
    const { smtpHost, smtpPort, smtpUser, smtpPassword, smtpFromName } = req.body;

    const update = { updatedAt: new Date() };
    // Store gstNumber under 'gstin' to match existing branch schema field
    if (gstNumber            !== undefined) update.gstin               = gstNumber.trim();
    if (phone                !== undefined) update.phone               = phone.trim();
    if (email                !== undefined) update.email               = email.trim();
    if (address              !== undefined) update.address             = address.trim();
    if (state                !== undefined) update.state               = state.trim();
    if (whatsappNumber       !== undefined) update.whatsappNumber      = whatsappNumber.trim();
    if (panNumber            !== undefined) update.panNumber           = panNumber.trim();
    if (invoiceNote          !== undefined) update.invoiceNote         = invoiceNote.trim();
    if (bankAccountHolder    !== undefined) update.bankAccountHolder   = bankAccountHolder.trim();
    if (bankAccountNumber    !== undefined) update.bankAccountNumber   = bankAccountNumber.trim();
    if (bankIfscCode         !== undefined) update.bankIfscCode        = bankIfscCode.trim();
    if (bankName             !== undefined) update.bankName            = bankName.trim();
    if (upiId                !== undefined) update.upiId               = upiId.trim();
    if (otherPaymentOptions  !== undefined) update.otherPaymentOptions = otherPaymentOptions.trim();
    if (smtpHost     !== undefined) update.smtpHost     = smtpHost.trim();
    if (smtpPort     !== undefined) update.smtpPort     = parseInt(smtpPort) || 587;
    if (smtpUser     !== undefined) update.smtpUser     = smtpUser.trim();
    if (smtpFromName !== undefined) update.smtpFromName = smtpFromName.trim();
    if (smtpPassword !== undefined && smtpPassword.trim() !== '') {
      update.smtpPasswordEnc = encrypt(smtpPassword.trim());
      update.smtpVerified    = false;
    }

    const result = await db.collection('branches').findOneAndUpdate(
      { branchId, orgId },
      { $set: update },
      { returnDocument: 'after' }
    );

    return res.json({
      success: true,
      message: 'Branch profile updated successfully',
      data: { branch: result },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/branches/:branchId/upload-logo ────────────────────────
router.post(
  '/:branchId/upload-logo',
  verifyFinanceJWT,
  branchLogoUpload.single('logo'),
  async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
      const db       = req.db;
      const orgId    = req.user.orgId;
      const { branchId } = req.params;

      const branch = await db.collection('branches').findOne({ branchId, orgId });
      if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

      // Delete old branch logo file if exists
      if (branch.logoUrl) {
        try {
          const old = path.join(__dirname, '..', branch.logoUrl.replace(/^\//, ''));
          if (fs.existsSync(old)) fs.unlinkSync(old);
        } catch (_) {}
      }

      const logoUrl = `/uploads/branch-logos/${req.file.filename}`;
      await db.collection('branches').updateOne(
        { branchId, orgId },
        { $set: { logoUrl, logoUpdatedAt: new Date(), updatedAt: new Date() } }
      );

      return res.json({ success: true, message: 'Branch logo uploaded', data: { branchId, logoUrl } });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }
);

// ─── DELETE /api/finance/branches/:branchId/delete-logo ──────────────────────
router.delete('/:branchId/delete-logo', verifyFinanceJWT, async (req, res) => {
  try {
    const db       = req.db;
    const orgId    = req.user.orgId;
    const { branchId } = req.params;

    const branch = await db.collection('branches').findOne({ branchId, orgId });
    if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

    if (branch.logoUrl) {
      try {
        const fp = path.join(__dirname, '..', branch.logoUrl.replace(/^\//, ''));
        if (fs.existsSync(fp)) fs.unlinkSync(fp);
      } catch (_) {}
    }

    await db.collection('branches').updateOne(
      { branchId, orgId },
      { $set: { logoUrl: null, updatedAt: new Date() } }
    );

    return res.json({ success: true, message: 'Branch logo removed', data: { branchId, logoUrl: null } });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ============================================================================
// MULTER — Branch QR Code Upload
// ============================================================================
const branchQrStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'branch-qr');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const branchId = req.params.branchId || 'unknown';
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `bqr-${branchId}-${Date.now()}${ext}`);
  },
});
const branchQrUpload = multer({
  storage: branchQrStorage,
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const ok = /jpeg|jpg|png|webp/.test(path.extname(file.originalname).toLowerCase());
    ok ? cb(null, true) : cb(new Error('Only image files allowed'));
  },
});

// ─── POST /api/finance/branches/:branchId/upload-qr ──────────────────────────
router.post(
  '/:branchId/upload-qr',
  verifyFinanceJWT,
  branchQrUpload.single('qr'),
  async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
      const db       = req.db;
      const orgId    = req.user.orgId;
      const { branchId } = req.params;

      const branch = await db.collection('branches').findOne({ branchId, orgId });
      if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

      // Delete old QR file if exists
      if (branch.qrCodePath) {
        try {
          const old = path.join(__dirname, '..', branch.qrCodePath.replace(/^\//, ''));
          if (fs.existsSync(old)) fs.unlinkSync(old);
        } catch (_) {}
      }

      const qrCodePath = `/uploads/branch-qr/${req.file.filename}`;
      await db.collection('branches').updateOne(
        { branchId, orgId },
        { $set: { qrCodePath, qrUpdatedAt: new Date(), updatedAt: new Date() } }
      );

      return res.json({
        success: true,
        message: 'Branch QR code uploaded',
        data: { branchId, qrCodePath },
      });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }
);

// ─── DELETE /api/finance/branches/:branchId/delete-qr ────────────────────────
router.delete('/:branchId/delete-qr', verifyFinanceJWT, async (req, res) => {
  try {
    const db       = req.db;
    const orgId    = req.user.orgId;
    const { branchId } = req.params;

    const branch = await db.collection('branches').findOne({ branchId, orgId });
    if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

    if (branch.qrCodePath) {
      try {
        const fp = path.join(__dirname, '..', branch.qrCodePath.replace(/^\//, ''));
        if (fs.existsSync(fp)) fs.unlinkSync(fp);
      } catch (_) {}
    }

    await db.collection('branches').updateOne(
      { branchId, orgId },
      { $set: { qrCodePath: null, updatedAt: new Date() } }
    );

    return res.json({
      success: true,
      message: 'Branch QR code removed',
      data: { branchId, qrCodePath: null },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ─── POST /api/finance/branches/:branchId/upload-signature ───────────────────
router.post(
  '/:branchId/upload-signature',
  verifyFinanceJWT,
  branchSigUpload.single('signature'),
  async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ success: false, message: 'No file uploaded' });
      const db       = req.db;
      const orgId    = req.user.orgId;
      const { branchId } = req.params;

      const branch = await db.collection('branches').findOne({ branchId, orgId });
      if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

      // Delete old signature file if exists
      if (branch.digitalSignaturePath) {
        try {
          const old = path.join(__dirname, '..', branch.digitalSignaturePath.replace(/^\//, ''));
          if (fs.existsSync(old)) fs.unlinkSync(old);
        } catch (_) {}
      }

      const digitalSignaturePath = `/uploads/branch-signatures/${req.file.filename}`;
      await db.collection('branches').updateOne(
        { branchId, orgId },
        { $set: { digitalSignaturePath, signatureUpdatedAt: new Date(), updatedAt: new Date() } }
      );

      return res.json({
        success: true,
        message: 'Branch signature uploaded',
        data: { branchId, digitalSignaturePath },
      });
    } catch (err) {
      return res.status(500).json({ success: false, message: err.message });
    }
  }
);

// ─── DELETE /api/finance/branches/:branchId/delete-signature ─────────────────
router.delete('/:branchId/delete-signature', verifyFinanceJWT, async (req, res) => {
  try {
    const db       = req.db;
    const orgId    = req.user.orgId;
    const { branchId } = req.params;

    const branch = await db.collection('branches').findOne({ branchId, orgId });
    if (!branch) return res.status(404).json({ success: false, message: 'Branch not found' });

    if (branch.digitalSignaturePath) {
      try {
        const fp = path.join(__dirname, '..', branch.digitalSignaturePath.replace(/^\//, ''));
        if (fs.existsSync(fp)) fs.unlinkSync(fp);
      } catch (_) {}
    }

    await db.collection('branches').updateOne(
      { branchId, orgId },
      { $set: { digitalSignaturePath: null, updatedAt: new Date() } }
    );

    return res.json({
      success: true,
      message: 'Branch signature removed',
      data: { branchId, digitalSignaturePath: null },
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
module.exports.getEffectiveOrgData = getEffectiveOrgData;
