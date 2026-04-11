// ============================================================================
// E-WAY BILL NIC SERVICE — COMPLETE REAL IMPLEMENTATION
// ============================================================================
// File: backend/services/eway_bill_nic_service.js
//
// REAL MODE:
//   .env → EWB_MOCK_MODE=false
//   .env → EWB_NIC_BASE_URL=https://einvoice1.gst.gov.in/eway
//   Finance team enters GSTIN + Username + Password in the app
//   Credentials saved encrypted in MongoDB
//   Auth token auto-refreshes every 6 hours
//
// MOCK MODE (development):
//   .env → EWB_MOCK_MODE=true
//   All calls return realistic fake data — no NIC connection needed
// ============================================================================

const crypto = require('crypto');

const USE_MOCK = process.env.EWB_MOCK_MODE !== 'false';
const NIC_BASE = (process.env.EWB_NIC_BASE_URL || 'https://einvoice1.gst.gov.in/eway').replace(/\/$/, '');

if (USE_MOCK) {
  console.log('🔵 [EWB] MOCK mode — set EWB_MOCK_MODE=false in .env to use real NIC API');
} else {
  console.log(`🟢 [EWB] REAL mode — NIC URL: ${NIC_BASE}`);
}

// ── AES-256-CBC encryption for storing passwords in MongoDB ──────────────────
const _rawKey = process.env.EWB_ENCRYPTION_KEY || 'abra_finance_ewb_default_key_32c';
const ENC_KEY  = Buffer.from(
  crypto.createHash('sha256').update(_rawKey).digest('hex').slice(0, 32)
);

function encryptPassword(plainText) {
  const iv     = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', ENC_KEY, iv);
  let enc = cipher.update(plainText, 'utf8', 'hex');
  enc    += cipher.final('hex');
  return iv.toString('hex') + ':' + enc;
}

function decryptPassword(encryptedText) {
  const [ivHex, enc] = encryptedText.split(':');
  const decipher = crypto.createDecipheriv('aes-256-cbc', ENC_KEY, Buffer.from(ivHex, 'hex'));
  let dec = decipher.update(enc, 'hex', 'utf8');
  dec    += decipher.final('utf8');
  return dec;
}

// ── Validity calculation (government rules) ───────────────────────────────────
function calculateValidity(distanceKm, vehicleType = 'REGULAR') {
  const dist = parseInt(distanceKm) || 0;
  let days;
  if      (dist <= 100)  days = 1;
  else if (dist <= 300)  days = 3;
  else if (dist <= 500)  days = 5;
  else if (dist <= 1000) days = 10;
  else                   days = 15;
  if (vehicleType === 'OVER_DIMENSIONAL_CARGO') days *= 2;

  const validUntil = new Date();
  validUntil.setDate(validUntil.getDate() + days);
  validUntil.setHours(23, 59, 59, 999);
  return { validityDays: days, validUntil };
}

function _mockEWBNumber() {
  return String(Math.floor(100000000000 + Math.random() * 900000000000));
}

// =============================================================================
// MOCK IMPLEMENTATIONS
// =============================================================================

function _mockValidateCredentials(gstin, username, password) {
  if (!gstin || gstin.trim().length !== 15) {
    return { success: false, message: 'Invalid GSTIN — must be exactly 15 characters' };
  }
  if (!username || !username.trim()) {
    return { success: false, message: 'Username is required' };
  }
  if (!password || !password.trim()) {
    return { success: false, message: 'Password is required' };
  }
  // Simulate wrong credentials for testing
  if (password === 'wrongpassword') {
    return { success: false, message: 'Invalid username or password. Please check your EWB portal credentials.' };
  }
  return {
    success:        true,
    message:        `Connected successfully to EWB Portal (Mock) — GSTIN: ${gstin}`,
    authToken:      `MOCK_TOKEN_${Date.now()}`,
    sek:            Buffer.from(crypto.randomBytes(32)).toString('base64'),
    tokenExpiresAt: new Date(Date.now() + 6 * 60 * 60 * 1000),
  };
}

