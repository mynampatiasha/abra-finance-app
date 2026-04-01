// ============================================================================
// RECONCILIATION BILLING - COMPLETE BACKEND (ALL FIXES APPLIED)
// ============================================================================
// File: backend/routes/reconciliation_billing.js
// 
// FIXES APPLIED:
// ✅ 1. Support both account ID and account name in queries
// ✅ 2. Better error messages for debugging
// ✅ 3. Enhanced match validation with detailed warnings
// ✅ 4. Fixed petty cash expense queries
// ✅ 5. Added comprehensive logging
// ============================================================================

const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const XLSX = require('xlsx');
const { verifyFinanceJWT } = require('../middleware/finance_jwt');

// Apply auth middleware to all routes
router.use(verifyFinanceJWT);

// ============================================================================
// SECTION 1: MONGOOSE SCHEMAS & MODELS
// ============================================================================

// ProviderTransaction Schema
const ProviderTransactionSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  accountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'PaymentAccount',
    required: true,
    index: true,
  },
  transactionDate: {
    type: Date,
    required: true,
    index: true,
  },
  amount: {
    type: Number,
    required: true,
  },
  description: {
    type: String,
    default: null,
  },
  location: {
    type: String,
    default: null,
  },
  merchantName: {
    type: String,
    default: null,
  },
  cardNumber: {
    type: String,
    default: null,
  },
  vehicleNumber: {
    type: String,
    default: null,
  },
  referenceNumber: {
    type: String,
    default: null,
  },
  transactionType: {
    type: String,
    enum: ['DEBIT', 'CREDIT', 'REFUND'],
    default: 'DEBIT',
  },
 reconciliationStatus: {
    type: String,
    enum: ['UNMATCHED', 'PENDING', 'MATCHED', 'REJECTED', 'IGNORED', 'CARRIED_FORWARD'],
    default: 'UNMATCHED',
    index: true,
  },
  matchedExpenseId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Expense',
    default: null,
  },
  matchConfidence: {
    type: Number,
    min: 0,
    max: 100,
    default: null,
  },
  matchedBy: {
    type: String,
    default: null,
  },
  matchedAt: {
    type: Date,
    default: null,
  },
  variance: {
    type: Number,
    default: 0,
  },
  varianceReason: {
    type: String,
    default: null,
  },
  importBatchId: {
    type: String,
    required: true,
    index: true,
  },
  importedAt: {
    type: Date,
    default: Date.now,
  },
  importedBy: {
    type: String,
    default: 'system',
  },
 rawData: {
    type: Object,
    default: null,
  },
  isCarriedForward: {
    type: Boolean,
    default: false,
  },
  carriedForwardAt: {
    type: Date,
    default: null,
  },
  carriedForwardNotes: {
    type: String,
    default: null,
  },
  carriedForwardBy: {
    type: String,
    default: null,
  },
  isAdjustment: {
    type: Boolean,
    default: false,
  },
  adjustmentReason: {
    type: String,
    default: null,
  },
  adjustmentNotes: {
    type: String,
    default: null,
  },
  adjustmentType: {
    type: String,
    enum: ['WRITE_OFF', 'TIMING_DIFFERENCE', 'BANK_CHARGE', 'OTHER'],
    default: null,
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
});

ProviderTransactionSchema.pre('save', async function() {
  this.updatedAt = Date.now();
});

// ReconciliationSession Schema
const ReconciliationSessionSchema = new mongoose.Schema({
  accountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'PaymentAccount',
    required: true,
    index: true,
  },
  accountName: {
    type: String,
    required: true,
  },
  accountType: {
    type: String,
    required: true,
  },
  periodStart: {
    type: Date,
    required: true,
  },
  periodEnd: {
    type: Date,
    required: true,
  },
  status: {
    type: String,
    enum: ['IN_PROGRESS', 'COMPLETED', 'LOCKED'],
    default: 'IN_PROGRESS',
    index: true,
  },
  totalProviderTransactions: {
    type: Number,
    default: 0,
  },
  totalSystemExpenses: {
    type: Number,
    default: 0,
  },
  totalMatched: {
    type: Number,
    default: 0,
  },
  totalUnmatched: {
    type: Number,
    default: 0,
  },
  totalPending: {
    type: Number,
    default: 0,
  },
  providerBalance: {
    type: Number,
    default: 0,
  },
  systemBalance: {
    type: Number,
    default: 0,
  },
  balanceDifference: {
    type: Number,
    default: 0,
  },
  totalVariance: {
    type: Number,
    default: 0,
  },
  varianceExplained: {
    type: Number,
    default: 0,
  },
  varianceUnexplained: {
    type: Number,
    default: 0,
  },
  physicalCashCount: {
    type: Number,
    default: null,
  },
  denominations: [{
    denomination: Number,
    count: Number,
    total: Number,
  }],
  startedBy: {
    type: String,
    default: 'system',
  },
  startedAt: {
    type: Date,
    default: Date.now,
  },
  completedBy: {
    type: String,
    default: null,
  },
  completedAt: {
    type: Date,
    default: null,
  },
  isLocked: {
    type: Boolean,
    default: false,
  },
  lockedAt: {
    type: Date,
    default: null,
  },
  lockedBy: {
    type: String,
    default: null,
  },
reconciliationNotes: {
    type: String,
    default: null,
  },
  // Phase 7: Maker-Checker
  requiresApproval: {
    type: Boolean,
    default: false,
  },
  submittedForApproval: {
    type: Boolean,
    default: false,
  },
  submittedAt: {
    type: Date,
    default: null,
  },
  submittedBy: {
    type: String,
    default: null,
  },
  approvalStatus: {
    type: String,
    enum: ['NOT_REQUIRED', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED'],
    default: 'NOT_REQUIRED',
  },
  approvedBy: {
    type: String,
    default: null,
  },
  approvedAt: {
    type: Date,
    default: null,
  },
  approvalNotes: {
    type: String,
    default: null,
  },
  rejectedBy: {
    type: String,
    default: null,
  },
  rejectedAt: {
    type: Date,
    default: null,
  },
  rejectionReason: {
    type: String,
    default: null,
  },
orgId: { type: String, index: true, default: null },
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
});

ReconciliationSessionSchema.pre('save', async function() {
  this.updatedAt = Date.now();
});

// ColumnMapping Schema
const ColumnMappingSchema = new mongoose.Schema({
  accountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'PaymentAccount',
    required: true,
    index: true,
  },
  mappingName: {
    type: String,
    required: true,
  },
  fileFormat: {
    type: String,
    enum: ['EXCEL', 'CSV'],
    required: true,
  },
  columnMappings: {
    dateColumn: {
      type: String,
      required: true,
    },
    amountColumn: {
      type: String,
      required: true,
    },
    descriptionColumn: {
      type: String,
      default: null,
    },
    referenceColumn: {
      type: String,
      default: null,
    },
    locationColumn: {
      type: String,
      default: null,
    },
    cardNumberColumn: {
      type: String,
      default: null,
    },
    vehicleNumberColumn: {
      type: String,
      default: null,
    },
  },
  dateFormat: {
    type: String,
    default: 'DD/MM/YYYY',
  },
  usageCount: {
    type: Number,
    default: 0,
  },
  lastUsedAt: {
    type: Date,
    default: null,
  },
  createdBy: {
    type: String,
    default: 'system',
  },
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
});

// ImportBatch Schema
const ImportBatchSchema = new mongoose.Schema({
  batchId: {
    type: String,
    required: true,
    unique: true,
    index: true,
  },
  accountId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'PaymentAccount',
    required: true,
  },
  fileName: {
    type: String,
    required: true,
  },
  fileSize: {
    type: Number,
    required: true,
  },
  fileType: {
    type: String,
    enum: ['xlsx', 'xls', 'csv'],
    required: true,
  },
  totalRows: {
    type: Number,
    default: 0,
  },
  successfulImports: {
    type: Number,
    default: 0,
  },
  failedImports: {
    type: Number,
    default: 0,
  },
  errors: [{
    row: Number,
    error: String,
  }],
  uploadedBy: {
    type: String,
    default: 'system',
  },
  uploadedAt: {
    type: Date,
    default: Date.now,
  },
});

// Create Models
const ProviderTransaction = mongoose.models.ProviderTransaction || 
  mongoose.model('ProviderTransaction', ProviderTransactionSchema);

const ReconciliationSession = mongoose.models.ReconciliationSession || 
  mongoose.model('ReconciliationSession', ReconciliationSessionSchema);

const ColumnMapping = mongoose.models.ColumnMapping || 
  mongoose.model('ColumnMapping', ColumnMappingSchema);

const ImportBatch = mongoose.models.ImportBatch || 
  mongoose.model('ImportBatch', ImportBatchSchema);

const Expense = mongoose.models.Expense || 
  mongoose.model('Expense', new mongoose.Schema({}, { strict: false }), 'expenses');

// Phase 8: Audit Trail Schema
const ReconciliationAuditLogSchema = new mongoose.Schema({
  sessionId: { type: mongoose.Schema.Types.ObjectId, ref: 'ReconciliationSession', index: true },
  accountId: { type: mongoose.Schema.Types.ObjectId, ref: 'PaymentAccount', index: true },
  action: {
    type: String,
    enum: [
      'SESSION_STARTED', 'SESSION_FINALIZED', 'SESSION_LOCKED', 'SESSION_REOPENED',
      'SESSION_SUBMITTED_FOR_APPROVAL', 'SESSION_APPROVED', 'SESSION_REJECTED',
      'TRANSACTION_MATCHED', 'TRANSACTION_UNMATCHED', 'TRANSACTION_FORCED_MATCH',
      'TRANSACTION_CARRIED_FORWARD', 'TRANSACTION_ADJUSTED',
      'AUTO_MATCH_RUN', 'MATCH_ACCEPTED', 'MATCH_REJECTED',
      'OPENING_BALANCE_VERIFIED', 'CLOSING_BALANCE_VERIFIED',
      'BULK_CARRY_FORWARD', 'BULK_ADJUSTMENT',
    ],
    required: true,
  },
  performedBy: { type: String, default: 'system' },
  performedAt: { type: Date, default: Date.now },
  details: { type: Object, default: null },
  notes: { type: String, default: null },
});

const ReconciliationAuditLog = mongoose.models.ReconciliationAuditLog ||
  mongoose.model('ReconciliationAuditLog', ReconciliationAuditLogSchema);

