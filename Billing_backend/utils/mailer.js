'use strict';

const nodemailer = require('nodemailer');
const crypto     = require('crypto');
const { decrypt } = require('./encryption');

// ── Connection reuse ─────────────────────────────────────────────────────────
// Logging in to the mail server for every email is slow, and some mail hosts
// throttle repeated connections. One pooled transporter is kept per distinct
// login (host + port + user + password) and reused for a few minutes. Because
// the password is part of the key, changing the saved Email Settings always
// produces a fresh connection.
const POOL_TTL_MS = 5 * 60 * 1000;
const _pool = new Map(); // key → { transporter, expiresAt }

function _closeExpired() {
  const now = Date.now();
  for (const [key, entry] of _pool) {
    if (entry.expiresAt <= now) {
      try { entry.transporter.close(); } catch (_) {}
      _pool.delete(key);
    }
  }
}
setInterval(_closeExpired, 60 * 1000).unref();

function _poolKey(smtp) {
  const passHash = crypto.createHash('sha256').update(String(smtp.pass || '')).digest('hex').slice(0, 16);
  return `${smtp.host}|${smtp.port}|${smtp.user}|${passHash}`;
}

function _getPooledTransporter(smtp) {
  _closeExpired();
  const key = _poolKey(smtp);
  const hit = _pool.get(key);
  if (hit) {
    hit.expiresAt = Date.now() + POOL_TTL_MS;
    return hit.transporter;
  }
  const transporter = nodemailer.createTransport({
    host:   smtp.host,
    port:   smtp.port,
    secure: smtp.port === 465,
    auth:   { user: smtp.user, pass: smtp.pass },
    tls:    { rejectUnauthorized: false },
    pool:           true,
    maxConnections: 3,
    maxMessages:    50,
    connectionTimeout: 30 * 1000,
    greetingTimeout:   30 * 1000,
    socketTimeout:     90 * 1000,
  });
  _pool.set(key, { transporter, expiresAt: Date.now() + POOL_TTL_MS });
  return transporter;
}

async function getTransporter(orgId, branchId, db) {
  console.log('🔍 mailer: orgId=', orgId, 'branchId=', branchId);
  let smtp = null;

  try {
    // 1. Try branch SMTP first
    if (branchId) {
      const branch = await db.collection('branches').findOne({ branchId, orgId });
      if (branch?.smtpUser && branch?.smtpPasswordEnc) {
        smtp = {
          host:     branch.smtpHost     || 'smtp.hostinger.com',
          port:     branch.smtpPort     || 587,
          user:     branch.smtpUser,
          pass:     decrypt(branch.smtpPasswordEnc),
          fromName: branch.smtpFromName || branch.branchName || '',
        };
      }
    }

    // 2. Try org SMTP
    if (!smtp) {
      const org = await db.collection('organizations').findOne({ orgId });
      if (org?.smtpUser && org?.smtpPasswordEnc) {
        smtp = {
          host:     org.smtpHost     || 'smtp.hostinger.com',
          port:     org.smtpPort     || 587,
          user:     org.smtpUser,
          pass:     decrypt(org.smtpPasswordEnc),
          fromName: org.smtpFromName || org.orgName || '',
        };
      }
    }
  } catch (e) {
    // A saved login that cannot be read silently falls back to the default
    // sender below — make that very visible in the logs.
    console.error('❌ mailer: could not load/decrypt saved org/branch SMTP — FALLING BACK to default sender:', e.message);
  }

  // 3. Fall back to .env default
  if (!smtp) {
    smtp = {
      host:     process.env.SMTP_HOST || 'smtp.gmail.com',
      port:     parseInt(process.env.SMTP_PORT) || 587,
      user:     process.env.SMTP_USER,
      pass:     process.env.SMTP_PASSWORD,
      fromName: 'Accounts',
    };
  }

  const transporter = _getPooledTransporter(smtp);

  console.log('📧 mailer: using smtp user=', smtp.user, 'host=', smtp.host);
  const fromAddress = `"${smtp.fromName}" <${smtp.user}>`;
  return { transporter, fromAddress };
}

async function sendMail({ orgId, branchId, db, to, cc, subject, html, text, attachments }) {
  const { transporter, fromAddress } = await getTransporter(orgId, branchId, db);
  return transporter.sendMail({
    from:        fromAddress,
    to,
    ...(cc ? { cc } : {}),
    subject,
    html,
    text,
    attachments,
  });
}

// Used by tests / graceful shutdown.
function closeAll() {
  for (const [key, entry] of _pool) {
    try { entry.transporter.close(); } catch (_) {}
    _pool.delete(key);
  }
}

module.exports = { getTransporter, sendMail, closeAll };