function _mockGenerateEWB(partAData, partBData) {
  const ewbNumber = _mockEWBNumber();
  const { validityDays, validUntil } = calculateValidity(
    partAData.approximateDistance || 100,
    partBData?.vehicleType || 'REGULAR'
  );
  const hasVehicle = partBData?.vehicleNumber?.trim().length > 0;
  return {
    success:      true,
    ewbNumber,
    ewbDate:      new Date(),
    validUntil,
    validityDays,
    status:       hasVehicle ? 'GENERATED' : 'PART_A',
    message:      `e-Way Bill ${ewbNumber} generated successfully (Mock)`,
  };
}

function _mockUpdatePartB(ewbNumber) {
  return { success: true, ewbNumber, updatedAt: new Date(), message: `Vehicle details updated for EWB ${ewbNumber} (Mock)` };
}

function _mockCancelEWB(ewbNumber) {
  return { success: true, ewbNumber, cancelledAt: new Date(), message: `EWB ${ewbNumber} cancelled (Mock)` };
}

function _mockExtendValidity(ewbNumber, extData) {
  const { validUntil } = calculateValidity(extData.remainingDistance || 100);
  return { success: true, ewbNumber, newValidUntil: validUntil, extendedAt: new Date(), message: `EWB ${ewbNumber} validity extended (Mock)` };
}

function _mockGenerateConsolidated(ewbNumbers) {
  return {
    success:     true,
    cewbNumber:  `C${_mockEWBNumber()}`,
    generatedAt: new Date(),
    ewbNumbers,
    message:     `Consolidated EWB generated (Mock)`,
  };
}

// =============================================================================
// REAL NIC API — CORRECT IMPLEMENTATION
//
// NIC EWB API Reference: https://einvoice1.gst.gov.in/eway
// Authentication endpoint: POST /ewbapi/authenticate
// All other endpoints require: authtoken header + gstin header
// Payload must be AES-256-ECB encrypted using the SEK (Session Encryption Key)
// =============================================================================

// ── AES-256-ECB encrypt using SEK (NIC requirement) ──────────────────────────
function _encryptWithSEK(data, sekBase64) {
  try {
    const sekBuffer = Buffer.from(sekBase64, 'base64');
    // NIC uses AES-256-ECB with the SEK as key
    const cipher = crypto.createCipheriv('aes-256-ecb', sekBuffer.slice(0, 32), null);
    cipher.setAutoPadding(true);
    let encrypted = cipher.update(JSON.stringify(data), 'utf8', 'base64');
    encrypted    += cipher.final('base64');
    return encrypted;
  } catch (err) {
    console.error('❌ SEK encryption failed:', err.message);
    throw new Error(`SEK encryption failed: ${err.message}`);
  }
}

// ── AES-256-ECB decrypt using SEK (NIC responses are encrypted) ──────────────
function _decryptWithSEK(encryptedBase64, sekBase64) {
  try {
    const sekBuffer = Buffer.from(sekBase64, 'base64');
    const decipher  = crypto.createDecipheriv('aes-256-ecb', sekBuffer.slice(0, 32), null);
    decipher.setAutoPadding(true);
    let decrypted = decipher.update(encryptedBase64, 'base64', 'utf8');
    decrypted    += decipher.final('utf8');
    return JSON.parse(decrypted);
  } catch (err) {
    console.error('❌ SEK decryption failed:', err.message);
    return null;
  }
}

