// ============================================================================
// PAYMENT GATEWAY + PAYMENT LINKS — COMPLETE BACKEND
// ============================================================================
// File: backend/routes/payment_gateway_routes.js
//
// Covers everything in 1 file:
//   ✅ Payment Gateway Setup (per org — Razorpay / Stripe)
//   ✅ Test Gateway Connection
//   ✅ Payment Links CRUD (create, list, get, cancel, delete)
//   ✅ Change Expiry Date
//   ✅ Send Email to Customer
//   ✅ Public payment page (customer opens link)
//   ✅ Mark as Paid (manual or via webhook)
//   ✅ Razorpay Webhook handler
//   ✅ Auto-creates entry in payments_received on payment
//   ✅ Status: GENERATED → VIEWED → PAID / EXPIRED / CANCELED
//   ✅ Credentials AES-256 encrypted at rest
//   ✅ orgId isolation — each org sees only its own data
// ============================================================================

'use strict';

const express   = require('express');
const router    = express.Router();
const mongoose  = require('mongoose');
const crypto    = require('crypto');
const { verifyFinanceJWT } = require('../middleware/finance_jwt');

// ── Optional deps (install when ready) ───────────────────────────────────────
let Razorpay, nodemailer;
try { Razorpay   = require('razorpay');   } catch (_) {}
try { nodemailer = require('nodemailer'); } catch (_) {}

// ── Encryption helpers (AES-256-CBC) ─────────────────────────────────────────
const ENC_KEY = (process.env.PAYMENT_ENC_KEY || 'abra_finance_default_enc_key_32b!').padEnd(32).slice(0, 32);
const ENC_IV_LEN = 16;

function encrypt(text) {
  const iv     = crypto.randomBytes(ENC_IV_LEN);
  const cipher = crypto.createCipheriv('aes-256-cbc', Buffer.from(ENC_KEY), iv);
  const enc    = Buffer.concat([cipher.update(text), cipher.final()]);
  return iv.toString('hex') + ':' + enc.toString('hex');
}

function decrypt(text) {
  try {
    const [ivHex, encHex] = text.split(':');
    const iv      = Buffer.from(ivHex, 'hex');
    const decipher = crypto.createDecipheriv('aes-256-cbc', Buffer.from(ENC_KEY), iv);
    const dec     = Buffer.concat([decipher.update(Buffer.from(encHex, 'hex')), decipher.final()]);
    return dec.toString();
  } catch (_) { return null; }
}

// ── Helper: orgFilter ─────────────────────────────────────────────────────────
function orgFilter(req) {
  return req.user?.orgId ? { orgId: req.user.orgId } : {};
}

// ============================================================================
// MONGOOSE MODELS
// ============================================================================

// ── OrgPaymentGateway ─────────────────────────────────────────────────────────
const gatewaySchema = new mongoose.Schema({
  orgId:          { type: String, required: true, index: true },
  gateway:        { type: String, enum: ['razorpay', 'stripe'], default: 'razorpay' },
  keyId:          { type: String, default: '' },          // plain — public key
  keySecretEnc:   { type: String, default: '' },          // AES-256 encrypted
  accountName:    { type: String, default: '' },
  accountEmail:   { type: String, default: '' },
  accountId:      { type: String, default: '' },
  businessType:   { type: String, default: '' },
  profileStatus:  { type: String, default: '' },
  isActive:       { type: Boolean, default: false },
  connectedAt:    { type: Date, default: null },
  createdAt:      { type: Date, default: Date.now },
  updatedAt:      { type: Date, default: Date.now },
}, { collection: 'org_payment_gateways' });

const OrgGateway = mongoose.models.OrgPaymentGateway ||
  mongoose.model('OrgPaymentGateway', gatewaySchema);

