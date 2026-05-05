// =============================================================================
// utils/encryption.js
// Shared AES-256-CBC encrypt / decrypt utility
// Used by: payment_gateway_routes.js, finance_auth.js (SMTP passwords), branches.js
//
// Key source: process.env.PAYMENT_ENC_KEY  (same key for all secrets)
// =============================================================================

'use strict';

const crypto = require('crypto');

const ENC_KEY    = (process.env.PAYMENT_ENC_KEY || 'abra_finance_default_enc_key_32b!').padEnd(32).slice(0, 32);
const ENC_IV_LEN = 16;

/**
 * Encrypt a plain-text string.
 * Returns  "ivHex:encryptedHex"
 */
function encrypt(text) {
  if (!text) return '';
  const iv     = crypto.randomBytes(ENC_IV_LEN);
  const cipher = crypto.createCipheriv('aes-256-cbc', Buffer.from(ENC_KEY), iv);
  const enc    = Buffer.concat([cipher.update(String(text)), cipher.final()]);
  return iv.toString('hex') + ':' + enc.toString('hex');
}

/**
 * Decrypt a string produced by encrypt().
 * Returns the original plain text, or null on failure.
 */
function decrypt(text) {
  if (!text) return null;
  try {
    const [ivHex, encHex] = text.split(':');
    const iv       = Buffer.from(ivHex, 'hex');
    const decipher = crypto.createDecipheriv('aes-256-cbc', Buffer.from(ENC_KEY), iv);
    const dec      = Buffer.concat([decipher.update(Buffer.from(encHex, 'hex')), decipher.final()]);
    return dec.toString();
  } catch (_) {
    return null;
  }
}

module.exports = { encrypt, decrypt };