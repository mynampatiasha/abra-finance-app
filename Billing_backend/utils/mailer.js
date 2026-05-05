'use strict';

const nodemailer = require('nodemailer');
const { decrypt } = require('./encryption');

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
    console.warn('⚠️ mailer: could not load org/branch SMTP, using default:', e.message);
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

  const transporter = nodemailer.createTransport({
    host:   smtp.host,
    port:   smtp.port,
    secure: smtp.port === 465,
    auth:   { user: smtp.user, pass: smtp.pass },
    tls:    { rejectUnauthorized: false },
  });

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

module.exports = { getTransporter, sendMail };