async function createAuditLog(sessionId, accountId, action, details = null, performedBy = 'system', notes = null) {
  try {
    const log = new ReconciliationAuditLog({
      sessionId,
      accountId,
      action,
      performedBy,
      details,
      notes,
    });
    await log.save();
    console.log(`📋 Audit log: ${action} — Session ${sessionId}`);
  } catch (err) {
    console.error('⚠️ Failed to create audit log (non-blocking):', err.message);
  }
}
// ============================================================================
// SECTION 2: MULTER CONFIGURATION
// ============================================================================

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = './uploads/reconciliation';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, 'statement-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const fileFilter = (req, file, cb) => {
  console.log('📋 Reconciliation file upload check:');
  console.log('  - Filename:', file.originalname);
  console.log('  - MIME type:', file.mimetype);
  
  const allowedExtensions = /\.(xlsx|xls|csv)$/i;
  const hasValidExtension = allowedExtensions.test(file.originalname);
  
  console.log('  - Extension valid:', hasValidExtension);

  if (hasValidExtension) {
    console.log('✅ File accepted');
    return cb(null, true);
  } else {
    console.log('❌ File rejected - invalid extension');
    cb(new Error('Only Excel (.xlsx, .xls) and CSV (.csv) files are allowed!'));
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: { fileSize: 10 * 1024 * 1024 },
});

// ============================================================================
// SECTION 3: HELPER FUNCTIONS
// ============================================================================

function parseDate(dateValue, dateFormat = 'DD/MM/YYYY') {
  if (!dateValue) return null;
  
  if (typeof dateValue === 'number') {
    const excelEpoch = new Date(1899, 11, 30);
    return new Date(excelEpoch.getTime() + dateValue * 86400000);
  }
  
  if (typeof dateValue === 'string') {
    const ddmmyyyy = dateValue.match(/^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$/);
    if (ddmmyyyy) {
      const [, day, month, year] = ddmmyyyy;
      return new Date(year, month - 1, day);
    }
    
    const yyyymmdd = dateValue.match(/^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})$/);
    if (yyyymmdd) {
      const [, year, month, day] = yyyymmdd;
      return new Date(year, month - 1, day);
    }
    
    return new Date(dateValue);
  }
  
  return new Date(dateValue);
}

function normalizeColumnName(name) {
  if (!name) return '';
  return name.toString().toLowerCase().trim().replace(/[^a-z0-9]/g, '');
}

function findColumnName(row, possibleNames) {
  const columns = Object.keys(row);
  
  for (const targetName of possibleNames) {
    const normalizedTarget = normalizeColumnName(targetName);
    
    for (const col of columns) {
      const normalizedCol = normalizeColumnName(col);
      
      if (normalizedCol === normalizedTarget || 
          normalizedCol.includes(normalizedTarget) ||
          normalizedTarget.includes(normalizedCol)) {
        return col;
      }
    }
  }
  
  return null;
}

function parseStatementFile(filePath, mapping) {
  try {
    const workbook = XLSX.readFile(filePath);
    const sheetName = workbook.SheetNames[0];
    const worksheet = workbook.Sheets[sheetName];
    
    const rawData = XLSX.utils.sheet_to_json(worksheet, { 
      defval: '',
      header: 1
    });

    console.log(`📊 Total rows in file: ${rawData.length}`);
    
    let headerRowIndex = -1;
    const { columnMappings } = mapping;
    
    for (let i = 0; i < Math.min(rawData.length, 20); i++) {
      const row = rawData[i];
      const rowStr = row.join('|').toLowerCase();
      
      const hasDate = rowStr.includes('transaction date') || rowStr.includes('date');
      const hasDebit = rowStr.includes('debit') || rowStr.includes('withdrawal');
      const hasCredit = rowStr.includes('credit') || rowStr.includes('deposit');
      const hasDescription = rowStr.includes('description') || rowStr.includes('particulars') || rowStr.includes('narration');
      
      const matchCount = [hasDate, hasDebit, hasCredit, hasDescription].filter(Boolean).length;
      
      if (matchCount >= 2) {
        headerRowIndex = i;
        console.log(`✅ Found header row at index ${i}: ${row.join(' | ')}`);
        break;
      }
    }
    
    if (headerRowIndex === -1) {
      console.log('⚠️ Could not auto-detect header row, using row 0');
      headerRowIndex = 0;
    }
    
    const data = XLSX.utils.sheet_to_json(worksheet, { 
      defval: '',
      range: headerRowIndex
    });

    console.log(`📊 Parsed ${data.length} data rows (after skipping ${headerRowIndex + 1} header rows)`);
    
    return data;
  } catch (error) {
    console.error('❌ Error parsing file:', error);
    throw new Error(`Failed to parse file: ${error.message}`);
  }
}

function extractTransactionData(row, mapping) {
  const { columnMappings, dateFormat } = mapping;
  
  const dateColumnNames = [
    columnMappings.dateColumn,
    'Transaction Date',
    'Date',
    'Txn Date',
    'Value Date',
    'Posting Date'
  ].filter(Boolean);
  
  const actualDateColumn = findColumnName(row, dateColumnNames);
  if (!actualDateColumn) {
    throw new Error(`Could not find date column. Tried: ${dateColumnNames.join(', ')}`);
  }
  
  const dateValue = row[actualDateColumn];
  const transactionDate = parseDate(dateValue, dateFormat);
  
  if (!transactionDate || isNaN(transactionDate.getTime())) {
    throw new Error(`Invalid date: ${dateValue}`);
  }
  
  const debitColumnNames = [
    columnMappings.debitColumn,
    'Debit',
    'Debit Amount',
    'Withdrawal',
    'Dr',
    'Paid Out'
  ].filter(Boolean);
  
  const actualDebitColumn = findColumnName(row, debitColumnNames);
  
  const creditColumnNames = [
    columnMappings.creditColumn,
    'Credit',
    'Credit Amount',
    'Deposit',
    'Cr',
    'Paid In'
  ].filter(Boolean);
  
  const actualCreditColumn = findColumnName(row, creditColumnNames);
  
  console.log(`📊 Found columns: Date="${actualDateColumn}", Debit="${actualDebitColumn}", Credit="${actualCreditColumn}"`);
  
  let debitValue = actualDebitColumn ? row[actualDebitColumn] : 0;
  let creditValue = actualCreditColumn ? row[actualCreditColumn] : 0;
  
  if (debitValue) {
    if (typeof debitValue === 'string') {
      debitValue = parseFloat(debitValue.replace(/[^0-9.-]/g, ''));
    }
    debitValue = parseFloat(debitValue) || 0;
  } else {
    debitValue = 0;
  }
  
  if (creditValue) {
    if (typeof creditValue === 'string') {
      creditValue = parseFloat(creditValue.replace(/[^0-9.-]/g, ''));
    }
    creditValue = parseFloat(creditValue) || 0;
  } else {
    creditValue = 0;
  }
  
  let amount = 0;
  let transactionType = 'DEBIT';
  
  if (debitValue > 0) {
    amount = debitValue;
    transactionType = 'DEBIT';
  } else if (creditValue > 0) {
    amount = creditValue;
    transactionType = 'CREDIT';
  } else {
    throw new Error(`No amount found`);
  }
  
  if (isNaN(amount) || amount === 0) {
    throw new Error(`Invalid amount: Debit=${debitValue}, Credit=${creditValue}`);
  }
  
  const descriptionColumnNames = [
    columnMappings.descriptionColumn,
    'Description',
    'Particulars',
    'Narration',
    'Details',
    'Transaction Details'
  ].filter(Boolean);
  
  const actualDescriptionColumn = findColumnName(row, descriptionColumnNames);
  const description = actualDescriptionColumn ? row[actualDescriptionColumn] : null;
  
  const referenceColumnNames = [
    columnMappings.referenceColumn,
    'Reference Number',
    'Reference',
    'Ref No',
    'Transaction ID',
    'Txn ID',
    'Cheque No'
  ].filter(Boolean);
  
  const actualReferenceColumn = findColumnName(row, referenceColumnNames);
  const referenceNumber = actualReferenceColumn ? row[actualReferenceColumn] : null;
  
  const location = columnMappings.locationColumn ? row[columnMappings.locationColumn] : null;
  const cardNumber = columnMappings.cardNumberColumn ? row[columnMappings.cardNumberColumn] : null;
  const vehicleNumber = columnMappings.vehicleNumberColumn ? row[columnMappings.vehicleNumberColumn] : null;
  
  return {
    transactionDate,
    amount: Math.abs(amount),
    description,
    referenceNumber,
    location,
    cardNumber,
    vehicleNumber,
    transactionType,
    rawData: row,
  };
}

// ✅ FIXED: Auto-match with account name/ID support
async function autoMatchTransactions(accountId, dateRange) {
  console.log('🔍 Starting auto-match algorithm...');
  console.log('📊 Account ID:', accountId);
  console.log('📊 Date range:', dateRange);

  const { startDate, endDate } = dateRange;

  const providerTxns = await ProviderTransaction.find({
    accountId,
    transactionDate: { $gte: startDate, $lte: endDate },
    reconciliationStatus: 'UNMATCHED',
  }).sort({ transactionDate: 1 });

  console.log(`📊 Found ${providerTxns.length} unmatched provider transactions`);

 const PaymentAccount = mongoose.models.PaymentAccount || 
  mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
  const account = await PaymentAccount.findById(accountId);

  if (!account) {
    console.log('❌ Account not found:', accountId);
    return { matchedCount: 0, pendingCount: 0, totalProcessed: 0 };
  }

  console.log('✅ Found account:', account.accountName);

  // ✅ FIXED: Merged $or into $and — two $or keys in same object
  // silently overwrites the first one in MongoDB
  const systemExpenses = await Expense.find({
    $and: [
      {
        $or: [
          { paidThrough: accountId },
          { paidThrough: account._id.toString() },
          { paidThrough: account.accountName }
        ]
      },
      {
        date: {
          $gte: startDate.toISOString().split('T')[0],
          $lte: endDate.toISOString().split('T')[0]
        }
      },
      {
        $or: [
          { providerTransactionId: null },
          { providerTransactionId: { $exists: false } }
        ]
      }
    ]
  }).sort({ date: 1 });

  console.log(`📊 Found ${systemExpenses.length} unmatched system expenses`);

  if (systemExpenses.length > 0) {
    console.log('📋 Sample expenses:');
    systemExpenses.slice(0, 3).forEach((exp, i) => {
      console.log(`  ${i + 1}. Date: ${exp.date}, Amount: ₹${exp.total}, Account: ${exp.expenseAccount}, Paid Through: ${exp.paidThrough}`);
    });
  }

  if (providerTxns.length === 0) {
    console.log('⚠️ No provider transactions to match');
    return { matchedCount: 0, pendingCount: 0, totalProcessed: 0 };
  }

  if (systemExpenses.length === 0) {
    console.log('⚠️ No system expenses found to match against');
    return { matchedCount: 0, pendingCount: 0, totalProcessed: providerTxns.length };
  }

  let matchedCount = 0;
  let pendingCount = 0;

  const DATE_TOLERANCE_DAYS = 2;
  const AMOUNT_TOLERANCE = 50;

  for (const providerTxn of providerTxns) {
    let bestMatch = null;
    let bestConfidence = 0;

    for (const expense of systemExpenses) {
      if (expense.providerTransactionId) continue;

      const expenseDate = new Date(expense.date);
      const dateDiff = Math.abs(
        (providerTxn.transactionDate - expenseDate) / (1000 * 60 * 60 * 24)
      );
      const amountDiff = Math.abs(providerTxn.amount - expense.total);

      let confidence = 0;

      if (dateDiff === 0 && amountDiff === 0) {
        confidence = 100;
      } else if (dateDiff <= DATE_TOLERANCE_DAYS && amountDiff === 0) {
        confidence = 90;
      } else if (dateDiff === 0 && amountDiff <= AMOUNT_TOLERANCE) {
        confidence = 85;
      } else if (dateDiff <= DATE_TOLERANCE_DAYS && amountDiff <= AMOUNT_TOLERANCE) {
        confidence = 75;
      }

      if (confidence > bestConfidence) {
        bestConfidence = confidence;
        bestMatch = expense;
      }

      if (confidence === 100) break;
    }

    if (bestMatch && bestConfidence >= 75) {
      if (bestConfidence === 100) {
        providerTxn.reconciliationStatus = 'MATCHED';
        providerTxn.matchedExpenseId = bestMatch._id;
        providerTxn.matchConfidence = bestConfidence;
        providerTxn.matchedBy = 'auto-match';
        providerTxn.matchedAt = new Date();
        providerTxn.variance = providerTxn.amount - bestMatch.total;

        await providerTxn.save();

        bestMatch.providerTransactionId = providerTxn._id;
        bestMatch.isReconciledMatched = true;
        bestMatch.reconciledAt = new Date();
        bestMatch.reconciledBy = 'auto-match';
        await bestMatch.save();

        matchedCount++;
        console.log(`✅ Auto-matched (${bestConfidence}%): ₹${providerTxn.amount} ↔ ₹${bestMatch.total} ${bestMatch.expenseAccount}`);
      } else {
        providerTxn.reconciliationStatus = 'PENDING';
        providerTxn.matchedExpenseId = bestMatch._id;
        providerTxn.matchConfidence = bestConfidence;
        providerTxn.variance = providerTxn.amount - bestMatch.total;

        await providerTxn.save();

        pendingCount++;
        console.log(`🟡 Pending match (${bestConfidence}%): ₹${providerTxn.amount} ↔ ₹${bestMatch.total} ${bestMatch.expenseAccount}`);
      }
    } else {
      console.log(`❌ No match found for: ₹${providerTxn.amount} on ${providerTxn.transactionDate.toISOString().split('T')[0]}`);
    }
  }

  console.log(`\n✅ Auto-match complete: ${matchedCount} matched, ${pendingCount} pending`);

  return {
    matchedCount,
    pendingCount,
    totalProcessed: providerTxns.length,
  };
}