// ── Make NIC API request with correct headers ─────────────────────────────────
async function _nicRequest(method, endpoint, credentials, body = null) {
  const url = `${NIC_BASE}${endpoint}`;
  const headers = {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
  };

  // Add auth headers for all requests except authenticate
  if (credentials?.authToken) {
    headers['authtoken'] = credentials.authToken;
    headers['gstin']     = credentials.gstin || '';
  }

  const options = { method, headers };
  if (body) options.body = JSON.stringify(body);

  console.log(`📡 NIC ${method} ${endpoint}`);
  const response = await fetch(url, options);
  const text     = await response.text();

  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = { status: '0', message: text };
  }

  console.log(`📡 NIC response status: ${data?.status}, HTTP: ${response.status}`);
  return { httpStatus: response.status, data };
}

// ── REAL: Authenticate with NIC EWB portal ────────────────────────────────────
// Correct endpoint: POST /ewbapi/authenticate
// NIC expects: gstin, username, password (base64), app_key (base64 random 32 bytes)
async function _realValidateCredentials(gstin, username, password) {
  try {
    const gstinClean = gstin.trim().toUpperCase();

    // Generate app key — random 32 bytes, base64 encoded
    const appKey = crypto.randomBytes(32).toString('base64');

    // NIC requires password to be base64 encoded
    const passwordB64 = Buffer.from(password).toString('base64');

    const payload = {
      action:   'ACCESSTOKEN',
      gstin:    gstinClean,
      username: username.trim(),
      password: passwordB64,
      app_key:  appKey,
    };

    const response = await fetch(`${NIC_BASE}/ewbapi/authenticate`, {
      method:  'POST',
      headers: {
        'Content-Type': 'application/json',
        'gstin':        gstinClean,
      },
      body: JSON.stringify(payload),
    });

    const text = await response.text();
    let data;
    try { data = JSON.parse(text); } catch { data = { status: '0', message: text }; }

    console.log(`📡 NIC authenticate response:`, JSON.stringify(data).slice(0, 200));

    // NIC returns status '1' for success
    if (data.status === '1' && data.data) {
      let authData = data.data;

      // NIC response data may be encrypted with app_key — try to decrypt
      if (typeof authData === 'string') {
        try {
          const appKeyBuffer = Buffer.from(appKey, 'base64');
          const decipher     = crypto.createDecipheriv('aes-256-ecb', appKeyBuffer.slice(0, 32), null);
          decipher.setAutoPadding(true);
          let decrypted  = decipher.update(authData, 'base64', 'utf8');
          decrypted     += decipher.final('utf8');
          authData       = JSON.parse(decrypted);
        } catch (decErr) {
          console.warn('⚠️ Could not decrypt auth response, using raw:', decErr.message);
        }
      }

      const authToken = authData?.authtoken || authData?.AuthToken || authData?.auth_token;
      const sek       = authData?.sek       || authData?.Sek       || authData?.sessionKey;

      if (!authToken) {
        console.error('❌ No authtoken in NIC response:', JSON.stringify(authData));
        return { success: false, message: 'No auth token received from NIC portal. Please check credentials.' };
      }

      console.log(`✅ NIC auth success for GSTIN: ${gstinClean}`);
      return {
        success:        true,
        authToken,
        sek:            sek || '',
        appKey,
        tokenExpiresAt: new Date(Date.now() + 6 * 60 * 60 * 1000),
        message:        `Connected successfully to EWB Portal — GSTIN: ${gstinClean}`,
      };
    }

    // NIC error responses
    const errMsg = data.message || data.error || data.errorMessage || `Authentication failed`;
    console.error('❌ NIC auth failed:', errMsg, '| Full response:', JSON.stringify(data));

    // Map NIC error codes to user-friendly messages
    let userMessage = errMsg;
    if (errMsg.toLowerCase().includes('invalid') || errMsg.toLowerCase().includes('wrong')) {
      userMessage = 'Invalid username or password. Please check your EWB portal credentials at ewaybillgst.gov.in';
    } else if (errMsg.toLowerCase().includes('gstin') || errMsg.toLowerCase().includes('registered')) {
      userMessage = 'GSTIN not registered on the EWB portal. Please register at ewaybillgst.gov.in first.';
    } else if (errMsg.toLowerCase().includes('block') || errMsg.toLowerCase().includes('lock')) {
      userMessage = 'Account is temporarily blocked. Please visit ewaybillgst.gov.in to unlock.';
    }

    return { success: false, message: userMessage };

  } catch (err) {
    console.error('❌ NIC auth network error:', err.message);
    if (err.message.includes('fetch') || err.message.includes('ENOTFOUND') || err.message.includes('ECONNREFUSED')) {
      return { success: false, message: 'Cannot reach NIC EWB portal. Please check your internet connection and try again.' };
    }
    return { success: false, message: `Connection error: ${err.message}` };
  }
}

