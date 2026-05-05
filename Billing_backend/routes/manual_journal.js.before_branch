// ============================================================================
// MANUAL JOURNALS - COMPLETE BACKEND
// ============================================================================
// File: backend/routes/manual_journal.js
// Register in app.js: app.use('/api/manual-journals', require('./routes/manual_journal'));
// ============================================================================

const express  = require('express');
const router   = express.Router();
const mongoose = require('mongoose');
const multer   = require('multer');
const path     = require('path');
const fs       = require('fs');
const PDFDocument = require('pdfkit');

// ── COA Integration ──────────────────────────────────────────────────────────
const { postTransactionToCOA, ChartOfAccount } = require('./chart_of_accounts');

async function getAccountById(id) {
  try {
    return await ChartOfAccount.findById(id).lean();
  } catch (e) { return null; }
}

// ============================================================================
// MONGOOSE SCHEMA
// ============================================================================

const journalLineSchema = new mongoose.Schema({
  accountId:   { type: mongoose.Schema.Types.ObjectId, ref: 'ChartOfAccount', required: true },
  accountName: { type: String, required: true },
  accountCode: { type: String, default: '' },
  description: { type: String, default: '' },
  contactId:   { type: String, default: null },
  contactName: { type: String, default: null },
  contactType: { type: String, enum: ['vendor', 'customer', null], default: null },
  debit:       { type: Number, default: 0, min: 0 },
  credit:      { type: Number, default: 0, min: 0 },
}, { _id: true });

const manualJournalSchema = new mongoose.Schema({
  orgId: { type: String, index: true, default: null },
  journalNumber: { type: String, required: true, unique: true, index: true },
  date:          { type: Date, required: true, default: Date.now },
  referenceNumber: { type: String, default: '' },
  notes:         { type: String, default: '' },
  reportingMethod: {
    type: String,
    enum: ['Accrual and Cash', 'Accrual Only', 'Cash Only'],
    default: 'Accrual and Cash',
  },
  currency: { type: String, default: 'INR' },

  lineItems: [journalLineSchema],

  totalDebit:  { type: Number, default: 0 },
  totalCredit: { type: Number, default: 0 },
  difference:  { type: Number, default: 0 },

  status: {
    type: String,
    enum: ['Draft', 'Published', 'Void'],
    default: 'Draft',
    index: true,
  },

  // Template reference
  templateId:   { type: mongoose.Schema.Types.ObjectId, ref: 'JournalTemplate', default: null },
  templateName: { type: String, default: null },

  // Apply Credits linkage
  appliedCredits: [{
    type:          { type: String, enum: ['Invoice', 'Bill'], required: true },
    referenceId:   { type: mongoose.Schema.Types.ObjectId, required: true },
    referenceNumber: { type: String, required: true },
    amount:        { type: Number, required: true },
    appliedDate:   { type: Date, default: Date.now },
  }],

  // Attachments
  attachments: [{
    filename:   String,
    filepath:   String,
    size:       Number,
    uploadedAt: { type: Date, default: Date.now },
  }],

  // Void info
  voidedAt:  { type: Date, default: null },
  voidedBy:  { type: String, default: null },
  voidReason:{ type: String, default: null },

  // Clone lineage
  clonedFromId:     { type: mongoose.Schema.Types.ObjectId, default: null },
  clonedFromNumber: { type: String, default: null },

  // PDF
  pdfPath:        { type: String, default: null },
  pdfGeneratedAt: { type: Date, default: null },

  // Audit
  createdBy: { type: String, default: 'system' },
  updatedBy: { type: String, default: 'system' },
  publishedAt: { type: Date, default: null },
  publishedBy: { type: String, default: null },

  companyId: { type: String, default: 'default' },
}, { timestamps: true });

manualJournalSchema.index({ date: -1 });
manualJournalSchema.index({ status: 1, date: -1 });
manualJournalSchema.index({ journalNumber: 1 });

manualJournalSchema.pre('save', function() {
  this.totalDebit  = this.lineItems.reduce((s, l) => s + (l.debit  || 0), 0);
  this.totalCredit = this.lineItems.reduce((s, l) => s + (l.credit || 0), 0);
  this.difference  = Math.round((this.totalDebit - this.totalCredit) * 100) / 100;
});