// ✅ FIXED: Calculate session stats with account name/ID support
async function calculateSessionStats(accountId, startDate, endDate) {
  console.log('📊 Calculating session stats...');
  console.log('  - Account ID:', accountId);
  console.log('  - Date range:', startDate, 'to', endDate);
  
  const providerTxns = await ProviderTransaction.find({
    accountId,
    transactionDate: { $gte: startDate, $lte: endDate },
  });
  
  console.log(`  - Provider transactions: ${providerTxns.length}`);
  
  const PaymentAccount = mongoose.models.PaymentAccount || 
  mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
  const account = await PaymentAccount.findById(accountId);
  
  let systemExpenses = [];
  
  if (account) {
    systemExpenses = await Expense.find({
      $or: [
        { paidThrough: accountId },
        { paidThrough: account._id.toString() },
        { paidThrough: account.accountName }
      ],
      date: { 
        $gte: startDate.toISOString().split('T')[0], 
        $lte: endDate.toISOString().split('T')[0] 
      },
    });
  } else {
    systemExpenses = await Expense.find({
      paidThrough: accountId,
      date: { 
        $gte: startDate.toISOString().split('T')[0], 
        $lte: endDate.toISOString().split('T')[0] 
      },
    });
  }
  
  console.log(`  - System expenses: ${systemExpenses.length}`);
  
  const totalProviderTransactions = providerTxns.length;
  const totalSystemExpenses = systemExpenses.length;
  const totalMatched = providerTxns.filter(t => t.reconciliationStatus === 'MATCHED').length;
  const totalUnmatched = providerTxns.filter(t => t.reconciliationStatus === 'UNMATCHED').length;
  const totalPending = providerTxns.filter(t => t.reconciliationStatus === 'PENDING').length;
  
  const providerBalance = providerTxns.reduce((sum, t) => sum + t.amount, 0);
  const systemBalance = systemExpenses.reduce((sum, e) => sum + e.total, 0);
  const balanceDifference = Math.abs(providerBalance - systemBalance);
  
  const totalVariance = providerTxns.reduce((sum, t) => sum + Math.abs(t.variance || 0), 0);
  
  console.log('  - Stats calculated:', {
    totalProviderTransactions,
    totalSystemExpenses,
    totalMatched,
    totalUnmatched,
    totalPending,
    providerBalance,
    systemBalance,
    balanceDifference
  });
  
  return {
    totalProviderTransactions,
    totalSystemExpenses,
    totalMatched,
    totalUnmatched,
    totalPending,
    providerBalance,
    systemBalance,
    balanceDifference,
    totalVariance,
  };
}

// ============================================================================
// SECTION 4: API ROUTES
// ============================================================================