// ── REAL: Generate EWB ────────────────────────────────────────────────────────
async function _realGenerateEWB(credentials, partAData, partBData) {
  try {
    if (!credentials?.authToken || !credentials?.sek) {
      return { success: false, message: 'Not connected to EWB portal. Please reconnect.' };
    }

    const payload = {
      supplyType:    partAData.supplyType    || 'O',
      subSupplyType: _subTypeCode(partAData.subType),
      docType:       _docTypeCode(partAData.documentType),
      docNo:         partAData.documentNumber,
      docDate:       _formatNICDate(partAData.documentDate),
      fromGstin:     partAData.fromGstin    || 'URP',
      fromTrdName:   partAData.fromTradeName,
      fromAddr1:     partAData.fromAddress1  || '',
      fromAddr2:     '',
      fromPlace:     partAData.fromPlace,
      fromPincode:   parseInt(partAData.fromPincode)    || 0,
      fromStateCode: parseInt(partAData.fromStateCode)  || 0,
      toGstin:       partAData.toGstin       || 'URP',
      toTrdName:     partAData.toTradeName,
      toAddr1:       partAData.toAddress1    || '',
      toAddr2:       '',
      toPlace:       partAData.toPlace,
      toPincode:     parseInt(partAData.toPincode)      || 0,
      toStateCode:   parseInt(partAData.toStateCode)    || 0,
      itemList: [{
        productName:   partAData.productName  || '',
        productDesc:   partAData.productDesc  || partAData.productName || '',
        hsnCode:       String(partAData.hsnCode),
        quantity:      parseFloat(partAData.quantity)      || 1,
        qtyUnit:       partAData.unit          || 'NOS',
        taxableAmount: parseFloat(partAData.taxableAmount) || 0,
        sgstRate:      parseFloat(partAData.sgstRate)      || 0,
        cgstRate:      parseFloat(partAData.cgstRate)      || 0,
        igstRate:      parseFloat(partAData.igstRate)      || 0,
        cessRate:      parseFloat(partAData.cessRate)      || 0,
        cessNonAdvolRate: 0,
      }],
      totalValue:      parseFloat(partAData.totalInvoiceValue) || 0,
      cgstValue:       parseFloat(partAData.cgstRate)          || 0,
      sgstValue:       parseFloat(partAData.sgstRate)          || 0,
      igstValue:       parseFloat(partAData.igstRate)          || 0,
      cessValue:       0,
      cessNonAdvolValue: 0,
      otherValue:      0,
      totInvValue:     parseFloat(partAData.totalInvoiceValue) || 0,
      transMode:       _transportModeCode(partAData.transportMode),
      transDistance:   parseInt(partAData.approximateDistance) || 0,
      transporterName: partAData.transporterName || '',
      transporterId:   partAData.transporterId   || '',
      transDocNo:      partAData.transDocNo       || '',
      transDocDate:    partAData.transDocDate ? _formatNICDate(partAData.transDocDate) : '',
      vehicleNo:       partBData?.vehicleNumber   || '',
      vehicleType:     partBData?.vehicleType === 'OVER_DIMENSIONAL_CARGO' ? 'O' : 'R',
    };

    // Encrypt payload with SEK
    const encryptedPayload = _encryptWithSEK(payload, credentials.sek);

    const { httpStatus, data } = await _nicRequest('POST', '/ewbapi/generate', credentials, {
      action: 'GENEWAYBILL',
      data:   encryptedPayload,
    });

    // Decrypt response data
    let responseData = data.data;
    if (typeof responseData === 'string' && credentials.sek) {
      responseData = _decryptWithSEK(responseData, credentials.sek) || responseData;
    }

    if (data.status === '1' && (responseData?.ewayBillNo || responseData?.EwbNo)) {
      const ewbNo = String(responseData.ewayBillNo || responseData.EwbNo);
      const { validityDays, validUntil } = calculateValidity(
        partAData.approximateDistance,
        partBData?.vehicleType
      );
      return {
        success:      true,
        ewbNumber:    ewbNo,
        ewbDate:      new Date(),
        validUntil,
        validityDays,
        status:       partBData?.vehicleNumber ? 'GENERATED' : 'PART_A',
        message:      `e-Way Bill ${ewbNo} generated successfully`,
      };
    }

    const errMsg = data.message || responseData?.message || `EWB generation failed (HTTP ${httpStatus})`;
    console.error('❌ NIC generate EWB failed:', errMsg);
    return { success: false, message: errMsg };

  } catch (err) {
    console.error('❌ NIC generate EWB error:', err.message);
    return { success: false, message: `EWB generation error: ${err.message}` };
  }
}