const ManualJournal = mongoose.models.ManualJournal
  || mongoose.model('ManualJournal', manualJournalSchema);

// ============================================================================
// JOURNAL TEMPLATE SCHEMA
// ============================================================================

const journalTemplateSchema = new mongoose.Schema({
  templateName: { type: String, required: true },
  notes:        { type: String, default: '' },
  reportingMethod: { type: String, default: 'Accrual and Cash' },
  currency:     { type: String, default: 'INR' },
  lineItems: [{
    accountId:   mongoose.Schema.Types.ObjectId,
    accountName: String,
    accountCode: String,
    description: String,
    debit:       { type: Number, default: 0 },
    credit:      { type: Number, default: 0 },
  }],
  isAmountBased: { type: Boolean, default: false },
  createdBy: { type: String, default: 'system' },
}, { timestamps: true });

const JournalTemplate = mongoose.models.JournalTemplate
  || mongoose.model('JournalTemplate', journalTemplateSchema);

// ============================================================================
// HELPERS
// ============================================================================

async function generateJournalNumber(orgId = null) {
  const { generateNumber } = require('../utils/numberGenerator');
  return generateNumber(ManualJournal, 'journalNumber', 'JNL', orgId);
}

// Reverse COA entries for void
async function reverseCOAEntries(journal, orgId) {
  try {
    for (const line of journal.lineItems) {
      if (!line.accountId) continue;
      // Reverse: swap debit/credit
      if (line.debit > 0) {
        await postTransactionToCOA({
          accountId: line.accountId,
          orgId: orgId || null,
          date: new Date(),
          description: `VOID: ${journal.journalNumber} - ${line.description || line.accountName}`,
          referenceType: 'Journal',
          referenceId: journal._id,
          referenceNumber: journal.journalNumber,
          debit: 0, credit: line.debit,
        });
      }
      if (line.credit > 0) {
        await postTransactionToCOA({
          accountId: line.accountId,
          orgId: orgId || null,
          date: new Date(),
          description: `VOID: ${journal.journalNumber} - ${line.description || line.accountName}`,
          referenceType: 'Journal',
          referenceId: journal._id,
          referenceNumber: journal.journalNumber,
          debit: line.credit, credit: 0,
        });
      }
    }
    console.log(`✅ COA reversed for void: ${journal.journalNumber}`);
  } catch (e) {
    console.error('COA reverse error:', e.message);
  }
}

// Publish to COA
async function publishToCOA(journal, orgId) {
  try {
    for (const line of journal.lineItems) {
      if (!line.accountId) continue;
      if (line.debit > 0 || line.credit > 0) {
        await postTransactionToCOA({
          accountId: line.accountId,
          orgId: orgId || null,
          date: new Date(journal.date),
          description: line.description || `Journal ${journal.journalNumber} - ${line.accountName}`,
          referenceType: 'Journal',
          referenceId: journal._id,
          referenceNumber: journal.journalNumber,
          debit: line.debit || 0,
          credit: line.credit || 0,
        });
      }
    }
    console.log(`✅ COA posted for journal: ${journal.journalNumber}`);
  } catch (e) {
    console.error('COA post error:', e.message);
  }
}

// ============================================================================
// MIDDLEWARE
// ============================================================================

const { verifyFinanceJWT } = require('../middleware/finance_jwt');
const authenticate = verifyFinanceJWT;

// Multer for attachments
const attachStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', 'uploads', 'journals');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    cb(null, `jnl-${Date.now()}-${Math.round(Math.random() * 1e6)}${path.extname(file.originalname)}`);
  },
});
const attachUpload = multer({
  storage: attachStorage,
  limits: { fileSize: 10 * 1024 * 1024, files: 5 },
});

// ============================================================================
// ROUTES — STATS
// ============================================================================