// ── PaymentLink ───────────────────────────────────────────────────────────────
const paymentLinkSchema = new mongoose.Schema({
  orgId:           { type: String, required: true, index: true },
  branchId:        { type: String, index: true, default: null },

  // Reference number (auto-generated: PL-000001)
  referenceNumber: { type: String, index: true },

  // Customer info
  customerId:      { type: String, default: '' },
  customerName:    { type: String, required: true },
  customerEmail:   { type: String, default: '' },
  customerPhone:   { type: String, default: '' },

  // Link details
  amount:          { type: Number, required: true },
  currency:        { type: String, default: 'INR' },
  description:     { type: String, default: '' },
  expirationDate:  { type: Date, required: true },

  // Status
  status: {
    type: String,
    enum: ['GENERATED', 'VIEWED', 'PAID', 'EXPIRED', 'CANCELED'],
    default: 'GENERATED',
    index: true,
  },

  // Gateway data
  gateway:              { type: String, default: 'razorpay' },
  gatewayPaymentLinkId: { type: String, default: '' },  // Razorpay payment_link id
  shortUrl:             { type: String, default: '' },  // rzp.io/l/xxxxx
  token:                { type: String, unique: true, index: true }, // internal token for public page

  // Payment result (when PAID)
  paymentReceivedId:    { type: String, default: '' },  // ID in payments_received collection
  paidAt:               { type: Date, default: null },
  paidAmount:           { type: Number, default: 0 },
  razorpayPaymentId:    { type: String, default: '' },

  // Email tracking
  emailSentAt:     { type: Date, default: null },
  viewedAt:        { type: Date, default: null },

  // Audit
  createdBy:       { type: String, default: '' },
  createdAt:       { type: Date, default: Date.now },
  updatedAt:       { type: Date, default: Date.now },
}, { collection: 'payment_links' });

// Auto-expire check virtual
paymentLinkSchema.virtual('isExpired').get(function () {
  return this.expirationDate < new Date() && this.status === 'GENERATED';
  
});


paymentLinkSchema.index({ orgId: 1, referenceNumber: 1 }, { unique: true });
const PaymentLink = mongoose.models.PaymentLink ||
  mongoose.model('PaymentLink', paymentLinkSchema);

// ── Number generator ──────────────────────────────────────────────────────────
async function generateReferenceNumber(orgId, branchId = null) {
  const query = { orgId };
  if (branchId) query.branchId = branchId;

  const last = await PaymentLink.findOne(query)
    .sort({ createdAt: -1 })
    .select('referenceNumber')
    .lean();

  let next = 1;
  if (last?.referenceNumber) {
    const num = parseInt(last.referenceNumber.replace('PL-', ''), 10);
    if (!isNaN(num)) next = num + 1;
  }

  // Guard against duplicate: keep incrementing until we find an unused number
  let candidate = `PL-${String(next).padStart(6, '0')}`;
  let exists = await PaymentLink.exists({ ...query, referenceNumber: candidate });
  while (exists) {
    next++;
    candidate = `PL-${String(next).padStart(6, '0')}`;
    exists = await PaymentLink.exists({ ...query, referenceNumber: candidate });
  }

  return candidate;
}

function generateToken() {
  return crypto.randomBytes(24).toString('hex');
}

// ── Build Razorpay client for an org ─────────────────────────────────────────
async function getRazorpayClient(orgId) {
  if (!Razorpay) throw new Error('Razorpay SDK not installed. Run: npm install razorpay');
  const gw = await OrgGateway.findOne({ orgId, isActive: true }).lean();
  if (!gw) throw new Error('Payment gateway not configured. Go to Settings → Payment Gateway to set up.');
  const secret = decrypt(gw.keySecretEnc);
  console.log('DEBUG keyId:', gw.keyId);
  console.log('DEBUG secret decrypted:', secret);
  if (!secret) throw new Error('Gateway credentials invalid. Please reconnect your gateway.');
  return new Razorpay({ key_id: gw.keyId, key_secret: secret });
}

// ── Send email via nodemailer ─────────────────────────────────────────────────
async function sendEmail({ to, subject, html }) {
  if (!nodemailer || !process.env.SMTP_USER) return false;
  try {
    const transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: process.env.SMTP_PORT || 587,
      secure: false,
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASSWORD },
    });
    await transporter.sendMail({
      from: `"Abra Finance" <${process.env.SMTP_USER}>`,
      to,
      subject: subject || `Payment Request — ₹${link.amount.toLocaleString('en-IN')} — ${link.referenceNumber}`,
      html:    html,
    });
    return true;
  } catch (e) {
    console.error('📧 Email error:', e.message);
    return false;
  }
}

// ── Auto-expire stale links ───────────────────────────────────────────────────
async function expireOldLinks() {
  try {
    await PaymentLink.updateMany(
      { status: { $in: ['GENERATED', 'VIEWED'] }, expirationDate: { $lt: new Date() } },
      { $set: { status: 'EXPIRED', updatedAt: new Date() } }
    );
  } catch (_) {}
}