// ── REAL: Update Part B ───────────────────────────────────────────────────────
async function _realUpdatePartB(credentials, ewbNumber, partBData) {
  try {
    if (!credentials?.authToken || !credentials?.sek) {
      return { success: false, message: 'Not connected to EWB portal. Please reconnect.' };
    }
    const payload = {
      ewbNo:        String(ewbNumber),
      vehicleNo:    (partBData.vehicleNumber || '').toUpperCase(),
      fromPlace:    partBData.fromPlace    || '',
      fromState:    parseInt(partBData.fromStateCode) || 0,
      reasonCode:   partBData.reasonCode   || '1',
      reasonRem:    '',
      transDocNo:   partBData.transDocNo   || '',
      transDocDate: partBData.transDocDate ? _formatNICDate(partBData.transDocDate) : '',
      transMode:    _transportModeCode(partBData.transportMode || 'ROAD'),
      vehicleType:  partBData.vehicleType === 'OVER_DIMENSIONAL_CARGO' ? 'O' : 'R',
    };

    const encryptedPayload = _encryptWithSEK(payload, credentials.sek);
    const { data } = await _nicRequest('POST', '/ewbapi/vehewb', credentials, {
      action: 'UPDATEVEHICLE',
      data:   encryptedPayload,
    });

    let responseData = data.data;
    if (typeof responseData === 'string') {
      responseData = _decryptWithSEK(responseData, credentials.sek) || {};
    }

    if (data.status === '1') {
      return { success: true, ewbNumber, updatedAt: new Date(), message: 'Vehicle details updated successfully' };
    }
    return { success: false, message: data.message || responseData?.message || 'Vehicle update failed' };
  } catch (err) {
    return { success: false, message: `Vehicle update error: ${err.message}` };
  }
}

// ── REAL: Cancel EWB ──────────────────────────────────────────────────────────
async function _realCancelEWB(credentials, ewbNumber, cancelReason) {
  try {
    if (!credentials?.authToken || !credentials?.sek) {
      return { success: false, message: 'Not connected to EWB portal. Please reconnect.' };
    }
    const reasonCodeMap = { 'Duplicate': 1, 'Order Cancelled': 2, 'Data Entry Mistake': 3, 'Others': 4 };
    const payload = {
      ewbNo:         String(ewbNumber),
      cancelRsnCode: reasonCodeMap[cancelReason] || 4,
      cancelRmrk:    cancelReason,
    };

    const encryptedPayload = _encryptWithSEK(payload, credentials.sek);
    const { data } = await _nicRequest('POST', '/ewbapi/cancel', credentials, {
      action: 'CANCELEWB',
      data:   encryptedPayload,
    });

    let responseData = data.data;
    if (typeof responseData === 'string') {
      responseData = _decryptWithSEK(responseData, credentials.sek) || {};
    }

    if (data.status === '1') {
      return { success: true, ewbNumber, cancelledAt: new Date(), message: 'EWB cancelled successfully' };
    }
    return { success: false, message: data.message || responseData?.message || 'Cancellation failed' };
  } catch (err) {
    return { success: false, message: `Cancel error: ${err.message}` };
  }
}

