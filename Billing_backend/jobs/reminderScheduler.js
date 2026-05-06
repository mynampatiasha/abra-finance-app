// ============================================================================
// REMINDER SCHEDULER — INVOICE OVERDUE AUTOMATION
// ============================================================================
// File: backend/jobs/reminderScheduler.js
// ============================================================================

const cron         = require('node-cron');
const mongoose     = require('mongoose');
const { sendMail } = require('../utils/mailer');

function getInvoiceModel()          { return mongoose.models.Invoice; }
function getReminderSettingsModel() { return mongoose.models.ReminderSettings; }

// ============================================================================
// META WHATSAPP — TEMPLATE CACHE
// Caches approved templates per WABA ID so we don't hit Meta API on every invoice
// Cache TTL: 30 minutes
// ============================================================================

const _templateCache = new Map(); // wabaId → { templates: [], fetchedAt: Date }
const TEMPLATE_CACHE_TTL_MS = 30 * 60 * 1000; // 30 min

async function fetchApprovedTemplates(wabaId, accessToken) {
  const now     = Date.now();
  const cached  = _templateCache.get(wabaId);
  if (cached && (now - cached.fetchedAt) < TEMPLATE_CACHE_TTL_MS) {
    return cached.templates;
  }

  try {
    const https    = require('https');
    const result   = await new Promise((resolve, reject) => {
      const options = {
        hostname: 'graph.facebook.com',
        port: 443,
        path: `/v18.0/${wabaId}/message_templates?fields=name,status,language,category&limit=50`,
        method: 'GET',
        headers: { 'Authorization': `Bearer ${accessToken}` },
      };
      const req = https.request(options, (res) => {
        let data = '';
        res.on('data', c => { data += c; });
        res.on('end', () => {
          try { resolve(JSON.parse(data)); } catch (e) { reject(e); }
        });
      });
      req.on('error', reject);
      req.end();
    });

    // Only keep APPROVED templates, exclude Meta's sandbox hello_world
    const approved = Array.isArray(result.data)
      ? result.data.filter(t => t.status === 'APPROVED' && t.name !== 'hello_world')
      : [];

    // Sort: put payment_reminder first if it exists, so auto-pick always prefers it
    approved.sort((a, b) => {
      if (a.name === 'payment_reminder') return -1;
      if (b.name === 'payment_reminder') return  1;
      return 0;
    });

    console.log(`📋 [WA Templates] WABA ${wabaId}: ${approved.length} approved custom template(s) found`);
    _templateCache.set(wabaId, { templates: approved, fetchedAt: now });
    return approved;
  } catch (err) {
    console.warn(`⚠️ [WA Templates] Could not fetch templates for WABA ${wabaId}:`, err.message);
    return [];
  }
}

// ============================================================================
// META WHATSAPP SENDER
// ============================================================================
// Strategy:
//   1. If settings has a configured templateName → use that template directly
//   2. Else auto-pick first approved template from WABA (excluding hello_world)
//   3. If no approved template found → fall back to text message with a warning
//      (text only delivers if customer messaged business in last 24h)
// ============================================================================