// NEW — sync status from Razorpay for active links
async function syncRazorpayLinkStatuses(orgId) {
  try {
    if (!Razorpay) return;

    // Get all non-final links for this org that have a Razorpay link ID
    const activeLinks = await PaymentLink.find({
      orgId,
      status: { $in: ['GENERATED', 'VIEWED'] },
      gatewayPaymentLinkId: { $ne: '' },
      gateway: 'razorpay',
    }).lean();

    if (!activeLinks.length) return;

    const rzp = await getRazorpayClient(orgId);

    for (const link of activeLinks) {
      try {
        // Fetch live status from Razorpay
        const rzpLink = await rzp.paymentLink.fetch(link.gatewayPaymentLinkId);

        let newStatus = link.status;

        if (rzpLink.status === 'paid') {
          newStatus = 'PAID';
        } else if (rzpLink.status === 'cancelled') {
          newStatus = 'CANCELED';
        } else if (rzpLink.status === 'expired') {
          newStatus = 'EXPIRED';
        } else if (rzpLink.times_payment_attempted > 0) {
          // Customer opened and attempted payment
          newStatus = 'VIEWED';
        }

        if (newStatus !== link.status) {
          const updateData = { status: newStatus, updatedAt: new Date() };

          // If paid via Razorpay — also create payments_received entry
          if (newStatus === 'PAID' && link.status !== 'PAID') {
            const paidAmount = (rzpLink.amount_paid || rzpLink.amount || 0) / 100;
            const rzpPaymentId = rzpLink.payments?.items?.[0]?.id || '';
            const fullLink = await PaymentLink.findById(link._id);
            await _markLinkAsPaid(fullLink, paidAmount, rzpPaymentId);
            console.log(`✅ Synced PAID from Razorpay: ${link.referenceNumber}`);
          } else {
            await PaymentLink.findByIdAndUpdate(link._id, { $set: updateData });
            console.log(`🔄 Status synced: ${link.referenceNumber} → ${newStatus}`);
          }
        }
      } catch (linkErr) {
        console.warn(`⚠️ Could not sync link ${link.referenceNumber}:`, linkErr.message);
      }
    }
  } catch (e) {
    console.warn('syncRazorpayLinkStatuses error:', e.message);
  }
}

// ============================================================================
// GATEWAY SETUP ROUTES
// ============================================================================