// ── REAL: Extend Validity ─────────────────────────────────────────────────────
async function _realExtendValidity(credentials, ewbNumber, extData) {
  try {
    if (!credentials?.authToken || !credentials?.sek) {
      return { success: false, message: 'Not connected to EWB portal. Please reconnect.' };
    }
    const payload = {
      ewbNo:         String(ewbNumber),
      vehicleNo:     (extData.vehicleNumber || '').toUpperCase(),
      fromPlace:     extData.fromPlace      || '',
      fromState:     parseInt(extData.fromStateCode) || 0,
      remainingDist: parseInt(extData.remainingDistance) || 100,
      transMode:     _transportModeCode(extData.transportMode || 'ROAD'),
      extnRsnCode:   1,
      extnRemarks:   extData.reason || '',
    };

    const encryptedPayload = _encryptWithSEK(payload, credentials.sek);
    const { data } = await _nicRequest('POST', '/ewbapi/extendvalidity', credentials, {
      action: 'EXTENDVALIDITY',
      data:   encryptedPayload,
    });

    let responseData = data.data;
    if (typeof responseData === 'string') {
      responseData = _decryptWithSEK(responseData, credentials.sek) || {};
    }

    const { validUntil } = calculateValidity(extData.remainingDistance || 100);
    if (data.status === '1') {
      return { success: true, ewbNumber, newValidUntil: validUntil, extendedAt: new Date(), message: 'Validity extended successfully' };
    }
    return { success: false, message: data.message || responseData?.message || 'Extension failed' };
  } catch (err) {
    return { success: false, message: `Extend validity error: ${err.message}` };
  }
}

// ── REAL: Generate Consolidated EWB ──────────────────────────────────────────
async function _realGenerateConsolidated(credentials, vehicleData, ewbNumbers) {
  try {
    if (!credentials?.authToken || !credentials?.sek) {
      return { success: false, message: 'Not connected to EWB portal. Please reconnect.' };
    }
    const payload = {
      vehicleNo:   (vehicleData.vehicleNumber || '').toUpperCase(),
      fromPlace:   vehicleData.fromPlace   || '',
      fromState:   parseInt(vehicleData.fromStateCode) || 0,
      transMode:   _transportModeCode(vehicleData.transportMode || 'ROAD'),
      vehicleType: 'R',
      ewbNos:      ewbNumbers,
    };

    const encryptedPayload = _encryptWithSEK(payload, credentials.sek);
    const { data } = await _nicRequest('POST', '/ewbapi/cewb', credentials, {
      action: 'GENCEWB',
      data:   encryptedPayload,
    });

    let responseData = data.data;
    if (typeof responseData === 'string') {
      responseData = _decryptWithSEK(responseData, credentials.sek) || {};
    }

    if (data.status === '1' && (responseData?.cEwayBillNo || responseData?.cewbNo)) {
      const cewbNo = String(responseData.cEwayBillNo || responseData.cewbNo);
      return { success: true, cewbNumber: cewbNo, generatedAt: new Date(), ewbNumbers, message: `Consolidated EWB ${cewbNo} generated successfully` };
    }
    return { success: false, message: data.message || responseData?.message || 'Consolidated EWB failed' };
  } catch (err) {
    return { success: false, message: `Consolidated EWB error: ${err.message}` };
  }
}