async function sendWhatsAppMessage({
  phoneNumberId,
  accessToken,
  wabaId,
  toPhone,
  message,
  templateName,     // optional: specific template name to use
  templateLanguage, // optional: language code e.g. 'en_US'
  templateParams,   // optional: array of body parameter values e.g. ['Rajesh', 'INV-001', '5000']
}) {
  if (!phoneNumberId || !accessToken) {
    return { success: false, error: 'WhatsApp credentials not configured for this branch' };
  }
  if (!toPhone) {
    return { success: false, error: 'Customer phone number not available' };
  }

  try {
    let phone = String(toPhone).replace(/[^\d]/g, '');
    if (!phone.startsWith('91') && phone.length === 10) phone = '91' + phone;

    const https = require('https');

    // ── Resolve which template to use ────────────────────────────────────────
    let resolvedTemplate     = templateName     || null;
    let resolvedLanguage     = templateLanguage || 'en';
    let resolvedParams       = templateParams   || null;

    if (!resolvedTemplate && wabaId) {
      // Auto-pick first approved template
      const templates = await fetchApprovedTemplates(wabaId, accessToken);
      if (templates.length > 0) {
        resolvedTemplate = templates[0].name;
        resolvedLanguage = templates[0].language || 'en';
        console.log(`📤 [WA] Auto-selected template: "${resolvedTemplate}" (${resolvedLanguage})`);
      }
    }

    // ── Build payload ─────────────────────────────────────────────────────────
    let payload;
    if (resolvedTemplate) {
      // Template message — works anytime, no 24h window needed
      const templateBody = {
        name:     resolvedTemplate,
        language: { code: resolvedLanguage },
      };
      // If caller provided explicit params, add them as body components
      if (resolvedParams && resolvedParams.length > 0) {
        templateBody.components = [{
          type:       'body',
          parameters: resolvedParams.map(v => ({ type: 'text', text: String(v) })),
        }];
      }
      payload = {
        messaging_product: 'whatsapp',
        to:       phone,
        type:     'template',
        template: templateBody,
      };
      console.log(`📤 [WA] Sending template "${resolvedTemplate}" to ${phone}`);
    } else {
      // No template available — fall back to free text
      // ⚠️ This will only deliver if recipient messaged business in last 24h
      console.warn(`⚠️ [WA] No approved template found — sending as text to ${phone}. Message may not deliver outside 24h window.`);
      payload = {
        messaging_product: 'whatsapp',
        to:   phone,
        type: 'text',
        text: { body: message },
      };
    }

    // ── Send ──────────────────────────────────────────────────────────────────
    const postData = JSON.stringify(payload);
    const result   = await new Promise((resolve, reject) => {
      const options = {
        hostname: 'graph.facebook.com',
        port: 443,
        path: `/v18.0/${phoneNumberId}/messages`,
        method: 'POST',
        headers: {
          'Authorization':  `Bearer ${accessToken}`,
          'Content-Type':   'application/json',
          'Content-Length': Buffer.byteLength(postData),
        },
      };
      const req = https.request(options, (res) => {
        let data = '';
        res.on('data', c => { data += c; });
        res.on('end', () => {
          try { resolve({ statusCode: res.statusCode, body: JSON.parse(data) }); }
          catch (e) { reject(new Error('Invalid JSON from Meta API')); }
        });
      });
      req.on('error', reject);
      req.write(postData);
      req.end();
    });

    console.log(`📥 [WA] Meta response for ${phone}:`, JSON.stringify(result.body));

    if (result.statusCode === 200 && result.body.messages) {
      return {
        success:      true,
        messageId:    result.body.messages[0]?.id,
        templateUsed: resolvedTemplate || null,
        usedText:     !resolvedTemplate,
      };
    }

    const errCode = result.body.error?.code;
    const errMsg  = result.body.error?.message || 'WhatsApp API error';
    let friendly  = `Meta error ${errCode}: ${errMsg}`;
    if (errCode === 190)    friendly = 'Access token invalid or expired';
    if (errCode === 131030) friendly = 'Recipient not on WhatsApp or outside 24h window';
    if (errCode === 132000) friendly = `Template "${resolvedTemplate}" not found or not approved`;
    if (errCode === 131047) friendly = 'Payment method missing on Meta Business Account';

    return { success: false, error: friendly, metaCode: errCode };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

// ============================================================================
// TEMPLATE RENDERER
// ============================================================================

function renderTemplate(template, vars) {
  if (!template) return '';
  return template
    .replace(/\{\{invoiceNumber\}\}/g,  vars.invoiceNumber  || '')
    .replace(/\{\{customerName\}\}/g,   vars.customerName   || '')
    .replace(/\{\{amount\}\}/g,         vars.amount         || '')
    .replace(/\{\{amountDue\}\}/g,      vars.amountDue      || '')
    .replace(/\{\{dueDate\}\}/g,        vars.dueDate        || '')
    .replace(/\{\{companyName\}\}/g,    vars.companyName    || '')
    .replace(/\{\{daysOverdue\}\}/g,    vars.daysOverdue    || '')
    .replace(/\{\{daysBefore\}\}/g,     vars.daysBefore     || '')
    .replace(/\{\{orgGST\}\}/g,         vars.orgGST         || '')
    .replace(/\{\{orgPhone\}\}/g,       vars.orgPhone       || '')
    .replace(/\{\{orgEmail\}\}/g,       vars.orgEmail       || '')
    .replace(/\{\{bankAccount\}\}/g,    vars.bankAccount    || '')
    .replace(/\{\{ifscCode\}\}/g,       vars.ifscCode       || '')
    .replace(/\{\{bankName\}\}/g,       vars.bankName       || '')
    .replace(/\{\{accountHolder\}\}/g,  vars.accountHolder  || '')
    .replace(/\{\{upiId\}\}/g,          vars.upiId          || '');
}

// ============================================================================
// OVERDUE EMAIL TEMPLATE — RED / URGENT
// ============================================================================

function buildOverdueEmailHtml(vars) {
  const {
    invoiceNumber, customerName, amount, amountDue, dueDate,
    companyName, daysOverdue, orgGST, orgPhone, orgEmail,
    bankAccount, ifscCode, bankName, accountHolder, upiId,
  } = vars;

  const dayNum = parseInt(daysOverdue) || 0;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Payment Overdue - ${invoiceNumber}</title>
</head>
<body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#222;background:#f4f4f4;">
<div style="max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd;border-radius:4px;overflow:hidden;">

  <!-- HEADER -->
  <div style="background:#0f1e3d;padding:24px 32px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td>
          <div style="color:#fff;font-size:18px;font-weight:bold;">${companyName}</div>
          <div style="color:rgba(255,255,255,0.6);font-size:11px;margin-top:2px;letter-spacing:0.5px;">BILLING &amp; FINANCE</div>
          ${orgGST ? `<div style="color:rgba(255,255,255,0.5);font-size:11px;margin-top:4px;">GSTIN: ${orgGST}</div>` : ''}
        </td>
        <td align="right">
          <div style="background:#dc2626;color:#fff;padding:6px 14px;border-radius:20px;font-size:11px;font-weight:bold;letter-spacing:1px;display:inline-block;">&#9888; OVERDUE</div>
        </td>
      </tr>
    </table>
    <div style="margin-top:16px;">
      <div style="color:rgba(255,255,255,0.6);font-size:11px;letter-spacing:0.5px;">INVOICE NUMBER</div>
      <div style="color:#fff;font-size:20px;font-weight:bold;margin-top:2px;">${invoiceNumber}</div>
    </div>
  </div>

  <!-- URGENT RED BANNER -->
  <div style="background:#dc2626;padding:14px 32px;text-align:center;">
    <div style="color:#fff;font-size:16px;font-weight:bold;">&#9888; Payment Overdue — Immediate Action Required</div>
    <div style="color:rgba(255,255,255,0.85);font-size:12px;margin-top:4px;">This invoice was due on ${dueDate} and has not been settled yet.</div>
  </div>

  <!-- BODY -->
  <div style="padding:28px 32px;">
    <p style="font-size:14px;color:#222;margin-bottom:14px;">Dear <strong>${customerName}</strong>,</p>
    <p style="color:#444;line-height:1.7;margin-bottom:0;">
      We hope this message finds you well. Despite our previous communication,
      we have not yet received payment for Invoice <strong>${invoiceNumber}</strong>.
      Kindly arrange payment at the earliest to avoid any disruption to services.
    </p>

    <!-- DAYS OVERDUE BOX -->
    <div style="background:#fef2f2;border:2px solid #dc2626;border-radius:8px;padding:16px 20px;margin:20px 0;text-align:center;">
      <div style="font-size:36px;font-weight:bold;color:#dc2626;">${dayNum === 0 ? 'Today' : daysOverdue}</div>
      <div style="font-size:13px;color:#991b1b;font-weight:600;margin-top:4px;">${dayNum === 0 ? 'DUE TODAY — PAYMENT REQUIRED' : `DAY${dayNum === 1 ? '' : 'S'} OVERDUE`}</div>
    </div>

    <!-- INVOICE DETAILS -->
    <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px;">Invoice Details</div>
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="font-size:13px;">
      <tr>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;color:#555;width:160px;">Invoice Number</td>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;font-weight:600;text-align:right;">${invoiceNumber}</td>
      </tr>
      <tr>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;color:#555;">Original Due Date</td>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;font-weight:bold;color:#dc2626;text-align:right;">${dueDate}</td>
      </tr>
      <tr>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;color:#555;">Invoice Total</td>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;font-weight:600;text-align:right;">Rs. ${amount}</td>
      </tr>
      <tr>
        <td style="padding:12px 0 0 0;color:#dc2626;font-size:15px;font-weight:bold;border-top:2px solid #dc2626;">Balance Due</td>
        <td style="padding:12px 0 0 0;color:#dc2626;font-size:16px;font-weight:bold;text-align:right;border-top:2px solid #dc2626;">Rs. ${amountDue}</td>
      </tr>
    </table>

    <!-- PAYMENT INFO -->
    ${bankAccount || upiId ? `
    <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px;">Payment Information</div>
    ` : ''}
    ${bankAccount ? `
    <div style="background:#f9f9f9;border-left:3px solid #0f1e3d;padding:12px 16px;margin:8px 0;font-size:12px;line-height:1.8;">
      <strong style="display:block;font-size:10px;text-transform:uppercase;letter-spacing:0.5px;color:#555;margin-bottom:4px;">Bank Transfer / NEFT / RTGS / IMPS</strong>
      Account Holder : ${accountHolder}<br>
      Account Number : ${bankAccount}<br>
      IFSC Code &nbsp;&nbsp;&nbsp;&nbsp;: ${ifscCode}<br>
      Bank Name &nbsp;&nbsp;&nbsp;&nbsp;: ${bankName}<br>
      <em style="font-size:11px;color:#555;">Please mention <strong>${invoiceNumber}</strong> in payment remarks.</em>
    </div>` : ''}
    ${upiId ? `
    <div style="background:#f9f9f9;border-left:3px solid #0f1e3d;padding:12px 16px;margin:8px 0;font-size:12px;line-height:1.8;">
      <strong style="display:block;font-size:10px;text-transform:uppercase;letter-spacing:0.5px;color:#555;margin-bottom:4px;">UPI Payment</strong>
      UPI ID : <strong>${upiId}</strong><br>
      <em style="font-size:11px;color:#555;">Pay via Google Pay, PhonePe, Paytm or any UPI app.</em>
    </div>` : ''}

    <p style="margin-top:20px;font-size:12px;color:#555;line-height:1.7;">
      If you have already made the payment, please disregard this reminder and
      share the payment confirmation with us. For any queries, please reply to this email.
    </p>
    <p style="margin-top:16px;font-size:13px;color:#222;">
      Regards,<br>
      <strong>${companyName}</strong>
      ${orgPhone ? `<br><span style="color:#555;font-size:12px;">${orgPhone}</span>` : ''}
      ${orgEmail ? `<br><span style="color:#555;font-size:12px;">${orgEmail}</span>` : ''}
    </p>
  </div>

  <!-- FOOTER -->
  <div style="background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7;">
    <strong style="color:#333;">${companyName}</strong>
    ${orgGST   ? ` &nbsp;|&nbsp; GST: ${orgGST}`   : ''}
    ${orgPhone ? ` &nbsp;|&nbsp; ${orgPhone}`       : ''}
    ${orgEmail ? ` &nbsp;|&nbsp; ${orgEmail}`       : ''}
    <br>This is an automated reminder. Please do not reply if payment has already been made.
  </div>

</div>
</body>
</html>`;
}

// ============================================================================
// PRE-DUE EMAIL TEMPLATE — ORANGE / GENTLE
// ============================================================================

function buildPreDueEmailHtml(vars) {
  const {
    invoiceNumber, customerName, amount, amountDue, dueDate,
    companyName, daysBefore, orgGST, orgPhone, orgEmail,
    bankAccount, ifscCode, bankName, accountHolder, upiId,
  } = vars;

  const dayNum = parseInt(daysBefore) || 0;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Payment Reminder - ${invoiceNumber}</title>
</head>
<body style="margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#222;background:#f4f4f4;">
<div style="max-width:620px;margin:24px auto;background:#fff;border:1px solid #ddd;border-radius:4px;overflow:hidden;">

  <!-- HEADER -->
  <div style="background:#0f1e3d;padding:24px 32px;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0">
      <tr>
        <td>
          <div style="color:#fff;font-size:18px;font-weight:bold;">${companyName}</div>
          <div style="color:rgba(255,255,255,0.6);font-size:11px;margin-top:2px;letter-spacing:0.5px;">BILLING &amp; FINANCE</div>
          ${orgGST ? `<div style="color:rgba(255,255,255,0.5);font-size:11px;margin-top:4px;">GSTIN: ${orgGST}</div>` : ''}
        </td>
        <td align="right">
          <div style="background:#d97706;color:#fff;padding:6px 14px;border-radius:20px;font-size:11px;font-weight:bold;letter-spacing:1px;display:inline-block;">&#128276; DUE SOON</div>
        </td>
      </tr>
    </table>
    <div style="margin-top:16px;">
      <div style="color:rgba(255,255,255,0.6);font-size:11px;letter-spacing:0.5px;">INVOICE NUMBER</div>
      <div style="color:#fff;font-size:20px;font-weight:bold;margin-top:2px;">${invoiceNumber}</div>
    </div>
  </div>

  <!-- ORANGE NUDGE BANNER -->
  <div style="background:linear-gradient(135deg,#d97706,#b45309);padding:14px 32px;text-align:center;">
    <div style="color:#fff;font-size:16px;font-weight:bold;">&#128276; Friendly Payment Reminder</div>
    <div style="color:rgba(255,255,255,0.85);font-size:12px;margin-top:4px;">Your invoice is due in ${daysBefore} day${dayNum === 1 ? '' : 's'}. No action needed if already paid.</div>
  </div>

  <!-- BODY -->
  <div style="padding:28px 32px;">
    <p style="font-size:14px;color:#222;margin-bottom:14px;">Dear <strong>${customerName}</strong>,</p>
    <p style="color:#444;line-height:1.7;margin-bottom:0;">
      This is a gentle reminder that Invoice <strong>${invoiceNumber}</strong> will be due soon.
      We kindly request you to arrange payment before the due date to avoid any late fees.
    </p>

    <!-- COUNTDOWN BOX -->
    <div style="background:#fffbeb;border:2px solid #d97706;border-radius:8px;padding:16px 20px;margin:20px 0;text-align:center;">
      <div style="font-size:36px;font-weight:bold;color:#d97706;">${daysBefore}</div>
      <div style="font-size:13px;color:#92400e;font-weight:600;margin-top:4px;">DAY${dayNum === 1 ? '' : 'S'} UNTIL DUE</div>
    </div>

    <!-- INVOICE DETAILS -->
    <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px;">Invoice Details</div>
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="font-size:13px;">
      <tr>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;color:#555;width:160px;">Invoice Number</td>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;font-weight:600;text-align:right;">${invoiceNumber}</td>
      </tr>
      <tr>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;color:#555;">Invoice Total</td>
        <td style="padding:8px 0;border-bottom:1px dashed #e8e8e8;font-weight:600;text-align:right;">Rs. ${amount}</td>
      </tr>
      <tr>
        <td style="padding:12px 0 0 0;color:#d97706;font-size:15px;font-weight:bold;border-top:2px solid #d97706;">Due Date</td>
        <td style="padding:12px 0 0 0;color:#d97706;font-size:15px;font-weight:bold;text-align:right;border-top:2px solid #d97706;">${dueDate}</td>
      </tr>
    </table>

    <!-- PAYMENT INFO -->
    ${bankAccount || upiId ? `
    <div style="font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;color:#666;border-bottom:1px solid #e0e0e0;padding-bottom:6px;margin:22px 0 12px;">Payment Information</div>
    ` : ''}
    ${bankAccount ? `
    <div style="background:#f9f9f9;border-left:3px solid #0f1e3d;padding:12px 16px;margin:8px 0;font-size:12px;line-height:1.8;">
      <strong style="display:block;font-size:10px;text-transform:uppercase;letter-spacing:0.5px;color:#555;margin-bottom:4px;">Bank Transfer / NEFT / RTGS / IMPS</strong>
      Account Holder : ${accountHolder}<br>
      Account Number : ${bankAccount}<br>
      IFSC Code &nbsp;&nbsp;&nbsp;&nbsp;: ${ifscCode}<br>
      Bank Name &nbsp;&nbsp;&nbsp;&nbsp;: ${bankName}<br>
      <em style="font-size:11px;color:#555;">Please mention <strong>${invoiceNumber}</strong> in payment remarks.</em>
    </div>` : ''}
    ${upiId ? `
    <div style="background:#f9f9f9;border-left:3px solid #0f1e3d;padding:12px 16px;margin:8px 0;font-size:12px;line-height:1.8;">
      <strong style="display:block;font-size:10px;text-transform:uppercase;letter-spacing:0.5px;color:#555;margin-bottom:4px;">UPI Payment</strong>
      UPI ID : <strong>${upiId}</strong><br>
      <em style="font-size:11px;color:#555;">Pay via Google Pay, PhonePe, Paytm or any UPI app.</em>
    </div>` : ''}

    <p style="margin-top:20px;font-size:12px;color:#555;line-height:1.7;">
      If you have already arranged payment, please ignore this reminder.
      For any queries, feel free to reply to this email.
    </p>
    <p style="margin-top:16px;font-size:13px;color:#222;">
      Warm regards,<br>
      <strong>${companyName}</strong>
      ${orgPhone ? `<br><span style="color:#555;font-size:12px;">${orgPhone}</span>` : ''}
      ${orgEmail ? `<br><span style="color:#555;font-size:12px;">${orgEmail}</span>` : ''}
    </p>
  </div>

  <!-- FOOTER -->
  <div style="background:#f4f4f4;border-top:1px solid #ddd;padding:16px 32px;font-size:11px;color:#777;text-align:center;line-height:1.7;">
    <strong style="color:#333;">${companyName}</strong>
    ${orgGST   ? ` &nbsp;|&nbsp; GST: ${orgGST}`   : ''}
    ${orgPhone ? ` &nbsp;|&nbsp; ${orgPhone}`       : ''}
    ${orgEmail ? ` &nbsp;|&nbsp; ${orgEmail}`       : ''}
    <br>This is an automated reminder. Please do not reply if payment has already been made.
  </div>

</div>
</body>
</html>`;
}

// ============================================================================
// BUILD TEMPLATE VARS
// ============================================================================

function buildTemplateVars(invoice, orgData, type) {
  const now = new Date();
  return {
    invoiceNumber:  invoice.invoiceNumber || '',
    customerName:   invoice.customerName  || 'Customer',
    amount:         (invoice.totalAmount  || 0).toFixed(2),
    amountDue:      (invoice.amountDue    || 0).toFixed(2),
    dueDate:        new Date(invoice.dueDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }),
    companyName:    orgData?.orgName           || 'Accounts Team',
    orgGST:         orgData?.gstNumber         || '',
    orgPhone:       orgData?.phone             || '',
    orgEmail:       orgData?.email             || '',
    accountHolder:  orgData?.bankAccountHolder || '',
    bankAccount:    orgData?.bankAccountNumber || '',
    ifscCode:       orgData?.bankIfscCode      || '',
    bankName:       orgData?.bankName          || '',
    upiId:          orgData?.upiId             || '',
    daysOverdue: type === 'overdue'
      ? String(Math.max(0, Math.floor((Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) - Date.UTC(new Date(invoice.dueDate).getFullYear(), new Date(invoice.dueDate).getMonth(), new Date(invoice.dueDate).getDate())) / 86400000)))
      : '0',
    daysBefore: type === 'predue'
      ? String(Math.max(0, Math.floor((Date.UTC(new Date(invoice.dueDate).getFullYear(), new Date(invoice.dueDate).getMonth(), new Date(invoice.dueDate).getDate()) - Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000)))
      : '0',
  };
}

// ============================================================================
// PROCESS ONE INVOICE
// ============================================================================

async function processInvoice(invoice, settings, orgData, type) {
  const now  = new Date();
  const vars = buildTemplateVars(invoice, orgData, type);
  const channel    = settings.channel || 'email';
  const logEntries = [];

  // EMAIL
  if (channel === 'email' || channel === 'both') {
    try {
      let subject, html;
      if (type === 'overdue') {
        subject = settings.emailSubjectTemplate
          ? renderTemplate(settings.emailSubjectTemplate, vars)
          : `Payment Overdue — Invoice ${vars.invoiceNumber} (${vars.daysOverdue} days)`;
        html = settings.emailTemplate
          ? renderTemplate(settings.emailTemplate, vars)
          : buildOverdueEmailHtml(vars);
      } else {
        subject = settings.emailSubjectPreDue
          ? renderTemplate(settings.emailSubjectPreDue, vars)
          : `Payment Due in ${vars.daysBefore} Day${parseInt(vars.daysBefore) === 1 ? '' : 's'} — Invoice ${vars.invoiceNumber}`;
        html = settings.emailTemplatePreDue
          ? renderTemplate(settings.emailTemplatePreDue, vars)
          : buildPreDueEmailHtml(vars);
      }

      // Generate PDF for attachment
      let attachments = [];
      try {
        const { generateInvoicePDF } = require('../routes/invoices');
        const pdfInfo = await generateInvoicePDF(invoice, invoice.orgId, invoice.branchId);
        attachments = [{
          filename: `Invoice-${invoice.invoiceNumber}.pdf`,
          path:     pdfInfo.filepath,
        }];
      } catch (pdfErr) {
        console.warn(`⚠️ Could not generate PDF for reminder — ${invoice.invoiceNumber}:`, pdfErr.message);
      }

      await sendMail({
        orgId:       invoice.orgId,
        branchId:    invoice.branchId,
        db:          mongoose.connection.db,
        to:          invoice.customerEmail,
        cc:          (Array.isArray(settings.ccEmails) && settings.ccEmails.length > 0)
                       ? settings.ccEmails.filter(e => e && e.trim()).join(',')
                       : undefined,
        subject,
        html,
        attachments,
      });

      logEntries.push({ sentAt: now, channel: 'email', type, success: true, recipientEmail: invoice.customerEmail });
      console.log(`✅ Reminder email sent — ${invoice.invoiceNumber} → ${invoice.customerEmail}`);
    } catch (err) {
      logEntries.push({ sentAt: now, channel: 'email', type, success: false, failReason: err.message });
      console.error(`❌ Reminder email failed — ${invoice.invoiceNumber}:`, err.message);
    }
  }

  // WHATSAPP
  if (channel === 'whatsapp' || channel === 'both') {
    try {
      const defaultWaOverdue =
        `Hello ${vars.customerName},\n\nInvoice *${vars.invoiceNumber}* from *${vars.companyName}* is *${vars.daysOverdue} day(s) overdue*.\n\nBalance Due: Rs. ${vars.amountDue}\nWas Due: ${vars.dueDate}\n\nPlease arrange payment at the earliest.\n\nThank you!`;
      const defaultWaPredue =
        `Hello ${vars.customerName},\n\nInvoice *${vars.invoiceNumber}* from *${vars.companyName}* is due in *${vars.daysBefore} day(s)*.\n\nAmount Due: Rs. ${vars.amountDue}\nDue Date: ${vars.dueDate}\n\nPlease arrange payment before the due date.\n\nThank you!`;

      const message = type === 'overdue'
        ? (settings.whatsappTemplate ? renderTemplate(settings.whatsappTemplate, vars) : defaultWaOverdue)
        : (settings.whatsappTemplatePreDue ? renderTemplate(settings.whatsappTemplatePreDue, vars) : defaultWaPredue);

      // Resolve credentials — prefer branch/org data, fall back to settings
      const phoneNumberId = orgData?.whatsappMetaPhoneNumberId || settings.whatsappMetaPhoneNumberId;
      const wabaId        = orgData?.whatsappMetaWabaId        || settings.whatsappMetaWabaId;
      const rawToken      = orgData?.whatsappMetaAccessToken   || settings.whatsappMetaAccessToken;
      const accessToken   = (() => {
        if (!rawToken) return null;
        try { const { decrypt } = require('../utils/encryption'); return decrypt(rawToken); } catch (_) { return rawToken; }
      })();

      // Resolve which template to use for this reminder type
      // Settings can store per-type template names: whatsappOverdueTemplateName / whatsappPreDueTemplateName
      const templateName     = type === 'overdue'
        ? (settings.whatsappOverdueTemplateName || settings.whatsappTemplateName || null)
        : (settings.whatsappPreDueTemplateName  || settings.whatsappTemplateName || null);
      const templateLanguage = settings.whatsappTemplateLanguage || 'en';

      // Build template parameters matching the payment_reminder template:
      // {{1}} = customer name, {{2}} = invoice number, {{3}} = company name,
      // {{4}} = amount due,    {{5}} = due date
      const templateParams = [
        vars.customerName,
        vars.invoiceNumber,
        vars.companyName,
        vars.amountDue,
        vars.dueDate,
      ];

      const waResult = await sendWhatsAppMessage({
        phoneNumberId,
        accessToken,
        wabaId,
        toPhone:          invoice.customerPhone,
        message,          // used as fallback text if no template
        templateName,
        templateLanguage,
        templateParams,   // {{1}}..{{5}} values
      });

      logEntries.push({
        sentAt:         now,
        channel:        'whatsapp',
        type,
        success:        waResult.success,
        failReason:     waResult.success ? undefined : waResult.error,
        recipientPhone: invoice.customerPhone,
        templateUsed:   waResult.templateUsed || null,
      });

      if (waResult.success) {
        if (waResult.usedText) {
          console.warn(`⚠️ [WA] ${invoice.invoiceNumber} — sent as TEXT (no approved template). May not deliver.`);
        } else {
          console.log(`✅ [WA] ${invoice.invoiceNumber} — sent via template "${waResult.templateUsed}"`);
        }
      } else {
        console.warn(`❌ [WA] ${invoice.invoiceNumber} failed: ${waResult.error}`);
      }
    } catch (err) {
      logEntries.push({ sentAt: now, channel: 'whatsapp', type, success: false, failReason: err.message });
      console.error(`❌ [WA] processInvoice error for ${invoice.invoiceNumber}:`, err.message);
    }
  }

  return logEntries;
}

// ============================================================================
// BLACKOUT CHECK
// ============================================================================

function isBlackedOut(settings) {
  const now       = new Date();
  const dayOfWeek = now.getDay();
  const currentHr = now.getHours();
  if ((settings.blackoutDays || []).includes(dayOfWeek)) return { blacked: true };
  const startHr = settings.blackoutStartHour ?? 22;
  const endHr   = settings.blackoutEndHour   ?? 8;
  // startHr === endHr means no blackout window configured
  if (startHr === endHr) return { blacked: false };
  if (startHr > endHr) {
    // Wraps midnight e.g. 22:00 → 08:00
    if (currentHr >= startHr || currentHr < endHr) return { blacked: true };
  } else {
    if (currentHr >= startHr && currentHr < endHr) return { blacked: true };
  }
  return { blacked: false };
}

function isReminderHour(settings) {
  if (!settings.reminderTime) return true;
  const [hh, mm] = settings.reminderTime.split(':').map(Number);
  const now = new Date();
  // Match the configured hour:minute window (fires within that minute)
  return now.getHours() === hh && now.getMinutes() === (mm || 0);
}

// ============================================================================
// MAIN SCHEDULER
// ============================================================================

async function runReminderJob() {
  console.log(`\n🔔 [${new Date().toISOString()}] Running invoice reminder job...`);
  const Invoice          = getInvoiceModel();
  const ReminderSettings = getReminderSettingsModel();
  if (!Invoice || !ReminderSettings) { console.warn('⚠️ Models not ready'); return; }

  try {
    const allSettings = await ReminderSettings.find({ enabled: true }).lean();
    if (!allSettings.length) { console.log('ℹ️ No active reminder settings found'); return; }

    console.log(`📋 Found ${allSettings.length} active reminder setting(s)`);

    for (const settings of allSettings) {
      console.log(`\n⚙️  Processing settings — orgId: ${settings.orgId}, branchId: ${settings.branchId || 'none'}, channel: ${settings.channel}, reminderTime: ${settings.reminderTime}`);

      const { blacked } = isBlackedOut(settings);
      if (blacked) { console.log('🚫 Skipping — blackout period'); continue; }

      if (!isReminderHour(settings)) {
        const now = new Date();
        console.log(`⏰ Skipping — not reminder time (now: ${now.getHours()}:${String(now.getMinutes()).padStart(2,'0')}, configured: ${settings.reminderTime})`);
        continue;
      }

      let orgData = null;
      try {
        const { getEffectiveOrgData } = require('../routes/branches');
        orgData = await getEffectiveOrgData(settings.orgId, settings.branchId, mongoose.connection.db);
      } catch (_) {}

      // Resolve WhatsApp credentials — prefer branch orgData, fall back to settings doc
      const phoneNumberId = orgData?.whatsappMetaPhoneNumberId || settings.whatsappMetaPhoneNumberId;
      const wabaId        = orgData?.whatsappMetaWabaId        || settings.whatsappMetaWabaId;
      const rawToken      = orgData?.whatsappMetaAccessToken   || settings.whatsappMetaAccessToken;
      const accessToken   = (() => {
        if (!rawToken) return null;
        try { const { decrypt } = require('../utils/encryption'); return decrypt(rawToken); } catch (_) { return rawToken; }
      })();

      console.log(`🔑 WA credentials — phoneNumberId: ${phoneNumberId ? '✅' : '❌ missing'}, wabaId: ${wabaId ? '✅' : '❌ missing'}, token: ${accessToken ? '✅' : '❌ missing'}`);

      const now        = new Date();
      const graceDays  = settings.gracePeriodDays ?? 1;
      const maxCap     = settings.maxReminderCap  ?? 10;
      const freqDays   = settings.frequencyDays   ?? 1;
      const preDueDays = settings.preDueDays      ?? 0;

      // Overdue invoices
      const graceCutoff = new Date(now.getTime() - graceDays * 86400000);
      const overdueInvoices = await Invoice.find({
        orgId:          settings.orgId,
        status:         { $in: ['OVERDUE', 'UNPAID', 'PARTIALLY_PAID', 'SENT'] },
        dueDate:        { $lt: graceCutoff },
        reminderPaused: { $ne: true },
        $or: [
          { reminderCount: { $exists: false } },
          { reminderCount: null },
          { reminderCount: { $lt: maxCap } },
        ],
        ...(settings.branchId ? { branchId: settings.branchId } : {}),
      }).lean();

      console.log(`📄 Overdue invoices found: ${overdueInvoices.length}`);

      for (const invoice of overdueInvoices) {
        // Skip if no contact for the chosen channel
        if ((settings.channel === 'email' || settings.channel === 'both') && !invoice.customerEmail) {
          console.log(`⚠️ Skipping ${invoice.invoiceNumber} — no customer email`);
          continue;
        }
        if ((settings.channel === 'whatsapp' || settings.channel === 'both') && !invoice.customerPhone) {
          console.log(`⚠️ Skipping ${invoice.invoiceNumber} — no customer phone`);
          continue;
        }

        // Frequency throttle — use <= so exactly freqDays gap is required
        const log          = invoice.reminderLog || [];
        const lastReminder = log.length > 0 ? log[log.length - 1] : null;
        if (lastReminder && (now - new Date(lastReminder.sentAt)) / 86400000 <= freqDays) {
          console.log(`⏭️  Skipping ${invoice.invoiceNumber} — last reminder sent ${((now - new Date(lastReminder.sentAt)) / 3600000).toFixed(1)}h ago (frequency: every ${freqDays} day(s))`);
          continue;
        }

        // Re-check invoice status right before sending (customer may have paid)
        const freshInvoice = await Invoice.findById(invoice._id).lean();
        if (!freshInvoice || freshInvoice.status === 'PAID' || freshInvoice.status === 'CANCELLED') continue;

        const logEntries = await processInvoice(invoice, settings, orgData, 'overdue');
        await Invoice.updateOne(
          { _id: invoice._id },
          {
            $push: {
              reminderLog: { $each: logEntries },
              // Also record in emailsSent so it shows in customer Mails tab
              emailsSent: {
                $each: logEntries
                  .filter(e => e.channel === 'email' && e.success)
                  .map(e => ({
                    sentTo:    e.recipientEmail,
                    sentAt:    e.sentAt,
                    emailType: 'reminder',
                  })),
              },
            },
            $inc: { reminderCount: 1 },
            $set: { lastReminderSentAt: now },
          },
        );
      }

      // Pre-due invoices
      if (preDueDays > 0) {
        const preDueStart    = new Date(now.getTime() + (preDueDays - 0.5) * 86400000);
        const preDueEnd      = new Date(now.getTime() + (preDueDays + 0.5) * 86400000);
        const preDueInvoices = await Invoice.find({
          orgId:          settings.orgId,
          status:         { $in: ['UNPAID', 'SENT', 'PARTIALLY_PAID'] },
          dueDate:        { $gte: preDueStart, $lte: preDueEnd },
          reminderPaused: { $ne: true },
          ...(settings.branchId ? { branchId: settings.branchId } : {}),
        }).lean();

        for (const invoice of preDueInvoices) {
          if ((settings.channel === 'email' || settings.channel === 'both') && !invoice.customerEmail) {
            console.log(`⚠️ Skipping pre-due ${invoice.invoiceNumber} — no customer email`);
            continue;
          }
          const log = invoice.reminderLog || [];
          // Prevent duplicate pre-due for same window (store preDueDays in log)
          const alreadySent = log.some(l =>
            l.type === 'predue' &&
            l.preDueDays === preDueDays &&
            new Date(l.sentAt).toDateString() === now.toDateString()
          );
          if (alreadySent) continue;

          // Re-check status before sending
          const freshInvoice = await Invoice.findById(invoice._id).lean();
          if (!freshInvoice || freshInvoice.status === 'PAID' || freshInvoice.status === 'CANCELLED') continue;

          const logEntries = await processInvoice(invoice, settings, orgData, 'predue');
          // Tag each log entry with preDueDays for dedup
          logEntries.forEach(e => { e.preDueDays = preDueDays; });
          await Invoice.updateOne({ _id: invoice._id }, { $push: { reminderLog: { $each: logEntries } } });
        }
      }
    }
    console.log(`✅ Reminder job complete — ${new Date().toISOString()}\n`);
  } catch (err) {
    console.error('❌ Reminder job error:', err.message);
  }
}

// ============================================================================
// REMINDER SETTINGS SCHEMA
// ============================================================================

const reminderSettingsSchema = new mongoose.Schema({
  orgId:    { type: String, required: true, index: true },
  branchId: { type: String, default: null,  index: true },
  enabled:  { type: Boolean, default: false },
  channel:  { type: String, enum: ['email', 'whatsapp', 'both'], default: 'email' },
  frequencyDays:        { type: Number, default: 1,  min: 1 },
  reminderTime:         { type: String, default: '10:00' },
  gracePeriodDays:      { type: Number, default: 1,  min: 0 },
  maxReminderCap:       { type: Number, default: 10, min: 1 },
  preDueDays:           { type: Number, default: 0,  min: 0 },
  blackoutDays:         { type: [Number], default: [] },
  blackoutStartHour:    { type: Number, default: 22 },
  blackoutEndHour:      { type: Number, default: 8  },
  ccEmails:             { type: [String], default: [] },
  emailSubjectTemplate: { type: String, default: '' },
  emailTemplate:        { type: String, default: '' },
  emailSubjectPreDue:   { type: String, default: '' },
  emailTemplatePreDue:  { type: String, default: '' },
  whatsappTemplate:        { type: String, default: '' },
  whatsappTemplatePreDue:  { type: String, default: '' },
  whatsappMetaPhoneNumberId: { type: String, default: '' },
  whatsappMetaAccessToken:   { type: String, default: '' },
  whatsappMetaWabaId:        { type: String, default: '' },
  // ── Template names (approved Meta templates to use for reminders) ──────────
  whatsappTemplateName:         { type: String, default: '' }, // fallback for both types
  whatsappOverdueTemplateName:  { type: String, default: '' }, // overdue-specific
  whatsappPreDueTemplateName:   { type: String, default: '' }, // pre-due-specific
  whatsappTemplateLanguage:     { type: String, default: 'en' },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
}, { timestamps: true });

reminderSettingsSchema.index({ orgId: 1, branchId: 1 }, { unique: true });

const ReminderSettings = mongoose.models.ReminderSettings
  || mongoose.model('ReminderSettings', reminderSettingsSchema);

// ============================================================================
// SETTINGS ROUTES
// ============================================================================

const express        = require('express');
const settingsRouter = express.Router();

// GET settings
settingsRouter.get('/', async (req, res) => {
  try {
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    let settings   = await ReminderSettings.findOne({ orgId: req.user?.orgId, branchId }).lean();
    if (!settings) {
      settings = {
        enabled: false, channel: 'email',
        frequencyDays: 1, reminderTime: '10:00',
        gracePeriodDays: 1, maxReminderCap: 10, preDueDays: 0,
        blackoutDays: [0], blackoutStartHour: 22, blackoutEndHour: 8,
        ccEmails: [],
        emailSubjectTemplate: '', emailTemplate: '',
        emailSubjectPreDue: '', emailTemplatePreDue: '',
        whatsappTemplate: '', whatsappTemplatePreDue: '',
        whatsappMetaPhoneNumberId: '', whatsappMetaAccessToken: '', whatsappMetaWabaId: '',
        whatsappTemplateName: '', whatsappOverdueTemplateName: '', whatsappPreDueTemplateName: '',
        whatsappTemplateLanguage: 'en',
      };
    }
    if (settings.whatsappMetaAccessToken) settings.whatsappMetaAccessToken = '••••••••';
    res.json({ success: true, data: settings });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// PUT save settings
settingsRouter.put('/', async (req, res) => {
  try {
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const body     = { ...req.body };
    if (body.whatsappMetaAccessToken === '••••••••') delete body.whatsappMetaAccessToken;
    const settings = await ReminderSettings.findOneAndUpdate(
      { orgId: req.user?.orgId, branchId },
      { ...body, orgId: req.user?.orgId, branchId, updatedAt: new Date() },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    );
    const safe = settings.toObject();
    if (safe.whatsappMetaAccessToken) safe.whatsappMetaAccessToken = '••••••••';
    res.json({ success: true, message: 'Reminder settings saved', data: safe });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /preview/:type — returns rendered HTML for preview dialog
settingsRouter.get('/preview/:type', async (req, res) => {
  try {
    const type     = req.params.type;
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;

    let orgData = null;
    try {
      const { getEffectiveOrgData } = require('../routes/branches');
      orgData = await getEffectiveOrgData(req.user?.orgId, branchId, mongoose.connection.db);
    } catch (_) {}

    const settings = await ReminderSettings.findOne({ orgId: req.user?.orgId, branchId }).lean() || {};

    const vars = {
      invoiceNumber:  'INV-2024-0042',
      customerName:   'Rajesh Kumar',
      amount:         '25,000.00',
      amountDue:      '25,000.00',
      dueDate:        new Date().toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }),
      companyName:    orgData?.orgName           || 'Your Company',
      orgGST:         orgData?.gstNumber         || '27AABCT1332L1Z8',
      orgPhone:       orgData?.phone             || '+91 98765 43210',
      orgEmail:       orgData?.email             || 'accounts@yourcompany.com',
      accountHolder:  orgData?.bankAccountHolder || 'Your Company Pvt Ltd',
      bankAccount:    orgData?.bankAccountNumber || '1234567890',
      ifscCode:       orgData?.bankIfscCode      || 'HDFC0001234',
      bankName:       orgData?.bankName          || 'HDFC Bank',
      upiId:          orgData?.upiId             || 'yourcompany@hdfcbank',
      daysOverdue:    '5',
      daysBefore:     '3',
    };

    let html, subject;
    if (type === 'overdue') {
      subject = settings.emailSubjectTemplate
        ? renderTemplate(settings.emailSubjectTemplate, vars)
        : `Payment Overdue — Invoice ${vars.invoiceNumber} (${vars.daysOverdue} days)`;
      html = settings.emailTemplate
        ? renderTemplate(settings.emailTemplate, vars)
        : buildOverdueEmailHtml(vars);
    } else {
      subject = settings.emailSubjectPreDue
        ? renderTemplate(settings.emailSubjectPreDue, vars)
        : `Payment Due in ${vars.daysBefore} Days — Invoice ${vars.invoiceNumber}`;
      html = settings.emailTemplatePreDue
        ? renderTemplate(settings.emailTemplatePreDue, vars)
        : buildPreDueEmailHtml(vars);
    }

    res.json({ success: true, data: { subject, html, type } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /whatsapp-preview/:type — returns WhatsApp message text for preview
settingsRouter.get('/whatsapp-preview/:type', async (req, res) => {
  try {
    const type     = req.params.type; // 'overdue' or 'predue'
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;

    let orgData = null;
    try {
      const { getEffectiveOrgData } = require('../routes/branches');
      orgData = await getEffectiveOrgData(req.user?.orgId, branchId, mongoose.connection.db);
    } catch (_) {}

    const settings = await ReminderSettings.findOne({
      orgId: req.user?.orgId, branchId
    }).lean() || {};

    const vars = {
      invoiceNumber: 'INV-2024-0042',
      customerName:  'Rajesh Kumar',
      customerPhone: '+91 98765 43210',
      amount:        '25,000.00',
      amountDue:     '25,000.00',
      dueDate:       new Date().toLocaleDateString('en-IN', {
        day: '2-digit', month: 'short', year: 'numeric'
      }),
      companyName:   orgData?.orgName   || 'Your Company',
      orgPhone:      orgData?.phone     || '+91 98765 43210',
      orgEmail:      orgData?.email     || 'accounts@yourcompany.com',
      bankAccount:   orgData?.bankAccountNumber || '1234567890',
      ifscCode:      orgData?.bankIfscCode      || 'HDFC0001234',
      bankName:      orgData?.bankName          || 'HDFC Bank',
      accountHolder: orgData?.bankAccountHolder || 'Your Company Pvt Ltd',
      upiId:         orgData?.upiId             || 'yourcompany@hdfcbank',
      daysOverdue:   '5',
      daysBefore:    '3',
    };

    const defaultWaOverdue =
      `Hello ${vars.customerName},\n\nInvoice *${vars.invoiceNumber}* from *${vars.companyName}* is *${vars.daysOverdue} day(s) overdue*.\n\nBalance Due: Rs. ${vars.amountDue}\nWas Due: ${vars.dueDate}\n\nPlease arrange payment at the earliest.\n\nThank you!`;

    const defaultWaPredue =
      `Hello ${vars.customerName},\n\nInvoice *${vars.invoiceNumber}* from *${vars.companyName}* is due in *${vars.daysBefore} day(s)*.\n\nAmount Due: Rs. ${vars.amountDue}\nDue Date: ${vars.dueDate}\n\nPlease arrange payment before the due date.\n\nThank you!`;

    let message;
    if (type === 'overdue') {
      message = settings.whatsappTemplate
        ? renderTemplate(settings.whatsappTemplate, vars)
        : defaultWaOverdue;
    } else {
      message = settings.whatsappTemplatePreDue
        ? renderTemplate(settings.whatsappTemplatePreDue, vars)
        : defaultWaPredue;
    }

    res.json({
      success: true,
      data: {
        type,
        message,
        testPhone: vars.customerPhone,
        invoiceNumber: vars.invoiceNumber,
        customerName:  vars.customerName,
      },
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /test-email
settingsRouter.post('/test-email', async (req, res) => {
  try {
    const branchId = req.branchIds?.length > 0 ? req.branchIds[0] : null;
    const type     = req.body.type || 'overdue';

    let orgData = null;
    try {
      const { getEffectiveOrgData } = require('../routes/branches');
      orgData = await getEffectiveOrgData(req.user?.orgId, branchId, mongoose.connection.db);
    } catch (_) {}

    const settings = await ReminderSettings.findOne({ orgId: req.user?.orgId, branchId }).lean() || {};

    const vars = {
      invoiceNumber:  'INV-2024-0042',
      customerName:   'Rajesh Kumar',
      amount:         '25,000.00',
      amountDue:      '25,000.00',
      dueDate:        new Date().toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }),
      companyName:    orgData?.orgName           || req.body.companyName || 'Your Company',
      orgGST:         orgData?.gstNumber         || '',
      orgPhone:       orgData?.phone             || '',
      orgEmail:       orgData?.email             || '',
      accountHolder:  orgData?.bankAccountHolder || '',
      bankAccount:    orgData?.bankAccountNumber || '',
      ifscCode:       orgData?.bankIfscCode      || '',
      bankName:       orgData?.bankName          || '',
      upiId:          orgData?.upiId             || '',
      daysOverdue:    '5',
      daysBefore:     '3',
    };

    let subject, html;
    if (type === 'overdue') {
      subject = settings.emailSubjectTemplate
        ? renderTemplate(settings.emailSubjectTemplate, vars)
        : `Payment Overdue — Invoice ${vars.invoiceNumber} (${vars.daysOverdue} days)`;
      html = settings.emailTemplate
        ? renderTemplate(settings.emailTemplate, vars)
        : buildOverdueEmailHtml(vars);
    } else {
      subject = settings.emailSubjectPreDue
        ? renderTemplate(settings.emailSubjectPreDue, vars)
        : `Payment Due in ${vars.daysBefore} Days — Invoice ${vars.invoiceNumber}`;
      html = settings.emailTemplatePreDue
        ? renderTemplate(settings.emailTemplatePreDue, vars)
        : buildPreDueEmailHtml(vars);
    }

    await sendMail({
      orgId:    req.user?.orgId,
      branchId,
      db:       mongoose.connection.db,
      to:       req.body.testEmail || req.user?.email,
      cc:       (Array.isArray(settings.ccEmails) && settings.ccEmails.length > 0)
                  ? settings.ccEmails.filter(e => e && e.trim()).join(',')
                  : undefined,
      subject,
      html,
    });

    res.json({ success: true, message: `Test ${type} email sent to ${req.body.testEmail || req.user?.email}` });
  } catch (err) {
    console.error('Test email error:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================================
// INIT CRON
// ============================================================================

function initReminderScheduler() {
  console.log('🕐 Initializing invoice reminder scheduler...');
  cron.schedule('* * * * *', async () => { await runReminderJob(); });
  console.log('✅ Reminder scheduler started — runs every hour at :00');
}

// ============================================================================
// WHATSAPP MESSAGE BUILDERS (for manual reminders)
// ============================================================================

function buildOverdueWhatsAppMessage(vars) {
  return `Hello ${vars.customerName},\n\nInvoice *${vars.invoiceNumber}* from *${vars.companyName}* is *${vars.daysOverdue} day(s) overdue*.\n\nBalance Due: Rs. ${vars.amountDue}\nWas Due: ${vars.dueDate}\n\nPlease arrange payment at the earliest.\n\nThank you!`;
}

function buildPreDueWhatsAppMessage(vars) {
  return `Hello ${vars.customerName},\n\nInvoice *${vars.invoiceNumber}* from *${vars.companyName}* is due in *${vars.daysBefore} day(s)*.\n\nAmount Due: Rs. ${vars.amountDue}\nDue Date: ${vars.dueDate}\n\nPlease arrange payment before the due date.\n\nThank you!`;
}

module.exports = {
  initReminderScheduler,
  settingsRouter,
  ReminderSettings,
  runReminderJob,
  buildOverdueEmailHtml,
  buildPreDueEmailHtml,
  buildOverdueWhatsAppMessage,
  buildPreDueWhatsAppMessage,
  buildTemplateVars,
  renderTemplate,
  sendWhatsAppMessage,
};