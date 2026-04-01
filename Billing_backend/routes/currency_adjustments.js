// ============================================================================
// CURRENCY ADJUSTMENTS — COMPLETE BACKEND
// ============================================================================
// File: backend/routes/currency_adjustments.js
// Register in app.js:
//   app.use('/api/finance/currency-adjustments',
//           require('./routes/currency_adjustments'));
// ============================================================================

const express  = require('express');
const router   = express.Router();
const mongoose = require('mongoose');
const multer   = require('multer');

const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

let ManualJournal;
try { ManualJournal = require('./manual_journal').ManualJournal; } catch (_) {}

const { verifyFinanceJWT } = require('../middleware/finance_jwt');
const authenticate = verifyFinanceJWT;

const SUPPORTED_CURRENCIES = [
  'USD','EUR','GBP','AED','SGD','JPY','CNY','CHF',
  'CAD','AUD','NZD','SAR','QAR','KWD','BHD','OMR',
  'MYR','THB','IDR','PHP','ZAR','HKD','SEK','NOK','DKK',
];

// ============================================================================
// SCHEMA
// ============================================================================

const adjustmentLineSchema = new mongoose.Schema({
  transactionType:      { type: String, enum: ['Invoice','Bill'], required: true },
  transactionId:        { type: mongoose.Schema.Types.ObjectId, required: true },
  transactionNumber:    { type: String, required: true },
  partyName:            { type: String, default: '' },
  partyId:              { type: mongoose.Schema.Types.ObjectId, default: null },
  amountDue:            { type: Number, default: 0 },
  originalRate:         { type: Number, default: 1 },
  newRate:              { type: Number, required: true },
  gainLoss:             { type: Number, default: 0 },
  baseCurrencyGainLoss: { type: Number, default: 0 },
  dueDate:              { type: Date, default: null },
  status:               { type: String, default: '' },
}, { _id: true });

const currencyAdjustmentSchema = new mongoose.Schema({
  adjustmentNumber: { type: String, required: true, unique: true, index: true },
  adjustmentDate:   { type: Date, required: true, default: Date.now },
  currency:         { type: String, required: true, uppercase: true, trim: true },
  newExchangeRate:  { type: Number, required: true, min: 0 },
  notes:            { type: String, default: '', trim: true },
  lineItems:        [adjustmentLineSchema],
  totalGain:        { type: Number, default: 0 },
  totalLoss:        { type: Number, default: 0 },
  netAdjustment:    { type: Number, default: 0 },
  totalTransactions:{ type: Number, default: 0 },
  status:           { type: String, enum: ['Draft','Published','Void'], default: 'Draft', index: true },
  coaEntriesCreated:{ type: Boolean, default: false },
  journalId:        { type: mongoose.Schema.Types.ObjectId, default: null },
  journalNumber:    { type: String, default: null },
  voidedAt:         { type: Date, default: null },
  voidedBy:         { type: String, default: null },
  voidReason:       { type: String, default: null },
  createdBy:        { type: String, default: 'system' },
  updatedBy:        { type: String, default: 'system' },
  publishedAt:      { type: Date, default: null },
  publishedBy:      { type: String, default: null },
  companyId:        { type: String, default: 'default' },
  orgId:            { type: String, index: true, default: null },
}, { timestamps: true });

currencyAdjustmentSchema.index({ adjustmentDate: -1 });
currencyAdjustmentSchema.index({ currency: 1, status: 1 });

currencyAdjustmentSchema.pre('save', function(next) {
  let gain = 0, loss = 0;
  this.lineItems.forEach(l => {
    if (l.gainLoss > 0) gain += l.gainLoss;
    else                loss += Math.abs(l.gainLoss);
  });
  this.totalGain         = Math.round(gain * 100) / 100;
  this.totalLoss         = Math.round(loss * 100) / 100;
  this.netAdjustment     = Math.round((gain - loss) * 100) / 100;
  this.totalTransactions = this.lineItems.length;
  next();
});