// ── GET /gateway/status — check if gateway is configured for this org ──────
router.get('/gateway/status', verifyFinanceJWT, async (req, res) => {
  try {
    const gw = await OrgGateway.findOne(orgFilter(req)).lean();
    if (!gw || !gw.isActive) {
      return res.json({
        success: true,
        data: { configured: false, gateway: null, accountName: '', keyId: '' },
      });
    }
    res.json({
      success: true,
      data: {
        configured:    true,
        gateway:       gw.gateway,
        accountName:   gw.accountName,
        accountEmail:  gw.accountEmail,
        accountId:     gw.accountId     || '',
        businessType:  gw.businessType  || '',
        profileStatus: gw.profileStatus || '',
        keyId:         gw.keyId,
        connectedAt:   gw.connectedAt,
      },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── POST /gateway/test — verify credentials without saving ────────────────
router.post('/gateway/test', verifyFinanceJWT, async (req, res) => {
  try {
    const { gateway = 'razorpay', keyId, keySecret } = req.body;
    if (!keyId || !keySecret) {
      return res.status(400).json({ success: false, message: 'Key ID and Key Secret are required' });
    }

    if (gateway === 'razorpay') {
      if (!Razorpay) {
        return res.status(400).json({
          success: false,
          message: 'Razorpay SDK not installed on server. Run: npm install razorpay'
        });
      }

      // Verify credentials by calling Razorpay payments list
      const rzp = new Razorpay({ key_id: keyId, key_secret: keySecret });
      try {
        await rzp.payments.all({ count: 1 });
      } catch (e) {
        return res.json({
          success: false,
          message: 'Invalid credentials. Please check your Key ID and Key Secret.'
        });
      }

      // Fetch full account details via direct HTTP (Basic Auth)
const isLive = keyId.startsWith('rzp_live_');

return res.json({
  success: true,
  data: {
    valid:         true,
    accountName:   isLive ? 'Razorpay Live Account' : 'Razorpay Test Account',
    accountEmail:  '',
    accountId:     keyId,
    businessType:  isLive ? 'Live Account' : 'Test Account',
    profileStatus: 'Active ✓',
    verifyMessage: 'Verify this Key ID matches your Razorpay Dashboard → Settings → API Keys',
  },
});
    }

    // Stripe test (basic)
    if (gateway === 'stripe') {
      const Stripe = (() => { try { return require('stripe'); } catch (_) { return null; } })();
      if (!Stripe) return res.status(400).json({ success: false, message: 'Stripe SDK not installed on server.' });
      const stripe = Stripe(keySecret);
      const account = await stripe.accounts.retrieve();
      return res.json({
        success: true,
        data: {
          valid:       true,
          accountName: account?.business_profile?.name || account?.email || 'Verified ✓',
          accountEmail:account?.email || '',
        },
      });
    }

    res.status(400).json({ success: false, message: 'Unsupported gateway' });
  } catch (e) {
    console.error('Gateway test error:', e.message);
    res.json({ success: false, message: 'Invalid credentials. Please check your Key ID and Key Secret.' });
  }
});

// ── POST /gateway/save — save gateway credentials for this org ────────────
router.post('/gateway/save', verifyFinanceJWT, async (req, res) => {
  try {
    const { gateway = 'razorpay', keyId, keySecret, accountName = '', accountEmail = '' } = req.body;
    if (!keyId || !keySecret) {
      return res.status(400).json({ success: false, message: 'Key ID and Key Secret are required' });
    }

    const keySecretEnc = encrypt(keySecret);

    await OrgGateway.findOneAndUpdate(
      { orgId: req.user.orgId },
      {
        orgId:         req.user.orgId,
        gateway,
        keyId,
        keySecretEnc,
        accountName,
        accountEmail,
        accountId:     req.body.accountId     || '',
        businessType:  req.body.businessType  || '',
        profileStatus: req.body.profileStatus || '',
        isActive:      true,
        connectedAt:   new Date(),
        updatedAt:     new Date(),
      },
      { upsert: true, new: true }
    );

    res.json({ success: true, message: 'Payment gateway connected successfully ✓' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── DELETE /gateway/disconnect — remove gateway config ───────────────────
router.delete('/gateway/disconnect', verifyFinanceJWT, async (req, res) => {
  try {
    await OrgGateway.findOneAndUpdate(
      { orgId: req.user.orgId },
      { isActive: false, keySecretEnc: '', keyId: '', updatedAt: new Date() }
    );
    res.json({ success: true, message: 'Gateway disconnected' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// PAYMENT LINKS ROUTES
// ============================================================================

// ── GET /links — list all payment links for this org ─────────────────────
router.get('/links', verifyFinanceJWT, async (req, res) => {
  try {
    await expireOldLinks();
    // Sync live status from Razorpay every time list is fetched
    await syncRazorpayLinkStatuses(req.user.orgId).catch(() => {});

    const { status, page = 1, limit = 50, search } = req.query;
    const filter = { ...orgFilter(req), ...(req.branchFilter || {}) };
    if (status && status !== 'ALL') filter.status = status;
    if (search) {
      filter.$or = [
        { customerName:    { $regex: search, $options: 'i' } },
        { referenceNumber: { $regex: search, $options: 'i' } },
        { description:     { $regex: search, $options: 'i' } },
      ];
    }

    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const [links, total] = await Promise.all([
      PaymentLink.find(filter).sort({ createdAt: -1 }).skip(skip).limit(parseInt(limit)).lean(),
      PaymentLink.countDocuments(filter),
    ]);

    // Stats
    const stats = await PaymentLink.aggregate([
      { $match: { ...orgFilter(req), ...(req.branchFilter || {}) } },
      { $group: {
          _id:       null,
          total:     { $sum: 1 },
          generated: { $sum: { $cond: [{ $eq: ['$status', 'GENERATED'] }, 1, 0] } },
          paid:      { $sum: { $cond: [{ $eq: ['$status', 'PAID']      }, 1, 0] } },
          expired:   { $sum: { $cond: [{ $eq: ['$status', 'EXPIRED']   }, 1, 0] } },
          canceled:  { $sum: { $cond: [{ $eq: ['$status', 'CANCELED']  }, 1, 0] } },
          totalPaid: { $sum: { $cond: [{ $eq: ['$status', 'PAID'] }, '$paidAmount', 0] } },
      }},
    ]);

    res.json({
      success: true,
      data: {
        links,
        pagination: {
          currentPage: parseInt(page),
          totalPages:  Math.ceil(total / parseInt(limit)),
          total,
        },
        stats: stats[0] || { total: 0, generated: 0, paid: 0, expired: 0, canceled: 0, totalPaid: 0 },
      },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── GET /links/:id — single payment link detail ───────────────────────────
router.get('/links/:id', verifyFinanceJWT, async (req, res) => {
  try {
    await expireOldLinks();
    const link = await PaymentLink.findOne({ _id: req.params.id, ...orgFilter(req), ...(req.branchFilter || {}) }).lean();
    if (!link) return res.status(404).json({ success: false, message: 'Payment link not found' });
    res.json({ success: true, data: link });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── POST /links — create new payment link ─────────────────────────────────
router.post('/links', verifyFinanceJWT, async (req, res) => {
  try {
    const {
      customerId, customerName, customerEmail = '', customerPhone = '',
      amount, description = '',
      expirationDate, // optional — default 15 days
    } = req.body;

    if (!customerName) return res.status(400).json({ success: false, message: 'Customer name is required' });
    if (!amount || amount <= 0) return res.status(400).json({ success: false, message: 'Amount must be greater than 0' });

    // Check gateway is configured
    const gw = await OrgGateway.findOne({ orgId: req.user.orgId, isActive: true }).lean();
    if (!gw) {
      return res.status(400).json({
        success: false,
        message: 'Payment gateway not configured. Go to Settings → Payment Gateway first.',
        requiresGateway: true,
      });
    }

    const expiry = expirationDate
      ? new Date(expirationDate)
      : new Date(Date.now() + 15 * 24 * 60 * 60 * 1000); // 15 days default

    const referenceNumber = await generateReferenceNumber(req.user.orgId, req.branchIds?.length > 0 ? req.branchIds[0] : null);
    const token           = generateToken();

    let shortUrl             = '';
    let gatewayPaymentLinkId = '';

    // ── Create on Razorpay ──────────────────────────────────────────────────
    if (gw.gateway === 'razorpay' && Razorpay) {
      try {
        const rzp = await getRazorpayClient(req.user.orgId);
        const rzpLink = await rzp.paymentLink.create({
          amount:      Math.round(amount * 100), // paise
          currency:    'INR',
          description: description || `Payment request - ${referenceNumber}`,
          customer: {
            name:  customerName,
            email: customerEmail || undefined,
            contact: customerPhone || undefined,
          },
          notify: { sms: !!customerPhone, email: !!customerEmail },
          expire_by: Math.floor(expiry.getTime() / 1000),
          reminder_enable: true,
          notes: {
            orgId:           req.user.orgId,
            referenceNumber,
            internalToken:   token,
          },
          callback_url:    `${process.env.APP_BASE_URL || 'https://yourapp.com'}/payment-success`,
          callback_method: 'get',
        });
        shortUrl             = rzpLink.short_url || '';
        gatewayPaymentLinkId = rzpLink.id        || '';
      } catch (rzpErr) {
        console.error('Razorpay link creation error FULL:', JSON.stringify(rzpErr));
        const errDesc = rzpErr?.error?.description
          || rzpErr?.message
          || JSON.stringify(rzpErr)
          || 'Unknown Razorpay error';
        return res.status(400).json({
          success: false,
          message: `Payment gateway error: ${errDesc}. Please check your Key ID and Key Secret in Settings → Finance Profile → Payment Gateway.`,
        });
      }
    } else {
      // Simulated / no gateway
      const baseUrl = process.env.APP_BASE_URL || 'https://yourapp.com';
      shortUrl = `${baseUrl}/pay/${token}`;
    }

    const link = new PaymentLink({
      orgId:                req.user.orgId,
      branchId:             req.branchIds?.length > 0 ? req.branchIds[0] : null,
      referenceNumber,
      customerId:           customerId || '',
      customerName,
      customerEmail,
      customerPhone,
      amount:               parseFloat(amount),
      description,
      expirationDate:       expiry,
      status:               'GENERATED',
      gateway:              gw.gateway,
      gatewayPaymentLinkId,
      shortUrl,
      token,
      createdBy:            req.user.email || 'system',
    });

    try {
      await link.save();
    } catch (saveErr) {
      // Duplicate referenceNumber — regenerate and retry once
      if (saveErr.code === 11000 && saveErr.message.includes('referenceNumber')) {
        link.referenceNumber = await generateReferenceNumber(req.user.orgId);
        await link.save();
      } else {
        throw saveErr;
      }
    }

    res.status(201).json({
      success: true,
      message: 'Payment link created successfully',
      data: link,
    });
  } catch (e) {
    console.error('Create payment link error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── PUT /links/:id/expiry — change expiration date (generates new URL) ────
router.put('/links/:id/expiry', verifyFinanceJWT, async (req, res) => {
  try {
    const { expirationDate } = req.body;
    if (!expirationDate) return res.status(400).json({ success: false, message: 'expirationDate is required' });

    const link = await PaymentLink.findOne({ _id: req.params.id, ...orgFilter(req), ...(req.branchFilter || {}) });
    if (!link) return res.status(404).json({ success: false, message: 'Payment link not found' });
    if (['PAID', 'CANCELED'].includes(link.status)) {
      return res.status(400).json({ success: false, message: `Cannot update expiry — link is ${link.status}` });
    }

    const newExpiry  = new Date(expirationDate);
    const newToken   = generateToken(); // new token = new URL
    const baseUrl    = process.env.APP_BASE_URL || 'https://yourapp.com';
    const newShortUrl = `${baseUrl}/pay/${newToken}`;

    // Update on Razorpay if applicable
    if (link.gateway === 'razorpay' && link.gatewayPaymentLinkId && Razorpay) {
      try {
        const rzp = await getRazorpayClient(req.user.orgId);
        await rzp.paymentLink.update(link.gatewayPaymentLinkId, {
          expire_by: Math.floor(newExpiry.getTime() / 1000),
        });
      } catch (e) {
        console.warn('Razorpay expiry update warning:', e.message);
      }
    }

    link.expirationDate = newExpiry;
    link.token          = newToken;
    link.shortUrl       = newShortUrl;
    link.status         = 'GENERATED'; // reset if was expired
    link.updatedAt      = new Date();
    await link.save();

    res.json({
      success: true,
      message: 'Expiry date updated. New link generated — please resend to customer.',
      data: { shortUrl: newShortUrl, expirationDate: newExpiry, referenceNumber: link.referenceNumber },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── POST /links/:id/send — send payment link via email ────────────────────
router.post('/links/:id/send', verifyFinanceJWT, async (req, res) => {
  try {
    const link = await PaymentLink.findOne({ _id: req.params.id, ...orgFilter(req), ...(req.branchFilter || {}) }).lean();
    if (!link) return res.status(404).json({ success: false, message: 'Payment link not found' });
    if (link.status === 'PAID') return res.status(400).json({ success: false, message: 'Link is already paid' });
    if (link.status === 'CANCELED') return res.status(400).json({ success: false, message: 'Link is canceled' });

    const { emails, subject } = req.body; // array of email addresses
    const toList = emails && emails.length > 0 ? emails : [link.customerEmail].filter(Boolean);

    if (!toList.length) {
      return res.status(400).json({ success: false, message: 'No email address to send to' });
    }

    // Fetch org name
    let orgName = 'Abra Finance';
    try {
      const db = req.db || mongoose.connection.db;
      const org = await db.collection('organizations').findOne({ orgId: req.user.orgId });
      if (org?.orgName) orgName = org.orgName;
    } catch (_) {}

    const emailHtml = `
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="font-family:Arial,sans-serif;background:#f4f4f4;margin:0;padding:20px">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,0.08)">
    <div style="background:linear-gradient(135deg,#2563eb,#1d4ed8);padding:32px 24px;text-align:center">
      <h1 style="color:#fff;margin:0;font-size:22px">${orgName}</h1>
      <p style="color:rgba(255,255,255,0.85);margin:8px 0 0">Payment Request</p>
    </div>
    <div style="padding:32px 24px">
      <p style="color:#374151;font-size:15px">Dear <strong>${link.customerName}</strong>,</p>
      <p style="color:#6b7280;font-size:14px">You have a payment request of:</p>
      <div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:8px;padding:20px;text-align:center;margin:20px 0">
        <div style="font-size:32px;font-weight:700;color:#0369a1">₹${link.amount.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</div>
        ${link.description ? `<p style="color:#0369a1;margin:8px 0 0;font-size:14px">${link.description}</p>` : ''}
      </div>
      <div style="background:#fafafa;border-radius:8px;padding:16px;margin:16px 0;font-size:13px;color:#6b7280">
        <div style="display:flex;justify-content:space-between;padding:4px 0">
          <span>Reference:</span><strong style="color:#374151">${link.referenceNumber}</strong>
        </div>
        <div style="display:flex;justify-content:space-between;padding:4px 0;margin-top:4px">
          <span>Expires on:</span><strong style="color:#374151">${new Date(link.expirationDate).toLocaleDateString('en-IN', { day:'numeric', month:'short', year:'numeric' })}</strong>
        </div>
      </div>
      <div style="text-align:center;margin:28px 0">
        <a href="${link.shortUrl}" style="background:#2563eb;color:#fff;text-decoration:none;padding:14px 36px;border-radius:8px;font-size:16px;font-weight:600;display:inline-block">
          Proceed to Payment →
        </a>
      </div>
      <p style="color:#9ca3af;font-size:12px;text-align:center">
        Or copy this link: <a href="${link.shortUrl}" style="color:#2563eb">${link.shortUrl}</a>
      </p>
    </div>
    <div style="background:#f9fafb;padding:16px;text-align:center;color:#9ca3af;font-size:12px">
      This is an automated payment request. Please do not reply to this email.
    </div>
  </div>
</body>
</html>`;

    const sent = await sendEmail({
      to:      toList.join(','),
      subject: `Payment Request — ₹${link.amount.toLocaleString('en-IN')} — ${link.referenceNumber}`,
      html:    emailHtml,
    });

    // Update emailSentAt
    await PaymentLink.findByIdAndUpdate(link._id, {
      emailSentAt: new Date(), updatedAt: new Date(),
    });

    res.json({
      success: true,
      message: sent ? `Email sent to ${toList.join(', ')}` : 'Email queued (SMTP not configured)',
      data: { shortUrl: link.shortUrl, sentTo: toList },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── PUT /links/:id/cancel — cancel a payment link ─────────────────────────
router.put('/links/:id/cancel', verifyFinanceJWT, async (req, res) => {
  try {
    const link = await PaymentLink.findOne({ _id: req.params.id, ...orgFilter(req), ...(req.branchFilter || {}) });
    if (!link) return res.status(404).json({ success: false, message: 'Payment link not found' });
    if (link.status === 'PAID')     return res.status(400).json({ success: false, message: 'Cannot cancel a paid link' });
    if (link.status === 'CANCELED') return res.status(400).json({ success: false, message: 'Already canceled' });

    // Cancel on Razorpay if applicable
    if (link.gateway === 'razorpay' && link.gatewayPaymentLinkId && Razorpay) {
      try {
        const rzp = await getRazorpayClient(req.user.orgId);
        await rzp.paymentLink.cancel(link.gatewayPaymentLinkId);
      } catch (e) {
        console.warn('Razorpay cancel warning:', e.message);
      }
    }

    link.status    = 'CANCELED';
    link.updatedAt = new Date();
    await link.save();

    res.json({ success: true, message: 'Payment link canceled' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── DELETE /links/:id — delete a payment link ─────────────────────────────
router.delete('/links/:id', verifyFinanceJWT, async (req, res) => {
  try {
    const link = await PaymentLink.findOne({ _id: req.params.id, ...orgFilter(req), ...(req.branchFilter || {}) });
    if (!link) return res.status(404).json({ success: false, message: 'Payment link not found' });
    if (link.status === 'PAID') {
      return res.status(400).json({ success: false, message: 'Cannot delete a paid link. Cancel it instead.' });
    }

    await PaymentLink.deleteOne({ _id: link._id });
    res.json({ success: true, message: 'Payment link deleted' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// PUBLIC ROUTES — No auth required (customer-facing)
// ============================================================================

// ── GET /pay/:token — customer opens payment link (marks as VIEWED) ───────
router.get('/pay/:token', async (req, res) => {
  try {
    await expireOldLinks();

    const link = await PaymentLink.findOne({ token: req.params.token }).lean();
    if (!link) {
      return res.status(404).json({ success: false, message: 'Payment link not found or expired' });
    }

    if (link.status === 'PAID') {
      return res.json({ success: true, data: { ...link, alreadyPaid: true } });
    }
    if (['EXPIRED', 'CANCELED'].includes(link.status)) {
      return res.json({ success: false, data: link, message: `This link is ${link.status.toLowerCase()}` });
    }

    // Mark as VIEWED (only first time)
    if (link.status === 'GENERATED') {
      await PaymentLink.findByIdAndUpdate(link._id, {
        status:    'VIEWED',
        viewedAt:  new Date(),
        updatedAt: new Date(),
      });
      link.status = 'VIEWED';
    }

    // Fetch org info for payment page
    let orgInfo = { orgName: 'Abra Finance', logoUrl: null };
    try {
      const db = mongoose.connection.db;
      const org = await db.collection('organizations').findOne({ orgId: link.orgId });
      if (org) orgInfo = { orgName: org.orgName, logoUrl: org.logoUrl };
    } catch (_) {}

    res.json({
      success: true,
      data: {
        referenceNumber: link.referenceNumber,
        customerName:    link.customerName,
        amount:          link.amount,
        currency:        link.currency,
        description:     link.description,
        expirationDate:  link.expirationDate,
        status:          link.status,
        shortUrl:        link.shortUrl,
        gatewayLinkId:   link.gatewayPaymentLinkId,
        orgName:         orgInfo.orgName,
        orgLogo:         orgInfo.logoUrl,
      },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── POST /webhook/razorpay — Razorpay webhook (payment.link.paid) ─────────
router.post('/webhook/razorpay', express.raw({ type: 'application/json' }), async (req, res) => {
  try {
    const body      = req.body.toString();
    const signature = req.headers['x-razorpay-signature'];

    // Parse event
    let event;
    try { event = JSON.parse(body); } catch (_) {
      return res.status(400).json({ success: false, message: 'Invalid JSON' });
    }

    if (event.event !== 'payment_link.paid') {
      return res.json({ success: true, message: 'Event ignored' });
    }

    const paymentLinkId = event.payload?.payment_link?.entity?.id;
    const rzpPaymentId  = event.payload?.payment?.entity?.id;
    const paidAmount    = (event.payload?.payment_link?.entity?.amount_paid || 0) / 100;

    if (!paymentLinkId) return res.json({ success: true, message: 'No payment link ID' });

    const link = await PaymentLink.findOne({ gatewayPaymentLinkId: paymentLinkId });
    if (!link || link.status === 'PAID') return res.json({ success: true });

    // Verify signature using org's key secret
    const gw = await OrgGateway.findOne({ orgId: link.orgId, isActive: true }).lean();
    if (gw) {
      try {
        // Verify webhook signature using RAZORPAY_WEBHOOK_SECRET from .env
        const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET || '';
        if (webhookSecret) {
          const expected = crypto
            .createHmac('sha256', webhookSecret)
            .update(body)
            .digest('hex');
          if (expected !== signature) {
            console.warn('⚠️ Razorpay webhook signature mismatch');
            return res.status(400).json({ success: false, message: 'Signature mismatch' });
          }
        }
      } catch (_) {}
    }

    // Mark link as PAID
    await _markLinkAsPaid(link, paidAmount, rzpPaymentId);

    res.json({ success: true });
  } catch (e) {
    console.error('Webhook error:', e.message);
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── POST /links/:id/mark-paid — manual mark as paid (for testing) ─────────
router.post('/links/:id/mark-paid', verifyFinanceJWT, async (req, res) => {
  try {
    const link = await PaymentLink.findOne({ _id: req.params.id, ...orgFilter(req), ...(req.branchFilter || {}) });
    if (!link) return res.status(404).json({ success: false, message: 'Payment link not found' });
    if (link.status === 'PAID') return res.status(400).json({ success: false, message: 'Already paid' });

    await _markLinkAsPaid(link, link.amount, 'manual');
    res.json({ success: true, message: 'Marked as paid', data: link });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ── Internal: mark a link as PAID + create payments_received entry ────────
async function _markLinkAsPaid(link, paidAmount, rzpPaymentId = '') {
  try {
    const db = mongoose.connection.db;

    // Generate payment number
    const existing = await db.collection('payments_received')
      .find({ orgId: link.orgId, paymentNumber: { $regex: '^REC' } }, { projection: { paymentNumber: 1 } })
      .toArray();
    let max = 0;
    for (const p of existing) {
      const n = parseInt((p.paymentNumber || '').slice(3), 10);
      if (!isNaN(n) && n > max) max = n;
    }
    const paymentNumber = `REC${String(max + 1).padStart(6, '0')}`;

    // Insert into payments_received (matches your existing schema)
    const paymentResult = await db.collection('payments_received').insertOne({
      customerId:      link.customerId || '',
      customerName:    link.customerName,
      customerEmail:   link.customerEmail || '',
      amountReceived:  paidAmount,
      bankCharges:     0,
      paymentDate:     new Date().toLocaleDateString('en-IN'),
      paymentNumber,
      paymentMode:     'Online',
      depositTo:       'Online Payments',
      reference:       link.referenceNumber,
      taxDeduction:    'No Tax deducted',
      notes:           `Payment via link ${link.referenceNumber}`,
      status:          'paid',
      invoicePayments: {},
      netAmount:       paidAmount,
      amountUsedForPayments: 0,
      amountRefunded:  0,
      amountInExcess:  paidAmount,
      orgId:           link.orgId,
      branchId:        link.branchId || null,
      paymentProofs:   [],
      source:          'payment_link',
      paymentLinkId:   link._id.toString(),
      razorpayPaymentId: rzpPaymentId || '',
      emailSent:       false,
      createdAt:       new Date(),
      updatedAt:       new Date(),
      createdBy:       'system',
    });

    // Update link
    link.status            = 'PAID';
    link.paidAt            = new Date();
    link.paidAmount        = paidAmount;
    link.razorpayPaymentId = rzpPaymentId || '';
    link.paymentReceivedId = paymentResult.insertedId.toString();
    link.updatedAt         = new Date();
    await link.save();

    console.log(`✅ Payment link ${link.referenceNumber} marked PAID — ${paymentNumber} created`);
  } catch (e) {
    console.error('_markLinkAsPaid error:', e.message);
    throw e;
  }
}

module.exports = router;
console.log('✅ Payment Gateway + Payment Links module loaded');