router.get('/stats', authenticate, async (req, res) => {
  try {
const orgFilter = req.user?.orgId ? { orgId: req.user.orgId } : {};
const [total, draft, published, voided, agg] = await Promise.all([
  ManualJournal.countDocuments({ ...orgFilter }),
  ManualJournal.countDocuments({ ...orgFilter, status: 'Draft' }),
  ManualJournal.countDocuments({ ...orgFilter, status: 'Published' }),
  ManualJournal.countDocuments({ ...orgFilter, status: 'Void' }),
  ManualJournal.aggregate([
    { $match: { ...orgFilter, status: 'Published' } },
    { $group: { _id: null, totalDebit: { $sum: '$totalDebit' }, totalCredit: { $sum: '$totalCredit' } } },
  ]),
]);
    const pub = agg[0] || { totalDebit: 0, totalCredit: 0 };
    res.json({ success: true, data: { total, draft, published, voided, totalDebit: pub.totalDebit, totalCredit: pub.totalCredit } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — LIST
// ============================================================================

router.get('/', authenticate, async (req, res) => {
  try {
    const { status, fromDate, toDate, search, page = 1, limit = 50 } = req.query;
    const query = {};
    if (req.user?.orgId) query.orgId = req.user.orgId;

    if (status && status !== 'All') query.status = status;
    if (fromDate || toDate) {
      query.date = {};
      if (fromDate) query.date.$gte = new Date(fromDate);
      if (toDate)   query.date.$lte = new Date(new Date(toDate).setHours(23, 59, 59));
    }
    if (search && search.trim()) {
      query.$or = [
        { journalNumber:   { $regex: search.trim(), $options: 'i' } },
        { notes:           { $regex: search.trim(), $options: 'i' } },
        { referenceNumber: { $regex: search.trim(), $options: 'i' } },
      ];
    }

    const skip  = (parseInt(page) - 1) * parseInt(limit);
    const total = await ManualJournal.countDocuments(query);
    const journals = await ManualJournal.find(query)
      .sort({ date: -1, createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .lean();

    res.json({
      success: true,
      data: { journals: journals.map(j => ({ ...j, id: j._id })),
        pagination: { total, page: parseInt(page), limit: parseInt(limit), pages: Math.ceil(total / parseInt(limit)) } },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — SINGLE
// ============================================================================

router.get('/:id', authenticate, async (req, res) => {
  try {
    const j = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!j) return res.status(404).json({ success: false, message: 'Journal not found' });
    res.json({ success: true, data: { ...j, id: j._id } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — CREATE
// ============================================================================

router.post('/', authenticate, async (req, res) => {
  try {
    const data = req.body;

    if (!data.lineItems || data.lineItems.length === 0)
      return res.status(400).json({ success: false, message: 'At least one line item is required' });

    if (!data.journalNumber) data.journalNumber = await generateJournalNumber(req.user?.orgId);

    const journal = await ManualJournal.create({
      ...data,
      status: data.status || 'Draft',
      orgId: req.user?.orgId || null,
      createdBy: req.user?.email || 'system',
    });

    console.log(`✅ Journal created: ${journal.journalNumber}`);
    res.status(201).json({ success: true, message: 'Journal created', data: { ...journal.toObject(), id: journal._id } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — UPDATE
// ============================================================================

router.put('/:id', authenticate, async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });
    if (journal.status !== 'Draft')
      return res.status(400).json({ success: false, message: 'Only Draft journals can be edited' });

    const allowed = ['date','referenceNumber','notes','reportingMethod','currency','lineItems','templateId','templateName'];
    allowed.forEach(k => { if (req.body[k] !== undefined) journal[k] = req.body[k]; });
    journal.updatedBy = req.user?.email || 'system';
    await journal.save();

    res.json({ success: true, message: 'Journal updated', data: { ...journal.toObject(), id: journal._id } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — PUBLISH
// ============================================================================

router.post('/:id/publish', authenticate, async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });
    if (journal.status === 'Published')
      return res.status(400).json({ success: false, message: 'Journal is already published' });
    if (journal.status === 'Void')
      return res.status(400).json({ success: false, message: 'Cannot publish a voided journal' });

    // Validate debit = credit
    const totalDebit  = journal.lineItems.reduce((s, l) => s + (l.debit  || 0), 0);
    const totalCredit = journal.lineItems.reduce((s, l) => s + (l.credit || 0), 0);
    const diff = Math.abs(totalDebit - totalCredit);
    if (diff > 0.01)
      return res.status(400).json({ success: false, message: `Debit (${totalDebit.toFixed(2)}) must equal Credit (${totalCredit.toFixed(2)}). Difference: ${diff.toFixed(2)}` });

    journal.status      = 'Published';
    journal.publishedAt = new Date();
    journal.publishedBy = req.user?.email || 'system';
    journal.updatedBy   = req.user?.email || 'system';
    await journal.save();

    // Post to COA
    await publishToCOA(journal, req.user?.orgId);

    res.json({ success: true, message: 'Journal published and posted to Chart of Accounts', data: { ...journal.toObject(), id: journal._id } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — VOID
// ============================================================================

router.post('/:id/void', authenticate, async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });
    if (journal.status === 'Void')
      return res.status(400).json({ success: false, message: 'Journal is already voided' });

    const wasPublished = journal.status === 'Published';

    journal.status     = 'Void';
    journal.voidedAt   = new Date();
    journal.voidedBy   = req.user?.email || 'system';
    journal.voidReason = req.body.reason || '';
    journal.updatedBy  = req.user?.email || 'system';
    await journal.save();

    // Reverse COA entries if it was published
    if (wasPublished) await reverseCOAEntries(journal, req.user?.orgId);

    res.json({ success: true, message: 'Journal voided and COA entries reversed', data: { ...journal.toObject(), id: journal._id } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — CLONE
// ============================================================================

router.post('/:id/clone', authenticate, async (req, res) => {
  try {
    const source = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!source) return res.status(404).json({ success: false, message: 'Journal not found' });

    const newNumber = await generateJournalNumber(req.user?.orgId);
// REPLACE WITH — add orgId:
const clone = await ManualJournal.create({
  journalNumber:    newNumber,
  date:             new Date(),
  referenceNumber:  source.referenceNumber,
  notes:            source.notes,
  reportingMethod:  source.reportingMethod,
  currency:         source.currency,
  lineItems: source.lineItems.map(l => ({
  accountId:   l.accountId,
  accountName: l.accountName,
  accountCode: l.accountCode,
  description: l.description,
  contactId:   l.contactId,
  contactName: l.contactName,
  contactType: l.contactType,
  debit:       l.debit,
  credit:      l.credit,
})),
  status:           'Draft',
  clonedFromId:     source._id,
  clonedFromNumber: source.journalNumber,
  orgId:            req.user?.orgId || null,
  createdBy:        req.user?.email || 'system',
});

    res.status(201).json({ success: true, message: `Journal cloned as ${newNumber}`, data: { ...clone.toObject(), id: clone._id } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — APPLY CREDITS (Link to Invoice or Bill)
// ============================================================================

router.post('/:id/apply-credits', authenticate, async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });
    if (journal.status !== 'Published')
      return res.status(400).json({ success: false, message: 'Only published journals can have credits applied' });

    const { type, referenceId, referenceNumber, amount } = req.body;
    if (!type || !referenceId || !amount)
      return res.status(400).json({ success: false, message: 'type, referenceId, and amount are required' });

    // Check if already applied to this reference
    const existing = journal.appliedCredits.find(c => c.referenceId.toString() === referenceId);
    if (existing)
      return res.status(400).json({ success: false, message: 'Credit already applied to this reference' });

    journal.appliedCredits.push({ type, referenceId, referenceNumber, amount, appliedDate: new Date() });
    journal.updatedBy = req.user?.email || 'system';
    await journal.save();

    res.json({ success: true, message: `Credit applied to ${type} ${referenceNumber}`, data: { ...journal.toObject(), id: journal._id } });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — PDF
// ============================================================================

router.get('/:id/pdf', authenticate, async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    }).lean();
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });

    const uploadsDir = path.join(__dirname, '..', 'uploads', 'journals');
    if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir, { recursive: true });

    const filename = `journal-${journal.journalNumber}.pdf`;
    const filepath = path.join(uploadsDir, filename);

    const OrgModel = mongoose.models.Organisation ||
      mongoose.model('Organisation', new mongoose.Schema({}, { strict: false }));
    const orgData = journal.orgId ? await OrgModel.findOne({ orgId: journal.orgId }).lean() : null;
    const orgName = orgData?.orgName || orgData?.name || 'Your Organisation';

    await generateJournalPDF(journal, filepath, orgName);

    res.download(filepath, filename);
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

async function generateJournalPDF(journal, filepath, orgName = 'Your Organisation') {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 50 });
    const stream = fs.createWriteStream(filepath);
    doc.pipe(stream);

    // Header
    doc.fontSize(22).fillColor('#0F172A').font('Helvetica-Bold').text('MANUAL JOURNAL', 50, 50);
    doc.fontSize(10).fillColor('#64748B').font('Helvetica').text(orgName, 50, 80);

    // Status badge
    const statusColors = { Published: '#16A34A', Draft: '#D97706', Void: '#DC2626' };
    doc.fontSize(12).fillColor(statusColors[journal.status] || '#64748B')
       .font('Helvetica-Bold').text(journal.status.toUpperCase(), 400, 55, { align: 'right' });

    // Journal details box
    doc.rect(50, 105, 495, 70).fillAndStroke('#F8FAFC', '#E2E8F0');
    doc.fontSize(9).fillColor('#374151').font('Helvetica-Bold');
    doc.text('Journal #:', 65, 120); doc.text('Date:', 65, 137); doc.text('Reference #:', 65, 154);
    doc.fillColor('#000').font('Helvetica');
    doc.text(journal.journalNumber, 160, 120);
    doc.text(new Date(journal.date).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' }), 160, 137);
    doc.text(journal.referenceNumber || '-', 160, 154);
    doc.fillColor('#374151').font('Helvetica-Bold');
    doc.text('Reporting:', 320, 120); doc.text('Currency:', 320, 137); doc.text('Notes:', 320, 154);
    doc.fillColor('#000').font('Helvetica');
    doc.text(journal.reportingMethod, 400, 120);
    doc.text(journal.currency, 400, 137);
    doc.text(journal.notes || '-', 400, 154, { width: 130, ellipsis: true });

    // Line items table header
    doc.rect(50, 190, 495, 22).fill('#0F172A');
    doc.fontSize(8).fillColor('#FFF').font('Helvetica-Bold');
    doc.text('ACCOUNT', 60, 198); doc.text('DESCRIPTION', 190, 198); doc.text('CONTACT', 330, 198);
    doc.text('DEBIT', 415, 198, { width: 55, align: 'right' });
    doc.text('CREDIT', 470, 198, { width: 65, align: 'right' });

    // Line items
    let y = 212;
    journal.lineItems.forEach((line, i) => {
      doc.rect(50, y, 495, 22).fillAndStroke(i % 2 === 0 ? '#FFF' : '#F8FAFC', '#E2E8F0');
      doc.fontSize(8).fillColor('#000').font('Helvetica');
      doc.text(line.accountName, 60, y + 7, { width: 125, ellipsis: true });
      doc.text(line.description || '-', 190, y + 7, { width: 135, ellipsis: true });
      doc.text(line.contactName || '-', 330, y + 7, { width: 80, ellipsis: true });
      if (line.debit > 0)
        doc.fillColor('#DC2626').text(`₹${line.debit.toFixed(2)}`, 415, y + 7, { width: 55, align: 'right' });
      else doc.fillColor('#94A3B8').text('-', 415, y + 7, { width: 55, align: 'right' });
      if (line.credit > 0)
        doc.fillColor('#16A34A').text(`₹${line.credit.toFixed(2)}`, 470, y + 7, { width: 65, align: 'right' });
      else doc.fillColor('#94A3B8').text('-', 470, y + 7, { width: 65, align: 'right' });
      y += 22;
    });

    // Totals
    y += 10;
    doc.fontSize(9).fillColor('#374151').font('Helvetica-Bold');
    doc.text('Sub Total', 350, y); doc.text(`₹${journal.totalDebit.toFixed(2)}`, 415, y, { width: 55, align: 'right' });
    doc.text(`₹${journal.totalCredit.toFixed(2)}`, 470, y, { width: 65, align: 'right' });
    y += 15;
    doc.text('Difference', 350, y);
    doc.fillColor(Math.abs(journal.difference) < 0.01 ? '#16A34A' : '#DC2626');
    doc.text(`₹${journal.difference.toFixed(2)}`, 415, y, { width: 120, align: 'right' });

    // Applied credits
    if (journal.appliedCredits && journal.appliedCredits.length > 0) {
      y += 30;
      doc.fontSize(10).fillColor('#0F172A').font('Helvetica-Bold').text('Applied Credits', 50, y);
      y += 16;
      journal.appliedCredits.forEach(c => {
        doc.fontSize(9).fillColor('#374151').font('Helvetica');
        doc.text(`${c.type} ${c.referenceNumber} — ₹${c.amount.toFixed(2)}`, 60, y);
        y += 15;
      });
    }

    // Footer
    doc.fontSize(7).fillColor('#94A3B8').font('Helvetica')
       .text(`Generated: ${new Date().toLocaleString('en-IN')}`, 50, 780, { align: 'center', width: 495 });

    doc.end();
    stream.on('finish', resolve);
    stream.on('error', reject);
  });
}

// ============================================================================
// ROUTES — ATTACHMENTS
// ============================================================================

router.post('/:id/attachments', authenticate, attachUpload.array('files', 5), async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });

    const added = (req.files || []).map(f => ({
      filename: f.originalname, filepath: f.path, size: f.size, uploadedAt: new Date(),
    }));

    if (journal.attachments.length + added.length > 5)
      return res.status(400).json({ success: false, message: 'Maximum 5 attachments allowed' });

    journal.attachments.push(...added);
    await journal.save();

    res.json({ success: true, message: `${added.length} file(s) attached`, data: journal.attachments });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

router.delete('/:id/attachments/:attachId', authenticate, async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });

    const idx = journal.attachments.findIndex(a => a._id.toString() === req.params.attachId);
    if (idx === -1) return res.status(404).json({ success: false, message: 'Attachment not found' });

    const attach = journal.attachments[idx];
    if (attach.filepath && fs.existsSync(attach.filepath)) {
      try { fs.unlinkSync(attach.filepath); } catch (_) {}
    }
    journal.attachments.splice(idx, 1);
    await journal.save();

    res.json({ success: true, message: 'Attachment removed' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — TEMPLATES
// ============================================================================

router.get('/templates/list', authenticate, async (req, res) => {
  try {
    const templates = await JournalTemplate.find({}).sort({ templateName: 1 }).lean();
    res.json({ success: true, data: templates });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

router.post('/templates', authenticate, async (req, res) => {
  try {
    const t = await JournalTemplate.create({ ...req.body, createdBy: req.user?.email || 'system' });
    res.status(201).json({ success: true, message: 'Template saved', data: t });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

router.delete('/templates/:id', authenticate, async (req, res) => {
  try {
    await JournalTemplate.findByIdAndDelete(req.params.id);
    res.json({ success: true, message: 'Template deleted' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — IMPORT
// ============================================================================

const importUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

router.post('/import', authenticate, importUpload.single('file'), async (req, res) => {
  try {
    const journalsData = JSON.parse(req.body.journals || '[]');
    let successCount = 0, failedCount = 0;
    const errors = [];

    for (let i = 0; i < journalsData.length; i++) {
      const item = journalsData[i];
      try {
        if (!item.journalNumber) item.journalNumber = await generateJournalNumber(req.user?.orgId);
item.createdBy = req.user?.email || 'system';
item.orgId = req.user?.orgId || null;
await ManualJournal.create(item);
        successCount++;
      } catch (e) {
        errors.push(`Row ${i + 2}: ${e.message}`);
        failedCount++;
      }
    }

    res.json({
      success: true,
      message: `Imported ${successCount} journals`,
      data: { totalProcessed: journalsData.length, successCount, failedCount, errors },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// ============================================================================
// ROUTES — DELETE (Draft only)
// ============================================================================

router.delete('/:id', authenticate, async (req, res) => {
  try {
    const journal = await ManualJournal.findOne({
      _id: req.params.id,
      ...(req.user?.orgId ? { orgId: req.user.orgId } : {}),
    });
    if (!journal) return res.status(404).json({ success: false, message: 'Journal not found' });
    if (journal.status !== 'Draft')
      return res.status(400).json({ success: false, message: 'Only Draft journals can be deleted' });

    await journal.deleteOne();
    res.json({ success: true, message: 'Journal deleted' });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

module.exports = router;
module.exports.ManualJournal    = ManualJournal;
module.exports.JournalTemplate  = JournalTemplate;
module.exports.generateJournalNumber = generateJournalNumber;