const CurrencyAdjustment = mongoose.models.CurrencyAdjustment
  || mongoose.model('CurrencyAdjustment', currencyAdjustmentSchema);

// ============================================================================
// SEED EXCHANGE ACCOUNTS
// ============================================================================

async function seedExchangeAccounts() {
  const toSeed = [
    { accountCode: '4900', accountName: 'Exchange Gain', accountType: 'Other Income',   accountSubType: 'Other Income',   description: 'Gain from forex rate movements', isSystemAccount: true, isActive: true, createdBy: 'system' },
    { accountCode: '5900', accountName: 'Exchange Loss', accountType: 'Other Expense',  accountSubType: 'Other Expense',  description: 'Loss from forex rate movements', isSystemAccount: true, isActive: true, createdBy: 'system' },
  ];
  for (const acc of toSeed) {
    const exists = await ChartOfAccount.findOne({ accountName: acc.accountName });
    if (!exists) { await ChartOfAccount.create(acc); console.log(`✅ Seeded: ${acc.accountName}`); }
  }
}
seedExchangeAccounts().catch(console.error);

// ============================================================================
// HELPERS
// ============================================================================

async function generateAdjustmentNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(CurrencyAdjustment, 'adjustmentNumber', 'CADJ', orgId);
}

async function getAccountId(name) {
  const acc = await ChartOfAccount.findOne({ accountName: name, isSystemAccount: true }).select('_id').lean();
  return acc ? acc._id : null;
}

async function fetchOpenInvoices(currency) {
  const Invoice = mongoose.models.Invoice;
  if (!Invoice) return [];
  return Invoice.find({ currency: currency.toUpperCase(), status: { $in: ['UNPAID','PARTIALLY_PAID','OVERDUE','SENT'] }, amountDue: { $gt: 0 } })
    .select('invoiceNumber customerId customerName invoiceDate dueDate status amountDue totalAmount currency exchangeRate').lean();
}

async function fetchOpenBills(currency) {
  const Bill = mongoose.models.Bill;
  if (!Bill) return [];
  return Bill.find({ currency: currency.toUpperCase(), status: { $in: ['OPEN','PARTIALLY_PAID','OVERDUE'] }, amountDue: { $gt: 0 } })
    .select('billNumber vendorId vendorName billDate dueDate status amountDue totalAmount currency exchangeRate').lean();
}

function buildLineItems(invoices, bills, newRate) {
  const lines = [];
  for (const inv of invoices) {
    const origRate = inv.exchangeRate || 1;
    const gainLoss = Math.round((newRate - origRate) * inv.amountDue * 100) / 100;
    lines.push({ transactionType: 'Invoice', transactionId: inv._id, transactionNumber: inv.invoiceNumber, partyName: inv.customerName || '', partyId: inv.customerId || null, amountDue: inv.amountDue, originalRate: origRate, newRate, gainLoss, baseCurrencyGainLoss: gainLoss, dueDate: inv.dueDate || null, status: inv.status });
  }
  for (const bill of bills) {
    const origRate = bill.exchangeRate || 1;
    const gainLoss = Math.round((origRate - newRate) * bill.amountDue * 100) / 100;
    lines.push({ transactionType: 'Bill', transactionId: bill._id, transactionNumber: bill.billNumber, partyName: bill.vendorName || '', partyId: bill.vendorId || null, amountDue: bill.amountDue, originalRate: origRate, newRate, gainLoss, baseCurrencyGainLoss: gainLoss, dueDate: bill.dueDate || null, status: bill.status });
  }
  return lines;
}