// ── Helper functions ──────────────────────────────────────────────────────────
function _formatNICDate(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return '';
  const dd   = String(d.getDate()).padStart(2, '0');
  const mm   = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
}

function _transportModeCode(mode) {
  const map = { ROAD: '1', RAIL: '2', AIR: '3', SHIP: '4' };
  return map[(mode || '').toUpperCase()] || '1';
}

function _subTypeCode(subType) {
  const map = {
    SUPPLY: '1', EXPORT: '2', JOB_WORK: '3', 'SKD_CKD': '4',
    'SKD/CKD': '4', FOR_OWN_USE: '5', EXHIBITION_FAIRS: '6',
    EXHIBITION_OR_FAIRS: '6', LINE_SALES: '7', OTHERS: '8',
  };
  return map[subType] || '1';
}

function _docTypeCode(docType) {
  const map = {
    INV: 'INV', BILL_OF_SUPPLY: 'BIL', CREDIT_NOTE: 'CHL',
    DELIVERY_CHALLAN: 'CHL', OTHERS: 'OTH',
  };
  return map[docType] || 'INV';
}

// =============================================================================
// EXPORTED SERVICE
// =============================================================================
const EWBNICService = {

  encryptPassword,
  decryptPassword,
  calculateValidity,

  async validateCredentials(gstin, username, password) {
    if (USE_MOCK) {
      console.log(`🔵 [EWB MOCK] Validate — GSTIN: ${gstin}`);
      return _mockValidateCredentials(gstin, username, password);
    }
    console.log(`🟢 [EWB REAL] Validate — GSTIN: ${gstin}`);
    return _realValidateCredentials(gstin, username, password);
  },

  async generateEWayBill(credentials, partAData, partBData) {
    if (USE_MOCK) {
      console.log(`🔵 [EWB MOCK] Generate — doc: ${partAData.documentNumber}`);
      return _mockGenerateEWB(partAData, partBData);
    }
    console.log(`🟢 [EWB REAL] Generate — doc: ${partAData.documentNumber}`);
    return _realGenerateEWB(credentials, partAData, partBData);
  },

  async updatePartB(credentials, ewbNumber, partBData) {
    if (USE_MOCK) {
      console.log(`🔵 [EWB MOCK] Update Part B — EWB: ${ewbNumber}`);
      return _mockUpdatePartB(ewbNumber);
    }
    console.log(`🟢 [EWB REAL] Update Part B — EWB: ${ewbNumber}`);
    return _realUpdatePartB(credentials, ewbNumber, partBData);
  },

  async cancelEWayBill(credentials, ewbNumber, cancelReason) {
    if (USE_MOCK) {
      console.log(`🔵 [EWB MOCK] Cancel — EWB: ${ewbNumber}`);
      return _mockCancelEWB(ewbNumber);
    }
    console.log(`🟢 [EWB REAL] Cancel — EWB: ${ewbNumber}`);
    return _realCancelEWB(credentials, ewbNumber, cancelReason);
  },

  async extendValidity(credentials, ewbNumber, extData) {
    if (USE_MOCK) {
      console.log(`🔵 [EWB MOCK] Extend — EWB: ${ewbNumber}`);
      return _mockExtendValidity(ewbNumber, extData);
    }
    console.log(`🟢 [EWB REAL] Extend — EWB: ${ewbNumber}`);
    return _realExtendValidity(credentials, ewbNumber, extData);
  },

  async generateConsolidatedEWB(credentials, vehicleData, ewbNumbers) {
    if (USE_MOCK) {
      console.log(`🔵 [EWB MOCK] Consolidated — ${ewbNumbers.length} EWBs`);
      return _mockGenerateConsolidated(ewbNumbers);
    }
    console.log(`🟢 [EWB REAL] Consolidated — ${ewbNumbers.length} EWBs`);
    return _realGenerateConsolidated(credentials, vehicleData, ewbNumbers);
  },
};

module.exports = EWBNICService;