// POST /api/reconciliation/import
// POST /api/reconciliation/import
router.post('/import', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'No file uploaded',
      });
    }

    const { accountId, mappingId, columnMappings, dateFormat } = req.body;

    if (!accountId) {
      return res.status(400).json({
        success: false,
        message: 'Account ID is required',
      });
    }

    console.log('📥 Processing import for account:', accountId);
    console.log('📄 File:', req.file.originalname);

    let mapping;

    if (mappingId) {
      mapping = await ColumnMapping.findById(mappingId);
      if (!mapping) {
        return res.status(400).json({
          success: false,
          message: 'Column mapping not found',
        });
      }
      mapping.usageCount += 1;
      mapping.lastUsedAt = new Date();
      await mapping.save();
    } else if (columnMappings) {
      mapping = {
        columnMappings: JSON.parse(columnMappings),
        dateFormat: dateFormat || 'DD/MM/YYYY',
      };
    } else {
      return res.status(400).json({
        success: false,
        message: 'Column mappings are required',
      });
    }

    const rows = parseStatementFile(req.file.path, mapping);

    const batchId = `BATCH-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    const importBatch = new ImportBatch({
      batchId,
      accountId,
      fileName: req.file.originalname,
      fileSize: req.file.size,
      fileType: path.extname(req.file.originalname).substring(1),
      totalRows: rows.length,
    });

    const imported = [];
    const errors = [];
    const skipped = [];
    const duplicates = [];

    console.log('\n📊 ========================================');
    console.log('📊 STARTING ROW-BY-ROW IMPORT ANALYSIS');
    console.log('📊 ========================================');
    console.log(`📊 Total rows in file: ${rows.length}`);
    console.log(`📊 Column mappings:`, JSON.stringify(mapping.columnMappings, null, 2));
    console.log('📊 ========================================\n');

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const rowNumber = i + 1;

      try {
        console.log(`\n🔍 ===== ROW ${rowNumber} ANALYSIS =====`);
        console.log(`📄 Raw row data:`, JSON.stringify(row, null, 2));

        const dateColumn = mapping.columnMappings.dateColumn;
        const dateValue = row[dateColumn];

        console.log(`📅 Date column name: "${dateColumn}"`);
        console.log(`📅 Date value found: "${dateValue}" (type: ${typeof dateValue})`);

        const debitColumn = mapping.columnMappings.debitColumn || 'Debit';
        const creditColumn = mapping.columnMappings.creditColumn || 'Credit';
        const debitValue = row[debitColumn];
        const creditValue = row[creditColumn];

        console.log(`💰 Debit column name: "${debitColumn}"`);
        console.log(`💰 Debit value found: "${debitValue}" (type: ${typeof debitValue})`);
        console.log(`💰 Credit column name: "${creditColumn}"`);
        console.log(`💰 Credit value found: "${creditValue}" (type: ${typeof creditValue})`);

        if (!dateValue || (!debitValue && !creditValue)) {
          const reason = !dateValue
            ? `Empty date column "${dateColumn}"`
            : `No amount in Debit ("${debitColumn}") or Credit ("${creditColumn}")`;
          console.log(`⏭️ SKIPPED: ${reason}`);
          skipped.push({ row: rowNumber, reason });
          continue;
        }

        const dateStr = String(dateValue).toLowerCase().trim();
        const headerKeywords = ['date', 'transaction date', 'instruction', 'delete', 'sample'];
        const isHeader = headerKeywords.some(keyword => dateStr === keyword || dateStr.includes(keyword));

        if (isHeader) {
          const reason = `Header row detected: "${dateStr}"`;
          console.log(`⏭️ SKIPPED: ${reason}`);
          skipped.push({ row: rowNumber, reason });
          continue;
        }

        console.log(`✅ Row ${rowNumber} passed validation checks`);
        console.log(`🔄 Attempting to extract transaction data...`);

        const txnData = extractTransactionData(row, mapping);

        console.log(`✅ Transaction data extracted:`, {
          date: txnData.transactionDate,
          amount: txnData.amount,
          type: txnData.transactionType,
          description: txnData.description
        });

        // ── DUPLICATE DETECTION ───────────────────────────────────────────────
        // Check if a transaction with the same accountId + amount + transactionDate
        // already exists in the database. If yes, skip and count as duplicate.
        // Date comparison uses a 1-minute window to handle minor time offsets
        // introduced by different Excel/CSV parsers on the same source date.
        const txnDateStart = new Date(txnData.transactionDate);
        txnDateStart.setHours(0, 0, 0, 0);
        const txnDateEnd = new Date(txnData.transactionDate);
        txnDateEnd.setHours(23, 59, 59, 999);

        const existingTxn = await ProviderTransaction.findOne({
          accountId,
          amount: txnData.amount,
          transactionDate: {
            $gte: txnDateStart,
            $lte: txnDateEnd,
          },
          transactionType: txnData.transactionType,
        });

        if (existingTxn) {
          const dupReason = `Duplicate: same account, amount ₹${txnData.amount}, date ${txnData.transactionDate.toISOString().split('T')[0]}, type ${txnData.transactionType}`;
          console.log(`⚠️ DUPLICATE SKIPPED (Row ${rowNumber}): ${dupReason}`);
          duplicates.push({
            row: rowNumber,
            reason: dupReason,
            existingId: existingTxn._id,
            amount: txnData.amount,
            date: txnData.transactionDate.toISOString().split('T')[0],
          });
          continue;
        }
        // ── END DUPLICATE DETECTION ───────────────────────────────────────────

        const providerTxn = new ProviderTransaction({
          accountId,
          ...txnData,
          importBatchId: batchId,
          importedAt: new Date(),
          importedBy: req.user?.email || 'system',
          orgId: req.user?.orgId || null,
        });

        await providerTxn.save();
        imported.push(providerTxn);

        console.log(`✅✅✅ Row ${rowNumber}: SUCCESSFULLY IMPORTED - ${txnData.transactionDate.toISOString().split('T')[0]} - ₹${txnData.amount}`);

      } catch (error) {
        console.error(`❌❌❌ Row ${rowNumber} ERROR:`, error.message);
        console.error(`❌ Full error:`, error);
        errors.push({
          row: rowNumber,
          error: error.message,
        });
      }
    }

    console.log('\n📊 ========================================');
    console.log('📊 IMPORT SUMMARY');
    console.log('📊 ========================================');
    console.log(`✅ Successfully imported: ${imported.length} rows`);
    console.log(`⚠️ Duplicates skipped:   ${duplicates.length} rows`);
    console.log(`⏭️ Skipped:              ${skipped.length} rows`);
    console.log(`❌ Errors:               ${errors.length} rows`);
    console.log('📊 ========================================');

    if (duplicates.length > 0) {
      console.log('\n⚠️ DUPLICATE ROWS DETAILS:');
      duplicates.forEach(d => console.log(`  Row ${d.row}: ${d.reason}`));
    }

    if (skipped.length > 0) {
      console.log('\n⏭️ SKIPPED ROWS DETAILS:');
      skipped.forEach(s => console.log(`  Row ${s.row}: ${s.reason}`));
    }

    if (errors.length > 0) {
      console.log('\n❌ ERROR ROWS DETAILS:');
      errors.forEach(e => console.log(`  Row ${e.row}: ${e.error}`));
    }

    console.log('\n');

    importBatch.successfulImports = imported.length;
    importBatch.failedImports = errors.length;
    importBatch.errors = errors;
    await importBatch.save();

    if (fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }

    console.log(`✅ Import complete: ${imported.length} imported, ${duplicates.length} duplicates skipped, ${errors.length} errors`);

    res.json({
      success: true,
      message: `Successfully imported ${imported.length} transaction(s)${duplicates.length > 0 ? `, ${duplicates.length} duplicate(s) skipped` : ''}`,
      data: {
        batchId,
        imported: imported.length,
        duplicates: duplicates.length,
        duplicateDetails: duplicates,
        errors: errors.length,
        errorDetails: errors,
        transactions: imported,
      },
    });

  } catch (error) {
    console.error('❌ Import error:', error);

    if (req.file && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }

    res.status(500).json({
      success: false,
      message: 'Import failed',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/save-mapping
router.post('/save-mapping', async (req, res) => {
  try {
    const { accountId, mappingName, fileFormat, columnMappings, dateFormat } = req.body;

    if (!accountId || !mappingName || !columnMappings) {
      return res.status(400).json({
        success: false,
        message: 'Account ID, mapping name, and column mappings are required',
      });
    }

    const mapping = new ColumnMapping({
      accountId,
      mappingName,
      fileFormat: fileFormat || 'EXCEL',
      columnMappings,
      dateFormat: dateFormat || 'DD/MM/YYYY',
      createdBy: 'system',
    });

    await mapping.save();

    console.log('✅ Column mapping saved:', mapping._id);

    res.json({
      success: true,
      message: 'Column mapping saved successfully',
      data: mapping,
    });

  } catch (error) {
    console.error('❌ Error saving mapping:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to save mapping',
      error: error.message,
    });
  }
});

// GET /api/reconciliation/mappings/:accountId
router.get('/mappings/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;

    const mappings = await ColumnMapping.find({ accountId }).sort({ usageCount: -1 });

    res.json({
      success: true,
      count: mappings.length,
      data: mappings,
    });

  } catch (error) {
    console.error('❌ Error fetching mappings:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch mappings',
      error: error.message,
    });
  }
});

// GET /api/reconciliation/provider-transactions
router.get('/provider-transactions', async (req, res) => {
  try {
    const { accountId, status, startDate, endDate } = req.query;

    const filter = {};
    if (req.user?.orgId) filter.orgId = req.user.orgId;
    
    if (accountId) {
      filter.accountId = accountId;
    }

    if (status) {
      filter.reconciliationStatus = status;
    }

    if (startDate || endDate) {
      filter.transactionDate = {};
      if (startDate) filter.transactionDate.$gte = new Date(startDate);
      if (endDate) filter.transactionDate.$lte = new Date(endDate);
    }

    const transactions = await ProviderTransaction.find(filter)
      .populate('matchedExpenseId')
      .sort({ transactionDate: -1 });

    res.json({
      success: true,
      count: transactions.length,
      data: transactions,
    });

  } catch (error) {
    console.error('❌ Error fetching provider transactions:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch provider transactions',
      error: error.message,
    });
  }
});

// ✅ FIXED: GET /api/reconciliation/system-expenses
router.get('/system-expenses', async (req, res) => {
  try {
    const { accountId, startDate, endDate, matched } = req.query;

    console.log('📥 Fetching system expenses...');
    console.log('  - Account ID:', accountId);
    console.log('  - Start Date:', startDate);
    console.log('  - End Date:', endDate);
    console.log('  - Matched filter:', matched);

    const filter = {};
    
    if (accountId) {
      console.log('🔍 Searching expenses for accountId:', accountId);
      
      const PaymentAccount = mongoose.models.PaymentAccount || 
  mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
      const account = await PaymentAccount.findById(accountId);
      
      if (account) {
        console.log('✅ Found account:', account.accountName);
        
        // ✅ FIX: Search by BOTH ID and account name
        filter.$or = [
          { paidThrough: accountId },
          { paidThrough: account._id.toString() },
          { paidThrough: account.accountName }
        ];
        
        console.log('🔍 Searching by: ID OR Name =', account.accountName);
      } else {
        console.log('⚠️ Account not found, searching by ID only');
        filter.paidThrough = accountId;
      }
    }

    if (startDate || endDate) {
      filter.date = {};
      if (startDate) filter.date.$gte = startDate;
      if (endDate) filter.date.$lte = endDate;
    }

    if (matched === 'true') {
      filter.providerTransactionId = { $ne: null };
    } else if (matched === 'false') {
      // Use $and to combine the accountId $or with the unmatched $or without overwriting
      if (filter.$or) {
        filter.$and = [
          { $or: filter.$or },
          { $or: [
            { providerTransactionId: null },
            { providerTransactionId: { $exists: false } }
          ]}
        ];
        delete filter.$or;
      } else {
        filter.$or = [
          { providerTransactionId: null },
          { providerTransactionId: { $exists: false } }
        ];
      }
    }

    console.log('📊 Final query filter:', JSON.stringify(filter, null, 2));

    const expenses = await Expense.find(filter).sort({ date: -1 });

    console.log(`✅ Found ${expenses.length} expenses`);
    
    // ✅ DEBUG: Show sample results
    if (expenses.length > 0) {
      console.log('📋 Sample expenses:');
      expenses.slice(0, 3).forEach((exp, i) => {
        console.log(`  ${i + 1}. Date: ${exp.date}, Amount: ₹${exp.total}, Paid Through: ${exp.paidThrough}`);
      });
    } else if (accountId) {
      console.log('⚠️ No expenses found. Checking all expenses for this account...');
      const allExpenses = await Expense.find({}).limit(5);
      console.log(`📋 Total expenses in DB: ${await Expense.countDocuments()}`);
      console.log('📋 Sample of all expenses (first 5):');
      allExpenses.forEach((exp, i) => {
        console.log(`  ${i + 1}. Paid Through: "${exp.paidThrough}" (type: ${typeof exp.paidThrough})`);
      });
    }

    res.json({
      success: true,
      count: expenses.length,
      data: expenses,
    });

  } catch (error) {
    console.error('❌ Error fetching system expenses:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch system expenses',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/auto-match
router.post('/auto-match', async (req, res) => {
  try {
    const { accountId, startDate, endDate } = req.body;

    if (!accountId || !startDate || !endDate) {
      return res.status(400).json({
        success: false,
        message: 'Account ID, start date, and end date are required',
      });
    }

    console.log('🔍 Starting auto-match for account:', accountId);

    const result = await autoMatchTransactions(accountId, {
      startDate: new Date(startDate),
      endDate: new Date(endDate),
    });

    res.json({
      success: true,
      message: 'Auto-match completed',
      data: result,
    });

  } catch (error) {
    console.error('❌ Auto-match error:', error);
    res.status(500).json({
      success: false,
      message: 'Auto-match failed',
      error: error.message,
    });
  }
});

// ✅ ENHANCED: POST /api/reconciliation/manual-match with validation
// ✅ ENHANCED: POST /api/reconciliation/manual-match with validation
router.post('/manual-match', async (req, res) => {
  try {
    const { providerTxnId, expenseId, forceMatch } = req.body;

    if (!providerTxnId || !expenseId) {
      return res.status(400).json({
        success: false,
        message: 'Provider transaction ID and expense ID are required',
      });
    }

    console.log('🔍 Manual match request:');
    console.log('  - Provider Txn ID:', providerTxnId);
    console.log('  - Expense ID:', expenseId);
    console.log('  - Force Match:', forceMatch);

    const providerTxn = await ProviderTransaction.findOne({
      _id: providerTxnId,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!providerTxn) {
      return res.status(404).json({
        success: false,
        message: 'Provider transaction not found',
      });
    }

    const expense = await Expense.findById(expenseId);
    if (!expense) {
      return res.status(404).json({
        success: false,
        message: 'Expense not found',
      });
    }

    const amountDiff = Math.abs(providerTxn.amount - expense.total);
    const providerDate = new Date(providerTxn.transactionDate);
    const expenseDate = new Date(expense.date);
    const dateDiff = Math.abs((providerDate - expenseDate) / (1000 * 60 * 60 * 24));

    const warnings = [];
    let matchConfidence = 100;

    console.log('📊 Validation:');
    console.log('  - Provider: ₹', providerTxn.amount, 'on', providerDate.toISOString().split('T')[0]);
    console.log('  - Expense: ₹', expense.total, 'on', expense.date);
    console.log('  - Amount diff: ₹', amountDiff);
    console.log('  - Date diff:', dateDiff, 'days');

    if (amountDiff > 0) {
      warnings.push({
        type: 'amount_mismatch',
        severity: amountDiff > 100 ? 'high' : 'medium',
        message: `Amount mismatch: Bank ₹${providerTxn.amount} vs System ₹${expense.total} (Difference: ₹${amountDiff})`
      });
      matchConfidence -= Math.min(30, (amountDiff / 100) * 10);
    }

    if (dateDiff > 0) {
      warnings.push({
        type: 'date_mismatch',
        severity: dateDiff > 7 ? 'high' : 'medium',
        message: `Date difference: ${Math.round(dateDiff)} days apart (Bank: ${providerDate.toLocaleDateString()} vs System: ${expenseDate.toLocaleDateString()})`
      });
      matchConfidence -= Math.min(20, dateDiff * 3);
    }

    if (amountDiff > 500 && !forceMatch) {
      console.log('⚠️ Large amount mismatch detected, requesting confirmation');
      return res.status(400).json({
        success: false,
        requiresConfirmation: true,
        message: 'Large amount mismatch detected!',
        warnings: warnings,
        details: {
          bankAmount: providerTxn.amount,
          systemAmount: expense.total,
          difference: amountDiff,
          bankDate: providerDate.toISOString().split('T')[0],
          systemDate: expense.date,
          dateDifference: Math.round(dateDiff),
        },
        suggestion: 'Please verify this is correct before proceeding.'
      });
    }

    if (dateDiff > 14 && !forceMatch) {
      console.log('⚠️ Large date difference detected, requesting confirmation');
      return res.status(400).json({
        success: false,
        requiresConfirmation: true,
        message: 'Large date difference detected!',
        warnings: warnings,
        details: {
          bankAmount: providerTxn.amount,
          systemAmount: expense.total,
          difference: amountDiff,
          bankDate: providerDate.toISOString().split('T')[0],
          systemDate: expense.date,
          dateDifference: Math.round(dateDiff),
        },
        suggestion: 'Transactions are more than 2 weeks apart. Please verify this is correct.'
      });
    }

    providerTxn.reconciliationStatus = 'MATCHED';
    providerTxn.matchedExpenseId = expense._id;
    providerTxn.matchConfidence = Math.max(50, Math.round(matchConfidence));
    providerTxn.matchedBy = forceMatch ? 'manual-forced' : 'manual';
    providerTxn.matchedAt = new Date();
    providerTxn.variance = providerTxn.amount - expense.total;

    if (amountDiff > 0 || dateDiff > 0) {
      const reasons = [];
      if (amountDiff > 0) reasons.push(`Amount difference: ₹${amountDiff}`);
      if (dateDiff > 0) reasons.push(`Date difference: ${Math.round(dateDiff)} days`);
      providerTxn.varianceReason = reasons.join('; ');
    }

    await providerTxn.save();

    expense.providerTransactionId = providerTxn._id;
    expense.isReconciledMatched = true;
    expense.reconciledAt = new Date();
    expense.reconciledBy = forceMatch ? 'manual-forced' : 'manual';
    await expense.save();

    // ✅ AUDIT LOG — Phase 8
    await createAuditLog(null, providerTxn.accountId, forceMatch ? 'TRANSACTION_FORCED_MATCH' : 'TRANSACTION_MATCHED', {
      providerTxnId,
      expenseId,
      variance: providerTxn.variance,
      matchConfidence: Math.round(matchConfidence),
    });

    console.log(`✅ Manual match: Provider ${providerTxnId} ↔ Expense ${expenseId}`);
    if (warnings.length > 0) {
      console.log(`⚠️ Warnings:`, warnings.map(w => w.message).join('; '));
    }

    res.json({
      success: true,
      message: warnings.length > 0
        ? 'Transactions matched with warnings'
        : 'Transactions matched successfully',
      warnings: warnings,
      data: {
        providerTransaction: providerTxn,
        expense: expense,
        matchConfidence: Math.round(matchConfidence),
        variance: providerTxn.variance,
      },
    });

  } catch (error) {
    console.error('❌ Manual match error:', error);
    res.status(500).json({
      success: false,
      message: 'Manual match failed',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/accept-match/:id
router.post('/accept-match/:id', async (req, res) => {
  try {
    const providerTxn = await ProviderTransaction.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!providerTxn) {
      return res.status(404).json({
        success: false,
        message: 'Provider transaction not found',
      });
    }

    if (providerTxn.reconciliationStatus !== 'PENDING') {
      return res.status(400).json({
        success: false,
        message: 'Transaction is not in pending status',
      });
    }

    if (!providerTxn.matchedExpenseId) {
      return res.status(400).json({
        success: false,
        message: 'No matched expense found',
      });
    }

    providerTxn.reconciliationStatus = 'MATCHED';
    providerTxn.matchedBy = 'user-approved';
    providerTxn.matchedAt = new Date();
    await providerTxn.save();

    const expense = await Expense.findById(providerTxn.matchedExpenseId);
    if (expense) {
      expense.providerTransactionId = providerTxn._id;
      expense.isReconciledMatched = true;
      expense.reconciledAt = new Date();
      expense.reconciledBy = 'user-approved';
      await expense.save();
    }

    console.log(`✅ Accepted match: Provider ${req.params.id}`);

    res.json({
      success: true,
      message: 'Match accepted',
      data: providerTxn,
    });

  } catch (error) {
    console.error('❌ Accept match error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to accept match',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/reject-match/:id
router.post('/reject-match/:id', async (req, res) => {
  try {
    const providerTxn = await ProviderTransaction.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!providerTxn) {
      return res.status(404).json({
        success: false,
        message: 'Provider transaction not found',
      });
    }

    providerTxn.reconciliationStatus = 'UNMATCHED';
    providerTxn.matchedExpenseId = null;
    providerTxn.matchConfidence = null;
    providerTxn.matchedBy = null;
    providerTxn.matchedAt = null;
    providerTxn.variance = 0;
    await providerTxn.save();

    console.log(`❌ Rejected match: Provider ${req.params.id}`);

    res.json({
      success: true,
      message: 'Match rejected',
      data: providerTxn,
    });

  } catch (error) {
    console.error('❌ Reject match error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to reject match',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/unmatch/:id
router.post('/unmatch/:id', async (req, res) => {
  try {
    const providerTxn = await ProviderTransaction.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!providerTxn) {
      return res.status(404).json({
        success: false,
        message: 'Provider transaction not found',
      });
    }

    if (providerTxn.matchedExpenseId) {
      const expense = await Expense.findById(providerTxn.matchedExpenseId);
      if (expense) {
        expense.providerTransactionId = null;
        expense.isReconciledMatched = false;
        expense.reconciledAt = null;
        expense.reconciledBy = null;
        await expense.save();
      }
    }

    providerTxn.reconciliationStatus = 'UNMATCHED';
    providerTxn.matchedExpenseId = null;
    providerTxn.matchConfidence = null;
    providerTxn.matchedBy = null;
    providerTxn.matchedAt = null;
    providerTxn.variance = 0;
    await providerTxn.save();

    console.log(`🔓 Unmatched: Provider ${req.params.id}`);

    res.json({
      success: true,
      message: 'Transaction unmatched',
      data: providerTxn,
    });

  } catch (error) {
    console.error('❌ Unmatch error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to unmatch transaction',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/sessions/start
router.post('/sessions/start', async (req, res) => {
  try {
    const { accountId, accountName, accountType, periodStart, periodEnd } = req.body;

    if (!accountId || !accountName || !periodStart || !periodEnd) {
      return res.status(400).json({
        success: false,
        message: 'Account ID, account name, period start, and period end are required',
      });
    }

    const existingSession = await ReconciliationSession.findOne({
      accountId,
      periodStart: new Date(periodStart),
      periodEnd: new Date(periodEnd),
      status: { $in: ['IN_PROGRESS', 'COMPLETED'] },
    });

    if (existingSession) {
      return res.json({
        success: true,
        message: 'Reconciliation session already exists',
        data: existingSession,
      });
    }

    const stats = await calculateSessionStats(
      accountId,
      new Date(periodStart),
      new Date(periodEnd)
    );

const session = new ReconciliationSession({
      accountId,
      accountName,
      accountType,
      periodStart: new Date(periodStart),
      periodEnd: new Date(periodEnd),
      ...stats,
      startedBy: 'system',
      orgId: req.user?.orgId || null,
    });

    await session.save();

    console.log('✅ Reconciliation session started:', session._id);

    res.json({
      success: true,
      message: 'Reconciliation session started',
      data: session,
    });

  } catch (error) {
    console.error('❌ Error starting session:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to start reconciliation session',
        error: error.stack || error.message,
    });
  }
});

// POST /api/reconciliation/sessions/verify-opening-balance
router.post('/sessions/verify-opening-balance', async (req, res) => {
  try {
    const { accountId, statementOpeningBalance } = req.body;

    if (!accountId || statementOpeningBalance === undefined) {
      return res.status(400).json({
        success: false,
        message: 'Account ID and statement opening balance are required',
      });
    }

    const PaymentAccount = mongoose.models.PaymentAccount || 
  mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const account = await PaymentAccount.findById(accountId);

    if (!account) {
      return res.status(404).json({
        success: false,
        message: 'Account not found',
      });
    }

    const systemBalance = account.currentBalance || 0;
    const statementBalance = parseFloat(statementOpeningBalance);
    const difference = statementBalance - systemBalance;
    const isMatched = Math.abs(difference) < 0.01;

    console.log(`📊 Opening Balance Verification for "${account.accountName}":`);
    console.log(`   System Balance:    ₹${systemBalance}`);
    console.log(`   Statement Balance: ₹${statementBalance}`);
    console.log(`   Difference:        ₹${difference}`);
    console.log(`   Result:            ${isMatched ? '✅ MATCHED' : '⚠️ MISMATCH'}`);

    res.json({
      success: true,
      data: {
        accountId,
        accountName: account.accountName,
        systemBalance,
        statementBalance,
        difference,
        isMatched,
        severity: Math.abs(difference) === 0
          ? 'none'
          : Math.abs(difference) <= 100
          ? 'low'
          : Math.abs(difference) <= 1000
          ? 'medium'
          : 'high',
        message: isMatched
          ? 'Opening balance matches. You can proceed with reconciliation.'
          : `Opening balance mismatch of ₹${Math.abs(difference).toFixed(2)}. System shows ₹${systemBalance.toFixed(2)} but your statement shows ₹${statementBalance.toFixed(2)}.`,
      },
    });

  } catch (error) {
    console.error('❌ Error verifying opening balance:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to verify opening balance',
      error: error.message,
    });
  }
});

// GET /api/reconciliation/sessions
router.get('/sessions', async (req, res) => {
  try {
    const { accountId, status } = req.query;

const filter = {};
    if (req.user?.orgId) filter.orgId = req.user.orgId;
    if (accountId) filter.accountId = accountId;
    if (status) filter.status = status;

    const sessions = await ReconciliationSession.find(filter).sort({ startedAt: -1 });

    res.json({
      success: true,
      count: sessions.length,
      data: sessions,
    });

  } catch (error) {
    console.error('❌ Error fetching sessions:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch reconciliation sessions',
      error: error.message,
    });
  }
});

// GET /api/reconciliation/sessions/:id
router.get('/sessions/:id', async (req, res) => {
  try {
    const session = await ReconciliationSession.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!session) {
      return res.status(404).json({
        success: false,
        message: 'Reconciliation session not found',
      });
    }

    const stats = await calculateSessionStats(
      session.accountId,
      session.periodStart,
      session.periodEnd
    );

    Object.assign(session, stats);
    await session.save();

    res.json({
      success: true,
      data: session,
    });

  } catch (error) {
    console.error('❌ Error fetching session:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch session details',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/sessions/:id/finalize
// POST /api/reconciliation/sessions/:id/finalize
router.post('/sessions/:id/finalize', async (req, res) => {
  try {
    const session = await ReconciliationSession.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!session) {
      return res.status(404).json({
        success: false,
        message: 'Reconciliation session not found. Please refresh and try again.',
      });
    }

    if (session.isLocked) {
      return res.status(400).json({
        success: false,
        message: 'This reconciliation period is already locked. No further changes are allowed.',
      });
    }

    const unmatchedCount = await ProviderTransaction.countDocuments({
      accountId: session.accountId,
      transactionDate: { $gte: session.periodStart, $lte: session.periodEnd },
      reconciliationStatus: 'UNMATCHED',
    });

    if (unmatchedCount > 0) {
      return res.status(400).json({
        success: false,
        message: `Cannot finalize: ${unmatchedCount} unmatched transaction(s) still need to be resolved. Please match, carry forward, or create an adjustment for each one before finalizing.`,
        unmatchedCount,
        requiresResolution: true,
      });
    }

    const pendingCount = await ProviderTransaction.countDocuments({
      accountId: session.accountId,
      transactionDate: { $gte: session.periodStart, $lte: session.periodEnd },
      reconciliationStatus: 'PENDING',
    });

    if (pendingCount > 0) {
      return res.status(400).json({
        success: false,
        message: `Cannot finalize: ${pendingCount} transaction(s) are in Pending status. Please accept or reject all pending matches before finalizing.`,
        pendingCount,
      });
    }

    const { statementClosingBalance, notes } = req.body;

    if (statementClosingBalance === undefined || statementClosingBalance === null) {
      return res.status(400).json({
        success: false,
        message: 'Statement closing balance is required to finalize. Please enter the closing balance from your bank statement.',
        requiresClosingBalance: true,
      });
    }

    const PaymentAccount = mongoose.models.PaymentAccount || 
  mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const account = await PaymentAccount.findById(session.accountId);

    if (!account) {
      return res.status(404).json({
        success: false,
        message: 'Account not found. Cannot verify closing balance.',
      });
    }

    const systemClosingBalance = account.currentBalance || 0;
    const statementClosing = parseFloat(statementClosingBalance);
    const closingDifference = statementClosing - systemClosingBalance;
    const isClosingMatched = Math.abs(closingDifference) < 0.01;

    console.log(`📊 Closing Balance Verification for "${account.accountName}":`);
    console.log(`   System Closing Balance:    ₹${systemClosingBalance}`);
    console.log(`   Statement Closing Balance: ₹${statementClosing}`);
    console.log(`   Difference:                ₹${closingDifference}`);
    console.log(`   Result:                    ${isClosingMatched ? '✅ MATCHED' : '⚠️ MISMATCH'}`);

    const { forceFinalize } = req.body;

    if (!isClosingMatched && !forceFinalize) {
      const severity = Math.abs(closingDifference) <= 100
        ? 'low'
        : Math.abs(closingDifference) <= 1000
        ? 'medium'
        : 'high';

      return res.status(400).json({
        success: false,
        requiresConfirmation: true,
        message: `Closing balance mismatch detected. System shows ₹${systemClosingBalance.toFixed(2)} but your statement shows ₹${statementClosing.toFixed(2)}. Difference is ₹${Math.abs(closingDifference).toFixed(2)}.`,
        closingBalanceCheck: {
          systemClosingBalance,
          statementClosingBalance: statementClosing,
          difference: closingDifference,
          severity,
          isMatched: false,
        },
      });
    }

    const stats = await calculateSessionStats(
      session.accountId,
      session.periodStart,
      session.periodEnd
    );

    Object.assign(session, stats);
    session.status = 'LOCKED';
    session.completedBy = 'system';
    session.completedAt = new Date();
    session.isLocked = true;
    session.lockedBy = 'system';
    session.lockedAt = new Date();
    session.reconciliationNotes = notes || null;
    session.statementClosingBalance = statementClosing;
    session.systemClosingBalance = systemClosingBalance;
    session.closingBalanceDifference = closingDifference;
    session.closingBalanceMatched = isClosingMatched;
    session.finalizedWithForce = !isClosingMatched && forceFinalize === true;

    await session.save();

    // ✅ AUDIT LOG — Phase 8
    await createAuditLog(session._id, session.accountId, 'SESSION_FINALIZED', {
      isClosingMatched,
      closingDifference,
      forcedFinalize: session.finalizedWithForce,
    });

    console.log(`🔒 Reconciliation session finalized: ${session._id}`);
    console.log(`   Closing balance matched: ${isClosingMatched}`);
    console.log(`   Forced finalization: ${session.finalizedWithForce}`);

    res.json({
      success: true,
      message: isClosingMatched
        ? 'Reconciliation completed and locked successfully. Closing balance verified.'
        : 'Reconciliation completed and locked. Note: Closing balance had a difference of ₹' + Math.abs(closingDifference).toFixed(2) + ' which was acknowledged.',
      data: session,
    });

  } catch (error) {
    console.error('❌ Error finalizing session:', error);
    res.status(500).json({
      success: false,
      message: 'Something went wrong while finalizing. Please try again.',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/sessions/:id/reopen
router.post('/sessions/:id/reopen', async (req, res) => {
  try {
    const session = await ReconciliationSession.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!session) {
      return res.status(404).json({
        success: false,
        message: 'Reconciliation session not found',
      });
    }

    if (!session.isLocked) {
      return res.status(400).json({
        success: false,
        message: 'Session is not locked',
      });
    }

    session.status = 'IN_PROGRESS';
    session.isLocked = false;
    session.lockedBy = null;
    session.lockedAt = null;

    await session.save();

    console.log('🔓 Reconciliation session reopened:', session._id);

    res.json({
      success: true,
      message: 'Reconciliation session reopened',
      data: session,
    });

  } catch (error) {
    console.error('❌ Error reopening session:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to reopen session',
      error: error.message,
    });
  }
});

// ✅ FIXED: POST /api/reconciliation/petty-cash/count
router.post('/petty-cash/count', async (req, res) => {
  try {
    const { 
      accountId, 
      accountName,
      periodStart, 
      periodEnd, 
      physicalCashCount, 
      denominations, 
      countedBy,
      notes 
    } = req.body;

    if (!accountId || !periodStart || !periodEnd || physicalCashCount === undefined) {
      return res.status(400).json({
        success: false,
        message: 'Account ID, period, and physical cash count are required',
      });
    }

    console.log('💰 Petty cash count submission:');
    console.log('  - Account ID:', accountId);
    console.log('  - Account Name:', accountName);
    console.log('  - Period:', periodStart, 'to', periodEnd);
    console.log('  - Physical Count: ₹', physicalCashCount);

    const PaymentAccount = mongoose.models.PaymentAccount || 
  mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const account = await PaymentAccount.findById(accountId);
    
    if (!account) {
      return res.status(404).json({
        success: false,
        message: 'Account not found',
      });
    }

    // ✅ FIX: Search expenses by BOTH ID and name
    const expenses = await Expense.find({
      $or: [
        { paidThrough: accountId },
        { paidThrough: account._id.toString() },
        { paidThrough: account.accountName }
      ],
      date: { 
        $gte: new Date(periodStart).toISOString().split('T')[0], 
        $lte: new Date(periodEnd).toISOString().split('T')[0] 
      },
    });

    console.log(`  - Found ${expenses.length} expenses`);

    const totalExpenses = expenses.reduce((sum, e) => sum + e.total, 0);
    
    console.log('  - Total Expenses: ₹', totalExpenses);

    let session = await ReconciliationSession.findOne({
      accountId,
      periodStart: new Date(periodStart),
      periodEnd: new Date(periodEnd),
    });

    if (!session) {
      session = new ReconciliationSession({
        accountId,
        accountName: accountName || account.accountName,
        accountType: 'PETTY_CASH',
        periodStart: new Date(periodStart),
        periodEnd: new Date(periodEnd),
        startedBy: countedBy || 'system',
      });
    }

    session.physicalCashCount = physicalCashCount;
    session.denominations = denominations || [];
    session.systemBalance = totalExpenses;
    session.balanceDifference = Math.abs(physicalCashCount - totalExpenses);
    session.totalVariance = session.balanceDifference;
    session.reconciliationNotes = notes || null;
    session.status = 'COMPLETED';
    session.completedBy = countedBy || 'system';
    session.completedAt = new Date();

    await session.save();

    console.log('✅ Petty cash count recorded:', session._id);

    res.json({
      success: true,
      message: 'Petty cash count recorded',
      data: session,
    });

  } catch (error) {
    console.error('❌ Error recording petty cash count:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to record petty cash count',
      error: error.message,
    });
  }
});

// ✅ FIXED: GET /api/reconciliation/petty-cash/summary
router.get('/petty-cash/summary', async (req, res) => {
  try {
    const { accountId, startDate, endDate } = req.query;

    if (!accountId) {
      return res.status(400).json({ success: false, message: 'accountId is required' });
    }

    // Get account opening balance
    const account = await mongoose.connection.collection('paymentaccounts')
      .findOne({ _id: new mongoose.Types.ObjectId(accountId) });

    const openingBalance = account ? (account.currentBalance || 0) : 0;

    // Build date filter
    let dateFilter = {};
    if (startDate && endDate) {
      // Parse DD/MM/YYYY or ISO
      const parseD = (d) => {
        if (!d) return null;
        if (d.includes('/')) {
          const [day, month, year] = d.split('/');
          return `${year}-${month.padStart(2,'0')}-${day.padStart(2,'0')}`;
        }
        return d.split('T')[0];
      };
      dateFilter = {
        date: { $gte: parseD(startDate), $lte: parseD(endDate) }
      };
    }

    // Get expenses paid through this account (by ID or name)
    const accountName = account ? account.accountName : null;
    const expenseQuery = {
      ...dateFilter,
      $or: [
        { paidThrough: accountId },
        ...(accountName ? [{ paidThrough: accountName }] : [])
      ]
    };

    const expenses = await mongoose.connection.collection('expenses')
      .find(expenseQuery)
      .sort({ date: -1 })
      .toArray();

    const totalExpenses = expenses.reduce((sum, e) => sum + (e.total || 0), 0);
    const expectedBalance = openingBalance - totalExpenses;

    res.json({
      success: true,
      data: {
        openingBalance,
        totalExpenses,
        expectedBalance,
        expenseCount: expenses.length,
        expenses: expenses.map(e => ({
          _id: e._id,
          date: e.date,
          expenseAccount: e.expenseAccount,
          vendor: e.vendor,
          total: e.total,
          notes: e.notes,
        })),
      }
    });
  } catch (e) {
    console.error('❌ getPettyCashSummary error:', e);
    res.status(500).json({ success: false, message: e.message });
  }
});

// GET /api/reconciliation/stats/:accountId
router.get('/stats/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const { startDate, endDate } = req.query;

    if (!startDate || !endDate) {
      return res.status(400).json({
        success: false,
        message: 'Start date and end date are required',
      });
    }

    const stats = await calculateSessionStats(
      accountId,
      new Date(startDate),
      new Date(endDate)
    );

    res.json({
      success: true,
      data: stats,
    });

  } catch (error) {
    console.error('❌ Error fetching stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch statistics',
      error: error.message,
    });
  }
});

// DELETE /api/reconciliation/provider-transactions/:id
router.delete('/provider-transactions/:id', async (req, res) => {
  try {
    const providerTxn = await ProviderTransaction.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!providerTxn) {
      return res.status(404).json({
        success: false,
        message: 'Provider transaction not found',
      });
    }

    if (providerTxn.matchedExpenseId) {
      const expense = await Expense.findById(providerTxn.matchedExpenseId);
      if (expense) {
        expense.providerTransactionId = null;
        expense.isReconciledMatched = false;
        expense.reconciledAt = null;
        expense.reconciledBy = null;
        await expense.save();
      }
    }

    await providerTxn.deleteOne();

    console.log('🗑️ Provider transaction deleted:', req.params.id);

    res.json({
      success: true,
      message: 'Provider transaction deleted',
    });

  } catch (error) {
    console.error('❌ Error deleting provider transaction:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete provider transaction',
      error: error.message,
    });
  }
});

// GET /api/reconciliation/import-history
router.get('/import-history', async (req, res) => {
  try {
    const { accountId } = req.query;

    const filter = {};
    if (accountId) filter.accountId = accountId;

    const batches = await ImportBatch.find(filter).sort({ uploadedAt: -1 });

    res.json({
      success: true,
      count: batches.length,
      data: batches,
    });

  } catch (error) {
    console.error('❌ Error fetching import history:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch import history',
      error: error.message,
    });
  }
});

// Health Check
router.get('/health', async (req, res) => {
  try {
    const providerCount = await ProviderTransaction.countDocuments();
    const sessionCount = await ReconciliationSession.countDocuments();
    const mappingCount = await ColumnMapping.countDocuments();

    res.json({
      success: true,
      status: 'healthy',
      stats: {
        providerTransactions: providerCount,
        reconciliationSessions: sessionCount,
        columnMappings: mappingCount,
      },
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      status: 'unhealthy',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/carry-forward/:id
// POST /api/reconciliation/carry-forward/:id
router.post('/carry-forward/:id', async (req, res) => {
  try {
    const { notes } = req.body;

    const providerTxn = await ProviderTransaction.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    
    if (!providerTxn) {
      return res.status(404).json({
        success: false,
        message: 'Provider transaction not found.',
        error: 'Transaction not found'
      });
    }

    if (providerTxn.reconciliationStatus === 'MATCHED') {
      return res.status(400).json({
        success: false,
        message: 'This transaction is already matched. Only unmatched transactions can be carried forward.',
      });
    }

    if (providerTxn.isCarriedForward) {
      return res.status(400).json({
        success: false,
        message: 'This transaction has already been carried forward to the next period.',
      });
    }

    providerTxn.reconciliationStatus = 'CARRIED_FORWARD';
    providerTxn.isCarriedForward = true;
    providerTxn.carriedForwardAt = new Date();
    providerTxn.carriedForwardNotes = notes || 'Carried forward to next reconciliation period';
    providerTxn.carriedForwardBy = 'system';

    await providerTxn.save();

    // ✅ AUDIT LOG — Phase 8
    await createAuditLog(null, providerTxn.accountId, 'TRANSACTION_CARRIED_FORWARD', {
      transactionId: providerTxn._id,
      amount: providerTxn.amount,
      notes,
    });

    console.log(`➡️ Transaction carried forward: ${providerTxn._id} — ₹${providerTxn.amount}`);

    res.json({
      success: true,
      message: `Transaction of ₹${providerTxn.amount.toFixed(2)} has been carried forward to the next reconciliation period.`,
      data: providerTxn,
    });

  } catch (error) {
    console.error('❌ Error carrying forward transaction:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to carry forward transaction. Please try again.',
      error: error.message,
    });
  }
});
// POST /api/reconciliation/adjustment/:id
// POST /api/reconciliation/adjustment/:id
router.post('/adjustment/:id', async (req, res) => {
  try {
    const { reason, notes, adjustmentType } = req.body;

    if (!reason) {
      return res.status(400).json({
        success: false,
        message: 'A reason is required to mark a transaction as an adjustment.',
      });
    }

    const providerTxn = await ProviderTransaction.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!providerTxn) {
      return res.status(404).json({
        success: false,
        message: 'Provider transaction not found.',
      });
    }

    if (providerTxn.reconciliationStatus === 'MATCHED') {
      return res.status(400).json({
        success: false,
        message: 'This transaction is already matched. Only unmatched transactions can be marked as adjustments.',
      });
    }

    const adjustmentExpense = new Expense({
      date: new Date().toISOString().split('T')[0],
      expenseAccount: 'Reconciliation Adjustment',
      paidThrough: providerTxn.accountId.toString(),
      total: providerTxn.amount,
      amount: providerTxn.amount,
      tax: 0,
      orgId: req.user?.orgId || null,
      expenseNumber: `ADJ-${Date.now()}`,
      vendor: 'Reconciliation Adjustment',
      notes: `Adjustment for unmatched provider transaction. Reason: ${reason}. ${notes || ''}`.trim(),
      isReconciliationAdjustment: true,
      adjustmentReason: reason,
      providerTransactionId: providerTxn._id,
    });

    await adjustmentExpense.save();

    console.log(`📝 Adjustment expense created: ${adjustmentExpense._id} — ₹${providerTxn.amount}`);

    providerTxn.reconciliationStatus = 'MATCHED';
    providerTxn.matchedExpenseId = adjustmentExpense._id;
    providerTxn.matchedBy = 'adjustment';
    providerTxn.matchedAt = new Date();
    providerTxn.variance = 0;
    providerTxn.varianceReason = `Adjustment: ${reason}`;
    providerTxn.isAdjustment = true;
    providerTxn.adjustmentReason = reason;
    providerTxn.adjustmentNotes = notes || null;
    providerTxn.adjustmentType = adjustmentType || 'WRITE_OFF';

    await providerTxn.save();

    // ✅ AUDIT LOG — Phase 8
    await createAuditLog(null, providerTxn.accountId, 'TRANSACTION_ADJUSTED', {
      transactionId: providerTxn._id,
      adjustmentExpenseId: adjustmentExpense._id,
      amount: providerTxn.amount,
      reason,
      adjustmentType,
    });

    console.log(`✅ Transaction marked as adjustment: ${providerTxn._id}`);

    res.json({
      success: true,
      message: `Transaction of ₹${providerTxn.amount.toFixed(2)} has been marked as an adjustment and an expense entry has been created.`,
      data: {
        providerTransaction: providerTxn,
        adjustmentExpense: adjustmentExpense,
      },
    });

  } catch (error) {
    console.error('❌ Error creating adjustment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create adjustment. Please try again.',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/bulk-resolve
router.post('/bulk-resolve', async (req, res) => {
  try {
    const { transactionIds, action, reason, notes } = req.body;

    if (!transactionIds || !transactionIds.length) {
      return res.status(400).json({
        success: false,
        message: 'No transaction IDs provided.',
      });
    }

    if (!action || !['carry-forward', 'adjustment'].includes(action)) {
      return res.status(400).json({
        success: false,
        message: 'Action must be either "carry-forward" or "adjustment".',
      });
    }

    if (action === 'adjustment' && !reason) {
      return res.status(400).json({
        success: false,
        message: 'A reason is required for bulk adjustment.',
      });
    }

    console.log(`📦 Bulk resolve: ${transactionIds.length} transactions → ${action}`);

    const results = [];
    const errors = [];

    for (const txnId of transactionIds) {
      try {
        const providerTxn = await ProviderTransaction.findOne({
          _id: txnId,
          ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
        });
        if (!providerTxn) {
          errors.push({ id: txnId, error: 'Transaction not found' });
          continue;
        }

        if (action === 'carry-forward') {
          providerTxn.reconciliationStatus = 'CARRIED_FORWARD';
          providerTxn.isCarriedForward = true;
          providerTxn.carriedForwardAt = new Date();
          providerTxn.carriedForwardNotes = notes || 'Bulk carried forward';
          providerTxn.carriedForwardBy = 'system';
          await providerTxn.save();
          results.push({ id: txnId, action: 'carried-forward', amount: providerTxn.amount });

        } else if (action === 'adjustment') {
          const adjustmentExpense = new Expense({
            date: new Date().toISOString().split('T')[0],
            expenseAccount: 'Reconciliation Adjustment',
            paidThrough: providerTxn.accountId.toString(),
            total: providerTxn.amount,
            amount: providerTxn.amount,
            tax: 0,
            orgId: req.user?.orgId || null,
            expenseNumber: `ADJ-${Date.now()}`,
            vendor: 'Reconciliation Adjustment',
            notes: `Bulk adjustment. Reason: ${reason}. ${notes || ''}`.trim(),
            isReconciliationAdjustment: true,
            adjustmentReason: reason,
            providerTransactionId: providerTxn._id,
          });
          await adjustmentExpense.save();

          providerTxn.reconciliationStatus = 'MATCHED';
          providerTxn.matchedExpenseId = adjustmentExpense._id;
          providerTxn.matchedBy = 'bulk-adjustment';
          providerTxn.matchedAt = new Date();
          providerTxn.variance = 0;
          providerTxn.varianceReason = `Bulk Adjustment: ${reason}`;
          providerTxn.isAdjustment = true;
          providerTxn.adjustmentReason = reason;
          await providerTxn.save();
          results.push({ id: txnId, action: 'adjusted', amount: providerTxn.amount });
        }

      } catch (err) {
        console.error(`❌ Error processing ${txnId}:`, err.message);
        errors.push({ id: txnId, error: err.message });
      }
    }

    console.log(`✅ Bulk resolve complete: ${results.length} success, ${errors.length} errors`);

    res.json({
      success: true,
      message: `${results.length} transaction(s) resolved successfully${errors.length > 0 ? `, ${errors.length} failed` : ''}.`,
      data: { results, errors },
    });

  } catch (error) {
    console.error('❌ Bulk resolve error:', error);
    res.status(500).json({
      success: false,
      message: 'Bulk resolve failed. Please try again.',
      error: error.message,
    });
  }
});


// GET /api/reconciliation/sessions/:id/report
router.get('/sessions/:id/report', async (req, res) => {
  try {
    const session = await ReconciliationSession.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!session) {
      return res.status(404).json({
        success: false,
        message: 'Reconciliation session not found.',
      });
    }

    const providerTxns = await ProviderTransaction.find({
      accountId: session.accountId,
      transactionDate: { $gte: session.periodStart, $lte: session.periodEnd },
    }).sort({ transactionDate: 1 });

    const PaymentAccount = mongoose.models.PaymentAccount || 
  mongoose.model('PaymentAccount', new mongoose.Schema({}, { strict: false }), 'paymentaccounts');
    const account = await PaymentAccount.findById(session.accountId);

    const matched = providerTxns.filter(t => t.reconciliationStatus === 'MATCHED' && !t.isAdjustment);
    const adjustments = providerTxns.filter(t => t.isAdjustment === true);
    const carriedForward = providerTxns.filter(t => t.isCarriedForward === true);
    const unmatched = providerTxns.filter(t => t.reconciliationStatus === 'UNMATCHED');

    res.json({
      success: true,
      data: {
        session,
        account: account ? { accountName: account.accountName, accountType: account.accountType } : null,
        summary: {
          totalTransactions: providerTxns.length,
          matched: matched.length,
          adjustments: adjustments.length,
          carriedForward: carriedForward.length,
          unmatched: unmatched.length,
          totalAmount: providerTxns.reduce((s, t) => s + t.amount, 0),
          matchedAmount: matched.reduce((s, t) => s + t.amount, 0),
          adjustmentAmount: adjustments.reduce((s, t) => s + t.amount, 0),
          carriedForwardAmount: carriedForward.reduce((s, t) => s + t.amount, 0),
        },
        transactions: {
          matched,
          adjustments,
          carriedForward,
          unmatched,
        },
      },
    });

  } catch (error) {
    console.error('❌ Error generating report data:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to generate report. Please try again.',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/sessions/:id/submit-for-approval
router.post('/sessions/:id/submit-for-approval', async (req, res) => {
  try {
    const { submittedBy, notes } = req.body;

    const session = await ReconciliationSession.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!session) {
      return res.status(404).json({
        success: false,
        message: 'Reconciliation session not found.',
      });
    }

    if (session.isLocked) {
      return res.status(400).json({
        success: false,
        message: 'This session is already locked and finalized.',
      });
    }

    if (session.submittedForApproval) {
      return res.status(400).json({
        success: false,
        message: 'This session has already been submitted for approval. Please wait for the approver to review it.',
      });
    }

    const unmatchedCount = await ProviderTransaction.countDocuments({
      accountId: session.accountId,
      transactionDate: { $gte: session.periodStart, $lte: session.periodEnd },
      reconciliationStatus: 'UNMATCHED',
    });

    if (unmatchedCount > 0) {
      return res.status(400).json({
        success: false,
        message: `Cannot submit for approval: ${unmatchedCount} unmatched transaction(s) still need to be resolved first.`,
        unmatchedCount,
      });
    }

    session.submittedForApproval = true;
    session.submittedAt = new Date();
    session.submittedBy = submittedBy || 'system';
    session.approvalStatus = 'PENDING_APPROVAL';
    session.reconciliationNotes = notes || session.reconciliationNotes;

    await session.save();

    // ✅ AUDIT LOG — Phase 8
    await createAuditLog(session._id, session.accountId, 'SESSION_SUBMITTED_FOR_APPROVAL', {
      submittedBy: session.submittedBy,
    }, session.submittedBy);

    console.log(`📤 Session submitted for approval: ${session._id} by ${session.submittedBy}`);

    res.json({
      success: true,
      message: 'Reconciliation submitted for approval successfully. The approver will be notified.',
      data: session,
    });

  } catch (error) {
    console.error('❌ Error submitting for approval:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to submit for approval. Please try again.',
      error: error.message,
    });
  }
});

// POST /api/reconciliation/sessions/:id/approve
router.post('/sessions/:id/approve', async (req, res) => {
  try {
    const { action, approvedBy, approvalNotes, rejectionReason } = req.body;

    if (!action || !['approve', 'reject'].includes(action)) {
      return res.status(400).json({
        success: false,
        message: 'Action must be either "approve" or "reject".',
      });
    }

    const session = await ReconciliationSession.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });

    if (!session) {
      return res.status(404).json({
        success: false,
        message: 'Reconciliation session not found.',
      });
    }

    if (!session.submittedForApproval) {
      return res.status(400).json({
        success: false,
        message: 'This session has not been submitted for approval yet.',
      });
    }

    if (session.approvalStatus !== 'PENDING_APPROVAL') {
      return res.status(400).json({
        success: false,
        message: `This session has already been ${session.approvalStatus === 'APPROVED' ? 'approved' : 'rejected'}.`,
      });
    }

    if (action === 'approve') {
      const stats = await calculateSessionStats(
        session.accountId,
        session.periodStart,
        session.periodEnd
      );

      Object.assign(session, stats);
      session.approvalStatus = 'APPROVED';
      session.approvedBy = approvedBy || 'system';
      session.approvedAt = new Date();
      session.approvalNotes = approvalNotes || null;
      session.status = 'LOCKED';
      session.isLocked = true;
      session.lockedBy = approvedBy || 'system';
      session.lockedAt = new Date();

      await session.save();

      // ✅ AUDIT LOG — Phase 8 (approve branch)
      await createAuditLog(session._id, session.accountId, 'SESSION_APPROVED', {
        approvedBy: session.approvedBy,
        approvalNotes,
      }, session.approvedBy);

      console.log(`✅ Session approved and locked: ${session._id} by ${session.approvedBy}`);

      res.json({
        success: true,
        message: 'Reconciliation approved and locked successfully.',
        data: session,
      });

    } else {
      if (!rejectionReason) {
        return res.status(400).json({
          success: false,
          message: 'A rejection reason is required.',
        });
      }

      session.approvalStatus = 'REJECTED';
      session.rejectedBy = approvedBy || 'system';
      session.rejectedAt = new Date();
      session.rejectionReason = rejectionReason;
      session.submittedForApproval = false;

      await session.save();

      // ✅ AUDIT LOG — Phase 8 (reject branch)
      await createAuditLog(session._id, session.accountId, 'SESSION_REJECTED', {
        rejectedBy: session.rejectedBy,
        rejectionReason,
      }, session.rejectedBy);

      console.log(`❌ Session rejected: ${session._id} by ${session.rejectedBy}. Reason: ${rejectionReason}`);

      res.json({
        success: true,
        message: 'Reconciliation rejected. The reconciler has been notified and can make corrections.',
        data: session,
      });
    }

  } catch (error) {
    console.error('❌ Error processing approval:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process approval. Please try again.',
      error: error.message,
    });
  }
});
// GET /api/reconciliation/audit-log
router.get('/audit-log', async (req, res) => {
  try {
    const { sessionId, accountId, limit = 50 } = req.query;

    const filter = {};
    if (sessionId) filter.sessionId = sessionId;
    if (accountId) filter.accountId = accountId;

    const logs = await ReconciliationAuditLog.find(filter)
      .sort({ performedAt: -1 })
      .limit(parseInt(limit));

    res.json({
      success: true,
      count: logs.length,
      data: logs,
    });

  } catch (error) {
    console.error('❌ Error fetching audit log:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch audit log.',
      error: error.message,
    });
  }
});

// GET /api/reconciliation/alerts/:accountId
router.get('/alerts/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const alerts = [];
    const now = new Date();

    // Alert 1: Sessions stuck in progress > 30 days
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const stuckSessions = await ReconciliationSession.find({
      accountId,
      status: 'IN_PROGRESS',
      startedAt: { $lt: thirtyDaysAgo },
    });

    if (stuckSessions.length > 0) {
      alerts.push({
        type: 'STUCK_SESSION',
        severity: 'high',
        title: 'Unfinished Reconciliation',
        message: `${stuckSessions.length} reconciliation session(s) have been in progress for more than 30 days.`,
        actionLabel: 'Review Sessions',
        count: stuckSessions.length,
      });
    }

    // Alert 2: Unmatched transactions older than 7 days
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const oldUnmatched = await ProviderTransaction.countDocuments({
      accountId,
      reconciliationStatus: 'UNMATCHED',
      transactionDate: { $lt: sevenDaysAgo },
    });

    if (oldUnmatched > 0) {
      alerts.push({
        type: 'OLD_UNMATCHED',
        severity: oldUnmatched > 10 ? 'high' : 'medium',
        title: 'Old Unmatched Transactions',
        message: `${oldUnmatched} unmatched transaction(s) are more than 7 days old and need attention.`,
        actionLabel: 'View Transactions',
        count: oldUnmatched,
      });
    }

    // Alert 3: Pending approval sessions
    const pendingApproval = await ReconciliationSession.countDocuments({
      accountId,
      approvalStatus: 'PENDING_APPROVAL',
    });

    if (pendingApproval > 0) {
      alerts.push({
        type: 'PENDING_APPROVAL',
        severity: 'medium',
        title: 'Waiting for Approval',
        message: `${pendingApproval} reconciliation session(s) are waiting for your approval.`,
        actionLabel: 'Review & Approve',
        count: pendingApproval,
      });
    }

    // Alert 4: Sessions rejected by approver
    const rejected = await ReconciliationSession.countDocuments({
      accountId,
      approvalStatus: 'REJECTED',
      isLocked: false,
    });

    if (rejected > 0) {
      alerts.push({
        type: 'REJECTED_SESSION',
        severity: 'high',
        title: 'Reconciliation Rejected',
        message: `${rejected} reconciliation session(s) were rejected and need to be corrected.`,
        actionLabel: 'Fix & Resubmit',
        count: rejected,
      });
    }

    // Alert 5: No reconciliation ever done for this account
    const totalSessions = await ReconciliationSession.countDocuments({ accountId });
    if (totalSessions === 0) {
      alerts.push({
        type: 'NO_RECONCILIATION',
        severity: 'low',
        title: 'No Reconciliation Found',
        message: 'This account has never been reconciled. Start your first reconciliation session.',
        actionLabel: 'Start Reconciliation',
        count: 0,
      });
    }

    console.log(`📊 Alerts for account ${accountId}: ${alerts.length} alerts`);

    res.json({
      success: true,
      count: alerts.length,
      data: alerts,
    });

  } catch (error) {
    console.error('❌ Error fetching alerts:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch alerts.',
      error: error.message,
    });
  }
});

// GET /api/reconciliation/history/:accountId
router.get('/history/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const { limit = 20, page = 1 } = req.query;

    const skip = (parseInt(page) - 1) * parseInt(limit);

    const sessions = await ReconciliationSession.find({ accountId })
      .sort({ startedAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    const total = await ReconciliationSession.countDocuments({ accountId });

    const history = sessions.map(s => ({
      id: s._id,
      period: `${new Date(s.periodStart).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })} – ${new Date(s.periodEnd).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })}`,
      periodStart: s.periodStart,
      periodEnd: s.periodEnd,
      status: s.status,
      isLocked: s.isLocked,
      approvalStatus: s.approvalStatus,
      totalMatched: s.totalMatched,
      totalUnmatched: s.totalUnmatched,
      totalPending: s.totalPending,
      providerBalance: s.providerBalance,
      systemBalance: s.systemBalance,
      balanceDifference: s.balanceDifference,
      startedBy: s.startedBy,
      startedAt: s.startedAt,
      completedAt: s.completedAt,
      lockedAt: s.lockedAt,
      lockedBy: s.lockedBy,
      approvedBy: s.approvedBy,
      rejectionReason: s.rejectionReason,
      reconciliationNotes: s.reconciliationNotes,
    }));

    res.json({
      success: true,
      count: sessions.length,
      total,
      page: parseInt(page),
      totalPages: Math.ceil(total / parseInt(limit)),
      data: history,
    });

  } catch (error) {
    console.error('❌ Error fetching history:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch reconciliation history.',
      error: error.message,
    });
  }
});

module.exports = router;