async function postCOAEntries(adj, reverse = false) {
  const [gainId, lossId, arId, apId] = await Promise.all([
    getAccountId('Exchange Gain'), getAccountId('Exchange Loss'),
    getAccountId('Accounts Receivable'), getAccountId('Accounts Payable'),
  ]);
  const txnDate = reverse ? new Date() : new Date(adj.adjustmentDate);
  const prefix  = reverse ? 'VOID: ' : '';

  for (const line of adj.lineItems) {
    if (Math.abs(line.gainLoss) < 0.01) continue;
    const isGain = reverse ? line.gainLoss < 0 : line.gainLoss > 0; // flip on reverse
    const amt  = Math.abs(line.gainLoss);
    const desc = `${prefix}Currency Adj ${adj.adjustmentNumber} — ${line.transactionType} ${line.transactionNumber} (${adj.currency})`;
    const ref  = { referenceType: 'Journal', referenceId: adj._id, referenceNumber: adj.adjustmentNumber };

    if (line.transactionType === 'Invoice') {
      if (isGain) {
        if (arId)   await postTransactionToCOA({ accountId: arId,   date: txnDate, description: desc, ...ref, debit: amt, credit: 0   });
        if (gainId) await postTransactionToCOA({ accountId: gainId, date: txnDate, description: desc, ...ref, debit: 0,   credit: amt });
      } else {
        if (lossId) await postTransactionToCOA({ accountId: lossId, date: txnDate, description: desc, ...ref, debit: amt, credit: 0   });
        if (arId)   await postTransactionToCOA({ accountId: arId,   date: txnDate, description: desc, ...ref, debit: 0,   credit: amt });
      }
    } else {
      if (isGain) {
        if (apId)   await postTransactionToCOA({ accountId: apId,   date: txnDate, description: desc, ...ref, debit: amt, credit: 0   });
        if (gainId) await postTransactionToCOA({ accountId: gainId, date: txnDate, description: desc, ...ref, debit: 0,   credit: amt });
      } else {
        if (lossId) await postTransactionToCOA({ accountId: lossId, date: txnDate, description: desc, ...ref, debit: amt, credit: 0   });
        if (apId)   await postTransactionToCOA({ accountId: apId,   date: txnDate, description: desc, ...ref, debit: 0,   credit: amt });
      }
    }
  }
  console.log(`✅ COA ${reverse ? 'reversed' : 'posted'} for: ${adj.adjustmentNumber}`);
}

async function createAuditJournal(adj, user) {
  if (!ManualJournal) return null;
  try {
    const { generateJournalNumber } = require('./manual_journal');
    const jNum = await generateJournalNumber(adj.orgId || null);
    const [gainId, lossId, arId, apId] = await Promise.all([
      getAccountId('Exchange Gain'), getAccountId('Exchange Loss'),
      getAccountId('Accounts Receivable'), getAccountId('Accounts Payable'),
    ]);
    const lineItems = [];
    for (const line of adj.lineItems) {
      if (Math.abs(line.gainLoss) < 0.01) continue;
      const isGain = line.gainLoss > 0;
      const amt    = Math.abs(line.gainLoss);
      const desc   = `${line.transactionType} ${line.transactionNumber} — ${line.partyName}`;
      if (line.transactionType === 'Invoice') {
        if (isGain) {
          if (arId)   lineItems.push({ accountId: arId,   accountName: 'Accounts Receivable', description: desc, debit: amt, credit: 0   });
          if (gainId) lineItems.push({ accountId: gainId, accountName: 'Exchange Gain',        description: desc, debit: 0,   credit: amt });
        } else {
          if (lossId) lineItems.push({ accountId: lossId, accountName: 'Exchange Loss',        description: desc, debit: amt, credit: 0   });
          if (arId)   lineItems.push({ accountId: arId,   accountName: 'Accounts Receivable',  description: desc, debit: 0,   credit: amt });
        }
      } else {
        if (isGain) {
          if (apId)   lineItems.push({ accountId: apId,   accountName: 'Accounts Payable', description: desc, debit: amt, credit: 0   });
          if (gainId) lineItems.push({ accountId: gainId, accountName: 'Exchange Gain',     description: desc, debit: 0,   credit: amt });
        } else {
          if (lossId) lineItems.push({ accountId: lossId, accountName: 'Exchange Loss',     description: desc, debit: amt, credit: 0   });
          if (apId)   lineItems.push({ accountId: apId,   accountName: 'Accounts Payable',  description: desc, debit: 0,   credit: amt });
        }
      }
    }
    if (lineItems.length === 0) return null;
    const journal = await ManualJournal.create({
      journalNumber: jNum, date: adj.adjustmentDate,
      referenceNumber: adj.adjustmentNumber,
      notes: `Auto-generated for Currency Adjustment ${adj.adjustmentNumber} (${adj.currency} @ ${adj.newExchangeRate})`,
      reportingMethod: 'Accrual and Cash', currency: 'INR',
      lineItems, status: 'Published',
      publishedAt: new Date(), publishedBy: user, createdBy: user,
    });
    console.log(`✅ Audit journal: ${journal.journalNumber}`);
    return journal;
  } catch (e) { console.error('⚠️ Audit journal failed:', e.message); return null; }
}

async function updateTransactionRates(adj) {
  const Invoice = mongoose.models.Invoice;
  const Bill    = mongoose.models.Bill;
  for (const line of adj.lineItems) {
    try {
      if (line.transactionType === 'Invoice' && Invoice) {
        await Invoice.findByIdAndUpdate(line.transactionId, { exchangeRate: adj.newExchangeRate, baseCurrencyAmount: line.amountDue * adj.newExchangeRate, updatedAt: new Date() });
      } else if (line.transactionType === 'Bill' && Bill) {
        await Bill.findByIdAndUpdate(line.transactionId, { exchangeRate: adj.newExchangeRate, baseCurrencyAmount: line.amountDue * adj.newExchangeRate, updatedAt: new Date() });
      }
    } catch (e) { console.error(`⚠️ Rate update failed ${line.transactionNumber}:`, e.message); }
  }
}

// ============================================================================
// ROUTES
// ============================================================================

router.get('/stats', authenticate, async (req, res) => {
  try {
    const [total, draft, published, voided, agg] = await Promise.all([
      CurrencyAdjustment.countDocuments({}),
      CurrencyAdjustment.countDocuments({ status: 'Draft' }),
      CurrencyAdjustment.countDocuments({ status: 'Published' }),
      CurrencyAdjustment.countDocuments({ status: 'Void' }),
      CurrencyAdjustment.aggregate([{ $match: { status: 'Published' } }, { $group: { _id: null, totalGain: { $sum: '$totalGain' }, totalLoss: { $sum: '$totalLoss' }, netAdjustment: { $sum: '$netAdjustment' } } }]),
    ]);
    const pub = agg[0] || { totalGain: 0, totalLoss: 0, netAdjustment: 0 };
    res.json({ success: true, data: { total, draft, published, voided, totalGain: pub.totalGain, totalLoss: pub.totalLoss, netAdjustment: pub.netAdjustment } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/supported-currencies', authenticate, async (req, res) => {
  res.json({ success: true, data: SUPPORTED_CURRENCIES });
});

router.get('/open-transactions', authenticate, async (req, res) => {
  try {
    const { currency } = req.query;
    if (!currency) return res.status(400).json({ success: false, message: 'currency is required' });
    const [invoices, bills] = await Promise.all([fetchOpenInvoices(currency), fetchOpenBills(currency)]);
    const transactions = [
      ...invoices.map(inv  => ({ transactionType: 'Invoice', transactionId: inv._id,  transactionNumber: inv.invoiceNumber, partyName: inv.customerName || '', partyId: inv.customerId || null, amountDue: inv.amountDue, originalRate: inv.exchangeRate || 1, dueDate: inv.dueDate, status: inv.status, currency: inv.currency })),
      ...bills.map(bill    => ({ transactionType: 'Bill',    transactionId: bill._id, transactionNumber: bill.billNumber,   partyName: bill.vendorName  || '', partyId: bill.vendorId  || null, amountDue: bill.amountDue, originalRate: bill.exchangeRate || 1, dueDate: bill.dueDate, status: bill.status, currency: bill.currency })),
    ];
    res.json({ success: true, data: transactions, count: transactions.length });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/', authenticate, async (req, res) => {
  try {
    const { status, currency, fromDate, toDate, search, page = 1, limit = 50 } = req.query;
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;
    if (status && status !== 'All')     query.status   = status;
    if (currency && currency !== 'All') query.currency = currency.toUpperCase();
    if (fromDate || toDate) {
      query.adjustmentDate = {};
      if (fromDate) query.adjustmentDate.$gte = new Date(fromDate);
      if (toDate)   query.adjustmentDate.$lte = new Date(new Date(toDate).setHours(23,59,59));
    }
    if (search) query.$or = [{ adjustmentNumber: { $regex: search, $options: 'i' } }, { currency: { $regex: search, $options: 'i' } }, { notes: { $regex: search, $options: 'i' } }];
    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const total = await CurrencyAdjustment.countDocuments(query);
    const adjustments = await CurrencyAdjustment.find(query).sort({ adjustmentDate: -1, createdAt: -1 }).skip(skip).limit(parseInt(limit)).lean();
    res.json({ success: true, data: { adjustments: adjustments.map(a => ({ ...a, id: a._id })), pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) } } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.get('/:id', authenticate, async (req, res) => {
  try {
    const adj = await CurrencyAdjustment.findById(req.params.id).lean();
    if (!adj) return res.status(404).json({ success: false, message: 'Adjustment not found' });
    res.json({ success: true, data: { ...adj, id: adj._id } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.post('/', authenticate, async (req, res) => {
  try {
    const { currency, adjustmentDate, newExchangeRate, notes } = req.body;
    if (!currency)        return res.status(400).json({ success: false, message: 'Currency is required' });
    if (!newExchangeRate) return res.status(400).json({ success: false, message: 'New exchange rate is required' });
    if (!notes || !notes.trim()) return res.status(400).json({ success: false, message: 'Notes / reason is required' });
    if (currency.toUpperCase() === 'INR') return res.status(400).json({ success: false, message: 'Cannot adjust base currency (INR)' });

    const upperCurrency = currency.toUpperCase();
    const rate = parseFloat(newExchangeRate);
    const [invoices, bills] = await Promise.all([fetchOpenInvoices(upperCurrency), fetchOpenBills(upperCurrency)]);
    const lineItems = buildLineItems(invoices, bills, rate);
    const adjNumber = await generateAdjustmentNumber(req.user?.orgId || null);

    const adjustment = await CurrencyAdjustment.create({
      adjustmentNumber: adjNumber,
      adjustmentDate:   adjustmentDate ? new Date(adjustmentDate) : new Date(),
      currency: upperCurrency, newExchangeRate: rate, notes: notes.trim(),
      lineItems, status: 'Draft', createdBy: req.user?.email || 'system',
      orgId: req.user?.orgId || null,
    });

    console.log(`✅ Currency adjustment created: ${adjustment.adjustmentNumber}`);
    res.status(201).json({ success: true, message: 'Currency adjustment created as draft', data: { ...adjustment.toObject(), id: adjustment._id } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.put('/:id', authenticate, async (req, res) => {
  try {
    const adj = await CurrencyAdjustment.findById(req.params.id);
    if (!adj) return res.status(404).json({ success: false, message: 'Not found' });
    if (adj.status !== 'Draft') return res.status(400).json({ success: false, message: 'Only Draft adjustments can be edited' });

    const { adjustmentDate, newExchangeRate, notes } = req.body;
    if (adjustmentDate)         adj.adjustmentDate  = new Date(adjustmentDate);
    if (notes !== undefined)    adj.notes           = notes;
    if (newExchangeRate) {
      adj.newExchangeRate = parseFloat(newExchangeRate);
      const [invoices, bills] = await Promise.all([fetchOpenInvoices(adj.currency), fetchOpenBills(adj.currency)]);
      adj.lineItems = buildLineItems(invoices, bills, parseFloat(newExchangeRate));
    }
    adj.updatedBy = req.user?.email || 'system';
    await adj.save();
    res.json({ success: true, message: 'Adjustment updated', data: { ...adj.toObject(), id: adj._id } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.post('/:id/publish', authenticate, async (req, res) => {
  try {
    const adj = await CurrencyAdjustment.findById(req.params.id);
    if (!adj) return res.status(404).json({ success: false, message: 'Not found' });
    if (adj.status === 'Published') return res.status(400).json({ success: false, message: 'Already published' });
    if (adj.status === 'Void')      return res.status(400).json({ success: false, message: 'Cannot publish a voided adjustment' });
    if (!adj.notes || !adj.notes.trim()) return res.status(400).json({ success: false, message: 'Notes / reason is required' });
    if (adj.lineItems.length === 0) return res.status(400).json({ success: false, message: 'No open transactions found for this currency' });

    const user = req.user?.email || 'system';
    adj.status = 'Published'; adj.publishedAt = new Date(); adj.publishedBy = user; adj.updatedBy = user;
    await adj.save();

    await postCOAEntries(adj, false);
    adj.coaEntriesCreated = true;
    await updateTransactionRates(adj);

    const journal = await createAuditJournal(adj, user);
    if (journal) { adj.journalId = journal._id; adj.journalNumber = journal.journalNumber; }
    await adj.save();

    res.json({ success: true, message: `Published. ${journal ? `Journal ${journal.journalNumber} created.` : ''}`, data: { ...adj.toObject(), id: adj._id } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.post('/:id/void', authenticate, async (req, res) => {
  try {
    const adj = await CurrencyAdjustment.findById(req.params.id);
    if (!adj) return res.status(404).json({ success: false, message: 'Not found' });
    if (adj.status === 'Void') return res.status(400).json({ success: false, message: 'Already voided' });

    const wasPublished = adj.status === 'Published';
    adj.status = 'Void'; adj.voidedAt = new Date(); adj.voidedBy = req.user?.email || 'system';
    adj.voidReason = req.body.reason || ''; adj.updatedBy = req.user?.email || 'system';
    await adj.save();

    if (wasPublished) await postCOAEntries(adj, true);

    res.json({ success: true, message: 'Adjustment voided and COA entries reversed', data: { ...adj.toObject(), id: adj._id } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

router.delete('/:id', authenticate, async (req, res) => {
  try {
    const adj = await CurrencyAdjustment.findById(req.params.id);
    if (!adj) return res.status(404).json({ success: false, message: 'Not found' });
    if (adj.status !== 'Draft') return res.status(400).json({ success: false, message: 'Only Draft adjustments can be deleted' });
    await adj.deleteOne();
    res.json({ success: true, message: 'Adjustment deleted' });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

const importUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
router.post('/import', authenticate, importUpload.single('file'), async (req, res) => {
  try {
    const data = JSON.parse(req.body.adjustments || '[]');
    let successCount = 0, failedCount = 0;
    const errors = [];
    for (let i = 0; i < data.length; i++) {
      const item = data[i];
      try {
        if (!item.adjustmentNumber) item.adjustmentNumber = await generateAdjustmentNumber(req.user?.orgId || null);
        item.createdBy = req.user?.email || 'system'; item.status = 'Draft';
        item.orgId = req.user?.orgId || null;
        await CurrencyAdjustment.create(item);
        successCount++;
      } catch (e) { errors.push(`Row ${i + 2}: ${e.message}`); failedCount++; }
    }
    res.json({ success: true, message: `Imported ${successCount} adjustments`, data: { totalProcessed: data.length, successCount, failedCount, errors } });
  } catch (e) { res.status(500).json({ success: false, message: e.message }); }
});

module.exports = router;
module.exports.CurrencyAdjustment = CurrencyAdjustment;